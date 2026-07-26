import XCTest
@testable import ReticulumSwift

/// The `type` and `short_name` fields a Python peer reads out of the interface-stats
/// payload.
///
/// Python builds them as `type(interface).__name__` and `str(interface.name)`
/// (RNS/Reticulum.py:1425-1427). Deriving `type` reflectively in Swift publishes the Swift
/// class name, which for the two shared-instance interfaces is not what Python calls them —
/// so a Python `rnstatus -d` against a Swift daemon shows an interface kind that does not
/// exist in RNS.
///
/// Caught by pointing the real Python `rnstatus -j` at a Swift `rnsd`: it reported
/// `"type": "PosixTCPServer"` where a Python daemon reports `"LocalServerInterface"`.
final class InterfaceStatsIdentityTests: XCTestCase {

    // MARK: - The two interfaces Python names differently

    func testSharedInstanceServerPublishesPythonsClassName() {
        // Python: class LocalServerInterface (RNS/Interfaces/LocalInterface.py:377).
        let server = PosixTCPServer(name: "Shared Instance", port: 37428)
        XCTAssertEqual(server.statsTypeName, "LocalServerInterface")
    }

    func testSharedInstanceServerPublishesPythonsShortName() {
        // Python: `self.name = "Reticulum"` (LocalInterface.py:391) while __str__ stays
        // "Shared Instance[<port>]" — the two are deliberately different strings.
        let server = PosixTCPServer(name: "Shared Instance", port: 37428)
        XCTAssertEqual(server.statsShortName, "Reticulum")
        XCTAssertEqual(server.displayName, "Shared Instance[37428]")
    }

    func testLocalClientPublishesPythonsClassName() {
        // Python: class LocalClientInterface (LocalInterface.py:62). The Swift class is
        // named for Python's __str__, not its class name.
        let client = LocalInterface(host: "127.0.0.1", port: 37428)
        XCTAssertEqual(client.statsTypeName, "LocalClientInterface")
        XCTAssertEqual(client.displayName, "LocalInterface[37428]")
    }

    // MARK: - Everything else keeps reflecting over the Swift type

    func testOrdinaryInterfacesKeepTheirOwnTypeName() {
        // These names are identical in both implementations, so the reflective default is
        // already correct and must not be overridden into a stale hardcoded list.
        let udp = UDPInterface(name: "Isolated UDP", listenPort: 4242, forwardPort: 4243)
        XCTAssertEqual(udp.statsTypeName, "UDPInterface")
        XCTAssertEqual(udp.statsShortName, "Isolated UDP")
    }

    // MARK: - The payload actually carries them

    func testPayloadUsesThePublishedNamesNotTheSwiftType() throws {
        let transport = Transport()
        let server = PosixTCPServer(name: "Shared Instance", port: 37428)
        transport.register(interface: server)
        defer { transport.deregister(interface: server) }

        let payload = InterfaceStatsPayload.build(transport)
        let interfaces = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray)
        let entry = try XCTUnwrap(interfaces.first?.asDictionary)

        XCTAssertEqual(entry["type"]?.asString, "LocalServerInterface")
        XCTAssertEqual(entry["short_name"]?.asString, "Reticulum")
        XCTAssertEqual(entry["name"]?.asString, "Shared Instance[37428]")
    }
}
