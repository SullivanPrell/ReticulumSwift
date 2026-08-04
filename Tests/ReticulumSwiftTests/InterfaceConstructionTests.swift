import XCTest
@testable import ReticulumSwift

/// `swift_devel/bugs/031` — the four documented interface types a config file could not build.
///
/// `ConfigTemplateRoundTripTests` proves the *switch* has the cases and the *keys* have readers,
/// structurally. These tests drive `synthesizeInterfaces` for real, through stub transport
/// factories (design D6): the availability split — serial on macOS, BLE from an application —
/// lives in `InterfaceTransportFactories`, so a stub registration exercises both the
/// constructed and the unavailable path on any platform, which an `#if os(iOS)` in the switch
/// never could.
final class InterfaceConstructionTests: XCTestCase {

    // MARK: - Stubs

    private final class StubSerialPort: SerialPortTransport {
        var onTransportError: ((Error) -> Void)?
        var isOpen = false
        func open(port: String, baudRate: Int, dataBits: Int,
                  parity: SerialParity, stopBits: Int) throws { isOpen = true }
        func close() { isOpen = false }
        @discardableResult func write(_ data: Data) throws -> Int { data.count }
        func setReadCallback(_ callback: @escaping (Data) -> Void) {}
    }

    private final class StubRNodeTransport: RNodeTransport {
        var onTransportError: ((Error) -> Void)?
        var byteHandler: ((Data) -> Void)?
        private(set) var opened = false
        func open() throws { opened = true }
        func close() { opened = false }
        func write(_ data: Data) throws {
            // Behave like firmware, which `start()`'s bring-up gate now requires: answer a
            // detect request, and echo every configuration command back verbatim — that echo
            // is exactly what real RNode firmware sends as each parameter is applied.
            let bytes = [UInt8](data)
            if bytes.count > 1, bytes[1] == KISS.cmdDetect {
                byteHandler?(Data([KISS.fend, KISS.cmdDetect, KISS.detectResp, KISS.fend]))
            } else {
                byteHandler?(data)
            }
        }
    }

    private final class StubI2PDaemon: I2PDaemonProtocol {
        let samPort = 7656
        func start(dataDirectory: URL) throws {}
        func stop() {}
    }

    // MARK: - Registry save/restore

    /// The registry is process-global by design (an application registers once); a test that
    /// leaves stubs behind poisons every later test in the process.
    private var savedSerial: ((String) throws -> SerialPortTransport)?
    private var savedRNode: ((String) throws -> RNodeTransport)?
    private var savedI2P: (() throws -> I2PDaemonProtocol)?
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        savedSerial = InterfaceTransportFactories.serial
        savedRNode = InterfaceTransportFactories.rnode
        savedI2P = InterfaceTransportFactories.i2pDaemon
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rns_ifconstruct_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        InterfaceTransportFactories.serial = savedSerial
        InterfaceTransportFactories.rnode = savedRNode
        InterfaceTransportFactories.i2pDaemon = savedI2P
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func registerStubs() {
        InterfaceTransportFactories.serial = { _ in StubSerialPort() }
        InterfaceTransportFactories.rnode = { _ in StubRNodeTransport() }
        InterfaceTransportFactories.i2pDaemon = { StubI2PDaemon() }
    }

    private func makeStack() -> Reticulum {
        Reticulum(configuration: .init(storagePath: tempDir, shareInstance: false))
    }

    private func parse(_ blocks: String) -> ReticulumConfig {
        ReticulumConfig.parse("""
        [reticulum]
          enable_transport = no
          share_instance = no

        [interfaces]
        \(blocks)
        """)
    }

    // MARK: - 7.1: the four types construct

    func testEveryPreviouslyUnconstructibleTypeIsConstructedFromItsConfigBlock() throws {
        registerStubs()
        let stack = makeStack()
        let cfg = parse("""
          [[LoRa]]
            type = RNodeInterface
            enabled = yes
            port = /dev/cu.usbserial-test
            frequency = 867200000
            bandwidth = 125000
            txpower = 7
            spreadingfactor = 8
            codingrate = 5

          [[Packet Radio KISS]]
            type = KISSInterface
            enabled = yes
            port = /dev/cu.usbserial-kiss
            speed = 115200

          [[Packet Radio AX25]]
            type = AX25KISSInterface
            enabled = yes
            port = /dev/cu.usbserial-ax25
            callsign = NO1CLL
            ssid = 0

          [[I2P]]
            type = I2PInterface
            enabled = yes
            peers = base32one.b32.i2p, base32two.b32.i2p
        """)

        try stack.synthesizeInterfaces(from: cfg)

        let byName = Dictionary(uniqueKeysWithValues:
            stack.transport.interfaces.map { ($0.name, $0) })

        let rnode = try XCTUnwrap(byName["LoRa"] as? RNodeInterface,
                                  "the RNode block fell through the switch (`bugs/031`)")
        XCTAssertEqual(rnode.frequency, 867_200_000)
        XCTAssertEqual(rnode.bandwidth, 125_000)
        XCTAssertEqual(rnode.txPower, 7)
        XCTAssertEqual(rnode.sf, 8)
        XCTAssertEqual(rnode.cr, 5)

        let kiss = try XCTUnwrap(byName["Packet Radio KISS"] as? KISSInterface)
        XCTAssertEqual(kiss.speed, 115_200)

        let ax25 = try XCTUnwrap(byName["Packet Radio AX25"] as? AX25KISSInterface)
        XCTAssertEqual(ax25.srcCallsign, "NO1CLL")

        let i2p = try XCTUnwrap(byName["I2P"] as? I2PInterface)
        XCTAssertEqual(i2p.peers, ["base32one.b32.i2p", "base32two.b32.i2p"],
                       "`peers` is a comma list, as Python's `c.as_list` reads it")
    }

    /// The station-ID pair rides the same block (`RNodeInterface.py:333-343`): both halves
    /// arm it, and an over-long callsign fails construction as `validcfg` does.
    func testRNodeStationIdentificationConfigures() throws {
        registerStubs()
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[LoRa]]
            type = RNodeInterface
            enabled = yes
            port = /dev/cu.usbserial-test
            frequency = 867200000
            bandwidth = 125000
            txpower = 7
            spreadingfactor = 8
            codingrate = 5
            id_callsign = MYCALL-15
            id_interval = 600
        """))
        let rnode = try XCTUnwrap(stack.transport.interfaces.first as? RNodeInterface)
        XCTAssertEqual(rnode.idCallsign, Data("MYCALL-15".utf8))
        XCTAssertEqual(rnode.idInterval, 600)
    }

    // MARK: - 7.2: an unknown type is loud, and takes nothing else down

    /// The current reference routes an unknown type through the external-interface-module
    /// lookup and logs an ERROR when no module exists (`Reticulum.py:1055-1061`) — it does not
    /// raise, and the other interfaces still come up. This port loads no external modules, so
    /// the observable is the same: named error, everything else constructed.
    func testUnknownTypeIsSkippedLoudlyWhileOthersConstruct() throws {
        registerStubs()
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[Mystery]]
            type = HyperspaceInterface
            enabled = yes

          [[Real]]
            type = KISSInterface
            enabled = yes
            port = /dev/cu.usbserial-kiss
        """))
        XCTAssertNil(stack.transport.interfaces.first { $0.name == "Mystery" },
                     "an unknown type must not produce an interface")
        XCTAssertNotNil(stack.transport.interfaces.first { $0.name == "Real" },
                        "one bad block must not take the good ones with it — the reference "
                        + "logs and continues for an unknown type")
    }

    // MARK: - Construction failures carry the cause (the reference panics; this throws)

    func testAnOutOfRangeRadioParameterFailsConstruction() {
        registerStubs()
        let stack = makeStack()
        XCTAssertThrowsError(try stack.synthesizeInterfaces(from: parse("""
          [[LoRa]]
            type = RNodeInterface
            enabled = yes
            port = /dev/cu.usbserial-test
            frequency = 12345
            bandwidth = 125000
            txpower = 7
            spreadingfactor = 8
            codingrate = 5
        """))) { error in
            XCTAssertEqual(error as? InterfaceConstructionError,
                           .invalidValue(interface: "LoRa", key: "frequency", value: "12345"),
                           "the reference's `validcfg` gate raises on this "
                           + "(`RNodeInterface.py:305-307`) and `RNS.panic()`s the daemon; "
                           + "the throw is this port's equivalent, and it must name the key")
        }
    }

    func testAMissingRequiredKeyFailsConstruction() {
        registerStubs()
        let stack = makeStack()
        XCTAssertThrowsError(try stack.synthesizeInterfaces(from: parse("""
          [[NoCallsign]]
            type = AX25KISSInterface
            enabled = yes
            port = /dev/cu.usbserial-ax25
        """))) { error in
            XCTAssertEqual(error as? InterfaceConstructionError,
                           .missingKey(interface: "NoCallsign", key: "callsign"))
        }
    }

    // MARK: - 7.3: the unavailable path is as loud as the constructed one

    func testAnUnregisteredFamilyFailsWithTheCause() {
        registerStubs()
        InterfaceTransportFactories.serial = nil
        let stack = makeStack()
        XCTAssertThrowsError(try stack.synthesizeInterfaces(from: parse("""
          [[Radio]]
            type = KISSInterface
            enabled = yes
            port = /dev/cu.usbserial-kiss
        """))) { error in
            guard case .unavailable(let family, let device, _)? =
                    error as? InterfaceTransportFactories.FactoryError else {
                return XCTFail("expected FactoryError.unavailable, got \(error)")
            }
            XCTAssertEqual(family, "serial")
            XCTAssertEqual(device, "/dev/cu.usbserial-kiss",
                           "the error must name the device the operator configured — a bare "
                           + "'unavailable' is the silent skip with punctuation")
        }
    }

    /// BLE is an application concern (CoreBluetooth), so the *default* RNode factory refuses
    /// `ble://` with the registration hint rather than pretending — on every platform.
    func testBLEDeviceStringWithoutAnAppFactoryNamesTheRegistration() {
        registerStubs()
        InterfaceTransportFactories.rnode = InterfaceTransportFactories.defaultRNodeFactory
        let stack = makeStack()
        XCTAssertThrowsError(try stack.synthesizeInterfaces(from: parse("""
          [[BLE RNode]]
            type = RNodeInterface
            enabled = yes
            port = ble://RNode 3B87
            frequency = 867200000
            bandwidth = 125000
            txpower = 7
            spreadingfactor = 8
            codingrate = 5
        """))) { error in
            guard case .unavailable(_, let device, let hint)? =
                    error as? InterfaceTransportFactories.FactoryError else {
                return XCTFail("expected FactoryError.unavailable, got \(error)")
            }
            XCTAssertEqual(device, "ble://RNode 3B87")
            XCTAssertTrue(hint.contains("InterfaceTransportFactories.rnode"),
                          "the hint must say where the application registers BLE support")
        }
    }

    /// A factory-created transport has no owner but the interface — `RNodeInterface.transport`
    /// is `weak` (applications own their BLE controllers), so without an owning reference the
    /// transport deallocates before `start()` and the radio is silently gone: the zombie-
    /// interface shape, one level down.
    func testTheConstructedRNodeKeepsItsFactoryTransportAlive() throws {
        registerStubs()
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[LoRa]]
            type = RNodeInterface
            enabled = yes
            port = /dev/cu.usbserial-test
            frequency = 867200000
            bandwidth = 125000
            txpower = 7
            spreadingfactor = 8
            codingrate = 5
        """))
        let rnode = try XCTUnwrap(stack.transport.interfaces.first as? RNodeInterface)
        XCTAssertNotNil(rnode.transport,
                        "the weak transport reference is already gone — nothing owns the "
                        + "factory-created transport")
    }

    // MARK: - 7.7: what discovery writes, a restart constructs

    /// Discovery suggests config entries for discovered RNode, KISS and I2P peers, in the
    /// reference's own `config_entry` shapes (`Discovery.py:348,360,378,408`) — which is what
    /// made `bugs/031` self-defeating: the discovery path emitted blocks the config path could
    /// not construct, so an auto-discovered LoRa peer was written down and then silently
    /// ignored on the next start.
    ///
    /// The radio shapes leave `port = ` empty for the operator's device; this test completes
    /// it exactly as an operator would and leaves everything else as discovery wrote it —
    /// including the empty `txpower = ` line the reference's own suggestion carries.
    func testTheEntriesDiscoveryEmitsConstructOnRestart() throws {
        registerStubs()
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[Discovered RNode]]
            type = RNodeInterface
            enabled = yes
            port = /dev/cu.usbserial-0001
            frequency = 867200000
            bandwidth = 125000
            spreadingfactor = 8
            codingrate = 5
            txpower =

          [[Discovered KISS]]
            type = KISSInterface
            enabled = yes
            port = /dev/cu.usbserial-0002

          [[Discovered I2P]]
            type = I2PInterface
            enabled = yes
            peers = discoveredpeer.b32.i2p
        """))
        let names = Set(stack.transport.interfaces.map(\.name))
        XCTAssertEqual(names, ["Discovered RNode", "Discovered KISS", "Discovered I2P"],
                       "an entry discovery wrote must be an entry the config path constructs — "
                       + "emitting blocks the daemon then ignores is `bugs/031` eating its own "
                       + "output")
    }

    /// The reference constructs an RNode whose port is not yet usable and brings it up later
    /// (`open_port` failure → log + periodic reconnect, `RNodeInterface.py:354-360`); an
    /// unfilled discovery suggestion must therefore construct rather than throw — the failure
    /// belongs to `start()`, where the cause is a real open error.
    func testAnUnfilledDiscoveryPortStillConstructs() throws {
        registerStubs()
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[Unfilled RNode]]
            type = RNodeInterface
            enabled = yes
            port =
            frequency = 867200000
            bandwidth = 125000
            spreadingfactor = 8
            codingrate = 5
            txpower =
        """))
        XCTAssertNotNil(stack.transport.interfaces.first { $0.name == "Unfilled RNode" })
    }

    // MARK: - device = <name> on the constructible families (`bugs/031`'s two-line rider)

    func testDeviceKeyBindsTheNamedDevicesAddressOnTCPServer() throws {
        let stack = makeStack()
        // `lo0` exists on every Darwin machine and its IPv4 address is stable.
        try stack.synthesizeInterfaces(from: parse("""
          [[Bound Server]]
            type = TCPServerInterface
            enabled = yes
            device = lo0
            listen_port = 0
        """))
        let server = try XCTUnwrap(stack.transport.interfaces.first as? TCPServerInterface)
        XCTAssertEqual(server.bindIP, "127.0.0.1",
                       "`device` names a network device whose address replaces the wildcard "
                       + "(`TCPInterface.py:517,548`); it was read by nothing")
    }
}
