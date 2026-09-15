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

/// The count a repository or a release has been thanked, as Python RNS 1.5.4 keeps it.
final class RNGitPageThanksTests: XCTestCase {

  /// The link identifiers the reference thanked with.
  private static let link = Data(0..<16)
  private static let otherLink = Data(16..<32)

  /// A scratch directory, removed when the test that made it ends.
  private func scratch() throws -> String {
    let directory = NSTemporaryDirectory() + "/rngit-thanks-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(atPath: directory) }
    return directory
  }

  /// What the thanks file at `path` holds, or nothing where it holds no count.
  private func onDisk(_ path: String) -> Int? {
    guard let contents = FileManager.default.contents(atPath: path),
      let decoded = try? MsgPack.decode(contents), case .map(let fields) = decoded
    else { return nil }
    return fields.first(where: { $0.0.asString == "count" })?.1.asInt
  }

  /// A repository's thanks are read, added to and read back as the reference did.
  func testRepositoryThanksMatchTheReference() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()
    let one = directory + "/one"
    let file = one + ".thanks"

    XCTAssertEqual(thanks.repository(at: one), 0, "firstRead")
    XCTAssertEqual(onDisk(file), 0, "firstRead on disk")
    XCTAssertEqual(thanks.repository(at: one), 0, "secondRead")
    XCTAssertEqual(onDisk(file), 0, "secondRead on disk")
    XCTAssertEqual(thanks.repository(at: one, thankedBy: Self.link), 1, "firstAdd")
    XCTAssertEqual(onDisk(file), 1, "firstAdd on disk")
    XCTAssertEqual(thanks.repository(at: one, thankedBy: Self.link), 1, "sameLinkAgain")
    XCTAssertEqual(onDisk(file), 1, "sameLinkAgain on disk")
    XCTAssertEqual(thanks.repository(at: one, thankedBy: Self.otherLink), 2, "otherLink")
    XCTAssertEqual(onDisk(file), 2, "otherLink on disk")
    XCTAssertEqual(thanks.repository(at: one), 2, "readAfter")
    XCTAssertEqual(onDisk(file), 2, "readAfter on disk")
  }

  /// A first thanks is written but not returned, as the reference wrote and returned it.
  func testAFirstThanksIsWrittenButNotReturned() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()
    let two = directory + "/two"
    let file = two + ".thanks"

    XCTAssertEqual(thanks.repository(at: two, thankedBy: Self.link), 0, "addToAbsent")
    XCTAssertEqual(onDisk(file), 1, "addToAbsent on disk")
    XCTAssertEqual(thanks.repository(at: two), 1, "readTheAbsentBack")
    XCTAssertEqual(onDisk(file), 1, "readTheAbsentBack on disk")
  }

  /// A thanks file naming something other than a count is left as it stands.
  func testAThanksFileWithoutACountIsLeftAlone() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()
    let three = directory + "/three"
    let file = three + ".thanks"
    try MsgPack.encode(.map([(.string("total"), .int(9))])).write(to: URL(fileURLWithPath: file))

    XCTAssertEqual(thanks.repository(at: three), 0, "wrongKey")
    XCTAssertEqual(onDisk(file), nil, "wrongKey on disk")
  }

  /// A thanks file that does not read back at all is left as it stands.
  func testAnUnreadableThanksFileIsLeftAlone() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()
    let four = directory + "/four"
    let file = four + ".thanks"
    try Data([0x6e, 0x6f, 0x74, 0x20, 0xff, 0xfe]).write(to: URL(fileURLWithPath: file))

    XCTAssertEqual(thanks.repository(at: four), 0, "unreadableFile")
    XCTAssertEqual(onDisk(file), nil, "unreadableFile on disk")
  }

  /// A release's thanks are read, added to and read back as the reference did.
  func testReleaseThanksMatchTheReference() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()
    let release = directory + "/rel-one"
    try FileManager.default.createDirectory(atPath: release, withIntermediateDirectories: true)
    let file = release + "/THANKS"

    XCTAssertEqual(thanks.release(at: release), 0, "releaseFirstRead")
    XCTAssertEqual(onDisk(file), 0, "releaseFirstRead on disk")
    XCTAssertEqual(thanks.release(at: release, thankedBy: Self.link), 1, "releaseFirstAdd")
    XCTAssertEqual(onDisk(file), 1, "releaseFirstAdd on disk")
    XCTAssertEqual(thanks.release(at: release, thankedBy: Self.link), 1, "releaseSameLinkAgain")
    XCTAssertEqual(onDisk(file), 1, "releaseSameLinkAgain on disk")
    XCTAssertEqual(thanks.release(at: release, thankedBy: Self.otherLink), 2, "releaseOtherLink")
    XCTAssertEqual(onDisk(file), 2, "releaseOtherLink on disk")
  }

  /// A release whose directory is not there is thanked without a count reaching disk.
  func testThanksForAReleaseThatIsNotThereReachNoFile() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()
    let missing = directory + "/nosuchdirectory"
    let file = missing + "/THANKS"

    XCTAssertEqual(thanks.release(at: missing), 0, "releaseInMissingDirectory")
    XCTAssertEqual(onDisk(file), nil, "releaseInMissingDirectory on disk")
  }

  /// A link that thanks one path may thank another, since the pair is what is remembered.
  func testTheSameLinkMayThankTwoDifferentPaths() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()
    let one = directory + "/one"
    let two = directory + "/two"

    XCTAssertEqual(thanks.repository(at: one), 0, "twoPathsReadA")
    XCTAssertEqual(thanks.repository(at: two), 0, "twoPathsReadB")
    XCTAssertEqual(thanks.repository(at: one, thankedBy: Self.link), 1, "twoPathsAddA")
    XCTAssertEqual(thanks.repository(at: two, thankedBy: Self.link), 1, "twoPathsAddB")
  }

  /// Only the last two hundred and fifty-six additions are remembered.
  func testAnAdditionIsForgottenOnceTwoHundredAndFiftySixCameAfterIt() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()
    let one = directory + "/one"

    XCTAssertEqual(thanks.repository(at: one, thankedBy: Self.link), 0, "firstAdd")
    for index in 0..<RNGitPageThanks.rememberedAdditions {
      _ = thanks.repository(at: one, thankedBy: Data([UInt8(index % 256), 0xaa]))
    }
    XCTAssertEqual(thanks.repository(at: one), 257, "afterTwoFiftySix")
    XCTAssertEqual(thanks.repository(at: one, thankedBy: Self.link), 258, "forgottenLinkAgain")
  }

  /// A release's count is kept in a file named as the reference names it.
  func testAReleaseCountIsKeptInTheFileTheReferenceNames() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()
    let release = directory + "/rel-named"
    try FileManager.default.createDirectory(atPath: release, withIntermediateDirectories: true)

    _ = thanks.release(at: release, thankedBy: Self.link)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: release), ["THANKS"])
  }

  /// A repository's count is kept in a file named as the reference names it.
  func testARepositoryCountIsKeptInTheFileTheReferenceNames() throws {
    let directory = try scratch()
    let thanks = RNGitPageThanks()

    _ = thanks.repository(at: directory + "/named", thankedBy: Self.link)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory), ["named.thanks"])
  }
}
