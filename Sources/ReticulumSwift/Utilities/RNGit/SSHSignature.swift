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

/// The `SSHSIG` envelope a Reticulum signature travels in when `git` signs a commit.
///
/// `git` delegates signing to an external program and stores what it returns, so the
/// signature it reads back has to be an armoured `SSHSIG`. `rngcs` puts an `rsg` in the
/// signature field of one (`Utilities/rngit/commitsigs.py:42-66`).
public enum SSHSignature {

  /// The six bytes every `SSHSIG` blob opens with.
  public static let magic = Data("SSHSIG".utf8)
  /// The only envelope version this reads or writes.
  public static let version: UInt32 = 1
  /// Namespace `git` signs commits under.
  public static let namespaceGit = Data("git".utf8)
  /// Hash algorithm named in the envelope.
  public static let hashAlgorithm = Data("sha256".utf8)
  /// Key-type name in the public key field.
  public static let keyTypeEd25519 = Data("ssh-ed25519".utf8)

  private static let beginMarker = "-----BEGIN SSH SIGNATURE-----"
  private static let endMarker = "-----END SSH SIGNATURE-----"
  private static let armourLineLength = 70

  /// The fields of a parsed envelope.
  public struct Parsed: Equatable {
    /// Envelope version.
    public let version: UInt32
    /// Signer's public key, in SSH wire format.
    public let publicKey: Data
    /// Namespace the signature was made under.
    public let namespace: Data
    /// Reserved field, empty in everything this writes.
    public let reserved: Data
    /// Hash algorithm named in the envelope.
    public let hashAlgorithm: Data
    /// The signature itself, which is an `rsg` here.
    public let signatureData: Data
  }

  /// Reasons an envelope or its armour could not be read.
  public enum SignatureError: Error, Equatable {
    /// The blob does not open with ``magic``.
    case missingMagic
    /// A length or a field ran past the end of the blob.
    case truncated
    /// An envelope version this does not implement.
    case unsupportedVersion(UInt32)
    /// Armoured text with nothing between the markers.
    case noSignatureData
  }

  // MARK: - Framing

  /// Frames `data` as an `ssh-string`: a big-endian length, then the bytes.
  ///
  /// Python: `struct.pack(">I", len(data)) + data` (`commitsigs.py:48`).
  static func string(_ data: Data) -> Data {
    let length = UInt32(data.count)
    var framed = Data([
      UInt8(truncatingIfNeeded: length >> 24), UInt8(truncatingIfNeeded: length >> 16),
      UInt8(truncatingIfNeeded: length >> 8), UInt8(truncatingIfNeeded: length),
    ])
    framed.append(data)
    return framed
  }

  /// Reads the `ssh-string` at `offset`, returning it and the offset just past it.
  ///
  /// Python: `read_ssh_string` (`commitsigs.py:50-55`).
  static func readString(_ data: Data, at offset: Int) throws -> (value: Data, next: Int) {
    let base = data.startIndex
    guard offset >= 0, offset + 4 <= data.count else { throw SignatureError.truncated }
    var length: UInt32 = 0
    for byte in data[(base + offset)..<(base + offset + 4)] {
      length = (length << 8) | UInt32(byte)
    }
    let end = offset + 4 + Int(length)
    guard end <= data.count else { throw SignatureError.truncated }
    return (Data(data[(base + offset + 4)..<(base + end)]), end)
  }

  // MARK: - The envelope

  /// Builds an `SSHSIG` blob from its fields.
  ///
  /// Python: `create_ssh_signature` (`commitsigs.py:56-66`).
  public static func create(
    publicKeyWire: Data, namespace: Data, reserved: Data, hashAlgorithm: Data,
    signatureData: Data
  ) -> Data {
    var blob = magic
    blob.append(contentsOf: [0x00, 0x00, 0x00, UInt8(truncatingIfNeeded: version)])
    blob += string(publicKeyWire)
    blob += string(namespace)
    blob += string(reserved)
    blob += string(hashAlgorithm)
    blob += string(signatureData)
    return blob
  }

  /// Reads an `SSHSIG` blob.
  ///
  /// Python: `parse_ssh_signature` (`commitsigs.py:68-90`).
  public static func parse(_ blob: Data) throws -> Parsed {
    guard blob.starts(with: magic) else { throw SignatureError.missingMagic }
    var offset = magic.count

    guard offset + 4 <= blob.count else { throw SignatureError.truncated }
    let base = blob.startIndex
    var envelopeVersion: UInt32 = 0
    for byte in blob[(base + offset)..<(base + offset + 4)] {
      envelopeVersion = (envelopeVersion << 8) | UInt32(byte)
    }
    guard envelopeVersion == version else {
      throw SignatureError.unsupportedVersion(envelopeVersion)
    }
    offset += 4

    let (publicKey, afterKey) = try readString(blob, at: offset)
    let (namespace, afterNamespace) = try readString(blob, at: afterKey)
    let (reserved, afterReserved) = try readString(blob, at: afterNamespace)
    let (algorithm, afterAlgorithm) = try readString(blob, at: afterReserved)
    let (signature, _) = try readString(blob, at: afterAlgorithm)

    return Parsed(
      version: envelopeVersion, publicKey: publicKey, namespace: namespace,
      reserved: reserved, hashAlgorithm: algorithm, signatureData: signature)
  }

  // MARK: - Armour

  /// Wraps a blob in the armour `git` stores in a commit's `gpgsig` header.
  ///
  /// Python: base64 in 70-character lines between the two markers
  /// (`commitsigs.py:92-99`).
  public static func armour(_ blob: Data) -> String {
    let encoded = blob.base64EncodedString()
    var lines: [String] = []
    var index = encoded.startIndex
    while index < encoded.endIndex {
      let end = encoded.index(index, offsetBy: armourLineLength, limitedBy: encoded.endIndex)
      lines.append(String(encoded[index..<(end ?? encoded.endIndex)]))
      index = end ?? encoded.endIndex
    }
    return beginMarker + "\n" + lines.joined(separator: "\n") + "\n" + endMarker + "\n"
  }

  /// Recovers a blob from its armour, ignoring anything outside the markers.
  ///
  /// Python: `unarmor_ssh_signature` (`commitsigs.py:101-113`).
  public static func unarmour(_ armoured: String) throws -> Data {
    var encoded = ""
    var inSignature = false
    for line in armoured.trimmingCharacters(in: .whitespacesAndNewlines).split(
      separator: "\n", omittingEmptySubsequences: false)
    {
      if line.contains("BEGIN SSH SIGNATURE") {
        inSignature = true
        continue
      }
      if line.contains("END SSH SIGNATURE") { break }
      if inSignature { encoded += line.trimmingCharacters(in: .whitespaces) }
    }

    guard !encoded.isEmpty else { throw SignatureError.noSignatureData }
    guard let blob = Data(base64Encoded: encoded) else { throw SignatureError.noSignatureData }
    return blob
  }

  // MARK: - Public key

  /// The identity's signing key in SSH wire format.
  ///
  /// Python: `ssh_string(b"ssh-ed25519")+ssh_string(identity.sig_pub_bytes)`
  /// (`commitsigs.py:115-116`).
  public static func publicKeyWire(for identity: Identity) -> Data {
    string(keyTypeEd25519) + string(identity.signingPublicKey.rawRepresentation)
  }
}
