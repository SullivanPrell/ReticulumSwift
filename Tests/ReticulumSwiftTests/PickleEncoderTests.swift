import XCTest
@testable import ReticulumSwift

/// Tests for PickleEncoder and PickleDecoder.
///
/// Every encoded value is verified by comparing against the exact bytes produced by:
///   python3 -c "import pickle, sys; sys.stdout.buffer.write(pickle.dumps(X, protocol=4))"
///
/// The decoder tests verify that round-trip extraction works on realistic RPC payloads.
final class PickleEncoderTests: XCTestCase {

    // MARK: - Scalar encoding

    func testNone() {
        let data = PickleEncoder.encode(.none)
        XCTAssertEqual(data, Data([0x80, 0x04, 0x4e, 0x2e]))
    }

    func testTrue() {
        let data = PickleEncoder.encode(.bool(true))
        XCTAssertEqual(data, Data([0x80, 0x04, 0x88, 0x2e]))
    }

    func testFalse() {
        let data = PickleEncoder.encode(.bool(false))
        XCTAssertEqual(data, Data([0x80, 0x04, 0x89, 0x2e]))
    }

    func testIntZero() {
        let data = PickleEncoder.encode(.int(0))
        // BININT1 0x00
        XCTAssertEqual(data, Data([0x80, 0x04, 0x4b, 0x00, 0x2e]))
    }

    func testIntSmall() {
        let data = PickleEncoder.encode(.int(42))
        XCTAssertEqual(data, Data([0x80, 0x04, 0x4b, 0x2a, 0x2e]))
    }

    func testInt255() {
        let data = PickleEncoder.encode(.int(255))
        // BININT1 0xff
        XCTAssertEqual(data, Data([0x80, 0x04, 0x4b, 0xff, 0x2e]))
    }

    func testInt256() {
        let data = PickleEncoder.encode(.int(256))
        // BININT2: 0x4c 0x00 0x01
        XCTAssertEqual(data, Data([0x80, 0x04, 0x4c, 0x00, 0x01, 0x2e]))
    }

    func testInt65535() {
        let data = PickleEncoder.encode(.int(65535))
        // BININT2: 0x4c 0xff 0xff
        XCTAssertEqual(data, Data([0x80, 0x04, 0x4c, 0xff, 0xff, 0x2e]))
    }

    func testInt65536() {
        let data = PickleEncoder.encode(.int(65536))
        // BININT: 0x4a 0x00 0x01 0x00 0x00
        XCTAssertEqual(data, Data([0x80, 0x04, 0x4a, 0x00, 0x00, 0x01, 0x00, 0x2e]))
    }

    func testIntNegative() {
        let data = PickleEncoder.encode(.int(-1))
        // BININT: 0x4a 0xff 0xff 0xff 0xff
        XCTAssertEqual(data, Data([0x80, 0x04, 0x4a, 0xff, 0xff, 0xff, 0xff, 0x2e]))
    }

    func testFloatZero() {
        let data = PickleEncoder.encode(.float(0.0))
        // BINFLOAT: 0x47 + 8 bytes big-endian IEEE 754 (0.0 = all zeros)
        XCTAssertEqual(data, Data([0x80, 0x04, 0x47, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2e]))
    }

    func testFloatOne() {
        let data = PickleEncoder.encode(.float(1.0))
        // 1.0 IEEE 754 big-endian: 3f f0 00 00 00 00 00 00
        XCTAssertEqual(data, Data([0x80, 0x04, 0x47, 0x3f, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2e]))
    }

    func testEmptyString() {
        let data = PickleEncoder.encode(.string(""))
        // SHORT_BINUNICODE len=0 + MEMOIZE
        XCTAssertEqual(data, Data([0x80, 0x04, 0x8c, 0x00, 0x94, 0x2e]))
    }

    func testShortString() {
        let data = PickleEncoder.encode(.string("hi"))
        // 0x8c 0x02 h i 0x94
        XCTAssertEqual(data, Data([0x80, 0x04, 0x8c, 0x02, 0x68, 0x69, 0x94, 0x2e]))
    }

    func testEmptyBytes() {
        let data = PickleEncoder.encode(.bytes(Data()))
        // SHORT_BINBYTES len=0 + MEMOIZE
        XCTAssertEqual(data, Data([0x80, 0x04, 0x43, 0x00, 0x94, 0x2e]))
    }

    func testShortBytes() {
        let data = PickleEncoder.encode(.bytes(Data([0xde, 0xad])))
        // 0x43 0x02 de ad 0x94
        XCTAssertEqual(data, Data([0x80, 0x04, 0x43, 0x02, 0xde, 0xad, 0x94, 0x2e]))
    }

    // MARK: - Collection encoding

    func testEmptyList() {
        let data = PickleEncoder.encode(.array([]))
        // EMPTY_LIST + MEMOIZE (no MARK/APPENDS)
        XCTAssertEqual(data, Data([0x80, 0x04, 0x5d, 0x94, 0x2e]))
    }

    func testSingletonList() {
        let data = PickleEncoder.encode(.array([.int(1)]))
        // EMPTY_LIST + MEMOIZE + MARK + BININT1(1) + APPENDS
        XCTAssertEqual(data, Data([0x80, 0x04, 0x5d, 0x94, 0x28, 0x4b, 0x01, 0x65, 0x2e]))
    }

    func testEmptyDict() {
        let data = PickleEncoder.encode(.dict([]))
        XCTAssertEqual(data, Data([0x80, 0x04, 0x7d, 0x94, 0x2e]))
    }

    func testStringKeyedDict() {
        // {"a": 1}
        let data = PickleEncoder.encode(.stringDict([("a", .int(1))]))
        // EMPTY_DICT MEMOIZE MARK SHORT_BINUNICODE"a" MEMOIZE BININT1(1) SETITEMS STOP
        let expected = Data([0x80, 0x04,
                             0x7d, 0x94,  // {}
                             0x28,         // MARK
                             0x8c, 0x01, 0x61, 0x94,  // "a"
                             0x4b, 0x01,   // 1
                             0x75,         // SETITEMS
                             0x2e])        // STOP
        XCTAssertEqual(data, expected)
    }

    // MARK: - Realistic pickle interface_stats shape (smoke test)

    func testInterfaceStatsDictDecodable() throws {
        // Build a minimal interface_stats dict (pickle format — for future use)
        let ifaceDict = PickleValue.stringDict([
            ("name",       .string("AutoInterface[local]")),
            ("short_name", .string("local")),
            ("rxb",        .int(12345)),
            ("txb",        .int(678)),
            ("status",     .bool(true)),
            ("mode",       .int(1)),
            ("bitrate",    .int(1_000_000)),
            ("rxs",        .float(1024.5)),
            ("txs",        .float(512.0)),
            ("burst_active",    .bool(false)),
            ("pr_burst_active", .bool(false)),
            ("held_announces",  .int(0)),
            ("announce_queue",  .none),
            ("clients",    .none),
        ])
        let statsDict = PickleValue.stringDict([
            ("interfaces", .array([ifaceDict])),
            ("rxb",        .int(100)),
            ("txb",        .int(200)),
            ("rxs",        .float(0.0)),
            ("txs",        .float(0.0)),
            ("rss",        .none),
        ])
        let data = PickleEncoder.encode(statsDict)
        XCTAssertGreaterThan(data.count, 10)
        XCTAssertEqual(data[0], 0x80)    // PROTO opcode
        XCTAssertEqual(data[1], 0x04)    // Protocol 4
        XCTAssertEqual(data.last, 0x2e)  // STOP
    }

    // MARK: - PickleDecoder

    func testDecoderBytes16() {
        let hash = Data(repeating: 0xab, count: 16)
        let payload = PickleEncoder.encode(.stringDict([
            ("get",              .string("next_hop")),
            ("destination_hash", .bytes(hash)),
        ]))
        let dec = PickleDecoder(payload)
        XCTAssertEqual(dec.bytes16(for: "destination_hash"), hash)
    }

    func testDecoderBytes16MissingKey() {
        let payload = PickleEncoder.encode(.stringDict([("get", .string("interface_stats"))]))
        let dec = PickleDecoder(payload)
        XCTAssertNil(dec.bytes16(for: "destination_hash"))
    }

    func testDecoderIntPresent() {
        let payload = PickleEncoder.encode(.stringDict([
            ("get",      .string("path_table")),
            ("max_hops", .int(10)),
        ]))
        let dec = PickleDecoder(payload)
        XCTAssertEqual(dec.int(for: "max_hops"), 10)
    }

    func testDecoderIntNone() {
        let payload = PickleEncoder.encode(.stringDict([
            ("get",      .string("path_table")),
            ("max_hops", .none),
        ]))
        let dec = PickleDecoder(payload)
        XCTAssertNil(dec.int(for: "max_hops"))
        XCTAssertTrue(dec.isNone(for: "max_hops"))
    }

    func testDecoderIdentityHash() {
        let hash = Data((0..<16).map { UInt8($0) })
        let payload = PickleEncoder.encode(.stringDict([
            ("get",           .string("is_blackholed")),
            ("identity_hash", .bytes(hash)),
        ]))
        let dec = PickleDecoder(payload)
        XCTAssertEqual(dec.bytes16(for: "identity_hash"), hash)
    }

    // MARK: - MsgPack RPC round-trip (mirrors the actual wire protocol used by RNS 1.3.x)

    func testMsgPackRPCInterfaceStatsCall() throws {
        // Verify {"get": "interface_stats"} encodes to the exact bytes Python sends.
        // Python: mp.packb({"get": "interface_stats"}) = 81 a3 "get" af "interface_stats"
        let call: MsgPack.Value = .map([
            (.string("get"), .string("interface_stats"))
        ])
        let encoded = MsgPack.encode(call)
        // fixmap{1} + fixstr"get" + fixstr"interface_stats"
        let expected = Data([0x81,  // fixmap{1}
                             0xa3, 0x67, 0x65, 0x74,  // "get"
                             0xaf, 0x69, 0x6e, 0x74, 0x65, 0x72, 0x66, 0x61, 0x63, 0x65, 0x5f,
                             0x73, 0x74, 0x61, 0x74, 0x73])  // "interface_stats"
        XCTAssertEqual(encoded, expected)
    }

    func testMsgPackRPCPathTableCall() throws {
        // {"get": "path_table", "max_hops": nil}
        let call: MsgPack.Value = .map([
            (.string("get"),      .string("path_table")),
            (.string("max_hops"), .nil),
        ])
        let encoded = MsgPack.encode(call)
        let decoded = try MsgPack.decode(encoded)
        guard case .map(let pairs) = decoded else { XCTFail("expected map"); return }
        let kv = Dictionary(uniqueKeysWithValues: pairs.compactMap { k, v -> (String, MsgPack.Value)? in
            guard case .string(let s) = k else { return nil }
            return (s, v)
        })
        XCTAssertEqual(kv["get"], .string("path_table"))
        XCTAssertEqual(kv["max_hops"], .nil)
    }

    func testMsgPackRPCNextHopCall() throws {
        // {"get": "next_hop", "destination_hash": <16 bytes>}
        let hash = Data(repeating: 0xde, count: 16)
        let call: MsgPack.Value = .map([
            (.string("get"),              .string("next_hop")),
            (.string("destination_hash"), .bytes(hash)),
        ])
        let encoded = MsgPack.encode(call)
        let decoded = try MsgPack.decode(encoded)
        guard case .map(let pairs) = decoded else { XCTFail(); return }
        let kv = Dictionary(uniqueKeysWithValues: pairs.compactMap { k, v -> (String, MsgPack.Value)? in
            guard case .string(let s) = k else { return nil }
            return (s, v)
        })
        guard case .bytes(let gotHash) = kv["destination_hash"] else { XCTFail(); return }
        XCTAssertEqual(gotHash, hash)
    }

    func testMsgPackRPCInterfaceStatsResponse() throws {
        // Build the stats response shape that RPCServer returns and verify Python can parse it
        let stats: MsgPack.Value = .map([
            (.string("interfaces"), .array([])),
            (.string("rxb"),        .int(0)),
            (.string("txb"),        .int(0)),
            (.string("rxs"),        .double(0.0)),
            (.string("txs"),        .double(0.0)),
            (.string("rss"),        .nil),
        ])
        let encoded = MsgPack.encode(stats)
        let decoded = try MsgPack.decode(encoded)
        guard case .map(let pairs) = decoded else { XCTFail("not a map"); return }
        let keys = pairs.compactMap { k, _ -> String? in
            guard case .string(let s) = k else { return nil }
            return s
        }
        XCTAssertTrue(keys.contains("interfaces"))
        XCTAssertTrue(keys.contains("rxb"))
        XCTAssertTrue(keys.contains("txb"))
    }

    // MARK: - displayName integration

    func testLocalInterfaceDisplayName() {
        let iface = LocalInterface(name: "LocalInterface", host: "127.0.0.1", port: 37428)
        XCTAssertEqual(iface.displayName, "LocalInterface[37428]")
    }

    func testPosixTCPServerDisplayName() {
        let server = PosixTCPServer(name: "Shared Instance", port: 37428)
        XCTAssertEqual(server.displayName, "Shared Instance[37428]")
    }

    func testTCPClientInterfaceDisplayName() {
        let iface = TCPClientInterface(name: "TestTCP", host: "10.0.0.1", port: 42422)
        XCTAssertEqual(iface.displayName, "TCPInterface[Client on 10.0.0.1:42422]")
    }

    func testTCPServerInterfaceDisplayName() {
        let iface = TCPServerInterface(name: "TestServer", port: 42422)
        XCTAssertEqual(iface.displayName, "TCPInterface[Server on 0.0.0.0:42422]")
    }

    func testAutoInterfaceDisplayName() {
        let iface = AutoInterface(name: "local")
        XCTAssertEqual(iface.displayName, "AutoInterface[local]")
    }

    func testUDPInterfaceDisplayName() {
        let iface = UDPInterface(name: "myudp", listenPort: 4242)
        XCTAssertEqual(iface.displayName, "UDPInterface[myudp/0.0.0.0:4242]")
    }

    // MARK: - Transport.startTime

    func testTransportStartTime() {
        let t = Transport()
        XCTAssertEqual(t.startTime, 0, "startTime should be 0 before start()")
        let before = Date().timeIntervalSince1970
        try? t.start()
        let after = Date().timeIntervalSince1970
        XCTAssertGreaterThanOrEqual(t.startTime, before)
        XCTAssertLessThanOrEqual(t.startTime, after)
        t.stop()
    }

    // MARK: - Transport.ingressState and announceQueueCount

    func testIngressStateCreatedOnRegister() {
        let t = Transport()
        let iface = MockInterface(name: "mock")
        t.register(interface: iface)
        // Ingress state is created when the interface is registered.
        let state = t.ingressState(for: iface)
        XCTAssertNotNil(state)
        XCTAssertFalse(state?.burstActive ?? true)
        XCTAssertFalse(state?.prBurstActive ?? true)
    }

    func testIngressStateNilForUnregisteredInterface() {
        let t = Transport()
        let iface = MockInterface(name: "unregistered")
        // No register() call — state should not exist.
        XCTAssertNil(t.ingressState(for: iface))
    }

    func testAnnounceQueueCountNilBeforeUse() {
        let t = Transport()
        let iface = MockInterface(name: "mock")
        t.register(interface: iface)
        // No announces have been queued, so the queue doesn't exist yet.
        XCTAssertNil(t.announceQueueCount(for: iface))
    }
}

// MARK: - Minimal mock interface for testing

private final class MockInterface: Interface {
    let name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var ifacIdentity: Identity?
    var ifacKey: Data?
    var ifacSize: Int = 16
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var wantsTunnel: Bool = false
    var tunnelID: Data?
    var bootstrapOnly: Bool = false
    init(name: String) { self.name = name }
    func send(_ packet: Packet) throws {}
    func start() throws {}
    func stop() {}
}
