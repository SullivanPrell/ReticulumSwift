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

/// The identity fields of a raw `git` commit or tag object.
///
/// Python: `extract_commit_author`, `extract_commit_committer` and `extract_commit_tagger`
/// (`Utilities/rngit/commitsigs.py:212-261`), which are three copies of one scan. The
/// field taken is the address between `<` and `>`, and in an `rngit` repository that
/// address is the signer's identity hash rather than an email.
public enum GitCommitHeaders {

  private static let authorPrefix = Data("author ".utf8)
  private static let committerPrefix = Data("committer ".utf8)
  private static let tagPrefix = Data("tag ".utf8)
  private static let taggerPrefix = Data("tagger ".utf8)

  /// The `author` header's address, or `""` when the object has none.
  public static func author(in message: Data) -> String {
    address(after: authorPrefix, in: message) ?? ""
  }

  /// The `committer` header's address, or `""` when the object has none.
  ///
  /// Read for parity with the reference, which extracts it in `verify` but decides on the
  /// author (`commitsigs.py:276-290`).
  public static func committer(in message: Data) -> String {
    address(after: committerPrefix, in: message) ?? ""
  }

  /// The `tagger` header's address, and whether the object is a tag at all.
  ///
  /// A `tagger ` line is only read once a `tag ` line has been seen, so a commit that
  /// carries one reports nothing (`commitsigs.py:244-261`).
  public static func tagger(in message: Data) -> (tagger: String, isTag: Bool) {
    var isTag = false
    for line in headerLines(of: message) {
      if line.starts(with: tagPrefix) {
        isTag = true
      } else if line.starts(with: taggerPrefix), isTag {
        if let address = address(in: line, after: taggerPrefix.count) { return (address, true) }
      }
    }
    return ("", isTag)
  }

  /// The object's lines up to the empty line that ends its headers.
  ///
  /// Python breaks on the first falsy line (`commitsigs.py:215`), so nothing in the commit
  /// message body can present itself as a header.
  private static func headerLines(of message: Data) -> [Data] {
    var lines: [Data] = []
    for line in message.split(separator: 0x0A, omittingEmptySubsequences: false) {
      if line.isEmpty { break }
      lines.append(Data(line))
    }
    return lines
  }

  /// The address on the first header line starting with `prefix`.
  private static func address(after prefix: Data, in message: Data) -> String? {
    for line in headerLines(of: message) where line.starts(with: prefix) {
      if let address = address(in: line, after: prefix.count) { return address }
    }
    return nil
  }

  /// The text between the first `<` and the first `>` on `line`.
  ///
  /// The reference's three bounds are kept: the `<` sits past the prefix, the `>` follows
  /// it, and at least one character follows the `>`, which is the timestamp `git` writes
  /// after the address (`commitsigs.py:218-220`).
  private static func address(in line: Data, after prefixLength: Int) -> String? {
    let base = line.startIndex
    guard let openIndex = line.firstIndex(of: 0x3C), let closeIndex = line.firstIndex(of: 0x3E)
    else { return nil }
    let open = line.distance(from: base, to: openIndex)
    let close = line.distance(from: base, to: closeIndex)
    guard open > prefixLength, close > open, close < line.count - 1 else { return nil }
    return String(data: Data(line[line.index(after: openIndex)..<closeIndex]), encoding: .utf8)
  }
}

/// `rngcs`, the program `git` calls to sign and verify with a Reticulum identity.
///
/// Python: `RNS/Utilities/rngit/commitsigs.py`. The four operations are the ones
/// `gpg.ssh.program` is invoked with: `sign`, `find-principals`, `check-novalidate` and
/// `verify` (`commitsigs.py:299-323`). The signature itself is an `rsg` carried in an
/// `SSHSIG` envelope, so `git` stores and hands back a blob it already understands while
/// the trust decision stays Reticulum's.
public enum GitCommitSignature {

  /// What verifying a signature concluded.
  public enum Outcome: Equatable {
    /// The signature is valid and made by the object's own author.
    case good(signer: String)
    /// The armour or the envelope could not be read.
    case malformedSignature
    /// The envelope was signed under some namespace other than `git`.
    case namespaceMismatch
    /// The `rsg` did not validate against the object.
    case invalidSignature
    /// The signature is valid, but the author field is not the signer.
    case authorMismatch
    /// The signature is valid, but a demanded principal is not the signer.
    case principalMismatch
  }

  /// Reasons an operation could not reach a verdict.
  public enum SigningError: Error, Equatable {
    /// The envelope was signed under some namespace other than `git`.
    case namespaceMismatch
    /// The `rsg` records no signer.
    case unknownSigner
  }

  /// Signs `message` and returns the armoured `SSHSIG` `git` stores.
  ///
  /// Python: `sign` (`commitsigs.py:118-170`).
  public static func sign(message: Data, identity: Identity) throws -> String {
    let rsg = try RSG.create(signer: identity, message: .bytes(message))
    let blob = SSHSignature.create(
      publicKeyWire: SSHSignature.publicKeyWire(for: identity),
      namespace: SSHSignature.namespaceGit, reserved: Data(),
      hashAlgorithm: SSHSignature.hashAlgorithm, signatureData: rsg.data)
    return SSHSignature.armour(blob)
  }

  /// Checks a signature against the object it was made over.
  ///
  /// Python: `verify` (`commitsigs.py:263-297`). A valid signature is not enough: the
  /// author field, or on a tag the tagger field, has to be the signer's identity hash.
  /// An empty `principal` is no principal, as in Python.
  public static func verify(
    message: Data, armouredSignature: String, principal: String? = nil
  ) -> Outcome {
    guard let blob = try? SSHSignature.unarmour(armouredSignature),
      let envelope = try? SSHSignature.parse(blob)
    else { return .malformedSignature }

    var author = GitCommitHeaders.author(in: message)
    let (tagger, isTag) = GitCommitHeaders.tagger(in: message)

    guard envelope.namespace == SSHSignature.namespaceGit else { return .namespaceMismatch }

    guard
      let result = try? RSG.validate(
        rsgData: envelope.signatureData, message: .bytes(message), requiredSigner: .none),
      result.isValid, let signingIdentity = result.signingIdentity
    else { return .invalidSignature }

    if isTag { author = tagger }

    let signerHash = RNSUtilities.hexrep(signingIdentity.hash, delimit: false)
    guard author == signerHash else { return .authorMismatch }
    if let principal, !principal.isEmpty, principal != signerHash { return .principalMismatch }

    return .good(signer: signerHash)
  }

  /// The identity hash recorded in a signature, without checking it against anything.
  ///
  /// Python: `find_principals` (`commitsigs.py:173-193`), which `git` calls to learn who a
  /// signature claims to be from.
  public static func findPrincipals(armouredSignature: String) throws -> String {
    let envelope = try SSHSignature.parse(SSHSignature.unarmour(armouredSignature))
    guard envelope.namespace == SSHSignature.namespaceGit else {
      throw SigningError.namespaceMismatch
    }
    guard let signer = try RSG.extractSignedData(envelope.signatureData)?.signer else {
      throw SigningError.unknownSigner
    }
    return RNSUtilities.hexrep(signer, delimit: false)
  }

  /// Whether a signature is well formed, which is all `git` asks before it has the object.
  ///
  /// Python: `check_novalidate` (`commitsigs.py:195-210`); it parses and extracts, and
  /// never validates.
  public static func checkWithoutValidating(armouredSignature: String) -> Bool {
    do {
      let envelope = try SSHSignature.parse(SSHSignature.unarmour(armouredSignature))
      guard envelope.namespace == SSHSignature.namespaceGit else { return false }
      return try RSG.extractSignedData(envelope.signatureData) != nil
    } catch {
      return false
    }
  }
}
