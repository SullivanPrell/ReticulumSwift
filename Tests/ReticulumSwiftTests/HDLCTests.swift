import XCTest
@testable import ReticulumSwift

final class HDLCTests: XCTestCase {

    func testEscapeUnescapeRoundTrip() {
        let raw = Data([0x01, HDLC.flag, 0x02, HDLC.esc, 0x03])
        let escaped = HDLC.escape(raw)
        XCTAssertEqual(HDLC.unescape(escaped), raw)
    }

    func testFrameDecoderRecoversFrames() {
        let raw1 = Data([0x10, HDLC.flag, 0x20])
        let raw2 = Data([HDLC.esc, 0x30])
        let stream = HDLC.frame(raw1) + HDLC.frame(raw2)

        let decoder = HDLC.FrameDecoder()
        let frames = decoder.feed(stream)
        XCTAssertEqual(frames, [raw1, raw2])
    }

    func testFrameDecoderHandlesSplitChunks() {
        let raw = Data([0xAB, HDLC.flag, 0xCD])
        let framed = HDLC.frame(raw)
        let mid = framed.count / 2
        let decoder = HDLC.FrameDecoder()
        XCTAssertTrue(decoder.feed(framed.prefix(mid)).isEmpty)
        let frames = decoder.feed(framed.suffix(framed.count - mid))
        XCTAssertEqual(frames, [raw])
    }

    func testKISSFrameDecoder() {
        let payload = Data([0x01, KISS.fend, 0x02, KISS.fesc, 0x03])
        let framed = KISS.frameData(payload)
        let decoder = KISS.FrameDecoder()
        let frames = decoder.feed(framed)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].command, KISS.commandData)
        XCTAssertEqual(frames[0].data, payload)
    }
}
