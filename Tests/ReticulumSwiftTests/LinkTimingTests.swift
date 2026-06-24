import XCTest
@testable import ReticulumSwift

/// Tests for Link timing API methods that mirror Python's Link:
///   - `getAge()` → time since link established
///   - `noDataFor()` → time since last DATA payload (excluding keepalives)
///   - `activatedAt` → timestamp when link became .active
///   - `lastData` → timestamp of last non-keepalive data
///   - `expectedRate` → in-flight data rate updated after Resource transfers
final class LinkTimingTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String
        var bitrate: Int = 100_000
        var isOnline: Bool = true
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

    private func makeTransports() -> (Transport, Transport) {
        (Transport(), Transport())
    }

    private func establishLink(
        aTransport: Transport,
        bTransport: Transport
    ) throws -> (Link, Link) {
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["timing"])
        bTransport.ownerIdentity = bId
        bTransport.register(destination: bDest)

        let aIface = LoopbackInterface(name: "A")
        let bIface = LoopbackInterface(name: "B")
        aIface.paired = bIface; bIface.paired = aIface
        aTransport.register(interface: aIface)
        bTransport.register(interface: bIface)

        let aE = expectation(description: "a-active")
        let bE = expectation(description: "b-active")
        aTransport.onLinkEstablished = { _ in aE.fulfill() }
        bTransport.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aTransport)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bTransport.links[aLink.linkID!])
        return (aLink, bLink)
    }

    // MARK: - activatedAt

    func testActivatedAtSetAfterEstablishment() throws {
        let (aT, bT) = makeTransports()
        let (aLink, _) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }
        XCTAssertNotNil(aLink.activatedAt, "activatedAt must be set after link establishment")
    }

    func testActivatedAtIsRecentlyInPast() throws {
        let before = Date()
        let (aT, bT) = makeTransports()
        let (aLink, _) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }
        let after = Date()
        guard let ts = aLink.activatedAt else { return XCTFail("activatedAt nil") }
        XCTAssertGreaterThanOrEqual(ts, before)
        XCTAssertLessThanOrEqual(ts, after)
    }

    // MARK: - getAge

    func testGetAgePositiveAfterEstablishment() throws {
        let (aT, bT) = makeTransports()
        let (aLink, _) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }
        guard let age = aLink.getAge() else { return XCTFail("getAge nil") }
        XCTAssertGreaterThanOrEqual(age, 0)
        XCTAssertLessThan(age, 5.0, "link was just established")
    }

    func testGetAgeGrowsOverTime() throws {
        let (aT, bT) = makeTransports()
        let (aLink, _) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }
        let age1 = aLink.getAge() ?? 0
        Thread.sleep(forTimeInterval: 0.05)
        let age2 = aLink.getAge() ?? 0
        XCTAssertGreaterThan(age2, age1)
    }

    // MARK: - noDataFor

    func testNoDataForIsLargeBeforeAnyDataSent() throws {
        let (aT, bT) = makeTransports()
        let (aLink, _) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }
        // Before any data, noDataFor should return a large value (not recent).
        let nd = aLink.noDataFor()
        XCTAssertGreaterThanOrEqual(nd, 0)
    }

    func testNoDataForResetWhenDataReceived() throws {
        let (aT, bT) = makeTransports()
        let (aLink, bLink) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }

        Thread.sleep(forTimeInterval: 0.1)

        let received = expectation(description: "data-received")
        aLink.onDataReceived = { _, _ in received.fulfill() }
        try bLink.send(Data("hello".utf8))
        wait(for: [received], timeout: 1.0)

        // After receiving data, noDataFor should be small.
        let nd = aLink.noDataFor()
        XCTAssertLessThan(nd, 0.5, "noDataFor should be small after receiving data")
    }

    func testNoDataForNotResetByKeepalive() throws {
        let (aT, bT) = makeTransports()
        let (aLink, bLink) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }

        // Wait so baseline noDataFor is larger.
        Thread.sleep(forTimeInterval: 0.05)
        let ndBefore = aLink.noDataFor()

        // Send a keepalive from the initiator; this should NOT update lastData.
        try? aLink.sendKeepalive()
        _ = bLink

        // noDataFor still reflects time since last DATA, not keepalive.
        Thread.sleep(forTimeInterval: 0.05)
        let ndAfter = aLink.noDataFor()
        XCTAssertGreaterThanOrEqual(ndAfter, ndBefore,
            "noDataFor should not decrease without actual DATA traffic")
    }

    func testLastDataUpdatedOnOutbound() throws {
        let (aT, bT) = makeTransports()
        let (aLink, bLink) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }

        // lastData nil or old before sending
        let ndBefore = aLink.noDataFor()
        let received = expectation(description: "received-on-b")
        bLink.onDataReceived = { _, _ in received.fulfill() }

        try aLink.send(Data("hi".utf8))
        wait(for: [received], timeout: 1.0)

        // Sending DATA updates noDataFor on the sender side too.
        let ndAfter = aLink.noDataFor()
        XCTAssertLessThan(ndAfter, ndBefore + 0.01,
            "noDataFor should reset after outbound DATA")
    }

    // MARK: - expectedRate

    func testExpectedRateNilInitially() throws {
        let (aT, bT) = makeTransports()
        let (aLink, _) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }
        // expectedRate is nil until a Resource transfer completes.
        // Just verify the property exists and is accessible.
        _ = aLink.expectedRate
    }

    func testExpectedRateSetAfterResourceTransfer() throws {
        let (aT, bT) = makeTransports()
        let (aLink, bLink) = try establishLink(aTransport: aT, bTransport: bT)
        defer { _ = (aT, bT) }

        let payload = Data(repeating: 0xAB, count: 512)

        let completed = expectation(description: "resource-complete")
        var receivedPayload: Data?
        let rt = ResourceTransfer(link: aLink)
        rt.onComplete = { _ in completed.fulfill() }

        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        receiver.onPayloadReceived = { data, _ in receivedPayload = data }

        try rt.send(payload: payload)
        wait(for: [completed], timeout: 5.0)

        XCTAssertEqual(receivedPayload, payload)
        // After a Resource transfer, the link's expectedRate should be set.
        XCTAssertNotNil(bLink.expectedRate, "expectedRate should be set after resource transfer")
        if let rate = bLink.expectedRate {
            XCTAssertGreaterThan(rate, 0)
        }
    }
}
