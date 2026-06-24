import XCTest
@testable import ReticulumSwift

final class NetworkDestinationTests: XCTestCase {

    func testNetworkDestinationsNotCreatedWithoutNetworkIdentity() {
        let transport = Transport()
        transport.transportIdentity = Identity()
        let countBefore = transport.registeredDestinations.count
        transport.setupNetworkDestinations()
        XCTAssertEqual(transport.registeredDestinations.count, countBefore,
                       "No network destinations should be created without networkIdentity")
    }

    func testNetworkDestinationsCreatedWhenNetworkIdentitySet() {
        let transport = Transport()
        let netIdentity = Identity()
        transport.setNetworkIdentity(netIdentity)
        let countBefore = transport.registeredDestinations.count
        transport.setupNetworkDestinations()
        XCTAssertEqual(transport.registeredDestinations.count, countBefore + 2,
                       "Two network destinations should be created: network and network.instance.<hex>")
    }

    func testNetworkDestinationHashMatchesExpected() throws {
        let netIdentity = Identity()
        let transport = Transport()
        transport.setNetworkIdentity(netIdentity)
        transport.setupNetworkDestinations()

        let expected = try Destination(identity: netIdentity, direction: .in, kind: .single,
                                        appName: "rnstransport", aspects: ["network"])
        XCTAssertNotNil(transport.registeredDestinations[expected.hash],
                        "Network destination should be registered with correct hash")
    }

    func testNetworkInstanceDestinationHashMatchesExpected() throws {
        let netIdentity = Identity()
        let transport = Transport()
        transport.setNetworkIdentity(netIdentity)
        transport.setupNetworkDestinations()

        let hexHash = netIdentity.hash.map { String(format: "%02x", $0) }.joined()
        let expected = try Destination(identity: netIdentity, direction: .in, kind: .single,
                                        appName: "rnstransport",
                                        aspects: ["network", "instance", hexHash])
        XCTAssertNotNil(transport.registeredDestinations[expected.hash],
                        "Network instance destination should be registered with correct hash")
    }

    func testNetworkDestinationsUseNetworkIdentity() {
        let netIdentity = Identity()
        let transport = Transport()
        transport.setNetworkIdentity(netIdentity)
        transport.setupNetworkDestinations()

        let found = transport.registeredDestinations.values.filter {
            $0.identity?.hash == netIdentity.hash
        }
        XCTAssertEqual(found.count, 2, "Both network destinations should use network identity")
    }

    func testSetupNetworkDestinationsIdempotent() {
        let netIdentity = Identity()
        let transport = Transport()
        transport.setNetworkIdentity(netIdentity)
        transport.setupNetworkDestinations()
        let countAfterFirst = transport.registeredDestinations.count
        transport.setupNetworkDestinations()
        // Calling again just re-registers same destinations (same hashes, same entries).
        // The count should not grow (register(destination:) is idempotent for same hash).
        XCTAssertEqual(transport.registeredDestinations.count, countAfterFirst,
                       "Re-running setupNetworkDestinations should not add duplicate entries")
    }
}
