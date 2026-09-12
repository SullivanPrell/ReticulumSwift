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

/// Errors raised by the KISS TNC interface.
public enum KISSInterfaceError: Error {
  case portNotFound(String)
  case portOpenFailed(String)
  case configWriteError(String)
}

// MARK: - KISSInterface

/// KISS TNC interface over a serial port.
///
/// Wire-compatible with Python `RNS/Interfaces/KISSInterface.py`.
/// Supports optional flow-control (CMD_READY handshake) and beacon transmission.
///
/// Like `SerialInterface`, the physical serial port is injected via
/// `SerialPortTransport` so the interface is unit-testable without hardware.
public final class KISSInterface: Interface {
  /// Per-interface mutable configuration (mode, announce rate control, ingress/egress
  /// control, the `ic_*` tunables).
  ///
  /// One stored property satisfies the whole settable set;
  /// see `InterfaceState` and `swift_devel/bugs/025-*.md`.
  public let interfaceState = InterfaceState()

  /// Mirrors Python's `Interface.announces_to_internal` (RNS 1.4.1).
  public var announcesToInternal: Bool? = nil
  /// Mirrors Python's `Interface.gravity` (RNS 1.4.1).
  public var gravity: Int = InterfaceMode.defaultGravity

  // MARK: - Class constants

  /// Assumed bitrate when the TNC reports none.
  ///
  /// Python: `BITRATE_GUESS = 1200`
  public static let bitrateGuess: Int = 1_200

  /// Default IFAC authentication field size in bytes.
  ///
  /// Python: `DEFAULT_IFAC_SIZE = 8`
  public static let defaultIfacSize: Int = 8

  /// Hardware maximum transmission unit in bytes.
  ///
  /// Python: `self.HW_MTU = 564`
  public static let hwMtuConstant: Int = 564

  // MARK: - Interface protocol properties

  /// Interface name as it appears in configuration and status output.
  public let name: String
  /// Nominal interface bitrate in bits per second.
  public var bitrate: Int = KISSInterface.bitrateGuess
  private let onlineFlag = LockedFlag(false)
  /// Whether the interface is up and able to carry traffic.
  public private(set) var isOnline: Bool {
    get { onlineFlag.value }
    set { onlineFlag.value = newValue }
  }

  /// Lock-guarded—written from this interface's I/O queue while the UI
  /// and status reporting read from another thread.
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

  /// Hardware maximum transmission unit in bytes, or `nil` when unconstrained.
  public var hwMtu: Int? { KISSInterface.hwMtuConstant }

  /// Called with each packet decoded from an inbound frame.
  public var inboundHandler: ((Packet, any Interface) -> Void)? = nil
  /// Called with each inbound frame, before packet decoding.
  public var rawInboundHandler: ((Data, any Interface) -> Void)? = nil

  /// Identity authenticating this interface under IFAC, or `nil` when IFAC is off.
  public var ifacIdentity: Identity? = nil
  /// Derived IFAC key used to sign and verify frames.
  public var ifacKey: Data? = nil
  /// IFAC authentication field size in bytes.
  public var ifacSize: Int = KISSInterface.defaultIfacSize

  /// Whether the interface asks Transport to establish a tunnel over it.
  public var wantsTunnel: Bool = false
  /// Identifier of the transport tunnel established over this interface.
  public var tunnelID: Data? = nil

  // MARK: - Serial configuration

  /// Serial device path the TNC is attached to.
  public let port: String
  /// Serial line speed in baud.
  public let speed: Int
  /// Number of data bits per character.
  public let dataBits: Int
  /// Serial parity setting.
  public let parity: SerialParity
  /// Number of stop bits per character.
  public let stopBits: Int

  // MARK: - KISS configuration (Python defaults)

  /// Preamble in milliseconds.
  ///
  /// Python default: `350`.
  public var preamble: Int = 350
  /// TX tail in milliseconds.
  ///
  /// Python default: `20`.
  public var txtail: Int = 20
  /// Persistence (0–255).
  ///
  /// Python default: `64`.
  public var persistence: Int = 64
  /// Slot time in milliseconds.
  ///
  /// Python default: `20`.
  public var slottime: Int = 20
  /// Whether to use hardware flow control (CMD_READY handshake).
  public var flowControl: Bool = false

  // MARK: - Beacon configuration

  /// Seconds between beacon transmissions (nil = disabled).
  public var beaconInterval: TimeInterval? = nil
  /// Raw bytes sent as beacon payload.
  public var beaconData: Data = Data()

  // MARK: - Flow control state

  /// True when the TNC is ready to accept the next frame.
  ///
  /// Set to false after sending when `flowControl = true`; restored on CMD_READY.
  public private(set) var interfaceReady: Bool = false

  // MARK: - Packet queue (used when flowControl=true and TNC is busy)

  private var packetQueue: [Data] = []

  // MARK: - Private

  private let transport: SerialPortTransport
  private let decoder = KISS.FrameDecoder()
  private let lock = NSLock()

  // MARK: - Init

  /// Creates a KISS interface on a serial-attached TNC.
  public init(
    name: String,
    port: String,
    speed: Int = 9600,
    dataBits: Int = 8,
    parity: SerialParity = .none,
    stopBits: Int = 1,
    preamble: Int = 350,
    txtail: Int = 20,
    persistence: Int = 64,
    slottime: Int = 20,
    flowControl: Bool = false,
    beaconInterval: TimeInterval? = nil,
    beaconData: String = "",
    transport: SerialPortTransport
  ) {
    self.name = name
    self.port = port
    self.speed = speed
    self.dataBits = dataBits
    self.parity = parity
    self.stopBits = stopBits
    self.preamble = preamble
    self.txtail = txtail
    self.persistence = persistence
    self.slottime = slottime
    self.flowControl = flowControl
    self.beaconInterval = beaconInterval
    self.beaconData = Data(beaconData.utf8)
    self.transport = transport
  }

  /// Convenience init that parses parity from an INI config string ("N", "E", "O").
  ///
  /// Use `SerialParity(string:)` at the call site when parsing config files.
  public convenience init(
    name: String,
    port: String,
    speed: Int = 9600,
    dataBits: Int = 8,
    parityString: String,
    stopBits: Int = 1,
    preamble: Int = 350,
    txtail: Int = 20,
    persistence: Int = 64,
    slottime: Int = 20,
    flowControl: Bool = false,
    beaconInterval: TimeInterval? = nil,
    beaconData: String = "",
    transport: SerialPortTransport
  ) {
    self.init(
      name: name, port: port,
      speed: speed, dataBits: dataBits,
      parity: SerialParity(string: parityString), stopBits: stopBits,
      preamble: preamble, txtail: txtail,
      persistence: persistence, slottime: slottime,
      flowControl: flowControl,
      beaconInterval: beaconInterval, beaconData: beaconData,
      transport: transport)
  }

  // MARK: - Interface lifecycle

  /// Seconds between redial attempts after device loss.
  ///
  /// Python's reconnect loop hardcodes
  /// `time.sleep(5)` (`KISSInterface.py:373`).
  public var reconnectWait: TimeInterval = 5.0
  private let reconnector = TransportReconnector()

  /// Open the serial port, configure the KISS TNC, and bring the interface online.
  public func start() throws {
    transport.onTransportError = { [weak self] error in self?.handleTransportLoss(error) }
    try transport.open(
      port: port, baudRate: speed,
      dataBits: dataBits, parity: parity, stopBits: stopBits)
    transport.setReadCallback { [weak self] data in
      self?.feedBytes(data)
    }
    lock.lock()
    isOnline = true
    lock.unlock()
    sendKISSConfig()
    lock.lock()
    interfaceReady = true
    lock.unlock()
  }

  /// Take the interface offline and close the serial port.
  public func stop() {
    reconnector.cancel()
    transport.onTransportError = nil
    lock.lock()
    isOnline = false
    interfaceReady = false
    lock.unlock()
    transport.close()
  }

  /// Device loss → offline → redial until the TNC answers, re-running the whole `start()`
  /// (the KISS configuration must be resent to a re-powered TNC), as Python's read loop does
  /// when it raises into `reconnect_port` (`KISSInterface.py:365-380`).
  private func handleTransportLoss(_ error: Error) {
    Reticulum.log(
      "\(displayName) lost its serial device (\(error)) — reconnecting",
      level: .error)
    lock.lock()
    isOnline = false
    interfaceReady = false
    lock.unlock()
    reconnector.begin(wait: reconnectWait) { [weak self] in
      guard let self else { return true }
      try? self.start()
      return self.isOnline
    }
  }

  // MARK: - KISS TNC configuration commands

  /// Send all KISS configuration commands to the TNC.
  private func sendKISSConfig() {
    setPreamble(preamble)
    setTxTail(txtail)
    setPersistence(persistence)
    setSlotTime(slottime)
    setFlowControl(flowControl)
  }

  /// Sets the transmit delay ahead of each frame, in units of 10 ms.
  ///
  /// Python: `setPreamble(preamble)`—`FEND CMD_TXDELAY value FEND`
  public func setPreamble(_ preamble: Int) {
    var value = preamble / 10
    value = max(0, min(255, value))
    let cmd = Data([KISS.fend, KISS.cmdTxDelay, UInt8(value), KISS.fend])
    try? transport.write(cmd)
  }

  /// Sets the transmit tail after each frame, in units of 10 ms.
  ///
  /// Python: `setTxTail(txtail)`—`FEND CMD_TXTAIL value FEND`
  public func setTxTail(_ txtail: Int) {
    var value = txtail / 10
    value = max(0, min(255, value))
    let cmd = Data([KISS.fend, KISS.cmdTxTail, UInt8(value), KISS.fend])
    try? transport.write(cmd)
  }

  /// Sets the CSMA persistence parameter.
  ///
  /// Python: `setPersistence(persistence)`—`FEND CMD_P value FEND`
  public func setPersistence(_ persistence: Int) {
    let value = UInt8(max(0, min(255, persistence)))
    let cmd = Data([KISS.fend, KISS.cmdP, value, KISS.fend])
    try? transport.write(cmd)
  }

  /// Sets the CSMA slot time, in units of 10 ms.
  ///
  /// Python: `setSlotTime(slottime)`—`FEND CMD_SLOTTIME value FEND`
  public func setSlotTime(_ slottime: Int) {
    var value = slottime / 10
    value = max(0, min(255, value))
    let cmd = Data([KISS.fend, KISS.cmdSlotTime, UInt8(value), KISS.fend])
    try? transport.write(cmd)
  }

  /// Enables or disables hardware flow control on the TNC.
  ///
  /// Python: `setFlowControl(_)`—`FEND CMD_READY 0x01 FEND`
  public func setFlowControl(_ enabled: Bool) {
    let cmd = Data([KISS.fend, KISS.cmdReady, 0x01, KISS.fend])
    try? transport.write(cmd)
  }

  // MARK: - Outgoing

  /// Send a Reticulum packet.
  ///
  /// Called by Transport.
  ///
  /// Applies the IFAC mask (when an IFAC key is configured) before KISS
  /// framing, mirroring the central IFAC application in Python
  /// `Transport.transmit`. Without this, frames go out un-masked and
  /// IFAC-protected Python peers drop them.
  public func send(_ packet: Packet) throws {
    guard let raw = try? packet.pack() else { return }
    processOutgoing(wrapIfac(raw))
  }

  /// KISS-frame `data` and write to the TNC (or queue when not ready).
  ///
  /// Python: `process_outgoing(data)`
  public func processOutgoing(_ data: Data) {
    // Decide send-vs-enqueue atomically under `lock`: `interfaceReady` and
    // `packetQueue` are two halves of the same flow-control state, so the
    // read of `interfaceReady` and the enqueue must be one critical section
    // (otherwise the CMD_READY handler racing here loses packets or double-sends).
    lock.lock()
    guard isOnline else {
      lock.unlock()
      return
    }
    if interfaceReady {
      if flowControl {
        interfaceReady = false
      }
      lock.unlock()
      let framed = KISS.frame(data)
      // Counted only on success—a failed write isn't traffic (the failure reaches
      // `handleTransportLoss` through the transport's error callback).
      guard (try? transport.write(framed)) != nil else { return }
      counters.addTx(bytes: data.count)  // Python counts original (unframed) bytes
    } else {
      packetQueue.append(data)
      lock.unlock()
    }
  }

  /// Pop and send the first queued packet; mark TNC as ready.
  ///
  /// Python: `process_queue()`
  public func processQueue() {
    lock.lock()
    guard !packetQueue.isEmpty else {
      interfaceReady = true
      lock.unlock()
      return
    }
    let next = packetQueue.removeFirst()
    interfaceReady = true
    lock.unlock()
    processOutgoing(next)
  }

  // MARK: - Incoming

  /// Feed raw bytes from the serial port.
  ///
  /// KISS frames are decoded; `CMD_DATA` frames are delivered to the inbound
  /// handler; `CMD_READY` events trigger the outbound queue.
  public func feedBytes(_ data: Data) {
    let frames = decoder.feed(data)
    for (cmd, payload) in frames {
      if cmd == KISS.cmdData {
        counters.addRx(bytes: payload.count)
        rawInboundHandler?(payload, self)
      } else if cmd == KISS.cmdReady {
        processQueue()
      }
    }
  }

  // MARK: - Queue inspection (for tests)

  /// Number of packets queued (waiting for CMD_READY).
  public var queuedPacketCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return packetQueue.count
  }
}
