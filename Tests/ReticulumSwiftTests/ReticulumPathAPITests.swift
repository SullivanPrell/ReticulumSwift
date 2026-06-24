import XCTest
@testable import ReticulumSwift

final class ReticulumPathAPITests: XCTestCase {

    private func makeReticulum() -> Reticulum {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReticulumPathAPITest-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Reticulum(configuration: .init(storagePath: dir))
    }

    // MARK: - getNextHop / getNextHopIfName / getFirstHopTimeout

    func testGetNextHopReturnsNilForUnknownDestination() {
        let r = makeReticulum()
        XCTAssertNil(r.getNextHop(for: Data(repeating: 0xAA, count: 16)))
    }

    func testGetNextHopIfNameReturnsNilForUnknownDestination() {
        let r = makeReticulum()
        XCTAssertNil(r.getNextHopIfName(for: Data(repeating: 0xBB, count: 16)))
    }

    func testGetFirstHopTimeoutReturnsDefaultForUnknownDestination() {
        let r = makeReticulum()
        XCTAssertEqual(r.getFirstHopTimeout(for: Data(repeating: 0xCC, count: 16)),
                       Constants.defaultPerHopTimeout)
    }

    func testGetNextHopReturnsHopForKnownPath() {
        let r = makeReticulum()
        let destHash = Data(repeating: 0x01, count: 16)
        let nextHop  = Data(repeating: 0x02, count: 16)
        let iface    = LoopbackInterface(name: "PathAPITestNext")
        r.transport.register(interface: iface)
        r.transport.injectPath(destHash, nextHop: nextHop, receivedOn: iface, hops: 1, announcePacketHash: nil)
        XCTAssertEqual(r.getNextHop(for: destHash), nextHop)
    }

    func testGetNextHopIfNameReturnsInterfaceNameForKnownPath() {
        let r = makeReticulum()
        let destHash = Data(repeating: 0x03, count: 16)
        let nextHop  = Data(repeating: 0x04, count: 16)
        let iface    = LoopbackInterface(name: "PathAPIIfNameIface")
        r.transport.register(interface: iface)
        r.transport.injectPath(destHash, nextHop: nextHop, receivedOn: iface, hops: 1, announcePacketHash: nil)
        XCTAssertEqual(r.getNextHopIfName(for: destHash), "PathAPIIfNameIface")
    }

    // MARK: - retainDestinationData / unretainDestinationData / retainIdentity

    func testRetainDestinationDataReturnsFalseForUnknown() {
        let r = makeReticulum()
        XCTAssertFalse(r.retainDestinationData(Data(repeating: 0xDD, count: 16)))
    }

    func testRetainAndUnretainRoundtrip() throws {
        let r = makeReticulum()
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "test", aspects: ["pathapi"])
        r.transport.register(destination: dest)
        r.transport.restore(identity: identity, forDestination: dest.hash)

        XCTAssertTrue(r.retainDestinationData(dest.hash))
        XCTAssertTrue(r.unretainDestinationData(dest.hash))
        XCTAssertFalse(r.unretainDestinationData(Data(repeating: 0xEE, count: 16)))
    }

    func testRetainIdentityReturnsFalseForUnknown() {
        let r = makeReticulum()
        XCTAssertFalse(r.retainIdentity(Data(repeating: 0xFF, count: 16)))
    }

    func testUsedDestinationDataReturnsFalseForUnknown() {
        let r = makeReticulum()
        XCTAssertFalse(r.usedDestinationData(Data(repeating: 0x11, count: 16)))
    }

    // MARK: - haltInterface / resumeInterface (stubs — must not crash)

    func testHaltInterfaceDoesNotCrash() {
        let r = makeReticulum()
        r.haltInterface(LoopbackInterface(name: "HaltTest"))
    }

    func testResumeInterfaceDoesNotCrash() {
        let r = makeReticulum()
        r.resumeInterface(LoopbackInterface(name: "ResumeTest"))
    }
}
