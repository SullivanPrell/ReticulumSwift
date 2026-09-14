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

/// One WebP encoding backend: what it is called, and the words that run it.
public struct RNGitMediaBackend: Equatable, Sendable {

  /// What the backend is called, which is also what the environment forces it by.
  public let name: String

  /// The words the backend is run as, the program it runs among them.
  public let arguments: [String]

  /// Creates a backend.
  public init(name: String, arguments: [String]) {
    self.name = name
    self.arguments = arguments
  }

  /// The program the backend runs.
  public var executable: String { arguments[0] }
}

/// What one conversion run came to.
public enum RNGitMediaOutcome: Equatable, Sendable {

  /// The encoder ran to the end and returned nothing to complain about.
  case converted

  /// The run was still going when its time was up, and was stopped.
  case timedOut

  /// The encoder returned a failure, with whatever the two programs wrote to their error streams.
  case failed(encoder: String, input: String)

  /// The run could not be started at all.
  case couldNotRun(String)
}

/// Runs the two processes a conversion needs.
///
/// A conversion is one program writing an image and a second encoding what the first wrote, so
/// both are run together and neither is waited on alone.
public protocol RNGitMediaConverter: Sendable {

  /// Runs `producing` in `directory` and feeds what it writes into `encoding`, whose own output
  /// goes to `path`.
  func convert(
    producing: [String], in directory: String?, through encoding: [String], to path: String,
    within timeout: TimeInterval
  ) -> RNGitMediaOutcome

  /// Feeds the file at `source` into `encoding`, whose output goes to `path`.
  func convert(
    reading source: String, through encoding: [String], to path: String,
    within timeout: TimeInterval
  ) -> RNGitMediaOutcome
}

/// Converting media to WebP: which backends there are, what each is asked for, and what the file
/// one wrote has to look like.
///
/// Every supported encoder family handles the still formats a repository carries, so which one
/// runs is settled by what stands on the system rather than by what is being converted.
public enum RNGitMedia {

  /// How long a conversion is given, in seconds.
  public static let conversionTimeout = 8

  /// The environment variable one backend is forced with.
  public static let backendVariable = "RNGIT_MEDIA_BACKEND"

  /// The backends, in the order one is picked in.
  public static let backends: [RNGitMediaBackend] = [
    RNGitMediaBackend(name: "magick", arguments: ["magick", "-", "webp:-"]),
    RNGitMediaBackend(name: "convert", arguments: ["convert", "-", "webp:-"]),
    RNGitMediaBackend(name: "gm", arguments: ["gm", "convert", "-", "webp:-"]),
    RNGitMediaBackend(
      name: "ffmpeg",
      arguments: ["ffmpeg", "-y", "-loglevel", "error", "-i", "-", "-f", "webp", "pipe:1"]),
    RNGitMediaBackend(
      name: "avconv",
      arguments: ["avconv", "-y", "-loglevel", "error", "-i", "-", "-f", "webp", "pipe:1"]),
  ]

  /// The family that takes its options before the output it writes.
  static let imageMagickFamily: Set<String> = ["magick", "convert", "gm"]

  /// The family that takes its options before the format it is told to write.
  static let ffmpegFamily: Set<String> = ["ffmpeg", "avconv"]

  /// Each backend by name, and whether it stands on the search path.
  public static func availableBackends(
    found: (String) -> Bool = isOnPath
  ) -> [(name: String, available: Bool)] {
    backends.map { ($0.name, found($0.executable)) }
  }

  /// The backend a conversion runs.
  ///
  /// Where `forced` names one, it is the only one tried. Otherwise `preferring` names the one
  /// that last worked, which is tried before the rest, and the first that stands on the search
  /// path is the one that runs.
  public static func backend(
    forced: String? = nil, preferring: String? = nil, found: (String) -> Bool = isOnPath
  ) -> RNGitMediaBackend? {
    if let forced {
      return backends.first { $0.name == forced && found($0.executable) }
    }
    if let preferring, let last = backends.first(where: { $0.name == preferring }),
      found(last.executable)
    {
      return last
    }
    return backends.first { found($0.executable) }
  }

  /// `backend` with the words `quality` and `maxDimension` ask for.
  ///
  /// A quality outside one to a hundred is brought inside it, and a size below one pixel is not
  /// asked for at all. Each family takes its options at the one place the rest of its words still
  /// read the same way afterwards.
  public static func encoding(
    _ backend: RNGitMediaBackend, quality: Int? = nil, maxDimension: Int? = nil
  ) -> RNGitMediaBackend {
    var options: [String] = []
    if let quality { options += ["-quality", String(min(100, max(1, quality)))] }

    let size = (maxDimension ?? 0) < 1 ? nil : maxDimension
    var arguments = backend.arguments

    if imageMagickFamily.contains(backend.name) {
      if let size { options += ["-resize", "\(size)x\(size)>"] }
      arguments = arguments.dropLast() + options + arguments.suffix(1)
    } else if ffmpegFamily.contains(backend.name) {
      if let size {
        options += [
          "-vf", "scale='min(iw,\(size))':'min(ih,\(size))':force_original_aspect_ratio=decrease",
        ]
      }
      let format = arguments.firstIndex(of: "-f") ?? arguments.endIndex
      arguments = Array(arguments[..<format]) + options + Array(arguments[format...])
    }

    return RNGitMediaBackend(name: backend.name, arguments: arguments)
  }

  /// The width and height the WebP header in `data` names, or `nil` where it names none.
  ///
  /// The three chunk kinds carry the size in three places and three widths, and a header naming
  /// no pixels at all is no header worth reading.
  public static func webPSize(_ data: Data) -> (width: Int, height: Int)? {
    guard data.count >= 30, data.prefix(4) == Data("RIFF".utf8),
      data[data.startIndex + 8..<data.startIndex + 12] == Data("WEBP".utf8)
    else { return nil }

    let width: Int
    let height: Int
    switch String(decoding: byte(data, 12, 16), as: UTF8.self) {
    case "VP8X":
      width = little(byte(data, 24, 27)) + 1
      height = little(byte(data, 27, 30)) + 1
    case "VP8 ":
      width = little(byte(data, 26, 28)) & 0x3FFF
      height = little(byte(data, 28, 30)) & 0x3FFF
    case "VP8L":
      let bits = little(byte(data, 21, 25))
      width = (bits & 0x3FFF) + 1
      height = ((bits >> 14) & 0x3FFF) + 1
    default:
      return nil
    }

    guard width > 0, height > 0 else { return nil }
    return (width, height)
  }

  /// Whether the file at `path` starts the way a WebP file starts.
  public static func isWebP(at path: String) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? handle.close() }
    guard let head = try? handle.read(upToCount: 30) else { return false }
    return webPSize(head) != nil
  }

  /// Whether a program called `name` stands on the search path.
  public static func isOnPath(_ name: String) -> Bool {
    let search = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    for directory in search.split(separator: ":") where !directory.isEmpty {
      if FileManager.default.isExecutableFile(atPath: String(directory) + "/" + name) {
        return true
      }
    }
    return false
  }

  /// What a run through `backend` that came to `outcome` is written to the log as, or `nil` where
  /// it converted.
  public static func complaint(
    about outcome: RNGitMediaOutcome, through backend: String, after timeout: Int
  ) -> String? {
    switch outcome {
    case .converted:
      return nil
    case .timedOut:
      return "Media conversion via \(backend) timed out after \(timeout) seconds"
    case .failed(let encoder, let input):
      var detail = ""
      if !encoder.isEmpty { detail += " Encoder: " + encoder }
      if !input.isEmpty { detail += " Input: " + input }
      return "Media conversion via \(backend) failed." + detail
    case .couldNotRun(let reason):
      return "Error during media conversion: " + reason
    }
  }

  /// The bytes of `data` from `start` up to `end`, counted from where the data starts.
  private static func byte(_ data: Data, _ start: Int, _ end: Int) -> Data {
    data[data.startIndex + start..<data.startIndex + end]
  }

  /// What `data` reads as, least significant byte first.
  private static func little(_ data: Data) -> Int {
    data.reversed().reduce(0) { $0 << 8 | Int($1) }
  }
}

/// Converts media to WebP through whichever backend stands on the system.
///
/// The backend that last worked is remembered, so a system carrying several of them settles on
/// one rather than probing the whole list on every conversion.
public final class RNGitMediaEncoder {

  /// What a conversion is said to be no good for, once.
  public static let noBackend =
    "No WebP encoding backend available for media conversion. You can Install ImageMagick or "
    + "ffmpeg to enable image conversion."

  private let converter: RNGitMediaConverter
  private let forced: String?
  private let found: (String) -> Bool
  private var winner: String?
  private var complainedAboutBackends = false

  /// Creates an encoder.
  public init(
    converter: RNGitMediaConverter = RNGitMediaProcessConverter(),
    forced: String? = ProcessInfo.processInfo.environment[RNGitMedia.backendVariable],
    found: @escaping (String) -> Bool = RNGitMedia.isOnPath
  ) {
    self.converter = converter
    self.forced = forced
    self.found = found
  }

  /// Whether what `producing` writes reached `path` as a WebP file.
  ///
  /// The file a run that did not come off left behind is taken away, so what stands at `path`
  /// afterwards is a WebP file or nothing.
  @discardableResult
  public func convert(
    producedBy producing: [String], in directory: String? = nil, to path: String,
    within timeout: Int? = nil, quality: Int? = nil, maxDimension: Int? = nil
  ) -> Bool {
    guard let asked = ask(quality: quality, maxDimension: maxDimension) else { return false }
    let seconds = timeout ?? RNGitMedia.conversionTimeout
    let outcome = converter.convert(
      producing: producing, in: directory, through: asked.arguments, to: path,
      within: TimeInterval(seconds))
    return settle(
      outcome, from: asked.name, to: path, after: seconds,
      sayingInvalid: {
        "Media conversion via \($0) produced invalid WebP output"
      })
  }

  /// Where the file at `source` was converted to, or `nil` where it was not.
  public func convert(
    file source: String, quality: Int? = 85, maxDimension: Int? = nil, within timeout: Int? = nil
  ) -> String? {
    guard let asked = ask(quality: quality, maxDimension: maxDimension) else { return nil }
    guard RNGitClientEnvironment.isFile(source) else {
      Reticulum.log(
        "Cannot convert media: source file does not exist: " + source, level: .warning)
      return nil
    }

    let path =
      NSTemporaryDirectory() + "/rns_media_" + UUID().uuidString.prefix(8) + ".webp"
    let seconds = timeout ?? RNGitMedia.conversionTimeout
    let outcome = converter.convert(
      reading: source, through: asked.arguments, to: path, within: TimeInterval(seconds))
    let converted = settle(
      outcome, from: asked.name, to: path, after: seconds,
      sayingInvalid: {
        "Invalid media conversion output from \($0)"
      })
    return converted ? path : nil
  }

  /// The backend to run, asked for what the caller asked for, or `nil` where there is none.
  private func ask(quality: Int?, maxDimension: Int?) -> RNGitMediaBackend? {
    guard let backend = RNGitMedia.backend(forced: forced, preferring: winner, found: found) else {
      if !complainedAboutBackends {
        complainedAboutBackends = true
        Reticulum.log(Self.noBackend, level: .warning)
      }
      return nil
    }
    complainedAboutBackends = false
    if forced == nil { winner = backend.name }
    return RNGitMedia.encoding(backend, quality: quality, maxDimension: maxDimension)
  }

  /// Whether `outcome` left a WebP file at `path`, having said what it was where it did not and
  /// taken away whatever it did leave.
  private func settle(
    _ outcome: RNGitMediaOutcome, from backend: String, to path: String, after timeout: Int,
    sayingInvalid invalid: (String) -> String
  ) -> Bool {
    if let complaint = RNGitMedia.complaint(about: outcome, through: backend, after: timeout) {
      Reticulum.log(complaint, level: .warning)
      try? FileManager.default.removeItem(atPath: path)
      return false
    }
    guard RNGitMedia.isWebP(at: path) else {
      Reticulum.log(invalid(backend), level: .warning)
      try? FileManager.default.removeItem(atPath: path)
      return false
    }
    Reticulum.log("Media converted to WebP with " + backend, level: .debug)
    return true
  }
}
