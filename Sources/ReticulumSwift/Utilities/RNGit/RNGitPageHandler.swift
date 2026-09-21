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

/// The node's answer to a request for one of the Micron pages it serves.
///
/// Built fresh for each request, the way the git-wire-protocol handlers are: it is handed a
/// copy of the node's statistics, records into that copy, and the caller reads `statistics`
/// back afterward. `thanks` is the exception — a class the node holds for as long as it runs, so
/// a link is only ever counted once no matter how many handlers come and go answering it.
public struct RNGitPageHandler {

  /// What a reader may see, resolving one with no identity against the standing null identity.
  public var access: RNGitPageAccess

  /// Runs the `git` a page's content is read with.
  public var runner: RNGitCommandRunner

  /// The destination the node serves its pages on, which a repository page links back to.
  public var destinationHash: Data

  /// The settings that say whether the node counts a view, and who it never counts.
  public var settings: RNGitNodeSettings

  /// The counters the node keeps.
  public var statistics: RNGitStatistics

  /// How many times a repository or a release has been thanked.
  public var thanks: RNGitPageThanks

  /// Colors a repository's readme and the code blocks inside it.
  public var syntaxHighlighter: MicronSyntaxHighlighting

  /// The templates a page is rendered into.
  public var templates: RNGitPageTemplates

  /// Reads a repository through `runner`, for the pages that show what one holds.
  private var reader: RNGitRepositoryReader { RNGitRepositoryReader(runner: runner) }

  /// Creates a handler answering from `access`.
  public init(
    access: RNGitPageAccess, runner: RNGitCommandRunner, destinationHash: Data,
    settings: RNGitNodeSettings = RNGitNodeSettings(),
    statistics: RNGitStatistics = RNGitStatistics(), thanks: RNGitPageThanks = RNGitPageThanks(),
    syntaxHighlighter: MicronSyntaxHighlighting = SyntaxHighlighter(), templates: RNGitPageTemplates
  ) {
    self.access = access
    self.runner = runner
    self.destinationHash = destinationHash
    self.settings = settings
    self.statistics = statistics
    self.thanks = thanks
    self.syntaxHighlighter = syntaxHighlighter
    self.templates = templates
  }

  // MARK: - Front page

  /// The front page: every group `identityHash` may see, and how many repositories each holds.
  ///
  /// Mirrors `serve_front_page` exactly: the view is counted before the no-identity check, so a
  /// reader turned away for having no identity still counts as a view.
  public mutating func serveFrontPage(identityHash: Data?) -> Data {
    let startedAt = Date().timeIntervalSince1970
    let accessibleGroups = access.groups(readableBy: identityHash)

    var content = ""
    if accessibleGroups.isEmpty {
      content = ">>\nNo groups available\n"
    } else {
      for name in RNGitPage.sorted(accessibleGroups.keys) {
        guard let group = accessibleGroups[name] else { continue }
        let count = group.repositories.count
        let word = count == 1 ? "repository" : "repositories"
        let link = RNGitPageMicron.link(
          "  \(MarkdownToMicron.bullet) \(name)", RNGitPage.Path.group, [("g", name)])
        content += "\(link) (\(count) \(word))\n"
      }
    }

    let navigation = ">>\n" + RNGitPageMicron.link("Node", RNGitPage.Path.index) + " /" + "\n"

    viewSucceeded(group: nil, repository: nil, for: identityHash)

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", navigation: navigation, template: RNGitPageTemplate.noIdentity.rawValue,
        startedAt: startedAt)
    }
    return templates.render(
      content, navigation: navigation, template: RNGitPageTemplate.front.rawValue,
      startedAt: startedAt)
  }

  // MARK: - Group page

  /// One group's repositories, and what each holds — or that `groupName` names no group
  /// `identityHash` may see, which reads the same whether it exists and is closed or does not
  /// exist at all.
  ///
  /// Mirrors `serve_group_page`: Python's own "no repositories available" branch can never run,
  /// since the not-found check just above it already returns whenever the accessible set is
  /// empty, so this only ever builds the repository list.
  public mutating func serveGroupPage(identityHash: Data?, groupName: String) -> Data {
    let startedAt = Date().timeIntervalSince1970

    guard !groupName.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nInvalid request\n", startedAt: startedAt)
    }

    let navigation =
      ">>\n" + RNGitPageMicron.link("Node", RNGitPage.Path.index) + " / " + groupName + "\n"

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", navigation: navigation, template: RNGitPageTemplate.noIdentity.rawValue,
        startedAt: startedAt)
    }

    let accessibleRepositories = access.repositories(readableBy: identityHash, in: groupName)
    guard access.control.groups[groupName] != nil, !accessibleRepositories.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Group Not Found", level: 2)
          + "\nThe requested group was not found\n",
        navigation: navigation, startedAt: startedAt)
    }

    var content = RNGitPageMicron.heading(" Repositories", level: 1) + "\n"
    for name in RNGitPage.sorted(accessibleRepositories.keys) {
      guard let repository = accessibleRepositories[name] else { continue }
      let link = RNGitPageMicron.link(
        "  \(MarkdownToMicron.bullet) \(name)", RNGitPage.Path.repository,
        [("g", groupName), ("r", name)])
      if let description = reader.description(of: repository.path) {
        content += "\(link) - \(description)\n"
      } else {
        content += "\(link)\n"
      }
    }

    viewSucceeded(group: groupName, repository: nil, for: identityHash)

    return templates.render(
      content, navigation: navigation, template: RNGitPageTemplate.group.rawValue,
      startedAt: startedAt)
  }

  // MARK: - Refs page

  /// One repository's branches and tags, `refType` narrowing them to `"heads"` or `"tags"`.
  ///
  /// Mirrors `serve_refs_page`, including its one quirk: when `refType` narrows the page to just
  /// branches or just tags, "No refs found" never shows even if that narrowed set is empty —
  /// Python's own guard is an AND of both sides, not the one the request actually asked for.
  public mutating func serveRefsPage(
    identityHash: Data?, groupName: String, repositoryName: String, refType: String = ""
  ) -> Data {
    let startedAt = Date().timeIntervalSince1970

    let breadcrumb =
      RNGitPageMicron.link("Node", RNGitPage.Path.index) + " / "
      + RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]) + " / "
      + RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)])
      + " / refs"
    let navigation = ">>\n" + breadcrumb + "\n"

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", template: RNGitPageTemplate.noIdentity.rawValue, startedAt: startedAt)
    }

    guard !groupName.isEmpty, !repositoryName.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nInvalid request\n", startedAt: startedAt)
    }

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2)
          + "\nThe requested repository was not found.\n",
        navigation: navigation, startedAt: startedAt)
    }

    let sep = RNGitPage.icon(.separator)
    let filterLinks = [
      RNGitPageMicron.link("All", RNGitPage.Path.refs, [("g", groupName), ("r", repositoryName)]),
      RNGitPageMicron.link(
        "Branches only", RNGitPage.Path.refs,
        [("g", groupName), ("r", repositoryName), ("type", "heads")]),
      RNGitPageMicron.link(
        "Tags only", RNGitPage.Path.refs,
        [("g", groupName), ("r", repositoryName), ("type", "tags")]),
    ]
    var content = filterLinks.joined(separator: " \(sep) ") + "\n\n"

    let defaultBranch = reader.defaultBranch(of: repository.path)
    let showHeads = refType.isEmpty || refType == "heads"
    let showTags = refType.isEmpty || refType == "tags"
    let refs = reader.referenceDetails(of: repository.path, defaultBranch: defaultBranch)

    if showHeads, !refs.heads.isEmpty {
      content += RNGitPageMicron.heading("Branches (\(refs.heads.count))", level: 2) + "\n"
      for head in refs.heads {
        let nameDisplay =
          head.isDefault ? RNGitPage.Colour.diffAdded + head.name + "`f" : head.name
        let defaultMarker = head.isDefault ? " " + RNGitPage.Colour.diffAdded + "(default)`f" : ""
        let treeLink = RNGitPageMicron.link(
          "tree", RNGitPage.Path.tree,
          [("g", groupName), ("r", repositoryName), ("ref", head.name)])
        let commitsLink = RNGitPageMicron.link(
          "commits", RNGitPage.Path.commits,
          [("g", groupName), ("r", repositoryName), ("ref", head.name)])
        content += "\(nameDisplay)\(defaultMarker) [\(treeLink)] [\(commitsLink)]\n"
        content += "\(head.shortHash): \(RNGitPageMicron.escape(head.commitSubject))\n\n"
      }
    }

    if showTags, !refs.tags.isEmpty {
      content += RNGitPageMicron.heading("Tags (\(refs.tags.count))", level: 2) + "\n"
      for tag in refs.tags.reversed() {
        let annotatedMarker = tag.isAnnotated ? " `Faa0(annotated)`f" : ""
        let treeLink = RNGitPageMicron.link(
          "tree", RNGitPage.Path.tree,
          [("g", groupName), ("r", repositoryName), ("ref", tag.name)])
        let commitsLink = RNGitPageMicron.link(
          "commits", RNGitPage.Path.commits,
          [("g", groupName), ("r", repositoryName), ("ref", tag.name)])
        content +=
          "\(tag.name)\(annotatedMarker) \(RNGitPage.Colour.dim)\(tag.shortHash)`f "
          + "[\(treeLink)] [\(commitsLink)]\n"
        if tag.isAnnotated, let message = tag.tagMessage, !message.isEmpty {
          content += "\(RNGitPageMicron.escape(String(message.prefix(512))))\n\n"
        } else {
          content += "\(RNGitPageMicron.escape(tag.commitSubject))\n\n"
        }
      }
    }

    if (showHeads && refs.heads.isEmpty) && (showTags && refs.tags.isEmpty) {
      content += "No refs found in this repository.\n"
    }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    content = Self.rstripped(content) + "\n"

    return templates.render(
      content, navigation: navigation, template: RNGitPageTemplate.refs.rawValue,
      startedAt: startedAt)
  }

  // MARK: - Repository page

  /// One repository: its description, where it stands, and its readme.
  public mutating func serveRepoPage(
    identityHash: Data?, groupName: String, repositoryName: String, ref: String = "HEAD",
    thanksClicked: Bool = false, linkID: Data? = nil
  ) -> Data {
    let startedAt = Date().timeIntervalSince1970

    guard !groupName.isEmpty, !repositoryName.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nInvalid request\n", startedAt: startedAt)
    }

    let repoURL =
      RNGitPage.Colour.dim + "rns://" + RNSUtilities.hexrep(destinationHash, delimit: false) + "/"
      + groupName + "/" + repositoryName + "`f"
    var navigation =
      ">>\n" + RNGitPageMicron.link("Node", RNGitPage.Path.index) + " / "
      + RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]) + " / "
      + repositoryName + " " + repoURL + "\n"

    let repository = access.repository(
      readableBy: identityHash, in: groupName, named: repositoryName)

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", navigation: navigation, template: RNGitPageTemplate.noIdentity.rawValue,
        startedAt: startedAt)
    }

    guard let repository else {
      return templates.render(
        RNGitPageMicron.heading("Not Found", level: 1)
          + "\nThe requested repository was not found.\n",
        navigation: navigation, startedAt: startedAt)
    }

    if let fork = repository.fork, !fork.isEmpty {
      navigation += sourceLine(
        type: "fork", sourceURL: fork, groupName: groupName, repositoryName: repositoryName,
        repositoryPath: repository.path)
    } else if let mirror = repository.mirror, !mirror.isEmpty {
      navigation += sourceLine(
        type: "mirror", sourceURL: mirror, groupName: groupName, repositoryName: repositoryName,
        repositoryPath: repository.path)
    }

    let description = reader.description(of: repository.path).map { $0 + "\n\n" } ?? ""
    let thanksCount = thanks.repository(
      at: repository.path, thankedBy: thanksClicked ? linkID : nil)

    var content = description

    let refs = reader.references(of: repository.path)
    let resolvedRef = reader.resolve(ref, in: repository.path)
    let commitsCount = resolvedRef.map { reader.commitCount(in: repository.path, at: $0) } ?? 0
    let branchCount = refs.heads.count
    let tagCount = refs.tags.count
    let workCount = reader.activeWorkDocumentCount(of: repository.path)
    let releasesCount = Self.publishedReleaseCount(of: repository.path)

    let sep = RNGitPage.icon(.separator)
    var statsLinks = [
      RNGitPageMicron.requestLink(
        RNGitPage.icon(.folder) + " Files", RNGitPage.Path.tree,
        [("g", groupName), ("r", repositoryName), ("ref", "HEAD")])
    ]
    if releasesCount > 0 {
      statsLinks.append(
        RNGitPageMicron.requestLink(
          RNGitPage.icon(.package) + " Releases (\(releasesCount))", RNGitPage.Path.releases,
          [("g", groupName), ("r", repositoryName)]))
    }
    statsLinks.append(
      RNGitPageMicron.requestLink(
        RNGitPage.icon(.work) + " Work (\(workCount))", RNGitPage.Path.work,
        [("g", groupName), ("r", repositoryName)]))
    statsLinks.append(
      RNGitPageMicron.requestLink(
        RNGitPage.icon(.commits) + " Commits (\(commitsCount))", RNGitPage.Path.commits,
        [("g", groupName), ("r", repositoryName), ("ref", "HEAD")]))
    statsLinks.append(
      RNGitPageMicron.requestLink(
        RNGitPage.icon(.branch) + " Branches (\(branchCount))", RNGitPage.Path.refs,
        [("g", groupName), ("r", repositoryName), ("type", "heads")]))
    statsLinks.append(
      RNGitPageMicron.requestLink(
        RNGitPage.icon(.tag) + " Tags (\(tagCount))", RNGitPage.Path.refs,
        [("g", groupName), ("r", repositoryName), ("type", "tags")]))
    statsLinks.append(
      RNGitPageMicron.requestLink(
        RNGitPage.icon(.heart) + " Thanks (\(thanksCount))", RNGitPage.Path.repository,
        [("g", groupName), ("r", repositoryName), ("thanks", "y")]))
    if access.allows(
      identityHash, group: groupName, repository: repositoryName, permission: .stats)
    {
      statsLinks.append(
        RNGitPageMicron.requestLink(
          RNGitPage.icon(.stats) + " Stats", RNGitPage.Path.stats,
          [("g", groupName), ("r", repositoryName)]))
    }
    content += statsLinks.joined(separator: " \(sep) ") + "\n\n<"

    if let readme = reader.readme(of: repository.path) {
      let leading = readme.content.drop { $0.isWhitespace }
      if !leading.hasPrefix("#") && !leading.hasPrefix(">") {
        content += RNGitPageMicron.divider()
      }
      if readme.isMarkdown {
        let urlScope = ":/page/blob.mu`g=\(groupName)|r=\(repositoryName)|ref=\(ref)|path="
        let converter = MarkdownToMicron(
          maxWidth: RNGitPage.maxRenderWidth, syntaxHighlighter: syntaxHighlighter,
          urlScope: urlScope)
        content += converter.formatBlock(readme.content)
      } else {
        content += "\n\(Self.rstripped(readme.content))\n"
      }
    } else {
      content += RNGitPageMicron.divider()
      content += "\n"
      content += RNGitPageMicron.italic("No README file found in this repository.")
      content += "\n"
    }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    return templates.render(
      content, navigation: navigation, template: RNGitPageTemplate.repo.rawValue,
      startedAt: startedAt)
  }

  /// How many releases under `repository` are published.
  private static func publishedReleaseCount(of repository: String) -> Int {
    let directory = RNGitReleaseStore.directory(forRepository: repository)
    guard let listing = RNGitReleaseStore.listing(directory) else { return 0 }
    return listing.releases.filter { value in
      guard case .map(let fields) = value else { return false }
      return fields.first { $0.0 == .string("status") }?.1 == .string("published")
    }.count
  }

  /// The line a repository's navigation carries when it was forked or mirrored from elsewhere.
  private func sourceLine(
    type sourceType: String, sourceURL: String, groupName: String, repositoryName: String,
    repositoryPath: String
  ) -> String {
    var displayURL = sourceURL
    if sourceURL.lowercased().hasPrefix("rns://") {
      let components = sourceURL.split(separator: "/", omittingEmptySubsequences: false).map(
        String.init)
      let hashHexLength = Identity.truncatedHashLength / 8 * 2
      if components.count == 5, components[2].count == hashHexLength,
        let sourceDestination = Data(pythonHex: components[2]),
        let sourceIdentity = Identity.recall(destinationHash: sourceDestination)
      {
        let sourcePageDestination = Destination.hash(
          fromFullName: RNGitNodeEnvironment.pagesFullName, identity: sourceIdentity)
        displayURL = RNGitPageMicron.externalLink(
          sourceURL, remote: RNSUtilities.hexrep(sourcePageDestination, delimit: false),
          RNGitPage.Path.repository, [("g", components[3]), ("r", components[4])])
      }
    }

    let syncedAgo = max(
      0,
      Date().timeIntervalSince1970
        - Double(RNGitWorkingCopy.lastUpstreamSync(repositoryPath, runner: runner)))
    let syncTime =
      RNStatusRenderer.prettytime(syncedAgo, isFloat: false, compact: true)
      .split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
    let syncText = " `*" + RNGitPage.Colour.dimmer + "synced " + syncTime + " ago`f`*\n"

    let sourceDescription = sourceType + "ed from"
    let breadcrumbLength = "Node / \(groupName) / \(repositoryName)".count
    let indent = String(repeating: " ", count: max(0, breadcrumbLength - sourceDescription.count))
    let capitalised =
      sourceDescription.prefix(1).uppercased() + sourceDescription.dropFirst().lowercased()

    return RNGitPage.Colour.dim + capitalised + indent + " " + displayURL + "`f" + syncText + "\n"
  }

  /// `text` without the whitespace it ends on, matching Python's argument-less `.rstrip()`,
  /// which strips every trailing whitespace character rather than only trailing newlines.
  private static func rstripped(_ text: String) -> String {
    var trimmed = Substring(text)
    while let last = trimmed.last, last.isWhitespace { trimmed = trimmed.dropLast() }
    return String(trimmed)
  }

  // MARK: - Statistics

  /// Counts one view, in the narrowest scope the arguments name.
  ///
  /// A nil `group` and nil `repository` count a front-page view, `group` alone counts that
  /// group's view, and both present count that repository's view — unless `identityHash` is one
  /// the node does not count, or the node counts no views at all.
  private mutating func viewSucceeded(
    group: String?, repository: String?, for identityHash: Data?
  ) {
    if let identityHash, settings.statsIgnored.contains(identityHash) { return }
    guard settings.statsEnabled else { return }
    let day = RNGitStatsStore.day()
    if group == nil, repository == nil {
      statistics.recordPageView(on: day)
    } else if let group, repository == nil {
      statistics.recordGroupView(group, on: day)
    } else if let group, let repository {
      statistics.recordRepositoryView(group, repository, on: day)
    }
  }
}
