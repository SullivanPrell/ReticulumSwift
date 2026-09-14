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

/// Runs a conversion as subprocesses.
///
/// The platform gate matches ``RNGitProcessRunner``'s: `Foundation.Process` exists only on
/// macOS, so a conversion anywhere else could not be started, as it could not be where no
/// encoder stands on the system.
public struct RNGitMediaProcessConverter: RNGitMediaConverter {

  /// How much of an error stream is kept to say what a failure was.
  static let errorTail = 1024

  /// Creates a converter.
  public init() {}

  /// Runs `producing` in `directory` and feeds what it writes into `encoding`, whose own output
  /// goes to `path`.
  public func convert(
    producing: [String], in directory: String?, through encoding: [String], to path: String,
    within timeout: TimeInterval
  ) -> RNGitMediaOutcome {
    #if os(macOS)
    guard let output = writable(path) else {
      return .couldNotRun("could not open " + path + " for writing")
    }
    defer { try? output.close() }

    let between = Pipe()
    let inputErrors = Pipe()
    let encoderErrors = Pipe()

    let input = process(producing, in: directory)
    input.standardOutput = between
    input.standardError = inputErrors

    let encoder = process(encoding, in: nil)
    encoder.standardInput = between
    encoder.standardOutput = output
    encoder.standardError = encoderErrors

    do {
      try input.run()
      try encoder.run()
    } catch {
      terminate(input)
      terminate(encoder)
      return .couldNotRun("\(error)")
    }

    // The parent must not keep the write end of the pipe between them, or the encoder would
    // never see the end of what the input process wrote.
    try? between.fileHandleForWriting.close()

    guard finished(encoder, and: input, within: timeout) else { return .timedOut }
    guard encoder.terminationStatus == 0 else {
      return .failed(encoder: tail(encoderErrors), input: tail(inputErrors))
    }
    return .converted
    #else
    return .couldNotRun("subprocesses are not available on this platform")
    #endif
  }

  /// Feeds the file at `source` into `encoding`, whose output goes to `path`.
  public func convert(
    reading source: String, through encoding: [String], to path: String,
    within timeout: TimeInterval
  ) -> RNGitMediaOutcome {
    #if os(macOS)
    guard let input = FileHandle(forReadingAtPath: source) else {
      return .couldNotRun("could not open " + source + " for reading")
    }
    defer { try? input.close() }
    guard let output = writable(path) else {
      return .couldNotRun("could not open " + path + " for writing")
    }
    defer { try? output.close() }

    let errors = Pipe()
    let encoder = process(encoding, in: nil)
    encoder.standardInput = input
    encoder.standardOutput = output
    encoder.standardError = errors

    do { try encoder.run() } catch { return .couldNotRun("\(error)") }

    guard finished(encoder, and: nil, within: timeout) else { return .timedOut }
    guard encoder.terminationStatus == 0 else {
      return .failed(encoder: tail(errors), input: "")
    }
    return .converted
    #else
    return .couldNotRun("subprocesses are not available on this platform")
    #endif
  }

  #if os(macOS)
  /// A process that runs `words` in `directory`, the program it runs looked up on the search path
  /// where the word naming it carries no separator.
  private func process(_ words: [String], in directory: String?) -> Process {
    let process = Process()
    if words[0].contains("/") {
      process.executableURL = URL(fileURLWithPath: words[0])
      process.arguments = Array(words.dropFirst())
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = words
    }
    if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
    return process
  }

  /// A handle writing to `path`, which is emptied first where something already stands there.
  private func writable(_ path: String) -> FileHandle? {
    FileManager.default.createFile(atPath: path, contents: Data())
      ? FileHandle(forWritingAtPath: path) : nil
  }

  /// Whether both processes ended before their time was up, stopping both where they did not.
  private func finished(_ encoder: Process, and input: Process?, within timeout: TimeInterval)
    -> Bool
  {
    let deadline = Date().addingTimeInterval(timeout)
    while encoder.isRunning || (input?.isRunning ?? false) {
      if Date() >= deadline {
        if let input { terminate(input) }
        terminate(encoder)
        return false
      }
      usleep(20_000)
    }
    return true
  }

  /// Stops `process` and waits for it to go.
  private func terminate(_ process: Process) {
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
  }

  /// What a process wrote to its error stream, up to what is kept of one.
  private func tail(_ errors: Pipe) -> String {
    let written =
      (try? errors.fileHandleForReading.read(upToCount: Self.errorTail)) ?? Data()
    return String(decoding: written ?? Data(), as: UTF8.self).trimmingCharacters(
      in: .whitespacesAndNewlines)
  }
  #endif
}
