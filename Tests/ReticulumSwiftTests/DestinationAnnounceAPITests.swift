import XCTest
@testable import ReticulumSwift

/// Tests for `Destination.announce(appData:attachedInterface:isPathResponse:)`.
///
/// Python reference:
///   Destination.announce(app_data=None, path_response=False, attached_interface=None, ...)
///
/// Key requirements:
///   - attachedInterface routes the announce to a single interface
///   - isPathResponse tags the announce so it is not re-forwarded
///   - Returns nil when attached_interface is given (no receipt)
///   - Returns a receipt (or nil) when broadcasting on all interfaces
final class DestinationAnnounceAPITests: XCTestCase {

    final class CapturingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    private var tmpDir: URL!
    private var rns: Reticulum?

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-ann-api-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        rns?.stop()
        rns = nil
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func startReticulum() throws -> Reticulum {
        let cfg = Reticulum.Configuration(storagePath: tmpDir.appendingPathComponent("storage"))
        let r = Reticulum(configuration: cfg)
        try r.start()
        rns = r
        return r
    }

    // MARK: - attachedInterface routes to a single interface only

    func testAnnounceOnAttachedInterfaceSendsToThatInterfaceOnly() throws {
        let _ = try startReticulum()
        guard let transport = Reticulum.shared?.transport else {
            XCTFail("shared transport must be available"); return
        }

        let iface1 = CapturingInterface(name: "if1")
        let iface2 = CapturingInterface(name: "if2")
        transport.register(interface: iface1)
        transport.register(interface: iface2)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["annapi"])

        try dest.announce(attachedInterface: iface1)

        XCTAssertEqual(iface1.sent.count, 1, "announce must reach the attached interface")
        XCTAssertEqual(iface2.sent.count, 0, "announce must NOT reach other interfaces")
        XCTAssertEqual(iface1.sent.first?.packetType, .announce)
    }

    // MARK: - attachedInterface returns nil receipt

    func testAnnounceOnAttachedInterfaceReturnsNilReceipt() throws {
        let _ = try startReticulum()
        guard let transport = Reticulum.shared?.transport else { return }

        let iface = CapturingInterface(name: "if3")
        transport.register(interface: iface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["annreceipt"])

        let receipt = try dest.announce(attachedInterface: iface)
        XCTAssertNil(receipt,
                     "announce on attached_interface must return nil receipt (matches Python)")
    }

    // MARK: - isPathResponse tags the packet with .pathResponse context

    func testAnnouncePathResponseSetsContextOnPacket() throws {
        let transport = Transport()
        let iface = CapturingInterface(name: "pr")
        transport.register(interface: iface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["pathresp"])

        // Call transport.announce directly (Reticulum.shared not started here)
        try transport.announce(destination: dest, isPathResponse: true, onInterface: iface)

        let pkt = try XCTUnwrap(iface.sent.first, "announce packet must be sent")
        XCTAssertEqual(pkt.packetType, .announce)
        XCTAssertEqual(pkt.context, .pathResponse,
                       "path-response announce must have context == .pathResponse")
    }

    // MARK: - Default (no arguments) still works

    func testAnnounceDefaultArgumentsCompile() throws {
        let _ = try startReticulum()
        guard let transport = Reticulum.shared?.transport else { return }

        let iface = CapturingInterface(name: "def")
        transport.register(interface: iface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["defann"])

        // Must compile and not throw
        try dest.announce()
    }
}
