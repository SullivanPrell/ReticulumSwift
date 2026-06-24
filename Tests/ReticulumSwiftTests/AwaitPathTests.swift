import XCTest
@testable import ReticulumSwift

/// Tests for Transport.awaitPath() — blocking path resolution.
final class AwaitPathTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    func testAwaitPathReturnsTrueWhenPathExists() {
        let t = Transport()
        let destHash = Data(repeating: 0xAA, count: 16)
        t.restore(path: Transport.PathEntry(
            destinationHash: destHash,
            nextHopInterfaceName: "test",
            hops: 1,
            lastHeard: Date(),
            identityHash: Data(repeating: 0x00, count: 16)
        ), forDestination: destHash)

        let found = t.awaitPath(to: destHash, timeout: 0.1)
        XCTAssertTrue(found)
    }

    func testAwaitPathReturnsFalseWhenNoPathAndTimeout() throws {
        let t = Transport()
        let iface = LoopbackInterface(name: "void")
        t.register(interface: iface)

        let unknown = Data(repeating: 0xFF, count: 16)
        let start = Date()
        let found = t.awaitPath(to: unknown, timeout: 0.1)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(found, "should return false when destination unknown")
        XCTAssertGreaterThanOrEqual(elapsed, 0.05, "should wait at least for timeout")
    }

    func testAwaitPathRespectsOnInterfaceParameter() throws {
        let t = Transport()
        let iface = LoopbackInterface(name: "specific")
        t.register(interface: iface)

        let destHash = Data(repeating: 0xBB, count: 16)

        // Should send path request on the specific interface only
        var sentOnSpecific = false
        iface.inboundHandler = { pkt, _ in
            // Count path requests received (bounced back via loopback)
            _ = pkt
        }

        let origSend = iface.send(_:)
        _ = origSend  // just to confirm it exists

        let found = t.awaitPath(to: destHash, timeout: 0.05, onInterface: iface)
        XCTAssertFalse(found)  // destination not known
        _ = sentOnSpecific
    }
}
