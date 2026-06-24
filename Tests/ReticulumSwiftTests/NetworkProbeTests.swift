import XCTest
@testable import ReticulumSwift

/// Tests for NetworkProbe constants and API.
/// Python reference: RNS/Utilities/rnprobe.py

final class NetworkProbeTests: XCTestCase {

    // MARK: - Constants

    func testDefaultProbeSize() {
        // Python: DEFAULT_PROBE_SIZE = 16
        XCTAssertEqual(NetworkProbe.defaultProbeSize, 16)
    }

    func testDefaultTimeout() {
        // Python: DEFAULT_TIMEOUT = 12
        XCTAssertEqual(NetworkProbe.defaultTimeout, 12)
    }

    func testAppName() {
        // rnprobe doesn't declare an APP_NAME but the utility is called "rnprobe"
        XCTAssertEqual(NetworkProbe.appName, "rnprobe")
    }

    // MARK: - Instantiation

    func testCanInstantiateWithTransport() {
        let t = Transport()
        let probe = NetworkProbe(transport: t)
        XCTAssertNotNil(probe)
    }

    func testDefaultSizeIsConfigurable() {
        let t = Transport()
        let probe = NetworkProbe(transport: t, defaultSize: 64)
        XCTAssertEqual(probe.size, 64)
    }

    func testDefaultSizeDefaultsToClass() {
        let t = Transport()
        let probe = NetworkProbe(transport: t)
        XCTAssertEqual(probe.size, NetworkProbe.defaultProbeSize)
    }

    func testDefaultTimeoutIsConfigurable() {
        let t = Transport()
        let probe = NetworkProbe(transport: t, timeout: 30)
        XCTAssertEqual(probe.timeout, 30)
    }

    func testDefaultTimeoutDefaultsToClass() {
        let t = Transport()
        let probe = NetworkProbe(transport: t)
        XCTAssertEqual(probe.timeout, NetworkProbe.defaultTimeout)
    }
}
