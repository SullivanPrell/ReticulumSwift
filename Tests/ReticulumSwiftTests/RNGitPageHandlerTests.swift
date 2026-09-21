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
  private static let fixtureScript = """
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
    git add -A
    git commit -q -m "First commit"

    git branch other
    git tag light
    git tag -a annotated -m "An annotated tag"

    git config repository.description "A configured description"
    """

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
  /// read as "not found" — the same message either way.
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
  /// returning it when the file did not already exist, so only the next call — deduped or
  /// not — actually reads that count back.
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
}
