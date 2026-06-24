import XCTest
@testable import ReticulumSwift

final class PacketReceiptGetterTests: XCTestCase {

    private func makeReceipt(timeout: TimeInterval = 60) -> PacketReceipt {
        let hash = Data(repeating: 0xAB, count: 32)
        let r = PacketReceipt(testHash: hash)
        r.timeout = timeout
        return r
    }

    // MARK: - getStatus

    func testGetStatusDefaultIsSent() {
        let r = makeReceipt()
        XCTAssertEqual(r.getStatus(), .sent)
    }

    // MARK: - setTimeout

    func testSetTimeoutUpdatesTimeout() {
        let r = makeReceipt(timeout: 30)
        r.setTimeout(120)
        XCTAssertEqual(r.timeout, 120)
    }

    // MARK: - isTimedOutMethod

    func testIsTimedOutMethodFalseForFutureTimeout() {
        let r = makeReceipt(timeout: 9999)
        XCTAssertFalse(r.isTimedOutMethod())
    }

    func testIsTimedOutMethodTrueForExpiredTimeout() {
        let r = makeReceipt(timeout: 0.001)
        Thread.sleep(forTimeInterval: 0.01)
        XCTAssertTrue(r.isTimedOutMethod())
    }

    // MARK: - getRtt

    func testGetRttNilBeforeDelivery() {
        let r = makeReceipt()
        XCTAssertNil(r.getRtt())
    }

    // MARK: - setDeliveryCallback

    func testSetDeliveryCallbackFires() {
        let r = makeReceipt()
        let exp = expectation(description: "delivery")
        r.setDeliveryCallback { _ in exp.fulfill() }
        // Prove it by injecting proof: use internal timeout fire → failed, not delivered.
        // So just verify callback is assigned and manually invoke.
        r.onDelivery?(r)
        wait(for: [exp], timeout: 1)
    }

    // MARK: - setTimeoutCallback

    func testSetTimeoutCallbackFires() {
        let r = makeReceipt(timeout: 0.001)
        let exp = expectation(description: "timeout")
        r.setTimeoutCallback { _ in exp.fulfill() }
        Thread.sleep(forTimeInterval: 0.02)
        r.checkTimeout()
        wait(for: [exp], timeout: 1)
    }
}
