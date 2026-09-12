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

/// A transport node that answers a path request for an *unknown* destination does so by
/// re-broadcasting the request on every other interface. Python gates that fan-out on the
/// receiving interface's path-request burst state:
///
///     should_ingress_limit = ingress_limited or attached_interface.should_ingress_limit_pr()
///     ...
///     # Abort recursive path request if receiving interface has PR burst active
///     if should_ingress_limit: ... return                    (`Transport.py:3427`, `:3546`)
///
/// This port implemented `shouldIngressLimitPR` in full, tested it, and then never called it:
/// the only ingress-limit call site was the announce one. So a peer could emit path requests
/// for unknown destinations as fast as it liked and every one of them was amplified onto all
/// other interfaces. The gate predates 1.5.x—1.5.1 only added `ingress_limited` as a second
/// way to arm it—but it lands here because the burst state machine it consumes is what this
/// pass rebuilt.
final class PathRequestIngressLimitTests: XCTestCase {

  // MARK: - Fixtures

  private final class PRInterface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var sent: [Packet] = []
    var mode: InterfaceMode = .full
    var recursivePrs: Bool = false
    var ingressControl: Bool = true
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  /// `target || requestor transport id || tag`—the three-field body shape
  /// `path_request_handler` parses (`Transport.py:3391-3402`).
  private func request(for target: Data, on t: Transport, tag: Data) -> Packet {
    Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Transport.pathRequestDestinationHash,
      data: target + t.transportInstanceID + tag)
  }

  private func forwardedRequests(_ iface: PRInterface) -> [Packet] {
    iface.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
  }

  /// Fill the incoming path-request deque with a full deque's worth of samples inside the
  /// last half-second of *real* time, so that the limiter—which reads the wall clock—observes
  /// a burst well above threshold.
  private func floodPathRequests(_ t: Transport, on iface: any Interface) {
    let start = Date().timeIntervalSince1970 - 0.5
    for i in 0..<InterfaceFreqTracker.maxSamples {
      t.notifyIncomingPathRequest(on: iface, at: start + Double(i) * 0.01)
    }
  }

  private func makePair() -> (Transport, PRInterface, PRInterface) {
    let t = Transport()
    t.transportEnabled = true
    let ingress = PRInterface(name: "ingress")
    ingress.recursivePrs = true
    let egress = PRInterface(name: "egress")
    t.register(interface: ingress)
    t.register(interface: egress)
    return (t, ingress, egress)
  }

  // MARK: - The gate

  func testAQuietInterfaceStillGetsItsRecursiveFanOut() {
    let (t, ingress, egress) = makePair()
    ingress.inboundHandler?(
      request(
        for: Data(repeating: 0x77, count: 16), on: t,
        tag: Data(repeating: 0x01, count: 16)), ingress)

    XCTAssertEqual(
      forwardedRequests(egress).count, 1,
      "the gate must not suppress ordinary discovery — without this control the "
        + "suppression test below would pass for the wrong reason")
  }

  func testAPathRequestBurstSuppressesTheRecursiveFanOut() {
    let (t, ingress, egress) = makePair()
    floodPathRequests(t, on: ingress)
    XCTAssertTrue(t.shouldIngressLimitPR(on: ingress), "the fixture must actually arm the limiter")

    ingress.inboundHandler?(
      request(
        for: Data(repeating: 0x77, count: 16), on: t,
        tag: Data(repeating: 0x01, count: 16)), ingress)

    XCTAssertTrue(
      forwardedRequests(egress).isEmpty,
      """
      `if should_ingress_limit: ... return` (Transport.py:3546) — a peer \
      flooding requests for unknown destinations must not have each one \
      amplified onto every other interface
      """)
  }

  func testTheGateOnlySuppressesDiscoveryNotAKnownAnswer() throws {
    // Python evaluates `should_ingress_limit` at the top of `path_request` but consumes it
    // only inside the `should_search_for_unknown` branch. A node that can answer from its
    // own path table still answers while limited—the limit is on amplification, not on
    // being useful.
    let (t, ingress, egress) = makePair()
    let identity = Identity()
    let dest = try Destination(
      identity: identity, direction: .in, kind: .single,
      appName: "test", aspects: ["known"])
    let announce = try Announce.make(for: dest)
    egress.inboundHandler?(announce, egress)
    XCTAssertTrue(t.hasPath(to: dest.hash), "the announce must have installed a path")

    floodPathRequests(t, on: ingress)
    ingress.sent.removeAll()
    ingress.inboundHandler?(
      request(
        for: dest.hash, on: t,
        tag: Data(repeating: 0x02, count: 16)), ingress)

    XCTAssertFalse(
      ingress.sent.isEmpty,
      "a known path must still be answered back to the requestor while the "
        + "interface is ingress-limited")
  }

  func testDisablingIngressControlDisarmsTheGate() {
    let (t, ingress, egress) = makePair()
    ingress.ingressControl = false
    floodPathRequests(t, on: ingress)

    ingress.inboundHandler?(
      request(
        for: Data(repeating: 0x77, count: 16), on: t,
        tag: Data(repeating: 0x01, count: 16)), ingress)

    XCTAssertEqual(
      forwardedRequests(egress).count, 1,
      "`if self.ingress_control:` (Interface.py:210) — an operator who turns "
        + "ingress control off must get no limiting at all")
  }

  // MARK: - Tag truncation (`Transport.py:1843`)

  /// Both truncation tests answer from a destination local to this node, and count the
  /// answers rather than the recursive fan-out.
  ///
  /// The fan-out is no longer a clean read on tag identity: `inflight_path_requests`
  /// (`Transport.py:1862-1886`) collapses a second request for a destination already being
  /// searched for, whatever its tag. Counting fan-outs would therefore let the duplicate case
  /// pass with the tag dedup deleted outright, and would fail the distinct case for a reason
  /// that has nothing to do with tags. An answered request releases the in-flight marker on
  /// the way out (`:3595-3599`), so this observable isolates the tag.
  private func answerableRequest(on t: Transport) throws -> Destination {
    let local = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "test", aspects: ["truncation"])
    t.register(destination: local)
    return local
  }

  private func pathResponses(_ iface: PRInterface) -> [Packet] {
    iface.sent.filter { $0.packetType == .announce && $0.context == .pathResponse }
  }

  func testTagsDifferingOnlyPastTheSixteenthByteAreOneRequest() throws {
    // `if len(tag_bytes) > TRUNCATED_HASHLENGTH//8: tag_bytes = tag_bytes[:...]`—the
    // dedup key is built from the truncated tag. Keying on the untruncated bytes lets a
    // sender defeat deduplication for free by varying a tail Python never reads, turning
    // one path request into as many answers as it cares to ask for.
    let (t, ingress, _) = makePair()
    let local = try answerableRequest(on: t)
    let head = Data(repeating: 0x01, count: 16)

    ingress.inboundHandler?(
      request(for: local.hash, on: t, tag: head + Data([0xAA, 0xBB, 0xCC, 0xDD])), ingress)
    XCTAssertEqual(pathResponses(ingress).count, 1, "the first request is answered")

    ingress.inboundHandler?(
      request(for: local.hash, on: t, tag: head + Data([0x11, 0x22, 0x33, 0x44])), ingress)
    XCTAssertEqual(
      pathResponses(ingress).count, 1,
      "the second request carries the same 16-byte tag and must be a duplicate")
  }

  func testTagsDifferingWithinTheSixteenthByteRemainDistinct() throws {
    let (t, ingress, _) = makePair()
    let local = try answerableRequest(on: t)

    var second = Data(repeating: 0x01, count: 16)
    second[15] = 0x02

    ingress.inboundHandler?(
      request(for: local.hash, on: t, tag: Data(repeating: 0x01, count: 16)), ingress)
    ingress.inboundHandler?(request(for: local.hash, on: t, tag: second), ingress)

    XCTAssertEqual(
      pathResponses(ingress).count, 2,
      "truncation must not collapse tags that genuinely differ inside the "
        + "16 bytes the protocol reads")
  }
}
