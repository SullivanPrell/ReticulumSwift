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

/// File-backed request responses, response metadata, and the compression limit.
///
/// Upstream added all three in RNS 0.9.6 (`594f5fba`, "Added ability to return file
/// resources for request responses. Added option to specify request response
/// auto-compression limits."). None was ported. A response generator returning
/// `(file_handle, metadata)` is how `rngit` serves a git bundle
/// (`Utilities/rngit/server.py:3001`), and the result code rides in the metadata.
final class RequestFileResponseTests: XCTestCase {

  final class AsyncLoopbackInterface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    weak var paired: AsyncLoopbackInterface?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    let queue: DispatchQueue
    init(name: String, queue: DispatchQueue) {
      self.name = name
      self.queue = queue
    }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
      let raw = try packet.pack()
      queue.async { [weak self] in
        guard let paired = self?.paired, let copy = try? Packet.unpack(raw) else { return }
        paired.inboundHandler?(copy, paired)
      }
    }
  }

  var aT: Transport!
  var bT: Transport!
  private var scratch: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("rs-file-response-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: scratch)
    aT = nil
    bT = nil
    try super.tearDownWithError()
  }

  /// Incompressible, so a payload stays over the segment threshold on the wire.
  private func incompressible(_ count: Int) -> Data {
    Data((0..<count).map { _ in UInt8.random(in: 0...255) })
  }

  private func writeScratchFile(_ bytes: Data, named name: String = "payload.bin") throws -> URL {
    let url = scratch.appendingPathComponent(name)
    try bytes.write(to: url)
    return url
  }

  /// The responder is `aLink.destination`; requests are sent from `bLink`.
  private func makeLinkedPair() throws -> (aLink: Link, bLink: Link) {
    aT = Transport()
    bT = Transport()
    let bId = Identity()
    let bDest = try Destination(
      identity: bId, direction: .in, kind: .single, appName: "fr")
    bT.ownerIdentity = bId
    bT.register(destination: bDest)
    let queue = DispatchQueue(label: "file-response-loopback")
    let a = AsyncLoopbackInterface(name: "a", queue: queue)
    let b = AsyncLoopbackInterface(name: "b", queue: queue)
    a.paired = b
    b.paired = a
    aT.register(interface: a)
    bT.register(interface: b)
    let aE = expectation(description: "aE")
    let bE = expectation(description: "bE")
    aT.onLinkEstablished = { _ in aE.fulfill() }
    bT.onLinkEstablished = { _ in bE.fulfill() }
    let aLink = try Link.initiate(destination: bDest, transport: aT)
    wait(for: [aE, bE], timeout: 5.0)
    let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
    return (aLink, bLink)
  }

  private struct RequestOutcome {
    var response: Data?
    var metadata: MsgPack.Value?
    var failure: String?
  }

  private func sendRequest(
    on link: Link, path: String, data: Data? = nil, timeout: TimeInterval = 30
  ) throws -> RequestOutcome {
    let done = expectation(description: "request \(path)")
    var outcome = RequestOutcome()
    _ = try link.request(
      path: path,
      data: data,
      responseCallback: { payload, receipt in
        outcome.response = payload
        outcome.metadata = receipt.metadata
        done.fulfill()
      },
      failedCallback: { reason, _ in
        outcome.failure = reason
        done.fulfill()
      },
      timeout: timeout)
    wait(for: [done], timeout: timeout + 5)
    return outcome
  }

  // MARK: - File responses

  /// A response generator may answer with a file, which is sent as a resource.
  ///
  /// Python: `RNS.Resource(file_handle, self, metadata=metadata, request_id=request_id,
  /// is_response=True)` (`Link.py:846`). The file's bytes are the resource payload:
  /// there is no `[request_id, response]` msgpack envelope on this path, the request
  /// ID rides in the advertisement instead.
  func testFileResponseDeliversTheFileBytes() throws {
    let (aLink, bLink) = try makeLinkedPair()
    let body = incompressible(9_000)
    let url = try writeScratchFile(body)

    aLink.destination.registerResponseGenerator(path: "/file", allow: .all) { _, _, _, _, _ in
      .file(url, metadata: nil)
    }

    let outcome = try sendRequest(on: bLink, path: "/file")
    XCTAssertNil(outcome.failure, "file response failed: \(outcome.failure ?? "")")
    XCTAssertEqual(outcome.response, body)
  }

  /// The metadata a generator returns reaches the requester's receipt.
  ///
  /// Python: `pending_request.response_received(response, metadata)` sets
  /// `RequestReceipt.metadata` (`Link.py:1437-1441`). `rngit`'s client reads its
  /// result code straight out of it (`rngit/client.py:519-522`).
  func testFileResponseMetadataReachesTheReceipt() throws {
    let (aLink, bLink) = try makeLinkedPair()
    let body = incompressible(6_000)
    let url = try writeScratchFile(body)

    aLink.destination.registerResponseGenerator(path: "/file", allow: .all) { _, _, _, _, _ in
      .file(url, metadata: .map([(.uint(0x01), .uint(0x00))]))
    }

    let outcome = try sendRequest(on: bLink, path: "/file")
    XCTAssertNil(outcome.failure, "file response failed: \(outcome.failure ?? "")")
    XCTAssertEqual(outcome.response, body)
    guard case .map(let pairs)? = outcome.metadata else {
      return XCTFail("no metadata on the receipt, got \(String(describing: outcome.metadata))")
    }
    XCTAssertEqual(pairs.count, 1)
    XCTAssertEqual(pairs.first?.0, .uint(0x01))
    XCTAssertEqual(pairs.first?.1, .uint(0x00))
  }

  /// A value response carries no metadata, so the receipt reports none.
  func testValueResponseHasNoMetadata() throws {
    let (aLink, bLink) = try makeLinkedPair()
    aLink.destination.registerResponseGenerator(path: "/value", allow: .all) { _, _, _, _, _ in
      .value(.bytes(Data([0x00])))
    }

    let outcome = try sendRequest(on: bLink, path: "/value")
    XCTAssertNil(outcome.failure, "value response failed: \(outcome.failure ?? "")")
    XCTAssertNil(outcome.metadata, "a value response must not synthesise metadata")
  }

  /// A generator answering `nil` sends nothing, exactly as a byte handler's nil does.
  func testNilResponseSendsNothing() throws {
    let (aLink, bLink) = try makeLinkedPair()
    aLink.destination.registerResponseGenerator(path: "/quiet", allow: .all) { _, _, _, _, _ in
      nil
    }

    let outcome = try sendRequest(on: bLink, path: "/quiet", timeout: 3)
    XCTAssertNil(outcome.response)
    XCTAssertNotNil(outcome.failure, "an unanswered request must time out, not succeed")
  }

  /// An unreadable file fails the request rather than answering with an empty body.
  func testUnreadableFileResponseDoesNotAnswerWithEmptyBody() throws {
    let (aLink, bLink) = try makeLinkedPair()
    let missing = scratch.appendingPathComponent("does-not-exist.bin")
    aLink.destination.registerResponseGenerator(path: "/gone", allow: .all) { _, _, _, _, _ in
      .file(missing, metadata: nil)
    }

    let outcome = try sendRequest(on: bLink, path: "/gone", timeout: 3)
    XCTAssertNotEqual(
      outcome.response, Data(),
      "a missing file must not be delivered as a successful empty response")
  }

  /// A file larger than one segment arrives whole, and its metadata survives the split.
  ///
  /// Python reads each segment from the open file rather than buffering the whole of it
  /// (`Resource.py:307-322`), and only segment 1 carries the metadata block
  /// (`Resource.py:709-717`).
  func testSplitFileResponseArrivesWholeWithMetadata() throws {
    ResourceTransfer.testSegmentSizeOverrideGlobal = 4_000
    defer { ResourceTransfer.testSegmentSizeOverrideGlobal = nil }

    let (aLink, bLink) = try makeLinkedPair()
    let body = incompressible(11_000)
    let url = try writeScratchFile(body)

    aLink.destination.registerResponseGenerator(path: "/big", allow: .all) { _, _, _, _, _ in
      .file(url, metadata: .map([(.string("code"), .uint(7))]))
    }

    let outcome = try sendRequest(on: bLink, path: "/big", timeout: 60)
    XCTAssertNil(outcome.failure, "split file response failed: \(outcome.failure ?? "")")
    XCTAssertEqual(outcome.response?.count, body.count)
    XCTAssertEqual(outcome.response, body)
    guard case .map(let pairs)? = outcome.metadata else {
      return XCTFail("metadata lost across the segment split")
    }
    XCTAssertEqual(pairs.first?.1, .uint(7))
  }
}
