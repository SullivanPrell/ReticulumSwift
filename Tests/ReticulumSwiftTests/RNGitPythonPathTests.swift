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

/// A path taken apart as Python RNS 1.5.4's `os.path` takes it apart.
final class RNGitPythonPathTests: XCTestCase {

  /// Each path, the root and extension `os.path.splitext` parts it into, and what
  /// `os.path.basename` answers for it.
  private static let recorded: [(String, String, String, String)] = [
    ("logo.png", "logo", ".png", "logo.png"),
    ("LOGO.PNG", "LOGO", ".PNG", "LOGO.PNG"),
    ("src/logo.png", "src/logo", ".png", "logo.png"),
    (".png", ".png", "", ".png"),
    ("dir/.png", "dir/.png", "", ".png"),
    ("..png", "..png", "", "..png"),
    ("a..png", "a.", ".png", "a..png"),
    ("a.b/c", "a.b/c", "", "c"),
    ("a.b/", "a.b/", "", ""),
    ("archive.tar.gz", "archive.tar", ".gz", "archive.tar.gz"),
    ("noext", "noext", "", "noext"),
    ("dir.v1/file", "dir.v1/file", "", "file"),
    (".hidden.jpg", ".hidden", ".jpg", ".hidden.jpg"),
    ("a/b/...", "a/b/...", "", "..."),
    ("trailing.", "trailing", ".", "trailing."),
    ("x.JPeG", "x", ".JPeG", "x.JPeG"),
    ("/abs/y.gif", "/abs/y", ".gif", "y.gif"),
    ("a.b.c/d.e", "a.b.c/d", ".e", "d.e"),
  ]

  /// A path parts into a root and an extension as `os.path.splitext` parts it: at the last dot
  /// after the last separator, unless nothing but dots comes before that dot.
  func testAPathPartsAtItsExtensionAsTheReferencePartsIt() {
    for (path, root, pathExtension, _) in Self.recorded {
      let parted = path.pythonSplitExtension
      XCTAssertEqual(parted.root, root, path)
      XCTAssertEqual(parted.pathExtension, pathExtension, path)
    }
  }

  /// A path's last component is what follows its last separator, as `os.path.basename` has it.
  func testAPathsLastComponentIsWhatTheReferenceAnswers() {
    for (path, _, _, basename) in Self.recorded {
      XCTAssertEqual(path.pythonBasename, basename, path)
    }
  }

  /// A separator is found at the scalar, so one a combining mark follows still separates.
  func testASeparatorACombiningMarkFollowsStillSeparates() {
    XCTAssertEqual("a/\u{301}b.png".pythonBasename, "\u{301}b.png")
    XCTAssertEqual("a.b/\u{301}c".pythonSplitExtension.pathExtension, "")
  }
}
