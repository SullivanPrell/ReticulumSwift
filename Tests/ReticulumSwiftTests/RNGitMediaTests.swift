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

/// The WebP conversion a node runs media through before serving it.
final class RNGitMediaTests: XCTestCase {

  /// The first 30 bytes of a lossy WebP file, which `cwebp` wrote from a 37 by 23 image.
  private static let lossy =
    "52494646200200005745425056503820140200 00300f009d012a2500 1700"
    .replacingOccurrences(of: " ", with: "")

  /// The first 30 bytes of a lossless WebP file, which `cwebp -lossless` wrote from the same
  /// 37 by 23 image.
  private static let lossless =
    "52494646b2000000574542505650384ca5000000 2f2480050060 9cd8b693"
    .replacingOccurrences(of: " ", with: "")

  /// The first 30 bytes of an extended WebP file, which `cwebp` wrote from a 53 by 19 image
  /// carrying an alpha channel.
  private static let extended =
    "5249464674000000574542505650385800000000 10000000340000 120000"
    .replacingOccurrences(of: " ", with: "")

  /// A directory of its own, removed when the test ends.
  private func makeDirectory() throws -> String {
    let path = NSTemporaryDirectory() + "/rngit-media-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
    return path
  }

  /// A lookup answering for the names in `names` and nothing else.
  private func onPath(_ names: String...) -> (String) -> Bool {
    let found = Set(names)
    return { found.contains($0) }
  }

  // MARK: Reading a header

  /// The size a WebP header names, for each of the three shapes a header comes in.
  func testTheHeaderOfAWebPFileNamesItsSize() {
    XCTAssertEqual(
      RNGitMedia.webPSize(Data(hex: Self.lossy)!).map { [$0.width, $0.height] }, [37, 23])
    XCTAssertEqual(
      RNGitMedia.webPSize(Data(hex: Self.lossless)!).map { [$0.width, $0.height] }, [37, 23])
    XCTAssertEqual(
      RNGitMedia.webPSize(Data(hex: Self.extended)!).map { [$0.width, $0.height] }, [53, 19])
  }

  /// What is not a WebP header names no size.
  func testWhatIsNotAWebPHeaderNamesNoSize() {
    var short = Data(hex: Self.lossy)!
    short.removeLast()
    XCTAssertNil(RNGitMedia.webPSize(short))

    var notRiff = Data(hex: Self.lossy)!
    notRiff[0] = UInt8(ascii: "X")
    XCTAssertNil(RNGitMedia.webPSize(notRiff))

    var notWebP = Data(hex: Self.lossy)!
    notWebP[8] = UInt8(ascii: "X")
    XCTAssertNil(RNGitMedia.webPSize(notWebP))

    var unknownChunk = Data(hex: Self.lossy)!
    unknownChunk[14] = UInt8(ascii: "9")
    XCTAssertNil(RNGitMedia.webPSize(unknownChunk))

    var noWidth = Data(hex: Self.lossy)!
    noWidth[26] = 0
    noWidth[27] = 0
    XCTAssertNil(RNGitMedia.webPSize(noWidth))
  }

  /// A file is taken for a WebP file where its first bytes say so, and nothing else is.
  func testAFileIsAWebPFileWhereItsFirstBytesSaySo() throws {
    let directory = try makeDirectory()
    let image = directory + "/image.webp"
    let text = directory + "/notes.txt"
    XCTAssertTrue(
      FileManager.default.createFile(atPath: image, contents: Data(hex: Self.lossless)!))
    XCTAssertTrue(FileManager.default.createFile(atPath: text, contents: Data("hello".utf8)))

    XCTAssertTrue(RNGitMedia.isWebP(at: image))
    XCTAssertFalse(RNGitMedia.isWebP(at: text))
    XCTAssertFalse(RNGitMedia.isWebP(at: directory + "/nothing.webp"))
  }

  // MARK: Picking a backend

  /// Every backend is reported on, whether or not it stands on the search path.
  func testEveryBackendIsReportedOnByName() {
    let reported = RNGitMedia.availableBackends(found: onPath("gm", "avconv"))
    XCTAssertEqual(reported.map(\.name), ["magick", "convert", "gm", "ffmpeg", "avconv"])
    XCTAssertEqual(reported.map(\.available), [false, false, true, false, true])
  }

  /// The backend picked is the first on the list that stands on the search path.
  func testTheFirstBackendOnThePathIsThePickedOne() {
    XCTAssertEqual(
      RNGitMedia.backend(found: onPath("magick", "convert", "gm", "ffmpeg", "avconv"))?.name,
      "magick")
    XCTAssertEqual(RNGitMedia.backend(found: onPath("ffmpeg", "avconv"))?.name, "ffmpeg")
    XCTAssertNil(RNGitMedia.backend(found: onPath()))
  }

  /// A forced backend is the only one tried, and one that is not there leaves nothing to run.
  func testAForcedBackendIsTheOnlyOneTried() {
    XCTAssertEqual(RNGitMedia.backend(forced: "gm", found: onPath("magick", "gm"))?.name, "gm")
    XCTAssertNil(RNGitMedia.backend(forced: "gm", found: onPath("magick")))
    XCTAssertNil(RNGitMedia.backend(forced: "cwebp", found: onPath("cwebp", "magick")))
  }

  /// The backend that last worked is tried before the rest, and the order stands where it is gone.
  func testTheBackendThatLastWorkedIsTriedFirst() {
    let all = onPath("magick", "convert", "gm", "ffmpeg", "avconv")
    XCTAssertEqual(RNGitMedia.backend(preferring: "ffmpeg", found: all)?.name, "ffmpeg")
    XCTAssertEqual(
      RNGitMedia.backend(preferring: "ffmpeg", found: onPath("convert", "gm"))?.name, "convert")
  }

  // MARK: What a backend is asked for

  /// What each backend is run as, for each quality and size a run can ask for.
  ///
  /// Recorded from Python RNS 1.5.4, one row per pair the two options can be given as, including
  /// the ones that are refused: a quality outside one to a hundred, and a size below one pixel.
  private static let recorded: [(backend: String, quality: Int?, dimension: Int?, argv: [String])] =
    [
      ("magick", nil, nil, ["magick", "-", "webp:-"]),
      ("magick", nil, -5, ["magick", "-", "webp:-"]),
      ("magick", nil, 0, ["magick", "-", "webp:-"]),
      ("magick", nil, 1, ["magick", "-", "-resize", "1x1>", "webp:-"]),
      ("magick", nil, 640, ["magick", "-", "-resize", "640x640>", "webp:-"]),
      ("magick", 0, nil, ["magick", "-", "-quality", "1", "webp:-"]),
      ("magick", 0, -5, ["magick", "-", "-quality", "1", "webp:-"]),
      ("magick", 0, 0, ["magick", "-", "-quality", "1", "webp:-"]),
      ("magick", 0, 1, ["magick", "-", "-quality", "1", "-resize", "1x1>", "webp:-"]),
      ("magick", 0, 640, ["magick", "-", "-quality", "1", "-resize", "640x640>", "webp:-"]),
      ("magick", 1, nil, ["magick", "-", "-quality", "1", "webp:-"]),
      ("magick", 1, -5, ["magick", "-", "-quality", "1", "webp:-"]),
      ("magick", 1, 0, ["magick", "-", "-quality", "1", "webp:-"]),
      ("magick", 1, 1, ["magick", "-", "-quality", "1", "-resize", "1x1>", "webp:-"]),
      ("magick", 1, 640, ["magick", "-", "-quality", "1", "-resize", "640x640>", "webp:-"]),
      ("magick", 70, nil, ["magick", "-", "-quality", "70", "webp:-"]),
      ("magick", 70, -5, ["magick", "-", "-quality", "70", "webp:-"]),
      ("magick", 70, 0, ["magick", "-", "-quality", "70", "webp:-"]),
      ("magick", 70, 1, ["magick", "-", "-quality", "70", "-resize", "1x1>", "webp:-"]),
      ("magick", 70, 640, ["magick", "-", "-quality", "70", "-resize", "640x640>", "webp:-"]),
      ("magick", 85, nil, ["magick", "-", "-quality", "85", "webp:-"]),
      ("magick", 85, -5, ["magick", "-", "-quality", "85", "webp:-"]),
      ("magick", 85, 0, ["magick", "-", "-quality", "85", "webp:-"]),
      ("magick", 85, 1, ["magick", "-", "-quality", "85", "-resize", "1x1>", "webp:-"]),
      ("magick", 85, 640, ["magick", "-", "-quality", "85", "-resize", "640x640>", "webp:-"]),
      ("magick", 100, nil, ["magick", "-", "-quality", "100", "webp:-"]),
      ("magick", 100, -5, ["magick", "-", "-quality", "100", "webp:-"]),
      ("magick", 100, 0, ["magick", "-", "-quality", "100", "webp:-"]),
      ("magick", 100, 1, ["magick", "-", "-quality", "100", "-resize", "1x1>", "webp:-"]),
      ("magick", 100, 640, ["magick", "-", "-quality", "100", "-resize", "640x640>", "webp:-"]),
      ("magick", 101, nil, ["magick", "-", "-quality", "100", "webp:-"]),
      ("magick", 101, -5, ["magick", "-", "-quality", "100", "webp:-"]),
      ("magick", 101, 0, ["magick", "-", "-quality", "100", "webp:-"]),
      ("magick", 101, 1, ["magick", "-", "-quality", "100", "-resize", "1x1>", "webp:-"]),
      ("magick", 101, 640, ["magick", "-", "-quality", "100", "-resize", "640x640>", "webp:-"]),
      ("convert", nil, nil, ["convert", "-", "webp:-"]),
      ("convert", nil, -5, ["convert", "-", "webp:-"]),
      ("convert", nil, 0, ["convert", "-", "webp:-"]),
      ("convert", nil, 1, ["convert", "-", "-resize", "1x1>", "webp:-"]),
      ("convert", nil, 640, ["convert", "-", "-resize", "640x640>", "webp:-"]),
      ("convert", 0, nil, ["convert", "-", "-quality", "1", "webp:-"]),
      ("convert", 0, -5, ["convert", "-", "-quality", "1", "webp:-"]),
      ("convert", 0, 0, ["convert", "-", "-quality", "1", "webp:-"]),
      ("convert", 0, 1, ["convert", "-", "-quality", "1", "-resize", "1x1>", "webp:-"]),
      ("convert", 0, 640, ["convert", "-", "-quality", "1", "-resize", "640x640>", "webp:-"]),
      ("convert", 1, nil, ["convert", "-", "-quality", "1", "webp:-"]),
      ("convert", 1, -5, ["convert", "-", "-quality", "1", "webp:-"]),
      ("convert", 1, 0, ["convert", "-", "-quality", "1", "webp:-"]),
      ("convert", 1, 1, ["convert", "-", "-quality", "1", "-resize", "1x1>", "webp:-"]),
      ("convert", 1, 640, ["convert", "-", "-quality", "1", "-resize", "640x640>", "webp:-"]),
      ("convert", 70, nil, ["convert", "-", "-quality", "70", "webp:-"]),
      ("convert", 70, -5, ["convert", "-", "-quality", "70", "webp:-"]),
      ("convert", 70, 0, ["convert", "-", "-quality", "70", "webp:-"]),
      ("convert", 70, 1, ["convert", "-", "-quality", "70", "-resize", "1x1>", "webp:-"]),
      ("convert", 70, 640, ["convert", "-", "-quality", "70", "-resize", "640x640>", "webp:-"]),
      ("convert", 85, nil, ["convert", "-", "-quality", "85", "webp:-"]),
      ("convert", 85, -5, ["convert", "-", "-quality", "85", "webp:-"]),
      ("convert", 85, 0, ["convert", "-", "-quality", "85", "webp:-"]),
      ("convert", 85, 1, ["convert", "-", "-quality", "85", "-resize", "1x1>", "webp:-"]),
      ("convert", 85, 640, ["convert", "-", "-quality", "85", "-resize", "640x640>", "webp:-"]),
      ("convert", 100, nil, ["convert", "-", "-quality", "100", "webp:-"]),
      ("convert", 100, -5, ["convert", "-", "-quality", "100", "webp:-"]),
      ("convert", 100, 0, ["convert", "-", "-quality", "100", "webp:-"]),
      ("convert", 100, 1, ["convert", "-", "-quality", "100", "-resize", "1x1>", "webp:-"]),
      ("convert", 100, 640, ["convert", "-", "-quality", "100", "-resize", "640x640>", "webp:-"]),
      ("convert", 101, nil, ["convert", "-", "-quality", "100", "webp:-"]),
      ("convert", 101, -5, ["convert", "-", "-quality", "100", "webp:-"]),
      ("convert", 101, 0, ["convert", "-", "-quality", "100", "webp:-"]),
      ("convert", 101, 1, ["convert", "-", "-quality", "100", "-resize", "1x1>", "webp:-"]),
      ("convert", 101, 640, ["convert", "-", "-quality", "100", "-resize", "640x640>", "webp:-"]),
      ("gm", nil, nil, ["gm", "convert", "-", "webp:-"]),
      ("gm", nil, -5, ["gm", "convert", "-", "webp:-"]),
      ("gm", nil, 0, ["gm", "convert", "-", "webp:-"]),
      ("gm", nil, 1, ["gm", "convert", "-", "-resize", "1x1>", "webp:-"]),
      ("gm", nil, 640, ["gm", "convert", "-", "-resize", "640x640>", "webp:-"]),
      ("gm", 0, nil, ["gm", "convert", "-", "-quality", "1", "webp:-"]),
      ("gm", 0, -5, ["gm", "convert", "-", "-quality", "1", "webp:-"]),
      ("gm", 0, 0, ["gm", "convert", "-", "-quality", "1", "webp:-"]),
      ("gm", 0, 1, ["gm", "convert", "-", "-quality", "1", "-resize", "1x1>", "webp:-"]),
      ("gm", 0, 640, ["gm", "convert", "-", "-quality", "1", "-resize", "640x640>", "webp:-"]),
      ("gm", 1, nil, ["gm", "convert", "-", "-quality", "1", "webp:-"]),
      ("gm", 1, -5, ["gm", "convert", "-", "-quality", "1", "webp:-"]),
      ("gm", 1, 0, ["gm", "convert", "-", "-quality", "1", "webp:-"]),
      ("gm", 1, 1, ["gm", "convert", "-", "-quality", "1", "-resize", "1x1>", "webp:-"]),
      ("gm", 1, 640, ["gm", "convert", "-", "-quality", "1", "-resize", "640x640>", "webp:-"]),
      ("gm", 70, nil, ["gm", "convert", "-", "-quality", "70", "webp:-"]),
      ("gm", 70, -5, ["gm", "convert", "-", "-quality", "70", "webp:-"]),
      ("gm", 70, 0, ["gm", "convert", "-", "-quality", "70", "webp:-"]),
      ("gm", 70, 1, ["gm", "convert", "-", "-quality", "70", "-resize", "1x1>", "webp:-"]),
      ("gm", 70, 640, ["gm", "convert", "-", "-quality", "70", "-resize", "640x640>", "webp:-"]),
      ("gm", 85, nil, ["gm", "convert", "-", "-quality", "85", "webp:-"]),
      ("gm", 85, -5, ["gm", "convert", "-", "-quality", "85", "webp:-"]),
      ("gm", 85, 0, ["gm", "convert", "-", "-quality", "85", "webp:-"]),
      ("gm", 85, 1, ["gm", "convert", "-", "-quality", "85", "-resize", "1x1>", "webp:-"]),
      ("gm", 85, 640, ["gm", "convert", "-", "-quality", "85", "-resize", "640x640>", "webp:-"]),
      ("gm", 100, nil, ["gm", "convert", "-", "-quality", "100", "webp:-"]),
      ("gm", 100, -5, ["gm", "convert", "-", "-quality", "100", "webp:-"]),
      ("gm", 100, 0, ["gm", "convert", "-", "-quality", "100", "webp:-"]),
      ("gm", 100, 1, ["gm", "convert", "-", "-quality", "100", "-resize", "1x1>", "webp:-"]),
      ("gm", 100, 640, ["gm", "convert", "-", "-quality", "100", "-resize", "640x640>", "webp:-"]),
      ("gm", 101, nil, ["gm", "convert", "-", "-quality", "100", "webp:-"]),
      ("gm", 101, -5, ["gm", "convert", "-", "-quality", "100", "webp:-"]),
      ("gm", 101, 0, ["gm", "convert", "-", "-quality", "100", "webp:-"]),
      ("gm", 101, 1, ["gm", "convert", "-", "-quality", "100", "-resize", "1x1>", "webp:-"]),
      ("gm", 101, 640, ["gm", "convert", "-", "-quality", "100", "-resize", "640x640>", "webp:-"]),
      (
        "ffmpeg", nil, nil,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", nil, -5,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", nil, 0, ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", nil, 1,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", nil, 640,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 0, nil,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 0, -5,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 0, 0,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 0, 1,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 0, 640,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 1, nil,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 1, -5,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 1, 0,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 1, 1,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 1, 640,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 70, nil,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 70, -5,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 70, 0,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 70, 1,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 70, 640,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 85, nil,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 85, -5,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 85, 0,
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-f", "webp", "pipe:1"]
      ),
      (
        "ffmpeg", 85, 1,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 85, 640,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 100, nil,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 100, -5,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 100, 0,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 100, 1,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 100, 640,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 101, nil,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 101, -5,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 101, 0,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 101, 1,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "ffmpeg", 101, 640,
        [
          "ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", nil, nil,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", nil, -5,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", nil, 0, ["avconv", "-y", "-loglevel", "error", "-i", "-", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", nil, 1,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", nil, 640,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 0, nil,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 0, -5,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 0, 0,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 0, 1,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 0, 640,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 1, nil,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 1, -5,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 1, 0,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 1, 1,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 1, 640,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "1", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 70, nil,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 70, -5,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 70, 0,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 70, 1,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 70, 640,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "70", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 85, nil,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 85, -5,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 85, 0,
        ["avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-f", "webp", "pipe:1"]
      ),
      (
        "avconv", 85, 1,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 85, 640,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "85", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 100, nil,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 100, -5,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 100, 0,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 100, 1,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 100, 640,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 101, nil,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 101, -5,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 101, 0,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 101, 1,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-vf",
          "scale='min(iw,1)':'min(ih,1)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
      (
        "avconv", 101, 640,
        [
          "avconv", "-y", "-loglevel", "error", "-i", "-", "-quality", "100", "-vf",
          "scale='min(iw,640)':'min(ih,640)':force_original_aspect_ratio=decrease", "-f", "webp",
          "pipe:1",
        ]
      ),
    ]

  /// Every backend runs the words it was recorded running, for every quality and size.
  func testEveryBackendRunsTheWordsItWasRecordedRunning() throws {
    for row in Self.recorded {
      let backend = try XCTUnwrap(RNGitMedia.backend(found: onPath(row.backend)), row.backend)
      let asked = RNGitMedia.encoding(
        backend, quality: row.quality, maxDimension: row.dimension)
      XCTAssertEqual(
        asked.arguments, row.argv,
        "\(row.backend) quality \(row.quality as Any) size \(row.dimension as Any)")
      XCTAssertEqual(asked.name, row.backend)
    }
  }

  // MARK: What a run is logged as

  /// A run that converted is complained about with nothing.
  func testARunThatConvertedIsComplainedAboutWithNothing() {
    XCTAssertNil(RNGitMedia.complaint(about: .converted, through: "magick", after: 8))
  }

  /// What each way a run can end is written to the log as.
  func testWhatEachWayARunCanEndIsWrittenToTheLogAs() {
    XCTAssertEqual(
      RNGitMedia.complaint(about: .timedOut, through: "gm", after: 8),
      "Media conversion via gm timed out after 8 seconds")
    XCTAssertEqual(
      RNGitMedia.complaint(about: .failed(encoder: "", input: ""), through: "gm", after: 8),
      "Media conversion via gm failed.")
    XCTAssertEqual(
      RNGitMedia.complaint(
        about: .failed(encoder: "no decode delegate", input: "not a git object"), through: "gm",
        after: 8),
      "Media conversion via gm failed. Encoder: no decode delegate Input: not a git object")
    XCTAssertEqual(
      RNGitMedia.complaint(about: .couldNotRun("nothing there"), through: "gm", after: 8),
      "Error during media conversion: nothing there")
  }

  // MARK: Converting

  /// A converter answering what its script says, recording everything it was asked to run.
  private final class Converter: RNGitMediaConverter, @unchecked Sendable {
    let outcome: RNGitMediaOutcome
    let writing: Data?
    var produced: [[String]] = []
    var read: [String] = []
    var encodings: [[String]] = []
    var directories: [String?] = []
    var timeouts: [TimeInterval] = []

    init(outcome: RNGitMediaOutcome = .converted, writing: Data? = nil) {
      self.outcome = outcome
      self.writing = writing
    }

    func convert(
      producing: [String], in directory: String?, through encoding: [String], to path: String,
      within timeout: TimeInterval
    ) -> RNGitMediaOutcome {
      produced.append(producing)
      directories.append(directory)
      return record(encoding, to: path, within: timeout)
    }

    func convert(
      reading source: String, through encoding: [String], to path: String,
      within timeout: TimeInterval
    ) -> RNGitMediaOutcome {
      read.append(source)
      return record(encoding, to: path, within: timeout)
    }

    private func record(_ encoding: [String], to path: String, within timeout: TimeInterval)
      -> RNGitMediaOutcome
    {
      encodings.append(encoding)
      timeouts.append(timeout)
      if let writing { FileManager.default.createFile(atPath: path, contents: writing) }
      return outcome
    }
  }

  /// What the encoder runs is the backend it picked, asked for what the caller asked for.
  func testWhatTheEncoderRunsIsTheBackendItPickedAskedForWhatWasAskedOfIt() throws {
    let directory = try makeDirectory()
    let converter = Converter(writing: Data(hex: Self.lossy)!)
    let encoder = RNGitMediaEncoder(
      converter: converter, forced: nil, found: onPath("magick", "ffmpeg"))

    XCTAssertTrue(
      encoder.convert(
        producedBy: ["git", "show", "HEAD:logo.png"], in: "/repo",
        to: directory + "/out.webp", quality: 70, maxDimension: 640))
    XCTAssertEqual(converter.produced, [["git", "show", "HEAD:logo.png"]])
    XCTAssertEqual(converter.directories, ["/repo"])
    XCTAssertEqual(
      converter.encodings, [["magick", "-", "-quality", "70", "-resize", "640x640>", "webp:-"]])
    XCTAssertEqual(converter.timeouts, [8])
  }

  /// A run whose output is no WebP file is no conversion.
  func testARunWhoseOutputIsNoWebPFileIsNoConversion() throws {
    let directory = try makeDirectory()
    let converter = Converter(writing: Data("not an image".utf8))
    let encoder = RNGitMediaEncoder(converter: converter, forced: nil, found: onPath("magick"))
    XCTAssertFalse(
      encoder.convert(producedBy: ["git", "show", "HEAD:logo.png"], to: directory + "/out.webp"))
  }

  /// A run that gave up is no conversion, and the file it left is taken away.
  func testARunThatGaveUpLeavesNoFileBehind() throws {
    let directory = try makeDirectory()
    let converter = Converter(outcome: .timedOut, writing: Data(hex: Self.lossy)!)
    let encoder = RNGitMediaEncoder(converter: converter, forced: nil, found: onPath("magick"))
    XCTAssertFalse(
      encoder.convert(producedBy: ["git", "show", "HEAD:logo.png"], to: directory + "/out.webp"))
  }

  /// Where no backend stands on the system, nothing is run at all.
  func testWhereNoBackendStandsOnTheSystemNothingIsRun() throws {
    let directory = try makeDirectory()
    let converter = Converter(writing: Data(hex: Self.lossy)!)
    let encoder = RNGitMediaEncoder(converter: converter, forced: nil, found: onPath())
    XCTAssertFalse(
      encoder.convert(producedBy: ["git", "show", "HEAD:logo.png"], to: directory + "/out.webp"))
    XCTAssertTrue(converter.encodings.isEmpty)
  }

  /// A file the encoder converted is left where the encoder says it is, and taken away where the
  /// conversion did not come off.
  func testAFileTheEncoderConvertedIsLeftWhereItSaysItIs() throws {
    let directory = try makeDirectory()
    let source = directory + "/logo.png"
    XCTAssertTrue(FileManager.default.createFile(atPath: source, contents: Data("png".utf8)))

    let converter = Converter(writing: Data(hex: Self.lossless)!)
    let encoder = RNGitMediaEncoder(converter: converter, forced: nil, found: onPath("magick"))
    let converted = try XCTUnwrap(encoder.convert(file: source))
    XCTAssertEqual(converter.read, [source])
    XCTAssertEqual(
      converter.encodings, [["magick", "-", "-quality", "85", "webp:-"]])
    XCTAssertTrue(RNGitMedia.isWebP(at: converted))
    try? FileManager.default.removeItem(atPath: converted)

    let refused = Converter(outcome: .failed(encoder: "broken", input: ""), writing: Data())
    let stopping = RNGitMediaEncoder(converter: refused, forced: nil, found: onPath("magick"))
    XCTAssertNil(stopping.convert(file: source))
  }

  /// A file that is not there is not converted, and nothing is run for it.
  func testAFileThatIsNotThereIsNotConverted() throws {
    let directory = try makeDirectory()
    let converter = Converter(writing: Data(hex: Self.lossless)!)
    let encoder = RNGitMediaEncoder(converter: converter, forced: nil, found: onPath("magick"))
    XCTAssertNil(encoder.convert(file: directory + "/nothing.png"))
    XCTAssertTrue(converter.encodings.isEmpty)
  }
}
