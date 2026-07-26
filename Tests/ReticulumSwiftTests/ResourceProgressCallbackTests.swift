import XCTest
@testable import ReticulumSwift

/// `Resource.progress_callback` parity (Python `RNS/Resource.py`).
///
/// Python fires the progress callback in two places: on the receiver for every
/// newly-accepted part (Resource.py:889-893), and on the sender at the tail of
/// its part-send loop (Resource.py:1075-1081). Swift declared `onProgress` and
/// wired it through `Link.request(progressCallback:)` and
/// `RequestReceipt.updateProgress`, but nothing ever called it — so every
/// progress observer in the stack was silently inert, and a mid-transfer
/// `responseSize` (the only time it is useful) was never readable.
final class ResourceProgressCallbackTests: XCTestCase {

    final class LoopIface: Interface {
        var name: String; var bitrate: Int = 1_000_000; var isOnline: Bool = true
        weak var paired: LoopIface?
        var inboundHandler: ((Packet, any Interface) -> Void)?

        /// Deliver on a serial queue instead of inside the caller's stack.
        ///
        /// Synchronous delivery makes a resource transfer run to completion inside
        /// the first `send`, which hides every intermediate state from the sender —
        /// its own progress emits all land after the last part has gone out. Real
        /// interfaces never behave that way. Ordering is still FIFO.
        var asynchronous: Bool = false
        private let queue: DispatchQueue

        init(name: String) {
            self.name = name
            self.queue = DispatchQueue(label: "loopiface.\(name)")
        }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            guard let paired else { return }
            if asynchronous {
                queue.async {
                    guard let copy = try? Packet.unpack(raw) else { return }
                    paired.inboundHandler?(copy, paired)
                }
            } else {
                let copy = try Packet.unpack(raw)
                paired.inboundHandler?(copy, paired)
            }
        }
    }

    private var transports: [Transport] = []

    /// Incompressible, so it stays over the link MDU on the wire and is actually
    /// transferred as a multi-part Resource.
    private func incompressible(_ count: Int) -> Data {
        Data((0 ..< count).map { _ in UInt8.random(in: 0 ... 255) })
    }

    private func establishLink(requestPayload: Data? = nil,
                               asynchronous: Bool = false) throws -> (Link, Link, Destination) {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["progress"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        if let requestPayload {
            bDest.registerRequestHandler(path: "/big", allow: .all) { _, _, _, _, _ in requestPayload }
        }

        let aI = LoopIface(name: "A"); let bI = LoopIface(name: "B")
        aI.paired = bI; bI.paired = aI
        aI.asynchronous = asynchronous; bI.asynchronous = asynchronous
        aT.register(interface: aI); bT.register(interface: bI)

        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }; bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 2.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        transports = [aT, bT]
        return (aLink, bLink, bDest)
    }

    // MARK: - Receiver side

    func testReceiverFiresProgressCallbackPerPart() throws {
        let (aLink, bLink, _) = try establishLink()
        bLink.setResourceStrategy(.acceptAll)

        let lock = NSLock()
        var observed: [Double] = []
        let concluded = expectation(description: "concluded")
        bLink.onResourceStarted = { transfer in
            transfer.onProgress = { p, _ in
                lock.lock(); observed.append(p); lock.unlock()
            }
        }
        bLink.setResourceConcludedCallback { _, _, _ in concluded.fulfill() }

        let rt = ResourceTransfer(link: aLink)
        try rt.send(payload: incompressible(8192))
        wait(for: [concluded], timeout: 10.0)

        lock.lock(); let progress = observed; lock.unlock()
        XCTAssertGreaterThan(progress.count, 1,
                             "a multi-part transfer must report progress more than once")
        XCTAssertEqual(progress, progress.sorted(),
                       "receiver progress must be monotonically non-decreasing")
        XCTAssertEqual(progress.last, 1.0,
                       "the final part must report a complete transfer")
    }

    // MARK: - Sender side

    /// Python's `get_progress` measures *sent* parts for the initiator
    /// (Resource.py:1146-1149). Swift used the receive counter for both roles, so
    /// a sender reported 0.0 for the entire transfer and then jumped to 1.0.
    func testSenderProgressAdvancesBeforeCompletion() throws {
        let (aLink, bLink, _) = try establishLink(asynchronous: true)
        bLink.setResourceStrategy(.acceptAll)

        let lock = NSLock()
        var observed: [Double] = []
        let done = expectation(description: "sender done")

        let rt = ResourceTransfer(link: aLink)
        rt.onProgress = { p, _ in lock.lock(); observed.append(p); lock.unlock() }
        rt.onComplete = { _ in done.fulfill() }
        try rt.send(payload: incompressible(8192))
        wait(for: [done], timeout: 10.0)

        lock.lock(); let progress = observed; lock.unlock()
        XCTAssertFalse(progress.isEmpty, "sender never reported progress")
        XCTAssertTrue(progress.contains { $0 > 0.0 && $0 < 1.0 },
                      "sender only ever reported 0.0 or 1.0: \(progress) — the receive "
                      + "counter is 0 for a sender, so reading it yields 0.0 until the "
                      + "status flips to complete and short-circuits to 1.0")
        XCTAssertEqual(progress, progress.sorted())
    }

    // MARK: - Through RequestReceipt

    /// The whole reason the callback matters above the Resource layer: a request
    /// whose response arrives as a Resource must expose its size and progress
    /// *while it is arriving*.
    func testRequestReceiptReportsResponseSizeMidTransfer() throws {
        let payload = incompressible(8192)
        let (aLink, _, _) = try establishLink(requestPayload: payload)

        let sawSize = expectation(description: "size visible mid-transfer")
        sawSize.assertForOverFulfill = false
        let responded = expectation(description: "response delivered")

        let lock = NSLock()
        var midTransferSize: Int?
        var midTransferProgress: Double?

        _ = try aLink.request(
            path: "/big",
            data: Data([0x01]),
            responseCallback: { _, _ in responded.fulfill() },
            progressCallback: { progress, receipt in
                guard progress < 1.0, let size = receipt.responseSize else { return }
                lock.lock()
                if midTransferSize == nil { midTransferSize = size; midTransferProgress = progress }
                lock.unlock()
                sawSize.fulfill()
            },
            timeout: 30
        )
        wait(for: [sawSize, responded], timeout: 10.0)

        lock.lock(); let size = midTransferSize; let progress = midTransferProgress; lock.unlock()
        let observedSize = try XCTUnwrap(size)
        XCTAssertGreaterThanOrEqual(observedSize, payload.count,
                                    "advertised response size should cover the payload")
        let observedProgress = try XCTUnwrap(progress)
        XCTAssertGreaterThan(observedProgress, 0.0)
        XCTAssertLessThan(observedProgress, 1.0)
    }
}
