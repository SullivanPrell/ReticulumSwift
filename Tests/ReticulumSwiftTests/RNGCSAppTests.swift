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

/// The `rngcs` command line, which `git` drives through `gpg.ssh.program`.
///
/// Python: `main` and the four operations (`Utilities/rngit/commitsigs.py:118-323`). The
/// switches are the ones `git` passes an SSH signing program, so the surface is fixed by
/// `git` rather than chosen here.
final class RNGCSAppTests: XCTestCase {

  private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rngcs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory
  }

  private func identityFile(in directory: URL) throws -> (Identity, String) {
    let identity = Identity()
    let url = directory.appendingPathComponent("identity")
    XCTAssertTrue(try identity.toFile(url))
    return (identity, url.path)
  }

  private func commit(author: String) -> Data {
    Data(
      ("tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\n"
        + "author Someone <\(author)> 1757000000 +0000\n"
        + "committer Someone <\(author)> 1757000000 +0000\n"
        + "\nA commit message\n").utf8)
  }

  // MARK: - Argument parsing

  /// The operation switch is `-Y`, and it is the one argument `git` always supplies.
  ///
  /// Python: `parser.add_argument("-Y", dest="op", required=True, choices=[...])`
  /// (`commitsigs.py:301`).
  func testOperationIsReadFromDashY() throws {
    let invocation = try RNGCSCommandLine.parse(["-Y", "sign", "-f", "key", "message.txt"])
    XCTAssertEqual(invocation.operation, .sign)
    XCTAssertEqual(invocation.keyfile, "key")
    XCTAssertEqual(invocation.file, "message.txt")

    XCTAssertEqual(try RNGCSCommandLine.parse(["-Y", "verify", "-s", "s"]).operation, .verify)
    XCTAssertEqual(
      try RNGCSCommandLine.parse(["-Y", "find-principals", "-s", "s"]).operation,
      .findPrincipals)
    XCTAssertEqual(
      try RNGCSCommandLine.parse(["-Y", "check-novalidate", "-s", "s"]).operation,
      .checkNoValidate)
  }

  /// An operation outside the four is rejected.
  ///
  /// Python: `choices=` makes `argparse` exit 2.
  func testUnknownOperationIsRejected() {
    XCTAssertThrowsError(try RNGCSCommandLine.parse(["-Y", "encrypt"]))
    XCTAssertThrowsError(try RNGCSCommandLine.parse([]))
  }

  /// `-O` is accepted and ignored, because `git` passes it and nothing here reads it.
  ///
  /// Python: `action="append"`, plus a `parse_known_args` loop that skips any leftover
  /// `-O` token (`commitsigs.py:308-315`). Both bundled and separated forms are covered.
  func testSSHOptionsAreAcceptedAndIgnored() throws {
    let invocation = try RNGCSCommandLine.parse(
      ["-Y", "verify", "-s", "sig", "-O", "verify-time=20260101", "-Oextra"])
    XCTAssertEqual(invocation.operation, .verify)
    XCTAssertEqual(invocation.sigfile, "sig")
  }

  /// Any other unrecognised argument is an error.
  ///
  /// Python: the `parse_known_args` loop exits 1 on anything not starting with `-O`
  /// (`commitsigs.py:312-315`).
  func testUnknownArgumentIsAnError() {
    XCTAssertThrowsError(try RNGCSCommandLine.parse(["-Y", "verify", "-s", "sig", "--bogus"]))
  }

  // MARK: - Operations

  /// Signing a file writes the armoured signature beside it.
  ///
  /// Python: `sig_file = args.file + ".sig"` (`commitsigs.py:134`).
  func testSigningAFileWritesADotSigBeside() throws {
    let directory = try scratch()
    let (identity, keyfile) = try identityFile(in: directory)
    let hash = RNSUtilities.hexrep(identity.hash, delimit: false)
    let messagePath = directory.appendingPathComponent("commit").path
    try commit(author: hash).write(to: URL(fileURLWithPath: messagePath))

    let output = RNIDCapturingOutput()
    let operations = RNGCSOperations(
      output: output, errorOutput: RNIDCapturingOutput(), fileSystem: RNIDRealFileSystem(),
      standardInput: { Data() })

    XCTAssertEqual(
      operations.run(
        try RNGCSCommandLine.parse(["-Y", "sign", "-f", keyfile, messagePath])), 0)

    let armoured = try String(contentsOfFile: messagePath + ".sig", encoding: .utf8)
    XCTAssertTrue(armoured.hasPrefix("-----BEGIN SSH SIGNATURE-----"))
    XCTAssertTrue(output.lines.isEmpty, "a file signature is written, not printed")
  }

  /// With no file, the message comes from standard input and the signature is printed.
  ///
  /// Python: `message = sys.stdin.buffer.read()` then `print(armored, end="")`
  /// (`commitsigs.py:137-138`, `:169`).
  func testSigningStandardInputPrintsTheSignature() throws {
    let directory = try scratch()
    let (identity, keyfile) = try identityFile(in: directory)
    let message = commit(author: RNSUtilities.hexrep(identity.hash, delimit: false))

    let output = RNIDCapturingOutput()
    let operations = RNGCSOperations(
      output: output, errorOutput: RNIDCapturingOutput(), fileSystem: RNIDRealFileSystem(),
      standardInput: { message })

    XCTAssertEqual(operations.run(try RNGCSCommandLine.parse(["-Y", "sign", "-f", keyfile])), 0)
    XCTAssertTrue(output.partials.joined().hasPrefix("-----BEGIN SSH SIGNATURE-----"))
  }

  /// A missing identity file is an error, not a crash.
  ///
  /// Python: `if not keyfile or not os.path.isfile(keyfile): ... return 1`
  /// (`commitsigs.py:120-122`).
  func testSigningWithoutAnIdentityFails() throws {
    let errors = RNIDCapturingOutput()
    let operations = RNGCSOperations(
      output: RNIDCapturingOutput(), errorOutput: errors, fileSystem: RNIDRealFileSystem(),
      standardInput: { Data() })

    XCTAssertEqual(operations.run(try RNGCSCommandLine.parse(["-Y", "sign"])), 1)
    XCTAssertEqual(
      operations.run(try RNGCSCommandLine.parse(["-Y", "sign", "-f", "/nonexistent/key"])), 1)
    XCTAssertFalse(errors.lines.isEmpty)
  }

  /// Verifying reads the signature from `-s` and the object from standard input.
  ///
  /// Python: `verify` (`commitsigs.py:263-297`); the success line names the signer.
  func testVerifyReadsTheObjectFromStandardInput() throws {
    let directory = try scratch()
    let (identity, keyfile) = try identityFile(in: directory)
    let hash = RNSUtilities.hexrep(identity.hash, delimit: false)
    let message = commit(author: hash)

    let armoured = try GitCommitSignature.sign(message: message, identity: identity)
    let sigfile = directory.appendingPathComponent("sig").path
    try armoured.write(toFile: sigfile, atomically: true, encoding: .utf8)

    let output = RNIDCapturingOutput()
    let operations = RNGCSOperations(
      output: output, errorOutput: RNIDCapturingOutput(), fileSystem: RNIDRealFileSystem(),
      standardInput: { message })

    XCTAssertEqual(
      operations.run(try RNGCSCommandLine.parse(["-Y", "verify", "-s", sigfile])), 0)
    XCTAssertEqual(output.lines.count, 1)
    XCTAssertTrue(output.lines[0].contains(hash))
    XCTAssertTrue(output.lines[0].hasPrefix("Good \"git\" signature"))

    _ = keyfile
  }

  /// Verifying a signature that does not match the object exits non-zero.
  func testVerifyRejectsATamperedObject() throws {
    let directory = try scratch()
    let (identity, _) = try identityFile(in: directory)
    let hash = RNSUtilities.hexrep(identity.hash, delimit: false)

    let armoured = try GitCommitSignature.sign(message: commit(author: hash), identity: identity)
    let sigfile = directory.appendingPathComponent("sig").path
    try armoured.write(toFile: sigfile, atomically: true, encoding: .utf8)

    var tampered = commit(author: hash)
    tampered.append(contentsOf: Data("tampered\n".utf8))

    let operations = RNGCSOperations(
      output: RNIDCapturingOutput(), errorOutput: RNIDCapturingOutput(),
      fileSystem: RNIDRealFileSystem(), standardInput: { tampered })

    XCTAssertEqual(
      operations.run(try RNGCSCommandLine.parse(["-Y", "verify", "-s", sigfile])), 1)
  }

  /// `find-principals` prints the signer, and `check-novalidate` prints nothing.
  ///
  /// Python: `print(RNS.hexrep(identity_hash, delimit=False))` (`commitsigs.py:191`), and
  /// `check_novalidate` returns a code only (`commitsigs.py:195-210`).
  func testFindPrincipalsAndCheckWithoutValidation() throws {
    let directory = try scratch()
    let (identity, _) = try identityFile(in: directory)
    let hash = RNSUtilities.hexrep(identity.hash, delimit: false)

    let armoured = try GitCommitSignature.sign(message: commit(author: hash), identity: identity)
    let sigfile = directory.appendingPathComponent("sig").path
    try armoured.write(toFile: sigfile, atomically: true, encoding: .utf8)

    let output = RNIDCapturingOutput()
    let operations = RNGCSOperations(
      output: output, errorOutput: RNIDCapturingOutput(), fileSystem: RNIDRealFileSystem(),
      standardInput: { Data() })

    XCTAssertEqual(
      operations.run(try RNGCSCommandLine.parse(["-Y", "find-principals", "-s", sigfile])), 0)
    XCTAssertEqual(output.lines, [hash])

    XCTAssertEqual(
      operations.run(try RNGCSCommandLine.parse(["-Y", "check-novalidate", "-s", sigfile])), 0)
    XCTAssertEqual(output.lines, [hash], "check-novalidate reports through its exit code only")

    let missing = directory.appendingPathComponent("absent").path
    XCTAssertEqual(
      operations.run(try RNGCSCommandLine.parse(["-Y", "check-novalidate", "-s", missing])), 1)
  }
}
