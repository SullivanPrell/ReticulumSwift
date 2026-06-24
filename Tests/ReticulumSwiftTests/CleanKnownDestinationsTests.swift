import XCTest
@testable import ReticulumSwift

/// Tests for Transport.cleanKnownDestinations().
/// Mirrors Python's `Identity.clean_known_destinations()`.
///
/// Python constants (Transport):
///   DESTINATION_TIMEOUT       = 60*60*24*7  = 604_800 s (7 days)
///   UNUSED_DESTINATION_LINGER = 6*60        = 360 s
///
/// Stale conditions (Python logic):
///   no path AND never-used AND last_announce > UNUSED_DESTINATION_LINGER → remove
///   no path AND was-used BUT unused_for > DESTINATION_TIMEOUT*1.25 → remove
///   has path → always keep
final class CleanKnownDestinationsTests: XCTestCase {

    // MARK: - Helpers

    private func makeTransport() -> Transport { Transport() }

    private func addIdentity(to transport: Transport,
                              announcedSecondsAgo: TimeInterval,
                              hasPath: Bool = false) -> Data {
        let identity = Identity()
        let destHash = Hashes.truncatedHash(identity.publicKeyBytes)
        let announcedAt = Date(timeIntervalSinceNow: -announcedSecondsAgo)
        transport.restore(identity: identity, forDestination: destHash, announcedAt: announcedAt)

        if hasPath {
            let path = Transport.PathEntry(
                destinationHash: destHash,
                nextHopInterfaceName: "fake0",
                hops: 1,
                lastHeard: Date(),
                identityHash: identity.hash
            )
            transport.restore(path: path, forDestination: destHash)
        }
        return destHash
    }

    // MARK: - Entries with an active path are always retained

    func testEntryWithPathIsRetained() {
        let t = makeTransport()
        // Announce a very long time ago — but there IS a path.
        let h = addIdentity(to: t, announcedSecondsAgo: Transport.destinationTimeout * 2, hasPath: true)
        t.cleanKnownDestinations()
        XCTAssertNotNil(t.recall(identity: h),
            "entry with an active path must not be cleaned regardless of age")
    }

    // MARK: - Never-used entries without a path

    func testNeverUsedPathlessEntryOlderThanLingerIsRemoved() {
        let t = makeTransport()
        let h = addIdentity(to: t, announcedSecondsAgo: Transport.unusedDestinationLinger + 1)
        t.cleanKnownDestinations()
        XCTAssertNil(t.recall(identity: h),
            "never-used pathless entry announced > UNUSED_DESTINATION_LINGER ago must be cleaned")
    }

    func testNeverUsedPathlessEntryWithinLingerIsRetained() {
        let t = makeTransport()
        let h = addIdentity(to: t, announcedSecondsAgo: Transport.unusedDestinationLinger / 2)
        t.cleanKnownDestinations()
        XCTAssertNotNil(t.recall(identity: h),
            "never-used pathless entry announced recently must be retained")
    }

    // MARK: - Used entries without a path

    func testUsedPathlessEntryNotYetExpiredIsRetained() {
        let t = makeTransport()
        // Announced 1 day ago, marked as recently used.
        let h = addIdentity(to: t, announcedSecondsAgo: 86_400)
        t.markDestinationUsed(h)
        t.cleanKnownDestinations()
        XCTAssertNotNil(t.recall(identity: h),
            "used entry not yet past DESTINATION_TIMEOUT*1.25 must be retained")
    }

    func testUsedPathlessEntryOlderThanTimeoutIsRemoved() {
        let t = makeTransport()
        let h = addIdentity(to: t, announcedSecondsAgo: Transport.destinationTimeout + 1)
        // Mark as used but the last-use was long ago.
        let lastUsed = Date(timeIntervalSinceNow: -(Transport.destinationTimeout * 1.25 + 1))
        t.markDestinationUsed(h, at: lastUsed)
        t.cleanKnownDestinations()
        XCTAssertNil(t.recall(identity: h),
            "used entry unused for > DESTINATION_TIMEOUT*1.25 without a path must be cleaned")
    }

    // MARK: - Constants match Python

    func testDestinationTimeoutConstant() {
        XCTAssertEqual(Transport.destinationTimeout, 60 * 60 * 24 * 7,
            "DESTINATION_TIMEOUT must be 7 days in seconds")
    }

    func testUnusedDestinationLingerConstant() {
        XCTAssertEqual(Transport.unusedDestinationLinger, 6 * 60,
            "UNUSED_DESTINATION_LINGER must be 6 minutes in seconds")
    }
}
