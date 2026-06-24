import XCTest
@testable import ReticulumSwift

/// Tests verifying destination hash computation against Python reference test vectors.
/// These use the same test vectors as Python's tests/link.py.
final class KnownDestinationHashTests: XCTestCase {

    // From Python tests: fixed_keys[0] = ("f8953f...", "650b5d...")
    let id1PrivKey = "f8953ffaf607627e615603ff1530c82c434cf87c07179dd7689ea776f30b964cfb7ba6164af00c5111a45e69e57d885e1285f8dbfe3a21e95ae17cf676b0f8b7"
    let id1Hash = "650b5d76b6bec0390d1f8cfca5bd33f9"

    // Python: RNS.Destination(id1, RNS.Destination.OUT, RNS.Destination.SINGLE,
    //                         "rns_unit_tests", "link", "establish")
    //         → hash = "fb48da0e82e6e01ba0c014513f74540d"
    let expectedDestHash = "fb48da0e82e6e01ba0c014513f74540d"

    func testIdentityHashMatchesPython() throws {
        guard let privBytes = Data(hex: id1PrivKey) else {
            return XCTFail("invalid key hex")
        }
        let id = try Identity(privateKeyBytes: privBytes)
        XCTAssertEqual(id.hexHash, id1Hash)
    }

    func testDestinationHashMatchesPython() throws {
        guard let privBytes = Data(hex: id1PrivKey) else {
            return XCTFail("invalid key hex")
        }
        let id = try Identity(privateKeyBytes: privBytes)
        XCTAssertEqual(id.hexHash, id1Hash)

        let dest = try Destination(
            identity: id,
            direction: .out,
            kind: .single,
            appName: "rns_unit_tests",
            aspects: ["link", "establish"]
        )
        XCTAssertEqual(dest.hexHash, expectedDestHash,
            "Destination hash must match Python reference for same key and name")
    }

    func testDestinationHashIsStable() throws {
        guard let privBytes = Data(hex: id1PrivKey) else { return }
        let id = try Identity(privateKeyBytes: privBytes)

        let d1 = try Destination(identity: id, direction: .out, kind: .single,
                                  appName: "rns_unit_tests", aspects: ["link", "establish"])
        let d2 = try Destination(identity: id, direction: .in, kind: .single,
                                  appName: "rns_unit_tests", aspects: ["link", "establish"])
        // Direction doesn't affect hash (only identity, name, and aspects matter)
        XCTAssertEqual(d1.hash, d2.hash)
        XCTAssertEqual(d1.hexHash, expectedDestHash)
    }

    // Additional known vector: check that the transport APP_NAME hash is stable
    func testPathRequestDestinationHash() {
        // Python: Transport.path_request_destination = RNS.Destination(None, IN, PLAIN, "rnstransport", "path", "request")
        let nameHash = Destination.computeNameHash(appName: "rnstransport", aspects: ["path", "request"])
        let destHash = Destination.computeHash(identity: nil, nameHash: nameHash, kind: .plain)
        XCTAssertEqual(destHash, Transport.pathRequestDestinationHash,
            "Path request destination hash must match Transport.pathRequestDestinationHash")
    }
}
