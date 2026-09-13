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

/// The request paths a node registers a handler for.
///
/// Python: `PATH_*` on both classes (`server.py:285-295`, `server.py:1953-1963`).
public enum RNGitRequestPath: String, CaseIterable, Sendable {

  /// The references a repository holds.
  case list = "/git/list"

  /// A pack of the objects a peer asks for.
  case fetch = "/git/fetch"

  /// A pack a peer sends, with the references it updates.
  case push = "/git/push"

  /// Removing a repository.
  case delete = "/git/delete"

  /// Creating a repository.
  case create = "/git/create"

  /// Creating a repository from another the node serves.
  case fork = "/git/fork"

  /// Synchronizing a mirror with its upstream.
  case sync = "/git/sync"

  /// Creating a repository that mirrors an upstream.
  case mirror = "/git/mirror"

  /// The releases a repository carries, and their assets.
  case release = "/mgmt/release"

  /// The work documents a repository carries.
  case work = "/mgmt/work"

  /// The permissions a repository and its group grant.
  case perms = "/mgmt/perms"
}

/// The first byte of every answer a node sends.
///
/// Python: `RES_*` on both classes (`server.py:297-301`, `server.py:1965-1969`).
public enum RNGitResponseCode: UInt8, CaseIterable, Sendable {

  /// The request succeeded, and the rest of the answer is its result.
  case ok = 0x00

  /// The peer may not make this request.
  case disallowed = 0x01

  /// The request is not one the handler can read.
  case invalidRequest = 0x02

  /// There is nothing at the path the request names, as far as the peer may know.
  case notFound = 0x03

  /// The node tried and failed.
  case remoteFailure = 0xFF
}

/// The keys a request map carries.
///
/// Python: `IDX_*` on both classes (`server.py:303-305`, `server.py:1971-1973`), which are
/// integers rather than strings; the requests that carry other fields key those by name.
public enum RNGitRequestKey {

  /// The `group/repository` path a request works on.
  public static let repository: UInt8 = 0x00

  /// The result code an answer carries.
  public static let resultCode: UInt8 = 0x01

  /// The group a request works on.
  public static let group: UInt8 = 0x02
}

/// One answer a node sends, as a result code and the bytes that follow it.
public struct RNGitResponse: Equatable, Sendable {

  /// The code the answer opens with.
  public let code: RNGitResponseCode

  /// Everything after the code.
  public let body: Data

  /// The answer as it goes on the wire.
  public var encoded: Data { Data([code.rawValue]) + body }

  /// Creates an answer carrying `body`.
  public init(_ code: RNGitResponseCode, _ body: Data = Data()) {
    self.code = code
    self.body = body
  }

  /// Creates an answer carrying `message` as UTF-8.
  public init(_ code: RNGitResponseCode, _ message: String) {
    self.init(code, Data(message.utf8))
  }
}
