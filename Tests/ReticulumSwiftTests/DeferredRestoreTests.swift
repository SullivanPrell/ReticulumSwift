import XCTest
@testable import ReticulumSwift

/// A restored path must survive interfaces that register *after* the tables are read.
///
/// `bugs/041` — the reference builds every configured interface in `__apply_config()` and only
/// then calls `Transport.start()`, which reads the tables (`Reticulum.py:340` before `:346`), so
/// `find_interface_from_hash` always has something to find. In this port the daemon's interfaces
/// are synthesised by `rnsd` *after* `Reticulum.start()` returns, so the restore ran against an
/// empty interface set and dropped every entry, every time. The path table had never survived a
/// restart in a real daemon — under any on-disk format, which is why the `bugs/029` format work
/// alone would not have fixed it.
///
/// Found by `tri-test`'s `test_python_state_read_by_swift`, not by a unit test: every unit test
/// registered its interface before calling `start()`, which is the one order the daemon does not
/// use.
final class DeferredRestoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-deferred-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private var tableURL: URL { StorageInventory.url(.destinationTable, storage: tmpDir) }

    private func makeTransport() -> Transport {
        let transport = Transport()
        transport.cacheDirectory = tmpDir.appendingPathComponent("cache")
        return transport
    }

    /// Write a table holding one path through an interface named `eth0`.
    private func seedTable() throws -> Data {
        let live = makeTransport()
        let iface = LoopbackInterface(name: "eth0")
        live.register(interface: iface)
        let installed = try installPersistablePath(on: live, through: iface, aspect: "deferred")
        try PathStore.snapshot(of: live).write(to: tableURL)
        return installed.destinationHash
    }

    // MARK: - The defect

    func testAPathIsInstalledWhenItsInterfaceRegistersLater() throws {
        let destHash = try seedTable()

        // The daemon's order: read the tables, *then* bring up interfaces.
        let revived = makeTransport()
        try PathStore.read(from: tableURL).apply(to: revived)
        XCTAssertNil(revived.paths[destHash],
                     "nothing can be installed yet — there is no interface to resolve against")

        revived.register(interface: LoopbackInterface(name: "eth0"))

        XCTAssertNotNil(revived.paths[destHash],
                        """
                        the entry must be installed once its interface appears. Resolving only \
                        at read time drops every entry in a real daemon, because `rnsd` \
                        synthesises interfaces after `Reticulum.start()` returns (bugs/041).
                        """)
        XCTAssertEqual(revived.paths[destHash]?.nextHopInterfaceName, "eth0")
    }

    /// The order the unit suite has always used still works, and does not leave the entry parked.
    func testAPathIsInstalledImmediatelyWhenItsInterfaceIsAlreadyThere() throws {
        let destHash = try seedTable()

        let revived = makeTransport()
        revived.register(interface: LoopbackInterface(name: "eth0"))
        try PathStore.read(from: tableURL).apply(to: revived)

        XCTAssertNotNil(revived.paths[destHash])
        XCTAssertTrue(revived.pendingPathRestores.isEmpty,
                      "an entry installed on the spot must not also be held pending")
    }

    /// An interface that never arrives costs the entry, as it does in the reference — the wait is
    /// bounded, not indefinite. Otherwise a discovered interface registering minutes later would
    /// install a path the reference had already discarded.
    func testAnEntryWhoseInterfaceNeverArrivesIsGivenUpOn() throws {
        let destHash = try seedTable()

        let revived = makeTransport()
        try PathStore.read(from: tableURL).apply(to: revived)
        XCTAssertFalse(revived.pendingPathRestores.isEmpty, "parked, waiting for `eth0`")

        // Rewind the clock past the window rather than sleeping through it.
        revived.lock.lock()
        revived.pendingRestoresReadAt = Date(timeIntervalSinceNow: -Transport.pendingRestoreWindow - 1)
        revived.lock.unlock()
        revived.sweepPendingRestores()

        XCTAssertTrue(revived.pendingPathRestores.isEmpty, "the wait is bounded")

        revived.register(interface: LoopbackInterface(name: "eth0"))
        XCTAssertNil(revived.paths[destHash],
                     "an interface arriving after the window installs nothing — the reference "
                     + "drops such an entry permanently (Transport.py:334,348)")
    }

    /// An entry that failed for a reason an interface cannot fix is *not* parked. Otherwise the
    /// pending set fills with entries that can never install, and the sweep's log line reports a
    /// problem that is not one.
    func testAnEntryWithNoCachedAnnounceIsNotParked() throws {
        let live = makeTransport()
        let iface = LoopbackInterface(name: "eth0")
        live.register(interface: iface)
        try installPersistablePath(on: live, through: iface, aspect: "noannounce")
        try PathStore.snapshot(of: live).write(to: tableURL)
        try FileManager.default.removeItem(at: tmpDir.appendingPathComponent("cache"))

        let revived = makeTransport()
        revived.register(interface: LoopbackInterface(name: "eth0"))
        try PathStore.read(from: tableURL).apply(to: revived)

        XCTAssertTrue(revived.pendingPathRestores.isEmpty,
                      "a missing announce is final; only a missing interface is recoverable")
    }

    // MARK: - Tunnels do not need this, and must not get it

    /// A tunnel restores whether or not its interface is present, so it is never parked.
    ///
    /// The reference restores a tunnel path with `receiving_interface = None` and gates only on
    /// the announce (`Transport.py:398-400`), attaching an interface to every one of the tunnel's
    /// paths when the endpoint reappears (`:2440-2447`). Deferring it would delay a tunnel that
    /// was ready, and would leave `TunnelStore`'s share of the pending machinery permanently
    /// empty — dead code that reads as coverage.
    func testATunnelRestoresWithoutWaitingForAnInterface() throws {
        let live = makeTransport()
        let iface = LoopbackInterface(name: "tun0")
        live.register(interface: iface)
        let installed = try installPersistablePath(on: live, through: iface, aspect: "tunnel")
        let tunnelID = Hashes.fullHash(Data("deferred-tunnel".utf8))
        live.tunnels[tunnelID] = Transport.TunnelEntry(
            tunnelID: tunnelID,
            iface: iface,
            paths: [installed.destinationHash: live.paths[installed.destinationHash]!],
            expires: Date().addingTimeInterval(Transport.tunnelTimeout))
        let url = StorageInventory.url(.tunnels, storage: tmpDir)
        try TunnelStore.snapshot(of: live).write(to: url)

        let revived = makeTransport()
        try TunnelStore.read(from: url).apply(to: revived)

        let tunnel = try XCTUnwrap(revived.tunnels[tunnelID],
                                   "the tunnel restores with no interface registered at all")
        XCTAssertNil(tunnel.iface, "field 1 of a restored tunnel is None (Transport.py:403)")
        XCTAssertNil(tunnel.paths[installed.destinationHash]?.nextHopInterface,
                     "and its paths are unattached until the endpoint reappears")
        XCTAssertTrue(revived.pendingPathRestores.isEmpty,
                      "nothing about a tunnel is parked waiting for an interface")
    }
}
