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

/// The count a repository or a release has been thanked, and the additions to it.
///
/// A link may thank each thing once: the addition is remembered by the hash of the link's own
/// identifier and the path it thanked, and a repeat of that pair is read rather than counted.
public final class RNGitPageThanks: @unchecked Sendable {

  /// How many additions are remembered before the oldest is forgotten.
  public static let rememberedAdditions = 256

  /// The additions already counted, oldest first.
  private var counted: [Data] = []

  /// Serialises the remembered additions.
  private let lock = NSLock()

  /// Creates a store that remembers nothing yet.
  public init() {}

  /// The count the repository at `path` has been thanked, after `link` thanks it when one does.
  ///
  /// The count is kept in `path` with `.thanks` after it.
  public func repository(at path: String, thankedBy link: Data? = nil) -> Int {
    count(in: path + ".thanks", for: path, thankedBy: link)
  }

  /// The count the release at `path` has been thanked, after `link` thanks it when one does.
  ///
  /// The count is kept in a `THANKS` file inside the release.
  public func release(at path: String, thankedBy link: Data? = nil) -> Int {
    count(in: path + "/THANKS", for: path, thankedBy: link)
  }

  /// The count in `file`, with a thanks from `link` for `path` added where it is new.
  ///
  /// A file that is not there is written with the count this call makes it, and the caller is
  /// answered zero rather than that count: the count reaches the reader on the next read.
  private func count(in file: String, for path: String, thankedBy link: Data?) -> Int {
    var adds = false
    if let link {
      let addition = Hashes.fullHash(link + Data(path.utf8))
      lock.lock()
      if counted.contains(addition) {
        adds = false
      } else {
        counted.append(addition)
        if counted.count > Self.rememberedAdditions { counted.removeFirst() }
        adds = true
      }
      lock.unlock()
    }

    guard FileManager.default.fileExists(atPath: file), !RNGitReleaseStore.isDirectory(file) else {
      write(adds ? 1 : 0, to: file)
      return 0
    }

    guard let contents = FileManager.default.contents(atPath: file),
      let decoded = try? MsgPack.decode(contents), case .map(let fields) = decoded,
      let read = fields.first(where: { $0.0.asString == "count" })?.1.asInt
    else { return 0 }

    let count = adds ? read + 1 : read
    write(count, to: file)
    return count
  }

  /// Writes `count` to `file`, leaving it unwritten where it cannot be.
  private func write(_ count: Int, to file: String) {
    let encoded = MsgPack.encode(.map([(.string("count"), .int(Int64(count)))]))
    try? encoded.write(to: URL(fileURLWithPath: file))
  }
}
