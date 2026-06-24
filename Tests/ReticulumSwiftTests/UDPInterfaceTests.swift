import XCTest
@testable import ReticulumSwift

final class UDPInterfaceTests: XCTestCase {

    func testDatagramRoundTripBetweenTwoUDPInterfaces() throws {
        // Pick two different ports on loopback. Use high range to avoid
        // collisions in shared CI environments.
        let portA: UInt16 = UInt16.random(in: 40_000...50_000)
        let portB: UInt16 = portA + 1

        let a = UDPInterface(
            name: "A",
            listenPort: portA,
            forwardHost: "127.0.0.1",
            forwardPort: portB
        )
        let b = UDPInterface(
            name: "B",
            listenPort: portB,
            forwardHost: "127.0.0.1",
            forwardPort: portA
        )

        let received = expectation(description: "B receives")
        var got: Packet?
        b.inboundHandler = { pkt, _ in
            got = pkt
            received.fulfill()
        }

        try a.start()
        try b.start()
        defer { a.stop(); b.stop() }

        // Give the sockets a moment to actually bind before we fire.
        Thread.sleep(forTimeInterval: 0.05)

        let pkt = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xCC, count: Constants.truncatedHashLength),
            data: Data("udp-hello".utf8)
        )
        try a.send(pkt)

        wait(for: [received], timeout: 2.0)
        XCTAssertEqual(got?.data, Data("udp-hello".utf8))
        XCTAssertEqual(got?.destinationHash, pkt.destinationHash)
    }
}
