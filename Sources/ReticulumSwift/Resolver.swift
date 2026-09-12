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

/// Local address book mapping human-readable labels to Destination hashes.
///
/// Reticulum has no DNS—this is just a keyring.
public final class Resolver {
  /// A label bound to a destination address.
  public struct Entry: Sendable, Equatable, Codable {
    /// Human-readable label.
    public let label: String
    /// Destination address the label resolves to.
    public let destinationHash: Data
    /// Creates an entry binding a label to an address.
    public init(label: String, destinationHash: Data) {
      self.label = label
      self.destinationHash = destinationHash
    }
  }

  /// Every known entry.
  public private(set) var entries: [Entry]
  /// Creates a resolver holding `entries`.
  public init(entries: [Entry] = []) { self.entries = entries }

  /// Adds an entry.
  public func add(_ entry: Entry) { entries.append(entry) }

  /// Returns the entry for a label, or `nil` when none is known.
  public func resolve(label: String) -> Entry? {
    entries.first { $0.label == label }
  }

  /// Returns the entry for a destination address, or `nil` when none is known.
  public func resolve(hash: Data) -> Entry? {
    entries.first { $0.destinationHash == hash }
  }

  /// Removes every entry carrying the given label.
  public func remove(label: String) {
    entries.removeAll { $0.label == label }
  }

  /// Writes the entries to `url`.
  public func write(toFile url: URL) throws {
    let data = try JSONEncoder().encode(entries)
    try data.write(to: url, options: .atomic)
  }

  /// Reads a resolver from `url`.
  public static func read(fromFile url: URL) throws -> Resolver {
    let data = try Data(contentsOf: url)
    return Resolver(entries: try JSONDecoder().decode([Entry].self, from: data))
  }
}
