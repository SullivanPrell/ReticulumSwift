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

extension RNGitCommandLine {

  /// One option a subcommand takes.
  struct Option {

    /// Every spelling, the short one first.
    let names: [String]

    /// What the option's value is called, or `nil` where the option takes none.
    let metavar: String?

    /// What the option is for.
    let help: String

    /// What the option stands for where it is not given.
    var fallback: String?
  }

  /// One word a subcommand takes in its own right.
  struct Positional {

    /// What the word is called.
    let name: String

    /// What the word is for.
    let help: String

    /// Whether the subcommand refuses to run without it.
    var required = true
  }

  /// What one subcommand takes.
  struct Shape {

    /// The line printed above the option list.
    let description: String

    /// The options the subcommand takes beyond the ones every subcommand takes.
    let options: [Option]

    /// The words the subcommand takes in its own right.
    var positionals: [Positional] = []
  }

  /// The options every subcommand takes before its own.
  private static let leading = [
    Option(names: ["--config"], metavar: "CONFIG", help: "path to alternative config directory"),
    Option(
      names: ["--rnsconfig"], metavar: "RNSCONFIG",
      help: "path to alternative Reticulum config directory"),
  ]

  /// The options every subcommand takes after its own.
  private static let trailing = [
    Option(names: ["-v", "--verbose"], metavar: nil, help: ""),
    Option(names: ["-q", "--quiet"], metavar: nil, help: ""),
    Option(
      names: ["--version"], metavar: nil, help: "show program's version number and exit"),
  ]

  /// The identity option, which every subcommand but the node takes.
  private static func identity(_ help: String) -> Option {
    Option(names: ["-i", "--identity"], metavar: "PATH", help: help)
  }

  /// What `subcommand` takes.
  static func shape(of subcommand: RNGitSubcommand) -> Shape {
    switch subcommand {
    case .node:
      return Shape(
        description: "Reticulum Git Repository Node",
        options: [
          Option(
            names: ["-p", "--print-identity"], metavar: nil,
            help: "print identity and destination info and exit"),
          Option(
            names: ["-s", "--service"], metavar: nil,
            help: "rngit is running as a service and should log to file"),
          Option(
            names: ["-i", "--interactive"], metavar: nil,
            help: "drop into interactive shell after initialisation"),
        ])

    case .create:
      return Shape(
        description: "Reticulum Git Repository Creation",
        options: [identity("path to identity")],
        positionals: [Positional(name: "repository", help: "URL of repository to create")])

    case .release:
      return Shape(
        description: "Reticulum Git Release Manager",
        options: [
          identity("path to release identity"),
          Option(
            names: ["-s", "--signer"], metavar: "PATH",
            help: "path to signing identity, if different from release identity"),
          Option(
            names: ["-n", "--name"], metavar: "name",
            help: "package name if different from repo name"),
          Option(
            names: ["-L", "--local"], metavar: nil,
            help: "generate release locally, but don't upload"),
          Option(
            names: ["-o", "--offline"], metavar: nil,
            help: "verify manifest locally, but don't fetch updates"),
        ],
        positionals: [
          Positional(
            name: "repository", help: "URL of remote repository, or path to RSM manifest",
            required: false),
          Positional(
            name: "operation", help: "list, view, fetch, verify, create, latest or delete",
            required: false),
          Positional(
            name: "target", help: "tag and path to release artifacts directory", required: false),
        ])

    case .perms:
      return Shape(
        description: "Reticulum Git Release Manager",
        options: [identity("path to release identity")],
        positionals: [
          Positional(name: "remote", help: "URL of remote group or repository")
        ])

    case .work:
      return Shape(
        description: "Reticulum Git Work Document Manager",
        options: [
          identity("path to identity"),
          Option(
            names: ["--scope"], metavar: "SCOPE",
            help: "document scope: active, completed or all", fallback: "active"),
          Option(
            names: ["-t", "--title"], metavar: "TITLE", help: "document title for create"),
          Option(names: ["-d", "--id"], metavar: "ID", help: "document ID"),
        ],
        positionals: [
          Positional(name: "repository", help: "URL of remote repository", required: false),
          Positional(
            name: "operation",
            help: "list, view, create, propose, edit, delete, update, complete, activate or perms",
            required: false),
        ])

    case .fork:
      return Shape(
        description: "Reticulum Git Repository Forker",
        options: [identity("path to identity")],
        positionals: [
          Positional(name: "source", help: "URL of source repository"),
          Positional(name: "target", help: "URL of target repository"),
        ])

    case .sync:
      return Shape(
        description: "Reticulum Git Repository Syncer",
        options: [identity("path to identity")],
        positionals: [Positional(name: "repository", help: "URL of repository")])

    case .mirror:
      return Shape(
        description: "Reticulum Git Mirror Management",
        options: [
          identity("path to identity"),
          Option(
            names: ["--scope"], metavar: "SCOPE",
            help: "document scope: active, completed or all", fallback: "active"),
        ],
        positionals: [
          Positional(name: "source", help: "URL of source repository"),
          Positional(name: "target", help: "URL of target repository"),
        ])
    }
  }

  /// Every option `subcommand` takes, in the order they are written out.
  static func options(of subcommand: RNGitSubcommand) -> [Option] {
    leading + shape(of: subcommand).options + trailing
  }

  /// The parser `subcommand` reads its arguments with.
  static func makeParser(for subcommand: RNGitSubcommand) -> ArgumentParser {
    let shape = shape(of: subcommand)
    var parser = ArgumentParser(program: program, overview: shape.description)
    for option in options(of: subcommand) {
      guard let metavar = option.metavar else {
        if option.names.first == "-v" || option.names.first == "-q" {
          parser.counted(option.names, help: option.help)
        } else {
          parser.flag(option.names, help: option.help)
        }
        continue
      }
      parser.option(
        option.names, metavar: metavar, help: option.help, default: option.fallback)
    }
    for positional in shape.positionals {
      parser.positional(positional.name, help: positional.help, required: positional.required)
    }
    return parser
  }

  /// The `usage:` block `subcommand` writes before an error message, with no blank line after.
  static func usage(for subcommand: RNGitSubcommand) -> String {
    let shape = shape(of: subcommand)
    var block = ArgparseHelp.usage(
      program: program,
      optionals: ["[-h]"]
        + options(of: subcommand).map { option in
          guard let metavar = option.metavar else { return "[" + option.names[0] + "]" }
          return "[" + option.names[0] + " " + metavar + "]"
        },
      positionals: shape.positionals.map {
        $0.required ? $0.name : "[" + $0.name + "]"
      })
    if block.hasSuffix("\n\n") { block.removeLast() }
    return block
  }

  /// The whole text `subcommand` prints for `--help`.
  static func help(for subcommand: RNGitSubcommand) -> String {
    let shape = shape(of: subcommand)
    return ArgparseHelp.help(
      program: program,
      description: shape.description,
      usageOptionals: ["[-h]"]
        + options(of: subcommand).map { option in
          guard let metavar = option.metavar else { return "[" + option.names[0] + "]" }
          return "[" + option.names[0] + " " + metavar + "]"
        },
      usagePositionals: shape.positionals.map {
        $0.required ? $0.name : "[" + $0.name + "]"
      },
      positionals: shape.positionals.map {
        ArgparseHelp.Entry(invocation: $0.name, help: $0.help)
      },
      options: [
        ArgparseHelp.Entry(
          invocation: "-h, --help", help: "show this help message and exit")
      ]
        + options(of: subcommand).map { option in
          guard let metavar = option.metavar else {
            return ArgparseHelp.Entry(
              invocation: option.names.joined(separator: ", "), help: option.help)
          }
          return ArgparseHelp.Entry(
            invocation: option.names.map { $0 + " " + metavar }.joined(separator: ", "),
            help: option.help)
        })
  }
}
