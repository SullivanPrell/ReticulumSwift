//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest

@testable import ReticulumSwift

/// `RequestReceipt` states as RNS 1.5.5 moves them (`Link.py:1320-1415`).
///
/// A request sent as one packet stays `SENT` until its response arrives, and
/// 1.5.5 lets `response_rejected` and `request_timed_out` conclude a `SENT`
/// receipt as well as a `DELIVERED` one. A request sent as a resource becomes
/// `DELIVERED` when the resource completes, and its response timeout starts then.
final class RequestReceiptStatusTests: XCTestCase {

  private struct Pair {
    let initiator: Link
    let responder: Link
    let destination: Destination
    let aT: Transport
    let bT: Transport
  }

  private func makeEstablishedPair() throws -> Pair {
    let aT = Transport()
    let bT = Transport()
    let bId = Identity()
    let bDest = try Destination(
      identity: bId, direction: .in, kind: .single, appName: "rrstatus", aspects: ["req"])
    bT.ownerIdentity = bId
    bT.register(destination: bDest)
    let aI = LoopbackInterface(name: "RRInitiator-\(Int.random(in: 0...10000))")
    let bI = LoopbackInterface(name: "RRResponder-\(Int.random(in: 0...10000))")
    aI.paired = bI
    bI.paired = aI
    aT.register(interface: aI)
    bT.register(interface: bI)
    let established = expectation(description: "link established")
    bT.onLinkEstablished = { _ in established.fulfill() }
    let initiator = try Link.initiate(destination: bDest, transport: aT)
    wait(for: [established], timeout: 2.0)
    let responder = try XCTUnwrap(bT.links[initiator.linkID!])
    return Pair(
      initiator: initiator, responder: responder, destination: bDest, aT: aT, bT: bT)
  }

  func testRejectingASentReceiptFailsIt() {
    let r = RequestReceipt(
      requestID: Data(repeating: 2, count: 16), path: "/x", requestSize: 10,
      maxResponseSize: 16)
    var failed = false
    r.onFailed = { _, _ in failed = true }
    r.responseRejected()
    guard case .failed = r.status else {
      return XCTFail("1.5.5 fails a SENT receipt on rejection, got \(r.status)")
    }
    XCTAssertTrue(failed)
  }

  func testRejectingAReceivingReceiptLeavesIt() {
    let r = RequestReceipt(
      requestID: Data(repeating: 3, count: 16), path: "/x", requestSize: 10,
      maxResponseSize: 16)
    r.beginReceivingResponse()
    r.responseRejected()
    XCTAssertEqual(r.status, .receiving(0), "Python guards on SENT and DELIVERED only")
  }

  func testAnOversizedSinglePacketResponseFailsTheRequestAtOnce() throws {
    let pair = try makeEstablishedPair()
    pair.destination.registerRequestHandler(path: "/big", allow: .all) { _, _, _, _, _ in
      Data(repeating: 0x41, count: 64)
    }
    let failed = expectation(description: "failed callback")
    var reason: String?
    let receipt = try pair.initiator.request(
      path: "/big",
      failedCallback: { r, _ in
        reason = r
        failed.fulfill()
      },
      timeout: 30, maxResponseSize: 8)
    wait(for: [failed], timeout: 2.0)
    XCTAssertTrue(receipt.isFailed)
    XCTAssertNotEqual(reason, "timeout", "the rejection concludes it, not the request timeout")
    _ = (pair.aT, pair.bT)
  }

  func testARequestSentAsAResourceIsDeliveredWhenTheResourceCompletes() throws {
    let pair = try makeEstablishedPair()
    let handled = expectation(description: "request handled")
    pair.destination.registerRequestHandler(path: "/quiet", allow: .all) { _, _, _, _, _ in
      handled.fulfill()
      return nil
    }
    let body = Data(repeating: 0x5A, count: pair.initiator.mdu * 3)
    let receipt = try pair.initiator.request(path: "/quiet", data: body, timeout: 30)
    wait(for: [handled], timeout: 5.0)
    let deadline = Date().addingTimeInterval(2)
    while receipt.status == .sent, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    XCTAssertEqual(receipt.status, .delivered, "request_resource_concluded, Link.py:1366-1372")
    _ = (pair.aT, pair.bT)
  }

  func testAResourceRequestTimeoutStartsWhenTheResourceCompletes() {
    let r = RequestReceipt(
      requestID: Data(repeating: 4, count: 16), path: "/x", requestSize: 10_000,
      timeout: 0.1, maxResponseSize: nil, sentAsResource: true)
    Thread.sleep(forTimeInterval: 0.3)
    XCTAssertEqual(r.status, .sent, "no response timeout runs while the request uploads")
    r.requestResourceConcluded(complete: true)
    XCTAssertEqual(r.status, .delivered)
    let deadline = Date().addingTimeInterval(2)
    while !r.isFailed, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    XCTAssertEqual(r.status, .failed(reason: "timeout"))
  }

  func testAFailedRequestResourceFailsTheReceipt() {
    let r = RequestReceipt(
      requestID: Data(repeating: 5, count: 16), path: "/x", requestSize: 10_000,
      timeout: 30, maxResponseSize: nil, sentAsResource: true)
    var failed = false
    r.onFailed = { _, _ in failed = true }
    r.requestResourceConcluded(complete: false)
    XCTAssertTrue(r.isFailed)
    XCTAssertTrue(failed)
  }
}
