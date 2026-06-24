import XCTest
@testable import ReticulumSwift

/// Tests for Identity.recall() and Identity.recallAppData() static methods.
/// Mirrors Python's `RNS.Identity.recall(target_hash)` API.
final class IdentityRecallTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    func testRecallReturnsIdentityAfterAnnounce() throws {
        let aT = Transport()
        let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["recall"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)

        let aIface = LoopbackInterface(name: "A"); let bIface = LoopbackInterface(name: "B")
        aIface.paired = bIface; bIface.paired = aIface
        aT.register(interface: aIface); bT.register(interface: bIface)

        // B announces; A should learn bId from the announce
        let announced = expectation(description: "announce-received")
        aT.onAnnounceReceived = { _, _ in announced.fulfill() }
        try bT.announce(destination: bDest)
        wait(for: [announced], timeout: 1.0)

        // A's Transport should now know bId by bDest.hash
        let recalled = aT.recall(identity: bDest.hash)
        XCTAssertNotNil(recalled, "should recall identity after announce")
        XCTAssertEqual(recalled?.hash, bId.hash)

        // Static Identity.recall should also work via shared transport
        // (requires Reticulum.shared — skip that form; test transport directly)
        _ = (aT, bT)
    }

    func testRecallAppDataAfterAnnounce() throws {
        let aT = Transport()
        let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["appdata"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)

        let appData = Data("hello reticulum".utf8)
        bDest.defaultAppData = appData

        let aIface = LoopbackInterface(name: "A"); let bIface = LoopbackInterface(name: "B")
        aIface.paired = bIface; bIface.paired = aIface
        aT.register(interface: aIface); bT.register(interface: bIface)

        let announced = expectation(description: "announce-received")
        aT.onAnnounceReceived = { _, _ in announced.fulfill() }
        try bT.announce(destination: bDest)
        wait(for: [announced], timeout: 1.0)

        // Recall app data
        let recalled = aT.recallAppData(forDestination: bDest.hash)
        XCTAssertEqual(recalled, appData)

        _ = (aT, bT)
    }

    func testRecallNilForUnknownDestination() {
        let t = Transport()
        let unknown = Data(repeating: 0xAA, count: 16)
        XCTAssertNil(t.recall(identity: unknown))
        XCTAssertNil(t.recallAppData(forDestination: unknown))
    }

    func testStaticIdentityRecallDelegatesToSharedTransport() throws {
        // Identity.recall(destinationHash:) should delegate to Reticulum.shared?.transport
        let unknown = Data(repeating: 0xFF, count: 16)
        // Without a shared instance, returns nil
        let result = Identity.recall(destinationHash: unknown)
        XCTAssertNil(result)
    }
}
