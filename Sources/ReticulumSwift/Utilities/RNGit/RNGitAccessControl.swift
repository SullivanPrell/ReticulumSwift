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

/// What a remote identity is asking an `rngit` node to do.
///
/// These are compared against the node's own configuration, so they name a configuration surface
/// rather than a wire one.
public enum RNGitPermission: UInt8, CaseIterable, Sendable {

  /// Read a repository.
  case read = 0x01

  /// Write to a repository.
  case write = 0x02

  /// Read and write, which a configuration line may ask for as one word.
  case readWrite = 0x03

  /// Create a repository in a group.
  case create = 0x04

  /// Read a node's statistics.
  case stats = 0x05

  /// Publish or withdraw a release.
  case release = 0x06

  /// Comment on a work document.
  case interact = 0x07

  /// Propose a work document.
  case propose = 0x08

  /// Administer a group, repository or document.
  case admin = 0xFE

  /// The permission a configuration keyword names, or `nil` if none does.
  ///
  /// The keyword is matched already lowercased.
  public static func named(_ keyword: String) -> RNGitPermission? {
    switch keyword {
    case "r", "read": return .read
    case "w", "write": return .write
    case "rw", "readwrite": return .readWrite
    case "c", "create": return .create
    case "s", "stats": return .stats
    case "rel", "release": return .release
    case "i", "interact": return .interact
    case "p", "propose": return .propose
    case "adm", "admin": return .admin
    default: return nil
    }
  }
}

/// Who a permission line grants a permission to.
public enum RNGitPermissionTarget: Hashable, Sendable {

  /// Nobody, which overrides every other grant at the same level.
  case nobody

  /// Everyone who identifies on the link.
  case everyone

  /// One identity, by the hash the line spells out.
  case identity(Data)

  /// The target a configuration keyword or identity hash names, or `nil` if neither.
  ///
  /// A hash is taken only at the length of a truncated identity hash, and anything else is dropped.
  public static func named(_ text: String) -> RNGitPermissionTarget? {
    if ["n", "none", "nobody"].contains(text) { return .nobody }
    if ["a", "all", "everyone"].contains(text) { return .everyone }
    guard text.count == Reticulum.truncatedHashLength / 8 * 2,
      let hash = Data(pythonHex: text)
    else { return nil }
    return .identity(hash)
  }
}

/// The targets an `allowed` file grants each permission to.
///
/// Order is the order the file grants them in, and a target is listed once per permission.
public struct RNGitPermissionSet: Equatable, Sendable {

  /// Targets allowed to read.
  public var read: [RNGitPermissionTarget] = []

  /// Targets allowed to write.
  public var write: [RNGitPermissionTarget] = []

  /// Targets allowed to create.
  public var create: [RNGitPermissionTarget] = []

  /// Targets allowed to read statistics.
  public var stats: [RNGitPermissionTarget] = []

  /// Targets allowed to publish releases.
  public var release: [RNGitPermissionTarget] = []

  /// Targets allowed to comment on work documents.
  public var interact: [RNGitPermissionTarget] = []

  /// Targets allowed to propose work documents.
  public var propose: [RNGitPermissionTarget] = []

  /// Targets allowed to administer.
  public var admin: [RNGitPermissionTarget] = []

  /// Creates an empty set, which grants nothing.
  public init() {}

  /// The targets granted `permission`, or `nil` for a permission no grant is stored under.
  ///
  /// `readWrite` is a spelling a configuration line may use, never a stored key.
  public subscript(permission: RNGitPermission) -> [RNGitPermissionTarget]? {
    switch permission {
    case .read: return read
    case .write: return write
    case .create: return create
    case .stats: return stats
    case .release: return release
    case .interact: return interact
    case .propose: return propose
    case .admin: return admin
    case .readWrite: return nil
    }
  }

  /// The `allowed` file a node writes for a repository it makes for `identityHash`.
  ///
  /// The hash is written as undelimited hexadecimal.
  public static func creationLine(for identityHash: Data) -> String {
    "adm:" + identityHash.map { String(format: "%02x", $0) }.joined()
  }

  /// The permission and target one configuration line grants, each `nil` where the line names
  /// none.
  ///
  /// The target is resolved through the node's identity aliases before it is read, and the two
  /// halves fail independently: `"read:garbage"` names a permission and no target. Five callers
  /// read them apart.
  public static func grant(
    in line: String, aliases: [String: String] = [:]
  ) -> (permission: RNGitPermission?, target: RNGitPermissionTarget?) {
    let components = line.components(separatedBy: ":")
    guard components.count == 2 else { return (nil, nil) }

    let keyword = components[0].lowercased()
    let target = resolvingAlias(components[1], aliases: aliases)
    return (RNGitPermission.named(keyword), RNGitPermissionTarget.named(target))
  }

  /// The grants an `allowed` file makes, with lines that grant nothing left out.
  ///
  /// A line starting with `#` is a comment, `readwrite` grants both read and write, and a target of
  /// no bytes grants nothing.
  public static func parsing(_ input: String?, aliases: [String: String] = [:])
    -> RNGitPermissionSet
  {
    var permissions = RNGitPermissionSet()
    guard let input else { return permissions }

    for line in input.pythonLines {
      let entry = line.trimmedForMicron
      guard !entry.hasPrefix("#") else { continue }
      permissions.grant(entry, aliases: aliases)
    }

    return permissions
  }

  /// Adds what one permission line grants, leaving the set alone where it grants nothing.
  ///
  /// ``RNGitRepositoryStore`` repeats this over the entries of the configuration's `access`
  /// section.
  public mutating func grant(_ entry: String, aliases: [String: String] = [:]) {
    let grant = Self.grant(in: entry, aliases: aliases)
    guard let permission = grant.permission, let target = grant.target,
      target != .identity(Data())
    else { return }

    switch permission {
    case .read: append(target, to: \.read)
    case .write: append(target, to: \.write)
    case .readWrite:
      append(target, to: \.read)
      append(target, to: \.write)
    case .create: append(target, to: \.create)
    case .stats: append(target, to: \.stats)
    case .release: append(target, to: \.release)
    case .interact: append(target, to: \.interact)
    case .propose: append(target, to: \.propose)
    case .admin: append(target, to: \.admin)
    }
  }

  private mutating func append(
    _ target: RNGitPermissionTarget, to list: WritableKeyPath<Self, [RNGitPermissionTarget]>
  ) {
    if !self[keyPath: list].contains(target) { self[keyPath: list].append(target) }
  }

  /// The alias an identity name stands for, or the name itself.
  ///
  /// A keyword or a spelled-out hash is left alone; anything else is looked up.
  public static func resolvingAlias(_ alias: String, aliases: [String: String]) -> String {
    let keywords = ["n", "none", "nobody", "a", "all", "everyone"]
    if keywords.contains(alias.lowercased()) { return alias }
    if alias.count == Identity.truncatedHashLength / 8 * 2, let hash = Data(pythonHex: alias),
      !hash.isEmpty
    {
      return alias
    }
    return aliases[alias] ?? alias
  }
}

/// One repository a node serves, with the permissions its own `allowed` file grants.
public struct RNGitRepository: Equatable, Sendable {

  /// The name the repository answers to, without its group.
  public let name: String

  /// Where the repository is on disk.
  public let path: String

  /// What the repository's own `allowed` file grants.
  public var permissions: RNGitPermissionSet

  /// The upstream this repository forks, or `nil` where it is not a fork.
  public var fork: String?

  /// The upstream this repository mirrors, or `nil` where it is not a mirror.
  public var mirror: String?

  /// Creates a repository record.
  public init(
    name: String, path: String, permissions: RNGitPermissionSet = RNGitPermissionSet(),
    fork: String? = nil, mirror: String? = nil
  ) {
    self.name = name
    self.path = path
    self.permissions = permissions
    self.fork = fork
    self.mirror = mirror
  }
}

/// One group of repositories, with the permissions its own `allowed` file grants.
public struct RNGitGroup: Equatable, Sendable {

  /// The name the group answers to.
  public let name: String

  /// Where the group is on disk.
  public let path: String

  /// The repositories the group holds, by name.
  public var repositories: [String: RNGitRepository]

  /// What the group's own `allowed` file grants.
  public var permissions: RNGitPermissionSet

  /// Whether the `allowed` file is a program the node runs for each answer.
  public var dynamicPermissions: Bool

  /// Creates a group record.
  public init(
    name: String, path: String, repositories: [String: RNGitRepository] = [:],
    permissions: RNGitPermissionSet = RNGitPermissionSet(), dynamicPermissions: Bool = false
  ) {
    self.name = name
    self.path = path
    self.repositories = repositories
    self.permissions = permissions
    self.dynamicPermissions = dynamicPermissions
  }
}

/// Decides what a remote identity may do on an `rngit` node.
///
/// A repository that grants a permission to anyone at all settles the question for that permission,
/// so a group grant is only consulted where the repository names nobody.
public struct RNGitAccessControl: Sendable {

  /// The groups the node serves, by name.
  public var groups: [String: RNGitGroup]

  /// Identities the node refuses before resolving anything.
  public var blockedIdentities: Set<Data>

  /// Names that stand for an identity hash in a permission line.
  public var identityAliases: [String: String]

  /// Creates an access control over `groups`.
  public init(
    groups: [String: RNGitGroup] = [:], blockedIdentities: Set<Data> = [],
    identityAliases: [String: String] = [:]
  ) {
    self.groups = groups
    self.blockedIdentities = blockedIdentities
    self.identityAliases = identityAliases
  }

  /// Whether `identityHash` may do `permission` on one repository.
  ///
  /// The only resolver that consults the block list.
  public func allows(
    _ identityHash: Data, group groupName: String, repository repositoryName: String,
    permission: RNGitPermission
  ) -> Bool {
    guard !blockedIdentities.contains(identityHash) else { return false }
    guard let group = groups[groupName],
      let repository = group.repositories[repositoryName],
      let repositoryGrants = repository.permissions[permission],
      let groupGrants = group.permissions[permission]
    else { return false }

    return Self.settle(
      identityHash, grants: repositoryGrants, admins: repository.permissions.admin,
      otherwise: {
        guard repositoryGrants.isEmpty else { return false }
        return Self.decide(
          identityHash, grants: groupGrants, admins: group.permissions.admin) ?? false
      })
  }

  /// Whether `identityHash` may do `permission` on one group.
  public func allowsGroup(
    _ identityHash: Data, group groupName: String, permission: RNGitPermission
  ) -> Bool {
    guard let group = groups[groupName], let grants = group.permissions[permission] else {
      return false
    }
    return Self.decide(identityHash, grants: grants, admins: group.permissions.admin) ?? false
  }

  /// Whether `identityHash` may do `permission` on one work document.
  ///
  /// The document's own `allowed` file is read at this point, and an unreadable one grants nothing.
  /// Pass what that file grants as `documentPermissions`.
  public func allowsDocument(
    _ identityHash: Data, group groupName: String, repository repositoryName: String,
    permission: RNGitPermission, documentPermissions: RNGitPermissionSet
  ) -> Bool {
    guard permission != .stats, permission != .release,
      let group = groups[groupName],
      let repository = group.repositories[repositoryName],
      let repositoryGrants = repository.permissions[permission],
      let groupGrants = group.permissions[permission],
      let documentGrants = documentPermissions[permission]
    else { return false }

    return Self.settle(
      identityHash, grants: documentGrants, admins: documentPermissions.admin,
      otherwise: {
        Self.settle(
          identityHash, grants: repositoryGrants, admins: repository.permissions.admin,
          otherwise: {
            guard repositoryGrants.isEmpty else { return false }
            return Self.decide(
              identityHash, grants: groupGrants, admins: group.permissions.admin) ?? false
          })
      })
  }

  /// The group and repository a request path names, or `nil` if it names neither.
  public static func repositoryPath(_ path: String) -> (group: String, repository: String)? {
    let components = path.components(separatedBy: "/")
    guard components.count == 2, components[0].count <= 256, components[1].count <= 256 else {
      return nil
    }
    return (components[0], components[1])
  }

  /// The group a request path names, or `nil` if it names none.
  public static func groupPath(_ path: String) -> String? {
    let components = path.components(separatedBy: "/")
    guard components.count == 1, components[0].count <= 256 else { return nil }
    return components[0]
  }

  /// The verdict one level reaches on its own, or `nil` where it defers to the next.
  private static func decide(
    _ identityHash: Data, grants: [RNGitPermissionTarget], admins: [RNGitPermissionTarget]
  ) -> Bool? {
    if grants.contains(.nobody) { return false }
    if grants.contains(.everyone) { return true }
    if grants.contains(.identity(identityHash)) { return true }
    if admins.contains(.identity(identityHash)) { return true }
    return nil
  }

  /// The verdict of one level, falling back to `otherwise` where the level defers.
  private static func settle(
    _ identityHash: Data, grants: [RNGitPermissionTarget], admins: [RNGitPermissionTarget],
    otherwise: () -> Bool
  ) -> Bool {
    decide(identityHash, grants: grants, admins: admins) ?? otherwise()
  }
}

extension Data {

  /// The bytes a hexadecimal string names, or `nil` if it names none.
  ///
  /// Refuses any character that is not a hexadecimal digit, as well as an odd number of digits.
  /// ASCII whitespace is skipped, but only between complete byte pairs: `"aa bb"` is two bytes
  /// where `"a abb"` is an error.
  public init?(pythonHex text: String) {
    var digits: [UInt8] = []
    for scalar in text.unicodeScalars {
      switch scalar {
      case " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}":
        guard digits.count % 2 == 0 else { return nil }
      case "0"..."9": digits.append(UInt8(scalar.value - 0x30))
      case "a"..."f": digits.append(UInt8(scalar.value - 0x61 + 10))
      case "A"..."F": digits.append(UInt8(scalar.value - 0x41 + 10))
      default: return nil
      }
    }

    guard digits.count % 2 == 0 else { return nil }
    var bytes = Data(capacity: digits.count / 2)
    for index in stride(from: 0, to: digits.count, by: 2) {
      bytes.append(digits[index] << 4 | digits[index + 1])
    }
    self = bytes
  }
}
