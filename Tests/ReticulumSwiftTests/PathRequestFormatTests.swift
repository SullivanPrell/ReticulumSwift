import XCTest
@testable import ReticulumSwift

/// Tests for path request packet format matching Python reference.
/// Python: if transport_enabled: body = destHash + transport_id + tag
///         else:                  body = destHash + tag
final class PathRequestFormatTests: XCTestCase {

    final class CapturingInterface: Interface {
        var name: String = "capture"
        var bitrate: Int = 0
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var captured: [Packet] = []

        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws { captured.append(packet) }
    }

    func testPathRequestIncludesTransportIDWhenEnabled() throws {
        let t = Transport()
        t.transportEnabled = true
        let iface = CapturingInterface()
        t.register(interface: iface)

        let destHash = Data(repeating: 0xAA, count: 16)
        try t.requestPath(for: destHash)

        let sent = try XCTUnwrap(iface.captured.first, "should have sent a path request")
        let body = sent.data

        // When transport enabled: body = destHash(16) + transportInstanceID(16) + tag(16) = 48 bytes
        XCTAssertEqual(body.count, 48, "transport-enabled path request body must be 48 bytes")
        XCTAssertEqual(Data(body.prefix(16)), destHash, "first 16 bytes must be destination hash")
        XCTAssertEqual(Data(body[16..<32]), t.transportInstanceID, "next 16 bytes must be transport instance ID")
    }

    func testPathRequestOmitsTransportIDWhenDisabled() throws {
        let t = Transport()
        t.transportEnabled = false
        let iface = CapturingInterface()
        t.register(interface: iface)

        let destHash = Data(repeating: 0xBB, count: 16)
        try t.requestPath(for: destHash)

        let sent = try XCTUnwrap(iface.captured.first)
        let body = sent.data

        // When transport disabled: body = destHash(16) + tag(16) = 32 bytes
        XCTAssertEqual(body.count, 32, "transport-disabled path request body must be 32 bytes")
        XCTAssertEqual(Data(body.prefix(16)), destHash, "first 16 bytes must be destination hash")
    }

    func testPathRequestSentAsPlainBroadcast() throws {
        let t = Transport()
        let iface = CapturingInterface()
        t.register(interface: iface)

        try t.requestPath(for: Data(repeating: 0xCC, count: 16))

        let sent = try XCTUnwrap(iface.captured.first)
        XCTAssertEqual(sent.packetType, .data)
        XCTAssertEqual(sent.destinationType, .plain)
        XCTAssertEqual(sent.transportType, .broadcast)
        XCTAssertEqual(sent.destinationHash, Transport.pathRequestDestinationHash)
    }
}
