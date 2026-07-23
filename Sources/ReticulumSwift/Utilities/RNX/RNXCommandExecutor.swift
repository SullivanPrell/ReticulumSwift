import Foundation

/// The outcome of running one remote command.
///
/// Python reference: the locals of `execute_received_command` — `process`, `stdout`,
/// `stderr` and `process.returncode` (rnx.py:178-241).
public struct RNXExecution: Equatable {

    /// Whether `subprocess.Popen` succeeded. Python sets `result[0] = True` immediately
    /// after the constructor returns and `False` (returning at once) if it raised —
    /// command not found, permission denied, or an **empty argv** (`Popen([])` →
    /// `IndexError`), which is what an empty interactive line produces.
    public var spawned: Bool

    /// `process.returncode`. After `terminate()` + `wait()` this is a negative signal
    /// number on Unix (-15 for SIGTERM); Python passes it straight through.
    public var returnCode: Int?

    /// Captured stdout, or nil for Python's terminate-but-still-running branch
    /// (rnx.py:213), which is the state that tracebacks its response generator.
    public var stdout: Data?

    /// Captured stderr; same nil semantics as ``stdout``.
    public var stderr: Data?

    /// Whether the deadline fired and the child was killed. Python has no such flag —
    /// it re-derives the condition from the wall clock at rnx.py:218, and its `timed_out`
    /// local is dead code (rnx.py:188, 243). Carrying it explicitly makes the
    /// concluded-timestamp rule testable without a clock.
    public var timedOut: Bool

    public init(spawned: Bool,
                returnCode: Int? = nil,
                stdout: Data? = nil,
                stderr: Data? = nil,
                timedOut: Bool = false) {
        self.spawned = spawned
        self.returnCode = returnCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    /// Python: the `except` at rnx.py:182-184 — `result[0] = False; return result`.
    public static let spawnFailed = RNXExecution(spawned: false)
}

/// Runs a command on behalf of an ``RNXListener``.
///
/// This is the platform seam: `Foundation.Process` exists only on macOS among the four
/// platforms ReticulumSwift targets, so the library never spawns anything itself. The
/// `rnx` executable supplies a `Process`-backed implementation; XCTest supplies a mock.
///
/// - Important: `execute` may block for the whole `timeout` — 15 seconds by default.
///   ReticulumSwift dispatches request handlers **inline on the link receive thread**
///   (`Link.receive` → `Link.dispatchRequest`), where Python spawns a daemon thread per
///   REQUEST packet (Link.py:985-987). Never call this from a handler; ``RNXListener``
///   hands it to a background queue and delivers the response itself.
public protocol RNXCommandExecutor: AnyObject {
    func execute(command: String, stdin: Data?, timeout: TimeInterval?) -> RNXExecution
}
