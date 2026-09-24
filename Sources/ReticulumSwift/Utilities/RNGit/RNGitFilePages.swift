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

/// What a page request for a file is answered with.
public enum RNGitPageDownload: Equatable {

  /// A file the node sends as a resource, its name in the metadata beside it.
  case file(RNGitFile)

  /// A value the node sends as the response itself.
  case value(MsgPack.Value)
}

extension RNGitPageHandler {

  // MARK: - Release artifacts

  /// One artifact of a published release, or nil where the reference answers nothing.
  ///
  /// Mirrors `serve_artifact` (`pages.py:1714-1772`). The artifact's name is read back as
  /// `unquote_plus` reads it, and a name holding a separator once read is refused. A `tag` of
  /// `latest` names the release the `latest` file names, or else the newest release whether
  /// published or not. The release directory is joined as `os.path.join` joins it, so a tag
  /// opening with a separator stands on its own.
  public mutating func serveArtifact(
    identityHash: Data?, groupName: String, repositoryName: String, tag requestedTag: String,
    artifact requestedArtifact: String
  ) -> RNGitPageDownload? {
    let artifact = RNGitPageMicron.unquotePlus(requestedArtifact)
    guard !artifact.unicodeScalars.contains("/") else { return nil }

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else { return nil }

    let releases = RNGitReleaseStore.directory(forRepository: repository.path)
    var tag = requestedTag
    if tag == "latest" {
      guard let listing = RNGitReleaseStore.listing(releases), !listing.releases.isEmpty else {
        return nil
      }
      if let latest = listing.latest {
        tag = latest
      } else {
        guard let newest = listing.releases[0].asDictionary?["tag"]?.asString else { return nil }
        tag = newest
      }
    }

    let directory = RNGitReleaseHandler.joined(releases, tag)
    let artifacts = RNGitReleaseHandler.joined(directory, "artifacts")
    let path = RNGitReleaseHandler.joined(artifacts, artifact)
    guard let details = RNGitReleaseStore.details(directory, tag: tag)?.asDictionary,
      details["status"] == .string("published")
    else { return nil }
    guard RNGitReleaseStore.isDirectory(directory), RNGitReleaseStore.isDirectory(artifacts),
      RNGitWorkStore.isFile(path)
    else { return nil }

    downloadSucceeded(
      group: groupName, repository: repositoryName, for: identityHash, release: true)
    return .file(RNGitFile(path: path, metadata: .name(artifact)))
  }

  // MARK: - Repository files

  /// One file of a repository as it stands at `ref`, or nil where the reference answers nothing.
  ///
  /// Mirrors `serve_download` (`pages.py:1837-1880`). The path is read back as `unquote_plus`
  /// reads it, and the file is named for its last component, which is empty where the path ends
  /// in a separator. A directory is sent as `git show` lists it, and a symbolic link as the path
  /// it holds. The reference hands the transfer the pipe `git show` writes to; this port writes
  /// what it prints to a directory held for `link` and sends that file.
  public mutating func serveDownload(
    identityHash: Data?, groupName: String, repositoryName: String, ref: String = "HEAD",
    path requestedPath: String, link: Data
  ) -> RNGitPageDownload? {
    let filePath = RNGitPageMicron.unquotePlus(requestedPath)
    let fileName = filePath.pythonBasename
    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else { return nil }

    let reader = RNGitRepositoryReader(runner: runner)
    guard let resolved = reader.resolve(ref, in: repository.path), !filePath.isEmpty,
      reader.blobInfo(in: repository.path, at: resolved, path: filePath) != nil,
      let spooled = spool(filePath, at: resolved, in: repository.path, for: link, named: fileName)
    else { return nil }

    downloadSucceeded(group: groupName, repository: repositoryName, for: identityHash)
    return .file(spooled)
  }

  // MARK: - Media

  /// A file a page shows inline, `false` where the request cannot be answered, or nil where the
  /// reference answers nothing.
  ///
  /// Mirrors `serve_media` (`pages.py:1774-1835`). `request` names the file as
  /// `/media/<group>/<repository>/<ref>/<path>`. Where `mediaConversion` is on, an image in any
  /// format but WebP is converted to WebP for a link that is still open, and sent in the
  /// original format where the conversion does not come off. Nothing is counted.
  public mutating func serveMedia(identityHash: Data?, request: MsgPack.Value, link: Data)
    -> RNGitPageDownload?
  {
    let refused = RNGitPageDownload.value(.bool(false))
    guard let fields = RNGitRequestFields(request), fields["key"] != nil else { return refused }
    guard let requested = fields["path"], requested.pythonIsTruthy else { return refused }
    guard case .string(let mediaPath) = requested else { return nil }

    var scalars = mediaPath.unicodeScalars[...]
    let prefix = "/media".unicodeScalars
    if scalars.starts(with: prefix) { scalars = scalars.dropFirst(prefix.count) }
    while scalars.first == "/" { scalars = scalars.dropFirst() }
    let components = scalars.split(separator: "/", omittingEmptySubsequences: false).map {
      String($0)
    }
    guard components.count >= 4 else { return refused }

    let groupName = components[0]
    let repositoryName = components[1]
    let ref = components[2]
    let filePath = RNGitPageMicron.unquotePlus(components[3...].joined(separator: "/"))
    let fileName = filePath.pythonBasename

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else { return refused }

    let reader = RNGitRepositoryReader(runner: runner)
    guard let resolved = reader.resolve(ref, in: repository.path), !filePath.isEmpty,
      reader.blobInfo(in: repository.path, at: resolved, path: filePath) != nil
    else { return refused }

    let fileExtension = filePath.pythonSplitExtension.pathExtension.lowercased()
    if mediaConversion, RNGitPage.imageExtensions.contains(fileExtension),
      fileExtension != ".webp",
      let converted = webP(filePath, at: resolved, in: repository.path, for: link)
    {
      return .file(converted)
    }

    return spool(filePath, at: resolved, in: repository.path, for: link, named: fileName).map {
      .file($0)
    }
  }

  // MARK: - Work documents

  /// One work document's text, named for its title and format, or nil where the reference
  /// answers nothing.
  ///
  /// Mirrors `serve_wd_download` (`pages.py:1882-1954`). A `scope` other than `active`,
  /// `completed` or `all` reads as `active`, so `proposed` finds nothing, and `all` looks in
  /// `active`, then `completed`, then `proposed`. The number is written back as Python writes
  /// it, so `01` finds document 1. A title is cut to 256 members, and one that is not text is
  /// written as `str` writes it. The reference raises where the document is missing, and where
  /// its text is bytes it raises after counting the download.
  public mutating func serveWorkDocumentDownload(
    identityHash: Data?, groupName: String, repositoryName: String, documentID: String,
    scope: String = "all"
  ) -> RNGitPageDownload? {
    guard !groupName.isEmpty, !repositoryName.isEmpty, !documentID.isEmpty,
      let number = documentID.pythonInteger
    else { return nil }

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName),
      access.allowsDocument(
        identityHash, group: groupName, repository: repositoryName, number: number,
        permission: .read)
    else { return nil }

    let work = RNGitWorkStore.directory(forRepository: repository.path)
    func folder(_ name: String) -> String { work + "/" + name + "/" + String(number) }
    let directory: String
    switch scope {
    case "completed": directory = folder("completed")
    case "all":
      directory =
        [folder("active"), folder("completed")].first(where: RNGitWorkStore.isDirectory)
        ?? folder("proposed")
    default: directory = folder("active")
    }

    let root = directory + "/root"
    guard RNGitWorkStore.isFile(root), let document = RNGitWorkStore.document(at: root),
      document.pythonIsTruthy, let fields = RNGitRequestFields(document),
      let meta = RNGitRequestFields(fields["meta"] ?? .map([]))
    else { return nil }

    let format = meta["format"] ?? .string("markdown")
    guard let title = Self.cut(meta["title"] ?? .string("Untitled"), to: 256) else { return nil }

    switch fields["content"] ?? .string("") {
    case .string(let text):
      let content = text.pythonStripped
      guard !content.isEmpty else { return nil }
      let name = title + (format.pythonEquals(.string("micron")) ? ".mu" : ".md")
      downloadSucceeded(group: groupName, repository: repositoryName, for: identityHash)
      return .value(.array([.string(name), .bytes(Data(content.utf8))]))
    case .bytes(let bytes):
      guard !bytes.pythonStripped.isEmpty else { return nil }
      downloadSucceeded(group: groupName, repository: repositoryName, for: identityHash)
      return nil
    default:
      return nil
    }
  }

  // MARK: - Helpers

  /// `value[:length]` as an f-string writes it, or nil where Python raises.
  private static func cut(_ value: MsgPack.Value, to length: Int) -> String? {
    switch value {
    case .string(let text): return text.pythonPrefix(length)
    case .bytes(let bytes): return MsgPack.Value.bytes(Data(bytes.prefix(length))).pythonDescription
    case .array(let items):
      return MsgPack.Value.array(Array(items.prefix(length))).pythonDescription
    default: return nil
    }
  }

  /// What `git show` prints for `filePath` at `ref`, written to a directory held for `link` and
  /// named `name`, or nil where it could not be run or written.
  private mutating func spool(
    _ filePath: String, at ref: String, in repository: String, for link: Data, named name: String
  ) -> RNGitFile? {
    guard
      let shown = runner.run(
        bytes: "git", arguments: ["show", ref + ":" + filePath.pythonStripping("/")],
        in: repository),
      let directory = temporaries.make(for: link)
    else { return nil }
    let path = directory + "/blob"
    guard FileManager.default.createFile(atPath: path, contents: shown.standardOutput) else {
      temporaries.release(directory, of: link)
      return nil
    }
    return RNGitFile(path: path, directory: directory, metadata: .name(name))
  }

  /// `filePath` at `ref` converted to WebP in a directory held for `link`, or nil where `link`
  /// is not open or the conversion does not come off.
  ///
  /// Mirrors `get_webp_stream` (`pages.py:2206-2238`): the file is named for the original's
  /// stem, and the directory is let go again where nothing was converted.
  private mutating func webP(
    _ filePath: String, at ref: String, in repository: String, for link: Data
  )
    -> RNGitFile?
  {
    let stripped = filePath.pythonStripping("/")
    guard activeLinks.contains(link) else {
      Reticulum.log("Could not resolve link for media conversion of " + stripped, level: .warning)
      return nil
    }
    guard let directory = temporaries.make(for: link) else { return nil }

    let stem = stripped.pythonBasename.pythonSplitExtension.root
    let unique = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8)
    let path = directory + "/" + stem + "." + unique + ".webp"
    guard
      mediaEncoder.convert(
        producedBy: ["git", "show", ref + ":" + stripped], in: repository, to: path)
    else {
      temporaries.release(directory, of: link)
      return nil
    }
    return RNGitFile(path: path, directory: directory, metadata: .name(stem + ".webp"))
  }

  /// Counts one download of a file, or of a release's artifact, unless the settings leave this
  /// peer or every download out.
  ///
  /// Mirrors `download_succeeded` and `release_download_succeeded` (`server.py:4778-4786`).
  mutating func downloadSucceeded(
    group: String, repository: String, for identityHash: Data?, release: Bool = false
  ) {
    if let identityHash, settings.statsIgnored.contains(identityHash) { return }
    guard settings.statsEnabled, !group.isEmpty, !repository.isEmpty else { return }
    let day = RNGitStatsStore.day()
    if release {
      statistics.recordReleaseDownload(group, repository, on: day)
    } else {
      statistics.recordDownload(group, repository, on: day)
    }
  }
}
