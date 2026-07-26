import Foundation

// MARK: - I2PDaemon error

public enum I2PDaemonError: Error {
    case startFailed(String)
}

// MARK: - I2PDaemonProtocol

/// Abstracts the lifecycle of an i2pd daemon instance.
/// Python: `I2PController` manages the i2plib event loop + SAM tunnels.
/// Swift: this protocol lets production code use the embedded `I2PDaemon`
/// while tests inject a `MockI2PDaemon`.
public protocol I2PDaemonProtocol: AnyObject {
    /// TCP port on which this daemon's SAM bridge is listening.
    var samPort: Int { get }

    /// Start the daemon, writing its data files under `dataDirectory`.
    func start(dataDirectory: URL) throws

    /// Stop the daemon cleanly.
    func stop()
}

// MARK: - Process-global i2pd phase
//
// Deliberately outside the CI2PD-gated section below so the rule it encodes can
// be tested on any platform, without a live i2pd.

/// Which state the *process-global* i2pd router is in.
///
/// i2pd's router is not per-instance: `C_InitI2P` / `C_StartI2P` initialise
/// dylib-scope singletons and `C_TerminateI2P` tears down the crypto subsystem
/// for the whole process. Two rules follow, and `I2PDaemon` is the only place
/// that can enforce them:
///
///   1. At most one daemon owns the globals at a time — a second `C_InitI2P`
///      while one is running would silently reconfigure the running router.
///   2. Once `C_TerminateI2P` has run there is no supported way back; i2pd has
///      no re-init path, so a second `C_InitI2P` is undefined behaviour.
///
/// A caller that needs I2P again after a stop has to relaunch the process.
enum I2PDaemonPhase {
    case idle
    case running
    case terminated

    /// Throws if a daemon may not claim the globals from this phase.
    func validateStart() throws {
        switch self {
        case .idle:
            return
        case .running:
            throw I2PDaemonError.startFailed(
                "an i2pd daemon is already running in this process; i2pd's router state is process-global, so only one can run at a time")
        case .terminated:
            throw I2PDaemonError.startFailed(
                "i2pd has already been shut down in this process and cannot be re-initialised; relaunch to use I2P again")
        }
    }
}

// MARK: - I2PDaemon (embedded i2pd via CI2PD xcframework)
//
// Currently ships a macOS arm64 slice only.
// Run build_ci2pd_ios.sh to add iOS arm64 + iOS-Simulator arm64 slices;
// that script also patches the #if guard below and Package.swift to enable iOS.

#if os(macOS) || os(iOS)
import CI2PD

/// Embedded i2pd daemon.
/// Wraps the lifecycle C calls exposed by `capi.h` / `capi_client.h`.
///
/// Startup sequence:
///  1. `C_InitI2P` — parse config, set up file-system paths
///  2. `C_StartI2P` — start NetDB, Transports, Tunnels, RouterContext
///  3. `C_StartClientServices` — start SAM bridge (port `samPort`), address book
///
/// Shutdown sequence:
///  4. `C_StopClientServices` — stop SAM, clean up tunnels
///  5. `C_StopI2P` — stop routing
///  6. `C_TerminateI2P` — release crypto / global state
///
/// The shutdown sequence is not optional. i2pd runs a dozen threads of its own
/// (Tunnels, NetDB, Transports, SSU2, NTCP2, …) that live on *dylib-scope C++
/// singletons*. If the process reaches `exit()` with those threads still
/// running, the C++ runtime destroys the singletons out from under them and one
/// of the workers segfaults on freed state — reliably `Tunnels::Run` reading a
/// half-destroyed `i2p::transport::transports`. `stop()` is what prevents that,
/// and `atexit` (below) is the net for every path that forgets to call it.
public final class I2PDaemon: I2PDaemonProtocol {

    // MARK: - Process-global i2pd state
    //
    // See `I2PDaemonPhase` for the rules this enforces. RetiOS surfaces the
    // relaunch requirement in Interfaces ▸ I2P Network.

    private static let globalLock = NSLock()
    private static var globalPhase: I2PDaemonPhase = .idle
    /// The daemon that currently owns the globals. Weak: ownership of the
    /// *object* stays with whoever created it, and `deinit` still stops i2pd.
    private static weak var activeDaemon: I2PDaemon?

    /// Stops i2pd during `exit()`, before the C++ runtime destroys its globals.
    ///
    /// Registered on first `start()` rather than at load time, deliberately:
    /// `atexit`/`__cxa_atexit` handlers run in reverse registration order, and
    /// i2pd's singletons register their destructors during image
    /// initialisation — so anything we register after `main` is guaranteed to
    /// run *before* them. Registering earlier would invert that and defeat the
    /// whole point.
    ///
    /// This is a backstop, not the shutdown path: it only fires for exits that
    /// never called `stop()`, and it runs on the exiting thread with the rest
    /// of the app already quiescing.
    private static let atExitHook: Void = {
        atexit {
            I2PDaemon.stopForProcessExit()
        }
    }()

    private static func stopForProcessExit() {
        globalLock.lock()
        defer { globalLock.unlock() }
        guard globalPhase == .running else { return }
        performGlobalStop()
    }

    /// The C shutdown sequence. Caller must hold `globalLock` and have checked
    /// `globalPhase == .running`.
    private static func performGlobalStop() {
        C_StopClientServices()
        C_StopI2P()
        C_TerminateI2P()
        globalPhase = .terminated
        activeDaemon?.isRunning = false
        activeDaemon = nil
    }

    // MARK: - Properties

    /// SAM bridge TCP port.  Default matches i2pd's own default (sam.port=7656).
    public let samPort: Int

    /// `true` after `start()` returns and before `stop()` is called.
    public private(set) var isRunning: Bool = false

    /// `true` once i2pd has been shut down in this process, after which no
    /// daemon can be started again until relaunch. Lets callers explain the
    /// restriction up front instead of surfacing a failed `start()`.
    public static var isTerminatedForProcess: Bool {
        globalLock.lock()
        defer { globalLock.unlock() }
        return globalPhase == .terminated
    }

    // MARK: - Init

    /// - Parameter samPort: SAM bridge port for i2pd to listen on.
    ///   Pass `--sam.port=N` to `C_InitI2P` if not the default.
    public init(samPort: Int = 7656) {
        self.samPort = samPort
    }

    // MARK: - Lifecycle

    public func start(dataDirectory: URL) throws {
        guard !isRunning else { return }

        Self.globalLock.lock()
        do {
            try Self.globalPhase.validateStart()
        } catch {
            Self.globalLock.unlock()
            throw error
        }
        // Claim the globals *before* touching them, and arm the exit net, so a
        // start that dies partway through is still torn down at exit.
        _ = Self.atExitHook
        Self.globalPhase = .running
        Self.activeDaemon = self
        isRunning = true
        Self.globalLock.unlock()

        // Build argv for i2pd.  We enable SAM on the configured port.
        // C_InitI2P copies what it needs; we free the strings afterwards.
        let args: [String] = [
            "--datadir=\(dataDirectory.path)",
            "--sam.enabled=true",
            "--sam.port=\(samPort)",
            "--loglevel=none",
        ]
        let cStrings = args.map { strdup($0) }
        var argv = cStrings.map { UnsafeMutablePointer<CChar>(mutating: $0) }
        C_InitI2P(Int32(argv.count), &argv, "reticulum")
        cStrings.forEach { free($0) }

        C_StartI2P()
        C_StartClientServices()
    }

    public func stop() {
        Self.globalLock.lock()
        defer { Self.globalLock.unlock() }
        // `isRunning` *is* the ownership test: `start()` refuses to run while
        // another daemon holds the globals, so at most one instance can have it
        // set while the phase is `.running`. (Identity against `activeDaemon`
        // would be wrong here — it is weak, and weak loads already read nil by
        // the time `deinit` calls this.)
        guard isRunning else { return }
        isRunning = false
        guard Self.globalPhase == .running else { return }
        Self.performGlobalStop()
    }

    /// Stops i2pd if this instance still owns it. A last resort — the owner
    /// (`I2PInterface`) calls `stop()` explicitly and the `atexit` hook covers
    /// process exit — but dropping the last reference to a running daemon has
    /// always meant "shut i2pd down", and silently leaking the router threads
    /// instead would just recreate the exit crash from a different direction.
    deinit { stop() }
}
#endif // os(macOS) || os(iOS)
