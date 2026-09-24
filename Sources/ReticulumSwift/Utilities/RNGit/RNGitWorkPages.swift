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

extension RNGitPageHandler {

  /// The most of a title the work page lists a document under.
  public static let workListingTitleLength = 92

  /// The most of a title a work document's page is headed with.
  public static let workDocumentTitleLength = 256

  /// The scopes a work page may be asked for; any other is read as `active`.
  static let workScopes = ["active", "completed", "proposed", "all"]

  // MARK: - Work page

  /// The work documents of one repository the reader may read, in the scope asked for, each
  /// section newest first—or nil where the reference raises and answers nothing.
  ///
  /// Mirrors `serve_work_page` (`pages.py:1461-1561`). A document is ordered by the later of
  /// when it was created and when it was edited, and the reference raises where those cannot
  /// be compared, or where a document's title cannot be cut short or its creation cannot be
  /// dated. An entry that is not a document the reader may read is passed over, and so is
  /// one the reference raises on while reading it.
  public mutating func serveWorkPage(
    identityHash: Data?, groupName: String, repositoryName: String,
    scope requested: String = "active", timeZone: TimeZone = .current
  ) -> Data? {
    let startedAt = Date().timeIntervalSince1970
    let scope = Self.workScopes.contains(requested) ? requested : "active"

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

    let navigation =
      ">>\n" + RNGitPageMicron.link("Node", RNGitPage.Path.index) + " / "
      + RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]) + " / "
      + RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)])
      + " / work\n"

    let filters = [
      ("Active", "active"), ("Completed", "completed"), ("Proposed", "proposed"), ("All", "all"),
    ].map { label, name in
      let underline = name == scope ? "`_" : ""
      return underline
        + RNGitPageMicron.link(
          label, RNGitPage.Path.work,
          [("g", groupName), ("r", repositoryName), ("scope", name)]) + underline
    }
    var content = filters.joined(separator: " \(RNGitPage.icon(.separator)) ") + "\n\n"

    let work = RNGitWorkStore.directory(forRepository: repository.path)
    let rendering = RNGitReleaseRendering(timeZone: timeZone)
    let dim = RNGitPage.Colour.dim
    for folder in scope == "all" ? RNGitWorkStore.scopes : [scope] {
      guard
        let listed = listedDocuments(
          in: work + "/" + folder, reader: identityHash, group: groupName,
          repository: repositoryName)
      else { return nil }

      let heading = RNGitPageMicron.heading(
        "\(Self.capitalised(folder)) (\(listed.count))", level: 2)
      guard !listed.isEmpty else {
        content += heading + "\n`*No \(folder) work documents`*\n\n"
        continue
      }

      content += heading + "\n"
      for document in listed {
        guard
          let title = Self.shortened(
            document.title, to: Self.workListingTitleLength, appendingToText: true),
          let author = Self.prettyHex(document.author, otherwise: "unknown"),
          let created = Self.localTime(document.created, "yyyy-MM-dd", rendering, otherwise: "")
        else { return nil }
        let link = RNGitPageMicron.link(
          RNGitPage.icon(.file) + " " + title, RNGitPage.Path.workDocument,
          [
            ("g", groupName), ("r", repositoryName), ("id", String(document.number)),
            ("scope", folder),
          ])
        content += "\(link) \(dim)#\(document.number)`f\n"
        content += "\(dim)\(created) by \(author)`f\n"
        if document.comments > 0 { content += "\(dim)\(document.comments) updates`f\n" }
        content += "\n"
      }
    }
    if content.hasSuffix("\n") { content.removeLast() }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    return templates.render(
      content, navigation: navigation, template: RNGitPageTemplate.work.rawValue,
      startedAt: startedAt)
  }

  /// One document as the work page lists it.
  private struct ListedWorkDocument {
    let number: Int
    let title: MsgPack.Value
    let created: MsgPack.Value
    let author: MsgPack.Value
    let comments: Int
  }

  /// The documents under `folder` the reader may read, newest first, or nil where ordering
  /// them raises.
  private func listedDocuments(
    in folder: String, reader: Data?, group: String, repository: String
  ) -> [ListedWorkDocument]? {
    guard RNGitWorkStore.isDirectory(folder) else { return [] }
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else {
      return nil
    }

    var listed: [(key: MsgPack.Value, value: ListedWorkDocument)] = []
    for entry in entries {
      let directory = folder + "/" + entry
      guard RNGitWorkStore.isDirectory(directory),
        let number = entry.pythonInteger,
        access.allowsDocument(
          reader, group: group, repository: repository, number: number, permission: .read),
        RNGitWorkStore.isFile(directory + "/root"),
        let document = RNGitWorkStore.document(at: directory + "/root"),
        document.pythonIsTruthy,
        let fields = RNGitRequestFields(document),
        let meta = RNGitRequestFields(fields["meta"] ?? .map([])),
        let numbered = RNGitWorkStore.numbered(directory)
      else { continue }

      let created = meta["created"] ?? .int(0)
      let edited = meta["edited"] ?? .int(0)
      guard let later = created.pythonPrecedes(edited) else { return nil }
      listed.append(
        (
          later ? edited : created,
          ListedWorkDocument(
            number: number, title: meta["title"] ?? .string("Untitled"), created: created,
            author: meta["author"] ?? .bytes(Data()),
            comments: numbered.filter { RNGitWorkStore.isFile(directory + "/" + $0) }.count)
        ))
    }
    return RNGitWorkStore.descending(listed)
  }

  // MARK: - Work document page

  /// One work document with its signature checked and every update posted to it—or nil where
  /// the reference raises and answers nothing.
  ///
  /// Mirrors `serve_work_doc_page` (`pages.py:1563-1713`). A scope of `all` finds the document
  /// in the first scope holding it, and any scope not asked for by name is read as `active`.
  /// The document is looked for under the number `documentID` reads as, so a document kept in a
  /// directory named with leading zeroes is not found. The reference raises on a document
  /// without `meta`, on one whose title cannot be cut short, and on one whose times cannot be
  /// dated.
  ///
  /// An update is shown as Markdown unless it names another format beside its content, which a
  /// node never writes there; the reference reads the format from that place, not from the
  /// update's `meta`.
  public mutating func serveWorkDocumentPage(
    identityHash: Data?, groupName: String, repositoryName: String, documentID: String,
    scope requested: String = "all", timeZone: TimeZone = .current
  ) -> Data? {
    let startedAt = Date().timeIntervalSince1970
    var scope = Self.workScopes.contains(requested) ? requested : "active"

    func failure(_ heading: String, _ message: String) -> Data {
      templates.render(
        RNGitPageMicron.heading(heading, level: 2) + "\n" + message + "\n", startedAt: startedAt)
    }

    guard !groupName.isEmpty, !repositoryName.isEmpty, !documentID.isEmpty else {
      return failure("Error", "Invalid request")
    }

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", template: RNGitPageTemplate.noIdentity.rawValue, startedAt: startedAt)
    }

    guard let number = documentID.pythonInteger else {
      return failure("Error", "Invalid document ID")
    }
    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else { return failure("Error", "The requested repository was not found") }
    guard
      access.allowsDocument(
        identityHash, group: groupName, repository: repositoryName, number: number,
        permission: .read)
    else { return failure("Error", "The requested work document was not found") }

    let work = RNGitWorkStore.directory(forRepository: repository.path)
    func held(in folder: String) -> String { work + "/" + folder + "/" + String(number) }
    if scope == "all" {
      scope =
        RNGitWorkStore.scopes.dropLast().first { RNGitWorkStore.isDirectory(held(in: $0)) }
        ?? "proposed"
    }
    let directory = held(in: scope)

    guard RNGitWorkStore.isFile(directory + "/root") else {
      return failure("Not Found", "The requested work document was not found")
    }
    guard let document = RNGitWorkStore.document(at: directory + "/root"),
      document.pythonIsTruthy
    else { return failure("Error", "Could not load work document") }

    guard let fields = RNGitRequestFields(document), let metaValue = fields["meta"],
      let meta = RNGitRequestFields(metaValue),
      let title = Self.shortened(
        meta["title"] ?? .string("Untitled"), to: Self.workDocumentTitleLength,
        appendingToText: false),
      let author = Self.prettyHex(meta["author"] ?? .bytes(Data()), otherwise: "Unknown")
    else { return nil }

    let body = fields["content"] ?? .string("")
    var signature = "Document not signed"
    if case .bytes(let signed)? = meta["signature"], signed.count == Identity.sigLength / 8,
      case .bytes(let key)? = meta["identity"], key.count == Identity.keySize / 8
    {
      guard case .string(let text) = body else { return nil }
      let identity = try? Identity(publicKeyBytes: key)
      let valid = identity?.validate(signature: signed, for: Data(text.utf8)) ?? false
      signature = valid ? "Valid" : "Not valid"
    }

    let rendering = RNGitReleaseRendering(timeZone: timeZone)
    let created = meta["created"] ?? .int(0)
    let edited = meta["edited"] ?? .int(0)
    let dim = RNGitPage.Colour.dim
    guard
      let createdAt = Self.localTime(
        created, "yyyy-MM-dd HH:mm", rendering, otherwise: "unknown")
    else { return nil }

    var content = RNGitPageMicron.heading(title, level: 2)
    content += "\n\(dim)Author    : \(author)`f\n"
    content += "\(dim)Signature : \(signature)`f\n"
    content += "\(dim)Created   : \(createdAt)`f\n"
    if edited.pythonIsTruthy, !edited.pythonEquals(created) {
      guard let editedAt = Self.localTime(edited, "yyyy-MM-dd HH:mm", rendering, otherwise: "")
      else { return nil }
      content += "\(dim)Edited    : \(editedAt)`f\n"
    }
    content += "\(dim)Status    : \(Self.capitalised(scope))`f\n\n"

    switch body {
    case .string(let text):
      let stripped = text.pythonStripped
      if !stripped.isEmpty {
        content +=
          meta["format"] == .string("micron") ? stripped : markdownRenderer.formatBlock(stripped)
        content += "\n"
      }
    case .bytes(let bytes):
      guard bytes.pythonStripped.isEmpty else { return nil }
    default: return nil
    }

    guard let updates = Self.updates(in: directory) else { return nil }
    if !updates.isEmpty {
      content += "\n" + RNGitPageMicron.heading("Updates (\(updates.count))", level: 2)
      for update in updates {
        let text: String
        if update.format == .string("markdown") {
          guard case .string(let markdown) = update.content else { return nil }
          text = markdownRenderer.formatBlock(markdown)
        } else {
          text = update.content.pythonDescription
        }
        guard let by = Self.prettyHex(update.author, otherwise: "Unknown"),
          let on = Self.localTime(
            update.created, "yyyy-MM-dd HH:mm", rendering, otherwise: "unknown")
        else { return nil }
        content += "\n\(dim)#\(update.number) by \(by) on \(on)`f\n"
        content += "\(text)\n"
      }
    }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    let download = RNGitPageMicron.link(
      "Download", RNGitPage.Path.workDocumentFile,
      [("g", groupName), ("r", repositoryName), ("id", String(number))])
    let navigation =
      ">>\n" + RNGitPageMicron.link("Node", RNGitPage.Path.index) + " / "
      + RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]) + " / "
      + RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)])
      + " / "
      + RNGitPageMicron.link(
        "work", RNGitPage.Path.work, [("g", groupName), ("r", repositoryName)])
      + " / #\(number)\n\n\(download)\n"

    return templates.render(
      content, navigation: navigation, template: RNGitPageTemplate.workDocument.rawValue,
      startedAt: startedAt)
  }

  /// One update posted to a work document.
  private struct WorkDocumentUpdate {
    let number: Int
    let format: MsgPack.Value
    let content: MsgPack.Value
    let created: MsgPack.Value
    let author: MsgPack.Value
  }

  /// The updates posted to the document in `directory`, in the order of their numbers, or nil
  /// where the directory cannot be read.
  private static func updates(in directory: String) -> [WorkDocumentUpdate]? {
    guard RNGitWorkStore.isDirectory(directory) else { return [] }
    guard let entries = RNGitWorkStore.numbered(directory) else { return nil }

    var updates: [WorkDocumentUpdate] = []
    for entry in entries {
      let path = directory + "/" + entry
      guard RNGitWorkStore.isFile(path),
        let number = entry.pythonInteger,
        let update = RNGitWorkStore.document(at: path),
        update.pythonIsTruthy,
        let fields = RNGitRequestFields(update),
        let meta = RNGitRequestFields(fields["meta"] ?? .map([]))
      else { continue }
      updates.append(
        WorkDocumentUpdate(
          number: number, format: fields["format"] ?? .string("markdown"),
          content: fields["content"] ?? .string(""), created: meta["created"] ?? .int(0),
          author: meta["author"] ?? .bytes(Data())))
    }
    return updates.enumerated().sorted {
      ($0.element.number, $0.offset) < ($1.element.number, $1.offset)
    }.map(\.element)
  }

  // MARK: - Python formatting

  /// The converter work documents are written through.
  private var markdownRenderer: MarkdownToMicron {
    MarkdownToMicron(maxWidth: RNGitPage.maxRenderWidth, syntaxHighlighter: syntaxHighlighter)
  }

  /// `name` with its first letter raised, as `str.capitalize` writes a scope's name.
  private static func capitalised(_ name: String) -> String {
    name.prefix(1).uppercased() + name.dropFirst()
  }

  /// A title cut to its first `length` members, as `title[:length]` cuts it, and marked with an
  /// ellipsis where that left any out—or nil where Python raises.
  ///
  /// A title that is not text is written as `str` writes it. Where `appendingToText` is false,
  /// the ellipsis is added to the cut title before it is written, which raises for bytes and
  /// adds a member to a list.
  private static func shortened(
    _ title: MsgPack.Value, to length: Int, appendingToText: Bool
  ) -> String? {
    let ellipsis = "\u{2026}"
    switch title {
    case .string(let text):
      let cut = text.pythonPrefix(length)
      return cut.unicodeScalars.count < text.unicodeScalars.count ? cut + ellipsis : cut
    case .bytes(let bytes):
      let cut = MsgPack.Value.bytes(Data(bytes.prefix(length)))
      if appendingToText {
        let written = cut.pythonDescription
        return written.unicodeScalars.count < bytes.count ? written + ellipsis : written
      }
      return bytes.count > length ? nil : cut.pythonDescription
    case .array(let items):
      let cut = Array(items.prefix(length))
      if appendingToText {
        let written = MsgPack.Value.array(cut).pythonDescription
        return written.unicodeScalars.count < items.count ? written + ellipsis : written
      }
      let marked = items.count > length ? cut + [.string(ellipsis)] : cut
      return MsgPack.Value.array(marked).pythonDescription
    default: return nil
    }
  }

  /// `value` as `RNS.prettyhexrep` writes it, `otherwise` where the value is false, or nil
  /// where Python raises.
  private static func prettyHex(_ value: MsgPack.Value, otherwise: String) -> String? {
    guard value.pythonIsTruthy else { return otherwise }
    guard value.pythonIterated != nil, let digits = value.pythonHexrep else { return nil }
    return "<" + digits + ">"
  }

  /// The moment `value` names in the reader's time zone, as `time.strftime` writes it from
  /// `time.localtime`, `otherwise` where the value is false, or nil where Python raises.
  ///
  /// A fractional moment is taken to the second at or before it.
  private static func localTime(
    _ value: MsgPack.Value, _ format: String, _ rendering: RNGitReleaseRendering,
    otherwise: String
  ) -> String? {
    guard value.pythonIsTruthy else { return otherwise }
    let seconds: Int?
    switch value {
    case .bool(let flag): seconds = flag ? 1 : 0
    case .int(let number): seconds = Int(exactly: number)
    case .uint(let number): seconds = Int(exactly: number)
    case .double(let number):
      seconds = number.isFinite ? Int(exactly: number.rounded(.down)) : nil
    default: seconds = nil
    }
    return seconds.map { rendering.dated($0, as: format) }
  }
}
