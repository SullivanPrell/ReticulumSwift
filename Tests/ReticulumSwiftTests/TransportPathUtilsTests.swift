import XCTest
@testable import ReticulumSwift

/// Tests for Transport path/latency utility methods that mirror
/// Python's Transport.next_hop_interface_bitrate, first_hop_timeout,
/// extra_link_proof_timeout, and next_hop_interface_hw_mtu.
final class TransportPathUtilsTests: XCTestCase {

    // MARK: - Mock interface

    final class MockInterface: Interface {
        var name: String
        var bitrate: Int
        var isOnline: Bool = true
        var hwMtu: Int?
        var autoconfigureMtu: Bool = false
        var fixedMtu: Bool = false
        var inboundHandler: ((Packet, any Interface) -> Void)?

        init(name: String, bitrate: Int = 10_000_000, hwMtu: Int? = nil,
             autoconfigure: Bool = false, fixed: Bool = false) {
            self.name = name
            self.bitrate = bitrate
            self.hwMtu = hwMtu
            self.autoconfigureMtu = autoconfigure
            self.fixedMtu = fixed
        }

        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {}
    }

    func makeTransportWithPath(bitrate: Int = 10_000_000, hwMtu: Int? = nil,
                                autoconfigure: Bool = false, fixed: Bool = false)
        -> (Transport, Data, MockInterface)
    {
        let transport = Transport()
        let iface = MockInterface(name: "test0", bitrate: bitrate,
                                  hwMtu: hwMtu, autoconfigure: autoconfigure, fixed: fixed)
        transport.register(interface: iface)

        let destHash = Data(repeating: 0xAB, count: 16)
        transport.restore(
            path: Transport.PathEntry(
                destinationHash: destHash,
                nextHopInterfaceName: "test0",
                hops: 1,
                lastHeard: Date(),
                identityHash: Data(repeating: 0, count: 16)
            ),
            forDestination: destHash
        )
        return (transport, destHash, iface)
    }

    // MARK: - nextHopInterfaceBitrate

    func testNextHopInterfaceBitrateKnownPath() {
        let (transport, destHash, _) = makeTransportWithPath(bitrate: 9_600)
        XCTAssertEqual(transport.nextHopInterfaceBitrate(for: destHash), 9_600)
    }

    func testNextHopInterfaceBitrateNilForUnknownPath() {
        let transport = Transport()
        let unknown = Data(repeating: 0xFF, count: 16)
        XCTAssertNil(transport.nextHopInterfaceBitrate(for: unknown))
    }

    func testNextHopInterfaceBitrateNilForOfflineInterface() {
        let (transport, destHash, iface) = makeTransportWithPath(bitrate: 1_200)
        iface.isOnline = false
        // Interface exists but is offline — still returns bitrate (Python does not filter by online)
        XCTAssertEqual(transport.nextHopInterfaceBitrate(for: destHash), 1_200)
    }

    // MARK: - nextHopInterfaceHwMtu

    func testNextHopInterfaceHwMtuWithAutoconfigure() {
        let (transport, destHash, _) = makeTransportWithPath(hwMtu: 262144, autoconfigure: true)
        XCTAssertEqual(transport.nextHopInterfaceHwMtu(for: destHash), 262144)
    }

    func testNextHopInterfaceHwMtuWithFixedMtu() {
        let (transport, destHash, _) = makeTransportWithPath(hwMtu: 1064, fixed: true)
        XCTAssertEqual(transport.nextHopInterfaceHwMtu(for: destHash), 1064)
    }

    func testNextHopInterfaceHwMtuNilWhenNeitherFlag() {
        let (transport, destHash, _) = makeTransportWithPath(hwMtu: 1064,
                                                              autoconfigure: false, fixed: false)
        XCTAssertNil(transport.nextHopInterfaceHwMtu(for: destHash))
    }

    func testNextHopInterfaceHwMtuNilForUnknownPath() {
        let transport = Transport()
        let unknown = Data(repeating: 0xCC, count: 16)
        XCTAssertNil(transport.nextHopInterfaceHwMtu(for: unknown))
    }

    // MARK: - firstHopTimeout

    func testFirstHopTimeoutDefaultWhenNoPath() {
        let transport = Transport()
        let unknown = Data(repeating: 0x11, count: 16)
        XCTAssertEqual(transport.firstHopTimeout(for: unknown), Constants.defaultPerHopTimeout)
    }

    func testFirstHopTimeoutDefaultWhenBitrateIsZero() {
        let (transport, destHash, _) = makeTransportWithPath(bitrate: 0)
        // bitrate=0 → division by zero guard → falls back to default
        XCTAssertEqual(transport.firstHopTimeout(for: destHash), Constants.defaultPerHopTimeout)
    }

    func testFirstHopTimeoutCalculatedFromBitrate() {
        // Python: MTU * (1/bitrate * 8) + DEFAULT_PER_HOP_TIMEOUT
        // = 500 * (8/bitrate) + 6
        let bitrate = 1_200
        let (transport, destHash, _) = makeTransportWithPath(bitrate: bitrate)
        let expected = Double(Constants.mtu) * (8.0 / Double(bitrate)) + Constants.defaultPerHopTimeout
        XCTAssertEqual(transport.firstHopTimeout(for: destHash), expected, accuracy: 1e-9)
    }

    // MARK: - extraLinkProofTimeout

    func testExtraLinkProofTimeoutZeroForNilInterface() {
        XCTAssertEqual(Transport.extraLinkProofTimeout(for: nil), 0.0)
    }

    func testExtraLinkProofTimeoutZeroForZeroBitrate() {
        let iface = MockInterface(name: "x", bitrate: 0)
        XCTAssertEqual(Transport.extraLinkProofTimeout(for: iface), 0.0)
    }

    func testExtraLinkProofTimeoutCalculated() {
        // Python: ((1/bitrate)*8) * MTU
        let bitrate = 9_600
        let iface = MockInterface(name: "x", bitrate: bitrate)
        let expected = (8.0 / Double(bitrate)) * Double(Constants.mtu)
        XCTAssertEqual(Transport.extraLinkProofTimeout(for: iface), expected, accuracy: 1e-9)
    }

    // MARK: - defaultPerHopTimeout constant

    func testDefaultPerHopTimeoutIsCorrect() {
        // Python: Reticulum.DEFAULT_PER_HOP_TIMEOUT = 6
        XCTAssertEqual(Constants.defaultPerHopTimeout, 6.0)
    }

    // MARK: - Interface hwMtu defaults

    func testInterfaceHwMtuDefaultIsNil() {
        let iface = MockInterface(name: "y")
        // Protocol default should be nil
        let asProtocol: any Interface = iface
        XCTAssertNil(asProtocol.hwMtu)
    }

    func testInterfaceAutoconfigureMtuDefaultIsFalse() {
        let iface = MockInterface(name: "y")
        let asProtocol: any Interface = iface
        XCTAssertFalse(asProtocol.autoconfigureMtu)
    }

    func testInterfaceFixedMtuDefaultIsFalse() {
        let iface = MockInterface(name: "y")
        let asProtocol: any Interface = iface
        XCTAssertFalse(asProtocol.fixedMtu)
    }

    // MARK: - TCPClientInterface hwMtu

    func testTCPClientInterfaceHwMtu() {
        let tcp = TCPClientInterface(name: "tcp0", host: "127.0.0.1", port: 4242)
        XCTAssertEqual(tcp.hwMtu, 262144)
        XCTAssertTrue(tcp.autoconfigureMtu)
    }

    // MARK: - UDPInterface hwMtu

    func testUDPInterfaceHwMtu() {
        let udp = UDPInterface(name: "udp0", listenPort: 4243)
        XCTAssertEqual(udp.hwMtu, 1064)
    }
}
