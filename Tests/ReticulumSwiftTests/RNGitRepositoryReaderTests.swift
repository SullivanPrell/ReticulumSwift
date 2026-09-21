//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest

@testable import ReticulumSwift

/// Reading a repository, as Python RNS 1.5.4 reads one.
///
/// Every expectation is what the reference answered for the repository this suite builds. The
/// repository is built from fixed content under fixed names, dates and addresses, so `git`
/// records the same object for it on any machine and the recorded hashes hold.
final class RNGitRepositoryReaderTests: XCTestCase {

  /// Where this test's repository stands.
  private var base = ""

  /// The repository itself.
  private var repository: String { base + "/repo" }

  /// The reader under test.
  private let reader = RNGitRepositoryReader()

  override func setUpWithError() throws {
    try super.setUpWithError()
    base = NSTemporaryDirectory() + "/rngit-reader-" + UUID().uuidString
    try FileManager.default.createDirectory(
      atPath: base, withIntermediateDirectories: true)
    let script = base + "/build.sh"
    try Self.fixtureScript.write(toFile: script, atomically: true, encoding: .utf8)
    let built = RNGitProcessRunner().run("sh", arguments: [script, repository], in: base)
    try XCTSkipIf(built == nil, "no shell to build the repository with")
    XCTAssertEqual(built?.status, 0, built?.standardError ?? "")
    for (name, object) in Self.commitObjects {
      let path = base + "/" + name + ".obj"
      try object.write(toFile: path, atomically: true, encoding: .utf8)
      let written = RNGitProcessRunner().run(
        "git", arguments: ["hash-object", "-w", "-t", "commit", path], in: repository)
      XCTAssertEqual(written?.status, 0, name)
    }
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: base)
    super.tearDown()
  }

  /// A repository's description comes from its configuration, and then from the file beside it.
  func testTheDescriptionMatchesTheReference() throws {
    XCTAssertEqual(reader.description(of: repository), "A configured description")

    let unset = RNGitProcessRunner().run(
      "git", arguments: ["config", "--unset", "repository.description"], in: repository)
    XCTAssertEqual(unset?.status, 0)
    XCTAssertEqual(reader.description(of: repository), nil)

    try "  A described repository\n".write(
      toFile: repository + ".description", atomically: true, encoding: .utf8)
    XCTAssertEqual(reader.description(of: repository), "A described repository")

    try "   \n".write(toFile: repository + ".description", atomically: true, encoding: .utf8)
    XCTAssertEqual(reader.description(of: repository), nil)
  }

  /// The branches and tags are the ones the reference listed, pointing where it said.
  func testTheReferencesMatchTheReference() {
    let references = reader.references(of: repository)
    XCTAssertEqual(references.heads.count, 2)
    XCTAssertEqual(references.heads[0].name, "main")
    XCTAssertEqual(references.heads[0].hash, "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(references.heads[0].shortHash, "ef12603")
    XCTAssertEqual(references.heads[1].name, "other")
    XCTAssertEqual(references.heads[1].hash, "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(references.heads[1].shortHash, "ef12603")
    XCTAssertEqual(references.tags.count, 2)
    XCTAssertEqual(references.tags[0].name, "annotated")
    XCTAssertEqual(references.tags[0].hash, "6d0cf04c3ea029c45af0ddb76f0f2aed2a86008b")
    XCTAssertEqual(references.tags[0].shortHash, "6d0cf04")
    XCTAssertEqual(references.tags[1].name, "light")
    XCTAssertEqual(references.tags[1].hash, "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(references.tags[1].shortHash, "ef12603")
  }

  /// A repository that is not there has no branches and no tags.
  func testAMissingRepositoryHasNoReferences() {
    let references = reader.references(of: base + "/nothing")
    XCTAssertEqual(references.heads, [])
    XCTAssertEqual(references.tags, [])
  }

  /// `HEAD` is a symbolic ref to `main`, the way the fixture script points it.
  func testTheDefaultBranchMatchesTheReference() {
    XCTAssertEqual(reader.defaultBranch(of: repository), "main")
  }

  /// A repository that is not there points `HEAD` at nothing.
  func testAMissingRepositoryHasNoDefaultBranch() {
    XCTAssertEqual(reader.defaultBranch(of: base + "/nothing"), nil)
  }

  /// A repository with no `.work/active` directory at all has no active work.
  func testActiveWorkDocumentCountIsZeroWithNoWorkDirectory() {
    XCTAssertEqual(reader.activeWorkDocumentCount(of: repository), 0)
  }

  /// Only numerically-named directories are counted: a non-numeric directory and a file that
  /// merely happens to have a numeric name are both skipped, matching the reference's own
  /// `f.isdigit() and os.path.isdir(...)` filter.
  func testActiveWorkDocumentCountCountsOnlyNumericDirectories() throws {
    let active = repository + ".work/active"
    try FileManager.default.createDirectory(
      atPath: active, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      atPath: active + "/1", withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      atPath: active + "/2", withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      atPath: active + "/not-a-number", withIntermediateDirectories: true)
    try "not a directory".write(
      toFile: active + "/3", atomically: true, encoding: .utf8)

    XCTAssertEqual(reader.activeWorkDocumentCount(of: repository), 2)
  }

  /// Each branch and tag carries what the reference read about it.
  func testTheReferenceDetailsMatchTheReference() {
    let details = reader.referenceDetails(of: repository, defaultBranch: "main")
    XCTAssertEqual(details.heads.count, 2)
    XCTAssertEqual(details.heads[0].name, "main")
    XCTAssertEqual(details.heads[0].hash, "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(
      details.heads[0].commitSubject, "Second commit")
    XCTAssertTrue(details.heads[0].isDefault)
    XCTAssertFalse(details.heads[0].isAnnotated)
    XCTAssertEqual(details.heads[0].tagMessage, nil)
    XCTAssertEqual(details.heads[1].name, "other")
    XCTAssertEqual(details.heads[1].hash, "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(
      details.heads[1].commitSubject, "Second commit")
    XCTAssertFalse(details.heads[1].isDefault)
    XCTAssertFalse(details.heads[1].isAnnotated)
    XCTAssertEqual(details.heads[1].tagMessage, nil)
    XCTAssertEqual(details.tags.count, 2)
    XCTAssertEqual(details.tags[0].name, "annotated")
    XCTAssertEqual(details.tags[0].hash, "6d0cf04c3ea029c45af0ddb76f0f2aed2a86008b")
    XCTAssertEqual(
      details.tags[0].commitSubject, "An annotated tag")
    XCTAssertFalse(details.tags[0].isDefault)
    XCTAssertTrue(details.tags[0].isAnnotated)
    XCTAssertEqual(details.tags[0].tagMessage, "An annotated tag")
    XCTAssertEqual(details.tags[1].name, "light")
    XCTAssertEqual(details.tags[1].hash, "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(
      details.tags[1].commitSubject, "Second commit")
    XCTAssertFalse(details.tags[1].isDefault)
    XCTAssertFalse(details.tags[1].isAnnotated)
    XCTAssertEqual(details.tags[1].tagMessage, nil)
  }

  /// Without a default branch named, no branch is the default one.
  func testNoBranchIsTheDefaultUntilOneIsNamed() {
    let details = reader.referenceDetails(of: repository)
    XCTAssertEqual(details.heads.filter(\.isDefault), [])
  }

  /// Every recorded reference resolves to the object the reference resolved it to.
  func testEveryReferenceResolvesAsTheReferenceResolvedIt() {
    XCTAssertEqual(
      reader.resolve("HEAD", in: repository), "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(
      reader.resolve("main", in: repository), "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(
      reader.resolve("other", in: repository), "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(
      reader.resolve("light", in: repository), "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(
      reader.resolve("annotated", in: repository), "6d0cf04c3ea029c45af0ddb76f0f2aed2a86008b")
    XCTAssertEqual(
      reader.resolve("HEAD~1", in: repository), "317b7674f36fccdeed8f32e78c9eded0f3f17486")
    XCTAssertEqual(
      reader.resolve("refs/heads/main", in: repository), "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d")
    XCTAssertEqual(reader.resolve("nonexistent", in: repository), nil)
    XCTAssertEqual(reader.resolve("", in: repository), nil)
    XCTAssertEqual(
      reader.resolve("HEAD^{tree}", in: repository), "6670979f4915ccc75e90c7b3452026a4753d6768")
  }

  /// Every recorded directory reads as the reference read it.
  func testEveryTreeMatchesTheReference() {
    XCTAssertEqual(
      reader.treeEntries(in: repository, at: "HEAD", path: ""),
      [
        RNGitTreeEntry(
          name: "README.md", kind: "blob", mode: "100644", size: 26, linkTarget: nil),
        RNGitTreeEntry(
          name: "README.mu", kind: "blob", mode: "100644", size: 16, linkTarget: nil),
        RNGitTreeEntry(
          name: "added.txt", kind: "blob", mode: "100644", size: 6, linkTarget: nil),
        RNGitTreeEntry(
          name: "binary.bin", kind: "blob", mode: "100644", size: 21, linkTarget: nil),
        RNGitTreeEntry(
          name: "kept.txt", kind: "blob", mode: "100644", size: 26, linkTarget: nil),
        RNGitTreeEntry(
          name: "late_binary.bin", kind: "blob", mode: "100644", size: 28, linkTarget: nil),
        RNGitTreeEntry(
          name: "link.txt", kind: "link", mode: "120000", size: 8, linkTarget: "kept.txt"),
        RNGitTreeEntry(
          name: "src", kind: "tree", mode: "040000", size: 0, linkTarget: nil),
      ])
    XCTAssertEqual(
      reader.treeEntries(in: repository, at: "HEAD", path: "/"),
      [
        RNGitTreeEntry(
          name: "README.md", kind: "blob", mode: "100644", size: 26, linkTarget: nil),
        RNGitTreeEntry(
          name: "README.mu", kind: "blob", mode: "100644", size: 16, linkTarget: nil),
        RNGitTreeEntry(
          name: "added.txt", kind: "blob", mode: "100644", size: 6, linkTarget: nil),
        RNGitTreeEntry(
          name: "binary.bin", kind: "blob", mode: "100644", size: 21, linkTarget: nil),
        RNGitTreeEntry(
          name: "kept.txt", kind: "blob", mode: "100644", size: 26, linkTarget: nil),
        RNGitTreeEntry(
          name: "late_binary.bin", kind: "blob", mode: "100644", size: 28, linkTarget: nil),
        RNGitTreeEntry(
          name: "link.txt", kind: "link", mode: "120000", size: 8, linkTarget: "kept.txt"),
        RNGitTreeEntry(
          name: "src", kind: "tree", mode: "040000", size: 0, linkTarget: nil),
      ])
    XCTAssertEqual(
      reader.treeEntries(in: repository, at: "HEAD", path: "src"),
      [
        RNGitTreeEntry(
          name: "deep", kind: "tree", mode: "040000", size: 0, linkTarget: nil),
        RNGitTreeEntry(
          name: "main.rs", kind: "blob", mode: "100644", size: 13, linkTarget: nil),
      ])
    XCTAssertEqual(
      reader.treeEntries(in: repository, at: "HEAD", path: "/src/"),
      [
        RNGitTreeEntry(
          name: "deep", kind: "tree", mode: "040000", size: 0, linkTarget: nil),
        RNGitTreeEntry(
          name: "main.rs", kind: "blob", mode: "100644", size: 13, linkTarget: nil),
      ])
    XCTAssertEqual(
      reader.treeEntries(in: repository, at: "HEAD", path: "src/deep"),
      [
        RNGitTreeEntry(
          name: "file.txt", kind: "blob", mode: "100644", size: 5, linkTarget: nil)
      ])
    XCTAssertNil(reader.treeEntries(in: repository, at: "HEAD", path: "nope"))
    XCTAssertNil(reader.treeEntries(in: repository, at: "HEAD", path: "kept.txt"))
    XCTAssertEqual(
      reader.treeEntries(in: repository, at: "HEAD~1", path: ""),
      [
        RNGitTreeEntry(
          name: "README.md", kind: "blob", mode: "100644", size: 26, linkTarget: nil),
        RNGitTreeEntry(
          name: "README.mu", kind: "blob", mode: "100644", size: 16, linkTarget: nil),
        RNGitTreeEntry(
          name: "binary.bin", kind: "blob", mode: "100644", size: 21, linkTarget: nil),
        RNGitTreeEntry(
          name: "kept.txt", kind: "blob", mode: "100644", size: 18, linkTarget: nil),
        RNGitTreeEntry(
          name: "late_binary.bin", kind: "blob", mode: "100644", size: 28, linkTarget: nil),
        RNGitTreeEntry(
          name: "link.txt", kind: "link", mode: "120000", size: 8, linkTarget: "kept.txt"),
        RNGitTreeEntry(
          name: "removed.txt", kind: "blob", mode: "100644", size: 10, linkTarget: nil),
        RNGitTreeEntry(
          name: "src", kind: "tree", mode: "040000", size: 0, linkTarget: nil),
      ])
    XCTAssertNil(reader.treeEntries(in: repository, at: "nonexistent", path: ""))
    XCTAssertEqual(
      reader.treeEntries(in: repository, at: "main", path: "src"),
      [
        RNGitTreeEntry(
          name: "deep", kind: "tree", mode: "040000", size: 0, linkTarget: nil),
        RNGitTreeEntry(
          name: "main.rs", kind: "blob", mode: "100644", size: 13, linkTarget: nil),
      ])
  }

  /// Every recorded file reads as the reference read it.
  func testEveryBlobMatchesTheReference() {
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD", path: "kept.txt"),
      RNGitBlobInfo(
        size: 26, isTree: false, isBinary: false, isSymlink: false, symlinkTarget: nil))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD", path: "kept.txt"),
      "line one\nline two changed\n")
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD", path: "/kept.txt"),
      RNGitBlobInfo(
        size: 26, isTree: false, isBinary: false, isSymlink: false, symlinkTarget: nil))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD", path: "/kept.txt"),
      "line one\nline two changed\n")
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD", path: "binary.bin"),
      RNGitBlobInfo(
        size: 21, isTree: false, isBinary: true, isSymlink: false, symlinkTarget: nil))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD", path: "binary.bin"),
      "a\u{0}b\u{0}c binary payload\n")
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD", path: "link.txt"),
      RNGitBlobInfo(
        size: 8, isTree: false, isBinary: false, isSymlink: true, symlinkTarget: "kept.txt"))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD", path: "link.txt"),
      "kept.txt")
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD", path: "src/main.rs"),
      RNGitBlobInfo(
        size: 13, isTree: false, isBinary: false, isSymlink: false, symlinkTarget: nil))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD", path: "src/main.rs"),
      "fn main() {}\n")
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD", path: "src"),
      RNGitBlobInfo(
        size: 66, isTree: true, isBinary: false, isSymlink: false, symlinkTarget: nil))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD", path: "src"),
      "tree HEAD:src\n\ndeep/\nmain.rs\n")
    XCTAssertNil(reader.blobInfo(in: repository, at: "HEAD", path: "nope.txt"))
    XCTAssertNil(reader.blobContent(in: repository, at: "HEAD", path: "nope.txt"))
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD~1", path: "removed.txt"),
      RNGitBlobInfo(
        size: 10, isTree: false, isBinary: false, isSymlink: false, symlinkTarget: nil))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD~1", path: "removed.txt"),
      "goes away\n")
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD", path: "added.txt"),
      RNGitBlobInfo(
        size: 6, isTree: false, isBinary: false, isSymlink: false, symlinkTarget: nil))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD", path: "added.txt"),
      "added\n")
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD", path: "late_binary.bin"),
      RNGitBlobInfo(
        size: 28, isTree: false, isBinary: true, isSymlink: false, symlinkTarget: nil))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD", path: "late_binary.bin"),
      "plain text here\u{0}then binary\n")
    XCTAssertEqual(
      reader.blobInfo(in: repository, at: "HEAD", path: "README.mu"),
      RNGitBlobInfo(
        size: 16, isTree: false, isBinary: false, isSymlink: false, symlinkTarget: nil))
    XCTAssertEqual(
      reader.blobContent(in: repository, at: "HEAD", path: "README.mu"),
      "A micron readme\n")
  }

  /// Every recorded count reads as the reference counted it.
  func testEveryCommitCountMatchesTheReference() {
    XCTAssertEqual(reader.commitCount(in: repository, at: "HEAD"), 2)
    XCTAssertEqual(reader.commitCount(in: repository, at: "main"), 2)
    XCTAssertEqual(reader.commitCount(in: repository, at: "HEAD~1"), 1)
    XCTAssertEqual(reader.commitCount(in: repository, at: "nonexistent"), 0)
  }

  /// Every recorded listing reads as the reference listed it.
  func testEveryCommitListingMatchesTheReference() {
    XCTAssertEqual(
      reader.commits(
        in: repository, at: "HEAD", path: nil, skip: 0, limit: 10),
      [
        RNGitCommitSummary(
          hash: "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d", subject: "Second commit",
          author: "Author", authorEmail: "9710b86ba12c42d1d8f30f74fe509286",
          timestamp: 1_700_003_600),
        RNGitCommitSummary(
          hash: "317b7674f36fccdeed8f32e78c9eded0f3f17486", subject: "First commit",
          author: "Author", authorEmail: "9710b86ba12c42d1d8f30f74fe509286",
          timestamp: 1_700_000_000),
      ])
    XCTAssertEqual(
      reader.commits(
        in: repository, at: "HEAD", path: nil, skip: 1, limit: 10),
      [
        RNGitCommitSummary(
          hash: "317b7674f36fccdeed8f32e78c9eded0f3f17486", subject: "First commit",
          author: "Author", authorEmail: "9710b86ba12c42d1d8f30f74fe509286",
          timestamp: 1_700_000_000)
      ])
    XCTAssertEqual(
      reader.commits(
        in: repository, at: "HEAD", path: nil, skip: 0, limit: 1),
      [
        RNGitCommitSummary(
          hash: "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d", subject: "Second commit",
          author: "Author", authorEmail: "9710b86ba12c42d1d8f30f74fe509286",
          timestamp: 1_700_003_600)
      ])
    XCTAssertEqual(
      reader.commits(
        in: repository, at: "HEAD", path: "kept.txt", skip: 0, limit: 10),
      [
        RNGitCommitSummary(
          hash: "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d", subject: "Second commit",
          author: "Author", authorEmail: "9710b86ba12c42d1d8f30f74fe509286",
          timestamp: 1_700_003_600),
        RNGitCommitSummary(
          hash: "317b7674f36fccdeed8f32e78c9eded0f3f17486", subject: "First commit",
          author: "Author", authorEmail: "9710b86ba12c42d1d8f30f74fe509286",
          timestamp: 1_700_000_000),
      ])
    XCTAssertEqual(
      reader.commits(
        in: repository, at: "HEAD", path: "added.txt", skip: 0, limit: 10),
      [
        RNGitCommitSummary(
          hash: "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d", subject: "Second commit",
          author: "Author", authorEmail: "9710b86ba12c42d1d8f30f74fe509286",
          timestamp: 1_700_003_600)
      ])
    XCTAssertEqual(
      reader.commits(
        in: repository, at: "HEAD", path: "nope.txt", skip: 0, limit: 10),
      [])
    XCTAssertEqual(
      reader.commits(
        in: repository, at: "HEAD", path: nil, skip: 5, limit: 10),
      [])
    XCTAssertNil(
      reader.commits(
        in: repository, at: "nonexistent", path: nil, skip: 0, limit: 10))
  }

  /// The head commit reads as the reference read it.
  func testTheHeadCommitMatchesTheReference() throws {
    let info = try XCTUnwrap(
      reader.commitInfo(in: repository, of: "ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d"))
    XCTAssertEqual(info.parents, ["317b7674f36fccdeed8f32e78c9eded0f3f17486"])
    XCTAssertEqual(info.authorName, "Author")
    XCTAssertEqual(info.authorEmail, "9710b86ba12c42d1d8f30f74fe509286")
    XCTAssertEqual(info.authorDate, "2023-11-14T23:13:20Z")
    XCTAssertEqual(info.committerName, "Committer")
    XCTAssertEqual(info.committerEmail, "ef330a1940c70349459fc4401d273cb9")
    XCTAssertEqual(info.committerDate, "2023-11-14T23:13:20Z")
    XCTAssertEqual(info.message, "Second commit\n\nA body line, and a \\backslash.")
    XCTAssertEqual(
      info.files,
      [
        RNGitCommitFile(
          path: "added.txt", status: "A", additions: 1, deletions: 0),
        RNGitCommitFile(
          path: "kept.txt", status: "M", additions: 1, deletions: 1),
        RNGitCommitFile(
          path: "removed.txt", status: "D", additions: 0, deletions: 1),
      ])
    XCTAssertEqual(info.diff, Self.headDiff)
  }

  /// The first commit reads as the reference read it.
  func testTheFirstCommitMatchesTheReference() throws {
    let info = try XCTUnwrap(
      reader.commitInfo(in: repository, of: "317b7674f36fccdeed8f32e78c9eded0f3f17486"))
    XCTAssertEqual(info.parents, [])
    XCTAssertEqual(info.authorName, "Author")
    XCTAssertEqual(info.authorEmail, "9710b86ba12c42d1d8f30f74fe509286")
    XCTAssertEqual(info.authorDate, "2023-11-14T22:13:20Z")
    XCTAssertEqual(info.committerName, "Committer")
    XCTAssertEqual(info.committerEmail, "ef330a1940c70349459fc4401d273cb9")
    XCTAssertEqual(info.committerDate, "2023-11-14T22:13:20Z")
    XCTAssertEqual(info.message, "First commit")
    XCTAssertEqual(
      info.files,
      [])
    XCTAssertEqual(info.diff, Self.firstDiff)
  }

  /// A commit that is not there reads as nothing.
  func testAMissingCommitReadsAsNothing() {
    XCTAssertNil(reader.commitInfo(in: repository, of: "nonexistent"))
  }

  /// Every recorded signature reads as the reference read it.
  func testEverySignatureMatchesTheReference() {
    XCTAssertEqual(
      reader.commitSignature(in: repository, of: "cc5c204c75a5beee272033d4b20c63d6b15bb699"),
      RNGitCommitSignatureStatus(
        signed: true, valid: true, signerHash: "9908739db197027b00bcede903330d07",
        authorMatch: true,
        message: "Valid, signed by <9908739db197027b00bcede903330d07>"), "signedByAuthor")
    XCTAssertEqual(
      reader.commitSignature(in: repository, of: "1390720afbc7c3e6090fb45db53c793c7b0df41d"),
      RNGitCommitSignatureStatus(
        signed: true, valid: true, signerHash: "9908739db197027b00bcede903330d07",
        authorMatch: false,
        message:
          "Invalid signer <9908739db197027b00bcede903330d07>, author is <856f0a1ada5f65506e18448690532e21>"
      ), "signedByAnother")
    XCTAssertEqual(
      reader.commitSignature(in: repository, of: "bf9b9c80653d361edad0b58481436fc92e158a82"),
      RNGitCommitSignatureStatus(
        signed: false, valid: false, signerHash: nil, authorMatch: false,
        message: "Not signed"), "unsigned")
    XCTAssertEqual(
      reader.commitSignature(in: repository, of: "c4ac7d5d3a896c7aa8aab0ad25b07ea62d9889a4"),
      RNGitCommitSignatureStatus(
        signed: true, valid: false, signerHash: nil, authorMatch: false,
        message: "Signature validation error"), "malformed")
    XCTAssertEqual(
      reader.commitSignature(in: repository, of: "00cdc9db21580d18705c484667b0d0d10b209111"),
      RNGitCommitSignatureStatus(
        signed: true, valid: false, signerHash: nil, authorMatch: false,
        message: "Malformed SSH wrapping for RSG data"), "badEnvelope")
    XCTAssertEqual(
      reader.commitSignature(in: repository, of: "4287ed80f837f5c125f2669bc2f6b113d5877aac"),
      RNGitCommitSignatureStatus(
        signed: true, valid: false, signerHash: nil, authorMatch: false,
        message: "Invalid signature"), "wrongContent")
    XCTAssertEqual(
      reader.commitSignature(in: repository, of: "f52cfb30a8589a5edb8ff4b6eece55b2eea353b9"),
      RNGitCommitSignatureStatus(
        signed: true, valid: true, signerHash: "9908739db197027b00bcede903330d07",
        authorMatch: true,
        message: "Valid, signed by <9908739db197027b00bcede903330d07>"), "signedSha256")
    XCTAssertEqual(
      reader.commitSignature(in: repository, of: "0000000000000000000000000000000000000000"),
      RNGitCommitSignatureStatus(
        signed: false, valid: false, signerHash: nil, authorMatch: false,
        message: "Could not read commit object"), "missing")
  }

  /// A signed commit that records no author cannot have its author verified.
  ///
  /// `git` will not write such an object, so the reference was handed it directly and the
  /// reader is handed the same through a runner that answers with it.
  func testASignedCommitWithNoAuthorCannotHaveItsAuthorVerified() {
    let reader = RNGitRepositoryReader(runner: FixedOutput(text: Self.authorlessCommit))
    XCTAssertEqual(
      reader.commitSignature(in: "/nowhere", of: "irrelevant"),
      RNGitCommitSignatureStatus(
        signed: true, valid: true, signerHash: "9908739db197027b00bcede903330d07",
        authorMatch: false,
        message: "Could not verify author"))
  }

  /// A runner that answers every command with the same output.
  private struct FixedOutput: RNGitCommandRunner {
    let text: String

    func run(_ executable: String, arguments: [String], in directory: String?)
      -> RNGitCommandOutput?
    {
      RNGitCommandOutput(status: 0, standardOutput: text, standardError: "")
    }
  }

  /// The readme reads as the reference read it.
  func testTheReadmeMatchesTheReference() throws {
    let readme = try XCTUnwrap(reader.readme(of: repository))
    XCTAssertEqual(readme.content, "A micron readme\n")
    XCTAssertFalse(readme.isMarkdown)
  }

  /// A repository with no readme has none to read.
  func testARepositoryWithNoReadmeHasNone() throws {
    let empty = base + "/bare"
    let made = RNGitProcessRunner().run("git", arguments: ["init", "-q", empty], in: base)
    XCTAssertEqual(made?.status, 0)
    XCTAssertNil(reader.readme(of: empty))
  }

  /// A repository carrying only the markdown name reads as markdown.
  ///
  /// The fixture carries both names, so the one that wins there is the micron one; this is the
  /// other side of that order.
  func testAMarkdownOnlyReadmeReadsAsMarkdown() throws {
    let only = base + "/mdonly"
    try FileManager.default.createDirectory(atPath: only, withIntermediateDirectories: true)
    let runner = RNGitProcessRunner()
    XCTAssertEqual(runner.run("git", arguments: ["init", "-q", "."], in: only)?.status, 0)
    try "# Only markdown\n".write(toFile: only + "/README.md", atomically: true, encoding: .utf8)
    XCTAssertEqual(runner.run("git", arguments: ["add", "-A"], in: only)?.status, 0)
    XCTAssertEqual(
      runner.run(
        "git",
        arguments: [
          "-c", "user.name=Author", "-c", "user.email=a", "-c", "commit.gpgsign=false",
          "commit", "-q", "-m", "md",
        ], in: only)?.status, 0)

    let readme = try XCTUnwrap(reader.readme(of: only))
    XCTAssertEqual(readme.content, "# Only markdown\n")
    XCTAssertTrue(readme.isMarkdown)
  }

  /// A ref that resolves to something no object ID could be resolves to nothing.
  ///
  /// `git rev-parse --verify` does not answer this way, so the reference was handed the answer
  /// directly and the reader is handed the same.
  func testARefResolvingToSomethingOtherThanAnObjectIDResolvesToNothing() {
    let reader = RNGitRepositoryReader(
      runner: FixedOutput(text: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n"))
    XCTAssertNil(reader.resolve("whatever", in: "/nowhere"))
  }

  /// A commit list carrying a time that will not read as a number is no list at all.
  func testACommitListCarryingAnUnreadableTimeIsNoListAtAll() {
    let reader = RNGitRepositoryReader(
      runner: FixedOutput(text: "abc|_SEP_|Subject|_SEP_|Author|_SEP_|a@b|_SEP_|not a number\n"))
    XCTAssertNil(reader.commits(in: "/nowhere", at: "HEAD", path: nil, skip: 0, limit: 10))
  }

  /// A commit shown in fewer than seven lines is not read at all.
  func testACommitShownInFewerThanSevenLinesIsNotRead() {
    let reader = RNGitRepositoryReader(runner: FixedOutput(text: "one\ntwo\nthree\n"))
    XCTAssertNil(reader.commitInfo(in: "/nowhere", of: "whatever"))
  }

  /// The commit objects this test writes into the repository, keyed by what each one shows.
  private static let commitObjects: [(String, String)] = [
    (
      "signedByAuthor",
      "tree 6670979f4915ccc75e90c7b3452026a4753d6768\nparent ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d\nauthor Author <9908739db197027b00bcede903330d07> 1700007200 +0000\ncommitter Committer <9908739db197027b00bcede903330d07> 1700007200 +0000\ngpgsig -----BEGIN SSH SIGNATURE-----\n U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgF8t5+ytBIPKx7GXkGY1uCLKOgT\n /rAeSkAIObheGAgM4AAAADZ2l0AAAAAAAAAAZzaGEyNTYAAADgwmvp2arx2JSpDysbiBI8\n 2KwtdiZIU+3vB3cei7DortfVNZKBEM+B5RNp+X2R+tu87E5/dCN0f29Up5mCBNMSBYOoaG\n FzaHR5cGWmc2hhMjU2pGhhc2jEIEJFKf2jrcvQy++tVR9vIlemVYNucTJqQV3wxFzxafJf\n pG1ldGGCpnNpZ25lcsQQmQhznbGXAnsAvO3pAzMNB6ZwdWJrZXnEQHsNR9k0J/gxEWB4HH\n xzP9ifiJcK70kNiqDuGaTLihsUF8t5+ytBIPKx7GXkGY1uCLKOgT/rAeSkAIObheGAgM4=\n -----END SSH SIGNATURE-----\n\nA signed commit\n"
    ),
    (
      "signedByAnother",
      "tree 6670979f4915ccc75e90c7b3452026a4753d6768\nparent ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d\nauthor Author <856f0a1ada5f65506e18448690532e21> 1700007200 +0000\ncommitter Committer <856f0a1ada5f65506e18448690532e21> 1700007200 +0000\ngpgsig -----BEGIN SSH SIGNATURE-----\n U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgF8t5+ytBIPKx7GXkGY1uCLKOgT\n /rAeSkAIObheGAgM4AAAADZ2l0AAAAAAAAAAZzaGEyNTYAAADgdO93WMQGlr8V3Ovzys2C\n /6xS58gY40BLCZBN73wGUiWYu02995rQeCBAsdNL0yLZ92DSqpmp7TalTfz1gZIqCYOoaG\n FzaHR5cGWmc2hhMjU2pGhhc2jEIMvCDvwjZ2V8JSALpjAr2mdTdcJCzZe3ph15CbSrcKDW\n pG1ldGGCpnNpZ25lcsQQmQhznbGXAnsAvO3pAzMNB6ZwdWJrZXnEQHsNR9k0J/gxEWB4HH\n xzP9ifiJcK70kNiqDuGaTLihsUF8t5+ytBIPKx7GXkGY1uCLKOgT/rAeSkAIObheGAgM4=\n -----END SSH SIGNATURE-----\n\nA signed commit\n"
    ),
    (
      "unsigned",
      "tree 6670979f4915ccc75e90c7b3452026a4753d6768\nparent ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d\nauthor Author <9908739db197027b00bcede903330d07> 1700007200 +0000\ncommitter Committer <9908739db197027b00bcede903330d07> 1700007200 +0000\n\nA signed commit\n"
    ),
    (
      "signedSha256",
      "tree 6670979f4915ccc75e90c7b3452026a4753d6768\nparent ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d\nauthor Author <9908739db197027b00bcede903330d07> 1700007200 +0000\ncommitter Committer <9908739db197027b00bcede903330d07> 1700007200 +0000\ngpgsig-sha256 -----BEGIN SSH SIGNATURE-----\n U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgF8t5+ytBIPKx7GXkGY1uCLKOgT\n /rAeSkAIObheGAgM4AAAADZ2l0AAAAAAAAAAZzaGEyNTYAAADgwmvp2arx2JSpDysbiBI8\n 2KwtdiZIU+3vB3cei7DortfVNZKBEM+B5RNp+X2R+tu87E5/dCN0f29Up5mCBNMSBYOoaG\n FzaHR5cGWmc2hhMjU2pGhhc2jEIEJFKf2jrcvQy++tVR9vIlemVYNucTJqQV3wxFzxafJf\n pG1ldGGCpnNpZ25lcsQQmQhznbGXAnsAvO3pAzMNB6ZwdWJrZXnEQHsNR9k0J/gxEWB4HH\n xzP9ifiJcK70kNiqDuGaTLihsUF8t5+ytBIPKx7GXkGY1uCLKOgT/rAeSkAIObheGAgM4=\n -----END SSH SIGNATURE-----\n\nA signed commit\n"
    ),
    (
      "badEnvelope",
      "tree 6670979f4915ccc75e90c7b3452026a4753d6768\nparent ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d\nauthor Author <9908739db197027b00bcede903330d07> 1700007200 +0000\ncommitter Committer <9908739db197027b00bcede903330d07> 1700007200 +0000\ngpgsig -----BEGIN SSH SIGNATURE-----\n bm90IGFuIFNTSFNJRyBlbnZlbG9wZSBhdCBhbGwsIGJ1dCB3ZWxsIGZvcm1lZCBiYXNlNjQ=\n -----END SSH SIGNATURE-----\n\nA signed commit\n"
    ),
    (
      "wrongContent",
      "tree 6670979f4915ccc75e90c7b3452026a4753d6768\nparent ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d\nauthor Author <856f0a1ada5f65506e18448690532e21> 1700007200 +0000\ncommitter Committer <856f0a1ada5f65506e18448690532e21> 1700007200 +0000\ngpgsig -----BEGIN SSH SIGNATURE-----\n U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgF8t5+ytBIPKx7GXkGY1uCLKOgT\n /rAeSkAIObheGAgM4AAAADZ2l0AAAAAAAAAAZzaGEyNTYAAADgwmvp2arx2JSpDysbiBI8\n 2KwtdiZIU+3vB3cei7DortfVNZKBEM+B5RNp+X2R+tu87E5/dCN0f29Up5mCBNMSBYOoaG\n FzaHR5cGWmc2hhMjU2pGhhc2jEIEJFKf2jrcvQy++tVR9vIlemVYNucTJqQV3wxFzxafJf\n pG1ldGGCpnNpZ25lcsQQmQhznbGXAnsAvO3pAzMNB6ZwdWJrZXnEQHsNR9k0J/gxEWB4HH\n xzP9ifiJcK70kNiqDuGaTLihsUF8t5+ytBIPKx7GXkGY1uCLKOgT/rAeSkAIObheGAgM4=\n -----END SSH SIGNATURE-----\n\nA signed commit\n"
    ),
    (
      "malformed",
      "tree 6670979f4915ccc75e90c7b3452026a4753d6768\nparent ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d\nauthor Author <9908739db197027b00bcede903330d07> 1700007200 +0000\ncommitter Committer <9908739db197027b00bcede903330d07> 1700007200 +0000\ngpgsig -----BEGIN SSH SIGNATURE-----\n not base64 at all!!!\n -----END SSH SIGNATURE-----\n\nA signed commit\n"
    ),
  ]

  /// A signed commit carrying no author line, which `git` will not write.
  private static let authorlessCommit =
    "tree 6670979f4915ccc75e90c7b3452026a4753d6768\nparent ef12603bf088b3b2e783ebf59fcc5a09a83d1f5d\ncommitter Committer <9908739db197027b00bcede903330d07> 1700007200 +0000\ngpgsig -----BEGIN SSH SIGNATURE-----\n U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgF8t5+ytBIPKx7GXkGY1uCLKOgT\n /rAeSkAIObheGAgM4AAAADZ2l0AAAAAAAAAAZzaGEyNTYAAADgMQjTIvBcvrWsaHtIddtj\n AEfokEnrn2SPWqTTw+xpCI/rxG7hfo36wdOiNIxoBErNr4OCc8wRsrA5yPbe4+VTBoOoaG\n FzaHR5cGWmc2hhMjU2pGhhc2jEIGB3pvC5un/bUwQVp22HVCse19VQ9ClaRU+4rIh2qz14\n pG1ldGGCpnNpZ25lcsQQmQhznbGXAnsAvO3pAzMNB6ZwdWJrZXnEQHsNR9k0J/gxEWB4HH\n xzP9ifiJcK70kNiqDuGaTLihsUF8t5+ytBIPKx7GXkGY1uCLKOgT/rAeSkAIObheGAgM4=\n -----END SSH SIGNATURE-----\n\nA signed commit\n"

  /// What the head commit changed.
  private static let headDiff =
    "diff --git a/added.txt b/added.txt\nnew file mode 100644\nindex 0000000..d5f7fc3\n--- /dev/null\n+++ b/added.txt\n@@ -0,0 +1 @@\n+added\ndiff --git a/kept.txt b/kept.txt\nindex e5c5c55..59afb9d 100644\n--- a/kept.txt\n+++ b/kept.txt\n@@ -1,2 +1,2 @@\n line one\n-line two\n+line two changed\ndiff --git a/removed.txt b/removed.txt\ndeleted file mode 100644\nindex bac8f5e..0000000\n--- a/removed.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-goes away\n"

  /// What the first commit changed.
  private static let firstDiff =
    "diff --git a/README.md b/README.md\nnew file mode 100644\nindex 0000000..489bbdf\n--- /dev/null\n+++ b/README.md\n@@ -0,0 +1,3 @@\n+# Title\n+\n+Some *markdown*.\ndiff --git a/README.mu b/README.mu\nnew file mode 100644\nindex 0000000..e45f78a\n--- /dev/null\n+++ b/README.mu\n@@ -0,0 +1 @@\n+A micron readme\ndiff --git a/binary.bin b/binary.bin\nnew file mode 100644\nindex 0000000..d21c470\nBinary files /dev/null and b/binary.bin differ\ndiff --git a/kept.txt b/kept.txt\nnew file mode 100644\nindex 0000000..e5c5c55\n--- /dev/null\n+++ b/kept.txt\n@@ -0,0 +1,2 @@\n+line one\n+line two\ndiff --git a/late_binary.bin b/late_binary.bin\nnew file mode 100644\nindex 0000000..e9a9fe9\nBinary files /dev/null and b/late_binary.bin differ\ndiff --git a/link.txt b/link.txt\nnew file mode 120000\nindex 0000000..72ad13c\n--- /dev/null\n+++ b/link.txt\n@@ -0,0 +1 @@\n+kept.txt\n\\ No newline at end of file\ndiff --git a/removed.txt b/removed.txt\nnew file mode 100644\nindex 0000000..bac8f5e\n--- /dev/null\n+++ b/removed.txt\n@@ -0,0 +1 @@\n+goes away\ndiff --git a/src/deep/file.txt b/src/deep/file.txt\nnew file mode 100644\nindex 0000000..4cdb226\n--- /dev/null\n+++ b/src/deep/file.txt\n@@ -0,0 +1 @@\n+deep\ndiff --git a/src/main.rs b/src/main.rs\nnew file mode 100644\nindex 0000000..f328e4d\n--- /dev/null\n+++ b/src/main.rs\n@@ -0,0 +1 @@\n+fn main() {}\n"

  /// The shell that builds this test's repository.
  ///
  /// Every name, date and address is fixed, so `git` records the same objects wherever it runs
  /// and the recorded hashes hold. `HEAD` is set outright rather than left to whatever the
  /// machine's `init.defaultBranch` says.
  private static let fixtureScript =
    "#!/bin/sh\n# Builds a deterministic repository: same content, same hashes, on any machine.\nset -e\nroot=\"$1\"\nrm -rf \"$root\"\nmkdir -p \"$root\"\ncd \"$root\"\n\nexport GIT_AUTHOR_NAME=\"Author\"\nexport GIT_AUTHOR_EMAIL=\"9710b86ba12c42d1d8f30f74fe509286\"\nexport GIT_COMMITTER_NAME=\"Committer\"\nexport GIT_COMMITTER_EMAIL=\"ef330a1940c70349459fc4401d273cb9\"\nexport GIT_AUTHOR_DATE=\"1700000000 +0000\"\nexport GIT_COMMITTER_DATE=\"1700000000 +0000\"\n\ngit init -q .\ngit symbolic-ref HEAD refs/heads/main\ngit config user.name \"$GIT_AUTHOR_NAME\"\ngit config user.email \"$GIT_AUTHOR_EMAIL\"\ngit config commit.gpgsign false\n\nprintf 'line one\\nline two\\n' > kept.txt\nprintf 'goes away\\n' > removed.txt\nmkdir -p src/deep\nprintf 'fn main() {}\\n' > src/main.rs\nprintf 'deep\\n' > src/deep/file.txt\nprintf '# Title\\n\\nSome *markdown*.\\n' > README.md\nprintf 'A micron readme\\n' > README.mu\nprintf 'plain text here\\000then binary\\n' > late_binary.bin\nprintf 'a\\000b\\000c binary payload\\n' > binary.bin\nln -s kept.txt link.txt\ngit add -A\ngit commit -q -m \"First commit\"\n\nexport GIT_AUTHOR_DATE=\"1700003600 +0000\"\nexport GIT_COMMITTER_DATE=\"1700003600 +0000\"\nprintf 'line one\\nline two changed\\n' > kept.txt\nrm removed.txt\nprintf 'added\\n' > added.txt\ngit add -A\ngit commit -q -m \"Second commit\n\nA body line, and a \\\\backslash.\"\n\ngit tag light\ngit tag -a annotated -m \"An annotated tag\"\ngit branch other\n\ngit config repository.description \"A configured description\"\ngit rev-parse HEAD\n"
}
