import XCTest
@testable import ReticulumSwift

/// RNS 1.5.0/1.5.2 changes around empty frames on the shared-instance and TCP paths.
///
/// Python 1.5.0 rewrote `LocalClientInterface.send_keepalive` to emit a bare `7E 7E` — an
/// empty HDLC frame — and 1.5.2 added `if not data: return` at the top of `process_incoming`
/// on the TCP and I2P interfaces. Neither is a change this port has to *make*: Swift already
/// drops empty frames in the deframer, and `Packet.unpack` cannot parse an empty payload. What
/// the tests below do is pin that, because the two implementations now depend on it in a way
/// they previously did not — an Android Python client on a Swift shared instance sends these
/// keepalives, and a decoder that mishandled them would desync the whole stream.
final class LocalInterfaceKeepaliveTests: XCTestCase {

    /// A minimal but structurally valid packet: HEADER_1, 16-byte destination, one context
    /// byte, a payload. Long enough that Python's own deframer (`frame_len > HEADER_MINSIZE`)
    /// would also pass it, so the fixtures below describe frames both stacks accept.
    private static var realPacket: Data {
        Data([0x00, 0x00]) + Data(repeating: 0xAB, count: Constants.truncatedHashLength)
            + Data([0x00]) + Data("hello".utf8)
    }

    private func decode(_ stream: Data) -> [Data] {
        HDLC.FrameDecoder().feed(stream)
    }

    // MARK: - The keepalive frame itself

    func testABareFlagPairYieldsNoFrame() {
        // `data = bytes([HDLC.FLAG])+bytes([HDLC.FLAG])` (`LocalInterface.py:198`). Python's
        // deframer discards it via `frame_len > HEADER_MINSIZE`; this port discards it because
        // the accumulated buffer is empty. Same outcome, and it has to be — a keepalive that
        // surfaced as a frame would be handed to the transport core as a zero-byte packet.
        XCTAssertEqual(decode(Data([HDLC.flag, HDLC.flag])), [],
                       "the shared-instance keepalive is an empty frame and must be absorbed")
    }

    func testRepeatedKeepalivesYieldNoFrames() {
        XCTAssertEqual(decode(Data([HDLC.flag, HDLC.flag, HDLC.flag, HDLC.flag])), [],
                       "keepalives arrive on a timer, so several can coalesce in one read")
    }

    func testAKeepaliveBetweenTwoRealFramesDisturbsNeither() {
        // The case that actually costs something if it is wrong. A stray flag pair mid-stream
        // must not shift the decoder's notion of where the next frame starts; if it did, every
        // subsequent packet from that peer would be garbage rather than just one.
        let stream = HDLC.frame(Self.realPacket)
            + Data([HDLC.flag, HDLC.flag])
            + HDLC.frame(Self.realPacket)

        XCTAssertEqual(decode(stream), [Self.realPacket, Self.realPacket],
                       "both real frames must survive, byte-identical, either side of the "
                       + "keepalive — a desync here corrupts the rest of the connection")
    }

    func testAKeepaliveSplitAcrossTwoReadsIsStillAbsorbed() {
        // `recv(4096)` boundaries fall wherever the kernel puts them, so the two flag bytes
        // routinely arrive in separate reads. The decoder is stateful precisely for this.
        let decoder = HDLC.FrameDecoder()
        XCTAssertEqual(decoder.feed(Data([HDLC.flag])), [])
        XCTAssertEqual(decoder.feed(Data([HDLC.flag])), [])
        XCTAssertEqual(decoder.feed(HDLC.frame(Self.realPacket)), [Self.realPacket],
                       "the frame following a split keepalive must still decode")
    }

    // MARK: - Empty payloads below the deframer (`process_incoming`, 1.5.2)

    func testAnEmptyPayloadCannotBeParsedAsAPacket() {
        // `if not data: return` (`TCPInterface.py:305`, `I2PInterface.py:540`). This port has no
        // equivalent guard and needs none: the only consumer of raw interface bytes is
        // `Packet.unpack`, which rejects anything shorter than a complete header. Pinned here
        // so that the guard's absence stays justified rather than merely true.
        XCTAssertThrowsError(try Packet.unpack(Data()))
    }

    func testAFrameShorterThanAHeaderCannotBeParsedAsAPacket() {
        // Python's deframer drops these before `process_incoming` ever sees them
        // (`frame_len > HEADER_MINSIZE`); this port lets them through the deframer and rejects
        // them at unpack. Different seam, identical outcome — nothing reaches the core.
        for length in 1...(Constants.headerMinSize - 1) {
            XCTAssertThrowsError(try Packet.unpack(Data(repeating: 0x00, count: length)),
                                 "a \(length)-byte frame is shorter than a header")
        }
    }

    // MARK: - `ifac_size` (`LocalInterface.py:64,364`)

    func testLocalInterfaceUsesTheSixteenByteDefaultIfacSize() {
        // 1.5.0 hoisted `DEFAULT_IFAC_SIZE = 16` onto the `Interface` base class and made both
        // LocalInterface halves set `ifac_size` from it explicitly — previously they inherited
        // no value at all. 16 bytes is what a Swift shared instance already uses, so a Python
        // 1.5.x client and this port agree on the IFAC field width.
        let iface = LocalInterface(name: "shared", port: 37428)
        XCTAssertEqual(iface.ifacSize, 16,
                       "an IFAC-enabled shared instance and its clients must agree on the "
                       + "code width or every frame between them fails verification")
        XCTAssertEqual(iface.ifacSize, Constants.defaultIfacSize)
    }
}
