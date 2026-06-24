import XCTest
@testable import ReticulumSwift

/// Tests that Link.request() wires the Python-compatible callback parameters
/// (responseCallback, failedCallback, progressCallback) to the RequestReceipt.
final class LinkRequestCallbackTests: XCTestCase {

    private struct TestPair {
        let initiator: Link
        let responder: Link
        let aT: Transport  // kept alive (Link holds a weak reference)
        let bT: Transport
    }

    private func makeEstablishedPair() throws -> TestPair {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "cbtest", aspects: ["req"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)
        let aI = LoopbackInterface(name: "CBInitiator-\(Int.random(in: 0...10000))")
        let bI = LoopbackInterface(name: "CBResponder-\(Int.random(in: 0...10000))")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let established = expectation(description: "link established")
        bT.onLinkEstablished = { _ in established.fulfill() }
        let initiator = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [established], timeout: 2.0)
        let responder = try XCTUnwrap(bT.links[initiator.linkID!])
        return TestPair(initiator: initiator, responder: responder, aT: aT, bT: bT)
    }

    func testRequestWithFailedCallbackReceivesTimeoutFailure() throws {
        let pair = try makeEstablishedPair()
        let exp = expectation(description: "failedCallback fires on timeout")
        let receipt = try pair.initiator.request(
            path: "/status",
            failedCallback: { _, _ in exp.fulfill() },
            timeout: 0.05
        )
        XCTAssertEqual(receipt.path, "/status")
        wait(for: [exp], timeout: 2.0)
        XCTAssertTrue(receipt.isFailed)
        _ = pair.aT // keep alive
    }

    func testRequestCallbacksAssignedToReceipt() throws {
        let pair = try makeEstablishedPair()
        var responseFired = false
        var progressFired = false
        let receipt = try pair.initiator.request(
            path: "/check",
            responseCallback: { _, _ in responseFired = true },
            failedCallback: { _, _ in },
            progressCallback: { _, _ in progressFired = true },
            timeout: 30
        )
        XCTAssertNotNil(receipt.onResponse)
        XCTAssertNotNil(receipt.onFailed)
        XCTAssertNotNil(receipt.onProgress)
        receipt.onResponse?(Data(), receipt)
        receipt.onProgress?(0.5, receipt)
        XCTAssertTrue(responseFired)
        XCTAssertTrue(progressFired)
        _ = pair.aT
    }

    func testRequestWithoutCallbacksDoesNotCrash() throws {
        let pair = try makeEstablishedPair()
        let receipt = try pair.initiator.request(path: "/noop", timeout: 0.001)
        XCTAssertFalse(receipt.isReady)
        Thread.sleep(forTimeInterval: 0.05)
        _ = pair.aT
    }
}
