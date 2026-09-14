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

// git-remote-rns—the remote helper git runs for an rns:// remote.
//
// git writes commands on standard input and reads answers on standard output, so both streams
// carry the protocol and everything the helper says goes to standard error. Streams and the exit
// code live here; the behaviour is in ReticulumSwift's RNGit* types.

/// Where the helper answers git.
final class StandardOutput: RNGitClientOutput {
  func write(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
  }
}

/// Where the helper writes what it is doing.
final class StandardError: RNGitClientOutput {
  func write(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
  }
}

/// What git is telling the helper to do.
final class StandardInput: RNGitClientInput {
  func readLine() -> String? { Swift.readLine(strippingNewline: false) }
}

exit(
  RNGitHelperRuntime.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    environment: ProcessInfo.processInfo.environment,
    streams: RNGitHelperRuntime.Streams(
      standardOutput: StandardOutput(), standardError: StandardError(),
      standardInput: StandardInput())))
