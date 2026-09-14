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

/// What a client asks of a running stack, over a link to the node.
///
/// A response that carries metadata is a file, and its bytes are written under the transport's
/// own directory so they outlive the request.
public final class RNGitLinkTransport: RNGitClientTransport {

  /// How long a path is waited for, before the slowest interface's own timeout is taken.
  public static let pathTimeout: TimeInterval = 15

  /// How long a link is waited for, before the link's own establishment timeout is taken.
  public static let linkTimeout: TimeInterval = 15

  /// The stack the transport runs on.
  private let reticulum: Reticulum

  /// The identity the client identifies as, or `nil` where it identifies as nobody.
  private let identity: Identity?

  /// Where file responses are written.
  private let directory: String

  /// The aspect the node serves repositories under.
  private let aspect: String

  /// The link to the node, or `nil` before one is opened.
  private var link: Link?

  /// Whether the link came up and the client identified over it.
  private var ready = false

  /// Whether the link closed before it came up.
  private var failed = false

  /// Guards `ready` and `failed`, which the link's callbacks write from the receive thread.
  private let lock = NSLock()

  /// How many file responses have been written, which names the next one.
  private var retained = 0

  /// Creates a transport running on `reticulum`, identifying as `identity`.
  ///
  /// File responses are written under `directory`, which the caller makes and removes.
  public init(
    reticulum: Reticulum, identity: Identity?, directory: String,
    aspect: String = RNGitDestination.aspect
  ) {
    self.reticulum = reticulum
    self.identity = identity
    self.directory = directory
    self.aspect = aspect
  }

  /// How long a link is waited for, where the link itself takes `establishment` to come up.
  static func wait(for establishment: TimeInterval) -> TimeInterval {
    max(linkTimeout, establishment)
  }

  /// How long a path may take, which is the floor or the slowest interface's own timeout.
  public func mediumPathTimeout() -> TimeInterval {
    max(Self.pathTimeout, reticulum.getMediumPathTimeout())
  }

  /// Whether a path to `destinationHash` came up inside `timeout`.
  public func awaitPath(to destinationHash: Data, timeout: TimeInterval) -> Bool {
    reticulum.transport.awaitPath(to: destinationHash, timeout: timeout)
  }

  /// The identity the stack holds for `destinationHash`, or `nil` where it holds none.
  public func recallIdentity(for destinationHash: Data) -> Identity? {
    reticulum.transport.recall(identity: destinationHash)
  }

  /// Opens a link to `identity` and identifies over it, answering whether it came up.
  public func establishLink(to identity: Identity) -> Bool {
    guard
      let destination = try? Destination(
        identity: identity, direction: .out, kind: .single,
        appName: RNGitDestination.appName, aspects: [aspect]),
      let opened = try? Link.initiate(destination: destination, transport: reticulum.transport)
    else { return false }

    opened.onEstablished = { [weak self] link in
      guard let self else { return }
      try? link.identify(as: self.identity ?? Identity())
      self.lock.lock()
      self.ready = true
      self.lock.unlock()
    }
    opened.onClosed = { [weak self] _ in
      guard let self else { return }
      self.lock.lock()
      if !self.ready { self.failed = true }
      self.lock.unlock()
    }
    link = opened

    var remaining = Self.wait(for: opened.establishmentTimeout)
    while remaining > 0 {
      lock.lock()
      let (up, down) = (ready, failed)
      lock.unlock()
      if up || down { break }
      Thread.sleep(forTimeInterval: 0.5)
      remaining -= 0.5
    }

    lock.lock()
    defer { lock.unlock() }
    return ready
  }

  /// Sends a request to `path` carrying `fields`, waiting for what comes back.
  public func request(
    _ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval,
    progress: ((RNGitTransferProgress) -> Void)?
  ) -> RNGitClientResponse {
    guard let link else { return RNGitClientResponse(result: .none) }

    let waiting = DispatchSemaphore(value: 0)
    var payload: Data?
    var metadata: MsgPack.Value?

    let receipt = try? link.request(
      path: path.rawValue, nativeValue: fields,
      responseCallback: { response, receipt in
        payload = response
        metadata = receipt.metadata
        waiting.signal()
      },
      failedCallback: { _, _ in waiting.signal() },
      progressCallback: progress.map { report in
        { fraction, receipt in
          report(
            RNGitTransferProgress(
              fraction: fraction, size: receipt.responseSize,
              transferSize: receipt.responseTransferSize))
        }
      },
      timeout: timeout)
    guard receipt != nil else { return RNGitClientResponse(result: .none) }

    guard waiting.wait(timeout: .now() + timeout) == .success, let payload else {
      return RNGitClientResponse(result: .none)
    }

    // A response carrying metadata is a file, and the bytes are kept on disk under the
    // transport's own directory the way a file response is kept beyond the request.
    guard let metadata else { return RNGitClientResponse(result: .bytes(payload)) }
    retained += 1
    let file = directory + "/response-" + String(retained)
    guard FileManager.default.createFile(atPath: file, contents: payload) else {
      return RNGitClientResponse(result: .none, metadata: metadata)
    }
    return RNGitClientResponse(result: .file(file), metadata: metadata)
  }

  /// Closes the link and lets go of it.
  public func teardown() {
    try? link?.teardown()
    link = nil
  }
}
