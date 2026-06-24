import XCTest
@testable import ReticulumSwift

/// Tests for interface synthesis from config.
final class InterfaceSynthesisTests: XCTestCase {

    private var tmpDir: URL!
    private var rns: Reticulum?

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-iface-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        rns?.stop()
        rns = nil
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func makeRns(config: ReticulumConfig) throws -> Reticulum {
        let storage = tmpDir.appendingPathComponent("storage")
        let c = Reticulum.Configuration(storagePath: storage)
        let r = Reticulum(configuration: c)
        try r.start()
        rns = r
        return r
    }

    // MARK: - Supported interface types

    func testUDPInterfaceSynthesizedFromConfig() throws {
        var cfg = ReticulumConfig()
        cfg.interfaces = [ReticulumConfig.InterfaceConfig(
            name: "TestUDP",
            type: "UDPInterface",
            enabled: true,
            parameters: ["listen_port": "54321", "forward_ip": "127.0.0.1", "forward_port": "54321"]
        )]
        let r = try makeRns(config: cfg)
        try r.synthesizeInterfaces(from: cfg)
        XCTAssertGreaterThan(r.transport.interfaces.count, 0)
    }

    func testUnknownInterfaceTypeSilentlyIgnored() throws {
        var cfg = ReticulumConfig()
        cfg.interfaces = [ReticulumConfig.InterfaceConfig(
            name: "Unknown",
            type: "BackboneInterface",  // Not implemented in Swift
            enabled: true,
            parameters: [:]
        )]
        let r = try makeRns(config: cfg)
        // Should not throw — unknown types are silently ignored
        XCTAssertNoThrow(try r.synthesizeInterfaces(from: cfg))
        // No interfaces registered for unknown types
        XCTAssertEqual(r.transport.interfaces.count, 0)
    }

    func testDisabledInterfaceNotSynthesized() throws {
        var cfg = ReticulumConfig()
        cfg.interfaces = [ReticulumConfig.InterfaceConfig(
            name: "DisabledUDP",
            type: "UDPInterface",
            enabled: false,  // disabled
            parameters: ["listen_port": "54322"]
        )]
        let r = try makeRns(config: cfg)
        try r.synthesizeInterfaces(from: cfg)
        XCTAssertEqual(r.transport.interfaces.count, 0, "disabled interface should not be synthesized")
    }
}
