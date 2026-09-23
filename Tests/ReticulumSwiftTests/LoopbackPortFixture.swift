//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Darwin
import Foundation
import XCTest

/// What a connect attempt to a loopback port found waiting there.
enum LoopbackPortState: Equatable {
  /// Nothing is bound to the port, so the kernel answers the connect with a reset.
  case refused
  /// Something is listening and took the connection.
  case accepting
  /// The connect drew no answer inside the probe window.
  ///
  /// A socket bound to the port without listening produces this: macOS drops the
  /// incoming segment instead of resetting it, so a client hangs until its own
  /// timeout rather than failing fast.
  case unanswered
}

/// Reports what a connect to `port` on 127.0.0.1 meets, without leaving a connection open.
///
/// A probe that can't be set up reports ``LoopbackPortState/unanswered``, because every
/// caller treats anything other than ``LoopbackPortState/refused`` as unusable.
func loopbackPortState(_ port: UInt16, timeout: TimeInterval = 0.25) -> LoopbackPortState {
  let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
  guard fd >= 0 else { return .unanswered }
  defer { Darwin.close(fd) }

  let flags = Darwin.fcntl(fd, F_GETFL, 0)
  guard flags >= 0, Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
    return .unanswered
  }

  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  Darwin.inet_aton("127.0.0.1", &addr.sin_addr)
  let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  if connected == 0 { return .accepting }
  let immediate = Darwin.errno
  if immediate == ECONNREFUSED { return .refused }
  guard immediate == EINPROGRESS else { return .unanswered }

  var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
  let milliseconds = Int32((timeout * 1000).rounded())
  guard Darwin.poll(&descriptor, 1, max(1, milliseconds)) > 0 else { return .unanswered }

  var pending: Int32 = 0
  var size = socklen_t(MemoryLayout<Int32>.size)
  guard Darwin.getsockopt(fd, SOL_SOCKET, SO_ERROR, &pending, &size) == 0 else {
    return .unanswered
  }
  switch pending {
  case 0: return .accepting
  case ECONNREFUSED: return .refused
  default: return .unanswered
  }
}

/// Asks the kernel for a loopback port that was free at the moment it answered.
///
/// Binding to port 0 makes the kernel pick from the ephemeral range and hand back a port
/// nothing else holds. Closing the socket releases it again: an unaccepted listener leaves
/// no `TIME_WAIT` behind, so the port is immediately bindable and connects to it are refused.
func kernelAssignedLoopbackPort() -> UInt16? {
  let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
  guard fd >= 0 else { return nil }
  defer { Darwin.close(fd) }

  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = 0
  Darwin.inet_aton("127.0.0.1", &addr.sin_addr)
  let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  guard bound == 0 else { return nil }

  var assigned = sockaddr_in()
  var size = socklen_t(MemoryLayout<sockaddr_in>.size)
  let named = withUnsafeMutablePointer(to: &assigned) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.getsockname(fd, $0, &size)
    }
  }
  guard named == 0 else { return nil }
  return UInt16(bigEndian: assigned.sin_port)
}

/// Returns a loopback port that a connect attempt is provably refused on.
///
/// A test that asserts "connecting here fails" has to know the port is free rather than
/// assume it. Picking one at random out of a range and hoping means the assertion measures
/// the machine the suite runs on: when the pick collides with any listener the connect
/// succeeds and the test reports a failure that has nothing to do with what it covers.
///
/// Each candidate is checked with ``loopbackPortState(_:timeout:)`` and discarded unless the
/// answer is a reset. A port the kernel hands back and then refuses can still be taken by an
/// outbound connection in the moment between the check and the caller's use, so a caller that
/// binds the port keeps its own retry for the bind.
///
/// - Parameters:
///   - attempts: How many candidates to check before giving up.
///   - nextCandidate: Source of candidate ports. Tests override it to feed a known port.
///   - file: File the caller sits in, reported if no port can be proven free.
///   - line: Line the caller sits on, reported if no port can be proven free.
/// - Returns: A loopback port that refused a connect a moment ago.
/// - Throws: `XCTSkip` once `attempts` candidates have each turned out to be unusable.
func freeLoopbackPort(
  attempts: Int = 8,
  nextCandidate: () -> UInt16? = kernelAssignedLoopbackPort,
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> UInt16 {
  for _ in 0..<attempts {
    guard let candidate = nextCandidate() else { continue }
    if loopbackPortState(candidate) == .refused { return candidate }
  }
  throw XCTSkip(
    "no loopback port could be proven free in \(attempts) attempts", file: file, line: line)
}
