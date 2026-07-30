import XCTest
@testable import ReticulumSwift

/// One construction site for **every** concrete `Interface` the library ships.
///
/// This exists because `bugs/022` and `bugs/025` both got in through the same hole: a test that
/// declared it covered "every concrete interface" and in fact covered a hand-picked three — the
/// three that were already correct (`InterfaceGetterTests.swift:46-60`). Any requirement that is
/// supposed to hold for all interfaces asserts it over `everyConcreteInterface()`, and
/// `InterfaceConformerCoverageTests` fails if a conformer exists in `Sources/` that this file does
/// not construct. Adding an interface type therefore cannot silently escape the protocol-wide
/// requirements.
///
/// Test doubles are deliberately **not** included: a double that can do something the real type
/// cannot is not a test of the real type (`bugs/025`, "Why the tests do not catch any of it").
enum InterfaceConformers {

    /// The Swift type names of every conformer. Note these are *not* always the same as the
    /// published `statsTypeName` — a spawned TCP-server client is a `TCPServerClientInterface`
    /// in Swift and publishes `TCPClientInterface`, which is correct per Python and is exactly
    /// what `bugs/022` is about. `InterfaceConformerCoverageTests` cross-checks this list against
    /// the `Sources/` tree.
    static let expectedTypeNames: Set<String> = [
        "AutoInterface",
        "AX25KISSInterface",
        "BackboneInterface",
        "BLEMeshInterface",
        "I2PInterface",
        "I2PInterfacePeer",
        "KISSInterface",
        "LocalInterface",
        "PosixTCPServer",
        "RNodeInterface",
        "RNodeMultiInterface",
        "RNodeSubInterface",
        "SerialInterface",
        "TCPClientInterface",
        "TCPServerInterface",
        "TCPServerClientInterface",
        "UDPInterface",
        "WeaveInterface",
        "WeaveInterfacePeer",
    ]

    /// Every concrete conformer, constructed with the least ceremony that yields a usable object.
    /// Nothing here is started, so no socket is opened and no device is touched.
    static func everyConcreteInterface() throws -> [any Interface] {
        var all: [any Interface] = []

        all.append(AutoInterface(name: "auto0"))
        all.append(BackboneInterface(name: "backbone0", host: "10.0.0.1", port: 4242))
        all.append(BLEMeshInterface(name: "ble0", transport: RegistryBLEMeshTransport()))
        all.append(LocalInterface(name: "local0", port: 37428))
        all.append(PosixTCPServer(name: "posix0", port: 4243))
        all.append(TCPClientInterface(name: "tcp0", host: "127.0.0.1", port: 4242))
        all.append(UDPInterface(name: "udp0", listenPort: 4244))

        // Serial family — these need a transport; the mocks live alongside their own suites.
        all.append(SerialInterface(name: "serial0", port: "/dev/null",
                                   transport: MockSerialPort()))
        all.append(KISSInterface(name: "kiss0", port: "/dev/null",
                                 transport: MockSerialPort()))
        all.append(try AX25KISSInterface(name: "ax250", port: "/dev/null",
                                        callsign: "NOCALL", ssid: 0,
                                        transport: MockSerialPort()))
        all.append(WeaveInterface(name: "weave0", port: "/dev/null",
                                  transport: MockSerialPort()))

        // RNode family.
        all.append(RNodeInterface(name: "rnode0", transport: MockRNodeTransport()))
        let sub = RNodeSubInterface(name: "sub0", index: 0, interfaceType: "LoRa",
                                   frequency: 867_200_000, bandwidth: 125_000,
                                   txPower: 0, sf: 8, cr: 5)
        all.append(sub)
        all.append(try RNodeMultiInterface(name: "rnodemulti0",
                                           transport: MockRNodeTransport(),
                                           subInterfaces: [sub]))

        // I2P.
        let i2p = I2PInterface(name: "i2p0", daemon: MockI2PDaemon(),
                               dataDirectory: URL(fileURLWithPath: "/tmp"))
        all.append(i2p)
        all.append(I2PInterfacePeer(name: "i2ppeer0",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: i2p))

        // Server-spawned per-connection interfaces. These are the ones `bugs/027` is about, so
        // they must be in the enumeration even though an operator never configures one directly.
        let server = TCPServerInterface(name: "tcpserver0", port: 4245)
        all.append(server)
        all.append(TCPServerClientInterface(name: "Client on tcpserver0",
                                            parentServer: server,
                                            peerHost: "10.0.0.9", peerPort: 51000))

        let weaveOwner = WeaveInterface(name: "weaveowner0", port: "/dev/null",
                                        transport: MockSerialPort())
        all.append(WeaveInterfacePeer(owner: weaveOwner,
                                      endpointAddr: Data([0x01, 0x02, 0x03, 0x04])))

        return all
    }
}

/// A do-nothing `BLEMeshTransport`. Declared here under its own name because
/// `BLEMeshInterfaceTests`' equivalent is file-private and therefore not reusable.
final class RegistryBLEMeshTransport: BLEMeshTransport {
    var peerConnected: ((BLEMeshPeerID) -> Void)?
    var peerDisconnected: ((BLEMeshPeerID) -> Void)?
    var peerDataHandler: ((BLEMeshPeerID, Data) -> Void)?
    var connectedPeers: [BLEMeshPeerID] = []
    func start() throws {}
    func stop() {}
    func send(_ data: Data, to peer: BLEMeshPeerID) throws {}
}

/// Guards the registry above against drift.
final class InterfaceConformerCoverageTests: XCTestCase {

    /// Every type declared as an `Interface` conformer in `Sources/` must appear in the registry.
    ///
    /// This is a structural check, deliberately. `bugs/022` and `bugs/025` both survived because
    /// the protocol-wide assertions ran over a hand-listed subset, and no behavioural test can
    /// notice a type that was never added to the list.
    func testRegistryCoversEveryConformerInSources() throws {
        let interfacesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ReticulumSwiftTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Sources/ReticulumSwift/Interfaces")

        let files = try FileManager.default.contentsOfDirectory(at: interfacesDir,
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        // Matches `final class Foo: Interface`, `class Foo: SomeProtocol, Interface`, etc.
        let pattern = try NSRegularExpression(
            pattern: #"class\s+(\w+)\s*:\s*([^\{]*\b(?:Interface|LocalClientServingInterface)\b[^\{]*)\{"#
        )

        var declared: Set<String> = []
        for file in files {
            let src = try String(contentsOf: file, encoding: .utf8)
            let ns = src as NSString
            for m in pattern.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
                let typeName = ns.substring(with: m.range(at: 1))
                let inheritance = ns.substring(with: m.range(at: 2))
                // Skip conformances to unrelated protocols that merely contain "Interface"
                // in a longer name (e.g. `: RNodeTransportInterfaceDelegate`).
                let conforms = inheritance
                    .split(whereSeparator: { ",: \t\n".contains($0) })
                    .contains { $0 == "Interface" || $0 == "LocalClientServingInterface" }
                if conforms { declared.insert(typeName) }
            }
        }

        XCTAssertFalse(declared.isEmpty,
                       "Found no Interface conformers in \(interfacesDir.path) — the scan is broken, "
                       + "not the tree")

        let missing = declared.subtracting(InterfaceConformers.expectedTypeNames)
        XCTAssertTrue(missing.isEmpty,
                      """
                      Interface conformer(s) not covered by InterfaceConformers: \(missing.sorted()).
                      Add them to `expectedTypeNames` AND construct them in `everyConcreteInterface()`,
                      then make sure the protocol-wide requirements still hold for them. This guard
                      exists because bugs/022 and bugs/025 both got in through a hand-listed subset.
                      """)

        let stale = InterfaceConformers.expectedTypeNames.subtracting(declared)
        XCTAssertTrue(stale.isEmpty,
                      "expectedTypeNames lists type(s) that no longer conform: \(stale.sorted())")
    }

    /// The registry must actually build every one of them.
    func testRegistryConstructsEveryListedType() throws {
        let all = try InterfaceConformers.everyConcreteInterface()
        let built = Set(all.map { String(describing: type(of: $0)) })
        let notBuilt = InterfaceConformers.expectedTypeNames.subtracting(built)
        XCTAssertTrue(notBuilt.isEmpty,
                      "Listed but not constructed by everyConcreteInterface(): \(notBuilt.sorted())")
    }
}
