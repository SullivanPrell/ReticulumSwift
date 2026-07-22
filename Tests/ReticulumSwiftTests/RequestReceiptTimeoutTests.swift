import XCTest
@testable import ReticulumSwift

/// Regression tests for the NomadNet "pages won't load" bug: a page request
/// used a fixed timeout that was never disarmed once the response began arriving
/// as a Resource, so any response that took longer than the timeout to transfer
/// (any real, multi-KB page over a slower / multi-hop mesh) was aborted
/// mid-download. Python disarms the request timeout the moment the response
/// enters RECEIVING and lets the Resource's own watchdog finish the transfer
/// (RNS/Link.py `RequestReceipt.response_resource_progress`).
final class RequestReceiptTimeoutTests: XCTestCase {

    private func makeReceipt(timeout: TimeInterval) -> RequestReceipt {
        RequestReceipt(requestID: Data([0xAB, 0xCD]), path: "/page/index.mu",
                       requestSize: 8, timeout: timeout)
    }

    /// Baseline / fail-safe: with no response at all, the fixed timeout still
    /// fires. (Guards against the fix accidentally disabling the timeout.)
    func testTimeoutFiresWhenNoResponseArrives() {
        let receipt = makeReceipt(timeout: 0.2)
        let failed = expectation(description: "timeout fired")
        receipt.onFailed = { reason, _ in
            XCTAssertEqual(reason, "timeout")
            failed.fulfill()
        }
        wait(for: [failed], timeout: 2.0)
        XCTAssertTrue(receipt.isFailed)
    }

    /// The fix: once the response begins arriving as a Resource, the request
    /// timeout is disarmed and does NOT fire, even well past the original
    /// deadline — the Resource watchdog governs the transfer from here.
    func testResponseResourceStartDisarmsRequestTimeout() {
        let receipt = makeReceipt(timeout: 0.2)
        var failReason: String?
        receipt.onFailed = { reason, _ in failReason = reason }

        // Response Resource begins arriving before the 0.2 s deadline.
        receipt.beginReceivingResponse()

        // Wait well past the original timeout.
        let waited = expectation(description: "waited past timeout")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { waited.fulfill() }
        wait(for: [waited], timeout: 2.0)

        XCTAssertNil(failReason, "request timeout must not fire once the response Resource has started")
        XCTAssertFalse(receipt.isFailed)

        // The (arbitrarily long) transfer then completes normally.
        let ready = expectation(description: "response delivered")
        receipt.onResponse = { data, _ in
            XCTAssertEqual(data, Data("big page".utf8))
            ready.fulfill()
        }
        receipt.deliverReady(Data("big page".utf8))
        wait(for: [ready], timeout: 1.0)
        XCTAssertTrue(receipt.isReady)
    }

    /// Safety: a response Resource that stalls after it started must still
    /// conclude the receipt as failed (Link wires the resource's onFailed to
    /// `fail`), not hang forever now that the request timeout is disarmed.
    func testFailAfterReceivingStartConcludesReceipt() {
        let receipt = makeReceipt(timeout: 30)  // long — not the trigger here
        receipt.beginReceivingResponse()
        let failed = expectation(description: "explicit fail concludes receipt")
        receipt.onFailed = { _, _ in failed.fulfill() }
        receipt.fail("response resource transfer failed (failed)")
        wait(for: [failed], timeout: 1.0)
        XCTAssertTrue(receipt.isFailed)
    }
}
