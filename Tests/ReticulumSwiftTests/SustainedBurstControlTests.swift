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

/// RNS 1.5.1 reworked ingress/egress burst control (`Interface.py:191-247`).
///
/// The 1.4.2 shape had one timer per burst: `ic_burst_activated`. A flood that ran for
/// minutes therefore cleared its own burst flag fifteen seconds after it *started*, while it
/// was still running—the hold window measured the wrong end of the event. 1.5.1 adds a
/// second timestamp, `ic_burst_sustained`, refreshed on every above-threshold evaluation, and
/// requires *both* windows to have elapsed. The burst now expires fifteen seconds after the
/// flood stops.
///
/// Path-request bursts get the same treatment plus a cooldown counter, and egress limiting
/// changed its sample floor from six to two—the constant was renamed in the process
/// (`IC_BURST_MIN_SAMPLES` → `EC_BURST_MIN_SAMPLES`), which is upstream conceding that it was
/// only ever an egress knob.
final class SustainedBurstControlTests: XCTestCase {

  private static let mature = IngressControlState.icNewTime + 1

  /// Interface age is `now - createdAt`, and `createdAt` is a real epoch date, so the `now`
  /// these tests hand the limiter has to be a real epoch value too.
  ///
  /// A synthetic base like
  /// `1000` makes the age hugely negative, which reads as *new* and quietly swaps in the
  /// lower `IC_BURST_FREQ_NEW`/`IC_PR_BURST_FREQ_NEW` thresholds—the opposite of what a
  /// test naming a mature interface means to exercise.
  private static func base() -> TimeInterval { Date().timeIntervalSince1970 }

  /// A deque holds at most `InterfaceFreqTracker.maxSamples` timestamps, so appending a full
  /// deque's worth evicts every older one.
  ///
  /// That's the only way to move `oldest` forward in
  /// one step, and these tests need it: frequency is `n / (now - oldest)`, so without a full
  /// roll a stale first sample pins the span open and no later burst can be expressed.
  private func rollDeque(_ record: (TimeInterval) -> Void, from start: TimeInterval) {
    for i in 0..<InterfaceFreqTracker.maxSamples { record(start + Double(i) * 0.01) }
  }

  // MARK: - Announce bursts: the hold window now runs from the last flood sample

  func testASustainedFloodKeepsTheBurstActivePastTheActivationHold() {
    let t = Transport()
    let t0 = Self.base()
    let iface = TestInterface(
      name: "sustained",
      createdAt: Date(timeIntervalSince1970: t0 - Self.mature))
    t.register(interface: iface)

    // 48 announces in half a second—96 Hz against a 10 Hz threshold.
    rollDeque({ t.notifyIncomingAnnounce(on: iface, at: $0) }, from: t0)
    XCTAssertTrue(t.shouldIngressLimit(on: iface, now: t0 + 0.5), "the flood must activate a burst")

    // The flood is still running at t0+14.5, one second inside the activation hold. This
    // evaluation is what refreshes `ic_burst_sustained` (`Interface.py:196`).
    rollDeque({ t.notifyIncomingAnnounce(on: iface, at: $0) }, from: t0 + 14)
    XCTAssertTrue(t.shouldIngressLimit(on: iface, now: t0 + 14.5))

    // t0+25 is past `activated + IC_BURST_HOLD` (t0+15.5) but not past
    // `sustained + IC_BURST_HOLD` (t0+29.5), and the frequency has fallen to ~4 Hz. Before
    // 1.5.1 this is exactly where the flag cleared—mid-flood, on the strength of a timer
    // started before the flood had gotten going.
    XCTAssertTrue(t.shouldIngressLimit(on: iface, now: t0 + 25))
    XCTAssertTrue(
      t.ingressState(for: iface)?.burstActive ?? false,
      """
      the burst must still be active: `time.time() > self.ic_burst_sustained + \
      self.ic_burst_hold` (Interface.py:194) has not been met, and the hold \
      window measures time since the flood was last seen, not since it began
      """)

    // Fifteen seconds after that last above-threshold evaluation, it finally clears.
    XCTAssertTrue(
      t.shouldIngressLimit(on: iface, now: t0 + 31),
      "the clearing call is itself still limited — Python's `return True` sits "
        + "outside the deactivation branch")
    XCTAssertFalse(
      t.ingressState(for: iface)?.burstActive ?? true,
      "both hold windows have now elapsed, so the flag clears")
  }

  func testActivatingABurstSeedsTheSustainedTimestamp() {
    let t = Transport()
    let t0 = Self.base()
    let iface = TestInterface(
      name: "seed",
      createdAt: Date(timeIntervalSince1970: t0 - Self.mature))
    t.register(interface: iface)

    rollDeque({ t.notifyIncomingAnnounce(on: iface, at: $0) }, from: t0)
    XCTAssertTrue(t.shouldIngressLimit(on: iface, now: t0 + 0.5))

    XCTAssertEqual(
      t.ingressState(for: iface)?.burstSustained ?? 0, t0 + 0.5, accuracy: 0.001,
      """
      `self.ic_burst_sustained = time.time()` at activation \
      (Interface.py:205). Leaving it at 0 would make `now > sustained + hold` \
      trivially true forever, and the second window would never gate anything
      """)
  }

  // MARK: - Path-request bursts: three qualifying calls before the flag may clear

  func testAPathRequestBurstNeedsFourQuietCallsToClear() {
    let t = Transport()
    let t0 = Self.base()
    let iface = TestInterface(
      name: "pr-cooldown",
      createdAt: Date(timeIntervalSince1970: t0 - Self.mature))
    t.register(interface: iface)

    rollDeque({ t.notifyIncomingPathRequest(on: iface, at: $0) }, from: t0)
    XCTAssertTrue(
      t.shouldIngressLimitPR(on: iface, now: t0 + 0.5), "the flood must activate a PR burst")

    // Every probe below is fully quiet—frequency ~1 Hz against an 8 Hz threshold, and
    // both hold windows long since elapsed. Each merely decrements the cooldown.
    for (probe, remaining) in [(t0 + 40, 2), (t0 + 41, 1), (t0 + 42, 0)] {
      XCTAssertTrue(t.shouldIngressLimitPR(on: iface, now: probe))
      XCTAssertTrue(
        t.ingressState(for: iface)?.prBurstActive ?? false,
        """
        `else: self.ic_pr_burst_cooldown -= 1` (Interface.py:221) — a \
        qualifying call spends cooldown instead of clearing the flag
        """)
      XCTAssertEqual(
        t.ingressState(for: iface)?.prBurstCooldown, remaining,
        "cooldown counts down one per qualifying call")
    }

    XCTAssertTrue(t.shouldIngressLimitPR(on: iface, now: t0 + 43))
    XCTAssertFalse(
      t.ingressState(for: iface)?.prBurstActive ?? true,
      "`if self.ic_pr_burst_cooldown <= 0: self.ic_pr_burst_active = False` "
        + "(Interface.py:220)")
  }

  func testAnyNonQualifyingCallRefillsThePathRequestCooldown() {
    let t = Transport()
    let t0 = Self.base()
    let iface = TestInterface(
      name: "pr-refill",
      createdAt: Date(timeIntervalSince1970: t0 - Self.mature))
    t.register(interface: iface)

    rollDeque({ t.notifyIncomingPathRequest(on: iface, at: $0) }, from: t0)
    XCTAssertTrue(t.shouldIngressLimitPR(on: iface, now: t0 + 0.5))

    _ = t.shouldIngressLimitPR(on: iface, now: t0 + 40)  // cooldown 3 -> 2
    _ = t.shouldIngressLimitPR(on: iface, now: t0 + 41)  // cooldown 2 -> 1

    // The flood resumes. `self.ic_pr_burst_cooldown = 3` (Interface.py:223) is in the
    // `else` branch, so it refills unconditionally—the counter measures *consecutive*
    // quiet evaluations, and one busy one resets the run.
    rollDeque({ t.notifyIncomingPathRequest(on: iface, at: $0) }, from: t0 + 50)
    XCTAssertTrue(t.shouldIngressLimitPR(on: iface, now: t0 + 50.5))
    XCTAssertEqual(
      t.ingressState(for: iface)?.prBurstCooldown, 3,
      "a busy evaluation refills the cooldown to its full run")

    for probe in [t0 + 70, t0 + 71, t0 + 72] {
      _ = t.shouldIngressLimitPR(on: iface, now: probe)
      XCTAssertTrue(
        t.ingressState(for: iface)?.prBurstActive ?? false,
        "the refilled cooldown has to be spent again before the flag can clear")
    }
    _ = t.shouldIngressLimitPR(on: iface, now: t0 + 73)
    XCTAssertFalse(t.ingressState(for: iface)?.prBurstActive ?? true)
  }

  // MARK: - Egress limiting

  func testEgressBurstMinSamplesIsTwo() {
    XCTAssertEqual(
      IngressControlState.ecBurstMinSamples, 2,
      "`EC_BURST_MIN_SAMPLES = 2` (Interface.py:85), down from 6 in 1.4.2")
  }

  func testTwoOutgoingSamplesAreEnoughToEgressLimit() {
    let t = Transport()
    let t0 = Self.base()
    let iface = TestInterface(
      name: "egress-floor",
      createdAt: Date(timeIntervalSince1970: t0 - Self.mature))
    iface.egressControl = true
    t.register(interface: iface)

    t.notifyOutgoingPathRequest(on: iface, at: t0)
    t.notifyOutgoingPathRequest(on: iface, at: t0 + 0.1)

    // 2 samples (3 with the preemptive one) over 0.2 s is 15 Hz against `EC_PR_FREQ = 5`.
    // Under the old floor of six samples this stream was unlimited no matter how fast it
    // ran, which is the whole point of the change: a burst of two is already a burst.
    XCTAssertTrue(
      t.shouldEgressLimitPR(on: iface, now: t0 + 0.2),
      "`if len(self.op_freq_deque) >= self.EC_BURST_MIN_SAMPLES: return True` "
        + "(Interface.py:246)")
  }

  func testTheRequestAboutToBeSentCountsTowardTheFrequency() {
    let t = Transport()
    let t0 = Self.base()
    let iface = TestInterface(
      name: "preemptive",
      createdAt: Date(timeIntervalSince1970: t0 - Self.mature))
    iface.egressControl = true
    t.register(interface: iface)

    // Six samples spanning 1.2 s: exactly 5.0 Hz, which is *not* greater than `EC_PR_FREQ`.
    // Counting the request this call is about to authorise gives 7/1.2 = 5.83 Hz, which is.
    for i in 0..<6 { t.notifyOutgoingPathRequest(on: iface, at: t0 + Double(i) * 0.2) }

    XCTAssertEqual(
      t.outgoingPathRequestFrequency(for: iface, preemptive: false, now: t0 + 1.2),
      5.0, accuracy: 0.0001,
      "without the preemptive sample the stream sits exactly on the threshold")

    XCTAssertTrue(
      t.shouldEgressLimitPR(on: iface, now: t0 + 1.2),
      """
      `op_freq = self.outgoing_pr_frequency(preemptive=True)` \
      (Interface.py:243) — the limiter asks what the frequency *will be*, so a \
      stream sitting on the threshold is stopped rather than allowed to cross it
      """)
  }

  func testThePreemptiveSampleDoesNotSatisfyTheMinimumCountItself() {
    // `if not len(self.op_freq_deque) > 1: return 0` (Interface.py:381) reads the real
    // length, not the incremented one. A single recorded request must still report zero—otherwise
    // the very first path request on an interface would limit itself.
    let t = Transport()
    let t0 = Self.base()
    let iface = TestInterface(
      name: "single",
      createdAt: Date(timeIntervalSince1970: t0 - Self.mature))
    iface.egressControl = true
    t.register(interface: iface)

    t.notifyOutgoingPathRequest(on: iface, at: t0)

    XCTAssertEqual(
      t.outgoingPathRequestFrequency(for: iface, preemptive: true, now: t0 + 0.01),
      0, accuracy: 0.0001,
      "one sample plus the preemptive one is still one recorded sample")
    XCTAssertFalse(
      t.shouldEgressLimitPR(on: iface, now: t0 + 0.01),
      "a first path request must not limit itself")
  }

  // MARK: - Helper

  private final class TestInterface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var createdAt: Date
    init(name: String, createdAt: Date) {
      self.name = name
      self.createdAt = createdAt
    }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }
}
