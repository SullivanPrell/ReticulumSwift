import XCTest
@testable import ReticulumSwift

/// The `RNS.log()` line format and the `LOG_FILE` destination.
///
/// Python reference: `RNS/__init__.py` — `loglevelname` (98-109), `log` (126-161) including
/// the append, the 5 MiB single-generation rotation, the `logging_lock` serialisation and the
/// permanent fall-back-to-console latch.
final class FileLogSinkTests: XCTestCase {

    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLogSinkTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private var logFile: URL { temporaryDirectory.appendingPathComponent("logfile") }
    private var rotatedFile: URL { temporaryDirectory.appendingPathComponent("logfile.1") }

    private func contents(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Line format

    /// A fixed instant so the timestamp is deterministic. Formatted in the *local* zone,
    /// exactly as Python's `time.localtime` + `strftime` does.
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private var fixedStamp: String { RNSUtilities.timestampStr(1_700_000_000) }

    func testFormatLogLineMatchesPython() {
        // Python: logstring = "[<ts>] " + loglevelname(level) + " " + msg, and
        // loglevelname(LOG_NOTICE) is the 10-char padded "[Notice]  " — so THREE spaces.
        let line = FileLogSink.formatLogLine("hello", level: .notice, timestamps: true, at: fixedDate)
        XCTAssertEqual(line, "[\(fixedStamp)] [Notice]   hello")
        XCTAssertTrue(line.contains("[Notice]   hello"))
    }

    func testFormatLogLineWithoutTimestamps() {
        // Python: `("["+timestamp_str(...)+"] " if logtimestamps else "")`.
        XCTAssertEqual(FileLogSink.formatLogLine("hello", level: .notice, timestamps: false, at: fixedDate),
                       "[Notice]   hello")
    }

    func testFormatLogLineCompact() {
        // Python: compact_log_fmt drops the level name but keeps the timestamp.
        XCTAssertEqual(FileLogSink.formatLogLine("hello", level: .notice, timestamps: true,
                                                 compact: true, at: fixedDate),
                       "[\(fixedStamp)] hello")
        XCTAssertEqual(FileLogSink.formatLogLine("hello", level: .notice, timestamps: false,
                                                 compact: true, at: fixedDate),
                       "hello")
    }

    func testFormatLogLinePrecise() {
        // Python: the `pt=True` branch always emits a timestamp, even with logtimestamps off,
        // formatted "%H:%M:%S.%f" trimmed to three fractional digits.
        let line = FileLogSink.formatLogLine("hello", level: .error, timestamps: false,
                                             precise: true, at: fixedDate)
        XCTAssertTrue(line.hasSuffix("] [Error]    hello"), line)
        let stamp = String(line.dropFirst().prefix(while: { $0 != "]" }))
        XCTAssertEqual(stamp.count, 12, "HH:mm:ss.SSS is 12 characters, got \(stamp)")
    }

    func testFormatLogLineForEveryLevel() {
        // Python's loglevelname table, padded to 10 characters, plus log()'s extra space.
        let expected: [(Reticulum.LogLevel, String, Int)] = [
            (.critical, "[Critical]", 1),
            (.error,    "[Error]   ", 4),
            (.warning,  "[Warning] ", 2),
            (.notice,   "[Notice]  ", 3),
            (.info,     "[Info]    ", 5),
            (.verbose,  "[Verbose] ", 2),
            (.debug,    "[Debug]   ", 4),
            (.pathing,  "[Pathing] ", 2),
            (.extreme,  "[Extra]   ", 4),
        ]
        for (level, name, gap) in expected {
            XCTAssertEqual(Reticulum.loglevelname(level), name)
            let line = FileLogSink.formatLogLine("msg", level: level, timestamps: false, at: fixedDate)
            XCTAssertEqual(line, name + " msg")
            // Spaces between the closing ']' of the level name and the message.
            let afterBracket = line.drop(while: { $0 != "]" }).dropFirst()
            XCTAssertEqual(afterBracket.prefix(while: { $0 == " " }).count, gap,
                           "wrong gap for \(name)")
        }
    }

    func testLoglevelnameForNoneDivergence() {
        // DIVERGENCE, pinned so it cannot regress silently: Python's loglevelname falls
        // through to the unpadded 7-char "Unknown" for anything unmatched, including
        // LOG_NONE (-1). This port returns a padded "[None]    " instead, which keeps
        // column alignment for a level that is never actually emitted.
        XCTAssertEqual(Reticulum.loglevelname(Reticulum.LogLevel.none), "[None]    ")
    }

    // MARK: - File destination

    func testWriteAppendsFormattedLines() {
        let sink = FileLogSink(fileURL: logFile)
        sink.write("first")
        sink.write("second")

        XCTAssertEqual(contents(of: logFile), "first\nsecond\n")
        XCTAssertFalse(sink.fellBackToConsole)
    }

    func testEmitFormatsThroughTheSink() {
        // Reticulum.logHandler receives the RAW message, unlike Python's LOG_CALLBACK which
        // gets the finished logstring — so the sink has to format.
        let sink = FileLogSink(fileURL: logFile)
        sink.emit("hello", level: .notice)
        XCTAssertTrue(contents(of: logFile).hasSuffix("[Notice]   hello\n"), contents(of: logFile))
    }

    func testRotationAtMaxSize() {
        let sink = FileLogSink(fileURL: logFile, maxSize: 64)
        // 5 lines of 10 bytes each ("0123456789\n" is 11) crosses 64 on the sixth.
        for index in 0..<6 { sink.write(String(repeating: "\(index)", count: 10)) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: rotatedFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logFile.path),
                       "Python renames the live file away; a new one is created on the next write")
        XCTAssertTrue(contents(of: rotatedFile).hasPrefix("0000000000\n"))
    }

    func testSizeCheckIsAfterWrite() {
        // Python calls os.path.getsize AFTER writing, so an oversized line lands in full and
        // only then rotates — the rotated file holds the whole line.
        let sink = FileLogSink(fileURL: logFile, maxSize: 10)
        let long = String(repeating: "x", count: 50)
        sink.write(long)

        XCTAssertFalse(FileManager.default.fileExists(atPath: logFile.path))
        XCTAssertEqual(contents(of: rotatedFile), long + "\n")
    }

    func testRotationKeepsOnlyOneGeneration() {
        let sink = FileLogSink(fileURL: logFile, maxSize: 10)
        sink.write("generation-one")
        sink.write("generation-two")

        // Python: `if os.path.isfile(prevfile): os.unlink(prevfile)` — no .2 ever appears.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: temporaryDirectory.appendingPathComponent("logfile.1.1").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: temporaryDirectory.appendingPathComponent("logfile.2").path))
        XCTAssertEqual(contents(of: rotatedFile), "generation-two\n")
    }

    // MARK: - Failure fallback

    /// A log path whose parent is a regular file, so every open fails.
    private func unwritableLogFile() throws -> URL {
        let blocker = temporaryDirectory.appendingPathComponent("blocker")
        try "not a directory".write(to: blocker, atomically: true, encoding: .utf8)
        return blocker.appendingPathComponent("logfile")
    }

    func testFallbackToConsoleOnWriteFailure() throws {
        var captured: [String] = []
        let sink = FileLogSink(fileURL: try unwritableLogFile(),
                               consoleWriter: { captured.append($0) })
        sink.emit("original message", level: .notice)

        XCTAssertTrue(sink.fellBackToConsole)
        XCTAssertEqual(captured.count, 3)
        // Python emits the three lines in exactly this order (RNS/__init__.py:152-155).
        XCTAssertTrue(captured[0].contains("Exception occurred while writing log message to log file"),
                      captured[0])
        XCTAssertTrue(captured[1].contains("Dumping future log events to console!"), captured[1])
        XCTAssertTrue(captured[2].contains("original message"), captured[2])
        XCTAssertTrue(captured[2].contains("[Notice]"), "re-logged at its ORIGINAL level")
        XCTAssertTrue(captured[0].contains("[Critical]"), "the two notices are LOG_CRITICAL")
    }

    func testFallbackDoesNotDeadlock() throws {
        // Python's failure path re-enters log() three times while the dispatch lock is
        // conceptually held; a non-recursive lock here would hang instead of failing.
        let expectation = XCTestExpectation(description: "failing write returns")
        let sink = FileLogSink(fileURL: try unwritableLogFile(), consoleWriter: { _ in })
        DispatchQueue.global().async {
            sink.emit("boom", level: .error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }

    func testFallbackIsPermanent() throws {
        // Python's `_always_override_destination` is a process-global latch that is never
        // cleared, so later messages go to the console even if the file becomes writable.
        var captured: [String] = []
        let sink = FileLogSink(fileURL: try unwritableLogFile(),
                               consoleWriter: { captured.append($0) })
        sink.emit("first", level: .notice)
        captured.removeAll()

        sink.emit("second", level: .notice)
        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(captured[0].contains("second"))
    }

    func testConcurrentWritesDoNotInterleave() {
        // Python serialises the whole destination dispatch under a module-global
        // `logging_lock` (RNS/__init__.py:96, 136); without an equivalent, concurrent
        // appends can tear.
        let sink = FileLogSink(fileURL: logFile)
        let group = DispatchGroup()
        for queueIndex in 0..<8 {
            let queue = DispatchQueue(label: "sink-\(queueIndex)")
            for lineIndex in 0..<25 {
                group.enter()
                queue.async {
                    sink.write("q\(queueIndex)-l\(lineIndex)-\(String(repeating: "p", count: 40))")
                    group.leave()
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 20), .success)

        let lines = contents(of: logFile).split(separator: "\n", omittingEmptySubsequences: false)
            .dropLast()     // trailing newline
        XCTAssertEqual(lines.count, 200)
        for line in lines {
            XCTAssertTrue(line.hasPrefix("q"), "torn line: \(line)")
            XCTAssertEqual(line.reversed().prefix(while: { $0 == "p" }).count, 40,
                           "torn line: \(line)")
        }
    }

    // MARK: - Handler installation

    func testInstallRoutesReticulumLogThroughTheSink() {
        let savedHandler = Reticulum.logHandler
        let savedLevel = Reticulum.globalLogLevel
        defer {
            Reticulum.logHandler = savedHandler
            Reticulum.globalLogLevel = savedLevel
        }

        let sink = FileLogSink(fileURL: logFile)
        sink.install()
        Reticulum.globalLogLevel = .info
        Reticulum.log("routed", level: .notice)
        // Below the threshold: Reticulum.log returns before reaching the handler.
        Reticulum.log("filtered", level: .debug)

        XCTAssertTrue(contents(of: logFile).contains("routed"))
        XCTAssertFalse(contents(of: logFile).contains("filtered"))
    }

    func testInstallStdoutHandlerFormatsLikePython() {
        let savedHandler = Reticulum.logHandler
        let savedLevel = Reticulum.globalLogLevel
        defer {
            Reticulum.logHandler = savedHandler
            Reticulum.globalLogLevel = savedLevel
        }

        var captured: [String] = []
        FileLogSink.installStdoutHandler(writer: { captured.append($0) })
        Reticulum.globalLogLevel = .notice
        Reticulum.log("Started rnsd version \(Reticulum.version)", level: .notice)

        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(captured[0].hasSuffix("[Notice]   Started rnsd version \(Reticulum.version)"),
                      captured[0])
    }
}
