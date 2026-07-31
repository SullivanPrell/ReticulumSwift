import XCTest
@testable import ReticulumSwift

/// `storage/tunnels` — the one file in `bugs/029` that is not a divergence but an absence.
///
/// The reference writes the tunnel table on the same clock as the path table
/// (`Transport.persist_data` at `Transport.py:3510-3512`) and restores it at start (`:368-405`).
/// The port writes no counterpart at all, so a node with an established tunnel loses every tunnel
/// path across a restart and cannot serve them again until the peer re-announces — which for a
/// tunnel endpoint that is itself waiting is not guaranteed to happen at all.
///
/// The entry is `[tunnel_id, interface_hash, paths, expires]` (`:3487`), where each path is the
/// same 8-element list the destination table uses. So the two files share a codec, and the tunnel
/// restore has the same announce-cache dependency: a path whose announce cannot be loaded is
/// dropped (`:398`).
final class TunnelPersistenceTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-tunnels-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private var fileURL: URL {
        tmpDir.appendingPathComponent(StorageInventory.Entry.tunnels.components.last!)
    }

    private func makeTransport() -> (Transport, LoopbackInterface) {
        let transport = Transport()
        transport.cacheDirectory = tmpDir.appendingPathComponent("cache")
        let iface = LoopbackInterface(name: "tun0")
        transport.register(interface: iface)
        return (transport, iface)
    }

    /// Install a tunnel holding one path, the way `handle_tunnel` and the announce handler leave
    /// it: an interface, an expiry, and paths carrying their cached announce.
    @discardableResult
    private func installTunnel(on transport: Transport,
                               through interface: any Interface,
                               tunnelID: Data,
                               aspect: String = "tunnelpath") throws -> Data {
        let installed = try installPersistablePath(on: transport, through: interface,
                                                   aspect: aspect)
        let path = transport.paths[installed.destinationHash]!
        transport.tunnels[tunnelID] = Transport.TunnelEntry(
            tunnelID: tunnelID,
            iface: interface,
            paths: [installed.destinationHash: path],
            expires: Date().addingTimeInterval(Transport.tunnelTimeout)
        )
        return installed.destinationHash
    }

    // MARK: - The gap

    func testTunnelTableSurvivesRestart() throws {
        let (live, iface) = makeTransport()
        let tunnelID = Hashes.fullHash(Data("tunnel".utf8))
        let destHash = try installTunnel(on: live, through: iface, tunnelID: tunnelID)

        try TunnelStore.snapshot(of: live).write(to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      """
                      the reference writes `storage/tunnels` on the same clock as the path table \
                      (Transport.py:3510-3512). Nothing in the port writes it, so an established \
                      tunnel does not outlive the process.
                      """)

        let (revived, _) = makeTransport()
        try TunnelStore.read(from: fileURL).apply(to: revived)

        let tunnel = try XCTUnwrap(revived.tunnels[tunnelID],
                                   "the tunnel must be in the table after the restart, without "
                                   + "waiting for the peer to re-announce")
        XCTAssertEqual(tunnel.paths.count, 1)
        XCTAssertNotNil(tunnel.paths[destHash], "and it must still carry its path")
    }

    // MARK: - The shape

    /// `serialised_tunnel = [tunnel_id, interface_hash, serialised_paths, expires]` —
    /// `Transport.py:3487`, indexed positionally at `:373-376`.
    func testEntryIsTheReferenceFourElementList() throws {
        let (live, iface) = makeTransport()
        let tunnelID = Hashes.fullHash(Data("shape".utf8))
        try installTunnel(on: live, through: iface, tunnelID: tunnelID)
        try TunnelStore.snapshot(of: live).write(to: fileURL)

        guard case .array(let entries) = try MsgPack.decode(Data(contentsOf: fileURL)),
              case .array(let fields) = entries.first else {
            return XCTFail("the file is `umsgpack.packb(serialised_tunnels)` (Transport.py:3491)")
        }
        XCTAssertEqual(fields.count, 4,
                       "[tunnel_id, interface_hash, paths, expires] (Transport.py:3487)")
        guard fields.count == 4 else { return }

        XCTAssertEqual(fields[0], .bytes(tunnelID))
        XCTAssertEqual(fields[1], .bytes(iface.hash),
                       "field 1 is the tunnel's `interface.get_hash()` (Transport.py:3456)")

        guard case .array(let paths) = fields[2], case .array(let path) = paths.first else {
            return XCTFail("field 2 is the list of serialised paths")
        }
        XCTAssertEqual(path.count, 8,
                       """
                       a tunnel path is the same 8-element list as a destination table entry \
                       (Transport.py:3470-3479), so the two files share one codec — and one \
                       announce-cache dependency.
                       """)
    }

    /// `if interface != None: interface_hash = interface.get_hash() else: interface_hash = None`
    /// (`Transport.py:3456-3457`) — a tunnel whose interface has gone is still written, with a
    /// null interface. `TunnelEntry.iface` is weak here, so this is the state after the interface
    /// is deregistered, not a hypothetical.
    func testTunnelWithNoInterfaceIsStillWritten() throws {
        let (live, iface) = makeTransport()
        let tunnelID = Hashes.fullHash(Data("nointerface".utf8))
        try installTunnel(on: live, through: iface, tunnelID: tunnelID)
        live.tunnels[tunnelID]?.iface = nil

        try TunnelStore.snapshot(of: live).write(to: fileURL)

        guard case .array(let entries) = try MsgPack.decode(Data(contentsOf: fileURL)),
              case .array(let fields) = entries.first, fields.count == 4 else {
            return XCTFail("the tunnel must still be written")
        }
        XCTAssertEqual(fields[1], .nil,
                       "a tunnel whose interface is gone writes None, not a placeholder")
    }

    /// `if announce_packet != None: … tunnel_paths[destination_hash] = tunnel_path` and
    /// `if len(tunnel_paths) > 0` (`Transport.py:398-404`) — a tunnel all of whose paths lost
    /// their announce is not restored at all.
    func testTunnelWithNoRestorablePathIsDropped() throws {
        let (live, iface) = makeTransport()
        let tunnelID = Hashes.fullHash(Data("noannounce".utf8))
        try installTunnel(on: live, through: iface, tunnelID: tunnelID)
        try TunnelStore.snapshot(of: live).write(to: fileURL)

        // Empty the announce cache: the entry now names a hash nothing answers.
        try FileManager.default.removeItem(at: tmpDir.appendingPathComponent("cache"))

        let (revived, _) = makeTransport()
        try TunnelStore.read(from: fileURL).apply(to: revived)

        XCTAssertNil(revived.tunnels[tunnelID],
                     """
                     the reference installs a tunnel only when at least one of its paths came \
                     back (Transport.py:402). An empty tunnel is a tunnel that can route nothing.
                     """)
    }

    /// The restored tunnel's interface is null, exactly as `tunnel = [tunnel_id, None,
    /// tunnel_paths, expires]` sets it (`Transport.py:403`): the tunnel is re-attached to a live
    /// interface when the endpoint reappears, not by the restore.
    func testRestoredTunnelHasNoInterfaceUntilTheEndpointReappears() throws {
        let (live, iface) = makeTransport()
        let tunnelID = Hashes.fullHash(Data("reattach".utf8))
        try installTunnel(on: live, through: iface, tunnelID: tunnelID)
        try TunnelStore.snapshot(of: live).write(to: fileURL)

        let (revived, _) = makeTransport()
        try TunnelStore.read(from: fileURL).apply(to: revived)

        XCTAssertNotNil(revived.tunnels[tunnelID])
        XCTAssertNil(revived.tunnels[tunnelID]?.iface,
                     "field 1 of the restored tunnel is None (Transport.py:403)")
    }

    // MARK: - Wired into the lifecycle

    /// Python persists all three tables together (`Transport.persist_data`,
    /// `Transport.py:3510-3512`) and restores the tunnel table immediately after the destination
    /// table (`:365`). A `TunnelStore` nothing calls is the same defect one level out.
    func testReticulumStopWritesTunnelsAndStartRestoresThem() throws {
        let dir = tmpDir.appendingPathComponent("lifecycle")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = Reticulum.Configuration(storagePath: dir)
        let tunnelID = Hashes.fullHash(Data("lifecycle".utf8))
        var destHash = Data()

        let rns = Reticulum(configuration: config)
        try rns.start()
        let iface = LoopbackInterface(name: "tun0")
        rns.transport.register(interface: iface)
        destHash = try installTunnel(on: rns.transport, through: iface, tunnelID: tunnelID)
        rns.stop()

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: StorageInventory.url(.tunnels, storage: dir).path),
            "stop() must write the tunnel table alongside the path table")

        let revived = Reticulum(configuration: config)
        revived.transport.register(interface: LoopbackInterface(name: "tun0"))
        try revived.start()
        defer { revived.stop() }

        let tunnel = try XCTUnwrap(revived.transport.tunnels[tunnelID],
                                   "start() must restore the tunnel table (Transport.py:365-405)")
        XCTAssertNotNil(tunnel.paths[destHash])
    }
}
