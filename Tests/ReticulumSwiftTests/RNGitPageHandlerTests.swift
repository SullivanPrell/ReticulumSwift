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

/// The pages a node serves, as Python RNS 1.5.4's `serve_front_page` resolves them.
final class RNGitPageHandlerTests: XCTestCase {

  /// An identity the fixture groups do not name, standing in for any ordinary reader.
  private static let stranger = Data(repeating: 0x42, count: 16)

  /// The identity a reader who has not identified is resolved as, as the reference recovers it.
  private static let nullIdentityHash = Data(pythonHex: "d7db22f63b453c23bb0688dde565b7c1")!

  /// The destination a repository page renders its own `rns://` address from.
  private static let destinationHash = Data(repeating: 0x7A, count: 16)

  /// Where this test's real repository fixture stands.
  private var fixtureBase = ""

  /// The repository the refs- and repo-page tests read from: one commit, two branches (`main`
  /// the default, and `other`), and two tags (`light` unannotated, `annotated` carrying a
  /// message), with a configured description and a Micron readme.
  private var demoRepository: String { fixtureBase + "/demo" }

  override func setUpWithError() throws {
    try super.setUpWithError()
    fixtureBase = NSTemporaryDirectory() + "/rngit-page-handler-" + UUID().uuidString
    try FileManager.default.createDirectory(
      atPath: fixtureBase, withIntermediateDirectories: true)
    let script = fixtureBase + "/build.sh"
    try Self.fixtureScript.write(toFile: script, atomically: true, encoding: .utf8)
    let built = RNGitProcessRunner().run(
      "sh", arguments: [script, demoRepository], in: fixtureBase)
    try XCTSkipIf(built == nil, "no shell to build the repository with")
    XCTAssertEqual(built?.status, 0, built?.standardError ?? "")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: fixtureBase)
    super.tearDown()
  }

  /// Builds `demoRepository`, pinning `HEAD` to `main` explicitly so the fixture does not
  /// inherit whatever `init.defaultBranch` the host happens to be configured with.
  ///
  /// A raw string literal: the script embeds `printf` octal escapes (`\000`, for the binary
  /// fixtures) that must reach the shell unchanged, not collapsed by Swift's own `\0`-is-NUL
  /// string-literal escaping.
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
    export GIT_AUTHOR_DATE="1700000000 +0000"
    export GIT_COMMITTER_DATE="1700000000 +0000"

    git init -q .
    git symbolic-ref HEAD refs/heads/main
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
    git config commit.gpgsign false

    printf 'A micron readme\n' > README.mu

    mkdir -p src
    printf 'let x = 1\n' > src/main.swift
    printf '# Notes\n\nSome *notes*.\n' > notes.md
    printf 'abc\000def\n' > data.bin
    printf 'PNG\000fakeimagedata\n' > logo.png
    yes 'line of text ' | head -c 300000 > big.txt
    ln -s README.mu link_to_readme

    git add -A
    git update-index --add --cacheinfo 160000,1234567890123456789012345678901234567890,sub
    git commit -q -m "First commit"

    git branch other
    git tag light
    git tag -a annotated -m "An annotated tag"

    git config repository.description "A configured description"
    """#

  /// An empty repository: initialised, with `HEAD` pinned, but with no commit and so no refs.
  private func makeEmptyRepository() throws -> String {
    let path = fixtureBase + "/empty"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    let made = RNGitProcessRunner().run("git", arguments: ["init", "-q", "."], in: path)
    try XCTSkipIf(made == nil, "no git to build the repository with")
    XCTAssertEqual(made?.status, 0)
    XCTAssertEqual(
      RNGitProcessRunner().run(
        "git", arguments: ["symbolic-ref", "HEAD", "refs/heads/main"], in: path
      )?.status, 0)
    return path
  }

  /// Access over one group ("proj") holding one repository ("demo") at a real fixture path.
  private func realAccess(
    fork: String? = nil, mirror: String? = nil, permissions: RNGitPermissionSet? = nil
  ) -> RNGitPageAccess {
    RNGitPageAccess(
      control: RNGitAccessControl(groups: [
        "proj": RNGitGroup(
          name: "proj", path: fixtureBase + "/g",
          repositories: [
            "demo": RNGitRepository(
              name: "demo", path: demoRepository,
              permissions: permissions ?? Self.readableByEveryone(), fork: fork, mirror: mirror)
          ],
          permissions: Self.readableByEveryone())
      ]))
  }

  /// Groups open to any reader: "apple" with one repository, "Zebra" with two.
  ///
  /// The names are chosen so a code-point sort and Swift's default `String` sort disagree:
  /// Python's `sorted()` puts capital `Z` (0x5A) before lowercase `a` (0x61).
  private static func access(blockedIdentities: Set<Data> = []) -> RNGitPageAccess {
    RNGitPageAccess(
      control: RNGitAccessControl(
        groups: [
          "apple": RNGitGroup(
            name: "apple", path: "/g/apple",
            repositories: ["one": RNGitRepository(name: "one", path: "/g/apple/one")],
            permissions: readableByEveryone()),
          "Zebra": RNGitGroup(
            name: "Zebra", path: "/g/zebra",
            repositories: [
              "one": RNGitRepository(name: "one", path: "/g/zebra/one"),
              "two": RNGitRepository(name: "two", path: "/g/zebra/two"),
            ],
            permissions: readableByEveryone()),
        ],
        blockedIdentities: blockedIdentities))
  }

  /// A permission set granting read to everyone, the way `RNGitPermissionSet` is built up.
  private static func readableByEveryone() -> RNGitPermissionSet {
    var permissions = RNGitPermissionSet()
    permissions.read = [.everyone]
    return permissions
  }

  /// A handler reading no custom templates, over `access`.
  private static func handler(
    access: RNGitPageAccess, settings: RNGitNodeSettings = RNGitNodeSettings()
  ) -> RNGitPageHandler {
    RNGitPageHandler(
      access: access, runner: RNGitProcessRunner(), destinationHash: destinationHash,
      settings: settings,
      templates: RNGitPageTemplates(
        directory: "/nonexistent/templates", nodeName: "A Node", version: "1.5.4"))
  }

  /// Every accessible group is listed, in code-point order, each with its repository count.
  func testFrontPageListsAccessibleGroupsInCodePointOrder() throws {
    var handler = Self.handler(access: Self.access())
    let page = try XCTUnwrap(
      String(data: handler.serveFrontPage(identityHash: Self.stranger), encoding: .utf8))

    let zebra = try XCTUnwrap(page.range(of: "Zebra"))
    let apple = try XCTUnwrap(page.range(of: "apple"))
    XCTAssertLessThan(zebra.lowerBound, apple.lowerBound, "Zebra must be listed before apple")

    XCTAssertTrue(
      page.contains(
        "`!`[  \u{2022} apple`:/page/group.mu`g=apple]`!" + " (1 repository)"))
    XCTAssertTrue(
      page.contains(
        "`!`[  \u{2022} Zebra`:/page/group.mu`g=Zebra]`!" + " (2 repositories)"))
    XCTAssertTrue(page.contains("`!`[Node`:/page/index.mu]`!" + " /"))
  }

  /// A reader who can see no groups is told so, rather than shown an empty list.
  func testFrontPageWithNoAccessibleGroups() throws {
    let shut = RNGitPageAccess(control: RNGitAccessControl(groups: [:]))
    var handler = Self.handler(access: shut)
    let page = try XCTUnwrap(
      String(data: handler.serveFrontPage(identityHash: Self.stranger), encoding: .utf8))

    XCTAssertTrue(page.contains("No groups available"))
  }

  /// The view is counted before an unidentified reader is turned away, not instead of it.
  func testFrontPageCountsTheViewBeforeTurningAnUnidentifiedReaderAway() throws {
    var settings = RNGitNodeSettings()
    settings.statsEnabled = true
    settings.blockedIdentities = [Self.nullIdentityHash]
    let blocked = Self.access(blockedIdentities: [Self.nullIdentityHash])
    var handler = Self.handler(access: blocked, settings: settings)

    let page = try XCTUnwrap(
      String(data: handler.serveFrontPage(identityHash: nil), encoding: .utf8))

    XCTAssertTrue(page.contains("This page requires identification, and none was received."))
    XCTAssertEqual(handler.statistics.frontPageViews.values.reduce(0, +), 1)
  }

  /// An identity the settings name to ignore is not counted.
  func testFrontPageIgnoresAnIdentityTheNodeDoesNotCount() throws {
    var settings = RNGitNodeSettings()
    settings.statsEnabled = true
    settings.statsIgnored = [Self.stranger]
    var handler = Self.handler(access: Self.access(), settings: settings)

    _ = handler.serveFrontPage(identityHash: Self.stranger)

    XCTAssertTrue(handler.statistics.frontPageViews.isEmpty)
  }

  /// A node that counts nothing counts no front-page views either.
  func testFrontPageCountsNothingWhenStatisticsAreDisabled() throws {
    var handler = Self.handler(access: Self.access())
    _ = handler.serveFrontPage(identityHash: Self.stranger)
    XCTAssertTrue(handler.statistics.frontPageViews.isEmpty)
  }

  // MARK: - Group page

  /// A group's repositories are listed in code-point order.
  func testGroupPageListsAccessibleRepositoriesSorted() throws {
    var handler = Self.handler(access: Self.access())
    let page = try XCTUnwrap(
      String(
        data: handler.serveGroupPage(identityHash: Self.stranger, groupName: "Zebra"),
        encoding: .utf8))

    let one = try XCTUnwrap(page.range(of: "one"))
    let two = try XCTUnwrap(page.range(of: "two"))
    XCTAssertLessThan(one.lowerBound, two.lowerBound, "one must be listed before two")
    XCTAssertTrue(page.contains("> Repositories"))
    XCTAssertTrue(page.contains("`!`[Node`:/page/index.mu]`!" + " / Zebra"))
  }

  /// A group no group of that name has, and a group whose repositories are all closed, both
  /// read as "not found"—the same message either way.
  func testGroupPageNotFoundForUnknownGroup() throws {
    var handler = Self.handler(access: Self.access())
    let page = try XCTUnwrap(
      String(
        data: handler.serveGroupPage(identityHash: Self.stranger, groupName: "Nonexistent"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("The requested group was not found"))
  }

  /// An empty group name is rejected before any lookup.
  func testGroupPageInvalidRequestForEmptyGroupName() throws {
    var handler = Self.handler(access: Self.access())
    let page = try XCTUnwrap(
      String(
        data: handler.serveGroupPage(identityHash: Self.stranger, groupName: ""),
        encoding: .utf8))
    XCTAssertTrue(page.contains("Invalid request"))
  }

  /// Unlike the front page, a group page's view is only counted on success: a reader turned
  /// away for having no identity is not counted, because the check runs before `viewSucceeded`.
  func testGroupPageDoesNotCountViewWhenBlocked() throws {
    var settings = RNGitNodeSettings()
    settings.statsEnabled = true
    settings.blockedIdentities = [Self.nullIdentityHash]
    let blocked = Self.access(blockedIdentities: [Self.nullIdentityHash])
    var handler = Self.handler(access: blocked, settings: settings)

    _ = handler.serveGroupPage(identityHash: nil, groupName: "Zebra")

    XCTAssertNil(handler.statistics.groups["Zebra"])
  }

  /// A successful request counts a group view, not a repository view.
  func testGroupPageCountsGroupViewOnSuccess() throws {
    var settings = RNGitNodeSettings()
    settings.statsEnabled = true
    var handler = Self.handler(access: Self.access(), settings: settings)

    _ = handler.serveGroupPage(identityHash: Self.stranger, groupName: "Zebra")

    XCTAssertEqual(handler.statistics.groups["Zebra"]?.view.values.reduce(0, +), 1)
    XCTAssertEqual(handler.statistics.groups["Zebra"]?.repositories.isEmpty, true)
  }

  // MARK: - Refs page

  /// Every branch and tag is listed, the default branch and the annotated tag each marked.
  func testRefsPageListsBranchesAndTags() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveRefsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Branches (2)"))
    XCTAssertTrue(page.contains("Tags (2)"))
    let main = try XCTUnwrap(page.range(of: "main"))
    let other = try XCTUnwrap(page.range(of: "other"))
    XCTAssertLessThan(main.lowerBound, other.lowerBound, "main must be listed before other")
    XCTAssertTrue(page.contains("(default)"))
    XCTAssertTrue(page.contains("(annotated)"))
    XCTAssertTrue(page.contains("light"))
  }

  /// Filtering to branches only omits the tags section entirely.
  func testRefsPageFiltersToHeadsOnly() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveRefsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          refType: "heads"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Branches (2)"))
    XCTAssertFalse(page.contains("Tags ("))
  }

  /// Filtering to tags only omits the branches section entirely.
  func testRefsPageFiltersToTagsOnly() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveRefsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          refType: "tags"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Tags (2)"))
    XCTAssertFalse(page.contains("Branches ("))
  }

  /// "No refs found" only ever fires when the request looked at both kinds at once: narrowed to
  /// one kind, the message stays silent even over a repository with no refs at all.
  func testRefsPageNoRefsMessageNeverFiresWhenFilteredToOneType() throws {
    let empty = try makeEmptyRepository()
    let access = RNGitPageAccess(
      control: RNGitAccessControl(groups: [
        "proj": RNGitGroup(
          name: "proj", path: fixtureBase + "/g",
          repositories: ["empty": RNGitRepository(name: "empty", path: empty)],
          permissions: Self.readableByEveryone())
      ]))
    var handler = Self.handler(access: access)
    let page = try XCTUnwrap(
      String(
        data: handler.serveRefsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "empty",
          refType: "heads"),
        encoding: .utf8))

    XCTAssertFalse(page.contains("No refs found"))
  }

  /// An unknown repository is reported as not found, with the breadcrumb still shown.
  func testRefsPageRepositoryNotFound() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveRefsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "nonexistent"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("The requested repository was not found."))
  }

  /// An empty group or repository name is rejected before any lookup.
  func testRefsPageInvalidRequestForEmptyNames() throws {
    var handler = Self.handler(access: Self.access())
    let page = try XCTUnwrap(
      String(
        data: handler.serveRefsPage(identityHash: Self.stranger, groupName: "", repositoryName: ""),
        encoding: .utf8))
    XCTAssertTrue(page.contains("Invalid request"))
  }

  /// A reader with no identity is turned away where the node blocks the null identity.
  func testRefsPageNoIdentityBlocked() throws {
    var settings = RNGitNodeSettings()
    settings.statsEnabled = true
    settings.blockedIdentities = [Self.nullIdentityHash]
    let blocked = Self.access(blockedIdentities: [Self.nullIdentityHash])
    var handler = Self.handler(access: blocked, settings: settings)
    let page = try XCTUnwrap(
      String(
        data: handler.serveRefsPage(identityHash: nil, groupName: "Zebra", repositoryName: "one"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("This page requires identification, and none was received."))
  }

  // MARK: - Repository page

  /// The description, the readme, and a stats row with no releases and no stats link (the
  /// reader holds no stats permission) are all shown.
  func testRepoPageShowsDescriptionStatsAndReadme() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("A configured description"))
    XCTAssertTrue(page.contains("Files"))
    XCTAssertTrue(page.contains("Work (0)"))
    XCTAssertTrue(page.contains("Commits (1)"))
    XCTAssertTrue(page.contains("Branches (2)"))
    XCTAssertTrue(page.contains("Tags (2)"))
    XCTAssertTrue(page.contains("Thanks (0)"))
    XCTAssertFalse(page.contains("Releases ("))
    XCTAssertFalse(page.contains("/page/stats.mu"))
    XCTAssertTrue(page.contains("A micron readme"))
    XCTAssertTrue(
      page.contains(
        "rns://" + RNSUtilities.hexrep(Self.destinationHash, delimit: false) + "/proj/demo"))
  }

  /// A reader who holds the stats permission is shown the stats link; one who does not, is not.
  func testRepoPageShowsStatsLinkOnlyWithPermission() throws {
    var granted = Self.readableByEveryone()
    granted.stats = [.everyone]
    var handler = Self.handler(access: realAccess(permissions: granted))
    let page = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("/page/stats.mu"))
  }

  /// Thanking the same repository from the same link twice counts once; a different link counts
  /// again, mirroring the reference's own link-keyed deduplication.
  ///
  /// The first click reads back "Thanks (0)", not "(1)": the reference's own
  /// `repository_thanks` writes the new count to disk but falls out of its `if` without
  /// returning it when the file did not already exist, so only the next call—deduped or
  /// not—actually reads that count back.
  func testRepoPageThanksCountsOnceThenAgainForADifferentLink() throws {
    let linkA = Data(repeating: 0x01, count: 16)
    let linkB = Data(repeating: 0x02, count: 16)
    var handler = Self.handler(access: realAccess())

    let first = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          thanksClicked: true, linkID: linkA),
        encoding: .utf8))
    XCTAssertTrue(first.contains("Thanks (0)"), "the very first click never reads its own write")

    let second = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          thanksClicked: true, linkID: linkA),
        encoding: .utf8))
    XCTAssertTrue(second.contains("Thanks (1)"), "the same link must not be counted twice")

    let third = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          thanksClicked: true, linkID: linkB),
        encoding: .utf8))
    XCTAssertTrue(third.contains("Thanks (2)"))
  }

  /// An unknown repository is reported as not found.
  func testRepoPageNotFound() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "nonexistent"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("The requested repository was not found."))
  }

  /// An empty group or repository name is rejected before any lookup.
  func testRepoPageInvalidRequestForEmptyNames() throws {
    var handler = Self.handler(access: Self.access())
    let page = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(identityHash: Self.stranger, groupName: "", repositoryName: ""),
        encoding: .utf8))
    XCTAssertTrue(page.contains("Invalid request"))
  }

  /// A reader with no identity is turned away where the node blocks the null identity.
  func testRepoPageNoIdentityBlocked() throws {
    var settings = RNGitNodeSettings()
    settings.blockedIdentities = [Self.nullIdentityHash]
    let blocked = Self.access(blockedIdentities: [Self.nullIdentityHash])
    var handler = Self.handler(access: blocked, settings: settings)
    let page = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(identityHash: nil, groupName: "Zebra", repositoryName: "one"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("This page requires identification, and none was received."))
  }

  /// A repository with no readme at all shows the placeholder rather than nothing.
  func testRepoPageWithNoReadmeShowsPlaceholder() throws {
    let empty = try makeEmptyRepository()
    let access = RNGitPageAccess(
      control: RNGitAccessControl(groups: [
        "proj": RNGitGroup(
          name: "proj", path: fixtureBase + "/g",
          repositories: ["empty": RNGitRepository(name: "empty", path: empty)],
          permissions: Self.readableByEveryone())
      ]))
    var handler = Self.handler(access: access)
    let page = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "empty"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("No README file found in this repository."))
  }

  /// A negative `source_indent` (a breadcrumb shorter than "mirrored from") must clamp to zero
  /// rather than crash `String(repeating:count:)`, which has no tolerance for a negative count.
  func testRepoPageMirroredFromLineDoesNotCrashWithAShortBreadcrumb() throws {
    let access = RNGitPageAccess(
      control: RNGitAccessControl(groups: [
        "a": RNGitGroup(
          name: "a", path: fixtureBase + "/g",
          repositories: [
            "a": RNGitRepository(
              name: "a", path: demoRepository, mirror: "https://example.com/upstream")
          ],
          permissions: Self.readableByEveryone())
      ]))
    var handler = Self.handler(access: access)
    let page = try XCTUnwrap(
      String(
        data: handler.serveRepoPage(
          identityHash: Self.stranger, groupName: "a", repositoryName: "a"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Mirrored from"))
    XCTAssertTrue(page.contains("https://example.com/upstream"))
  }

  // MARK: - Tree page

  /// Root listing sorts directories and the submodule ahead of files, then alphabetically by
  /// lowercased name within each group—the reference's own `sort_key`.
  ///
  /// Root has no parent directory to link back to.
  func testTreePageSortsDirectoriesAndSubmodulesBeforeFilesAlphabetically() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveTreePage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo"),
        encoding: .utf8))

    let markers = [
      "path=src", "sub", "path=big.txt", "path=data.bin", "link_to_readme", "path=logo.png",
      "path=README.mu",
    ]
    let positions = try markers.map { marker -> String.Index in
      try XCTUnwrap(page.range(of: marker)?.lowerBound, "expected to find '\(marker)'")
    }
    XCTAssertEqual(positions, positions.sorted(), "expected \(markers) in that order")
    XCTAssertFalse(page.contains("../"), "the root listing has no parent directory to link to")
  }

  /// A submodule (a gitlink tree entry) is marked distinctly from an ordinary directory.
  func testTreePageMarksSubmoduleEntries() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveTreePage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("sub"))
    XCTAssertTrue(page.contains("(submodule)"))
  }

  /// A symlink entry in a tree listing shows its target rather than a size.
  func testTreePageShowsSymlinkTargetWithArrow() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveTreePage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("link_to_readme"))
    XCTAssertTrue(page.contains("→ README.mu"))
  }

  /// A subdirectory's page carries a parent-directory link and lists only its own entries.
  func testTreePageNestedDirectoryShowsParentLinkAndOwnEntries() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveTreePage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          treePath: "src"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("../"), "a subdirectory must link back to its parent")
    XCTAssertTrue(
      page.contains("path=src%2Fmain.swift"),
      "the field value is percent-encoded like any other quotePlus field")
    XCTAssertTrue(page.contains("main.swift"))
  }

  /// An unresolvable ref reports the error by name and offers a way back to the refs list.
  func testTreePageRefNotFoundShowsErrorAndRefsLink() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveTreePage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          ref: "nonexistent-ref"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("The ref 'nonexistent-ref' does not exist in this repository."))
    XCTAssertTrue(page.contains("View All Refs"))
  }

  /// An unknown repository is reported as not found, distinctly worded from the refs/repo pages.
  func testTreePageRepositoryNotFound() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveTreePage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "nonexistent"),
        encoding: .utf8))
    XCTAssertTrue(
      page.contains("The requested repository does not exist or you do not have access to it."))
  }

  /// A reader with no identity is turned away where the node blocks the null identity.
  func testTreePageNoIdentityBlocked() throws {
    var settings = RNGitNodeSettings()
    settings.blockedIdentities = [Self.nullIdentityHash]
    let blocked = Self.access(blockedIdentities: [Self.nullIdentityHash])
    var handler = Self.handler(access: blocked, settings: settings)
    let page = try XCTUnwrap(
      String(
        data: handler.serveTreePage(identityHash: nil, groupName: "Zebra", repositoryName: "one"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("This page requires identification, and none was received."))
  }

  /// A repository whose root holds `count` files named so a lexical sort matches a numeric one
  /// (`file0000.txt` through `file<count-1>.txt`), for the tree page's pagination boundary.
  private func makeManyFilesRepository(count: Int) throws -> String {
    let path = fixtureBase + "/many"
    let width = String(count - 1).count
    let script = """
      set -e
      root="$1"
      rm -rf "$root"
      mkdir -p "$root"
      cd "$root"
      git init -q .
      git symbolic-ref HEAD refs/heads/main
      git config user.name Author
      git config user.email author@example.com
      git config commit.gpgsign false
      i=0
      while [ $i -le \(count - 1) ]; do
        name=$(printf 'file%0\(width)d.txt' "$i")
        printf 'x' > "$name"
        i=$((i + 1))
      done
      git add -A
      git commit -q -m many
      """
    let scriptPath = fixtureBase + "/many.sh"
    try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
    let built = RNGitProcessRunner().run("sh", arguments: [scriptPath, path], in: fixtureBase)
    try XCTSkipIf(built == nil, "no shell to build the repository with")
    XCTAssertEqual(built?.status, 0, built?.standardError ?? "")
    return path
  }

  /// More than one page of entries: pagination controls with the right counts, and the
  /// unclamped low bound the reference's own slicing arithmetic produces.
  func testTreePagePaginatesPastOneThousandEntries() throws {
    let many = try makeManyFilesRepository(count: 1001)
    let access = RNGitPageAccess(
      control: RNGitAccessControl(groups: [
        "proj": RNGitGroup(
          name: "proj", path: fixtureBase + "/g",
          repositories: ["many": RNGitRepository(name: "many", path: many)],
          permissions: Self.readableByEveryone())
      ]))
    var handler = Self.handler(access: access)

    let firstPage = try XCTUnwrap(
      String(
        data: handler.serveTreePage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "many"),
        encoding: .utf8))
    XCTAssertTrue(firstPage.contains("Showing 1-1000 of 1001 entries"))
    XCTAssertTrue(firstPage.contains("Page 1 of 2"))
    XCTAssertTrue(firstPage.contains("Next »"))
    XCTAssertFalse(firstPage.contains("« Previous"))

    let secondPage = try XCTUnwrap(
      String(
        data: handler.serveTreePage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "many", page: 1),
        encoding: .utf8))
    XCTAssertTrue(secondPage.contains("Showing 1001-1001 of 1001 entries"))
    XCTAssertTrue(secondPage.contains("Page 2 of 2"))
    XCTAssertTrue(secondPage.contains("« Previous"))
    XCTAssertFalse(secondPage.contains("Next »"))
  }

  // MARK: - Blob page

  /// A symlink shows its target in italics rather than trying to display file content.
  func testBlobPageSymlinkShowsTargetInItalics() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "link_to_readme"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Symlink → README.mu"))
    XCTAssertTrue(page.contains("`*README.mu`*"))
  }

  /// A non-image binary file gets a placeholder message and only a download link, no
  /// rendered/raw toggle.
  func testBlobPageBinaryNonImageShowsPlaceholderAndOnlyDownload() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "data.bin"),
        encoding: .utf8))

    XCTAssertTrue(
      page.contains("This file appears to be binary and cannot be displayed as text."))
    XCTAssertTrue(page.contains("Displaying Raw"))
    XCTAssertFalse(page.contains("View rendered"))
    XCTAssertTrue(page.contains("Binary"))
  }

  /// A binary file with an image extension is offered inline as an image rather than the
  /// binary-file placeholder.
  func testBlobPageBinaryImageRendersImageMarkup() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "logo.png"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("`(Image file"))
    XCTAssertTrue(page.contains("/media/proj/demo/HEAD/logo.png"))
    XCTAssertFalse(page.contains("appears to be binary and cannot be displayed"))
  }

  /// A file over the display limit shows a size-exceeded message rather than its content.
  func testBlobPageOversizedFileExceedsDisplayLimit() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "big.txt"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("which exceeds the display limit of"))
    XCTAssertTrue(page.contains("Text,"))
  }

  /// A `.mu` file is rendered by default, its Micron markup passed through as page content.
  func testBlobPageMicronFileRendersByDefault() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "README.mu"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Displaying Rendered"))
    XCTAssertTrue(page.contains("View raw"))
    XCTAssertTrue(page.contains("A micron readme"))
  }

  /// Asking for the raw view of a renderable file flips the nav state without needing the
  /// render flag.
  func testBlobPageMicronFileRawShowsRawNavState() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "README.mu", raw: true),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Displaying Raw"))
    XCTAssertTrue(page.contains("View rendered"))
  }

  /// A `.md` file is converted through `MarkdownToMicron` when rendered, not shown as literal
  /// source: the heading marker becomes a Micron heading, and the italic marker becomes one too.
  func testBlobPageMarkdownFileRendersThroughMarkdownToMicron() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "notes.md"),
        encoding: .utf8))

    XCTAssertTrue(page.contains(">Notes"))
    XCTAssertTrue(page.contains("`*notes`*"))
    XCTAssertFalse(page.contains("# Notes"), "the heading marker must be converted, not shown raw")
  }

  /// A non-renderable source file is always shown through the syntax highlighter, never offered
  /// a rendered view.
  func testBlobPageSourceFileIsSyntaxHighlighted() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "src/main.swift"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Displaying Raw"))
    XCTAssertFalse(page.contains("View rendered"), "a non-renderable file has no rendered view")
    XCTAssertTrue(page.contains("let"), "the highlighted output must still carry the source text")
  }

  /// Turning off syntax highlighting falls back to the same plain-source wrapping a
  /// renderable-but-unrendered file gets, matching the reference's own fallback.
  func testBlobPageSourceFileWithHighlightingDisabledShowsPlainSource() throws {
    var settings = RNGitNodeSettings()
    settings.highlightSyntax = false
    var handler = Self.handler(access: realAccess(), settings: settings)
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "src/main.swift"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("`="))
    XCTAssertTrue(page.contains("let x = 1"))
  }

  /// A path naming a directory is answered with the tree page, not a blob error.
  func testBlobPageOfADirectoryRedirectsToTreePage() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "src"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Contents:"))
    XCTAssertTrue(page.contains("main.swift"))
  }

  /// An empty file path is rejected before any repository lookup.
  func testBlobPageInvalidPathForEmptyFilePath() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo", filePath: ""),
        encoding: .utf8))
    XCTAssertTrue(page.contains("No file path specified."))
  }

  /// An unresolvable ref is reported with the blob page's own wording ("Ref Not Found" as a
  /// level-1 heading), distinct from the tree page's "Error" level-2 heading for the same case.
  func testBlobPageRefNotFound() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          ref: "nonexistent-ref", filePath: "README.mu"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("The ref 'nonexistent-ref' does not exist in this repository."))
  }

  /// An unknown repository is reported as not found.
  func testBlobPageRepositoryNotFound() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "nonexistent",
          filePath: "README.mu"),
        encoding: .utf8))
    XCTAssertTrue(
      page.contains("The requested repository does not exist or you do not have access to it."))
  }

  /// A path that resolves to no object at the ref reports "not found", not an error.
  func testBlobPageFileNotFoundAtRef() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "nonexistent-file.txt"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("File not found at this ref."))
  }

  /// A reader with no identity is turned away where the node blocks the null identity.
  func testBlobPageNoIdentityBlocked() throws {
    var settings = RNGitNodeSettings()
    settings.blockedIdentities = [Self.nullIdentityHash]
    let blocked = Self.access(blockedIdentities: [Self.nullIdentityHash])
    var handler = Self.handler(access: blocked, settings: settings)
    let page = try XCTUnwrap(
      String(
        data: handler.serveBlobPage(identityHash: nil, groupName: "Zebra", repositoryName: "one"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("This page requires identification, and none was received."))
  }

  /// The full hash `ref` names in `repository`, fetched directly rather than through the code
  /// under test.
  private func revParse(_ ref: String, in repository: String) throws -> String {
    let result = RNGitProcessRunner().run("git", arguments: ["rev-parse", ref], in: repository)
    try XCTSkipIf(result == nil, "no git to resolve a hash with")
    XCTAssertEqual(result?.status, 0)
    return (result?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Two commits touching the same three files, so the second commit's own status detection (the
  /// only one with a parent to compare against) reports all four letters: `alpha.txt` modified,
  /// `beta.txt` deleted, `gamma.txt` added, and `pic.bin`—a binary file present on both sides,
  /// which numstat can only ever report as `-`/`-`—left at the reader's own fallback of "R".
  private func makeHistoryRepository() throws -> String {
    let path = fixtureBase + "/history"
    let script = #"""
      set -e
      root="$1"
      rm -rf "$root"
      mkdir -p "$root"
      cd "$root"

      export GIT_AUTHOR_NAME="Hist Author"
      export GIT_AUTHOR_EMAIL="hist@example.com"
      export GIT_COMMITTER_NAME="Hist Author"
      export GIT_COMMITTER_EMAIL="hist@example.com"
      export GIT_AUTHOR_DATE="1700000100 +0000"
      export GIT_COMMITTER_DATE="1700000100 +0000"

      git init -q .
      git symbolic-ref HEAD refs/heads/main
      git config user.name "$GIT_AUTHOR_NAME"
      git config user.email "$GIT_AUTHOR_EMAIL"
      git config commit.gpgsign false

      printf 'alpha one\n' > alpha.txt
      printf 'beta one\n' > beta.txt
      printf 'BIN\000one\n' > pic.bin
      git add -A
      git commit -q -m "First commit"

      rm beta.txt
      printf 'alpha one\nalpha two\n' > alpha.txt
      printf 'GAMMA\n' > gamma.txt
      printf 'BIN\000two\n' > pic.bin
      export GIT_AUTHOR_DATE="1700000200 +0000"
      export GIT_COMMITTER_DATE="1700000200 +0000"
      git add -A
      git commit -q -m "Second commit"
      """#
    let scriptPath = fixtureBase + "/history.sh"
    try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
    let built = RNGitProcessRunner().run("sh", arguments: [scriptPath, path], in: fixtureBase)
    try XCTSkipIf(built == nil, "no shell to build the repository with")
    XCTAssertEqual(built?.status, 0, built?.standardError ?? "")
    return path
  }

  // MARK: - Commits page

  /// Each commit lists its full hash in the link's `h` field, its short hash as the visible
  /// label, its author, and its subject on its own line.
  func testCommitsPageListsHashAuthorAndSubject() throws {
    let hash = try revParse("HEAD", in: demoRepository)
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("h=\(hash)"))
    XCTAssertTrue(page.contains(String(hash.prefix(7))))
    XCTAssertTrue(page.contains("Author"))
    XCTAssertTrue(page.contains("First commit"))
  }

  /// Filtering to one file's history adds that file to the breadcrumb and titles the heading
  /// with it.
  func testCommitsPageBreadcrumbIncludesFilePathWhenFiltering() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "README.mu"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("README.mu"))
    XCTAssertTrue(page.contains("Commits for README.mu"))
  }

  /// A path that touches no commits under `ref` reports the empty-state message, not an error.
  func testCommitsPageNoCommitsFoundForUnmatchedPath() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          filePath: "nonexistent-file.txt"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("No commits found."))
  }

  /// A page past the end of history is empty, not an error.
  func testCommitsPageNoCommitsFoundPastLastPage() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo", page: 5),
        encoding: .utf8))

    XCTAssertTrue(page.contains("No commits found."))
  }

  /// An unresolvable ref reports the error by name.
  func testCommitsPageRefNotFound() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          ref: "nonexistent-ref"),
        encoding: .utf8))

    XCTAssertTrue(page.contains("The ref 'nonexistent-ref' does not exist in this repository."))
  }

  /// An unknown repository is reported as not found, worded the way the refs/tree/blob pages are.
  func testCommitsPageRepositoryNotFound() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitsPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "nonexistent"),
        encoding: .utf8))
    XCTAssertTrue(
      page.contains("The requested repository does not exist or you do not have access to it."))
  }

  /// A reader with no identity is turned away where the node blocks the null identity.
  func testCommitsPageNoIdentityBlocked() throws {
    var settings = RNGitNodeSettings()
    settings.blockedIdentities = [Self.nullIdentityHash]
    let blocked = Self.access(blockedIdentities: [Self.nullIdentityHash])
    var handler = Self.handler(access: blocked, settings: settings)
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitsPage(
          identityHash: nil, groupName: "Zebra", repositoryName: "one"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("This page requires identification, and none was received."))
  }

  // MARK: - Commit page

  /// The metadata block names the author and, this fixture's committer differing from its
  /// author, the committer too, and offers a link to browse the tree at this commit.
  func testCommitPageShowsMetadataCommitterAndTreeLink() throws {
    let hash = try revParse("HEAD", in: demoRepository)
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          commitHash: hash),
        encoding: .utf8))

    XCTAssertTrue(page.contains("Commit \(hash)"))
    XCTAssertTrue(page.contains("Browse tree at this commit"))
    XCTAssertTrue(page.contains("ref=\(hash)"))
    XCTAssertTrue(page.contains("Author     : Author <author@example.com>"))
    XCTAssertTrue(page.contains("Committer : Committer <committer@example.com>"))
    XCTAssertTrue(page.contains("Date       : 2023-11-14T22:13:20Z"))
    XCTAssertTrue(page.contains("Date      : 2023-11-14T22:13:20Z"))
  }

  /// An unsigned commit computes "Not signed" internally but never actually renders the
  /// "Signature  :" line—`show_sig` only turns true inside the three signed branches, so this
  /// is the reference's own control flow, not an omission to fix.
  func testCommitPageSignatureLineOmittedWhenUnsigned() throws {
    let hash = try revParse("HEAD", in: demoRepository)
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          commitHash: hash),
        encoding: .utf8))

    XCTAssertFalse(page.contains("Signature"))
    XCTAssertFalse(page.contains("Not signed"))
  }

  /// The Diff section renders the commit's own patch, colour-coded by addition.
  func testCommitPageShowsDiffSection() throws {
    let hash = try revParse("HEAD", in: demoRepository)
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          commitHash: hash),
        encoding: .utf8))

    XCTAssertTrue(page.contains(">>Diff\n"))
    XCTAssertTrue(page.contains("\(RNGitPage.Colour.diffAdded)+A micron readme`f"))
  }

  /// A commit with a parent gets full status detection: a file absent from the parent is "A",
  /// one absent from the commit itself is "D", one present on both sides that changed is "M",
  /// and a binary file present on both sides keeps the reader's own fallback of "R".
  func testCommitPageShowsAllFourFileStatusIndicators() throws {
    let history = try makeHistoryRepository()
    let access = RNGitPageAccess(
      control: RNGitAccessControl(groups: [
        "proj": RNGitGroup(
          name: "proj", path: fixtureBase + "/g",
          repositories: ["history": RNGitRepository(name: "history", path: history)],
          permissions: Self.readableByEveryone())
      ]))
    var handler = Self.handler(access: access)
    let hash = try revParse("HEAD", in: history)

    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "history",
          commitHash: hash),
        encoding: .utf8))

    XCTAssertTrue(page.contains("\(RNGitPage.Colour.diffAdded)A`f"))
    XCTAssertTrue(page.contains("\(RNGitPage.Colour.diffRemoved)D`f"))
    XCTAssertTrue(page.contains("`Faa0M`f"))
    XCTAssertTrue(page.contains("\(RNGitPage.Colour.diffPosition)R`f"))
    XCTAssertTrue(page.contains("alpha.txt"))
    XCTAssertTrue(page.contains("beta.txt"))
    XCTAssertTrue(page.contains("gamma.txt"))
    XCTAssertTrue(page.contains("pic.bin"))
    XCTAssertTrue(page.contains("4 files changed"))
  }

  /// Missing group or repository names are rejected before anything else runs.
  func testCommitPageInvalidRequestForEmptyNames() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "", repositoryName: ""),
        encoding: .utf8))
    XCTAssertTrue(page.contains("Invalid request"))
  }

  /// This page's own repository-not-found wording differs from the refs/tree/blob/commits
  /// pages': "was not found" at an "Error" heading, not "does not exist or access" at "Not
  /// Found".
  func testCommitPageRepositoryNotFound() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "nonexistent"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("The requested repository was not found."))
  }

  func testCommitPageRefNotFound() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          ref: "nonexistent-ref"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("The ref 'nonexistent-ref' does not exist in this repository."))
  }

  /// Both an empty hash and one under seven characters are rejected before any git call.
  func testCommitPageEmptyOrShortCommitHashRejected() throws {
    var handler = Self.handler(access: realAccess())

    let emptyPage = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo"),
        encoding: .utf8))
    XCTAssertTrue(emptyPage.contains("No valid commit hash specified."))

    let shortPage = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          commitHash: "abc12"),
        encoding: .utf8))
    XCTAssertTrue(shortPage.contains("No valid commit hash specified."))
  }

  func testCommitPageUnresolvableCommitHash() throws {
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          commitHash: "abcdef0"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("The commit abcdef0 does not exist in this repository."))
  }

  /// A hash that resolves to a real object which is not a commit (here, a blob) is reported by
  /// name rather than treated as a commit.
  func testCommitPageHashResolvesButIsNotACommit() throws {
    let blobHash = try revParse("HEAD:README.mu", in: demoRepository)
    var handler = Self.handler(access: realAccess())
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: Self.stranger, groupName: "proj", repositoryName: "demo",
          commitHash: blobHash),
        encoding: .utf8))
    XCTAssertTrue(page.contains("The hash \(blobHash) does not refer to a commit."))
  }

  /// A reader with no identity is turned away where the node blocks the null identity.
  func testCommitPageNoIdentityBlocked() throws {
    var settings = RNGitNodeSettings()
    settings.blockedIdentities = [Self.nullIdentityHash]
    let blocked = Self.access(blockedIdentities: [Self.nullIdentityHash])
    var handler = Self.handler(access: blocked, settings: settings)
    let page = try XCTUnwrap(
      String(
        data: handler.serveCommitPage(
          identityHash: nil, groupName: "Zebra", repositoryName: "one"),
        encoding: .utf8))
    XCTAssertTrue(page.contains("This page requires identification, and none was received."))
  }
}
