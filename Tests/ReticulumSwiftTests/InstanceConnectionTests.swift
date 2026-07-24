import XCTest
@testable import ReticulumSwift

/// Tests for ``InstanceConnection`` — the shared-instance attach logic every `rn*`
/// utility starts with.
///
/// Python reference: `RNS/Reticulum.py` — config-directory resolution in `__init__`
/// and the become-shared-instance / connect-as-client branch in `__start_local_interface`.
final class InstanceConnectionTests: XCTestCase {

    private var temporaryDirectories: [URL] = []
    private var connections: [InstanceConnection] = []

    override func tearDown() {
        for connection in connections { connection.stop() }
        connections = []
        for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
        temporaryDirectories = []
        super.tearDown()
    }

    /// Create a throwaway config directory containing a config file that pins the
    /// shared-instance and control ports well away from the real 37428/37429.
    private func makeConfigDirectory(shareInstance: Bool, sharedPort: UInt16, controlPort: UInt16) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("instconn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)

        let text = """
        [reticulum]
        enable_transport = False
        share_instance = \(shareInstance ? "Yes" : "No")
        shared_instance_port = \(sharedPort)
        instance_control_port = \(controlPort)

        [logging]
        loglevel = 1

        [interfaces]
        """
        try text.write(to: directory.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        return directory
    }

    private func freePortPair() -> (UInt16, UInt16) {
        let base = UInt16.random(in: 41_000...48_000)
        return (base, base &+ 1)
    }

    private func attach(_ directory: URL,
                        requireSharedInstance: Bool = false) throws -> InstanceConnection {
        let connection = try InstanceConnection.attach(configDirectory: directory,
                                                       requireSharedInstance: requireSharedInstance,
                                                       synthesizeInterfaces: false)
        connections.append(connection)
        return connection
    }

    // MARK: - Config directory resolution

    func testResolveConfigDirectory_explicitWins() {
        let explicit = URL(fileURLWithPath: "/tmp/some-reticulum-dir")
        XCTAssertEqual(InstanceConnection.resolveConfigDirectory(explicit), explicit)
    }

    func testResolveConfigDirectory_fallsBackToDotReticulum() {
        // Python's final fallback is ~/.reticulum. The two earlier branches
        // (/etc/reticulum, ~/.config/reticulum) only apply when a *config file*
        // exists there, so on a machine without them this is what we get.
        let resolved = InstanceConnection.resolveConfigDirectory(nil)
        let candidates = [
            URL(fileURLWithPath: "/etc/reticulum"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/reticulum"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".reticulum"),
        ]
        XCTAssertTrue(candidates.contains(resolved), "unexpected config dir \(resolved)")
    }

    func testStoragePathLayout() {
        // Python: storagepath = configdir+"/storage"
        let directory = URL(fileURLWithPath: "/tmp/rns")
        XCTAssertEqual(InstanceConnection.storagePath(for: directory).path, "/tmp/rns/storage")
        XCTAssertEqual(InstanceConnection.configPath(for: directory).path, "/tmp/rns/config")
    }

    // MARK: - Standalone

    func testAttach_shareInstanceDisabled_isStandalone() throws {
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: false, sharedPort: shared, controlPort: control)
        let connection = try attach(directory)
        XCTAssertEqual(connection.role, .standalone)
        XCTAssertFalse(connection.isConnectedToSharedInstance)
        XCTAssertNil(connection.rpc)
    }

    func testAttach_shareInstanceDisabled_requireShared_throws() throws {
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: false, sharedPort: shared, controlPort: control)
        XCTAssertThrowsError(try attach(directory, requireSharedInstance: true)) { error in
            guard case InstanceConnection.InstanceError.noSharedInstance = error else {
                return XCTFail("expected noSharedInstance, got \(error)")
            }
        }
    }

    // MARK: - Becoming the shared instance

    func testAttach_firstProcess_becomesSharedInstance() throws {
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: true, sharedPort: shared, controlPort: control)
        let connection = try attach(directory)
        XCTAssertEqual(connection.role, .sharedInstance)
        XCTAssertFalse(connection.isConnectedToSharedInstance)
    }

    func testAttach_requireShared_whenNoneRunning_throws() throws {
        // Python: "Existing shared instance required, but this instance started as
        // shared instance. Aborting startup."
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: true, sharedPort: shared, controlPort: control)
        XCTAssertThrowsError(try attach(directory, requireSharedInstance: true)) { error in
            guard case InstanceConnection.InstanceError.noSharedInstance = error else {
                return XCTFail("expected noSharedInstance, got \(error)")
            }
        }
    }

    func testAttach_requireShared_releasesThePortItBrieflyBound() throws {
        // The failed require-shared attach must not leave the port held, or the
        // next attach would wrongly see a "running instance".
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: true, sharedPort: shared, controlPort: control)
        XCTAssertThrowsError(try attach(directory, requireSharedInstance: true))

        let connection = try attach(directory)
        XCTAssertEqual(connection.role, .sharedInstance,
                       "port should have been released by the aborted attach")
    }

    // MARK: - Attaching to an existing shared instance

    func testAttach_secondProcess_becomesLocalClient() throws {
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: true, sharedPort: shared, controlPort: control)

        let first = try attach(directory)
        XCTAssertEqual(first.role, .sharedInstance)

        let second = try attach(directory)
        XCTAssertEqual(second.role, .localClient)
        XCTAssertTrue(second.isConnectedToSharedInstance)
    }

    func testAttach_localClient_disablesTransport() throws {
        // Python: `Reticulum.__transport_enabled = False` on the client side.
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: true, sharedPort: shared, controlPort: control)
        _ = try attach(directory)
        let client = try attach(directory)
        XCTAssertEqual(client.role, .localClient)
        XCTAssertFalse(client.reticulum.transport.transportEnabled)
    }

    func testAttach_localClient_marksTransportAsBehindASharedInstance() throws {
        // Python: `Reticulum.is_connected_to_shared_instance = True`, which Transport reads
        // back through `Transport.owner.is_connected_to_shared_instance`.
        //
        // Three behaviours hang off this flag and all of them are wrong while it is false:
        //   - filterAndRecord re-runs the HEADER_2 transport_id filter that the shared
        //     instance has already applied, dropping packets that were forwarded *to us*;
        //   - shouldApplyDelta applies the local hops delta a second time;
        //   - rnprobe takes the standalone branch and never reports RSSI/SNR/Link Quality.
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: true, sharedPort: shared, controlPort: control)

        let instance = try attach(directory)
        XCTAssertEqual(instance.role, .sharedInstance)
        XCTAssertFalse(instance.reticulum.transport.isConnectedToSharedInstance,
                       "the shared instance itself is not behind one")

        let client = try attach(directory)
        XCTAssertEqual(client.role, .localClient)
        XCTAssertTrue(client.reticulum.transport.isConnectedToSharedInstance)
    }

    func testAttach_standalone_isNotBehindASharedInstance() throws {
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: false, sharedPort: shared, controlPort: control)
        let connection = try attach(directory)
        XCTAssertEqual(connection.role, InstanceConnection.Role.standalone)
        XCTAssertFalse(connection.reticulum.transport.isConnectedToSharedInstance)
    }

    func testAttach_localClient_getsWorkingRPCChannel() throws {
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: true, sharedPort: shared, controlPort: control)

        _ = try attach(directory)
        let client = try attach(directory)

        let rpc = try XCTUnwrap(client.rpc, "local client should hold an RPC channel")
        let stats = try rpc.interfaceStats()
        XCTAssertNotNil(stats.asDictionary?["interfaces"],
                        "RPC channel should reach the shared instance we just started")
    }

    func testAttach_requireShared_succeedsAgainstRunningInstance() throws {
        let (shared, control) = freePortPair()
        let directory = try makeConfigDirectory(shareInstance: true, sharedPort: shared, controlPort: control)

        _ = try attach(directory)
        let client = try attach(directory, requireSharedInstance: true)
        XCTAssertEqual(client.role, .localClient)
    }

    // MARK: - Config keys

    func testConfigParsesInstancePorts() throws {
        // These two keys were previously ignored, so a utility could not find an
        // instance running on non-default ports.
        let config = ReticulumConfig.parse("""
        [reticulum]
        shared_instance_port = 47428
        instance_control_port = 47429
        """)
        XCTAssertEqual(config.reticulum.sharedInstancePort, 47428)
        XCTAssertEqual(config.reticulum.instanceControlPort, 47429)
    }

    func testConfigInstancePortDefaults() {
        let config = ReticulumConfig.parse("[reticulum]")
        XCTAssertEqual(config.reticulum.sharedInstancePort, 37428)
        XCTAssertEqual(config.reticulum.instanceControlPort, 37429)
    }
}
