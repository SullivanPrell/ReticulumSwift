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

/// Why an `allowed` file could not be read.
///
/// The two callers treat these differently.
public enum RNGitAllowedError: Error, Equatable, Sendable {

  /// The file is not valid UTF-8.
  case notText(path: String)

  /// The file is a program that would not run.
  case notRunnable(path: String)
}

/// The groups and repositories a node serves, as it reads them from disk.
public struct RNGitRepositoryStore: Sendable {

  /// The groups the node serves, by name.
  public private(set) var groups: [String: RNGitGroup] = [:]

  /// Names that stand for an identity hash in a permission line.
  public var identityAliases: [String: String]

  /// The configuration's `access` section, whose keys are group names.
  public var access: RNGitConfigSection?

  private let runner: RNGitCommandRunner

  /// Creates a store that reads through `runner`, holding `groups` to begin with.
  public init(
    runner: RNGitCommandRunner, groups: [String: RNGitGroup] = [:],
    identityAliases: [String: String] = [:], access: RNGitConfigSection? = nil
  ) {
    self.runner = runner
    self.groups = groups
    self.identityAliases = identityAliases
    self.access = access
  }

  /// What the `allowed` file at `path` grants, and whether it is a program.
  ///
  /// An executable file is run and its output read whatever its exit status; anything else is read
  /// as text. A path naming no file grants nothing.
  public func allowedPermissions(at path: String) throws
    -> (permissions: RNGitPermissionSet, dynamic: Bool)
  {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else { return (RNGitPermissionSet(), false) }

    if FileManager.default.isExecutableFile(atPath: path) {
      guard let output = runner.run(path, arguments: [], in: nil) else {
        throw RNGitAllowedError.notRunnable(path: path)
      }
      return (RNGitPermissionSet.parsing(output.standardOutput, aliases: identityAliases), true)
    }

    guard let data = FileManager.default.contents(atPath: path),
      let text = String(data: data, encoding: .utf8)
    else { throw RNGitAllowedError.notText(path: path) }
    return (RNGitPermissionSet.parsing(text, aliases: identityAliases), false)
  }

  /// Reads the group named `name` at `path`, along with every repository it holds.
  ///
  /// A group already known under a different path is left as it is.
  public mutating func loadGroup(named name: String, at path: String) throws {
    if groups[name] == nil { groups[name] = RNGitGroup(name: name, path: path) }
    guard groups[name]?.path == path else { return }

    updateGroupPermissions(named: name)

    for entry in try FileManager.default.contentsOfDirectory(atPath: path) {
      try loadRepository(into: name, at: "\(path)/\(entry)")
    }
  }

  /// Reads the permissions of the group named `name` from its `allowed` file and the
  /// configuration.
  ///
  /// The `allowed` file replaces what the group held, and the configuration's entries are added on
  /// top of it.
  public mutating func updateGroupPermissions(named name: String) {
    guard let group = groups[name] else { return }

    var permissions = RNGitPermissionSet()
    let allowedPath = group.path + ".allowed"
    if FileManager.default.fileExists(atPath: allowedPath) {
      if let allowed = try? allowedPermissions(at: allowedPath) {
        permissions = allowed.permissions
        groups[name]?.dynamicPermissions = allowed.dynamic
      }
    } else {
      groups[name]?.dynamicPermissions = false
    }

    for entry in access?.list(name) ?? [] {
      permissions.grant(entry, aliases: identityAliases)
    }

    groups[name]?.permissions = permissions
  }

  /// Reads the permissions of one repository from its own `allowed` file.
  ///
  /// The repository is left as it is where the file cannot be read.
  public mutating func updateRepositoryPermissions(group name: String, repository: String) {
    guard let path = groups[name]?.repositories[repository]?.path else { return }
    guard let allowed = try? allowedPermissions(at: path + ".allowed") else { return }
    groups[name]?.repositories[repository]?.permissions = allowed.permissions
  }

  /// Reads the repository at `path` into the group named `name`, answering whether it is one.
  ///
  /// A working directory, a `.work` or `.releases` directory, and anything that is not a bare
  /// repository are all passed over.
  @discardableResult
  public mutating func loadRepository(into name: String, at path: String) throws -> Bool {
    guard groups[name] != nil, !path.isEmpty else { return false }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue, !path.hasSuffix(".work"), !path.hasSuffix(".releases")
    else { return false }

    guard RNGitWorkingCopy.isGitRepository(path, runner: runner),
      RNGitWorkingCopy.isBareRepository(path, runner: runner)
    else { return false }

    let allowed = try allowedPermissions(at: path + ".allowed")
    let repository = RNGitRepository(
      name: (path as NSString).lastPathComponent, path: path,
      permissions: allowed.permissions,
      fork: RNGitWorkingCopy.forkSource(of: path, runner: runner),
      mirror: RNGitWorkingCopy.mirrorSource(of: path, runner: runner))
    groups[name]?.repositories[repository.name] = repository
    return true
  }
}
