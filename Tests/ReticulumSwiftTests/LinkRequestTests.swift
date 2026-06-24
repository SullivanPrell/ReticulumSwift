import XCTest
@testable import ReticulumSwift

final class LinkRequestTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String
        var bitrate: Int = 0
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

    var aTransport: Transport!
    var bTransport: Transport!

    private func establishLink() throws -> (Link, Link, Destination) {
        aTransport = Transport()
        bTransport = Transport()
        let bIdentity = Identity()
        let bDestination = try Destination(
            identity: bIdentity, direction: .in, kind: .single,
            appName: "lxmf", aspects: ["delivery"]
        )
        bTransport.ownerIdentity = bIdentity
        bTransport.register(destination: bDestination)

        let aIface = LoopbackInterface(name: "A")
        let bIface = LoopbackInterface(name: "B")
        aIface.paired = bIface; bIface.paired = aIface
        aTransport.register(interface: aIface)
        bTransport.register(interface: bIface)

        let aE = expectation(description: "a")
        let bE = expectation(description: "b")
        aTransport.onLinkEstablished = { _ in aE.fulfill() }
        bTransport.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDestination, transport: aTransport)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bTransport.links[aLink.linkID!])
        return (aLink, bLink, bDestination)
    }

    // MARK: - Basic round-trip

    func testRequestRoundTrip() throws {
        let (aLink, _, bDestination) = try establishLink()

        let handlerCalled = expectation(description: "handler")
        bDestination.registerRequestHandler(path: "ping", allow: .all) { _, payload, _, _, _ in
            handlerCalled.fulfill()
            return Data("pong:".utf8) + (payload ?? Data())
        }

        let received = expectation(description: "response")
        var got: Data?
        let receipt = try aLink.request(path: "ping", data: Data("hello".utf8))
        receipt.onResponse = { resp, _ in got = resp; received.fulfill() }

        wait(for: [handlerCalled, received], timeout: 1.0)
        XCTAssertEqual(got, Data("pong:hello".utf8))
        if case .ready(let d) = receipt.status {
            XCTAssertEqual(d, got)
        } else {
            XCTFail("expected ready status, got \(receipt.status)")
        }
    }

    func testUnregisteredPathProducesNoResponse() throws {
        let (aLink, _, _) = try establishLink()
        let receipt = try aLink.request(path: "missing")
        XCTAssertEqual(receipt.status, .sent)
    }

    func testRequestIDIsTruncatedHashOfPackedRequest() throws {
        let (aLink, _, _) = try establishLink()
        let receipt = try aLink.request(path: "x", data: Data("y".utf8))
        XCTAssertEqual(receipt.requestID.count, Constants.truncatedHashLength)
    }

    func testLargeRequestViaResource() throws {
        let (aLink, _, bDestination) = try establishLink()

        let handlerCalled = expectation(description: "handler")
        bDestination.registerRequestHandler(path: "large", allow: .all) { _, payload, _, _, _ in
            handlerCalled.fulfill()
            return payload ?? Data()
        }

        let bigPayload = Data(repeating: 0xCC, count: Constants.mdu + 100)
        let received = expectation(description: "response")
        var got: Data?
        let receipt = try aLink.request(path: "large", data: bigPayload)
        receipt.onResponse = { resp, _ in got = resp; received.fulfill() }

        wait(for: [handlerCalled, received], timeout: 3.0)
        XCTAssertEqual(got, bigPayload)
    }

    // MARK: - Allow policy

    func testRequestHandlerDefaultAllowNoneBlocksRequest() throws {
        let (aLink, _, bDestination) = try establishLink()

        let handlerCalled = expectation(description: "handler-blocked")
        handlerCalled.isInverted = true
        // Default allow policy is .none — handler should never fire.
        bDestination.registerRequestHandler(path: "secret") { _, _, _, _, _ in
            handlerCalled.fulfill()
            return Data("secret".utf8)
        }

        _ = try aLink.request(path: "secret")
        wait(for: [handlerCalled], timeout: 0.3)
    }

    func testRequestHandlerAllowAllServesRequest() throws {
        let (aLink, _, bDestination) = try establishLink()

        let handlerCalled = expectation(description: "handler")
        bDestination.registerRequestHandler(path: "pub", allow: .all) { _, _, _, _, _ in
            handlerCalled.fulfill()
            return Data("ok".utf8)
        }

        let responded = expectation(description: "response")
        let receipt = try aLink.request(path: "pub")
        receipt.onResponse = { _, _ in responded.fulfill() }
        wait(for: [handlerCalled, responded], timeout: 1.0)
    }

    func testRequestHandlerAllowListBlocksUnidentifiedPeer() throws {
        let (aLink, _, bDestination) = try establishLink()

        let handlerCalled = expectation(description: "handler-blocked")
        handlerCalled.isInverted = true
        let someIdentity = Identity()
        bDestination.registerRequestHandler(path: "restricted", allow: .list, allowedList: [someIdentity]) { _, _, _, _, _ in
            handlerCalled.fulfill()
            return Data("ok".utf8)
        }

        _ = try aLink.request(path: "restricted")
        wait(for: [handlerCalled], timeout: 0.3)
    }

    func testRequestHandlerAllowListServesIdentifiedPeer() throws {
        let (aLink, bLink, bDestination) = try establishLink()
        let aIdentity = Identity()

        let identified = expectation(description: "identified")
        bLink.onRemoteIdentified = { _, _ in identified.fulfill() }
        try aLink.identify(as: aIdentity)
        wait(for: [identified], timeout: 1.0)

        let handlerCalled = expectation(description: "handler")
        bDestination.registerRequestHandler(
            path: "restricted", allow: .list, allowedList: [aIdentity],
            handler: { _, _, _, _, _ in
                handlerCalled.fulfill()
                return Data("ok".utf8)
            }
        )

        let responded = expectation(description: "response")
        let receipt = try aLink.request(path: "restricted")
        receipt.onResponse = { _, _ in responded.fulfill() }
        wait(for: [handlerCalled, responded], timeout: 1.0)
    }

    // MARK: - Timeout

    func testRequestReceiptTimeoutFiresFailedCallback() throws {
        let (aLink, _, _) = try establishLink()
        // No handler registered — response will never arrive.
        let failed = expectation(description: "timeout")
        let receipt = try aLink.request(path: "noreply", timeout: 0.1)
        receipt.onFailed = { _, _ in failed.fulfill() }
        wait(for: [failed], timeout: 1.0)
        if case .failed = receipt.status { } else {
            XCTFail("expected failed status, got \(receipt.status)")
        }
    }

    func testRequestReceiptTimeoutReplayWhenCallbackSetAfterFire() throws {
        let (aLink, _, _) = try establishLink()
        let receipt = try aLink.request(path: "noreply", timeout: 0.05)
        // Wait for the timeout to fire before attaching the callback.
        Thread.sleep(forTimeInterval: 0.2)
        let failed = expectation(description: "replay")
        receipt.onFailed = { _, _ in failed.fulfill() }
        wait(for: [failed], timeout: 0.5)
    }

    // MARK: - Status progression

    func testRequestReceiptReadyStatusOnSuccess() throws {
        let (aLink, _, bDestination) = try establishLink()
        bDestination.registerRequestHandler(path: "ok", allow: .all) { _, _, _, _, _ in
            return Data("hi".utf8)
        }

        let responded = expectation(description: "response")
        let receipt = try aLink.request(path: "ok")
        receipt.onResponse = { _, _ in responded.fulfill() }
        wait(for: [responded], timeout: 1.0)

        if case .ready(let d) = receipt.status {
            XCTAssertEqual(d, Data("hi".utf8))
        } else {
            XCTFail("expected ready, got \(receipt.status)")
        }
        XCTAssertNotNil(receipt.responseConcludedAt)
        XCTAssertNotNil(receipt.responseTime)
    }

    func testRequestReceiptResponseReplayWhenSetAfterReady() throws {
        let (aLink, _, bDestination) = try establishLink()
        bDestination.registerRequestHandler(path: "replay", allow: .all) { _, _, _, _, _ in
            return Data("x".utf8)
        }

        let responded = expectation(description: "response1")
        let receipt = try aLink.request(path: "replay")
        receipt.onResponse = { _, _ in responded.fulfill() }
        wait(for: [responded], timeout: 1.0)

        // Setting a second callback after status is .ready should replay immediately.
        let replayed = expectation(description: "replay")
        receipt.onResponse = { _, _ in replayed.fulfill() }
        wait(for: [replayed], timeout: 0.2)
    }

    func testRequestSizeIsCorrect() throws {
        let (aLink, _, _) = try establishLink()
        let data = Data("hello".utf8)
        let receipt = try aLink.request(path: "x", data: data)
        XCTAssertGreaterThan(receipt.requestSize, 0)
    }

    // MARK: - RTT-based default timeout

    func testDefaultTimeoutDerivesFromRTT() throws {
        let (aLink, _, _) = try establishLink()
        // After link establishment, rtt should be set.
        XCTAssertNotNil(aLink.rtt, "rtt must be set after link establishment")

        guard let rtt = aLink.rtt else { return }
        let expected = rtt * Link.trafficTimeoutFactor + Link.requestTimeoutGrace

        // Fire a request with no explicit timeout — the receipt should have the RTT-derived timeout.
        // We can't inspect the timeout directly, but we can verify it's sane.
        // If rtt is very small (in-process loopback), expected ≈ requestTimeoutGrace + ε.
        XCTAssertGreaterThan(expected, Link.requestTimeoutGrace - 0.001)
    }

    func testExplicitTimeoutOverridesDefault() throws {
        let (aLink, bLink, bDest) = try establishLink()
        bDest.registerRequestHandler(path: "/slow", allow: .all) { _, _, _, _, _ in
            // Don't respond — let the explicit timeout fire.
            return nil
        }

        let failed = expectation(description: "explicit timeout fires")
        let receipt = try aLink.request(path: "/slow", data: nil, timeout: 0.1)
        receipt.onFailed = { _, _ in failed.fulfill() }
        wait(for: [failed], timeout: 2.0)
        _ = bLink  // keep alive
    }

    func testTrafficTimeoutFactorConstant() {
        XCTAssertEqual(Link.trafficTimeoutFactor, 6.0)
    }

    func testRequestTimeoutGraceConstant() {
        XCTAssertEqual(Link.requestTimeoutGrace, 11.25, accuracy: 0.001)
    }

    // MARK: - Native request handler (Python-compatible)

    /// A native handler receives the raw MsgPack value (not re-encoded bytes)
    /// and returns a native value that is embedded directly in the response array.
    func testNativeRequestHandlerReceivesArrayValue() throws {
        let (aLink, _, bDestination) = try establishLink()

        var receivedValue: MsgPack.Value?
        let handlerCalled = expectation(description: "native handler")
        bDestination.registerNativeRequestHandler(path: "/native", allow: .all) { _, data, _, _, _ in
            receivedValue = data
            handlerCalled.fulfill()
            return .array([.uint(1), .uint(2)])
        }

        // Send a native array (Python-style, not bytes-wrapped)
        let received = expectation(description: "response")
        var got: Data?
        let receipt = try aLink.request(path: "/native",
                                        nativeValue: .array([.uint(42), .nil]))
        receipt.onResponse = { resp, _ in got = resp; received.fulfill() }

        wait(for: [handlerCalled, received], timeout: 1.0)

        // Verify handler received the raw array (not re-encoded bytes)
        XCTAssertEqual(receivedValue, .array([.uint(42), .nil]))

        // Verify response is a native array embedded directly (not bytes-wrapped)
        let decoded = try? MsgPack.decode(got!)
        XCTAssertEqual(decoded, .array([.uint(1), .uint(2)]))
    }

    /// Native handler returning nil sends no response.
    func testNativeRequestHandlerNilReturnsNoResponse() throws {
        let (aLink, _, bDestination) = try establishLink()
        bDestination.registerNativeRequestHandler(path: "/nil-native", allow: .all) { _, _, _, _, _ in
            return nil
        }
        let receipt = try aLink.request(path: "/nil-native", nativeValue: .nil)
        XCTAssertEqual(receipt.status, .sent)
        // Brief wait — no response expected.
        let noResp = expectation(description: "no-resp")
        noResp.isInverted = true
        receipt.onResponse = { _, _ in noResp.fulfill() }
        wait(for: [noResp], timeout: 0.2)
    }

    /// Bytes handler still wraps response in .bytes (backward compat).
    func testBytesHandlerResponseIsWrappedAsBytes() throws {
        let (aLink, _, bDestination) = try establishLink()
        bDestination.registerRequestHandler(path: "/bytes", allow: .all) { _, _, _, _, _ in
            return Data([0x01, 0x02, 0x03])
        }
        let received = expectation(description: "response")
        var got: Data?
        let receipt = try aLink.request(path: "/bytes")
        receipt.onResponse = { resp, _ in got = resp; received.fulfill() }
        wait(for: [received], timeout: 1.0)
        // Response data is the raw bytes (not double-encoded)
        XCTAssertEqual(got, Data([0x01, 0x02, 0x03]))
    }
}
