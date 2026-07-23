import XCTest
@testable import ReticulumSwift

/// Config-directory resolution, the storage tree and the log-level arithmetic every
/// `rnsd`-family process performs before a stack exists.
///
/// Python reference: `RNS/Reticulum.py` — `__init__` lines 229-236 (config-dir search),
/// 316-322 (`makedirs`), 329-333 (default config creation), 298-305 (explicit `loglevel=`)
/// and `__apply_config` lines 452-460 (the `[logging] loglevel` + verbosity arithmetic).
final class DaemonBootstrapTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var savedLogLevel: Reticulum.LogLevel!
    private var savedLogHandler: ((String, Reticulum.LogLevel) -> Void)?

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaemonBootstrapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        // These tests drive code that writes to the process-global log configuration.
        savedLogLevel = Reticulum.globalLogLevel
        savedLogHandler = Reticulum.logHandler
        Reticulum.logHandler = { _, _ in }
    }

    override func tearDownWithError() throws {
        Reticulum.globalLogLevel = savedLogLevel
        Reticulum.logHandler = savedLogHandler
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: - Config directory search order

    func testResolveConfigDirPrefersExplicit() {
        // Python: `if configdir != None: Reticulum.configdir = configdir`.
        let resolved = DaemonBootstrap.resolveConfigDir(explicit: "/tmp/foo",
                                                        home: temporaryDirectory,
                                                        systemConfigDir: temporaryDirectory)
        XCTAssertEqual(resolved.path, "/tmp/foo")
    }

    func testResolveConfigDirTreatsEmptyStringAsAbsent() {
        // Python: `if args.config:` — '' is falsy, so the search order runs (rnsd.py:79-82).
        let resolved = DaemonBootstrap.resolveConfigDir(explicit: "",
                                                        home: temporaryDirectory,
                                                        systemConfigDir: temporaryDirectory)
        XCTAssertEqual(resolved.path, temporaryDirectory.appendingPathComponent(".reticulum").path)
    }

    func testResolveConfigDirPrefersEtcWhenConfigFilePresent() throws {
        // Python: `elif os.path.isdir("/etc/reticulum") and os.path.isfile("/etc/reticulum/config")`.
        let etc = temporaryDirectory.appendingPathComponent("etc-reticulum")
        try FileManager.default.createDirectory(at: etc, withIntermediateDirectories: true)
        try "".write(to: etc.appendingPathComponent("config"), atomically: true, encoding: .utf8)

        let resolved = DaemonBootstrap.resolveConfigDir(explicit: nil,
                                                        home: temporaryDirectory,
                                                        systemConfigDir: etc)
        XCTAssertEqual(resolved.path, etc.path)
    }

    func testResolveConfigDirIgnoresEtcWithoutConfigFile() throws {
        let etc = temporaryDirectory.appendingPathComponent("etc-reticulum")
        try FileManager.default.createDirectory(at: etc, withIntermediateDirectories: true)

        let resolved = DaemonBootstrap.resolveConfigDir(explicit: nil,
                                                        home: temporaryDirectory,
                                                        systemConfigDir: etc)
        XCTAssertEqual(resolved.path, temporaryDirectory.appendingPathComponent(".reticulum").path)
    }

    func testResolveConfigDirPrefersXDGConfig() throws {
        // Python: `elif os.path.isdir(userdir+"/.config/reticulum") and isfile(.../config)`.
        let xdg = temporaryDirectory.appendingPathComponent(".config/reticulum")
        try FileManager.default.createDirectory(at: xdg, withIntermediateDirectories: true)
        try "".write(to: xdg.appendingPathComponent("config"), atomically: true, encoding: .utf8)

        let resolved = DaemonBootstrap.resolveConfigDir(
            explicit: nil,
            home: temporaryDirectory,
            systemConfigDir: temporaryDirectory.appendingPathComponent("no-such-etc"))
        XCTAssertEqual(resolved.path, xdg.path)
    }

    func testResolveConfigDirFallsBackToDotReticulum() {
        // Python: `else: Reticulum.configdir = Reticulum.userdir+"/.reticulum"` — unconditional,
        // even though nothing exists there yet.
        let resolved = DaemonBootstrap.resolveConfigDir(
            explicit: nil,
            home: temporaryDirectory,
            systemConfigDir: temporaryDirectory.appendingPathComponent("no-such-etc"))
        XCTAssertEqual(resolved.path, temporaryDirectory.appendingPathComponent(".reticulum").path)
    }

    func testResolveConfigDirDelegatesToInstanceConnection() throws {
        // Guards against a second config-dir resolver drifting from the first.
        let xdg = temporaryDirectory.appendingPathComponent(".config/reticulum")
        try FileManager.default.createDirectory(at: xdg, withIntermediateDirectories: true)
        try "".write(to: xdg.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        let etc = temporaryDirectory.appendingPathComponent("no-such-etc")

        for explicit in [nil, "/tmp/explicit"] as [String?] {
            let viaBootstrap = DaemonBootstrap.resolveConfigDir(explicit: explicit,
                                                                home: temporaryDirectory,
                                                                systemConfigDir: etc)
            let viaConnection = InstanceConnection.resolveConfigDirectory(
                explicit.map { URL(fileURLWithPath: $0) },
                home: temporaryDirectory,
                systemConfigDir: etc,
                fileManager: .default)
            XCTAssertEqual(viaBootstrap.path, viaConnection.path, "explicit: \(String(describing: explicit))")
        }
    }

    // MARK: - Paths

    func testPathsLayout() {
        let root = URL(fileURLWithPath: "/tmp/rns-config")
        let paths = DaemonBootstrap.Paths(configDir: root)
        XCTAssertEqual(paths.configFile.path, "/tmp/rns-config/config")
        XCTAssertEqual(paths.storage.path, "/tmp/rns-config/storage")
        XCTAssertEqual(paths.cache.path, "/tmp/rns-config/storage/cache")
        XCTAssertEqual(paths.announceCache.path, "/tmp/rns-config/storage/cache/announces")
        XCTAssertEqual(paths.resources.path, "/tmp/rns-config/storage/resources")
        XCTAssertEqual(paths.identities.path, "/tmp/rns-config/storage/identities")
        XCTAssertEqual(paths.blackhole.path, "/tmp/rns-config/storage/blackhole")
        XCTAssertEqual(paths.interfaces.path, "/tmp/rns-config/interfaces")
        XCTAssertEqual(paths.logFile.path, "/tmp/rns-config/logfile")
        XCTAssertEqual(paths.rotatedLogFile.path, "/tmp/rns-config/logfile.1")
    }

    func testCreateStorageTree() throws {
        // Python: seven makedirs calls at Reticulum.py:316-322.
        let paths = DaemonBootstrap.Paths(configDir: temporaryDirectory.appendingPathComponent("cfg"))
        try DaemonBootstrap.createStorageTree(paths)

        for directory in [paths.storage, paths.cache, paths.announceCache, paths.resources,
                          paths.identities, paths.blackhole, paths.interfaces] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                          "missing \(directory.lastPathComponent)")
            XCTAssertTrue(isDirectory.boolValue, "\(directory.path) is not a directory")
        }

        // Python guards every call with `if not os.path.isdir(...)`, so a second run is a no-op.
        XCTAssertNoThrow(try DaemonBootstrap.createStorageTree(paths))
    }

    // MARK: - Log level arithmetic

    func testEffectiveLogLevelAddsVerbosity() {
        // Python: `RNS.loglevel = int(value)` then `RNS.loglevel += requested_verbosity`.
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 4, verbosity: 1), .verbose)
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 4, verbosity: 2), .debug)
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 4, verbosity: -1), .notice)
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 4, verbosity: 0), .info)
    }

    func testEffectiveLogLevelClampsAtSeven() {
        // Python: `if RNS.loglevel > 7: RNS.loglevel = 7` — LOG_EXTREME (8) is unreachable
        // through the config file or -v, only through an explicit loglevel= argument.
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 4, verbosity: 10), .pathing)
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 7, verbosity: 1), .pathing)
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 8, verbosity: nil), .pathing)
    }

    func testEffectiveLogLevelClampsAtZero() {
        // Python: `if RNS.loglevel < 0: RNS.loglevel = 0`.
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 0, verbosity: -5), .critical)
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 2, verbosity: -10), .critical)
    }

    func testEffectiveLogLevelIgnoresVerbosityWhenConfigKeyAbsent() {
        // Python: with no `loglevel` key the whole branch never runs, so RNS.loglevel keeps
        // its module default of LOG_NOTICE and -v/-q are silently discarded.
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: nil, verbosity: 3), .notice)
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: nil, verbosity: -3), .notice)
    }

    func testEffectiveLogLevelServiceModeUsesConfigVerbatim() {
        // Python: service mode sets targetverbosity = None (rnsd.py:45).
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 6, verbosity: nil), .debug)
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 0, verbosity: nil), .critical)
    }

    func testRequestedLogLevelWinsAndClampsAtEight() {
        // Python: an explicit loglevel= suppresses the config value and the delta, and its
        // ceiling really is LOG_EXTREME (Reticulum.py:298-305) — unlike the config path's 7.
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 4,
                                                         requestedLogLevel: .extreme,
                                                         verbosity: 3), .extreme)
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: nil,
                                                         requestedLogLevel: .critical,
                                                         verbosity: 5), .critical)
        // Clamped high first, then low. Spelled out because a bare `.none` in an
        // `Optional<LogLevel>` position resolves to `Optional.none`, not `LogLevel.none`.
        XCTAssertEqual(DaemonBootstrap.effectiveLogLevel(configLogLevel: 4,
                                                         requestedLogLevel: Reticulum.LogLevel.none,
                                                         verbosity: nil), .critical)
    }

    // MARK: - Reading the config file's loglevel

    func testConfiguredLogLevelReadsLoggingSection() {
        XCTAssertEqual(DaemonBootstrap.configuredLogLevel(inConfigText: "[logging]\nloglevel = 6\n"), 6)
        XCTAssertNil(DaemonBootstrap.configuredLogLevel(inConfigText: "[logging]\nlogtimestamps = no\n"))
        XCTAssertNil(DaemonBootstrap.configuredLogLevel(inConfigText: "[reticulum]\nloglevel = 6\n"))
        // Commented-out keys do not count — the example config's legend is all comments.
        XCTAssertNil(DaemonBootstrap.configuredLogLevel(inConfigText: "[logging]\n# loglevel = 6\n"))
    }

    func testConfiguredLogLevelOfShippedTemplates() {
        // Both Python templates carry `loglevel = 4`.
        XCTAssertEqual(DaemonBootstrap.configuredLogLevel(inConfigText: RNSConfigTemplates.defaultConfig), 4)
        XCTAssertEqual(DaemonBootstrap.configuredLogLevel(inConfigText: RNSConfigTemplates.exampleConfig), 4)
    }

    // MARK: - Bootstrap

    func testBootstrapCreatesDefaultConfigAndStorageTree() throws {
        let paths = DaemonBootstrap.Paths(configDir: temporaryDirectory.appendingPathComponent("fresh"))
        let result = try DaemonBootstrap.bootstrap(paths: paths, verbosity: 1)

        XCTAssertTrue(result.createdDefaultConfig)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.announceCache.path))
        // Python's default config has `loglevel = 4`; -v makes it LOG_VERBOSE.
        XCTAssertEqual(result.logLevel, .verbose)
        XCTAssertEqual(Reticulum.globalLogLevel, .verbose)
        XCTAssertEqual(result.config.interfaces.count, 1)
        XCTAssertEqual(result.config.interfaces[0].type, "AutoInterface")
    }

    func testBootstrapIsIdempotentAndDoesNotRewriteConfig() throws {
        let paths = DaemonBootstrap.Paths(configDir: temporaryDirectory.appendingPathComponent("twice"))
        _ = try DaemonBootstrap.bootstrap(paths: paths, verbosity: nil)
        try "[logging]\nloglevel = 2\n".write(to: paths.configFile, atomically: true, encoding: .utf8)

        let second = try DaemonBootstrap.bootstrap(paths: paths, verbosity: nil)
        XCTAssertFalse(second.createdDefaultConfig)
        XCTAssertEqual(second.logLevel, .warning)
        XCTAssertEqual(second.configText, "[logging]\nloglevel = 2\n")
    }
}
