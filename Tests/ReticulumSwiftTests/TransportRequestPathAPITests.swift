import XCTest
@testable import ReticulumSwift

/// Tests for the extended `Transport.requestPath(for:onInterface:tag:recursive:)` signature,
/// mirroring Python's `Transport.request_path(destination_hash, on_interface=None, tag=None, recursive=False)`.
final class TransportRequestPathAPITests: XCTestCase {

    // MARK: - Helpers

    private func makeTransportWithLoopback() -> (Transport, LoopbackInterface) {
        let t = Transport()
        let lo = LoopbackInterface(name: "RequestPathAPITest")
        t.register(interface: lo)
        return (t, lo)
    }

    private func randomHash() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    }

    // MARK: - Default parameters (no tag, no recursive)

    func testRequestPathDefaultParamsDoesNotThrow() throws {
        let (t, _) = makeTransportWithLoopback()
        let dest = randomHash()
        XCTAssertNoThrow(try t.requestPath(for: dest),
                         "requestPath with default params must not throw")
    }

    // MARK: - Explicit tag parameter

    func testRequestPathWithExplicitTagDoesNotThrow() throws {
        let (t, _) = makeTransportWithLoopback()
        let dest = randomHash()
        let tag = Data(repeating: 0xAB, count: 16)
        XCTAssertNoThrow(try t.requestPath(for: dest, tag: tag),
                         "requestPath with explicit tag must not throw")
    }

    func testRequestPathWithExplicitTagSameHashDedupedOnce() throws {
        let (t, _) = makeTransportWithLoopback()
        let dest = randomHash()
        let tag = Data(repeating: 0xCD, count: 16)
        // Two calls with the same tag: both must succeed (dedup is internal).
        XCTAssertNoThrow(try t.requestPath(for: dest, tag: tag))
        XCTAssertNoThrow(try t.requestPath(for: dest, tag: tag))
    }

    func testRequestPathWithDifferentTagsAreBothAccepted() throws {
        let (t, _) = makeTransportWithLoopback()
        let dest = randomHash()
        let tag1 = Data(repeating: 0x01, count: 16)
        let tag2 = Data(repeating: 0x02, count: 16)
        XCTAssertNoThrow(try t.requestPath(for: dest, tag: tag1))
        XCTAssertNoThrow(try t.requestPath(for: dest, tag: tag2))
    }

    // MARK: - Recursive flag

    func testRequestPathWithRecursiveTrueDoesNotThrow() throws {
        let (t, _) = makeTransportWithLoopback()
        let dest = randomHash()
        XCTAssertNoThrow(try t.requestPath(for: dest, recursive: true),
                         "requestPath with recursive=true must not throw")
    }

    func testRequestPathWithRecursiveFalseDoesNotThrow() throws {
        let (t, _) = makeTransportWithLoopback()
        let dest = randomHash()
        XCTAssertNoThrow(try t.requestPath(for: dest, recursive: false),
                         "requestPath with recursive=false must not throw")
    }

    // MARK: - Combined parameters

    func testRequestPathWithAllParametersDoesNotThrow() throws {
        let (t, _) = makeTransportWithLoopback()
        let dest = randomHash()
        let tag = Data(repeating: 0xFF, count: 16)
        XCTAssertNoThrow(
            try t.requestPath(for: dest, onInterface: nil, tag: tag, recursive: false),
            "requestPath with all explicit params must not throw"
        )
    }

    func testRequestPathWithTagAndInterfaceDoesNotThrow() throws {
        let (t, lo) = makeTransportWithLoopback()
        let dest = randomHash()
        let tag = Data(repeating: 0x77, count: 16)
        XCTAssertNoThrow(
            try t.requestPath(for: dest, onInterface: lo, tag: tag, recursive: false),
            "requestPath routed to a specific interface with explicit tag must not throw"
        )
    }

    // MARK: - Invalid hash rejected

    func testRequestPathWithShortHashIsIgnored() throws {
        let (t, _) = makeTransportWithLoopback()
        // A hash shorter than 16 bytes must be silently ignored (guard in impl).
        XCTAssertNoThrow(try t.requestPath(for: Data(repeating: 0, count: 8)),
                         "requestPath with short hash must not throw (silently ignored)")
    }

    func testRequestPathWithLongHashIsIgnored() throws {
        let (t, _) = makeTransportWithLoopback()
        XCTAssertNoThrow(try t.requestPath(for: Data(repeating: 0, count: 32)),
                         "requestPath with long hash must not throw (silently ignored)")
    }
}
