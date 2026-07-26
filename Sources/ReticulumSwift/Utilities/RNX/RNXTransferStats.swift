import Foundation

/// The sliding-window transfer meter behind `rnx`'s "Receiving result" spinner.
///
/// Python reference: `remote_execution_progress` (rnx.py:304-321) and the `stat_str`
/// built inside `spin_stat` (rnx.py:288).
///
/// Python keeps `current_progress`, `stats` and `speed` as **module globals that are
/// never cleared between commands**, so in interactive mode the first frame of command N
/// shows command N-1's percentage and a speed averaged across a window straddling both
/// transfers. That is reproduced by owning one instance per session rather than per
/// request — see the executable, which creates exactly one.
public struct RNXTransferStats {

    /// Python: `stats_max = 32` — rnx.py:305.
    public static let maxSamples: Int = 32

    /// Python: `current_progress`, i.e. `request_receipt.progress`, 0…1.
    public private(set) var progress: Double = 0

    /// Python: `response_transfer_size`, in bytes.
    public private(set) var transferSize: Int = 0

    /// **Bytes** per second over the window. Fed to `size_str(..., "b")`, which multiplies
    /// by 8 — so render it with `UtilityFormatting.sizeStr(speed, suffix: "b") + "ps"`,
    /// never `RNSUtilities.prettyspeed`, which expects bits/sec and divides by 8 first.
    public private(set) var speed: Double = 0

    private var samples: [(at: TimeInterval, got: Double)] = []

    public init() {}

    /// Python: rnx.py:307-321. Note the callback also fires once on READY
    /// (Link.py:1413-1415), so the last sample is always 100%.
    public mutating func record(progress: Double, transferSize: Int, at now: TimeInterval) {
        self.progress = progress
        self.transferSize = transferSize

        let got = progress * Double(transferSize)
        samples.append((now, got))
        while samples.count > RNXTransferStats.maxSamples { samples.removeFirst() }

        let span = now - samples[0].at
        speed = span == 0 ? 0 : (got - samples[0].got) / span
    }

    /// Number of samples currently retained. Exposed so the 32-entry cap is assertable.
    public var sampleCount: Int { samples.count }

    /// Python: `stat_str = str(percent)+"% - "+size_str(int(prg*size))+" of "+size_str(size)
    /// +" - "+size_str(speed,"b")+"ps"` — rnx.py:287-288.
    public func statusLine() -> String {
        let percent = RNXResultRenderer.pythonFloatString(progress * 100.0, decimals: 1)
        let got = Int(progress * Double(transferSize))
        return percent + "% - "
            + UtilityFormatting.sizeStr(got) + " of "
            + UtilityFormatting.sizeStr(transferSize) + " - "
            + UtilityFormatting.sizeStr(speed, suffix: "b") + "ps"
    }
}
