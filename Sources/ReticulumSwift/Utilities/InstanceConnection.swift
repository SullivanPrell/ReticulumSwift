import Foundation

/// How a utility process obtains a Reticulum stack: by attaching to an instance that is
/// already running, or by standing one up itself.
///
/// Python reference: `RNS/Reticulum.py`, `__init__` (config-directory resolution) and
/// `__start_local_interface` (become the shared instance, or connect to the one already
/// there). Every `rn*` utility begins by constructing `RNS.Reticulum(...)` and then
/// branching on `is_connected_to_shared_instance`; this type is the Swift equivalent of
/// that opening move, so the utilities do not each re-derive it.
///
/// The three outcomes match Python's three flags exactly:
///
/// | Outcome                | Python flags                                        |
/// |------------------------|-----------------------------------------------------|
/// | ``Role/sharedInstance``| `is_shared_instance = True`                         |
/// | ``Role/localClient``   | `is_connected_to_shared_instance = True`            |
/// | ``Role/standalone``    | `is_standalone_instance = True`                     |
///
/// Note that `Reticulum` itself is deliberately left alone: it does not probe or bind
/// anything on `start()`, because embedders such as RetiOS manage their own interface
/// set. Attaching is a utility-level concern, so it lives here.
public final class InstanceConnection {

    // MARK: - Role

    /// Which side of the shared-instance relationship this process ended up on.
    public enum Role: Equatable {
        /// We bound the shared-instance port and now serve local clients.
        /// Python: `is_shared_instance`.
        case sharedInstance
        /// Another instance already owned the port, so we attached to it as a client.
        /// Python: `is_connected_to_shared_instance`.
        case localClient
        /// Instance sharing is off, so we own a private stack with no local socket.
        /// Python: `is_standalone_instance`.
        case standalone
    }

    // MARK: - State

    /// The live stack.
    public let reticulum: Reticulum

    /// Parsed configuration file contents.
    public let config: ReticulumConfig

    /// Directory holding `config`, `storage/`, `interfaces/`.
    public let configDirectory: URL

    /// How this process is attached.
    public private(set) var role: Role

    /// Management RPC channel — non-nil only when attached as a ``Role/localClient``,
    /// because that is the only case where another process owns the state worth asking about.
    public private(set) var rpc: RPCClient?

    /// Python: `is_connected_to_shared_instance`.
    public var isConnectedToSharedInstance: Bool { role == .localClient }

    private var sharedInstanceServer: PosixTCPServer?
    private var localInterface: LocalInterface?

    private init(reticulum: Reticulum,
                 config: ReticulumConfig,
                 configDirectory: URL,
                 role: Role,
                 rpc: RPCClient?,
                 sharedInstanceServer: PosixTCPServer?,
                 localInterface: LocalInterface?) {
        self.reticulum = reticulum
        self.config = config
        self.configDirectory = configDirectory
        self.role = role
        self.rpc = rpc
        self.sharedInstanceServer = sharedInstanceServer
        self.localInterface = localInterface
    }

    // MARK: - Path resolution

    /// Resolve the configuration directory the way Python does.
    ///
    /// Python `Reticulum.__init__`:
    /// ```
    /// if configdir != None:                                    use it
    /// elif /etc/reticulum/config exists:                        /etc/reticulum
    /// elif ~/.config/reticulum/config exists:                   ~/.config/reticulum
    /// else:                                                     ~/.reticulum
    /// ```
    public static func resolveConfigDirectory(_ explicit: URL? = nil) -> URL {
        resolveConfigDirectory(explicit,
                               home: homeDirectory(),
                               systemConfigDir: URL(fileURLWithPath: "/etc/reticulum"),
                               fileManager: .default)
    }

    /// The home directory the config search starts from.
    ///
    /// Python reaches `~/.reticulum` through `os.path.expanduser("~")`, which returns
    /// **`$HOME` when it is set** and only falls back to the password database otherwise.
    /// `NSHomeDirectory()` does not: on macOS it always reports the account's real home,
    /// so a Swift utility launched with `HOME` pointed at a sandbox silently read and wrote
    /// the developer's actual `~/.reticulum` — and, finding the real daemon's identity
    /// there, authenticated to the real daemon on 37428 and reported its status. That is
    /// how `tri-test` came to be running "isolated" Swift utilities against a live node;
    /// its Python half was correctly sandboxed the whole time.
    ///
    /// `NSHomeDirectory()` stays as the fallback rather than
    /// `FileManager.homeDirectoryForCurrentUser`, which is macOS-only — this type lives in
    /// the library target and has to keep compiling for iOS, tvOS and watchOS.
    static func homeDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    /// `os.path.expanduser` — expand a leading `~` from `$HOME`.
    ///
    /// The counterpart to ``homeDirectory(environment:)`` for the paths a *user* types, and it
    /// exists for the same reason. `NSString.expandingTildeInPath` ignores `$HOME` on macOS
    /// exactly as `NSHomeDirectory()` does, so `--config ~/scratch` under a relocated `HOME`
    /// resolved into the account's real home while the surrounding code believed it was
    /// sandboxed. Eleven call sites across five utilities used it (`bugs/024`), which is why the
    /// 1.7.0 fix — one resolver, in one place — did not hold: it corrected where the *default*
    /// came from and left every explicit `~` path going somewhere else.
    ///
    /// Semantics, matching CPython's `posixpath.expanduser`:
    /// - `"~"` → `$HOME`, `"~/x"` → `$HOME/x`.
    /// - A trailing slash on `$HOME` is not doubled.
    /// - `~user` is returned **unchanged**. CPython looks it up in the password database;
    ///   nothing in RNS passes one, and silently resolving it to `$HOME` would be worse than
    ///   leaving it for the filesystem to reject.
    /// - Anything not starting with `~` is returned unchanged.
    static func expandTilde(_ path: String,
                            environment: [String: String] = ProcessInfo.processInfo.environment)
    -> String {
        expandTilde(path, home: homeDirectory(environment: environment).path)
    }

    /// ``expandTilde(_:environment:)`` against an explicitly supplied home.
    ///
    /// The core implementation, separate so `rncp` — whose filesystem abstraction already carries
    /// an injected home — reaches the same expansion rather than keeping its own copy. It had
    /// one; the two agreed except on a home with repeated trailing slashes, where CPython's
    /// `rstrip('/')` is what this does.
    static func expandTilde(_ path: String, home: String) -> String {
        guard path.hasPrefix("~") else { return path }
        let rest = String(path.dropFirst())
        if rest.isEmpty { return home }
        // `~user…` — not ours to expand. CPython consults the password database; RNS never does,
        // and resolving it to `$HOME` would be worse than letting the filesystem reject it.
        guard rest.hasPrefix("/") else { return path }
        // CPython: `userhome.rstrip('/') + path[i:]` (`posixpath.expanduser`).
        var base = home
        while base.count > 1, base.hasSuffix("/") { base.removeLast() }
        if base == "/" { return rest }
        return base + rest
    }

    /// The same search order with its two fixed locations injected, so it can be exercised
    /// against a temporary tree instead of the real `/etc` and `$HOME`.
    ///
    /// Python checks `os.path.isdir(dir) and os.path.isfile(dir+"/config")`; testing only for
    /// the `config` file is equivalent, since a file cannot live inside a non-directory.
    public static func resolveConfigDirectory(_ explicit: URL?,
                                              home: URL,
                                              systemConfigDir: URL,
                                              fileManager: FileManager) -> URL {
        if let explicit { return explicit }

        if fileManager.fileExists(atPath: StorageInventory.url(.config, in: systemConfigDir).path) {
            return systemConfigDir
        }

        let xdg = home.appendingPathComponent(".config/reticulum")
        if fileManager.fileExists(atPath: StorageInventory.url(.config, in: xdg).path) { return xdg }

        return home.appendingPathComponent(".reticulum")
    }

    /// `<configdir>/storage`. Python: `Reticulum.storagepath`.
    public static func storagePath(for configDirectory: URL) -> URL {
        StorageInventory.url(.storage, in: configDirectory)
    }

    /// `<configdir>/config`. Python: `Reticulum.configpath`.
    public static func configPath(for configDirectory: URL) -> URL {
        StorageInventory.url(.config, in: configDirectory)
    }

    // MARK: - Attach

    /// Bring up a stack for a command-line utility.
    ///
    /// - Parameters:
    ///   - configDirectory: explicit config directory, or `nil` to resolve as Python does.
    ///   - requireSharedInstance: when true, fail unless an instance is *already* running.
    ///     Python: `RNS.Reticulum(require_shared_instance=True)`, used by `rnstatus` and
    ///     `rnpath`, which only read state that a running daemon owns.
    ///   - logLevel: log verbosity for the stack we bring up.
    ///   - synthesizeInterfaces: whether to bring up the interfaces named in the config
    ///     file. A utility attaching as a local client must not, since the shared instance
    ///     already owns them — this mirrors Python only adding the `LocalClientInterface`.
    public static func attach(configDirectory explicitConfigDirectory: URL? = nil,
                              requireSharedInstance: Bool = false,
                              logLevel: Reticulum.LogLevel = .error,
                              synthesizeInterfaces: Bool = true) throws -> InstanceConnection {

        let configDirectory = resolveConfigDirectory(explicitConfigDirectory)
        let storagePath = storagePath(for: configDirectory)
        let configPath = configPath(for: configDirectory)

        try FileManager.default.createDirectory(at: storagePath, withIntermediateDirectories: true)

        let config: ReticulumConfig
        if let loaded = ReticulumConfig.load(from: configPath) {
            config = loaded
        } else {
            config = ReticulumConfig.parse(ReticulumConfig.defaultConfigText)
        }

        Reticulum.globalLogLevel = logLevel
        let reticulum = Reticulum(configuration: Reticulum.Configuration(
            storagePath: storagePath,
            configPath: configPath,
            shareInstance: config.reticulum.shareInstance,
            logLevel: logLevel
        ))
        try reticulum.start()

        let sharedPort = config.reticulum.sharedInstancePort
        let controlPort = config.reticulum.instanceControlPort

        // Instance sharing disabled → private stack, nothing to attach to.
        // Python: the `else` branch of `if self.share_instance:`.
        guard config.reticulum.shareInstance else {
            if requireSharedInstance {
                reticulum.stop()
                throw InstanceError.noSharedInstance
            }
            if synthesizeInterfaces { try reticulum.synthesizeInterfaces(from: config) }
            return InstanceConnection(reticulum: reticulum, config: config,
                                      configDirectory: configDirectory, role: .standalone,
                                      rpc: nil, sharedInstanceServer: nil, localInterface: nil)
        }

        // Try to become the shared instance by binding its port. Python does exactly this
        // and treats the bind failure as "someone else is already the shared instance".
        let server = PosixTCPServer(name: "Shared Instance", port: sharedPort)
        do {
            reticulum.transport.register(interface: server)
            try server.start()
        } catch {
            // --- Someone else owns the port: attach as a local client. ---
            reticulum.transport.deregister(interface: server)

            let localInterface = LocalInterface(host: "127.0.0.1", port: sharedPort)
            reticulum.transport.register(interface: localInterface)
            do {
                try localInterface.start()
            } catch {
                reticulum.transport.deregister(interface: localInterface)
                reticulum.stop()
                throw InstanceError.couldNotConnect(error)
            }

            // Python disables transport, remote management and probes on a local client,
            // because the shared instance is the one doing all of that.
            reticulum.transport.transportEnabled = false

            // Python: `is_connected_to_shared_instance = True`, which Transport reads back
            // as `Transport.owner.is_connected_to_shared_instance`. Without it a client
            // re-applies work the shared instance has already done: `filterAndRecord` runs
            // the HEADER_2 transport-id filter a second time and drops packets that were
            // forwarded *to us*, `shouldApplyDelta` re-applies the local hops delta, and
            // rnprobe takes the standalone branch so it never reports RSSI/SNR/Link Quality.
            reticulum.transport.isConnectedToSharedInstance = true

            let rpc = try? RPCClient.forInstance(storagePath: storagePath, port: controlPort)
            return InstanceConnection(reticulum: reticulum, config: config,
                                      configDirectory: configDirectory, role: .localClient,
                                      rpc: rpc, sharedInstanceServer: nil,
                                      localInterface: localInterface)
        }

        // --- We became the shared instance. ---
        // Python: "Existing shared instance required, but this instance started as shared
        // instance. Aborting startup." → detach and raise.
        if requireSharedInstance {
            server.stop()
            reticulum.transport.deregister(interface: server)
            reticulum.stop()
            throw InstanceError.noSharedInstance
        }

        try? reticulum.startRPC(port: controlPort)
        if synthesizeInterfaces { try reticulum.synthesizeInterfaces(from: config) }

        return InstanceConnection(reticulum: reticulum, config: config,
                                  configDirectory: configDirectory, role: .sharedInstance,
                                  rpc: nil, sharedInstanceServer: server, localInterface: nil)
    }

    // MARK: - Teardown

    /// Tear down whatever ``attach(configDirectory:requireSharedInstance:logLevel:synthesizeInterfaces:)`` brought up.
    public func stop() {
        localInterface?.stop()
        sharedInstanceServer?.stop()
        reticulum.stop()
    }

    // MARK: - Errors

    public enum InstanceError: Error, CustomStringConvertible {
        /// No instance was already running, and the caller required one.
        /// Python prints "No shared RNS instance available to get status from" and exits 1.
        case noSharedInstance
        /// A shared instance appears to be running but could not be connected to.
        case couldNotConnect(Error)

        public var description: String {
            switch self {
            case .noSharedInstance:
                return "No shared RNS instance available"
            case .couldNotConnect(let underlying):
                return "Local shared instance appears to be running, but it could not be connected: \(underlying)"
            }
        }
    }
}
