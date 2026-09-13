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

extension RNGitClientCommands {

  /// What the client offers where an entity has no permissions yet.
  public static let permissionsTemplate =
    "# No permissions are currently defined for this entity. Add them below, and save and exit "
    + "when you are done."

  /// Hands the user the permissions the group `remote` names grants, and sends back their edit.
  public func groupPermissions(remote: String?) throws {
    try editPermissions(
      remote: remote, operation: "gperms", key: RNGitRequestKey.group,
      naming: { try RNGitRemoteURL.group($0, aliases: self.aliases).group },
      done: { "Permissions updated for group \($0)\n" })
  }

  /// Hands the user the permissions the repository `remote` names grants, and sends back the edit.
  public func repositoryPermissions(remote: String?) throws {
    try editPermissions(
      remote: remote, operation: "rperms", key: RNGitRequestKey.repository,
      naming: {
        let named = try RNGitRemoteURL.repository($0, aliases: self.aliases)
        return named.group + "/" + named.repository
      },
      done: { "Permissions updated for \($0)\n" })
  }

  /// The fields a permissions request naming `name` under `key` carries.
  private static func permissionFields(
    _ key: UInt8, _ name: String, _ operation: String, step: String, content: String? = nil
  ) -> MsgPack.Value {
    var entries: [(MsgPack.Value, MsgPack.Value)] = [
      (.uint(UInt64(key)), .string(name)),
      (.string("operation"), .string(operation)),
      (.string("step"), .string(step)),
    ]
    if let content { entries.append((.string("content"), .string(content))) }
    return .map(entries)
  }

  /// Hands the user what `remote` grants today and sends back what they made of it.
  private func editPermissions(
    remote: String?, operation: String, key: UInt8, naming: (String) throws -> String,
    done: (String) -> String
  ) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    try connect(to: remote, failure: "Failed to establish link")
    output.write("\r                       \r")
    defer { transport.teardown() }

    let name = try read { try naming(remote) }
    let asked = try requesting(
      .perms, Self.permissionFields(key, name, operation, step: "get"), timeout: 120)
    let body = try answered(Self.remoteError.reading(asked))

    var standing = ""
    if !body.isEmpty {
      guard let decoded = try? MsgPack.decode(body) else {
        throw RNGitClientAbort("Error editing permissions: unreadable data")
      }
      standing = decoded.asDictionary?["content"]?.asString ?? ""
    }

    let template = standing.isEmpty ? Self.permissionsTemplate : standing
    guard let content = edited(template, suffix: ".txt") else {
      output.write("Edit cancelled\n")
      return
    }

    let sent = try requesting(
      .perms, Self.permissionFields(key, name, operation, step: "set", content: content),
      timeout: 120)
    _ = try answered(Self.remoteError.reading(sent))
    output.write(done(name))
  }
}
