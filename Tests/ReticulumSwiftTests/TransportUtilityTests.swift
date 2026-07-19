import XCTest
@testable import ReticulumSwift

final class TransportUtilityTests: XCTestCase {

    // MARK: - timebaseFromRandomBlob

    func testTimebaseFromRandomBlobExtractsBytesEight() {
        // bytes [5..9] big-endian = the timestamp
        var blob = Data(repeating: 0, count: 10)
        // Encode value 0x0102030405 in bytes 5..9
        blob[5] = 0x01; blob[6] = 0x02; blob[7] = 0x03; blob[8] = 0x04; blob[9] = 0x05
        let expected = TimeInterval(0x0102030405)
        XCTAssertEqual(Transport.timebaseFromRandomBlob(blob), expected)
    }

    func testTimebaseFromRandomBlobZeroForShortData() {
        let blob = Data(repeating: 0, count: 5)
        XCTAssertEqual(Transport.timebaseFromRandomBlob(blob), 0)
    }

    func testTimebaseFromRandomBlobIgnoresBytesBefore5() {
        var blob = Data(repeating: 0xFF, count: 10) // fill everything with 0xFF
        // Zero out bytes 5..9
        for i in 5..<10 { blob[i] = 0x00 }
        XCTAssertEqual(Transport.timebaseFromRandomBlob(blob), 0)
    }

    // MARK: - timebaseFromRandomBlobs

    func testTimebaseFromRandomBlobsReturnsMax() {
        var blob1 = Data(repeating: 0, count: 10)
        blob1[9] = 100
        var blob2 = Data(repeating: 0, count: 10)
        blob2[9] = 200
        var blob3 = Data(repeating: 0, count: 10)
        blob3[9] = 50
        let result = Transport.timebaseFromRandomBlobs([blob1, blob2, blob3])
        XCTAssertEqual(result, 200)
    }

    func testTimebaseFromRandomBlobsEmptyListReturnsZero() {
        XCTAssertEqual(Transport.timebaseFromRandomBlobs([]), 0)
    }

    // MARK: - isLocalClientInterface / fromLocalClient / interfaceToSharedInstance
    //
    // Semantics mirror Python RNS exactly (Transport.is_local_client_interface /
    // interface_to_shared_instance):
    //   * is_local_client_interface  → the SERVER side: an interface serving a
    //     locally-connected shared-instance client. In Swift that is a
    //     `LocalClientServingInterface` (e.g. PosixTCPServer on port 37428).
    //   * interface_to_shared_instance → the CLIENT side: this node's own
    //     connection *to* a shared instance. In Swift that is `LocalInterface`.
    // A `LocalInterface` is therefore NOT a local-client interface (it is the
    // client end), and a serving interface is NOT an interface-to-shared-instance.

    /// Minimal stand-in for PosixTCPServer's serving role.
    private final class MockServingInterface: Interface, LocalClientServingInterface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        var clientCount: Int
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String, clientCount: Int = 1) { self.name = name; self.clientCount = clientCount }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }

    func testServingInterfaceIsLocalClient() {
        let transport = Transport()
        let iface = MockServingInterface(name: "SharedInstance[37428]")
        XCTAssertTrue(transport.isLocalClientInterface(iface),
                      "A LocalClientServingInterface (the server side) IS a local-client interface")
        XCTAssertTrue(transport.fromLocalClient(interface: iface))
    }

    func testLocalInterfaceIsNotLocalClient() {
        // A LocalInterface is this node's connection TO a shared instance (client
        // side), which Python classifies as interface_to_shared_instance, NOT as a
        // local-client interface.
        let transport = Transport()
        let iface = LocalInterface(name: "lo0test")
        XCTAssertFalse(transport.isLocalClientInterface(iface))
        XCTAssertFalse(transport.fromLocalClient(interface: iface))
    }

    func testUDPInterfaceIsNotLocalClient() {
        let transport = Transport()
        let iface = UDPInterface(name: "udp0")
        XCTAssertFalse(transport.isLocalClientInterface(iface))
    }

    func testInterfaceToSharedInstanceLocalInterface() {
        let transport = Transport()
        let iface = LocalInterface(name: "lo0shared")
        XCTAssertTrue(transport.interfaceToSharedInstance(iface))
    }

    func testInterfaceToSharedInstanceUDP() {
        let transport = Transport()
        let iface = UDPInterface(name: "udp0shared")
        XCTAssertFalse(transport.interfaceToSharedInstance(iface))
    }

    func testServingInterfaceIsNotInterfaceToSharedInstance() {
        let transport = Transport()
        let iface = MockServingInterface(name: "SharedInstance[37428]")
        XCTAssertFalse(transport.interfaceToSharedInstance(iface))
    }

    // MARK: - voidQueues

    func testVoidQueuesClearsReceipts() {
        let transport = Transport()
        // inject a receipt via test helper to verify clearing
        let hash = Data(repeating: 0xAB, count: 32)
        let receipt = PacketReceipt(testHash: hash)
        transport.testInjectReceipt(receipt)
        XCTAssertEqual(transport.testReceiptCount(), 1)
        transport.voidQueues()
        XCTAssertEqual(transport.testReceiptCount(), 0)
    }

    // MARK: - detachInterfaces

    func testDetachInterfacesStopsAllInterfaces() {
        let transport = Transport()
        let udp1 = UDPInterface(name: "udp1detach")
        let udp2 = UDPInterface(name: "udp2detach")
        transport.register(interface: udp1)
        transport.register(interface: udp2)
        transport.detachInterfaces()
        XCTAssertFalse(udp1.isOnline)
        XCTAssertFalse(udp2.isOnline)
    }
}
