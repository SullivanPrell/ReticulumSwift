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

/// `PipeInterface` against `RNS/Interfaces/PipeInterface.py` (RNS 1.5.5).
final class PipeInterfaceTests: XCTestCase {

  /// A child process that exists only in memory.
  class FakeChild: PipeProcessTransport {
    var readHandler: ((Data) -> Void)?
    var terminationHandler: (() -> Void)?

    private let lock = NSLock()
    private var _spawned: [[String]] = []
    private var _written = Data()
    private var _kills = 0
    private var _spawnError: Error?

    var spawned: [[String]] { lock.withLock { _spawned } }
    var written: Data { lock.withLock { _written } }
    var kills: Int { lock.withLock { _kills } }
    var spawnError: Error? {
      get { lock.withLock { _spawnError } }
      set { lock.withLock { _spawnError = newValue } }
    }

    func spawn(arguments: [String]) throws {
      try lock.withLock {
        if let error = _spawnError { throw error }
        _spawned.append(arguments)
      }
    }

    func write(_ data: Data) throws -> Int {
      lock.withLock { _written.append(data) }
      return data.count
    }

    func kill() { lock.withLock { _kills += 1 } }

    /// The child writes `bytes` to its stdout.
    func emit(_ bytes: [UInt8]) { readHandler?(Data(bytes)) }

    /// The child exits.
    func exit() { terminationHandler?() }
  }

  struct SpawnFailure: Error {}

  private var savedHandler: ((String, Reticulum.LogLevel) -> Void)?
  private var savedLevel: Reticulum.LogLevel = .notice
  private let logLock = NSLock()
  private var logged: [(String, Reticulum.LogLevel)] = []

  override func setUp() {
    super.setUp()
    savedHandler = Reticulum.logHandler
    savedLevel = Reticulum.globalLogLevel
    Reticulum.globalLogLevel = .extreme
    Reticulum.logHandler = { [weak self] message, level in
      guard let self else { return }
      self.logLock.withLock { self.logged.append((message, level)) }
    }
  }

  override func tearDown() {
    Reticulum.logHandler = savedHandler
    Reticulum.globalLogLevel = savedLevel
    super.tearDown()
  }

  private func logs(at level: Reticulum.LogLevel) -> [String] {
    logLock.withLock { logged.filter { $0.1 == level }.map(\.0) }
  }

  private func waitUntil(
    _ condition: @escaping () -> Bool, timeout: TimeInterval = 3,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { usleep(5_000) }
    XCTAssertTrue(condition(), "timed out", file: file, line: line)
  }

  private func makePipe(
    command: String = "nc -U /tmp/rns.sock", respawnDelay: TimeInterval = 5,
    child: FakeChild = FakeChild()
  ) -> PipeInterface {
    PipeInterface(name: "Pipes", command: command, respawnDelay: respawnDelay, transport: child)
  }

  // MARK: - Constants and names

  func testTheConstantsMatchTheReference() {
    let pipe = makePipe()
    XCTAssertEqual(pipe.hwMtu, 1064, "PipeInterface.py:76")
    XCTAssertEqual(pipe.bitrate, 1_000_000, "BITRATE_GUESS, PipeInterface.py:56")
    XCTAssertEqual(pipe.ifacSize, 8, "DEFAULT_IFAC_SIZE, PipeInterface.py:57")
    XCTAssertEqual(PipeInterface.maxChunk, 32768, "MAX_CHUNK, PipeInterface.py:55")
    XCTAssertEqual(PipeInterface.defaultRespawnDelay, 5, "PipeInterface.py:73-74")
  }

  func testTheNamesMatchTheReference() {
    let pipe = makePipe()
    XCTAssertEqual(pipe.displayName, "PipeInterface[Pipes]", "PipeInterface.py:206-207")
    XCTAssertEqual(pipe.statsTypeName, "PipeInterface", "type(interface).__name__")
  }

  // MARK: - Spawning

  func testStartSplitsTheCommandAsShlexDoes() throws {
    let child = FakeChild()
    let pipe = makePipe(command: #"socat - 'UNIX-CONNECT:/tmp/a b' "-v""#, child: child)
    try pipe.start()
    XCTAssertEqual(child.spawned, [["socat", "-", "UNIX-CONNECT:/tmp/a b", "-v"]])
    XCTAssertTrue(pipe.isOnline)
    XCTAssertEqual(
      logs(at: .verbose),
      [
        "Connecting subprocess pipe for PipeInterface[Pipes]...",
        "Subprocess pipe for PipeInterface[Pipes] is now connected",
      ], "PipeInterface.py:103, :119")
  }

  func testACommandShlexCannotSplitFailsTheStart() {
    let child = FakeChild()
    let pipe = makePipe(command: "cat 'unterminated", child: child)
    XCTAssertThrowsError(try pipe.start(), "shlex.split raises ValueError")
    XCTAssertTrue(child.spawned.isEmpty)
    XCTAssertFalse(pipe.isOnline)
    XCTAssertEqual(logs(at: .error), ["Could connect pipe for interface PipeInterface[Pipes]"])
  }

  func testAChildThatWontSpawnFailsTheStart() {
    let child = FakeChild()
    child.spawnError = SpawnFailure()
    let pipe = makePipe(child: child)
    XCTAssertThrowsError(try pipe.start(), "PipeInterface.py:92-94 re-raises")
    XCTAssertFalse(pipe.isOnline)
    XCTAssertEqual(
      logs(at: .error), ["Could connect pipe for interface PipeInterface[Pipes]"],
      "PipeInterface.py:93")
  }

  // MARK: - Outgoing

  func testSendingWritesAnHDLCFrameToTheChild() throws {
    let child = FakeChild()
    let pipe = makePipe(child: child)
    try pipe.start()
    try pipe.processOutgoing(Data([0x01, 0x7E, 0x02, 0x7D, 0x03]))
    XCTAssertEqual(
      child.written, Data([0x7E, 0x01, 0x7D, 0x5E, 0x02, 0x7D, 0x5D, 0x03, 0x7E]),
      "PipeInterface.py:130")
    XCTAssertEqual(pipe.txBytes, 9, "txb counts the framed bytes, PipeInterface.py:133")
  }

  func testNothingIsWrittenWhileOffline() throws {
    let child = FakeChild()
    let pipe = makePipe(child: child)
    try pipe.processOutgoing(Data([0x01]))
    XCTAssertTrue(child.written.isEmpty, "PipeInterface.py:129")
    XCTAssertEqual(pipe.txBytes, 0)
  }

  func testAShortWriteIsCountedThenRaised() throws {
    final class ShortChild: FakeChild {
      override func write(_ data: Data) throws -> Int { data.count - 1 }
    }
    let pipe = makePipe(child: ShortChild())
    try pipe.start()
    XCTAssertThrowsError(
      try pipe.processOutgoing(Data([0x01, 0x02])), "IOError, PipeInterface.py:134-135")
    XCTAssertEqual(pipe.txBytes, 4, "txb grows before the check, PipeInterface.py:133")
  }

  func testAFailedWriteIsNotCounted() throws {
    final class BrokenChild: FakeChild {
      override func write(_ data: Data) throws -> Int { throw SpawnFailure() }
    }
    let pipe = makePipe(child: BrokenChild())
    try pipe.start()
    XCTAssertThrowsError(try pipe.processOutgoing(Data([0x01, 0x02])))
    XCTAssertEqual(pipe.txBytes, 0, "stdin.write raises before txb grows")
  }

  // MARK: - Incoming

  func testFramesFromTheChildReachTransportUnescaped() throws {
    let child = FakeChild()
    let pipe = makePipe(child: child)
    var frames: [Data] = []
    pipe.rawInboundHandler = { frame, _ in frames.append(frame) }
    try pipe.start()
    child.emit([0x7E, 0x01, 0x7D, 0x5E, 0x02])
    child.emit([0x7D, 0x5D, 0x03, 0x7E])
    XCTAssertEqual(frames, [Data([0x01, 0x7E, 0x02, 0x7D, 0x03])])
    XCTAssertEqual(pipe.rxBytes, 5, "rxb counts the unescaped bytes, PipeInterface.py:124")
  }

  func testAnEmptyFrameIsIgnored() throws {
    let child = FakeChild()
    let pipe = makePipe(child: child)
    var frames: [Data] = []
    pipe.rawInboundHandler = { frame, _ in frames.append(frame) }
    try pipe.start()
    child.emit([0x7E, 0x7E])
    XCTAssertTrue(frames.isEmpty, "RNS 1.5.5 guards empty keepalive frames, PipeInterface.py:123")
    XCTAssertEqual(pipe.rxBytes, 0)
  }

  // MARK: - Respawning

  func testAChildThatExitsIsRespawnedAfterTheDelay() throws {
    let child = FakeChild()
    let pipe = makePipe(respawnDelay: 0.2, child: child)
    try pipe.start()
    let exitedAt = Date()
    child.exit()
    XCTAssertFalse(pipe.isOnline, "PipeInterface.py:190")
    XCTAssertEqual(child.kills, 1, "PipeInterface.py:173")
    XCTAssertEqual(logs(at: .notice), ["Subprocess terminated on PipeInterface[Pipes]"])

    waitUntil { child.spawned.count == 2 && pipe.isOnline }
    XCTAssertGreaterThanOrEqual(
      Date().timeIntervalSince(exitedAt), 0.2, "sleeps respawn_delay first, PipeInterface.py:196")
    XCTAssertEqual(child.spawned[1], ["nc", "-U", "/tmp/rns.sock"])
    waitUntil { self.logs(at: .notice).contains("Reconnected pipe for PipeInterface[Pipes]") }
    XCTAssertTrue(
      logs(at: .verbose).contains("Attempting to respawn subprocess for PipeInterface[Pipes]..."),
      "PipeInterface.py:197")
    pipe.stop()
  }

  func testARespawnThatFailsIsRetried() throws {
    let child = FakeChild()
    let pipe = makePipe(respawnDelay: 0.05, child: child)
    try pipe.start()
    child.spawnError = SpawnFailure()
    child.exit()
    waitUntil {
      self.logs(at: .error).filter {
        $0.hasPrefix("Error while spawning subprocess, the contained exception was: ")
      }.count >= 2
    }
    XCTAssertFalse(pipe.isOnline)
    child.spawnError = nil
    waitUntil { pipe.isOnline }
    XCTAssertEqual(child.spawned.count, 2)
    pipe.stop()
  }

  func testStopKillsTheChildAndEndsRespawning() throws {
    let child = FakeChild()
    let pipe = makePipe(respawnDelay: 0.05, child: child)
    try pipe.start()
    pipe.stop()
    XCTAssertEqual(child.kills, 1)
    XCTAssertFalse(pipe.isOnline)
    child.exit()
    usleep(200_000)
    XCTAssertEqual(child.spawned.count, 1, "a stopped interface doesn't respawn its child")
    XCTAssertFalse(pipe.isOnline)
  }

  // MARK: - A real child process

  #if os(macOS)
    func testARealChildEchoesAFrameBack() throws {
      let pipe = PipeInterface(
        name: "Echo", command: "cat", respawnDelay: 5, transport: ProcessPipeTransport())
      let received = expectation(description: "frame")
      var frames: [Data] = []
      pipe.rawInboundHandler = { frame, _ in
        frames.append(frame)
        received.fulfill()
      }
      try pipe.start()
      defer { pipe.stop() }
      let payload = Data([0x01, 0x7E, 0x02, 0x7D, 0x03] + Array(repeating: 0x55, count: 400))
      try pipe.processOutgoing(payload)
      wait(for: [received], timeout: 5)
      XCTAssertEqual(frames, [payload])
    }

    func testABurstOfFramesFromManyThreadsComesBackWhole() throws {
      let pipe = PipeInterface(
        name: "Echo", command: "cat", respawnDelay: 5, transport: ProcessPipeTransport())
      let lock = NSLock()
      var frames: [Data] = []
      let all = expectation(description: "frames")
      all.expectedFulfillmentCount = 200
      pipe.rawInboundHandler = { frame, _ in
        lock.withLock { frames.append(frame) }
        all.fulfill()
      }
      try pipe.start()
      defer { pipe.stop() }
      let sent = (0..<200).map { i in Data((0..<450).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ i) }) }
      DispatchQueue.concurrentPerform(iterations: 4) { worker in
        for i in stride(from: worker, to: 200, by: 4) { try? pipe.processOutgoing(sent[i]) }
      }
      wait(for: [all], timeout: 10)
      XCTAssertEqual(Set(frames), Set(sent))
    }

    func testARealChildThatCannotBeFoundFailsTheStart() {
      let pipe = PipeInterface(
        name: "Missing", command: "no-such-command-\(UUID().uuidString)", respawnDelay: 5,
        transport: ProcessPipeTransport())
      XCTAssertThrowsError(try pipe.start(), "Popen raises FileNotFoundError")
      XCTAssertFalse(pipe.isOnline)
    }

    func testARealChildThatExitsIsReportedAndRespawned() throws {
      let pipe = PipeInterface(
        name: "Brief", command: "/usr/bin/true", respawnDelay: 0.1,
        transport: ProcessPipeTransport())
      try pipe.start()
      defer { pipe.stop() }
      waitUntil {
        self.logs(at: .notice).contains("Subprocess terminated on PipeInterface[Brief]")
          && self.logs(at: .verbose).contains(
            "Attempting to respawn subprocess for PipeInterface[Brief]...")
      }
    }
  #endif
}
