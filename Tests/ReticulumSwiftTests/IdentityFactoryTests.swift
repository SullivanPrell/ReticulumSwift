import XCTest
@testable import ReticulumSwift

/// Tests for Identity factory methods mirroring Python's:
///   - `Identity.from_bytes(prv_bytes)`
///   - `Identity.from_file(path)`
///   - `Identity.to_file(path)` / `Identity.pub_to_file(path)`
final class IdentityFactoryTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-id-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Identity.from_bytes (mirrors Python Identity.from_bytes)

    func testFromBytesCreatesIdentity() throws {
        let original = Identity()
        let privBytes = try XCTUnwrap(original.privateKeyBytes)
        let loaded = Identity.fromBytes(privBytes)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.hash, original.hash)
    }

    func testFromBytesReturnsNilForInvalidData() {
        let bad = Data(repeating: 0x00, count: 10)
        XCTAssertNil(Identity.fromBytes(bad))
    }

    func testFromBytesPreservesPublicKey() throws {
        let original = Identity()
        let privBytes = try XCTUnwrap(original.privateKeyBytes)
        let loaded = try XCTUnwrap(Identity.fromBytes(privBytes))
        XCTAssertEqual(loaded.publicKeyBytes, original.publicKeyBytes)
    }

    // MARK: - Identity.from_file / to_file (mirrors Python Identity.from_file / to_file)

    func testToFileAndFromFileRoundTrip() throws {
        let original = Identity()
        let path = tmpDir.appendingPathComponent("id.key")
        let saved = try XCTUnwrap(original.toFile(path))
        XCTAssertTrue(saved)

        let loaded = Identity.fromFile(path)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.hash, original.hash)
    }

    func testFromFileReturnsNilForMissingFile() {
        let absent = tmpDir.appendingPathComponent("nonexistent.key")
        XCTAssertNil(Identity.fromFile(absent))
    }

    // MARK: - Identity.pub_to_file (mirrors Python Identity.pub_to_file)

    func testPubToFile() throws {
        let id = Identity()
        let path = tmpDir.appendingPathComponent("id.pub")
        let saved = id.pubToFile(path)
        XCTAssertTrue(saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        // Public key file should be 64 bytes
        let data = try Data(contentsOf: path)
        XCTAssertEqual(data.count, Constants.keySize)
        XCTAssertEqual(data, id.publicKeyBytes)
    }

    // MARK: - get_private_key / get_public_key (mirrors Python Identity methods)

    func testGetPrivateKey() throws {
        let id = Identity()
        let prv = try XCTUnwrap(id.getPrivateKey())
        XCTAssertEqual(prv.count, Constants.keySize)
        XCTAssertEqual(prv, id.privateKeyBytes)
    }

    func testGetPublicKey() {
        let id = Identity()
        XCTAssertEqual(id.getPublicKey(), id.publicKeyBytes)
        XCTAssertEqual(id.getPublicKey().count, Constants.keySize)
    }

    func testGetPrivateKeyNilForPublicOnly() throws {
        let id = Identity()
        let pubOnly = try Identity(publicKeyBytes: id.publicKeyBytes)
        XCTAssertNil(pubOnly.getPrivateKey())
    }
}
