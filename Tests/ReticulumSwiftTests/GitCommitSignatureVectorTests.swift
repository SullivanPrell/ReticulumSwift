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

/// A commit signed by the Python `rngcs`, verified here.
///
/// The signature below was produced by `rngcs -Y sign` from RNS 1.5.4 over the commit
/// below, and accepted by `rngcs -Y verify`. A Swift-to-Swift round trip cannot catch a
/// framing divergence, because both ends would share it; this fixture can, because the
/// bytes came from the reference.
///
/// The signing identity is not carried: `verify` recovers the key from the `pubkey` the
/// `rsg` embeds (`RSG/validate`), which is what makes the fixture self-contained.
final class GitCommitSignatureVectorTests: XCTestCase {

  private let signer = "016809b2a9c0f8fe0595fab011fd71b3"

  private let commit = Data(
    ("tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\n"
      + "author Someone <016809b2a9c0f8fe0595fab011fd71b3> 1757000000 +0000\n"
      + "committer Someone <016809b2a9c0f8fe0595fab011fd71b3> 1757000000 +0000\n"
      + "\nCaptured from the Python reference\n").utf8)

  private let armoured = """
    -----BEGIN SSH SIGNATURE-----
    U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgyDGK2sHbMxgwxtzWc2tKdVqE2x
    FqMhybe8TyLYVP178AAAADZ2l0AAAAAAAAAAZzaGEyNTYAAADge0ci/y2dOkdXTHcPddNh
    gDTMKjFJg7uEEZ+6OODvJ/r5/3Q7QSZzm+oJH3BDBBkKnd44QK7+NnhZ4kvLL0m6DIOoaG
    FzaHR5cGWmc2hhMjU2pGhhc2jEIB7BO1qAe4jGrJB7oQhN/xOXCRSIJyYPtck4+2P+SzcD
    pG1ldGGCpnNpZ25lcsQQAWgJsqnA+P4FlfqwEf1xs6ZwdWJrZXnEQL6Ch65fNeq5EJF4q0
    Dq4nmr2KpsgTCjqhhbAABUF6UZyDGK2sHbMxgwxtzWc2tKdVqE2xFqMhybe8TyLYVP178=
    -----END SSH SIGNATURE-----

    """

  /// The reference's envelope parses field for field.
  func testPythonEnvelopeParses() throws {
    let envelope = try SSHSignature.parse(SSHSignature.unarmour(armoured))

    XCTAssertEqual(envelope.version, 1)
    XCTAssertEqual(envelope.namespace, SSHSignature.namespaceGit)
    XCTAssertEqual(envelope.reserved, Data())
    XCTAssertEqual(envelope.hashAlgorithm, SSHSignature.hashAlgorithm)

    let (keyType, next) = try SSHSignature.readString(envelope.publicKey, at: 0)
    XCTAssertEqual(keyType, SSHSignature.keyTypeEd25519)
    let (key, end) = try SSHSignature.readString(envelope.publicKey, at: next)
    XCTAssertEqual(key.count, 32)
    XCTAssertEqual(end, envelope.publicKey.count)
  }

  /// The reference's signature verifies against the commit it was made over.
  func testPythonSignatureVerifies() {
    XCTAssertEqual(
      GitCommitSignature.verify(message: commit, armouredSignature: armoured),
      .good(signer: signer))
  }

  /// The other two operations agree with the reference on the same bytes.
  func testPythonSignatureReportsItsSigner() throws {
    XCTAssertEqual(try GitCommitSignature.findPrincipals(armouredSignature: armoured), signer)
    XCTAssertTrue(GitCommitSignature.checkWithoutValidating(armouredSignature: armoured))
  }

  /// A byte changed anywhere in the commit invalidates the reference's signature.
  func testAlteringThePythonVectorBreaksIt() {
    var altered = commit
    altered[altered.count - 2] = 0x21

    guard
      case .invalidSignature = GitCommitSignature.verify(
        message: altered, armouredSignature: armoured)
    else { return XCTFail("the captured signature must not survive an edit") }
  }
}
