import XCTest
@testable import ReticulumSwift

/// Tests for Destination static hash utilities and sign method.
/// Mirrors Python's `Destination.hash()`, `Destination.hash_from_name_and_identity()`,
/// `Destination.app_and_aspects_from_name()`, and `Destination.sign()`.
final class DestinationHashTests: XCTestCase {

    // MARK: - Destination.hash()

    func testStaticHashMatchesInstanceHash() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "myapp", aspects: ["service"])
        let computed = Destination.hash(identity: id, appName: "myapp", aspects: ["service"])
        XCTAssertEqual(computed, dest.hash)
    }

    func testStaticHashConsistentWithoutIdentity() {
        let h1 = Destination.hash(identity: nil, appName: "myapp", aspects: ["pub"])
        let h2 = Destination.hash(identity: nil, appName: "myapp", aspects: ["pub"])
        XCTAssertEqual(h1, h2)
    }

    func testStaticHashDiffersWithDifferentIdentity() {
        let id1 = Identity()
        let id2 = Identity()
        let h1 = Destination.hash(identity: id1, appName: "myapp", aspects: [])
        let h2 = Destination.hash(identity: id2, appName: "myapp", aspects: [])
        XCTAssertNotEqual(h1, h2)
    }

    func testStaticHashLength() {
        let h = Destination.hash(identity: nil, appName: "test", aspects: [])
        XCTAssertEqual(h.count, Constants.truncatedHashLength)
    }

    // MARK: - Destination.hash(fromFullName:identity:)

    func testHashFromFullNameMatchesInstanceHash() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "lxmf", aspects: ["delivery"])
        let fromFull = Destination.hash(fromFullName: "lxmf.delivery", identity: id)
        XCTAssertEqual(fromFull, dest.hash)
    }

    // MARK: - Destination.appAndAspects(fromFullName:)

    func testAppAndAspectsSimple() {
        let (appName, aspects) = Destination.appAndAspects(fromFullName: "myapp")
        XCTAssertEqual(appName, "myapp")
        XCTAssertEqual(aspects, [])
    }

    func testAppAndAspectsWithAspects() {
        let (appName, aspects) = Destination.appAndAspects(fromFullName: "lxmf.delivery.inbox")
        XCTAssertEqual(appName, "lxmf")
        XCTAssertEqual(aspects, ["delivery", "inbox"])
    }

    // MARK: - Destination.sign()

    func testSignProducesValidSignature() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["sign"])
        let message = Data("hello".utf8)
        let sig = dest.sign(message)
        XCTAssertNotNil(sig)
        XCTAssertEqual(sig?.count, Constants.signatureLength)
        // Signature should validate with the identity's public key
        XCTAssertTrue(id.validate(signature: sig!, for: message))
    }

    func testSignReturnsNilForPlainDestination() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "test", aspects: [])
        let sig = dest.sign(Data("msg".utf8))
        XCTAssertNil(sig)
    }

    func testSignReturnsNilForOutboundWithoutPrivateKey() throws {
        let id = Identity()
        // Public-only identity can't sign
        let pubOnly = try Identity(publicKeyBytes: id.publicKeyBytes)
        let dest = try Destination(identity: pubOnly, direction: .out, kind: .single,
                                   appName: "test", aspects: [])
        let sig = dest.sign(Data("msg".utf8))
        XCTAssertNil(sig)
    }
}
