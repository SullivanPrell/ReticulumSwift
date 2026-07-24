import XCTest
@testable import ReticulumSwift

/// `via` in a published path-table entry.
///
/// Python sets it while handling an announce (Transport.py:1772-1796):
///
///     if packet.transport_id != None: received_from = packet.transport_id
///     else:                           received_from = packet.destination_hash
///
/// and stores it at `path_table[dst][1]`, which `get_path_table` publishes as `via`. It is
/// therefore **never None**, and consumers rely on that: `rnpath -t` calls
/// `RNS.prettyhexrep(path["via"])` with no guard, so a null there is not a blank column —
/// it is `TypeError: 'NoneType' object is not iterable` and the tool dies.
///
/// Swift stores the transport id alone, which is legitimately nil for a directly-attached
/// destination, so the published value has to fall back the way Python's does. Caught by
/// running the real Python `rnpath -t` against a Swift `rnsd` that had learned a single
/// 0-hop path: it crashed with exactly that TypeError.
///
/// `RNPathModels` already compensated for this in its own `resolvedVia`, which is why
/// Swift's own `rnpath` rendered correctly throughout — the gap was only ever visible to a
/// Python client, because the fix sat on the consumer instead of the producer.
final class PathTableViaTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Reticulum.remoteManagementEnabled_ = true
    }

    override func tearDown() {
        Reticulum.remoteManagementEnabled_ = false
        super.tearDown()
    }

    private let destination = Data(repeating: 0xAB, count: 16)
    private let nextHop     = Data(repeating: 0xCD, count: 16)

    private func makeTransport() throws -> Transport {
        let transport = Transport()
        transport.transportIdentity = Identity()
        try transport.start()
        return transport
    }

    private func makeMinimalLink() -> Link {
        let identity = Identity()
        let destination = try! Destination(identity: identity, direction: .in, kind: .single,
                                           appName: "dummy", aspects: ["link"])
        let transport = Transport()
        transport.register(interface: LoopbackInterface(name: "PathViaTest"))
        return try! Link.initiate(destination: destination, transport: transport)
    }

    private func addPath(_ transport: Transport, hops: UInt8, nextHop: Data?,
                         interfaceName: String = "TestIface") {
        transport.restore(path: Transport.PathEntry(
            destinationHash: destination,
            nextHopInterfaceName: interfaceName,
            hops: hops,
            lastHeard: Date(),
            identityHash: Data(repeating: 0x01, count: 16),
            nextHopTransportID: nextHop
        ), forDestination: destination)
    }

    // MARK: - Transport.getPathTable

    func testDirectPathReportsTheDestinationItself() throws {
        // No transport id — Python's `else` branch stores the destination hash.
        let transport = try makeTransport()
        addPath(transport, hops: 0, nextHop: nil)

        let entry = try XCTUnwrap(transport.getPathTable().first)
        XCTAssertEqual(entry.via, destination,
                       "a 0-hop path must publish the destination hash, never nil")
    }

    func testTransportPathReportsTheNextHop() throws {
        let transport = try makeTransport()
        addPath(transport, hops: 2, nextHop: nextHop)

        let entry = try XCTUnwrap(transport.getPathTable().first)
        XCTAssertEqual(entry.via, nextHop)
    }

    // MARK: - interface

    func testInterfaceIsPublishedAsItsDisplayName() throws {
        // Python: `"interface": str(receiving_interface)` (Reticulum.py:1485), i.e. the
        // display name — "LocalInterface[56156]", not the short config name. A path entry
        // stores only the short name, so the producer has to resolve it, exactly as `via`
        // has to fall back. Same failure mode: visible only to a client that is not
        // Swift's own rnpath, which compensated for this in its bridging init.
        let transport = try makeTransport()
        let iface = UDPInterface(name: "Bridge", listenPort: 0)
        transport.register(interface: iface)
        defer { transport.deregister(interface: iface) }
        addPath(transport, hops: 0, nextHop: nil, interfaceName: "Bridge")

        let entry = try XCTUnwrap(transport.getPathTable().first)
        XCTAssertEqual(entry.interfaceName, iface.displayName)
        XCTAssertNotEqual(entry.interfaceName, "Bridge", "the short name is not what Python prints")
    }

    func testUnregisteredInterfaceKeepsItsStoredName() throws {
        // A path restored from disk can outlive the interface that heard it; Python would
        // have nothing to stringify either, so keeping the stored name is the safe fallback.
        let transport = try makeTransport()
        addPath(transport, hops: 0, nextHop: nil)

        let entry = try XCTUnwrap(transport.getPathTable().first)
        XCTAssertEqual(entry.interfaceName, "TestIface")
    }

    // MARK: - What actually reaches a Python client

    func testRemotePathHandlerNeverPublishesNilVia() throws {
        // Python: rnpath -R -t → prettyhexrep(path["via"]).
        let transport = try makeTransport()
        addPath(transport, hops: 0, nextHop: nil)

        let mgmt = try XCTUnwrap(transport.remoteManagementDestination)
        let pathHash = Hashes.truncatedHash(Data("/path".utf8))
        let handlerEntry = try XCTUnwrap(mgmt.requestHandlers[pathHash])
        let raw = try XCTUnwrap(handlerEntry.handler(
            pathHash, MsgPack.encode(.array([.string("table")])), Data(), makeMinimalLink(), 0))
        let entries = try XCTUnwrap(MsgPack.decode(raw).asArray)

        let first = try XCTUnwrap(entries.first?.asDictionary)
        XCTAssertFalse(first["via"]?.isNil ?? true, "via must not be nil on the wire")
        XCTAssertEqual(first["via"]?.asData, destination)
    }
}
