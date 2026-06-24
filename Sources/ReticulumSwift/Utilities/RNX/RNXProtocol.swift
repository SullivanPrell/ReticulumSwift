import Foundation

/// Wire types for the rnx remote-execution protocol.
/// Python reference: RNS/Utilities/rnx.py
///
/// rnx uses RNS Link.request / Link.respond to run shell commands on a
/// remote host.  The request is a 5-element msgpack array; the response
/// is an 8-element msgpack array.

// MARK: - RNXRequest

/// Encodes a remote execution request.
/// Python: request_data = [command, timeout, stdoutl, stderrl, stdin]
public struct RNXRequest {

    /// Shell command string to run on the remote host.
    public var command: String

    /// Optional execution timeout in seconds.
    public var timeout: TimeInterval? = nil

    /// Maximum bytes captured from stdout (nil = unlimited).
    public var stdoutLimit: Int? = nil

    /// Maximum bytes captured from stderr (nil = unlimited).
    public var stderrLimit: Int? = nil

    /// Optional data fed to the command's stdin.
    public var stdin: Data? = nil

    public init(command: String) {
        self.command = command
    }

    /// Pack to msgpack for transmission via `link.request(data:)`.
    /// Python: request_data[0] = command.encode("utf-8") — bytes, not a string.
    public func pack() throws -> Data {
        let arr: [MsgPack.Value] = [
            .bytes(Data(command.utf8)),                         // [0] command as bytes
            timeout.map { .double($0) } ?? .nil,               // [1] timeout
            stdoutLimit.map { .int(Int64($0)) } ?? .nil,       // [2] stdout size limit
            stderrLimit.map { .int(Int64($0)) } ?? .nil,       // [3] stderr size limit
            stdin.map { .bytes($0) } ?? .nil,                  // [4] stdin data
        ]
        return MsgPack.encode(.array(arr))
    }
}

// MARK: - RNXResult

/// Decoded result of a remote execution request.
/// Python response indices:
///   [0] executed (bool)
///   [1] return_code (int or None)
///   [2] stdout (bytes or None)
///   [3] stderr (bytes or None)
///   [4] total stdout length (int or None)
///   [5] total stderr length (int or None)
///   [6] started_at (float)
///   [7] concluded_at (float or None)
public struct RNXResult {

    /// True if the command was actually started on the remote end.
    public var executed: Bool

    /// Process exit code (nil if not executed or not yet available).
    public var returnCode: Int?

    /// Captured stdout bytes (may be truncated by stdoutLimit).
    public var stdout: Data?

    /// Captured stderr bytes (may be truncated by stderrLimit).
    public var stderr: Data?

    /// Total length of stdout produced (before any truncation).
    public var totalStdoutLength: Int?

    /// Total length of stderr produced (before any truncation).
    public var totalStderrLength: Int?

    /// Unix timestamp when the command started (seconds since epoch).
    public var startedAt: TimeInterval?

    /// Unix timestamp when the command concluded (nil if still running).
    public var concludedAt: TimeInterval?

    /// Decode an RNXResult from a packed msgpack 8-element array.
    public init(unpackFrom data: Data) throws {
        guard case .array(let arr) = try MsgPack.decode(data), arr.count == 8 else {
            throw RNXError.malformedResponse
        }

        // [0] executed
        guard case .bool(let exec) = arr[0] else { throw RNXError.malformedResponse }
        executed = exec

        // [1] return_code
        returnCode = arr[1].asInt

        // [2] stdout
        if case .bytes(let b) = arr[2] { stdout = b } else { stdout = nil }

        // [3] stderr
        if case .bytes(let b) = arr[3] { stderr = b } else { stderr = nil }

        // [4] total stdout length
        totalStdoutLength = arr[4].asInt

        // [5] total stderr length
        totalStderrLength = arr[5].asInt

        // [6] started_at
        if case .double(let t) = arr[6] { startedAt = t } else { startedAt = nil }

        // [7] concluded_at
        if case .double(let t) = arr[7] { concludedAt = t } else { concludedAt = nil }
    }
}

// MARK: - RNXError

public enum RNXError: Error {
    case malformedResponse
    case executionDenied
}
