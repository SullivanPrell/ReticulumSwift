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

/// Python remembers handled path-request tags in two sets, `discovery_pr_tags` and
/// `discovery_pr_tags_prev`, capped by `max_pr_tags = 16000` (`Transport.py:193-195`).
///
/// A request is new only when its tag is in neither (`:1849-1851`), and the jobs loop rotates the
/// sets once the current one passes the cap (`:849-853`), RNS 1.5.5.
///
/// A request counts toward `prxc` only once it passes the duplicate check (`:1857`), so the
/// count is the observable. Each resend names a different requesting transport, which leaves
/// the dedup key (destination + tag) alone but changes the packet hash, so the packet hashlist
/// can't be what drops it.
final class PathRequestTagCacheTests: XCTestCase {

  private let transport = Transport()
  private let iface = PathRequestResponderTests.CapturingInterface(name: "in")

  override func setUp() {
    super.setUp()
    transport.register(interface: iface)
  }

  private var admitted: Int { transport.interfaceCounts(for: iface).pathRequestRxCount }

  private func receive(target: Data, tag: Data) {
    let body = target + Data((0..<16).map { _ in UInt8.random(in: 0...255) }) + tag
    let request = Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Transport.pathRequestDestinationHash, data: body)
    iface.inboundHandler?(request, iface)
  }

  private func isDuplicate(target: Data, tag: Data) -> Bool {
    let before = admitted
    receive(target: target, tag: tag)
    return admitted == before
  }

  private func randomHash() -> Data { Data((0..<16).map { _ in UInt8.random(in: 0...255) }) }

  func testATagOutlivesFourThousandNewerOnes() {
    let target = randomHash()
    let tag = randomHash()
    receive(target: target, tag: tag)
    for _ in 0..<4096 { receive(target: randomHash(), tag: randomHash()) }
    XCTAssertEqual(admitted, 4097, "test premise: every distinct tag is admitted")
    XCTAssertTrue(isDuplicate(target: target, tag: tag))
  }

  func testTheJobsLoopKeepsExactlyTwoGenerations() {
    transport.pathRequestCacheCap = 4
    let first = (0..<5).map { _ in (randomHash(), randomHash()) }
    for (target, tag) in first { receive(target: target, tag: tag) }
    XCTAssertTrue(
      isDuplicate(target: first[0].0, tag: first[0].1),
      "the cap is enforced by the jobs loop, not on insert (Transport.py:850)")

    transport.runJobs()
    let second = (0..<5).map { _ in (randomHash(), randomHash()) }
    for (target, tag) in second { receive(target: target, tag: tag) }
    XCTAssertTrue(isDuplicate(target: first[1].0, tag: first[1].1), "the previous generation")

    transport.runJobs()
    XCTAssertTrue(isDuplicate(target: second[0].0, tag: second[0].1), "the previous generation")
    XCTAssertFalse(
      isDuplicate(target: first[2].0, tag: first[2].1), "the generation before is forgotten")
  }

  /// No Python counterpart: `requestPath` pre-seeds its own tag, so its echo is dropped.
  func testAnEchoOfThisNodesOwnRequestIsADuplicate() throws {
    let target = randomHash()
    try transport.requestPath(for: target)
    let sent = try XCTUnwrap(
      iface.sent.last { $0.destinationHash == Transport.pathRequestDestinationHash })
    XCTAssertTrue(isDuplicate(target: target, tag: Data(sent.data.suffix(16))))
  }
}
