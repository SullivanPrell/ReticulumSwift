import XCTest
@testable import ReticulumSwift

/// Tests for RNIDApp constants.
/// Python reference: RNS/Utilities/rnid.py

final class RNIDAppTests: XCTestCase {

    // MARK: - Names

    func testAppName() {
        // Python: APP_NAME = "rns"
        XCTAssertEqual(RNIDApp.appName, "rns")
    }

    func testDefaultAspects() {
        // Python: DEFAULT_ASPECTS = f"{APP_NAME}.id"
        XCTAssertEqual(RNIDApp.defaultAspects, "rns.id")
    }

    // MARK: - Flag bytes

    func testNoMessage() {
        // Python: NO_MESSAGE = 0x01
        XCTAssertEqual(RNIDApp.noMessage, 0x01)
    }

    func testNoMeta() {
        // Python: NO_META = 0x02
        XCTAssertEqual(RNIDApp.noMeta, 0x02)
    }

    // MARK: - File extensions

    func testPrvExt() {
        // Python: PRV_EXT = "rid"
        XCTAssertEqual(RNIDApp.prvExt, "rid")
    }

    func testPubExt() {
        // Python: PUB_EXT = "pub"
        XCTAssertEqual(RNIDApp.pubExt, "pub")
    }

    func testSigExt() {
        // Python: SIG_EXT = "rsg"
        XCTAssertEqual(RNIDApp.sigExt, "rsg")
    }

    func testMsgExt() {
        // Python: MSG_EXT = "rsm"
        XCTAssertEqual(RNIDApp.msgExt, "rsm")
    }

    func testEncryptExt() {
        // Python: ENCRYPT_EXT = "rfe"
        XCTAssertEqual(RNIDApp.encryptExt, "rfe")
    }

    // MARK: - Chunk sizes

    func testChunkBlocks() {
        // Python: CHUNK_BLOCKS = 1024*1024
        XCTAssertEqual(RNIDApp.chunkBlocks, 1_048_576)
    }

    func testEncChunk() {
        // Python: ENC_CHUNK = CHUNK_BLOCKS * RNS.Identity.AES256_BLOCKSIZE
        // Identity.aes256BlockSize = 16
        XCTAssertEqual(RNIDApp.encChunk, 1_048_576 * 16)
    }

    func testDecChunk() {
        // Python: DEC_CHUNK = ENC_CHUNK + RNS.Cryptography.Token.TOKEN_OVERHEAD*2
        // Token.tokenOverhead = 48
        let expected = RNIDApp.encChunk + 48 * 2
        XCTAssertEqual(RNIDApp.decChunk, expected)
    }

    // MARK: - RSG hash types

    func testRsgHashTypesContainsSha256() {
        // Python: RSG_HASHTYPES = ["sha256"]
        XCTAssertTrue(RNIDApp.rsgHashTypes.contains("sha256"))
    }

    func testRsgHashTypesCount() {
        XCTAssertEqual(RNIDApp.rsgHashTypes.count, 1)
    }

    // MARK: - Error codes

    func testResultOK() {
        XCTAssertEqual(RNIDApp.Result.ok.rawValue, 0)
    }

    func testResultNoSigFile() {
        XCTAssertEqual(RNIDApp.Result.noSigFile.rawValue, 1)
    }

    func testResultNoIdentity() {
        XCTAssertEqual(RNIDApp.Result.noIdentity.rawValue, 2)
    }

    func testResultNoPubKey() {
        XCTAssertEqual(RNIDApp.Result.noPubKey.rawValue, 3)
    }

    func testResultNoPrvKey() {
        XCTAssertEqual(RNIDApp.Result.noPrvKey.rawValue, 4)
    }

    func testResultNoKeys() {
        XCTAssertEqual(RNIDApp.Result.noKeys.rawValue, 5)
    }

    func testResultNoFile() {
        XCTAssertEqual(RNIDApp.Result.noFile.rawValue, 6)
    }

    func testResultInvalidFile() {
        XCTAssertEqual(RNIDApp.Result.invalidFile.rawValue, 7)
    }

    func testResultInvalidIdentity() {
        XCTAssertEqual(RNIDApp.Result.invalidIdentity.rawValue, 8)
    }

    func testResultInvalidAspects() {
        XCTAssertEqual(RNIDApp.Result.invalidAspects.rawValue, 9)
    }

    func testResultInvalidSignature() {
        XCTAssertEqual(RNIDApp.Result.invalidSignature.rawValue, 10)
    }

    func testResultFileExists() {
        XCTAssertEqual(RNIDApp.Result.fileExists.rawValue, 11)
    }

    func testResultDecryptFailed() {
        XCTAssertEqual(RNIDApp.Result.decryptFailed.rawValue, 12)
    }

    func testResultInvalidArgs() {
        XCTAssertEqual(RNIDApp.Result.invalidArgs.rawValue, 250)
    }

    func testResultSequenceError() {
        XCTAssertEqual(RNIDApp.Result.sequenceError.rawValue, 251)
    }

    func testResultReadError() {
        XCTAssertEqual(RNIDApp.Result.readError.rawValue, 252)
    }

    func testResultWriteError() {
        XCTAssertEqual(RNIDApp.Result.writeError.rawValue, 253)
    }

    func testResultUnknownError() {
        XCTAssertEqual(RNIDApp.Result.unknownError.rawValue, 254)
    }

    func testResultInterrupted() {
        XCTAssertEqual(RNIDApp.Result.interrupted.rawValue, 255)
    }
}
