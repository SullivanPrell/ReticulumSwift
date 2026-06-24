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

    func testLocalInterfaceIsLocalClient() {
        let transport = Transport()
        let iface = LocalInterface(name: "lo0test")
        XCTAssertTrue(transport.isLocalClientInterface(iface))
    }

    func testUDPInterfaceIsNotLocalClient() {
        let transport = Transport()
        let iface = UDPInterface(name: "udp0")
        XCTAssertFalse(transport.isLocalClientInterface(iface))
    }

    func testFromLocalClientWithLocalInterface() {
        let transport = Transport()
        let iface = LocalInterface(name: "lo0fromLocal")
        XCTAssertTrue(transport.fromLocalClient(interface: iface))
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
