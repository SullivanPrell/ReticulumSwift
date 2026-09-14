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
import XCTest

@testable import ReticulumSwift

/// What a node brings up, what it serves, and what it holds while it serves it.
final class RNGitNodeTests: XCTestCase {

  /// A runner answering the node's `git` calls the way its script names, recording every one.
  ///
  /// A call the script does not name succeeds having printed nothing, and a `bundle create`
  /// leaves a bundle where it said it would, so a handler reading one back finds it.
  private final class Runner: RNGitCommandRunner, @unchecked Sendable {

    /// Whether `git` answers at all.
    let available: Bool

    /// What `git --version` comes back with.
    let version: Int32

    /// What a call whose arguments open with each prefix printed, the first match answering.
    let script: [(prefix: [String], output: String)]

    /// The arguments of every call the node made, in the order it made them.
    var calls: [[String]] = []

    init(
      available: Bool = true, version: Int32 = 0,
      script: [(prefix: [String], output: String)] = []
    ) {
      self.available = available
      self.version = version
      self.script = script
    }

    func run(_ executable: String, arguments: [String], in directory: String?)
      -> RNGitCommandOutput?
    {
      calls.append(arguments)
      guard available else { return nil }
      if arguments == ["--version"] {
        return RNGitCommandOutput(
          status: version, standardOutput: "git version 2.39.5\n", standardError: "")
      }
      if arguments.starts(with: ["bundle", "create"]) {
        FileManager.default.createFile(atPath: arguments[3], contents: Data("bundle".utf8))
      }
      for entry in script where arguments.starts(with: entry.prefix) {
        return RNGitCommandOutput(status: 0, standardOutput: entry.output, standardError: "")
      }
      return RNGitCommandOutput(status: 0, standardOutput: "", standardError: "")
    }
  }

  /// What the script answers for a directory the node is to take as a bare repository.
  private static let bareRepository: [(prefix: [String], output: String)] = [
    (["rev-parse", "--git-dir"], "."),
    (["config", "--bool", "core.bare"], "true"),
  ]

  /// A directory that stands for the run of one test.
  private func makeDirectory() throws -> String {
    let path = NSTemporaryDirectory() + "/rngit-node-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
    return path
  }

  /// A node brought up in a directory of its own.
  private func makeNode(
    configuration: String? = nil, runner: Runner = Runner(),
    clock: @escaping @Sendable () -> Date = Date.init
  ) throws -> RNGitNode {
    let directory = try makeDirectory()
    if let configuration {
      try configuration.write(
        toFile: directory + "/" + RNGitNodeEnvironment.configurationFileName, atomically: true,
        encoding: .utf8)
    }
    return try RNGitNode(configDirectory: directory, runner: runner, clock: clock)
  }

  /// A link that has been opened but has come no further, which the node holds and lets go of.
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

  /// A node serving one group, `public`, at a directory of its own.
  ///
  /// Each name in `repositories` is a directory the scripted `git` answers for as a bare one, so
  /// the node registers it the way it registers a real repository.
  private func makeServingNode(
    repositories: [String] = [], granting: String, settings: String = "", runner: Runner
  ) throws -> (node: RNGitNode, group: String) {
    let group = try makeDirectory()
    for name in repositories {
      try FileManager.default.createDirectory(
        atPath: group + "/" + name, withIntermediateDirectories: true)
    }
    let node = try makeNode(
      configuration: """
        [rngit]
        \(settings)

        [repositories]
        public = \(group)

        [access]
        public = \(granting)
        """, runner: runner)
    return (node, group)
  }

  // MARK: - Bring-up

  func testANodeThatCannotRunGitIsNotBroughtUp() throws {
    let directory = try makeDirectory()
    XCTAssertThrowsError(
      try RNGitNode(configDirectory: directory, runner: Runner(available: false))
    ) { error in
      XCTAssertEqual(
        (error as? RNGitClientAbort)?.message,
        "The \"git\" command is not available. Aborting server startup.")
    }
  }

  func testAGitThatAnswersWithAFailureIsNoGitToRun() throws {
    let directory = try makeDirectory()
    XCTAssertThrowsError(
      try RNGitNode(configDirectory: directory, runner: Runner(version: 1))
    ) { error in
      XCTAssertEqual(
        (error as? RNGitClientAbort)?.message,
        "The \"git\" command is not available. Aborting server startup.")
    }
  }

  func testABringUpWritesTheConfigurationAndTheIdentityItFindsNone() throws {
    let directory = try makeDirectory()
    let node = try RNGitNode(configDirectory: directory, runner: Runner(available: true))

    XCTAssertTrue(node.ready)
    XCTAssertEqual(node.directory, directory)
    XCTAssertEqual(node.configurationPath, directory + "/config")
    XCTAssertEqual(node.identityPath, directory + "/repositories_identity")
    XCTAssertEqual(node.statisticsPath, directory + "/stats")
    XCTAssertEqual(node.logPath, directory + "/server_log")
    XCTAssertTrue(FileManager.default.fileExists(atPath: node.configurationPath))
    XCTAssertTrue(FileManager.default.fileExists(atPath: node.identityPath))
    XCTAssertTrue(FileManager.default.fileExists(atPath: node.statisticsPath))
  }

  func testABringUpReadsWhatTheShippedConfigurationSpellsOut() throws {
    let node = try makeNode()
    XCTAssertEqual(node.settings.announceInterval, 21600)
    XCTAssertEqual(node.settings.mirrorInterval, 86400)
    XCTAssertEqual(node.settings.nodeName, "Anonymous Git Node")
    XCTAssertFalse(node.settings.serveNomadNet)
  }

  func testTheIdentityIsReadBackOnTheNextBringUp() throws {
    let directory = try makeDirectory()
    let first = try RNGitNode(configDirectory: directory, runner: Runner(available: true))
    let second = try RNGitNode(configDirectory: directory, runner: Runner(available: true))
    XCTAssertEqual(first.identity.hash, second.identity.hash)
  }

  func testAConfigurationThatNamesAGroupLoadsIt() throws {
    let repositories = try makeDirectory()
    try FileManager.default.createDirectory(
      atPath: repositories + "/public", withIntermediateDirectories: true)
    let node = try makeNode(
      configuration: """
        [repositories]
        public = \(repositories)/public
        """)
    XCTAssertEqual(Array(node.store.groups.keys), ["public"])
    XCTAssertEqual(node.store.groups["public"]?.path, repositories + "/public")
  }

  func testAConfigurationThatCannotBeReadStopsTheBringUp() throws {
    let directory = try makeDirectory()
    try "[rngit\n".write(
      toFile: directory + "/config", atomically: true, encoding: .utf8)
    XCTAssertThrowsError(
      try RNGitNode(configDirectory: directory, runner: Runner(available: true))
    ) { error in
      XCTAssertEqual(
        (error as? RNGitClientAbort)?.message,
        "Could not parse the configuration at " + directory + "/config")
    }
  }

  // MARK: - Serving

  func testEveryRequestPathIsRegisteredAsTheReferenceRegistersIt() throws {
    let node = try makeNode()
    let destination = try node.makeDestination()
    node.attach(to: destination)

    // Recorded from the reference's own `register_request_handlers`, in the order it runs.
    let recorded = [
      "/git/list", "/git/fetch", "/git/push", "/git/create", "/mgmt/perms", "/git/fork",
      "/git/sync", "/git/mirror", "/git/delete", "/mgmt/release", "/mgmt/work",
    ]
    XCTAssertEqual(destination.requestHandlers.count, recorded.count)
    for path in recorded {
      let key = Hashes.truncatedHash(Data(path.utf8))
      guard let entry = destination.requestHandlers[key] else {
        return XCTFail("no handler registered for " + path)
      }
      XCTAssertEqual(entry.path, path)
      XCTAssertEqual(entry.allow, .all)
      XCTAssertTrue(entry.allowedHashes.isEmpty)
    }
  }

  func testTheDestinationIsTheOneTheIdentityNames() throws {
    let node = try makeNode()
    let destination = try node.makeDestination()
    XCTAssertEqual(
      destination.hash,
      Destination.hash(
        identity: node.identity, appName: RNGitDestination.appName,
        aspects: [RNGitDestination.aspect]))

    // The reference serves its repositories on an inbound single destination.
    XCTAssertEqual(destination.direction, .in)
    XCTAssertEqual(destination.kind, .single)
  }

  func testAPeerThatDidNotIdentifyIsRefusedOnEveryPath() throws {
    let node = try makeNode()
    for path in RNGitNode.servedPaths {
      guard case .response(let response)? = node.answer(path, .map([]), from: nil, on: nil) else {
        return XCTFail("no answer on " + path.rawValue)
      }
      XCTAssertEqual(response.code, .disallowed, path.rawValue)
      XCTAssertEqual(
        String(decoding: response.body, as: UTF8.self), "Not identified", path.rawValue)
    }
  }

  func testARequestNamingNoRepositoryIsRefused() throws {
    let node = try makeNode()
    let answer = node.answer(
      .list, .map([(.uint(0), .string("a/b/c/d"))]), from: Identity(), on: nil)
    guard case .response(let response)? = answer else { return XCTFail("no answer") }
    XCTAssertEqual(response.code, .notFound)
  }

  /// What each path answers a peer that identified over a link the node holds, but named no
  /// repository.
  ///
  /// The reference resolves the identity before it resolves the request, so a peer that has
  /// identified is never turned away for not having.
  func testAPeerThatIdentifiedIsRefusedOverTheRequestAndNotTheIdentity() throws {
    let node = try makeNode()
    let link = try makeLink()
    node.identified(link)

    // The permissions path reads the group a request names rather than the repository, so it is
    // the one path an empty request is turned away from over its shape.
    for path in RNGitNode.servedPaths {
      guard
        case .response(let response)? = node.answer(
          path, .map([]), from: Identity(), on: link.linkID)
      else { return XCTFail("no answer on " + path.rawValue) }
      XCTAssertEqual(response.code, .invalidRequest, path.rawValue)
      XCTAssertEqual(
        String(decoding: response.body, as: UTF8.self),
        path == .perms ? "Invalid request" : "No repository specified", path.rawValue)
    }
  }

  /// What the node's log calls a request on each path, as the reference's own log calls it.
  func testEachRequestIsLoggedTheWayTheReferenceLogsIt() {
    let recorded: [RNGitRequestPath: String] = [
      .list: "List", .fetch: "Fetch", .push: "Push", .create: "Create", .delete: "Delete",
      .fork: "Fork", .sync: "Upstream sync", .mirror: "Mirror", .release: "Release",
      .work: "Work", .perms: "Permissions",
    ]
    XCTAssertEqual(recorded.count, RNGitNode.servedPaths.count)
    for path in RNGitNode.servedPaths {
      XCTAssertEqual(RNGitNode.describing(path), recorded[path], path.rawValue)
    }
  }

  func testAnIdentityTheConfigurationBlocksIsRefusedWhatTheGroupGrants() throws {
    let blocked = Identity()
    let runner = Runner(script: Self.bareRepository)
    let held = try makeServingNode(
      repositories: ["project.git"], granting: "r:all",
      settings: "blocked_identities = " + blocked.hash.hexString, runner: runner)
    let request = MsgPack.Value.map([(.uint(0), .string("public/project.git"))])

    guard case .response(let refused)? = held.node.answer(.list, request, from: blocked, on: nil)
    else { return XCTFail("no answer") }
    XCTAssertEqual(refused.code, .notFound)

    guard case .response(let served)? = held.node.answer(.list, request, from: Identity(), on: nil)
    else { return XCTFail("no answer") }
    XCTAssertEqual(served.code, .ok)
  }

  func testARepositoryAPeerAsksForIsRegisteredOnTheNodeThatMadeIt() throws {
    let runner = Runner(script: Self.bareRepository)
    let held = try makeServingNode(granting: "c:all", runner: runner)

    guard
      case .response(let made)? = held.node.answer(
        .create, .map([(.uint(0), .string("public/project.git"))]), from: Identity(), on: nil)
    else { return XCTFail("no answer") }
    XCTAssertEqual(made.code, .ok)
    XCTAssertEqual(
      Array(held.node.store.groups["public"]?.repositories.keys ?? [:].keys), ["project.git"])
  }

  func testAFetchIsCountedWhereTheConfigurationAsksForCounts() throws {
    let runner = Runner(script: Self.bareRepository)
    let held = try makeServingNode(
      repositories: ["project.git"], granting: "r:all", settings: "record_stats = yes",
      runner: runner)
    let link = try makeLink()
    held.node.identified(link)

    let answer = held.node.answer(
      .fetch,
      .map([
        (.uint(0), .string("public/project.git")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]), from: Identity(), on: link.linkID)
    guard case .file(let bundle)? = answer,
      case .file(let url, let metadata)? = RNGitNode.generating(answer)
    else { return XCTFail("no bundle") }
    XCTAssertEqual(url.path, bundle.path)
    XCTAssertEqual(metadata, bundle.metadata.encoded)
    XCTAssertEqual(
      held.node.statistics.groups["public"]?.repositories["project.git"]?
        .fetch[RNGitStatsStore.day()], 1)
  }

  func testAForkIsRecordedAsAForkAndAMirrorAsAMirror() throws {
    for (path, kind) in [(RNGitRequestPath.fork, "fork"), (.mirror, "mirror")] {
      let runner = Runner(script: Self.bareRepository)
      let held = try makeServingNode(granting: "c:all", runner: runner)
      let link = try makeLink()
      held.node.identified(link)

      guard
        case .response(let cloned)? = held.node.answer(
          path,
          .map([
            (.uint(0), .string("public/project.git")),
            (.string("source"), .string("https://example.invalid/project.git")),
          ]), from: Identity(), on: link.linkID)
      else { return XCTFail("no answer on " + path.rawValue) }
      XCTAssertEqual(cloned.code, .ok, path.rawValue)
      XCTAssertTrue(
        runner.calls.contains(["config", "repository.rngit.type", kind]), path.rawValue)
      XCTAssertEqual(
        Array(held.node.store.groups["public"]?.repositories.keys ?? [:].keys), ["project.git"],
        path.rawValue)
    }
  }

  // MARK: - Links

  func testALinkTheNodeTookHoldOfIsHeldOnceThePeerIdentifies() throws {
    let node = try makeNode()
    let link = try makeLink()
    node.connected(link)
    XCTAssertTrue(node.activeLinks.isEmpty)

    link.onRemoteIdentified?(link, Identity())
    XCTAssertEqual(node.activeLinks, [link.linkID!])
  }

  func testADirectoryMadeForALinkTheNodeDoesNotHoldIsLeftWhereItIs() throws {
    let node = try makeNode()
    let link = try makeLink()
    guard let temporary = node.makeTemporaryDirectory(for: link.linkID!) else {
      return XCTFail("no temporary directory")
    }

    node.release(links: [link.linkID!])
    XCTAssertTrue(FileManager.default.fileExists(atPath: temporary))
  }

  func testAPeerThatIdentifiesIsHeldUntilItsLinkGoesStale() throws {
    let node = try makeNode()
    let link = try makeLink()
    node.identified(link)
    XCTAssertEqual(node.activeLinks, [link.linkID!])

    node.release(links: [link.linkID!])
    XCTAssertTrue(node.activeLinks.isEmpty)
  }

  func testATemporaryDirectoryIsRemovedWithTheLinkItWasMadeFor() throws {
    let node = try makeNode()
    let link = try makeLink()
    node.identified(link)
    guard let temporary = node.makeTemporaryDirectory(for: link.linkID!) else {
      return XCTFail("no temporary directory")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: temporary))

    node.release(links: [link.linkID!])
    XCTAssertFalse(FileManager.default.fileExists(atPath: temporary))
  }

  // MARK: - Jobs

  func testTheStatisticsAreWrittenWhereTheBringUpFoundThem() throws {
    let node = try makeNode()
    node.record { $0.recordPageView(on: "2026-09-14") }
    try node.persistStatistics()

    let read = RNGitStatsStore.load(from: node.statisticsPath)
    XCTAssertEqual(read.frontPageViews["2026-09-14"], 1)
  }

  func testEveryDueJobRunsAndIsRecordedAsHavingRun() throws {
    let moment = Date(timeIntervalSince1970: 100_000)
    let node = try makeNode(clock: { moment })
    let link = try makeLink()
    node.identified(link)
    XCTAssertEqual(node.schedule.announce, 0)

    let now = moment.timeIntervalSince1970 + 21_601
    node.runDueJobs(at: now)

    XCTAssertEqual(node.schedule.announce, moment.timeIntervalSince1970)
    XCTAssertEqual(node.schedule.statistics, now)
    XCTAssertEqual(node.schedule.syncCheck, now)
    XCTAssertEqual(node.schedule.linkClean, now)
    XCTAssertTrue(node.activeLinks.isEmpty)
  }

  func testARepositoryThatMirrorsNothingIsNotSynchronized() throws {
    let runner = Runner(script: Self.bareRepository)
    let held = try makeServingNode(
      repositories: ["project.git"], granting: "r:all", runner: runner)
    runner.calls = []

    held.node.syncMirrors(at: 100_000)
    XCTAssertEqual(runner.calls, [])
  }

  func testAMirrorIsLeftAloneUntilItsIntervalHasPassed() throws {
    let source = "https://example.invalid/project.git"
    let runner = Runner(
      script: Self.bareRepository + [
        (["config", "repository.rngit.type"], "mirror"),
        (["config", "repository.rngit.upstream.source"], source),
        (["config", "repository.rngit.upstream.sync"], "100000"),
      ])
    let held = try makeServingNode(
      repositories: ["project.git"], granting: "r:all", runner: runner)
    runner.calls = []

    held.node.syncMirrors(at: 100_001)
    XCTAssertEqual(runner.calls, [["config", "repository.rngit.upstream.sync"]])

    held.node.syncMirrors(at: 186_401)
    XCTAssertTrue(runner.calls.contains(["fetch", source, "+refs/*:refs/*"]))
  }

  func testAnAnnounceIsDueOnceTheConfiguredIntervalHasPassed() throws {
    let node = try makeNode()
    XCTAssertFalse(node.due(at: 21600).announce)
    XCTAssertTrue(node.due(at: 21601).announce)
  }
}

/// What one `rngit` run does with what its command line asked for.
final class RNGitRuntimeDispatchTests: XCTestCase {

  /// A node that lets every link up and answers no request, so a command reaches the node and
  /// gets no further.
  private final class RecordingTransport: RNGitClientTransport {

    /// The path, operation and timeout of every request the command sent.
    var asked: [String] = []

    func mediumPathTimeout() -> TimeInterval { 0 }
    func awaitPath(to destinationHash: Data, timeout: TimeInterval) -> Bool { true }
    func recallIdentity(for destinationHash: Data) -> Identity? { Identity() }
    func establishLink(to identity: Identity) -> Bool { true }

    func request(
      _ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval,
      progress: ((RNGitTransferProgress) -> Void)?
    ) -> RNGitClientResponse {
      asked.append(
        path.rawValue + " " + (Self.operation(in: fields) ?? "") + " " + String(Int(timeout)))
      return RNGitClientResponse(result: .none)
    }

    func teardown() {}

    /// The operation a request map names, or `nil` where it names none.
    private static func operation(in fields: MsgPack.Value) -> String? {
      guard case .map(let entries) = fields else { return nil }
      for (key, value) in entries where key.asString == "operation" {
        if let text = value.asString { return text }
        if case .bytes(let bytes) = value { return String(decoding: bytes, as: UTF8.self) }
      }
      return nil
    }
  }

  /// Everything the run wrote.
  private final class Recorder: RNGitClientOutput {
    var written = ""
    func write(_ text: String) { written += text }
  }

  /// An editor the user saved something in.
  private final class Editor: RNGitClientEditor {
    func editor() -> String { "edit" }
    func run(_ editor: String, over path: String) -> Int32 {
      (try? "r:all\n".write(toFile: path, atomically: true, encoding: .utf8)) == nil ? 1 : 0
    }
  }

  /// A user who says yes to whatever they are asked.
  private final class Yes: RNGitClientInput {
    func readLine() -> String? { "y\n" }
  }

  /// The repository every case names, so the destination is read before the command is reached.
  private static let remote = "rns://9710b86ba12c42d1d8f30f74fe509286/group/repository"

  /// What a command says where the node answered nothing, which is what this node does.
  private static let failedRequest = "Request failed or timed out"

  /// The group the operations that name one reach for.
  private static let groupRemote = "rns://9710b86ba12c42d1d8f30f74fe509286/group"

  /// The status the reference's client stops a run that gave up part way with.
  ///
  /// The value is the literal the reference exits with, not the one this port holds, so a port
  /// that holds the wrong one is caught rather than confirmed.
  private static let gaveUp: Int32 = 1

  /// What running `task` came to, against a node that answers nothing.
  private func run(_ task: RNGitTask) -> (status: Int32, asked: [String], aborted: String?) {
    let output = Recorder()
    let transport = RecordingTransport()
    let commands = RNGitClientCommands(
      identity: Identity(), transport: transport, output: output, input: Yes(), editor: Editor())
    do {
      let status = try RNGitRuntime.dispatch(task, through: commands, output: output)
      return (status, transport.asked, nil)
    } catch let abort as RNGitClientAbort {
      return (Self.gaveUp, transport.asked, abort.message)
    } catch {
      return (Self.gaveUp, transport.asked, "\(error)")
    }
  }

  /// One dispatch: what a subcommand and its operation reach for.
  private struct Case {
    let command: RNGitSubcommand
    let operation: String?
    /// The remote the operation is given, which is a group for the operations that name one.
    var remote: String = RNGitRuntimeDispatchTests.remote
    /// What the operation works on: a tag, a tag and a path, or the repository a copy goes to.
    var target: String = "1.0.0"
    /// The request the command sent, which names the node path and the operation it carries.
    let asked: [String]
    /// What the command gave up over, which is what an operation reaching no node says instead.
    let aborted: String
    let status: Int32
  }

  /// Every operation the reference's own dispatch takes, and what each one reaches here.
  ///
  /// The operations were recorded by running the reference's `program_setup` against a client
  /// that answers every method; the request, the abort and the status are what this dispatch
  /// comes to against a node that answers nothing.
  private static let cases: [Case] = [
    Case(
      command: .create, operation: "create", asked: ["/git/create  120"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .fork, operation: "fork", target: remote, asked: ["/git/fork  7200"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .mirror, operation: "fork", target: remote, asked: ["/git/mirror  7200"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .sync, operation: "sync", asked: ["/git/sync  7200"], aborted: failedRequest,
      status: gaveUp),
    Case(
      command: .release, operation: "list", asked: ["/mgmt/release list 120"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .release, operation: "view", asked: ["/mgmt/release view 300"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .release, operation: "fetch", target: "1.0.0:all",
      asked: ["/mgmt/release fetch 7200"], aborted: failedRequest, status: gaveUp),
    Case(
      command: .release, operation: "verify", asked: [],
      aborted: "Cannot perform offline verification without a local manifest", status: gaveUp),
    Case(
      command: .release, operation: "create", target: "1.0.0:./dist", asked: [],
      aborted: "Specified artifacts directory does not exist", status: gaveUp),
    Case(
      command: .release, operation: "delete", asked: ["/mgmt/release delete 120"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .release, operation: "latest", asked: ["/mgmt/release latest 120"],
      aborted: failedRequest, status: gaveUp),
    Case(command: .release, operation: "bogus", asked: [], aborted: "", status: 1),
    Case(
      command: .perms, operation: "gperms", remote: groupRemote,
      asked: ["/mgmt/perms gperms 120"], aborted: failedRequest, status: gaveUp),
    Case(
      command: .perms, operation: "rperms", asked: ["/mgmt/perms rperms 120"],
      aborted: failedRequest, status: gaveUp),
    Case(command: .perms, operation: "bogus", asked: [], aborted: "", status: 1),
    Case(
      command: .work, operation: "list", asked: ["/mgmt/work list 120"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .work, operation: "view", asked: ["/mgmt/work view 120"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .work, operation: "create", asked: ["/mgmt/work create 600"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .work, operation: "propose", asked: ["/mgmt/work propose 600"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .work, operation: "edit", asked: ["/mgmt/work view 600"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .work, operation: "delete", asked: ["/mgmt/work delete 120"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .work, operation: "update", asked: ["/mgmt/work comment 600"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .work, operation: "complete", asked: ["/mgmt/work complete 120"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .work, operation: "activate", asked: ["/mgmt/work activate 120"],
      aborted: failedRequest, status: gaveUp),
    Case(
      command: .work, operation: "perms", asked: ["/mgmt/work perms 120"],
      aborted: failedRequest, status: gaveUp),
    Case(command: .work, operation: "bogus", asked: [], aborted: "", status: 1),
  ]

  func testEveryOperationReachesTheCommandTheReferenceReachesFor() {
    for recorded in Self.cases {
      let name = recorded.command.rawValue + " " + (recorded.operation ?? "")
      let result = run(
        RNGitTask(
          command: recorded.command, operation: recorded.operation, remote: recorded.remote,
          source: Self.remote, target: recorded.target, documentIdentifier: 7, title: "T"))
      XCTAssertEqual(result.asked, recorded.asked, name)
      XCTAssertEqual(result.aborted ?? "", recorded.aborted, name)
      XCTAssertEqual(result.status, recorded.status, name)
    }
  }

  func testAnOperationTheSubcommandDoesNotTakeStopsTheRun() {
    let output = Recorder()
    XCTAssertEqual(RNGitRuntime.refuse(output), 1)
    XCTAssertEqual(output.written, "Invalid operation\n")
  }

  /// The `node` subcommand carries no task, so a dispatch reaching it stops the run.
  ///
  /// The reference stops a run over a command it cannot place with 1, which is the status this
  /// dispatch has no command to run comes to.
  func testTheNodeSubcommandIsNoTaskToDispatch() {
    let result = run(RNGitTask(command: .node))
    XCTAssertEqual(result.status, 1)
    XCTAssertEqual(result.asked, [])
  }
}

/// The editor a run hands the user, and what a run makes of its command line.
final class RNGitRuntimeTests: XCTestCase {

  /// A system holding the commands it was made with, and nothing else.
  private struct Runner: RNGitCommandRunner {
    let available: Set<String>
    func run(_ executable: String, arguments: [String], in directory: String?)
      -> RNGitCommandOutput?
    {
      guard executable == "which", let wanted = arguments.first else { return nil }
      return RNGitCommandOutput(
        status: available.contains(wanted) ? 0 : 1, standardOutput: "", standardError: "")
    }
  }

  /// Everything the run wrote.
  private final class Recorder: RNGitClientOutput {
    var written = ""
    func write(_ text: String) { written += text }
  }

  /// A user typing nothing.
  private final class Silent: RNGitClientInput {
    func readLine() -> String? { nil }
  }

  private func editor(_ environment: [String: String], _ available: Set<String>) -> String {
    RNGitProcessEditor(environment: environment, runner: Runner(available: available)).editor()
  }

  func testTheEnvironmentNamesTheEditorWhereItNamesOne() {
    XCTAssertEqual(editor(["EDITOR": "emacs"], ["nano", "vim", "vi"]), "emacs")
  }

  func testAnEnvironmentNamingNothingFallsBackToTheFirstEditorTheSystemHas() {
    XCTAssertEqual(editor([:], ["nano", "vim", "vi"]), "nano")
    XCTAssertEqual(editor([:], ["vim", "vi"]), "vim")
    XCTAssertEqual(editor([:], ["vi"]), "vi")
    XCTAssertEqual(editor(["EDITOR": ""], ["vim"]), "vim")
  }

  func testASystemWithNoneOfTheEditorsNamesNone() {
    XCTAssertEqual(editor([:], []), "")
    XCTAssertEqual(RNGitProcessEditor.fallbacks, ["nano", "vim", "vi"])
  }

  /// What running `arguments` came to, before anything is brought up.
  private func run(_ arguments: [String]) -> (status: Int32, out: String, error: String) {
    let out = Recorder()
    let error = Recorder()
    let status = RNGitRuntime.run(
      arguments: arguments, version: "1.2.3",
      streams: RNGitRuntime.Streams(
        standardOutput: out, standardError: error, standardInput: Silent()))
    return (status, out.written, error.written)
  }

  func testTheVersionIsTheOneTheRunWasGiven() {
    let result = run(["--version"])
    XCTAssertEqual(result.status, 0)
    XCTAssertEqual(result.out, "rngit 1.2.3\n")
    XCTAssertEqual(result.error, "")
  }

  func testACommandLineTheSubcommandCannotReadStopsTheRun() {
    let result = run(["create"])
    XCTAssertEqual(result.status, 2)
    XCTAssertEqual(result.out, "")
    XCTAssertTrue(result.error.contains("the following arguments are required"), result.error)
  }

  func testAHelpRequestIsAnsweredWhereTheRunStops() {
    let result = run(["node", "--help"])
    XCTAssertEqual(result.status, 0)
    XCTAssertTrue(result.out.contains("usage: rngit"), result.out)
    XCTAssertEqual(result.error, "")
  }

  func testPrintingWhatTheNodeIsBringsNoStackUp() throws {
    let directory = NSTemporaryDirectory() + "/rngit-identity-" + UUID().uuidString
    defer { try? FileManager.default.removeItem(atPath: directory) }

    let result = run([
      "node", "--print-identity", "--config", directory, "--rnsconfig", directory + "/rns",
    ])
    XCTAssertEqual(result.status, 0)

    let node = try RNGitNodeEnvironment.identity(
      at: directory + "/" + RNGitNodeEnvironment.identityFileName, in: directory)
    let client = try RNGitNodeEnvironment.identity(
      at: directory + "/" + RNGitClientEnvironment.identityFileName, in: directory)
    let lines = RNGitNodeEnvironment.identityLines(
      node: node, client: client, servingPages: false)
    XCTAssertEqual(result.out, lines.joined(separator: "\n") + "\n")
    XCTAssertEqual(lines.count, 3)
  }

  /// What a run that gave up part way stops with, and what it says before it does.
  ///
  /// The reference's own client prints what it gave up over and stops with 1, which is not the
  /// status its remote helper stops on.
  func testARunThatGaveUpPartWaySaysSoAndStops() {
    let said = Recorder()
    XCTAssertEqual(RNGitRuntime.gaveUp(over: RNGitClientAbort("Not found"), saying: said), 1)
    XCTAssertEqual(said.written, "Not found\n")

    let quiet = Recorder()
    XCTAssertEqual(RNGitRuntime.gaveUp(over: RNGitClientFailure(), saying: quiet), 1)
    XCTAssertEqual(quiet.written, "")
  }

  /// A client configuration that will not parse stops the run where the reference panics over
  /// one, which is 255.
  func testAClientConfigurationThatWillNotParseStopsTheRun() {
    XCTAssertEqual(RNGitRuntime.unreadableConfiguration(at: "/nowhere"), 255)
  }

  /// A node whose configuration will not parse never says what it is.
  ///
  /// The reference stops a run whose node did not come up with 255, which is what a node that
  /// cannot be read far enough to say what it is comes to here.
  func testANodeThatWillNotComeUpStopsTheRunWhereTheReferenceStopsIt() throws {
    let directory = NSTemporaryDirectory() + "/rngit-identity-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    try "[rngit\n".write(
      toFile: directory + "/" + RNGitNodeEnvironment.configurationFileName, atomically: true,
      encoding: .utf8)

    let result = run([
      "node", "--print-identity", "--config", directory, "--rnsconfig", directory + "/rns",
    ])
    XCTAssertEqual(result.status, 255)
    XCTAssertEqual(result.out, "")
  }
}
