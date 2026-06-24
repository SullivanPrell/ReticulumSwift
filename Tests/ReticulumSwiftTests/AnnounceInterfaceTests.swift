import XCTest
@testable import ReticulumSwift

/// Tests for announce on specific interface and interface attachment.
final class AnnounceInterfaceTests: XCTestCase {

    final class CapturingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    // MARK: - announce on all interfaces (default)

    func testAnnounceGoesToAllInterfaces() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["all"])
        t.ownerIdentity = id

        let if1 = CapturingInterface(name: "if1")
        let if2 = CapturingInterface(name: "if2")
        t.register(interface: if1)
        t.register(interface: if2)

        try t.announce(destination: dest)

        let announces1 = if1.sent.filter { $0.packetType == .announce }
        let announces2 = if2.sent.filter { $0.packetType == .announce }
        XCTAssertGreaterThan(announces1.count, 0, "if1 should receive announce")
        XCTAssertGreaterThan(announces2.count, 0, "if2 should receive announce")
    }

    // MARK: - announce on specific interface

    func testAnnounceOnSpecificInterface() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["specific"])
        t.ownerIdentity = id

        let if1 = CapturingInterface(name: "if1")
        let if2 = CapturingInterface(name: "if2")
        t.register(interface: if1)
        t.register(interface: if2)

        try t.announce(destination: dest, onInterface: if1)

        let announces1 = if1.sent.filter { $0.packetType == .announce }
        let announces2 = if2.sent.filter { $0.packetType == .announce }
        XCTAssertGreaterThan(announces1.count, 0, "if1 should receive announce")
        XCTAssertEqual(announces2.count, 0, "if2 should NOT receive announce when if1 specified")
    }

    // MARK: - announce has correct content

    func testAnnounceContainsValidSignature() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["valid"])
        t.ownerIdentity = id

        let iface = CapturingInterface(name: "cap")
        t.register(interface: iface)
        try t.announce(destination: dest)

        let announce = try XCTUnwrap(iface.sent.first(where: { $0.packetType == .announce }))
        let decoded = try Announce.validate(announce)
        XCTAssertEqual(decoded.destinationHash, dest.hash)
    }
}
