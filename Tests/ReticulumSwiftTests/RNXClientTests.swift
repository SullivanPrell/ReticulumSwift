import XCTest
@testable import ReticulumSwift

/// The `rnx <destination> <command>` half, plus an in-process client↔listener round trip.
/// Python reference: RNS/Utilities/rnx.py:326-397.
final class RNXClientTests: XCTestCase {

    /// In-memory loopback interface. Every existing test file declares its own — there is
    /// no shared helper — so this follows the same idiom under an rnx-specific name.
    final class RNXLoopbackInterface: Interface {
        var name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        weak var paired: RNXLoopbackInterface?
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

    // MARK: - Pure logic

    func testParseDestination() throws {
        XCTAssertThrowsError(try RNXClient.parseDestination(String(repeating: "a", count: 31))) {
            XCTAssertEqual($0 as? RNXClient.ClientError, .invalidDestinationLength(31))
        }
        XCTAssertThrowsError(try RNXClient.parseDestination(String(repeating: "z", count: 32))) {
            XCTAssertEqual($0 as? RNXClient.ClientError, .invalidDestinationHex)
        }
        XCTAssertEqual(try RNXClient.parseDestination(String(repeating: "ab", count: 16)),
                       Data(repeating: 0xAB, count: 16))
    }

    func testRexecTimeoutArithmetic() {
        // Python: rexec_timeout = timeout + link.rtt*4 + remote_exec_grace (rnx.py:388).
        // Pins the *4 factor and the 2.0 grace against Link.trafficTimeoutFactor (6) and
        // Link.requestTimeoutGrace, which Swift would otherwise substitute.
        XCTAssertEqual(RNXClient.rexecTimeout(commandTimeout: 15, rtt: 0.25), 18.0, accuracy: 1e-9)
        XCTAssertEqual(RNXClient.rexecTimeout(commandTimeout: 15, rtt: nil), 17.0, accuracy: 1e-9)
    }

    func testStatusPredicatesMatchPythonScalarCompares() {
        // Python's statuses are plain ints; Swift's carry associated values, so each
        // predicate has to pattern-match rather than compare.
        XCTAssertTrue(RNXClient.isSent(.sent))
        XCTAssertTrue(RNXClient.isDelivered(.delivered))
        XCTAssertTrue(RNXClient.isReceiving(.receiving(0.5)))
        XCTAssertTrue(RNXClient.isFailed(.failed(reason: "timeout")))
        XCTAssertFalse(RNXClient.isReceiving(.ready(Data())))
        XCTAssertFalse(RNXClient.isSent(.delivered))
    }

    // MARK: - End-to-end harness

    struct Harness {
        let listener: RNXListener
        let executor: MockRNXCommandExecutor
        let client: RNXClient
        let initiatorTransport: Transport
        let responderTransport: Transport
        // Interfaces must stay alive for the duration of the test.
        let interfaces: [RNXLoopbackInterface]
    }

    private func makeHarness(allowAll: Bool,
                             allowed: [Data] = [],
                             clientIdentity: Identity = Identity()) throws -> Harness {
        let listenerIdentity = Identity()
        let responderTransport = Transport()
        responderTransport.ownerIdentity = listenerIdentity

        let executor = MockRNXCommandExecutor()
        let listener = try RNXListener(identity: listenerIdentity,
                                       transport: responderTransport,
                                       executor: executor,
                                       allowedIdentityHashes: allowed,
                                       allowAll: allowAll,
                                       executionQueue: DispatchQueue(label: "rnx.e2e"))
        listener.onLog = { _, _ in }
        listener.register()

        let initiatorTransport = Transport()
        let ifaceA = RNXLoopbackInterface(name: "initiator")
        let ifaceB = RNXLoopbackInterface(name: "responder")
        ifaceA.paired = ifaceB
        ifaceB.paired = ifaceA
        initiatorTransport.register(interface: ifaceA)
        responderTransport.register(interface: ifaceB)

        // The announce is what gives the initiator both a path and the listener identity —
        // exactly the state `rnx <dest>` needs before it can open a link.
        let announced = expectation(description: "initiator sees the announce")
        initiatorTransport.onAnnounceReceived = { _, _ in announced.fulfill() }
        try listener.announce()
        wait(for: [announced], timeout: 2.0)

        let client = RNXClient(transport: initiatorTransport,
                               identity: clientIdentity,
                               destinationHash: listener.destination.hash)
        return Harness(listener: listener, executor: executor, client: client,
                       initiatorTransport: initiatorTransport,
                       responderTransport: responderTransport,
                       interfaces: [ifaceA, ifaceB])
    }

    private func establishLink(_ harness: Harness, identify: Bool = true) throws {
        XCTAssertTrue(harness.client.hasPath, "announce should have installed a path")
        let established = expectation(description: "link active")
        harness.initiatorTransport.onLinkEstablished = { _ in established.fulfill() }
        try harness.client.openLinkIfNeeded()
        wait(for: [established], timeout: 3.0)
        XCTAssertEqual(harness.client.linkStatus, .active)
        try harness.client.identifyIfNeeded(noID: !identify)
    }

    // MARK: - End-to-end

    func testRequestResponseRoundTrip() throws {
        let harness = try makeHarness(allowAll: true)
        harness.executor.result = RNXExecution(spawned: true, returnCode: 0,
                                               stdout: Data("hi\n".utf8), stderr: Data())
        try establishLink(harness)

        let ready = expectation(description: "response ready")
        let receipt = try harness.client.sendCommand(RNXRequest(command: "echo hi", timeout: 15),
                                                     timeout: 10)
        receipt.onResponse = { _, _ in ready.fulfill() }
        wait(for: [ready], timeout: 5.0)

        let result = try RNXResult(unpacking: try MsgPack.decode(XCTUnwrap(receipt.response)))
        XCTAssertTrue(result.executed)
        XCTAssertEqual(result.returnCode, 0)
        XCTAssertEqual(result.stdout, Data("hi\n".utf8))
        XCTAssertEqual(result.totalStdoutLength, 3)
        XCTAssertEqual(harness.executor.calls.first?.command, "echo hi")
        XCTAssertEqual(harness.executor.calls.first?.timeout, 15)
    }

    func testAllowListGateSilentlyDropsUnidentifiedRequests() throws {
        // Python's ALLOW_LIST requires `__remote_identity != None` (Link.py:820-821) and
        // sends no response at all when it fails — the client just times out (exit 245)
        // rather than being told it was refused. `-N/--noid` is exactly this case.
        let harness = try makeHarness(allowAll: false, allowed: [])
        try establishLink(harness, identify: false)

        let neverReady = expectation(description: "response must not arrive")
        neverReady.isInverted = true
        let receipt = try harness.client.sendCommand(RNXRequest(command: "echo hi", timeout: 15),
                                                     timeout: 30)
        receipt.onResponse = { _, _ in neverReady.fulfill() }
        wait(for: [neverReady], timeout: 1.0)
        XCTAssertEqual(harness.executor.callCount, 0, "the executor must never run")
    }

    func testDisallowedIdentityTearsDownTheLink() throws {
        // Python: initiator_identified tears the link down for an identity that is not on
        // the list (rnx.py:148-153) — belt-and-braces on top of the handler gate.
        let harness = try makeHarness(allowAll: false, allowed: [Data(repeating: 0xAA, count: 16)])
        try establishLink(harness, identify: true)

        let closed = expectation(description: "link torn down")
        // The teardown may already have landed synchronously over the loopback.
        if harness.client.linkStatus == .closed {
            closed.fulfill()
        } else {
            harness.client.link?.setLinkClosedCallback { _ in closed.fulfill() }
        }
        wait(for: [closed], timeout: 3.0)
        XCTAssertEqual(harness.executor.callCount, 0)
    }

    func testAllowedIdentityIsAccepted() throws {
        let clientIdentity = Identity()
        let harness = try makeHarness(allowAll: false,
                                      allowed: [clientIdentity.hash],
                                      clientIdentity: clientIdentity)
        harness.executor.result = RNXExecution(spawned: true, returnCode: 0,
                                               stdout: Data("ok".utf8), stderr: Data())
        try establishLink(harness)

        let ready = expectation(description: "response ready")
        let receipt = try harness.client.sendCommand(RNXRequest(command: "id", timeout: 15),
                                                     timeout: 10)
        receipt.onResponse = { _, _ in ready.fulfill() }
        wait(for: [ready], timeout: 5.0)
        XCTAssertEqual(harness.executor.callCount, 1)
    }

    func testLargeStdinTravelsAsAResourceAndArrivesIntact() throws {
        // Regression test for Link.handleIncomingRequestResource, which dropped the native
        // request value twice (payload unwrapped only for .bytes, and `rawValue:` omitted
        // so the handler received .nil). Before the fix `rnx <dest> cat --stdin '<400+ B>'`
        // reached the listener as an empty request.
        let harness = try makeHarness(allowAll: true)
        harness.executor.result = RNXExecution(spawned: true, returnCode: 0,
                                               stdout: Data(), stderr: Data())
        try establishLink(harness)

        let stdin = Data((0..<2000).map { UInt8($0 % 251) })
        let request = RNXRequest(command: "cat", timeout: 15, stdin: stdin)
        XCTAssertGreaterThan(MsgPack.encode(request.packedValue()).count, Constants.linkMdu,
                             "payload must exceed the packet threshold to take the Resource path")

        let ready = expectation(description: "response ready")
        let receipt = try harness.client.sendCommand(request, timeout: 20)
        receipt.onResponse = { _, _ in ready.fulfill() }
        wait(for: [ready], timeout: 10.0)

        XCTAssertEqual(harness.executor.calls.first?.command, "cat")
        XCTAssertEqual(harness.executor.calls.first?.stdin, stdin)
    }

    func testLargeResponseReportsSizesAndProgress() throws {
        // Exercises the response Resource path, which needs both the deliverReady(size:)
        // wiring and the ResourceTransfer.onProgress invocation. Without them
        // responseSize / responseTransferSize stay nil and spin_stat renders 0.0% forever.
        let harness = try makeHarness(allowAll: true)
        let stdout = Data((0..<4000).map { _ in UInt8.random(in: 0...255) })
        harness.executor.result = RNXExecution(spawned: true, returnCode: 0,
                                               stdout: stdout, stderr: Data())
        try establishLink(harness)

        let progressLock = NSLock()
        var progressSamples: [Double] = []
        let ready = expectation(description: "response ready")
        let receipt = try harness.client.sendCommand(RNXRequest(command: "cat big", timeout: 15),
                                                     timeout: 30) { progress, _ in
            progressLock.lock(); progressSamples.append(progress); progressLock.unlock()
        }
        receipt.onResponse = { _, _ in ready.fulfill() }
        wait(for: [ready], timeout: 15.0)

        let result = try RNXResult(unpacking: try MsgPack.decode(XCTUnwrap(receipt.response)))
        XCTAssertEqual(result.stdout, stdout)
        XCTAssertNotNil(receipt.responseSize)
        XCTAssertNotNil(receipt.responseTransferSize)
        XCTAssertGreaterThan(receipt.responseTransferSize ?? 0, 0)
        progressLock.lock()
        let samples = progressSamples
        progressLock.unlock()
        XCTAssertFalse(samples.isEmpty, "ResourceTransfer.onProgress never fired")
        XCTAssertGreaterThan(samples.max() ?? 0, 0.0)
    }

    func testLinkIsReusedUntilClosed() throws {
        // Python: `if link == None or link.status == CLOSED or link.status == PENDING`
        // — ACTIVE / HANDSHAKE / STALE links are reused (rnx.py:364).
        let harness = try makeHarness(allowAll: true)
        try establishLink(harness)
        let first = harness.client.link
        try harness.client.openLinkIfNeeded()
        XCTAssertTrue(first === harness.client.link, "an active link must be reused")
        XCTAssertTrue(harness.client.didIdentify)
    }

    func testSmallResponseAlsoReportsSize() throws {
        // Python: transfer_size = len(umsgpack.packb(response_data))-2 for the
        // single-packet path (Link.py:998).
        let harness = try makeHarness(allowAll: true)
        harness.executor.result = RNXExecution(spawned: true, returnCode: 0,
                                               stdout: Data("ok".utf8), stderr: Data())
        try establishLink(harness)

        let ready = expectation(description: "response ready")
        let receipt = try harness.client.sendCommand(RNXRequest(command: "echo ok", timeout: 15),
                                                     timeout: 10)
        receipt.onResponse = { _, _ in ready.fulfill() }
        wait(for: [ready], timeout: 5.0)
        XCTAssertNotNil(receipt.responseSize)
        XCTAssertEqual(receipt.responseSize, receipt.responseTransferSize)
        XCTAssertGreaterThan(receipt.requestSize, 0)
    }
}
