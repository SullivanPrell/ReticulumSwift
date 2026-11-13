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
import SQLite3

/// RNS 1.6.0's write-behind SQLite store for known destinations and their ratchets
/// (`Storage.py:215-547`), at `storage/known_destinations.db`.
///
/// The transport's in-memory tables stay authoritative. This only persists them, so a Python
/// node pointed at the same storage directory reads the same rows, and a local client of
/// either reads the shared instance's table from it.
public final class KnownDestinationsStore {

  /// One `known_destinations` row: Python's entry list `[last_heard, packet_hash, public_key,
  /// app_data, used, stamp, stamp_value, lr_cost]` (`Storage.py:425-430`).
  public struct Row: Equatable {
    /// When the destination last announced, in seconds since 1970.
    public var lastHeard: Double
    /// The full hash of the announce that taught it.
    public var packetHash: Data?
    /// The identity's 64-byte public key.
    public var publicKey: Data
    /// The announce's application data.
    public var appData: Data?
    /// 0 for never used, -1 for retained, otherwise the time of last use.
    public var used: Double
    /// The announce's stamp, valid or not.
    public var stamp: Data?
    /// The stamp's value.
    public var stampValue: Double?
    /// The link-request cost a valid stamp announced.
    public var lrCost: Double?

    /// Creates a row from its fields.
    public init(
      lastHeard: Double, packetHash: Data?, publicKey: Data, appData: Data?, used: Double,
      stamp: Data?, stampValue: Double?, lrCost: Double?
    ) {
      self.lastHeard = lastHeard
      self.packetHash = packetHash
      self.publicKey = publicKey
      self.appData = appData
      self.used = used
      self.stamp = stamp
      self.stampValue = stampValue
      self.lrCost = lrCost
    }

    /// A legacy `known_destinations` entry, or nil when it carries no public key.
    ///
    /// Padded to eight fields with `None, 0, None`, as `Identity.py:332-339` and
    /// `Storage.py:537` do.
    init?(entry: [MsgPack.Value]) {
      var fields = entry
      while fields.count < 8 { fields.append(fields.count == 6 ? .int(0) : .nil) }
      guard case .bytes(let publicKey) = fields[2] else { return nil }
      self.init(
        lastHeard: fields[0].asDouble ?? 0, packetHash: fields[1].asData, publicKey: publicKey,
        appData: fields[3].asData, used: fields[4].asDouble ?? 0, stamp: fields[5].asData,
        stampValue: fields[6].asDouble, lrCost: fields[7].asDouble)
    }
  }

  /// One `ratchets` row.
  public struct Ratchet: Equatable {
    /// The destination's 32-byte ratchet public key.
    public var ratchet: Data
    /// When it was first received, in seconds since 1970.
    public var received: Double

    /// Creates a row from its fields.
    public init(ratchet: Data, received: Double) {
      self.ratchet = ratchet
      self.received = received
    }
  }

  /// An SQLite error, described as Python's `sqlite3` exception prints.
  public struct Error: Swift.Error, CustomStringConvertible {
    /// SQLite's message, such as `unable to open database file`.
    public let description: String
  }

  private var db: OpaquePointer?
  private let lock = NSLock()
  // What the last flush or load left on disk; the next flush writes only the difference.
  // shortcut: each flush diffs every row, O(n) where Python tracks dirty sets; add dirty
  // marks at the mutation sites if a large transport node shows flushes in profiles.
  private var written: [Data: Row] = [:]
  private var writtenRatchets: [Data: Ratchet] = [:]

  /// Opens or creates the database, or opens it read-only as a local client does
  /// (`Storage.py:221-240`).
  public init(path: URL, readOnly: Bool = false) throws {
    let rc =
      readOnly
      ? sqlite3_open_v2(
        "file:\(path.path)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
      : sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    guard rc == SQLITE_OK else {
      let error = failure()
      sqlite3_close_v2(db)
      db = nil
      throw error
    }
    guard !readOnly else { return }
    try query("PRAGMA journal_mode=WAL")
    try query("PRAGMA synchronous=NORMAL")
    try query("PRAGMA journal_size_limit=8388608")
    try createSchema()
  }

  deinit { sqlite3_close_v2(db) }

  private func createSchema() throws {
    if let version = try query("PRAGMA user_version").first?.first as? Int64, version > 0 {
      Reticulum.log(
        "Pre-release database detected, rebuilding known destinations DB to release format",
        level: .warning)
      try query("DROP TABLE IF EXISTS known_destinations")
    }
    try query(
      """
      CREATE TABLE IF NOT EXISTS known_destinations (
          destination_hash BLOB PRIMARY KEY,
          last_heard       REAL NOT NULL,
          packet_hash      BLOB,
          public_key       BLOB NOT NULL,
          app_data         BLOB,
          used             REAL NOT NULL DEFAULT 0,
          stamp            BLOB,
          stamp_value      REAL,
          lr_cost          REAL,
          identity_hash    BLOB NOT NULL)
      """)
    try query(
      """
      CREATE TABLE IF NOT EXISTS ratchets (
          destination_hash BLOB PRIMARY KEY,
          ratchet          BLOB NOT NULL,
          received         REAL NOT NULL)
      """)
    do {
      try query("BEGIN")
      try query("PRAGMA user_version = 0")
      try query("COMMIT")
    } catch {
      Reticulum.log(
        "Known destinations database version migration failed: \(error)", level: .critical)
      Reticulum.log(
        "You will need to remove the known_destinations.db* files from your storage directory "
          + "so it can be rebuilt", level: .critical)
    }
  }

  // MARK: - Reading

  /// Every known destination (`Storage.py:426-431`).
  public func loadAll() throws -> [Data: Row] {
    lock.lock()
    defer { lock.unlock() }
    var rows: [Data: Row] = [:]
    for r in try query(
      "SELECT destination_hash, last_heard, packet_hash, public_key, app_data, used, stamp, "
        + "stamp_value, lr_cost FROM known_destinations")
    {
      guard let hash = r[0] as? Data, let publicKey = r[3] as? Data else { continue }
      rows[hash] = Row(
        lastHeard: Self.double(r[1]) ?? 0, packetHash: r[2] as? Data, publicKey: publicKey,
        appData: r[4] as? Data, used: Self.double(r[5]) ?? 0, stamp: r[6] as? Data,
        stampValue: Self.double(r[7]), lrCost: Self.double(r[8]))
    }
    written = rows
    return rows
  }

  /// Every stored ratchet (`Storage.py:490-495`).
  public func loadRatchets() throws -> [Data: Ratchet] {
    lock.lock()
    defer { lock.unlock() }
    var ratchets: [Data: Ratchet] = [:]
    for r in try query("SELECT destination_hash, ratchet, received FROM ratchets") {
      guard let hash = r[0] as? Data, let ratchet = r[1] as? Data else { continue }
      ratchets[hash] = Ratchet(ratchet: ratchet, received: Self.double(r[2]) ?? 0)
    }
    writtenRatchets = ratchets
    return ratchets
  }

  /// The stored ratchet for `destinationHash` (`Storage.py:455-465`).
  public func fetchRatchet(_ destinationHash: Data) throws -> Ratchet? {
    lock.lock()
    defer { lock.unlock() }
    guard
      let r = try query(
        "SELECT ratchet, received FROM ratchets WHERE destination_hash=?", [destinationHash]
      ).first, let ratchet = r[0] as? Data
    else { return nil }
    return Ratchet(ratchet: ratchet, received: Self.double(r[1]) ?? 0)
  }

  // MARK: - Writing

  /// Writes what changed since the last flush or load.
  ///
  /// One transaction, as `Storage.py:363-412` uses. A ratchet is kept only for a destination
  /// in `rows`.
  ///
  /// On failure nothing is recorded as written, so the next flush retries the whole difference,
  /// as Python re-marks the rows dirty.
  @discardableResult
  public func flush(_ rows: [Data: Row], ratchets: [Data: Ratchet]) throws -> Int {
    lock.lock()
    defer { lock.unlock() }
    let upserts = rows.filter { written[$0.key] != $0.value }
    let deletes = written.keys.filter { rows[$0] == nil }
    let kept = ratchets.filter { rows[$0.key] != nil }
    let ratchetUpserts = kept.filter { writtenRatchets[$0.key] != $0.value }
    let ratchetDeletes = writtenRatchets.keys.filter { kept[$0] == nil }
    let count = upserts.count + deletes.count + ratchetUpserts.count + ratchetDeletes.count
    guard count > 0 else { return 0 }

    try query("BEGIN")
    do {
      for (hash, row) in upserts {
        try query(
          "INSERT INTO known_destinations (destination_hash, last_heard, packet_hash, "
            + "public_key, app_data, used, stamp, stamp_value, lr_cost, identity_hash) "
            + "VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(destination_hash) DO UPDATE SET "
            + "last_heard=excluded.last_heard, packet_hash=excluded.packet_hash, "
            + "public_key=excluded.public_key, app_data=excluded.app_data, used=excluded.used, "
            + "stamp=excluded.stamp, stamp_value=excluded.stamp_value, "
            + "lr_cost=excluded.lr_cost, identity_hash=excluded.identity_hash",
          Self.parameters(hash, row))
      }
      for hash in deletes {
        try query("DELETE FROM known_destinations WHERE destination_hash=?", [hash])
      }
      for (hash, entry) in ratchetUpserts {
        try query(
          "INSERT INTO ratchets VALUES (?,?,?) ON CONFLICT(destination_hash) DO UPDATE SET "
            + "ratchet=excluded.ratchet, received=excluded.received",
          [hash, entry.ratchet, entry.received])
      }
      for hash in ratchetDeletes {
        try query("DELETE FROM ratchets WHERE destination_hash=?", [hash])
      }
      try query("COMMIT")
    } catch {
      _ = try? query("ROLLBACK")
      throw error
    }
    // shortcut: no per-row quarantine (`Storage.py:313-343`); every Row field is typed, so
    // only a disk or lock fault can fail a write, and that fails the whole flush instead.
    written = rows
    writtenRatchets = kept
    return count
  }

  /// Imports a legacy `known_destinations` msgpack file (`Storage.py:528-547`).
  public func importLegacy(from url: URL) throws -> Int {
    guard case .map(let pairs) = try MsgPack.decode(Data(contentsOf: url)) else {
      throw MsgPack.Error.typeMismatch
    }
    let now = Date().timeIntervalSince1970
    var rows: [(Data, Row)] = []
    for (key, value) in pairs {
      guard case .bytes(let hash) = key, case .array(let entry) = value, entry.count >= 5,
        var row = Row(entry: entry)
      else { continue }
      if row.lastHeard <= 0 { row.lastHeard = now }
      rows.append((hash, row))
    }
    lock.lock()
    defer { lock.unlock() }
    try query("BEGIN")
    do {
      for (hash, row) in rows {
        try query(
          "INSERT OR REPLACE INTO known_destinations (destination_hash, last_heard, "
            + "packet_hash, public_key, app_data, used, stamp, stamp_value, lr_cost, "
            + "identity_hash) VALUES (?,?,?,?,?,?,?,?,?,?)", Self.parameters(hash, row))
      }
      try query("COMMIT")
    } catch {
      _ = try? query("ROLLBACK")
      throw error
    }
    return rows.count
  }

  /// Imports the legacy per-destination ratchet files in `directory` and removes every one
  /// of them, imported or not (`Storage.py:497-526`).
  public func importLegacyRatchets(from directory: URL, cutoff: Double, known: Set<Data>)
    -> Int
  {
    let manager = FileManager.default
    var imported: [Data: Ratchet] = [:]
    for filename in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? [] {
      let url = directory.appendingPathComponent(filename)
      var isDirectory: ObjCBool = false
      guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
      else { continue }
      do {
        guard case .map(let pairs) = try MsgPack.decode(Data(contentsOf: url)),
          let hash = Data(hex: filename)
        else { throw Error(description: "Invalid ratchet file") }
        let fields = Dictionary(
          pairs.compactMap { k, v in k.asString.map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        guard let ratchet = fields["ratchet"]?.asData, let received = fields["received"]?.asDouble
        else { throw Error(description: "Invalid ratchet file") }
        if ratchet.count != Constants.ratchetSize {
          throw Error(description: "Invalid ratchet width")
        }
        if received < cutoff { throw Error(description: "Ratchet expired") }
        if !known.contains(hash) { throw Error(description: "Destination unknown") }
        imported[hash] = Ratchet(ratchet: ratchet, received: received)
      } catch {
        Reticulum.log("Could not import ratchet for \(filename): \(error)", level: .warning)
      }
      try? manager.removeItem(at: url)
    }
    lock.lock()
    defer { lock.unlock() }
    for (hash, entry) in imported {
      _ = try? query(
        "INSERT INTO ratchets VALUES (?,?,?) ON CONFLICT(destination_hash) DO UPDATE SET "
          + "ratchet=excluded.ratchet, received=excluded.received",
        [hash, entry.ratchet, entry.received])
    }
    return imported.count
  }

  // MARK: - SQLite

  private static func parameters(_ hash: Data, _ row: Row) -> [Any?] {
    [
      hash, row.lastHeard, row.packetHash, row.publicKey, row.appData, row.used, row.stamp,
      row.stampValue, row.lrCost, Hashes.truncatedHash(row.publicKey),
    ]
  }

  private static func double(_ value: Any?) -> Double? {
    (value as? Double) ?? (value as? Int64).map(Double.init)
  }

  private func failure() -> Error {
    Error(description: db.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory")
  }

  /// Runs one statement and returns its rows: a BLOB as `Data`, an INTEGER as `Int64`, a
  /// REAL as `Double`, TEXT as `String` and NULL as nil.
  @discardableResult
  func query(_ sql: String, _ parameters: [Any?] = []) throws -> [[Any?]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (offset, parameter) in parameters.enumerated() {
      let index = Int32(offset + 1)
      switch parameter {
      case let data as Data where data.isEmpty:
        sqlite3_bind_zeroblob(statement, index, 0)
      case let data as Data:
        _ = data.withUnsafeBytes {
          sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient)
        }
      case let number as Double:
        sqlite3_bind_double(statement, index, number)
      default:
        sqlite3_bind_null(statement, index)
      }
    }
    var rows: [[Any?]] = []
    while true {
      let rc = sqlite3_step(statement)
      if rc == SQLITE_DONE { break }
      guard rc == SQLITE_ROW else { throw failure() }
      rows.append(
        (0..<sqlite3_column_count(statement)).map { column -> Any? in
          switch sqlite3_column_type(statement, column) {
          case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count > 0, let bytes = sqlite3_column_blob(statement, column) else {
              return Data()
            }
            return Data(bytes: bytes, count: count)
          case SQLITE_INTEGER: return sqlite3_column_int64(statement, column)
          case SQLITE_FLOAT: return sqlite3_column_double(statement, column)
          case SQLITE_TEXT: return String(cString: sqlite3_column_text(statement, column))
          default: return nil
          }
        })
    }
    return rows
  }
}
