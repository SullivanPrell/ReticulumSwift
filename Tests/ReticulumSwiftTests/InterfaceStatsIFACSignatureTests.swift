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

/// The `ifac_signature` key of the interface stats payload.
///
/// Python signs `full_hash(ifac_key)` once when it configures IFAC and reports the stored value
/// (`Reticulum.py:1306`, `:1863`). Its Ed25519 is RFC 8032 deterministic, so `rnstatus` prints
/// one `Access` fingerprint per segment on every node and every refresh.
final class InterfaceStatsIFACSignatureTests: XCTestCase {

  /// Captured from RNS 1.6.1 by `scripts/capture-ifac-signature-vectors.py` for network name
  /// `seg` and passphrase `secret`.
  private let pythonSignature =
    "ee1f3d6c6bdc639715dccf0547467cbb63bb7145bac1517e36819b2219e5518b"
    + "45efc321d78eb2c23f0e411dae9202e080e381060e34141d8392d16a3ddeb407"

  private func ifacSignature(_ transport: Transport) throws -> Data {
    let payload = InterfaceStatsPayload.build(transport)
    let first = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray?.first)
    guard case .map(let pairs) = first else {
      XCTFail("an interface entry must be a map")
      return Data()
    }
    for (k, v) in pairs where k == .string("ifac_signature") {
      guard case .bytes(let signature) = v else { break }
      return signature
    }
    XCTFail("ifac_signature must be bytes on an IFAC interface")
    return Data()
  }

  func testTwoBuildsReportTheSameSignature() throws {
    let transport = Transport()
    let iface = UDPInterface(name: "udp-ifac-stable", listenPort: 4272)
    Transport.configureIfac(on: iface, netname: "seg", netkey: "secret")
    transport.register(interface: iface)
    defer { transport.deregister(interface: iface) }

    XCTAssertEqual(try ifacSignature(transport), try ifacSignature(transport))
  }

  func testSignatureMatchesPythonForOneSegment() throws {
    let transport = Transport()
    let iface = UDPInterface(name: "udp-ifac-python", listenPort: 4273)
    Transport.configureIfac(on: iface, netname: "seg", netkey: "secret")
    transport.register(interface: iface)
    defer { transport.deregister(interface: iface) }

    XCTAssertEqual(try ifacSignature(transport).hexString, pythonSignature)
  }
}
