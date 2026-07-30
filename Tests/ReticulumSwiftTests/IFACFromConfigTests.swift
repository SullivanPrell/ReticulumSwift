import XCTest
@testable import ReticulumSwift

/// `bugs/015` — IFAC must be configurable from a config file.
///
/// `Transport.configureIfac` is correct, and `IFACTests` / `IFACSendPathTests` prove it
/// thoroughly. They prove it by calling it **by hand**. Nothing in the port ever called it from
/// the config path, so an operator who set `network_name` and `passphrase` on an interface got an
/// interface that came up, reported Up, and passed nothing: every frame it sent was unflagged and
/// dropped by the peer, every frame it received was flagged and dropped locally. A comprehensive
/// test suite for an API with no caller.
///
/// So every assertion here starts from a config **string** and ends at traffic crossing, and
/// nothing in this file calls `configureIfac`.
final class IFACFromConfigTests: XCTestCase {

    private var tmpDirs: [URL] = []

    override func tearDown() {
        for dir in tmpDirs { try? FileManager.default.removeItem(at: dir) }
        tmpDirs = []
        super.tearDown()
    }

    /// A loopback pair that hands whatever one side sends to the other, so "did the frame survive
    /// IFAC on both ends" is observable without a socket. Counts rejections, because the defect's
    /// signature is silent dropping rather than an error.
    final class PairedInterface: Interface {
        let interfaceState = InterfaceState()
        var name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var ifacIdentity: Identity?
        var ifacKey: Data?
        var ifacSize: Int = Constants.defaultIfacSize
        weak var paired: PairedInterface?
        private(set) var rejectedFrames = 0
        private(set) var deliveredFrames = 0

        init(_ name: String) { self.name = name }
        func start() throws {}
        func stop() {}

        func send(_ packet: Packet) throws {
            paired?.receive(wrapIfac(try packet.pack()))
        }

        func receive(_ framed: Data) {
            guard let raw = unwrapIfac(framed), let packet = try? Packet.unpack(raw) else {
                rejectedFrames += 1
                return
            }
            deliveredFrames += 1
            inboundHandler?(packet, self)
        }
    }

    // MARK: - Driving the real config path

    /// Parse a config **string** and synthesise its interfaces, which is the path an operator's
    /// file actually takes: `ReticulumConfig.parse` → `synthesizeInterfaces`.
    ///
    /// The stack is not started — `synthesizeInterfaces` needs only the transport, and starting it
    /// would bind the shared-instance port.
    private func synthesise(_ config: String) throws -> [any Interface] {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ifac-config-\(UUID().uuidString)")
        tmpDirs.append(tmp)
        let reticulum = Reticulum(configuration: .init(storagePath: tmp.appendingPathComponent("storage"),
                                                      shareInstance: false))
        try reticulum.synthesizeInterfaces(from: ReticulumConfig.parse(config))
        return reticulum.transport.interfaces
    }

    /// A UDP block with no ports, so nothing binds. `interface_enabled` and the type are the only
    /// keys synthesis requires.
    private func udpBlock(_ body: String) -> String {
        """
        [interfaces]
          [[Segment Interface]]
            type = UDPInterface
            interface_enabled = True
        \(body)
        """
    }

    // MARK: - The key arrives via a parsed config

    /// The documented segment example, from
    /// `reference_implementations/reticulum/docs/markdown/interfaces.md:1063-1067`.
    func testNetworkNameAndPassphraseFromConfigInstallAnIFACKey() throws {
        let interfaces = try synthesise(udpBlock("""
            network_name = internal_1
            passphrase = a-passphrase
        """))

        let iface = try XCTUnwrap(interfaces.first, "no interface synthesised from the config")
        XCTAssertNotNil(iface.ifacKey,
                        """
                        The interface came up with no IFAC key, from a config that set \
                        network_name and passphrase. It reports Up and passes nothing: every frame \
                        it sends is unflagged and dropped by the peer, every frame it receives is \
                        flagged and dropped locally (bugs/015).
                        """)
        // Python derives 64 bytes by HKDF over the salted origin hash (`Reticulum.py:969-970`).
        XCTAssertEqual(iface.ifacKey?.count, Constants.keySize)
    }

    /// Python accepts both spellings of each key (`Reticulum.py:778-788`).
    func testBothConfigKeySpellingsAreAccepted() throws {
        let underscored = try synthesise(udpBlock("""
            network_name = seg
            pass_phrase = secret
        """))
        let compact = try synthesise(udpBlock("""
            networkname = seg
            passphrase = secret
        """))
        XCTAssertEqual(try XCTUnwrap(underscored.first?.ifacKey),
                       try XCTUnwrap(compact.first?.ifacKey),
                       "networkname/network_name and passphrase/pass_phrase are aliases")
    }

    /// A network name on its own is enough — Python derives from whichever of the two is present
    /// (`Reticulum.py:960-966`).
    func testNetworkNameAloneInstallsAKey() throws {
        let interfaces = try synthesise(udpBlock("    network_name = seg"))
        XCTAssertNotNil(try XCTUnwrap(interfaces.first).ifacKey)
    }

    /// An empty value is not a value — Python guards each with `!= ""` (`Reticulum.py:780`, `:784`).
    func testEmptyNetworkNameAndPassphraseLeaveIFACOff() throws {
        let interfaces = try synthesise(udpBlock("""
            network_name =
            passphrase =
        """))
        XCTAssertNil(try XCTUnwrap(interfaces.first).ifacKey,
                     "an empty network_name/passphrase must not install a key")
    }

    /// An interface with neither key stays off IFAC entirely.
    func testAnInterfaceWithNoSegmentKeysHasNoIFAC() throws {
        let interfaces = try synthesise(udpBlock("    listen_port = 4966"))
        XCTAssertNil(try XCTUnwrap(interfaces.first).ifacKey)
    }

    /// `ifac_size` in the config is in **bits** and is divided by 8 (`Reticulum.py:776`).
    func testIFACSizeIsReadInBits() throws {
        let interfaces = try synthesise(udpBlock("""
            network_name = seg
            ifac_size = 64
        """))
        XCTAssertEqual(try XCTUnwrap(interfaces.first).ifacSize, 8,
                       "config ifac_size is bits; 64 bits is 8 bytes")
    }

    /// Python ignores a value below `IFAC_MIN_SIZE * 8`, leaving the class default in place — the
    /// assignment sits inside the `>=` guard (`Reticulum.py:776`).
    func testIFACSizeBelowTheMinimumIsIgnored() throws {
        let interfaces = try synthesise(udpBlock("""
            network_name = seg
            ifac_size = 4
        """))
        XCTAssertEqual(try XCTUnwrap(interfaces.first).ifacSize, Constants.defaultIfacSize,
                       "4 bits is below IFAC_MIN_SIZE*8, so Python leaves the class default")
    }

    /// Python sets `ifac_identity` and `ifac_signature` alongside the key
    /// (`Reticulum.py:972-973`). `rnstatus` prints the signature's last bytes as the segment's
    /// "Access" fingerprint, so a key without an identity means a Swift node reports no access
    /// code where a Python node on the same segment reports one.
    func testIFACIdentityIsDerivedFromTheKey() throws {
        let interfaces = try synthesise(udpBlock("""
            network_name = seg
            passphrase = secret
        """))
        let iface = try XCTUnwrap(interfaces.first)
        let identity = try XCTUnwrap(iface.ifacIdentity,
                                     """
                                     ifac_identity was not derived. Python builds it from the IFAC \
                                     key at Reticulum.py:972 and signs full_hash(key) with it; \
                                     without it the stats payload reports ifac_signature nil and \
                                     rnstatus shows no Access fingerprint for an interface that is \
                                     on an IFAC segment.
                                     """)
        // `Identity.from_bytes(interface.ifac_key)` — derived, not random, so two nodes on one
        // segment produce the same signature.
        XCTAssertEqual(identity.privateKeyBytes, try XCTUnwrap(iface.ifacKey))
    }

    // MARK: - Traffic actually crosses

    /// The assertion the spec insists on: not that a key was installed, but that packets cross.
    func testTrafficCrossesBetweenTwoConfigDrivenPeersOnOneSegment() throws {
        let (a, b) = try pairOnSegments(("internal_1", "shared-secret"),
                                        ("internal_1", "shared-secret"))
        var received = 0
        b.inboundHandler = { _, _ in received += 1 }
        try a.send(makePacket())

        XCTAssertEqual(received, 1, "a packet must cross between two peers on one IFAC segment")
        XCTAssertEqual(b.rejectedFrames, 0)
    }

    /// The other half — unflagged traffic from an unconfigured peer is dropped
    /// (`Transport.py:1480-1482`).
    func testUnflaggedTrafficIsRejected() throws {
        let (_, b) = try pairOnSegments(nil, ("internal_1", "shared-secret"))
        var received = 0
        b.inboundHandler = { _, _ in received += 1 }
        // A peer with no IFAC sends the frame raw.
        b.receive(try makePacket().pack())

        XCTAssertEqual(received, 0, "an unflagged frame must not be delivered")
        XCTAssertEqual(b.rejectedFrames, 1)
    }

    /// Two different segments must not interoperate, or "traffic crosses" above would also pass
    /// for an implementation that installed no key at all.
    func testDifferentSegmentsDoNotInteroperate() throws {
        let (a, b) = try pairOnSegments(("internal_1", "one"), ("internal_2", "two"))
        var received = 0
        b.inboundHandler = { _, _ in received += 1 }
        try a.send(makePacket())

        XCTAssertEqual(received, 0, "different segments must not interoperate")
        XCTAssertEqual(b.rejectedFrames, 1)
    }

    // MARK: - Status output

    /// `rnstatus` shows the segment's network name for a Python daemon. The Swift payload
    /// hardcoded `ifac_netname` to nil (`InterfaceStatsPayload.swift:115`).
    func testIFACNetnameAppearsInStatusOutput() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ifac-netname-\(UUID().uuidString)")
        tmpDirs.append(tmp)
        let reticulum = Reticulum(configuration: .init(storagePath: tmp.appendingPathComponent("storage"),
                                                      shareInstance: false))
        reticulum.transport.transportIdentity = Identity()
        try reticulum.synthesizeInterfaces(from: ReticulumConfig.parse(udpBlock("""
            network_name = internal_1
            passphrase = secret
        """)))

        let stats = try XCTUnwrap(RNStatusStats(InterfaceStatsPayload.build(reticulum.transport)))
        let row = try XCTUnwrap(stats.interfaces.first)
        XCTAssertEqual(row.string("ifac_netname"), "internal_1",
                       """
                       ifac_netname is absent from the status payload, so an operator cannot see \
                       which segment an interface is on — a Python daemon reports it.
                       """)
    }

    /// An interface with no segment reports nil, as Python does.
    func testIFACNetnameIsNilWithoutASegment() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ifac-nonetname-\(UUID().uuidString)")
        tmpDirs.append(tmp)
        let reticulum = Reticulum(configuration: .init(storagePath: tmp.appendingPathComponent("storage"),
                                                      shareInstance: false))
        reticulum.transport.transportIdentity = Identity()
        try reticulum.synthesizeInterfaces(from: ReticulumConfig.parse(udpBlock("    listen_port = 4967")))

        let stats = try XCTUnwrap(RNStatusStats(InterfaceStatsPayload.build(reticulum.transport)))
        XCTAssertNil(try XCTUnwrap(stats.interfaces.first).string("ifac_netname"))
    }

    // MARK: - Helpers

    private func makePacket() -> Packet {
        Packet(destinationType: .single,
               packetType: .data,
               destinationHash: Data(repeating: 0xAB, count: Constants.truncatedHashLength),
               data: Data("hello segment".utf8))
    }

    /// Two paired interfaces, each configured the way a config block would configure it — through
    /// the same entry point `synthesizeInterfaces` uses, never `Transport.configureIfac`. That
    /// distinction is what the suite exists to preserve.
    private func pairOnSegments(_ left: (String, String)?,
                                _ right: (String, String)?) throws -> (PairedInterface, PairedInterface) {
        let a = PairedInterface("a")
        let b = PairedInterface("b")
        a.paired = b
        b.paired = a
        for (iface, segment) in [(a, left), (b, right)] {
            guard let segment else { continue }
            var parameters: [String: String] = [:]
            parameters["network_name"] = segment.0
            parameters["passphrase"] = segment.1
            Reticulum.applyIfacConfiguration(
                to: iface,
                from: ReticulumConfig.InterfaceConfig(name: iface.name,
                                                      type: "UDPInterface",
                                                      enabled: true,
                                                      parameters: parameters))
        }
        return (a, b)
    }
}
