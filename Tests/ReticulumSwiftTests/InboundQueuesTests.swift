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

/// Tests for `InboundQueues`, the port of Python's `InboundQueues` (`Transport.py:47-95`).
final class InboundQueuesTests: XCTestCase {

  private func makeQueues(
    data: Int = 8, announce: Int = 8, pathRequest: Int = 8, ingressLimited: Int = 8
  ) -> InboundQueues<String> {
    InboundQueues(
      dataLength: data, announceLength: announce, pathRequestLength: pathRequest,
      ingressLimitedLength: ingressLimited)
  }

  // MARK: - Constants

  /// `TC_DATA = 0x00` through `TC_INGRESS_LIMITED = 0x03` (`Transport.py:111-114`).
  func testTrafficClassValuesMatchPython() {
    XCTAssertEqual(Transport.TrafficClass.data.rawValue, 0x00)
    XCTAssertEqual(Transport.TrafficClass.announce.rawValue, 0x01)
    XCTAssertEqual(Transport.TrafficClass.pathRequest.rawValue, 0x02)
    XCTAssertEqual(Transport.TrafficClass.ingressLimited.rawValue, 0x03)
  }

  /// `INBOUND_DA_QUEUE_LENGTH` through `INBOUND_IL_QUEUE_LENGTH` (`Transport.py:143-146`).
  func testDefaultQueueLengthsMatchPython() {
    XCTAssertEqual(Transport.inboundDaQueueLength, 1024)
    XCTAssertEqual(Transport.inboundAnQueueLength, 128)
    XCTAssertEqual(Transport.inboundPrQueueLength, 128)
    XCTAssertEqual(Transport.inboundIlQueueLength, 8)
  }

  /// `USE_INBOUND_QUEUE = True` (`Transport.py:141`).
  func testUseInboundQueueDefaultMatchesPython() {
    XCTAssertTrue(Transport.useInboundQueue)
  }

  // MARK: - Ordering

  /// `get` scans the queues in class order and returns the first item it finds
  /// (`Transport.py:69-77`), so a lower class always drains first.
  func testGetDrainsInStrictClassOrder() {
    let queues = makeQueues()
    XCTAssertTrue(queues.put("il", trafficClass: .ingressLimited))
    XCTAssertTrue(queues.put("pr", trafficClass: .pathRequest))
    XCTAssertTrue(queues.put("an", trafficClass: .announce))
    XCTAssertTrue(queues.put("da", trafficClass: .data))

    XCTAssertEqual(queues.get(block: false), "da")
    XCTAssertEqual(queues.get(block: false), "an")
    XCTAssertEqual(queues.get(block: false), "pr")
    XCTAssertEqual(queues.get(block: false), "il")
    XCTAssertNil(queues.get(block: false))
  }

  /// Data that arrives after a backlog of announces still drains first.
  func testDataPreemptsAnAnnounceBacklog() {
    let queues = makeQueues()
    for n in 0..<5 { XCTAssertTrue(queues.put("an\(n)", trafficClass: .announce)) }
    XCTAssertEqual(queues.get(block: false), "an0")
    XCTAssertTrue(queues.put("da", trafficClass: .data))
    XCTAssertEqual(queues.get(block: false), "da")
    XCTAssertEqual(queues.get(block: false), "an1")
  }

  /// Each class is a `deque` drained with `popleft` (`Transport.py:52`, `:73`).
  func testEachClassIsFirstInFirstOut() {
    let queues = makeQueues()
    for n in 0..<4 { XCTAssertTrue(queues.put("da\(n)", trafficClass: .data)) }
    for n in 0..<4 { XCTAssertEqual(queues.get(block: false), "da\(n)") }
  }

  // MARK: - Bounds and drops

  /// A full class refuses the item and counts a drop against that class only
  /// (`Transport.py:61-63`).
  func testFullClassRefusesAndCountsADrop() {
    let queues = makeQueues(announce: 2)
    XCTAssertTrue(queues.put("an0", trafficClass: .announce))
    XCTAssertTrue(queues.put("an1", trafficClass: .announce))
    XCTAssertFalse(queues.put("an2", trafficClass: .announce))
    XCTAssertFalse(queues.put("an3", trafficClass: .announce))

    let snapshot = queues.snapshot()
    XCTAssertEqual(snapshot.dropped, [0, 2, 0, 0])
    XCTAssertEqual(snapshot.heights, [0, 2, 0, 0])
  }

  /// One class at capacity leaves the others open.
  func testFullClassLeavesOtherClassesOpen() {
    let queues = makeQueues(ingressLimited: 1)
    XCTAssertTrue(queues.put("il0", trafficClass: .ingressLimited))
    XCTAssertFalse(queues.put("il1", trafficClass: .ingressLimited))
    XCTAssertTrue(queues.put("da", trafficClass: .data))
    XCTAssertTrue(queues.put("an", trafficClass: .announce))
    XCTAssertTrue(queues.put("pr", trafficClass: .pathRequest))
  }

  /// A drained slot accepts a new item.
  func testDrainingReopensAFullClass() {
    let queues = makeQueues(data: 1)
    XCTAssertTrue(queues.put("da0", trafficClass: .data))
    XCTAssertFalse(queues.put("da1", trafficClass: .data))
    XCTAssertEqual(queues.get(block: false), "da0")
    XCTAssertTrue(queues.put("da2", trafficClass: .data))
  }

  // MARK: - Heights and snapshots

  /// `qsize()` sums every class; `qsize(tc)` reads one (`Transport.py:84-86`).
  func testQsizeTotalAndPerClass() {
    let queues = makeQueues()
    XCTAssertTrue(queues.put("da", trafficClass: .data))
    XCTAssertTrue(queues.put("an0", trafficClass: .announce))
    XCTAssertTrue(queues.put("an1", trafficClass: .announce))
    XCTAssertTrue(queues.put("pr", trafficClass: .pathRequest))

    XCTAssertEqual(queues.qsize(), 4)
    XCTAssertEqual(queues.qsize(.data), 1)
    XCTAssertEqual(queues.qsize(.announce), 2)
    XCTAssertEqual(queues.qsize(.pathRequest), 1)
    XCTAssertEqual(queues.qsize(.ingressLimited), 0)
  }

  /// `snapshot()` returns `(sum(heights), heights, dropped)` (`Transport.py:89-93`).
  func testSnapshotReportsTotalHeightsAndDrops() {
    let queues = makeQueues(pathRequest: 1)
    XCTAssertTrue(queues.put("da", trafficClass: .data))
    XCTAssertTrue(queues.put("pr0", trafficClass: .pathRequest))
    XCTAssertFalse(queues.put("pr1", trafficClass: .pathRequest))
    XCTAssertTrue(queues.put("il", trafficClass: .ingressLimited))

    let snapshot = queues.snapshot()
    XCTAssertEqual(snapshot.total, 3)
    XCTAssertEqual(snapshot.heights, [1, 0, 1, 1])
    XCTAssertEqual(snapshot.dropped, [0, 0, 1, 0])
  }

  /// A drained item leaves the drop count unchanged.
  func testDropCountsSurviveDraining() {
    let queues = makeQueues(data: 1)
    XCTAssertTrue(queues.put("da0", trafficClass: .data))
    XCTAssertFalse(queues.put("da1", trafficClass: .data))
    XCTAssertEqual(queues.get(block: false), "da0")
    XCTAssertEqual(queues.snapshot().dropped, [1, 0, 0, 0])
    XCTAssertEqual(queues.snapshot().total, 0)
  }

  // MARK: - Blocking

  /// A non-blocking `get` on empty queues returns `nil`, where Python raises `Empty`
  /// (`Transport.py:74`).
  func testNonBlockingGetOnEmptyReturnsNil() {
    XCTAssertNil(makeQueues().get(block: false))
  }

  /// A blocking `get` with a timeout returns `nil` once the deadline passes
  /// (`Transport.py:75-77`).
  func testBlockingGetTimesOut() {
    let queues = makeQueues()
    let start = Date()
    XCTAssertNil(queues.get(block: true, timeout: 0.1))
    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.1)
  }

  /// A blocked `get` wakes when another thread puts an item (`Transport.py:66`).
  func testBlockedGetWakesOnPut() {
    let queues = makeQueues()
    let received = expectation(description: "get returned the item")
    Thread.detachNewThread {
      if queues.get(block: true, timeout: 5) == "da" { received.fulfill() }
    }
    Thread.sleep(forTimeInterval: 0.05)
    XCTAssertTrue(queues.put("da", trafficClass: .data))
    wait(for: [received], timeout: 5)
  }

  /// `close()` wakes a blocked `get`, which returns `nil`, and a later `put` returns
  /// `false` without counting a drop.
  func testCloseWakesABlockedGet() {
    let queues = makeQueues()
    let returned = expectation(description: "get returned nil")
    Thread.detachNewThread {
      if queues.get(block: true) == nil { returned.fulfill() }
    }
    Thread.sleep(forTimeInterval: 0.05)
    queues.close()
    wait(for: [returned], timeout: 5)

    XCTAssertFalse(queues.put("da", trafficClass: .data))
    XCTAssertEqual(queues.snapshot().dropped, [0, 0, 0, 0])
  }

  /// `close()` discards anything still queued.
  func testCloseDiscardsQueuedItems() {
    let queues = makeQueues()
    XCTAssertTrue(queues.put("da", trafficClass: .data))
    XCTAssertTrue(queues.put("an", trafficClass: .announce))
    queues.close()
    XCTAssertNil(queues.get(block: false))
    XCTAssertEqual(queues.snapshot().total, 0)
  }

  /// `get` returns each item that many threads put exactly once.
  func testConcurrentProducersLoseNothing() {
    let queues = makeQueues(data: 4096)
    let producers = 8
    let perProducer = 256
    DispatchQueue.concurrentPerform(iterations: producers) { p in
      for n in 0..<perProducer {
        XCTAssertTrue(queues.put("\(p)-\(n)", trafficClass: .data))
      }
    }
    var drained = Set<String>()
    while let item = queues.get(block: false) { drained.insert(item) }
    XCTAssertEqual(drained.count, producers * perProducer)
  }
}
