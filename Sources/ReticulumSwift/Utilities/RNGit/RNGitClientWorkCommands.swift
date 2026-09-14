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

/// An answer a step cannot read at all.
struct RNGitUnreadableAnswer: Error, CustomStringConvertible {
  var description: String { "unreadable data" }
}

/// Bytes that stop before the value they carry ends.
///
/// The step that stopped says what it was doing, so this carries no message of its own.
struct RNGitTruncatedAnswer: Error, CustomStringConvertible {
  var description: String { "" }
}

/// An attribute something a step reached for does not carry.
struct RNGitMissingAttribute: Error, CustomStringConvertible {
  let owner: String
  let name: String
  var description: String { "'" + owner + "' object has no attribute '" + name + "'" }
}

extension RNGitClientCommands {

  /// What the client offers the user to write a work document over.
  public static let workDocumentTemplate =
    "# Remove this line and enter your document content. Save and exit when done, or save an "
    + "empty document to abort abort."

  /// What the client offers the user to write an update over.
  public static let workUpdateTemplate =
    "# Remove this line and enter your update. Save and exit when done, or save an empty "
    + "document to abort abort."

  /// Writes out the work documents the repository `remote` names holds under `scope`.
  ///
  /// A scope of `all` covers the active, completed and proposed documents at once.
  public func listWork(remote: String?, scope: String = "active") throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    try connect(to: remote)
    defer { transport.teardown() }

    try wrapping("Error listing work documents") {
      let path = try repositoryPath(remote)
      let answer = try requesting(
        .work, Self.workFields(path, "list", [("scope", .string(scope))]), timeout: 120)
      output.write("\r                       \r")
      let body = try answered(Self.remoteError.reading(answer))

      let listed =
        body.isEmpty
        ? MsgPack.Value.map([(.string("active"), .array([])), (.string("completed"), .array([]))])
        : try MsgPack.decode(body)
      guard let held = listed.asDictionary else { throw RNGitUnreadableAnswer() }

      for named in scope == "all" ? ["active", "completed", "proposed"] : [scope] {
        let documents = held[named] ?? .array([])
        guard documents.pythonIsTruthy else {
          if scope != "all" { output.write("No \(named) work documents found.\n") }
          continue
        }
        let heading = "\n" + Self.capitalized(named) + " documents"
        output.write(heading + "\n")
        output.write(String(repeating: "=", count: heading.unicodeScalars.count) + "\n\n")
        output.write(
          "ID".pythonPadded(4) + " " + "Title".pythonPadded(30) + " " + "Author".pythonPadded(17)
            + " " + "Created".pythonPadded(18) + " Comments\n")
        output.write(String(repeating: "-", count: 80) + "\n")
        for entry in documents.pythonIterated ?? [] { output.write(try row(entry)) }
        output.write("\n")
      }

      guard scope == "all" else { return }
      if !(held["active"]?.pythonIsTruthy ?? false), !(held["completed"]?.pythonIsTruthy ?? false),
        !(held["proposed"]?.pythonIsTruthy ?? false)
      {
        output.write("No work documents found.\n")
      }
    }
  }

  /// Writes out the work document `document` names under `scope`, and the updates on it.
  public func viewWork(remote: String?, document: Int?, scope: String = "active") throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let document else { throw RNGitClientAbort("No document ID specified") }
    try connect(to: remote)
    defer { transport.teardown() }

    try wrapping("Error viewing work document") {
      let path = try repositoryPath(remote)
      let answer = try requesting(
        .work, Self.documentFields(path, "view", document, scope: scope), timeout: 120)
      output.write("\r                       \r")
      let body = try answered(Self.remoteError.reading(answer))
      guard !body.isEmpty else { throw RNGitClientAbort("Empty response from remote") }
      try writing(try MsgPack.decode(body), as: scope)
    }
  }

  /// Hands the user an editor, and files what they wrote as an active work document.
  public func createWork(remote: String?, title: String?) throws {
    try makeWork(
      remote: remote, title: title, operation: "create", cancelled: "Creation cancelled",
      filed: "Work document created")
  }

  /// Hands the user an editor, and files what they wrote as a proposed work document.
  public func proposeWork(remote: String?, title: String?) throws {
    try makeWork(
      remote: remote, title: title, operation: "propose", cancelled: "Proposal cancelled",
      filed: "Work document proposed")
  }

  /// Hands the user the work document `document` names, and sends back what they made of it.
  ///
  /// The document keeps the title it has, where the command is given no other one.
  public func editWork(
    remote: String?, document: Int?, title: String? = nil, scope: String = "active"
  ) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let document else { throw RNGitClientAbort("No document ID specified") }
    try connect(to: remote, failure: "Failed to establish link")
    defer { transport.teardown() }
    output.write("\r                       \r")

    try wrapping("Error editing work document") {
      let path = try repositoryPath(remote)
      let asked = try requesting(
        .work, Self.documentFields(path, "view", document, scope: scope), timeout: 600)
      let body = try answered(Self.remoteError.reading(asked))

      guard !body.isEmpty else { throw RNGitTruncatedAnswer() }
      guard let fields = try MsgPack.decode(body).asDictionary else {
        throw RNGitUnreadableAnswer()
      }
      guard let standing = fields["content"] else { throw RNGitMissingKey(key: "content") }
      guard let meta = fields["meta"]?.asDictionary else { throw RNGitMissingKey(key: "meta") }
      guard let named = meta["title"] else { throw RNGitMissingKey(key: "title") }

      guard let content = workContent(over: standing.pythonDescription) else {
        output.write("Edit cancelled\n")
        return
      }
      let signature = try signed(content)
      let carried = (title?.isEmpty == false ? title : nil) ?? named.pythonDescription

      let sent = try requesting(
        .work,
        Self.documentFields(
          path, "edit", document, scope: scope,
          extra: [
            ("content", .string(content)), ("title", .string(carried)),
            ("signature", .bytes(signature)),
          ]), timeout: 600)
      _ = try answered(Self.remoteError.reading(sent))
      output.write("Work document \(scope) #\(document) updated\n")
    }
  }

  /// Asks the user, and then asks the node to drop the work document `document` names.
  public func deleteWork(remote: String?, document: Int?, scope: String = "active") throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let document else { throw RNGitClientAbort("No document ID specified") }
    try connect(to: remote, failure: "Failed to establish link")
    defer { transport.teardown() }
    output.write("\r                       \r")

    try wrapping("Error deleting work document") {
      let path = try repositoryPath(remote)
      output.write(
        "Are you sure you want to delete \(scope) work document #\(document)? [y/N]: ")
      guard agrees() else {
        output.write("Deletion cancelled\n")
        return
      }

      let answer = try requesting(
        .work, Self.documentFields(path, "delete", document, scope: scope), timeout: 120)
      _ = try answered(Self.remoteError.reading(answer))
      output.write("Work document \(scope) #\(document) deleted\n")
    }
  }

  /// Hands the user an editor, and files what they wrote as an update on `document`.
  public func commentWork(remote: String?, document: Int?, scope: String = "active") throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let document else { throw RNGitClientAbort("No document ID specified") }
    try connect(to: remote, failure: "Failed to establish link")
    defer { transport.teardown() }
    output.write("\r                       \r")

    try wrapping("Error adding comment") {
      let path = try repositoryPath(remote)
      guard let content = workContent(isComment: true) else {
        output.write("Update cancelled\n")
        return
      }

      let answer = try requesting(
        .work,
        Self.documentFields(
          path, "comment", document, scope: scope,
          extra: [("content", .string(content)), ("format", .string("markdown"))]),
        timeout: 600)
      let body = try answered(Self.remoteError.reading(answer))
      guard !body.isEmpty else {
        output.write("Update added\n")
        return
      }
      guard let made = try MsgPack.decode(body).asDictionary else {
        throw RNGitUnreadableAnswer()
      }
      guard let identifier = made["id"] else { throw RNGitMissingKey(key: "id") }
      output.write(
        "Update #\(identifier.pythonDescription) added to \(scope) document #\(document)\n")
    }
  }

  /// Asks the node to mark the work document `document` names completed.
  public func completeWork(remote: String?, document: Int?) throws {
    try moveWork(
      remote: remote, document: document, operation: "complete", done: "completed",
      trouble: "Error completing work document")
  }

  /// Asks the node to take the work document `document` names back up.
  public func activateWork(remote: String?, document: Int?) throws {
    try moveWork(
      remote: remote, document: document, operation: "activate", done: "activated",
      trouble: "Error activating work document")
  }

  /// Hands the user what the work document `document` names grants, and sends back their edit.
  public func workPermissions(remote: String?, document: Int?) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let document else { throw RNGitClientAbort("No document ID specified") }
    try connect(to: remote, failure: "Failed to establish link")
    defer { transport.teardown() }
    output.write("\r                       \r")

    try wrapping("Error editing permissions") {
      let path = try repositoryPath(remote)
      let asked = try requesting(
        .work, Self.documentFields(path, "perms", document, step: "get"), timeout: 120)
      let body = try answered(Self.remoteError.reading(asked))

      var standing = ""
      if !body.isEmpty {
        guard let made = try MsgPack.decode(body).asDictionary else {
          throw RNGitUnreadableAnswer()
        }
        standing = made["content"]?.asString ?? ""
      }

      guard
        let content = edited(
          standing.isEmpty ? Self.permissionsTemplate : standing,
          suffix: ".txt")
      else {
        output.write("Edit cancelled\n")
        return
      }

      let sent = try requesting(
        .work,
        Self.documentFields(
          path, "perms", document, step: "set", extra: [("content", .string(content))]),
        timeout: 120)
      _ = try answered(Self.remoteError.reading(sent))
      output.write("Permissions updated for work document #\(document)\n")
    }
  }

  /// `text` with the first character in upper case and the rest in lower.
  private static func capitalized(_ text: String) -> String {
    guard let first = text.first else { return text }
    return String(first).uppercased() + String(text.dropFirst()).lowercased()
  }

  /// What the client makes of one row of a listing.
  private func row(_ entry: MsgPack.Value) throws -> String {
    guard let held = entry.asDictionary else { throw RNGitUnreadableAnswer() }
    let identifier = held["id"]?.pythonDescription ?? "?"
    var title = try Self.text(held["title"], or: "Untitled")
    if title.unicodeScalars.count > 29 { title = title.pythonPrefix(29) + "…" }
    let author = try Self.text(held["author"], or: "").pythonPrefix(16) + "…"
    let created = held["created"]?.asInt ?? 0
    let when = created == 0 ? "unknown" : rendering.dated(created, as: "yyyy-MM-dd HH:mm")
    let comments = held["comments"]?.pythonDescription ?? "0"
    return identifier.pythonPadded(4) + " " + title.pythonPadded(30) + " "
      + author.pythonPadded(17) + " " + when.pythonPadded(18) + " " + comments + "\n"
  }

  /// The text `value` holds, or `fallback` where the node sent no value at all.
  ///
  /// A value of another kind is one the node had no business sending, since what stands here is
  /// measured and cut as text.
  private static func text(_ value: MsgPack.Value?, or fallback: String) throws -> String {
    guard let value else { return fallback }
    guard let held = value.asString else { throw RNGitUnreadableAnswer() }
    return held
  }

  /// Writes out `held`, which the node sent for a document held under `scope`.
  private func writing(_ held: MsgPack.Value, as scope: String) throws {
    guard let fields = held.asDictionary else { throw RNGitUnreadableAnswer() }
    guard let meta = fields["meta"] else { throw RNGitMissingKey(key: "meta") }
    guard let carried = meta.asDictionary else { throw RNGitUnreadableAnswer() }
    guard let author = carried["author"] else { throw RNGitMissingKey(key: "author") }

    var authorText = author.pythonDescription + " (not locally validated)"
    var signatureText = "Document not signed"
    if case .bytes(let signature)? = carried["signature"],
      signature.count == Identity.sigLength / 8,
      case .bytes(let key)? = carried["identity"], key.count == Identity.keySize / 8
    {
      let content = try Self.text(fields["content"], or: "")
      signatureText = "Not valid"
      if let signer = try? Identity(publicKeyBytes: key),
        signer.validate(signature: signature, for: Data(content.utf8))
      {
        signatureText = "Valid"
        authorText = RNSUtilities.prettyhexrep(signer.hash)
      }
    }

    guard let title = carried["title"] else { throw RNGitMissingKey(key: "title") }
    guard let identifier = fields["id"] else { throw RNGitMissingKey(key: "id") }
    let heading = title.pythonDescription + " (#" + identifier.pythonDescription + ")"
    output.write(heading + "\n")
    output.write(String(repeating: "=", count: heading.unicodeScalars.count) + "\n")
    output.write("Author    : \(authorText)\n")
    output.write("Signature : \(signatureText)\n")
    output.write("Status    : \(Self.capitalized(scope))\n")

    guard let created = carried["created"] else { throw RNGitMissingKey(key: "created") }
    output.write("Created   : \(rendering.dated(created.asInt ?? 0, as: "yyyy-MM-dd HH:mm:ss"))\n")
    guard let edited = carried["edited"] else { throw RNGitMissingKey(key: "edited") }
    output.write("Edited    : \(rendering.dated(edited.asInt ?? 0, as: "yyyy-MM-dd HH:mm:ss"))\n")
    guard let format = carried["format"] else { throw RNGitMissingKey(key: "format") }
    output.write("Format    : \(format.pythonDescription)\n")

    let updates = fields["comments"] ?? .array([])
    output.write("Updates   : \(updates.pythonLength ?? 0)\n\n")
    guard let written = fields["content"] else { throw RNGitMissingKey(key: "content") }
    output.write(written.pythonDescription + "\n")

    if updates.pythonIsTruthy {
      output.write("\nUpdates\n=======\n")
      for update in updates.pythonIterated ?? [] {
        guard let named = update.asDictionary else { throw RNGitUnreadableAnswer() }
        guard let identifier = named["id"] else { throw RNGitMissingKey(key: "id") }
        guard let by = named["author"] else { throw RNGitMissingKey(key: "author") }
        guard let at = named["created"] else { throw RNGitMissingKey(key: "created") }
        let stamp =
          "#" + identifier.pythonDescription + " by " + by.pythonDescription + " at "
          + rendering.dated(at.asInt ?? 0, as: "yyyy-MM-dd HH:mm:ss")
        output.write("\n" + stamp + "\n")
        output.write(String(repeating: "-", count: stamp.unicodeScalars.count) + "\n")
        guard let said = named["content"] else { throw RNGitMissingKey(key: "content") }
        output.write(said.pythonDescription + "\n")
      }
    }
    output.write("\n")
  }

  /// Hands the user an editor, and files what they wrote under `operation`.
  private func makeWork(
    remote: String?, title: String?, operation: String, cancelled: String, filed: String
  ) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let title, !title.isEmpty else { throw RNGitClientAbort("No title specified") }
    try connect(to: remote, failure: "Failed to establish link")
    defer { transport.teardown() }
    output.write("\r                       \r")

    try wrapping("Error creating work document") {
      let path = try repositoryPath(remote)
      guard let content = workContent() else {
        output.write(cancelled + "\n")
        return
      }
      let signature = try signed(content)

      let answer = try requesting(
        .work,
        Self.workFields(
          path, operation,
          [
            ("title", .string(title)), ("content", .string(content)),
            ("format", .string("markdown")), ("signature", .bytes(signature)),
          ]), timeout: 600)
      let body = try answered(Self.serverError.reading(answer))
      guard !body.isEmpty else {
        output.write(filed + "\n")
        return
      }
      guard let made = try MsgPack.decode(body).asDictionary else {
        throw RNGitUnreadableAnswer()
      }
      guard let scope = made["scope"] else { throw RNGitMissingKey(key: "scope") }
      guard let identifier = made["id"] else { throw RNGitMissingKey(key: "id") }
      output.write(
        "Work document created as \(scope.pythonDescription) #\(identifier.pythonDescription)\n")
    }
  }

  /// Asks the node to move the work document `document` names, however `operation` says.
  private func moveWork(
    remote: String?, document: Int?, operation: String, done: String, trouble: String
  ) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let document else { throw RNGitClientAbort("No document ID specified") }
    try connect(to: remote, failure: "Failed to establish link")
    defer { transport.teardown() }
    output.write("\r                       \r")

    try wrapping(trouble) {
      let path = try repositoryPath(remote)
      let answer = try requesting(
        .work, Self.workFields(path, operation, [("doc_id", .int(Int64(document)))]),
        timeout: 120)
      let body = try answered(Self.remoteError.reading(answer))
      guard !body.isEmpty else {
        output.write("Work document \(done)\n")
        return
      }
      guard let made = try MsgPack.decode(body).asDictionary else {
        throw RNGitUnreadableAnswer()
      }
      guard let identifier = made["id"] else { throw RNGitMissingKey(key: "id") }
      output.write("Work document #\(identifier.pythonDescription) \(done)\n")
    }
  }

  /// What the user wrote, or `nil` where they wrote nothing that was not the template.
  ///
  /// The user is handed `standing` where there is something to edit, and the template for a
  /// document or an update otherwise.
  private func workContent(over standing: String = "", isComment: Bool = false) -> String? {
    var template = isComment ? Self.workUpdateTemplate : Self.workDocumentTemplate
    if !standing.isEmpty { template = standing }
    guard let written = edited(template, suffix: ".md") else { return nil }
    let kept = written.components(separatedBy: "\n").filter {
      let line = $0.pythonStripped
      return !line.hasPrefix(Self.workUpdateTemplate)
        && !line.hasPrefix(Self.workDocumentTemplate)
    }
    let content = kept.joined(separator: "\n").pythonStripped
    return content.isEmpty ? nil : content
  }

  /// `content` signed by the identity the client holds.
  private func signed(_ content: String) throws -> Data {
    guard let signer = identity else {
      throw RNGitMissingAttribute(owner: "NoneType", name: "sign")
    }
    return try signer.sign(Data(content.utf8))
  }

  /// Runs `body`, saying `trouble` before whatever it could not get past.
  private func wrapping(_ trouble: String, _ body: () throws -> Void) throws {
    do {
      try body()
    } catch let abort as RNGitClientAbort {
      throw abort
    } catch {
      throw RNGitClientAbort("\(trouble): \(error)")
    }
  }

  /// The fields a work request naming `path` and running `operation` carries.
  private static func workFields(
    _ path: String, _ operation: String, _ extra: [(String, MsgPack.Value)]
  ) -> MsgPack.Value {
    var entries: [(MsgPack.Value, MsgPack.Value)] = [
      (.uint(UInt64(RNGitRequestKey.repository)), .string(path)),
      (.string("operation"), .string(operation)),
    ]
    entries.append(contentsOf: extra.map { (.string($0.0), $0.1) })
    return .map(entries)
  }

  /// The fields a work request naming one document carries.
  private static func documentFields(
    _ path: String, _ operation: String, _ document: Int, scope: String? = nil,
    step: String? = nil, extra: [(String, MsgPack.Value)] = []
  ) -> MsgPack.Value {
    var carried: [(String, MsgPack.Value)] = [("doc_id", .int(Int64(document)))]
    if let scope { carried.append(("scope", .string(scope))) }
    if let step { carried.append(("step", .string(step))) }
    carried.append(contentsOf: extra)
    return workFields(path, operation, carried)
  }
}
