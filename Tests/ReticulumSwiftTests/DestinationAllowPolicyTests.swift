import XCTest
@testable import ReticulumSwift

/// Tests for Destination allow policy constants and request handler integration.
/// Mirrors Python's ALLOW_NONE / ALLOW_ALL / ALLOW_LIST constants.
final class DestinationAllowPolicyTests: XCTestCase {

    // MARK: - Class constants

    func testAllowPolicyConstants() {
        // Python: Destination.ALLOW_NONE, ALLOW_ALL, ALLOW_LIST as class attributes
        XCTAssertEqual(Destination.allowNone, .none)
        XCTAssertEqual(Destination.allowAll, .all)
        XCTAssertEqual(Destination.allowList, .list)
    }

    func testProofStrategyConstants() {
        // Python: Destination.PROVE_NONE, PROVE_ALL, PROVE_APP
        XCTAssertEqual(Destination.proveNone, .proveNone)
        XCTAssertEqual(Destination.proveAll, .proveAll)
        XCTAssertEqual(Destination.proveApp, .proveApp)
    }

    // MARK: - Single / Group / Plain / Link kind constants

    func testKindConstants() {
        XCTAssertEqual(Destination.Kind.single.rawValue, 0x00)
        XCTAssertEqual(Destination.Kind.group.rawValue, 0x01)
        XCTAssertEqual(Destination.Kind.plain.rawValue, 0x02)
        XCTAssertEqual(Destination.Kind.link.rawValue, 0x03)
    }

    // MARK: - Request handler allow policies work correctly

    func testAllowNoneBlocksAllRequests() throws {
        var aT: Transport! = Transport(); var bT: Transport! = Transport()
        defer { _ = (aT, bT) }
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["allow"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)

        final class LoopbackInterface: Interface {
            var name: String; var bitrate: Int = 0; var isOnline: Bool = true
            weak var paired: LoopbackInterface?
            var inboundHandler: ((Packet, any Interface) -> Void)?
            init(name: String) { self.name = name }
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {
                let raw = try packet.pack(); let copy = try Packet.unpack(raw)
                paired?.inboundHandler?(copy, paired!)
            }
        }
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }; bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)

        // Register with ALLOW_NONE (Python default)
        let handlerFired = expectation(description: "handler-blocked")
        handlerFired.isInverted = true
        bDest.registerRequestHandler(path: "test", allow: Destination.allowNone) { _, _, _, _, _ in
            handlerFired.fulfill()
            return nil
        }

        _ = try aLink.request(path: "test")
        wait(for: [handlerFired], timeout: 0.3)
    }
}
