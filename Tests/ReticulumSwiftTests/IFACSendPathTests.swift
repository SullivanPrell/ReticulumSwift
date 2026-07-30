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
        configureIfacFromConfigBlock(on: iface, netname: netname)
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
        configureIfacFromConfigBlock(on: iface, netname: netname)
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
        configureIfacFromConfigBlock(on: iface, netname: netname)
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
        configureIfacFromConfigBlock(on: iface, netname: netname)
        XCTAssertNotNil(iface.ifacKey, "configureIfac must persist the key on BackboneInterface")
    }

    func testBackboneSendPathAppliesIfac() throws {
        let iface = BackboneInterface(name: "B0", host: "127.0.0.1", port: 4242)
        configureIfacFromConfigBlock(on: iface, netname: netname)

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

    /// The IFAC mask is interface-agnostic **in its derivation** — same network name and
    /// passphrase, same key — but its *length* is per-interface-class, so two classes only
    /// cross-verify when `ifac_size` is configured explicitly on both.
    ///
    /// This test previously claimed the opposite ("must unwrap on any other interface configured
    /// with the same network name / passphrase") and passed, because it called
    /// `Transport.configureIfac` directly and that call's `size:` parameter defaulted to a uniform
    /// 16 — overriding each class's own default. Python does not: `Reticulum.py:917-918` assigns
    /// `interface.ifac_size = interface.DEFAULT_IFAC_SIZE` whenever the config omits the key, and
    /// that is 8 for the radio family and 16 for TCP (`bugs/025` task 1.5). So the test asserted
    /// something the reference does not do, and its construction is what hid the per-class
    /// difference.
    ///
    /// Nothing in the protocol requires cross-class unwrapping, either: IFAC masks a frame on the
    /// wire of *one* interface. A frame arriving over TCP is unmasked there and re-masked by KISS
    /// when it is forwarded. These are separate links.
    func testCrossInterfaceUnwrapRequiresAMatchingConfiguredIFACSize() throws {
        // Without an explicit `ifac_size`, each class keeps its own default and the masks differ.
        let defaultsMock = MockSerialPort()
        let defaultKiss = KISSInterface(name: "K0", port: "/dev/null", transport: defaultsMock)
        configureIfacFromConfigBlock(on: defaultKiss, netname: "shared-mesh", netkey: "s3cr3t")
        try defaultKiss.start()
        let defaultTcp = TCPClientInterface(name: "T0", host: "127.0.0.1", port: 4242)
        configureIfacFromConfigBlock(on: defaultTcp, netname: "shared-mesh", netkey: "s3cr3t")

        XCTAssertEqual(defaultKiss.ifacSize, 8,  "KISSInterface.py:63 — DEFAULT_IFAC_SIZE = 8")
        XCTAssertEqual(defaultTcp.ifacSize, 16,  "TCPInterface.py:77 — DEFAULT_IFAC_SIZE = 16")
        XCTAssertNil(defaultTcp.unwrapIfac(try wrapOnKiss(defaultKiss, mock: defaultsMock)),
                     "different mask lengths must not cross-verify, as in Python")

        // With `ifac_size` set on both — what an operator spanning a mixed segment must do — the
        // key derivation is identical and the frame crosses.
        let mock = MockSerialPort()
        let kiss = KISSInterface(name: "K1", port: "/dev/null", transport: mock)
        configureIfacFromConfigBlock(on: kiss, netname: "shared-mesh", netkey: "s3cr3t",
                                     sizeBits: 128)
        try kiss.start()
        let tcp = TCPClientInterface(name: "T1", host: "127.0.0.1", port: 4243)
        configureIfacFromConfigBlock(on: tcp, netname: "shared-mesh", netkey: "s3cr3t",
                                     sizeBits: 128)

        XCTAssertEqual(kiss.ifacSize, 16)
        XCTAssertEqual(tcp.ifacSize, 16)
        let raw = try makePacket().pack()
        XCTAssertEqual(tcp.unwrapIfac(try wrapOnKiss(kiss, mock: mock)), raw,
                       "with a matching configured ifac_size the derivation is identical and the "
                       + "frame unwraps")
    }

    /// Send a packet on a KISS interface and recover the IFAC-wrapped frame it put on the wire.
    private func wrapOnKiss(_ kiss: KISSInterface, mock: MockSerialPort) throws -> Data {
        try kiss.send(makePacket())
        let framed = try XCTUnwrap(mock.writtenData.last)
        return Data(try XCTUnwrap(KISS.FrameDecoder().feed(framed).first).data)
    }

    /// A wrong netkey is rejected. `ifac_size` is set explicitly on both sides so the *only*
    /// difference between them is the passphrase — otherwise a mismatched mask length would
    /// reject the frame regardless and this would pass without testing the key at all.
    func testCrossInterfaceMismatchedNetkeyRejected() throws {
        let mock = MockSerialPort()
        let kiss = KISSInterface(name: "K0", port: "/dev/null", transport: mock)
        configureIfacFromConfigBlock(on: kiss, netname: "shared-mesh", netkey: "s3cr3t",
                                     sizeBits: 128)
        try kiss.start()

        let tcp = TCPClientInterface(name: "T0", host: "127.0.0.1", port: 4242)
        configureIfacFromConfigBlock(on: tcp, netname: "shared-mesh", netkey: "wrong-key",
                                     sizeBits: 128)
        XCTAssertEqual(kiss.ifacSize, tcp.ifacSize, "the netkey must be the only difference")

        XCTAssertNil(tcp.unwrapIfac(try wrapOnKiss(kiss, mock: mock)),
                     "a frame wrapped with a different netkey must be rejected")
    }
}
