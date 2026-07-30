import Foundation
import ReticulumSwift

#if os(macOS)

/// The only `Foundation.Process` user in the rnx port — macOS-only, because `Process` does
/// not exist on iOS, tvOS or watchOS.
///
/// Python reference: `subprocess.Popen(shlex.split(command), stdin=PIPE, stdout=PIPE,
/// stderr=PIPE)` plus the poll loop at rnx.py:178-219.
///
/// **No shell is involved.** Pipes, redirects, globs, `&&` and `$VAR` all arrive as literal
/// argv elements, exactly as in Python. Routing through `/bin/sh` would be a wire-visible
/// behaviour change, so it is deliberately not done.
final class ProcessCommandExecutor: RNXCommandExecutor {

    /// Poll cadence while waiting for the child.
    ///
    /// Python calls `communicate(timeout=1)` in a loop, which returns the instant the
    /// child exits and otherwise re-checks the deadline about once a second. Polling more
    /// often here makes the kill deadline tighter than Python's (up to a second late)
    /// while leaving fast commands equally responsive.
    private static let pollInterval: TimeInterval = 0.05

    /// Collector for one pipe. A background reader is required: a child that writes more
    /// than the 64 KB pipe buffer would deadlock if we only read after `waitUntilExit()`.
    private final class OutputCollector {
        private let lock = NSLock()
        private var buffer = Data()

        func append(_ data: Data) { lock.lock(); buffer.append(data); lock.unlock() }
        var value: Data { lock.lock(); defer { lock.unlock() }; return buffer }
    }

    func execute(command: String, stdin: Data?, timeout: TimeInterval?) -> RNXExecution {
        // Python: shlex.split(command). A ValueError here (unterminated quote, trailing
        // backslash) propagates out of Popen's argument evaluation, so the response
        // generator's `except` fires and executed stays False.
        guard let argv = try? RNXShellWords.split(command), let program = argv.first else {
            // Python: shlex.split("") == [] → Popen([]) → IndexError → executed = False.
            // A naive Process with an empty argv would trap instead.
            return .spawnFailed
        }
        guard let executableURL = ProcessCommandExecutor.resolve(program) else {
            // Python: FileNotFoundError / PermissionError → executed = False.
            return .spawnFailed
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = Array(argv.dropFirst())

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .spawnFailed
        }

        let outCollector = OutputCollector()
        let errCollector = OutputCollector()
        let readers = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: readers) {
            outCollector.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        }
        DispatchQueue.global(qos: .userInitiated).async(group: readers) {
            errCollector.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        }

        // Python: `process.stdin.write(stdin)` with no flush and no close — communicate()
        // is what actually closes it and delivers EOF. Closing here is the same net effect.
        if let stdin, !stdin.isEmpty {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: stdin)
        }
        try? stdinPipe.fileHandleForWriting.close()

        let startedAt = Date()
        var timedOut = false
        while process.isRunning {
            if let timeout, Date().timeIntervalSince(startedAt) > timeout {
                // Python: rnx.py:206-216 — log, terminate(), wait(), harvest.
                Reticulum.log("Command [\(command)] timed out and is being killed...")
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: ProcessCommandExecutor.pollInterval)
        }
        process.waitUntilExit()
        readers.wait()

        // Python's `process.returncode` is negative for a signal death (-15 for SIGTERM),
        // and rnx passes it straight through to the client's -m exit code.
        let returnCode: Int = process.terminationReason == .uncaughtSignal
            ? -Int(process.terminationStatus)
            : Int(process.terminationStatus)

        return RNXExecution(spawned: true,
                            returnCode: returnCode,
                            stdout: outCollector.value,
                            stderr: errCollector.value,
                            timedOut: timedOut)
    }

    /// `execvp`-style lookup: an argv[0] containing a slash is used as-is, otherwise `PATH`
    /// is searched left to right for an executable file. `Process` requires a concrete
    /// path, where Python's `Popen` gets the search for free.
    private static func resolve(_ program: String) -> URL? {
        let fileManager = FileManager.default
        if program.contains("/") {
            let url = DaemonBootstrap.expandTildeURL(program)
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(program)
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

#endif
