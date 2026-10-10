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

/// Restoring a tunnel's paths when its endpoint reappears, as Python RNS 1.5.5 does.
///
/// `Transport.handle_tunnel` (`Transport.py:2829-2874`) walks the tunnel's paths and installs
/// each one on the new interface when the path table has none, or when the tunnel's path has no
/// more hops than the current one, or the current one has expired, and its announce is no older.
/// A path it doesn't install leaves the tunnel. Hop counts compare as `IDX_PT_HOPS`, Python's
/// count. The announce handler records a tunnel path only when the announce entered the path
/// table, with its random blobs and packet hash (`Transport.py:2465-2475`).
final class TunnelPathRestoreTests: XCTestCase {

  // MARK: - Fixtures

  final class MeshIface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  /// Stands in for `LocalServerClientInterface`, where Python's count equals the wire count.
  final class ServingIface: Interface, LocalClientServingInterface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var clientCount: Int = 1
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  /// The remote side of a tunnel: its transport identity and the hash of its interface.
  struct Endpoint {
    let identity = Identity()
    let interfaceHash = Hashes.randomHash() + Hashes.randomHash()

    /// `full_hash(public_key + interface_hash)`—`Transport.py:2794-2795`.
    var tunnelID: Data { Hashes.fullHash(identity.publicKeyBytes + interfaceHash) }
  }

  /// Transports hold interfaces weakly.
  private var retained: [AnyObject] = []
  private var tmpDir: URL!

  override func setUp() {
    super.setUp()
    tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns-tunnel-restore-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    retained = []
    try? FileManager.default.removeItem(at: tmpDir)
    super.tearDown()
  }

  private func makeTransport() -> Transport {
    let t = Transport()
    t.cacheDirectory = tmpDir.appendingPathComponent("cache")
    retained.append(t)
    return t
  }

  private func mesh(_ name: String, on t: Transport) -> MeshIface {
    let iface = MeshIface(name: name)
    t.register(interface: iface)
    retained.append(iface)
    return iface
  }

  private func serving(_ name: String, on t: Transport) -> ServingIface {
    let iface = ServingIface(name: name)
    t.register(interface: iface)
    retained.append(iface)
    return iface
  }

  private func destination(_ aspect: String) throws -> Destination {
    try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "tunnelrestore",
      aspects: [aspect])
  }

  /// Delivers on `iface` the tunnel synthesis `endpoint` signs (`Transport.py:2764-2783`).
  private func synthesize(_ endpoint: Endpoint, on iface: any Interface) throws {
    let tunnelIDData = endpoint.identity.publicKeyBytes + endpoint.interfaceHash
    let signedData = tunnelIDData + Hashes.randomHash()
    let packet = Packet(
      destinationType: .plain,
      packetType: .data,
      destinationHash: Transport.tunnelSynthesizeHash,
      data: signedData + (try endpoint.identity.sign(signedData)))
    iface.inboundHandler?(try Packet.unpack(packet.pack()), iface)
  }

  /// Delivers an announce for `destination` on `iface`, carrying `hops` on the wire.
  private func announce(
    _ destination: Destination, on iface: any Interface, hops: UInt8 = 0,
    emittedAt: TimeInterval = Date().timeIntervalSince1970
  ) throws {
    var packet = try Announce.make(for: destination, timestamp: emittedAt)
    packet.hops = hops
    iface.inboundHandler?(try Packet.unpack(packet.pack()), iface)
  }

  /// A random blob whose last five bytes carry `emittedAt`—`Transport.py:3725-3726`.
  private func blob(emittedAt: TimeInterval) -> Data {
    var data = Data(Hashes.randomHash().prefix(5))
    let seconds = UInt64(emittedAt)
    for shift in stride(from: 32, through: 0, by: -8) {
      data.append(UInt8(truncatingIfNeeded: seconds >> shift))
    }
    return data
  }

  /// A tunnel through `iface` holding the path an announce `hops` away on the wire left in it.
  private func tunnelWithPath(
    on t: Transport, through iface: any Interface, hops: UInt8, aspect: String
  ) throws -> (Endpoint, Destination, Transport.PathEntry) {
    let endpoint = Endpoint()
    try synthesize(endpoint, on: iface)
    let destination = try destination(aspect)
    try announce(destination, on: iface, hops: hops)
    let path = try XCTUnwrap(
      t.tunnels[endpoint.tunnelID]?.paths[destination.hash],
      "the announce must be recorded on the tunnel (Transport.py:2467-2475)")
    return (endpoint, destination, path)
  }

  /// Replaces the path table's entry for `destination` with one through `iface`.
  private func install(
    _ destination: Destination, on t: Transport, through iface: any Interface, hops: UInt8,
    blobs: [Data], expires: Date = Date().addingTimeInterval(Transport.pathExpiry)
  ) {
    t.restore(
      path: Transport.PathEntry(
        destinationHash: destination.hash, nextHopInterface: iface, hops: hops,
        lastHeard: Date(), identityHash: destination.identity!.hash, expires: expires,
        randomBlobs: blobs),
      forDestination: destination.hash)
  }

  // MARK: - Recording

  func testATunnelPathCarriesItsAnnouncesRandomBlobsAndHash() throws {
    let t = makeTransport()
    let iface = mesh("tunnel", on: t)
    let (_, destination, tunnelPath) = try tunnelWithPath(
      on: t, through: iface, hops: 1, aspect: "carried")
    let path = try XCTUnwrap(t.paths[destination.hash])

    XCTAssertFalse(path.randomBlobs.isEmpty)
    XCTAssertEqual(
      tunnelPath.randomBlobs, path.randomBlobs,
      "the tunnel stores the path's `random_blobs` (Transport.py:2473)")
    XCTAssertNotNil(path.cachedAnnounceHash)
    XCTAssertEqual(
      tunnelPath.cachedAnnounceHash, path.cachedAnnounceHash,
      "and its `packet.packet_hash`, which `save_tunnel_table` writes (Transport.py:3924)")
  }

  func testAnAnnounceThePathTableRejectsIsNotRecordedOnTheTunnel() throws {
    let t = makeTransport()
    let direct = mesh("direct", on: t)
    let tunneled = mesh("tunnel", on: t)
    let endpoint = Endpoint()
    try synthesize(endpoint, on: tunneled)
    let destination = try destination("rejected")
    let now = Date().timeIntervalSince1970

    try announce(destination, on: direct, emittedAt: now)
    try announce(destination, on: tunneled, emittedAt: now - 100)

    XCTAssertTrue(
      t.paths[destination.hash]?.nextHopInterface === direct,
      "an older announce at the same hop count is rejected (Transport.py:2236-2245)")
    XCTAssertNil(
      t.tunnels[endpoint.tunnelID]?.paths[destination.hash],
      "the tunnel records a path inside `if should_add:` only (Transport.py:2298, :2467)")
  }

  // MARK: - Restoring

  func testAReappearingTunnelRestoresItsPathOnTheNewInterface() throws {
    let t = makeTransport()
    let first = mesh("first", on: t)
    let (endpoint, destination, tunnelPath) = try tunnelWithPath(
      on: t, through: first, hops: 1, aspect: "restored")
    t.deregister(interface: first)
    let second = mesh("second", on: t)
    let before = Date()

    try synthesize(endpoint, on: second)

    let restored = try XCTUnwrap(t.paths[destination.hash])
    XCTAssertTrue(restored.nextHopInterface === second, "`receiving_interface = interface` (:2844)")
    XCTAssertEqual(t.hopsTo(destination.hash), 2, "`announce_hops` is kept (:2841)")
    XCTAssertGreaterThanOrEqual(restored.lastHeard, before, "`time.time()` (:2846)")
    XCTAssertEqual(restored.expires, tunnelPath.expires, "`expires = path_entry[3]` (:2842)")
    XCTAssertEqual(restored.nextHopTransportID, tunnelPath.nextHopTransportID)
    XCTAssertEqual(restored.randomBlobs, tunnelPath.randomBlobs)
    XCTAssertEqual(restored.cachedAnnounceHash, tunnelPath.cachedAnnounceHash)
    XCTAssertEqual(restored.identityHash, tunnelPath.identityHash)
    XCTAssertTrue(t.tunnels[endpoint.tunnelID]?.iface === second)
    XCTAssertNotNil(t.tunnels[endpoint.tunnelID]?.paths[destination.hash])
    XCTAssertEqual(second.tunnelID, endpoint.tunnelID)
  }

  func testAPathMissingFromThePathTableIsRestored() throws {
    let t = makeTransport()
    let first = mesh("first", on: t)
    let (endpoint, destination, _) = try tunnelWithPath(
      on: t, through: first, hops: 1, aspect: "absent")
    t.paths.removeValue(forKey: destination.hash)
    let second = mesh("second", on: t)

    try synthesize(endpoint, on: second)

    XCTAssertTrue(
      t.paths[destination.hash]?.nextHopInterface === second,
      "`if time.time() < expires: should_add = True` (:2863)")
  }

  func testAnExpiredTunnelPathIsNotRestoredAndLeavesTheTunnel() throws {
    let t = makeTransport()
    let first = mesh("first", on: t)
    let (endpoint, destination, _) = try tunnelWithPath(
      on: t, through: first, hops: 1, aspect: "expired")
    t.paths.removeValue(forKey: destination.hash)
    t.tunnels[endpoint.tunnelID]?.paths[destination.hash]?.expires = Date().addingTimeInterval(-1)
    let second = mesh("second", on: t)

    try synthesize(endpoint, on: second)

    XCTAssertNil(t.paths[destination.hash], "an expired tunnel path isn't restored (:2864)")
    XCTAssertNil(
      t.tunnels[endpoint.tunnelID]?.paths[destination.hash],
      "a path not restored is removed from the tunnel (:2870-2874)")
  }

  func testAPathWithFewerHopsIsKept() throws {
    let t = makeTransport()
    let first = mesh("first", on: t)
    let direct = mesh("direct", on: t)
    let (endpoint, destination, tunnelPath) = try tunnelWithPath(
      on: t, through: first, hops: 2, aspect: "fewer")
    install(destination, on: t, through: direct, hops: 0, blobs: tunnelPath.randomBlobs)
    let second = mesh("second", on: t)

    try synthesize(endpoint, on: second)

    XCTAssertTrue(
      t.paths[destination.hash]?.nextHopInterface === direct,
      "3 hops isn't `<= old_hops` of 1, and the path hasn't expired (:2854)")
    XCTAssertNil(t.tunnels[endpoint.tunnelID]?.paths[destination.hash])
  }

  func testAnExpiredPathIsReplacedDespiteFewerHops() throws {
    let t = makeTransport()
    let first = mesh("first", on: t)
    let direct = mesh("direct", on: t)
    let (endpoint, destination, tunnelPath) = try tunnelWithPath(
      on: t, through: first, hops: 2, aspect: "stale")
    install(
      destination, on: t, through: direct, hops: 0, blobs: tunnelPath.randomBlobs,
      expires: Date().addingTimeInterval(-1))
    let second = mesh("second", on: t)

    try synthesize(endpoint, on: second)

    XCTAssertTrue(
      t.paths[destination.hash]?.nextHopInterface === second,
      "`or time.time() > old_expires` (:2854)")
    XCTAssertEqual(t.hopsTo(destination.hash), 3)
  }

  func testAPathFromANewerAnnounceIsKept() throws {
    let t = makeTransport()
    let first = mesh("first", on: t)
    let direct = mesh("direct", on: t)
    let (endpoint, destination, tunnelPath) = try tunnelWithPath(
      on: t, through: first, hops: 1, aspect: "newer")
    let newer = Transport.timebaseFromRandomBlobs(tunnelPath.randomBlobs) + 100
    install(destination, on: t, through: direct, hops: 3, blobs: [blob(emittedAt: newer)])
    let second = mesh("second", on: t)

    try synthesize(endpoint, on: second)

    XCTAssertTrue(
      t.paths[destination.hash]?.nextHopInterface === direct,
      "`if tunnel_announce_timebase >= current_path_timebase` (:2858)")
    XCTAssertNil(t.tunnels[endpoint.tunnelID]?.paths[destination.hash])
  }

  // MARK: - Python's hop count

  func testHopCountsCompareAsPythonCountsThem() throws {
    let t = makeTransport()
    let first = mesh("first", on: t)
    let client = serving("LocalInterface[50001]", on: t)
    let (endpoint, destination, tunnelPath) = try tunnelWithPath(
      on: t, through: first, hops: 2, aspect: "compared")
    install(destination, on: t, through: client, hops: 2, blobs: tunnelPath.randomBlobs)
    let second = mesh("second", on: t)

    try synthesize(endpoint, on: second)

    XCTAssertTrue(
      t.paths[destination.hash]?.nextHopInterface === client,
      """
      the tunnel path is 3 hops in Python's count and the local client's path 2, so \
      `announce_hops <= old_hops` fails (:2854), though both are 2 on the wire
      """)
    XCTAssertNil(t.tunnels[endpoint.tunnelID]?.paths[destination.hash])
  }

  func testARestoredPathKeepsPythonsCountOnTheNewInterface() throws {
    let t = makeTransport()
    let first = mesh("first", on: t)
    let (endpoint, destination, _) = try tunnelWithPath(
      on: t, through: first, hops: 2, aspect: "recounted")
    let client = serving("LocalInterface[50001]", on: t)

    try synthesize(endpoint, on: client)

    XCTAssertTrue(t.paths[destination.hash]?.nextHopInterface === client)
    XCTAssertEqual(
      t.hopsTo(destination.hash), 3,
      "`new_entry` carries `announce_hops` unchanged onto the new interface (:2846)")
  }

  func testAPersistedTunnelPathIsRestoredAtItsCount() throws {
    let live = makeTransport()
    let first = mesh("first", on: live)
    let (endpoint, destination, _) = try tunnelWithPath(
      on: live, through: first, hops: 2, aspect: "persisted")
    let store = try TunnelStore.decode(TunnelStore.snapshot(of: live).encoded())
    XCTAssertEqual(store.entries.first?.paths.count, 1, "`save_tunnel_table` (Transport.py:3879)")

    let revived = makeTransport()
    store.apply(to: revived)
    let second = mesh("second", on: revived)
    try synthesize(endpoint, on: second)

    XCTAssertTrue(revived.paths[destination.hash]?.nextHopInterface === second)
    XCTAssertEqual(revived.hopsTo(destination.hash), 3)
  }
}
