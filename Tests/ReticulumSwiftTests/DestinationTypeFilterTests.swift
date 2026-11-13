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

/// RNS 1.6.0's destination-type filter: blocked, allowed and client-wanted announce types, the
/// `required_only` ingress gate, the hop limiter and the `[filter]` config section
/// (`Transport.py:2022`, `2033-2042`, `4623-4693`; `Reticulum.py:487-503`).
final class DestinationTypeFilterTests: XCTestCase {

  final class Tap: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var sent: [Packet] = []
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(try Packet.unpack(packet.pack())) }
  }

  private var retained: [AnyObject] = []

  /// An announce for `app.aspect`, as another node puts it on the wire, with `hops` set.
  private func announce(_ app: String, _ aspect: String, hops: UInt8 = 0) throws -> (Packet, Data) {
    let b = Transport()
    let tap = Tap(name: "tap")
    b.register(interface: tap)
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: app, aspects: [aspect])
    b.register(destination: destination)
    retained += [b, tap]
    _ = try b.announce(destination: destination)
    var packet = try XCTUnwrap(tap.sent.last { $0.packetType == .announce })
    packet.hops = hops
    return (packet, destination.hash)
  }

  private func receiver() -> (Transport, Tap) {
    let a = Transport()
    let inbound = Tap(name: "in")
    a.register(interface: inbound)
    retained += [a, inbound]
    return (a, inbound)
  }

  private func admits(_ a: Transport, _ on: Tap, _ app: String, _ aspect: String, hops: UInt8 = 0)
    throws -> Bool
  {
    let (packet, hash) = try announce(app, aspect, hops: hops)
    a.handleIncoming(packet: packet, from: on)
    return a.hasPath(to: hash)
  }

  // MARK: - Ingress

  /// `if name_hash in Transport.blocked_destination_types: return` (`Transport.py:2035`).
  func testABlockedTypeIsDroppedAtIngress() throws {
    let (a, inbound) = receiver()
    XCTAssertTrue(a.blockDestinationType("filter.blocked"))

    XCTAssertFalse(try admits(a, inbound, "filter", "blocked"))
    XCTAssertTrue(try admits(a, inbound, "filter", "other"))
    XCTAssertFalse(
      a.wantsDestinationType("filter.blocked", requester: Data(repeating: 1, count: 16)),
      "a blocked type can't be wanted (`Transport.py:4652`)")
  }

  /// `required_only` admits allowed and client-wanted types only (`Transport.py:2036-2042`).
  func testRequiredOnlyAdmitsAllowedAndWantedTypes() throws {
    let (a, inbound) = receiver()
    a.requiredDestinationsOnly = true
    let requester = Data(repeating: 7, count: 16)

    XCTAssertFalse(try admits(a, inbound, "filter", "plain"))

    XCTAssertTrue(a.allowDestinationType("filter.allowed"))
    XCTAssertTrue(try admits(a, inbound, "filter", "allowed"))

    XCTAssertTrue(a.wantsDestinationType("filter.wanted", requester: requester))
    XCTAssertTrue(try admits(a, inbound, "filter", "wanted"))

    XCTAssertTrue(a.unwantsDestinationType("filter.wanted", requester: requester))
    XCTAssertFalse(try admits(a, inbound, "filter", "wanted"), "no requester left wants it")
  }

  /// Every requester's want is dropped by `_unwants_all_destination_types` (`Transport.py:4683`).
  func testUnwantingAllTypesDropsEveryWantOfOneRequester() throws {
    let (a, inbound) = receiver()
    a.requiredDestinationsOnly = true
    let one = Data(repeating: 1, count: 16)
    let other = Data(repeating: 2, count: 16)
    XCTAssertTrue(a.wantsDestinationType("filter.first", requester: one))
    XCTAssertTrue(a.wantsDestinationType("filter.shared", requester: one))
    XCTAssertTrue(a.wantsDestinationType("filter.shared", requester: other))

    XCTAssertTrue(a.unwantsAllDestinationTypes(requester: one))

    XCTAssertFalse(try admits(a, inbound, "filter", "first"))
    XCTAssertTrue(try admits(a, inbound, "filter", "shared"), "another requester still wants it")
    XCTAssertFalse(a.unwantsDestinationType("filter.first", requester: one), "not registered")
  }

  /// `if not packet.hops < Transport.HOP_LIMITER: return`, before the hop increment
  /// (`Transport.py:2022`).
  func testTheHopLimiterDropsAtTheLimit() throws {
    let (a, inbound) = receiver()
    a.hopLimiter = 2

    XCTAssertTrue(try admits(a, inbound, "hops", "one", hops: 1))
    XCTAssertFalse(try admits(a, inbound, "hops", "two", hops: 2))
  }

  final class Handler: AnnounceHandler {
    let aspectFilter: String? = "handler.paused"
    var paused = false
    var heard = 0
    func receivedAnnounce(
      destinationHash: Data, identity: Identity, appData: Data?,
      announcePacketHash: Data, isPathResponse: Bool
    ) { heard += 1 }
  }

  /// `if handler.paused: continue` (`Transport.py:2769`).
  func testAPausedHandlerHearsNothing() throws {
    let (a, inbound) = receiver()
    let handler = Handler()
    a.register(announceHandler: handler)

    handler.paused = true
    XCTAssertTrue(try admits(a, inbound, "handler", "paused"))
    handler.paused = false
    XCTAssertTrue(try admits(a, inbound, "handler", "paused"))

    let heard = expectation(description: "heard")
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { heard.fulfill() }
    wait(for: [heard], timeout: 2)
    XCTAssertEqual(handler.heard, 1)
  }

  // MARK: - Config

  /// The `[filter]` section, with `hop_limiter` clamped to `0…PATHFINDER_M`
  /// (`Reticulum.py:487-503`).
  func testTheFilterSectionConfiguresTransport() throws {
    let cfg = ReticulumConfig.parse(
      """
      [filter]
        required_only = yes
        ignored_types = filter.one, filter.two
        allowed_types = filter.three
        hop_limiter = 500
      """)
    XCTAssertTrue(cfg.filter.requiredOnly)
    XCTAssertEqual(cfg.filter.ignoredTypes, ["filter.one", "filter.two"])
    XCTAssertEqual(cfg.filter.allowedTypes, ["filter.three"])
    XCTAssertEqual(cfg.filter.hopLimiter, 500)
    XCTAssertEqual(cfg.unrecognisedKeys, [])

    let (a, inbound) = receiver()
    cfg.filter.apply(to: a)
    XCTAssertTrue(a.requiredDestinationsOnly)
    XCTAssertEqual(a.hopLimiter, Transport.pathfinderM)
    XCTAssertFalse(try admits(a, inbound, "filter", "two"))
    XCTAssertTrue(try admits(a, inbound, "filter", "three"))
  }

  // MARK: - RPC

  /// A 1.6.0 client registers its types with the shared instance over RPC
  /// (`Reticulum.py:1514-1529`).
  func testTheSharedInstanceAnswersTypeRegistrationCalls() throws {
    let t = Transport()
    let server = RPCServer(port: 37429, authkey: Data(repeating: 0, count: 32))
    server.transport = t
    t.requiredDestinationsOnly = true
    let requester = Data(repeating: 9, count: 16)
    func call(_ key: String, _ value: MsgPack.Value) throws -> MsgPack.Value {
      try MsgPack.decode(
        server.respond(
          to: MsgPack.encode(
            .map([
              (.string(key), value), (.string("requester"), .bytes(requester)),
              (.string("signature"), .nil),
            ]))))
    }

    XCTAssertEqual(try call("wants_destination_type", .string("filter.rpc")), .bool(true))
    XCTAssertTrue(t.wantsDestinationType("filter.rpc", requester: requester))
    XCTAssertEqual(try call("unwants_destination_type", .string("filter.rpc")), .bool(true))
    XCTAssertEqual(try call("unwants_destination_type", .string("filter.rpc")), .bool(false))
    XCTAssertEqual(try call("unwants_all_destination_types", .bool(true)), .bool(true))
  }

  /// The exit handler drops this application's wants (`Reticulum.py:189`).
  func testStoppingUnwantsTheApplicationsTypes() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns-filter-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let stack = Reticulum(configuration: .init(storagePath: dir, shareInstance: false))
    stack.transport.requiredDestinationsOnly = true
    XCTAssertTrue(stack.wantsDestinationType("filter.app"))
    XCTAssertFalse(stack.requiredAnnouncesOnly(true), "only a shared-instance client may")

    stack.stop()

    XCTAssertFalse(
      stack.unwantsDestinationType("filter.app"), "stop() already dropped the want")
  }
}
