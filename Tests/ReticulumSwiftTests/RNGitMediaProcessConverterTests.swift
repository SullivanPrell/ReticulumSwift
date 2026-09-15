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

/// The subprocesses a conversion is actually run as.
///
/// The programs here stand in for an image encoder, so what is under test is the wiring between
/// the two processes rather than any one encoder being installed.
final class RNGitMediaProcessConverterTests: XCTestCase {

  /// A directory of its own, removed when the test ends.
  private func makeDirectory() throws -> String {
    let path = NSTemporaryDirectory() + "/rngit-converter-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
    return path
  }

  /// What one process writes reaches the next, and what the second writes reaches the file.
  func testWhatOneProcessWritesReachesTheNextAndThenTheFile() throws {
    let path = try makeDirectory() + "/out"
    let outcome = RNGitMediaProcessConverter().convert(
      producing: ["printf", "hello"], in: nil, through: ["cat"], to: path, within: 8)

    XCTAssertEqual(outcome, .converted)
    XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "hello")
  }

  /// More than a pipe holds still reaches the file, so neither process is left waiting on the
  /// other.
  func testMoreThanAPipeHoldsStillReachesTheFile() throws {
    let path = try makeDirectory() + "/out"
    let outcome = RNGitMediaProcessConverter().convert(
      producing: ["head", "-c", "200000", "/dev/zero"], in: nil, through: ["cat"], to: path,
      within: 8)

    XCTAssertEqual(outcome, .converted)
    XCTAssertEqual(
      try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int, 200_000)
  }

  /// A process is run where it is told to be.
  func testAProcessIsRunWhereItIsToldToBe() throws {
    let directory = try makeDirectory()
    let path = directory + "/out"
    let outcome = RNGitMediaProcessConverter().convert(
      producing: ["pwd"], in: directory, through: ["cat"], to: path, within: 8)

    XCTAssertEqual(outcome, .converted)
    let written = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(
      in: .whitespacesAndNewlines)
    XCTAssertEqual(
      URL(fileURLWithPath: written).resolvingSymlinksInPath().path,
      URL(fileURLWithPath: directory).resolvingSymlinksInPath().path)
  }

  /// A run still going when its time is up is stopped, and says so.
  func testARunStillGoingWhenItsTimeIsUpIsStopped() throws {
    let path = try makeDirectory() + "/out"
    let started = Date()
    let outcome = RNGitMediaProcessConverter().convert(
      producing: ["sleep", "30"], in: nil, through: ["cat"], to: path, within: 0.3)

    XCTAssertEqual(outcome, .timedOut)
    XCTAssertLessThan(Date().timeIntervalSince(started), 10)
  }

  /// An encoder that returned a failure says so, carrying what both processes complained about.
  func testAnEncoderThatFailedCarriesWhatBothProcessesComplainedAbout() throws {
    let path = try makeDirectory() + "/out"
    let outcome = RNGitMediaProcessConverter().convert(
      producing: ["sh", "-c", "echo no such object >&2; exit 128"], in: nil,
      through: ["sh", "-c", "echo no decode delegate >&2; exit 1"], to: path, within: 8)

    XCTAssertEqual(
      outcome, .failed(encoder: "no decode delegate", input: "no such object"))
  }

  /// A program that is not there is not run.
  func testAProgramThatIsNotThereIsNotRun() throws {
    let path = try makeDirectory() + "/out"
    let outcome = RNGitMediaProcessConverter().convert(
      producing: ["/nonexistent/producer"], in: nil, through: ["cat"], to: path, within: 8)

    guard case .couldNotRun = outcome else { return XCTFail("\(outcome)") }
  }

  #if os(macOS)
  /// How many processes a converter waited for, counted from the single thread a test runs on.
  private final class Waits: @unchecked Sendable {
    var count = 0
  }

  /// A producer that could not be started is not waited for, as nothing was ever started.
  func testAProducerThatCouldNotBeStartedIsNotWaitedFor() throws {
    let path = try makeDirectory() + "/out"
    let waits = Waits()
    var converter = RNGitMediaProcessConverter()
    converter.waiting = { _ in waits.count += 1 }

    let outcome = converter.convert(
      producing: ["/nonexistent/producer"], in: nil, through: ["cat"], to: path, within: 8)

    guard case .couldNotRun = outcome else { return XCTFail("\(outcome)") }
    XCTAssertEqual(waits.count, 0)
  }

  /// Both processes of a run stopped because its time was up are waited for.
  func testBothProcessesOfARunStoppedAreWaitedFor() throws {
    let path = try makeDirectory() + "/out"
    let waits = Waits()
    var converter = RNGitMediaProcessConverter()
    converter.waiting = {
      $0.waitUntilExit()
      waits.count += 1
    }

    XCTAssertEqual(
      converter.convert(
        producing: ["sleep", "30"], in: nil, through: ["cat"], to: path, within: 0.3), .timedOut)
    XCTAssertEqual(waits.count, 2)
  }
  #endif

  /// A file reaches the encoder as it stands, and what the encoder writes reaches the output.
  func testAFileReachesTheEncoderAsItStands() throws {
    let directory = try makeDirectory()
    let source = directory + "/source"
    let path = directory + "/out"
    XCTAssertTrue(FileManager.default.createFile(atPath: source, contents: Data("image".utf8)))

    let outcome = RNGitMediaProcessConverter().convert(
      reading: source, through: ["cat"], to: path, within: 8)

    XCTAssertEqual(outcome, .converted)
    XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "image")
  }

  /// A file that is not there leaves nothing to run.
  func testAFileThatIsNotThereLeavesNothingToRun() throws {
    let directory = try makeDirectory()
    let outcome = RNGitMediaProcessConverter().convert(
      reading: directory + "/nothing", through: ["cat"], to: directory + "/out", within: 8)

    guard case .couldNotRun = outcome else { return XCTFail("\(outcome)") }
  }

  /// Whatever stood at the output before a run is gone once one has written over it.
  func testWhateverStoodAtTheOutputBeforeIsGone() throws {
    let path = try makeDirectory() + "/out"
    XCTAssertTrue(
      FileManager.default.createFile(atPath: path, contents: Data("an older and longer file".utf8)))

    XCTAssertEqual(
      RNGitMediaProcessConverter().convert(
        producing: ["printf", "new"], in: nil, through: ["cat"], to: path, within: 8), .converted)
    XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "new")
  }
}
