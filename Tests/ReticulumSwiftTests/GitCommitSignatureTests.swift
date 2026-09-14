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

/// `rngcs`, the signing program `git` calls for a Reticulum identity.
///
/// Python: `RNS/Utilities/rngit/commitsigs.py`. The four operations are the ones
/// `gpg.ssh.program` is invoked with: `sign`, `find-principals`, `check-novalidate` and
/// `verify` (`commitsigs.py:299-323`). A commit counts as signed by its author only when
/// the author's email field is the signer's identity hash, which is the convention `rngit`
/// repositories are built on (`commitsigs.py:288-292`).
final class GitCommitSignatureTests: XCTestCase {

  private func commit(author: String, committer: String? = nil) -> Data {
    var text = "tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\n"
    text += "author Someone <\(author)> 1757000000 +0000\n"
    text += "committer Someone <\(committer ?? author)> 1757000000 +0000\n"
    text += "\nA commit message\n"
    return Data(text.utf8)
  }

  private func tag(tagger: String) -> Data {
    var text = "object 4b825dc642cb6eb9a060e54bf8d69288fbee4904\n"
    text += "type commit\n"
    text += "tag v1.0.0\n"
    text += "tagger Someone <\(tagger)> 1757000000 +0000\n"
    text += "\nA tag message\n"
    return Data(text.utf8)
  }

  // MARK: - Header extraction

  /// The author is the email field of the `author` header.
  ///
  /// Python: `extract_commit_author` (`commitsigs.py:212-226`).
  func testAuthorIsTheEmailField() {
    XCTAssertEqual(GitCommitHeaders.author(in: commit(author: "abc123")), "abc123")
    XCTAssertEqual(
      GitCommitHeaders.committer(in: commit(author: "abc123", committer: "def456")), "def456")
  }

  /// The scan stops at the first empty line, so the body cannot supply a header.
  ///
  /// Python breaks on a falsy line (`commitsigs.py:216`), which is the blank line between
  /// a commit's headers and its message.
  func testHeaderScanStopsAtTheBody() {
    let forged = Data(
      ("tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\n"
        + "\n"
        + "author Someone <forged> 1757000000 +0000\n").utf8)
    XCTAssertEqual(GitCommitHeaders.author(in: forged), "")
  }

  /// A header whose address does not sit where `git` writes one yields nothing.
  ///
  /// Python requires the `<` past the prefix, the `>` after it, and at least one character
  /// after the `>`, which is the timestamp (`commitsigs.py:218-220`). An address that fails
  /// any of the three is dropped, and `""` is never a signer hash, so verification of such
  /// a commit fails closed.
  func testAddressBoundsFollowTheReference() {
    let noName = Data("author <abc123> 1757000000 +0000\n\nbody\n".utf8)
    XCTAssertEqual(GitCommitHeaders.author(in: noName), "")

    let noTimestamp = Data("author Someone <abc123>\n\nbody\n".utf8)
    XCTAssertEqual(GitCommitHeaders.author(in: noTimestamp), "")

    let reversed = Data("author Someone >abc123< 1757000000 +0000\n\nbody\n".utf8)
    XCTAssertEqual(GitCommitHeaders.author(in: reversed), "")
  }

  /// A tag reports its tagger, and says that it is a tag.
  ///
  /// Python: `extract_commit_tagger` records `is_tag` from the `tag ` header and only then
  /// accepts a `tagger ` line (`commitsigs.py:244-261`).
  func testTaggerIsOnlyReadOnATag() {
    let onTag = GitCommitHeaders.tagger(in: tag(tagger: "abc123"))
    XCTAssertTrue(onTag.isTag)
    XCTAssertEqual(onTag.tagger, "abc123")

    let onCommit = GitCommitHeaders.tagger(in: commit(author: "abc123"))
    XCTAssertFalse(onCommit.isTag)
    XCTAssertEqual(onCommit.tagger, "")
  }

  // MARK: - Signing and verifying

  /// A signature this program produces is one it accepts.
  ///
  /// Python: `sign` (`commitsigs.py:118-170`) then `verify` (`commitsigs.py:263-297`).
  func testSignedCommitVerifies() throws {
    let identity = Identity()
    let hash = RNSUtilities.hexrep(identity.hash, delimit: false)
    let message = commit(author: hash)

    let armoured = try GitCommitSignature.sign(message: message, identity: identity)
    let outcome = GitCommitSignature.verify(message: message, armouredSignature: armoured)

    XCTAssertEqual(outcome, .good(signer: hash))
  }

  /// A commit whose author is not the signer is rejected.
  ///
  /// Python: `if not author == signer_hash: ... return 1` (`commitsigs.py:288-290`).
  func testCommitNotSignedByItsAuthorIsRejected() throws {
    let identity = Identity()
    let message = commit(author: "0000000000000000000000000000000000000000000000000000000000000000")

    let armoured = try GitCommitSignature.sign(message: message, identity: identity)
    let outcome = GitCommitSignature.verify(message: message, armouredSignature: armoured)

    guard case .authorMismatch = outcome else {
      return XCTFail("expected an author mismatch, got \(outcome)")
    }
  }

  /// A tag is checked against its tagger rather than an author it does not have.
  ///
  /// Python: `if is_tag: author = tagger` (`commitsigs.py:285`).
  func testTagIsCheckedAgainstItsTagger() throws {
    let identity = Identity()
    let hash = RNSUtilities.hexrep(identity.hash, delimit: false)
    let message = tag(tagger: hash)

    let armoured = try GitCommitSignature.sign(message: message, identity: identity)
    XCTAssertEqual(
      GitCommitSignature.verify(message: message, armouredSignature: armoured),
      .good(signer: hash))
  }

  /// A message that changed after signing no longer verifies.
  func testAlteredMessageFailsValidation() throws {
    let identity = Identity()
    let hash = RNSUtilities.hexrep(identity.hash, delimit: false)
    let armoured = try GitCommitSignature.sign(message: commit(author: hash), identity: identity)

    var altered = commit(author: hash)
    altered.append(contentsOf: Data("tampered\n".utf8))

    guard
      case .invalidSignature = GitCommitSignature.verify(
        message: altered, armouredSignature: armoured)
    else { return XCTFail("an altered message must not verify") }
  }

  /// A signature made for another namespace is refused.
  ///
  /// Python checks `ssh_sig["namespace"] != NAMESPACE_GIT` before validating
  /// (`commitsigs.py:280`).
  func testForeignNamespaceIsRefused() throws {
    let identity = Identity()
    let hash = RNSUtilities.hexrep(identity.hash, delimit: false)
    let message = commit(author: hash)

    let rsg = try RSG.create(signer: identity, message: .bytes(message))
    let blob = SSHSignature.create(
      publicKeyWire: SSHSignature.publicKeyWire(for: identity),
      namespace: Data("file".utf8), reserved: Data(),
      hashAlgorithm: SSHSignature.hashAlgorithm, signatureData: rsg.data)

    guard
      case .namespaceMismatch = GitCommitSignature.verify(
        message: message, armouredSignature: SSHSignature.armour(blob))
    else { return XCTFail("a signature from another namespace must be refused") }
  }

  /// The principal, when given, must be the signer.
  ///
  /// Python: `if principal: if principal != signer_hash: ... return 1`
  /// (`commitsigs.py:291-292`).
  func testPrincipalMustMatchTheSigner() throws {
    let identity = Identity()
    let hash = RNSUtilities.hexrep(identity.hash, delimit: false)
    let message = commit(author: hash)
    let armoured = try GitCommitSignature.sign(message: message, identity: identity)

    XCTAssertEqual(
      GitCommitSignature.verify(message: message, armouredSignature: armoured, principal: hash),
      .good(signer: hash))

    guard
      case .principalMismatch = GitCommitSignature.verify(
        message: message, armouredSignature: armoured, principal: "deadbeef")
    else { return XCTFail("a principal that is not the signer must be refused") }
  }

  // MARK: - The other two operations

  /// `find-principals` reports the signer recorded in the signature.
  ///
  /// Python: `extract_signed_rsg_data(rsg)["meta"]["signer"]` (`commitsigs.py:189`).
  func testFindPrincipalsReportsTheSigner() throws {
    let identity = Identity()
    let message = commit(author: "irrelevant")
    let armoured = try GitCommitSignature.sign(message: message, identity: identity)

    XCTAssertEqual(
      try GitCommitSignature.findPrincipals(armouredSignature: armoured),
      RNSUtilities.hexrep(identity.hash, delimit: false))
  }

  /// `check-novalidate` accepts a well-formed signature without the message.
  ///
  /// Python: `check_novalidate` parses and extracts, and never validates
  /// (`commitsigs.py:195-210`).
  func testCheckWithoutValidationAcceptsAWellFormedSignature() throws {
    let identity = Identity()
    let armoured = try GitCommitSignature.sign(
      message: commit(author: "irrelevant"), identity: identity)

    XCTAssertTrue(GitCommitSignature.checkWithoutValidating(armouredSignature: armoured))
    XCTAssertFalse(GitCommitSignature.checkWithoutValidating(armouredSignature: "not a signature"))
  }
}
