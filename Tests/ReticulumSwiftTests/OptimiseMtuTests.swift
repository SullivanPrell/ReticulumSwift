import XCTest
@testable import ReticulumSwift

/// Python recomputes `HW_MTU` from the bitrate on every autoconfiguring interface —
/// `optimise_mtu()` (`Interface.py:205-217`), called unconditionally after the configured
/// bitrate lands (`Reticulum.py:914-915`) and on each spawned server-side client
/// (`TCPInterface.py:612-613`). The class attributes (262144 for TCP, 1048576 for Backbone)
/// never survive Python startup: a TCP interface runs at 8192 (bitrate guess 10e6) and a
/// dialing backbone at 16384 (guess 100e6). The port kept the class constants as `let`s —
/// the audit's structural class of a runtime-mutated Python attribute frozen at `{ get }` —
/// so Swift's LINKREQUEST MTU signalling advertised 262144/1048576 where Python advertises
/// 8192/16384 in the identical topology.
final class OptimiseMtuTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rns_mtu_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStack() -> Reticulum {
        Reticulum(configuration: .init(storagePath: tempDir, shareInstance: false))
    }

    private func parse(_ blocks: String) -> ReticulumConfig {
        ReticulumConfig.parse("""
        [reticulum]
          enable_transport = no
          share_instance = no

        [interfaces]
        \(blocks)
        """)
    }

    private func synthesized(_ blocks: String, name: String,
                             file: StaticString = #filePath,
                             line: UInt = #line) throws -> any Interface {
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse(blocks))
        guard let iface = stack.transport.interfaces.first(where: { $0.name == name }) else {
            XCTFail("interface '\(name)' was not constructed", file: file, line: line)
            throw XCTSkip("construction failed")
        }
        return iface
    }

    // MARK: - The ladder itself

    /// Every rung, both boundary sides, exactly `Interface.py:207-217`. Note the top rung is
    /// `>=` where all others are `>`, and everything at or below 62 500 bit/s has no
    /// hardware MTU at all.
    func testTheLadderMatchesThePythonRungs() {
        let expectations: [(bitrate: Int, mtu: Int?)] = [
            (1_000_000_000, 524_288),   // >= 1e9 — the one inclusive rung
            (999_999_999, 262_144),     // > 750e6
            (750_000_001, 262_144),
            (750_000_000, 131_072),     // > 400e6
            (400_000_000, 65_536),      // > 200e6
            (200_000_000, 32_768),      // > 100e6
            (100_000_000, 16_384),      // > 10e6 — the dialing-backbone guess lands here
            (10_000_000, 8_192),        // > 5e6 — the TCP guess lands here
            (5_000_000, 4_096),         // > 2e6
            (2_000_000, 2_048),         // > 1e6
            (1_000_000, 1_024),         // > 62_500
            (62_501, 1_024),
            (62_500, nil),              // else: None
            (300, nil),
        ]
        for (bitrate, mtu) in expectations {
            XCTAssertEqual(RNSInterfaceMtu.optimised(forBitrate: bitrate), mtu,
                           "bitrate \(bitrate) must map to \(String(describing: mtu)) "
                           + "(Interface.py:207-217)")
        }
    }

    // MARK: - The config path runs it

    func testAConfiguredTCPClientRunsAtThePythonOptimisedMtu() throws {
        let iface = try synthesized("""
          [[Uplink]]
            type = TCPClientInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4965
        """, name: "Uplink")
        XCTAssertEqual(iface.hwMtu, 8_192,
                       """
                       a TCP client's class constant (262144) must not survive startup: Python \
                       runs optimise_mtu() after post-init (Reticulum.py:915) and the bitrate \
                       guess of 10e6 lands on the 8192 rung — the 3-byte LINKREQUEST MTU \
                       signalling advertises this value to every directly connected peer
                       """)
    }

    func testAConfiguredBackboneRunsAtThePythonOptimisedMtu() throws {
        let iface = try synthesized("""
          [[Fat Pipe]]
            type = BackboneInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4966
        """, name: "Fat Pipe")
        XCTAssertEqual(iface.hwMtu, 16_384,
                       "a dialing backbone's guess of 100e6 lands on the 16384 rung "
                       + "(BackboneInterface.py:568, Interface.py:212); the 1MB class constant "
                       + "is a listener-side value Python never keeps on a client either")
    }

    func testAConfiguredBitrateReoptimisesTheMtu() throws {
        let iface = try synthesized("""
          [[Slow Uplink]]
            type = TCPClientInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4967
            bitrate = 1500000
        """, name: "Slow Uplink")
        XCTAssertEqual(iface.hwMtu, 2_048,
                       "optimise_mtu runs after the configured bitrate is applied "
                       + "(Reticulum.py:914-915), so an operator-set 1.5 Mb/s lands on the "
                       + "2048 rung (> 1e6, Interface.py:215), not the class guess's 8192")
    }

    // MARK: - The spawn path runs it

    func testASpawnedServerClientOptimisesFromItsInheritedBitrate() {
        let server = TCPServerInterface(name: "Listener", port: 0)
        let spawned = TCPServerClientInterface(name: "Client on Listener",
                                               parentServer: server,
                                               peerHost: "10.0.0.9", peerPort: 51000)
        XCTAssertEqual(spawned.hwMtu, 8_192,
                       "Python optimises each spawned client after copying the parent bitrate "
                       + "(TCPInterface.py:611-613); the inherited 10e6 guess lands on 8192")
    }

    // MARK: - The Local sibling gap

    func testTheLocalClientInterfaceCarriesPythonsMtu() {
        let iface = LocalInterface(name: "Local shared instance", port: 0)
        XCTAssertEqual(iface.hwMtu, 262_144,
                       "LocalClientInterface.HW_MTU = 262144 (LocalInterface.py:71); with nil "
                       + "here, link-MTU discovery through a Swift shared instance is disabled "
                       + "entirely — every local-client link stays at the 500-byte default")
        XCTAssertTrue(iface.autoconfigureMtu,
                      "AUTOCONFIGURE_MTU = True (LocalInterface.py:64)")
    }

    // MARK: - Structural guard

    /// `autoconfigureMtu == true` promises the MTU follows the bitrate; a type that says so
    /// without a settable `hwMtu` makes `optimiseMtu()` a silent no-op — the exact `{ get }`-only
    /// freeze this fix removes. Constructed through the same config machinery the daemon uses,
    /// so a new interface type joins this list by being constructible, not by being remembered.
    func testEveryAutoconfiguringTypeHasASettableMtu() throws {
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[T1]]
            type = TCPClientInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4968

          [[T2]]
            type = BackboneInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4969

          [[T3]]
            type = TCPServerInterface
            enabled = yes
            listen_ip = 127.0.0.1
            listen_port = 4970

          [[T4]]
            type = UDPInterface
            enabled = yes
            listen_ip = 127.0.0.1
            listen_port = 4971
        """))
        let constructed = stack.transport.interfaces
        XCTAssertGreaterThanOrEqual(constructed.count, 4, "all four blocks must construct")
        for iface in constructed where iface.autoconfigureMtu {
            XCTAssertTrue(iface is MtuAutoconfiguringInterface,
                          "\(iface.displayName) claims autoconfigureMtu but its hwMtu is not "
                          + "settable — optimiseMtu() cannot write it and the claim is inert")
        }
        // And the local pair, which the config path does not build.
        XCTAssertTrue(LocalInterface(name: "l", port: 0) is MtuAutoconfiguringInterface)
        XCTAssertTrue(PosixTCPServer(name: "ls", port: 0) is MtuAutoconfiguringInterface)
    }
}
