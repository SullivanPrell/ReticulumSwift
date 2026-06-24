import XCTest
@testable import ReticulumSwift

final class DestinationRetentionTests: XCTestCase {

    // Inject a known identity into transport so retain/unretain have something to act on
    private func makeTransportWithDestination() throws -> (Transport, Data, Identity) {
        let transport = Transport()
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "test", aspects: ["retain"])
        transport.register(destination: dest)
        // Also store in knownIdentities via restore
        transport.restore(identity: identity, forDestination: dest.hash)
        return (transport, dest.hash, identity)
    }

    // MARK: - retainDestinationData

    func testRetainDestinationDataReturnsTrueForKnown() throws {
        let (transport, destHash, _) = try makeTransportWithDestination()
        XCTAssertTrue(transport.retainDestinationData(destHash))
    }

    func testRetainDestinationDataReturnsFalseForUnknown() throws {
        let transport = Transport()
        let unknownHash = Data(repeating: 0xAA, count: 16)
        XCTAssertFalse(transport.retainDestinationData(unknownHash))
    }

    func testRetainedDestinationSurvivesClean() throws {
        let (transport, destHash, _) = try makeTransportWithDestination()
        transport.retainDestinationData(destHash)
        // Run clean with a far-future "now" — retained destination must survive
        let farFuture = Date().addingTimeInterval(Transport.unusedDestinationLinger * 10)
        transport.cleanKnownDestinations(now: farFuture)
        XCTAssertNotNil(transport.recall(identity: destHash),
                        "Retained destination should survive clean")
    }

    func testUnretainedDestinationRemovedByClean() throws {
        let (transport, destHash, _) = try makeTransportWithDestination()
        // Do NOT retain — should be removed when far-future clean runs (no path, never used)
        let farFuture = Date().addingTimeInterval(Transport.unusedDestinationLinger * 10)
        transport.cleanKnownDestinations(now: farFuture)
        XCTAssertNil(transport.recall(identity: destHash),
                     "Unretained unused destination should be cleaned up")
    }

    // MARK: - unretainDestinationData

    func testUnretainDestinationDataReturnsTrueForKnown() throws {
        let (transport, destHash, _) = try makeTransportWithDestination()
        transport.retainDestinationData(destHash)
        XCTAssertTrue(transport.unretainDestinationData(destHash))
    }

    func testUnretainDestinationDataReturnsFalseForUnknown() throws {
        let transport = Transport()
        let unknownHash = Data(repeating: 0xBB, count: 16)
        XCTAssertFalse(transport.unretainDestinationData(unknownHash))
    }

    func testUnretainedDestinationBecomesEligibleForClean() throws {
        let (transport, destHash, _) = try makeTransportWithDestination()
        transport.retainDestinationData(destHash)
        transport.unretainDestinationData(destHash)
        let farFuture = Date().addingTimeInterval(Transport.unusedDestinationLinger * 10)
        transport.cleanKnownDestinations(now: farFuture)
        XCTAssertNil(transport.recall(identity: destHash),
                     "Unretained destination should be cleaned up after unretain")
    }

    // MARK: - retainIdentity

    func testRetainIdentityPinsAllMatchingDestinations() throws {
        let (transport, destHash, identity) = try makeTransportWithDestination()
        let retained = transport.retainIdentity(identity.hash)
        XCTAssertTrue(retained)
        // Destination associated with this identity must survive a far-future clean
        let farFuture = Date().addingTimeInterval(Transport.unusedDestinationLinger * 10)
        transport.cleanKnownDestinations(now: farFuture)
        XCTAssertNotNil(transport.recall(identity: destHash))
    }

    func testRetainIdentityReturnsFalseForUnknownIdentity() throws {
        let transport = Transport()
        let unknownIdentityHash = Data(repeating: 0xCC, count: 16)
        XCTAssertFalse(transport.retainIdentity(unknownIdentityHash))
    }
}
