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
import XCTest

@testable import ReticulumSwift

/// The directories a node builds its work in, as Python RNS 1.5.4 builds them.
final class RNGitTemporaryDirectoriesTests: XCTestCase {

  private var root = ""

  override func setUpWithError() throws {
    root = NSTemporaryDirectory() + "/rngit-temporaries-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(atPath: root)
  }

  /// A directory the node makes is reachable only by the user that made it.
  func testDirectoryIsReachableOnlyByItsOwner() throws {
    var temporaries = RNGitTemporaryDirectories(root: root)
    let made = try XCTUnwrap(temporaries.make(for: Data([0x01])))
    let attributes = try FileManager.default.attributesOfItem(atPath: made)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
  }

  /// A link asking twice holds both directories, and they are distinct.
  func testDirectoriesAccumulateForOneLink() throws {
    var temporaries = RNGitTemporaryDirectories(root: root)
    let link = Data([0x02])
    let first = try XCTUnwrap(temporaries.make(for: link))
    let second = try XCTUnwrap(temporaries.make(for: link))
    XCTAssertNotEqual(first, second)
    XCTAssertEqual(temporaries.held[link], [first, second])
  }

  /// A directory that cannot be made is answered as none, and nothing is held for it.
  func testUnmakeableDirectoryIsAnsweredAsNone() throws {
    let blocked = root + "/file"
    try Data().write(to: URL(fileURLWithPath: blocked))
    var temporaries = RNGitTemporaryDirectories(root: blocked)
    let link = Data([0x03])
    XCTAssertNil(temporaries.make(for: link))
    XCTAssertNil(temporaries.held[link])
  }

  /// Letting go of one directory a link holds removes that one and leaves the rest held.
  func testLettingGoOfOneDirectoryLeavesTheRestHeld() throws {
    var temporaries = RNGitTemporaryDirectories(root: root)
    let link = Data([0x04])
    let first = try XCTUnwrap(temporaries.make(for: link))
    let second = try XCTUnwrap(temporaries.make(for: link))

    temporaries.release(first, of: link)
    XCTAssertEqual(temporaries.held[link], [second])
    XCTAssertFalse(FileManager.default.fileExists(atPath: first))
    XCTAssertTrue(FileManager.default.fileExists(atPath: second))

    temporaries.release(second, of: link)
    XCTAssertNil(temporaries.held[link])
    XCTAssertFalse(FileManager.default.fileExists(atPath: second))
  }
}
