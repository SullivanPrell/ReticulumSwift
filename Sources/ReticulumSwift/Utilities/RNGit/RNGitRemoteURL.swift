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

/// Why a remote URL could not be read.
public enum RNGitRemoteURLError: Error, Equatable, Sendable {

  /// The URL does not open with the protocol specifier.
  case invalidProtocol

  /// The URL holds a different number of components than was asked of it.
  case componentCount

  /// What the URL names as its destination is not the length of a hash.
  case hashLength

  /// What the URL names as its destination is not hexadecimal, and this is where reading it
  /// stopped.
  case hashDigits(position: Int)

  /// What the client says before it gives up.
  public var message: String {
    switch self {
    case .invalidProtocol: return "Invalid protocol in remote URL"
    case .componentCount: return "Invalid number of URL components"
    case .hashLength: return "Invalid destination hash length"
    case .hashDigits(let position):
      return "Invalid destination hash: non-hexadecimal number found in fromhex() arg at position "
        + String(position)
    }
  }
}

/// What a remote URL names, which is a destination and the group and repository under it.
///
/// The protocol specifier is matched without regard to case; everything after it is read as it is
/// written. A first component that is not a hash is looked up among the client's aliases.
public enum RNGitRemoteURL {

  /// What every remote URL opens with.
  public static let protocolSpecifier = "rns://"

  /// The destination, group and repository `remote` names.
  public static func repository(_ remote: String, aliases: [String: String] = [:]) throws
    -> (destination: Data, group: String, repository: String)
  {
    let read = try read(remote, aliases: aliases, count: 3)
    return (read.destination, read.components[1], read.components[2])
  }

  /// The destination and group `remote` names.
  public static func group(_ remote: String, aliases: [String: String] = [:]) throws
    -> (destination: Data, group: String)
  {
    let read = try read(remote, aliases: aliases, count: 2)
    return (read.destination, read.components[1])
  }

  /// The destination `remote` names, whatever else it goes on to name.
  public static func destination(_ remote: String, aliases: [String: String] = [:]) throws -> Data {
    try read(remote, aliases: aliases, count: nil).destination
  }

  /// The components of `remote`, and the destination the first of them names.
  ///
  /// A `count` is how many components the URL must hold, which is counted before the destination
  /// is read.
  private static func read(_ remote: String, aliases: [String: String], count: Int?) throws -> (
    destination: Data, components: [String]
  ) {
    guard remote.lowercased().hasPrefix(protocolSpecifier) else {
      throw RNGitRemoteURLError.invalidProtocol
    }
    let components = String(remote.dropFirst(protocolSpecifier.count))
      .components(separatedBy: "/")
    let named = RNGitClientSettings.resolving(components[0], aliases: aliases)
    if let count, components.count != count { throw RNGitRemoteURLError.componentCount }
    guard named.count == Identity.truncatedHashLength / 8 * 2 else {
      throw RNGitRemoteURLError.hashLength
    }

    switch Data.reading(pythonHex: named) {
    case .bytes(let destination): return (destination, components)
    case .stopped(let position): throw RNGitRemoteURLError.hashDigits(position: position)
    }
  }
}
