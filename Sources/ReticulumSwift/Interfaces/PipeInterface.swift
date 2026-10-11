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

// MARK: - Errors

/// Errors raised while starting or writing to a `PipeInterface` child process.
///
/// Each description is the text Python's exception prints, so the log lines read the same.
public enum PipeInterfaceError: Error, Equatable, CustomStringConvertible {
  /// `shlex.split` found an unterminated quote.
  case noClosingQuotation
  /// `shlex.split` found a trailing backslash.
  case noEscapedCharacter
  /// The command split into no words, so `Popen([])` raises `IndexError`.
  case emptyCommand
  /// `Popen` found no executable by this name.
  case notFound(String)
  /// `Popen` found the file but can't execute it.
  case permissionDenied(String)
  /// The child process isn't running.
  case notRunning
  /// The write to the child's standard input failed with this `errno`.
  case writeFailed(Int32)
  /// The child accepted fewer bytes than were written (`PipeInterface.py:134-135`).
  case shortWrite(written: Int, expected: Int)

  /// The text of the matching Python exception.
  public var description: String {
    switch self {
    case .noClosingQuotation: return "No closing quotation"
    case .noEscapedCharacter: return "No escaped character"
    case .emptyCommand: return "list index out of range"
    case .notFound(let program): return "[Errno 2] No such file or directory: '\(program)'"
    case .permissionDenied(let program): return "[Errno 13] Permission denied: '\(program)'"
    case .notRunning: return "I/O operation on closed file."
    case .writeFailed(let code): return "[Errno \(code)] \(String(cString: strerror(code)))"
    case .shortWrite(let written, let expected):
      return "Pipe interface only wrote \(written) bytes of \(expected)"
    }
  }
}

// MARK: - The child process

/// The child process a `PipeInterface` talks to, through its standard input and output.
///
/// `ProcessPipeTransport` is the real one, on macOS. Tests supply their own.
public protocol PipeProcessTransport: AnyObject {
  /// Called with the bytes the child writes to its standard output.
  var readHandler: ((Data) -> Void)? { get set }

  /// Called once the child's standard output closes, unless `kill()` ended the child first.
  var terminationHandler: (() -> Void)? { get set }

  /// Starts `arguments[0]` with the remaining words as its arguments.
  func spawn(arguments: [String]) throws

  /// Writes `data` to the child's standard input and returns the number of bytes written.
  @discardableResult func write(_ data: Data) throws -> Int

  /// Ends the child, if one is running.
  func kill()
}

// MARK: - PipeInterface

/// An interface that carries HDLC frames over a child process's standard input and output.
///
/// Wire-compatible with Python `RNS/Interfaces/PipeInterface.py`. The interface starts
/// `command`, writes each outgoing packet to the child's standard input as an HDLC frame,
/// and reads frames from its standard output. When the child exits, the interface waits
/// `respawnDelay` seconds and starts it again, for as long as the interface runs.
///
/// One deliberate difference: `stop()` kills the child. Python's `PipeInterface` has no
/// `detach()`, so a detached Python pipe leaves its child running and keeps delivering
/// what the child writes.
public final class PipeInterface: Interface {
  /// Per-interface mutable configuration (mode, announce rate control, ingress/egress
  /// control, the `ic_*` tunables).
  ///
  /// One stored property satisfies the whole settable set;
  /// see `InterfaceState` and `swift_devel/bugs/025-*.md`.
  public let interfaceState = InterfaceState()

  // MARK: - Class constants

  /// Maximum bytes read from the child in one call.
  ///
  /// Python: `MAX_CHUNK = 32768` (`PipeInterface.py:55`).
  public static let maxChunk: Int = 32_768

  /// Default bitrate estimate in bits per second.
  ///
  /// Python: `BITRATE_GUESS = 1*1000*1000` (`PipeInterface.py:56`).
  public static let bitrateGuess: Int = 1_000_000

  /// Default IFAC authentication field size in bytes.
  ///
  /// Python: `DEFAULT_IFAC_SIZE = 8` (`PipeInterface.py:57`).
  public static let defaultIfacSize: Int = 8

  /// Hardware maximum transmission unit in bytes.
  ///
  /// Python: `self.HW_MTU = 1064` (`PipeInterface.py:76`).
  public static let hwMtuConstant: Int = 1064

  /// Seconds between respawn attempts when the config gives none (`PipeInterface.py:73-74`).
  public static let defaultRespawnDelay: TimeInterval = 5

  // MARK: - Interface protocol properties

  /// Interface name as it appears in configuration and status output.
  public let name: String
  /// Nominal interface bitrate in bits per second.
  public var bitrate: Int = PipeInterface.bitrateGuess
  private let onlineFlag = LockedFlag(false)
  /// Whether the interface is up and able to carry traffic.
  public private(set) var isOnline: Bool {
    get { onlineFlag.value }
    set { onlineFlag.value = newValue }
  }

  /// Lock-guarded, because the child's reader thread and Transport both update it.
  ///
  /// See `InterfaceCounters`.
  private let counters = InterfaceCounters()
  /// Total bytes received on this interface.
  public var rxBytes: Int { counters.rxBytes }
  /// Total bytes transmitted on this interface.
  public var txBytes: Int { counters.txBytes }
  /// Total packets received on this interface.
  public var rxPackets: Int { counters.rxPackets }
  /// Total packets transmitted on this interface.
  public var txPackets: Int { counters.txPackets }

  /// Hardware maximum transmission unit in bytes.
  public var hwMtu: Int? { PipeInterface.hwMtuConstant }

  /// Called with each packet decoded from an inbound frame.
  public var inboundHandler: ((Packet, any Interface) -> Void)? = nil
  /// Called with each inbound frame, before packet decoding.
  public var rawInboundHandler: ((Data, any Interface) -> Void)? = nil

  /// Identity authenticating this interface under IFAC, or `nil` when IFAC is off.
  public var ifacIdentity: Identity? = nil
  /// Derived IFAC key used to sign and verify frames.
  public var ifacKey: Data? = nil
  /// IFAC authentication field size in bytes.
  public var ifacSize: Int = PipeInterface.defaultIfacSize

  /// Whether the interface asks Transport to establish a tunnel over it.
  public var wantsTunnel: Bool = false
  /// Identifier of the transport tunnel established over this interface.
  public var tunnelID: Data? = nil

  // MARK: - Pipe configuration

  /// The command line the interface runs, split into words as `shlex.split` does.
  public let command: String

  /// Seconds to wait before each attempt to start the child again.
  public let respawnDelay: TimeInterval

  // MARK: - Private

  private let transport: PipeProcessTransport
  private let decoder = HDLC.FrameDecoder()

  /// Serialises spawning, the child's termination and respawning, so a child that exits as it
  /// starts is handled after its spawn completes.
  private let lifecycle = DispatchQueue(label: "ReticulumSwift.PipeInterface.lifecycle")
  private let stateLock = NSLock()
  private var stopped = false
  private var generation = 0

  // MARK: - Init

  /// Creates a pipe interface.
  ///
  /// - Parameters:
  ///   - name: Interface name, for example `"Pipe"`.
  ///   - command: The command line to run.
  ///   - respawnDelay: Seconds to wait before starting an exited child again.
  ///   - transport: The child process to drive.
  public init(
    name: String, command: String,
    respawnDelay: TimeInterval = PipeInterface.defaultRespawnDelay,
    transport: PipeProcessTransport
  ) {
    self.name = name
    self.command = command
    self.respawnDelay = respawnDelay
    self.transport = transport
  }

  // MARK: - Interface lifecycle

  /// Start the child and bring the interface online.
  ///
  /// Python starts the child in `__init__` and re-raises a failure (`PipeInterface.py:90-94`),
  /// so a child that won't start throws here.
  public func start() throws {
    stateLock.withLock { stopped = false }
    transport.readHandler = { [weak self] data in self?.feedBytes(data) }
    transport.terminationHandler = { [weak self] in
      guard let self else { return }
      self.lifecycle.sync { self.childEnded() }
    }
    try lifecycle.sync {
      do {
        try openPipe()
      } catch {
        Reticulum.log("Could connect pipe for interface \(displayName)", level: .error)
        throw error
      }
      configurePipe()
    }
  }

  /// Kill the child and take the interface offline.
  public func stop() {
    stateLock.withLock {
      stopped = true
      generation += 1
    }
    transport.kill()
    isOnline = false
  }

  /// Python `open_pipe()` (`PipeInterface.py:102-109`).
  private func openPipe() throws {
    Reticulum.log("Connecting subprocess pipe for \(displayName)...", level: .verbose)
    let arguments: [String]
    do {
      arguments = try RNXShellWords.split(command)
    } catch RNXShellWords.ShellWordsError.noClosingQuotation {
      throw PipeInterfaceError.noClosingQuotation
    } catch {
      throw PipeInterfaceError.noEscapedCharacter
    }
    guard !arguments.isEmpty else { throw PipeInterfaceError.emptyCommand }
    decoder.reset()
    try transport.spawn(arguments: arguments)
  }

  /// Python `configure_pipe()` (`PipeInterface.py:112-119`).
  private func configurePipe() {
    isOnline = true
    Reticulum.log("Subprocess pipe for \(displayName) is now connected", level: .verbose)
  }

  /// The child's output closed: go offline and respawn it (`PipeInterface.py:168-190`).
  ///
  /// Python takes this branch when the child has exited by the time its output closes, and
  /// reports a pipe error when it hasn't. Both branches kill the child and respawn it.
  private func childEnded() {
    let current: Int? = stateLock.withLock { stopped ? nil : generation }
    guard let current else { return }
    Reticulum.log("Subprocess terminated on \(displayName)")
    transport.kill()
    isOnline = false
    scheduleRespawn(generation: current)
  }

  /// Python `reconnect_pipe()` (`PipeInterface.py:193-204`): sleep, then try again until the
  /// child starts.
  private func scheduleRespawn(generation expected: Int) {
    lifecycle.asyncAfter(deadline: .now() + respawnDelay) { [weak self] in
      guard let self else { return }
      let live = self.stateLock.withLock { !self.stopped && self.generation == expected }
      guard live else { return }
      do {
        Reticulum.log(
          "Attempting to respawn subprocess for \(self.displayName)...", level: .verbose)
        try self.openPipe()
        self.configurePipe()
        Reticulum.log("Reconnected pipe for \(self.displayName)")
      } catch {
        Reticulum.log(
          "Error while spawning subprocess, the contained exception was: \(error)",
          level: .error)
        self.scheduleRespawn(generation: expected)
      }
    }
  }

  // MARK: - Outgoing

  /// Send a Reticulum packet.
  ///
  /// Called by Transport.
  ///
  /// Applies the IFAC mask (when an IFAC key is configured) before framing,
  /// mirroring the central IFAC application in Python `Transport.transmit`.
  public func send(_ packet: Packet) throws {
    guard let raw = try? packet.pack() else { return }
    try processOutgoing(wrapIfac(raw))
  }

  /// HDLC-frame `data` and write it to the child's standard input.
  ///
  /// Python `process_outgoing(data)` (`PipeInterface.py:128-135`). The framed length counts
  /// as sent once the write returns, before the short-write check, as in Python.
  public func processOutgoing(_ data: Data) throws {
    guard isOnline else { return }
    let framed = HDLC.frame(data)
    let written = try transport.write(framed)
    counters.addTx(bytes: framed.count)
    if written != framed.count {
      throw PipeInterfaceError.shortWrite(written: written, expected: framed.count)
    }
  }

  // MARK: - Incoming

  /// Feed bytes the child wrote.
  ///
  /// Each complete, non-empty frame goes to `rawInboundHandler` (`PipeInterface.py:122-125`).
  public func feedBytes(_ data: Data) {
    let frames = decoder.feed(data, hwMtu: hwMtu, ifacSize: ifacSize)
    for frame in frames {
      counters.addRx(bytes: frame.count)
      rawInboundHandler?(frame, self)
    }
  }
}

// MARK: - The real child process

#if os(macOS)
/// A child process started with `Foundation.Process`, as Python's
/// `subprocess.Popen(shlex.split(command), stdin=PIPE, stdout=PIPE)` starts one.
///
/// The child's standard error stays the parent's, as `Popen` leaves it. A dedicated thread
/// reads the child's standard output. `Process` exists only on macOS.
public final class ProcessPipeTransport: PipeProcessTransport {
  /// Called with the bytes the child writes to its standard output.
  public var readHandler: ((Data) -> Void)?
  /// Called once the child's standard output closes, unless `kill()` ended the child first.
  public var terminationHandler: (() -> Void)?

  private let lock = NSLock()
  private let writeLock = NSLock()
  private var current: Process?
  private var stdinHandle: FileHandle?

  /// Creates a transport with no child running.
  public init() {}

  /// Starts `arguments[0]`, searching `PATH` for a bare name as `execvp` does.
  public func spawn(arguments: [String]) throws {
    guard let program = arguments.first else { throw PipeInterfaceError.emptyCommand }
    let process = Process()
    process.executableURL = try Self.resolve(program)
    process.arguments = Array(arguments.dropFirst())
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    // A child that stops reading would otherwise raise SIGPIPE in this process, where
    // Python ignores the signal and the write raises instead.
    _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    try process.run()
    try? output.fileHandleForWriting.close()
    try? input.fileHandleForReading.close()
    lock.withLock {
      current = process
      stdinHandle = input.fileHandleForWriting
    }
    let reader = output.fileHandleForReading
    let thread = Thread { [weak self] in self?.readLoop(reader, process: process) }
    thread.name = "ReticulumSwift.PipeInterface.read"
    thread.start()
  }

  /// Writes all of `data`, as `stdin.write` followed by `flush()` does.
  public func write(_ data: Data) throws -> Int {
    guard let handle = lock.withLock({ stdinHandle }) else {
      throw PipeInterfaceError.notRunning
    }
    return try writeLock.withLock {
      try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
        guard let base = buffer.baseAddress else { return 0 }
        var offset = 0
        while offset < buffer.count {
          let n = Darwin.write(handle.fileDescriptor, base + offset, buffer.count - offset)
          if n < 0 {
            if errno == EINTR { continue }
            throw PipeInterfaceError.writeFailed(errno)
          }
          offset += n
        }
        return offset
      }
    }
  }

  /// Sends the child `SIGKILL`, as Python's `Popen.kill()` does.
  public func kill() {
    let (process, handle) = lock.withLock { () -> (Process?, FileHandle?) in
      defer {
        current = nil
        stdinHandle = nil
      }
      return (current, stdinHandle)
    }
    try? handle?.close()
    guard let process, process.isRunning else { return }
    _ = Darwin.kill(process.processIdentifier, SIGKILL)
  }

  private func readLoop(_ handle: FileHandle, process: Process) {
    let fd = handle.fileDescriptor
    var buffer = [UInt8](repeating: 0, count: PipeInterface.maxChunk)
    while true {
      let n = read(fd, &buffer, buffer.count)
      if n > 0 {
        readHandler?(Data(buffer[0..<n]))
      } else if n < 0 && errno == EINTR {
        continue
      } else {
        break
      }
    }
    try? handle.close()
    let isCurrent = lock.withLock { current === process }
    if isCurrent { terminationHandler?() }
  }

  /// Resolves `program` as `execvp` does.
  ///
  /// A name with a slash is used as given, and a bare name is searched for along `PATH`.
  static func resolve(_ program: String) throws -> URL {
    let fileManager = FileManager.default
    if program.contains("/") {
      guard fileManager.fileExists(atPath: program) else {
        throw PipeInterfaceError.notFound(program)
      }
      guard fileManager.isExecutableFile(atPath: program) else {
        throw PipeInterfaceError.permissionDenied(program)
      }
      return URL(fileURLWithPath: program)
    }
    let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    for directory in path.split(separator: ":", omittingEmptySubsequences: false) {
      let candidate = (directory.isEmpty ? "." : String(directory)) + "/" + program
      if fileManager.isExecutableFile(atPath: candidate) {
        return URL(fileURLWithPath: candidate)
      }
    }
    throw PipeInterfaceError.notFound(program)
  }
}
#endif
