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
public final class I2PDaemon: I2PDaemonProtocol {

    // MARK: - Properties

    /// SAM bridge TCP port.  Default matches i2pd's own default (sam.port=7656).
    public let samPort: Int

    /// `true` after `start()` returns and before `stop()` is called.
    public private(set) var isRunning: Bool = false

    // MARK: - Init

    /// - Parameter samPort: SAM bridge port for i2pd to listen on.
    ///   Pass `--sam.port=N` to `C_InitI2P` if not the default.
    public init(samPort: Int = 7656) {
        self.samPort = samPort
    }

    // MARK: - Lifecycle

    public func start(dataDirectory: URL) throws {
        guard !isRunning else { return }

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
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        C_StopClientServices()
        C_StopI2P()
        C_TerminateI2P()
        isRunning = false
    }

    deinit { stop() }
}
#endif // os(macOS) || os(iOS)
