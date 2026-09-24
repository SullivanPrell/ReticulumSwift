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

/// A repository's work documents, listed and shown one at a time, as Python RNS 1.5.4's
/// `serve_work_page` and `serve_work_doc_page` render them.
///
/// The reference rendered every step over one copy of `fixtureScript` with `TZ=UTC`, its
/// permissions resolved by `resolve_doc_permission` itself, so a document's own `allowed` file
/// is read as the node reads it. How long a page took to generate is replaced by `{GEN_TIME}`,
/// and a nil page is a step the reference raised on and answered nothing.
final class RNGitWorkPagesVectorTests: XCTestCase {

  /// Which page a step asks for.
  private enum Kind {
    case list
    case document
  }

  /// One request, the page the reference answered it with, and the repositories it counted a
  /// view of.
  private struct Step {
    let name: String
    let kind: Kind
    let repository: String
    let documentID: String
    let scope: String?
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
    let base = NSTemporaryDirectory() + "/rngit-work-pages-" + UUID().uuidString
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
      switch (step.kind, step.scope) {
      case (.list, let scope?):
        page = handler.serveWorkPage(
          identityHash: nil, groupName: "proj", repositoryName: step.repository, scope: scope,
          timeZone: utc)
      case (.list, nil):
        page = handler.serveWorkPage(
          identityHash: nil, groupName: "proj", repositoryName: step.repository, timeZone: utc)
      case (.document, let scope?):
        page = handler.serveWorkDocumentPage(
          identityHash: nil, groupName: "proj", repositoryName: step.repository,
          documentID: step.documentID, scope: scope, timeZone: utc)
      case (.document, nil):
        page = handler.serveWorkDocumentPage(
          identityHash: nil, groupName: "proj", repositoryName: step.repository,
          documentID: step.documentID, timeZone: utc)
      }

      XCTAssertEqual(
        page.map(Self.normalised), step.page?.joined(separator: "\n"), step.name)
      let counted = handler.statistics.groups["proj"]?.repositories.flatMap { name, counters in
        Array(repeating: name, count: counters.view.values.reduce(0, +))
      }
      XCTAssertEqual(counted ?? [], step.views, step.name)
    }
  }

  /// A node whose `[pages]` section sets `unicode_icons` marks each document with the file icon
  /// every font carries, as the reference renders the "work all" step with `use_nerdfonts` off.
  func testTheListingDrawsUnicodeIconsWhereTheNodeTurnsNerdFontsOff() throws {
    var handler = handler(blockNullIdentity: false)
    handler.useNerdFonts = false
    let page = handler.serveWorkPage(
      identityHash: nil, groupName: "proj", repositoryName: "demo", scope: "all",
      timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")))
    XCTAssertEqual(page.map(Self.normalised), Self.listingWithUnicodeIcons.joined(separator: "\n"))
  }

  /// The "work all" page, rendered by the reference with `use_nerdfonts` off.
  private static let listingWithUnicodeIcons: [String] = [
    "#!c=0",
    "> A Node",
    "",
    ">>",
    "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / work",
    "",
    "`!`[Active`:/page/work.mu`g=proj|r=demo|scope=active]`! • `!`[Completed`:/page/work.mu`g=proj|r=demo|scope=completed]`! • `!`[Proposed`:/page/work.mu`g=proj|r=demo|scope=proposed]`! • `_`!`[All`:/page/work.mu`g=proj|r=demo|scope=all]`!`_",
    "",
    ">>Active (3)",
    "",
    "`!`[🗎 Numbered with zeroes`:/page/work_doc.mu`g=proj|r=demo|id=7|scope=active]`! `F666#7`f",
    "`F6662026-09-25 by <aca31af0441d81dbec71e82da0b4b5f5>`f",
    "",
    "`!`[🗎 A title long enough that the listing has to cut it short before it runs off the edge of the …`:/page/work_doc.mu`g=proj|r=demo|id=2|scope=active]`! `F666#2`f",
    "`F6662026-09-22 by <069092a03c194639207219dd05f9c840>`f",
    "",
    "`!`[🗎 Port the work pages`:/page/work_doc.mu`g=proj|r=demo|id=1|scope=active]`! `F666#1`f",
    "`F6662026-09-21 by <aca31af0441d81dbec71e82da0b4b5f5>`f",
    "`F6666 updates`f",
    "",
    ">>Completed (3)",
    "",
    "`!`[🗎 'a', 1`:/page/work_doc.mu`g=proj|r=demo|id=13|scope=completed]`! `F666#13`f",
    "`F6662026-09-28 by <069092a03c194639207219dd05f9c840>`f",
    "",
    "`!`[🗎 b'bytes title'`:/page/work_doc.mu`g=proj|r=demo|id=11|scope=completed]`! `F666#11`f",
    "`F666 by unknown`f",
    "",
    "`!`[🗎 Untitled`:/page/work_doc.mu`g=proj|r=demo|id=12|scope=completed]`! `F666#12`f",
    "`F666 by unknown`f",
    "",
    ">>Proposed (0)",
    "",
    "`*No proposed work documents`*",
    "",
    "<",
    "-",
    "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
  ]

  /// A handler over group "proj" and its three repositories, each open to everyone, counting
  /// every view.
  private func handler(blockNullIdentity: Bool) -> RNGitPageHandler {
    var permissions = RNGitPermissionSet()
    permissions.read = [.everyone]
    var repositories: [String: RNGitRepository] = [:]
    for name in ["demo", "empty", "broken"] {
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

  /// The documents the steps read.
  ///
  /// Under "demo": in `active`, a signed Markdown document with
  /// comments beside entries that are not comments; a Micron one whose signature does not
  /// verify; one in a directory named with leading zeroes; one its own `allowed` file closes;
  /// and entries that are not documents. In `completed`, documents titled with bytes and with a
  /// list, and one with no `meta`. `proposed` is empty. "broken" holds a document dated in words,
  /// and "empty" has no work at all.
  private static let fixtureScript = #"""
    set -e
    root="$1"
    rm -rf "$root"
    mkdir -p "$root"
    cd "$root"
    mkdir -p 'demo.work/active/1/3'
    mkdir -p 'demo.work/active/4'
    mkdir -p 'demo.work/active/x'
    mkdir -p 'demo.work/proposed'
    mkdir -p 'broken.work/active/1'
    printf '\202\247content\257Dated in words\056\244meta\203\245title\247Undated\247created\251yesterday\246edited\251yesterday' > 'broken.work/active/1/root'
    mkdir -p 'demo.work'
    printf '\043 closed to everyone\012read\072none\012' > 'demo.work/3.allowed'
    mkdir -p 'demo.work/active/007'
    printf '\202\247content\257Leading zeroes\056\244meta\205\246format\250markdown\245title\264Numbered with zeroes\247created\316j\265\317\140\246edited\316j\265\317\140\246author\304\020\254\243\032\360D\035\201\333\354q\350\055\240\264\265\365' > 'demo.work/active/007/root'
    mkdir -p 'demo.work/active/1'
    printf '\202\247content\270Started on the \052\052list\052\052\056\244meta\206\246format\250markdown\245title\300\247created\313A\332\254Rd\020\000\000\246edited\313A\332\254Rd\020\000\000\251signature\304\000\246author\304\020\006\220\222\240\074\031F9 r\031\335\005\371\310\100' > 'demo.work/active/1/1'
    mkdir -p 'demo.work/active/1'
    printf '\202\247content\277Tenth\054 sorted after the second\056\244meta\203\246format\246micron\247created\000\246author\304\020\254\243\032\360D\035\201\333\354q\350\055\240\264\265\365' > 'demo.work/active/1/10'
    mkdir -p 'demo.work/active/1'
    printf '\203\247content\222\241x\001\246format\244text\244meta\202\247created\313A\332\254Yu\371\231\232\246author\222\001\314\377' > 'demo.work/active/1/12'
    mkdir -p 'demo.work/active/1'
    printf '\203\247content\266\140\041bold\140\041 micron \133kept\135\246format\246micron\244meta\202\247created\316j\261W\240\246author\304\000' > 'demo.work/active/1/2'
    mkdir -p 'demo.work/active/1'
    printf '\222\001\002' > 'demo.work/active/1/4'
    mkdir -p 'demo.work/active/1'
    printf '\301' > 'demo.work/active/1/5'
    mkdir -p 'demo.work/active/1'
    printf 'not a comment\012' > 'demo.work/active/1/notes.txt'
    mkdir -p 'demo.work/active/1'
    printf '\202\247content\331P\012  \043 Plan\012\012Ship the \052\052work\052\052 pages\072\012\012\055 list them\012\055 show one\012\012Then \140wire\140 it\056\012  \012\244meta\207\246format\250markdown\245title\263Port the work pages\247created\313A\332\254N\340 \000\000\246edited\313A\332\254N\340 \000\000\246author\304\020\254\243\032\360D\035\201\333\354q\350\055\240\264\265\365\251signature\304\100\370\227\073\013\370\3749\256\362\212\260K\246\362\201oU\237\220y0\100\076\312\0201\207\023\362\275O\012M\000\3517\027\315\053\345\232\007f\312\034\260\306\134\057\372\333o\202\336a\365\264\245\221\326\325\073\072\007\250identity\304\100\217\100\305\255\266\217\045bJ\345\262\024\352vzn\311M\202\235\075\173\136\032\321\272o\076\0418\050\137\051\254\272\341A\274\312\360\262\056\032\224\323M\013\3076\036Rm\013\376\022\310\227\224\274\223\042\226m\327' > 'demo.work/active/1/root'
    mkdir -p 'demo.work/active/2'
    printf '\202\247content\272\076Heading\012\140F00fBlue\140f text\012\244meta\207\246format\246micron\245title\331\140A title long enough that the listing has to cut it short before it runs off the edge of the page\247created\316j\262\302 \246edited\316j\264H\300\246author\304\020\006\220\222\240\074\031F9 r\031\335\005\371\310\100\251signature\304\100\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\250identity\304\100\217\100\305\255\266\217\045bJ\345\262\024\352vzn\311M\202\235\075\173\136\032\321\272o\076\0418\050\137\051\254\272\341A\274\312\360\262\056\032\224\323M\013\3076\036Rm\013\376\022\310\227\224\274\223\042\226m\327' > 'demo.work/active/2/root'
    mkdir -p 'demo.work/active/3'
    printf '\202\247content\247Hidden\056\244meta\205\246format\250markdown\245title\266Closed by its own file\247created\316j\267V\000\246edited\316j\267V\000\246author\304\020\254\243\032\360D\035\201\333\354q\350\055\240\264\265\365' > 'demo.work/active/3/root'
    mkdir -p 'demo.work/active/5'
    printf '\301' > 'demo.work/active/5/root'
    mkdir -p 'demo.work/active/6'
    printf '\200' > 'demo.work/active/6/root'
    mkdir -p 'demo.work/active'
    printf 'a file\054 not a document\012' > 'demo.work/active/9'
    mkdir -p 'demo.work/completed/11'
    printf '\202\247content\240\244meta\204\246format\250markdown\245title\304\013bytes title\247created\000\246edited\316j\270\334\240' > 'demo.work/completed/11/root'
    mkdir -p 'demo.work/completed/12'
    printf '\201\247content\257No meta at all\056' > 'demo.work/completed/12/root'
    mkdir -p 'demo.work/completed/13'
    printf '\202\247content\245  \011  \244meta\204\245title\222\241a\001\247created\316j\272c\100\246edited\316j\272c\100\246author\304\020\006\220\222\240\074\031F9 r\031\335\005\371\310\100' > 'demo.work/completed/13/root'
    mkdir -p demo empty broken
    """#

  /// Each request, in the order the reference answered them.
  private static let steps: [Step] = [
    Step(
      name: "work invalid", kind: .list, repository: "",
      documentID: "", scope: nil,
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
      name: "work no identity", kind: .list, repository: "demo",
      documentID: "", scope: nil,
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
      name: "work unknown", kind: .list, repository: "nope",
      documentID: "", scope: nil,
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
      name: "work active", kind: .list, repository: "demo",
      documentID: "", scope: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / work",
        "",
        "`_`!`[Active`:/page/work.mu`g=proj|r=demo|scope=active]`!`_ • `!`[Completed`:/page/work.mu`g=proj|r=demo|scope=completed]`! • `!`[Proposed`:/page/work.mu`g=proj|r=demo|scope=proposed]`! • `!`[All`:/page/work.mu`g=proj|r=demo|scope=all]`!",
        "",
        ">>Active (3)",
        "",
        "`!`[ Numbered with zeroes`:/page/work_doc.mu`g=proj|r=demo|id=7|scope=active]`! `F666#7`f",
        "`F6662026-09-25 by <aca31af0441d81dbec71e82da0b4b5f5>`f",
        "",
        "`!`[ A title long enough that the listing has to cut it short before it runs off the edge of the …`:/page/work_doc.mu`g=proj|r=demo|id=2|scope=active]`! `F666#2`f",
        "`F6662026-09-22 by <069092a03c194639207219dd05f9c840>`f",
        "",
        "`!`[ Port the work pages`:/page/work_doc.mu`g=proj|r=demo|id=1|scope=active]`! `F666#1`f",
        "`F6662026-09-21 by <aca31af0441d81dbec71e82da0b4b5f5>`f",
        "`F6666 updates`f",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "work completed", kind: .list, repository: "demo",
      documentID: "", scope: "completed",
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / work",
        "",
        "`!`[Active`:/page/work.mu`g=proj|r=demo|scope=active]`! • `_`!`[Completed`:/page/work.mu`g=proj|r=demo|scope=completed]`!`_ • `!`[Proposed`:/page/work.mu`g=proj|r=demo|scope=proposed]`! • `!`[All`:/page/work.mu`g=proj|r=demo|scope=all]`!",
        "",
        ">>Completed (3)",
        "",
        "`!`[ 'a', 1`:/page/work_doc.mu`g=proj|r=demo|id=13|scope=completed]`! `F666#13`f",
        "`F6662026-09-28 by <069092a03c194639207219dd05f9c840>`f",
        "",
        "`!`[ b'bytes title'`:/page/work_doc.mu`g=proj|r=demo|id=11|scope=completed]`! `F666#11`f",
        "`F666 by unknown`f",
        "",
        "`!`[ Untitled`:/page/work_doc.mu`g=proj|r=demo|id=12|scope=completed]`! `F666#12`f",
        "`F666 by unknown`f",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "work proposed", kind: .list, repository: "demo",
      documentID: "", scope: "proposed",
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / work",
        "",
        "`!`[Active`:/page/work.mu`g=proj|r=demo|scope=active]`! • `!`[Completed`:/page/work.mu`g=proj|r=demo|scope=completed]`! • `_`!`[Proposed`:/page/work.mu`g=proj|r=demo|scope=proposed]`!`_ • `!`[All`:/page/work.mu`g=proj|r=demo|scope=all]`!",
        "",
        ">>Proposed (0)",
        "",
        "`*No proposed work documents`*",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "work all", kind: .list, repository: "demo",
      documentID: "", scope: "all",
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / work",
        "",
        "`!`[Active`:/page/work.mu`g=proj|r=demo|scope=active]`! • `!`[Completed`:/page/work.mu`g=proj|r=demo|scope=completed]`! • `!`[Proposed`:/page/work.mu`g=proj|r=demo|scope=proposed]`! • `_`!`[All`:/page/work.mu`g=proj|r=demo|scope=all]`!`_",
        "",
        ">>Active (3)",
        "",
        "`!`[ Numbered with zeroes`:/page/work_doc.mu`g=proj|r=demo|id=7|scope=active]`! `F666#7`f",
        "`F6662026-09-25 by <aca31af0441d81dbec71e82da0b4b5f5>`f",
        "",
        "`!`[ A title long enough that the listing has to cut it short before it runs off the edge of the …`:/page/work_doc.mu`g=proj|r=demo|id=2|scope=active]`! `F666#2`f",
        "`F6662026-09-22 by <069092a03c194639207219dd05f9c840>`f",
        "",
        "`!`[ Port the work pages`:/page/work_doc.mu`g=proj|r=demo|id=1|scope=active]`! `F666#1`f",
        "`F6662026-09-21 by <aca31af0441d81dbec71e82da0b4b5f5>`f",
        "`F6666 updates`f",
        "",
        ">>Completed (3)",
        "",
        "`!`[ 'a', 1`:/page/work_doc.mu`g=proj|r=demo|id=13|scope=completed]`! `F666#13`f",
        "`F6662026-09-28 by <069092a03c194639207219dd05f9c840>`f",
        "",
        "`!`[ b'bytes title'`:/page/work_doc.mu`g=proj|r=demo|id=11|scope=completed]`! `F666#11`f",
        "`F666 by unknown`f",
        "",
        "`!`[ Untitled`:/page/work_doc.mu`g=proj|r=demo|id=12|scope=completed]`! `F666#12`f",
        "`F666 by unknown`f",
        "",
        ">>Proposed (0)",
        "",
        "`*No proposed work documents`*",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "work unknown scope", kind: .list, repository: "demo",
      documentID: "", scope: "later",
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / work",
        "",
        "`_`!`[Active`:/page/work.mu`g=proj|r=demo|scope=active]`!`_ • `!`[Completed`:/page/work.mu`g=proj|r=demo|scope=completed]`! • `!`[Proposed`:/page/work.mu`g=proj|r=demo|scope=proposed]`! • `!`[All`:/page/work.mu`g=proj|r=demo|scope=all]`!",
        "",
        ">>Active (3)",
        "",
        "`!`[ Numbered with zeroes`:/page/work_doc.mu`g=proj|r=demo|id=7|scope=active]`! `F666#7`f",
        "`F6662026-09-25 by <aca31af0441d81dbec71e82da0b4b5f5>`f",
        "",
        "`!`[ A title long enough that the listing has to cut it short before it runs off the edge of the …`:/page/work_doc.mu`g=proj|r=demo|id=2|scope=active]`! `F666#2`f",
        "`F6662026-09-22 by <069092a03c194639207219dd05f9c840>`f",
        "",
        "`!`[ Port the work pages`:/page/work_doc.mu`g=proj|r=demo|id=1|scope=active]`! `F666#1`f",
        "`F6662026-09-21 by <aca31af0441d81dbec71e82da0b4b5f5>`f",
        "`F6666 updates`f",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "work without a work directory", kind: .list, repository: "empty",
      documentID: "", scope: "all",
      blockNullIdentity: false, views: ["empty"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[empty`:/page/repo.mu`g=proj|r=empty]`! / work",
        "",
        "`!`[Active`:/page/work.mu`g=proj|r=empty|scope=active]`! • `!`[Completed`:/page/work.mu`g=proj|r=empty|scope=completed]`! • `!`[Proposed`:/page/work.mu`g=proj|r=empty|scope=proposed]`! • `_`!`[All`:/page/work.mu`g=proj|r=empty|scope=all]`!`_",
        "",
        ">>Active (0)",
        "",
        "`*No active work documents`*",
        "",
        ">>Completed (0)",
        "",
        "`*No completed work documents`*",
        "",
        ">>Proposed (0)",
        "",
        "`*No proposed work documents`*",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "work dated in words", kind: .list, repository: "broken",
      documentID: "", scope: nil,
      blockNullIdentity: false, views: [],
      page: nil),
    Step(
      name: "doc invalid", kind: .document, repository: "demo",
      documentID: "", scope: nil,
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
      name: "doc no identity", kind: .document, repository: "demo",
      documentID: "1", scope: nil,
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
      name: "doc not a number", kind: .document, repository: "demo",
      documentID: "one", scope: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Error",
        "",
        "Invalid document ID",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc unknown repository", kind: .document, repository: "nope",
      documentID: "1", scope: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Error",
        "",
        "The requested repository was not found",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc closed by its own file", kind: .document, repository: "demo",
      documentID: "3", scope: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Error",
        "",
        "The requested work document was not found",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc signed", kind: .document, repository: "demo",
      documentID: " 1 ", scope: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[work`:/page/work.mu`g=proj|r=demo]`! / #1",
        "",
        "`!`[Download`:/file/workdoc`g=proj|r=demo|id=1]`!",
        "",
        ">>Port the work pages",
        "",
        "`F666Author    : <aca31af0441d81dbec71e82da0b4b5f5>`f",
        "`F666Signature : Valid`f",
        "`F666Created   : 2026-09-21 14:13`f",
        "`F666Status    : Active`f",
        "",
        ">Plan",
        "",
        "Ship the `!work`! pages:",
        "",
        " • list them",
        " • show one",
        "",
        "Then `BT383838`Fdddwire`f`b it.",
        "",
        ">>Updates (4)",
        "",
        "`F666#1 by <069092a03c194639207219dd05f9c840> on 2026-09-21 15:13`f",
        "Started on the `!list`!.",
        "",
        "`F666#2 by Unknown on 2026-09-21 16:13`f",
        "`!bold`! micron [kept]",
        "",
        "`F666#10 by <aca31af0441d81dbec71e82da0b4b5f5> on unknown`f",
        "Tenth, sorted after the second.",
        "",
        "`F666#12 by <01ff> on 2026-09-21 17:13`f",
        "['x', 1]",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc in the wrong scope", kind: .document, repository: "demo",
      documentID: "1", scope: "completed",
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Not Found",
        "",
        "The requested work document was not found",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc unknown scope", kind: .document, repository: "demo",
      documentID: "1", scope: "later",
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[work`:/page/work.mu`g=proj|r=demo]`! / #1",
        "",
        "`!`[Download`:/file/workdoc`g=proj|r=demo|id=1]`!",
        "",
        ">>Port the work pages",
        "",
        "`F666Author    : <aca31af0441d81dbec71e82da0b4b5f5>`f",
        "`F666Signature : Valid`f",
        "`F666Created   : 2026-09-21 14:13`f",
        "`F666Status    : Active`f",
        "",
        ">Plan",
        "",
        "Ship the `!work`! pages:",
        "",
        " • list them",
        " • show one",
        "",
        "Then `BT383838`Fdddwire`f`b it.",
        "",
        ">>Updates (4)",
        "",
        "`F666#1 by <069092a03c194639207219dd05f9c840> on 2026-09-21 15:13`f",
        "Started on the `!list`!.",
        "",
        "`F666#2 by Unknown on 2026-09-21 16:13`f",
        "`!bold`! micron [kept]",
        "",
        "`F666#10 by <aca31af0441d81dbec71e82da0b4b5f5> on unknown`f",
        "Tenth, sorted after the second.",
        "",
        "`F666#12 by <01ff> on 2026-09-21 17:13`f",
        "['x', 1]",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc micron", kind: .document, repository: "demo",
      documentID: "2", scope: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[work`:/page/work.mu`g=proj|r=demo]`! / #2",
        "",
        "`!`[Download`:/file/workdoc`g=proj|r=demo|id=2]`!",
        "",
        ">>A title long enough that the listing has to cut it short before it runs off the edge of the page",
        "",
        "`F666Author    : <069092a03c194639207219dd05f9c840>`f",
        "`F666Signature : Not valid`f",
        "`F666Created   : 2026-09-22 18:00`f",
        "`F666Edited    : 2026-09-23 21:46`f",
        "`F666Status    : Active`f",
        "",
        ">Heading",
        "`F00fBlue`f text",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc named with zeroes", kind: .document, repository: "demo",
      documentID: "7", scope: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Not Found",
        "",
        "The requested work document was not found",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc undecodable", kind: .document, repository: "demo",
      documentID: "5", scope: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Error",
        "",
        "Could not load work document",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc empty", kind: .document, repository: "demo",
      documentID: "6", scope: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Error",
        "",
        "Could not load work document",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc bytes title", kind: .document, repository: "demo",
      documentID: "11", scope: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[work`:/page/work.mu`g=proj|r=demo]`! / #11",
        "",
        "`!`[Download`:/file/workdoc`g=proj|r=demo|id=11]`!",
        "",
        ">>b'bytes title'",
        "",
        "`F666Author    : Unknown`f",
        "`F666Signature : Document not signed`f",
        "`F666Created   : unknown`f",
        "`F666Edited    : 2026-09-27 09:06`f",
        "`F666Status    : Completed`f",
        "",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc without meta", kind: .document, repository: "demo",
      documentID: "12", scope: nil,
      blockNullIdentity: false, views: [],
      page: nil),
    Step(
      name: "doc list title", kind: .document, repository: "demo",
      documentID: "13", scope: nil,
      blockNullIdentity: false, views: ["demo"],
      page: [
        "#!c=0",
        "> A Node",
        "",
        ">>",
        "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / `!`[work`:/page/work.mu`g=proj|r=demo]`! / #13",
        "",
        "`!`[Download`:/file/workdoc`g=proj|r=demo|id=13]`!",
        "",
        ">>['a', 1]",
        "",
        "`F666Author    : <069092a03c194639207219dd05f9c840>`f",
        "`F666Signature : Document not signed`f",
        "`F666Created   : 2026-09-28 12:53`f",
        "`F666Status    : Completed`f",
        "",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc missing", kind: .document, repository: "demo",
      documentID: "99", scope: nil,
      blockNullIdentity: false, views: [],
      page: [
        "#!c=0",
        "> A Node",
        "",
        "",
        ">>Not Found",
        "",
        "The requested work document was not found",
        "",
        "<",
        "-",
        "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
      ]),
    Step(
      name: "doc dated in words", kind: .document, repository: "broken",
      documentID: "1", scope: nil,
      blockNullIdentity: false, views: [],
      page: nil),
  ]
}
