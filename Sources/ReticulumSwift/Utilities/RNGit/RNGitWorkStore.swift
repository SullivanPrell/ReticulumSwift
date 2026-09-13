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

/// The work documents a repository carries, read from and written to the directory beside it.
///
/// A document is a directory named for its number, holding a `root` file and one file per comment,
/// each named for the comment's number. The three scopes a document may be in are directories of
/// their own, and the permissions a document grants are a file named for its number.
public enum RNGitWorkStore {

  /// The scopes a document may be in, in the order every search walks them.
  public static let scopes = ["active", "completed", "proposed"]

  /// The directory holding the work of the repository at `path`.
  public static func directory(forRepository path: String) -> String { path + ".work" }

  /// Whether there is a directory at `path`.
  public static func isDirectory(_ path: String) -> Bool {
    var directory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
    return exists && directory.boolValue
  }

  /// Whether there is a file at `path`.
  public static func isFile(_ path: String) -> Bool {
    var directory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
    return exists && !directory.boolValue
  }

  /// The document at `path`, or `nil` where it is missing or does not decode.
  ///
  /// Bytes left over after the value are ignored. A map decodes to nothing where a dictionary
  /// cannot be built from it, which holds for a map keyed by a value that cannot be hashed and
  /// for one holding a key twice.
  public static func document(at path: String) -> MsgPack.Value? {
    guard let bytes = FileManager.default.contents(atPath: path),
      let value = try? MsgPack.decode(bytes)
    else { return nil }
    return dictionaries(value)
  }

  /// Writes `document` at `path` through a neighbouring file, answering whether it landed.
  public static func save(_ document: MsgPack.Value, at path: String) -> Bool {
    let directory = (path as NSString).deletingLastPathComponent
    if !isDirectory(directory) {
      guard
        (try? FileManager.default.createDirectory(
          atPath: directory, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o755])) != nil
      else { return false }
    }
    let staged = path + ".tmp"
    guard FileManager.default.createFile(atPath: staged, contents: MsgPack.encode(document))
    else { return false }
    return rename(staged, to: path)
  }

  /// Moves what is at `path` onto `destination`, answering whether it landed.
  ///
  /// A destination that is a directory is refused, and one that is a file is replaced.
  public static func rename(_ path: String, to destination: String) -> Bool {
    guard !isDirectory(destination) else { return false }
    try? FileManager.default.removeItem(atPath: destination)
    return (try? FileManager.default.moveItem(atPath: path, toPath: destination)) != nil
  }

  /// Moves the directory at `path` to `destination`, answering whether it landed.
  ///
  /// A destination that is already a directory takes what moves inside it, and refuses where it
  /// already holds an entry of that name.
  public static func move(_ path: String, to destination: String) -> Bool {
    var target = destination
    if isDirectory(destination) {
      target = destination + "/" + (path as NSString).lastPathComponent
      guard !FileManager.default.fileExists(atPath: target) else { return false }
    }
    if (try? FileManager.default.moveItem(atPath: path, toPath: target)) != nil { return true }

    // A move the directory above the destination is missing for lands by way of a copy, which
    // makes what it needs of that directory first.
    guard isDirectory(path),
      (try? FileManager.default.createDirectory(
        atPath: (target as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)) != nil
    else { return false }
    return (try? FileManager.default.moveItem(atPath: path, toPath: target)) != nil
  }

  /// Removes the file at `path`, answering whether it went; a directory is refused.
  public static func unlink(_ path: String) -> Bool {
    guard !isDirectory(path) else { return false }
    return (try? FileManager.default.removeItem(atPath: path)) != nil
  }

  /// The number the next document under `work` takes.
  public static func nextDocumentID(under work: String) -> Int {
    scopes.map { next(in: work + "/" + $0) }.max() ?? 1
  }

  /// The number the next comment in the document at `path` takes.
  public static func nextCommentID(in path: String) -> Int { next(in: path) }

  /// The entries named for a number under `path`, in the order the directory holds them, or
  /// `nil` where the directory could not be read.
  public static func numbered(_ path: String) -> [String]? {
    (try? FileManager.default.contentsOfDirectory(atPath: path))?.filter(\.pythonIsDigit)
  }

  /// One past the largest number an entry under `path` is named for, or one where none is.
  private static func next(in path: String) -> Int {
    guard isDirectory(path) else { return 1 }
    guard let entries = numbered(path) else { return 1 }
    var largest: Int?
    for entry in entries {
      guard let number = entry.pythonInteger else { return 1 }
      largest = max(largest ?? number, number)
    }
    guard let largest else { return 1 }
    return largest + 1
  }

  /// The value where every map in it builds a dictionary, and `nil` where one does not.
  ///
  /// A key that cannot be hashed, and a key a map holds twice, both refuse the whole value. A
  /// key written as a list is hashed as the tuple it becomes, which is held against nothing
  /// already there, so a list written twice keeps only what it last held.
  private static func dictionaries(_ value: MsgPack.Value) -> MsgPack.Value? {
    switch value {
    case .array(let items):
      for item in items where dictionaries(item) == nil { return nil }
      return value
    case .map(let entries):
      var taken: Set<String> = []
      for (key, held) in entries {
        guard let token = hashed(key) else { return nil }
        switch key {
        // A list written as a key stands for the tuple it converts to, which never reaches
        // the test for a key written twice.
        case .array: break
        default: guard taken.insert(token).inserted else { return nil }
        }
        guard dictionaries(held) != nil else { return nil }
      }
      return value
    default: return value
    }
  }

  /// What a key stands for among the keys of one dictionary, or `nil` where it cannot be
  /// hashed.
  ///
  /// Numbers stand for what they count, so the same number written two ways is one key. A
  /// mapping cannot be hashed, and neither can a list holding one anywhere in it.
  private static func hashed(_ key: MsgPack.Value) -> String? {
    switch key {
    case .nil: return "n"
    case .bool(let flag): return "i:" + (flag ? "1" : "0")
    case .int(let number): return "i:" + String(number)
    case .uint(let number):
      return number <= UInt64(Int64.max) ? "i:" + String(Int64(number)) : "u:" + String(number)
    case .double(let number):
      guard number.rounded() == number, number >= -9.223_372_036_854_775_8e18,
        number < 9.223_372_036_854_775_8e18
      else { return "d:" + String(number) }
      return "i:" + String(Int64(number))
    case .string(let text): return "s:" + text
    case .bytes(let bytes): return "b:" + bytes.hexString
    case .array(let items):
      var token = "t"
      for item in items {
        guard let held = hashed(item) else { return nil }
        token += ":" + String(held.count) + ":" + held
      }
      return token
    case .map: return nil
    }
  }

  /// The values ordered as sorting them in reverse orders them, or `nil` where comparing raises.
  ///
  /// Values that compare equal keep the order they arrived in.
  public static func descending<Element>(_ items: [(key: MsgPack.Value, value: Element)])
    -> [Element]?
  {
    merged(items).map { $0.map(\.value) }
  }

  /// `items` ordered from the largest key down, or `nil` where comparing two of them raises.
  private static func merged<Element>(_ items: [(key: MsgPack.Value, value: Element)])
    -> [(key: MsgPack.Value, value: Element)]?
  {
    guard items.count > 1 else { return items }
    let middle = items.count / 2
    guard let left = merged(Array(items[..<middle])),
      let right = merged(Array(items[middle...]))
    else { return nil }

    var ordered: [(key: MsgPack.Value, value: Element)] = []
    var first = 0
    var second = 0
    while first < left.count, second < right.count {
      guard let precedes = left[first].key.pythonPrecedes(right[second].key) else { return nil }
      if precedes {
        ordered.append(right[second])
        second += 1
      } else {
        ordered.append(left[first])
        first += 1
      }
    }
    return ordered + left[first...] + right[second...]
  }
}
