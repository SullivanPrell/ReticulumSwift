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

// rngcs—Git commit signer and validator for a Reticulum identity.
//
// Python reference: RNS/Utilities/rngit/commitsigs.py.
//
// `git` runs this program when `gpg.ssh.program` names it, so its exit code is the whole
// verdict. Argument parsing, streams and exit codes live here; the behaviour is in
// ReticulumSwift's RNGCS* and GitCommitSignature types.

/// Python: `print(text)`.
final class StandardOutput: RNIDOutput {
  func line(_ text: String) { print(text) }

  func partial(_ text: String) {
    print(text, terminator: "")
    fflush(stdout)
  }
}

/// Python: `print(..., file=sys.stderr)`.
final class StandardError: RNIDOutput {
  func line(_ text: String) { write(text + "\n") }
  func partial(_ text: String) { write(text) }

  private func write(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
  }
}

func runRNGCS() -> Int32 {
  let invocation: RNGCSCommandLine.Invocation
  do {
    invocation = try RNGCSCommandLine.parse(Array(CommandLine.arguments.dropFirst()))
  } catch {
    let detail = (error as? ArgumentError).map { RNGCSCommandLine.makeParser().message(for: $0) }
    FileHandle.standardError.write(Data(((detail ?? "\(error)") + "\n").utf8))
    return 2
  }

  let operations = RNGCSOperations(
    output: StandardOutput(), errorOutput: StandardError(),
    fileSystem: RNIDRealFileSystem(),
    // Python: `sys.stdin.buffer.read()`, read only by the operations that need it.
    standardInput: { FileHandle.standardInput.readDataToEndOfFile() })

  return operations.run(invocation)
}

exit(runRNGCS())
