import Foundation

/// Turns a decoded ``RNXResult`` into the exact bytes and lines `rnx` prints.
///
/// Python reference: `RNS/Utilities/rnx.py:459-518` (the `if detailed:` / `else:` blocks
/// inside `execute`), plus the local `size_str` (rnx.py:678) and `pretty_time` (rnx.py:697).
///
/// Zero I/O, so every line is assertable. The executable writes ``Rendered/stdoutBytes``
/// to fd 1, ``Rendered/stderrBytes`` to fd 2 and then prints ``Rendered/trailer``.
public enum RNXResultRenderer {

    /// Transfer accounting the `-d` block needs, lifted off `RequestReceipt`.
    public struct Metrics: Equatable {
        /// Swift's `RequestReceipt.requestSize` is a non-optional `Int`; Python's may be
        /// None, and the addition is guarded (rnx.py:475). Optional here for parity.
        public var requestSize: Int?
        public var responseSize: Int?
        public var sentAt: Date
        public var responseConcludedAt: Date?

        public init(requestSize: Int?, responseSize: Int?, sentAt: Date, responseConcludedAt: Date?) {
            self.requestSize = requestSize
            self.responseSize = responseSize
            self.sentAt = sentAt
            self.responseConcludedAt = responseConcludedAt
        }
    }

    public struct Rendered: Equatable {
        /// Raw remote stdout. Python does `stdout.decode("utf-8")` with no error handler,
        /// so non-UTF-8 remote output tracebacks the client; writing the raw bytes is
        /// better behaviour but means binary payloads will not match Python.
        public var stdoutBytes: Data
        public var stderrBytes: Data
        /// Everything printed to stdout *after* the raw output, with no trailing newline.
        /// `""` when there is none.
        public var trailer: String

        public init(stdoutBytes: Data, stderrBytes: Data, trailer: String) {
            self.stdoutBytes = stdoutBytes
            self.stderrBytes = stderrBytes
            self.trailer = trailer
        }
    }

    /// - Parameters:
    ///   - stdoutLimitArg: the local `--stdout` value, **not** the one echoed by the
    ///     remote. Python compares `stdoutl != 0`, and `None != 0` is True — so an
    ///     unset limit still enables the truncation notice.
    public static func render(result: RNXResult,
                              detailed: Bool,
                              metrics: Metrics,
                              stdoutLimitArg: Int?,
                              stderrLimitArg: Int?) -> Rendered {
        // Python: nothing at all is printed on the not-executed path — both output blocks
        // live inside `if executed:` (rnx.py:459). The caller prints
        // "Remote could not execute command" and exits 248.
        guard result.executed else {
            return Rendered(stdoutBytes: Data(), stderrBytes: Data(), trailer: "")
        }

        let stdout = result.stdout ?? Data()
        let stderr = result.stderr ?? Data()
        // Python evaluates `len(stdout) < outlen` unguarded and tracebacks on a nil
        // outlen; treating a missing total as "no truncation" is the documented divergence.
        let outLength = result.totalStdoutLength ?? stdout.count
        let errLength = result.totalStderrLength ?? stderr.count

        var lines: [String] = []

        if detailed {
            // Python: print("\n--- End of remote output, rnx done ---") — a blank line,
            // then the marker.
            lines.append("")
            lines.append("--- End of remote output, rnx done ---")

            if let started = result.startedAt, let concluded = result.concludedAt {
                let commandDuration = pythonRound(concluded - started, decimals: 3)
                lines.append("Remote command execution took "
                             + pythonRepr(commandDuration) + " seconds")

                // Python: `total_size = response_size` then `+= request_size` when non-None.
                // A nil response_size is a TypeError there; treated as 0 here.
                let totalSize = (metrics.responseSize ?? 0) + (metrics.requestSize ?? 0)

                let concludedAt = metrics.responseConcludedAt ?? metrics.sentAt
                let wallSpan = concludedAt.timeIntervalSince(metrics.sentAt)
                let transferDuration = pythonRound(wallSpan - commandDuration, decimals: 3)

                var line = "Transferred " + UtilityFormatting.sizeStr(totalSize)
                    + transferDurationPhrase(transferDuration)
                // Python: `total_size/transfer_duration` is a ZeroDivisionError when the
                // duration rounds to 0.0. The rate is simply omitted instead.
                if transferDuration != 0 {
                    line += ", effective rate "
                        + UtilityFormatting.sizeStr(Double(totalSize) / transferDuration, suffix: "b")
                        + "ps"
                }
                lines.append(line)
            }

            // Python: rnx.py:490-502.
            if result.totalStdoutLength != nil, result.stdout != nil {
                let suffix = stdout.count < outLength ? ", \(stdout.count) bytes displayed" : ""
                lines.append("Remote wrote \(outLength) bytes to stdout" + suffix)
            }
            if result.totalStderrLength != nil, result.stderr != nil {
                let suffix = stderr.count < errLength ? ", \(stderr.count) bytes displayed" : ""
                lines.append("Remote wrote \(errLength) bytes to stderr" + suffix)
            }
        } else {
            // Python: rnx.py:511-518. `stdoutl != 0` where stdoutl is the LOCAL --stdout
            // value, and `None != 0` is True.
            let stdoutTruncated = (stdoutLimitArg != 0) && stdout.count < outLength
            let stderrTruncated = (stderrLimitArg != 0) && stderr.count < errLength
            if stdoutTruncated || stderrTruncated {
                lines.append("")   // the leading \n of print("\nOutput truncated...")
                lines.append("Output truncated before being returned:")
                if stdout.count != 0 && stdout.count < outLength {
                    lines.append("  stdout truncated to \(stdout.count) bytes")
                }
                if stderr.count != 0 && stderr.count < errLength {
                    lines.append("  stderr truncated to \(stderr.count) bytes")
                }
            }
        }

        return Rendered(stdoutBytes: stdout,
                        stderrBytes: stderr,
                        trailer: lines.joined(separator: "\n"))
    }

    // MARK: - Python number formatting

    /// Python's `round(value, decimals)` — round-half-to-even on the exact binary value,
    /// which is what `printf("%.*f")` does under the default rounding mode.
    public static func pythonRound(_ value: Double, decimals: Int) -> Double {
        Double(String(format: "%.\(decimals)f", value)) ?? value
    }

    /// Python's `str(float)` — the shortest representation that round-trips, always
    /// carrying at least one decimal digit. Swift's default `Double` description matches.
    public static func pythonRepr(_ value: Double) -> String { "\(value)" }

    /// Python's `str(round(value, decimals))`.
    public static func pythonFloatString(_ value: Double, decimals: Int) -> String {
        pythonRepr(pythonRound(value, decimals: decimals))
    }

    // MARK: - Duration phrasing

    /// Python: rnx.py:479-484. `transfer_duration` reaches this already rounded to 3
    /// decimals, and can legitimately be 0 or negative.
    public static func transferDurationPhrase(_ seconds: Double) -> String {
        if seconds == 1 { return " in 1 second" }
        if seconds < 10 { return " in " + pythonFloatString(seconds, decimals: 3) + " seconds" }
        return " in " + rnxPrettyTime(seconds)
    }

    /// Byte-exact port of `rnx.pretty_time` (rnx.py:697-737).
    ///
    /// Deliberately **not** `RNSUtilities.prettytime`, which differs in two visible ways:
    /// - it collapses a whole-number seconds component to `"5s"`, where Python formats
    ///   `str(round(t, 2))` — always a float repr — giving `"5.0s"`;
    /// - it returns `"0s"` for an all-zero duration, where rnx's local copy ends with a
    ///   bare `return tstr` and yields `""`.
    ///
    /// Python's `//` and `%` are floor-based, so a negative input wraps into a large
    /// positive remainder rather than staying negative. That is reproduced too.
    public static func rnxPrettyTime(_ seconds: Double, verbose: Bool = false) -> String {
        var time = seconds
        let days = Int(pythonFloorDiv(time, 24 * 3600))
        time = pythonMod(time, 24 * 3600)
        let hours = Int(pythonFloorDiv(time, 3600))
        time = pythonMod(time, 3600)
        let minutes = Int(pythonFloorDiv(time, 60))
        time = pythonMod(time, 60)
        let secondsComponent = pythonRound(time, decimals: 2)

        let ss = secondsComponent == 1 ? "" : "s"
        let sm = minutes == 1 ? "" : "s"
        let sh = hours == 1 ? "" : "s"
        let sd = days == 1 ? "" : "s"

        var components: [String] = []
        if days > 0    { components.append(verbose ? "\(days) day\(sd)" : "\(days)d") }
        if hours > 0   { components.append(verbose ? "\(hours) hour\(sh)" : "\(hours)h") }
        if minutes > 0 { components.append(verbose ? "\(minutes) minute\(sm)" : "\(minutes)m") }
        if secondsComponent > 0 {
            let text = pythonRepr(secondsComponent)
            components.append(verbose ? "\(text) second\(ss)" : "\(text)s")
        }

        var result = ""
        for (index, component) in components.enumerated() {
            let position = index + 1
            if position == 1 {
                // Python: `pass` — no separator before the first component.
            } else if position < components.count {
                result += ", "
            } else {
                result += " and "
            }
            result += component
        }
        return result
    }

    /// Python's `//` on floats: floor division, not truncation.
    private static func pythonFloorDiv(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs / rhs).rounded(.down)
    }

    /// Python's `%` on floats: the result takes the sign of the divisor.
    private static func pythonMod(_ lhs: Double, _ rhs: Double) -> Double {
        lhs - pythonFloorDiv(lhs, rhs) * rhs
    }
}
