import XCTest
@testable import ReticulumSwift

/// Tests for Destination.expandName / expandName-derived helpers and
/// Destination.loadPublicKey() — all mirroring Python Destination class methods.
///
/// Python reference (Destination.py):
///   Destination.expand_name(identity, app_name, *aspects)
///     → "app.aspect1.aspect2" or "app.aspect1.<identity_hexhash>"
///   Destination.load_public_key(key)
///     → always raises TypeError; SINGLE keys live in Identity, not Destination
///
/// Swift already has expandName(identity:appName:aspects:) — these tests
/// document its contract and cover the missing loadPublicKey(_:) method.
final class DestinationExpandNameTests: XCTestCase {

    // MARK: - expandName (already implemented — contract tests)

    func testExpandNameWithoutIdentity() {
        let name = Destination.expandName(identity: nil, appName: "myapp", aspects: ["service", "node"])
        XCTAssertEqual(name, "myapp.service.node",
                       "expand_name without identity must produce 'app.a1.a2'")
    }

    func testExpandNameWithIdentity() {
        let id = Identity()
        let name = Destination.expandName(identity: id, appName: "myapp", aspects: ["node"])
        let expected = "myapp.node." + id.hexHash
        XCTAssertEqual(name, expected,
                       "expand_name with identity must append identity hexhash")
    }

    func testExpandNameNoAspects() {
        let name = Destination.expandName(identity: nil, appName: "svc", aspects: [])
        XCTAssertEqual(name, "svc")
    }

    func testExpandNameWithIdentityNoAspects() {
        let id = Identity()
        let name = Destination.expandName(identity: id, appName: "svc", aspects: [])
        XCTAssertEqual(name, "svc." + id.hexHash)
    }

    func testExpandNameDeterministic() {
        let id = Identity()
        let a = Destination.expandName(identity: id, appName: "app", aspects: ["x"])
        let b = Destination.expandName(identity: id, appName: "app", aspects: ["x"])
        XCTAssertEqual(a, b, "expand_name must be deterministic for same inputs")
    }

    // MARK: - loadPublicKey (new — was missing)

    /// Python: `load_public_key` on a SINGLE destination always raises TypeError
    /// ("A single destination holds keys through an Identity instance").
    /// Swift: should return false (no throw; keys are on the Identity).
    func testLoadPublicKeyOnSingleReturnsFalse() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["lpk"])
        let fakeKey = Data(repeating: 0xAB, count: 64)
        XCTAssertFalse(dest.loadPublicKey(fakeKey),
                       "loadPublicKey on SINGLE must return false " +
                       "(keys are held by the Identity instance)")
    }

    /// Python: `load_public_key` on PLAIN raises TypeError.
    /// Swift: should return false.
    func testLoadPublicKeyOnPlainReturnsFalse() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "test", aspects: ["lpk"])
        XCTAssertFalse(dest.loadPublicKey(Data(repeating: 0, count: 32)),
                       "loadPublicKey on PLAIN must return false")
    }

    /// GROUP destinations hold symmetric keys; loadPublicKey is an alias for loadGroupKey.
    func testLoadPublicKeyOnGroupLoadsKey() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["lpk"])
        let key = Data(repeating: 0x7F, count: 64)
        XCTAssertTrue(dest.loadPublicKey(key),
                      "loadPublicKey on GROUP must load the key and return true")
        XCTAssertEqual(dest.groupKeyBytes, key,
                       "loadPublicKey on GROUP must store the key in groupKeyBytes")
    }

    func testLoadPublicKeyOnGroupRoundTrips() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["rt"])
        let key = Data((0..<64).map { UInt8($0) })
        dest.loadPublicKey(key)
        XCTAssertEqual(dest.getPrivateKey(), key,
                       "getPrivateKey() must return the same bytes loaded by loadPublicKey()")
    }
}
