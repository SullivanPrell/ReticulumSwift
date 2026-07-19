import XCTest
@testable import ReticulumSwift

/// Concurrency stress tests for the `ResourceTransfer.stateLock` introduced in the
/// 2026-07-19 deferred data-race hardening pass. The rest of the resource suite is
/// single-threaded and cannot exercise the watchdog-vs-receive-thread races; here we
/// hammer the transfer's public accessors and internal entry points from many threads
/// at once, with a fast watchdog firing on its own queue and random cancellation.
///
/// A lock-order inversion or reentrant self-deadlock (e.g. holding `stateLock` across
/// a `link.*` callout) would make these tests TIME OUT; a torn read of `status` (an
/// enum carrying a `String`) or of the `advertisement` class reference, or a
/// mutation-during-iteration of the `parts`/`hashmap` arrays, would CRASH. Passing
/// under ThreadSanitizer (`swift test -Xswiftc -sanitize=thread --filter
/// ResourceTransferConcurrencyTests`) proves none of those happen on these paths.
final class ResourceTransferConcurrencyTests: XCTestCase {

    private final class LoopbackInterface: Interface {
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

    private var aT: Transport!; private var bT: Transport!

    private func establishLink() throws -> (Link, Link) {
        aT = Transport(); bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["rtconc"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }; bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink)
    }

    /// A valid, unpackable advertisement to feed the receiver's heavy-writer path.
    private func makeAdvertisementBytes() -> Data {
        let rhash = Data((0..<32).map { UInt8($0 &* 7 &+ 1) })
        let rand  = Data(repeating: 0x11, count: 32)
        let hashmap = Data((0..<16).map { UInt8($0) }) // 4 map-hashes × 4 bytes
        let adv = ResourceAdvertisement(
            transferSize: 4000, dataSize: 3200, partCount: 4,
            resourceHash: rhash, randomHash: rand, originalHash: rhash,
            segmentIndex: 1, totalSegments: 1, requestID: nil,
            hashmap: hashmap, encrypted: true, compressed: false, split: false,
            isRequest: false, isResponse: false, hasMetadata: false
        )
        return adv.pack()
    }

    /// A well-formed HMU (reaches the locked region rather than early-returning at parse).
    private func makeHMUBytes() -> Data {
        let rhash = Data((0..<32).map { UInt8($0 &* 7 &+ 1) })
        let hashmap = Data((0..<16).map { UInt8($0 &+ 32) })
        return rhash + MsgPack.encode(.array([.uint(0), .bytes(hashmap)]))
    }

    /// Reads EVERY public accessor once (the torn-read surface).
    private func hammerAccessors(_ rt: ResourceTransfer) {
        _ = rt.status
        _ = rt.progress
        _ = rt.transferSize
        _ = rt.dataSize
        _ = rt.partCount
        _ = rt.segmentCount
        _ = rt.hash
        _ = rt.isCompressed
        _ = rt.hasMetadata
        _ = rt.receivedMetadata
        _ = rt.getProgress()
        _ = rt.status.isTerminal
    }

    // MARK: - Receiver

    func testConcurrentReceiverAccessDoesNotCrashOrRace() throws {
        let (_, bLink) = try establishLink()
        let advData = makeAdvertisementBytes()
        let hmuData = makeHMUBytes()

        let rt = ResourceTransfer(link: bLink)
        rt.retryTimeout = 0.02   // fire the watchdog aggressively during the run
        rt.bindAsReceiver()
        rt.receiveAdvertisement(advData) // seed valid receiver state + start watchdog

        let done = expectation(description: "receiver stress")
        let workers = 8
        let iterations = 1200

        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                for i in 0..<iterations {
                    switch (w &+ i) % 8 {
                    case 0: rt.receiveAdvertisement(advData)                 // heavy writer: advertisement + arrays + status
                    case 1: rt.receivePart(Data(repeating: UInt8(i & 0xFF), count: 40)) // parts/hashmap mutation
                    case 2: rt.handleHashmapUpdate(hmuData)                  // hashmap mutation
                    case 3: self.hammerAccessors(rt)                        // torn-read surface
                    case 4: self.hammerAccessors(rt)
                    case 5: rt.receivePart(Data(repeating: UInt8(w & 0xFF), count: 40))
                    case 6: if (w &+ i) % 97 == 0 { rt.cancel() }           // occasional terminal transition
                    default: self.hammerAccessors(rt)
                    }
                }
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
        // No assertion on final state — the point is "no crash, no TSan race, no deadlock".
        _ = rt.status
    }

    // MARK: - Sender

    func testConcurrentSenderAccessDoesNotCrashOrRace() throws {
        let (aLink, _) = try establishLink()

        let rt = ResourceTransfer(link: aLink)
        rt.retryTimeout = 0.02
        rt.testSegmentSizeOverride = 300  // force several parts
        try? rt.send(payload: Data(repeating: 0xAB, count: 900)) // seed sender state (encryptedSegments/mapHashes/adv)

        // Craft a plausible RESOURCE_REQ: [not-exhausted flag][32-byte resource hash][one 4-byte map-hash]
        let reqBase = Data([ResourceTransfer.hashmapIsNotExhausted]) + rt.hash + Data((0..<4).map { UInt8($0) })
        let proofRandom = Data(repeating: 0x22, count: 64)

        let done = expectation(description: "sender stress")
        let workers = 8
        let iterations = 1000

        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                for i in 0..<iterations {
                    switch (w &+ i) % 8 {
                    case 0: try? rt.send(payload: Data(repeating: UInt8(i & 0xFF), count: 900)) // heavy writer
                    case 1: rt.handleRequest(reqBase)                       // sends parts / advances status
                    case 2: rt.validateProof(proofRandom)                  // proof-mismatch → fail path
                    case 3: self.hammerAccessors(rt)
                    case 4: self.hammerAccessors(rt)
                    case 5: rt.handleRequest(reqBase + Data([UInt8(i & 0xFF)]))
                    case 6: if (w &+ i) % 113 == 0 { rt.cancel() }
                    default: self.hammerAccessors(rt)
                    }
                }
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
        _ = rt.status
    }
}
