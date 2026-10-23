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

/// Disk-based packet cache: announces for path table persistence across restarts, and the
/// resource proofs a sender can ask for again.
///
/// Mirrors Python's `Transport.cache`, `Transport.get_cached_packet`, and
/// `Transport.clean_announce_cache()` (`Transport.py:3048-3095`).
///
/// Storage layout (under `Transport.cacheDirectory`):
///   announces/<32-byte-hash-hex>—umsgpack [raw, interface_name | nil]
///   <32-byte-hash-hex>—the same, for any other cached packet
///
/// The encoding is the reference's, byte for byte (`Transport.py:2646-2657`): a Python daemon
/// must be able to read what this writes, because a path table entry names its announce by
/// hash and the reference discards any entry whose announce it can't load (`:334-345`).
/// Storing the receiving interface's name is what lets a restored packet say where it came from.
extension Transport {

  // MARK: - Announces subdirectory

  private var announcesDirectory: URL? {
    guard let base = cacheDirectory else { return nil }
    return base.appendingPathComponent(
      StorageInventory.Entry.announceCache.fileName)
  }

  // MARK: - Write

  /// Write `packet` to the announce cache keyed by its full SHA-256 packet hash.
  ///
  /// Creates the `announces/` subdirectory if needed.
  /// Mirrors Python's `Transport.cache(packet, force_cache=True, packet_type="announce")`.
  public func cacheAnnounce(_ packet: Packet, receivingInterfaceName: String? = nil) throws {
    try writeCacheEntry(packet, interfaceName: receivingInterfaceName, in: announcesDirectory)
  }

  /// Write `packet` to `<cacheDirectory>/<packet hash hex>`, naming the interface it arrived on.
  ///
  /// Mirrors Python's `Transport.cache(packet, force_cache=True)` (`Transport.py:3053-3067`).
  public func cache(_ packet: Packet) throws {
    try writeCacheEntry(packet, interfaceName: packet.receivingInterface?.name, in: cacheDirectory)
  }

  private func writeCacheEntry(_ packet: Packet, interfaceName: String?, in dir: URL?) throws {
    guard let dir else { return }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    guard let hashable = try? packet.hashablePart() else { return }
    let hash = Hashes.fullHash(hashable)
    let hexName = hash.hexString
    let raw = try packet.pack()

    // `umsgpack.packb([packet.raw, interface_reference])`—Transport.py:2655. A packet with
    // no receiving interface stores None, not a placeholder (:2650-2651).
    let entry = MsgPack.Value.array([
      .bytes(raw),
      interfaceName.map(MsgPack.Value.string) ?? .nil,
    ])
    try MsgPack.encode(entry).write(to: dir.appendingPathComponent(hexName), options: .atomic)
  }

  // MARK: - Read

  /// Load a cached announce packet by its full packet hash.
  ///
  /// Returns nil if not found or if the file is corrupt.
  /// Mirrors Python's `Transport.get_cached_packet(hash, packet_type="announce")`.
  public func getCachedAnnounce(hash: Data) throws -> Packet? {
    try readCacheEntry(hash: hash, in: announcesDirectory)
  }

  /// Load a packet from `<cacheDirectory>/<packet hash hex>`, or nil if it's absent or corrupt.
  ///
  /// Mirrors Python's `Transport.get_cached_packet(hash)` (`Transport.py:3070-3095`).
  public func getCachedPacket(hash: Data) -> Packet? {
    try? readCacheEntry(hash: hash, in: cacheDirectory)
  }

  private func readCacheEntry(hash: Data, in dir: URL?) throws -> Packet? {
    guard let dir else { return nil }
    let file = dir.appendingPathComponent(hash.hexString)
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }

    let data = try Data(contentsOf: file)
    guard case .array(let fields) = try MsgPack.decode(data), fields.count == 2,
      case .bytes(let raw) = fields[0]
    else { return nil }

    var packet = try Packet.unpack(raw)

    // Resolve the stored reference back to a live interface, as Python does at
    // `Transport.py:2680-2683`. A name matching nothing leaves the packet without an
    // interface—the reference's loop simply finds no match.
    if case .string(let interfaceName) = fields[1] {
      lock.lock()
      let match = interfaces.first { $0.name == interfaceName }
      lock.unlock()
      packet.receivingInterface = match
    }
    return packet
  }

  // MARK: - Clean

  /// Remove cached announces that are no longer referenced by any active path or tunnel.
  ///
  /// Mirrors Python's `Transport.clean_announce_cache()`.
  public func cleanAnnounceCache() throws {
    guard let dir = announcesDirectory else { return }
    guard FileManager.default.fileExists(atPath: dir.path) else { return }

    // Snapshot the routing tables under `lock`, then compute the referenced
    // set and do the (slow) directory scan outside the lock.
    lock.lock()
    let pathsSnapshot = paths
    let tunnelsSnapshot = tunnels
    lock.unlock()
    // Collect all hashes referenced by active paths and tunnels.
    let activeHashes = Set(pathsSnapshot.values.compactMap { $0.cachedAnnounceHash?.hexString })
    let tunnelHashes = Set(
      tunnelsSnapshot.values.flatMap { $0.paths.values }
        .compactMap { $0.cachedAnnounceHash?.hexString })
    let referenced = activeHashes.union(tunnelHashes)

    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    for name in files where !referenced.contains(name) {
      try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }
  }

  /// Remove packet-cache entries older than `destinationTimeout`, leaving `announces/` alone.
  ///
  /// Mirrors the packet-cache half of Python's `Reticulum.__clean_caches`
  /// (`Reticulum.py:1346-1357`): only names of 64 characters, by modification time.
  public func cleanPacketCache(now: Date = Date()) {
    guard let dir = cacheDirectory,
      let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
    else { return }
    for name in names where name.count == Constants.fullHashLength * 2 {
      let file = dir.appendingPathComponent(name)
      guard
        let modified = try? FileManager.default.attributesOfItem(atPath: file.path)[
          .modificationDate] as? Date,
        now.timeIntervalSince(modified) > Transport.destinationTimeout
      else { continue }
      try? FileManager.default.removeItem(at: file)
    }
  }

  // MARK: - cache_request_packet (mirrors Python Transport.cache_request_packet)

  /// Handle an inbound CACHE_REQUEST packet.
  ///
  /// If `packet.data` is a full packet hash found in the packet cache, the cached packet is
  /// replayed into the inbound pipeline on the interface it arrived on.
  ///
  /// Returns `true` if the request was served from cache, `false` otherwise.
  /// Mirrors Python's `Transport.cache_request_packet(packet)` (`Transport.py:3098-3111`).
  @discardableResult
  public func cacheRequestPacket(_ packet: Packet) -> Bool {
    guard packet.data.count == Constants.fullHashLength,
      let cached = getCachedPacket(hash: packet.data)
    else { return false }
    replay(cached)
    return true
  }

  // MARK: - cache_request (mirrors Python Transport.cache_request)

  /// Satisfy a cache request for `packetHash` against `destination`.
  ///
  /// If the packet is found in the local packet cache it's replayed directly
  /// into the inbound pipeline (no network hop needed). Otherwise a CACHE_REQUEST
  /// DATA packet is sent to `destination` asking the peer to replay the packet.
  ///
  /// Mirrors Python's `Transport.cache_request(packet_hash, destination)`
  /// (`Transport.py:3114-3124`).
  public func cacheRequest(packetHash: Data, destination: Destination) {
    cacheRequest(packetHash, destinationType: .single, destinationHash: destination.hash)
  }

  /// Requests a cached packet over a link.
  ///
  /// A resource sender makes this request when its proof doesn't arrive
  /// (`Resource.py:652-672`). The request isn't encrypted (`Packet.py:212-214`).
  public func cacheRequest(packetHash: Data, link: Link) {
    guard let linkID = link.linkID else { return }
    cacheRequest(packetHash, destinationType: .link, destinationHash: linkID)
  }

  private func cacheRequest(
    _ packetHash: Data, destinationType: Packet.DestinationType, destinationHash: Data
  ) {
    if let cached = getCachedPacket(hash: packetHash) {
      replay(cached)
      return
    }
    let pkt = Packet(
      destinationType: destinationType,
      packetType: .data,
      destinationHash: destinationHash,
      context: .cacheRequest,
      data: packetHash
    )
    try? send(pkt, generateReceipt: false)
  }

  /// `Transport.inbound(packet.raw, packet.receiving_interface, ifac_handled=True)`
  /// (`Transport.py:3107`, `:3119`).
  private func replay(_ cached: Packet) {
    if let interface = cached.receivingInterface {
      inbound(cached, from: interface)
      return
    }
    // shortcut: with no interface, only a link's resource proof is delivered
    // (`Transport.py:2722-2724`), the one packet cached without one. Replay through `inbound`
    // if another kind is ever cached with no interface.
    if cached.packetType == .proof, cached.context == .resourceProof,
      let link = lookupLink(cached.destinationHash)
    {
      try? link.receive(cached)
    }
  }
}
