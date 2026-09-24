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

/// The `[pages]` settings a node reads once it serves its repositories as Nomad Network pages.
///
/// The reference reads them in `NomadNetworkNode.__init__` and nowhere else, so a value naming
/// no boolean stops a node that serves the pages and is never looked at by one that does not,
/// nor by `rngit node -p`.
public struct RNGitPageNodeSettings: Equatable, Sendable {

  /// Whether the pages draw the icons a Nerd Font carries.
  public var useNerdFonts = RNGitPage.useNerdFonts

  /// Whether an image a page shows is sent converted to WebP.
  public var mediaConversion = true

  /// Creates the settings with every default in place.
  public init() {}

  /// Creates the settings the `[pages]` section of `configuration` spells out.
  ///
  /// - Throws: ``RNGitSettingsError/notABoolean(key:)`` where `unicode_icons` or
  ///   `media_conversion` names neither true nor false, `unicode_icons` read first.
  public init(configuration: RNGitConfigSection) throws {
    guard let section = configuration.section("pages") else { return }
    if section.has("unicode_icons") {
      guard let unicode = section.bool("unicode_icons") else {
        throw RNGitSettingsError.notABoolean(key: "unicode_icons")
      }
      if unicode { useNerdFonts = false }
    }
    if section.has("media_conversion") {
      guard let conversion = section.bool("media_conversion") else {
        throw RNGitSettingsError.notABoolean(key: "media_conversion")
      }
      mediaConversion = conversion
    }
  }
}

/// The fields a page request carries, read as the reference's page handlers read them.
///
/// A request that is not a map carries no fields. The Nomad Network browser sends every `var_`
/// field as the `str` of its value (`Browser.py:407`), so a field holding anything but a
/// string reads as the field's default. The page number and the flags are the exceptions: the
/// reference reads the page number with `int`, which takes a number as readily as its text, and
/// a flag by whether Python reads its value as true.
struct RNGitPageRequest {

  private let fields: RNGitRequestFields?

  /// The fields `request` carries.
  init(_ request: MsgPack.Value) { fields = RNGitRequestFields(request) }

  /// The text `key` holds, or `fallback` where it holds none.
  func text(_ key: String, default fallback: String = "") -> String {
    fields?[key]?.asString ?? fallback
  }

  /// Whether `key` holds a value Python reads as true.
  func flag(_ key: String) -> Bool { fields?[key]?.pythonIsTruthy ?? false }

  /// The page `var_page` asks for, which is the first where `int` raises for it, and never
  /// before the first.
  ///
  /// Python's integer has no bounds, so text naming a page past the range of `Int` is read as
  /// the last page `Int` holds, which is as far past the last page as the reference's is.
  var page: Int {
    let value = fields?["var_page"] ?? .string("0")
    if case .string(let text) = value { return max(0, text.pythonIntegerClamped ?? 0) }
    return max(0, value.pythonInteger ?? 0)
  }
}

/// A node's repositories, served as Nomad Network pages on a destination of their own.
///
/// Mirrors `NomadNetworkNode`. The pages are read out of the node that owns them: each request
/// is answered by a handler built over the owner's store and statistics, and what the handler
/// counted is written back into the owner before the answer goes out. The links, their temporary
/// directories, and the thanks the pages count are the page node's own.
public final class RNGitPageNode {

  /// The application name the pages are served under.
  public static let appName = "nomadnetwork"

  /// The aspect the pages are served under.
  public static let aspect = "node"

  /// Seconds between sweeping links that are no longer up.
  public static let linkCleanInterval: TimeInterval = 60

  /// Every path the pages are served on, in the order the reference registers them.
  public static let servedPaths = [
    RNGitPage.Path.index, RNGitPage.Path.group, RNGitPage.Path.repository, RNGitPage.Path.tree,
    RNGitPage.Path.blob, RNGitPage.Path.commits, RNGitPage.Path.commit, RNGitPage.Path.refs,
    RNGitPage.Path.stats, RNGitPage.Path.releases, RNGitPage.Path.release, RNGitPage.Path.work,
    RNGitPage.Path.workDocument, RNGitPage.Path.media, RNGitPage.Path.artifact,
    RNGitPage.Path.download, RNGitPage.Path.workDocumentFile,
  ]

  /// The node whose repositories the pages show.
  public let owner: RNGitNode

  /// The `[pages]` settings the owner's configuration spells out.
  public let settings: RNGitPageNodeSettings

  /// The destination the pages are served on.
  public let destination: Destination

  /// The templates the pages are rendered into, read from the owner's `templates` directory.
  public let templates: RNGitPageTemplates

  /// How many times each repository and release has been thanked.
  public let thanks = RNGitPageThanks()

  /// Colors a page's readme and code blocks.
  let syntaxHighlighter: MicronSyntaxHighlighting = SyntaxHighlighter()

  /// Guards the links, their directories and the schedule, which the jobs and the requests
  /// reach from different threads.
  private let lock = NSLock()

  private var heldLinks: [Data: Link] = [:]
  private var heldTemporaries = RNGitTemporaryDirectories()
  private let clock: @Sendable () -> Date

  /// When the pages last announced, in seconds since the epoch.
  private(set) var lastAnnounce: TimeInterval = 0

  /// When the links were last swept, in seconds since the epoch.
  private(set) var lastLinkClean: TimeInterval = 0

  /// Brings the pages of `owner` up, reading the `[pages]` section of its configuration.
  ///
  /// A templates directory is made where none stands, and a failure to make one is logged
  /// rather than stopping the node, as the reference does.
  ///
  /// - Throws: ``RNGitSettingsError`` where the `[pages]` section names no boolean for a key
  ///   read as one, and whatever the destination throws.
  public init(
    owner: RNGitNode, version: String, clock: @escaping @Sendable () -> Date = Date.init
  ) throws {
    self.owner = owner
    self.clock = clock

    let directory = owner.directory + "/templates"
    if !RNGitNodeEnvironment.isDirectory(directory) {
      do {
        try FileManager.default.createDirectory(
          atPath: directory, withIntermediateDirectories: true)
      } catch {
        Reticulum.log(
          "Could not create templates directory \(directory): \(error)", level: .error)
      }
    }
    self.templates = RNGitPageTemplates(
      directory: directory, nodeName: owner.settings.nodeName, version: version,
      runner: owner.runner)
    self.settings = try RNGitPageNodeSettings(configuration: owner.configuration)

    self.destination = try Destination(
      identity: owner.identity, direction: .in, kind: .single, appName: Self.appName,
      aspects: [Self.aspect])
    let nodeName = owner.settings.nodeName
    destination.setDefaultAppData(provider: { Data(nodeName.utf8) })
    destination.setLinkEstablishedCallback { [weak self] link in self?.connected(link) }
    register()

    Reticulum.log(
      "Git Nomad Network Node listening on " + RNSUtilities.prettyhexrep(destination.hash),
      level: .notice)
  }

  /// The identifiers of the links the pages have open.
  public var activeLinks: Set<Data> { lock.withLock { Set(heldLinks.keys) } }

  /// The directories held for each open link.
  var temporaries: RNGitTemporaryDirectories { lock.withLock { heldTemporaries } }

  /// A directory held for the length of `link`.
  func makeTemporaryDirectory(for link: Data) -> String? {
    lock.withLock { heldTemporaries.make(for: link) }
  }

  // MARK: - Requests

  private func register() {
    for path in Self.servedPaths {
      destination.registerResponseGenerator(
        path: path, allow: .all,
        autoCompress: path == RNGitPage.Path.media ? .disabled : .enabled
      ) { [weak self] _, request, _, link, _ in
        guard let self, let linkID = link.linkID else { return nil }
        return self.answer(path, request, from: link.remoteIdentity, on: linkID)
      }
    }
  }

  /// What the page on `path` answers `request` with, asked over `link` by `identity`, or `nil`
  /// where the reference raises or answers nothing.
  public func answer(
    _ path: String, _ request: MsgPack.Value, from identity: Identity?, on link: Data
  ) -> Destination.RequestResponse? {
    lock.lock()
    defer { lock.unlock() }

    var handler = makeHandler()
    let answer = Self.serve(
      path, RNGitPageRequest(request), request, identity?.hash, link, &handler)
    heldTemporaries = handler.temporaries
    let counted = handler.statistics
    owner.record { $0 = counted }
    return answer
  }

  /// A handler over the owner's store and statistics, answering with the page node's settings,
  /// links and directories.
  func makeHandler() -> RNGitPageHandler {
    var handler = RNGitPageHandler(
      access: RNGitPageAccess(control: owner.access), runner: owner.runner,
      destinationHash: Destination.hash(
        identity: owner.identity, appName: RNGitDestination.appName,
        aspects: [RNGitDestination.aspect]),
      settings: owner.settings, statistics: owner.statistics, thanks: thanks,
      syntaxHighlighter: syntaxHighlighter, templates: templates)
    handler.activeLinks = Set(heldLinks.keys)
    handler.temporaries = heldTemporaries
    handler.useNerdFonts = settings.useNerdFonts
    handler.mediaConversion = settings.mediaConversion
    return handler
  }

  // swift-format-ignore: FunctionLength
  private static func serve(
    _ path: String, _ fields: RNGitPageRequest, _ request: MsgPack.Value, _ reader: Data?,
    _ link: Data, _ handler: inout RNGitPageHandler
  ) -> Destination.RequestResponse? {
    let group = fields.text("var_g")
    let repository = fields.text("var_r")
    let ref = fields.text("var_ref", default: "HEAD")

    switch path {
    case RNGitPage.Path.index:
      return page(handler.serveFrontPage(identityHash: reader))
    case RNGitPage.Path.group:
      return page(handler.serveGroupPage(identityHash: reader, groupName: group))
    case RNGitPage.Path.repository:
      return page(
        handler.serveRepoPage(
          identityHash: reader, groupName: group, repositoryName: repository, ref: ref,
          thanksClicked: fields.flag("var_thanks"), linkID: link))
    case RNGitPage.Path.tree:
      return page(
        handler.serveTreePage(
          identityHash: reader, groupName: group, repositoryName: repository, ref: ref,
          treePath: fields.text("var_path"), page: fields.page))
    case RNGitPage.Path.blob:
      return page(
        handler.serveBlobPage(
          identityHash: reader, groupName: group, repositoryName: repository, ref: ref,
          filePath: fields.text("var_path"), render: fields.flag("var_render"),
          raw: fields.flag("var_raw")))
    case RNGitPage.Path.commits:
      return page(
        handler.serveCommitsPage(
          identityHash: reader, groupName: group, repositoryName: repository, ref: ref,
          filePath: fields.text("var_path"), page: fields.page))
    case RNGitPage.Path.commit:
      return page(
        handler.serveCommitPage(
          identityHash: reader, groupName: group, repositoryName: repository, ref: ref,
          commitHash: fields.text("var_h")))
    case RNGitPage.Path.refs:
      return page(
        handler.serveRefsPage(
          identityHash: reader, groupName: group, repositoryName: repository,
          refType: fields.text("var_type")))
    case RNGitPage.Path.stats:
      return page(
        handler.serveStatsPage(identityHash: reader, groupName: group, repositoryName: repository))
    case RNGitPage.Path.releases:
      return page(
        handler.serveReleasesPage(
          identityHash: reader, groupName: group, repositoryName: repository))
    case RNGitPage.Path.release:
      return page(
        handler.serveReleasePage(
          identityHash: reader, groupName: group, repositoryName: repository,
          tag: fields.text("var_t"), thanksClicked: fields.flag("var_thanks"), linkID: link))
    case RNGitPage.Path.work:
      return page(
        handler.serveWorkPage(
          identityHash: reader, groupName: group, repositoryName: repository,
          scope: fields.text("var_scope", default: "active")))
    case RNGitPage.Path.workDocument:
      return page(
        handler.serveWorkDocumentPage(
          identityHash: reader, groupName: group, repositoryName: repository,
          documentID: fields.text("var_id"), scope: fields.text("var_scope", default: "all")))
    case RNGitPage.Path.media:
      return download(handler.serveMedia(identityHash: reader, request: request, link: link))
    case RNGitPage.Path.artifact:
      return download(
        handler.serveArtifact(
          identityHash: reader, groupName: group, repositoryName: repository,
          tag: fields.text("var_t"), artifact: fields.text("var_a")))
    case RNGitPage.Path.download:
      return download(
        handler.serveDownload(
          identityHash: reader, groupName: group, repositoryName: repository, ref: ref,
          path: fields.text("var_path"), link: link))
    case RNGitPage.Path.workDocumentFile:
      return download(
        handler.serveWorkDocumentDownload(
          identityHash: reader, groupName: group, repositoryName: repository,
          documentID: fields.text("var_id"), scope: fields.text("var_scope", default: "all")))
    default:
      return nil
    }
  }

  /// A rendered page as a response generator sends it.
  private static func page(_ rendered: Data?) -> Destination.RequestResponse? {
    rendered.map { .value(.bytes($0)) }
  }

  /// A file or a value as a response generator sends it.
  private static func download(_ answer: RNGitPageDownload?) -> Destination.RequestResponse? {
    switch answer {
    case .none: return nil
    case .value(let value): return .value(value)
    case .file(let file):
      return .file(URL(fileURLWithPath: file.path), metadata: file.metadata.encoded)
    }
  }

  // MARK: - Links

  /// Holds a link a reader just opened, until it closes or goes stale.
  func connected(_ link: Link) {
    Reticulum.log("Peer connected to \(destination)", level: .debug)
    guard let linkID = link.linkID else { return }
    lock.withLock { heldLinks[linkID] = link }
    link.onRemoteIdentified = { link, identity in
      Reticulum.log("Peer identified as \(identity) on \(link)", level: .debug)
    }
    link.onClosed = { [weak self] link in self?.disconnected(link) }
  }

  /// Lets go of a link a reader closed, and of what was held for it.
  func disconnected(_ link: Link) {
    Reticulum.log("Peer disconnected from \(destination)", level: .debug)
    guard let linkID = link.linkID else { return }
    let removed: [String] = lock.withLock {
      heldLinks.removeValue(forKey: linkID)
      return heldTemporaries.release(linkID)
    }
    for path in removed { Reticulum.log("Cleaned up " + path, level: .debug) }
  }

  /// Lets go of every held link that is no longer up, and of what was held for it.
  ///
  /// Each link's status is read outside the lock, so a link closing on another thread never
  /// waits on a sweep that waits on it.
  func cleanLinks() {
    let held = lock.withLock { heldLinks }
    let stale = RNGitNodeRuntime.stale(among: held.mapValues { $0.getStatus() })
    let removed: (links: Int, paths: [String]) = lock.withLock {
      var cleaned = 0
      var paths: [String] = []
      for linkID in stale where heldLinks.removeValue(forKey: linkID) != nil {
        cleaned += 1
        paths += heldTemporaries.release(linkID)
      }
      return (cleaned, paths)
    }
    for path in removed.paths { Reticulum.log("Cleaned up " + path, level: .debug) }
    if removed.links > 0 {
      Reticulum.log(
        "Cleaned \(removed.links) stale link" + (removed.links != 1 ? "s" : ""), level: .debug)
    }
  }

  // MARK: - Jobs

  /// Announces the destination the pages are served on.
  public func announce() {
    Reticulum.log("Announcing page node destination", level: .verbose)
    lock.withLock { lastAnnounce = clock().timeIntervalSince1970 }
    try? destination.announce()
  }

  /// Runs whatever is due at `now`: an announce once the owner's interval has passed, and a
  /// sweep of the links once a minute.
  public func runDueJobs(at now: TimeInterval) {
    let interval = TimeInterval(owner.settings.announceInterval)
    let (announceDue, cleanDue) = lock.withLock {
      (
        interval != 0 && now > lastAnnounce + interval,
        now > lastLinkClean + Self.linkCleanInterval
      )
    }
    if announceDue { announce() }
    if cleanDue {
      cleanLinks()
      lock.withLock { lastLinkClean = clock().timeIntervalSince1970 }
    }
  }
}
