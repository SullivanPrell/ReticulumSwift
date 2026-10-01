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

/// Every attribute `InterfaceState` holds lands in the box, on every conformer.
///
/// A conformer that declares its own stored property satisfies the protocol requirement with it,
/// so the `InterfaceState`-backed accessor in `extension Interface` never runs. The value then
/// never reaches `InterfaceState.inherit(from:)`, and a spawned interface starts from the default.
/// Python copies `recursive_prs`, `announces_from_internal`, `announces_to_internal` and
/// `announce_cap` onto each spawned client (RNS 1.5.5, `TCPInterface.py:639-642`).
final class InterfaceStateBackingTests: XCTestCase {

  func testEveryConformerKeepsItsAttributesInInterfaceState() throws {
    for iface in try InterfaceConformers.everyConcreteInterface() {
      let name = String(describing: type(of: iface))
      iface.announceCap = 0.07
      iface.announceRateTarget = 1234
      iface.announceRateGrace = 5
      iface.announceRatePenalty = 99
      iface.ingressControl = false
      iface.egressControl = true
      iface.ecPrFreq = 3.5
      iface.mode = .gateway
      iface.bootstrapOnly = true
      iface.recursivePrs = true
      iface.announcesFromInternal = false
      iface.announcesToInternal = true
      iface.gravity = 23

      let state = iface.interfaceState
      XCTAssertEqual(state.announceCap, 0.07, "\(name).announceCap")
      XCTAssertEqual(state.announceRateTarget, 1234, "\(name).announceRateTarget")
      XCTAssertEqual(state.announceRateGrace, 5, "\(name).announceRateGrace")
      XCTAssertEqual(state.announceRatePenalty, 99, "\(name).announceRatePenalty")
      XCTAssertFalse(state.ingressControl, "\(name).ingressControl")
      XCTAssertTrue(state.egressControl, "\(name).egressControl")
      XCTAssertEqual(state.ecPrFreq, 3.5, "\(name).ecPrFreq")
      XCTAssertEqual(state.mode, .gateway, "\(name).mode")
      XCTAssertTrue(state.bootstrapOnly, "\(name).bootstrapOnly")
      XCTAssertTrue(state.recursivePrs, "\(name).recursivePrs")
      XCTAssertFalse(state.announcesFromInternal, "\(name).announcesFromInternal")
      XCTAssertEqual(state.announcesToInternal, true, "\(name).announcesToInternal")
      XCTAssertEqual(state.gravity, 23, "\(name).gravity")
    }
  }
}
