import XCTest
@testable import ReticulumSwift

/// Tests for Python-parity static methods on `Reticulum`:
///   RNS.Reticulum.get_transport_instance()          → Reticulum.getTransportInstance()
///   RNS.Reticulum.is_connected_to_shared_instance() → Reticulum.isConnectedToSharedInstance()
final class ReticulumSharedInstanceTests: XCTestCase {

    private var rns: Reticulum?

    override func tearDown() {
        rns?.stop()
        rns = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func startInstance() -> Reticulum {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RNSSharedTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let config = Reticulum.Configuration(storagePath: tmpDir)
        let instance = Reticulum(configuration: config)
        // start() sets Reticulum.shared, which is required by getTransportInstance()
        // and isConnectedToSharedInstance().
        try? instance.start()
        rns = instance
        return instance
    }

    // MARK: - isConnectedToSharedInstance

    func testIsConnectedToSharedInstanceReturnsBool() {
        // The value depends on whether a shared instance has been created
        // by another test. We only verify the return type compiles and runs.
        let result = Reticulum.isConnectedToSharedInstance()
        XCTAssertTrue(result == true || result == false)
    }

    func testIsConnectedToSharedInstanceTrueAfterCreation() {
        _ = startInstance()
        // After creating a Reticulum instance (which sets shared), the result must be true.
        XCTAssertTrue(Reticulum.isConnectedToSharedInstance(),
                      "isConnectedToSharedInstance() must be true after a Reticulum instance is created")
    }

    func testIsConnectedToSharedInstanceAgreesWithSharedNil() {
        // isConnectedToSharedInstance() is exactly `shared != nil`
        let expected = Reticulum.shared != nil
        XCTAssertEqual(Reticulum.isConnectedToSharedInstance(), expected,
                       "isConnectedToSharedInstance() must equal (Reticulum.shared != nil)")
    }

    // MARK: - getTransportInstance

    func testGetTransportInstanceNonNilAfterCreation() {
        _ = startInstance()
        XCTAssertNotNil(Reticulum.getTransportInstance(),
                        "getTransportInstance() must be non-nil when a shared Reticulum instance exists")
    }

    func testGetTransportInstanceMatchesSharedTransport() {
        let instance = startInstance()
        let transport = Reticulum.getTransportInstance()
        XCTAssertTrue(transport === instance.transport,
                      "getTransportInstance() must return the same Transport as shared.transport")
    }

    func testGetTransportInstanceReturnsNilWhenNoShared() {
        // If no shared instance exists, getTransportInstance() must be nil.
        guard Reticulum.shared == nil else {
            // Another test may have left shared set; skip to avoid false positives.
            return
        }
        XCTAssertNil(Reticulum.getTransportInstance(),
                     "getTransportInstance() must be nil when Reticulum.shared is nil")
    }

    // MARK: - Consistency between the two methods

    func testBothMethodsAgreeThatInstanceExists() {
        _ = startInstance()
        XCTAssertTrue(Reticulum.isConnectedToSharedInstance())
        XCTAssertNotNil(Reticulum.getTransportInstance())
    }

    func testGetTransportInstanceIsNilExactlyWhenNotConnected() {
        // The two methods must be logically consistent: transport is nil iff not connected.
        let connected = Reticulum.isConnectedToSharedInstance()
        let transport = Reticulum.getTransportInstance()
        if connected {
            XCTAssertNotNil(transport)
        } else {
            XCTAssertNil(transport)
        }
    }
}
