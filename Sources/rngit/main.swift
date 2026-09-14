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
import ReticulumSwift

// rngit—runs a repository node, and asks one to do things.
//
// Streams and the exit code live here; the behaviour is in ReticulumSwift's RNGit* types.

/// Where the run says what it is doing.
final class StandardOutput: RNGitClientOutput {
  func write(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
  }
}

/// Where the run says what went wrong.
final class StandardError: RNGitClientOutput {
  func write(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
  }
}

/// What the user is typing.
final class StandardInput: RNGitClientInput {
  func readLine() -> String? { Swift.readLine(strippingNewline: false) }
}

exit(
  RNGitRuntime.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    version: Reticulum.version,
    streams: RNGitRuntime.Streams(
      standardOutput: StandardOutput(), standardError: StandardError(),
      standardInput: StandardInput())))
