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

/// With `publish_blackhole` on, `Transport.start` builds `rnstransport.info.blackhole` on the
/// transport identity, answers `/list` for anyone with `blackholed_identities`, and adds the
/// destination to the management announces (`Transport.py:375-380`, `:4091-4097`), RNS 1.5.7.
final class BlackholePublishTests: XCTestCase {

  private var savedPublish = false
  private let sink = PathRequestResponderTests.CapturingInterface(name: "eth0")
  private let transport = Transport()

  override func setUp() {
    super.setUp()
    savedPublish = Reticulum.storedPublishBlackholeEnabled
    Reticulum.storedPublishBlackholeEnabled = true
    transport.transportIdentity = Identity()
    transport.ownerIdentity = transport.transportIdentity
    transport.register(interface: sink)
  }

  override func tearDown() {
    transport.stop()
    Reticulum.storedPublishBlackholeEnabled = savedPublish
    super.tearDown()
  }

  private func expectedHash() throws -> Data {
    try Destination(
      identity: XCTUnwrap(transport.transportIdentity), direction: .in, kind: .single,
      appName: "rnstransport", aspects: ["info", "blackhole"]
    ).hash
  }

  func testAnInstancePublishesTheListOnItsTransportIdentity() throws {
    try transport.start()
    let destination = try XCTUnwrap(transport.blackholeDestination)
    XCTAssertEqual(destination.hash, try expectedHash())
    XCTAssertTrue(transport.registeredDestinations[destination.hash] === destination)
  }

  func testListAnswersAnyoneWithEveryEntry() throws {
    try transport.start()
    let banned = Data(repeating: 0xB1, count: 16)
    let forever = Data(repeating: 0xB2, count: 16)
    transport.blackholeIdentity(banned, until: 1_900_000_000, reason: "spam")
    transport.blackholeIdentity(forever)

    let pathHash = Hashes.truncatedHash(Data("/list".utf8))
    let entry = try XCTUnwrap(transport.blackholeDestination?.requestHandlers[pathHash])
    XCTAssertEqual(entry.allow, .all, "ALLOW_ALL at Transport.py:377")
    let native = try XCTUnwrap(entry.nativeHandler, "rnpath checks `type(response) == dict`")
    let link = try Link.initiate(
      destination: Destination(
        identity: Identity(), direction: .in, kind: .single, appName: "dummy", aspects: ["l"]),
      transport: transport)
    let response = try XCTUnwrap(native(pathHash, .nil, Data(), link, 0))

    guard case .map(let pairs) = response else { return XCTFail("\(response)") }
    let source = MsgPack.Value.bytes(try XCTUnwrap(transport.transportIdentity).hash)
    let value = { (hash: Data) in pairs.first { $0.0 == .bytes(hash) }?.1 }
    XCTAssertEqual(pairs.count, 2)
    XCTAssertEqual(
      value(banned),
      .map([
        (.string("source"), source), (.string("until"), .double(1_900_000_000)),
        (.string("reason"), .string("spam")),
      ]))
    XCTAssertEqual(
      value(forever),
      .map([(.string("source"), source), (.string("until"), .nil), (.string("reason"), .nil)]))
  }

  /// Bytes from RNS 1.5.7's `umsgpack.packb` for `{b1…: {"source": a5…, "until": 1.9e9,
  /// "reason": "spam"}}` and for an entry with no expiry or reason.
  func testTheListEncodesAsPythonsDoes() {
    let source = Data(repeating: 0xA5, count: 16)
    transport.blackholedIdentities = [
      Data(repeating: 0xB1, count: 16): .init(source: source, until: 1_900_000_000, reason: "spam")
    ]
    XCTAssertEqual(
      MsgPack.encode(transport.blackholeListValue()).hexString,
      "81c410" + String(repeating: "b1", count: 16) + "83a6736f75726365c410"
        + String(repeating: "a5", count: 16)
        + "a5756e74696ccb41dc4fecc0000000a6726561736f6ea47370616d")
    XCTAssertEqual(
      MsgPack.encode(Transport.BlackholeEntry(source: source, until: nil, reason: nil).msgPackValue)
        .hexString,
      "83a6736f75726365c410" + String(repeating: "a5", count: 16)
        + "a5756e74696cc0a6726561736f6ec0")
  }

  func testTheListIsAManagementAnnounce() throws {
    try transport.start()
    transport.announceManagementDestinations(now: .greatestFiniteMagnitude)
    let announced = sink.sent.filter { $0.packetType == .announce }.map(\.destinationHash)
    XCTAssertTrue(announced.contains(try expectedHash()), "Transport.py:378")
  }

  func testNothingIsPublishedWhenOffOrForAClient() throws {
    Reticulum.storedPublishBlackholeEnabled = false
    try transport.start()
    XCTAssertNil(transport.blackholeDestination)
    transport.stop()

    Reticulum.storedPublishBlackholeEnabled = true
    let client = Transport()
    client.transportIdentity = Identity()
    client.isConnectedToSharedInstance = true
    try client.start()
    defer { client.stop() }
    XCTAssertNil(client.blackholeDestination, "Transport.py:375")
  }
}
