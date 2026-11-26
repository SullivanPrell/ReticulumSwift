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
import Network

/// The **only** place in this package where socket options are constructed.
///
/// `bugs/023`. Python sets its socket options on every TCP socket it opens, in both directions:
/// the dialling branch at `TCPInterface.py:145-149` and the accepted-socket branch at `:241` and
/// `:259-261`, which is reached from `:591` where `TCPServerInterface` builds a client interface
/// out of the socket it just accepted. Direction doesn't decide whether the options apply.
///
/// The 1.7.0 release fixed the two dial paths and left `TCPServerInterface.start()` passing
/// `.tcp`—Network.framework's defaults, keepalive **off**—so a listening interface's accepted
/// connections couldn't notice a peer that vanished without sending FIN. It kept reporting Up
/// and discarding everything sent through it. The CHANGELOG claimed "every socket"; it was two of
/// four.
///
/// So the options live here and nowhere else, and `SocketOptionsTests` fails if any other file in
/// `Sources/` constructs an `NWProtocolTCP.Options`, an `NWParameters`, or opens a socket with a
/// stock `.tcp` parameter set. That structural check is the enforceable half: Network.framework
/// publishes no authoritative readback for TCP options—`NWParameters.defaultProtocolStack
/// .transportProtocol` is a *different* instance than the one handed to `NWParameters(tls:tcp:)`
/// and reports framework defaults on some OS versions—so "did this socket get keepalive?"
/// can't be asked of a live connection. What the port controls is which object it hands over.
enum RNSSocketOptions {

  // MARK: - Python's constants (`TCPInterface.py:83-86`)

  /// `TCP_KEEPIDLE`—idle seconds before the first probe.
  ///
  /// Python `TCP_PROBE_AFTER`.
  static let probeAfter: Int = 5
  /// `TCP_KEEPINTVL`—seconds between probes.
  ///
  /// Python `TCP_PROBE_INTERVAL`.
  static let probeInterval: Int = 2
  /// `TCP_KEEPCNT`—unanswered probes before the connection is dead.
  ///
  /// Python `TCP_PROBES`.
  static let probes: Int = 12
  /// `TCP_USER_TIMEOUT`—give up on unacknowledged data after this many seconds.
  ///
  /// Python
  /// `TCP_USER_TIMEOUT`; Network.framework spells it `connectionDropTime`.
  static let userTimeout: Int = 24

  /// The looser set Python uses for a socket carrying I2P-tunneled traffic
  /// (`TCPInterface.py:92-95`), selected by the `i2p_tunneled` flag at `:182` and `:204`.
  ///
  /// I2P
  /// round-trips are long enough that the direct-TCP timers would tear down a healthy tunnel.
  static let i2pProbeAfter: Int = 10
  static let i2pProbeInterval: Int = 9
  static let i2pProbes: Int = 5
  static let i2pUserTimeout: Int = 45

  // MARK: - Network.framework

  /// The full option set every Reticulum TCP socket carries: `TCP_NODELAY`, keepalive with
  /// Python's three timers, and the user timeout (`TCPInterface.py:145-149` dialling,
  /// `:241`/`:259-261` accepting).
  ///
  /// A fresh instance per call—`NWProtocolTCP.Options` is a reference type and one already
  /// handed to a live connection or listener can't be reused.
  static func tcpOptions() -> NWProtocolTCP.Options {
    let options = NWProtocolTCP.Options()
    // Python: `SO_KEEPALIVE, 1` + TCP_KEEPIDLE / TCP_KEEPINTVL / TCP_KEEPCNT.
    options.enableKeepalive = true
    options.keepaliveIdle = probeAfter
    options.keepaliveInterval = probeInterval
    options.keepaliveCount = probes
    options.connectionDropTime = userTimeout
    // Linux's TCP_USER_TIMEOUT also ends a peer that holds a zero window; Darwin needs the
    // persist timer for that, or every frame for a peer that stopped reading queues in memory.
    options.persistTimeout = userTimeout
    // RNS packets are small and latency-sensitive; Nagle would hold them behind the
    // delayed-ACK timer.
    options.noDelay = true
    return options
  }

  /// `TCP_NODELAY` only, with keepalive deliberately **off**—what Python's shared-instance
  /// interface sets, on its dial (`LocalInterface.py:147`) and on each socket its server
  /// accepts (`:100`). `LocalClientInterface` calls no `set_timeouts_*`; its only keepalive is
  /// the application-level `phy_keepalive` flag Python raises on Android, which isn't a
  /// socket option.
  ///
  /// Kept distinct from ``tcpOptions()`` rather than folded into it: enabling keepalive here
  /// would exceed the reference on a loopback socket, and the point of this type is that the
  /// option set is chosen deliberately at one place, not inherited by accident.
  static func localOptions() -> NWProtocolTCP.Options {
    let options = NWProtocolTCP.Options()
    options.noDelay = true
    return options
  }

  /// The option set for a socket carrying I2P-tunneled traffic—keepalive on, but with
  /// Python's I2P timers rather than its direct-TCP ones (`TCPInterface.py:190-194`, `:204-207`,
  /// reached because `I2PInterface` and `I2PInterfacePeer` both set `i2p_tunneled = True`,
  /// `I2PInterface.py:742`, `:356`).
  static func i2pOptions() -> NWProtocolTCP.Options {
    let options = NWProtocolTCP.Options()
    options.enableKeepalive = true
    options.keepaliveIdle = i2pProbeAfter
    options.keepaliveInterval = i2pProbeInterval
    options.keepaliveCount = i2pProbes
    options.connectionDropTime = i2pUserTimeout
    options.noDelay = true
    return options
  }

  /// Parameters carrying ``tcpOptions()``, plus the options instance they were built from.
  ///
  /// Both are returned because the options object is the only one whose values can be read
  /// back—see the type comment. A caller keeps `options` so a test can assert on the exact
  /// instance the framework was handed. A client passes `connectTimeout`, the socket timeout
  /// Python sets on every dial (`TCPInterface.py:241`, `BackboneInterface.py:976`).
  static func tcpParameters(connectTimeout: TimeInterval? = nil)
    -> (parameters: NWParameters, options: NWProtocolTCP.Options)
  {
    let options = tcpOptions()
    if let connectTimeout { options.connectionTimeout = Int(connectTimeout) }
    return (NWParameters(tls: nil, tcp: options), options)
  }

  /// Parameters carrying ``localOptions()``, plus the options instance they were built from.
  ///
  /// For `LocalInterface`'s dial, which Python opens with `TCP_NODELAY` and nothing else
  /// (`LocalInterface.py:139-140`).
  static func localParameters() -> (parameters: NWParameters, options: NWProtocolTCP.Options) {
    let options = localOptions()
    return (NWParameters(tls: nil, tcp: options), options)
  }

  /// A listener on `port` of `bindIP`, the address a Python server interface binds.
  ///
  /// Python's `TCPServerInterface` binds the address `listen_ip` resolves to
  /// (`TCPInterface.py:551`, `:567`, `:573`). `NWListener(using:on:)` binds every address, so any other
  /// address becomes a required local endpoint. A host name resolves first, to its IPv4 address
  /// where it has one (`TCPInterface.py:490-497`): `NWListener` given a name there listens on an
  /// arbitrary port.
  static func listener(using parameters: NWParameters, bindIP: String, port: NWEndpoint.Port)
    throws -> NWListener
  {
    if bindIP == "0.0.0.0" || bindIP == "::" { return try NWListener(using: parameters, on: port) }
    var hints = addrinfo()
    hints.ai_socktype = SOCK_STREAM
    var info: UnsafeMutablePointer<addrinfo>?
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    guard getaddrinfo(bindIP, nil, &hints, &info) == 0, let first = info else {
      throw NWError.posix(.EADDRNOTAVAIL)
    }
    defer { freeaddrinfo(info) }
    let entry =
      sequence(first: first) { $0.pointee.ai_next }.first { $0.pointee.ai_family == AF_INET }
      ?? first
    guard
      getnameinfo(
        entry.pointee.ai_addr, entry.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0,
        NI_NUMERICHOST) == 0
    else { throw NWError.posix(.EADDRNOTAVAIL) }
    parameters.requiredLocalEndpoint = .hostPort(
      host: NWEndpoint.Host(String(cString: host)), port: port)
    return try NWListener(using: parameters)
  }

  /// Parameters carrying ``i2pOptions()``, plus the options instance they were built from.
  static func i2pParameters() -> (parameters: NWParameters, options: NWProtocolTCP.Options) {
    let options = i2pOptions()
    return (NWParameters(tls: nil, tcp: options), options)
  }

  // MARK: - POSIX

  /// Apply the shared-instance option set to a raw file descriptor.
  ///
  /// `PosixTCPServer` binds and accepts with POSIX sockets rather than Network.framework, so it
  /// can't take an `NWParameters`. It's still a socket-opening site, and Python sets
  /// `TCP_NODELAY` on every socket its shared-instance server accepts
  /// (`LocalInterface.py:98-100`)—which this port didn't, on either the listening socket or
  /// the accepted ones. Found while building the factory; not in `bugs/023` as filed.
  ///
  /// Unlike the Network.framework paths this one *is* verifiable: `getsockopt` reads the value
  /// straight back, so `SocketOptionsTests` asserts the accepted descriptor's real state.
  /// Apply ``tcpOptions()``'s set to a raw descriptor: keepalive with Python's three timers,
  /// the user and persist timeouts and `TCP_NODELAY` (`TCPInterface.py:241`, `:259-261`).
  static func applyTCPOptions(toFileDescriptor fd: Int32) {
    func set(_ level: Int32, _ name: Int32, _ value: Int) {
      var value = Int32(value)
      setsockopt(fd, level, name, &value, socklen_t(MemoryLayout<Int32>.size))
    }
    set(SOL_SOCKET, SO_NOSIGPIPE, 1)
    set(SOL_SOCKET, SO_KEEPALIVE, 1)
    set(Int32(IPPROTO_TCP), TCP_KEEPALIVE, probeAfter)
    set(Int32(IPPROTO_TCP), TCP_KEEPINTVL, probeInterval)
    set(Int32(IPPROTO_TCP), TCP_KEEPCNT, probes)
    set(Int32(IPPROTO_TCP), TCP_RXT_CONNDROPTIME, userTimeout)
    set(Int32(IPPROTO_TCP), PERSIST_TIMEOUT, userTimeout)  // as `tcpOptions()`'s persistTimeout
    set(Int32(IPPROTO_TCP), TCP_NODELAY, 1)
  }

  /// A bind that failed, naming the address and port.
  struct ListenError: Error, CustomStringConvertible {
    let address: String
    let port: UInt16
    let code: Int32
    var description: String {
      "Could not bind \(address):\(port): [Errno \(code)] \(String(cString: strerror(code)))"
    }
  }

  /// A listening socket on `port` of `bindIP`, with `SO_REUSEADDR` as Python's
  /// `ThreadingTCPServer` sets it (`TCPInterface.py:518`).
  ///
  /// The address family is the resolved address's, IPv4 first where a name has both
  /// (`TCPInterface.py:490-497`), so `0.0.0.0` binds IPv4 only, as in Python.
  static func listeningSocket(bindIP: String, port: UInt16) throws -> Int32 {
    var hints = addrinfo()
    hints.ai_socktype = SOCK_STREAM
    hints.ai_flags = AI_PASSIVE
    var info: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(bindIP, String(port), &hints, &info) == 0, let first = info else {
      throw ListenError(address: bindIP, port: port, code: EADDRNOTAVAIL)
    }
    defer { freeaddrinfo(info) }
    let entry =
      sequence(first: first) { $0.pointee.ai_next }.first { $0.pointee.ai_family == AF_INET }
      ?? first
    let fd = socket(entry.pointee.ai_family, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ListenError(address: bindIP, port: port, code: errno) }
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
    guard Darwin.bind(fd, entry.pointee.ai_addr, entry.pointee.ai_addrlen) == 0,
      Darwin.listen(fd, 16) == 0
    else {
      let code = errno
      Darwin.close(fd)
      throw ListenError(address: bindIP, port: port, code: code)
    }
    return fd
  }

  static func applyLocalOptions(toFileDescriptor fd: Int32) {
    var one: Int32 = 1
    setsockopt(
      fd, Int32(IPPROTO_TCP), TCP_NODELAY,
      &one, socklen_t(MemoryLayout<Int32>.size))
  }
}

// MARK: - Endpoint ports

extension NWEndpoint.Port {

  /// The port `rawValue` names, or ``NWEndpoint/Port/any`` when it is zero.
  ///
  /// `NWEndpoint.Port(rawValue:)` is failable, so each of the three dial sites
  /// (`TCPClientInterface`, `LocalInterface`, `BackboneInterface`) had to decide what a
  /// rejected value means. They all mean the same thing—a port the interface was
  /// configured with is not one Network.framework accepts—so the decision is made
  /// once, here.
  static func orAny(_ rawValue: UInt16) -> NWEndpoint.Port {
    NWEndpoint.Port(rawValue: rawValue) ?? .any
  }
}
