import XCTest
@testable import ReticulumSwift

/// The last three implemented interface types a config file could not build — the remainder of
/// `bugs/031` after the first four cases landed. Python constructs `SerialInterface`
/// (`Reticulum.py:1024-1026`), `RNodeMultiInterface` (`:1044-1047`, plus `start()`) and
/// `WeaveInterface` (`:1049-1051`) from their blocks; this port had real, tested classes for all
/// three and dropped their config entries through the default case with an ERROR log calling
/// them "Unsupported" — a daemon configured with any of them started healthy and had no presence
/// on that medium. Weave is the aggravated case: this port's own discovery emits
/// `type = WeaveInterface` config entries (`InterfaceDiscovery.swift`, mirroring
/// `Discovery.py:380-392`) that its own config path then rejected.
///
/// `PipeInterface` is the one documented divergence: not implemented by design (macOS/Linux
/// subprocess pipes, no mobile use case — CLAUDE.md "Deferred Indefinitely"), so its block takes
/// the loud unknown-type path, pinned here so the divergence stays recorded.
final class RemainingConstructionTests: XCTestCase {

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
        func open() throws {}
        func close() {}
        func write(_ data: Data) throws {}
    }

    private var savedSerial: ((String) throws -> SerialPortTransport)?
    private var savedRNode: ((String) throws -> RNodeTransport)?
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        savedSerial = InterfaceTransportFactories.serial
        savedRNode = InterfaceTransportFactories.rnode
        InterfaceTransportFactories.serial = { _ in StubSerialPort() }
        InterfaceTransportFactories.rnode = { _ in StubRNodeTransport() }
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rns_restconstruct_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        InterfaceTransportFactories.serial = savedSerial
        InterfaceTransportFactories.rnode = savedRNode
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
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

    // MARK: - The parser must see sub-blocks as sub-blocks

    /// A `[[[sub]]]` line begins with `[[` and ends with `]]`, so the parser's subsection check
    /// matched it first and every RNodeMulti sub-interface became a *top-level* interface named
    /// `[High Datarate]` with type Unknown — the multi block itself lost its radio rows.
    func testTripleBracketBlocksParseAsSubInterfacesNotInterfaces() {
        let cfg = parse("""
          [[Dual Radio]]
            type = RNodeMultiInterface
            enabled = yes
            port = /dev/cu.usbserial-multi

            [[[High Datarate]]]
              vport = 1
              frequency = 2400000000
              bandwidth = 1625000
              txpower = 7
              spreadingfactor = 5
              codingrate = 5

            [[[Low Datarate]]]
              interface_enabled = yes
              vport = 2
              frequency = 867200000
              bandwidth = 125000
              txpower = 7
              spreadingfactor = 8
              codingrate = 5
        """)
        XCTAssertEqual(cfg.interfaces.count, 1,
                       "sub-blocks leaked out as top-level interfaces: "
                       + "\(cfg.interfaces.map(\.name))")
        let multi = cfg.interfaces[0]
        XCTAssertEqual(multi.subBlocks.map(\.name), ["High Datarate", "Low Datarate"],
                       "the radio rows must live inside their block, as configobj nests them")
        XCTAssertEqual(multi.subBlocks[0].int("frequency"), 2_400_000_000)
        XCTAssertEqual(multi.subBlocks[1].int("vport"), 2)
        XCTAssertEqual(multi["port"], "/dev/cu.usbserial-multi",
                       "the parent block's own keys stay its own")
    }

    // MARK: - The three types construct

    func testASerialBlockConstructs() throws {
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[Direct Serial]]
            type = SerialInterface
            enabled = yes
            port = /dev/cu.usbserial-ser
            speed = 57600
            parity = E
        """))
        guard let iface = stack.transport.interfaces.first(where: { $0.name == "Direct Serial" })
        else {
            return XCTFail("a SerialInterface block must construct (Reticulum.py:1024-1026); "
                           + "the class exists and its config-facing init had no caller")
        }
        let serial = try XCTUnwrap(iface as? SerialInterface)
        XCTAssertEqual(serial.speed, 57600)
        XCTAssertEqual(serial.parity, .even, "parity = E parses as Python's serial.PARITY_EVEN")
    }

    func testAWeaveBlockConstructs() throws {
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[Fabric]]
            type = WeaveInterface
            enabled = yes
            port = /dev/cu.usbserial-weave
        """))
        XCTAssertTrue(stack.transport.interfaces.contains { $0.name == "Fabric" },
                      "a WeaveInterface block must construct (Reticulum.py:1049-1051) — this "
                      + "port's own discovery emits these entries, so rejecting them makes "
                      + "discovery self-defeating for Weave")
    }

    func testAnRNodeMultiBlockConstructsWithItsSubInterfaces() throws {
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[Dual Radio]]
            type = RNodeMultiInterface
            enabled = yes
            port = /dev/cu.usbserial-multi

            [[[High Datarate]]]
              vport = 1
              frequency = 2400000000
              bandwidth = 1625000
              txpower = 7
              spreadingfactor = 5
              codingrate = 5
        """))
        guard let iface = stack.transport.interfaces.first(where: { $0.name == "Dual Radio" })
        else {
            return XCTFail("an RNodeMultiInterface block must construct "
                           + "(Reticulum.py:1044-1047)")
        }
        let multi = try XCTUnwrap(iface as? RNodeMultiInterface)
        XCTAssertEqual(multi.subInterfaces.map(\.name), ["High Datarate"])
        XCTAssertEqual(multi.subInterfaces[0].index, 1, "vport binds the sub's index")
        XCTAssertEqual(multi.subInterfaces[0].frequency, 2_400_000_000)
    }

    // MARK: - Reference failure semantics

    func testASerialBlockWithoutAPortFailsConstruction() {
        let stack = makeStack()
        XCTAssertThrowsError(try stack.synthesizeInterfaces(from: parse("""
          [[Portless]]
            type = SerialInterface
            enabled = yes
        """)), "Python raises \"No port specified for ...\" (SerialInterface.py) and rnsd "
             + "panics; constructing nothing silently is the bugs/031 shape") { error in
            XCTAssertEqual(error as? InterfaceConstructionError,
                           .missingKey(interface: "Portless", key: "port"))
        }
    }

    func testAnRNodeMultiBlockWithoutSubInterfacesFailsConstruction() {
        let stack = makeStack()
        XCTAssertThrowsError(try stack.synthesizeInterfaces(from: parse("""
          [[Empty Multi]]
            type = RNodeMultiInterface
            enabled = yes
            port = /dev/cu.usbserial-multi
        """)), "Python raises ValueError(\"No subinterfaces configured\") "
             + "(RNodeMultiInterface.py:220-222)")
    }

    /// A sub-block is enabled when its own `interface_enabled` is true **or the parent used the
    /// literal `enabled` spelling** (`RNodeMultiInterface.py:178`,`:188`) — a parent enabled via
    /// `interface_enabled` does not blanket-enable its subs. Faithfully quirky.
    func testSubInterfaceEnablementFollowsThePythonQuirk() {
        let stack = makeStack()
        XCTAssertThrowsError(try stack.synthesizeInterfaces(from: parse("""
          [[Quirk Multi]]
            type = RNodeMultiInterface
            interface_enabled = yes
            port = /dev/cu.usbserial-multi

            [[[Silent Radio]]]
              vport = 1
              frequency = 867200000
              bandwidth = 125000
              txpower = 7
              spreadingfactor = 8
              codingrate = 5
        """)), "with the parent enabled via interface_enabled and the sub carrying no "
             + "interface_enabled of its own, Python counts zero enabled subs and raises "
             + "ValueError(\"No subinterfaces enabled\")")
    }

    // MARK: - The one recorded divergence

    func testAPipeBlockTakesTheLoudUnknownTypePathByDesign() throws {
        let stack = makeStack()
        try stack.synthesizeInterfaces(from: parse("""
          [[Pipes]]
            type = PipeInterface
            enabled = yes
            command = netcat -l 5757
        """))
        XCTAssertFalse(stack.transport.interfaces.contains { $0.name == "Pipes" },
                       "PipeInterface is deliberately unimplemented (POSIX subprocess pipes, "
                       + "no mobile use case — CLAUDE.md); its block must keep taking the loud "
                       + "unknown-type ERROR path, not construct something else")
    }
}
