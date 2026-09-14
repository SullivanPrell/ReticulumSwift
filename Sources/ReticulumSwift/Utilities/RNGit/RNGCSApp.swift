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

/// The `rngcs` command line.
///
/// Python: `main` (`Utilities/rngit/commitsigs.py:299-323`). `git` invokes the program
/// named by `gpg.ssh.program`, so the switches below are `git`'s, not this port's.
public enum RNGCSCommandLine {

  /// One of the four operations `git` asks for.
  ///
  /// Python: `choices=["sign", "find-principals", "check-novalidate", "verify"]`.
  public enum Operation: String, Equatable {
    case sign
    case findPrincipals = "find-principals"
    case checkNoValidate = "check-novalidate"
    case verify
  }

  /// A parsed command line.
  public struct Invocation: Equatable {
    /// Python: `args.op`.
    public let operation: Operation
    /// Python: `args.namespace`, accepted for `git` compatibility and not read.
    public let namespace: String
    /// Python: `args.keyfile`, the identity to sign with.
    public let keyfile: String?
    /// Python: `args.principal`, the identity a verification demands.
    public let principal: String?
    /// Python: `args.sigfile`, the signature to read.
    public let sigfile: String?
    /// Python: the positional `file` to sign, when signing is not from standard input.
    public let file: String?
  }

  /// The parser, matching the reference's switches.
  public static func makeParser() -> ArgumentParser {
    var parser = ArgumentParser(
      program: "rngcs", overview: "Git commit signer and validator")
    parser.option(["-Y"], metavar: "OP", help: "Operation to perform")
    parser.option(["-n"], metavar: "NAMESPACE", help: "Namespace", default: "git")
    parser.option(
      ["-f"], metavar: "PATH",
      help: "Key file (for signing) or allowed signers file (for verification)")
    parser.option(["-I"], metavar: "PRINCIPAL", help: "Principal identity (for verification)")
    parser.option(["-s"], metavar: "PATH", help: "Signature file")
    parser.appending(["-O"], metavar: "OPTION", help: "SSH options, ignored")
    parser.positional("file", help: "File to sign (for signing)", required: false)
    return parser
  }

  /// Parses an argument vector.
  ///
  /// Python exits 1 on any unrecognised token that is not an `-O` option
  /// (`commitsigs.py:308-315`); here an unrecognised option throws instead, and `-O` is
  /// declared so every spelling of it is consumed and discarded.
  public static func parse(_ arguments: [String]) throws -> Invocation {
    let parsed = try makeParser().parse(arguments)

    guard let name = parsed.value("-Y"), let operation = Operation(rawValue: name) else {
      throw ArgumentError.missingValue("-Y")
    }

    return Invocation(
      operation: operation,
      namespace: parsed.value("-n") ?? "git",
      keyfile: parsed.value("-f"),
      principal: parsed.value("-I"),
      sigfile: parsed.value("-s"),
      file: parsed.positionals.first)
  }
}

/// The four `rngcs` operations, with their exit codes and their output.
///
/// Python: `sign`, `find_principals`, `check_novalidate` and `verify`
/// (`Utilities/rngit/commitsigs.py:118-297`). Every code is `git`'s only signal about
/// whether a signature held, so a failure returns 1 rather than throwing.
public final class RNGCSOperations {

  private let output: RNIDOutput
  private let errorOutput: RNIDOutput
  private let fileSystem: RNIDFileSystem
  private let standardInput: () -> Data

  /// Creates the operations over a set of streams.
  public init(
    output: RNIDOutput, errorOutput: RNIDOutput, fileSystem: RNIDFileSystem,
    standardInput: @escaping () -> Data
  ) {
    self.output = output
    self.errorOutput = errorOutput
    self.fileSystem = fileSystem
    self.standardInput = standardInput
  }

  /// Runs the invocation and returns the process exit code.
  public func run(_ invocation: RNGCSCommandLine.Invocation) -> Int32 {
    switch invocation.operation {
    case .sign: return sign(invocation)
    case .findPrincipals: return findPrincipals(invocation)
    case .checkNoValidate: return checkNoValidate(invocation)
    case .verify: return verify(invocation)
    }
  }

  // MARK: - sign

  private func sign(_ invocation: RNGCSCommandLine.Invocation) -> Int32 {
    guard let keyfile = invocation.keyfile, fileSystem.fileExists(atPath: keyfile) else {
      errorOutput.line("Identity file not found: \(invocation.keyfile ?? "")")
      return 1
    }
    guard let identity = Identity.fromFile(URL(fileURLWithPath: keyfile)),
      identity.hasPrivateKey
    else {
      errorOutput.line("Error: Could not load identity or identity has no private key")
      return 1
    }

    let message: Data
    var signaturePath: String?
    if let file = invocation.file, fileSystem.fileExists(atPath: file) {
      guard let contents = try? fileSystem.readData(atPath: file) else {
        errorOutput.line("Error reading \(file)")
        return 1
      }
      message = contents
      signaturePath = file + ".sig"
    } else {
      message = standardInput()
    }

    let armoured: String
    do {
      armoured = try GitCommitSignature.sign(message: message, identity: identity)
    } catch {
      errorOutput.line("Error creating signature: \(error)")
      return 1
    }

    guard let signaturePath else {
      output.partial(armoured)
      return 0
    }
    do {
      try fileSystem.writeData(Data(armoured.utf8), atPath: signaturePath)
    } catch {
      errorOutput.line("Error writing signature file: \(error)")
      return 1
    }
    return 0
  }

  // MARK: - find-principals

  private func findPrincipals(_ invocation: RNGCSCommandLine.Invocation) -> Int32 {
    guard let armoured = readSignature(invocation, reportMissing: true) else { return 1 }
    do {
      output.line(try GitCommitSignature.findPrincipals(armouredSignature: armoured))
      return 0
    } catch GitCommitSignature.SigningError.namespaceMismatch {
      errorOutput.line("Error: Namespace mismatch")
      return 1
    } catch {
      errorOutput.line("Could not determine signer identity: \(error)")
      return 1
    }
  }

  // MARK: - check-novalidate

  private func checkNoValidate(_ invocation: RNGCSCommandLine.Invocation) -> Int32 {
    guard let armoured = readSignature(invocation, reportMissing: false) else { return 1 }
    return GitCommitSignature.checkWithoutValidating(armouredSignature: armoured) ? 0 : 1
  }

  // MARK: - verify

  private func verify(_ invocation: RNGCSCommandLine.Invocation) -> Int32 {
    guard let armoured = readSignature(invocation, reportMissing: true) else { return 1 }
    let message = standardInput()

    switch GitCommitSignature.verify(
      message: message, armouredSignature: armoured, principal: invocation.principal)
    {
    case .good(let signer):
      output.line(
        "Good \"git\" signature for commit, signed with Reticulum Identity key <\(signer)>")
      return 0
    case .malformedSignature:
      errorOutput.line("Error parsing signature")
      return 1
    case .namespaceMismatch:
      errorOutput.line("Invalid commit signature namespace")
      return 1
    case .invalidSignature:
      errorOutput.line("Invalid signature")
      return 1
    case .authorMismatch:
      // Python prints this one on stdout, not stderr (`commitsigs.py:290`).
      output.line("Commit not signed by author <\(GitCommitHeaders.author(in: message))>")
      return 1
    case .principalMismatch:
      errorOutput.line("Principal mismatch")
      return 1
    }
  }

  // MARK: - Shared

  private func readSignature(
    _ invocation: RNGCSCommandLine.Invocation, reportMissing: Bool
  ) -> String? {
    guard let sigfile = invocation.sigfile, fileSystem.fileExists(atPath: sigfile) else {
      // Python: `find_principals` and `verify` say so; `check_novalidate` is silent.
      if reportMissing { errorOutput.line("Error: Signature file not found") }
      return nil
    }
    guard let text = try? fileSystem.readText(atPath: sigfile) else {
      if reportMissing { errorOutput.line("Error reading signature file") }
      return nil
    }
    return text
  }
}
