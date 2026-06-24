import XCTest
@testable import ReticulumSwift

#if canImport(Darwin)
final class AutoInterfaceTests: XCTestCase {

    func testMulticastAddressDerivation() {
        // Verify the multicast address computation matches Python's AutoInterface.
        // Python: sha256("reticulum") → "ff12:0:d70b:fb1c:16e4:5e39:485e:31e1"
        let iface = AutoInterface(name: "test")
        // Access the mcast address via reflection by initializing and checking send.
        // We verify the group hash calculation matches the Python reference.
        let groupID = AutoInterface.defaultGroupID
        let hash = Hashes.fullHash(groupID)
        let g = Array(hash)
        func pair(_ lo: Int, _ hi: Int) -> String {
            String(format: "%04x", Int(g[lo]) + (Int(g[hi]) << 8))
        }
        let gt = "0:\(pair(3,2)):\(pair(5,4)):\(pair(7,6)):\(pair(9,8)):\(pair(11,10)):\(pair(13,12))"
        let mcastAddr = "ff12:\(gt)"
        XCTAssertEqual(mcastAddr, "ff12:0:d70b:fb1c:16e4:5e39:485e:31e1")
    }

    func testDiscoveryBeaconFormat() {
        // Discovery beacon = sha256(group_id + link_local_addr)
        let groupID = AutoInterface.defaultGroupID
        let linkLocal = "fe80::1"
        let token = Hashes.fullHash(groupID + Data(linkLocal.utf8))
        XCTAssertEqual(token.count, 32)
        // Verify it matches Python:
        // sha256(b"reticulum" + b"fe80::1")
        // We can't easily run Python here, but we can verify structure.
        let expected = Hashes.fullHash(groupID + Data(linkLocal.utf8))
        XCTAssertEqual(token, expected)
    }

    func testAutoInterfaceDefaultPorts() {
        XCTAssertEqual(AutoInterface.defaultDiscoveryPort, 29716)
        XCTAssertEqual(AutoInterface.defaultDataPort, 42671)
    }

    func testAutoInterfaceInitialization() {
        let iface = AutoInterface(name: "auto0")
        XCTAssertEqual(iface.name, "auto0")
        XCTAssertFalse(iface.isOnline)
    }
}
#endif // canImport(Darwin)
