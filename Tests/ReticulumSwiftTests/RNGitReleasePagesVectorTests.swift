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

/// A repository's releases and release pages, as Python RNS 1.5.4's `serve_releases_page` and
/// `serve_release_page` render them.
///
/// The reference rendered every step in order over one copy of `fixtureScript`, with `TZ=UTC`
/// and a fresh page node each time, so the `THANKS` file one step writes is the one the next
/// reads. How long a page took to generate is replaced by `{GEN_TIME}`, and a nil page is a
/// step the reference raised on and answered nothing.
final class RNGitReleasePagesVectorTests: XCTestCase {

  /// Which page a step asks for.
  private enum Kind {
    case releases
    case release
  }

  /// One request, the page the reference answered it with, and the repositories it counted a
  /// view of.
  private struct Step {
    let name: String
    let kind: Kind
    let group: String
    let repository: String
    let tag: String
    let thanks: Bool
    let linkID: Data?
    let blockNullIdentity: Bool
    let views: [String]
    let page: [String]?
  }

  /// The identity a reader who has not identified is resolved as.
  private static let nullIdentityHash = Data(pythonHex: "d7db22f63b453c23bb0688dde565b7c1")!

  /// Where this test's fixture stands.
  private var root = ""

  override func setUpWithError() throws {
    try super.setUpWithError()
    let base = NSTemporaryDirectory() + "/rngit-release-pages-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    root = base + "/root"
    let script = base + "/fixture.sh"
    try Self.fixtureScript.write(toFile: script, atomically: true, encoding: .utf8)
    let built = RNGitProcessRunner().run("sh", arguments: [script, root], in: base)
    try XCTSkipIf(built == nil, "no shell to build the fixture with")
    XCTAssertEqual(built?.status, 0, built?.standardError ?? "")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: (root as NSString).deletingLastPathComponent)
    super.tearDown()
  }

  /// Every step answers as the reference's did, and counts the views it counted.
  func testEveryStepMatchesTheReference() throws {
    let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
    for step in Self.steps {
      var handler = handler(blockNullIdentity: step.blockNullIdentity)
      let page: Data?
      switch step.kind {
      case .releases:
        page = handler.serveReleasesPage(
          identityHash: nil, groupName: step.group, repositoryName: step.repository,
          timeZone: utc)
      case .release:
        page = handler.serveReleasePage(
          identityHash: nil, groupName: step.group, repositoryName: step.repository,
          tag: step.tag, thanksClicked: step.thanks, linkID: step.linkID, timeZone: utc)
      }

      XCTAssertEqual(
        page.map(Self.normalised), step.page?.joined(separator: "\n"), step.name)
      let counted = handler.statistics.groups["proj"]?.repositories.flatMap { name, counters in
        Array(repeating: name, count: counters.view.values.reduce(0, +))
      }
      XCTAssertEqual(counted ?? [], step.views, step.name)
    }
  }

  /// A handler over group "proj" and its four repositories, each open to everyone, counting
  /// every view.
  private func handler(blockNullIdentity: Bool) -> RNGitPageHandler {
    var permissions = RNGitPermissionSet()
    permissions.read = [.everyone]
    var repositories: [String: RNGitRepository] = [:]
    for name in ["demo", "bare", "drafts", "silent"] {
      repositories[name] = RNGitRepository(
        name: name, path: root + "/" + name, permissions: permissions)
    }
    var settings = RNGitNodeSettings()
    settings.statsEnabled = true
    if blockNullIdentity { settings.blockedIdentities = [Self.nullIdentityHash] }
    return RNGitPageHandler(
      access: RNGitPageAccess(
        control: RNGitAccessControl(groups: [
          "proj": RNGitGroup(
            name: "proj", path: root, repositories: repositories, permissions: permissions)
        ])),
      runner: RNGitProcessRunner(), destinationHash: Data(repeating: 0x7A, count: 16),
      settings: settings, thanks: RNGitPageThanks(),
      templates: RNGitPageTemplates(
        directory: "/nonexistent/templates", nodeName: "A Node", version: "1.5.4"))
  }

  /// `page` with how long it took to generate replaced, as the recorded pages have it.
  private static func normalised(_ page: Data) -> String {
    String(decoding: page, as: UTF8.self).replacingOccurrences(
      of: #"Generated in [^`]*`f$"#, with: "Generated in {GEN_TIME}`f",
      options: .regularExpression)
  }

  /// The releases the steps read: under "demo", five published (one of them `latest`, one
  /// undated, one whose notes open with a line longer than a preview keeps), one draft, and
  /// one whose notes are a `.txt` file a release page does not read; under "drafts", only
  /// drafts; under "silent", one published release with no notes; and "bare" has none.
  private static let fixtureScript = #"""
    set -e
    root="$1"
    rm -rf "$root"
    mkdir -p "$root"
    cd "$root"

    release() {
      mkdir -p "$1/artifacts"
      printf 'tag = %s\nhash = 0123abcd\ncreated = %s\nstatus = %s\ncreated_by = 7a7a\n' "$2" "$3" "$4" > "$1/META"
    }

    release demo.releases/v1.0 v1.0 1790000000 published
    printf '# Version 1.0\n\nFirst **bold** line\nSecond line\n' > demo.releases/v1.0/RELEASE.md
    head -c 100 /dev/zero > demo.releases/v1.0/artifacts/app.zip
    head -c 2048 /dev/zero > demo.releases/v1.0/artifacts/Notes.txt
    : > demo.releases/v1.0/artifacts/empty.bin

    release demo.releases/v1.1 v1.1 1790100000 published
    printf '>Heading\n`!Micron`! preview\n' > demo.releases/v1.1/RELEASE.mu
    head -c 1 /dev/zero > demo.releases/v1.1/artifacts/one.bin

    release demo.releases/v0.9 v0.9 1780000000 draft
    printf 'draft notes\n' > demo.releases/v0.9/RELEASE.txt

    release demo.releases/v2.0-rc v2.0-rc 1790200000 published
    printf 'plain `tick` text\nsecond\n' > demo.releases/v2.0-rc/RELEASE.txt
    rmdir demo.releases/v2.0-rc/artifacts

    release demo.releases/long long 1790150000 published
    awk 'BEGIN { for (i = 0; i < 2100; i++) printf "x"; printf "\n" }' > demo.releases/long/RELEASE.md

    release demo.releases/undated undated 0 published
    printf 'Undated notes\n' > demo.releases/undated/RELEASE.mu

    printf 'v1.0\n' > demo.releases/latest

    release drafts.releases/d1 d1 1790000000 draft
    printf 'one\n' > drafts.releases/d1/RELEASE.md
    release drafts.releases/d2 d2 1790100000 draft
    printf 'two\n' > drafts.releases/d2/RELEASE.md

    release silent.releases/quiet quiet 1790000000 published
    """#

  private static let steps: [Step] = [
    Step(
      name: "releases invalid", kind: .releases, group: "proj", repository: "",
      tag: "", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Error",
        "",
        "Invalid request",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "releases no identity", kind: .releases, group: "proj", repository: "demo",
      tag: "", thanks: false, linkID: nil,
      blockNullIdentity: true, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>No Identity",
        "",
        "This page requires identification, and none was received.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "releases unknown", kind: .releases, group: "proj", repository: "nope",
      tag: "", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Error",
        "",
        "The requested repository was not found.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "releases none", kind: .releases, group: "proj", repository: "bare",
      tag: "", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[bare`:/page/repo.mu`g=proj|r=bare]`! / releases",
        "",
        ">>Releases",
        "",
        "No releases available for this repository.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "releases drafts only", kind: .releases, group: "proj", repository: "drafts",
      tag: "", thanks: false, linkID: nil,
      blockNullIdentity: false, views: ["drafts"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[drafts`:/page/repo.mu`g=proj|r=drafts]`! / releases",
        "",
        ">>Releases (0)",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "releases demo", kind: .releases, group: "proj", repository: "demo",
      tag: "", thanks: false, linkID: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / releases",
        "",
        ">>Releases (5)",
        "",
        "`!`[v2.0-rc`:/page/release.mu`g=proj|r=demo|t=v2.0-rc]`! `F6662026-09-23 • `*0 artifacts`*`f",
        "plain \\`tick\\` text",
        "",
        "`!`[long`:/page/release.mu`g=proj|r=demo|t=long]`! `F6662026-09-23 • `*0 artifacts`*`f",
        "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx…",
        "",
        "`!`[v1.1`:/page/release.mu`g=proj|r=demo|t=v1.1]`! `F6662026-09-22 • `*1 artifact`*`f",
        "`!Micron`! preview",
        "",
        "`!`[v1.0`:/page/release.mu`g=proj|r=demo|t=v1.0]`! `F6662026-09-21 • `*3 artifacts`* • `FT537855`*Latest`*`f`f",
        "First `!bold`! line",
        "",
        "`!`[undated`:/page/release.mu`g=proj|r=demo|t=undated]`! `F666unknown • `*0 artifacts`*`f",
        "Undated notes",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "releases empty preview", kind: .releases, group: "proj", repository: "silent",
      tag: "", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: nil),
    Step(
      name: "release invalid", kind: .release, group: "proj", repository: "demo",
      tag: "", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Error",
        "",
        "Invalid request",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release no identity", kind: .release, group: "proj", repository: "demo",
      tag: "v1.0", thanks: false, linkID: nil,
      blockNullIdentity: true, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>No Identity",
        "",
        "This page requires identification, and none was received.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release unknown repository", kind: .release, group: "proj", repository: "nope",
      tag: "v1.0", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Error",
        "",
        "The requested repository was not found.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release latest", kind: .release, group: "proj", repository: "demo",
      tag: "latest", thanks: false, linkID: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[releases`:/page/releases.mu`g=proj|r=demo]`! / latest",
        "",
        "`[󰋑 Thanks (0)`:/page/release.mu`g=proj|r=demo|t=v1.0|thanks=y]",
        "",
        ">>Release v1.0 • 2026-09-21 14:13:20",
        "",
        ">Version 1.0",
        "",
        "First `!bold`! line",
        "Second line",
        "",
        "",
        ">>Artifacts (3)",
        "",
        "`[ Notes.txt`:/file/artifact`g=proj|r=demo|t=v1.0|a=Notes.txt] `F666`[(2.05 KB)`:/file/artifact`g=proj|r=demo|t=v1.0|a=Notes.txt]`f",
        "`[ app.zip`:/file/artifact`g=proj|r=demo|t=v1.0|a=app.zip] `F666`[(100 B)`:/file/artifact`g=proj|r=demo|t=v1.0|a=app.zip]`f",
        "`[ empty.bin`:/file/artifact`g=proj|r=demo|t=v1.0|a=empty.bin] `F666`[(0 B)`:/file/artifact`g=proj|r=demo|t=v1.0|a=empty.bin]`f",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release latest without file", kind: .release, group: "proj", repository: "drafts",
      tag: "latest", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[drafts`:/page/repo.mu`g=proj|r=drafts]`! / `!`[releases`:/page/releases.mu`g=proj|r=drafts]`! / latest",
        "",
        ">>Release Not Found",
        "",
        "The release d2 does not exist.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release latest with none", kind: .release, group: "proj", repository: "bare",
      tag: "latest", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[bare`:/page/repo.mu`g=proj|r=bare]`! / `!`[releases`:/page/releases.mu`g=proj|r=bare]`! / latest",
        "",
        ">>Release Not Found",
        "",
        "No releases exist.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release draft", kind: .release, group: "proj", repository: "demo",
      tag: "v0.9", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[releases`:/page/releases.mu`g=proj|r=demo]`! / v0.9",
        "",
        ">>Release Not Found",
        "",
        "The release v0.9 does not exist.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release missing", kind: .release, group: "proj", repository: "demo",
      tag: "nope", thanks: false, linkID: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[releases`:/page/releases.mu`g=proj|r=demo]`! / nope",
        "",
        ">>Release Not Found",
        "",
        "The release nope does not exist.",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release micron", kind: .release, group: "proj", repository: "demo",
      tag: "v1.1", thanks: false, linkID: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[releases`:/page/releases.mu`g=proj|r=demo]`! / v1.1",
        "",
        "`[󰋑 Thanks (0)`:/page/release.mu`g=proj|r=demo|t=v1.1|thanks=y]",
        "",
        ">>Release v1.1 • 2026-09-22 18:00:00",
        "",
        ">Heading",
        "`!Micron`! preview",
        "",
        "",
        ">>Artifacts (1)",
        "",
        "`[ one.bin`:/file/artifact`g=proj|r=demo|t=v1.1|a=one.bin] `F666`[(1 B)`:/file/artifact`g=proj|r=demo|t=v1.1|a=one.bin]`f",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release text", kind: .release, group: "proj", repository: "demo",
      tag: "v2.0-rc", thanks: false, linkID: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[releases`:/page/releases.mu`g=proj|r=demo]`! / v2.0-rc",
        "",
        "`[󰋑 Thanks (0)`:/page/release.mu`g=proj|r=demo|t=v2.0-rc|thanks=y]",
        "",
        ">>Release v2.0-rc • 2026-09-23 21:46:40",
        "",
        ">>Artifacts",
        "",
        "`*No artifacts for this release`*",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release undated", kind: .release, group: "proj", repository: "demo",
      tag: "undated", thanks: false, linkID: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[releases`:/page/releases.mu`g=proj|r=demo]`! / undated",
        "",
        "`[󰋑 Thanks (0)`:/page/release.mu`g=proj|r=demo|t=undated|thanks=y]",
        "",
        ">>Release undated",
        "",
        "Undated notes",
        "",
        "",
        ">>Artifacts",
        "",
        "`*No artifacts for this release`*",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release no notes", kind: .release, group: "proj", repository: "silent",
      tag: "quiet", thanks: false, linkID: nil,
      blockNullIdentity: false, views: ["silent"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[silent`:/page/repo.mu`g=proj|r=silent]`! / `!`[releases`:/page/releases.mu`g=proj|r=silent]`! / quiet",
        "",
        "`[󰋑 Thanks (0)`:/page/release.mu`g=proj|r=silent|t=quiet|thanks=y]",
        "",
        ">>Release quiet • 2026-09-21 14:13:20",
        "",
        ">>Artifacts",
        "",
        "`*No artifacts for this release`*",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release thanks first", kind: .release, group: "proj", repository: "demo",
      tag: "v1.1", thanks: true, linkID: Data(repeating: 0x33, count: 16),
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[releases`:/page/releases.mu`g=proj|r=demo]`! / v1.1",
        "",
        "`[󰋑 Thanks (1)`:/page/release.mu`g=proj|r=demo|t=v1.1|thanks=y]",
        "",
        ">>Release v1.1 • 2026-09-22 18:00:00",
        "",
        ">Heading",
        "`!Micron`! preview",
        "",
        "",
        ">>Artifacts (1)",
        "",
        "`[ one.bin`:/file/artifact`g=proj|r=demo|t=v1.1|a=one.bin] `F666`[(1 B)`:/file/artifact`g=proj|r=demo|t=v1.1|a=one.bin]`f",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "release thanks second", kind: .release, group: "proj", repository: "demo",
      tag: "v1.1", thanks: true, linkID: Data(repeating: 0x44, count: 16),
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[releases`:/page/releases.mu`g=proj|r=demo]`! / v1.1",
        "",
        "`[󰋑 Thanks (2)`:/page/release.mu`g=proj|r=demo|t=v1.1|thanks=y]",
        "",
        ">>Release v1.1 • 2026-09-22 18:00:00",
        "",
        ">Heading",
        "`!Micron`! preview",
        "",
        "",
        ">>Artifacts (1)",
        "",
        "`[ one.bin`:/file/artifact`g=proj|r=demo|t=v1.1|a=one.bin] `F666`[(1 B)`:/file/artifact`g=proj|r=demo|t=v1.1|a=one.bin]`f",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
  ]
}
