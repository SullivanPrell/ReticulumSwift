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

/// The files a node's pages hand out, answered as Python RNS 1.5.4's `serve_artifact`,
/// `serve_download`, `serve_media` and `serve_wd_download` answer them.
///
/// The reference answered every step over one copy of `fixtureScript`, on a fresh node, with
/// the owner's `download_succeeded` and `release_download_succeeded` recording what each step
/// counted, and `media.convert_to_webp` replaced by a stand-in that records what it was asked to
/// run and writes a file where the step says the conversion works. `.none` is a step the
/// reference answered nothing to, whether it returned `None` or raised.
///
/// `held` counts the directories held for the link once the step is done: the reference's
/// conversion directories, and one more wherever this port writes out a file the reference
/// streams from a pipe.
final class RNGitFilePagesVectorTests: XCTestCase {

  /// What a step asks for.
  private enum Request {
    case artifact(repository: String, tag: String, artifact: String)
    case download(repository: String, ref: String?, path: String)
    case workDocument(repository: String, documentID: String, scope: String?)
    case media(MsgPack.Value, conversion: Bool, linked: Bool, converts: Bool)
  }

  /// What the reference answered.
  private enum Answer {
    case none
    case refused
    case file(name: String, body: Data)
    case converted(name: String)
    case value(name: String, body: Data)
  }

  /// One request, the answer the reference gave it, what it counted, and what it converted.
  private struct Step {
    let name: String
    let request: Request
    let answer: Answer
    let counted: [String]
    let conversions: [[String]]
    let spoolStem: String?
    let held: Int
  }

  /// A converter standing in for the encoder, recording what it is asked to run.
  private final class Converter: RNGitMediaConverter, @unchecked Sendable {
    let converts: Bool
    var produced: [[String]] = []
    var directories: [String?] = []
    var paths: [String] = []

    init(converts: Bool) { self.converts = converts }

    func convert(
      producing: [String], in directory: String?, through encoding: [String], to path: String,
      within timeout: TimeInterval
    ) -> RNGitMediaOutcome {
      produced.append(producing)
      directories.append(directory)
      paths.append(path)
      guard converts else { return .failed(encoder: "", input: "") }
      FileManager.default.createFile(atPath: path, contents: RNGitFilePagesVectorTests.webP)
      return .converted
    }

    func convert(
      reading source: String, through encoding: [String], to path: String,
      within timeout: TimeInterval
    ) -> RNGitMediaOutcome { .couldNotRun("not asked for") }
  }

  /// The first bytes of a lossy WebP file, which is what the converter writes.
  fileprivate static let webP = Data(
    hex: "52494646200200005745425056503820140200" + "00300f009d012a25001700")!

  /// The link every step arrives on.
  private static let link = Data(count: 16)

  /// Where this test's fixture stands.
  private var base = ""
  private var root: String { base + "/root" }

  override func setUpWithError() throws {
    try super.setUpWithError()
    base = NSTemporaryDirectory() + "/rngit-file-pages-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    let script = base + "/fixture.sh"
    try Self.fixtureScript.write(toFile: script, atomically: true, encoding: .utf8)
    let built = RNGitProcessRunner().run("sh", arguments: [script, root], in: base)
    try XCTSkipIf(built == nil, "no shell to build the fixture with")
    XCTAssertEqual(built?.status, 0, built?.standardError ?? "")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: base)
    super.tearDown()
  }

  /// Every step answers as the reference's did, counts what it counted, converts what it
  /// converted, and leaves held exactly the directories it says.
  func testEveryStepMatchesTheReference() throws {
    for (index, step) in Self.steps.enumerated() {
      let held = base + "/held/" + String(index)
      try FileManager.default.createDirectory(atPath: held, withIntermediateDirectories: true)
      var converts = false
      var linked = false
      if case .media(_, _, let isLinked, let isConverting) = step.request {
        converts = isConverting
        linked = isLinked
      }
      let converter = Converter(converts: converts)
      var handler = handler(
        temporaries: RNGitTemporaryDirectories(root: held), converter: converter)
      if linked { handler.activeLinks = [Self.link] }

      let answer: RNGitPageDownload?
      switch step.request {
      case .artifact(let repository, let tag, let artifact):
        answer = handler.serveArtifact(
          identityHash: nil, groupName: "proj", repositoryName: repository, tag: tag,
          artifact: artifact)
      case .download(let repository, let ref?, let path):
        answer = handler.serveDownload(
          identityHash: nil, groupName: "proj", repositoryName: repository, ref: ref,
          path: path, link: Self.link)
      case .download(let repository, nil, let path):
        answer = handler.serveDownload(
          identityHash: nil, groupName: "proj", repositoryName: repository, path: path,
          link: Self.link)
      case .workDocument(let repository, let documentID, let scope?):
        answer = handler.serveWorkDocumentDownload(
          identityHash: nil, groupName: "proj", repositoryName: repository,
          documentID: documentID, scope: scope)
      case .workDocument(let repository, let documentID, nil):
        answer = handler.serveWorkDocumentDownload(
          identityHash: nil, groupName: "proj", repositoryName: repository,
          documentID: documentID)
      case .media(let request, let conversion, _, _):
        handler.mediaConversion = conversion
        answer = handler.serveMedia(identityHash: nil, request: request, link: Self.link)
      }

      try check(answer, against: step, converter: converter)
      XCTAssertEqual(counted(handler.statistics), step.counted, step.name)
      XCTAssertEqual(converter.produced, step.conversions, step.name)
      XCTAssertEqual(
        converter.directories, step.conversions.map { _ in root + "/demo" }, step.name)
      if let stem = step.spoolStem {
        for path in converter.paths {
          let name = (path as NSString).lastPathComponent
          XCTAssertTrue(name.hasPrefix(stem + ".") && name.hasSuffix(".webp"), step.name)
        }
      }

      let directories = handler.temporaries.held[Self.link] ?? []
      XCTAssertEqual(directories.count, step.held, step.name)
      let standing = try FileManager.default.contentsOfDirectory(atPath: held).map {
        held + "/" + $0
      }
      XCTAssertEqual(Set(standing), Set(directories), step.name + ": nothing else is left")
    }
  }

  /// Checks `answer` against what the reference answered `step` with.
  private func check(_ answer: RNGitPageDownload?, against step: Step, converter: Converter)
    throws
  {
    switch (step.answer, answer) {
    case (.none, nil):
      break
    case (.refused, .value(let value)?):
      XCTAssertEqual(value, .bool(false), step.name)
    case (.value(let name, let body), .value(let value)?):
      XCTAssertEqual(value, .array([.string(name), .bytes(body)]), step.name)
    case (.file(let name, let body), .file(let file)?):
      XCTAssertEqual(file.metadata, .name(name), step.name)
      XCTAssertEqual(FileManager.default.contents(atPath: file.path), body, step.name)
    case (.converted(let name), .file(let file)?):
      XCTAssertEqual(file.metadata, .name(name), step.name)
      XCTAssertEqual(converter.paths.last, file.path, step.name)
      XCTAssertEqual(FileManager.default.contents(atPath: file.path), Self.webP, step.name)
    default:
      XCTFail("\(step.name): answered \(String(describing: answer)), not \(step.answer)")
    }
  }

  /// Each download the handler counted, as `kind repository`.
  private func counted(_ statistics: RNGitStatistics) -> [String] {
    var counted: [String] = []
    for (name, counters) in (statistics.groups["proj"]?.repositories ?? [:]).sorted(by: {
      $0.key < $1.key
    }) {
      counted += Array(
        repeating: "release " + name, count: counters.releaseDownload.values.reduce(0, +))
      counted += Array(repeating: "download " + name, count: counters.download.values.reduce(0, +))
    }
    return counted
  }

  /// A handler over group "proj" and its three repositories, each open to everyone, counting
  /// every download.
  private func handler(temporaries: RNGitTemporaryDirectories, converter: Converter)
    -> RNGitPageHandler
  {
    var permissions = RNGitPermissionSet()
    permissions.read = [.everyone]
    var repositories: [String: RNGitRepository] = [:]
    for name in ["demo", "newest", "bare"] {
      repositories[name] = RNGitRepository(
        name: name, path: root + "/" + name, permissions: permissions)
    }
    var settings = RNGitNodeSettings()
    settings.statsEnabled = true
    var handler = RNGitPageHandler(
      access: RNGitPageAccess(
        control: RNGitAccessControl(groups: [
          "proj": RNGitGroup(
            name: "proj", path: root, repositories: repositories, permissions: permissions)
        ])),
      runner: RNGitProcessRunner(), destinationHash: Data(repeating: 0x7A, count: 16),
      settings: settings, thanks: RNGitPageThanks(),
      templates: RNGitPageTemplates(
        directory: "/nonexistent/templates", nodeName: "A Node", version: "1.5.4"))
    handler.temporaries = temporaries
    handler.mediaEncoder = RNGitMediaEncoder(
      converter: converter, forced: nil, found: { $0 == "magick" })
    return handler
  }

  /// The requests, in the order the reference answered them.
  private static let steps: [Step] = [
    Step(
      name: "artifact",
      request: .artifact(repository: "demo", tag: "v1.0", artifact: "app.zip"),
      answer: .file(name: "app.zip", body: Data(hex: "504b0304206f6e65")!),
      counted: ["release demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact unquoted",
      request: .artifact(repository: "demo", tag: "v1.0", artifact: "notes+v1.txt"),
      answer: .file(name: "notes v1.txt", body: Data(hex: "706c61696e206e6f7465730a")!),
      counted: ["release demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact quoted slash",
      request: .artifact(repository: "demo", tag: "v1.0", artifact: "a%2Fb"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact with a slash",
      request: .artifact(repository: "demo", tag: "v1.0", artifact: "../META"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact missing",
      request: .artifact(repository: "demo", tag: "v1.0", artifact: "nope.zip"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact unnamed",
      request: .artifact(repository: "demo", tag: "v1.0", artifact: ""),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact latest",
      request: .artifact(repository: "demo", tag: "latest", artifact: "app.zip"),
      answer: .file(name: "app.zip", body: Data(hex: "504b0304206f6e65")!),
      counted: ["release demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact newest",
      request: .artifact(repository: "newest", tag: "latest", artifact: "app.zip"),
      answer: .file(name: "app.zip", body: Data(hex: "6e6577")!),
      counted: ["release newest"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact draft",
      request: .artifact(repository: "demo", tag: "v3.0", artifact: "app.zip"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact no release",
      request: .artifact(repository: "demo", tag: "v9", artifact: "app.zip"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact no artifacts",
      request: .artifact(repository: "demo", tag: "empty", artifact: "app.zip"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact latest with none",
      request: .artifact(repository: "bare", tag: "latest", artifact: "app.zip"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "artifact unknown repository",
      request: .artifact(repository: "nope", tag: "v1.0", artifact: "app.zip"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "download",
      request: .download(repository: "demo", ref: nil, path: "src/main.swift"),
      answer: .file(name: "main.swift", body: Data(hex: "6c65742078203d20320a")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "download at a tag",
      request: .download(repository: "demo", ref: "v1", path: "src/main.swift"),
      answer: .file(name: "main.swift", body: Data(hex: "6c65742078203d20310a")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "download unquoted",
      request: .download(repository: "demo", ref: nil, path: "notes+v1.txt"),
      answer: .file(name: "notes v1.txt", body: Data(hex: "7370616365640a")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "download quoted plus",
      request: .download(repository: "demo", ref: nil, path: "a%2Bb.txt"),
      answer: .file(name: "a+b.txt", body: Data(hex: "706c75730a")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "download a directory",
      request: .download(repository: "demo", ref: nil, path: "src"),
      answer: .file(
        name: "src",
        body: Data(
          hex:
            "7472656520666238626664323231383436386337653166303639626461326139373630656362633662363937643a7372630a0a6d61696e2e73776966740a"
        )!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "download a link",
      request: .download(repository: "demo", ref: nil, path: "link"),
      answer: .file(name: "link", body: Data(hex: "524541444d452e6d64")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "download with slashes",
      request: .download(repository: "demo", ref: nil, path: "/src/main.swift/"),
      answer: .file(name: "", body: Data(hex: "6c65742078203d20320a")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "download missing",
      request: .download(repository: "demo", ref: nil, path: "nope"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "download no path",
      request: .download(repository: "demo", ref: nil, path: ""),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "download unknown ref",
      request: .download(repository: "demo", ref: "nope", path: "README.md"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "download unknown repository",
      request: .download(repository: "nope", ref: nil, path: "README.md"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc markdown",
      request: .workDocument(repository: "demo", documentID: "1", scope: nil),
      answer: .value(
        name: "Port the downloads.md", body: Data(hex: "2320506c616e0a0a446f2069742e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc proposed by all",
      request: .workDocument(repository: "demo", documentID: "2", scope: nil),
      answer: .value(name: "A proposal.mu", body: Data(hex: "3e48656164696e67")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc proposed by name",
      request: .workDocument(repository: "demo", documentID: "2", scope: "proposed"),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc blank",
      request: .workDocument(repository: "demo", documentID: "3", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc bytes title",
      request: .workDocument(repository: "demo", documentID: "4", scope: nil),
      answer: .value(name: "b'bytes title'.md", body: Data(hex: "446f6e652e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc closed",
      request: .workDocument(repository: "demo", documentID: "5", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc without meta",
      request: .workDocument(repository: "demo", documentID: "6", scope: nil),
      answer: .value(name: "Untitled.md", body: Data(hex: "4e6f206d6574612e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc long title",
      request: .workDocument(repository: "demo", documentID: "7", scope: nil),
      answer: .value(
        name:
          "TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT.md",
        body: Data(hex: "4c6f6e672e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc missing",
      request: .workDocument(repository: "demo", documentID: "99", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc bytes content",
      request: .workDocument(repository: "demo", documentID: "8", scope: nil),
      answer: .none,
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc list title",
      request: .workDocument(repository: "demo", documentID: "9", scope: nil),
      answer: .value(
        name:
          "['a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b', 'a', 'b'].mu",
        body: Data(hex: "4c69737465642e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc number title",
      request: .workDocument(repository: "demo", documentID: "10", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc bytes format",
      request: .workDocument(repository: "demo", documentID: "11", scope: nil),
      answer: .value(name: "Fmt.md", body: Data(hex: "427974657320666f726d61742e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc list meta",
      request: .workDocument(repository: "demo", documentID: "12", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc list document",
      request: .workDocument(repository: "demo", documentID: "13", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc number content",
      request: .workDocument(repository: "demo", documentID: "14", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc accented",
      request: .workDocument(repository: "demo", documentID: "15", scope: nil),
      answer: .value(
        name:
          "\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}.md",
        body: Data(hex: "c3a974c3a9")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc unreadable",
      request: .workDocument(repository: "demo", documentID: "16", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc completed by all",
      request: .workDocument(repository: "demo", documentID: "17", scope: nil),
      answer: .value(name: "Done.mu", body: Data(hex: "436f6d706c657465642e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc completed by name",
      request: .workDocument(repository: "demo", documentID: "17", scope: "completed"),
      answer: .value(name: "Done.mu", body: Data(hex: "436f6d706c657465642e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc active by name",
      request: .workDocument(repository: "demo", documentID: "1", scope: "active"),
      answer: .value(
        name: "Port the downloads.md", body: Data(hex: "2320506c616e0a0a446f2069742e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc leading zero",
      request: .workDocument(repository: "demo", documentID: "01", scope: nil),
      answer: .value(
        name: "Port the downloads.md", body: Data(hex: "2320506c616e0a0a446f2069742e")!),
      counted: ["download demo"], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc not a number",
      request: .workDocument(repository: "demo", documentID: "one", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc invalid",
      request: .workDocument(repository: "demo", documentID: "", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "workdoc unknown repository",
      request: .workDocument(repository: "nope", documentID: "1", scope: nil),
      answer: .none,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "media",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/logo.png")),
        ]), conversion: false, linked: false, converts: true),
      answer: .file(name: "logo.png", body: Data(hex: "89504e470d0a1a0a66616b6500696d6167650a")!),
      counted: [], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "media converting without a link",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/logo.png")),
        ]), conversion: true, linked: false, converts: true),
      answer: .file(name: "logo.png", body: Data(hex: "89504e470d0a1a0a66616b6500696d6167650a")!),
      counted: [], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "media converted",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/logo.png")),
        ]), conversion: true, linked: true, converts: true),
      answer: .converted(name: "logo.webp"),
      counted: [],
      conversions: [["git", "show", "fb8bfd2218468c7e1f069bda2a9760ecbc6b697d:logo.png"]],
      spoolStem: "logo", held: 1),
    Step(
      name: "media conversion failing",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/logo.png")),
        ]), conversion: true, linked: true, converts: false),
      answer: .file(name: "logo.png", body: Data(hex: "89504e470d0a1a0a66616b6500696d6167650a")!),
      counted: [],
      conversions: [["git", "show", "fb8bfd2218468c7e1f069bda2a9760ecbc6b697d:logo.png"]],
      spoolStem: "logo", held: 1),
    Step(
      name: "media conversion off",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/logo.png")),
        ]), conversion: false, linked: true, converts: true),
      answer: .file(name: "logo.png", body: Data(hex: "89504e470d0a1a0a66616b6500696d6167650a")!),
      counted: [], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "media already webp",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/pic.webp")),
        ]), conversion: true, linked: true, converts: true),
      answer: .file(name: "pic.webp", body: Data(hex: "52494646303030305745425056503820")!),
      counted: [], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "media upper case",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/Upper+Case.GIF")),
        ]), conversion: true, linked: true, converts: true),
      answer: .converted(name: "Upper Case.webp"),
      counted: [],
      conversions: [["git", "show", "fb8bfd2218468c7e1f069bda2a9760ecbc6b697d:Upper Case.GIF"]],
      spoolStem: "Upper Case", held: 1),
    Step(
      name: "media dot file",
      request: .media(
        .map([
          (.string("key"), .string("k")), (.string("path"), .string("/media/proj/demo/HEAD/.png")),
        ]), conversion: true, linked: true, converts: true),
      answer: .file(name: ".png", body: Data(hex: "6e6f20657874656e73696f6e")!),
      counted: [], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "media not an image",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/README.md")),
        ]), conversion: true, linked: true, converts: true),
      answer: .file(name: "README.md", body: Data(hex: "232044656d6f0a")!),
      counted: [], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "media at a tag converted",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/v1/logo.png")),
        ]), conversion: true, linked: true, converts: true),
      answer: .converted(name: "logo.webp"),
      counted: [],
      conversions: [["git", "show", "1857cd953bc27e9d4ae33a3f42b4815a1acde54e:logo.png"]],
      spoolStem: "logo", held: 1),
    Step(
      name: "media trailing slash",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/logo.png/")),
        ]), conversion: true, linked: true, converts: true),
      answer: .file(name: "", body: Data(hex: "89504e470d0a1a0a66616b6500696d6167650a")!),
      counted: [], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "media quoted",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/main/notes%20v1.txt")),
        ]), conversion: false, linked: false, converts: true),
      answer: .file(name: "notes v1.txt", body: Data(hex: "7370616365640a")!),
      counted: [], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "media nested",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/v1/src/main.swift")),
        ]), conversion: false, linked: false, converts: true),
      answer: .file(name: "main.swift", body: Data(hex: "6c65742078203d20310a")!),
      counted: [], conversions: [], spoolStem: nil, held: 1),
    Step(
      name: "media without the leading slash",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("media/proj/demo/v1/src/main.swift")),
        ]), conversion: false, linked: false, converts: true),
      answer: .refused,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "media not a mapping",
      request: .media(
        .array([.string("key"), .string("path")]), conversion: false, linked: false, converts: true),
      answer: .refused,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "media without a key",
      request: .media(
        .map([(.string("path"), .string("/media/proj/demo/HEAD/logo.png"))]), conversion: false,
        linked: false, converts: true),
      answer: .refused,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "media without a path",
      request: .media(
        .map([(.string("key"), .string("k"))]), conversion: false, linked: false, converts: true),
      answer: .refused,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "media too short",
      request: .media(
        .map([(.string("key"), .string("k")), (.string("path"), .string("/media/proj/demo/HEAD"))]),
        conversion: false, linked: false, converts: true),
      answer: .refused,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "media no file",
      request: .media(
        .map([(.string("key"), .string("k")), (.string("path"), .string("/media/proj/demo/HEAD/"))]
        ), conversion: false, linked: false, converts: true),
      answer: .refused,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "media missing",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/HEAD/nope.png")),
        ]), conversion: false, linked: false, converts: true),
      answer: .refused,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "media unknown ref",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/demo/nope/logo.png")),
        ]), conversion: false, linked: false, converts: true),
      answer: .refused,
      counted: [], conversions: [], spoolStem: nil, held: 0),
    Step(
      name: "media unknown repository",
      request: .media(
        .map([
          (.string("key"), .string("k")),
          (.string("path"), .string("/media/proj/nope/HEAD/logo.png")),
        ]), conversion: false, linked: false, converts: true),
      answer: .refused,
      counted: [], conversions: [], spoolStem: nil, held: 0),
  ]

  /// The repository, its releases and its work documents.
  ///
  /// "demo" is a repository of two commits, the first tagged `v1`, holding a Markdown file, a
  /// Swift file under `src`, file names with a space, a plus sign and upper case, a PNG, a WebP,
  /// a file named `.png` and a symbolic link. Its releases are `v1.0` (named `latest`), `v2.0`,
  /// the draft `v3.0` and `empty`, which has no artifacts. Its work documents cover a Markdown
  /// and a Micron document, a blank one, titles in bytes, as a list and as a number, one closed
  /// by its own `allowed` file, one with no `meta`, bodies in bytes and as a number, a `meta`
  /// and a document that are lists, and a file that is not MessagePack. "newest" has two
  /// releases and no `latest` file, and "bare" has none at all.
  private static let fixtureScript = #"""
    set -e
    root="$1"
    rm -rf "$root"
    mkdir -p "$root"
    cd "$root"
    export GIT_AUTHOR_NAME="Author"
    export GIT_AUTHOR_EMAIL="author@example.com"
    export GIT_COMMITTER_NAME="Committer"
    export GIT_COMMITTER_EMAIL="committer@example.com"
    export GIT_AUTHOR_DATE="1790000000 +0000"
    export GIT_COMMITTER_DATE="1790000000 +0000"
    mkdir -p demo
    cd demo
    git init -q .
    git symbolic-ref HEAD refs/heads/main
    git config commit.gpgsign false
    printf '# Demo\n' > README.md
    mkdir -p src
    printf 'let x = 1\n' > src/main.swift
    printf 'spaced\n' > 'notes v1.txt'
    printf 'plus\n' > 'a+b.txt'
    printf '\211PNG\015\012\032\012fake\000image\n' > logo.png
    printf 'RIFF0000WEBPVP8 ' > pic.webp
    printf 'GIF89a' > 'Upper Case.GIF'
    printf 'no extension' > '.png'
    ln -s README.md link
    git add -A
    git commit -q -m 'First commit'
    git tag v1
    printf 'let x = 2\n' > src/main.swift
    git commit -q -am 'Second commit'
    cd ..
    mkdir -p newest bare
    mkdir -p 'demo.releases/empty'
    printf 'tag \075 empty\012hash \075 0123abcd\012created \075 1789000000\012status \075 published\012created\137by \075 7a7a\012' > 'demo.releases/empty/META'
    mkdir -p 'demo.releases'
    printf 'v1\0560\012' > 'demo.releases/latest'
    mkdir -p 'demo.releases/v1.0'
    printf 'tag \075 v1\0560\012hash \075 0123abcd\012created \075 1790000000\012status \075 published\012created\137by \075 7a7a\012' > 'demo.releases/v1.0/META'
    mkdir -p 'demo.releases/v1.0/artifacts'
    printf 'PK\003\004 one' > 'demo.releases/v1.0/artifacts/app.zip'
    mkdir -p 'demo.releases/v1.0/artifacts'
    printf 'plain notes\012' > 'demo.releases/v1.0/artifacts/notes v1.txt'
    mkdir -p 'demo.releases/v2.0'
    printf 'tag \075 v2\0560\012hash \075 0123abcd\012created \075 1790100000\012status \075 published\012created\137by \075 7a7a\012' > 'demo.releases/v2.0/META'
    mkdir -p 'demo.releases/v2.0/artifacts'
    printf 'PK\003\004 two' > 'demo.releases/v2.0/artifacts/app.zip'
    mkdir -p 'demo.releases/v3.0'
    printf 'tag \075 v3\0560\012hash \075 0123abcd\012created \075 1790200000\012status \075 draft\012created\137by \075 7a7a\012' > 'demo.releases/v3.0/META'
    mkdir -p 'demo.releases/v3.0/artifacts'
    printf 'PK\003\004 three' > 'demo.releases/v3.0/artifacts/app.zip'
    mkdir -p 'demo.work'
    printf 'read\072none\012' > 'demo.work/5.allowed'
    mkdir -p 'demo.work/active/1'
    printf '\202\247content\263  \043 Plan\012\012Do it\056\012  \244meta\202\246format\250markdown\245title\262Port the downloads' > 'demo.work/active/1/root'
    mkdir -p 'demo.work/active/10'
    printf '\202\247content\251Numbered\056\244meta\201\245title\012' > 'demo.work/active/10/root'
    mkdir -p 'demo.work/active/11'
    printf '\202\247content\255Bytes format\056\244meta\202\245title\243Fmt\246format\304\006micron' > 'demo.work/active/11/root'
    mkdir -p 'demo.work/active/12'
    printf '\202\247content\254Listed meta\056\244meta\221\245title' > 'demo.work/active/12/root'
    mkdir -p 'demo.work/active/13'
    printf '\222\247content\244meta' > 'demo.work/active/13/root'
    mkdir -p 'demo.work/active/14'
    printf '\202\247content\016\244meta\201\245title\250Int body' > 'demo.work/active/14/root'
    mkdir -p 'demo.work/active/15'
    printf '\202\247content\250\303\251t\303\251\343\200\200\244meta\201\245title\332\002X\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251' > 'demo.work/active/15/root'
    mkdir -p 'demo.work/active/16'
    printf '\301 not msgpack' > 'demo.work/active/16/root'
    mkdir -p 'demo.work/active/3'
    printf '\202\247content\243 \012 \244meta\201\245title\245Blank' > 'demo.work/active/3/root'
    mkdir -p 'demo.work/active/5'
    printf '\202\247content\247Hidden\056\244meta\201\245title\246Closed' > 'demo.work/active/5/root'
    mkdir -p 'demo.work/active/6'
    printf '\201\247content\250No meta\056' > 'demo.work/active/6/root'
    mkdir -p 'demo.work/active/7'
    printf '\202\247content\245Long\056\244meta\201\245title\332\001\054TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT' > 'demo.work/active/7/root'
    mkdir -p 'demo.work/active/8'
    printf '\202\247content\304\015  raw bytes  \244meta\201\245title\252Bytes body' > 'demo.work/active/8/root'
    mkdir -p 'demo.work/active/9'
    printf '\202\247content\247Listed\056\244meta\202\245title\334\001\220\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\241a\241b\246format\246micron' > 'demo.work/active/9/root'
    mkdir -p 'demo.work/completed/17'
    printf '\202\247content\252Completed\056\244meta\202\245title\244Done\246format\246micron' > 'demo.work/completed/17/root'
    mkdir -p 'demo.work/completed/4'
    printf '\202\247content\245Done\056\244meta\201\245title\304\013bytes title' > 'demo.work/completed/4/root'
    mkdir -p 'demo.work/proposed/2'
    printf '\202\247content\251\076Heading\012\244meta\202\246format\246micron\245title\252A proposal' > 'demo.work/proposed/2/root'
    mkdir -p 'newest.releases/v1'
    printf 'tag \075 v1\012hash \075 0123abcd\012created \075 1790000000\012status \075 published\012created\137by \075 7a7a\012' > 'newest.releases/v1/META'
    mkdir -p 'newest.releases/v1/artifacts'
    printf 'old' > 'newest.releases/v1/artifacts/app.zip'
    mkdir -p 'newest.releases/v2'
    printf 'tag \075 v2\012hash \075 0123abcd\012created \075 1790100000\012status \075 published\012created\137by \075 7a7a\012' > 'newest.releases/v2/META'
    mkdir -p 'newest.releases/v2/artifacts'
    printf 'new' > 'newest.releases/v2/artifacts/app.zip'
    """#
}
