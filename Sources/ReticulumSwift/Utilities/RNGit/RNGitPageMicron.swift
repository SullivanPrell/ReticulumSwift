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

/// The micron a page is built out of.
///
/// Each call answers one piece of markup, and a page is the pieces joined. Fields are carried in
/// the order they are given, because a link is compared by the text it reads as.
public enum RNGitPageMicron {

  /// The character a divider is drawn with where none is named.
  public static let dividerCharacter = "\u{2500}"

  /// A heading at `level`, which is as many `>` as the level counts.
  public static func heading(_ text: String, level: Int = 1) -> String {
    String(repeating: ">", count: level) + text + "\n"
  }

  /// `text` in bold.
  public static func bold(_ text: String) -> String { "`!" + text + "`!" }

  /// `text` in italics.
  public static func italic(_ text: String) -> String { "`*" + text + "`*" }

  /// `text` underlined.
  public static func underline(_ text: String) -> String { "`_" + text + "`_" }

  /// `text` in `color`, which is either three hex digits or a `T` and six.
  public static func colorForeground(_ text: String, _ color: String) -> String {
    "`F" + color + text + "`f"
  }

  /// A divider drawn with `character`.
  public static func divider(_ character: String = dividerCharacter) -> String {
    "-" + character + "\n"
  }

  /// `text` with every backtick in it left as a backtick rather than read as markup.
  public static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "`", with: "\\`")
  }

  /// `text` aligned, where anything but `center`, `left` or `right` is read as the default.
  public static func align(_ text: String, _ alignment: String = "left") -> String {
    let tag = ["center": "c", "left": "l", "right": "r"][alignment] ?? "a"
    return "`" + tag + text + "`a"
  }

  /// A link to `path` on the node the page came from, reading as `label`.
  public static func link(
    _ label: String, _ path: String, _ fields: [(String, String)] = []
  ) -> String {
    "`!" + request(label, path, fields) + "`!"
  }

  /// A link to `path` on the node the page came from, reading as `label` and drawn as body text.
  ///
  /// The one link that is not bold is the one a page draws inside a line of its own text.
  public static func requestLink(
    _ label: String, _ path: String, _ fields: [(String, String)] = []
  ) -> String {
    request(label, path, fields)
  }

  /// A link to `path` on the node `remote` names, reading as `label`.
  public static func externalLink(
    _ label: String, remote: String, _ path: String, _ fields: [(String, String)] = []
  ) -> String {
    "`!`[" + sanitise(label) + "`" + remote + ":" + path + carried(fields) + "]`!"
  }

  /// A link with no weight of its own.
  private static func request(_ label: String, _ path: String, _ fields: [(String, String)])
    -> String
  {
    "`[" + sanitise(label) + "`:" + path + carried(fields) + "]"
  }

  /// The fields a link carries, or nothing where it carries none.
  private static func carried(_ fields: [(String, String)]) -> String {
    guard !fields.isEmpty else { return "" }
    return "`" + fields.map { $0.0 + "=" + quotePlus($0.1) }.joined(separator: "|")
  }

  /// `label` without the characters that would end the link early.
  private static func sanitise(_ label: String) -> String {
    label.filter { $0 != "[" && $0 != "]" && $0 != "`" }
  }

  /// `value` as a field carries it: every byte that is not left alone written as `%XX`, and a
  /// space written as `+`.
  static func quotePlus(_ value: String) -> String {
    var encoded = ""
    for byte in Array(value.utf8) {
      let character = Character(UnicodeScalar(byte))
      if character.isLetter && character.isASCII || character.isNumber && character.isASCII
        || "_.-~".contains(character)
      {
        encoded.append(character)
      } else if byte == UInt8(ascii: " ") {
        encoded.append("+")
      } else {
        encoded += String(format: "%%%02X", byte)
      }
    }
    return encoded
  }

  /// The value a field carries `text` back as, read as `urllib.parse.unquote_plus` reads it: `+`
  /// as a space, and each run of escapes decoded as UTF-8.
  ///
  /// Bytes that do not decode are replaced, and a `%` that two hexadecimal digits do not follow
  /// stands as it is. Only a run of ASCII is decoded, so a character outside it is carried over
  /// unchanged and ends the run before it.
  static func unquotePlus(_ value: String) -> String {
    var read = String.UnicodeScalarView()
    var pending: [UInt8] = []
    func decodePending() {
      read.append(contentsOf: String(decoding: pending, as: UTF8.self).unicodeScalars)
      pending.removeAll()
    }

    let scalars = Array(value.unicodeScalars)
    var index = 0
    while index < scalars.count {
      let scalar = scalars[index]
      if !scalar.isASCII {
        decodePending()
        read.append(scalar)
        index += 1
      } else if scalar == "%", index + 2 < scalars.count,
        let high = hexDigit(scalars[index + 1]), let low = hexDigit(scalars[index + 2])
      {
        pending.append(high << 4 | low)
        index += 3
      } else {
        pending.append(scalar == "+" ? UInt8(ascii: " ") : UInt8(scalar.value))
        index += 1
      }
    }
    decodePending()
    return String(read)
  }

  /// The value of one hexadecimal digit, or `nil` where `scalar` is none.
  private static func hexDigit(_ scalar: Unicode.Scalar) -> UInt8? {
    switch scalar {
    case "0"..."9": return UInt8(scalar.value - 0x30)
    case "a"..."f": return UInt8(scalar.value - 0x57)
    case "A"..."F": return UInt8(scalar.value - 0x37)
    default: return nil
    }
  }
}
