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

/// The `SSHSIG` envelope `rngcs` wraps a Reticulum signature in.
///
/// `git` signs and verifies through an external program, and reads back an armoured
/// `SSHSIG` blob. `rngcs` is that program for a Reticulum identity: it puts an `rsg`
/// signature in the `signature` field of an otherwise ordinary `SSHSIG`
/// (`Utilities/rngit/commitsigs.py:56-66`). The envelope is what `git` parses, so its
/// framing is a wire format.
final class SSHSignatureTests: XCTestCase {

  // MARK: - Framing

  /// An `ssh-string` is a big-endian length followed by the bytes.
  ///
  /// Python: `struct.pack(">I", len(data)) + data` (`commitsigs.py:48`).
  func testSSHStringIsLengthPrefixed() {
    XCTAssertEqual(
      SSHSignature.string(Data("abc".utf8)),
      Data([0x00, 0x00, 0x00, 0x03]) + Data("abc".utf8))
    XCTAssertEqual(SSHSignature.string(Data()), Data([0x00, 0x00, 0x00, 0x00]))
  }

  /// Reading a string returns its bytes and the offset just past it.
  ///
  /// Python: `read_ssh_string` (`commitsigs.py:50-55`).
  func testReadSSHStringAdvancesPastTheValue() throws {
    let blob = SSHSignature.string(Data("one".utf8)) + SSHSignature.string(Data("two".utf8))
    let (first, next) = try SSHSignature.readString(blob, at: 0)
    XCTAssertEqual(first, Data("one".utf8))
    let (second, end) = try SSHSignature.readString(blob, at: next)
    XCTAssertEqual(second, Data("two".utf8))
    XCTAssertEqual(end, blob.count)
  }

  /// A length that runs past the buffer is rejected rather than read short.
  ///
  /// Python raises `ValueError("Not enough data for string content")` (`commitsigs.py:53`).
  func testReadSSHStringRejectsALengthPastTheEnd() {
    let truncated = Data([0x00, 0x00, 0x00, 0x08]) + Data("abc".utf8)
    XCTAssertThrowsError(try SSHSignature.readString(truncated, at: 0))
    XCTAssertThrowsError(try SSHSignature.readString(Data([0x00, 0x00]), at: 0))
  }

  // MARK: - The envelope

  /// The envelope round-trips every field in the reference's order.
  ///
  /// Python: magic, version, public key, namespace, reserved, hash algorithm, signature
  /// (`commitsigs.py:56-66`).
  func testEnvelopeRoundTripsEveryField() throws {
    let blob = SSHSignature.create(
      publicKeyWire: Data("KEY".utf8), namespace: SSHSignature.namespaceGit,
      reserved: Data(), hashAlgorithm: SSHSignature.hashAlgorithm,
      signatureData: Data("SIG".utf8))

    XCTAssertTrue(blob.starts(with: SSHSignature.magic))

    let parsed = try SSHSignature.parse(blob)
    XCTAssertEqual(parsed.version, 1)
    XCTAssertEqual(parsed.publicKey, Data("KEY".utf8))
    XCTAssertEqual(parsed.namespace, SSHSignature.namespaceGit)
    XCTAssertEqual(parsed.reserved, Data())
    XCTAssertEqual(parsed.hashAlgorithm, SSHSignature.hashAlgorithm)
    XCTAssertEqual(parsed.signatureData, Data("SIG".utf8))
  }

  /// Parsing rejects a blob that is not an `SSHSIG`, and a version it does not know.
  ///
  /// Python: `commitsigs.py:71-77`.
  func testParseRejectsForeignMagicAndUnknownVersion() {
    XCTAssertThrowsError(try SSHSignature.parse(Data("PGPSIG\u{01}".utf8)))

    var wrongVersion = SSHSignature.magic
    wrongVersion.append(contentsOf: [0x00, 0x00, 0x00, 0x02])
    wrongVersion += SSHSignature.string(Data("KEY".utf8))
    XCTAssertThrowsError(try SSHSignature.parse(wrongVersion))
  }

  // MARK: - Armour

  /// Armoured output is the base64 blob in 70-character lines between the markers.
  ///
  /// Python: `armor_ssh_signature` (`commitsigs.py:92-99`).
  func testArmourWrapsAtSeventyCharacters() {
    let blob = Data((0..<200).map { UInt8($0 % 251) })
    let armoured = SSHSignature.armour(blob)
    let lines = armoured.split(separator: "\n", omittingEmptySubsequences: false)

    XCTAssertEqual(lines.first, "-----BEGIN SSH SIGNATURE-----")
    let body = lines.dropFirst().filter { $0 != "-----END SSH SIGNATURE-----" && !$0.isEmpty }
    XCTAssertGreaterThan(body.count, 1, "200 bytes of base64 must wrap")
    for line in body.dropLast() {
      XCTAssertEqual(line.count, 70)
    }
    XCTAssertLessThanOrEqual(body.last?.count ?? 0, 70)
    XCTAssertTrue(armoured.hasSuffix("-----END SSH SIGNATURE-----\n"))
  }

  /// Unarmouring recovers the blob, ignoring anything outside the markers.
  ///
  /// Python: `unarmor_ssh_signature` (`commitsigs.py:101-113`).
  func testUnarmourRecoversTheBlobAndIgnoresSurroundingText() throws {
    let blob = Data((0..<128).map { UInt8($0) })
    let armoured = SSHSignature.armour(blob)
    XCTAssertEqual(try SSHSignature.unarmour(armoured), blob)

    let noisy = "gpgsig header\n" + armoured + "trailing text\n"
    XCTAssertEqual(try SSHSignature.unarmour(noisy), blob)
  }

  /// Text with no signature body is rejected rather than decoded as empty.
  ///
  /// Python raises `ValueError("No signature data found in armored input")`
  /// (`commitsigs.py:111`).
  func testUnarmourRejectsTextWithNoBody() {
    XCTAssertThrowsError(try SSHSignature.unarmour("no signature here"))
    XCTAssertThrowsError(
      try SSHSignature.unarmour(
        "-----BEGIN SSH SIGNATURE-----\n-----END SSH SIGNATURE-----\n"))
  }

  // MARK: - Public key

  /// The public key is the `ssh-ed25519` name and the identity's signing key.
  ///
  /// Python: `ssh_string(b"ssh-ed25519")+ssh_string(identity.sig_pub_bytes)`
  /// (`commitsigs.py:115-116`).
  func testPublicKeyWireFormatNamesEd25519() throws {
    let identity = Identity()
    let wire = SSHSignature.publicKeyWire(for: identity)

    let (name, next) = try SSHSignature.readString(wire, at: 0)
    XCTAssertEqual(name, Data("ssh-ed25519".utf8))
    let (key, end) = try SSHSignature.readString(wire, at: next)
    XCTAssertEqual(key, identity.signingPublicKey.rawRepresentation)
    XCTAssertEqual(end, wire.count)
  }
}
