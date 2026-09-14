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

/// What the one concrete client transport answers without a link behind it.
final class RNGitLinkTransportTests: XCTestCase {

  private var directory = ""
  private var stack: Reticulum!
  private var transport: RNGitLinkTransport!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = NSTemporaryDirectory() + "/rngit-transport-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    stack = Reticulum(configuration: .init(storagePath: URL(fileURLWithPath: directory)))
    transport = RNGitLinkTransport(reticulum: stack, identity: Identity(), directory: directory)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(atPath: directory)
    try super.tearDownWithError()
  }

  func testTheTwoTimeoutsMatchTheReference() {
    XCTAssertEqual(RNGitLinkTransport.pathTimeout, 15)
    XCTAssertEqual(RNGitLinkTransport.linkTimeout, 15)
  }

  func testTheLinkTimeoutIsTheFloorWhereTheLinkItselfAsksForNoLonger() {
    XCTAssertEqual(RNGitLinkTransport.wait(for: 5), 15)
    XCTAssertEqual(RNGitLinkTransport.wait(for: 30), 30)
  }

  func testThePathTimeoutIsTheFloorWhereTheStackAsksForNoLonger() {
    XCTAssertEqual(stack.getMediumPathTimeout(), 0)
    XCTAssertEqual(transport.mediumPathTimeout(), 15)
  }

  func testARequestSentOverNoLinkComesBackWithNothing() {
    let answer = transport.request(.list, .nil, timeout: 1, progress: nil)
    XCTAssertEqual(answer.result, .none)
    XCTAssertNil(answer.metadata)
  }

  func testTearingDownWithoutALinkDoesNothing() {
    transport.teardown()
    XCTAssertEqual(transport.request(.list, .nil, timeout: 1, progress: nil).result, .none)
  }

  func testAnUnknownDestinationRecallsNoIdentity() {
    XCTAssertNil(transport.recallIdentity(for: Data(repeating: 0xAA, count: 16)))
  }
}
