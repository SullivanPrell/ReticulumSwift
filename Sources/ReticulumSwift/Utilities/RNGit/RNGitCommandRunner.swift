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

/// What one `git` invocation produced.
public struct RNGitCommandOutput: Equatable, Sendable {

  /// The exit status the command returned.
  public let status: Int32

  /// Everything the command wrote to standard output.
  public let standardOutput: String

  /// Everything the command wrote to standard error.
  public let standardError: String

  /// Creates an outcome.
  public init(status: Int32, standardOutput: String, standardError: String) {
    self.status = status
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}

/// What one invocation wrote, as the bytes it wrote rather than as text.
public struct RNGitCommandBytes: Equatable, Sendable {

  /// The exit status the command returned.
  public let status: Int32

  /// Everything the command wrote to standard output.
  public let standardOutput: Data

  /// Creates an outcome.
  public init(status: Int32, standardOutput: Data) {
    self.status = status
    self.standardOutput = standardOutput
  }
}

/// Runs the commands a node needs: `git`, and the `allowed` programs a group may carry.
public protocol RNGitCommandRunner: Sendable {

  /// Runs `executable` with `arguments` in `directory`, or answers `nil` if it could not run.
  ///
  /// A failure to launch is caught by the helper that called it. A name without a separator is
  /// looked up on the search path, as `execvp` does; a name with one is run as it stands, so a file
  /// the system cannot execute does not run at all.
  ///
  /// Output that is not UTF-8 answers `nil` as well. Every caller decodes strictly, either
  /// through `text=True` or through `bytes.decode("utf-8")`, so output the decoder refuses
  /// raises where a failure to launch raises.
  func run(_ executable: String, arguments: [String], in directory: String?)
    -> RNGitCommandOutput?

  /// Runs `executable` with `arguments` in `directory`, answering what it wrote as bytes.
  ///
  /// The output of a file read out of a repository is whatever the file holds, which need not
  /// decode, so the reader that has to look at those bytes asks for them here instead.
  func run(bytes executable: String, arguments: [String], in directory: String?)
    -> RNGitCommandBytes?
}

extension RNGitCommandRunner {

  /// The bytes of what the command printed, for a runner that only answers text.
  public func run(bytes executable: String, arguments: [String], in directory: String?)
    -> RNGitCommandBytes?
  {
    run(executable, arguments: arguments, in: directory).map {
      RNGitCommandBytes(status: $0.status, standardOutput: Data($0.standardOutput.utf8))
    }
  }
}

/// Runs a command as a subprocess.
///
/// The platform gate matches ``InterfaceAnnouncer``'s: `Foundation.Process` exists only on
/// macOS, so every command answers `nil` elsewhere, as it would where `git` is absent.
public struct RNGitProcessRunner: RNGitCommandRunner {

  /// Creates a runner.
  public init() {}

  /// Runs `executable` with `arguments` in `directory`, or answers `nil` if it could not run.
  public func run(_ executable: String, arguments: [String], in directory: String?)
    -> RNGitCommandOutput?
  {
    #if os(macOS)
    let process = Process()
    if executable.contains("/") {
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = [executable] + arguments
    }
    if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }

    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors

    do {
      try process.run()
      let producedOutput = output.fileHandleForReading.readDataToEndOfFile()
      let producedErrors = errors.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard let standardOutput = String(data: producedOutput, encoding: .utf8),
        let standardError = String(data: producedErrors, encoding: .utf8)
      else { return nil }
      return RNGitCommandOutput(
        status: process.terminationStatus, standardOutput: standardOutput,
        standardError: standardError)
    } catch {
      return nil
    }
    #else
    return nil
    #endif
  }

  /// Runs `executable` with `arguments` in `directory`, answering what it wrote as bytes.
  public func run(bytes executable: String, arguments: [String], in directory: String?)
    -> RNGitCommandBytes?
  {
    #if os(macOS)
    let process = Process()
    if executable.contains("/") {
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = [executable] + arguments
    }
    if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }

    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors

    do {
      try process.run()
      let produced = output.fileHandleForReading.readDataToEndOfFile()
      _ = errors.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return RNGitCommandBytes(status: process.terminationStatus, standardOutput: produced)
    } catch {
      return nil
    }
    #else
    return nil
    #endif
  }
}
