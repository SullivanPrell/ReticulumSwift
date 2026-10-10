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

/// Recovery of a lost resource proof through the packet cache.
///
/// The receiver caches its proof (`Resource.py:773`), the sender asks for it when the proof
/// doesn't arrive (`Resource.py:652-672`), and the receiver answers a link `CACHE_REQUEST`
/// from its cache (`Transport.py:2570-2584`).
final class ResourceProofCacheTests: XCTestCase {

  // `scripts/capture-resource-proof-cache-vectors.py`, RNS 1.5.5: a resource proof on link
  // 000102...0f, its packet hash, the cache entry `Transport.cache` writes for it and the
  // `CACHE_REQUEST` `Transport.cache_request` sends for it.
  static let vectorLinkID = Data(0..<16)
  static let proofRaw = Data(
    hex:
      "0f00000102030405060708090a0b0c0d0e0f05596c351aa2f09bea17dbda5e1b2a3ea642330219f152151d8378574f9510edd7e1923545820a99d5854fc0da930b5f001a9da0497f2b6e3ebd1f3e5aaa105f81"
  )!
  static let proofHash = Data(
    hex: "d4e62621cc0fa0b58317d372c6e697bb80215e11a4db1354e82cfa42954cde9e")!
  static let cacheEntry = Data(
    hex:
      "92c4530f00000102030405060708090a0b0c0d0e0f05596c351aa2f09bea17dbda5e1b2a3ea642330219f152151d8378574f9510edd7e1923545820a99d5854fc0da930b5f001a9da0497f2b6e3ebd1f3e5aaa105f81c0"
  )!
  static let cacheRequestRaw = Data(
    hex:
      "0c00000102030405060708090a0b0c0d0e0f08d4e62621cc0fa0b58317d372c6e697bb80215e11a4db1354e82cfa42954cde9e"
  )!
  static var proofData: Data { proofRaw.suffix(64) }

  final class LoopbackInterface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    weak var paired: LoopbackInterface?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    /// Returns true for a packet the link loses.
    var drops: ((Packet) -> Bool)?
    private let lock = NSLock()
    private var _sent: [Packet] = []
    private var _dropped: [Packet] = []
    var sent: [Packet] { locked { _sent } }
    var dropped: [Packet] { locked { _dropped } }
    private func locked<T>(_ body: () -> T) -> T {
      lock.lock()
      defer { lock.unlock() }
      return body()
    }
    init(name: String) { self.name = name }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
      let copy = try Packet.unpack(packet.pack())
      if drops?(copy) == true {
        locked { _dropped.append(copy) }
        return
      }
      locked { _sent.append(copy) }
      paired?.inboundHandler?(copy, paired!)
    }
  }

  private var transports: [Transport] = []
  private var directories: [URL] = []

  override func tearDown() {
    for directory in directories { try? FileManager.default.removeItem(at: directory) }
    transports.removeAll()
    super.tearDown()
  }

  private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns-proof-cache-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    directories.append(directory)
    return directory
  }

  /// A link from `a` to `b`, each a leaf with its own cache directory.
  private func establishLink() throws -> (
    a: Transport, b: Transport, aLink: Link, bLink: Link, aI: LoopbackInterface,
    bI: LoopbackInterface
  ) {
    let aT = Transport()
    let bT = Transport()
    transports = [aT, bT]
    aT.transportEnabled = false
    bT.transportEnabled = false
    aT.cacheDirectory = try makeDirectory()
    bT.cacheDirectory = try makeDirectory()
    let bId = Identity()
    let bDest = try Destination(
      identity: bId, direction: .in, kind: .single, appName: "test", aspects: ["proofcache"])
    bT.ownerIdentity = bId
    bT.register(destination: bDest)
    let aI = LoopbackInterface(name: "A")
    let bI = LoopbackInterface(name: "B")
    aI.paired = bI
    bI.paired = aI
    aT.register(interface: aI)
    bT.register(interface: bI)
    let aE = expectation(description: "a")
    let bE = expectation(description: "b")
    aT.onLinkEstablished = { _ in aE.fulfill() }
    bT.onLinkEstablished = { _ in bE.fulfill() }
    let aLink = try Link.initiate(destination: bDest, transport: aT)
    wait(for: [aE, bE], timeout: 2.0)
    let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
    return (aT, bT, aLink, bLink, aI, bI)
  }

  private static func isResourceProof(_ packet: Packet) -> Bool {
    packet.packetType == .proof && packet.context == .resourceProof
  }

  /// Writes `entry` where Python's `Transport.cache` puts a packet (`Transport.py:3060`).
  private func writeCacheEntry(_ entry: Data, hash: Data, on transport: Transport) throws {
    let directory = try XCTUnwrap(transport.cacheDirectory)
    try entry.write(to: directory.appendingPathComponent(hash.hexString))
  }

  private func linkCacheRequest(_ hash: Data, on link: Link) throws -> Packet {
    Packet(
      destinationType: .link, packetType: .data, destinationHash: try XCTUnwrap(link.linkID),
      context: .cacheRequest, data: hash)
  }

  private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
  }

  // MARK: - Python's packet

  func testResourceProofPacketMatchesPython() throws {
    let packet = Packet(
      destinationType: .link, packetType: .proof, destinationHash: Self.vectorLinkID,
      context: .resourceProof, data: Self.proofData)
    XCTAssertEqual(try packet.pack(), Self.proofRaw)
    XCTAssertEqual(Hashes.fullHash(try packet.hashablePart()), Self.proofHash)
  }

  // MARK: - Receiver

  func testAReceivedResourceCachesItsProof() throws {
    let (_, b, aLink, bLink, _, bI) = try establishLink()
    let receiver = ResourceTransfer(link: bLink)
    receiver.bindAsReceiver()
    let completed = expectation(description: "completed")
    let sender = ResourceTransfer(link: aLink)
    sender.onComplete = { _ in completed.fulfill() }
    try sender.send(payload: Data(repeating: 0x5A, count: 100))
    wait(for: [completed], timeout: 5.0)

    let proof = try XCTUnwrap(bI.sent.first(where: Self.isResourceProof))
    let file = try XCTUnwrap(b.cacheDirectory).appendingPathComponent(
      Hashes.fullHash(try proof.hashablePart()).hexString)
    XCTAssertEqual(
      try Data(contentsOf: file), MsgPack.encode(.array([.bytes(try proof.pack()), .nil])),
      "Transport.cache writes [raw, None] for a sent packet (Transport.py:3056-3064)")
  }

  func testALinkCacheRequestResendsTheCachedProof() throws {
    let (a, b, aLink, _, aI, bI) = try establishLink()
    try writeCacheEntry(Self.cacheEntry, hash: Self.proofHash, on: b)

    try a.send(try linkCacheRequest(Self.proofHash, on: aLink), generateReceipt: false)

    XCTAssertTrue(waitUntil(timeout: 2.0) { bI.sent.contains(where: Self.isResourceProof) })
    let resent = try XCTUnwrap(bI.sent.first(where: Self.isResourceProof))
    XCTAssertEqual(resent.destinationHash, aLink.linkID, "Packet(destination=link, ...)")
    XCTAssertEqual(resent.data, Self.proofData)
    XCTAssertEqual(aI.sent.filter { $0.context == .cacheRequest }.count, 1)
  }

  func testATransportNodeAnswersALinkCacheRequestFromItsOwnCache() throws {
    let (a, b, aLink, _, _, bI) = try establishLink()
    b.transportEnabled = true
    try writeCacheEntry(Self.cacheEntry, hash: Self.proofHash, on: b)

    try a.send(try linkCacheRequest(Self.proofHash, on: aLink), generateReceipt: false)

    // Inside the transport gate `cache_request_packet` replays the proof to this node's own
    // inbound and returns True (`Transport.py:1997`, `:2012-2013`), so the link never sees it.
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    XCTAssertFalse(bI.sent.contains(where: Self.isResourceProof))
  }

  // MARK: - Sender

  func testASenderAwaitingProofSendsACacheRequest() throws {
    let (_, _, aLink, bLink, aI, bI) = try establishLink()
    bI.drops = Self.isResourceProof
    let receiver = ResourceTransfer(link: bLink)
    receiver.bindAsReceiver()
    let sender = ResourceTransfer(link: aLink)
    sender.retryTimeout = 0.2
    try sender.send(payload: Data(repeating: 0x5B, count: 100))

    XCTAssertTrue(waitUntil(timeout: 3.0) { aI.sent.contains { $0.context == .cacheRequest } })
    let proof = try XCTUnwrap(bI.dropped.first)
    let request = try XCTUnwrap(aI.sent.first { $0.context == .cacheRequest })
    let expectedHash = Hashes.fullHash(try proof.hashablePart())
    // The layout of `cache_request_raw`: unencrypted DATA to the link (`Packet.py:212-214`).
    let linkID = try XCTUnwrap(aLink.linkID)
    XCTAssertEqual(try request.pack(), Data([0x0C, 0x00]) + linkID + Data([0x08]) + expectedHash)
    XCTAssertEqual(
      Self.cacheRequestRaw, Data([0x0C, 0x00]) + Self.vectorLinkID + Data([0x08]) + Self.proofHash)
    sender.cancel()
  }

  func testADroppedProofIsRecoveredFromTheReceiversCache() throws {
    let (_, _, aLink, bLink, _, bI) = try establishLink()
    let dropFirst = NSLock()
    var proofs = 0
    bI.drops = { packet in
      guard Self.isResourceProof(packet) else { return false }
      dropFirst.lock()
      defer { dropFirst.unlock() }
      proofs += 1
      return proofs == 1
    }
    let receiver = ResourceTransfer(link: bLink)
    receiver.bindAsReceiver()
    let completed = expectation(description: "completed")
    let sender = ResourceTransfer(link: aLink)
    sender.retryTimeout = 0.2
    sender.onComplete = { _ in completed.fulfill() }
    try sender.send(payload: Data(repeating: 0x5C, count: 100))

    wait(for: [completed], timeout: 3.0)
    XCTAssertEqual(bI.dropped.count, 1)
    XCTAssertEqual(bI.sent.filter(Self.isResourceProof).count, 1, "the proof replayed from cache")
  }

  // MARK: - cache_request_packet

  func testCacheRequestPacketReadsThePacketCacheNotTheAnnounceCache() throws {
    let t = Transport()
    transports = [t]
    t.cacheDirectory = try makeDirectory()
    let announce = try Announce.make(
      for: Destination(identity: Identity(), direction: .in, kind: .single, appName: "creq"))
    try t.cacheAnnounce(announce)
    let request = Packet(
      destinationType: .single, packetType: .data,
      destinationHash: Hashes.truncatedHash(Data("creq".utf8)), context: .cacheRequest,
      data: Hashes.fullHash(try announce.hashablePart()))

    XCTAssertFalse(
      t.cacheRequestPacket(request),
      "get_cached_packet(packet.data) reads cachepath, not cachepath/announces (Transport.py:3100)"
    )
  }

  func testCacheRequestPacketReplaysOnTheCachedPacketsInterface() throws {
    let t = Transport()
    transports = [t]
    t.cacheDirectory = try makeDirectory()
    let first = LoopbackInterface(name: "first")
    let cachedOn = LoopbackInterface(name: "cached-on")
    t.register(interface: first)
    t.register(interface: cachedOn)
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "creq", aspects: ["iface"])
    let announce = try Announce.make(for: destination)
    let hash = Hashes.fullHash(try announce.hashablePart())
    try writeCacheEntry(
      MsgPack.encode(.array([.bytes(try announce.pack()), .string(cachedOn.name)])), hash: hash,
      on: t)
    let request = Packet(
      destinationType: .single, packetType: .data,
      destinationHash: Hashes.truncatedHash(Data("creq".utf8)), context: .cacheRequest, data: hash)

    XCTAssertTrue(t.cacheRequestPacket(request))
    XCTAssertTrue(waitUntil(timeout: 2.0) { t.hasPath(to: destination.hash) })
    XCTAssertTrue(
      t.paths[destination.hash]?.nextHopInterface === cachedOn,
      "inbound(packet.raw, packet.receiving_interface) (Transport.py:3107)")
  }

  // MARK: - Cull

  func testTheJobsLoopCullsWeekOldPacketCacheEntries() throws {
    let t = Transport()
    transports = [t]
    let directory = try makeDirectory()
    t.cacheDirectory = directory
    let old = Date().addingTimeInterval(-(Transport.destinationTimeout + 60))
    func entry(_ name: String, in folder: URL, modified: Date) throws -> URL {
      let url = folder.appendingPathComponent(name)
      try Data([0x92, 0xC0, 0xC0]).write(to: url)
      try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
      return url
    }
    let stale = try entry(String(repeating: "a", count: 64), in: directory, modified: old)
    let fresh = try entry(String(repeating: "b", count: 64), in: directory, modified: Date())
    let shortName = try entry("abcd", in: directory, modified: old)
    let announces = directory.appendingPathComponent("announces")
    try FileManager.default.createDirectory(at: announces, withIntermediateDirectories: true)
    let announce = try entry(String(repeating: "c", count: 64), in: announces, modified: old)

    t.runJobs()

    // `Reticulum.__clean_caches` (`Reticulum.py:1342-1352`).
    XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: shortName.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: announce.path))
  }
}
