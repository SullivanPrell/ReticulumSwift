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

/// A command that ended in failure, having already said why.
public struct RNGitClientFailure: Error, Equatable, Sendable {

  /// Creates the failure.
  public init() {}
}

/// A key something a node sent does not carry.
struct RNGitMissingKey: Error, CustomStringConvertible {

  /// The key that is not there.
  let key: String

  /// What a client says where it names this key.
  var description: String { "'" + key + "'" }
}

/// An answer whose shape is not the one the step it came back to reads.
enum RNGitAnswerShape: Error, CustomStringConvertible {

  /// A node named the answer, but sent bytes where the name says a file.
  case bytesWhereAFileIsNamed

  /// A node named the answer nothing, and sent a file where no name says one.
  case fileWhereNoneIsNamed

  /// What a client says where it reads this answer.
  var description: String {
    switch self {
    case .bytesWhereAFileIsNamed: return "'bytes' object has no attribute 'name'"
    case .fileWhereNoneIsNamed: return "'_io.BufferedReader' object is not subscriptable"
    }
  }
}

extension RNGitClientCommands {

  /// Fetches the artifacts a release names, or checks the ones on disk against a manifest.
  ///
  /// `target` is a tag and an artifact pattern, written `1.0.0:*.zip`, where `all` takes every
  /// artifact the manifest names. Offline, `remote` names a manifest on disk, nothing goes over
  /// the network, and each artifact beside the manifest is checked against what it signed.
  public func fetchRelease(
    remote: String?, target: String?, signer: String? = nil, offline: Bool = false
  ) throws {
    var target = target
    if offline, target?.isEmpty != false { target = "latest:all" }
    guard var remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let target, !target.isEmpty else { throw RNGitClientAbort("No target specified") }
    let required = try requiredSigner(signer)

    var localManifest: String?
    var localManifestDirectory: String?
    if remote.hasSuffix("." + Self.messageExtension),
      Self.isFile(DaemonBootstrap.expandTilde(remote))
    {
      let path = DaemonBootstrap.expandTilde(remote)
      let rsg = try Data(contentsOf: URL(fileURLWithPath: path))
      let validated = try validated(rsg, requiring: required)
      output.write("Valid release manifest signature, signed by <\(validated.1.hash.hexString)>\n")
      if let complaint = RSG.checkReleaseRSMStructure(validated.0) {
        throw RNGitClientAbort(complaint)
      }
      let origin = validated.0.metaValue("origin")?.asData ?? Data()
      let originPath = validated.0.metaValue("path")?.pythonDescription ?? "None"
      remote =
        RNGitRemoteURL.protocolSpecifier + RNSUtilities.hexrep(origin, delimit: false) + "/"
        + originPath
      localManifest = path
      localManifestDirectory = path.replacingOccurrences(of: Self.basename(path), with: "")
      output.write("Release origin is \(remote)\n")
    }

    if offline, localManifest == nil {
      throw RNGitClientAbort("Cannot perform offline verification without a local manifest")
    }
    var linked = false
    defer { if linked { transport.teardown() } }
    if !offline {
      try connect(to: remote, failure: "Link establishment failed")
      linked = true
    }

    var verdict: Bool?
    do {
      verdict = try fetching(
        remote, target, offline: offline, requiring: required, manifest: localManifest,
        beside: localManifestDirectory)
    } catch let abort as RNGitClientAbort {
      throw abort
    } catch {
      throw RNGitClientAbort("Error fetching release: \(error)")
    }
    if verdict == false { throw RNGitClientFailure() }
  }

  /// Fetches or checks every artifact the release names, answering whether all of them held up
  /// where nothing went over the network, and `nil` where something did.
  private func fetching(
    _ remote: String, _ target: String, offline: Bool, requiring required: RSG.RequiredSigner,
    manifest localManifest: String?, beside localManifestDirectory: String?
  ) throws -> Bool? {
    let named = try read { try RNGitRemoteURL.repository(remote, aliases: aliases) }
    let path = named.group + "/" + named.repository

    let parts = target.components(separatedBy: ":")
    guard parts.count >= 2 else { throw RNGitClientAbort("Invalid release specification") }
    let tag = parts[0]
    let wanted = parts[1]

    var indent = ""
    func fetch(_ name: String) throws -> String {
      if offline {
        guard name != "manifest." + Self.messageExtension else { return localManifest ?? "" }
        return (localManifestDirectory ?? "") + name
      }
      var reporting = RNGitTransferReporting(label: name, indent: indent)
      let answer = try requesting(
        .release, Self.fetchFields(path, tag: tag, artifact: name), timeout: 7200,
        progress: { reporting.report($0, at: self.now().timeIntervalSince1970, to: self.output) })
      output.write("\r                       \r")
      if case .bytes(let body) = answer.result, body.isEmpty {
        throw RNGitClientAbort("No response from remote")
      }

      guard answer.metadata?.pythonIsTruthy == true else {
        guard case .bytes(let response) = answer.result else {
          throw RNGitAnswerShape.fileWhereNoneIsNamed
        }
        throw RNGitClientAbort(Self.fetching.refusal(response))
      }
      guard answer.metadata?.asDictionary?["name"] != nil else {
        throw RNGitClientAbort("Invalid result metadata on fetch response")
      }
      guard case .file(let file) = answer.result else {
        throw RNGitAnswerShape.bytesWhereAFileIsNamed
      }
      let size = ((try? FileManager.default.attributesOfItem(atPath: file))?[.size] as? Int) ?? 0
      output.write(
        indent + "Transferring \(name): 100% (\(RNSUtilities.prettysize(size)))"
          + String(repeating: " ", count: 25) + "\n")
      return file
    }

    let manifestPath = try fetch("manifest." + Self.messageExtension)
    let rsg = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let validated = try validated(rsg, requiring: required)
    output.write("Release manifest validated, signed by <\(validated.1.hash.hexString)>\n")
    if let complaint = RSG.checkReleaseRSMStructure(validated.0) {
      throw RNGitClientAbort(complaint)
    }

    let release = validated.0
    let name = release.metaValue("name")?.pythonDescription ?? "None"
    let version = release.metaValue("version")?.pythonDescription ?? "None"
    try rsg.write(
      to: URL(
        fileURLWithPath: Self.joined(
          workingDirectory, Self.basename(name + "_" + version + "." + Self.messageExtension))))

    let carried = release.metaValue("artifacts")
    guard carried?.pythonIsTruthy == true else {
      throw RNGitClientAbort("Release manifest contains no artifacts")
    }
    let artifacts = carried?.asArray ?? []
    let wantedArtifacts =
      wanted == "all"
      ? artifacts
      : artifacts.filter {
        FileNameMatching.matches($0.asDictionary?["name"]?.asString ?? "", wanted)
      }
    guard !wantedArtifacts.isEmpty else {
      throw RNGitClientAbort("No available artifacts specified for fetch")
    }

    output.write(
      (offline ? "Validating " : "Fetching ") + "\(wantedArtifacts.count) artifact"
        + (wantedArtifacts.count == 1 ? "" : "s") + "...\n")
    indent = "  "

    var held = 0
    for entry in wantedArtifacts {
      let carried = entry.asDictionary
      guard let named = carried?["name"] else { throw RNGitMissingKey(key: "name") }
      guard let signature = carried?["rsg"]?.asData else { throw RNGitMissingKey(key: "rsg") }
      let artifact = Self.basename(named.pythonDescription)
      let destination = Self.joined(workingDirectory, artifact)

      if !offline, !artifact.isEmpty, FileManager.default.fileExists(atPath: destination) {
        if try holds(signature, over: destination, requiring: required) {
          output.write("Existing file \(artifact) validated, not fetching again\n")
          continue
        }
        output.write(
          "Existing file \(artifact) does not match manifest, fetching and overwriting\n")
      }

      let fetched = try fetch(artifact)
      if offline, !FileManager.default.fileExists(atPath: fetched) {
        output.write("  File \(artifact) from manifest does not exist locally, cannot validate\n")
        continue
      }

      let valid = try holds(signature, over: fetched, requiring: required)
      if !valid {
        guard offline else {
          throw RNGitClientAbort("Fetched file \(artifact) does not match manifest, aborting")
        }
        output.write("  File \(artifact) does not match manifest\n")
      } else if offline {
        output.write("  File \(artifact) validated against manifest \(localManifest ?? "None")\n")
      } else {
        try? FileManager.default.removeItem(atPath: destination)
        try FileManager.default.moveItem(atPath: fetched, toPath: destination)
      }
      if valid { held += 1 }
    }

    guard offline else { return nil }
    if held == wantedArtifacts.count {
      output.write("\nAll files validated\n")
      return true
    }
    output.write("\nRelease is not valid\n")
    return false
  }

  /// How the client reads a code a node answers a fetch with.
  private static let fetching = RNGitResponseReading(
    named: [
      .invalidRequest: .text("Remote error: Invalid request"),
      .notFound: .sent(prefix: "", fallback: "Not found"),
      .disallowed: .sent(prefix: "", fallback: "Not allowed"),
    ],
    other: .sent(prefix: "Remote error: ", fallback: "Unknown error"))

  /// The fields a fetch of `artifact` under `tag` carries.
  private static func fetchFields(_ path: String, tag: String, artifact: String) -> MsgPack.Value {
    .map([
      (.uint(UInt64(RNGitRequestKey.repository)), .string(path)),
      (.string("operation"), .string("fetch")),
      (.string("tag"), .string(tag)),
      (.string("artifact"), .string(artifact)),
    ])
  }

  /// The signer a fetch is to insist on, or none where it was given none.
  private func requiredSigner(_ signer: String?) throws -> RSG.RequiredSigner {
    guard let signer, !signer.isEmpty else { return .none }
    guard signer.count == Identity.truncatedHashLength / 8 * 2 else {
      throw RNGitClientAbort("Invalid required signer identity hash length")
    }
    switch Data.reading(pythonHex: signer) {
    case .bytes(let hash): return .hash(hash)
    case .stopped(let position):
      throw RNGitClientAbort(
        "Invalid required signer identity hash: non-hexadecimal number found in fromhex() arg "
          + "at position \(position)")
    }
  }

  /// What `rsg` signed, where it holds up, and who signed it.
  private func validated(
    _ rsg: Data, requiring required: RSG.RequiredSigner
  ) throws -> (RSG.SignedData, Identity) {
    let embedded = try RSG.extractSignedData(rsg)?.message
    guard let embedded else { throw RNGitClientAbort("No embedded message in release manifest") }
    let result = try RSG.validate(
      rsgData: rsg, message: .bytes(embedded), requiredSigner: required)
    guard result.isValid, let signed = result.signedData, let identity = result.signingIdentity
    else {
      guard let hash = required.hash else {
        throw RNGitClientAbort("Could not validate release manifest signature")
      }
      throw RNGitClientAbort(
        "Release manifest not signed by " + RNSUtilities.prettyhexrep(hash) + ", aborting")
    }
    return (signed, identity)
  }

  /// Whether `signature` holds over the file at `path`.
  private func holds(
    _ signature: Data, over path: String, requiring required: RSG.RequiredSigner
  ) throws -> Bool {
    let reader = try RNIDFileReader(url: URL(fileURLWithPath: path))
    defer { reader.close() }
    return try RSG.validate(
      rsgData: signature, message: .file(reader), requiredSigner: required
    ).isValid
  }

  /// Whether a file, and not a directory, lies at `path`.
  private static func isFile(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return exists && !isDirectory.boolValue
  }

  /// What `path` names, which is everything after the last separator it carries.
  static func basename(_ path: String) -> String {
    guard let separator = path.lastIndex(of: "/") else { return path }
    return String(path[path.index(after: separator)...])
  }
}
