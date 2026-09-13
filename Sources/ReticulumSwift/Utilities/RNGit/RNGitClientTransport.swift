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

/// What came back from a request a client sent.
public enum RNGitRequestResult: Equatable, Sendable {

  /// The bytes the node answered with.
  case bytes(Data)

  /// A file the node answered with, which lies at this path.
  case file(String)

  /// Nothing came back.
  case none
}

/// Where a client's bytes go.
public protocol RNGitClientOutput: AnyObject {

  /// Writes `text` as it stands, adding nothing to it.
  func write(_ text: String)
}

/// Where a client's answers come from.
public protocol RNGitClientInput: AnyObject {

  /// The next line the user typed, or `nil` where there is no more to read.
  func readLine() -> String?
}

/// What a client says before it gives up.
public struct RNGitClientAbort: Error, Equatable, Sendable {

  /// What the client says.
  public let message: String

  /// Creates an abort saying `message`.
  public init(_ message: String) { self.message = message }
}

/// What a client asks of the running stack.
public protocol RNGitClientTransport: AnyObject {

  /// How long a path may take to come up over the slowest interface a path is held on.
  func mediumPathTimeout() -> TimeInterval

  /// Whether a path to `destinationHash` came up inside `timeout`.
  func awaitPath(to destinationHash: Data, timeout: TimeInterval) -> Bool

  /// The identity the stack holds for `destinationHash`, or `nil` where it holds none.
  func recallIdentity(for destinationHash: Data) -> Identity?

  /// Opens a link to `identity` and identifies over it, answering whether it came up.
  func establishLink(to identity: Identity) -> Bool

  /// Sends a request to `path` carrying `fields`, answering what came back.
  func request(_ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval)
    -> RNGitRequestResult

  /// Closes the link.
  func teardown()
}

/// What a client made of the answer a node sent.
public enum RNGitClientAnswer: Equatable, Sendable {

  /// The node did as it was asked, and sent these bytes after the code.
  case done(Data)

  /// The node did not, and this is what the client says.
  case failed(String)
}

/// How a client reads the codes one request path answers with.
public struct RNGitResponseReading: Equatable, Sendable {

  /// What one code that is not ``RNGitResponseCode/ok`` comes to.
  public enum Rule: Equatable, Sendable {

    /// This text stands, whatever the node sent alongside the code.
    case text(String)

    /// What the node sent, behind `prefix`, or `fallback` where it sent nothing.
    case sent(prefix: String, fallback: String)
  }

  /// What the client says where what came back is not an answer it can read.
  public static let noAnswer = "No response from remote"

  /// What each code the reading names comes to.
  public var named: [RNGitResponseCode: Rule]

  /// What every other code comes to, whether the protocol names it or not.
  public var other: Rule

  /// Creates a reading that names `named` and reads everything else as `other`.
  public init(named: [RNGitResponseCode: Rule] = [:], other: Rule) {
    self.named = named
    self.other = other
  }

  /// What `result` came to.
  public func reading(_ result: RNGitRequestResult) -> RNGitClientAnswer {
    guard case .bytes(let response) = result, !response.isEmpty else {
      return .failed(Self.noAnswer)
    }
    let code = RNGitResponseCode(rawValue: response[response.startIndex])
    guard code != .ok else { return .done(Data(response.dropFirst())) }
    return .failed(saying(code.flatMap { named[$0] } ?? other, response))
  }

  /// What `rule` makes of `response`.
  private func saying(_ rule: Rule, _ response: Data) -> String {
    switch rule {
    case .text(let fixed): return fixed
    case .sent(let prefix, let fallback):
      let body = Data(response.dropFirst())
      return prefix + (body.isEmpty ? fallback : body.utf8IgnoringInvalid)
    }
  }
}
