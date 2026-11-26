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

/// A repository node, from what it reads at startup to what it answers a peer with.
///
/// The node holds the one store, the one set of statistics and the one set of temporary
/// directories that every handler reads and writes, so a handler is handed them for the length of
/// a request and what it changed is read back out of it before the answer goes out.
public final class RNGitNode {

  /// What a node that cannot run `git` says before it stops.
  public static let noGit = "The \"git\" command is not available. Aborting server startup."

  /// The status a run whose node did not come up exits with.
  public static let notReadyStatus: Int32 = 255

  /// Where the node keeps its configuration, its identity and its statistics.
  public let directory: String

  /// The identity the node serves its repositories as.
  public let identity: Identity

  /// What the configuration spells out.
  public private(set) var settings: RNGitNodeSettings

  /// The configuration as it was read, which the pages read their own section of.
  public let configuration: RNGitConfigSection

  /// Guards the state requests, link callbacks and the jobs loop share.
  ///
  /// Nothing calls into a link, a subprocess or a callback while holding it.
  private let lock = NSLock()

  /// Serializes the requests that change the store, so none assigns a stale copy back.
  ///
  /// Held across their `git` calls, so it blocks only other store writers.
  private let storeWriters = NSLock()

  private var heldStore: RNGitRepositoryStore
  private var heldStatistics: RNGitStatistics
  private var heldLinks: [Data: Link] = [:]
  private var heldTemporaries: RNGitTemporaryDirectories
  private var heldSchedule: RNGitNodeRuntime.Schedule

  /// The groups the node serves, and what they grant.
  public var store: RNGitRepositoryStore { lock.withLock { heldStore } }

  /// What the node has counted.
  public var statistics: RNGitStatistics { lock.withLock { heldStatistics } }

  /// Whether the bring-up got as far as serving.
  public private(set) var ready = false

  /// The links peers have identified over, by the identifier each carries.
  public var links: [Data: Link] { lock.withLock { heldLinks } }

  /// The identifiers of the links peers have identified over.
  public var activeLinks: Set<Data> { Set(links.keys) }

  /// The directories the node removes with the links they were made for.
  var temporaries: RNGitTemporaryDirectories { lock.withLock { heldTemporaries } }

  /// When each periodic job last ran.
  var schedule: RNGitNodeRuntime.Schedule { lock.withLock { heldSchedule } }

  /// The destination the node serves on, or `nil` before one is attached.
  public private(set) var destination: Destination?

  let runner: RNGitCommandRunner
  private let clock: @Sendable () -> Date

  /// Where the configuration is.
  public var configurationPath: String {
    directory + "/" + RNGitNodeEnvironment.configurationFileName
  }

  /// Where the identity is.
  public var identityPath: String {
    directory + "/" + RNGitNodeEnvironment.identityFileName
  }

  /// Where the statistics are.
  public var statisticsPath: String {
    directory + "/" + RNGitNodeEnvironment.statisticsFileName
  }

  /// Where the log goes.
  public var logPath: String { directory + "/" + RNGitNodeEnvironment.logFileName }

  /// Brings a node up out of what stands in `configDirectory`.
  ///
  /// A directory holding no configuration is given the shipped one, and one holding no identity is
  /// given a new one, so the first run of a node leaves a directory the next run reads.
  ///
  /// - Throws: ``RNGitClientAbort`` where `git` cannot be run, where the configuration cannot be
  ///   read, or where the identity can be neither read nor written.
  public init(
    configDirectory: String?, verbosity: Int = 0,
    home: String = DaemonBootstrap.homeDirectory().path,
    runner: RNGitCommandRunner = RNGitProcessRunner(),
    clock: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    guard Self.canRunGit(runner) else { throw RNGitClientAbort(Self.noGit) }

    self.runner = runner
    self.clock = clock
    self.directory = RNGitNodeEnvironment.directory(given: configDirectory, home: home)

    let configurationPath = self.directory + "/" + RNGitNodeEnvironment.configurationFileName
    let configuration: RNGitConfigSection
    do {
      configuration = try RNGitNodeEnvironment.configuration(
        at: configurationPath, in: self.directory)
    } catch {
      throw RNGitClientAbort("Could not parse the configuration at " + configurationPath)
    }

    self.configuration = configuration
    self.identity = try RNGitNodeEnvironment.identity(
      at: self.directory + "/" + RNGitNodeEnvironment.identityFileName, in: self.directory)
    self.settings = try RNGitNodeSettings(configuration: configuration, verbosity: verbosity)

    var store = RNGitRepositoryStore(
      runner: runner, identityAliases: settings.identityAliases,
      access: configuration.section("access"))
    try store.loadGroups(from: configuration)
    self.heldStore = store

    self.heldStatistics = RNGitStatsStore.load(
      from: self.directory + "/" + RNGitNodeEnvironment.statisticsFileName)
    self.heldTemporaries = RNGitTemporaryDirectories()

    let now = clock().timeIntervalSince1970
    self.heldSchedule = RNGitNodeRuntime.Schedule(
      announce: 0, statistics: now, syncCheck: now, linkClean: 0)
    self.ready = true
  }

  /// Whether `git` answers at all.
  static func canRunGit(_ runner: RNGitCommandRunner) -> Bool {
    runner.run("git", arguments: ["--version"], in: nil)?.status == 0
  }

  // MARK: - Serving

  /// The destination the node's repositories are reached at.
  public func makeDestination() throws -> Destination {
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: RNGitDestination.appName,
      aspects: [RNGitDestination.aspect])
    if let value = settings.stampValue, value != 0 { destination.setValue(value) }
    destination.setLinkCost(settings.linkCost)
    return destination
  }

  /// Puts the node's handlers on `destination`, and takes it as the one the node serves on.
  ///
  /// Every path is served to any peer, and each handler settles for itself what the peer that
  /// asked may do.
  public func attach(to destination: Destination) {
    self.destination = destination
    destination.setLinkEstablishedCallback { [weak self] link in
      self?.connected(link)
    }

    for path in Self.servedPaths {
      switch path {
      case .fetch:
        destination.registerResponseGenerator(path: path.rawValue, allow: .all) {
          [weak self] _, request, _, link, _ in
          guard let self else { return nil }
          return Self.generating(
            self.answer(path, request, from: link.remoteIdentity, on: link.linkID))
        }
      default:
        destination.registerNativeRequestHandler(path: path.rawValue, allow: .all) {
          [weak self] _, request, _, link, _ in
          guard let self,
            let answer = self.answer(path, request, from: link.remoteIdentity, on: link.linkID)
          else { return nil }
          guard case .response(let response) = answer else { return nil }
          return .bytes(response.encoded)
        }
      }
    }
  }

  /// The paths the node serves, in the order the reference registers them.
  static let servedPaths: [RNGitRequestPath] = [
    .list, .fetch, .push, .create, .perms, .fork, .sync, .mirror, .delete, .release, .work,
  ]

  /// `answer` as a response generator sends it.
  static func generating(_ answer: RNGitAnswer?) -> Destination.RequestResponse? {
    switch answer {
    case .none: return nil
    case .response(let response): return .value(.bytes(response.encoded))
    case .file(let file):
      return .file(URL(fileURLWithPath: file.path), metadata: file.metadata.encoded)
    }
  }

  /// What a peer identifying as `identityHash` gets back from `path`.
  ///
  /// The handler is built over a snapshot of the node's state. Its counts and directories are
  /// added back as changes, and a store change is made under ``storeWriters``.
  public func answer(
    _ path: RNGitRequestPath, _ request: MsgPack.Value, from identity: RNGitRemoteIdentity?,
    on link: Data?
  ) -> RNGitAnswer? {
    let identityHash = identity?.hash
    let line = RNGitNodeRuntime.requestLine(
      Self.describing(path) + " request from remote", from: identityHash, settings: settings)
    Reticulum.log(line.text, level: line.level)

    switch path {
    case .list:
      let handler = RNGitListHandler(access: access, runner: runner)
      return handler.handle(request, from: identityHash).map { .response($0) }

    case .fetch:
      var handler = RNGitFetchHandler(
        access: access, runner: runner, settings: settings, activeLinks: activeLinks,
        temporaries: RNGitTemporaryDirectories(root: temporaries.root))
      let answer = handler.handle(request, from: identityHash, on: link)
      absorb(handler.statistics, handler.temporaries)
      return answer

    case .push:
      var handler = RNGitPushHandler(access: access, runner: runner, settings: settings)
      let answer = handler.handle(request, from: identityHash)
      absorb(handler.statistics)
      return answer.map { .response($0) }

    case .create:
      storeWriters.lock()
      defer { storeWriters.unlock() }
      var handler = RNGitCreateHandler(
        store: store, runner: runner, blockedIdentities: settings.blockedIdentities)
      let answer = handler.handle(request, from: identityHash)
      lock.withLock { heldStore = handler.store }
      return answer.map { .response($0) }

    case .fork, .mirror:
      storeWriters.lock()
      defer { storeWriters.unlock() }
      var handler = RNGitCloneHandler(
        store: store, runner: runner, activeLinks: activeLinks,
        blockedIdentities: settings.blockedIdentities,
        temporaries: RNGitTemporaryDirectories(root: temporaries.root))
      let kind: RNGitCloneKind = path == .fork ? .fork : .mirror
      let answer = handler.handle(request, from: identityHash, on: link, as: kind)
      lock.withLock { heldStore = handler.store }
      absorb(RNGitStatistics(), handler.temporaries)
      return answer.map { .response($0) }

    case .sync:
      let handler = RNGitSyncHandler(access: access, runner: runner)
      return handler.handle(request, from: identityHash).map { .response($0) }

    case .delete:
      var handler = RNGitDeleteHandler(access: access, runner: runner, settings: settings)
      let answer = handler.handle(request, from: identityHash)
      absorb(handler.statistics)
      return answer.map { .response($0) }

    case .release:
      let handler = RNGitReleaseHandler(access: access, runner: runner)
      return handler.handle(request, from: identityHash)

    case .work:
      let handler = RNGitWorkHandler(access: access)
      return handler.handle(request, from: identity).map { .response($0) }

    case .perms:
      storeWriters.lock()
      defer { storeWriters.unlock() }
      var handler = RNGitPermissionsHandler(
        store: store, blockedIdentities: settings.blockedIdentities)
      let answer = handler.handle(request, from: identity)
      lock.withLock { heldStore = handler.store }
      return .response(answer)
    }
  }

  /// Adds what a handler counted from empty statistics, and the directories it made.
  private func absorb(
    _ counted: RNGitStatistics,
    _ made: RNGitTemporaryDirectories = RNGitTemporaryDirectories()
  ) {
    lock.withLock {
      heldStatistics.add(counted, since: RNGitStatistics())
      heldTemporaries.adopt(made)
    }
  }

  /// What the node's log calls a request on `path`.
  static func describing(_ path: RNGitRequestPath) -> String {
    switch path {
    case .list: return "List"
    case .fetch: return "Fetch"
    case .push: return "Push"
    case .create: return "Create"
    case .delete: return "Delete"
    case .fork: return "Fork"
    case .sync: return "Upstream sync"
    case .mirror: return "Mirror"
    case .release: return "Release"
    case .work: return "Work"
    case .perms: return "Permissions"
    }
  }

  /// What the store grants, as a resolver reads it.
  var access: RNGitAccessControl {
    RNGitAccessControl(
      groups: store.groups, blockedIdentities: settings.blockedIdentities,
      identityAliases: store.identityAliases)
  }

  // MARK: - Links

  /// Takes hold of a link a peer just opened.
  func connected(_ link: Link) {
    Reticulum.log("Peer connected", level: .debug)
    link.onRemoteIdentified = { [weak self] link, _ in
      self?.identified(link)
    }
    link.onClosed = { _ in Reticulum.log("Peer disconnected", level: .debug) }
  }

  /// Holds `link`, which a peer has identified over.
  func identified(_ link: Link) {
    guard let linkID = link.linkID else { return }
    lock.withLock { heldLinks[linkID] = link }
  }

  /// A directory held for the length of `link`.
  func makeTemporaryDirectory(for link: Data) -> String? {
    lock.withLock { heldTemporaries.make(for: link) }
  }

  /// Lets go of `stale`, removing whatever was held for each of them.
  func release(links stale: Set<Data>) {
    var cleaned = 0
    var removed: [String] = []
    lock.withLock {
      for link in stale where heldLinks.removeValue(forKey: link) != nil {
        cleaned += 1
        removed += heldTemporaries.release(link)
      }
    }
    for path in removed { Reticulum.log("Cleaned up " + path, level: .debug) }
    if cleaned > 0 { Reticulum.log("Cleaned \(cleaned) links", level: .debug) }
  }

  // MARK: - Jobs

  /// Reads the statistics, writes what `change` makes of them, and holds the result.
  func record(_ change: (inout RNGitStatistics) -> Void) {
    lock.withLock { change(&heldStatistics) }
  }

  /// Writes the statistics where the bring-up found them.
  public func persistStatistics() throws {
    try RNGitStatsStore.persist(statistics, to: statisticsPath)
  }

  /// Announces the destination the node serves on.
  public func announce() {
    Reticulum.log("Announcing repositories destination", level: .verbose)
    try? destination?.announce()
    let now = clock().timeIntervalSince1970
    lock.withLock { heldSchedule.announce = now }
  }

  /// Which jobs are due at `now`.
  func due(at now: TimeInterval) -> RNGitNodeRuntime.Jobs {
    RNGitNodeRuntime.due(at: now, schedule: schedule, settings: settings)
  }

  /// Runs whatever is due at `now`, and records that it ran.
  public func runDueJobs(at now: TimeInterval) {
    let jobs = due(at: now)
    if jobs.announce { announce() }
    if jobs.persistStatistics {
      try? persistStatistics()
      lock.withLock { heldSchedule.statistics = now }
    }
    if jobs.syncMirrors {
      syncMirrors(at: now)
      lock.withLock { heldSchedule.syncCheck = now }
    }
    if jobs.cleanLinks {
      release(links: staleLinks())
      lock.withLock { heldSchedule.linkClean = now }
    }
  }

  /// The links the node holds that are no longer active.
  func staleLinks() -> Set<Data> {
    RNGitNodeRuntime.stale(among: links.mapValues { $0.getStatus() })
  }

  /// Brings every mirror whose interval has passed up to its upstream.
  func syncMirrors(at now: TimeInterval) {
    for (groupName, group) in store.groups {
      for (repositoryName, repository) in group.repositories {
        guard let source = repository.mirror, !source.isEmpty else { continue }
        let synced = RNGitWorkingCopy.mirrorSynced(repository.path, runner: runner)
        guard RNGitNodeRuntime.mirrorDue(syncedAt: synced, at: now, settings: settings) else {
          continue
        }
        Reticulum.log("Syncing mirror \(groupName)/\(repositoryName)", level: .info)
        _ = RNGitWorkingCopy.syncMirror(
          repository.path, from: source, runner: runner,
          now: { Int(self.clock().timeIntervalSince1970) })
      }
    }
  }
}
