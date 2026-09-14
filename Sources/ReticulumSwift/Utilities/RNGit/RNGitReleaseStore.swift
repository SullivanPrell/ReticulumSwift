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

/// The releases a repository carries, read from and written to the directory beside it.
///
/// A release is a directory named for its tag, holding a `META` file, release notes, an
/// `artifacts` directory and a `THANKS` count. The tag the `latest` file names is the one a
/// request for `latest` resolves to.
public enum RNGitReleaseStore {

  /// The directory holding the releases of the repository at `path`.
  public static func directory(forRepository path: String) -> String { path + ".releases" }

  /// The metadata at `path`, which is empty where there is no file and `nil` where the file
  /// does not parse.
  public static func metadata(at path: String) -> RNGitConfigSection? {
    guard FileManager.default.fileExists(atPath: path) else { return RNGitConfigSection() }
    guard let contents = FileManager.default.contents(atPath: path),
      let text = String(data: contents, encoding: .utf8)
    else { return nil }
    return try? RNGitConfigFile.parse(text)
  }

  /// The releases under `path` and the tag published as the latest, or `nil` where they could
  /// not be read.
  ///
  /// A release whose metadata does not parse, or whose creation moment is not a number, is
  /// left out. The latest is named only where it is a release that was published.
  public static func listing(_ path: String) -> (releases: [MsgPack.Value], latest: String?)? {
    guard isDirectory(path) else { return ([], nil) }
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
      return nil
    }

    var published: [String: Bool] = [:]
    var releases: [(created: Int, value: MsgPack.Value)] = []
    for entry in entries {
      let releaseDirectory = path + "/" + entry
      guard isDirectory(releaseDirectory) else { continue }
      let metaPath = releaseDirectory + "/META"
      guard FileManager.default.fileExists(atPath: metaPath), !isDirectory(metaPath) else {
        continue
      }
      guard let meta = metadata(at: metaPath) else { continue }

      let tag = packed(meta, "tag", or: .string(entry))
      let status = packed(meta, "status", or: .string("unknown"))
      guard let created = meta.has("created") ? meta.int("created") : 0 else { continue }

      let notes = preview(in: releaseDirectory)
      releases.append(
        (
          created,
          .map([
            (.string("tag"), tag),
            (.string("hash"), packed(meta, "hash", or: .string(""))),
            (.string("created"), .int(Int64(created))),
            (.string("status"), status),
            (.string("created_by"), packed(meta, "created_by", or: .string(""))),
            (.string("preview"), .string(notes.text)),
            (.string("format"), .string(notes.format)),
            (.string("artifacts"), .int(Int64(artifactCount(in: releaseDirectory)))),
          ])
        ))
      // Only a tag that is one value can be held against what it released.
      if case .string(let named) = tag { published[named] = status == .string("published") }
    }

    var latest: String?
    if let tag = latestTag(under: path), published[tag] == true { latest = tag }

    let ordered = releases.enumerated().sorted {
      $0.element.created == $1.element.created
        ? $0.offset < $1.offset : $0.element.created > $1.element.created
    }
    return (ordered.map { $0.element.value }, latest)
  }

  /// Everything a peer viewing the release at `path` is told, or `nil` where its metadata is
  /// missing or does not parse.
  public static func details(_ path: String, tag: String) -> MsgPack.Value? {
    let metaPath = path + "/META"
    guard FileManager.default.fileExists(atPath: metaPath), !isDirectory(metaPath),
      let meta = metadata(at: metaPath)
    else { return nil }
    guard let created = meta.has("created") ? meta.int("created") : 0 else { return nil }

    var notes = ""
    var format = "text"
    for (name, named) in [("RELEASE.md", "markdown"), ("RELEASE.mu", "micron")] {
      let notesPath = path + "/" + name
      guard FileManager.default.fileExists(atPath: notesPath), !isDirectory(notesPath) else {
        continue
      }
      if let contents = FileManager.default.contents(atPath: notesPath),
        let text = String(data: contents, encoding: .utf8)
      {
        notes = text
        format = named
      }
      break
    }

    var artifacts: [MsgPack.Value] = []
    let artifactsDirectory = path + "/artifacts"
    if isDirectory(artifactsDirectory),
      let entries = try? FileManager.default.contentsOfDirectory(atPath: artifactsDirectory)
    {
      for entry in entries {
        let artifactPath = artifactsDirectory + "/" + entry
        guard FileManager.default.fileExists(atPath: artifactPath), !isDirectory(artifactPath)
        else { continue }
        let size = (try? FileManager.default.attributesOfItem(atPath: artifactPath))?[.size]
        artifacts.append(
          .map([
            (.string("name"), .string(entry)),
            (.string("size"), .int(Int64((size as? NSNumber)?.intValue ?? 0))),
          ]))
      }
    }

    return .map([
      (.string("tag"), packed(meta, "tag", or: .string(tag))),
      (.string("hash"), packed(meta, "hash", or: .string(""))),
      (.string("created"), .int(Int64(created))),
      (.string("status"), packed(meta, "status", or: .string("unknown"))),
      (.string("created_by"), packed(meta, "created_by", or: .string(""))),
      (.string("notes"), .string(notes)),
      (.string("notes_format"), .string(format)),
      (.string("artifacts"), .array(artifacts)),
      (.string("thanks"), thanks(in: path)),
    ])
  }

  /// The tag the `latest` file under `path` names, or `nil` where it names none.
  public static func latestTag(under path: String) -> String? {
    let latestPath = path + "/latest"
    guard FileManager.default.fileExists(atPath: latestPath), !isDirectory(latestPath),
      let contents = FileManager.default.contents(atPath: latestPath),
      let text = String(data: contents, encoding: .utf8)
    else { return nil }
    return text.pythonStripped
  }

  /// What `key` holds, as a release answer carries it, or `fallback` where it holds none.
  ///
  /// A key holding several values answers them as a list, and a key opening a subsection
  /// answers the whole of it.
  private static func packed(
    _ meta: RNGitConfigSection, _ key: String, or fallback: MsgPack.Value
  ) -> MsgPack.Value {
    switch meta[key] {
    case .scalar(let value): return .string(value)
    case .list(let values): return .array(values.map { .string($0) })
    case .section(let value): return packed(value)
    case .none: return fallback
    }
  }

  /// A whole section, as a release answer carries it.
  private static func packed(_ section: RNGitConfigSection) -> MsgPack.Value {
    .map(section.keys.map { (.string($0), packed(section, $0, or: .string(""))) })
  }

  /// The notes shown beside a release in a listing, and the markup they are written in.
  ///
  /// The first of three files that exists is the one read, whether or not it reads, and a
  /// heading or a quote is left out of the preview.
  private static func preview(in path: String) -> (text: String, format: String) {
    for name in ["RELEASE.md", "RELEASE.mu", "RELEASE.txt"] {
      let notesPath = path + "/" + name
      guard FileManager.default.fileExists(atPath: notesPath), !isDirectory(notesPath) else {
        continue
      }
      var format = "markdown"
      if name.hasSuffix(".mu") {
        format = "micron"
      } else if name.hasSuffix(".txt") {
        format = "text"
      }
      guard let contents = FileManager.default.contents(atPath: notesPath),
        let text = String(data: contents, encoding: .utf8)
      else { return ("", "markdown") }
      var lines = ""
      for line in text.pythonLines where !line.hasPrefix("#") && !line.hasPrefix(">") {
        lines += line + "\n"
      }
      return (lines.pythonStripped, format)
    }
    return ("", "markdown")
  }

  /// How many files the release at `path` carries as artifacts.
  private static func artifactCount(in path: String) -> Int {
    let artifactsDirectory = path + "/artifacts"
    guard isDirectory(artifactsDirectory),
      let entries = try? FileManager.default.contentsOfDirectory(atPath: artifactsDirectory)
    else { return 0 }
    return entries.filter {
      FileManager.default.fileExists(atPath: artifactsDirectory + "/" + $0)
        && !isDirectory(artifactsDirectory + "/" + $0)
    }.count
  }

  /// The count the release at `path` was thanked, which is zero where there is none to read.
  private static func thanks(in path: String) -> MsgPack.Value {
    let thanksPath = path + "/THANKS"
    guard FileManager.default.fileExists(atPath: thanksPath), !isDirectory(thanksPath),
      let contents = FileManager.default.contents(atPath: thanksPath),
      let decoded = try? MsgPack.decode(contents), case .map(let fields) = decoded
    else { return .int(0) }
    for (key, value) in fields where key.asString == "count" { return value }
    return .int(0)
  }

  /// Whether there is a directory at `path`.
  static func isDirectory(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      return false
    }
    return isDirectory.boolValue
  }
}
