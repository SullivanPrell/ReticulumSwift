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

/// The reference and object-id checks an `rngit` node applies to a client's request.
///
/// A name that fails is not corrected, it is rejected, because these guard what reaches
/// `git` on the serving side.
final class GitReferenceNameTests: XCTestCase {

  /// An ordinary reference passes.
  func testOrdinaryReferenceIsAccepted() {
    XCTAssertEqual(GitReferenceNames.sanitise("refs/heads/main"), "refs/heads/main")
    XCTAssertEqual(GitReferenceNames.sanitise("refs/tags/v1.0.0"), "refs/tags/v1.0.0")
  }

  /// A reference must contain a separator and must not be shaped like an option or a path.
  func testShapeRulesAreEnforced() {
    for rejected in [
      "-refs/heads/main", "/refs/heads/main", "refs/heads/", "refs/heads/main.",
      "refs/heads/a b", "main", "refs/../heads", "refs/.hidden", "refs//heads",
      "refs\\heads",
    ] {
      XCTAssertNil(GitReferenceNames.sanitise(rejected), "\(rejected) must be rejected")
    }
  }

  /// A component ending in `.lock` is refused, because that is git's own lock suffix.
  func testLockComponentIsRefused() {
    XCTAssertNil(GitReferenceNames.sanitise("refs/heads/main.lock"))
    XCTAssertNil(GitReferenceNames.sanitise("refs/main.lock/x"))
    XCTAssertEqual(GitReferenceNames.sanitise("refs/heads/lock"), "refs/heads/lock")
  }

  /// The lower bound is code point 40, not the control range the comment names.
  ///
  /// `(` is 40 and passes; every punctuation mark below it, `'` and `&` and `!` among them,
  /// is refused along with the control characters.
  func testTheLowerBoundIsFortyNotThirtyTwo() {
    XCTAssertEqual(GitReferenceNames.sanitise("refs/heads/(x)"), "refs/heads/(x)")
    for rejected in ["refs/heads/it's", "refs/heads/a&b", "refs/heads/a!b", "refs/heads/a\u{01}b"] {
      XCTAssertNil(GitReferenceNames.sanitise(rejected), "\(rejected) must be rejected")
    }
  }

  /// The characters git itself reserves in a reference name are refused.
  func testGitReservedCharactersAreRefused() {
    for rejected in [
      "refs/heads/\u{7F}", "refs/heads/a~b", "refs/heads/a^b", "refs/heads/a:b",
      "refs/heads/a?b", "refs/heads/a*b", "refs/heads/a[b", "refs/heads/a@{b",
    ] {
      XCTAssertNil(GitReferenceNames.sanitise(rejected), "\(rejected) must be rejected")
    }
  }

  /// A list passes only when every entry does.
  func testAListIsAcceptedOnlyWhole() {
    XCTAssertEqual(
      GitReferenceNames.sanitise(["refs/heads/main", "refs/tags/v1"]),
      ["refs/heads/main", "refs/tags/v1"])
    XCTAssertNil(GitReferenceNames.sanitise(["refs/heads/main", "bad"]))
    XCTAssertEqual(GitReferenceNames.sanitise([String]()), [])
  }

  /// An object id is 40 hex characters or more, and nothing else.
  ///
  /// The length is checked, and then the hexadecimal is read.
  func testObjectIdMustBeHexAndFullLength() {
    let sha = String(repeating: "a", count: 40)
    XCTAssertEqual(GitReferenceNames.sanitiseObjectID(sha), sha)
    XCTAssertEqual(
      GitReferenceNames.sanitiseObjectID(String(repeating: "0", count: 64)),
      String(repeating: "0", count: 64))

    XCTAssertNil(GitReferenceNames.sanitiseObjectID(String(repeating: "a", count: 39)))
    XCTAssertNil(GitReferenceNames.sanitiseObjectID(String(repeating: "g", count: 40)))
    // `bytes.fromhex` needs whole bytes, so an odd length fails even at 41 characters.
    XCTAssertNil(GitReferenceNames.sanitiseObjectID(String(repeating: "a", count: 41)))
  }
}

extension GitReferenceNameTests {

  /// Only ASCII hex counts, matching `bytes.fromhex`.
  ///
  /// Swift's `hexDigitValue` also answers for the fullwidth forms, which `bytes.fromhex`
  /// refuses; an object id built from them must not pass.
  func testFullWidthDigitsAreNotHex() {
    XCTAssertNil(GitReferenceNames.sanitiseObjectID(String(repeating: "\u{FF41}", count: 40)))
    XCTAssertNil(GitReferenceNames.sanitiseObjectID(String(repeating: "\u{FF10}", count: 40)))
  }

  /// Whitespace separates bytes but cannot split one, as in `bytes.fromhex`.
  func testWhitespaceFollowsTheFromHexRule() {
    let spaced = String(repeating: "aa ", count: 20)
    XCTAssertEqual(GitReferenceNames.sanitiseObjectID(spaced), spaced)

    let split = String(repeating: "a a", count: 20)
    XCTAssertNil(GitReferenceNames.sanitiseObjectID(split))
  }

  /// The length floor counts code points, as `len` does.
  ///
  /// Python reads this as 42 characters and accepts it; `String.count` reads 39, because
  /// each `\r\n` is one grapheme.
  func testTheLengthFloorCountsCodePoints() {
    let sha = String(repeating: "aa", count: 18) + String(repeating: "\r\n", count: 3)
    XCTAssertEqual(sha.count, 39)
    XCTAssertEqual(GitReferenceNames.sanitiseObjectID(sha), sha)
  }
}
