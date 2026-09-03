import XCTest
@testable import ReticulumSwift

/// How far back a destination can still decrypt.
///
/// Python keeps the active ratchet and its predecessors in one list — `rotate_ratchets`
/// does `self.ratchets.insert(0, new_ratchet)` (`Destination.py:234`) and the announce
/// advertises `self.ratchets[0]` (`:287`) — capped by `_clean_ratchets` at
/// `retained_ratchets`, default `RATCHET_COUNT = 512` (`:209`, `:166`, `:85`).
///
/// Swift splits the same list in two: `Identity.activeRatchetPrivateKey` plus
/// `previousRatchets`, recombined by `ratchetPrivateKeyPool`. So the retained *total* is
/// `ratchetHistoryDepth + 1`, and the Python-facing number is the total — which is what
/// `Destination.setRetainedRatchets` takes and what these tests assert.
final class RatchetRetentionTests: XCTestCase {

    /// Rotate `count` times, ignoring the interval gate (`rotateRatchet` is the unconditional
    /// form; `rotateRatchetIfNeeded` is the one that waits for `ratchetInterval`).
    private func rotate(_ identity: Identity, times count: Int) {
        for _ in 0..<count { identity.rotateRatchet() }
    }

    private func sealed(to ratchetPub: Data, for recipient: Identity, _ text: String) throws -> Data {
        let pubOnly = try Identity(publicKeyBytes: recipient.publicKeyBytes)
        return try pubOnly.encrypt(Data(text.utf8), ratchetPublicKey: ratchetPub)
    }

    // MARK: - Retention depth

    func testTheRetainedPoolHoldsAsManyRatchetsAsPython() {
        let identity = Identity()
        rotate(identity, times: Destination.ratchetCount + 200)
        // Python: len(self.ratchets) == retained_ratchets == 512, active included.
        XCTAssertEqual(identity.ratchetPrivateKeyPool.count, Destination.ratchetCount)
    }

    func testTheDefaultDepthIsDerivedFromTheDestinationConstant() {
        // The one place the two constants are allowed to disagree is by the active ratchet,
        // which Swift stores outside the history and Python stores at index 0.
        XCTAssertEqual(Identity().ratchetHistoryDepth + 1, Destination.ratchetCount)
    }

    // MARK: - What that buys on the wire

    func testAPeerEncryptingToALongStaleRatchetStillDecrypts() throws {
        let recipient = Identity()
        recipient.rotateRatchet()
        let stalePub = try XCTUnwrap(recipient.activeRatchetPublicKey)
        let token = try sealed(to: stalePub, for: recipient, "sent before a long silence")

        // A sender caches an announced ratchet until it expires (30 days) or it hears a
        // newer announce. At the 30-minute RATCHET_INTERVAL a receiver that announces
        // steadily burns 48 ratchets a day, so "a few hundred rotations behind" is an
        // ordinary sender that was simply offline for a week — not a pathological case.
        rotate(recipient, times: 400)

        let recovered = try recipient.decrypt(
            token,
            ratchetPrivateKeys: recipient.ratchetPrivateKeyPool,
            enforceRatchets: true
        )
        XCTAssertEqual(String(decoding: recovered.plaintext, as: UTF8.self),
                       "sent before a long silence")
    }

    func testTheOldestRetainedRatchetDecryptsAndTheOneBeyondItDoesNot() throws {
        let recipient = Identity()
        recipient.rotateRatchet()
        let oldestPub = try XCTUnwrap(recipient.activeRatchetPublicKey)
        let token = try sealed(to: oldestPub, for: recipient, "right at the edge")

        // After 511 further rotations this ratchet is the 512th and last entry.
        rotate(recipient, times: Destination.ratchetCount - 1)
        let recovered = try recipient.decrypt(
            token,
            ratchetPrivateKeys: recipient.ratchetPrivateKeyPool,
            enforceRatchets: true
        )
        XCTAssertEqual(String(decoding: recovered.plaintext, as: UTF8.self), "right at the edge")

        // One more rotation pushes it off the end, exactly as Python's slice does.
        recipient.rotateRatchet()
        XCTAssertThrowsError(try recipient.decrypt(
            token,
            ratchetPrivateKeys: recipient.ratchetPrivateKeyPool,
            enforceRatchets: true
        )) { error in
            XCTAssertEqual(error as? Identity.IdentityError, .decryptionFailed)
        }
    }

    // MARK: - setRetainedRatchets counts the way Python counts

    func testSetRetainedRatchetsCountsTheActiveRatchet() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "test", aspects: ["ratchets"]
        )
        destination.setRetainedRatchets(4)
        rotate(identity, times: 40)
        // Python `self.ratchets[:4]` leaves four keys in total, of which one is active.
        XCTAssertEqual(identity.ratchetPrivateKeyPool.count, 4)
    }

    func testRetainingOneRatchetKeepsOnlyTheActiveOne() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "test", aspects: ["ratchets"]
        )
        destination.setRetainedRatchets(1)
        rotate(identity, times: 10)
        XCTAssertEqual(identity.ratchetPrivateKeyPool.count, 1)
        XCTAssertEqual(identity.ratchetPrivateKeyPool.first, identity.activeRatchetPrivateKey)
    }
}
