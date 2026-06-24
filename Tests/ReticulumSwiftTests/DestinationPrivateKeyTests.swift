import XCTest
@testable import ReticulumSwift

/// Tests for `Destination.getPrivateKey()` and `Destination.loadPrivateKey(_:)`.
///
/// Python reference:
///   Destination.get_private_key()   → returns private key bytes (GROUP: symmetric, SINGLE: identity priv)
///   Destination.load_private_key(key) → loads key material
final class DestinationPrivateKeyTests: XCTestCase {

    // MARK: - GROUP destinations

    func testGroupGetPrivateKeyNilBeforeCreateKeys() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["grp"])
        XCTAssertNil(dest.getPrivateKey(),
                     "getPrivateKey() must be nil before createKeys() is called")
    }

    func testGroupGetPrivateKeyAfterCreateKeys() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["grp2"])
        _ = dest.createKeys()
        let key = dest.getPrivateKey()
        XCTAssertNotNil(key, "getPrivateKey() must return key bytes after createKeys()")
        // Python: Token.generate_key(AES_256_CBC) = os.urandom(64) → 64 bytes
        XCTAssertEqual(key?.count, 64, "GROUP key must be 64 bytes (AES-256-CBC Token key)")
    }

    func testGroupGetPrivateKeyMatchesGetGroupKey() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["grp3"])
        _ = dest.createKeys()
        XCTAssertEqual(dest.getPrivateKey(), dest.getGroupKey(),
                       "getPrivateKey() and getGroupKey() must return the same bytes for GROUP destinations")
    }

    func testGroupLoadPrivateKeyRoundTrip() throws {
        let src = try Destination(identity: nil, direction: .in, kind: .group,
                                  appName: "test", aspects: ["grp4"])
        _ = src.createKeys()
        let exported = try XCTUnwrap(src.getPrivateKey())

        let dst = try Destination(identity: nil, direction: .in, kind: .group,
                                  appName: "test", aspects: ["grp5"])
        let ok = dst.loadPrivateKey(exported)
        XCTAssertTrue(ok, "loadPrivateKey must succeed for GROUP destinations")
        XCTAssertEqual(dst.getPrivateKey(), exported,
                       "loaded key must match the exported key")
    }

    // MARK: - SINGLE destinations

    func testSingleGetPrivateKeyReturnsNilForPublicOnly() throws {
        let pubId = Identity()
        // Strip private key by creating a new Identity from the public bytes only.
        let pubOnly = try Identity(publicKeyBytes: pubId.publicKeyBytes)
        let dest = try Destination(identity: pubOnly, direction: .out, kind: .single,
                                   appName: "test", aspects: ["single"])
        XCTAssertNil(dest.getPrivateKey(),
                     "getPrivateKey() must be nil when identity has no private key")
    }

    func testSingleGetPrivateKeyReturnsBytesForFullIdentity() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["single2"])
        let key = dest.getPrivateKey()
        XCTAssertNotNil(key,
                        "getPrivateKey() must return bytes when identity has a private key")
        XCTAssertEqual(key, id.privateKeyBytes)
    }

    // MARK: - PLAIN destinations

    func testPlainGetPrivateKeyReturnsNil() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "test", aspects: ["plain"])
        XCTAssertNil(dest.getPrivateKey(),
                     "PLAIN destinations have no private key material")
    }

    func testPlainLoadPrivateKeyReturnsFalse() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "test", aspects: ["plain2"])
        XCTAssertFalse(dest.loadPrivateKey(Data(repeating: 0, count: 32)),
                       "loadPrivateKey must fail for PLAIN destinations")
    }
}
