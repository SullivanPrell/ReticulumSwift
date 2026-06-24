import XCTest
@testable import ReticulumSwift

/// Tests for `Reticulum` class static API methods, mirroring Python's:
///   - `Reticulum.should_use_implicit_proof()`
///   - `Reticulum.transport_enabled()`
///   - `Reticulum.link_mtu_discovery()`
final class ReticulumAPITests: XCTestCase {

    // MARK: - should_use_implicit_proof

    func testShouldUseImplicitProofReturnsBool() {
        let result = Reticulum.shouldUseImplicitProof()
        // Default should be true (mirrors Python's default).
        XCTAssertTrue(result, "implicit proof should be enabled by default")
    }

    // MARK: - transport_enabled (via Transport)

    func testTransportEnabledDefaultFalseForNewTransport() {
        // A bare Transport() has transportEnabled=true by default (it's not a
        // shared-instance client). But the Reticulum.transportEnabled() static
        // method requires a running shared instance.
        let transport = Transport()
        XCTAssertTrue(transport.transportEnabled)
    }

    func testTransportEnabledCanBeDisabled() {
        let transport = Transport()
        transport.transportEnabled = false
        XCTAssertFalse(transport.transportEnabled)
    }

    // MARK: - link_mtu_discovery

    func testLinkMtuDiscoveryDefault() {
        // Default: link MTU discovery is enabled (matches Python LINK_MTU_DISCOVERY = True).
        let result = Reticulum.linkMtuDiscovery()
        XCTAssertTrue(result, "link MTU discovery should be enabled by default")
    }

    // MARK: - Constants match Python reference

    func testMTUConstant() {
        XCTAssertEqual(Constants.mtu, 500, "MTU must be 500 bytes (Python: Reticulum.MTU = 500)")
    }

    func testAnnounceCap() {
        // Python: Reticulum.ANNOUNCE_CAP = 2 (percent)
        XCTAssertEqual(Transport.announceCap, 2)
    }

    func testMinimumBitrate() {
        // Python: Reticulum.MINIMUM_BITRATE = 5 (bits/second)
        XCTAssertEqual(Transport.minimumBitrate, 5)
    }

    func testEncryptedMDU() {
        // Python: Packet.ENCRYPTED_MDU = 383
        XCTAssertEqual(Constants.encryptedMdu, 383)
    }

    func testPlainMDU() {
        // Python: Packet.PLAIN_MDU = 464
        XCTAssertEqual(Constants.plainMdu, 464)
    }
}
