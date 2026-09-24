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

/// What a handler needs of the peer that identified itself on the link.
public protocol RNGitRemoteIdentity {

  /// The truncated hash the node knows the peer by.
  var hash: Data { get }

  /// The peer's public keys.
  func getPublicKey() -> Data

  /// Whether `signature` covers `message`.
  func validate(signature: Data, for message: Data) -> Bool
}

extension Identity: RNGitRemoteIdentity {}

/// The node's answer to a peer working on the documents a repository carries.
///
/// A document is read with read access, commented on with interact access beside it, and written
/// with write access beside that. A document of its own may widen what its author's peers may do
/// with it, and the permission a proposal grants its author is written when the proposal lands.
public struct RNGitWorkHandler {

  /// The operations a document's own permissions are consulted for.
  static let documentOperations: Set<String> = [
    "read", "view", "comment", "edit", "delete", "perms",
  ]

  /// The scopes a request may name.
  static let scopes: Set<String> = ["active", "completed", "proposed", "all"]

  /// The formats a document may be written in.
  static let formats: Set<String> = ["markdown", "micron"]

  /// The most a document's title, body and format may come to together.
  static let documentLimit = 256 * 1024

  /// The length of the signature a document carries.
  static let signatureLength = Identity.sigLength / 8

  /// The groups the node serves, and what they grant.
  public var access: RNGitAccessControl

  /// Answers the moment a document records.
  public var clock: @Sendable () -> Double

  /// Creates a handler answering from `access`.
  public init(
    access: RNGitAccessControl,
    clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }
  ) {
    self.access = access
    self.clock = clock
  }

  /// The answer a peer identifying as `identity` gets, or `nil` where it gets none.
  public func handle(_ request: MsgPack.Value, from identity: RNGitRemoteIdentity?)
    -> RNGitResponse?
  {
    guard let identity else { return RNGitResponse(.disallowed, "Not identified") }
    guard let fields = RNGitRequestFields(request) else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    guard let requested = fields[RNGitRequestKey.repository] else {
      return RNGitResponse(.invalidRequest, "No repository specified")
    }
    let operation = fields["operation"] ?? .nil
    guard operation.pythonIsTruthy else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }

    guard let requestedPath = requested.asString else { return nil }
    let hash = identity.hash
    let names = RNGitAccessControl.repositoryPath(requestedPath)
    var read = access.allows(hash, names: names, permission: .read)
    var write = access.allows(hash, names: names, permission: .write)
    var interact = access.allows(hash, names: names, permission: .interact)
    let propose = access.allows(hash, names: names, permission: .propose)
    let admin = access.allows(hash, names: names, permission: .admin)
    guard read else { return RNGitResponse(.notFound, "Not found") }

    // Read access is granted only for a repository the node holds.
    guard let names,
      let repositoryPath = access.groups[names.group]?.repositories[names.repository]?.path
    else { return RNGitResponse(.notFound, "Not found") }
    let work = RNGitWorkStore.directory(forRepository: repositoryPath)

    let name = operation.asString ?? ""
    let given = fields["doc_id"] ?? .nil
    if Self.documentOperations.contains(name), given.pythonIsTruthy {
      guard let number = given.pythonInteger else {
        return RNGitResponse(.invalidRequest, "Invalid request")
      }
      read = documentAllows(hash, names, number, .read) || admin
      guard read else { return RNGitResponse(.notFound, "Document not found") }
    }
    if name == "comment", given.pythonIsTruthy {
      guard let number = given.pythonInteger else {
        return RNGitResponse(.invalidRequest, "Invalid request")
      }
      interact = interact || documentAllows(hash, names, number, .interact)
    }
    if name == "edit", given.pythonIsTruthy {
      guard let number = given.pythonInteger else {
        return RNGitResponse(.invalidRequest, "Invalid request")
      }
      interact = interact || documentAllows(hash, names, number, .interact)
      write = write || documentAllows(hash, names, number, .write)
    }

    let comments = interact && (read || write)
    let manage = interact && write
    var allowed = false
    switch name {
    case "list", "view": allowed = read
    case "comment": allowed = comments
    case "propose": allowed = propose
    case "create", "edit", "delete", "complete", "activate": allowed = manage
    case "perms": allowed = admin
    default: allowed = false
    }
    guard allowed else { return RNGitResponse(.disallowed, "Not allowed") }

    let answer: RNGitResponse?
    switch name {
    case "list": answer = list(work, fields, hash, names)
    case "view": answer = view(work, fields)
    case "comment": answer = comment(work, fields, identity)
    case "create": answer = create(work, fields, identity, scope: "active", owning: false)
    case "propose": answer = create(work, fields, identity, scope: "proposed", owning: true)
    case "edit": answer = edit(work, fields, identity)
    case "delete": answer = remove(work, fields, hash, names)
    case "complete": answer = complete(work, fields, hash, names)
    case "activate": answer = activate(work, fields, hash, names)
    default: answer = permissions(work, fields, hash, names)
    }
    return answer ?? RNGitResponse(.remoteFailure, "Remote error")
  }

  /// Everything the peer may read of the documents in the scopes it asked for.
  private func list(
    _ work: String, _ fields: RNGitRequestFields, _ hash: Data,
    _ names: (group: String, repository: String)
  ) -> RNGitResponse? {
    let scope = fields["scope"] ?? .string("active")
    var listed: [String: [MsgPack.Value]] = [:]
    for folder in RNGitWorkStore.scopes {
      listed[folder] = []
      guard scope == .string(folder) || scope == .string("all") else { continue }
      let path = work + "/" + folder
      guard RNGitWorkStore.isDirectory(path) else { continue }

      var entries: [(key: MsgPack.Value, value: MsgPack.Value)] = []
      guard let held = try? FileManager.default.contentsOfDirectory(atPath: path) else {
        return nil
      }
      for entry in held {
        let directory = path + "/" + entry
        guard RNGitWorkStore.isDirectory(directory) else { continue }
        guard let number = entry.pythonInteger,
          documentAllows(hash, names, number, .read),
          RNGitWorkStore.isFile(directory + "/root"),
          let document = RNGitWorkStore.document(at: directory + "/root"),
          document.pythonIsTruthy,
          let meta = Self.mapping(document, "meta"),
          let summary = Self.summary(meta, number, directory)
        else { continue }
        entries.append((meta["created"] ?? .int(0), summary))
      }
      guard let ordered = RNGitWorkStore.descending(entries) else { return nil }
      listed[folder] = ordered
    }

    return RNGitResponse(
      .ok,
      MsgPack.encode(
        .map(RNGitWorkStore.scopes.map { (.string($0), .array(listed[$0] ?? [])) })))
  }

  /// One document, with every comment on it.
  private func view(_ work: String, _ fields: RNGitRequestFields) -> RNGitResponse? {
    let scope = fields["scope"] ?? .string("all")
    guard Self.scopes.contains(where: { scope == .string($0) }) else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    guard let given = fields["doc_id"], given != .nil else {
      return RNGitResponse(.invalidRequest, "No document ID specified")
    }
    guard let number = given.pythonInteger else {
      return RNGitResponse(.invalidRequest, "Invalid document ID")
    }
    guard let found = Self.locate(work, number) else {
      return RNGitResponse(.notFound, "Not found")
    }
    guard RNGitWorkStore.isFile(found.directory + "/root") else {
      return RNGitResponse(.notFound, "Document not found")
    }
    guard let document = RNGitWorkStore.document(at: found.directory + "/root"),
      document.pythonIsTruthy
    else { return RNGitResponse(.remoteFailure, "Error loading document") }

    guard let numbered = RNGitWorkStore.numbered(found.directory) else { return nil }
    var comments: [(key: Int, value: MsgPack.Value)] = []
    for entry in numbered {
      let path = found.directory + "/" + entry
      guard RNGitWorkStore.isFile(path) else { continue }
      guard let number = entry.pythonInteger,
        let comment = RNGitWorkStore.document(at: path), comment.pythonIsTruthy,
        let held = RNGitRequestFields(comment), let meta = Self.mapping(comment, "meta"),
        let author = Self.author(meta)
      else { continue }
      let entries: [(MsgPack.Value, MsgPack.Value)] = [
        (.string("id"), .int(Int64(number))),
        (.string("content"), held["content"] ?? .string("")),
        (.string("created"), meta["created"] ?? .int(0)),
        (.string("edited"), meta["edited"] ?? .int(0)),
        (.string("author"), .string(author)),
        (.string("format"), meta["format"] ?? .string("markdown")),
      ]
      comments.append((number, .map(entries)))
    }

    guard let held = RNGitRequestFields(document), let meta = Self.mapping(document, "meta"),
      let author = Self.author(meta)
    else { return nil }
    let ordered = comments.enumerated().sorted {
      $0.element.key == $1.element.key
        ? $0.offset < $1.offset : $0.element.key < $1.element.key
    }
    let recorded: [(MsgPack.Value, MsgPack.Value)] = [
      (.string("title"), meta["title"] ?? .string("Untitled")),
      (.string("created"), meta["created"] ?? .int(0)),
      (.string("edited"), meta["edited"] ?? .int(0)),
      (.string("author"), .string(author)),
      (.string("identity"), meta["identity"] ?? .nil),
      (.string("signature"), meta["signature"] ?? .nil),
      (.string("format"), meta["format"] ?? .string("markdown")),
    ]
    let result: [(MsgPack.Value, MsgPack.Value)] = [
      (.string("id"), .int(Int64(number))),
      (.string("scope"), .string(found.scope)),
      (.string("content"), held["content"] ?? .string("")),
      (.string("comments"), .array(ordered.map(\.element.value))),
      (.string("meta"), .map(recorded)),
    ]
    return RNGitResponse(.ok, MsgPack.encode(.map(result)))
  }

  /// A document the peer writes, either into the active scope or as a proposal it then owns.
  private func create(
    _ work: String, _ fields: RNGitRequestFields, _ identity: RNGitRemoteIdentity,
    scope: String, owning: Bool
  ) -> RNGitResponse? {
    guard let title = (fields["title"] ?? .string("")).asString?.pythonStripped,
      let content = (fields["content"] ?? .string("")).asString?.pythonStripped
    else { return nil }
    let format = fields["format"] ?? .string("markdown")
    let signature = fields["signature"] ?? .nil

    guard signature.pythonIsTruthy else {
      return RNGitResponse(.invalidRequest, "No signature provided")
    }
    guard let length = signature.pythonLength else { return nil }
    guard length == Self.signatureLength else {
      return RNGitResponse(.invalidRequest, "Invalid signature length")
    }
    guard case .bytes(let signed) = signature,
      identity.validate(signature: signed, for: Data(content.utf8))
    else { return RNGitResponse(.invalidRequest, "Invalid signature") }
    guard let named = format.pythonLength else { return nil }
    guard
      title.unicodeScalars.count + content.unicodeScalars.count + named
        <= Self.documentLimit
    else { return RNGitResponse(.invalidRequest, "Content limit exceeded") }
    guard !title.isEmpty else { return RNGitResponse(.invalidRequest, "Title is required") }
    guard !content.isEmpty else { return RNGitResponse(.invalidRequest, "Content is required") }

    let number = RNGitWorkStore.nextDocumentID(under: work)
    let moment = clock()
    let document = MsgPack.Value.map([
      (.string("content"), .string(content)),
      (
        .string("meta"),
        .map([
          (.string("format"), Self.named(format)),
          (.string("title"), .string(title)),
          (.string("created"), .double(moment)),
          (.string("edited"), .double(moment)),
          (.string("author"), .bytes(identity.hash)),
          (.string("signature"), signature),
          (.string("identity"), .bytes(identity.getPublicKey())),
        ])
      ),
    ])
    guard
      RNGitWorkStore.save(
        document, at: work + "/" + scope + "/" + String(number) + "/root")
    else { return RNGitResponse(.remoteFailure, "Error saving document") }

    if owning {
      let written = identity.hash.map { String(format: "%02x", $0) }.joined()
      guard
        Self.place(
          "i:" + written + "\n" + "w:" + written + "\n",
          at: work + "/" + String(number) + ".allowed")
      else { return RNGitResponse(.remoteFailure, "Error setting document ownership") }
    }

    return RNGitResponse(
      .ok,
      MsgPack.encode(
        .map([(.string("id"), .int(Int64(number))), (.string("scope"), .string(scope))])))
  }

  /// The title and body its author replaces on a document it wrote.
  private func edit(
    _ work: String, _ fields: RNGitRequestFields, _ identity: RNGitRemoteIdentity
  ) -> RNGitResponse? {
    let scope = fields["scope"] ?? .string("active")
    let content = fields["content"] ?? .string("")
    let title = fields["title"] ?? .string("")
    let signature = fields["signature"] ?? .nil
    guard let body = content.asString else { return nil }

    var size = 0
    if title.pythonIsTruthy {
      guard let length = title.pythonLength else { return nil }
      size += length
    }
    if content.pythonIsTruthy { size += body.unicodeScalars.count }

    guard Self.scopes.contains(where: { scope == .string($0) }) else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    guard signature.pythonIsTruthy else {
      return RNGitResponse(.invalidRequest, "No signature provided")
    }
    guard let length = signature.pythonLength else { return nil }
    guard length == Self.signatureLength else {
      return RNGitResponse(.invalidRequest, "Invalid signature length")
    }
    guard case .bytes(let signed) = signature,
      identity.validate(signature: signed, for: Data(body.utf8))
    else { return RNGitResponse(.invalidRequest, "Invalid signature") }
    guard size <= Self.documentLimit else {
      return RNGitResponse(.invalidRequest, "Content limit exceeded")
    }
    guard content.pythonIsTruthy || title.pythonIsTruthy else {
      return RNGitResponse(.invalidRequest, "No changes specified")
    }
    let given = fields["doc_id"] ?? .nil
    guard given.pythonIsTruthy else {
      return RNGitResponse(.invalidRequest, "No document ID specified")
    }
    guard let number = given.pythonInteger else {
      return RNGitResponse(.invalidRequest, "Invalid document ID")
    }

    guard let found = Self.locate(work, number) else {
      return RNGitResponse(.notFound, "Not found")
    }
    let root = found.directory + "/root"
    guard RNGitWorkStore.isFile(root) else {
      return RNGitResponse(.notFound, "Document not found")
    }
    guard let document = RNGitWorkStore.document(at: root), document.pythonIsTruthy else {
      return RNGitResponse(.remoteFailure, "Error loading document")
    }
    guard let meta = Self.mapping(document, "meta") else { return nil }
    guard meta["author"] == .bytes(identity.hash) else {
      return RNGitResponse(.disallowed, "No access, not author")
    }

    guard case .map(var held) = document,
      case .map(var recorded) = RNGitRequestFields(document)?["meta"] ?? .nil
    else { return nil }
    if title.pythonIsTruthy {
      guard let named = title.asString else { return nil }
      Self.set(&recorded, "title", .string(named.pythonStripped))
    }
    if content.pythonIsTruthy { Self.set(&held, "content", .string(body.pythonStripped)) }
    Self.set(&recorded, "edited", .double(clock()))
    Self.set(&recorded, "signature", signature)
    Self.set(&recorded, "identity", .bytes(identity.getPublicKey()))
    Self.set(&held, "meta", .map(recorded))

    guard RNGitWorkStore.save(.map(held), at: root) else {
      return RNGitResponse(.remoteFailure, "Error saving document")
    }
    return RNGitResponse(.ok)
  }

  /// A comment the peer adds to a document.
  private func comment(
    _ work: String, _ fields: RNGitRequestFields, _ identity: RNGitRemoteIdentity
  ) -> RNGitResponse? {
    let scope = fields["scope"] ?? .string("active")
    guard let content = (fields["content"] ?? .string("")).asString?.pythonStripped else {
      return nil
    }
    let signature = fields["signature"] ?? .nil
    let format = fields["format"] ?? .string("markdown")

    guard Self.scopes.contains(where: { scope == .string($0) }) else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    guard content.unicodeScalars.count <= Self.documentLimit else {
      return RNGitResponse(.invalidRequest, "Content limit exceeded")
    }
    guard let given = fields["doc_id"], given != .nil else {
      return RNGitResponse(.invalidRequest, "No document ID specified")
    }
    guard let number = given.pythonInteger else {
      return RNGitResponse(.invalidRequest, "Invalid document ID")
    }
    guard !content.isEmpty else {
      return RNGitResponse(.invalidRequest, "Content is required")
    }

    // The directory is named from the scope a search found, which no answer is given for.
    guard let found = Self.locate(work, number) else { return nil }
    guard RNGitWorkStore.isFile(found.directory + "/root") else {
      return RNGitResponse(.notFound, "Document not found")
    }

    let comment = RNGitWorkStore.nextCommentID(in: found.directory)
    let moment = clock()
    let written = MsgPack.Value.map([
      (.string("content"), .string(content)),
      (
        .string("meta"),
        .map([
          (.string("format"), Self.named(format)),
          (.string("title"), .nil),
          (.string("created"), .double(moment)),
          (.string("edited"), .double(moment)),
          (.string("signature"), signature),
          (.string("author"), .bytes(identity.hash)),
        ])
      ),
    ])
    guard RNGitWorkStore.save(written, at: found.directory + "/" + String(comment)) else {
      return RNGitResponse(.remoteFailure, "Error saving comment")
    }
    return RNGitResponse(
      .ok, MsgPack.encode(.map([(.string("id"), .int(Int64(comment)))])))
  }

  /// A document its author or an administrator takes away, with what it granted.
  private func remove(
    _ work: String, _ fields: RNGitRequestFields, _ hash: Data,
    _ names: (group: String, repository: String)
  ) -> RNGitResponse? {
    let scope = fields["scope"] ?? .string("active")
    guard Self.scopes.contains(where: { scope == .string($0) }) else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    guard let given = fields["doc_id"], given != .nil else {
      return RNGitResponse(.invalidRequest, "No document ID specified")
    }
    guard let number = given.pythonInteger else {
      return RNGitResponse(.invalidRequest, "Invalid document ID")
    }

    // The directory is named from the scope a search found, which no answer is given for.
    guard let found = Self.locate(work, number) else { return nil }
    guard RNGitWorkStore.isFile(found.directory + "/root") else {
      return RNGitResponse(.notFound, "Document not found")
    }
    guard let document = RNGitWorkStore.document(at: found.directory + "/root"),
      document.pythonIsTruthy
    else { return RNGitResponse(.remoteFailure, "Error loading document") }

    guard let meta = Self.mapping(document, "meta") else { return nil }
    let author = meta["author"] == .bytes(hash)
    guard author || documentAllows(hash, names, number, .admin) else {
      return RNGitResponse(.disallowed, "No access, not author")
    }
    guard RNGitWorkStore.unlink(work + "/" + String(number) + ".allowed") else {
      return RNGitResponse(.remoteFailure, "Remote error")
    }
    guard (try? FileManager.default.removeItem(atPath: found.directory)) != nil else {
      return RNGitResponse(.remoteFailure, "Remote error")
    }
    return RNGitResponse(.ok)
  }

  /// An active document its author or an administrator moves into the completed scope.
  private func complete(
    _ work: String, _ fields: RNGitRequestFields, _ hash: Data,
    _ names: (group: String, repository: String)
  ) -> RNGitResponse? {
    guard let given = fields["doc_id"], given != .nil else {
      return RNGitResponse(.invalidRequest, "No document ID specified")
    }
    guard let number = given.pythonInteger else {
      return RNGitResponse(.invalidRequest, "Invalid document ID")
    }
    let directory = work + "/active/" + String(number)
    guard RNGitWorkStore.isDirectory(directory) else {
      return RNGitResponse(.notFound, "Document not found")
    }
    switch movable(directory, work, hash, names, number) {
    case .refused(let answer): return answer
    case .allowed: break
    }

    guard RNGitWorkStore.move(directory, to: work + "/completed/" + String(number)) else {
      return RNGitResponse(.remoteFailure, "Remote error")
    }
    return RNGitResponse(
      .ok,
      MsgPack.encode(
        .map([
          (.string("id"), .int(Int64(number))), (.string("scope"), .string("completed")),
        ])))
  }

  /// A completed or proposed document its author or an administrator moves back into the active
  /// scope.
  private func activate(
    _ work: String, _ fields: RNGitRequestFields, _ hash: Data,
    _ names: (group: String, repository: String)
  ) -> RNGitResponse? {
    guard let given = fields["doc_id"], given != .nil else {
      return RNGitResponse(.invalidRequest, "No document ID specified")
    }
    guard let number = given.pythonInteger else {
      return RNGitResponse(.invalidRequest, "Invalid document ID")
    }
    var directory: String?
    for scope in ["completed", "proposed"] {
      let held = work + "/" + scope + "/" + String(number)
      if RNGitWorkStore.isDirectory(held) {
        directory = held
        break
      }
    }
    guard let directory else { return RNGitResponse(.notFound, "Document not found") }
    switch movable(directory, work, hash, names, number) {
    case .refused(let answer): return answer
    case .allowed: break
    }

    guard RNGitWorkStore.move(directory, to: work + "/active/" + String(number)) else {
      return RNGitResponse(.remoteFailure, "Remote error")
    }
    return RNGitResponse(
      .ok,
      MsgPack.encode(
        .map([(.string("id"), .int(Int64(number))), (.string("scope"), .string("active"))])))
  }

  /// Whether the document at `directory` may be moved.
  private func movable(
    _ directory: String, _ work: String, _ hash: Data,
    _ names: (group: String, repository: String), _ number: Int
  ) -> Verdict {
    guard let document = RNGitWorkStore.document(at: directory + "/root"),
      document.pythonIsTruthy
    else { return .refused(RNGitResponse(.remoteFailure, "Error loading document")) }
    guard let meta = Self.mapping(document, "meta") else { return .refused(nil) }
    let author = meta["author"] == .bytes(hash)
    guard author || documentAllows(hash, names, number, .admin) else {
      return .refused(RNGitResponse(.disallowed, "Not allowed"))
    }
    return .allowed
  }

  /// What a document grants, read or replaced by its author or an administrator.
  private func permissions(
    _ work: String, _ fields: RNGitRequestFields, _ hash: Data,
    _ names: (group: String, repository: String)
  ) -> RNGitResponse? {
    let step = fields["step"] ?? .nil
    let read = access.allows(hash, names: names, permission: .read)
    let write = access.allows(hash, names: names, permission: .write)
    let interact = access.allows(hash, names: names, permission: .interact)
    guard read else { return RNGitResponse(.notFound, "Not found") }
    guard interact && write else { return RNGitResponse(.disallowed, "Not allowed") }
    guard step.pythonIsTruthy else { return RNGitResponse(.invalidRequest, "Invalid request") }

    switch step {
    case .string("get"): return readPermissions(work, fields, hash, names)
    case .string("set"): return writePermissions(work, fields, hash, names)
    default: return RNGitResponse(.invalidRequest, "Invalid step")
    }
  }

  /// The permission file a document carries, as the text it holds.
  private func readPermissions(
    _ work: String, _ fields: RNGitRequestFields, _ hash: Data,
    _ names: (group: String, repository: String)
  ) -> RNGitResponse? {
    guard let given = fields["doc_id"], given != .nil else {
      return RNGitResponse(.invalidRequest, "No document ID specified")
    }
    guard let number = given.pythonInteger else {
      return RNGitResponse(.invalidRequest, "Invalid document ID")
    }
    switch manages(work, hash, names, number) {
    case .refused(let answer): return answer
    case .allowed: break
    }

    let path = work + "/" + String(number) + ".allowed"
    var content = ""
    if RNGitWorkStore.isFile(path) {
      guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        return RNGitResponse(.remoteFailure, "Error getting permissions")
      }
      content = text
    }
    return RNGitResponse(
      .ok, MsgPack.encode(.map([(.string("content"), .string(content))])))
  }

  /// The permission file a document carries, replaced with what the peer sent.
  private func writePermissions(
    _ work: String, _ fields: RNGitRequestFields, _ hash: Data,
    _ names: (group: String, repository: String)
  ) -> RNGitResponse? {
    let content = fields["content"] ?? .string("")
    guard let given = fields["doc_id"], given != .nil else {
      return RNGitResponse(.invalidRequest, "No document ID specified")
    }
    guard let number = given.pythonInteger else {
      return RNGitResponse(.invalidRequest, "Invalid document ID")
    }
    switch manages(work, hash, names, number) {
    case .refused(let answer): return answer
    case .allowed: break
    }

    guard let text = content.asString else { return nil }
    for (index, line) in text.pythonLines.enumerated() {
      let entry = line.pythonStripped
      guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }
      let grant = RNGitPermissionSet.grant(in: entry, aliases: access.identityAliases)
      guard grant.permission != nil, grant.target != nil else {
        return RNGitResponse(
          .invalidRequest,
          "Invalid permission \"" + entry + "\" on line " + String(index + 1))
      }
    }

    guard Self.place(text, at: work + "/" + String(number) + ".allowed") else {
      return RNGitResponse(.remoteFailure, "Error setting permissions")
    }
    return RNGitResponse(.ok)
  }

  /// What a peer asking to work on one document is told before it is told anything else.
  private enum Verdict {

    /// The peer may go on.
    case allowed

    /// The answer the peer gets instead, which is nothing at all where answering raises.
    case refused(RNGitResponse?)
  }

  /// Whether the peer may manage the permissions the document numbered `number` grants.
  private func manages(
    _ work: String, _ hash: Data, _ names: (group: String, repository: String), _ number: Int
  ) -> Verdict {
    guard let found = Self.locate(work, number) else {
      return .refused(RNGitResponse(.notFound, "Document not found"))
    }
    guard let document = RNGitWorkStore.document(at: found.directory + "/root"),
      document.pythonIsTruthy
    else { return .refused(RNGitResponse(.remoteFailure, "Error loading document")) }
    guard let meta = Self.mapping(document, "meta") else { return .refused(nil) }

    let author = meta["author"] == .bytes(hash)
    let write = access.allows(hash, names: names, permission: .write)
    let interact = access.allows(hash, names: names, permission: .interact)
    let admin = documentAllows(hash, names, number, .admin)
    guard (author && interact && write) || admin else {
      return .refused(RNGitResponse(.disallowed, "Not allowed"))
    }
    return .allowed
  }

  /// Whether `hash` may do `permission` on the document numbered `number`.
  private func documentAllows(
    _ hash: Data, _ names: (group: String, repository: String), _ number: Int,
    _ permission: RNGitPermission
  ) -> Bool {
    access.allowsDocument(
      hash, group: names.group, repository: names.repository, number: number,
      permission: permission)
  }

  /// The scope holding the document numbered `number`, or `nil` where no scope holds it.
  private static func locate(_ work: String, _ number: Int)
    -> (scope: String, directory: String)?
  {
    for scope in RNGitWorkStore.scopes {
      let directory = work + "/" + scope + "/" + String(number)
      if RNGitWorkStore.isDirectory(directory) { return (scope, directory) }
    }
    return nil
  }

  /// What a peer listing the documents is told about one, or `nil` where telling it raises.
  private static func summary(
    _ meta: RNGitRequestFields, _ number: Int, _ directory: String
  ) -> MsgPack.Value? {
    guard let author = author(meta), let numbered = RNGitWorkStore.numbered(directory) else {
      return nil
    }
    let counted = numbered.filter { RNGitWorkStore.isFile(directory + "/" + $0) }
    return .map([
      (.string("id"), .int(Int64(number))),
      (.string("title"), meta["title"] ?? .string("Untitled")),
      (.string("created"), meta["created"] ?? .int(0)),
      (.string("edited"), meta["edited"] ?? .int(0)),
      (.string("author"), .string(author)),
      (.string("format"), meta["format"] ?? .string("markdown")),
      (.string("comments"), .int(Int64(counted.count))),
    ])
  }

  /// The author `meta` records, written as undelimited hexadecimal, or `nil` where writing it
  /// raises.
  private static func author(_ meta: RNGitRequestFields) -> String? {
    let recorded = meta["author"] ?? .bytes(Data())
    guard recorded.pythonIsTruthy else { return "" }
    return recorded.pythonHexrep
  }

  /// The mapping `key` holds in `value`, or `nil` where either is not a mapping.
  private static func mapping(_ value: MsgPack.Value, _ key: String) -> RNGitRequestFields? {
    guard let fields = RNGitRequestFields(value) else { return nil }
    return RNGitRequestFields(fields[key] ?? .map([]))
  }

  /// The format `value` names, which is the one it holds only where a document may be written
  /// in it.
  private static func named(_ value: MsgPack.Value) -> MsgPack.Value {
    guard let name = value.asString, formats.contains(name) else { return .string("markdown") }
    return value
  }

  /// Records `value` under `key`, which keeps the place it already took.
  private static func set(
    _ entries: inout [(MsgPack.Value, MsgPack.Value)], _ key: String, _ value: MsgPack.Value
  ) {
    if let index = entries.firstIndex(where: { $0.0 == .string(key) }) {
      entries[index].1 = value
    } else {
      entries.append((.string(key), value))
    }
  }

  /// Puts `text` at `path` through a neighbouring file, answering whether it landed.
  private static func place(_ text: String, at path: String) -> Bool {
    let staged = path + ".tmp"
    guard FileManager.default.createFile(atPath: staged, contents: Data(text.utf8)) else {
      return false
    }
    return RNGitWorkStore.rename(staged, to: path)
  }
}
