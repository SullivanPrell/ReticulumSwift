import XCTest
@testable import ReticulumSwift

/// Parity tests for RNS 1.3.9 HDLC received-frame length bounds
/// (Python TCPInterface.check_frame_len / read-loop, commit a5ed0a43).
final class HDLCFrameBoundsTests: XCTestCase {

    private let hwMtu = 64
    private let ifacSize = 4

    /// A frame within bounds is delivered unchanged.
    func testInBoundsFrameIsDelivered() {
        let decoder = HDLC.FrameDecoder()
        let payload = Data(repeating: 0x11, count: 40)
        let frames = decoder.feed(HDLC.frame(payload), hwMtu: hwMtu, ifacSize: ifacSize)
        XCTAssertEqual(frames, [payload])
    }

    /// A frame at exactly hwMtu + ifacSize is still delivered (upper bound is inclusive).
    func testFrameAtUpperBoundIsDelivered() {
        let decoder = HDLC.FrameDecoder()
        let payload = Data(repeating: 0x22, count: hwMtu + ifacSize)
        let frames = decoder.feed(HDLC.frame(payload), hwMtu: hwMtu, ifacSize: ifacSize)
        XCTAssertEqual(frames, [payload])
    }

    /// A frame larger than hwMtu + ifacSize is dropped.
    func testOversizedFrameIsDropped() {
        let decoder = HDLC.FrameDecoder()
        let payload = Data(repeating: 0x33, count: hwMtu + ifacSize + 1)
        let frames = decoder.feed(HDLC.frame(payload), hwMtu: hwMtu, ifacSize: ifacSize)
        XCTAssertTrue(frames.isEmpty, "oversized frame must be dropped")
    }

    /// With no bounds supplied (default), oversized frames are still delivered —
    /// preserving the original unbounded behavior for callers that don't opt in.
    func testUnboundedDecoderStillDeliversLargeFrame() {
        let decoder = HDLC.FrameDecoder()
        let payload = Data(repeating: 0x44, count: hwMtu * 10)
        let frames = decoder.feed(HDLC.frame(payload))
        XCTAssertEqual(frames, [payload])
    }

    /// An unterminated partial frame that grows past 2×hwMtu is discarded, and the
    /// decoder resynchronizes on the next FLAG-delimited frame.
    func testRunawayPartialFrameIsDiscardedThenResyncs() {
        let decoder = HDLC.FrameDecoder()

        // Open a frame (FLAG) then feed a runaway body with no closing FLAG.
        var runaway = Data([HDLC.flag])
        runaway.append(Data(repeating: 0x55, count: hwMtu * 2 + 10))
        let none = decoder.feed(runaway, hwMtu: hwMtu, ifacSize: ifacSize)
        XCTAssertTrue(none.isEmpty, "runaway partial frame must not emit anything")

        // A subsequent, well-formed frame must still decode (decoder resynced).
        let payload = Data(repeating: 0x66, count: 20)
        let frames = decoder.feed(HDLC.frame(payload), hwMtu: hwMtu, ifacSize: ifacSize)
        XCTAssertEqual(frames, [payload], "decoder must resync after discarding a runaway frame")
    }
}
