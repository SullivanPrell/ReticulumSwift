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
/// back afterward. `thanks` is the exception—a class the node holds for as long as it runs, so
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

  /// The links the node has open, by link identifier, which a media conversion needs.
  public var activeLinks: Set<Data> = []

  /// Where the node writes a file it sends, held against the link that asked for it.
  public var temporaries = RNGitTemporaryDirectories()

  /// Whether an image a page shows is sent converted to WebP.
  ///
  /// Mirrors `self.media_conversion`, which the reference turns on unless the `[pages]`
  /// section's `media_conversion` turns it off.
  public var mediaConversion = true

  /// Converts an image a page shows to WebP.
  public var mediaEncoder = RNGitMediaEncoder()

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

  /// One group's repositories, and what each holds—or that `groupName` names no group
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
  /// branches or just tags, "No refs found" never shows even if that narrowed set is empty—
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

  // MARK: - Tree page

  /// One directory inside a repository: its entries, directories and submodules sorted before
  /// files, alphabetically within each group, and paginated past
  /// `RNGitPage.treeEntriesPerPage` entries.
  ///
  /// Mirrors `serve_tree_page`.
  public mutating func serveTreePage(
    identityHash: Data?, groupName: String, repositoryName: String, ref: String = "HEAD",
    treePath rawTreePath: String = "", page: Int = 0
  ) -> Data {
    let startedAt = Date().timeIntervalSince1970
    let treePath = RNGitPageMicron.unquotePlus(rawTreePath)
    let pageNum = max(0, page)

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", template: RNGitPageTemplate.noIdentity.rawValue, startedAt: startedAt)
    }

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else {
      return templates.render(
        RNGitPageMicron.heading("Not Found", level: 1)
          + "\n\nThe requested repository does not exist or you do not have access to it.\n",
        startedAt: startedAt)
    }

    guard let resolvedRef = reader.resolve(ref, in: repository.path) else {
      let content =
        RNGitPageMicron.heading("Error", level: 2)
        + "\n\nThe ref '\(ref)' does not exist in this repository.\n"
        + "\n"
        + RNGitPageMicron.link(
          "View All Refs", RNGitPage.Path.refs, [("g", groupName), ("r", repositoryName)])
        + "\n"
      return templates.render(content, startedAt: startedAt)
    }

    var contentParts: [String] = []

    var breadcrumbParts = [
      RNGitPageMicron.link("Node", RNGitPage.Path.index),
      RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]),
      RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)]),
      RNGitPageMicron.link(
        "files", RNGitPage.Path.tree, [("g", groupName), ("r", repositoryName)]),
    ]

    if treePath.isEmpty {
      breadcrumbParts.append("")
    } else {
      breadcrumbParts += Self.pathBreadcrumbLinks(
        for: treePath, groupName: groupName, repositoryName: repositoryName, ref: ref)
    }
    let navigation = ">>\n" + breadcrumbParts.joined(separator: " / ") + "\n"

    if let entries = reader.treeEntries(in: repository.path, at: resolvedRef, path: treePath) {
      if entries.isEmpty {
        contentParts.append("Empty directory.\n")
      } else {
        let fileIcon = RNGitPage.icon(.file)
        let folderIcon = RNGitPage.icon(.folder)

        let sorted = entries.sorted { lhs, rhs in
          let lhsIsDirectory = lhs.kind == "tree" || lhs.kind == "commit"
          let rhsIsDirectory = rhs.kind == "tree" || rhs.kind == "commit"
          if lhsIsDirectory != rhsIsDirectory { return lhsIsDirectory }
          return lhs.name.lowercased() < rhs.name.lowercased()
        }

        let totalEntries = sorted.count
        let startIndex = pageNum * RNGitPage.treeEntriesPerPage
        let endIndex = startIndex + RNGitPage.treeEntriesPerPage
        let safeStart = min(startIndex, totalEntries)
        let safeEnd = min(endIndex, totalEntries)
        let pageEntries = Array(sorted[safeStart..<safeEnd])

        contentParts.append(
          RNGitPageMicron.heading(
            "Contents: \(ref) (\(String(resolvedRef.prefix(8))))", level: 2))
        contentParts.append("\n")

        if totalEntries > RNGitPage.treeEntriesPerPage {
          contentParts.append(
            "\(RNGitPage.Colour.dim)Showing \(startIndex + 1)-\(min(endIndex, totalEntries)) "
              + "of \(totalEntries) entries`f\n\n")
        }

        if !treePath.isEmpty {
          let parentComponents = Self.trimmedSlashes(treePath, leading: false)
            .components(separatedBy: "/")
          let parentPath = parentComponents.dropLast().joined(separator: "/")
          let iconLink = RNGitPageMicron.requestLink(
            folderIcon, RNGitPage.Path.tree,
            [("g", groupName), ("r", repositoryName), ("ref", ref), ("path", parentPath)])
          let parentLink = RNGitPageMicron.requestLink(
            " ../", RNGitPage.Path.tree,
            [("g", groupName), ("r", repositoryName), ("ref", ref), ("path", parentPath)])
          contentParts.append("\(RNGitPage.Colour.folder)\(iconLink)`f\(parentLink)\n")
        }

        for entry in pageEntries {
          switch entry.kind {
          case "tree":
            let subpath = treePath.isEmpty ? entry.name : treePath + "/" + entry.name
            let iconLink = RNGitPageMicron.requestLink(
              folderIcon, RNGitPage.Path.tree,
              [("g", groupName), ("r", repositoryName), ("ref", ref), ("path", subpath)])
            let entryLink = RNGitPageMicron.requestLink(
              " \(entry.name)/", RNGitPage.Path.tree,
              [("g", groupName), ("r", repositoryName), ("ref", ref), ("path", subpath)])
            contentParts.append("\(RNGitPage.Colour.folder)\(iconLink)`f\(entryLink)\n")

          case "commit":
            contentParts.append(
              "\(RNGitPage.Colour.folder)⧉`f \(entry.name) \(RNGitPage.Colour.dim)(submodule)`f\n"
            )

          case "link":
            let target = entry.linkTarget ?? "unknown"
            contentParts.append(
              "\(RNGitPage.Colour.file)↳`f \(entry.name) \(RNGitPage.Colour.dim)→ "
                + "\(RNGitPageMicron.escape(target))`f\n")

          default:
            let sizeText = RNSUtilities.prettysize(entry.size)
            let subpath = treePath.isEmpty ? entry.name : treePath + "/" + entry.name
            let iconLink = RNGitPageMicron.requestLink(
              fileIcon, RNGitPage.Path.blob,
              [("g", groupName), ("r", repositoryName), ("ref", ref), ("path", subpath)])
            let entryLink = RNGitPageMicron.requestLink(
              " \(entry.name)", RNGitPage.Path.blob,
              [("g", groupName), ("r", repositoryName), ("ref", ref), ("path", subpath)])
            contentParts.append(
              "\(RNGitPage.Colour.file)\(iconLink)`f\(entryLink) \(RNGitPage.Colour.dim)"
                + "(\(sizeText))`f\n")
          }
        }

        contentParts.append("\n")

        if totalEntries > RNGitPage.treeEntriesPerPage {
          var navLinks: [String] = []
          if pageNum > 0 {
            navLinks.append(
              RNGitPageMicron.link(
                "« Previous", RNGitPage.Path.tree,
                [
                  ("g", groupName), ("r", repositoryName), ("ref", ref), ("path", treePath),
                  ("page", String(pageNum - 1)),
                ]))
          }
          let totalPages =
            (totalEntries + RNGitPage.treeEntriesPerPage - 1) / RNGitPage.treeEntriesPerPage
          navLinks.append("Page \(pageNum + 1) of \(totalPages)")
          if endIndex < totalEntries {
            navLinks.append(
              RNGitPageMicron.link(
                "Next »", RNGitPage.Path.tree,
                [
                  ("g", groupName), ("r", repositoryName), ("ref", ref), ("path", treePath),
                  ("page", String(pageNum + 1)),
                ]))
          }
          contentParts.append(navLinks.joined(separator: " | ") + "\n")
        }
      }
    } else {
      contentParts.append("Error reading directory contents.\n")
    }

    if contentParts.last == "\n" { contentParts[contentParts.count - 1] = "" }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    return templates.render(
      contentParts.joined(), navigation: navigation, template: RNGitPageTemplate.tree.rawValue,
      startedAt: startedAt)
  }

  // MARK: - Blob page

  /// One file inside a repository: its size and type, and its content, rendered, raw and
  /// syntax-highlighted, or offered as a download, depending on what the reader can see and
  /// asked for.
  ///
  /// Mirrors `serve_blob_page`, including its one redirect: a path that names a directory
  /// rather than a file is answered with the tree page instead.
  public mutating func serveBlobPage(
    identityHash: Data?, groupName: String, repositoryName: String, ref: String = "HEAD",
    filePath rawFilePath: String = "", render: Bool = false, raw: Bool = false
  ) -> Data {
    let startedAt = Date().timeIntervalSince1970

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", template: RNGitPageTemplate.noIdentity.rawValue, startedAt: startedAt)
    }

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else {
      return templates.render(
        RNGitPageMicron.heading("Not Found", level: 1)
          + "\n\nThe requested repository does not exist or you do not have access to it.\n",
        startedAt: startedAt)
    }

    guard let resolvedRef = reader.resolve(ref, in: repository.path) else {
      return templates.render(
        RNGitPageMicron.heading("Ref Not Found", level: 1)
          + "\n\nThe ref '\(ref)' does not exist in this repository.\n",
        startedAt: startedAt)
    }

    let filePath = Self.normalisedBlobPath(RNGitPageMicron.unquotePlus(rawFilePath))
    guard !filePath.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Invalid Path", level: 1) + "\n\nNo file path specified.\n",
        startedAt: startedAt)
    }

    let fileExtension = Self.fileExtension(of: filePath)
    let renderable = RNGitPage.renderableExtensions.contains(fileExtension)
    var render = render
    var raw = raw
    if !renderable {
      raw = true
      render = false
    } else if raw {
      render = false
    } else if !render, RNGitPage.renderDefault.contains(fileExtension) {
      render = true
      raw = false
    }

    var contentParts: [String] = []
    var navParts: [String] = []

    var breadcrumbParts = [
      RNGitPageMicron.link("Node", RNGitPage.Path.index),
      RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]),
      RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)]),
      RNGitPageMicron.link(
        "files", RNGitPage.Path.tree, [("g", groupName), ("r", repositoryName)]),
    ]
    breadcrumbParts += Self.pathBreadcrumbLinks(
      for: filePath, groupName: groupName, repositoryName: repositoryName, ref: ref)
    navParts.append(">>\n" + breadcrumbParts.joined(separator: " / ") + "\n")

    let sep = RNGitPage.icon(.separator)
    let downloadLink = RNGitPageMicron.link(
      "Download", RNGitPage.Path.download,
      [("g", groupName), ("r", repositoryName), ("ref", ref), ("path", filePath)])

    if !renderable {
      navParts.append("\nDisplaying Raw \(sep) \(downloadLink)\n")
    } else {
      let renderedLink = RNGitPageMicron.link(
        "View rendered", RNGitPage.Path.blob,
        [
          ("g", groupName), ("r", repositoryName), ("ref", ref), ("path", filePath),
          ("render", "y"),
        ])
      let rawLink = RNGitPageMicron.link(
        "View raw", RNGitPage.Path.blob,
        [("g", groupName), ("r", repositoryName), ("ref", ref), ("path", filePath), ("raw", "y")])
      let renderControls =
        render
        ? "Displaying Rendered \(sep) \(rawLink)" : "Displaying Raw \(sep) \(renderedLink)"
      navParts.append("\n\(renderControls) \(sep) \(downloadLink)\n")
    }

    if let blobInfo = reader.blobInfo(in: repository.path, at: resolvedRef, path: filePath) {
      if blobInfo.isTree {
        return serveTreePage(
          identityHash: identityHash, groupName: groupName, repositoryName: repositoryName,
          ref: ref, treePath: rawFilePath, page: 0)
      }

      let typeText = blobInfo.isBinary ? "Binary" : "Text"
      let sizeText = RNSUtilities.prettysize(blobInfo.size)
      let symlinkText =
        blobInfo.isSymlink
        ? " | Symlink → \(RNGitPageMicron.escape(blobInfo.symlinkTarget ?? "unknown"))" : ""
      contentParts.append(
        RNGitPageMicron.heading(
          "\(filePath) \(RNGitPage.Colour.dimmer)\(ref) (\(String(resolvedRef.prefix(8)))) "
            + "\(typeText), \(sizeText)\(symlinkText)`f\n", level: 2))

      if blobInfo.isSymlink {
        contentParts.append(
          "`*\(RNGitPageMicron.escape(blobInfo.symlinkTarget ?? "unknown"))`*\n")
      } else if blobInfo.isBinary {
        if RNGitPage.imageExtensions.contains(fileExtension) {
          let encodedPath = RNGitPageMicron.quotePlus(filePath)
          contentParts.append(
            "`(Image file`w=n`a=c`:/media/\(groupName)/\(repositoryName)/\(ref)/\(encodedPath))\n"
          )
        } else {
          contentParts.append("This file appears to be binary and cannot be displayed as text.\n")
        }
      } else if blobInfo.size > RNGitPage.blobSizeLimit {
        contentParts.append(
          "This file is \(RNSUtilities.prettysize(blobInfo.size)), which exceeds the display "
            + "limit of \(RNSUtilities.prettysize(RNGitPage.blobSizeLimit)).\n")
      } else if let blobContent = reader.blobContent(
        in: repository.path, at: resolvedRef, path: filePath)
      {
        if renderable, render {
          if fileExtension == ".mu" {
            contentParts.append(Self.rstripped(blobContent) + "\n")
          } else if fileExtension == ".md" {
            let pathComponents = Self.trimmedSlashes(filePath).components(separatedBy: "/")
            let scopePath =
              pathComponents.count > 1
              ? pathComponents.dropLast().joined(separator: "/") + "/" : ""
            let urlScope =
              ":/page/blob.mu`g=\(groupName)|r=\(repositoryName)|ref=\(ref)|path=\(scopePath)"
            let converter = MarkdownToMicron(
              maxWidth: RNGitPage.maxRenderWidth, syntaxHighlighter: syntaxHighlighter,
              urlScope: urlScope)
            contentParts.append(Self.rstripped(converter.formatBlock(blobContent)) + "\n")
          } else {
            contentParts.append("`=\n\(blobContent)\n`=")
          }
        } else if settings.highlightSyntax {
          let highlighted =
            (try? syntaxHighlighter.highlight(blobContent, filename: filePath, language: nil))
            ?? blobContent
          contentParts.append(Self.rstripped(highlighted) + "\n")
        } else {
          contentParts.append("`=\n\(blobContent)\n`=")
        }
      } else {
        contentParts.append("Error reading file content.\n")
      }
    } else {
      contentParts.append("File not found at this ref.\n")
    }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    return templates.render(
      contentParts.joined(), navigation: navParts.joined(),
      template: RNGitPageTemplate.blob.rawValue, startedAt: startedAt)
  }

  /// The breadcrumb entries for each component of `path`: every one but the last a link to
  /// that directory's tree page, and the last one bare.
  private static func pathBreadcrumbLinks(
    for path: String, groupName: String, repositoryName: String, ref: String
  ) -> [String] {
    let components = trimmedSlashes(path).components(separatedBy: "/")
    var links: [String] = []
    var currentPath = ""
    for (index, component) in components.enumerated() {
      currentPath = currentPath.isEmpty ? component : currentPath + "/" + component
      if index == components.count - 1 {
        links.append(component)
      } else {
        links.append(
          RNGitPageMicron.link(
            component, RNGitPage.Path.tree,
            [("g", groupName), ("r", repositoryName), ("ref", ref), ("path", currentPath)]))
      }
    }
    return links
  }

  /// `path` with a leading `./` dropped and any interior `/./` collapsed, matching Python's
  /// `removeprefix("./").replace("/./", "/")`.
  private static func normalisedBlobPath(_ path: String) -> String {
    var normalised = path
    if normalised.hasPrefix("./") { normalised.removeFirst(2) }
    return normalised.replacingOccurrences(of: "/./", with: "/")
  }

  // MARK: - Commits page

  /// A repository's commit history, optionally scoped to one file's changes, paginated past
  /// `RNGitPage.commitsPerPage` commits.
  ///
  /// Mirrors `serve_commits_page`.
  public mutating func serveCommitsPage(
    identityHash: Data?, groupName: String, repositoryName: String, ref: String = "HEAD",
    filePath rawFilePath: String = "", page: Int = 0
  ) -> Data {
    let startedAt = Date().timeIntervalSince1970
    let filePath = RNGitPageMicron.unquotePlus(rawFilePath)
    let pageNum = max(0, page)

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", template: RNGitPageTemplate.noIdentity.rawValue, startedAt: startedAt)
    }

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else {
      return templates.render(
        RNGitPageMicron.heading("Not Found", level: 1)
          + "\n\nThe requested repository does not exist or you do not have access to it.\n",
        startedAt: startedAt)
    }

    guard let resolvedRef = reader.resolve(ref, in: repository.path) else {
      return templates.render(
        RNGitPageMicron.heading("Ref Not Found", level: 1)
          + "\n\nThe ref '\(ref)' does not exist in this repository.\n",
        startedAt: startedAt)
    }

    var contentParts: [String] = []

    var breadcrumbParts = [
      RNGitPageMicron.link("Node", RNGitPage.Path.index),
      RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]),
      RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)]),
      "commits",
    ]
    if !filePath.isEmpty { breadcrumbParts.insert(RNGitPageMicron.escape(filePath), at: 3) }
    let navigation = ">>\n" + breadcrumbParts.joined(separator: " / ") + "\n"

    let titleSuffix = filePath.isEmpty ? "" : " for \(filePath)"

    let skip = pageNum * RNGitPage.commitsPerPage
    let commits = reader.commits(
      in: repository.path, at: resolvedRef, path: filePath, skip: skip,
      limit: RNGitPage.commitsPerPage)

    switch commits {
    case nil:
      contentParts.append("Error reading commit history.\n")

    case .some(let commits) where commits.isEmpty:
      contentParts.append("No commits found.\n")

    case .some(let commits):
      contentParts.append(
        RNGitPageMicron.heading(
          "Commits\(titleSuffix) \(RNGitPage.Colour.dimmer)\(ref) "
            + "(\(String(resolvedRef.prefix(8))))`f", level: 2))
      contentParts.append("\n")

      for commit in commits {
        let shortHash = String(commit.hash.prefix(7))
        let date =
          RNGitPageFormatting.absoluteTime(TimeInterval(commit.timestamp)) + " - "
          + RNGitPageFormatting.relativeTime(TimeInterval(commit.timestamp))
        let hashLink = RNGitPageMicron.link(
          shortHash, RNGitPage.Path.commit,
          [("g", groupName), ("r", repositoryName), ("ref", ref), ("h", commit.hash)])
        contentParts.append(
          "\(RNGitPage.Colour.file)\(hashLink)`f \(RNGitPageMicron.escape(commit.author)) "
            + "\(RNGitPage.Colour.dim)\(date)`f\n")
        contentParts.append("\(RNGitPageMicron.escape(commit.subject))\n\n")
      }

      let hasMore = commits.count == RNGitPage.commitsPerPage
      if pageNum > 0 || hasMore {
        var navLinks: [String] = []
        if pageNum > 0 {
          navLinks.append(
            RNGitPageMicron.link(
              "« Newer", RNGitPage.Path.commits,
              [
                ("g", groupName), ("r", repositoryName), ("ref", ref), ("path", filePath),
                ("page", String(pageNum - 1)),
              ]))
        }
        navLinks.append("Page \(pageNum + 1)")
        if hasMore {
          navLinks.append(
            RNGitPageMicron.link(
              "Older »", RNGitPage.Path.commits,
              [
                ("g", groupName), ("r", repositoryName), ("ref", ref), ("path", filePath),
                ("page", String(pageNum + 1)),
              ]))
        }
        contentParts.append(navLinks.joined(separator: " | ") + "\n")
      }
    }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    return templates.render(
      contentParts.joined(), navigation: navigation, template: RNGitPageTemplate.commits.rawValue,
      startedAt: startedAt)
  }

  // MARK: - Commit page

  /// One commit: its metadata, message, signature status, changed files and diff.
  ///
  /// Mirrors `serve_commit_page`, including two divergences from its sibling pages: a repository
  /// that cannot be found here reads "was not found" at an "Error" heading, not the "Not Found"
  /// wording the other pages use, and none of this page's own error replies below carry the
  /// breadcrumb, even once it has been built, the way the closing, successful reply does.
  public mutating func serveCommitPage(
    identityHash: Data?, groupName: String, repositoryName: String, ref: String = "HEAD",
    commitHash: String = ""
  ) -> Data {
    let startedAt = Date().timeIntervalSince1970

    guard !groupName.isEmpty, !repositoryName.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nInvalid request\n", startedAt: startedAt)
    }

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", template: RNGitPageTemplate.noIdentity.rawValue, startedAt: startedAt)
    }

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2)
          + "\nThe requested repository was not found.\n",
        startedAt: startedAt)
    }

    guard let resolvedRef = reader.resolve(ref, in: repository.path) else {
      return templates.render(
        RNGitPageMicron.heading("Ref Not Found", level: 1)
          + "\n\nThe ref '\(ref)' does not exist in this repository.\n",
        startedAt: startedAt)
    }

    guard !commitHash.isEmpty, commitHash.count >= 7 else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nNo valid commit hash specified.\n",
        startedAt: startedAt)
    }

    guard let resolvedHash = reader.resolve(commitHash, in: repository.path) else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2)
          + "\nThe commit \(commitHash) does not exist in this repository.\n",
        startedAt: startedAt)
    }

    let breadcrumb = [
      RNGitPageMicron.link("Node", RNGitPage.Path.index),
      RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]),
      RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)]),
      RNGitPageMicron.link(
        "commits", RNGitPage.Path.commits,
        [("g", groupName), ("r", repositoryName), ("ref", ref)]),
      String(resolvedHash.prefix(7)),
    ].joined(separator: " / ")
    let navigation = ">>\n" + breadcrumb + "\n"

    let commitCheck = reader.isCommit(resolvedHash, in: repository.path)
    if commitCheck == false {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2)
          + "\nThe hash \(commitHash) does not refer to a commit.\n",
        startedAt: startedAt)
    }
    if commitCheck == nil {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nCould not verify commit object.\n",
        startedAt: startedAt)
    }

    guard let commitInfo = reader.commitInfo(in: repository.path, of: resolvedHash) else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\n\nCould not retrieve commit information.\n",
        startedAt: startedAt)
    }

    var contentParts: [String] = []
    contentParts.append(RNGitPageMicron.heading("Commit \(resolvedHash)", level: 2))
    contentParts.append("\n")

    let folderIcon = RNGitPage.icon(.folder)
    contentParts.append(
      RNGitPageMicron.link(
        "\(folderIcon) Browse tree at this commit", RNGitPage.Path.tree,
        [("g", groupName), ("r", repositoryName), ("ref", resolvedHash)]) + "\n\n")

    var showSig = false
    let sigStatus = reader.commitSignature(in: repository.path, of: resolvedHash)
    let sigText: String
    if sigStatus.signed {
      if sigStatus.valid, sigStatus.authorMatch {
        sigText = "`FT66BB85Valid, signed by author`f"
        showSig = true
      } else if sigStatus.valid {
        sigText = "`Faa0\(RNGitPageMicron.escape(sigStatus.message))`f"
        showSig = true
      } else {
        sigText = "\(RNGitPage.Colour.diffRemoved)\(RNGitPageMicron.escape(sigStatus.message))`f"
        showSig = true
      }
    } else {
      sigText = "Not signed"
    }

    if !commitInfo.parents.isEmpty {
      let parentLinks = commitInfo.parents.map { parentHash in
        RNGitPageMicron.link(
          String(parentHash.prefix(7)), RNGitPage.Path.commit,
          [("g", groupName), ("r", repositoryName), ("ref", ref), ("h", parentHash)])
      }
      contentParts.append("Parents    : \(parentLinks.joined(separator: " "))\n")
    }

    contentParts.append(
      "Author     : \(RNGitPageMicron.escape(commitInfo.authorName)) "
        + "<\(RNGitPageMicron.escape(commitInfo.authorEmail))>\n")
    if showSig { contentParts.append("Signature  : \(sigText)\n") }
    contentParts.append("Date       : \(commitInfo.authorDate)\n")

    if commitInfo.committerName != commitInfo.authorName {
      contentParts.append(
        "Committer : \(RNGitPageMicron.escape(commitInfo.committerName)) "
          + "<\(RNGitPageMicron.escape(commitInfo.committerEmail))>\n")
      contentParts.append("Date      : \(commitInfo.committerDate)\n")
    }

    contentParts.append("\n")

    if !commitInfo.message.isEmpty {
      contentParts.append(RNGitPageFormatting.commit(commitInfo.message) + "\n")
      contentParts.append("\n")
    }

    if !commitInfo.files.isEmpty {
      contentParts.append(RNGitPageMicron.heading("Changes", level: 2))
      contentParts.append("\n")

      let totalAdditions = commitInfo.files.reduce(0) { $0 + $1.additions }
      let totalDeletions = commitInfo.files.reduce(0) { $0 + $1.deletions }
      contentParts.append(
        "  \(commitInfo.files.count) files changed, \(totalAdditions) insertions(+), "
          + "\(totalDeletions) deletions(-)\n\n")

      for fileInfo in commitInfo.files {
        let statusDisplay: String
        switch fileInfo.status {
        case "A": statusDisplay = "\(RNGitPage.Colour.diffAdded)A`f"
        case "D": statusDisplay = "\(RNGitPage.Colour.diffRemoved)D`f"
        case "M": statusDisplay = "`Faa0M`f"
        case "R": statusDisplay = "\(RNGitPage.Colour.diffPosition)R`f"
        default: statusDisplay = fileInfo.status
        }

        let fileLink = RNGitPageMicron.link(
          RNGitPageMicron.escape(fileInfo.path), RNGitPage.Path.blob,
          [
            ("g", groupName), ("r", repositoryName), ("ref", resolvedHash),
            ("path", fileInfo.path),
          ])

        var stats: [String] = []
        if fileInfo.additions > 0 {
          stats.append("\(RNGitPage.Colour.diffAdded)+\(fileInfo.additions)`f")
        }
        if fileInfo.deletions > 0 {
          stats.append("\(RNGitPage.Colour.diffRemoved)-\(fileInfo.deletions)`f")
        }

        contentParts.append("  \(statusDisplay) \(fileLink) \(stats.joined(separator: " "))\n")
      }

      contentParts.append("\n")
    }

    if RNGitPage.showDiffByDefault, let diff = commitInfo.diff, !diff.isEmpty {
      contentParts.append(RNGitPageMicron.heading("Diff", level: 2))
      contentParts.append("\n")
      let formattedDiff = RNGitPageFormatting.diff(diff)
      contentParts.append(String(formattedDiff.drop(while: \.isWhitespace)))
    }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    return templates.render(
      contentParts.joined(), navigation: navigation, template: RNGitPageTemplate.commit.rawValue,
      startedAt: startedAt)
  }

  /// The extension of `path`, lowercased and with its leading dot, or empty where it has none.
  private static func fileExtension(of path: String) -> String {
    let extensionText = (path as NSString).pathExtension
    return extensionText.isEmpty ? "" : "." + extensionText.lowercased()
  }

  /// `text` with its leading and/or trailing `/` characters removed, matching Python's
  /// `.strip("/")` (both ends) or `.rstrip("/")` (`leading: false`).
  private static func trimmedSlashes(_ text: String, leading: Bool = true, trailing: Bool = true)
    -> String
  {
    var result = Substring(text)
    if leading { while result.hasPrefix("/") { result = result.dropFirst() } }
    if trailing { while result.hasSuffix("/") { result = result.dropLast() } }
    return String(result)
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
  static func rstripped(_ text: String) -> String {
    var trimmed = Substring(text)
    while let last = trimmed.last, last.isWhitespace { trimmed = trimmed.dropLast() }
    return String(trimmed)
  }

  // MARK: - Statistics

  /// Counts one view, in the narrowest scope the arguments name.
  ///
  /// A nil `group` and nil `repository` count a front-page view, `group` alone counts that
  /// group's view, and both present count that repository's view—unless `identityHash` is one
  /// the node does not count, or the node counts no views at all.
  mutating func viewSucceeded(
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
