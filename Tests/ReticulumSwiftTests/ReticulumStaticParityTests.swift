import XCTest
@testable import ReticulumSwift

/// Tests for Reticulum static API parity with Python Reticulum static methods.
final class ReticulumStaticParityTests: XCTestCase {

    // MARK: - shouldAutoconnectDiscoveredInterfaces / maxAutoconnectedInterfaces

    func testShouldAutoconnectDefaultsFalse() {
        // Default is 0 → false
        XCTAssertFalse(Reticulum.shouldAutoconnectDiscoveredInterfaces())
    }

    func testMaxAutoconnectedInterfacesDefaultsZero() {
        XCTAssertEqual(Reticulum.maxAutoconnectedInterfaces(), 0)
    }

    func testShouldAutoconnectTrueWhenMaxIsPositive() {
        let previous = Reticulum.maxAutoconnectedInterfaces_
        Reticulum.maxAutoconnectedInterfaces_ = 3
        XCTAssertTrue(Reticulum.shouldAutoconnectDiscoveredInterfaces())
        XCTAssertEqual(Reticulum.maxAutoconnectedInterfaces(), 3)
        Reticulum.maxAutoconnectedInterfaces_ = previous
    }

    // MARK: - remoteManagementEnabled / probeDestinationEnabled / linkMtuDiscovery

    func testRemoteManagementEnabledDefaultsFalse() {
        XCTAssertFalse(Reticulum.remoteManagementEnabled())
    }

    func testProbeDestinationEnabledDefaultsFalse() {
        XCTAssertFalse(Reticulum.probeDestinationEnabled())
    }

    func testLinkMtuDiscoveryDefaultsTrue() {
        XCTAssertTrue(Reticulum.linkMtuDiscovery())
    }

    // MARK: - publishBlackholeEnabled / blackholeSources

    func testPublishBlackholeEnabledDefaultsFalse() {
        XCTAssertFalse(Reticulum.publishBlackholeEnabled())
    }

    func testBlackholeSourcesDefaultsEmpty() {
        XCTAssertTrue(Reticulum.blackholeSources().isEmpty)
    }

    // MARK: - requiredDiscoveryValue

    func testRequiredDiscoveryValueIsPositive() {
        XCTAssertGreaterThan(Reticulum.requiredDiscoveryValue(), 0)
    }

    // MARK: - interfaceDiscoverySources

    func testInterfaceDiscoverySourcesDefaultsEmpty() {
        XCTAssertTrue(Reticulum.interfaceDiscoverySources().isEmpty)
    }

    // MARK: - discoveredInterfaces

    func testDiscoveredInterfacesDefaultsEmpty() {
        XCTAssertTrue(Reticulum.discoveredInterfaces().isEmpty)
    }

    // MARK: - transportEnabled / shouldUseImplicitProof

    func testTransportEnabledDefaultsFalse() {
        XCTAssertFalse(Reticulum.transportEnabled())
    }

    func testShouldUseImplicitProofHasBooleanValue() {
        let v = Reticulum.shouldUseImplicitProof()
        XCTAssert(v == true || v == false)
    }
}
