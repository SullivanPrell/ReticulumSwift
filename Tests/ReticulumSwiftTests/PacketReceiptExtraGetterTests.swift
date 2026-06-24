import XCTest
@testable import ReticulumSwift

/// Tests for the additional PacketReceipt getter methods that mirror Python's API:
///   PacketReceipt.get_hash()        → packetHash bytes
///   PacketReceipt.get_proved()      → proved flag
///   PacketReceipt.sent_at           → creation timestamp
///   PacketReceipt.concluded_at      → completion timestamp
final class PacketReceiptExtraGetterTests: XCTestCase {

    private func makeReceipt() -> PacketReceipt {
        PacketReceipt(testHash: Data(repeating: 0xAB, count: 32))
    }

    // MARK: - getHash

    func testGetHashMatchesPacketHash() {
        let r = makeReceipt()
        XCTAssertEqual(r.getHash(), r.packetHash,
                       "getHash() must return the same data as packetHash")
    }

    func testGetHashIs32Bytes() {
        let r = makeReceipt()
        XCTAssertEqual(r.getHash().count, 32,
                       "packet hash must be 32 bytes (full SHA-256)")
    }

    // MARK: - getProved

    func testGetProvedFalseByDefault() {
        let r = makeReceipt()
        XCTAssertFalse(r.getProved(),
                       "getProved() must be false before any proof arrives")
    }

    func testGetProvedMatchesProvedProperty() {
        let r = makeReceipt()
        XCTAssertEqual(r.getProved(), r.proved)
    }

    // MARK: - getSentAt

    func testGetSentAtMatchesSentAt() {
        let before = Date()
        let r = makeReceipt()
        let after = Date()
        let sent = r.getSentAt()
        XCTAssertGreaterThanOrEqual(sent, before)
        XCTAssertLessThanOrEqual(sent, after)
        XCTAssertEqual(sent, r.sentAt)
    }

    // MARK: - getConcludedAt

    func testGetConcludedAtNilBeforeConclusion() {
        let r = makeReceipt()
        XCTAssertNil(r.getConcludedAt(),
                     "getConcludedAt() must be nil while the receipt is still pending")
    }

    func testGetConcludedAtSetAfterTimeout() {
        let r = PacketReceipt(testHash: Data(repeating: 0xFF, count: 32))
        r.timeout = 0   // expire immediately
        Thread.sleep(forTimeInterval: 0.01)
        r.checkTimeout()
        XCTAssertNotNil(r.getConcludedAt(),
                        "getConcludedAt() must be non-nil after the receipt times out")
        XCTAssertEqual(r.getConcludedAt(), r.concludedAt)
    }
}
