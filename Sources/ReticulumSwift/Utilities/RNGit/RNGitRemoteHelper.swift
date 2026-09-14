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

/// Why a remote helper could not read the URL git handed it.
public enum RNGitHelperURLError: Error, Equatable, Sendable {

  /// The URL does not open with the protocol specifier.
  case scheme

  /// The URL names fewer things than a repository takes.
  case format

  /// What the helper says before it gives up.
  public var message: String {
    switch self {
    case .scheme: return "Invalid URL scheme. Must be rns://"
    case .format: return "Invalid URL format. Use rns://<hash>/<group>/<repo>"
    }
  }
}

/// What the URL git hands a remote helper names.
///
/// The protocol specifier is matched as it is written, and only the first two separators behind
/// it part anything, so a repository name carrying separators reaches the node whole.
public struct RNGitHelperURL: Equatable, Sendable {

  /// The destination the URL names, which may be an alias.
  public let destination: String

  /// The group the repository stands under.
  public let group: String

  /// The repository under the group.
  public let repository: String

  /// Creates a reading naming `destination`, `group` and `repository`.
  public init(destination: String, group: String, repository: String) {
    self.destination = destination
    self.group = group
    self.repository = repository
  }

  /// The `group/repository` path every request names.
  public var repositoryPath: String { group + "/" + repository }

  /// What `url` names.
  public static func reading(_ url: String) throws -> RNGitHelperURL {
    guard url.hasPrefix(RNGitRemoteURL.protocolSpecifier) else { throw RNGitHelperURLError.scheme }
    let parts = String(url.dropFirst(RNGitRemoteURL.protocolSpecifier.count))
      .pythonParted(on: "/", limit: 2)
    guard parts.count == 3 else { throw RNGitHelperURLError.format }
    return RNGitHelperURL(destination: parts[0], group: parts[1], repository: parts[2])
  }
}

/// A ref a node listed, and the commit it stands at.
public struct RNGitRemoteReference: Equatable, Sendable {

  /// What the node calls the ref.
  public let name: String

  /// The commit it stands at.
  public let sha: String

  /// Creates a ref named `name` standing at `sha`.
  public init(name: String, sha: String) {
    self.name = name
    self.sha = sha
  }
}

/// Words a command does not carry.
///
/// Python RNS 1.5.4 takes these words without counting them, so this is what its own reading
/// raises. The helper stops on the line the same way.
struct RNGitMissingWord: Error, CustomStringConvertible {
  var description: String { "list index out of range" }
}

/// A refspec naming one ref where it must name two.
struct RNGitUnpairedRefspec: Error, CustomStringConvertible {
  var description: String { "not enough values to unpack (expected 2, got 1)" }
}

/// A remote helper, which carries git's remote protocol over a link to a node.
///
/// Git runs the helper inside a repository and speaks its own line protocol over the helper's
/// input and output; everything the helper says for itself goes to its error output instead. The
/// link closes however the helper stops.
public struct RNGitRemoteHelper {

  /// What the helper says before it gives up, behind what it was doing.
  public static let failurePrefix = "git-remote-rns failed: "

  /// What the helper says where it is given no reason at all.
  public static let unknownReason = "Unknown reason"

  /// How many refs one fetch request asks for, where the configuration asks for no other number.
  public static let refBatchSize = 25

  /// How long the helper waits for a path, where the stack asks for no longer.
  public static let pathTimeout: TimeInterval = 15

  /// How long the helper waits out one request.
  public static let requestTimeout: TimeInterval = 7200

  /// How long the helper waits between transfer reports.
  static let reportInterval: TimeInterval = 1

  /// The destination the remote URL names.
  public var destination: String

  /// The `group/repository` path every request names.
  public var repositoryPath: String

  /// The destination hash each alias names.
  public var aliases: [String: String]

  /// How many refs one fetch request asks for.
  public var refBatchSize: Int

  /// How long the helper waits for a path, where the stack asks for no longer.
  public var pathTimeout: TimeInterval

  /// Where `git` runs, which is where git ran the helper.
  public var workingDirectory: String

  /// What the helper takes the time to be.
  public var now: () -> Date

  /// Whether git asked to be shown how transfers are going.
  public private(set) var progressEnabled = false

  /// The commit each ref the node listed stands at, in the order it listed them.
  public private(set) var remoteReferences: [RNGitRemoteReference] = []

  let transport: RNGitClientTransport
  let stdout: RNGitClientOutput
  let stderr: RNGitClientOutput
  let input: RNGitClientInput
  let runner: RNGitCommandRunner?

  /// Creates a helper for the repository `url` names, running over `transport`.
  ///
  /// A helper with no `runner` has no `git` to ask, which every step reads as a `git` that failed.
  public init(
    url: RNGitHelperURL, aliases: [String: String] = [:],
    refBatchSize: Int = RNGitRemoteHelper.refBatchSize,
    pathTimeout: TimeInterval = RNGitRemoteHelper.pathTimeout, workingDirectory: String = ".",
    now: @escaping () -> Date = Date.init, transport: RNGitClientTransport,
    stdout: RNGitClientOutput, stderr: RNGitClientOutput, input: RNGitClientInput,
    runner: RNGitCommandRunner? = nil
  ) {
    self.destination = url.destination
    self.repositoryPath = url.repositoryPath
    self.aliases = aliases
    self.refBatchSize = refBatchSize
    self.pathTimeout = pathTimeout
    self.workingDirectory = workingDirectory
    self.now = now
    self.transport = transport
    self.stdout = stdout
    self.stderr = stderr
    self.input = input
    self.runner = runner
  }

  /// Runs the helper until git stops sending it commands.
  public mutating func run() throws {
    var linked = false
    do {
      try reading(opened: { linked = true })
    } catch let abort as RNGitClientAbort {
      if linked { transport.teardown() }
      throw abort
    }
    if linked { transport.teardown() }
  }

  /// Answers git until it stops asking.
  private mutating func reading(opened: () -> Void) throws {
    try connect(opened: opened)

    var fetchQueue: [Wanted] = []
    var pushQueue: [Sending] = []

    while let read = input.readLine() {
      let line = read.pythonStripped
      if line == "capabilities" {
        stdout.write("list\nfetch\npush\noption\n\n")
      } else if line == "list" {
        try list(forPush: false)
      } else if line.hasPrefix("list ") {
        try list(forPush: true)
      } else if line.hasPrefix("option") {
        option(line)
      } else if line.hasPrefix("fetch") {
        let parts = line.pythonSplit()
        guard parts.count > 2 else { throw RNGitMissingWord() }
        let wanted = Wanted(sha: parts[1], ref: parts[2])
        if !fetchQueue.contains(where: { $0 == wanted }) { fetchQueue.append(wanted) }
        pushQueue = []
      } else if line.hasPrefix("push") {
        let parts = line.pythonSplit()
        guard parts.count > 1 else { throw RNGitMissingWord() }
        let refspec = parts[1].pythonParted(on: ":", limit: 1)
        guard refspec.count == 2 else { throw RNGitUnpairedRefspec() }
        pushQueue.append(Sending(local: refspec[0], remote: refspec[1]))
        fetchQueue = []
      } else if line.isEmpty {
        try fetch(fetchQueue)
        try push(pushQueue)
        fetchQueue = []
        pushQueue = []
        stdout.write("\n")
      } else {
        throw RNGitClientAbort("Unknown Git command: " + line)
      }
    }
  }

  /// `value` as git reads a quoted string.
  ///
  /// Everything outside printable ASCII is written as the hexadecimal of its scalar, which takes
  /// more than the two digits it is padded to wherever the scalar does.
  public static func escapeForStdout(_ value: String) -> String {
    var escaped = "\""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\\": escaped += "\\\\"
      case "\"": escaped += "\\\""
      case "\n": escaped += "\\n"
      case "\t": escaped += "\\t"
      case "\r": escaped += "\\r"
      default:
        guard scalar.value < 32 || scalar.value > 126 else {
          escaped.unicodeScalars.append(scalar)
          continue
        }
        var digits = String(scalar.value, radix: 16)
        if digits.count < 2 { digits = String(repeating: "0", count: 2 - digits.count) + digits }
        escaped += "\\x" + digits
      }
    }
    return escaped + "\""
  }

  /// A ref git asked for, and the commit it asked for it at.
  struct Wanted: Equatable {
    let sha: String
    let ref: String
  }

  /// A ref git asked to send, and where it goes on the node.
  struct Sending: Equatable {
    let local: String
    let remote: String
  }

  /// Opens a link to the destination the remote URL names.
  ///
  /// `opened` runs once the link exists, which is before it is known to have come up: a link
  /// that closes on the way up is still a link the helper has to close.
  private func connect(opened: () -> Void) throws {
    let named = RNGitClientSettings.resolving(destination, aliases: aliases)
    let hash: Data
    switch Data.reading(pythonHex: named) {
    case .bytes(let read): hash = read
    case .stopped(let position):
      throw RNGitClientAbort(
        "Invalid destination hash: non-hexadecimal number found in fromhex() arg at position "
          + String(position))
    }

    stderr.write("Requesting path...")
    guard transport.awaitPath(to: hash, timeout: max(pathTimeout, transport.mediumPathTimeout()))
    else {
      stderr.write("\n")
      throw RNGitClientAbort("Could not resolve path to " + RNSUtilities.prettyhexrep(hash))
    }
    stderr.write("\rPath resolved     ")

    guard let identity = transport.recallIdentity(for: hash) else {
      throw RNGitClientAbort("Could not recall remote identity. Is the server announcing?")
    }

    stderr.write("\rEstablishing link...")
    opened()
    guard transport.establishLink(to: identity) else {
      throw RNGitClientAbort("Failed to establish link")
    }
    stderr.write("\rLink established with remote\n")
  }

  /// Asks the node for the refs it holds, and writes them to git.
  private mutating func list(forPush: Bool) throws {
    let answer = try requesting(
      .list,
      .map([
        (.uint(UInt64(RNGitRequestKey.repository)), .string(repositoryPath)),
        (.string("for_push"), .bool(forPush)),
      ]))

    guard case .bytes(let response) = answer.result, !response.isEmpty else {
      throw RNGitClientAbort("Invalid list response from server")
    }
    let payload = Data(response.dropFirst())
    guard response[response.startIndex] == 0 else {
      throw RNGitClientAbort("Server refused list: " + payload.utf8IgnoringInvalid)
    }
    guard let text = String(data: payload, encoding: .utf8) else { throw RNGitUnreadableAnswer() }

    remoteReferences = []
    for line in text.components(separatedBy: "\n") {
      let listed = line.pythonStripped
      guard !listed.isEmpty else { continue }
      let parts = listed.pythonParted(on: " ", limit: 1)
      guard parts.count == 2, parts[1] != "HEAD" else { continue }
      record(parts[1], at: parts[0])
    }

    stdout.write(text)
    stdout.write("\n")
  }

  /// Takes the option `line` names, where the helper carries it.
  private mutating func option(_ line: String) {
    let parts = line.pythonSplit(limit: 2)
    let name = parts.count > 1 ? parts[1] : ""
    let value = parts.count > 2 ? parts[2] : ""
    guard name == "progress" else {
      stdout.write("unsupported\n")
      return
    }
    progressEnabled = ["true", "1", "yes"].contains(value.lowercased())
    stdout.write("ok\n")
  }

  /// Records that `name` stands at `sha`, keeping the place it first took.
  private mutating func record(_ name: String, at sha: String) {
    let reference = RNGitRemoteReference(name: name, sha: sha)
    if let at = remoteReferences.firstIndex(where: { $0.name == name }) {
      remoteReferences[at] = reference
    } else {
      remoteReferences.append(reference)
    }
  }

  /// What `path` answered, once the helper has waited out the request.
  func requesting(_ path: RNGitRequestPath, _ fields: MsgPack.Value) throws -> RNGitClientResponse {
    var reporting = RNGitTransferReporting(
      label: "", indent: "", interval: Self.reportInterval)
    let answer = transport.request(
      path, fields, timeout: Self.requestTimeout,
      progress: progressEnabled
        ? { reporting.report($0, at: self.now().timeIntervalSince1970, to: self.stderr) } : nil)
    if case .none = answer.result { throw RNGitClientAbort(RNGitClientCommands.noResult) }
    return answer
  }

  /// What `git` answered, run with `arguments` where git ran the helper.
  ///
  /// A `git` that cannot be run answers as one that failed, carrying nothing.
  func ran(_ arguments: [String]) -> RNGitCommandOutput {
    runner?.run("git", arguments: arguments, in: workingDirectory)
      ?? RNGitCommandOutput(status: 1, standardOutput: "", standardError: "")
  }

  /// What `git` answered, run with `arguments` where git ran the helper.
  func ran(_ arguments: String...) -> RNGitCommandOutput { ran(arguments) }

  /// The field naming the repository every request carries.
  var repositoryField: (MsgPack.Value, MsgPack.Value) {
    (.uint(UInt64(RNGitRequestKey.repository)), .string(repositoryPath))
  }
}

extension String {

  /// This string parted at `separator`, at most `limit` times.
  ///
  /// A separator standing next to another parts an empty field between them, and everything
  /// behind the last part is one field however many separators it carries.
  func pythonParted(on separator: Character, limit: Int) -> [String] {
    var parts: [String] = []
    var remainder = self[...]
    while parts.count < limit, let at = remainder.firstIndex(of: separator) {
      parts.append(String(remainder[remainder.startIndex..<at]))
      remainder = remainder[remainder.index(after: at)...]
    }
    parts.append(String(remainder))
    return parts
  }
}
