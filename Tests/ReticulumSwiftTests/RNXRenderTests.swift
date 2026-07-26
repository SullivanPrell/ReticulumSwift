import XCTest
@testable import ReticulumSwift

/// Exact output strings for rnx's plain, truncation-notice and `-d` blocks.
/// Python reference: RNS/Utilities/rnx.py:459-518, plus size_str (:678) and pretty_time (:697).
final class RNXRenderTests: XCTestCase {

    private func metrics(requestSize: Int? = nil,
                         responseSize: Int? = nil,
                         sentAt: TimeInterval = 0,
                         concludedAfter: TimeInterval? = nil) -> RNXResultRenderer.Metrics {
        RNXResultRenderer.Metrics(
            requestSize: requestSize,
            responseSize: responseSize,
            sentAt: Date(timeIntervalSince1970: sentAt),
            responseConcludedAt: concludedAfter.map { Date(timeIntervalSince1970: sentAt + $0) }
        )
    }

    // MARK: - Plain output

    func testPlainOutputWithNoTruncation() {
        let result = RNXResult(executed: true, returnCode: 0,
                               stdout: Data("hi\n".utf8), stderr: Data(),
                               totalStdoutLength: 3, totalStderrLength: 0,
                               startedAt: 1000, concludedAt: 1000.1)
        let rendered = RNXResultRenderer.render(result: result, detailed: false,
                                                metrics: metrics(),
                                                stdoutLimitArg: nil, stderrLimitArg: nil)
        XCTAssertEqual(rendered.stdoutBytes, Data("hi\n".utf8))
        XCTAssertEqual(rendered.trailer, "")
    }

    func testPlainTruncationNotice() {
        // Python: rnx.py:511-518. `stdoutl != 0` is True for the default None, and the
        // notice begins with a blank line from the leading \n in the print.
        let result = RNXResult(executed: true, returnCode: 0,
                               stdout: Data(repeating: 0x61, count: 10), stderr: Data(),
                               totalStdoutLength: 100, totalStderrLength: 0,
                               startedAt: 1000, concludedAt: 1000.1)
        let rendered = RNXResultRenderer.render(result: result, detailed: false,
                                                metrics: metrics(),
                                                stdoutLimitArg: nil, stderrLimitArg: nil)
        XCTAssertEqual(rendered.trailer,
                       "\nOutput truncated before being returned:\n  stdout truncated to 10 bytes")
    }

    func testPlainTruncationNoticeSuppressedByZeroLimitArgument() {
        // Python: `stdoutl != 0` — an explicit --stdout 0 disables the notice for stdout.
        let result = RNXResult(executed: true, returnCode: 0,
                               stdout: Data(), stderr: Data(),
                               totalStdoutLength: 100, totalStderrLength: 0,
                               startedAt: 1000, concludedAt: 1000.1)
        let rendered = RNXResultRenderer.render(result: result, detailed: false,
                                                metrics: metrics(),
                                                stdoutLimitArg: 0, stderrLimitArg: nil)
        XCTAssertEqual(rendered.trailer, "")
    }

    func testNotExecutedRendersNothing() {
        // Python: both output blocks live inside `if executed:` (rnx.py:459).
        let result = RNXResult(executed: false, startedAt: 1000)
        let rendered = RNXResultRenderer.render(result: result, detailed: true,
                                                metrics: metrics(responseSize: 60),
                                                stdoutLimitArg: nil, stderrLimitArg: nil)
        XCTAssertEqual(rendered.stdoutBytes, Data())
        XCTAssertEqual(rendered.stderrBytes, Data())
        XCTAssertEqual(rendered.trailer, "")
    }

    // MARK: - Detailed output

    func testDetailedTrailer() {
        // started 1000.0, concluded 1002.5  → cmd_duration 2.5
        // sent .. concluded spans 3.0 s     → transfer_duration 0.5
        // response 60 + request 40 = 100 B  → 100/0.5 = 200 B/s → *8 = 1.60 Kbps
        let result = RNXResult(executed: true, returnCode: 0,
                               stdout: Data(repeating: 0x61, count: 100), stderr: nil,
                               totalStdoutLength: 100, totalStderrLength: nil,
                               startedAt: 1000.0, concludedAt: 1002.5)
        let rendered = RNXResultRenderer.render(
            result: result, detailed: true,
            metrics: metrics(requestSize: 40, responseSize: 60, sentAt: 500, concludedAfter: 3.0),
            stdoutLimitArg: nil, stderrLimitArg: nil)

        XCTAssertEqual(rendered.trailer.components(separatedBy: "\n"), [
            "",
            "--- End of remote output, rnx done ---",
            "Remote command execution took 2.5 seconds",
            "Transferred 100 B in 0.5 seconds, effective rate 1.60 Kbps",
            "Remote wrote 100 bytes to stdout",
        ])
    }

    func testDetailedReportsDisplayedBytesWhenTruncated() {
        let result = RNXResult(executed: true, returnCode: 0,
                               stdout: Data(repeating: 0x61, count: 10), stderr: Data(),
                               totalStdoutLength: 100, totalStderrLength: 0,
                               startedAt: nil, concludedAt: nil)
        let rendered = RNXResultRenderer.render(result: result, detailed: true,
                                                metrics: metrics(),
                                                stdoutLimitArg: 10, stderrLimitArg: nil)
        XCTAssertEqual(rendered.trailer.components(separatedBy: "\n"), [
            "",
            "--- End of remote output, rnx done ---",
            "Remote wrote 100 bytes to stdout, 10 bytes displayed",
            "Remote wrote 0 bytes to stderr",
        ])
    }

    func testDetailedGuardsZeroTransferDuration() {
        // Python: total_size/transfer_duration is a ZeroDivisionError here. The rate is
        // omitted instead; everything else is unchanged.
        let result = RNXResult(executed: true, returnCode: 0,
                               stdout: Data(), stderr: Data(),
                               totalStdoutLength: 0, totalStderrLength: 0,
                               startedAt: 1000.0, concludedAt: 1002.0)
        let rendered = RNXResultRenderer.render(
            result: result, detailed: true,
            metrics: metrics(requestSize: 10, responseSize: 20, sentAt: 0, concludedAfter: 2.0),
            stdoutLimitArg: nil, stderrLimitArg: nil)
        XCTAssertTrue(rendered.trailer.contains("Transferred 30 B in 0.0 seconds"))
        XCTAssertFalse(rendered.trailer.contains("effective rate"))
    }

    // MARK: - Number formatting

    func testPythonFloatString() {
        // Python: str(round(x, n))
        XCTAssertEqual(RNXResultRenderer.pythonFloatString(2.0, decimals: 3), "2.0")
        XCTAssertEqual(RNXResultRenderer.pythonFloatString(1.50, decimals: 3), "1.5")
        XCTAssertEqual(RNXResultRenderer.pythonFloatString(0.1234, decimals: 3), "0.123")
        XCTAssertEqual(RNXResultRenderer.pythonFloatString(0.0, decimals: 1), "0.0")
        XCTAssertEqual(RNXResultRenderer.pythonFloatString(100.0, decimals: 1), "100.0")
    }

    // MARK: - Duration phrasing

    func testTransferDurationPhrase() {
        // Python: rnx.py:479-484
        XCTAssertEqual(RNXResultRenderer.transferDurationPhrase(1.0), " in 1 second")
        XCTAssertEqual(RNXResultRenderer.transferDurationPhrase(9.5), " in 9.5 seconds")
        // pretty_time formats seconds as str(round(t,2)) — always a float repr, so "5.0s",
        // NOT the "5s" RNSUtilities.prettytime would produce.
        XCTAssertEqual(RNXResultRenderer.transferDurationPhrase(65.0), " in 1m and 5.0s")
    }

    func testTransferDurationPhraseHandlesZeroAndNegative() {
        XCTAssertEqual(RNXResultRenderer.transferDurationPhrase(0.0), " in 0.0 seconds")
        XCTAssertEqual(RNXResultRenderer.transferDurationPhrase(-0.5), " in -0.5 seconds")
    }

    func testRnxPrettyTimeDivergesFromRNSPrettytime() {
        // Pinned rather than absorbed: rnx's local pretty_time ends with a bare
        // `return tstr` (rnx.py:737), so an all-zero duration yields "".
        XCTAssertEqual(RNXResultRenderer.rnxPrettyTime(0.0), "")
        XCTAssertEqual(RNSUtilities.prettytime(0.0), "0s")
        // And whole seconds keep their decimal point.
        XCTAssertEqual(RNXResultRenderer.rnxPrettyTime(65.0), "1m and 5.0s")
        XCTAssertEqual(RNSUtilities.prettytime(65.0), "1m and 5s")
    }

    func testRnxPrettyTimeComponents() {
        // Python: pretty_time(3*86400 + 4*3600 + 5*60 + 6.25).
        // Spelled out with explicit Double terms rather than inline: as one mixed
        // integer/floating literal expression the type checker has to weigh every
        // numeric overload of `*` and `+` at once, which times it out on CI.
        let days: Double = 3 * 86400
        let hours: Double = 4 * 3600
        let minutes: Double = 5 * 60
        let seconds: Double = 6.25
        XCTAssertEqual(RNXResultRenderer.rnxPrettyTime(days + hours + minutes + seconds),
                       "3d, 4h, 5m and 6.25s")
        XCTAssertEqual(RNXResultRenderer.rnxPrettyTime(3600, verbose: true), "1 hour")
        XCTAssertEqual(RNXResultRenderer.rnxPrettyTime(7200, verbose: true), "2 hours")
    }
}
