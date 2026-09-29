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

/// `Destination.encrypt` for a `SINGLE` destination encrypts to the ratchet recalled for
/// its hash and records that ratchet's ID, as `Destination.py:606-610` does through
/// `Identity.get_ratchet`.
final class DestinationEncryptRatchetTests: XCTestCase {

  private var stack: Reticulum!
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rs-encrypt-ratchet-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    stack = Reticulum(configuration: .init(storagePath: directory))
    try stack.start()
  }

  override func tearDownWithError() throws {
    stack.stop()
    try? FileManager.default.removeItem(at: directory)
  }

  func testEncryptUsesTheRecalledRatchet() throws {
    let receiver = Identity()
    let ratchet = receiver.rotateRatchet()
    let remote = try Identity(publicKeyBytes: receiver.publicKeyBytes)
    let out = try Destination(
      identity: remote, direction: .out, kind: .single, appName: "spec", aspects: [])
    stack.transport.restore(ratchet: ratchet, forDestination: out.hash)

    let token = try out.encrypt(Data("ratcheted".utf8))

    let result = try receiver.decrypt(
      token, ratchetPrivateKeys: receiver.ratchetPrivateKeyPool, enforceRatchets: true)
    XCTAssertEqual(result.plaintext, Data("ratcheted".utf8))
    XCTAssertEqual(result.ratchetID, Identity.ratchetID(forPublicKey: ratchet))
    XCTAssertEqual(out.latestRatchetID, Identity.ratchetID(forPublicKey: ratchet))
  }

  func testEncryptWithoutARecalledRatchetUsesTheIdentityKey() throws {
    let receiver = Identity()
    let remote = try Identity(publicKeyBytes: receiver.publicKeyBytes)
    let out = try Destination(
      identity: remote, direction: .out, kind: .single, appName: "spec", aspects: [])

    let token = try out.encrypt(Data("static".utf8))

    let result = try receiver.decrypt(token, ratchetPrivateKeys: [], enforceRatchets: false)
    XCTAssertEqual(result.plaintext, Data("static".utf8))
    XCTAssertNil(result.ratchetID)
    XCTAssertNil(out.latestRatchetID)
  }
}
