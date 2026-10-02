//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

extension Transport {
  /// The class an inbound packet queues under, in drain order (`Transport.py:111-114`).
  public enum TrafficClass: Int, CaseIterable, Comparable, Sendable {
    /// `TC_DATA`: every packet no other class claims.
    case data = 0x00
    /// `TC_ANNOUNCE`: announces.
    case announce = 0x01
    /// `TC_PATH_REQUEST`: path requests.
    case pathRequest = 0x02
    /// `TC_INGRESS_LIMITED`: path requests from an ingress-limited interface, and held
    /// announces on release.
    case ingressLimited = 0x03

    /// Orders classes by raw value, which is drain order.
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  /// Whether a running transport hands inbound packets to a drain worker
  /// (`USE_INBOUND_QUEUE`, `Transport.py:141`).
  public static let useInboundQueue = true

  /// Default capacity of the data queue (`INBOUND_DA_QUEUE_LENGTH`, `Transport.py:143`).
  public static let inboundDaQueueLength = 1024

  /// Default capacity of the announce queue (`INBOUND_AN_QUEUE_LENGTH`, `Transport.py:144`).
  public static let inboundAnQueueLength = 128

  /// Default capacity of the path-request queue (`INBOUND_PR_QUEUE_LENGTH`,
  /// `Transport.py:145`).
  public static let inboundPrQueueLength = 128

  /// Default capacity of the ingress-limited queue (`INBOUND_IL_QUEUE_LENGTH`,
  /// `Transport.py:146`).
  public static let inboundIlQueueLength = 8

  /// Name of the thread that drains the inbound queues.
  public static let inboundWorkerName = "ReticulumSwift.Transport.inbound"
}

/// Inbound queue heights and drop counts read at one instant.
public struct InboundQueueSnapshot: Equatable, Sendable {
  /// Items queued across every class.
  public let total: Int
  /// Items queued per class, indexed by `Transport.TrafficClass.rawValue`.
  public let heights: [Int]
  /// Items refused per class since creation, indexed by `Transport.TrafficClass.rawValue`.
  public let dropped: [Int]
}

/// One bounded first-in, first-out queue per traffic class, drained in class order.
///
/// Port of Python's `InboundQueues` (`Transport.py:47-95`). The data-queue high-water mark
/// that throttles `BackboneInterface`'s server-side dataplane (`Transport.py:59-60`) isn't
/// ported, because this port's Backbone is client-only.
public final class InboundQueues<Item>: @unchecked Sendable {

  private let condition = NSCondition()
  private var queues: [FIFO]
  private let sizes: [Int]
  private var dropped: [Int]
  private var closed = false

  /// Creates empty queues with the given capacity per class.
  public init(
    dataLength: Int, announceLength: Int, pathRequestLength: Int, ingressLimitedLength: Int
  ) {
    sizes = [dataLength, announceLength, pathRequestLength, ingressLimitedLength]
    queues = Array(repeating: FIFO(), count: sizes.count)
    dropped = Array(repeating: 0, count: sizes.count)
  }

  /// Appends `item` to its class's queue and wakes a waiting `get`.
  ///
  /// Returns `false` when the class is at capacity, which counts a drop
  /// (`Transport.py:61-63`), or after `close()`, which doesn't.
  public func put(_ item: Item, trafficClass: Transport.TrafficClass) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    if closed { return false }
    let index = trafficClass.rawValue
    if queues[index].count >= sizes[index] {
      dropped[index] += 1
      return false
    }
    queues[index].append(item)
    condition.signal()
    return true
  }

  /// Removes and returns the oldest item of the lowest non-empty class.
  ///
  /// Returns `nil` where Python raises `Empty` (`Transport.py:68-78`): when `block` is
  /// `false` and every queue is empty, or when `timeout` elapses first. A blocking call with
  /// no timeout waits until an item arrives or `close()` runs.
  public func get(block: Bool = true, timeout: TimeInterval? = nil) -> Item? {
    let deadline = timeout.map { Date().addingTimeInterval($0) }
    condition.lock()
    defer { condition.unlock() }
    while true {
      for index in queues.indices {
        if let item = queues[index].popFirst() { return item }
      }
      if closed || !block { return nil }
      if let deadline {
        if Date() >= deadline { return nil }
        condition.wait(until: deadline)
      } else {
        condition.wait()
      }
    }
  }

  /// Items queued in `trafficClass`, or across every class when `nil`
  /// (`Transport.py:84-86`).
  public func qsize(_ trafficClass: Transport.TrafficClass? = nil) -> Int {
    condition.lock()
    defer { condition.unlock() }
    guard let trafficClass else { return queues.reduce(0) { $0 + $1.count } }
    return queues[trafficClass.rawValue].count
  }

  /// Heights and drop counts under one lock (`Transport.py:89-93`).
  public func snapshot() -> InboundQueueSnapshot {
    condition.lock()
    defer { condition.unlock() }
    let heights = queues.map(\.count)
    return InboundQueueSnapshot(
      total: heights.reduce(0, +), heights: heights, dropped: dropped)
  }

  /// Discards every queued item, refuses later puts, and wakes every waiting `get`.
  public func close() {
    condition.lock()
    defer { condition.unlock() }
    closed = true
    for index in queues.indices { queues[index].removeAll() }
    condition.broadcast()
  }

  /// A first-in, first-out buffer with amortized constant-time removal from the front.
  private struct FIFO {
    private var storage: [Item?] = []
    private var head = 0

    var count: Int { storage.count - head }

    mutating func append(_ item: Item) { storage.append(item) }

    mutating func popFirst() -> Item? {
      guard head < storage.count else { return nil }
      let item = storage[head]
      storage[head] = nil
      head += 1
      if head * 2 >= storage.count {
        storage.removeFirst(head)
        head = 0
      }
      return item
    }

    mutating func removeAll() {
      storage.removeAll()
      head = 0
    }
  }
}
