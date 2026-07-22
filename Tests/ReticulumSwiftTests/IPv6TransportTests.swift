import XCTest
@testable import ReticulumSwift

/// Proves Reticulum rides over IPv6 — the transport a Yggdrasil node provides.
///
/// Reticulum-over-Yggdrasil (both Python and Swift) is simply TCP/Backbone over
/// the node's IPv6 address: Python config uses `device = tun0` /
/// `target_host = 201:…`. The Yggdrasil address space is `0200::/7`. Here we
/// exercise IPv6 loopback (`::1`), which is the same code path — `NWEndpoint.Host`
/// parses a bare IPv6 literal into an `.ipv6` host and `NWListener` binds on IPv6
/// too — so a green test here means the existing TCP/Backbone interfaces already
/// work over a Yggdrasil address once the tunnel is up.
final class IPv6TransportTests: XCTestCase {

    func testPacketExchangeOverIPv6Loopback() throws {
        let port: UInt16 = UInt16.random(in: 45_000...55_000)

        let server = TCPServerInterface(name: "ygg-server", port: port)
        let client = TCPClientInterface(name: "ygg-client", host: "::1", port: port)

        let received = expectation(description: "server receives a packet over IPv6")
        var got: Packet?

        // Transport normally wires *and retains* the spawned per-connection
        // sub-interface (it is only weakly referenced internally). Here we do both:
        // retain it and install an inbound handler ourselves. `Interface` is a
        // class-constrained protocol, so we can set the property on the value.
        var serverClient: (any Interface)?
        server.onClientConnected = { iface in
            serverClient = iface
            iface.inboundHandler = { pkt, _ in
                got = pkt
                received.fulfill()
            }
        }

        try server.start()
        try client.start()
        defer { client.stop(); server.stop() }

        // Wait for the IPv6 TCP connection to come up.
        let deadline = Date().addingTimeInterval(3.0)
        while !client.isOnline && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(client.isOnline, "client must connect to the server over IPv6 (::1)")

        let pkt = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xAB, count: Constants.truncatedHashLength),
            data: Data("yggdrasil-over-ipv6".utf8)
        )
        try client.send(pkt)

        wait(for: [received], timeout: 3.0)
        XCTAssertNotNil(serverClient, "server must have spawned a per-connection sub-interface")
        XCTAssertEqual(got?.data, Data("yggdrasil-over-ipv6".utf8))
        XCTAssertEqual(got?.destinationHash, pkt.destinationHash)
    }

    /// A bare Yggdrasil global address literal (`0200::/7`) must be accepted and
    /// retained verbatim by the client/backbone interfaces so it flows unchanged
    /// into `NWEndpoint.Host`.
    func testHostLiteralRetainsGlobalYggdrasilAddress() {
        let ygg = "201:5d78:af73:5caf:a4de:a79f:3278:71e5"
        let client = TCPClientInterface(name: "ygg-peer", host: ygg, port: 4242)
        XCTAssertEqual(client.host, ygg)
        let backbone = BackboneInterface(name: "ygg-bb", host: ygg, port: 4343)
        XCTAssertEqual(backbone.host, ygg)
    }
}
