import XCTest
@testable import ReticulumSwift

/// Tests for the Python-parity attribute getter methods added to `Destination`:
///   destination.hash        → Destination.getHash()
///   destination.name        → Destination.getName()
///   destination.type        → Destination.getType()
///   destination.direction   → Destination.getDirection()
///   destination.identity    → Destination.getIdentity()
///
/// Python accesses these as direct attributes; Swift exposes them as
/// explicit `get*()` methods for a uniform imperative-style API.
final class DestinationAttributeGetterTests: XCTestCase {

    // MARK: - getHash

    func testGetHashMatchesHashProperty() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["hash"])
        XCTAssertEqual(dest.getHash(), dest.hash,
                       "getHash() must return the same value as the hash property")
    }

    func testGetHashIs16Bytes() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "test", aspects: ["h16"])
        XCTAssertEqual(dest.getHash().count, 16,
                       "Reticulum destination hashes are always 16 bytes (truncated)")
    }

    func testGetHashDeterminstic() throws {
        let id = Identity()
        let d1 = try Destination(identity: id, direction: .in, kind: .single,
                                 appName: "app", aspects: ["x"])
        let d2 = try Destination(identity: id, direction: .in, kind: .single,
                                 appName: "app", aspects: ["x"])
        XCTAssertEqual(d1.getHash(), d2.getHash(),
                       "Same identity + name → same hash (deterministic)")
    }

    // MARK: - getName

    func testGetNameMatchesFullNameProperty() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "myapp", aspects: ["svc"])
        XCTAssertEqual(dest.getName(), dest.fullName,
                       "getName() must return the same value as the fullName property")
    }

    func testGetNameContainsAppName() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "testapp", aspects: ["sub"])
        XCTAssertTrue(dest.getName().hasPrefix("testapp"),
                      "getName() must start with appName")
    }

    func testGetNameContainsAspects() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "app", aspects: ["alpha", "beta"])
        let name = dest.getName()
        XCTAssertTrue(name.contains("alpha"), "getName() must contain first aspect")
        XCTAssertTrue(name.contains("beta"),  "getName() must contain second aspect")
    }

    // MARK: - getType

    func testGetTypeMatchesKindProperty() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["t"])
        XCTAssertEqual(dest.getType(), dest.kind,
                       "getType() must return the same value as the kind property")
    }

    func testGetTypeReturnsCorrectKindSingle() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["single"])
        XCTAssertEqual(dest.getType(), .single)
    }

    func testGetTypeReturnsCorrectKindPlain() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "test", aspects: ["plain"])
        XCTAssertEqual(dest.getType(), .plain)
    }

    func testGetTypeReturnsCorrectKindGroup() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["grp"])
        XCTAssertEqual(dest.getType(), .group)
    }

    // MARK: - getDirection

    func testGetDirectionMatchesDirectionProperty() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .out, kind: .single,
                                   appName: "test", aspects: ["dir"])
        XCTAssertEqual(dest.getDirection(), dest.direction,
                       "getDirection() must return the same value as the direction property")
    }

    func testGetDirectionIn() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["in"])
        XCTAssertEqual(dest.getDirection(), .in)
    }

    func testGetDirectionOut() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .out, kind: .single,
                                   appName: "test", aspects: ["out"])
        XCTAssertEqual(dest.getDirection(), .out)
    }

    // MARK: - getIdentity

    func testGetIdentityMatchesIdentityProperty() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["id"])
        XCTAssertTrue(dest.getIdentity() === id,
                      "getIdentity() must return the same object as the identity property")
        XCTAssertTrue(dest.getIdentity() === dest.identity)
    }

    func testGetIdentityNilForPlain() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "test", aspects: ["plain"])
        XCTAssertNil(dest.getIdentity(),
                     "getIdentity() must be nil for PLAIN destinations without an identity")
    }
}
