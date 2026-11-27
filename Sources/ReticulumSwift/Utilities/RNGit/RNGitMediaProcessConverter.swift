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

/// Runs a conversion as subprocesses.
///
/// The platform gate matches ``RNGitProcessRunner``'s: `Foundation.Process` exists only on
/// macOS, so a conversion anywhere else could not be started, as it could not be where no
/// encoder stands on the system.
public struct RNGitMediaProcessConverter: RNGitMediaConverter {

  /// How much of an error stream is kept to say what a failure was.
  static let errorTail = 1024

  /// Creates a converter.
  public init() {}

  /// Runs `producing` in `directory` and feeds what it writes into the encoder `encoding`
  /// answers, whose own output goes to `path`.
  ///
  /// Mirrors `media.py` `convert_to_webp`: the input is relayed through this process rather than
  /// piped straight across, so its format is read before an encoder starts and its size is
  /// counted as it goes.
  public func convert(
    producing: [String], in directory: String?, through encoding: (Data) -> [String]?,
    to path: String, within timeout: TimeInterval
  ) -> RNGitMediaOutcome {
    #if os(macOS)
    guard let output = writable(path) else {
      return .couldNotRun("could not open " + path + " for writing")
    }
    defer { try? output.close() }

    let deadline = Date().addingTimeInterval(timeout)
    let between = Pipe()
    let feed = Pipe()
    let inputErrors = Pipe()
    let encoderErrors = Pipe()

    let input = process(producing, in: directory)
    input.standardOutput = between
    input.standardError = inputErrors
    do { try input.run() } catch {
      terminate(input)
      return .couldNotRun("\(error)")
    }

    // The parent must not keep the write end of the pipe, or it would never see the end of what
    // the input process wrote.
    try? between.fileHandleForWriting.close()
    let source = between.fileHandleForReading.fileDescriptor

    guard let head = read(source, upTo: RNGitMedia.sniffBytes, by: deadline) else {
      terminate(input)
      return .timedOut
    }
    guard let words = encoding(head) else {
      terminate(input)
      return .refused("Input format is not supported")
    }

    let encoder = process(words, in: nil)
    encoder.standardInput = feed
    encoder.standardOutput = output
    encoder.standardError = encoderErrors
    do { try encoder.run() } catch {
      terminate(input)
      terminate(encoder)
      return .couldNotRun("\(error)")
    }

    // Holding the read end would keep a write to an encoder that has gone from failing.
    try? feed.fileHandleForReading.close()
    let sink = feed.fileHandleForWriting.fileDescriptor
    _ = fcntl(sink, F_SETNOSIGPIPE, 1)
    // Non-blocking, so an encoder that stops reading meets the deadline instead of the relay.
    _ = fcntl(sink, F_SETFL, fcntl(sink, F_GETFL) | O_NONBLOCK)
    let relayed = relay(head, from: source, to: sink, by: deadline)
    try? feed.fileHandleForWriting.close()

    if relayed != .done {
      terminate(input)
      terminate(encoder)
      switch relayed {
      case .timedOut: return .timedOut
      case .tooLarge:
        return .refused(
          "Streaming input exceeded maximum size of "
            + RNSUtilities.prettysize(RNGitMedia.conversionSizeMax))
      default: return .failed(encoder: tail(encoderErrors), input: tail(inputErrors))
      }
    }

    guard finished(encoder, and: input, within: max(0, deadline.timeIntervalSinceNow)) else {
      return .timedOut
    }
    guard encoder.terminationStatus == 0 else {
      return .failed(encoder: tail(encoderErrors), input: tail(inputErrors))
    }
    return .converted
    #else
    return .couldNotRun("subprocesses are not available on this platform")
    #endif
  }

  /// Feeds the file at `source` into the encoder `encoding` answers, whose output goes to `path`.
  ///
  /// Mirrors `media.py` `convert_file_to_webp`. The size and format are read from the same open
  /// file the encoder is then fed, so the file cannot be swapped between the two.
  public func convert(
    reading source: String, through encoding: (Data) -> [String]?, to path: String,
    within timeout: TimeInterval
  ) -> RNGitMediaOutcome {
    #if os(macOS)
    guard let input = FileHandle(forReadingAtPath: source) else {
      return .couldNotRun("could not open " + source + " for reading")
    }
    defer { try? input.close() }

    guard let size = try? input.seekToEnd(), (try? input.seek(toOffset: 0)) != nil else {
      return .couldNotRun("could not read " + source)
    }
    guard size <= UInt64(RNGitMedia.conversionSizeMax) else {
      return .refused(
        "Source file exceeds maximum size of "
          + RNSUtilities.prettysize(RNGitMedia.conversionSizeMax))
    }
    let head = (try? input.read(upToCount: RNGitMedia.sniffBytes)) ?? Data()
    guard let words = encoding(head) else {
      return .refused("Input format is not supported")
    }
    guard (try? input.seek(toOffset: 0)) != nil else {
      return .couldNotRun("could not read " + source)
    }

    guard let output = writable(path) else {
      return .couldNotRun("could not open " + path + " for writing")
    }
    defer { try? output.close() }

    let errors = Pipe()
    let encoder = process(words, in: nil)
    encoder.standardInput = input
    encoder.standardOutput = output
    encoder.standardError = errors

    do { try encoder.run() } catch { return .couldNotRun("\(error)") }

    guard finished(encoder, and: nil, within: timeout) else { return .timedOut }
    guard encoder.terminationStatus == 0 else {
      return .failed(encoder: tail(errors), input: "")
    }
    return .converted
    #else
    return .couldNotRun("subprocesses are not available on this platform")
    #endif
  }

  #if os(macOS)
  /// How a process that has been stopped is waited for.
  var waiting: @Sendable (Process) -> Void = { $0.waitUntilExit() }

  /// A process that runs `words` in `directory`, the program it runs looked up on the search path
  /// where the word naming it carries no separator.
  private func process(_ words: [String], in directory: String?) -> Process {
    let process = Process()
    if words[0].contains("/") {
      process.executableURL = URL(fileURLWithPath: words[0])
      process.arguments = Array(words.dropFirst())
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = words
    }
    if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
    return process
  }

  /// How relaying the input to an encoder ended.
  private enum Relay { case done, timedOut, tooLarge, encoderGone }

  /// Relays `head` and the rest of what `source` holds to `sink`, stopping once
  /// ``RNGitMedia/conversionSizeMax`` is passed (`media.py` `_pump`).
  private func relay(
    _ head: Data, from source: Int32, to sink: Int32, by deadline: Date
  ) -> Relay {
    var relayed = head.count
    let wroteHead = write(head, to: sink, by: deadline)
    guard wroteHead == .done else { return wroteHead }
    while true {
      guard let chunk = chunk(source, upTo: RNGitMedia.relayChunk, by: deadline) else {
        return .timedOut
      }
      if chunk.isEmpty { return .done }
      relayed += chunk.count
      if relayed > RNGitMedia.conversionSizeMax { return .tooLarge }
      let wrote = write(chunk, to: sink, by: deadline)
      guard wrote == .done else { return wrote }
    }
  }

  /// Up to `count` bytes from `fd`, fewer where it ends first, or `nil` where `deadline` passes
  /// first (`media.py` `_read_prefix`).
  private func read(_ fd: Int32, upTo count: Int, by deadline: Date) -> Data? {
    var data = Data()
    while data.count < count {
      guard let chunk = chunk(fd, upTo: count - data.count, by: deadline) else { return nil }
      if chunk.isEmpty { break }
      data += chunk
    }
    return data
  }

  /// What `fd` has next, up to `count` bytes and empty at its end, or `nil` where `deadline`
  /// passes first or the read fails.
  private func chunk(_ fd: Int32, upTo count: Int, by deadline: Date) -> Data? {
    guard ready(fd, for: POLLIN, by: deadline) else { return nil }

    var buffer = [UInt8](repeating: 0, count: count)
    let got = Darwin.read(fd, &buffer, count)
    return got < 0 ? nil : Data(buffer[..<got])
  }

  /// Whether `fd` is ready for `events` before `deadline` passes.
  private func ready(_ fd: Int32, for events: Int32, by deadline: Date) -> Bool {
    var result: Int32
    repeat {
      var poller = pollfd(fd: fd, events: Int16(events), revents: 0)
      result = poll(&poller, 1, Int32(max(0, deadline.timeIntervalSinceNow * 1000)))
    } while result < 0 && errno == EINTR
    return result > 0
  }

  /// `.done` once all of `data` is written to the non-blocking `fd`, `.timedOut` where `deadline`
  /// passes first, and `.encoderGone` where the reader has gone.
  private func write(_ data: Data, to fd: Int32, by deadline: Date) -> Relay {
    data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return .done }
      var offset = 0
      while offset < raw.count {
        let wrote = Darwin.write(fd, base + offset, raw.count - offset)
        if wrote >= 0 {
          offset += wrote
          continue
        }
        if errno == EINTR { continue }
        if errno != EAGAIN { return .encoderGone }
        if !ready(fd, for: POLLOUT, by: deadline) { return .timedOut }
      }
      return .done
    }
  }

  /// A handle writing to `path`, which is emptied first where something already stands there.
  private func writable(_ path: String) -> FileHandle? {
    FileManager.default.createFile(atPath: path, contents: Data())
      ? FileHandle(forWritingAtPath: path) : nil
  }

  /// Whether both processes ended before their time was up, stopping both where they did not.
  private func finished(_ encoder: Process, and input: Process?, within timeout: TimeInterval)
    -> Bool
  {
    let deadline = Date().addingTimeInterval(timeout)
    while encoder.isRunning || (input?.isRunning ?? false) {
      if Date() >= deadline {
        if let input { terminate(input) }
        terminate(encoder)
        return false
      }
      usleep(20_000)
    }
    return true
  }

  /// Stops `process` and waits for it to go, where it ever started.
  ///
  /// Waiting on a process that never started can stand without end on macOS 14, so one that
  /// carries no identifier is left alone.
  private func terminate(_ process: Process) {
    guard process.processIdentifier > 0 else { return }
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    waiting(process)
  }

  /// What a process wrote to its error stream, up to what is kept of one.
  private func tail(_ errors: Pipe) -> String {
    let written =
      (try? errors.fileHandleForReading.read(upToCount: Self.errorTail)) ?? Data()
    return String(decoding: written, as: UTF8.self).trimmingCharacters(
      in: .whitespacesAndNewlines)
  }
  #endif
}
