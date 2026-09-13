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
///
/// Python: the `subprocess.CompletedProcess` the node's git helpers read
/// (`server.py:2709-2780`).
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

/// Runs the commands a node needs: `git`, and the `allowed` programs a group may carry.
public protocol RNGitCommandRunner: Sendable {

  /// Runs `executable` with `arguments` in `directory`, or answers `nil` if it could not run.
  ///
  /// Python: `subprocess.run([executable] + arguments, cwd=directory, capture_output=True)`,
  /// whose failure to launch raises and is caught by the helper that called it. A name
  /// without a separator is looked up on the search path, as `execvp` does.
  func run(_ executable: String, arguments: [String], in directory: String?)
    -> RNGitCommandOutput?
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
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
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
      return RNGitCommandOutput(
        status: process.terminationStatus,
        standardOutput: String(decoding: producedOutput, as: UTF8.self),
        standardError: String(decoding: producedErrors, as: UTF8.self))
    } catch {
      return nil
    }
    #else
    return nil
    #endif
  }
}
