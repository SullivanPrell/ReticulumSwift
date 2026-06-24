import XCTest
@testable import ReticulumSwift

/// Tests for remaining Reticulum class-level constants not covered by
/// ReticulumConstantsTests or ReticulumWireConstantsTests.
///
/// Python reference (Reticulum.py):
///   Reticulum.CLEAN_INTERVAL        = 900
///   Reticulum.JOB_INTERVAL          = 300
///   Reticulum.MINIMUM_BITRATE       = 5
///   Reticulum.QUEUED_ANNOUNCE_LIFE  = 60*60*24 = 86400
///   Reticulum.RESOURCE_CACHE        = 60*60*24 = 86400
///   Reticulum.TRUNCATED_HASHLENGTH  = 128
///   Reticulum.IFAC_SALT             = bytes.fromhex("adf54d882c9a…")
final class ReticulumRemainingConstantsTests: XCTestCase {

    func testCleanInterval() {
        XCTAssertEqual(Reticulum.cleanInterval, 900,
                       "CLEAN_INTERVAL must be 900 seconds")
    }

    func testJobInterval() {
        XCTAssertEqual(Reticulum.jobInterval, 300,
                       "JOB_INTERVAL must be 300 seconds")
    }

    func testMinimumBitrate() {
        XCTAssertEqual(Reticulum.minimumBitrate, 5,
                       "MINIMUM_BITRATE must be 5 bits/s")
    }

    func testQueuedAnnounceLife() {
        XCTAssertEqual(Reticulum.queuedAnnounceLife, 86400,
                       "QUEUED_ANNOUNCE_LIFE must be 86400 seconds (24 hours)")
    }

    func testResourceCacheLifetime() {
        XCTAssertEqual(Reticulum.resourceCacheLifetime, 86400,
                       "RESOURCE_CACHE must be 86400 seconds (24 hours)")
    }

    func testTruncatedHashLength() {
        XCTAssertEqual(Reticulum.truncatedHashLength, 128,
                       "TRUNCATED_HASHLENGTH must be 128 bits")
    }

    func testIfacSaltIs32Bytes() {
        XCTAssertEqual(Reticulum.ifacSalt.count, 32,
                       "IFAC_SALT must be 32 bytes")
    }

    func testIfacSaltMatchesPython() {
        // Python: bytes.fromhex("adf54d882c9a9b80771eb4995d702d4a3e733391b2a0f53f416d9f907e55cff8")
        let expected = Data([
            0xad, 0xf5, 0x4d, 0x88, 0x2c, 0x9a, 0x9b, 0x80,
            0x77, 0x1e, 0xb4, 0x99, 0x5d, 0x70, 0x2d, 0x4a,
            0x3e, 0x73, 0x33, 0x91, 0xb2, 0xa0, 0xf5, 0x3f,
            0x41, 0x6d, 0x9f, 0x90, 0x7e, 0x55, 0xcf, 0xf8
        ])
        XCTAssertEqual(Reticulum.ifacSalt, expected,
                       "IFAC_SALT must match Python golden bytes exactly")
    }
}
