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

/// The settings the `git-remote-rns` helper takes from its own configuration file.
///
/// The helper reads everything an `rngit` client reads, and one setting of its own that an
/// `rngit` client passes over.
public struct RNGitHelperSettings: Equatable, Sendable {

  /// Everything an `rngit` client takes from the same file.
  public var client = RNGitClientSettings()

  /// How many refs one fetch request asks for.
  public var refBatchSize = RNGitRemoteHelper.refBatchSize

  /// Creates the settings with every default in place.
  public init() {}

  /// Creates the settings `configuration` spells out.
  public init(configuration: RNGitConfigSection) throws {
    client = try RNGitClientSettings(configuration: configuration)

    if let section = configuration.section("client"), section.has("ref_batch_size") {
      guard let size = section.int("ref_batch_size") else {
        throw RNGitSettingsError.notAnInteger(key: "ref_batch_size")
      }
      refBatchSize = max(0, min(Self.refBatchCeiling, size))
    }
  }

  /// The most refs one fetch request may ask for.
  private static let refBatchCeiling = 1024
}
