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

/// The directories a node builds its work in, held against the link that asked for it.
///
/// The node empties what a link holds once the link goes stale.
public struct RNGitTemporaryDirectories: Sendable {

  /// Where the directories are made.
  public var root: String

  /// The directories held for each link.
  public private(set) var held: [Data: [String]] = [:]

  /// Creates a holder making directories under `root`.
  public init(root: String = NSTemporaryDirectory()) { self.root = root }

  /// A new directory, reachable only by this user, held for `link`, or `nil` where it
  /// could not be made.
  public mutating func make(for link: Data) -> String? {
    let path = root + "/rngit-" + UUID().uuidString
    guard
      (try? FileManager.default.createDirectory(
        atPath: path, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])) != nil
    else { return nil }
    held[link, default: []].append(path)
    return path
  }

  /// Removes whatever was held for `link`, answering what it removed.
  @discardableResult
  public mutating func release(_ link: Data) -> [String] {
    let paths = held.removeValue(forKey: link) ?? []
    for path in paths { try? FileManager.default.removeItem(atPath: path) }
    return paths
  }
}
