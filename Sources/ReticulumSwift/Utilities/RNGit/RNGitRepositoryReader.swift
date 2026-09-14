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

/// A branch or a tag, and the object it points at.
public struct RNGitReference: Equatable, Sendable {

  /// The short name, which is what a page calls it.
  public let name: String

  /// The object the reference points at.
  public let hash: String

  /// What a subject line is followed by, empty where the reference carries none.
  public let commitSubject: String

  /// Whether this is the branch the repository opens on.
  public let isDefault: Bool

  /// Whether the tag carries a message of its own.
  public let isAnnotated: Bool

  /// The tag's own message, where it has one.
  public let tagMessage: String?

  /// The first seven characters of the hash, which is how a page prints it.
  public var shortHash: String { String(hash.prefix(7)) }
}

/// A repository's branches and tags.
public struct RNGitReferenceSet: Equatable, Sendable {

  /// The branches.
  public var heads: [RNGitReference] = []

  /// The tags.
  public var tags: [RNGitReference] = []
}

/// One entry in a repository directory.
public struct RNGitTreeEntry: Equatable, Sendable {

  /// The entry's name inside its directory.
  public let name: String

  /// What the entry is: `blob`, `tree`, `commit` or `link`.
  public let kind: String

  /// The mode `git` records for it.
  public let mode: String

  /// How large the object is, and zero for anything `git` does not size.
  public let size: Int

  /// Where a symbolic link points, and nothing for anything else.
  public let linkTarget: String?
}

/// What is known about one file in a repository.
public struct RNGitBlobInfo: Equatable, Sendable {

  /// How large the object is.
  public let size: Int

  /// Whether the path names a directory rather than a file.
  public let isTree: Bool

  /// Whether the file reads as bytes rather than as text.
  public let isBinary: Bool

  /// Whether the path names a symbolic link.
  public let isSymlink: Bool

  /// Where the link points, where it is one.
  public let symlinkTarget: String?
}

/// One commit, as a list of them names it.
public struct RNGitCommitSummary: Equatable, Sendable {

  /// The commit.
  public let hash: String

  /// Its first line.
  public let subject: String

  /// Who wrote it.
  public let author: String

  /// The address the author is recorded under.
  public let authorEmail: String

  /// When it was written.
  public let timestamp: Int
}

/// What one commit did to one file.
public struct RNGitCommitFile: Equatable, Sendable {

  /// The file.
  public let path: String

  /// `A`, `D`, `M` or `R`.
  public let status: String

  /// Lines added.
  public let additions: Int

  /// Lines removed.
  public let deletions: Int
}

/// Everything a commit page reads about one commit.
public struct RNGitCommitInfo: Equatable, Sendable {

  /// The commits this one follows.
  public let parents: [String]

  /// Who wrote it.
  public let authorName: String

  /// The address the author is recorded under.
  public let authorEmail: String

  /// When it was written.
  public let authorDate: String

  /// Who committed it.
  public let committerName: String

  /// The address the committer is recorded under.
  public let committerEmail: String

  /// When it was committed.
  public let committerDate: String

  /// The message, with the whitespace around it taken off.
  public let message: String

  /// What it did to each file it touched.
  public let files: [RNGitCommitFile]

  /// The diff, where the node serves one.
  public let diff: String?
}

/// What reading a commit's signature concluded.
public struct RNGitCommitSignatureStatus: Equatable, Sendable {

  /// Whether the commit carries a signature at all.
  public let signed: Bool

  /// Whether that signature validates against the commit.
  public let valid: Bool

  /// Who signed it, where that is known.
  public let signerHash: String?

  /// Whether the signer is the commit's own author.
  public let authorMatch: Bool

  /// What a page prints about it.
  public let message: String
}

/// A repository's readme, and whether it is markdown.
public struct RNGitReadme: Equatable, Sendable {

  /// What the file holds.
  public let content: String

  /// Whether it is markdown, and so gets rendered rather than shown.
  public let isMarkdown: Bool
}

/// Reads a repository through `git`, for the pages a node serves out of it.
public struct RNGitRepositoryReader: Sendable {

  /// What runs each `git` invocation.
  public let runner: RNGitCommandRunner

  /// Creates a reader.
  public init(runner: RNGitCommandRunner = RNGitProcessRunner()) {
    self.runner = runner
  }

  /// The files a readme is looked for under, in the order they are looked for.
  static let readmeNames: [(name: String, isMarkdown: Bool)] = [
    ("README.mu", false), ("Readme.mu", false), ("readme.mu", false), ("README", false),
    ("readme", false), ("README.md", true), ("readme.md", true), ("README.rst", false),
    ("README.txt", false), ("readme.rst", false), ("readme.txt", false),
  ]

  /// What separates one field from the next in a commit list.
  static let commitSeparator = "|_SEP_|"

  // MARK: - Repository

  /// What the repository says it is, from its configuration or from the file beside it.
  public func description(of repository: String) -> String? {
    if let configured = git(["config", "--get", "repository.description"], in: repository),
      configured.status == 0
    {
      let text = trimmed(configured.standardOutput)
      if !text.isEmpty { return text }
    }

    let beside = repository + ".description"
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: beside, isDirectory: &isDirectory),
      !isDirectory.boolValue,
      let described = try? String(contentsOfFile: beside, encoding: .utf8)
    else { return nil }
    let text = trimmed(described)
    return text.isEmpty ? nil : text
  }

  /// The repository's branches and tags, with nothing read about what they point at.
  public func references(of repository: String) -> RNGitReferenceSet {
    var references = RNGitReferenceSet()
    guard
      let listed = git(
        [
          "for-each-ref", "--format", "%(objectname) %(refname) %(refname:short)", "refs/heads",
          "refs/tags",
        ], in: repository), listed.status == 0
    else { return references }

    for line in lines(of: listed.standardOutput) {
      let parts = split(line, on: " ", keeping: 3)
      guard parts.count >= 2 else { continue }
      let reference = RNGitReference(
        name: parts.count > 2 ? parts[2] : parts[1], hash: parts[0], commitSubject: "",
        isDefault: false, isAnnotated: false, tagMessage: nil)
      if parts[1].hasPrefix("refs/heads/") {
        references.heads.append(reference)
      } else if parts[1].hasPrefix("refs/tags/") {
        references.tags.append(reference)
      }
    }
    return references
  }

  /// The repository's branches and tags, with what each one points at.
  public func referenceDetails(of repository: String, defaultBranch: String? = nil)
    -> RNGitReferenceSet
  {
    var references = RNGitReferenceSet()
    guard
      let listed = git(
        [
          "for-each-ref", "--format=%(objectname)|%(refname)|%(refname:short)|%(subject)",
          "refs/heads", "refs/tags",
        ], in: repository), listed.status == 0
    else { return references }

    for line in lines(of: listed.standardOutput) {
      let parts = split(line, on: "|", keeping: 4)
      guard parts.count >= 3 else { continue }
      let name = parts[2]
      let reference = RNGitReference(
        name: name, hash: parts[0], commitSubject: parts.count > 3 ? parts[3] : "",
        isDefault: name == defaultBranch, isAnnotated: false, tagMessage: nil)

      if parts[1].hasPrefix("refs/heads/") {
        references.heads.append(reference)
      } else if parts[1].hasPrefix("refs/tags/") {
        references.tags.append(annotation(of: reference, named: parts[1], in: repository))
      }
    }
    return references
  }

  /// `reference` with its own message, where it is a tag that carries one.
  private func annotation(
    of reference: RNGitReference, named refName: String, in repository: String
  )
    -> RNGitReference
  {
    guard
      let read = git(
        ["for-each-ref", "--format=%(objecttype)|%(contents:subject)", refName], in: repository),
      read.status == 0
    else { return reference }

    let parts = split(trimmed(read.standardOutput), on: "|", keeping: 2)
    guard parts.count >= 2, parts[0] == "tag" else { return reference }
    return RNGitReference(
      name: reference.name, hash: reference.hash, commitSubject: reference.commitSubject,
      isDefault: reference.isDefault, isAnnotated: true, tagMessage: parts[1])
  }

  /// The object `ref` names, or nothing where it names none.
  public func resolve(_ ref: String, in repository: String) -> String? {
    guard let resolved = git(["rev-parse", "--verify", ref], in: repository),
      resolved.status == 0
    else { return nil }
    return GitReferenceNames.sanitiseObjectID(trimmed(resolved.standardOutput).lowercased())
  }

  // MARK: - Trees and blobs

  /// What `path` holds at `ref`, empty where it is an empty directory and nothing where it is
  /// not a directory at all.
  public func treeEntries(in repository: String, at ref: String, path: String) -> [RNGitTreeEntry]?
  {
    let treePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let target = treePath.isEmpty ? ref : ref + ":" + treePath

    guard let listed = git(["ls-tree", "-l", target], in: repository) else { return nil }
    guard listed.status == 0 else {
      guard let kind = git(["cat-file", "-t", target], in: repository), kind.status == 0,
        trimmed(kind.standardOutput) == "tree"
      else { return nil }
      return []
    }

    var entries: [RNGitTreeEntry] = []
    for line in lines(of: listed.standardOutput) {
      let halves = split(line, on: "\t", keeping: 2)
      guard halves.count == 2 else { continue }
      let meta = halves[0].split(whereSeparator: \.isWhitespace).map(String.init)
      guard meta.count >= 3 else { continue }

      let name = halves[1]
      let mode = meta[0]
      var kind = meta[1]
      let size = meta.count >= 4 ? Int(meta[3]) ?? 0 : 0
      var linkTarget: String?

      if mode == "120000" {
        kind = "link"
        let shown = treePath.isEmpty ? ref + ":" + name : ref + ":" + treePath + "/" + name
        if let read = git(["show", shown], in: repository), read.status == 0 {
          linkTarget = trimmed(read.standardOutput)
        }
      }

      entries.append(
        RNGitTreeEntry(name: name, kind: kind, mode: mode, size: size, linkTarget: linkTarget))
    }
    return entries
  }

  /// What is known about the file at `path`, or nothing where there is no such object.
  public func blobInfo(in repository: String, at ref: String, path: String) -> RNGitBlobInfo? {
    let filePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    guard let sized = git(["cat-file", "-s", ref + ":" + filePath], in: repository),
      sized.status == 0, let size = Int(trimmed(sized.standardOutput))
    else { return nil }

    let treeTarget = filePath.isEmpty ? ref : ref + ":" + filePath
    let isTree = git(["ls-tree", treeTarget], in: repository)?.status == 0

    let components = filePath.components(separatedBy: "/")
    let parent = components.dropLast().joined(separator: "/")
    let filename = components[components.count - 1]
    var isSymlink = false
    if let listed = git(["ls-tree", parent.isEmpty ? ref : ref + ":" + parent], in: repository),
      listed.status == 0
    {
      isSymlink = lines(of: listed.standardOutput).contains {
        $0.contains("\t" + filename) && $0.hasPrefix("120000")
      }
    }

    var symlinkTarget: String?
    if isSymlink, let read = git(["show", ref + ":" + filePath], in: repository), read.status == 0 {
      symlinkTarget = trimmed(read.standardOutput)
    }

    var isBinary = false
    if !isSymlink, let sample = bytes(["show", ref + ":" + filePath], in: repository),
      sample.status == 0
    {
      if sample.standardOutput.prefix(8192).contains(0) {
        isBinary = true
      } else if let compared = git(
        ["diff", "--numstat", "--no-index", "--", "/dev/null", ref + ":" + filePath],
        in: repository), compared.status == 1
      {
        isBinary = trimmed(compared.standardOutput).components(separatedBy: "\n")[0]
          .hasPrefix("-")
      }
    }

    return RNGitBlobInfo(
      size: size, isTree: isTree, isBinary: isBinary, isSymlink: isSymlink,
      symlinkTarget: symlinkTarget)
  }

  /// What the file at `path` holds, or nothing where there is no such object.
  public func blobContent(in repository: String, at ref: String, path: String) -> String? {
    let filePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let read = git(["show", ref + ":" + filePath], in: repository), read.status == 0 else {
      return nil
    }
    return read.standardOutput
  }

  /// The repository's readme, under whichever of the names it carries one.
  public func readme(of repository: String) -> RNGitReadme? {
    for candidate in Self.readmeNames {
      if let read = runner.run(
        "git", arguments: ["show", "HEAD:" + candidate.name], in: repository), read.status == 0
      {
        return RNGitReadme(content: read.standardOutput, isMarkdown: candidate.isMarkdown)
      }
    }
    return nil
  }

  // MARK: - Commits

  /// How many commits `ref` has behind it, and none where it names nothing.
  public func commitCount(in repository: String, at ref: String) -> Int {
    guard let counted = git(["rev-list", "--count", ref], in: repository), counted.status == 0
    else { return 0 }
    return Int(trimmed(counted.standardOutput)) ?? 0
  }

  /// The commits behind `ref`, newest first, or nothing where `ref` names nothing.
  public func commits(
    in repository: String, at ref: String, path: String?, skip: Int, limit: Int
  ) -> [RNGitCommitSummary]? {
    let separator = Self.commitSeparator
    var arguments = [
      "log",
      "--format=%H\(separator)%s\(separator)%an\(separator)%ae\(separator)%at",
      "--skip", String(skip), "-n", String(limit), ref,
    ]
    if let path, !path.isEmpty { arguments += ["--", path] }

    guard let listed = git(arguments, in: repository), listed.status == 0 else { return nil }

    var summaries: [RNGitCommitSummary] = []
    for line in lines(of: listed.standardOutput) {
      let parts = split(line, on: separator, keeping: 5)
      guard parts.count >= 5 else { continue }
      guard let timestamp = Int(parts[4]) else { return nil }
      summaries.append(
        RNGitCommitSummary(
          hash: parts[0], subject: parts[1], author: parts[2], authorEmail: parts[3],
          timestamp: timestamp))
    }
    return summaries
  }

  /// Everything a commit page reads about `commit`, or nothing where there is no such commit.
  public func commitInfo(in repository: String, of commit: String) -> RNGitCommitInfo? {
    let format = "%P%n%an%n%ae%n%aI%n%cn%n%ce%n%cI%n%B"
    guard let shown = git(["show", "--no-patch", "--format=" + format, commit], in: repository),
      shown.status == 0
    else { return nil }

    let read = shown.standardOutput.components(separatedBy: "\n")
    guard read.count >= 7 else { return nil }
    let parents = trimmed(read[0]).split(whereSeparator: \.isWhitespace).map(String.init)

    return RNGitCommitInfo(
      parents: parents, authorName: read[1], authorEmail: read[2], authorDate: read[3],
      committerName: read[4], committerEmail: read[5], committerDate: read[6],
      message: trimmed(read[7...].joined(separator: "\n")),
      files: changes(in: repository, of: commit, against: parents.first),
      diff: RNGitPage.showDiffByDefault ? diff(in: repository, of: commit) : nil)
  }

  /// What `commit` did to each file it touched.
  private func changes(in repository: String, of commit: String, against parent: String?)
    -> [RNGitCommitFile]
  {
    guard let counted = git(["diff-tree", "--numstat", "-r", commit], in: repository),
      counted.status == 0
    else { return [] }

    var files: [RNGitCommitFile] = []
    for line in lines(of: counted.standardOutput) {
      let parts = line.components(separatedBy: "\t")
      guard parts.count >= 3 else { continue }
      var additions = parts[0]
      var deletions = parts[1]
      let path = parts[2]

      var status = "M"
      if additions == "-" && deletions == "-" {
        status = "R"
        additions = "0"
        deletions = "0"
      }

      if let parent {
        if git(["cat-file", "-e", parent + ":" + path], in: repository)?.status != 0 {
          status = "A"
        } else if git(["cat-file", "-e", commit + ":" + path], in: repository)?.status != 0 {
          status = "D"
        }
      }

      var added = 0
      var removed = 0
      if let readAdded = Int(additions), let readRemoved = Int(deletions) {
        added = readAdded
        removed = readRemoved
      }

      files.append(
        RNGitCommitFile(path: path, status: status, additions: added, deletions: removed))
    }
    return files
  }

  /// What `commit` changed, as a diff.
  private func diff(in repository: String, of commit: String) -> String? {
    guard let shown = git(["show", "--format=", commit], in: repository), shown.status == 0 else {
      return nil
    }
    return shown.standardOutput
  }

  // MARK: - Signatures

  /// What the signature on `commit` says about who wrote it.
  ///
  /// The verdict is reached without asking what namespace the envelope was signed under, so a
  /// signature made for something other than `git` is read here as the signature it is.
  public func commitSignature(in repository: String, of commit: String)
    -> RNGitCommitSignatureStatus
  {
    guard let object = git(["cat-file", "-p", commit], in: repository), object.status == 0 else {
      return unsigned("Could not read commit object")
    }

    var signatureLines: [String] = []
    var signedLines: [String] = []
    var inSignature = false
    for line in object.standardOutput.components(separatedBy: "\n") {
      if line.hasPrefix("gpgsig ") || line.hasPrefix("gpgsig-sha256 ") {
        inSignature = true
        let start = line.firstIndex(of: " ").map(line.index(after:)) ?? line.endIndex
        signatureLines.append(String(line[start...]))
      } else if inSignature {
        if line.hasPrefix(" ") {
          signatureLines.append(String(line.dropFirst()))
        } else {
          inSignature = false
          signedLines.append(line)
        }
      } else {
        signedLines.append(line)
      }
    }

    guard !signatureLines.isEmpty else { return unsigned("Not signed") }
    let signedContent = Data(signedLines.joined(separator: "\n").utf8)

    guard let blob = try? SSHSignature.unarmour(signatureLines.joined(separator: "\n")) else {
      return signedButInvalid("Signature validation error")
    }
    guard let envelope = try? SSHSignature.parse(blob) else {
      return signedButInvalid("Malformed SSH wrapping for RSG data")
    }
    guard
      let result = try? RSG.validate(
        rsgData: envelope.signatureData, message: .bytes(signedContent), requiredSigner: .none),
      result.isValid, let identity = result.signingIdentity
    else { return signedButInvalid("Invalid signature") }

    let signer = RNSUtilities.hexrep(identity.hash, delimit: false)
    let author = GitCommitHeaders.author(in: signedContent)
    if author.isEmpty {
      return RNGitCommitSignatureStatus(
        signed: true, valid: true, signerHash: signer, authorMatch: false,
        message: "Could not verify author")
    }
    if author == signer {
      return RNGitCommitSignatureStatus(
        signed: true, valid: true, signerHash: signer, authorMatch: true,
        message: "Valid, signed by <\(signer)>")
    }
    return RNGitCommitSignatureStatus(
      signed: true, valid: true, signerHash: signer, authorMatch: false,
      message: "Invalid signer <\(signer)>, author is <\(author)>")
  }

  /// A verdict on a commit that carries no signature to reach one from.
  private func unsigned(_ message: String) -> RNGitCommitSignatureStatus {
    RNGitCommitSignatureStatus(
      signed: false, valid: false, signerHash: nil, authorMatch: false, message: message)
  }

  /// A verdict on a commit that carries a signature that does not stand.
  private func signedButInvalid(_ message: String) -> RNGitCommitSignatureStatus {
    RNGitCommitSignatureStatus(
      signed: true, valid: false, signerHash: nil, authorMatch: false, message: message)
  }

  // MARK: - Running git

  /// Runs `git` with `arguments` in `repository`.
  private func git(_ arguments: [String], in repository: String) -> RNGitCommandOutput? {
    runner.run("git", arguments: arguments, in: repository)
  }

  /// Runs `git` with `arguments` in `repository`, answering what it wrote as bytes.
  private func bytes(_ arguments: [String], in repository: String) -> RNGitCommandBytes? {
    runner.run(bytes: "git", arguments: arguments, in: repository)
  }

  /// `text` with the whitespace around it taken off.
  private func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The lines `text` holds once the whitespace around it is taken off, blank ones dropped.
  private func lines(of text: String) -> [String] {
    trimmed(text).components(separatedBy: "\n").filter { !trimmed($0).isEmpty }
  }

  /// `text` cut on `separator` into at most `keeping` pieces, the last keeping every separator
  /// left in it.
  private func split(_ text: String, on separator: String, keeping: Int) -> [String] {
    var pieces: [String] = []
    var rest = Substring(text)
    while pieces.count < keeping - 1, let found = rest.range(of: separator) {
      pieces.append(String(rest[rest.startIndex..<found.lowerBound]))
      rest = rest[found.upperBound...]
    }
    pieces.append(String(rest))
    return pieces
  }
}
