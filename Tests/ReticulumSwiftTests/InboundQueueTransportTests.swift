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

/// Tests for the inbound split: `preprocess_inbound` on the receiving thread, then a traffic
/// class queue, then `_inbound` on one drain worker (`Transport.py:1751-1912`).
///
/// Each queued test holds the worker inside a delivery callback, so later packets stay
/// queued where the test can read their class.
final class InboundQueueTransportTests: XCTestCase {

  // MARK: - Fixtures

  private final class QueueInterface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var mode: InterfaceMode = .full
    var ingressControl: Bool = true
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
    func deliver(_ packet: Packet) { inboundHandler?(packet, self) }
  }

  /// Records delivery and announce events from any thread.
  private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ item: String) {
      lock.lock()
      items.append(item)
      lock.unlock()
    }
    var all: [String] {
      lock.lock()
      defer { lock.unlock() }
      return items
    }
  }

  private var savedLengths: [Int?] = []

  override func setUp() {
    super.setUp()
    savedLengths = [
      Reticulum.storedInboundDataQueueLength, Reticulum.storedInboundAnnounceQueueLength,
      Reticulum.storedInboundPrQueueLength, Reticulum.storedInboundIlQueueLength,
    ]
  }

  override func tearDown() {
    Reticulum.storedInboundDataQueueLength = savedLengths[0]
    Reticulum.storedInboundAnnounceQueueLength = savedLengths[1]
    Reticulum.storedInboundPrQueueLength = savedLengths[2]
    Reticulum.storedInboundIlQueueLength = savedLengths[3]
    super.tearDown()
  }

  private func plainDestination(_ aspect: String) throws -> Destination {
    try Destination(
      identity: nil, direction: .in, kind: .plain, appName: "queuetest", aspects: [aspect])
  }

  private func plainPacket(to destination: Destination, _ body: String = "x") -> Packet {
    Packet(
      destinationType: .plain, packetType: .data, destinationHash: destination.hash,
      data: Data(body.utf8))
  }

  private func remoteAnnounce(_ aspect: String) throws -> Packet {
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "queuetest",
      aspects: [aspect])
    return try Announce.make(for: destination)
  }

  private func pathRequest(for target: Data, tag: Data) -> Packet {
    Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Transport.pathRequestDestinationHash, data: target + tag)
  }

  /// A started transport whose drain worker waits inside a delivery callback.
  ///
  /// `release()` lets the worker continue. `events` records every later delivery as
  /// `data:<aspect>` and every accepted announce as `announce`.
  private struct HeldTransport {
    let transport: Transport
    let interface: QueueInterface
    let events: Events
    let release: () -> Void
  }

  private func heldTransport(file: StaticString = #filePath, line: UInt = #line) throws
    -> HeldTransport
  {
    let transport = Transport()
    let interface = QueueInterface(name: "queued")
    transport.register(interface: interface)
    let blocker = try plainDestination("blocker")
    transport.register(destination: blocker)
    let events = Events()
    let entered = DispatchSemaphore(value: 0)
    let gate = DispatchSemaphore(value: 0)
    transport.onPacketDelivered = { packet, destination, _ in
      if destination.hash == blocker.hash {
        entered.signal()
        gate.wait()
        return
      }
      events.append("data:\(destination.aspects.joined(separator: "."))")
    }
    transport.onAnnounceReceived = { _, _ in events.append("announce") }
    try transport.start()
    var released = false
    addTeardownBlock {
      if !released { gate.signal() }
      transport.stop()
    }

    interface.deliver(plainPacket(to: blocker))
    XCTAssertEqual(
      entered.wait(timeout: .now() + 5), .success, "the worker never reached the blocker",
      file: file, line: line)
    return HeldTransport(
      transport: transport, interface: interface, events: events,
      release: {
        released = true
        gate.signal()
      })
  }

  private func waitForEvents(
    _ events: Events, count: Int, file: StaticString = #filePath, line: UInt = #line
  ) {
    let deadline = Date().addingTimeInterval(5)
    while events.all.count < count, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    XCTAssertEqual(events.all.count, count, "events: \(events.all)", file: file, line: line)
  }

  /// Fills the incoming path-request deque inside the last half second of wall time, so the
  /// path-request limiter reads a burst.
  private func floodPathRequests(_ transport: Transport, on interface: any Interface) {
    let start = Date().timeIntervalSince1970 - 0.5
    for n in 0..<InterfaceFreqTracker.maxSamples {
      transport.notifyIncomingPathRequest(on: interface, at: start + Double(n) * 0.01)
    }
  }

  // MARK: - Lifecycle

  /// `USE_INBOUND_QUEUE = True` is the default for every transport (`Transport.py:141`).
  func testATransportUsesTheInboundQueueByDefault() {
    XCTAssertTrue(Transport().usesInboundQueue)
  }

  /// No worker runs before `start()`, so inbound runs to completion on the caller's thread.
  func testAnUnstartedTransportProcessesInline() throws {
    let transport = Transport()
    let interface = QueueInterface(name: "inline")
    transport.register(interface: interface)
    let destination = try plainDestination("inline")
    transport.register(destination: destination)
    var deliveredOnCaller = false
    let caller = Thread.current
    transport.onPacketDelivered = { _, _, _ in deliveredOnCaller = Thread.current == caller }

    interface.deliver(plainPacket(to: destination))

    XCTAssertTrue(deliveredOnCaller)
    XCTAssertNil(transport.inboundQueueSnapshot())
  }

  /// A started transport hands inbound to its drain worker.
  func testAStartedTransportProcessesOnTheDrainWorker() throws {
    let transport = Transport()
    let interface = QueueInterface(name: "worker")
    transport.register(interface: interface)
    let destination = try plainDestination("worker")
    transport.register(destination: destination)
    let delivered = expectation(description: "delivered")
    let caller = Thread.current
    transport.onPacketDelivered = { _, _, _ in
      XCTAssertNotEqual(Thread.current, caller)
      XCTAssertEqual(Thread.current.name, Transport.inboundWorkerName)
      delivered.fulfill()
    }
    try transport.start()
    defer { transport.stop() }

    interface.deliver(plainPacket(to: destination))

    wait(for: [delivered], timeout: 5)
    XCTAssertNotNil(transport.inboundQueueSnapshot())
  }

  /// `USE_INBOUND_QUEUE = False` keeps a started transport inline (`Transport.py:1891`).
  func testDisablingTheQueueKeepsAStartedTransportInline() throws {
    let transport = Transport()
    transport.usesInboundQueue = false
    let interface = QueueInterface(name: "disabled")
    transport.register(interface: interface)
    let destination = try plainDestination("disabled")
    transport.register(destination: destination)
    var deliveredOnCaller = false
    let caller = Thread.current
    transport.onPacketDelivered = { _, _, _ in deliveredOnCaller = Thread.current == caller }
    try transport.start()
    defer { transport.stop() }

    interface.deliver(plainPacket(to: destination))

    XCTAssertTrue(deliveredOnCaller)
    XCTAssertNil(transport.inboundQueueSnapshot())
  }

  /// `stop()` ends the worker; inbound after that runs inline.
  func testStopEndsTheWorker() throws {
    let transport = Transport()
    let interface = QueueInterface(name: "stopped")
    transport.register(interface: interface)
    let destination = try plainDestination("stopped")
    transport.register(destination: destination)
    try transport.start()
    transport.stop()
    var deliveredOnCaller = false
    let caller = Thread.current
    transport.onPacketDelivered = { _, _, _ in deliveredOnCaller = Thread.current == caller }

    interface.deliver(plainPacket(to: destination))

    XCTAssertTrue(deliveredOnCaller)
    XCTAssertNil(transport.inboundQueueSnapshot())
  }

  /// A transport started again after `stop()` gets a fresh worker.
  func testARestartedTransportQueuesAgain() throws {
    let transport = Transport()
    let interface = QueueInterface(name: "restarted")
    transport.register(interface: interface)
    let destination = try plainDestination("restarted")
    transport.register(destination: destination)
    try transport.start()
    transport.stop()
    try transport.start()
    defer { transport.stop() }
    let delivered = expectation(description: "delivered")
    transport.onPacketDelivered = { _, _, _ in
      XCTAssertEqual(Thread.current.name, Transport.inboundWorkerName)
      delivered.fulfill()
    }

    interface.deliver(plainPacket(to: destination))

    wait(for: [delivered], timeout: 5)
  }

  /// The worker holds the transport weakly, so a transport started and never stopped still
  /// deallocates.
  func testAStartedTransportStillDeallocates() throws {
    weak var weakTransport: Transport?
    try autoreleasepool {
      let transport = Transport()
      try transport.start()
      weakTransport = transport
    }
    let deadline = Date().addingTimeInterval(5)
    while weakTransport != nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    XCTAssertNil(weakTransport)
  }

  /// The queue capacities come from `qlen_in_*`, read when the transport starts
  /// (`Transport.py:310-317`).
  func testTheQueueCapacitiesComeFromTheConfiguredLengths() throws {
    Reticulum.storedInboundDataQueueLength = 3
    Reticulum.storedInboundAnnounceQueueLength = 4
    Reticulum.storedInboundPrQueueLength = 5
    Reticulum.storedInboundIlQueueLength = 6
    let transport = Transport()
    try transport.start()
    defer { transport.stop() }
    XCTAssertEqual(transport.inboundQueueLengths, [3, 4, 5, 6])
  }

  // MARK: - Classification

  /// An announce queues as `TC_ANNOUNCE` (`Transport.py:1805`).
  func testAnAnnounceQueuesInTheAnnounceClass() throws {
    let held = try heldTransport()
    held.interface.deliver(try remoteAnnounce("an"))
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [0, 1, 0, 0])
  }

  /// A path request queues as `TC_PATH_REQUEST` (`Transport.py:1829`).
  func testAPathRequestQueuesInThePathRequestClass() throws {
    let held = try heldTransport()
    held.interface.deliver(pathRequest(for: Data(repeating: 0x11, count: 16), tag: Data([1])))
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [0, 0, 1, 0])
  }

  /// A path request on an interface whose path-request limiter is active queues as
  /// `TC_INGRESS_LIMITED` (`Transport.py:1859-1860`).
  func testAPathRequestFromALimitedInterfaceQueuesAsIngressLimited() throws {
    let held = try heldTransport()
    floodPathRequests(held.transport, on: held.interface)
    held.interface.deliver(pathRequest(for: Data(repeating: 0x22, count: 16), tag: Data([2])))
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [0, 0, 0, 1])
  }

  /// A released held announce re-enters as `TC_INGRESS_LIMITED`, and the announce class
  /// never lowers it (`Interface.py:296`, `Transport.py:1805`).
  func testAReleasedHeldAnnounceQueuesAsIngressLimited() throws {
    let held = try heldTransport()
    let announce = try remoteAnnounce("held")
    held.transport.holdAnnounce(
      announce, destinationHash: announce.destinationHash, on: held.interface)
    XCTAssertNotNil(
      held.transport.processHeldAnnounces(
        for: held.interface, now: Date().timeIntervalSince1970 + 3600))
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [0, 0, 0, 1])
  }

  /// Only a data packet for the path-request destination passes path-request admission.
  ///
  /// Python admits any packet other than an announce for that hash (`Transport.py:1827`).
  /// This port declines, so a proof addressed there neither queues as a path request nor
  /// spends the tag a genuine request carries.
  func testOnlyADataPacketPassesPathRequestAdmission() throws {
    let held = try heldTransport()
    let target = Data(repeating: 0x44, count: 16)
    let tag = Data([4])
    held.interface.deliver(
      Packet(
        destinationType: .plain, packetType: .proof,
        destinationHash: Transport.pathRequestDestinationHash, data: target + tag))
    held.interface.deliver(pathRequest(for: target, tag: tag))
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [1, 0, 1, 0])
  }

  /// Any other packet queues as `TC_DATA` (`Transport.py:1796`).
  func testOtherTrafficQueuesInTheDataClass() throws {
    let held = try heldTransport()
    held.interface.deliver(plainPacket(to: try plainDestination("data")))
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [1, 0, 0, 0])
  }

  // MARK: - Preprocessing stays on the receiving thread

  /// An announce with a bad signature is a protocol violation before it can queue
  /// (`Transport.py:1808-1809`).
  func testABadAnnounceSignatureIsCountedWithoutQueueing() throws {
    let held = try heldTransport()
    var announce = try remoteAnnounce("bad")
    let last = announce.data.index(before: announce.data.endIndex)
    announce.data[last] ^= 0xFF

    held.interface.deliver(announce)

    XCTAssertEqual(held.transport.interfaceCounts(for: held.interface).protocolViolations, 1)
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.total, 0)
  }

  /// A path request with a tag already seen drops before it can queue (`Transport.py:1849-1855`).
  func testADuplicatePathRequestTagNeverQueues() throws {
    let held = try heldTransport()
    let target = Data(repeating: 0x33, count: 16)
    held.interface.deliver(pathRequest(for: target, tag: Data([3])))
    held.interface.deliver(pathRequest(for: target, tag: Data([3])))
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [0, 0, 1, 0])
  }

  /// The ingress limiter holds an unknown announce that arrives during an announce burst,
  /// and it never queues (`Transport.py:1823-1825`).
  func testAnAnnounceHeldByTheIngressLimiterNeverQueues() throws {
    let held = try heldTransport()
    let start = Date().timeIntervalSince1970 - 0.5
    for n in 0..<InterfaceFreqTracker.maxSamples {
      held.transport.notifyIncomingAnnounce(on: held.interface, at: start + Double(n) * 0.01)
    }

    held.interface.deliver(try remoteAnnounce("burst"))

    XCTAssertEqual(held.transport.heldAnnounceCount(for: held.interface), 1)
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.total, 0)
  }

  /// An announce for one of this node's own destinations never starts a burst and is never
  /// held.
  ///
  /// A deliberate difference: Python checks only the path table (`Transport.py:1812`), so the
  /// echo of a node's own announce can start a burst and take a release interval, although
  /// `_inbound` then ignores it (`Transport.py:2175-2176`).
  func testAnAnnounceForALocalDestinationIsNeverHeld() throws {
    let held = try heldTransport()
    let local = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "queuetest",
      aspects: ["local"])
    held.transport.register(destination: local)
    let start = Date().timeIntervalSince1970 - 0.5
    for n in 0..<InterfaceFreqTracker.maxSamples {
      held.transport.notifyIncomingAnnounce(on: held.interface, at: start + Double(n) * 0.01)
    }

    held.interface.deliver(try Announce.make(for: local))

    XCTAssertEqual(held.transport.heldAnnounceCount(for: held.interface), 0)
    XCTAssertFalse(held.transport.ingressState(for: held.interface)?.burstActive ?? true)
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [0, 1, 0, 0])
  }

  // MARK: - Draining

  /// Data that queued behind an announce still drains first (`Transport.py:69-73`).
  func testDataDrainsBeforeAnAnnounceThatQueuedFirst() throws {
    let held = try heldTransport()
    let data = try plainDestination("late")
    held.transport.register(destination: data)

    held.interface.deliver(try remoteAnnounce("early"))
    held.interface.deliver(plainPacket(to: data))
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [1, 1, 0, 0])
    held.release()

    waitForEvents(held.events, count: 2)
    XCTAssertEqual(held.events.all, ["data:late", "announce"])
  }

  /// A full class drops the packet and counts it (`Transport.py:1894-1895`).
  func testAFullClassDropsAndCounts() throws {
    Reticulum.storedInboundAnnounceQueueLength = 1
    let held = try heldTransport()
    // Three announces in a few milliseconds would otherwise trip the announce burst limiter.
    held.interface.ingressControl = false
    for n in 0..<3 { held.interface.deliver(try remoteAnnounce("full\(n)")) }

    let snapshot = try XCTUnwrap(held.transport.inboundQueueSnapshot())
    XCTAssertEqual(snapshot.heights, [0, 1, 0, 0])
    XCTAssertEqual(snapshot.dropped, [0, 2, 0, 0])
  }

  /// The worker drops a packet whose interface went offline while it waited
  /// (`Transport.py:1916`).
  func testAQueuedPacketFromAnInterfaceThatWentOfflineIsDropped() throws {
    let held = try heldTransport()
    let other = QueueInterface(name: "other")
    held.transport.register(interface: other)
    let first = try plainDestination("first")
    let second = try plainDestination("second")
    held.transport.register(destination: first)
    held.transport.register(destination: second)

    other.deliver(plainPacket(to: first))
    other.isOnline = false
    held.interface.deliver(plainPacket(to: second))
    held.release()

    waitForEvents(held.events, count: 1)
    XCTAssertEqual(held.events.all, ["data:second"])
  }

  /// A packet that queued behind an identical copy drops when its turn comes, so the
  /// stack handles it once.
  func testADuplicateThatQueuedBehindItsFirstCopyIsDroppedAtTheWorker() throws {
    let held = try heldTransport()
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "queuetest",
      aspects: ["dup"])
    held.transport.register(destination: destination)
    let packet = try Packet(
      destinationType: .single, packetType: .data, destinationHash: destination.hash,
      data: destination.encrypt(Data("once".utf8)))

    held.interface.deliver(packet)
    held.interface.deliver(packet)
    XCTAssertEqual(held.transport.inboundQueueSnapshot()?.heights, [2, 0, 0, 0])
    held.release()

    waitForEvents(held.events, count: 1)
    Thread.sleep(forTimeInterval: 0.2)
    XCTAssertEqual(held.events.all, ["data:dup"])
  }

  // MARK: - Statistics

  /// `rnstatus -q` reads the running queues' heights, drop counts and pressures, each
  /// pressure dividing a height by its class's configured capacity (`Reticulum.py:1667-1702`).
  func testInterfaceStatsReportTheRunningQueues() throws {
    Reticulum.storedInboundDataQueueLength = 4
    Reticulum.storedInboundAnnounceQueueLength = 2
    Reticulum.storedInboundPrQueueLength = 5
    Reticulum.storedInboundIlQueueLength = 2
    let held = try heldTransport()
    // Three announces in a few milliseconds would otherwise trip the announce burst limiter.
    held.interface.ingressControl = false
    let destination = try plainDestination("stats")
    for n in 0..<3 { held.interface.deliver(plainPacket(to: destination, "d\(n)")) }
    for n in 0..<3 { held.interface.deliver(try remoteAnnounce("stats\(n)")) }
    held.interface.deliver(pathRequest(for: Data(repeating: 0x33, count: 16), tag: Data([3])))

    let stats = try XCTUnwrap(InterfaceStatsPayload.build(held.transport).asDictionary)

    let depths: [String: Int] = [
      "rxqt": 6, "rxqd": 3, "rxqa": 2, "rxqp": 1, "rxqil": 0,
      "rxqtd": 1, "rxqdd": 0, "rxqad": 1, "rxqpd": 0, "rxqild": 0,
    ]
    for (key, expected) in depths { XCTAssertEqual(stats[key]?.asInt, expected, key) }
    let pressures: [String: Double] = [
      "tqpressure": 6.0 / 13.0, "dqpressure": 3.0 / 4.0, "aqpressure": 1.0,
      "pqpressure": 1.0 / 5.0, "ilqpressure": 0,
    ]
    for (key, expected) in pressures {
      XCTAssertEqual(try XCTUnwrap(stats[key]?.asDouble, key), expected, accuracy: 1e-12, key)
    }
  }
}
