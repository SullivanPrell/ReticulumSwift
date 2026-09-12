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

// The I/O seam for the `rnid` port.
//
// Python passes open file handles straight into `create_rsg`, `validate_rsg` and the
// encrypt/decrypt loops (rnid.py:650, :775, :876, :925). Reproducing that faithfully while
// keeping every behaviour drivable from XCTest without touching disk means routing all
// file access through these protocols.

// MARK: - Byte streams

/// A sequential byte source.
///
/// Python: an `io.BufferedReader`.
public protocol RNIDByteReader: AnyObject {
  /// Read up to `count` bytes, returning fewer only at end of stream.
  ///
  /// Python's `file.read(n)` on a regular file returns exactly `n` bytes until EOF, and
  /// the `.rfe` format depends on that: it has no framing, so decryption only re-aligns
  /// because each read consumes exactly one whole encrypted chunk. Conformers must fill
  /// the request unless the stream is exhausted.
  func read(upTo count: Int) throws -> Data
}

/// A sequential byte sink.
///
/// Python: an `io.BufferedWriter`.
public protocol RNIDByteWriter: AnyObject {
  /// Append `data`, returning the number of bytes written. Python: `file.write(data)`.
  @discardableResult
  func write(_ data: Data) throws -> Int
}

/// An in-memory ``RNIDByteReader``.
public final class RNIDDataReader: RNIDByteReader {
  private let data: Data
  private var offset: Int

  /// Creates a reader over `data`.
  public init(_ data: Data) {
    self.data = data
    self.offset = 0
  }

  /// Reads up to `count` bytes from the current offset.
  public func read(upTo count: Int) throws -> Data {
    guard count > 0, offset < data.count else { return Data() }
    let end = min(offset + count, data.count)
    defer { offset = end }
    return data.subdata(in: offset..<end)
  }
}

/// An in-memory ``RNIDByteWriter``.
public final class RNIDDataWriter: RNIDByteWriter {
  /// Bytes written so far.
  public private(set) var data: Data = Data()

  /// Creates an empty writer.
  public init() {}

  /// Appends `data` and returns the number of bytes written.
  @discardableResult
  public func write(_ data: Data) throws -> Int {
    self.data.append(data)
    return data.count
  }
}

/// A ``RNIDByteReader`` backed by a real file.
public final class RNIDFileReader: RNIDByteReader {
  private let handle: FileHandle

  /// Opens `url` for reading.
  public init(url: URL) throws {
    handle = try FileHandle(forReadingFrom: url)
  }

  /// Reads up to `count` bytes from the current offset.
  public func read(upTo count: Int) throws -> Data {
    // `FileHandle.read(upToCount:)` may legitimately return a short read; loop so the
    // caller always receives a full chunk until EOF.
    var buffer = Data()
    while buffer.count < count {
      guard let piece = try handle.read(upToCount: count - buffer.count), !piece.isEmpty else {
        break
      }
      buffer.append(piece)
    }
    return buffer
  }

  /// Closes the underlying file handle.
  public func close() { try? handle.close() }
  deinit { try? handle.close() }
}

/// A ``RNIDByteWriter`` backed by a real file, truncated on open.
public final class RNIDFileWriter: RNIDByteWriter {
  private let handle: FileHandle

  /// Creates `url` if needed and truncates it for writing.
  public init(url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        throw CocoaError(.fileWriteUnknown)
      }
    }
    handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: 0)
  }

  /// Writes `data` and returns the number of bytes written.
  @discardableResult
  public func write(_ data: Data) throws -> Int {
    try handle.write(contentsOf: data)
    return data.count
  }

  /// Closes the underlying file handle.
  public func close() { try? handle.close() }
  deinit { try? handle.close() }
}

// MARK: - File system

/// Everything `rnid` does to the file system, behind one protocol.
public protocol RNIDFileSystem: AnyObject {
  /// Python: `os.path.expanduser(path)`. Applied at ten call sites and deliberately
  /// skipped at two—see ``RNIDOperations`` for the full matrix.
  func expandTilde(_ path: String) -> String
  /// Python: `os.path.isfile(path)`.
  func fileExists(atPath path: String) -> Bool
  func readData(atPath path: String) throws -> Data
  /// Python: `open(path, "r", encoding="utf-8").read()`.
  func readText(atPath path: String) throws -> String
  func writeData(_ data: Data, atPath path: String) throws
  func makeReader(atPath path: String) throws -> RNIDByteReader
  func makeWriter(atPath path: String) throws -> RNIDByteWriter
}

/// The real file system.
public final class RNIDRealFileSystem: RNIDFileSystem {
  /// Creates a file system rooted at the real one.
  public init() {}

  /// Rewrites a leading tilde to the user's home directory.
  public func expandTilde(_ path: String) -> String {
    DaemonBootstrap.expandTilde(path)
  }

  /// Reports whether a regular file exists at `path`.
  public func fileExists(atPath path: String) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    // Python's os.path.isfile is False for directories.
    return exists && !isDirectory.boolValue
  }

  /// Reads the file at `path` as bytes.
  public func readData(atPath path: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: path))
  }

  /// Reads the file at `path` as UTF-8 text.
  public func readText(atPath path: String) throws -> String {
    let data = try readData(atPath: path)
    guard let text = String(data: data, encoding: .utf8) else {
      throw RNIDFileSystemError.notUTF8(path)
    }
    return text
  }

  /// Writes `data` to `path`, replacing any existing file.
  public func writeData(_ data: Data, atPath path: String) throws {
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  /// Opens `path` for streaming reads.
  public func makeReader(atPath path: String) throws -> RNIDByteReader {
    try RNIDFileReader(url: URL(fileURLWithPath: path))
  }

  /// Opens `path` for streaming writes.
  public func makeWriter(atPath path: String) throws -> RNIDByteWriter {
    try RNIDFileWriter(url: URL(fileURLWithPath: path))
  }
}

/// An in-memory file system for tests.
///
/// `expandTilde` rewrites a leading `~` to `/home/test` so path-expansion asymmetries
/// (`-g` and `-e`'s `-w` are *not* expanded; `-d`'s `-w` is) are directly assertable.
public final class RNIDMemoryFileSystem: RNIDFileSystem {
  /// Files this file system holds, keyed by path.
  public private(set) var files: [String: Data]
  /// Substituted for a leading `~`.
  ///
  /// Python: the user's home directory.
  public var homeDirectory: String

  /// Creates a file system preloaded with `files`.
  public init(files: [String: Data] = [:], homeDirectory: String = "/home/test") {
    self.files = files
    self.homeDirectory = homeDirectory
  }

  /// Rewrites a leading tilde to `homeDirectory`.
  public func expandTilde(_ path: String) -> String {
    guard path == "~" || path.hasPrefix("~/") else { return path }
    return homeDirectory + path.dropFirst(1)
  }

  /// Reports whether a file exists at `path`.
  public func fileExists(atPath path: String) -> Bool { files[path] != nil }

  /// Reads the file at `path` as bytes.
  public func readData(atPath path: String) throws -> Data {
    guard let data = files[path] else { throw RNIDFileSystemError.notFound(path) }
    return data
  }

  /// Reads the file at `path` as UTF-8 text.
  public func readText(atPath path: String) throws -> String {
    let data = try readData(atPath: path)
    guard let text = String(data: data, encoding: .utf8) else {
      throw RNIDFileSystemError.notUTF8(path)
    }
    return text
  }

  /// Writes `data` to `path`, replacing any existing file.
  public func writeData(_ data: Data, atPath path: String) throws { files[path] = data }

  /// Opens `path` for streaming reads.
  public func makeReader(atPath path: String) throws -> RNIDByteReader {
    RNIDDataReader(try readData(atPath: path))
  }

  /// Opens `path` for streaming writes.
  public func makeWriter(atPath path: String) throws -> RNIDByteWriter {
    let writer = MemoryWriter(path: path, fileSystem: self)
    files[path] = Data()
    return writer
  }

  fileprivate func append(_ data: Data, to path: String) {
    files[path, default: Data()].append(data)
  }

  private final class MemoryWriter: RNIDByteWriter {
    private let path: String
    private weak var fileSystem: RNIDMemoryFileSystem?

    init(path: String, fileSystem: RNIDMemoryFileSystem) {
      self.path = path
      self.fileSystem = fileSystem
    }

    @discardableResult
    func write(_ data: Data) throws -> Int {
      fileSystem?.append(data, to: path)
      return data.count
    }
  }
}

/// File system failures, worded as the Python tool reports them.
public enum RNIDFileSystemError: Error, CustomStringConvertible, Equatable {
  case notFound(String)
  case notUTF8(String)

  /// Message matching the one Python prints for this failure.
  public var description: String {
    switch self {
    case .notFound(let path): return "[Errno 2] No such file or directory: '\(path)'"
    case .notUTF8(let path): return "'utf-8' codec can't decode file '\(path)'"
    }
  }
}

// MARK: - Terminal output

/// Everything `rnid` prints.
///
/// Python: bare `print()` calls—no color, no ANSI, no stderr.
public protocol RNIDOutput: AnyObject {
  /// Python: `print(text)`.
  func line(_ text: String)
  /// Python: `print(text, end="")`—the `\r`-prefixed progress line.
  func partial(_ text: String)
}

/// Captures output for assertions.
public final class RNIDCapturingOutput: RNIDOutput {
  /// Whole lines captured so far.
  public private(set) var lines: [String] = []
  /// Partial writes captured so far.
  public private(set) var partials: [String] = []

  /// Creates an empty capture.
  public init() {}

  /// Captures a whole line.
  public func line(_ text: String) { lines.append(text) }
  /// Captures a partial write.
  public func partial(_ text: String) { partials.append(text) }

  /// All ``line(_:)`` output joined with newlines, as it would appear on a terminal.
  public var text: String { lines.joined(separator: "\n") }

  /// Discards everything captured so far.
  public func reset() {
    lines.removeAll()
    partials.removeAll()
  }
}

// MARK: - Injected side effects

/// Composes a message in `$EDITOR`.
///
/// Python: `get_editor_content()` (rnid.py:1034-1059),
/// which needs `subprocess` and therefore can't live in the library target.
public protocol RNIDEditor: AnyObject {
  func composeMessage() throws -> Data
}

/// Waits for a network path.
///
/// Python: `spin(until, msg, timeout)` (rnid.py:1061-1076).
///
/// The return value is deliberately advisory: Python **discards** `spin`'s result and
/// re-invokes the predicate itself (rnid.py:259), so the resolver must do the same.
public protocol RNIDPathWaiter: AnyObject {
  @discardableResult
  func wait(until condition: () -> Bool, message: String, timeout: TimeInterval) -> Bool
}
