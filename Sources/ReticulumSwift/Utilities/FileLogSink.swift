import Foundation

/// Python's `RNS.log()` destination machinery: the exact log-line format, the `LOG_FILE`
/// append-then-rotate destination, and the permanent fall-back-to-console latch.
///
/// Python reference: `RNS/__init__.py:96` (`logging_lock`), `98-109` (`loglevelname`),
/// `126-161` (`log`, including the file write, the 5 MiB rotation and the failure fallback).
///
/// Two things about the Swift side are worth knowing before using this type:
///
/// 1. ``Reticulum/logHandler`` receives the **raw, unformatted** message and level
///    (`Reticulum.swift`, `log(_:level:)`), unlike Python's `LOG_CALLBACK`, which receives the
///    finished `logstring`. Installing a handler also short-circuits the built-in formatter
///    entirely. So this sink owns both the formatting and the fallback.
/// 2. Python serialises the whole destination dispatch under a single global lock, and its
///    failure path re-enters `log()` three times. A non-recursive lock held across the
///    dispatch would deadlock there, so ``FileLogSink`` uses an `NSRecursiveLock`.
public final class FileLogSink {

    // MARK: - Formatting

    /// Build the exact line Python's `RNS.log()` emits.
    ///
    /// Python: `logstring = ("["+timestamp_str(time.time())+"] " if logtimestamps else "")`
    /// `+ loglevelname(level) + " " + msg` (`RNS/__init__.py:131`).
    ///
    /// `loglevelname` returns a **10-character padded** string (`"[Notice]  "`), and `log()`
    /// then appends one more space — so most levels are followed by more than one space.
    /// The resulting gap after the bracketed level name is: 1 for `[Critical]`, 2 for
    /// `[Warning]`/`[Verbose]`/`[Pathing]`, 3 for `[Notice]`, 4 for `[Error]`/`[Debug]`/
    /// `[Extra]`, 5 for `[Info]`.
    ///
    /// - Parameters:
    ///   - message: the raw message.
    ///   - level: severity; supplies the padded level name.
    ///   - timestamps: Python's `RNS.logtimestamps`.
    ///   - compact: Python's `RNS.compact_log_fmt` — drops the level name, keeps the timestamp.
    ///   - precise: Python's `pt=True` — millisecond timestamps, and the timestamp is emitted
    ///     even when `timestamps` is false.
    ///   - date: the instant to format. Python always uses "now"; injectable here for tests.
    public static func formatLogLine(_ message: String,
                                     level: Reticulum.LogLevel,
                                     timestamps: Bool = Reticulum.logTimestamps,
                                     compact: Bool = Reticulum.compactLogFmt,
                                     precise: Bool = false,
                                     at date: Date = Date()) -> String {
        if precise {
            // Python: `"["+precise_timestamp_str(time.time())+"] "+loglevelname(level)+" "+msg`
            // — unconditional timestamp, and `precise_timestamp_str` ignores its argument and
            // formats `datetime.now()`, a quirk `RNSUtilities.preciseTimestampStr()` inherits.
            return "[\(preciseTimestampStr(date))] \(Reticulum.loglevelname(level)) \(message)"
        }

        let stamp = timestamps ? "[\(RNSUtilities.timestampStr(date.timeIntervalSince1970))] " : ""
        if compact {
            // Python: the compact branch drops the level name entirely.
            return stamp + message
        }
        return stamp + Reticulum.loglevelname(level) + " " + message
    }

    /// `HH:mm:ss.SSS` for an injectable date. `RNSUtilities.preciseTimestampStr()` always uses
    /// "now" (matching Python's bug); tests need a fixed instant.
    private static func preciseTimestampStr(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    // MARK: - Stdout destination

    /// Install a `Reticulum.logHandler` that writes Python-formatted lines to stdout.
    ///
    /// Python: `RNS.LOG_STDOUT` (0x91), the default destination and the one `rnsd` uses when
    /// `-s/--service` is absent (`rnsd.py:47`). Kept out of the library's own default sink so
    /// embedders such as RetiOS, which install their own handler, are unaffected.
    public static func installStdoutHandler(writer: @escaping (String) -> Void = FileLogSink.defaultConsoleWriter) {
        Reticulum.logHandler = { message, level in
            writer(formatLogLine(message, level: level))
        }
    }

    /// `print` + `fflush`, so a daemon's output is not lost when stdout is a pipe.
    public static let defaultConsoleWriter: (String) -> Void = { line in
        Swift.print(line)
        fflush(stdout)
    }

    // MARK: - File destination

    /// `<configdir>/logfile`. Python: `RNS.logfile`.
    public let fileURL: URL

    /// `<configdir>/logfile.1` — the single generation Python keeps.
    public let rotatedFileURL: URL

    /// Python: `RNS.LOG_MAXSIZE = 5*1024*1024`.
    public let maxSize: Int

    /// Set permanently after any write failure. Python: the module-global
    /// `_always_override_destination` latch (`RNS/__init__.py:93`, set at `152`).
    public private(set) var fellBackToConsole: Bool = false

    /// Where fallback output goes. Injectable so tests can capture it.
    public var consoleWriter: (String) -> Void

    private let fileManager: FileManager
    /// Python holds `logging_lock` across the whole dispatch, and its failure path re-enters
    /// `log()` three times — recursive is mandatory, not an optimisation.
    private let lock = NSRecursiveLock()

    public init(fileURL: URL,
                maxSize: Int = RNSDApp.logMaxSize,
                fileManager: FileManager = .default,
                consoleWriter: @escaping (String) -> Void = FileLogSink.defaultConsoleWriter) {
        self.fileURL = fileURL
        self.rotatedFileURL = URL(fileURLWithPath: fileURL.path + RNSDApp.rotatedLogSuffix)
        self.maxSize = maxSize
        self.fileManager = fileManager
        self.consoleWriter = consoleWriter
    }

    /// The `(message, level)` closure to hand to ``Reticulum/logHandler``.
    public var handler: (String, Reticulum.LogLevel) -> Void {
        { [weak self] message, level in
            self?.emit(message, level: level)
        }
    }

    /// Route every `Reticulum.log` call through this sink.
    ///
    /// Remember the handler receives the *raw* message, so formatting happens here.
    public func install() {
        Reticulum.logHandler = handler
    }

    /// Format `message` and send it to the current destination, applying Python's fallback.
    ///
    /// Python: the `elif logdest == LOG_FILE and logfile != None` branch and its `except`
    /// body (`RNS/__init__.py:143-158`).
    public func emit(_ message: String, level: Reticulum.LogLevel) {
        lock.lock()
        defer { lock.unlock() }

        let line = FileLogSink.formatLogLine(message, level: level)

        // Python: `if logdest == LOG_STDOUT or _always_override_destination` comes first,
        // so once the latch is set every message goes to the console.
        if fellBackToConsole {
            consoleWriter(line)
            return
        }

        do {
            try appendAndRotate(line)
        } catch {
            // Python sets the latch *before* logging, so the three follow-up messages —
            // and everything after them — take the console branch.
            fellBackToConsole = true
            emit("Exception occurred while writing log message to log file: \(error)", level: .critical)
            emit("Dumping future log events to console!", level: .critical)
            emit(message, level: level)
        }
    }

    /// Append one already-formatted line, then rotate if the file has grown past `maxSize`.
    ///
    /// Python: `with open(logfile,"a") as file: file.write(logstring+"\n")`, then
    /// `if os.path.getsize(logfile) > LOG_MAXSIZE:` unlink `<logfile>.1` and rename.
    /// The size check happens **after** the write, so the live file may exceed the limit by
    /// one line before it rotates — reproduced deliberately.
    public func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if fellBackToConsole {
            consoleWriter(line)
            return
        }
        do {
            try appendAndRotate(line)
        } catch {
            fellBackToConsole = true
            emit("Exception occurred while writing log message to log file: \(error)", level: .critical)
            emit("Dumping future log events to console!", level: .critical)
            consoleWriter(line)
        }
    }

    private func appendAndRotate(_ line: String) throws {
        let payload = Data((line + "\n").utf8)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            guard fileManager.createFile(atPath: fileURL.path, contents: payload) else {
                throw SinkError.couldNotOpen(fileURL.path)
            }
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > maxSize else { return }

        // Python keeps exactly one generation: unlink `<logfile>.1`, then rename.
        if fileManager.fileExists(atPath: rotatedFileURL.path) {
            try fileManager.removeItem(at: rotatedFileURL)
        }
        try fileManager.moveItem(at: fileURL, to: rotatedFileURL)
    }

    public enum SinkError: Error, CustomStringConvertible {
        case couldNotOpen(String)

        public var description: String {
            switch self {
            case .couldNotOpen(let path): return "could not open log file at \(path)"
            }
        }
    }
}
