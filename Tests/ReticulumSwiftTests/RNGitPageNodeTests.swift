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

/// The Nomad Network pages a node serves, as Python RNS 1.5.4's `NomadNetworkNode` brings them up.
///
/// The settings, the destination, the handlers and the announce data were recorded from the
/// reference's own `__init__`, run with `RNS.Destination` replaced by a stand-in that notes what it
/// was asked for. The fields were read by the reference's own expressions.
final class RNGitPageNodeTests: XCTestCase {

  /// A `git` that answers every call, having printed nothing.
  private struct Runner: RNGitCommandRunner {
    func run(_ executable: String, arguments: [String], in directory: String?)
      -> RNGitCommandOutput?
    {
      RNGitCommandOutput(status: 0, standardOutput: "", standardError: "")
    }
  }

  /// The identity the reference's destination was recorded under: the private key 0, 1, … 63.
  private static let recordedIdentityKey = Data(0..<64)

  /// A node brought up in a directory of its own out of `configuration`.
  private func makeOwner(
    configuration: String = "", identityKey: Data? = nil,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) throws -> RNGitNode {
    let directory = NSTemporaryDirectory() + "/rngit-page-node-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(atPath: directory) }
    try configuration.write(
      toFile: directory + "/" + RNGitNodeEnvironment.configurationFileName, atomically: true,
      encoding: .utf8)
    if let identityKey {
      let written = try Identity(privateKeyBytes: identityKey).toFile(
        URL(fileURLWithPath: directory + "/" + RNGitNodeEnvironment.identityFileName))
      XCTAssertTrue(written)
    }
    return try RNGitNode(configDirectory: directory, runner: Runner(), clock: clock)
  }

  /// A link that has been opened but has come no further.
  private func makeLink() throws -> Link {
    let transport = Transport()
    transports.append(transport)
    let destination = try Destination(
      identity: Identity(), direction: .out, kind: .single, appName: "test",
      aspects: ["links"])
    return try Link.initiate(destination: destination, transport: transport)
  }

  /// The stacks the links were opened on, held for as long as the test runs.
  private var transports: [Transport] = []

  // MARK: - Settings

  /// Each `[pages]` section brings the pages up as the reference's did, or stops them over the
  /// key the reference raised on.
  func testTheSettingsMatchTheReference() throws {
    let recorded: [(String, Result<(nerdFonts: Bool, conversion: Bool), RNGitSettingsError>)] = [
      ("", .success((true, true))),
      ("[pages]\n", .success((true, true))),
      ("[pages]\nunicode_icons = yes\n", .success((false, true))),
      ("[pages]\nunicode_icons = True\n", .success((false, true))),
      ("[pages]\nunicode_icons = on\n", .success((false, true))),
      ("[pages]\nunicode_icons = 1\n", .success((false, true))),
      ("[pages]\nunicode_icons = no\n", .success((true, true))),
      ("[pages]\nunicode_icons = off\n", .success((true, true))),
      ("[pages]\nunicode_icons = maybe\n", .failure(.notABoolean(key: "unicode_icons"))),
      ("[pages]\nunicode_icons = \n", .failure(.notABoolean(key: "unicode_icons"))),
      ("[pages]\nmedia_conversion = no\n", .success((true, false))),
      ("[pages]\nmedia_conversion = false\n", .success((true, false))),
      ("[pages]\nmedia_conversion = yes\n", .success((true, true))),
      ("[pages]\nmedia_conversion = 0\n", .success((true, false))),
      ("[pages]\nmedia_conversion = maybe\n", .failure(.notABoolean(key: "media_conversion"))),
      (
        "[pages]\nserve_nomadnet = yes\nunicode_icons = yes\nmedia_conversion = no\n",
        .success((false, false))
      ),
      (
        "[pages]\nunicode_icons = maybe\nmedia_conversion = no\n",
        .failure(.notABoolean(key: "unicode_icons"))
      ),
      ("[rngit]\nunicode_icons = yes\nmedia_conversion = no\n", .success((true, true))),
      ("[pages]\nunicode_icons = yes, no\n", .failure(.notABoolean(key: "unicode_icons"))),
    ]
    for (text, expected) in recorded {
      let configuration = try RNGitConfigFile.parse(text)
      switch expected {
      case .success(let settings):
        let read = try RNGitPageNodeSettings(configuration: configuration)
        XCTAssertEqual(read.useNerdFonts, settings.nerdFonts, text)
        XCTAssertEqual(read.mediaConversion, settings.conversion, text)
      case .failure(let error):
        XCTAssertThrowsError(try RNGitPageNodeSettings(configuration: configuration), text) {
          XCTAssertEqual($0 as? RNGitSettingsError, error, text)
        }
      }
    }
  }

  /// A value naming no boolean stops the pages and leaves the node that owns them standing, as
  /// the reference reads the section only once it brings the pages up.
  func testASettingNamingNoBooleanStopsThePagesAndNotTheNode() throws {
    let owner = try makeOwner(configuration: "[pages]\nunicode_icons = maybe\n")
    XCTAssertTrue(owner.ready)
    XCTAssertThrowsError(try RNGitPageNode(owner: owner, version: "1.5.4")) {
      XCTAssertEqual($0 as? RNGitSettingsError, .notABoolean(key: "unicode_icons"))
    }
  }

  // MARK: - Serving

  func testEveryPageIsRegisteredAsTheReferenceRegistersIt() throws {
    let pages = try RNGitPageNode(owner: makeOwner(), version: "1.5.4")

    // Recorded from the reference's own `register_request_handlers`, in the order it runs.
    let recorded = [
      "/page/index.mu", "/page/group.mu", "/page/repo.mu", "/page/tree.mu", "/page/blob.mu",
      "/page/commits.mu", "/page/commit.mu", "/page/refs.mu", "/page/stats.mu",
      "/page/releases.mu", "/page/release.mu", "/page/work.mu", "/page/work_doc.mu", "/media",
      "/file/artifact", "/file/download", "/file/workdoc",
    ]
    XCTAssertEqual(RNGitPageNode.servedPaths, recorded)
    XCTAssertEqual(pages.destination.requestHandlers.count, recorded.count)
    for path in recorded {
      guard let entry = pages.destination.requestHandlers[Hashes.truncatedHash(Data(path.utf8))]
      else { return XCTFail("no handler registered for " + path) }
      XCTAssertEqual(entry.path, path)
      XCTAssertEqual(entry.allow, .all, path)
      XCTAssertTrue(entry.allowedHashes.isEmpty, path)
      XCTAssertEqual(entry.autoCompress, path == "/media" ? .disabled : .enabled, path)
    }
  }

  func testTheDestinationIsTheOneTheReferenceServesOn() throws {
    let pages = try RNGitPageNode(
      owner: makeOwner(identityKey: Self.recordedIdentityKey), version: "1.5.4")
    XCTAssertEqual(pages.destination.hash, Data(pythonHex: "8e484af42dd1c865a87fb2d16a5d8e63"))
    XCTAssertEqual(pages.destination.direction, .in)
    XCTAssertEqual(pages.destination.kind, .single)
  }

  func testTheAnnounceCarriesTheNodeName() throws {
    let pages = try RNGitPageNode(
      owner: makeOwner(configuration: "[rngit]\nnode_name = A Node\n"), version: "1.5.4")
    XCTAssertEqual(pages.destination.effectiveAppData, Data(pythonHex: "41204e6f6465"))
  }

  func testATemplatesDirectoryIsMadeWhereNoneStands() throws {
    let owner = try makeOwner()
    let directory = owner.directory + "/templates"
    XCTAssertFalse(RNGitNodeEnvironment.isDirectory(directory))
    let pages = try RNGitPageNode(owner: owner, version: "1.5.4")
    XCTAssertTrue(RNGitNodeEnvironment.isDirectory(directory))
    XCTAssertEqual(pages.templates.directory, directory)
  }

  /// Each request is answered by a handler holding the owner's store and statistics, the page
  /// node's own settings and links, and the repositories destination a repository page links to.
  func testAHandlerAnswersWithThePageNodesSettingsAndTheOwnersRepositories() throws {
    let owner = try makeOwner(
      configuration:
        "[rngit]\nnode_name = A Node\n\n[pages]\nunicode_icons = yes\nmedia_conversion = no\n")
    let pages = try RNGitPageNode(owner: owner, version: "1.5.4")
    let link = try makeLink()
    pages.connected(link)

    let handler = pages.makeHandler()
    XCTAssertFalse(handler.useNerdFonts)
    XCTAssertFalse(handler.mediaConversion)
    XCTAssertEqual(handler.activeLinks, [link.linkID!])
    XCTAssertEqual(handler.destinationHash, try owner.makeDestination().hash)
    XCTAssertEqual(handler.templates.nodeName, "A Node")
    XCTAssertEqual(handler.templates.version, "1.5.4")
    XCTAssertTrue(handler.thanks === pages.thanks)
  }

  /// A page is sent as the bytes the handler rendered, and what the handler counted is written
  /// back into the owner.
  func testAPageIsAnsweredAndCountedIntoTheOwner() throws {
    let owner = try makeOwner(configuration: "[rngit]\nnode_name = A Node\nrecord_stats = yes\n")
    let pages = try RNGitPageNode(owner: owner, version: "1.5.4")

    guard
      case .value(.bytes(let page))? = pages.answer(
        "/page/index.mu", .nil, from: nil, on: Data(count: 16))
    else { return XCTFail("no page") }
    XCTAssertTrue(String(decoding: page, as: UTF8.self).hasPrefix("#!c=0\n> A Node\n"))
    XCTAssertEqual(owner.statistics.frontPageViews.values.reduce(0, +), 1)
  }

  /// A media request the handler refuses is answered with the `False` the reference returns.
  func testARefusedMediaRequestIsAnsweredWithFalse() throws {
    let pages = try RNGitPageNode(owner: makeOwner(), version: "1.5.4")
    guard case .value(let value)? = pages.answer("/media", .nil, from: nil, on: Data(count: 16))
    else { return XCTFail("no answer") }
    XCTAssertEqual(value, .bool(false))
  }

  func testAPathThePagesDoNotServeIsAnsweredWithNothing() throws {
    let pages = try RNGitPageNode(owner: makeOwner(), version: "1.5.4")
    XCTAssertNil(pages.answer("/page/nothing.mu", .nil, from: nil, on: Data(count: 16)))
  }

  // MARK: - Fields

  /// The page number, read as `serve_tree_page` and `serve_commits_page` read it.
  ///
  /// The reference's integer is exact, so a number past the range of `Int` stands for a page past
  /// the last.
  func testThePageNumberIsReadAsTheReferenceReadsIt() {
    let recorded: [(MsgPack.Value?, Int)] = [
      (.string("2"), 2),
      (.string("0"), 0),
      (.string("-3"), 0),
      (.string(" 4 "), 4),
      (.string("x"), 0),
      (.string(""), 0),
      (.string("1_000"), 1000),
      (.string("٣"), 3),
      (.string("2.5"), 0),
      (.int(2), 2),
      (.int(-2), 0),
      (.double(2.9), 2),
      (.double(-0.5), 0),
      (.bool(true), 1),
      (.bool(false), 0),
      (.nil, 0),
      (.array([]), 0),
      (.array([.int(1)]), 0),
      (.map([]), 0),
      (.string("99999999999999999999"), .max),
      (.string("-99999999999999999999"), 0),
      (nil, 0),
    ]
    for (value, page) in recorded {
      let request = MsgPack.Value.map(value.map { [(.string("var_page"), $0)] } ?? [])
      XCTAssertEqual(RNGitPageRequest(request).page, page, "\(String(describing: value))")
    }
  }

  /// A flag, read as `serve_repo_page` reads `var_thanks` and `serve_blob_page` reads `var_raw`.
  func testAFlagIsReadAsTheReferenceReadsIt() {
    let recorded: [(MsgPack.Value?, Bool)] = [
      (.string("y"), true),
      (.string(""), false),
      (.string(" "), true),
      (.string("0"), true),
      (.int(0), false),
      (.int(1), true),
      (.double(0.0), false),
      (.double(0.5), true),
      (.bool(true), true),
      (.bool(false), false),
      (.nil, false),
      (.array([]), false),
      (.array([.int(0)]), true),
      (.map([]), false),
      (.bytes(Data()), false),
      (.bytes(Data([0])), true),
      (nil, false),
    ]
    for (value, flag) in recorded {
      let request = MsgPack.Value.map(value.map { [(.string("var_thanks"), $0)] } ?? [])
      XCTAssertEqual(
        RNGitPageRequest(request).flag("var_thanks"), flag, "\(String(describing: value))")
    }
  }

  /// A text field reads as its default where it is missing, or holds anything but a string, which
  /// no Nomad Network browser sends, or where the request carries no fields at all.
  func testATextFieldReadsAsItsDefaultWhereItHoldsNoString() {
    let fields = RNGitPageRequest(
      .map([(.string("var_g"), .string("proj")), (.string("var_r"), .int(5))]))
    XCTAssertEqual(fields.text("var_g"), "proj")
    XCTAssertEqual(fields.text("var_r"), "")
    XCTAssertEqual(fields.text("var_ref", default: "HEAD"), "HEAD")
    XCTAssertEqual(RNGitPageRequest(.nil).text("var_g"), "")
    XCTAssertEqual(RNGitPageRequest(.array([])).text("var_ref", default: "HEAD"), "HEAD")
  }

  // MARK: - Links

  /// A link is held from the moment it opens, where the repositories destination waits for the
  /// peer to identify.
  func testALinkIsHeldFromTheMomentItOpens() throws {
    let pages = try RNGitPageNode(owner: makeOwner(), version: "1.5.4")
    let link = try makeLink()
    pages.connected(link)
    XCTAssertEqual(pages.activeLinks, [link.linkID!])
  }

  func testALinkThatClosesIsLetGoWithItsDirectories() throws {
    let pages = try RNGitPageNode(owner: makeOwner(), version: "1.5.4")
    let link = try makeLink()
    pages.connected(link)
    let directory = try XCTUnwrap(pages.makeTemporaryDirectory(for: link.linkID!))

    link.onClosed?(link)
    XCTAssertTrue(pages.activeLinks.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory))
    XCTAssertTrue(pages.temporaries.held.isEmpty)
  }

  /// Links that are no longer up are swept on the first pass, and once a minute after.
  func testStaleLinksAreSweptOnceAMinute() throws {
    let moment = Date(timeIntervalSince1970: 100_000)
    let pages = try RNGitPageNode(
      owner: makeOwner(clock: { moment }), version: "1.5.4", clock: { moment })
    let first = try makeLink()
    pages.connected(first)
    let directory = try XCTUnwrap(pages.makeTemporaryDirectory(for: first.linkID!))

    let now = moment.timeIntervalSince1970
    pages.runDueJobs(at: now)
    XCTAssertTrue(pages.activeLinks.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory))

    let second = try makeLink()
    pages.connected(second)
    // `LINK_CLEAN_INTERVAL`, which the reference compares with a strict `>`.
    pages.runDueJobs(at: now + 60)
    XCTAssertEqual(pages.activeLinks, [second.linkID!])
    pages.runDueJobs(at: now + 61)
    XCTAssertTrue(pages.activeLinks.isEmpty)
  }

  // MARK: - The run

  /// The pages come up only where the configuration serves them, so a `[pages]` value naming no
  /// boolean stops only a node that does.
  func testThePagesComeUpOnlyWhereTheConfigurationServesThem() throws {
    XCTAssertNil(try RNGitRuntime.servedPages(of: makeOwner(), version: "1.5.4"))
    XCTAssertNil(
      try RNGitRuntime.servedPages(
        of: makeOwner(configuration: "[pages]\nunicode_icons = maybe\n"), version: "1.5.4"))

    let pages = try RNGitRuntime.servedPages(
      of: makeOwner(configuration: "[pages]\nserve_nomadnet = yes\nunicode_icons = yes\n"),
      version: "1.5.4")
    XCTAssertEqual(pages?.settings.useNerdFonts, false)
    XCTAssertThrowsError(
      try RNGitRuntime.servedPages(
        of: makeOwner(configuration: "[pages]\nserve_nomadnet = yes\nunicode_icons = maybe\n"),
        version: "1.5.4"))
  }

  // MARK: - Jobs

  /// The pages announce on the owner's interval, and never where it is zero.
  func testAnAnnounceIsDueOnceTheOwnersIntervalHasPassed() throws {
    let moment = Date(timeIntervalSince1970: 100_000)
    let silent = try RNGitPageNode(
      owner: makeOwner(clock: { moment }), version: "1.5.4", clock: { moment })
    silent.runDueJobs(at: moment.timeIntervalSince1970)
    XCTAssertEqual(silent.lastAnnounce, 0)

    let owner = try makeOwner(configuration: "[rngit]\nannounce_interval = 10\n", clock: { moment })
    let pages = try RNGitPageNode(owner: owner, version: "1.5.4", clock: { moment })
    pages.runDueJobs(at: moment.timeIntervalSince1970)
    XCTAssertEqual(pages.lastAnnounce, moment.timeIntervalSince1970)
  }
}
