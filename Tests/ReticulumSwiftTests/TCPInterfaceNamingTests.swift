import XCTest
@testable import ReticulumSwift

/// The join between what a TCP interface *calls itself* and what `rnstatus` does with
/// that name — the seam bug 013 fell through.
///
/// `rnstatus` hides interfaces whose name starts with one of a fixed set of prefixes
/// (`rnstatus.py:395-402`), because those denote sub-interfaces spawned by a listener
/// rather than anything the operator configured. One of them is `TCPInterface[Client`.
///
/// Python produces that prefix only for a *server-spawned* client, because the spawned
/// interface is constructed with `name = "Client on "+servername`
/// (`TCPInterface.py:590`) and `__str__` is `"TCPInterface["+name+"/"+ip+":"+port+"]"`
/// for both cases (`TCPInterface.py:456-462`). A configured client carries the config
/// block's own name and is therefore never hidden.
///
/// ReticulumSwift hardcoded the spawned form for *every* `TCPClientInterface`, so every
/// interface an operator put in their config file was filtered out of `rnstatus` — by
/// both implementations, since both apply the same Python rule. The interface was
/// online and passing traffic the entire time; only its name was wrong.
///
/// The existing coverage could not catch this: `RNStatusRendererTests` asserts the hide
/// rule against a hand-written payload, and `InterfaceGetterTests` asserted the name
/// against the same mistaken belief. Nothing ran an actual interface object through the
/// renderer. That is what this file does.
final class TCPInterfaceNamingTests: XCTestCase {

    // MARK: - Python name shapes

    /// Python: `"TCPInterface["+str(self.name)+"/"+ip_str+":"+str(self.target_port)+"]"`,
    /// where `target_ip` is the configured `target_host` *verbatim* — Python never
    /// resolves it for display (`TCPInterface.py:151`, `:456-462`).
    func testConfiguredClientUsesThePythonNameShape() {
        let iface = TCPClientInterface(name: "wisco.network TCP",
                                       host: "147.224.161.226", port: 4242)
        XCTAssertEqual(iface.displayName, "TCPInterface[wisco.network TCP/147.224.161.226:4242]")
    }

    /// A hostname is printed as configured, not resolved.
    func testConfiguredClientKeepsTheHostnameUnresolved() {
        let iface = TCPClientInterface(name: "remote", host: "rns.wisco.network", port: 4242)
        XCTAssertEqual(iface.displayName, "TCPInterface[remote/rns.wisco.network:4242]")
    }

    /// Python brackets an IPv6 literal before joining on ":" so the port stays readable.
    func testConfiguredClientBracketsIPv6Literals() {
        let iface = TCPClientInterface(name: "v6", host: "2001:db8::1", port: 4242)
        XCTAssertEqual(iface.displayName, "TCPInterface[v6/[2001:db8::1]:4242]")
    }

    /// Python: `"TCPServerInterface["+self.name+"/"+ip_str+":"+str(self.bind_port)+"]"`
    /// (`TCPInterface.py:680-686`). Not on the hide list, so this one was merely
    /// mis-named rather than invisible — but the name feeds `Interface.hash`, so a Swift
    /// listener published a different identity than the Python listener beside it.
    func testServerUsesThePythonNameShape() {
        let iface = TCPServerInterface(name: "TCP Server", port: 4242)
        XCTAssertEqual(iface.displayName, "TCPServerInterface[TCP Server/0.0.0.0:4242]")
    }

    func testServerReportsItsConfiguredBindAddress() {
        let iface = TCPServerInterface(name: "TCP Server", port: 4242, bindIP: "127.0.0.1")
        XCTAssertEqual(iface.displayName, "TCPServerInterface[TCP Server/127.0.0.1:4242]")
    }

    /// The spawned client is the case the hide rule exists for, so it must keep the
    /// `Client on` form — and carry the *peer* address, as Python does
    /// (`spawned_interface.target_ip = handler.client_address[0]`, `TCPInterface.py:609`).
    func testSpawnedServerClientKeepsTheHiddenForm() {
        let server = TCPServerInterface(name: "TCP Server", port: 4242)
        let client = TCPServerClientInterface(name: "Client on TCP Server",
                                              parentServer: server,
                                              peerHost: "10.0.0.9", peerPort: 51420)
        XCTAssertEqual(client.displayName, "TCPInterface[Client on TCP Server/10.0.0.9:51420]")
        XCTAssertTrue(client.displayName.hasPrefix("TCPInterface[Client"),
                      "the spawned form must still match rnstatus's hide prefix")
    }

    // MARK: - The join: object name -> stats payload -> rnstatus

    /// Build the payload from a live Transport, exactly as the RPC server does, and run
    /// it through the renderer with default options. This is the end-to-end path the
    /// operator sees, and it is the assertion that was missing.
    private func renderRegistered(_ interfaces: [any Interface], showAll: Bool = false) -> String {
        let transport = Transport()
        for iface in interfaces { transport.register(interface: iface) }
        defer { for iface in interfaces { transport.deregister(interface: iface) } }

        guard let stats = RNStatusStats(InterfaceStatsPayload.build(transport)) else {
            XCTFail("interface stats payload did not decode")
            return ""
        }
        var options = RNStatusRenderer.Options()
        options.showAll = showAll
        return RNStatusRenderer(options: options).render(stats: stats, linkCount: nil)
    }

    /// The headline regression: an interface synthesized from a config file must appear
    /// in `rnstatus` without `--all`.
    func testConfiguredClientIsVisibleInRnstatus() {
        let iface = TCPClientInterface(name: "wisco.network TCP",
                                       host: "147.224.161.226", port: 4242)
        let rendered = renderRegistered([iface])
        XCTAssertTrue(rendered.contains("TCPInterface[wisco.network TCP/147.224.161.226:4242]"),
                      "a configured TCP client must not be filtered out of rnstatus:\n\(rendered)")
    }

    func testConfiguredServerIsVisibleInRnstatus() {
        let iface = TCPServerInterface(name: "TCP Server", port: 4242)
        let rendered = renderRegistered([iface])
        XCTAssertTrue(rendered.contains("TCPServerInterface[TCP Server/0.0.0.0:4242]"), rendered)
    }

    /// The other half of the contract: the hide rule must still hide what it is for.
    func testSpawnedServerClientIsHiddenFromRnstatus() {
        let server = TCPServerInterface(name: "TCP Server", port: 4242)
        let client = TCPServerClientInterface(name: "Client on TCP Server",
                                              parentServer: server,
                                              peerHost: "10.0.0.9", peerPort: 51420)
        let rendered = renderRegistered([client])
        XCTAssertFalse(rendered.contains("TCPInterface[Client"),
                       "spawned server clients must stay hidden by default:\n\(rendered)")
        XCTAssertTrue(renderRegistered([client], showAll: true).contains("TCPInterface[Client on TCP Server/10.0.0.9:51420]"))
    }

    /// `Interface.hash` is `fullHash(displayName)`, so getting the name right is what
    /// makes a Swift daemon and a Python daemon agree on interface identity.
    func testHashFollowsTheCorrectedName() {
        let iface = TCPClientInterface(name: "remote", host: "1.2.3.4", port: 4242)
        XCTAssertEqual(iface.hash,
                       Hashes.fullHash(Data("TCPInterface[remote/1.2.3.4:4242]".utf8)))
    }

    // MARK: - Synthesis carries the config block name through

    /// Two clients pointed at the same peer are distinguishable only by their config
    /// block name, which the old format dropped entirely.
    func testSynthesisNamesEachClientAfterItsConfigBlock() throws {
        let cfg = ReticulumConfig.parse("""
        [interfaces]
          [[Backbone A]]
            type = TCPClientInterface
            interface_enabled = true
            target_host = 10.0.0.1
            target_port = 4242
          [[Backbone B]]
            type = TCPClientInterface
            interface_enabled = true
            target_host = 10.0.0.1
            target_port = 4242
        """)
        let names = cfg.interfaces.compactMap { entry -> String? in
            guard let host = entry["target_host"], let port = entry.int("target_port") else { return nil }
            return TCPClientInterface(name: entry.name, host: host, port: UInt16(port)).displayName
        }
        XCTAssertEqual(names, ["TCPInterface[Backbone A/10.0.0.1:4242]",
                               "TCPInterface[Backbone B/10.0.0.1:4242]"])
    }

    /// `UDPInterface` had the same hardcoded bind address, found by the cross-implementation
    /// name comparison in `tri-test` once it started comparing names by value: Python
    /// reported `UDPInterface[Isolated UDP/127.0.0.1:*]` for a loopback-bound interface and
    /// Swift reported `.../0.0.0.0:*`. Python: `UDPInterface.py:63`, `:131-132`.
    func testUDPInterfaceReportsItsConfiguredBindAddress() {
        let iface = UDPInterface(name: "Isolated UDP", listenPort: 4242, bindIP: "127.0.0.1")
        XCTAssertEqual(iface.displayName, "UDPInterface[Isolated UDP/127.0.0.1:4242]")
        XCTAssertEqual(UDPInterface(name: "any", listenPort: 4242).displayName,
                       "UDPInterface[any/0.0.0.0:4242]", "0.0.0.0 stays the default")
    }

    /// Python builds a plain `TCPClientInterface` from an accepted socket
    /// (`TCPInterface.py:591`) — there is no separate class — so `type` must say so.
    /// `TCPServerClientInterface` is a Swift implementation detail, and publishing it made
    /// a Swift daemon report an interface class that does not exist in RNS.
    func testSpawnedServerClientPublishesPythonsClassName() {
        let server = TCPServerInterface(name: "TCP Server", port: 4242)
        let client = TCPServerClientInterface(name: "Client on TCP Server",
                                              parentServer: server,
                                              peerHost: "10.0.0.9", peerPort: 51420)
        XCTAssertEqual(client.statsTypeName, "TCPClientInterface")
    }

    /// Python reads `listen_ip` for the bind address (`TCPInterface.py:518`); the Swift
    /// synthesizer ignored it, so every listener claimed 0.0.0.0 regardless of config.
    func testSynthesisReadsListenIPForTheServerName() throws {
        let cfg = ReticulumConfig.parse("""
        [interfaces]
          [[TCP Server]]
            type = TCPServerInterface
            interface_enabled = true
            listen_ip = 127.0.0.1
            listen_port = 4242
        """)
        let reticulum = Reticulum(configuration: Reticulum.Configuration(
            storagePath: FileManager.default.temporaryDirectory
                .appendingPathComponent("rns-naming-\(UUID().uuidString)")))
        try reticulum.start()
        defer { reticulum.stop() }
        try reticulum.synthesizeInterfaces(from: cfg)

        let names = reticulum.transport.interfaces.map(\.displayName)
        XCTAssertTrue(names.contains("TCPServerInterface[TCP Server/127.0.0.1:4242]"),
                      "got \(names)")
    }
}
