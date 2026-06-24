import XCTest
@testable import ReticulumSwift

/// Tests for Python-parity getter methods on the `Interface` protocol:
///   Interface.get_hash()   → Interface.getHash()
///   Interface.bitrate      → Interface.getBitrate()
///   Interface.mode         → Interface.getMode()
///
/// Python accesses these as direct attributes or via `get_hash()`;
/// Swift exposes them as explicit `get*()` methods on the protocol extension.
final class InterfaceGetterTests: XCTestCase {

    // MARK: - getHash

    func testGetHashMatchesHashProperty() {
        let lo = LoopbackInterface(name: "TestGetterLo")
        XCTAssertEqual(lo.getHash(), lo.hash,
                       "getHash() must return the same value as the hash property")
    }

    func testGetHashIs32Bytes() {
        let lo = LoopbackInterface(name: "TestGetterLo32")
        XCTAssertEqual(lo.getHash().count, 32,
                       "Interface hash is a full SHA-256 (32 bytes)")
    }

    func testGetHashDependsOnName() {
        let a = LoopbackInterface(name: "InterfaceA")
        let b = LoopbackInterface(name: "InterfaceB")
        XCTAssertNotEqual(a.getHash(), b.getHash(),
                          "Interfaces with different names must produce different hashes")
    }

    func testGetHashDeterministic() {
        let a1 = LoopbackInterface(name: "Stable")
        let a2 = LoopbackInterface(name: "Stable")
        XCTAssertEqual(a1.getHash(), a2.getHash(),
                       "Same name always produces the same hash")
    }

    /// Mirrors Python's `Interface.get_hash()` = `full_hash(str(self).encode("utf-8"))`:
    /// the hash must be derived from the type-qualified `displayName` (Python's
    /// `__str__`), not the bare `name`. This must hold via dynamic dispatch for
    /// every concrete interface that overrides `displayName` — `displayName` is
    /// declared as a protocol requirement specifically so these resolve to the
    /// override rather than the `Interface` extension's `{ name }` default.
    func testHashDerivesFromOverriddenDisplayNameViaDynamicDispatch() {
        let auto = AutoInterface(name: "auto0")
        XCTAssertEqual(auto.displayName, "AutoInterface[auto0]")
        XCTAssertEqual(auto.hash, Hashes.fullHash(Data(auto.displayName.utf8)))
        XCTAssertNotEqual(auto.hash, Hashes.fullHash(Data(auto.name.utf8)))

        let tcpClient = TCPClientInterface(name: "tcp0", host: "127.0.0.1", port: 4242)
        XCTAssertEqual(tcpClient.displayName, "TCPInterface[Client on 127.0.0.1:4242]")
        XCTAssertEqual(tcpClient.hash, Hashes.fullHash(Data(tcpClient.displayName.utf8)))
        XCTAssertNotEqual(tcpClient.hash, Hashes.fullHash(Data(tcpClient.name.utf8)))

        let local = LocalInterface(name: "local0", port: 37428)
        XCTAssertEqual(local.displayName, "LocalInterface[37428]")
        XCTAssertEqual(local.hash, Hashes.fullHash(Data(local.displayName.utf8)))
        XCTAssertNotEqual(local.hash, Hashes.fullHash(Data(local.name.utf8)))
    }

    // MARK: - getBitrate

    func testGetBitrateMatchesBitrateProperty() {
        let lo = LoopbackInterface(name: "TestBitrate")
        XCTAssertEqual(lo.getBitrate(), lo.bitrate,
                       "getBitrate() must return the same value as the bitrate property")
    }

    func testGetBitrateReflectsCurrentBitrateValue() {
        // getBitrate() must always mirror the bitrate property, whatever its value.
        let lo = LoopbackInterface(name: "TestBitratePos")
        XCTAssertEqual(lo.getBitrate(), lo.bitrate,
                       "getBitrate() must equal the bitrate property")
    }

    // MARK: - getMode

    func testGetModeMatchesModeProperty() {
        let lo = LoopbackInterface(name: "TestMode")
        XCTAssertEqual(lo.getMode(), lo.mode,
                       "getMode() must return the same value as the mode property")
    }

    func testGetModeDefaultIsFull() {
        // LoopbackInterface uses the default mode from the extension (.full).
        let lo = LoopbackInterface(name: "TestModeFull")
        XCTAssertEqual(lo.getMode(), .full,
                       "Default interface mode must be .full")
    }
}
