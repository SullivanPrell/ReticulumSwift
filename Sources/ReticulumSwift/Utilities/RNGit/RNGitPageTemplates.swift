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

/// The templates a page is rendered into, and the substitutions that fill them.
public enum RNGitPageTemplate: String, CaseIterable, Sendable {

  /// The frame every page is rendered inside.
  case base
  /// The node's own front page.
  case front
  /// One repository group.
  case group
  /// One repository.
  case repo
  /// A repository's releases.
  case releases
  /// One release.
  case release
  /// One directory inside a repository.
  case tree
  /// One file inside a repository.
  case blob
  /// A repository's commits.
  case commits
  /// One commit.
  case commit
  /// A repository's branches and tags.
  case refs
  /// What a repository has been counted doing.
  case stats
  /// A repository's work documents.
  case work
  /// One work document.
  case workDocument = "work_doc"
  /// What stands in for a page that was asked for without an identity.
  case noIdentity = "no_ident"

  /// The template shipped under this name.
  public var shipped: String {
    switch self {
    case .base: return RNGitPageTemplate.shippedBase
    case .front: return RNGitPageTemplate.shippedFront
    case .noIdentity: return RNGitPageTemplate.shippedNoIdentity
    default: return RNGitPageTemplate.contentOnly
    }
  }

  /// A template that is nothing but the page it carries.
  static let contentOnly = "{PAGE_CONTENT}"

  static let shippedBase = """
    #!c=0
    > {NODE_NAME}

    {NAVIGATION}
    {PAGE_CONTENT}
    <
    -
    `a`F666`[Served by rngit {VERSION}`:/page/index.mu] - {GEN_TIME}`f
    """

  static let shippedFront = """
    > Groups

    {PAGE_CONTENT}
    """

  static let shippedNoIdentity =
    ">>No Identity\n\nThis page requires identification, and none was received.\n"

  /// The placeholders a template carries.
  enum Placeholder {
    static let pageContent = "{PAGE_CONTENT}"
    static let nodeName = "{NODE_NAME}"
    static let version = "{VERSION}"
    static let navigation = "{NAVIGATION}"
    static let generationTime = "{GEN_TIME}"
  }
}

/// The templates a node renders with, read from the templates directory when one stands there.
public struct RNGitPageTemplates: Sendable {

  /// Where a template of a given name is looked for.
  public let directory: String

  /// The name of the node every page names itself after.
  public let nodeName: String

  /// The version every page says it was served by.
  public let version: String

  /// What runs a template that is marked executable.
  let runner: RNGitCommandRunner

  /// Templates read from `directory`, with `runner` running the ones marked executable.
  public init(
    directory: String, nodeName: String, version: String,
    runner: RNGitCommandRunner = RNGitProcessRunner()
  ) {
    self.directory = directory
    self.nodeName = nodeName
    self.version = version
    self.runner = runner
  }

  /// What the templates directory holds under `name`, or nothing when it holds no such template.
  ///
  /// A template that is marked executable is run and its output taken; one that is not is read.
  /// Either way the trailing whitespace is dropped.
  public func custom(_ name: String) -> String? {
    let path = directory + "/" + name + ".mu"
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else { return nil }

    if FileManager.default.isExecutableFile(atPath: path) {
      guard let output = runner.run(path, arguments: [], in: nil) else { return nil }
      return Self.trimmed(output.standardOutput)
    }

    guard let read = FileManager.default.contents(atPath: path),
      let text = String(data: read, encoding: .utf8)
    else { return nil }
    return Self.trimmed(text)
  }

  /// `pageContent` rendered inside `template`, and that inside the base template.
  ///
  /// A template read from the templates directory stands in for the shipped one of the same
  /// name, and a name that matches neither leaves the page to be rendered on its own.
  ///
  /// The base template is applied whatever `template` names, and is itself read from the
  /// templates directory when one stands there. How long the page took is a measured interval,
  /// so it is written in the form a floating-point count takes.
  public func render(
    _ pageContent: String, navigation: String? = nil, template: String? = nil,
    startedAt: TimeInterval? = nil, now: TimeInterval = Date().timeIntervalSince1970
  ) -> Data {
    var page = RNGitPageFormatting.tabs(pageContent) ?? pageContent
    let name = (template?.isEmpty ?? true) ? nil : template

    if let name, let custom = custom(name) {
      page = custom.replacingOccurrences(of: RNGitPageTemplate.Placeholder.pageContent, with: page)
    } else if let name, let shipped = RNGitPageTemplate(rawValue: name) {
      page = shipped.shipped.replacingOccurrences(
        of: RNGitPageTemplate.Placeholder.pageContent, with: page)
    }

    var base = custom(RNGitPageTemplate.base.rawValue) ?? RNGitPageTemplate.base.shipped
    base = base.replacingOccurrences(of: RNGitPageTemplate.Placeholder.nodeName, with: nodeName)
    base = base.replacingOccurrences(of: RNGitPageTemplate.Placeholder.version, with: version)
    base = base.replacingOccurrences(
      of: RNGitPageTemplate.Placeholder.navigation, with: navigation ?? "")

    let generated =
      startedAt.map { "Generated in " + RNStatusRenderer.prettytime(now - $0, isFloat: true) }
      ?? "Unknown generation time"
    base = base.replacingOccurrences(
      of: RNGitPageTemplate.Placeholder.generationTime, with: generated)
    base = base.replacingOccurrences(of: RNGitPageTemplate.Placeholder.pageContent, with: page)
    return Data(base.utf8)
  }

  /// `text` without the whitespace it ends on.
  private static func trimmed(_ text: String) -> String {
    var read = Substring(text)
    while let last = read.last, last.isWhitespace { read = read.dropLast() }
    return String(read)
  }
}
