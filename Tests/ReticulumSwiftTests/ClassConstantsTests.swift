import XCTest
@testable import ReticulumSwift

/// Tests verifying class-level constants match Python's reference implementation.
/// These constants are accessed as class attributes in Python (e.g. `RNS.Identity.KEYSIZE`,
/// `RNS.Packet.ENCRYPTED_MDU`, `RNS.Link.MDU`).
final class ClassConstantsTests: XCTestCase {

    // MARK: - Identity constants

    func testIdentityKeySize() {
        // Python: Identity.KEYSIZE = 256*2 = 512 bits
        XCTAssertEqual(Identity.keySize, 512)
    }

    func testIdentityEcPubSize() {
        // Python: Identity.ECPUBSIZE = 32+32 = 64 → per-side = 32 bytes = 256 bits
        XCTAssertEqual(Identity.ecPubSize, 256)
    }

    func testIdentitySigLength() {
        // Python: Identity.SIGLENGTH = Identity.KEYSIZE = 512 bits
        XCTAssertEqual(Identity.sigLength, 512)
    }

    func testIdentityTruncatedHashLength() {
        // Python: Identity.TRUNCATED_HASHLENGTH = 128 bits
        XCTAssertEqual(Identity.truncatedHashLength, 128)
    }

    func testIdentityNameHashLength() {
        // Python: Identity.NAME_HASH_LENGTH = 80 bits
        XCTAssertEqual(Identity.nameHashLength, 80)
    }

    // MARK: - Packet constants

    func testPacketEncryptedMDU() {
        // Python: Packet.ENCRYPTED_MDU = 383
        XCTAssertEqual(Packet.encryptedMdu, 383)
    }

    func testPacketPlainMDU() {
        // Python: Packet.PLAIN_MDU = 464
        XCTAssertEqual(Packet.plainMdu, 464)
    }

    // MARK: - Link constants

    func testLinkMTU() {
        // Python: RNS.Link.MDU = RNS.Reticulum.MDU = 464
        XCTAssertEqual(Link.mtu, 464)
    }

    func testLinkKeepaliveInterval() {
        // Python: Link.KEEPALIVE = 360
        XCTAssertEqual(Link.keepaliveInterval, 360)
    }

    func testLinkStaleTime() {
        // Python: STALE_TIME = STALE_FACTOR * KEEPALIVE = 2 * 360 = 720
        XCTAssertEqual(Link.staleTime, 720)
    }

    func testLinkEstablishmentTimeoutPerHop() {
        // Python: Link.ESTABLISHMENT_TIMEOUT_PER_HOP = 6
        XCTAssertEqual(Link.establishmentTimeoutPerHop, 6)
    }

    // MARK: - Transport/Reticulum constants

    func testAnnounceCap() {
        // Python: Reticulum.ANNOUNCE_CAP = 2 (percent)
        XCTAssertEqual(Transport.announceCap, 2)
    }

    func testMinimumBitrate() {
        // Python: Reticulum.MINIMUM_BITRATE = 5
        XCTAssertEqual(Transport.minimumBitrate, 5)
    }
}
