import XCTest
@testable import ReticulumSwift

/// Regression tests for the IFAC outbound (send-path) bug.
///
/// On an IFAC-protected network, the Serial / KISS / AX25KISS / Backbone
/// interfaces previously framed packets WITHOUT applying the IFAC mask, so a
/// Python peer dropped every outbound frame ("IFAC flag not set but should be").
/// Inbound was unwrapped centrally (Transport hooks `rawInboundHandler` →
/// `unwrapIfac`), so the break was asymmetric — a silent one-way link.
///
/// Python applies IFAC centrally in `Transport.transmit`; the Swift port wraps
/// per-interface inside `send()` (mirroring `RNodeInterface` and the
/// TCP/UDP/Auto interfaces). These tests drive each interface's real `send()`
/// path and assert the bytes that hit the wire are IFAC-flagged and unwrap back
/// to the original packet. The existing `IFACTests` only exercise the
/// wrap/unwrap extension methods directly, never through an interface's send
/// path — which is why this regression was invisible.
final class IFACSendPathTests: XCTestCase {

    private let netname = "ifac-send-path"

    private func makePacket() -> Packet {
        Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xAB, count: Constants.truncatedHashLength),
            data: Data("hello IFAC send".utf8)
        )
    }

    /// Assert `wrapped` carries the IFAC flag and unwraps (via `iface`) to `raw`.
    private func assertIfacWrapped(_ wrapped: Data,
                                   unwrapsTo raw: Data,
                                   via iface: any Interface,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) {
        let w = Data(wrapped)   // rebase indices; unwrapIfac indexes absolutely
        XCTAssertEqual(w[0] & 0x80, 0x80,
                       "IFAC flag must be set on the framed packet", file: file, line: line)
        XCTAssertNotEqual(w, raw,
                          "framed bytes must differ from the un-wrapped packet", file: file, line: line)
        XCTAssertEqual(w.count, raw.count + iface.ifacSize,
                       "IFAC code bytes must be inserted", file: file, line: line)
        XCTAssertEqual(iface.unwrapIfac(w), raw,
                       "framed bytes must unwrap to the original packet", file: file, line: line)
    }

    // MARK: - SerialInterface

    func testSerialSendAppliesIfac() throws {
        let mock = MockSerialPort()
        let iface = SerialInterface(name: "S0", port: "/dev/null", transport: mock)
        Transport.configureIfac(on: iface, netname: netname)
        try iface.start()

        let raw = try makePacket().pack()
        try iface.send(makePacket())

        let framed = try XCTUnwrap(mock.writtenData.last, "send must write to the serial port")
        let wrapped = try XCTUnwrap(HDLC.FrameDecoder().feed(framed).first,
                                    "written bytes must form a complete HDLC frame")
        assertIfacWrapped(wrapped, unwrapsTo: raw, via: iface)
    }

    func testSerialSendWithoutIfacIsUnflagged() throws {
        let mock = MockSerialPort()
        let iface = SerialInterface(name: "S0", port: "/dev/null", transport: mock)
        try iface.start()   // no IFAC configured

        let raw = try makePacket().pack()
        try iface.send(makePacket())

        let framed = try XCTUnwrap(mock.writtenData.last)
        let onWire = try XCTUnwrap(HDLC.FrameDecoder().feed(framed).first)
        XCTAssertEqual(Data(onWire), raw,
                       "without IFAC, framing must be identity (no flag, no mask)")
    }

    // MARK: - KISSInterface

    func testKISSSendAppliesIfac() throws {
        let mock = MockSerialPort()
        let iface = KISSInterface(name: "K0", port: "/dev/null", transport: mock)
        Transport.configureIfac(on: iface, netname: netname)
        try iface.start()

        let raw = try makePacket().pack()
        try iface.send(makePacket())

        // start() writes KISS config commands first; the data frame is last.
        let framed = try XCTUnwrap(mock.writtenData.last, "send must write to the TNC")
        let frame = try XCTUnwrap(KISS.FrameDecoder().feed(framed).first,
                                  "written bytes must form a complete KISS frame")
        XCTAssertEqual(frame.command, KISS.cmdData, "data must be sent as a CMD_DATA frame")
        assertIfacWrapped(frame.data, unwrapsTo: raw, via: iface)
    }

    // MARK: - AX25KISSInterface

    func testAX25KISSSendAppliesIfac() throws {
        let mock = MockSerialPort()
        let iface = try AX25KISSInterface(name: "AX0", port: "/dev/null",
                                          callsign: "NOCALL", ssid: 0, transport: mock)
        Transport.configureIfac(on: iface, netname: netname)
        try iface.start()

        let raw = try makePacket().pack()
        try iface.send(makePacket())

        let framed = try XCTUnwrap(mock.writtenData.last, "send must write to the TNC")
        let frame = try XCTUnwrap(KISS.FrameDecoder().feed(framed).first,
                                  "written bytes must form a complete KISS frame")
        XCTAssertEqual(frame.command, KISS.cmdData)
        // The AX.25 UI-frame header precedes the IFAC-wrapped packet (Python
        // wraps IFAC before prepending the AX.25 header).
        XCTAssertGreaterThan(frame.data.count, AX25.headerSize)
        let wrapped = Data(frame.data.dropFirst(AX25.headerSize))
        assertIfacWrapped(wrapped, unwrapsTo: raw, via: iface)
    }

    // MARK: - BackboneInterface

    func testBackboneConfigureIfacStoresKey() {
        // Regression: BackboneInterface had NO IFAC stored properties, so the
        // protocol's no-op default setter silently discarded the key.
        let iface = BackboneInterface(name: "B0", host: "127.0.0.1", port: 4242)
        XCTAssertNil(iface.ifacKey, "no IFAC before configuration")
        Transport.configureIfac(on: iface, netname: netname)
        XCTAssertNotNil(iface.ifacKey, "configureIfac must persist the key on BackboneInterface")
    }

    func testBackboneSendPathAppliesIfac() throws {
        let iface = BackboneInterface(name: "B0", host: "127.0.0.1", port: 4242)
        Transport.configureIfac(on: iface, netname: netname)

        let raw = try makePacket().pack()
        // `framePacketBytes` is exactly the transformation `send(_:)` applies to
        // the on-wire bytes (IFAC-wrap then HDLC-frame), factored out so it is
        // testable without a live NWConnection.
        let framed = iface.framePacketBytes(raw)
        let wrapped = try XCTUnwrap(HDLC.FrameDecoder().feed(framed).first)
        assertIfacWrapped(wrapped, unwrapsTo: raw, via: iface)
    }

    func testBackboneFramePacketBytesWithoutIfacIsUnflagged() throws {
        let iface = BackboneInterface(name: "B0", host: "127.0.0.1", port: 4242)
        let raw = try makePacket().pack()
        let framed = iface.framePacketBytes(raw)
        let onWire = try XCTUnwrap(HDLC.FrameDecoder().feed(framed).first)
        XCTAssertEqual(Data(onWire), raw, "without IFAC, framing must be identity")
    }

    // MARK: - Cross-interface interop (wrap on KISS, unwrap on TCP)

    /// The IFAC mask is interface-agnostic: a frame wrapped by one interface
    /// type must unwrap on any other interface configured with the same network
    /// name / passphrase. This is what makes a mixed Swift mesh (KISS radio +
    /// TCP backbone) interoperate with Python on an IFAC-protected network.
    func testCrossInterfaceWrapKISSUnwrapTCP() throws {
        let mock = MockSerialPort()
        let kiss = KISSInterface(name: "K0", port: "/dev/null", transport: mock)
        Transport.configureIfac(on: kiss, netname: "shared-mesh", netkey: "s3cr3t")
        try kiss.start()

        let tcp = TCPClientInterface(name: "T0", host: "127.0.0.1", port: 4242)
        Transport.configureIfac(on: tcp, netname: "shared-mesh", netkey: "s3cr3t")

        let raw = try makePacket().pack()
        try kiss.send(makePacket())

        let framed = try XCTUnwrap(mock.writtenData.last)
        let frame = try XCTUnwrap(KISS.FrameDecoder().feed(framed).first)
        let wrapped = Data(frame.data)

        XCTAssertEqual(tcp.unwrapIfac(wrapped), raw,
                       "frame wrapped on KISS must unwrap on TCP with the same IFAC credentials")
    }

    func testCrossInterfaceMismatchedNetkeyRejected() throws {
        let mock = MockSerialPort()
        let kiss = KISSInterface(name: "K0", port: "/dev/null", transport: mock)
        Transport.configureIfac(on: kiss, netname: "shared-mesh", netkey: "s3cr3t")
        try kiss.start()

        let tcp = TCPClientInterface(name: "T0", host: "127.0.0.1", port: 4242)
        Transport.configureIfac(on: tcp, netname: "shared-mesh", netkey: "wrong-key")

        try kiss.send(makePacket())
        let framed = try XCTUnwrap(mock.writtenData.last)
        let frame = try XCTUnwrap(KISS.FrameDecoder().feed(framed).first)

        XCTAssertNil(tcp.unwrapIfac(Data(frame.data)),
                     "a frame wrapped with a different netkey must be rejected")
    }
}
