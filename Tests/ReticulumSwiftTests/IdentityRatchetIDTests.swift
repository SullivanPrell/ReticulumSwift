import XCTest
@testable import ReticulumSwift

/// Tests for Identity.current_ratchet_id() and related ratchet ID methods.
/// Mirrors Python's `RNS.Identity.current_ratchet_id(destination_hash)`.
final class IdentityRatchetIDTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    // MARK: - Identity.ratchetID(forPublicKey:)

    func testRatchetIDIs10Bytes() {
        let pub = Data(repeating: 0xAA, count: 32)
        let rid = Identity.ratchetID(forPublicKey: pub)
        XCTAssertEqual(rid.count, Constants.nameHashLength,
            "ratchet ID must be 10 bytes (NAME_HASH_LENGTH//8)")
    }

    func testRatchetIDMatchesPythonFormula() {
        // Python: Identity._get_ratchet_id(pub) = full_hash(pub)[:NAME_HASH_LENGTH//8]
        let pub = Data(repeating: 0xBB, count: 32)
        let expected = Identity.fullHash(pub).prefix(Constants.nameHashLength)
        let actual = Identity.ratchetID(forPublicKey: pub)
        XCTAssertEqual(actual, Data(expected))
    }

    // MARK: - Identity.currentRatchetID(forDestination:)

    func testCurrentRatchetIDNilWhenNoRatchetKnown() {
        let unknown = Data(repeating: 0xCC, count: 16)
        let result = Identity.currentRatchetID(for: unknown)
        XCTAssertNil(result, "should be nil when no ratchet is known for this destination")
    }

    func testCurrentRatchetIDAfterReceivingAnnounceWithRatchet() throws {
        let aT = Transport()
        let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["ratchetid"])

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try bDest.enableRatchets(path: tmp)

        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)

        // B announces with ratchet; A should learn the ratchet
        let announced = expectation(description: "announce")
        aT.onAnnounceReceived = { _, _ in announced.fulfill() }
        try bT.announce(destination: bDest)
        wait(for: [announced], timeout: 1.0)

        // Now A knows B's ratchet
        let ratchetID = aT.currentRatchetID(forDestination: bDest.hash)
        XCTAssertNotNil(ratchetID, "should have ratchet ID after receiving announce with ratchet")
        XCTAssertEqual(ratchetID?.count, Constants.nameHashLength)

        // Identity.currentRatchetID requires Reticulum.shared — test Transport directly
        _ = (aT, bT)
    }

    // MARK: - Transport.currentRatchetID

    func testTransportCurrentRatchetIDMatchesFormula() {
        let t = Transport()
        let ratchetPub = Data(repeating: 0xDD, count: 32)
        let destHash = Data(repeating: 0xEE, count: 16)
        t.restore(ratchet: ratchetPub, forDestination: destHash)

        let fromTransport = t.currentRatchetID(forDestination: destHash)
        let expected = Identity.ratchetID(forPublicKey: ratchetPub)
        XCTAssertEqual(fromTransport, expected)
    }
}
