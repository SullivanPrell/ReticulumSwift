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

/// What a reader of the pages may see.
///
/// A page may be asked for without an identity, so a reader that has not identified is resolved
/// against a standing identity recovered from a key of nothing but zeroes, which no grant names.
public struct RNGitPageAccess: Sendable {

  /// The private key the standing identity is recovered from.
  static let nullPrivateKey = Data(repeating: 0, count: 64)

  /// What the node grants.
  public let control: RNGitAccessControl

  /// The identity a reader who has not identified is resolved as.
  public let nullIdentityHash: Data

  /// Creates a view of `control` for readers who may not have identified.
  public init(control: RNGitAccessControl) {
    self.control = control
    self.nullIdentityHash =
      (try? Identity(privateKeyBytes: Self.nullPrivateKey).hash) ?? Data(count: 16)
  }

  /// Whether `identityHash` may do `permission` on one repository.
  public func allows(
    _ identityHash: Data?, group: String, repository: String, permission: RNGitPermission
  ) -> Bool {
    control.allows(
      identityHash ?? nullIdentityHash, group: group, repository: repository,
      permission: permission)
  }

  /// Whether `identityHash` may do `permission` on the work document numbered `number`, by what
  /// the node grants and what the document's own `allowed` file grants.
  public func allowsDocument(
    _ identityHash: Data?, group: String, repository: String, number: Int,
    permission: RNGitPermission
  ) -> Bool {
    control.allowsDocument(
      identityHash ?? nullIdentityHash, group: group, repository: repository, number: number,
      permission: permission)
  }

  /// Whether `identityHash` may do `permission` on one work document, given what the document's
  /// own `allowed` file grants as `documentPermissions`.
  public func allowsDocument(
    _ identityHash: Data?, group: String, repository: String, permission: RNGitPermission,
    documentPermissions: RNGitPermissionSet
  ) -> Bool {
    control.allowsDocument(
      identityHash ?? nullIdentityHash, group: group, repository: repository,
      permission: permission, documentPermissions: documentPermissions)
  }

  /// The groups `identityHash` may read, each holding only the repositories it may read.
  ///
  /// A group whose repositories are all closed to the reader is not among them.
  public func groups(readableBy identityHash: Data?) -> [String: RNGitGroup] {
    var readable: [String: RNGitGroup] = [:]
    for (name, group) in control.groups {
      let repositories = self.repositories(readableBy: identityHash, in: name)
      guard !repositories.isEmpty else { continue }
      var read = group
      read.repositories = repositories
      readable[name] = read
    }
    return readable
  }

  /// The repositories of `group` that `identityHash` may read.
  public func repositories(readableBy identityHash: Data?, in group: String)
    -> [String: RNGitRepository]
  {
    guard let held = control.groups[group] else { return [:] }
    return held.repositories.filter {
      allows(identityHash, group: group, repository: $0.key, permission: .read)
    }
  }

  /// The one repository of `group` that `identityHash` may read, or nothing where it may not.
  public func repository(
    readableBy identityHash: Data?, in group: String, named repository: String
  ) -> RNGitRepository? {
    guard let held = control.groups[group], let found = held.repositories[repository],
      allows(identityHash, group: group, repository: repository, permission: .read)
    else { return nil }
    return found
  }
}
