import XCTest
@testable import ReticulumSwift

/// `rnstatus -R <hash>` — destination derivation, the `/status` request wire format and
/// response decoding.
///
/// Python reference: `get_remote_status` (`RNS/Utilities/rnstatus.py:66-153`) and the
/// responder, `Transport.remote_status_handler` (`RNS/Transport.py:2849-2864`).
final class RemoteStatusQueryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Reticulum.remoteManagementEnabled_ = true
    }

    override func tearDown() {
        Reticulum.remoteManagementEnabled_ = false
        super.tearDown()
    }

    // MARK: - Destination derivation

    func testDestinationHashMatchesPythonsDerivation() {
        let identityHash = Data((0..<16).map { UInt8($0) })
        let derived = RemoteStatusQuery.destinationHash(forIdentityHash: identityHash)

        // Python: Destination.hash_from_name_and_identity("rnstransport.remote.management", hash)
        // → full_hash(name_hash ‖ identity_material)[:16], where name_hash is
        // full_hash("rnstransport.remote.management")[:10].
        let nameHash = Destination.computeNameHash(appName: RNStatusApp.remoteManagementAppName,
                                                   aspects: RNStatusApp.remoteManagementAspects)
        XCTAssertEqual(nameHash.count, Constants.nameHashLength)
        XCTAssertEqual(derived, Hashes.truncatedHash(nameHash + identityHash))
        XCTAssertEqual(derived.count, Constants.truncatedHashLength)
    }

    /// Deriving from an identity's hash must equal deriving from the identity itself, or
    /// `-R <transport identity hash>` addresses a destination nobody is listening on.
    func testDestinationHashAgreesWithTheIdentityBasedHelper() {
        let identity = Identity()
        XCTAssertEqual(
            RemoteStatusQuery.destinationHash(forIdentityHash: identity.hash),
            Destination.hash(identity: identity,
                             appName: RNStatusApp.remoteManagementAppName,
                             aspects: RNStatusApp.remoteManagementAspects)
        )
    }

    // MARK: - Response decoding

    private func statsMap() -> MsgPack.Value {
        .map([
            (.string("interfaces"), .array([])),
            (.string("rxb"), .int(1)),
            (.string("txb"), .int(2)),
            (.string("rxs"), .double(0)),
            (.string("txs"), .double(0)),
            (.string("rss"), .nil),
        ])
    }

    func testDecodeWithLinkCount() {
        // Python: response[0] is the stats dict, response[1] the link count when -l was set.
        let payload = MsgPack.encode(.array([statsMap(), .int(7)]))
        guard case .success(let (stats, linkCount)) = RemoteStatusQuery.decode(payload) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(linkCount, 7)
        XCTAssertNotNil(RNStatusStats(stats))
    }

    func testDecodeWithoutLinkCount() {
        let payload = MsgPack.encode(.array([statsMap()]))
        guard case .success(let (_, linkCount)) = RemoteStatusQuery.decode(payload) else {
            return XCTFail("expected success")
        }
        XCTAssertNil(linkCount)
    }

    private func assertMalformed(_ payload: Data, _ message: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        switch RemoteStatusQuery.decode(payload) {
        case .failure(let error): XCTAssertEqual(error, .malformedResponse, message, file: file, line: line)
        case .success:            XCTFail(message, file: file, line: line)
        }
    }

    func testDecodeRejectsNonArray() {
        assertMalformed(MsgPack.encode(.map([])), "a bare map is not a /status response")
        assertMalformed(MsgPack.encode(.array([])), "an empty array carries no stats dict")
        assertMalformed(Data([0xFF, 0xFF]), "undecodable msgpack")
    }

    /// REGRESSION GUARD for the wire mismatch this port had to fix.
    ///
    /// The old Swift `/status` handler answered with an ARRAY of `{name, rxb, txb}` stubs.
    /// Python detects that with `isinstance(response, list)`; a Swift client cannot, because
    /// `Link.handleIncomingResponse` transparently unwraps a `.bytes` payload into a
    /// structurally valid array. So the guard has to be "does slot 0 decode as a stats
    /// dict", not "is the response an array".
    func testDecodeRejectsAnArrayOfInterfaceStubs() {
        let stub = MsgPack.Value.map([
            (.string("name"), .string("TCPInterface[Server on 0.0.0.0:4242]")),
            (.string("rxb"), .int(1)),
            (.string("txb"), .int(2)),
        ])
        let payload = MsgPack.encode(.array([stub, stub]))
        // It IS an array, and slot 0 is a perfectly good map — only the missing
        // "interfaces" key catches it.
        assertMalformed(payload, "an array of interface stubs must not decode as stats")
    }

    // MARK: - End-to-end over a loopback link

    final class LoopbackInterface: Interface {
        var name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?

        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    private struct Fixture {
        let clientTransport: Transport
        let serverTransport: Transport
        let link: Link
    }

    /// Stands up a responder with a real `rnstransport.remote.management` destination and
    /// an identified initiator link to it — the exact arrangement `rnstatus -R` creates.
    private func makeIdentifiedLink(allowClient: Bool = true) throws -> Fixture {
        let serverIdentity = Identity()
        let clientIdentity = Identity()

        let serverTransport = Transport()
        serverTransport.transportIdentity = serverIdentity
        if allowClient { serverTransport.remoteManagementAllowed = [clientIdentity] }
        try serverTransport.start()

        let clientTransport = Transport()
        let clientInterface = LoopbackInterface(name: "client")
        let serverInterface = LoopbackInterface(name: "server")
        clientInterface.paired = serverInterface
        serverInterface.paired = clientInterface
        clientTransport.register(interface: clientInterface)
        serverTransport.register(interface: serverInterface)

        let outbound = try Destination(identity: serverIdentity, direction: .out, kind: .single,
                                       appName: RNStatusApp.remoteManagementAppName,
                                       aspects: RNStatusApp.remoteManagementAspects)
        // The OUT destination must land on the same hash the responder registered.
        XCTAssertEqual(outbound.hash, serverTransport.remoteManagementDestination?.hash)
        XCTAssertEqual(outbound.hash,
                       RemoteStatusQuery.destinationHash(forIdentityHash: serverIdentity.hash))

        let established = expectation(description: "link established")
        clientTransport.onLinkEstablished = { _ in established.fulfill() }
        let link = try Link.initiate(destination: outbound, transport: clientTransport)
        wait(for: [established], timeout: 2.0)

        try link.identify(as: clientIdentity)
        return Fixture(clientTransport: clientTransport, serverTransport: serverTransport, link: link)
    }

    func testStatusRequestReturnsTheFullStatsDictAsANativeArray() throws {
        let fixture = try makeIdentifiedLink()

        let responded = expectation(description: "response")
        var payload: Data?
        // Python: link.request("/status", data=[include_lstats], …) — a NATIVE array
        // holding one boolean. The `data: Data?` overload would wrap it as msgpack BIN and
        // the responder's `isinstance(data, list)` check would fail.
        let receipt = try fixture.link.request(path: RNStatusApp.statusRequestPath,
                                               nativeValue: .array([.bool(true)]))
        receipt.onResponse = { data, _ in payload = data; responded.fulfill() }
        wait(for: [responded], timeout: 2.0)

        let decoded = try XCTUnwrap(payload.flatMap { try? MsgPack.decode($0) })
        let parts = try XCTUnwrap(decoded.asArray)
        XCTAssertEqual(parts.count, 2)                          // stats + link count
        // Slot 0 must be the full interface_stats MAP, not a summary array.
        let stats = try XCTUnwrap(RNStatusStats(parts[0]))
        XCTAssertEqual(stats.interfaces.count, 1)
        // The published name is `displayName`, class-qualified for every conformer since
        // `bugs/022` — the bare configured `name` here is "server".
        XCTAssertEqual(stats.interfaces.first?.name, "LoopbackInterface[server]")
        XCTAssertNotNil(parts[1].asInt)

        // And the decoder the CLI uses accepts it.
        guard case .success(let (_, linkCount)) = RemoteStatusQuery.decode(try XCTUnwrap(payload)) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(linkCount, 1)   // the management link itself
    }

    func testStatusRequestWithoutLinkStatsOmitsTheSecondSlot() throws {
        let fixture = try makeIdentifiedLink()
        let responded = expectation(description: "response")
        var payload: Data?
        let receipt = try fixture.link.request(path: RNStatusApp.statusRequestPath,
                                               nativeValue: .array([.bool(false)]))
        receipt.onResponse = { data, _ in payload = data; responded.fulfill() }
        wait(for: [responded], timeout: 2.0)

        let parts = try XCTUnwrap(payload.flatMap { try? MsgPack.decode($0) }?.asArray)
        XCTAssertEqual(parts.count, 1)
        guard case .success(let (_, linkCount)) = RemoteStatusQuery.decode(try XCTUnwrap(payload)) else {
            return XCTFail("expected success")
        }
        XCTAssertNil(linkCount)
    }

    func testUnknownIdentityGetsNoResponse() throws {
        // Python registers /status with ALLOW_LIST + remote_management_allowed; an
        // unlisted identity is answered with silence, and rnstatus reports
        // "The remote status request failed. Likely authentication failure."
        let fixture = try makeIdentifiedLink(allowClient: false)
        let silence = expectation(description: "no response")
        silence.isInverted = true
        let receipt = try fixture.link.request(path: RNStatusApp.statusRequestPath,
                                               nativeValue: .array([.bool(false)]))
        receipt.onResponse = { _, _ in silence.fulfill() }
        wait(for: [silence], timeout: 0.4)
    }

    func testEmptyRequestArrayGetsNoResponse() throws {
        // Python: `if isinstance(data, list) and len(data) > 0` (Transport.py:2853).
        let fixture = try makeIdentifiedLink()
        let silence = expectation(description: "no response")
        silence.isInverted = true
        let receipt = try fixture.link.request(path: RNStatusApp.statusRequestPath,
                                               nativeValue: .array([]))
        receipt.onResponse = { _, _ in silence.fulfill() }
        wait(for: [silence], timeout: 0.4)
    }

    // MARK: - Request body shape

    func testRequestBodyIsANativeArrayNotBytes() throws {
        // Python's Link.request packs [time.time(), truncated_hash(path), data]
        // (RNS/Link.py:485-487). Slot 2 must be the native array — the `data: Data?`
        // overload would put a msgpack BIN there instead.
        let pathHash = Hashes.truncatedHash(Data(RNStatusApp.statusRequestPath.utf8))
        XCTAssertEqual(pathHash.count, Constants.truncatedHashLength)

        let fixture = try makeIdentifiedLink()
        var received: MsgPack.Value?
        let handled = expectation(description: "handler")
        let mgmt = try XCTUnwrap(fixture.serverTransport.remoteManagementDestination)
        mgmt.registerNativeRequestHandler(path: "/probe", allow: .all) { hash, data, _, _, _ in
            XCTAssertEqual(hash, Hashes.truncatedHash(Data("/probe".utf8)))
            received = data
            handled.fulfill()
            return .nil
        }
        _ = try fixture.link.request(path: "/probe", nativeValue: .array([.bool(true)]))
        wait(for: [handled], timeout: 2.0)
        XCTAssertEqual(received, .array([.bool(true)]))

        // The bytes overload is what this must NOT do.
        let bytesHandled = expectation(description: "bytes handler")
        var bytesReceived: MsgPack.Value?
        mgmt.registerNativeRequestHandler(path: "/probe2", allow: .all) { _, data, _, _, _ in
            bytesReceived = data
            bytesHandled.fulfill()
            return .nil
        }
        _ = try fixture.link.request(path: "/probe2", data: MsgPack.encode(.array([.bool(true)])))
        wait(for: [bytesHandled], timeout: 2.0)
        if case .bytes = bytesReceived { } else {
            XCTFail("the data: overload should wrap the payload as msgpack BIN, got \(String(describing: bytesReceived))")
        }
    }
}
