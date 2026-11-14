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

/// RNS 1.6.0's SQLite known-destinations store (`Storage.py:215-547`) and how the stack reads
/// and writes it (`Identity.py:257-312`, `:617-650`; `Transport.py:1005-1007`).
final class KnownDestinationsStoreTests: XCTestCase {

  private var dir: URL!

  override func setUp() {
    super.setUp()
    dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns-kdstore-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    Reticulum.logHandler = nil
    try? FileManager.default.removeItem(at: dir)
    super.tearDown()
  }

  private var database: URL { StorageInventory.url(.knownDestinationsDatabase, storage: dir) }

  private func hash(_ byte: UInt8) -> Data { Data(repeating: byte, count: 16) }

  private func row(used: Double = 0) -> KnownDestinationsStore.Row {
    KnownDestinationsStore.Row(
      lastHeard: 1_760_000_000.25, packetHash: Data(repeating: 0x0C, count: 32),
      publicKey: Identity().publicKeyBytes, appData: Data("app".utf8), used: used,
      stamp: nil, stampValue: 0, lrCost: nil)
  }

  /// An inbound announce carrying a ratchet, the path that teaches a transport both.
  private func learn(on transport: Transport, ratchet: Bool = true) throws -> (Data, Data?) {
    let iface = LoopbackInterface(name: "kdstore-\(UUID().uuidString.prefix(6))")
    transport.register(interface: iface)
    let identity = Identity()
    let key = ratchet ? identity.rotateRatchet() : nil
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "kdstore", aspects: ["x"])
    transport.handleIncoming(
      packet: try Announce.make(for: destination, ratchet: key), from: iface)
    return (destination.hash, transport.knownRatchets[destination.hash])
  }

  // MARK: - The store

  /// Python's two tables, column for column (`Storage.py:257-272`), in WAL mode at
  /// `user_version` 0.
  func testTheSchemaIsPythons() throws {
    let store = try KnownDestinationsStore(path: database)
    func columns(_ table: String) throws -> [String] {
      try store.query("PRAGMA table_info(\(table))").map { c in
        "\(c[1]!) \(c[2]!) notnull=\(c[3]!) default=\(c[4].map { "\($0)" } ?? "-") pk=\(c[5]!)"
      }
    }
    XCTAssertEqual(
      try columns("known_destinations"),
      [
        "destination_hash BLOB notnull=0 default=- pk=1",
        "last_heard REAL notnull=1 default=- pk=0",
        "packet_hash BLOB notnull=0 default=- pk=0",
        "public_key BLOB notnull=1 default=- pk=0",
        "app_data BLOB notnull=0 default=- pk=0",
        "used REAL notnull=1 default=0 pk=0",
        "stamp BLOB notnull=0 default=- pk=0",
        "stamp_value REAL notnull=0 default=- pk=0",
        "lr_cost REAL notnull=0 default=- pk=0",
        "identity_hash BLOB notnull=1 default=- pk=0",
      ])
    XCTAssertEqual(
      try columns("ratchets"),
      [
        "destination_hash BLOB notnull=0 default=- pk=1",
        "ratchet BLOB notnull=1 default=- pk=0",
        "received REAL notnull=1 default=- pk=0",
      ])
    XCTAssertEqual(try store.query("PRAGMA journal_mode").first?.first as? String, "wal")
    XCTAssertEqual(try store.query("PRAGMA user_version").first?.first as? Int64, 0)
  }

  /// A database from an RNS pre-release has `user_version` above 0 and loses its
  /// `known_destinations` table (`Storage.py:250-255`).
  func testAPreReleaseDatabaseIsRebuilt() throws {
    do {
      let old = try KnownDestinationsStore(path: database)
      try old.query("DROP TABLE known_destinations")
      try old.query("CREATE TABLE known_destinations (destination_hash BLOB PRIMARY KEY, old BLOB)")
      try old.query("INSERT INTO known_destinations VALUES (?, ?)", [hash(1), Data([2])])
      try old.query("PRAGMA user_version = 3")
    }

    let store = try KnownDestinationsStore(path: database)

    XCTAssertEqual(try store.query("PRAGMA user_version").first?.first as? Int64, 0)
    XCTAssertEqual(
      try store.query("SELECT COUNT(*) FROM known_destinations").first?.first as? Int64, 0)
    XCTAssertTrue(
      try store.query("PRAGMA table_info(known_destinations)").contains {
        $0[1] as? String == "identity_hash"
      })
  }

  /// A flush writes what changed since the last one, drops the ratchet of a destination
  /// that's gone, and keeps no ratchet for a destination it doesn't know
  /// (`Storage.py:384-394`).
  func testAFlushWritesTheDifference() throws {
    let store = try KnownDestinationsStore(path: database)
    let (a, b, unknown) = (hash(0xA1), hash(0xB2), hash(0xC3))
    var rows = [a: row(), b: row(used: -1)]
    let ratchet = KnownDestinationsStore.Ratchet(
      ratchet: Data(repeating: 7, count: 32), received: 1_760_000_100)

    XCTAssertEqual(try store.flush(rows, ratchets: [a: ratchet, unknown: ratchet]), 3)
    XCTAssertEqual(try store.flush(rows, ratchets: [a: ratchet]), 0, "nothing changed")
    rows[b]!.used = 1_760_000_200
    rows[a] = nil
    XCTAssertEqual(
      try store.flush(rows, ratchets: [a: ratchet]), 3,
      "an update, a delete, and the deleted destination's ratchet")

    let reader = try KnownDestinationsStore(path: database, readOnly: true)
    XCTAssertEqual(try reader.loadAll(), rows)
    XCTAssertNil(try reader.fetchRatchet(a))
    XCTAssertNil(try reader.fetchRatchet(unknown))
    XCTAssertEqual(
      try store.query("SELECT identity_hash FROM known_destinations").first?.first as? Data,
      Hashes.truncatedHash(rows[b]!.publicKey), "`Storage.py:288`")
  }

  /// `sqlite3.connect("file:…?mode=ro", uri=True)` on a missing file
  /// (`Storage.py:234`): the error Python logs, and no file left behind.
  func testAReadOnlyOpenOfAMissingFileFailsAsPythonsDoes() {
    XCTAssertThrowsError(try KnownDestinationsStore(path: database, readOnly: true)) {
      XCTAssertEqual("\($0)", "unable to open database file")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))
  }

  /// `import_legacy` (`Storage.py:528-547`): entries under five fields are skipped, the rest
  /// padded with `None, 0, None`, and a zero `last_heard` becomes now.
  func testImportingTheLegacyFileFollowsPythonsRules() throws {
    let key = Identity().publicKeyBytes
    let stamp = Data(repeating: 0x5A, count: 32)
    let legacy = StorageInventory.url(.knownDestinations, storage: dir)
    try MsgPack.encode(
      .map([
        (
          .bytes(hash(1)),
          .array([.double(1_760_000_000), .bytes(Data([9])), .bytes(key), .nil, .uint(0)])
        ),
        (
          .bytes(hash(2)),
          .array([
            .uint(0), .bytes(Data([9])), .bytes(key), .bytes(Data("x".utf8)), .int(-1),
            .bytes(stamp), .double(12.5), .double(9.1),
          ])
        ),
        (.bytes(hash(3)), .array([.double(1), .bytes(Data()), .bytes(key), .nil])),
      ])
    ).write(to: legacy)
    let store = try KnownDestinationsStore(path: database)
    let before = Date().timeIntervalSince1970

    XCTAssertEqual(try store.importLegacy(from: legacy), 2)

    let rows = try store.loadAll()
    XCTAssertEqual(
      rows[hash(1)],
      KnownDestinationsStore.Row(
        lastHeard: 1_760_000_000, packetHash: Data([9]), publicKey: key, appData: nil, used: 0,
        stamp: nil, stampValue: 0, lrCost: nil))
    let second = try XCTUnwrap(rows[hash(2)])
    XCTAssertGreaterThanOrEqual(second.lastHeard, before)
    XCTAssertEqual(second.used, -1)
    XCTAssertEqual(second.stamp, stamp)
    XCTAssertEqual(second.stampValue, 12.5)
    XCTAssertEqual(second.lrCost, 9.1)
    XCTAssertNil(rows[hash(3)])
  }

  /// `import_legacy_ratchets` (`Storage.py:497-526`) keeps a current ratchet of a known
  /// destination and unlinks every file, imported or not.
  func testImportingLegacyRatchetsKeepsValidOnesAndRemovesEveryFile() throws {
    let ratchets = StorageInventory.url(.ratchets, storage: dir)
    try FileManager.default.createDirectory(at: ratchets, withIntermediateDirectories: true)
    let now = Date().timeIntervalSince1970
    func plant(_ name: String, width: Int = 32, received: Double) throws {
      try MsgPack.encode(
        .map([
          (.string("ratchet"), .bytes(Data(repeating: 5, count: width))),
          (.string("received"), .double(received)),
        ])
      ).write(to: ratchets.appendingPathComponent(name))
    }
    try plant(hash(1).hexString, received: now)
    try plant(hash(2).hexString, received: now - 40 * 86400)
    try plant(hash(3).hexString, received: now)
    try plant(hash(4).hexString, width: 31, received: now)
    try Data("garbage".utf8).write(to: ratchets.appendingPathComponent("zz"))
    let store = try KnownDestinationsStore(path: database)

    let imported = store.importLegacyRatchets(
      from: ratchets, cutoff: now - 30 * 86400, known: [hash(1), hash(2), hash(4)])

    XCTAssertEqual(imported, 1)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: ratchets.path), [])
    XCTAssertEqual(try store.fetchRatchet(hash(1))?.received, now)
    XCTAssertNil(try store.fetchRatchet(hash(2)))
  }

  // MARK: - The stack

  /// A start imports the legacy file and the ratchet files, renames the one and removes the
  /// others (`Identity.py:286-312`), and a restart reads everything back from the database.
  func testAStartImportsLegacyStateAndARestartReadsTheDatabase() throws {
    let writer = Transport()
    writer.ratchetsDirectory = StorageInventory.url(.ratchets, storage: dir)
    let (destination, ratchet) = try learn(on: writer)
    try writer.saveKnownDestinations(to: StorageInventory.url(.knownDestinations, storage: dir))
    XCTAssertNotNil(ratchet)

    let first = Reticulum(configuration: .init(storagePath: dir))
    try first.start()
    XCTAssertNotNil(first.transport.knownIdentities[destination])
    XCTAssertEqual(first.transport.currentRatchetKey(forDestination: destination), ratchet)
    first.stop()

    let manager = FileManager.default
    XCTAssertFalse(
      manager.fileExists(atPath: StorageInventory.url(.knownDestinations, storage: dir).path))
    XCTAssertTrue(
      manager.fileExists(
        atPath: StorageInventory.url(.knownDestinationsImported, storage: dir).path))
    XCTAssertEqual(
      try manager.contentsOfDirectory(atPath: StorageInventory.url(.ratchets, storage: dir).path),
      [])

    let second = Reticulum(configuration: .init(storagePath: dir))
    try second.start()
    defer { second.stop() }
    XCTAssertNotNil(second.transport.knownIdentities[destination])
    XCTAssertEqual(second.transport.currentRatchetKey(forDestination: destination), ratchet)
  }

  /// The jobs loop flushes every `kd_flush_interval` seconds (`Transport.py:351`, `:1005-1007`).
  func testTheJobsLoopFlushesEveryTenSeconds() throws {
    let transport = Transport()
    transport.knownDestinationsStore = try KnownDestinationsStore(path: database)
    let (destination, ratchet) = try learn(on: transport)
    let reader = try KnownDestinationsStore(path: database, readOnly: true)

    transport.lastKnownDestinationsFlush = Date()
    transport.runJobs()
    XCTAssertEqual(try reader.loadAll().count, 0, "inside the interval")

    transport.lastKnownDestinationsFlush = Date().addingTimeInterval(-11)
    transport.runJobs()
    let row = try XCTUnwrap(try reader.loadAll()[destination])
    XCTAssertEqual(row.publicKey, transport.knownIdentities[destination]?.publicKeyBytes)
    XCTAssertEqual(row.used, 0)
    XCTAssertEqual(try reader.fetchRatchet(destination)?.ratchet, ratchet)
  }

  /// `_remember_ratchet` returns before storing an identical ratchet (`Identity.py:538`), so
  /// a repeated announce doesn't move the ratchet's received time.
  func testARepeatedRatchetKeepsItsReceivedTime() throws {
    let transport = Transport()
    let iface = LoopbackInterface(name: "kdstore-repeat")
    transport.register(interface: iface)
    let identity = Identity()
    let ratchet = identity.rotateRatchet()
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "kdstore", aspects: ["r"])
    transport.handleIncoming(
      packet: try Announce.make(for: destination, ratchet: ratchet), from: iface)
    let aged = Date().addingTimeInterval(-60)
    transport.restore(
      ratchet: try XCTUnwrap(transport.knownRatchets[destination.hash]),
      forDestination: destination.hash, receivedAt: aged)

    transport.handleIncoming(
      packet: try Announce.make(for: destination, ratchet: ratchet), from: iface)

    XCTAssertEqual(transport.knownRatchetTimes[destination.hash], aged)
  }

  /// A local client loads the shared instance's table read-only and fetches a ratchet it
  /// lacks from the same database (`Identity.py:259-273`, `:636-648`).
  func testALocalClientReadsTheSharedInstanceDatabase() throws {
    let destination = hash(0xD4)
    let ratchet = KnownDestinationsStore.Ratchet(
      ratchet: Data(repeating: 3, count: 32), received: Date().timeIntervalSince1970)
    try KnownDestinationsStore(path: database).flush(
      [destination: row()], ratchets: [destination: ratchet])

    let client = Reticulum(configuration: .init(storagePath: dir))
    client.transport.isConnectedToSharedInstance = true
    try client.start()
    defer { client.stop() }

    XCTAssertNotNil(client.transport.knownIdentities[destination])
    XCTAssertNil(client.transport.knownRatchets[destination], "fetched on a miss, not at start")
    XCTAssertEqual(client.transport.currentRatchetKey(forDestination: destination), ratchet.ratchet)
  }

  /// With no database to read, a client logs Python's error, keeps an empty table and
  /// creates nothing (`Identity.py:271-273`).
  func testALocalClientWithoutADatabaseLogsPythonsError() throws {
    var errors: [String] = []
    Reticulum.logHandler = { message, level in if level == .error { errors.append(message) } }

    let client = Reticulum(configuration: .init(storagePath: dir))
    client.transport.isConnectedToSharedInstance = true
    try client.start()
    defer { client.stop() }

    XCTAssertTrue(
      errors.contains(
        "Could not load known destinations from shared instance database, continuing with an "
          + "empty table. The contained exception was: unable to open database file"),
      "\(errors)")
    XCTAssertTrue(client.transport.knownIdentities.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))
  }
}
