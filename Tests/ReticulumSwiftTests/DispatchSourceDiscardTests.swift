import XCTest
@testable import ReticulumSwift

/// Discarding an unstarted dispatch source must resume it, not just cancel it — `bugs/032`.
///
/// A source from `DispatchSource.make…Source` begins suspended. Releasing a suspended object
/// traps in libdispatch and takes the process with it:
///
///     BUG IN CLIENT OF LIBDISPATCH: Release of a suspended object
///     → EXC_BREAKPOINT / SIGTRAP in _dispatch_queue_xref_dispose
///
/// `cancel()` does not clear the suspension, so the natural-looking `timer.cancel(); return` on
/// an abandon path is a crash. Two sites had it: `Link.rescheduleWatchdog`, when a concurrent
/// `close()` made the link terminal between the watchdog tick's unlock and the reschedule's
/// lock, and `TCPClientInterface.scheduleReconnect`, when `stop()` landed in the same window.
///
/// **How it was found, and why no test caught it.** It surfaced as LXMFSwift's full suite
/// aborting with signal 5 part way through `ProofGatedDeliveryTests` — while every one of those
/// tests passed when run individually, because the race needs a link torn down under a live
/// watchdog. There is no assertion to write for it: a trap is not a failure XCTest can report,
/// it is the reporter dying. The crash report's stack (`Link.rescheduleWatchdog` →
/// `-[OS_dispatch_source _xref_dispose]` → `_dispatch_queue_xref_dispose.cold.1`) is what
/// identified it, and a standalone probe of the four lifecycles is what confirmed which one
/// traps.
///
/// So the gate is: the discard lifecycle is exercised directly here — if it regresses to a bare
/// `cancel()` this test process dies rather than failing — and the structural guard below pins
/// both call sites to the helper, since a third abandon path added later is the real risk.
final class DispatchSourceDiscardTests: XCTestCase {

    // MARK: - The lifecycle

    /// Executes the exact sequence that traps when done wrong: create, never resume, discard,
    /// release. Passing means the process survived.
    func testDiscardingAnUnstartedSourceIsSafe() {
        for _ in 0..<64 {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + 3600, repeating: .never)
            timer.setEventHandler { XCTFail("an abandoned source must never fire") }
            timer.cancelUnstarted()
            // Last reference dropped at the end of this iteration.
        }
    }

    func testDiscardCancelsTheSource() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 3600, repeating: .never)
        timer.setEventHandler { }
        timer.cancelUnstarted()
        XCTAssertTrue(timer.isCancelled,
                      "a discarded source must be cancelled, so it can never fire")
    }

    /// A source that was already running is discarded by the ordinary `cancel()` — the stored
    /// timers' `stop…()` helpers do that, and `cancelUnstarted()` must not be required there.
    func testAStartedSourceIsSafeToCancelAndRelease() {
        for _ in 0..<64 {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + 3600, repeating: .never)
            timer.setEventHandler { }
            timer.resume()
            timer.cancel()
        }
    }

    // MARK: - The structural guard

    /// Every abandon path in a source-owning file goes through `cancelUnstarted()`.
    ///
    /// The same device as D7's `$HOME` guard and for the same reason: the lifecycle test above
    /// covers the helper, and cannot observe a *new* site that hand-rolls `cancel(); return` on
    /// an unstarted source next month. Since the failure mode is a process trap rather than a
    /// reported failure, a site that regresses this costs a crash-report investigation to
    /// attribute — so the assignment form itself is what gets pinned.
    ///
    /// Scoped to files that actually create dispatch sources. `NWConnection.cancel()` is the
    /// same spelling on an unrelated type with no such requirement, and those files
    /// (`RPCServer`, `UDPInterface`) create no sources.
    func testEveryAbandonedSourceGoesThroughTheHelper() throws {
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ReticulumSwiftTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Sources")

        var sourceOwningFiles = 0
        var offences: [String] = []

        let walker = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let src = try String(contentsOf: url, encoding: .utf8)
            // Only files that build dispatch sources can abandon one. The helper's own file is
            // where `cancel()` legitimately appears bare.
            guard src.contains("DispatchSource.make"),
                  url.lastPathComponent != "DispatchSourceDiscard.swift" else { continue }
            sourceOwningFiles += 1

            for (index, line) in src.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else {
                    continue
                }
                // The abandon shape: cancel and bail out in the same breath.
                guard code.contains(".cancel()"), code.contains("return") else { continue }
                guard !code.contains("cancelUnstarted()") else { continue }
                offences.append("  \(url.lastPathComponent):\(index + 1) — \(code)")
            }
        }

        XCTAssertGreaterThan(sourceOwningFiles, 4,
                             "the guard found only \(sourceOwningFiles) dispatch-source-owning "
                             + "file(s) — it has stopped checking what it was written for")

        XCTAssertTrue(offences.isEmpty,
                      """
                      \(offences.count) site(s) cancel and abandon a dispatch source without \
                      resuming it:
                      \(offences.joined(separator: "\n"))
                      A source from DispatchSource.make…Source starts suspended, and releasing a \
                      suspended object traps in libdispatch — "Release of a suspended object" — \
                      killing the process, not reporting a failure. Use `source.cancelUnstarted()`.
                      """)
    }
}
