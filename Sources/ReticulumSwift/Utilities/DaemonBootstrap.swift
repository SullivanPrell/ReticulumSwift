import Foundation

/// The filesystem and log-level groundwork every `rnsd`-family process does before a stack
/// exists: work out which directory the configuration lives in, lay out the storage tree,
/// and turn `-v`/`-q` into an actual log level.
///
/// Python reference: `RNS/Reticulum.py`, `Reticulum.__init__` — specifically the
/// config-directory search at lines 229-236, the `makedirs` block at 316-322, the
/// default-config creation at 329-333, and the `[logging] loglevel` arithmetic inside
/// `__apply_config` at 452-460.
///
/// All of this is pure or `FileManager`-injected, so it is drivable from tests with no
/// terminal, no sockets and no live network.
public enum DaemonBootstrap {

    // MARK: - Paths

    /// Every path Python's constructor derives from the configuration directory.
    ///
    /// Python: `Reticulum.configdir` / `configpath` / `storagepath` / `cachepath` /
    /// `resourcepath` / `identitypath` / `blackholepath` / `interfacepath`
    /// (`Reticulum.py:245-251`), plus `RNS.logfile` (`Reticulum.py:237-243`).
    public struct Paths: Equatable {
        /// `<configdir>`.
        public let configDir: URL
        /// `<configdir>/config`.
        public let configFile: URL
        /// `<configdir>/storage`.
        public let storage: URL
        /// `<configdir>/storage/cache`.
        public let cache: URL
        /// `<configdir>/storage/cache/announces`.
        public let announceCache: URL
        /// `<configdir>/storage/resources`.
        public let resources: URL
        /// `<configdir>/storage/identities`.
        public let identities: URL
        /// `<configdir>/storage/blackhole`.
        public let blackhole: URL
        /// `<configdir>/interfaces` — where Python looks for external interface modules.
        public let interfaces: URL
        /// `<configdir>/logfile`. Python: `RNS.logfile = Reticulum.configdir+"/logfile"`.
        public let logFile: URL
        /// `<configdir>/logfile.1` — the single rotated generation Python keeps.
        public let rotatedLogFile: URL

        public init(configDir: URL) {
            self.configDir = configDir
            // Every path resolves through `StorageInventory` — the one place that names the
            // files we persist. `rnsd` bootstraps here rather than through `Reticulum`, so a
            // second set of literals in this file is a second place for bugs/029 to happen.
            self.configFile = StorageInventory.url(.config, in: configDir)
            let storage = StorageInventory.url(.storage, in: configDir)
            self.storage = storage
            self.cache = StorageInventory.url(.cache, in: configDir)
            self.announceCache = StorageInventory.url(.announceCache, in: configDir)
            self.resources = StorageInventory.url(.resources, in: configDir)
            self.identities = StorageInventory.url(.identities, in: configDir)
            self.blackhole = StorageInventory.url(.blackhole, in: configDir)
            self.interfaces = StorageInventory.url(.interfaceModules, in: configDir)
            self.logFile = configDir.appendingPathComponent(RNSDApp.logFileName)
            self.rotatedLogFile = configDir
                .appendingPathComponent(RNSDApp.logFileName + RNSDApp.rotatedLogSuffix)
        }
    }

    /// Resolve the configuration directory Python's way.
    ///
    /// Delegates to ``InstanceConnection/resolveConfigDirectory(_:home:systemConfigDir:fileManager:)``
    /// rather than re-deriving the order, so the two can never drift.
    /// Python: `Reticulum.py:229-236`.
    /// The home directory `~` expands to, honouring `$HOME` the way Python's
    /// `os.path.expanduser` does. See ``InstanceConnection/homeDirectory(environment:)``.
    public static func homeDirectory() -> URL { InstanceConnection.homeDirectory() }

    /// Expand a leading `~` from `$HOME`, as `os.path.expanduser` does.
    ///
    /// Every utility takes its `~`-containing paths through this rather than
    /// `NSString.expandingTildeInPath`, which ignores `$HOME` on macOS. See
    /// ``InstanceConnection/expandTilde(_:environment:)`` and `bugs/024`.
    public static func expandTilde(_ path: String) -> String {
        InstanceConnection.expandTilde(path)
    }

    /// ``expandTilde(_:)``, as a file URL.
    public static func expandTildeURL(_ path: String) -> URL {
        URL(fileURLWithPath: expandTilde(path))
    }

    public static func resolveConfigDir(explicit: String?,
                                        home: URL,
                                        systemConfigDir: URL = URL(fileURLWithPath: "/etc/reticulum"),
                                        fileManager: FileManager = .default) -> URL {
        // Python: `if args.config: configarg = args.config else: configarg = None` —
        // an empty string is falsy, so `--config ''` falls back to the search order.
        let explicitURL = (explicit?.isEmpty == false) ? URL(fileURLWithPath: explicit!) : nil
        return InstanceConnection.resolveConfigDirectory(explicitURL,
                                                         home: home,
                                                         systemConfigDir: systemConfigDir,
                                                         fileManager: fileManager)
    }

    /// Create the seven directories Python's constructor creates, in Python's order.
    ///
    /// Python: `Reticulum.py:316-322` — `storage`, `storage/cache`, `storage/resources`,
    /// `storage/identities`, `storage/blackhole`, `interfaces`, `storage/cache/announces`.
    /// Idempotent, exactly like `os.makedirs` behind an `isdir` guard.
    public static func createStorageTree(_ paths: Paths, fileManager: FileManager = .default) throws {
        // Python: the order below is literal. `interfaces` genuinely comes between
        // `storage/blackhole` and `storage/cache/announces`.
        let ordered = [
            paths.storage,
            paths.cache,
            paths.resources,
            paths.identities,
            paths.blackhole,
            paths.interfaces,
            paths.announceCache,
        ]
        for directory in ordered {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Log level

    /// Turn the config file's `loglevel`, an optional explicit level and the `-v`/`-q`
    /// delta into the level Python would end up with.
    ///
    /// Python, in two places:
    /// - `Reticulum.py:298-305` — an explicit `loglevel=` argument is clamped high-first
    ///   then low into `LOG_CRITICAL...LOG_EXTREME` (0...8) and suppresses the config value.
    /// - `Reticulum.py:452-460` — otherwise `RNS.loglevel = int(value)`, then
    ///   `+= requested_verbosity` when a verbosity was requested, then clamped to `0...7`.
    ///
    /// Two Python quirks are reproduced deliberately:
    /// 1. The config path's ceiling is **7**, not 8, so `LOG_EXTREME` is unreachable via the
    ///    config file or `-v`. The explicit-level path's ceiling really is 8.
    /// 2. When the config file has no `loglevel` key the whole block never runs, so
    ///    `RNS.loglevel` stays at the module default `LOG_NOTICE` and the verbosity delta is
    ///    silently discarded.
    ///
    /// - Parameters:
    ///   - configLogLevel: the `[logging] loglevel` value, or `nil` when the key is absent.
    ///   - requestedLogLevel: Python's `loglevel=` constructor argument. `rnsd`, `rnir` and
    ///     `rnpkg` never pass one.
    ///   - verbosity: `verbose - quiet`, or `nil` in service mode (Python sets
    ///     `targetverbosity = None`, `rnsd.py:45`).
    public static func effectiveLogLevel(configLogLevel: Int?,
                                         requestedLogLevel: Reticulum.LogLevel? = nil,
                                         verbosity: Int?) -> Reticulum.LogLevel {
        if let requestedLogLevel {
            // Python: clamp high first, then low.
            var raw = requestedLogLevel.rawValue
            if raw > Reticulum.LogLevel.extreme.rawValue { raw = Reticulum.LogLevel.extreme.rawValue }
            if raw < Reticulum.LogLevel.critical.rawValue { raw = Reticulum.LogLevel.critical.rawValue }
            return Reticulum.LogLevel(rawValue: raw) ?? .notice
        }

        // Python: no `loglevel` key → the `if option == "loglevel"` branch never fires,
        // RNS.loglevel keeps its module default of LOG_NOTICE, and -v/-q do nothing.
        guard let configLogLevel else { return .notice }

        var level = configLogLevel
        if let verbosity { level += verbosity }
        if level < 0 { level = 0 }
        if level > Reticulum.LogLevel.pathing.rawValue { level = Reticulum.LogLevel.pathing.rawValue }
        return Reticulum.LogLevel(rawValue: level) ?? .notice
    }

    /// The `[logging] loglevel` value in a raw config file, or `nil` when the key is absent.
    ///
    /// ``ReticulumConfig/LoggingSection/logLevel`` defaults to `4`, which is indistinguishable
    /// from an explicit `loglevel = 4`; Python's "key absent → discard the verbosity delta"
    /// rule needs the distinction, so this reads the text directly.
    ///
    /// Mirrors ConfigObj's view of the file: `#` starts a comment, section headers are
    /// `[name]`, and `[[name]]` opens a *sub*section (so `[[Default Interface]]` does not end
    /// the `[logging]` section — but no `[[...]]` block ever appears inside it in practice).
    public static func configuredLogLevel(inConfigText text: String) -> Int? {
        var inLoggingSection = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let stripped = String(rawLine).components(separatedBy: "#")[0]
                .trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }

            if stripped.hasPrefix("[[") {
                continue    // a subsection; does not change the enclosing section
            }
            if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
                inLoggingSection = (stripped == "[logging]")
                continue
            }
            guard inLoggingSection, let equals = stripped.firstIndex(of: "=") else { continue }
            let key = String(stripped[stripped.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
            guard key == "loglevel" else { continue }
            let value = String(stripped[stripped.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
            return Int(value)
        }
        return nil
    }

    // MARK: - Bootstrap

    /// What ``bootstrap(paths:verbosity:fileManager:)`` worked out before a stack exists.
    public struct Bootstrapped {
        /// The configuration file's contents — the default template when one was just written.
        public let configText: String
        /// The parsed configuration.
        public let config: ReticulumConfig
        /// The level Python would have ended up at, already assigned to
        /// ``Reticulum/globalLogLevel``.
        public let logLevel: Reticulum.LogLevel
        /// Whether a default config file was created on this run. Python then sleeps 1.5 s
        /// (`Reticulum.py:333`) so the operator sees the two notices; the caller does that,
        /// since a library function should not block.
        public let createdDefaultConfig: Bool
    }

    /// Everything Python's constructor does between resolving the config directory and
    /// starting Transport: lay out storage, create a default config if there is none, then
    /// apply the `[logging] loglevel` + verbosity arithmetic.
    ///
    /// Python: `Reticulum.py:316-338`.
    public static func bootstrap(paths: Paths,
                                 verbosity: Int?,
                                 fileManager: FileManager = .default) throws -> Bootstrapped {
        try createStorageTree(paths, fileManager: fileManager)

        var createdDefault = false
        if !fileManager.fileExists(atPath: paths.configFile.path) {
            // Python logs both lines at the default level (LOG_NOTICE).
            Reticulum.log("Could not load config file, creating default configuration file...")
            try RNSConfigTemplates.defaultConfig
                .write(to: paths.configFile, atomically: true, encoding: .utf8)
            Reticulum.log("Default config file created. Make any necessary changes in "
                          + paths.configDir.path + "/config and restart Reticulum if needed.")
            createdDefault = true
        }

        let configText = (try? String(contentsOf: paths.configFile, encoding: .utf8))
            ?? RNSConfigTemplates.defaultConfig
        let config = ReticulumConfig.parse(configText)

        let level = effectiveLogLevel(configLogLevel: configuredLogLevel(inConfigText: configText),
                                      verbosity: verbosity)
        Reticulum.globalLogLevel = level

        return Bootstrapped(configText: configText,
                            config: config,
                            logLevel: level,
                            createdDefaultConfig: createdDefault)
    }

    // MARK: - Periodic persistence

    /// Write the state Python's jobs thread checkpoints, without tearing the stack down.
    ///
    /// Python: `Reticulum.__jobs` (`Reticulum.py:369-386`) runs every `JOB_INTERVAL` (300 s)
    /// and calls `__persist_data()` on the `PERSIST_INTERVAL` / `GRACIOUS_PERSIST_INTERVAL`
    /// clocks. ReticulumSwift persists only from ``Reticulum/stop()``, so without this a
    /// daemon that is killed loses every path, known destination and hashlist entry learned
    /// since process start.
    ///
    /// Ratchets are not included: `Reticulum` holds the tracked identity privately and
    /// exposes no checkpoint hook for it, so they are still written only by `stop()`.
    public static func persistState(of reticulum: Reticulum) {
        let storage = reticulum.configuration.storagePath
        try? PathStore.snapshot(of: reticulum.transport)
            .write(to: storage.appendingPathComponent("paths.json"))
        try? reticulum.transport
            .saveKnownDestinations(to: storage.appendingPathComponent("known_destinations.json"))
        try? reticulum.transport
            .savePacketHashlist(to: storage.appendingPathComponent("packet_hashlist"))
        try? reticulum.transport
            .persistBlacklist(toDirectory: StorageInventory.url(.blackhole, storage: storage))
    }
}
