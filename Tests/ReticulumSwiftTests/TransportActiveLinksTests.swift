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

/// `Transport.activeLinks`—the links this node holds an endpoint of.
///
/// Python keeps the same distinction `getLinkCount()` draws: `Transport.active_links` is the
/// list of links this node terminates, while `link_table` routes links it relays for others.
/// The two counts answer different questions and, on a transport node, disagree.
final class TransportActiveLinksTests: XCTestCase {

  func testActiveLinksIsEmptyByDefault() {
    XCTAssertTrue(Transport().activeLinks.isEmpty)
  }

  func testAnEstablishedLinkIsActiveOnBothEndsAndInNeitherLinkTable() throws {
    let aT = Transport()
    let bT = Transport()
    let bId = Identity()
    let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "al")
    bT.ownerIdentity = bId
    bT.register(destination: bDest)

    let a = ActiveLinksLoopback(name: "a")
    let b = ActiveLinksLoopback(name: "b")
    a.paired = b
    b.paired = a
    aT.register(interface: a)
    bT.register(interface: b)

    let aE = expectation(description: "a")
    let bE = expectation(description: "b")
    aT.onLinkEstablished = { _ in aE.fulfill() }
    bT.onLinkEstablished = { _ in bE.fulfill() }
    let link = try Link.initiate(destination: bDest, transport: aT)
    wait(for: [aE, bE], timeout: 1.0)

    XCTAssertEqual(aT.activeLinks.count, 1)
    XCTAssertEqual(
      aT.activeLinks.first?.linkID, link.linkID,
      "the list must contain the link itself, not merely be the right length")
    XCTAssertEqual(bT.activeLinks.count, 1)

    XCTAssertEqual(
      aT.getLinkCount(), 0,
      """
      the two counts must not track each other: this link is active on both \
      ends and relayed by neither, so `activeLinks` is 1 and the link table \
      is empty. Asserting they are equal—as this suite once did, on an empty \
      transport where both read 0—can't observe that.
      """)
    XCTAssertEqual(bT.getLinkCount(), 0)
  }

  func testTeardownEmptiesTheActiveLinkList() throws {
    let aT = Transport()
    let bT = Transport()
    let bId = Identity()
    let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "al2")
    bT.ownerIdentity = bId
    bT.register(destination: bDest)

    let a = ActiveLinksLoopback(name: "a")
    let b = ActiveLinksLoopback(name: "b")
    a.paired = b
    b.paired = a
    aT.register(interface: a)
    bT.register(interface: b)

    let aE = expectation(description: "a")
    let bE = expectation(description: "b")
    aT.onLinkEstablished = { _ in aE.fulfill() }
    bT.onLinkEstablished = { _ in bE.fulfill() }
    let link = try Link.initiate(destination: bDest, transport: aT)
    wait(for: [aE, bE], timeout: 1.0)
    XCTAssertEqual(aT.activeLinks.count, 1)

    let closed = expectation(description: "closed")
    link.onClosed = { _ in closed.fulfill() }
    try link.teardown()
    wait(for: [closed], timeout: 1.0)

    XCTAssertEqual(
      aT.activeLinks.count, 0,
      "a torn-down link leaves the list — otherwise the count only ever grows")
  }
}

private final class ActiveLinksLoopback: Interface {
  var name: String
  var bitrate: Int = 0
  var isOnline: Bool = true
  weak var paired: ActiveLinksLoopback?
  var inboundHandler: ((Packet, any Interface) -> Void)?
  init(name: String) { self.name = name }
  func start() throws { isOnline = true }
  func stop() { isOnline = false }
  func send(_ packet: Packet) throws {
    let raw = try packet.pack()
    paired?.inboundHandler?(try Packet.unpack(raw), paired!)
  }
}
