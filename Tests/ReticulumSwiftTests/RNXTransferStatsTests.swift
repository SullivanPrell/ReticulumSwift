import XCTest
@testable import ReticulumSwift

/// The sliding-window meter behind the "Receiving result" spinner.
/// Python reference: RNS/Utilities/rnx.py:274-321 and the stat_str at :288.
final class RNXTransferStatsTests: XCTestCase {

    func testSpeedIsDeltaBytesOverDeltaSeconds() {
        var stats = RNXTransferStats()
        // 10 000-byte transfer, progress rising 0.1 per 0.1 s → 1000 B per 0.1 s.
        for step in 0...4 {
            stats.record(progress: Double(step) * 0.1,
                         transferSize: 10_000,
                         at: Double(step) * 0.1)
        }
        // Python: span = now - stats[0][0]; speed = (got - stats[0][1]) / span
        // = (4000 - 0) / 0.4 = 10 000 B/s.
        XCTAssertEqual(stats.speed, 10_000, accuracy: 1e-6)
        XCTAssertEqual(stats.progress, 0.4, accuracy: 1e-9)
        XCTAssertEqual(stats.transferSize, 10_000)
    }

    func testZeroSpanYieldsZeroSpeed() {
        // Python: `if span == 0: speed = 0` — the first sample always hits this.
        var stats = RNXTransferStats()
        stats.record(progress: 0.5, transferSize: 1000, at: 100)
        XCTAssertEqual(stats.speed, 0)
    }

    func testWindowCapsAt32Samples() {
        // Python: `while len(stats) > stats_max: stats.pop(0)` with stats_max = 32.
        var stats = RNXTransferStats()
        for step in 0..<100 {
            stats.record(progress: Double(step) / 100.0, transferSize: 1000, at: Double(step))
        }
        XCTAssertEqual(RNXTransferStats.maxSamples, 32)
        XCTAssertEqual(stats.sampleCount, 32)
    }

    func testStatusLineMatchesPython() {
        // Golden from Python:
        //   str(round(0.4*100.0,1))+"% - "+size_str(int(0.4*10000))+" of "+size_str(10000)
        //   +" - "+size_str(10000.0,"b")+"ps"  ==  '40.0% - 4.00 KB of 10.00 KB - 80.00 Kbps'
        var stats = RNXTransferStats()
        stats.record(progress: 0.0, transferSize: 10_000, at: 0.0)
        stats.record(progress: 0.4, transferSize: 10_000, at: 0.4)
        XCTAssertEqual(stats.speed, 10_000, accuracy: 1e-6)
        XCTAssertEqual(stats.statusLine(), "40.0% - 4.00 KB of 10.00 KB - 80.00 Kbps")
    }

    func testSamplesSurviveAcrossCommands() {
        // Python's `stats`, `current_progress` and `speed` are module globals that are
        // NEVER cleared between interactive commands, so the first frame of command N
        // shows command N-1's numbers and a speed averaged across both transfers.
        // Pinned here rather than "fixed", because it is visible behaviour.
        var stats = RNXTransferStats()
        stats.record(progress: 1.0, transferSize: 1000, at: 0.0)
        let carriedOver = stats.sampleCount
        stats.record(progress: 0.0, transferSize: 5000, at: 10.0)
        XCTAssertEqual(stats.sampleCount, carriedOver + 1)
        // The window still starts at the previous command's sample.
        XCTAssertEqual(stats.speed, (0.0 - 1000.0) / 10.0, accuracy: 1e-9)
    }
}
