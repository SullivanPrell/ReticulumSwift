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

/// Markdown offered and sent as Micron, as Python RNS 1.5.5's `serve_blob_page` links it and
/// `serve_download` converts it.
///
/// The reference answered every step over one copy of `fixtureScript` with `TZ=UTC`, on a fresh
/// node without pygments, which is how this port highlights with no lexer given, and with the
/// owner's `download_succeeded` recording what each step counted. A linked step
/// arrives on a link the node holds open. How long a page took to generate is replaced by
/// `{GEN_TIME}`, and `.none` is a download the reference answered nothing to.
///
/// `held` counts the directories held for the link once the step is done: the reference's
/// conversion directory, and one more wherever this port writes out a file the reference
/// streams from a pipe.
final class RNGitMicronDownloadVectorTests: XCTestCase {

  /// One blob page, and the page the reference answered it with.
  private struct BlobStep {
    let name: String
    let path: String
    let ref: String
    let raw: Bool
    let page: [String]
  }

  /// What the reference answered a download with.
  private enum Answer: Equatable {
    case none
    case file(name: String, body: [String])
  }

  /// One download, the answer the reference gave it, and what it counted.
  private struct DownloadStep {
    let name: String
    let repository: String
    let ref: String
    let path: String
    let format: String
    let linked: Bool
    let answer: Answer
    let counted: Int
    let held: Int
  }

  /// The link every download arrives on.
  private static let link = Data(count: 16)

  /// Where this test's fixture stands.
  private var base = ""
  private var root: String { base + "/root" }

  override func setUpWithError() throws {
    try super.setUpWithError()
    base = NSTemporaryDirectory() + "/rngit-micron-download-" + UUID().uuidString
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

  /// Every blob page answers as the reference's did.
  func testEveryBlobPageMatchesTheReference() throws {
    for step in Self.blobSteps {
      var handler = handler(temporaries: RNGitTemporaryDirectories(root: base + "/held"))
      let page = handler.serveBlobPage(
        identityHash: nil, groupName: "proj", repositoryName: "docs", ref: step.ref,
        filePath: step.path, raw: step.raw)
      XCTAssertEqual(
        Self.normalised(page), step.page.joined(separator: "\n"), step.name)
    }
  }

  /// Every download answers as the reference's did, counts what it counted, and leaves held
  /// exactly the directories it says.
  func testEveryDownloadMatchesTheReference() throws {
    for (index, step) in Self.downloadSteps.enumerated() {
      let held = base + "/held/" + String(index)
      try FileManager.default.createDirectory(atPath: held, withIntermediateDirectories: true)
      var handler = handler(temporaries: RNGitTemporaryDirectories(root: held))
      if step.linked { handler.activeLinks = [Self.link] }

      let answer = handler.serveDownload(
        identityHash: nil, groupName: "proj", repositoryName: step.repository, ref: step.ref,
        path: step.path, format: step.format, link: Self.link)

      switch (step.answer, answer) {
      case (.none, nil):
        break
      case (.file(let name, let body), .file(let file)?):
        XCTAssertEqual(file.metadata, .name(name), step.name)
        XCTAssertEqual(
          FileManager.default.contents(atPath: file.path),
          Data(body.joined(separator: "\n").utf8), step.name)
        if step.format == "mu" {
          let stem = (name as NSString).deletingPathExtension
          let written = (file.path as NSString).lastPathComponent
          XCTAssertTrue(
            written.hasPrefix(stem + ".") && written.hasSuffix(".mu") && written != name,
            "\(step.name): written as \(written)")
          XCTAssertNotNil(file.directory, step.name)
        }
      default:
        XCTFail("\(step.name): answered \(String(describing: answer)), not \(step.answer)")
      }

      let downloads =
        handler.statistics.groups["proj"]?.repositories[step.repository]?.download.values
        .reduce(0, +) ?? 0
      XCTAssertEqual(downloads, step.counted, step.name)

      let directories = handler.temporaries.held[Self.link] ?? []
      XCTAssertEqual(directories.count, step.held, step.name)
      let standing = try FileManager.default.contentsOfDirectory(atPath: held).map {
        held + "/" + $0
      }
      XCTAssertEqual(Set(standing), Set(directories), step.name + ": nothing else is left")
    }
  }

  /// The page node hands the download its `var_fmt` field, as `serve_download` reads it.
  func testThePageNodeReadsTheFormatField() throws {
    var handler = handler(temporaries: RNGitTemporaryDirectories(root: base + "/held"))
    handler.activeLinks = [Self.link]
    func request(_ format: String) -> MsgPack.Value {
      .map([
        (.string("var_g"), .string("proj")), (.string("var_r"), .string("docs")),
        (.string("var_path"), .string("guide/intro.md")), (.string("var_fmt"), .string(format)),
      ])
    }
    let converted = RNGitPageNode.serve(
      "/file/download", RNGitPageRequest(request("mu")), request("mu"), nil, Self.link,
      &handler)
    guard case .file(_, let metadata)? = converted else {
      return XCTFail("answered \(String(describing: converted))")
    }
    XCTAssertEqual(metadata, RNGitFileMetadata.name("intro.mu").encoded)
    XCTAssertNil(
      RNGitPageNode.serve(
        "/file/download", RNGitPageRequest(request("pdf")), request("pdf"), nil, Self.link,
        &handler))
  }

  /// `page` as text, with how long it took to generate replaced by `{GEN_TIME}`.
  private static func normalised(_ page: Data) -> String {
    let text = String(decoding: page, as: UTF8.self)
    return text.replacingOccurrences(
      of: "Generated in [^`]*`f$", with: "Generated in {GEN_TIME}`f",
      options: .regularExpression)
  }

  /// A handler over group "proj" and its one repository, open to everyone, counting every
  /// download.
  private func handler(temporaries: RNGitTemporaryDirectories) -> RNGitPageHandler {
    var permissions = RNGitPermissionSet()
    permissions.read = [.everyone]
    let repositories = [
      "docs": RNGitRepository(name: "docs", path: root + "/docs", permissions: permissions)
    ]
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
        directory: "/nonexistent/templates", nodeName: "A Node", version: "1.5.5"))
    handler.temporaries = temporaries
    return handler
  }

  /// The blob pages, in the order the reference answered them.
  private static let blobSteps: [BlobStep] = [
    BlobStep(
      name: "blob markdown", path: "README.md", ref: "HEAD", raw: false,
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[docs`:/page/repo.mu`g=proj|r=docs]`! / `!`[files`:/page/tree.mu`g=proj|r=docs]`! / README.md",
        "",
        "Displaying Rendered • `!`[View raw`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=README.md|raw=y]`! • `!`[Download`:/file/download`g=proj|r=docs|ref=HEAD|path=README.md]`! `F666`!`[as micron`:/file/download`g=proj|r=docs|ref=HEAD|path=README.md|fmt=mu]`!`f",
        "",
        ">>README.md `F444HEAD (246280e7) Text, 116 B`f",
        "",
        ">Docs",
        "",
        "See the `_`!`[guide`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=guide/intro.md]`!`_ and `*this`* `!text`!.",
        "",
        "`BT282828`Fddd",
        "`=",
        "def f(x):",
        "    return x + 1",
        "`=",
        "`f`b",
        "",
        " • one",
        " • two",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.5`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    BlobStep(
      name: "blob markdown raw", path: "README.md", ref: "HEAD", raw: true,
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[docs`:/page/repo.mu`g=proj|r=docs]`! / `!`[files`:/page/tree.mu`g=proj|r=docs]`! / README.md",
        "",
        "Displaying Raw • `!`[View rendered`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=README.md|render=y]`! • `!`[Download`:/file/download`g=proj|r=docs|ref=HEAD|path=README.md]`! `F666`!`[as micron`:/file/download`g=proj|r=docs|ref=HEAD|path=README.md|fmt=mu]`!`f",
        "",
        ">>README.md `F444HEAD (246280e7) Text, 116 B`f",
        "",
        "`=",
        "# Docs",
        "",
        "See the [guide](guide/intro.md) and *this* **text**.",
        "",
        "\\\\`\\\\`\\\\`python",
        "def f(x):",
        "    return x + 1",
        "\\\\`\\\\`\\\\`",
        "",
        "- one",
        "- two",
        "",
        "`=",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.5`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    BlobStep(
      name: "blob nested markdown", path: "guide/intro.md", ref: "HEAD", raw: false,
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[docs`:/page/repo.mu`g=proj|r=docs]`! / `!`[files`:/page/tree.mu`g=proj|r=docs]`! / `!`[guide`:/page/tree.mu`g=proj|r=docs|ref=HEAD|path=guide]`! / intro.md",
        "",
        "Displaying Rendered • `!`[View raw`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=guide%2Fintro.md|raw=y]`! • `!`[Download`:/file/download`g=proj|r=docs|ref=HEAD|path=guide%2Fintro.md]`! `F666`!`[as micron`:/file/download`g=proj|r=docs|ref=HEAD|path=guide%2Fintro.md|fmt=mu]`!`f",
        "",
        ">>guide/intro.md `F444HEAD (246280e7) Text, 80 B`f",
        "",
        ">>Intro",
        "",
        "Back to `_`!`[the top`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=guide/../README.md]`!`_. Visit `_`!`[a site`https://example.com]`!`_.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.5`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    BlobStep(
      name: "blob upper case markdown", path: "NOTES.MD", ref: "HEAD", raw: false,
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[docs`:/page/repo.mu`g=proj|r=docs]`! / `!`[files`:/page/tree.mu`g=proj|r=docs]`! / NOTES.MD",
        "",
        "Displaying Rendered • `!`[View raw`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=NOTES.MD|raw=y]`! • `!`[Download`:/file/download`g=proj|r=docs|ref=HEAD|path=NOTES.MD]`! `F666`!`[as micron`:/file/download`g=proj|r=docs|ref=HEAD|path=NOTES.MD|fmt=mu]`!`f",
        "",
        ">>NOTES.MD `F444HEAD (246280e7) Text, 8 B`f",
        "",
        ">Upper",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.5`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    BlobStep(
      name: "blob micron", path: "notes.mu", ref: "HEAD", raw: false,
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[docs`:/page/repo.mu`g=proj|r=docs]`! / `!`[files`:/page/tree.mu`g=proj|r=docs]`! / notes.mu",
        "",
        "Displaying Rendered • `!`[View raw`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=notes.mu|raw=y]`! • `!`[Download`:/file/download`g=proj|r=docs|ref=HEAD|path=notes.mu]`!",
        "",
        ">>notes.mu `F444HEAD (246280e7) Text, 8 B`f",
        "",
        ">Micron",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.5`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    BlobStep(
      name: "blob at a branch", path: "README.md", ref: "main", raw: false,
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[docs`:/page/repo.mu`g=proj|r=docs]`! / `!`[files`:/page/tree.mu`g=proj|r=docs]`! / README.md",
        "",
        "Displaying Rendered • `!`[View raw`:/page/blob.mu`g=proj|r=docs|ref=main|path=README.md|raw=y]`! • `!`[Download`:/file/download`g=proj|r=docs|ref=main|path=README.md]`! `F666`!`[as micron`:/file/download`g=proj|r=docs|ref=main|path=README.md|fmt=mu]`!`f",
        "",
        ">>README.md `F444main (246280e7) Text, 116 B`f",
        "",
        ">Docs",
        "",
        "See the `_`!`[guide`:/page/blob.mu`g=proj|r=docs|ref=main|path=guide/intro.md]`!`_ and `*this`* `!text`!.",
        "",
        "`BT282828`Fddd",
        "`=",
        "def f(x):",
        "    return x + 1",
        "`=",
        "`f`b",
        "",
        " • one",
        " • two",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.5`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    BlobStep(
      name: "blob trailing slash", path: "README.md/", ref: "HEAD", raw: false,
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[docs`:/page/repo.mu`g=proj|r=docs]`! / `!`[files`:/page/tree.mu`g=proj|r=docs]`! / README.md",
        "",
        "Displaying Raw • `!`[Download`:/file/download`g=proj|r=docs|ref=HEAD|path=README.md%2F]`!",
        "",
        ">>README.md/ `F444HEAD (246280e7) Text, 116 B`f",
        "",
        "`=",
        "# Docs",
        "",
        "See the [guide](guide/intro.md) and *this* **text**.",
        "",
        "\\\\`\\\\`\\\\`python",
        "def f(x):",
        "    return x + 1",
        "\\\\`\\\\`\\\\`",
        "",
        "- one",
        "- two",
        "",
        "`=",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.5`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
  ]

  /// The downloads, in the order the reference answered them.
  private static let downloadSteps: [DownloadStep] = [
    DownloadStep(
      name: "mu root", repository: "docs", ref: "HEAD", path: "README.md",
      format: "mu", linked: true,
      answer: .file(
        name: "README.mu",
        body: [
          ">Docs",
          "",
          "See the `_`!`[guide`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=guide/intro.md]`!`_ and `*this`* `!text`!.",
          "",
          "`BT282828`Fddd",
          "`=",
          "def f(x):",
          "    return x + 1",
          "`=",
          "`f`b",
          "",
          " • one",
          " • two",
        ]),
      counted: 1, held: 1),
    DownloadStep(
      name: "mu nested", repository: "docs", ref: "HEAD", path: "guide/intro.md",
      format: "mu", linked: true,
      answer: .file(
        name: "intro.mu",
        body: [
          ">>Intro",
          "",
          "Back to `_`!`[the top`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=guide/../README.md]`!`_. Visit `_`!`[a site`https://example.com]`!`_.",
        ]),
      counted: 1, held: 1),
    DownloadStep(
      name: "mu leading slash", repository: "docs", ref: "HEAD", path: "/guide/intro.md",
      format: "mu", linked: true,
      answer: .file(
        name: "intro.mu",
        body: [
          ">>Intro",
          "",
          "Back to `_`!`[the top`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=guide/../README.md]`!`_. Visit `_`!`[a site`https://example.com]`!`_.",
        ]),
      counted: 1, held: 1),
    DownloadStep(
      name: "mu quoted", repository: "docs", ref: "HEAD", path: "guide%2Fintro.md",
      format: "mu", linked: true,
      answer: .file(
        name: "intro.mu",
        body: [
          ">>Intro",
          "",
          "Back to `_`!`[the top`:/page/blob.mu`g=proj|r=docs|ref=HEAD|path=guide/../README.md]`!`_. Visit `_`!`[a site`https://example.com]`!`_.",
        ]),
      counted: 1, held: 1),
    DownloadStep(
      name: "mu at a branch", repository: "docs", ref: "main", path: "guide/intro.md",
      format: "mu", linked: true,
      answer: .file(
        name: "intro.mu",
        body: [
          ">>Intro",
          "",
          "Back to `_`!`[the top`:/page/blob.mu`g=proj|r=docs|ref=main|path=guide/../README.md]`!`_. Visit `_`!`[a site`https://example.com]`!`_.",
        ]),
      counted: 1, held: 1),
    DownloadStep(
      name: "mu upper case", repository: "docs", ref: "HEAD", path: "NOTES.MD",
      format: "mu", linked: true,
      answer: .file(
        name: "NOTES.mu",
        body: [
          ">Upper"
        ]),
      counted: 1, held: 1),
    DownloadStep(
      name: "mu byte order mark", repository: "docs", ref: "HEAD", path: "bom.md",
      format: "mu", linked: true,
      answer: .file(
        name: "bom.mu",
        body: [
          "\u{feff}# Marked"
        ]),
      counted: 1, held: 1),
    DownloadStep(
      name: "mu directory", repository: "docs", ref: "HEAD", path: "dir.md",
      format: "mu", linked: true,
      answer: .file(
        name: "dir.mu",
        body: [
          "tree 246280e7c3a4018a88212b8533cf5358c3103653:dir.md",
          "",
          "file.txt",
        ]),
      counted: 1, held: 1),
    DownloadStep(
      name: "mu unlinked", repository: "docs", ref: "HEAD", path: "README.md",
      format: "mu", linked: false,
      answer: .none,
      counted: 1, held: 0),
    DownloadStep(
      name: "mu blank", repository: "docs", ref: "HEAD", path: "empty.md",
      format: "mu", linked: true,
      answer: .none,
      counted: 1, held: 0),
    DownloadStep(
      name: "mu not utf-8", repository: "docs", ref: "HEAD", path: "bad.md",
      format: "mu", linked: true,
      answer: .none,
      counted: 1, held: 0),
    DownloadStep(
      name: "mu micron file", repository: "docs", ref: "HEAD", path: "notes.mu",
      format: "mu", linked: true,
      answer: .none,
      counted: 0, held: 0),
    DownloadStep(
      name: "mu trailing slash", repository: "docs", ref: "HEAD", path: "README.md/",
      format: "mu", linked: true,
      answer: .none,
      counted: 0, held: 0),
    DownloadStep(
      name: "mu missing", repository: "docs", ref: "HEAD", path: "nope.md",
      format: "mu", linked: true,
      answer: .none,
      counted: 0, held: 0),
    DownloadStep(
      name: "mu unknown ref", repository: "docs", ref: "nope", path: "README.md",
      format: "mu", linked: true,
      answer: .none,
      counted: 0, held: 0),
    DownloadStep(
      name: "mu unknown repository", repository: "nope", ref: "HEAD", path: "README.md",
      format: "mu", linked: true,
      answer: .none,
      counted: 0, held: 0),
    DownloadStep(
      name: "other format", repository: "docs", ref: "HEAD", path: "README.md",
      format: "pdf", linked: true,
      answer: .none,
      counted: 1, held: 0),
    DownloadStep(
      name: "other format on micron", repository: "docs", ref: "HEAD", path: "notes.mu",
      format: "pdf", linked: true,
      answer: .none,
      counted: 0, held: 0),
    DownloadStep(
      name: "no format", repository: "docs", ref: "HEAD", path: "README.md",
      format: "", linked: true,
      answer: .file(
        name: "README.md",
        body: [
          "# Docs",
          "",
          "See the [guide](guide/intro.md) and *this* **text**.",
          "",
          "```python",
          "def f(x):",
          "    return x + 1",
          "```",
          "",
          "- one",
          "- two",
          "",
        ]),
      counted: 1, held: 1),
  ]

  /// The repository every step reads, committed once.
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
    mkdir -p docs
    cd docs
    git init -q .
    git symbolic-ref HEAD refs/heads/main
    git config commit.gpgsign false
    printf '# Docs\n\nSee the [guide](guide/intro.md) and *this* **text**.\n\n```python\ndef f(x):\n    return x + 1\n```\n\n- one\n- two\n' > README.md
    mkdir -p guide
    printf '## Intro\n\nBack to [the top](../README.md). Visit [a site](https://example.com).\n' > guide/intro.md
    printf '   \n\n' > empty.md
    printf '\377\376 not text\n' > bad.md
    printf '\357\273\277# Marked\n' > bom.md
    printf '>Micron\n' > notes.mu
    printf '# Upper\n' > NOTES.MD
    mkdir -p dir.md
    printf 'inside\n' > dir.md/file.txt
    git add -A
    git commit -q -m 'First commit'
    """#
}
