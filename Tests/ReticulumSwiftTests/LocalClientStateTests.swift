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

/// The persisted transport state in a shared config directory belongs to the shared instance.
///
/// A local client reads none of the transport tables and writes none of the state files.
/// Python decides the role before `Transport.start` (`Reticulum.py:754` → `:399-458`, then
/// `:353`), and every load and save of that state is guarded on it:
///
/// | File | Load | Save |
/// |---|---|---|
/// | `destination_table` | `Transport.py:404,408` | `:3789`, `:3980` |
/// | `tunnels` | `:404,462` | `:3880`, `:3980` |
/// | `packet_hashlist.raw` | `:340` | `:3746-3747`, `:3980` |
/// | `known_destinations` | unguarded (`Reticulum.py:351`) | `Identity.py:179`, `:616` |
/// | `ratchets/<hash>` | unguarded (`Identity.py:485-497`) | `:420`; cleaned only at `Reticulum.py:352` |
/// | `cache/announces/<hash>` | unguarded | `Transport.py:2457`; cleaned only at `:3006` |
/// | `blackhole/local` | unguarded | through RPC in a client (`Reticulum.py:2017-2021`) |
/// | `discovery/` | n/a | `Reticulum.py:371-374` |
///
/// `bugs/063`.
final class LocalClientStateTests: XCTestCase {

  private var temporaryDirectories: [URL] = []
  private var connections: [InstanceConnection] = []

  override func tearDown() {
    for connection in connections { connection.stop() }
    connections = []
    for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
    temporaryDirectories = []
    super.tearDown()
  }

  // MARK: - Fixtures

  private func makeDirectory(_ prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    temporaryDirectories.append(directory)
    return directory
  }

  /// A config directory whose ports were free when the kernel assigned them.
  private func makeConfigDirectory(
    enableTransport: Bool, shareInstance: Bool = true, extra: String = ""
  ) throws -> (directory: URL, sharedPort: UInt16) {
    let sharedPort = try XCTUnwrap(kernelAssignedLoopbackPort())
    let controlPort = try XCTUnwrap(kernelAssignedLoopbackPort())
    let directory = try makeDirectory("clientstate")
    let text = """
      [reticulum]
      enable_transport = \(enableTransport ? "Yes" : "No")
      share_instance = \(shareInstance ? "Yes" : "No")
      shared_instance_port = \(sharedPort)
      instance_control_port = \(controlPort)
      \(extra)

      [logging]
      loglevel = 1

      [interfaces]
      """
    try text.write(
      to: StorageInventory.url(.config, in: directory), atomically: true, encoding: .utf8)
    try DaemonBootstrap.createStorageTree(DaemonBootstrap.Paths(configDir: directory))
    return (directory, sharedPort)
  }

  private func attach(_ directory: URL, requireSharedInstance: Bool = false) throws
    -> InstanceConnection
  {
    let connection = try InstanceConnection.attach(
      configDirectory: directory,
      requireSharedInstance: requireSharedInstance,
      synthesizeInterfaces: false)
    connections.append(connection)
    return connection
  }

  private struct SeededTables {
    let destinationHash: Data
    let tunnelID: Data
    let packetHash: Data
  }

  /// Writes a `destination_table` and a `tunnels` file each holding one entry through
  /// `interface`, with the announce in the cache, plus a one-entry `packet_hashlist.raw`.
  ///
  /// Every entry restores into a transport that has `interface` registered.
  private func seedTables(in storage: URL, through interface: any Interface) throws
    -> SeededTables
  {
    let writer = Transport()
    writer.cacheDirectory = StorageInventory.url(.cache, storage: storage)
    writer.register(interface: interface)
    let installed = try installPersistablePath(on: writer, through: interface, aspect: "owned")
    let tunnelPath = try installPersistablePath(
      on: writer, through: interface, aspect: "tunnelled")
    let tunnelID = Hashes.fullHash(Data("clientstate".utf8))
    writer.tunnels[tunnelID] = Transport.TunnelEntry(
      tunnelID: tunnelID,
      iface: interface,
      paths: [tunnelPath.destinationHash: writer.paths[tunnelPath.destinationHash]!],
      expires: Date().addingTimeInterval(Transport.tunnelTimeout))
    let packetHash = Hashes.fullHash(Data("clientstate-packet".utf8))
    writer.testInsertPacketHash(packetHash)

    try PathStore.snapshot(of: writer)
      .write(to: StorageInventory.url(.destinationTable, storage: storage))
    try TunnelStore.snapshot(of: writer)
      .write(to: StorageInventory.url(.tunnels, storage: storage))
    try writer.savePacketHashlist(to: StorageInventory.url(.packetHashlist, storage: storage))
    return SeededTables(
      destinationHash: installed.destinationHash, tunnelID: tunnelID, packetHash: packetHash)
  }

  /// Bytes no writer produces, at every state file a shared instance owns.
  private func writeSentinels(in storage: URL) throws -> [URL: Data] {
    let files: [URL] = [
      StorageInventory.url(.destinationTable, storage: storage),
      StorageInventory.url(.tunnels, storage: storage),
      StorageInventory.url(.knownDestinations, storage: storage),
      StorageInventory.url(.packetHashlist, storage: storage),
      StorageInventory.url(.blackholeLocal, storage: storage),
    ]
    var sentinels: [URL: Data] = [:]
    for file in files {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      let bytes = Data("sentinel \(file.lastPathComponent)".utf8)
      try bytes.write(to: file)
      sentinels[file] = bytes
    }
    return sentinels
  }

  private func assertUntouched(
    _ sentinels: [URL: Data], after step: String, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for (url, bytes) in sentinels {
      XCTAssertEqual(
        try? Data(contentsOf: url), bytes,
        "\(step) rewrote \(url.lastPathComponent)", file: file, line: line)
    }
  }

  // MARK: - Load side

  /// `Transport.py:404-408` and `:462`: the client restores neither table, so a destination
  /// the shared instance once knew is not a path in the client.
  func testALocalClientRestoresNoTransportTable() throws {
    let (directory, sharedPort) = try makeConfigDirectory(enableTransport: true)
    let storage = InstanceConnection.storagePath(for: directory)
    _ = try attach(directory)

    // Through an interface named as the client's, so an entry the client did read would
    // install as soon as the client registers it.
    let seeded = try seedTables(
      in: storage, through: LocalInterface(host: "127.0.0.1", port: sharedPort))

    let client = try attach(directory)
    XCTAssertEqual(client.role, .localClient)
    let transport = client.reticulum.transport

    XCTAssertNil(transport.paths[seeded.destinationHash], "Transport.py:408")
    XCTAssertTrue(
      transport.pendingPathRestores.isEmpty,
      "a parked entry would install when a matching interface registers")
    XCTAssertNil(transport.tunnels[seeded.tunnelID], "Transport.py:462")
    XCTAssertFalse(transport.testContainsPacketHash(seeded.packetHash), "Transport.py:340")
  }

  /// The shared instance still restores its tables through `attach` (`bugs/041`).
  func testTheSharedInstanceRestoresItsTransportTables() throws {
    let (directory, sharedPort) = try makeConfigDirectory(enableTransport: true)
    let storage = InstanceConnection.storagePath(for: directory)
    let seeded = try seedTables(
      in: storage, through: PosixTCPServer(name: "Shared Instance", port: sharedPort))

    let instance = try attach(directory)
    XCTAssertEqual(instance.role, .sharedInstance)
    let transport = instance.reticulum.transport

    XCTAssertNotNil(transport.paths[seeded.destinationHash])
    XCTAssertNotNil(transport.tunnels[seeded.tunnelID])
    XCTAssertTrue(transport.testContainsPacketHash(seeded.packetHash))
  }

  /// Python disables transport in a client before `Transport.start` chooses the transport
  /// identity (`Reticulum.py:440`, `Transport.py:332`), so the client runs behind an ephemeral
  /// one even when the shared config enables transport.
  func testALocalClientStartsWithTransportDisabled() throws {
    let (directory, _) = try makeConfigDirectory(enableTransport: true)
    let instance = try attach(directory)
    let persistent = try XCTUnwrap(instance.reticulum.transport.internalIdentity)

    let client = try attach(directory)
    XCTAssertFalse(client.reticulum.transport.transportEnabled)
    XCTAssertEqual(client.reticulum.transport.internalIdentity?.hash, persistent.hash)
    XCTAssertNotEqual(
      client.reticulum.transport.transportIdentity?.hash, persistent.hash,
      "Transport.py:332")
  }

  // MARK: - Save side

  /// `Transport.py:3980`, `:3789`, `:3880`, `:3746`; `Identity.py:179`, `:616`. A client also
  /// runs no persist job (`Reticulum.py:399-458` starts `__jobs` only for the other two roles).
  func testALocalClientWritesNoStateFile() throws {
    let (directory, _) = try makeConfigDirectory(enableTransport: true)
    let storage = InstanceConnection.storagePath(for: directory)
    _ = try attach(directory)
    let sentinels = try writeSentinels(in: storage)

    let client = try attach(directory)
    XCTAssertEqual(client.role, .localClient)
    client.reticulum.transport.restore(
      identity: Identity(), forDestination: Hashes.truncatedHash(Data("learned".utf8)))
    client.reticulum.transport.testInsertPacketHash(Hashes.fullHash(Data("seen".utf8)))

    try client.reticulum.checkpoint()
    assertUntouched(sentinels, after: "checkpoint()")
    DaemonBootstrap.persistState(of: client.reticulum)
    assertUntouched(sentinels, after: "DaemonBootstrap.persistState")
    client.stop()
    assertUntouched(sentinels, after: "stop()")
  }

  /// Python raises before `Transport.start` when a shared instance was required and none is
  /// running (`Reticulum.py:411-414`, `:453-454`), so neither the tables nor the files are touched.
  func testAUtilityThatFindsNoSharedInstanceTouchesNoStateFile() throws {
    let (directory, _) = try makeConfigDirectory(enableTransport: true)
    let storage = InstanceConnection.storagePath(for: directory)
    let sentinels = try writeSentinels(in: storage)

    XCTAssertThrowsError(try attach(directory, requireSharedInstance: true)) { error in
      guard case InstanceConnection.InstanceError.noSharedInstance = error else {
        return XCTFail("expected noSharedInstance, got \(error)")
      }
    }
    assertUntouched(sentinels, after: "an aborted attach")
  }

  /// `Identity.py:420`: a client remembers the ratchet without writing it.
  func testALocalClientRemembersARatchetWithoutPersistingIt() throws {
    for client in [false, true] {
      let directory = try makeDirectory("clientratchet")
      let transport = Transport()
      transport.isConnectedToSharedInstance = client
      transport.ratchetsDirectory = directory

      let interface = LoopbackInterface(name: "ratchet")
      transport.register(interface: interface)
      let identity = Identity()
      let ratchet = identity.rotateRatchet()
      let destination = try Destination(
        identity: identity, direction: .in, kind: .single,
        appName: "clientstate", aspects: ["ratchet"])
      transport.handleIncoming(
        packet: try Announce.make(for: destination, ratchet: ratchet), from: interface)

      XCTAssertEqual(transport.knownRatchets[destination.hash], ratchet, "client: \(client)")
      XCTAssertEqual(
        FileManager.default.fileExists(
          atPath: directory.appendingPathComponent(destination.hash.hexString).path),
        !client, "client: \(client)")
    }
  }

  /// `Transport.py:2457`: a client installs the path without caching the announce.
  func testALocalClientCachesNoAnnounce() throws {
    for client in [false, true] {
      let directory = try makeDirectory("clientcache")
      let transport = Transport()
      transport.isConnectedToSharedInstance = client
      transport.cacheDirectory = directory

      let interface = LoopbackInterface(name: "cache")
      transport.register(interface: interface)
      let destination = try Destination(
        identity: Identity(), direction: .in, kind: .single,
        appName: "clientstate", aspects: ["cache"])
      let announce = try Announce.make(for: destination)
      transport.handleIncoming(packet: announce, from: interface)

      XCTAssertNotNil(transport.paths[destination.hash], "client: \(client)")
      let cached = directory
        .appendingPathComponent(StorageInventory.Entry.announceCache.fileName)
        .appendingPathComponent(Hashes.fullHash(try announce.hashablePart()).hexString)
      XCTAssertEqual(
        FileManager.default.fileExists(atPath: cached.path), !client, "client: \(client)")
    }
  }

  /// `Reticulum.py:352`: only a non-client cleans the ratchet directory. A client still reads
  /// what is valid, as `Identity.get_ratchet` does (`Identity.py:485-497`).
  func testALocalClientRemovesNoRatchetFile() throws {
    for client in [false, true] {
      let directory = try makeDirectory("clientratchetclean")
      let transport = Transport()
      transport.isConnectedToSharedInstance = client
      transport.ratchetsDirectory = directory
      let expired = directory.appendingPathComponent(
        Hashes.truncatedHash(Data("expired".utf8)).hexString)
      let received = Date().addingTimeInterval(-transport.ratchetExpiry - 60)
      try MsgPack.encode(
        .map([
          (.string("ratchet"), .bytes(Data(repeating: 1, count: Constants.ratchetSize))),
          (.string("received"), .double(received.timeIntervalSince1970)),
        ])
      ).write(to: expired)
      let corrupt = directory.appendingPathComponent(
        Hashes.truncatedHash(Data("corrupt".utf8)).hexString)
      try Data("not msgpack".utf8).write(to: corrupt)
      let validHash = Hashes.truncatedHash(Data("valid".utf8))
      let validRatchet = Data(repeating: 2, count: Constants.ratchetSize)
      try MsgPack.encode(
        .map([
          (.string("ratchet"), .bytes(validRatchet)),
          (.string("received"), .double(Date().timeIntervalSince1970)),
        ])
      ).write(to: directory.appendingPathComponent(validHash.hexString))

      transport.loadKnownRatchets()
      transport.sweepKnownRatchets()

      XCTAssertEqual(transport.knownRatchets[validHash], validRatchet, "client: \(client)")
      XCTAssertEqual(
        FileManager.default.fileExists(atPath: expired.path), client, "client: \(client)")
      XCTAssertEqual(
        FileManager.default.fileExists(atPath: corrupt.path), client, "client: \(client)")
    }
  }

  /// `Reticulum.py:371-374`: interface discovery, which writes `storage/discovery`, runs only
  /// in a shared or standalone instance.
  func testALocalClientRunsNoInterfaceDiscovery() throws {
    for client in [false, true] {
      let directory = try makeDirectory("clientdiscovery")
      try """
      [reticulum]
      enable_transport = No
      discover_interfaces = Yes

      [interfaces]
      """.write(
        to: StorageInventory.url(.config, in: directory), atomically: true, encoding: .utf8)
      var configuration = Reticulum.Configuration(
        storagePath: InstanceConnection.storagePath(for: directory),
        configPath: StorageInventory.url(.config, in: directory))
      configuration.discoveryStampValidator = AcceptingStampValidator()
      let reticulum = Reticulum(configuration: configuration)
      reticulum.transport.isConnectedToSharedInstance = client
      try reticulum.start()
      defer { reticulum.stop() }

      XCTAssertEqual(reticulum.transport.discoveryHandler == nil, client, "client: \(client)")
    }
  }

  // MARK: - Transport disabled

  /// `Transport.py:340` and `:404`: without transport, a standalone instance restores none of
  /// the three tables, and `:3747` keeps it from writing the packet hashlist.
  func testTheTransportTablesRestoreOnlyWithTransportEnabled() throws {
    for enableTransport in [true, false] {
      let (directory, _) = try makeConfigDirectory(
        enableTransport: enableTransport, shareInstance: false)
      let storage = InstanceConnection.storagePath(for: directory)
      let seeded = try seedTables(in: storage, through: LoopbackInterface(name: "eth0"))

      let standalone = try attach(directory)
      XCTAssertEqual(standalone.role, .standalone)
      let transport = standalone.reticulum.transport
      transport.register(interface: LoopbackInterface(name: "eth0"))

      let label = "enable_transport: \(enableTransport)"
      XCTAssertEqual(transport.paths[seeded.destinationHash] != nil, enableTransport, label)
      XCTAssertEqual(transport.tunnels[seeded.tunnelID] != nil, enableTransport, label)
      XCTAssertEqual(
        transport.testContainsPacketHash(seeded.packetHash), enableTransport, label)

      let hashlist = StorageInventory.url(.packetHashlist, storage: storage)
      let sentinel = Data("sentinel".utf8)
      try sentinel.write(to: hashlist)
      standalone.stop()
      connections.removeAll { $0 === standalone }
      XCTAssertEqual(try Data(contentsOf: hashlist) == sentinel, !enableTransport, label)
    }
  }
}

private final class AcceptingStampValidator: DiscoveryStampValidator {
  var stampSize: Int { 32 }
  func stampWorkblock(material: Data, expandRounds: Int) -> Data { Data(repeating: 0, count: 32) }
  func stampValue(workblock: Data, stamp: Data) -> Int { 255 }
  func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { true }
}
