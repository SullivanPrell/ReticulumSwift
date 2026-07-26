import XCTest
@testable import ReticulumSwift

/// End-to-end loopback tests for the `rncp` port: two `Transport`s joined by paired
/// `LoopbackInterface` stubs (the LinkTests pattern), an ``RNCopyListener`` on one side and
/// an ``RNCopySender`` / ``RNCopyFetcher`` on the other.
///
/// Python reference: `RNS/Utilities/rncp.py`.
///
/// The loopback interface delivers synchronously on the caller's thread, so a whole
/// transfer completes inside `ResourceTransfer.send` / `Link.request`; the clients still
/// poll (as Python does) so nothing depends on that.

// MARK: - Fixture

/// A two-node rncp fixture. `client` is the sending/fetching side, `server` the listener.
private final class RNCopyFixture {

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
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

    let clientTransport = Transport()
    let serverTransport = Transport()
    let clientIdentity = Identity()
    let serverIdentity = Identity()
    let clientInterface = LoopbackInterface(name: "client")
    let serverInterface = LoopbackInterface(name: "server")

    init() {
        clientInterface.paired = serverInterface
        serverInterface.paired = clientInterface
        clientTransport.register(interface: clientInterface)
        serverTransport.register(interface: serverInterface)
        serverTransport.ownerIdentity = serverIdentity
    }

    /// Announce `destination` from the server so the client learns both the path and the
    /// listener identity — the two things `RNCopyLinkOpener` needs.
    func publish(_ destination: Destination, on test: XCTestCase) throws {
        let announced = test.expectation(description: "announce")
        clientTransport.onAnnounceReceived = { _, _ in announced.fulfill() }
        try serverTransport.announce(destination: destination)
        test.wait(for: [announced], timeout: 2.0)
        XCTAssertTrue(clientTransport.hasPath(to: destination.hash))
        XCTAssertNotNil(clientTransport.recall(identity: destination.hash))
    }
}

// MARK: - Listener

final class RNCopyListenerTests: XCTestCase {

    private func makeListener(fileSystem: MockRNCopyFileSystem,
                              fixture: RNCopyFixture,
                              allowedIdentityHashes: Set<Data> = [],
                              allowAll: Bool = false,
                              allowFetch: Bool = false,
                              fetchJail: String? = nil,
                              savePath: String? = nil,
                              allowOverwrite: Bool = false) throws -> RNCopyListener {
        let listener = try RNCopyListener(
            transport: fixture.serverTransport,
            fileSystem: fileSystem,
            configuration: RNCopyListener.Configuration(
                identity: fixture.serverIdentity,
                allowedIdentityHashes: allowedIdentityHashes,
                allowAll: allowAll,
                allowFetch: allowFetch,
                allowOverwriteOnReceive: allowOverwrite,
                fetchJail: fetchJail,
                savePath: savePath))
        listener.start()
        return listener
    }

    func testDestinationIsRncpReceive() throws {
        let fixture = RNCopyFixture()
        let listener = try makeListener(fileSystem: MockRNCopyFileSystem(), fixture: fixture)
        // Python: RNS.Destination(identity, IN, SINGLE, "rncp", "receive") (rncp.py:112)
        XCTAssertEqual(listener.destination.fullName,
                       "rncp.receive.\(fixture.serverIdentity.hexHash)")
        XCTAssertEqual(listener.destination.nameHash.hexString, "3e4bcdfc941d6f4fc33e")
    }

    func testAnnounceIsEmitted() throws {
        // The -b quirk: rncp ALWAYS announces once at listener startup, because Python's
        // `False >= 0` is True (rncp.py:86-87, 222-230).
        let fixture = RNCopyFixture()
        let listener = try makeListener(fileSystem: MockRNCopyFileSystem(), fixture: fixture)
        let announced = expectation(description: "announce")
        fixture.clientTransport.onAnnounceReceived = { _, _ in announced.fulfill() }
        try listener.announce()
        wait(for: [announced], timeout: 2.0)
        XCTAssertTrue(fixture.clientTransport.hasPath(to: listener.destination.hash))
    }

    func testAcceptCallbackRejectsUnknownIdentity() throws {
        let fixture = RNCopyFixture()
        let listener = try makeListener(fileSystem: MockRNCopyFileSystem(), fixture: fixture)
        try fixture.publish(listener.destination, on: self)

        let outbound = try Destination(identity: fixture.serverIdentity, direction: .out,
                                       kind: .single, appName: RNCopyApp.appName,
                                       aspects: [RNCopyApp.receiveAspect])
        let link = try Link.initiate(destination: outbound, transport: fixture.clientTransport)
        let serverLink = try XCTUnwrap(fixture.serverTransport.links[link.linkID!])

        // Python: receive_resource_callback returns False when the sender is unknown and
        // allow_all is off (rncp.py:254-266).
        XCTAssertFalse(listener.acceptResource(from: serverLink))
        listener.configuration.allowAll = true
        XCTAssertTrue(listener.acceptResource(from: serverLink))
    }

    func testDeniedSenderIsTornDown() throws {
        let fixture = RNCopyFixture()
        // allowAll = false and an empty allow-list: Python logs "Sender not allowed, tearing
        // down link" and calls link.teardown() (rncp.py:247-250).
        let listener = try makeListener(fileSystem: MockRNCopyFileSystem(), fixture: fixture)
        try fixture.publish(listener.destination, on: self)

        let outbound = try Destination(identity: fixture.serverIdentity, direction: .out,
                                       kind: .single, appName: RNCopyApp.appName,
                                       aspects: [RNCopyApp.receiveAspect])
        let link = try Link.initiate(destination: outbound, transport: fixture.clientTransport)

        let closed = expectation(description: "link-closed")
        link.onClosed = { _ in closed.fulfill() }

        let rejected = expectation(description: "sender-rejected")
        listener.onSenderRejected = { _ in rejected.fulfill() }

        try link.identify(as: fixture.clientIdentity)
        wait(for: [rejected, closed], timeout: 3.0)
        XCTAssertEqual(link.status, .closed)
    }

    func testAllowedSenderIsNotTornDown() throws {
        let fixture = RNCopyFixture()
        let listener = try makeListener(fileSystem: MockRNCopyFileSystem(), fixture: fixture,
                                        allowedIdentityHashes: [fixture.clientIdentity.hash])
        try fixture.publish(listener.destination, on: self)

        let outbound = try Destination(identity: fixture.serverIdentity, direction: .out,
                                       kind: .single, appName: RNCopyApp.appName,
                                       aspects: [RNCopyApp.receiveAspect])
        let link = try Link.initiate(destination: outbound, transport: fixture.clientTransport)
        try link.identify(as: fixture.clientIdentity)
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(link.status, .active)
    }

    // MARK: Fetch handler

    private func makeIdentifiedServerLink(_ fixture: RNCopyFixture,
                                          identify: Bool = true) throws -> Link {
        let outbound = try Destination(identity: fixture.serverIdentity, direction: .out,
                                       kind: .single, appName: RNCopyApp.appName,
                                       aspects: [RNCopyApp.receiveAspect])
        let link = try Link.initiate(destination: outbound, transport: fixture.clientTransport)
        if identify { try link.identify(as: fixture.clientIdentity) }
        Thread.sleep(forTimeInterval: 0.05)
        return try XCTUnwrap(fixture.serverTransport.links[link.linkID!])
    }

    func testFetchHandlerReturnsNotAllowedOnJailEscape() throws {
        let fixture = RNCopyFixture()
        let listener = try makeListener(fileSystem: MockRNCopyFileSystem(), fixture: fixture,
                                        allowedIdentityHashes: [fixture.clientIdentity.hash],
                                        allowFetch: true, fetchJail: "/j")
        try fixture.publish(listener.destination, on: self)
        let serverLink = try makeIdentifiedServerLink(fixture)

        // Python: return REQ_FETCH_NOT_ALLOWED (0xF0) — msgpack cc f0.
        XCTAssertEqual(listener.serveFetchRequest(requested: "../x", link: serverLink),
                       .uint(UInt64(RNCopyApp.reqFetchNotAllowed)))
    }

    func testFetchHandlerReturnsFalseWhenMissing() throws {
        let fixture = RNCopyFixture()
        let listener = try makeListener(fileSystem: MockRNCopyFileSystem(), fixture: fixture,
                                        allowedIdentityHashes: [fixture.clientIdentity.hash],
                                        allowFetch: true)
        try fixture.publish(listener.destination, on: self)
        let serverLink = try makeIdentifiedServerLink(fixture)

        // Python: RNS.log("Client-requested file not found: ...") then return False.
        XCTAssertEqual(listener.serveFetchRequest(requested: "/nope.txt", link: serverLink),
                       .bool(false))
    }

    func testFetchHandlerServesAndReturnsTrue() throws {
        let fixture = RNCopyFixture()
        let fileSystem = MockRNCopyFileSystem(files: ["/j/a.txt": Data("hello".utf8)])
        let listener = try makeListener(fileSystem: fileSystem, fixture: fixture,
                                        allowedIdentityHashes: [fixture.clientIdentity.hash],
                                        allowFetch: true, fetchJail: "/j")
        try fixture.publish(listener.destination, on: self)
        let serverLink = try makeIdentifiedServerLink(fixture)

        // Python constructs an ORDINARY resource (not a response resource) and returns True,
        // so the RESOURCE_ADV goes out BEFORE the scalar response packet.
        XCTAssertEqual(listener.serveFetchRequest(requested: "a.txt", link: serverLink),
                       .bool(true))
    }

    func testUnauthorisedFetchYieldsNoResponse() throws {
        let fixture = RNCopyFixture()
        let fileSystem = MockRNCopyFileSystem(files: ["/j/a.txt": Data("hello".utf8)])
        // Empty allow-list, allowAll off: Python's ALLOW_LIST sends nothing at all, which
        // the client reports as "unknown error (probably not authorised)".
        let listener = try makeListener(fileSystem: fileSystem, fixture: fixture,
                                        allowFetch: true, fetchJail: "/j")
        try fixture.publish(listener.destination, on: self)
        let serverLink = try makeIdentifiedServerLink(fixture, identify: false)

        XCTAssertNil(listener.serveFetchRequest(requested: "a.txt", link: serverLink))
    }

    func testFetchHandlerIsOnlyRegisteredWithAllowFetch() throws {
        let fixture = RNCopyFixture()
        // Python registers the handler only inside `if allow_fetch:` (rncp.py:213-218), which
        // is exactly why the `if not allow_fetch: return REQ_FETCH_NOT_ALLOWED` opener at
        // rncp.py:174 is dead code.
        let without = try makeListener(fileSystem: MockRNCopyFileSystem(), fixture: fixture)
        XCTAssertNil(without.destination.requestHandlers[RNCopyApp.fetchRequestPathHash])

        let fixture2 = RNCopyFixture()
        let with = try makeListener(fileSystem: MockRNCopyFileSystem(), fixture: fixture2,
                                    allowFetch: true)
        XCTAssertNotNil(with.destination.requestHandlers[RNCopyApp.fetchRequestPathHash])
    }
}

// MARK: - Sender

final class RNCopySenderTests: XCTestCase {

    func testMissingLocalFile() throws {
        let fixture = RNCopyFixture()
        let sender = RNCopySender(
            transport: fixture.clientTransport,
            fileSystem: MockRNCopyFileSystem(),
            configuration: RNCopySender.Configuration(identity: fixture.clientIdentity,
                                                      destinationHash: Data(repeating: 0xAA, count: 16),
                                                      filePath: "~/nope.txt",
                                                      timeout: 0.2),
            tick: 0.01)
        // Python: print("File not found"); sys.exit(1) — before Reticulum is even started.
        XCTAssertEqual(sender.run(), .fileNotFound)
    }

    func testPathNotFound() throws {
        let fixture = RNCopyFixture()
        let sender = RNCopySender(
            transport: fixture.clientTransport,
            fileSystem: MockRNCopyFileSystem(files: ["/h/a.txt": Data("x".utf8)]),
            configuration: RNCopySender.Configuration(identity: fixture.clientIdentity,
                                                      destinationHash: Data(repeating: 0xAA, count: 16),
                                                      filePath: "~/a.txt",
                                                      timeout: 0.2),
            tick: 0.01)
        XCTAssertEqual(sender.run(), .pathNotFound)
    }

    func testEndToEndSendSavesOnListener() throws {
        let fixture = RNCopyFixture()
        let serverFileSystem = MockRNCopyFileSystem()
        let listener = try RNCopyListener(
            transport: fixture.serverTransport,
            fileSystem: serverFileSystem,
            configuration: RNCopyListener.Configuration(
                identity: fixture.serverIdentity,
                allowedIdentityHashes: [fixture.clientIdentity.hash]))
        listener.start()
        try fixture.publish(listener.destination, on: self)

        let payload = Data("hello rncp".utf8)
        let clientFileSystem = MockRNCopyFileSystem(files: ["/h/docs/hello.txt": payload])
        let sender = RNCopySender(
            transport: fixture.clientTransport,
            fileSystem: clientFileSystem,
            configuration: RNCopySender.Configuration(identity: fixture.clientIdentity,
                                                      destinationHash: listener.destination.hash,
                                                      filePath: "~/docs/hello.txt",
                                                      timeout: 5),
            tick: 0.02)

        var progressSamples: [RNCopyProgress] = []
        sender.onProgress = { progressSamples.append($0) }

        let outcome = sender.run()
        guard case .completed(let bytes, _) = outcome else {
            return XCTFail("expected .completed, got \(outcome)")
        }
        XCTAssertEqual(bytes, payload.count)

        // The filename travelled in the resource metadata map {"name": b"hello.txt"} and the
        // listener wrote it relative to its CWD (no --save configured).
        XCTAssertEqual(serverFileSystem.writtenPaths, ["hello.txt"])
        XCTAssertEqual(serverFileSystem.files["hello.txt"], payload)

        // Sender-side progress must actually move — it is derived from sent parts.
        XCTAssertFalse(progressSamples.isEmpty)
        XCTAssertEqual(progressSamples.last?.fraction, 1.0)
        XCTAssertTrue(progressSamples.last?.done ?? false)
        XCTAssertEqual(progressSamples.last?.totalBytes, payload.count)
    }

    func testSendHonoursSavePathAndRenameCounter() throws {
        let fixture = RNCopyFixture()
        let serverFileSystem = MockRNCopyFileSystem(files: ["/out/hello.txt": Data("old".utf8)],
                                                    directories: ["/out"])
        let listener = try RNCopyListener(
            transport: fixture.serverTransport,
            fileSystem: serverFileSystem,
            configuration: RNCopyListener.Configuration(
                identity: fixture.serverIdentity,
                allowedIdentityHashes: [fixture.clientIdentity.hash],
                savePath: "/out"))
        listener.start()
        try fixture.publish(listener.destination, on: self)

        let payload = Data("fresh".utf8)
        let sender = RNCopySender(
            transport: fixture.clientTransport,
            fileSystem: MockRNCopyFileSystem(files: ["/h/hello.txt": payload]),
            configuration: RNCopySender.Configuration(identity: fixture.clientIdentity,
                                                      destinationHash: listener.destination.hash,
                                                      filePath: "~/hello.txt",
                                                      timeout: 5),
            tick: 0.02)

        guard case .completed = sender.run() else { return XCTFail("expected .completed") }
        // Python: collisions become name.1, name.2, … (rncp.py:304-306)
        XCTAssertEqual(serverFileSystem.writtenPaths, ["/out/hello.txt.1"])
        XCTAssertEqual(serverFileSystem.files["/out/hello.txt.1"], payload)
        XCTAssertEqual(serverFileSystem.files["/out/hello.txt"], Data("old".utf8))
    }

    func testRejectedResourceIsNotAccepted() throws {
        let fixture = RNCopyFixture()
        // A destination whose links keep Swift's default `.acceptNone` strategy replies
        // RESOURCE_RCL, which is exactly what a Python listener does when its ACCEPT_APP
        // callback returns False. The sender must report "File was not accepted by …".
        let destination = try Destination(identity: fixture.serverIdentity, direction: .in,
                                          kind: .single, appName: RNCopyApp.appName,
                                          aspects: [RNCopyApp.receiveAspect])
        fixture.serverTransport.register(destination: destination)
        try fixture.publish(destination, on: self)

        let sender = RNCopySender(
            transport: fixture.clientTransport,
            fileSystem: MockRNCopyFileSystem(files: ["/h/a.txt": Data("payload".utf8)]),
            configuration: RNCopySender.Configuration(identity: fixture.clientIdentity,
                                                      destinationHash: destination.hash,
                                                      filePath: "~/a.txt",
                                                      timeout: 5),
            tick: 0.02)

        XCTAssertEqual(sender.run(), .notAccepted)
    }

    func testZeroByteFileFailsToStart() throws {
        let fixture = RNCopyFixture()
        let listener = try RNCopyListener(
            transport: fixture.serverTransport,
            fileSystem: MockRNCopyFileSystem(),
            configuration: RNCopyListener.Configuration(
                identity: fixture.serverIdentity,
                allowedIdentityHashes: [fixture.clientIdentity.hash]))
        listener.start()
        try fixture.publish(listener.destination, on: self)

        let sender = RNCopySender(
            transport: fixture.clientTransport,
            fileSystem: MockRNCopyFileSystem(files: ["/h/empty.bin": Data()]),
            configuration: RNCopySender.Configuration(identity: fixture.clientIdentity,
                                                      destinationHash: listener.destination.hash,
                                                      filePath: "~/empty.bin",
                                                      timeout: 5),
            tick: 0.02)

        // Python also fails here (bz2 on an already-consumed file handle) and prints
        // "Could not start transfer: <e>"; only the exception text differs.
        guard case .startFailed = sender.run() else { return XCTFail("expected .startFailed") }
    }
}

// MARK: - Fetcher

final class RNCopyFetcherTests: XCTestCase {

    private func makeFetchListener(_ fixture: RNCopyFixture,
                                   fileSystem: MockRNCopyFileSystem,
                                   jail: String?) throws -> RNCopyListener {
        let listener = try RNCopyListener(
            transport: fixture.serverTransport,
            fileSystem: fileSystem,
            configuration: RNCopyListener.Configuration(
                identity: fixture.serverIdentity,
                allowedIdentityHashes: [fixture.clientIdentity.hash],
                allowFetch: true,
                fetchJail: jail))
        listener.start()
        try fixture.publish(listener.destination, on: self)
        return listener
    }

    func testEndToEndFetchSavesFile() throws {
        let fixture = RNCopyFixture()
        let payload = Data("remote contents".utf8)
        let listener = try makeFetchListener(fixture,
                                             fileSystem: MockRNCopyFileSystem(files: ["/j/doc.txt": payload]),
                                             jail: "/j")

        let clientFileSystem = MockRNCopyFileSystem()
        let fetcher = RNCopyFetcher(
            transport: fixture.clientTransport,
            fileSystem: clientFileSystem,
            configuration: RNCopyFetcher.Configuration(identity: fixture.clientIdentity,
                                                       destinationHash: listener.destination.hash,
                                                       remotePath: "doc.txt",
                                                       timeout: 5),
            tick: 0.02)

        let outcome = fetcher.run()
        guard case .completed(let savedTo, let bytes, _) = outcome else {
            return XCTFail("expected .completed, got \(outcome)")
        }
        // No --save, so the file lands in the CWD under its metadata-derived basename.
        XCTAssertEqual(savedTo, "doc.txt")
        XCTAssertEqual(bytes, payload.count)
        XCTAssertEqual(clientFileSystem.files["doc.txt"], payload)
    }

    func testFetchNotAllowedOutcome() throws {
        let fixture = RNCopyFixture()
        let listener = try makeFetchListener(fixture,
                                             fileSystem: MockRNCopyFileSystem(files: ["/etc/passwd": Data("x".utf8)]),
                                             jail: "/j")
        let fetcher = RNCopyFetcher(
            transport: fixture.clientTransport,
            fileSystem: MockRNCopyFileSystem(),
            configuration: RNCopyFetcher.Configuration(identity: fixture.clientIdentity,
                                                       destinationHash: listener.destination.hash,
                                                       remotePath: "../etc/passwd",
                                                       timeout: 5),
            tick: 0.02)
        // The jail escape is the ONLY live emitter of REQ_FETCH_NOT_ALLOWED (0xF0).
        XCTAssertEqual(fetcher.run(), .requestFailed(.fetchNotAllowed))
    }

    func testFetchNotFoundOutcome() throws {
        let fixture = RNCopyFixture()
        let listener = try makeFetchListener(fixture, fileSystem: MockRNCopyFileSystem(), jail: "/j")
        let fetcher = RNCopyFetcher(
            transport: fixture.clientTransport,
            fileSystem: MockRNCopyFileSystem(),
            configuration: RNCopyFetcher.Configuration(identity: fixture.clientIdentity,
                                                       destinationHash: listener.destination.hash,
                                                       remotePath: "missing.txt",
                                                       timeout: 5),
            tick: 0.02)
        XCTAssertEqual(fetcher.run(), .requestFailed(.notFound))
    }

    func testFetchWithoutAllowFetchTimesOutIntoUnknown() throws {
        let fixture = RNCopyFixture()
        // No -F: Python registers no handler at all, so the client gets NO response and its
        // request eventually times out into request_status == "unknown" (rncp.py:474-477).
        let listener = try RNCopyListener(
            transport: fixture.serverTransport,
            fileSystem: MockRNCopyFileSystem(files: ["/j/a.txt": Data("x".utf8)]),
            configuration: RNCopyListener.Configuration(
                identity: fixture.serverIdentity,
                allowedIdentityHashes: [fixture.clientIdentity.hash]))
        listener.start()
        try fixture.publish(listener.destination, on: self)

        let fetcher = RNCopyFetcher(
            transport: fixture.clientTransport,
            fileSystem: MockRNCopyFileSystem(),
            configuration: RNCopyFetcher.Configuration(identity: fixture.clientIdentity,
                                                       destinationHash: listener.destination.hash,
                                                       remotePath: "a.txt",
                                                       timeout: 0.5),
            tick: 0.02)
        XCTAssertEqual(fetcher.run(), .requestFailed(.unknown))
    }
}

// MARK: - Wire format

final class RNCopyWireFormatTests: XCTestCase {

    private func establishedPair() throws -> (client: Link, server: Link, destination: Destination, fixture: RNCopyFixture) {
        let fixture = RNCopyFixture()
        let destination = try Destination(identity: fixture.serverIdentity, direction: .in,
                                          kind: .single, appName: RNCopyApp.appName,
                                          aspects: [RNCopyApp.receiveAspect])
        fixture.serverTransport.register(destination: destination)
        let outbound = try Destination(identity: fixture.serverIdentity, direction: .out,
                                       kind: .single, appName: RNCopyApp.appName,
                                       aspects: [RNCopyApp.receiveAspect])
        let client = try Link.initiate(destination: outbound, transport: fixture.clientTransport)
        Thread.sleep(forTimeInterval: 0.05)
        let server = try XCTUnwrap(fixture.serverTransport.links[client.linkID!])
        return (client, server, destination, fixture)
    }

    func testNativeHandlerEnvelopeBytes() throws {
        let (client, _, destination, fixture) = try establishedPair()
        _ = fixture

        // rncp's responses are the bare scalars True / False / 0xF0. A BYTES handler would
        // emit msgpack([id, bin(...)]) — `c4 01 c3` where Python expects `c3` — and a Python
        // fetcher would mis-classify. Only registerNativeRequestHandler is correct.
        destination.registerNativeRequestHandler(path: RNCopyApp.fetchRequestPath,
                                                 allow: .all) { _, _, _, _, _ in .bool(true) }

        var responsePlaintext: Data?
        client.onPacketReceived = { plaintext, _, context, _ in
            if context == .response { responsePlaintext = plaintext }
        }

        let receipt = try client.request(path: RNCopyApp.fetchRequestPath,
                                         nativeValue: .string("a.txt"))
        Thread.sleep(forTimeInterval: 0.1)

        let plaintext = try XCTUnwrap(responsePlaintext)
        XCTAssertEqual(plaintext, MsgPack.encode(.array([.bytes(receipt.requestID), .bool(true)])))
        // 92 c4 10 <16-byte request id> c3
        XCTAssertEqual(plaintext.prefix(3), Data([0x92, 0xC4, 0x10]))
        XCTAssertEqual(plaintext.suffix(1), Data([0xC3]))
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(try XCTUnwrap(receipt.response)), .found)
    }

    func testNotAllowedEnvelopeBytes() throws {
        let (client, _, destination, fixture) = try establishedPair()
        _ = fixture
        destination.registerNativeRequestHandler(path: RNCopyApp.fetchRequestPath,
                                                 allow: .all) { _, _, _, _, _ in
            .uint(UInt64(RNCopyApp.reqFetchNotAllowed))
        }

        var responsePlaintext: Data?
        client.onPacketReceived = { plaintext, _, context, _ in
            if context == .response { responsePlaintext = plaintext }
        }
        let receipt = try client.request(path: RNCopyApp.fetchRequestPath,
                                         nativeValue: .string("a.txt"))
        Thread.sleep(forTimeInterval: 0.1)

        let plaintext = try XCTUnwrap(responsePlaintext)
        // Python: umsgpack.packb([request_id, 0xF0]) → 92 c4 10 <16 bytes> cc f0
        XCTAssertEqual(plaintext.suffix(2), Data([0xCC, 0xF0]))
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(try XCTUnwrap(receipt.response)),
                       .fetchNotAllowed)
    }

    func testRequestDataIsMsgpackString() throws {
        let (client, server, destination, fixture) = try establishedPair()
        _ = fixture
        destination.registerNativeRequestHandler(path: RNCopyApp.fetchRequestPath,
                                                 allow: .all) { _, _, _, _, _ in .bool(false) }

        var requestPlaintext: Data?
        server.onPacketReceived = { plaintext, _, context, _ in
            if context == .request { requestPlaintext = plaintext }
        }

        _ = try client.request(path: RNCopyApp.fetchRequestPath, nativeValue: .string("a.txt"))
        Thread.sleep(forTimeInterval: 0.1)

        // Python: msgpack([float64 time, bin16 path_hash, str filename]). The listener does
        // data.startswith(...) on element 2 — a msgpack bin would raise remotely.
        let parts = try XCTUnwrap(try MsgPack.decode(try XCTUnwrap(requestPlaintext)).asArray)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[1].asData, RNCopyApp.fetchRequestPathHash)
        XCTAssertEqual(parts[2], .string("a.txt"))
        XCTAssertNil(parts[2].asData, "must be a msgpack str, not a bin")
    }

    func testResourceCarriesNameEndToEnd() throws {
        let (client, server, _, fixture) = try establishedPair()
        _ = fixture

        let payload = Data(repeating: 0x5A, count: 300)
        let metadata = RNCopyApp.encodeMetadata(name: "f.bin")

        let done = expectation(description: "complete")
        var receivedPayload: Data?
        var receivedMetadata: Data?

        let sender = ResourceTransfer(link: client)
        sender.onComplete = { _ in done.fulfill() }
        let receiver = ResourceTransfer(link: server)
        receiver.bindAsReceiver()
        receiver.onPayloadReceived = { data, transfer in
            receivedPayload = data
            receivedMetadata = transfer.receivedMetadata
        }

        try sender.send(payload: payload, metadata: metadata)
        wait(for: [done], timeout: 3.0)

        XCTAssertEqual(receivedPayload, payload)
        XCTAssertEqual(RNCopyApp.decodeMetadataName(try XCTUnwrap(receivedMetadata)), "f.bin")
    }
}
