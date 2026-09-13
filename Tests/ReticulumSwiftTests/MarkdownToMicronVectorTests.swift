//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import CryptoKit
import Foundation
import XCTest

@testable import ReticulumSwift

/// Micron captured from `MarkdownToMicron` in Python RNS 1.5.4.
///
/// The inputs reach every branch of the converter: the block scanner's quote, table and
/// fence states, each inline form, both link shapes, the column squeeze, cell truncation
/// and the wrap. Comparing against recorded output rather than against another Swift call
/// is what makes a transcription error visible.
final class MarkdownToMicronVectorTests: XCTestCase {

  private struct Config {
    let maxWidth: Int
    let urlScope: String?
    let boldLinks: Bool?
    let underlineLinks: Bool?
    let linkColor: String?
  }

  private static let configs: [Config] = [
    Config(maxWidth: 100, urlScope: nil, boldLinks: nil, underlineLinks: nil, linkColor: nil),
    Config(maxWidth: 40, urlScope: nil, boldLinks: nil, underlineLinks: nil, linkColor: nil),
    Config(maxWidth: 12, urlScope: nil, boldLinks: nil, underlineLinks: nil, linkColor: nil),
    Config(maxWidth: 4, urlScope: nil, boldLinks: nil, underlineLinks: nil, linkColor: nil),
    Config(maxWidth: 100, urlScope: ":/file/", boldLinks: nil, underlineLinks: nil, linkColor: nil),
    Config(maxWidth: 100, urlScope: "", boldLinks: nil, underlineLinks: nil, linkColor: nil),
    Config(maxWidth: 60, urlScope: nil, boldLinks: false, underlineLinks: nil, linkColor: nil),
    Config(maxWidth: 60, urlScope: nil, boldLinks: nil, underlineLinks: false, linkColor: nil),
    Config(maxWidth: 60, urlScope: nil, boldLinks: false, underlineLinks: false, linkColor: nil),
    Config(maxWidth: 60, urlScope: nil, boldLinks: nil, underlineLinks: nil, linkColor: "abc"),
    Config(maxWidth: 60, urlScope: nil, boldLinks: nil, underlineLinks: nil, linkColor: "aabbcc"),
    Config(maxWidth: 60, urlScope: nil, boldLinks: nil, underlineLinks: nil, linkColor: "abcd"),
    Config(maxWidth: 500, urlScope: nil, boldLinks: nil, underlineLinks: nil, linkColor: nil),
    Config(maxWidth: 500, urlScope: ":/wide/", boldLinks: nil, underlineLinks: nil, linkColor: nil),
  ]

  /// Inputs the reference was measured on, in the order the digests fold them.
  private static let inputs: [String] = [
    "",
    "hello",
    "# Heading one",
    "###### Deep heading",
    "####### Seven hashes is not a heading",
    "#NoSpace",
    "## Heading with **bold** and `code`",
    "---",
    "***",
    "___",
    "===",
    "   ---   ",
    "- item one\n- item two\n- item three",
    "  * nested bullet",
    "+ plus bullet",
    "-notalist",
    "<html tag start",
    "a \\ backslash",
    "**bold** and *italic* and __bold__ and _italic_",
    "***both***",
    "`inline code`",
    "`code with \\` backtick`",
    "[label](https://example.com)",
    "[label](page.mu)",
    "[label](page.mu#anchor)",
    "[label](https://example.com#anchor)",
    "[**bold label**](target)",
    "[label with `tick`](target)",
    "text [a](b) middle [c](d) end",
    "> a quote",
    "> line one\n> line two\n\nafter",
    "> quote\nplain after quote",
    "> quote\n| a | b |\n|---|---|\n| 1 | 2 |",
    "```\nplain code\n```",
    "```python\nprint('hi')\n```",
    "```rawmu\n`!raw`!\n```",
    "```\nunclosed code",
    "```   \nspaces after fence\n```",
    "| a | b |\n|---|---|\n| 1 | 2 |",
    "| a | b |\n|:--|--:|\n| 1 | 2 |",
    "| a | b |\n|:-:|:-:|\n| 1 | 2 |",
    "| a | b | c |\n|---|---|\n| 1 |",
    "| header only |\n|---|",
    "a | b\n--- | ---\n1 | 2",
    "| not | a | table",
    "| esc \\| pipe | b |\n|---|---|\n| 1 | 2 |",
    "|" + String(repeating: " very long cell", count: 12) + "  | b |\n|---|---|\n| 1 | 2 |",
    "| 中文 | b |\n|---|---|\n| あいう | 2 |",
    "| **bold** | `code` |\n|---|---|\n| [l](t) | 2 |",
    "> a long quoted paragraph that will need wrapping a long quoted paragraph that will need wrapping a long quoted paragraph that will need wrapping a long quoted paragraph that will need wrapping ",
    "> supercalifragilisticexpialidocioussupercalifragilisticexpialidocioussupercalifragilisticexpialidocioussupercalifragilisticexpialidocioussupercalifragilisticexpialidocioussupercalifragilisticexpialidocious",
    "中文 heading\n# 中文",
    "line with trailing spaces   ",
    "\ttabbed line",
    "a\n\n\nb",
    "> q1\n> q2\n> \n> q4",
    "# Heading\r",
    "- item\r",
    "> quote\r",
    "```python\rx\n```",
    "| a | b |\r\n|---|---|\n| 1 | 2 |",
    "---\r",
    "plain\r",
    "text\r\nmore",
    "**bold**\r",
    "\u{B} vertical tab",
    "\u{1C} file separator",
    "\u{85} next line",
    "\u{A0} nbsp",
    "#\u{A0}nbsp heading",
    "-\u{B}vtab list",
    "| " + String(repeating: "x", count: 30) + " | " + String(repeating: "x", count: 30) + " | "
      + String(repeating: "x", count: 30) + " | " + String(repeating: "x", count: 30) + " |\n"
      + String(repeating: "|---", count: 4) + "|\n| " + String(repeating: "x", count: 30) + " | "
      + String(repeating: "x", count: 30) + " | " + String(repeating: "x", count: 30) + " | "
      + String(repeating: "x", count: 30) + " |",
    "| " + String(repeating: "y", count: 40) + " | " + String(repeating: "y", count: 40) + " | "
      + String(repeating: "y", count: 40) + " |\n|---|---|---|\n| "
      + String(repeating: "y", count: 40) + " | " + String(repeating: "y", count: 40) + " | "
      + String(repeating: "y", count: 40) + " |",
    "| " + String(repeating: "z", count: 25) + " | " + String(repeating: "z", count: 25) + " | "
      + String(repeating: "z", count: 25) + " | " + String(repeating: "z", count: 25) + " | "
      + String(repeating: "z", count: 25) + " |\n" + String(repeating: "|---", count: 5) + "|\n| "
      + String(repeating: "z", count: 25) + " | " + String(repeating: "z", count: 25) + " | "
      + String(repeating: "z", count: 25) + " | " + String(repeating: "z", count: 25) + " | "
      + String(repeating: "z", count: 25) + " |",
    "| " + String(repeating: "w", count: 60) + " | " + String(repeating: "w", count: 60)
      + " |\n|---|---|\n| " + String(repeating: "w", count: 60) + " | "
      + String(repeating: "w", count: 60) + " |",
    "| " + String(repeating: "q", count: 20) + " | " + String(repeating: "q", count: 20) + " | "
      + String(repeating: "q", count: 20) + " | " + String(repeating: "q", count: 20) + " | "
      + String(repeating: "q", count: 20) + " | " + String(repeating: "q", count: 20) + " |\n"
      + String(repeating: "|---", count: 6) + "|\n| " + String(repeating: "q", count: 20) + " | "
      + String(repeating: "q", count: 20) + " | " + String(repeating: "q", count: 20) + " | "
      + String(repeating: "q", count: 20) + " | " + String(repeating: "q", count: 20) + " | "
      + String(repeating: "q", count: 20) + " |",
    String(repeating: "| 中中中中中中中中中中中中中中中 ", count: 4) + "|\n" + String(repeating: "|---", count: 4)
      + "|\n" + String(repeating: "| 中中中中中中中中中中中中中中中 ", count: 4) + "|",
    "| " + String(repeating: "a", count: 30) + " | " + String(repeating: "b", count: 30)
      + " | cccccccccc |\n|---|---|---|\n| 1 | 2 | 3 |",
    "| aaaaaaaaaa | " + String(repeating: "b", count: 40) + " | "
      + String(repeating: "c", count: 40) + " |\n|---|---|---|\n| 1 | 2 | 3 |",
    "|" + String(repeating: " `!bold`!", count: 8) + "  | " + String(repeating: "x", count: 32)
      + " |\n|---|---|\n| 1 | 2 |",
    "| `FT282828" + String(repeating: "t", count: 40) + " | " + String(repeating: "u", count: 40)
      + " |\n|---|---|\n| 1 | 2 |",
    "#\u{B}heading",
    "#\u{1F}heading",
    "#\u{85}heading",
    "*\u{B}item",
    "+\u{85}item",
    "\u{B}---",
    "\u{85}***",
    "\u{1C}___",
    "|\u{B}---\u{B}|\u{B}---\u{B}|",
    "| a | b |\n|\u{B}---\u{B}|\u{B}---\u{B}|\n| 1 | 2 |",
    "---\u{B}",
    ">\u{B}quote",
    ">\u{85}quote",
    "  \u{B}* spaced item",
    "| abcd | b |\n|:-:|:-:|\n| 1 | 2 |",
    "| abcde | bcdef |\n|:-:|:-:|\n| 1 | 22 |",
    "| abcdef | b |\n|:-:|--:|\n| xy | 2 |",
    "| 中文ab | b |\n|:-:|:-:|\n| x | 2 |",
    "> 中文中文",
    "> a中b文c",
    "> \u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}",
    "| a | b | ccccc |\n|---|---|\n| 1 | 2 | x |",
    "| a | bbbbbb |\n|:-:|\n| 1 | y |",
    "| a | b | c | ddddd |\n|--:|\n| 1 | 2 | 3 | z |",
    "| aaaa | bbbb |\n" + String(repeating: "|---", count: 4) + "|\n| 1 | 2 |",
    "| a | b |\n|---|---|\n| 1 | 2 | 3 | 4 |",
    "a | b\n|---|---|\n| 1 | 2 |",
    "a | b\n--- | --- |\n1 | 2",
    "a|b\n|:-:|--:|\n1|2",
    "x | y | z\n|---|---|---|\n1 | 2 | 3",
    "[label](rns://aabbccdd/page)",
    "[label](rns://aabbccdd/page#anchor)",
    "[label](file:/tmp/page.mu)",
    "[label](:/already/scoped)",
    "[label](ftp://host/file#frag)",
    "text [a](rns://x/y) and [b](plain) end",
    "| `FT28`!bold`!" + String(repeating: "x", count: 20) + " | b |\n|---|---|\n| 1 | 2 |",
    "| `FT2828`*em`*" + String(repeating: "y", count: 20) + " | b |\n|---|---|\n| 1 | 2 |",
    "| `F12`_u`_" + String(repeating: "z", count: 20) + " | b |\n|---|---|\n| 1 | 2 |",
    "| `BT28`!b`!" + String(repeating: "w", count: 20) + " | b |\n|---|---|\n| 1 | 2 |",
    "| **a**" + String(repeating: "b", count: 30) + " | c |\n|---|---|\n| 1 | 2 |",
    "| *a*__b__" + String(repeating: "c", count: 30) + " | d |\n|---|---|\n| 1 | 2 |",
    "| **a**_b_**c**" + String(repeating: "d", count: 30) + " | e |\n|---|---|\n| 1 | 2 |",
    "| `x`**y**" + String(repeating: "z", count: 30) + " | e |\n|---|---|\n| 1 | 2 |",
    String(repeating: "| jjjjjjjjjj ", count: 40) + "|\n" + String(repeating: "|---", count: 40)
      + "|\n" + String(repeating: "| jjjjjjjjjj ", count: 40) + "|",
    String(repeating: "| kkkkkkkkkkkk ", count: 30) + "|\n" + String(repeating: "|---", count: 30)
      + "|\n" + String(repeating: "| kkkkkkkkkkkk ", count: 30) + "|",
    String(repeating: "| mmmmmmmmm ", count: 24) + "|\n" + String(repeating: "|---", count: 24)
      + "|\n" + String(repeating: "| mmmmmmmmm ", count: 24) + "|",
  ]

  /// Inputs for `formatLine`, derived from ``inputs`` as the reference derives them.
  private static let lineInputs: [String] = {
    var cases = inputs.flatMap { $0.components(separatedBy: "\n") }
    cases += [
      "`tick`", "\\already escaped", "-", "- ", "--", "-x", "<",
      String(repeating: "#", count: 7) + " x",
    ]
    return cases
  }()

  /// Rows for the table entry points, including the literal Micron that only
  /// ``MarkdownToMicron/formatTableRaw(_:align:)`` carries as far as the truncator.
  private static let tableRows: [[String]] = [
    ["| a | b |", "|---|---|", "| 1 | 2 |"],
    ["| `!x`! | b |", "|:-:|--:|", "| 中文 | 2 |"],
    [
      "| " + String(repeating: "a", count: 40) + " | " + String(repeating: "b", count: 40) + " |",
      "|---|---|", "| 1 | 2 |",
    ],
    ["| a |"],
    ["| a | b |", "|---|---|"],
    ["| `!a`!" + String(repeating: "b", count: 30) + " | c |", "|---|---|", "| 1 | 2 |"],
    ["| `*a`*`_b`_" + String(repeating: "c", count: 30) + " | d |", "|---|---|", "| 1 | 2 |"],
    ["| `=a`=`!b`!`*c" + String(repeating: "d", count: 30) + " | e |", "|---|---|", "| 1 | 2 |"],
    ["| `FT28`!b`!" + String(repeating: "x", count: 30) + " | c |", "|---|---|", "| 1 | 2 |"],
    ["| `FT2828`*e`*" + String(repeating: "y", count: 30) + " | c |", "|---|---|", "| 1 | 2 |"],
    ["| `BT28`!b`!" + String(repeating: "w", count: 30) + " | c |", "|---|---|", "| 1 | 2 |"],
    ["| `F12`_u`_" + String(repeating: "z", count: 30) + " | c |", "|---|---|", "| 1 | 2 |"],
    ["| `FT282828`!b`!" + String(repeating: "v", count: 30) + " | c |", "|---|---|", "| 1 | 2 |"],
  ]

  private static let tableConfigs = [0, 1, 2, 3]

  private static func converter(_ config: Config) -> MarkdownToMicron {
    let converter = MarkdownToMicron(maxWidth: config.maxWidth, urlScope: config.urlScope)
    if let bold = config.boldLinks { converter.boldLinks = bold }
    if let underline = config.underlineLinks { converter.underlineLinks = underline }
    if let color = config.linkColor { converter.linkColor = color }
    return converter
  }

  /// Inputs whose Micron is short enough to read, with the output the reference gave.
  private static let vectors: [(input: Int, expected: String)] = [
    (2, ">Heading one"),
    (12, " \u{2022} item one\n \u{2022} item two\n \u{2022} item three"),
    (7, "-"),
    (18, "`!bold`! and `*italic`* and `!bold`! and `*italic`*"),
    (20, "`BT383838`Fdddinline code`f`b"),
    (24, "`_`!`[label`:/page/page.mu|anchor=anchor]`!`_"),
    (25, "`_`!`[label`https://example.com]`!`_"),
    (112, "`_`!`[label`rns://aabbccdd/page]`!`_"),
    (29, " \u{2502} a quote"),
    (34, "`BT282828`Fddd\n`=\nprint('hi')\n`=\n`f`b"),
    (35, "`BT282828`Fddd\n`=\n\\`!raw\\`!\n`=\n`f`b"),
    (
      39,
      "`c\n\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{252C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}\n\u{2502} a   \u{2502} b   \u{2502}\n\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}\n\u{2502} 1   \u{2502}   2 \u{2502}\n\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2534}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}\n`a"
    ),
    (
      47,
      "`c\n\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{252C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}\n\u{2502} 中文   \u{2502} b   \u{2502}\n\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}\n\u{2502} あいう \u{2502} 2   \u{2502}\n\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2534}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}\n`a"
    ),
    (56, ">Heading\r"),
    (81, ">heading"),
    (15, "\\-notalist"),
    (17, "a \\\\ backslash"),
  ]

  /// Orderings the reference gave for the one input whose truncation leaves two tags open.
  ///
  /// `_truncate_cell` (`util.py:690-746`) collects the still-open tags in a `set` and
  /// writes them out by iterating it, so the order follows the interpreter's string hash
  /// seed and changes between processes. Twelve seeds gave these two orderings, so there
  /// is no single byte sequence to match and the digest skips these entries.
  private static let unstable: [(config: Int, input: Int, outputs: [String])] = [
    (
      2, 48,
      [
        "`c\n\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{252C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}\n\u{2502} \\`!bo\\`!\u{2026} \u{2502} \\`BT383838\\`Fdddco\\`f\\`b\u{2026} \u{2502}\n\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}\n\u{2502} `_`!`[`!`_\u{2026} \u{2502} 2   \u{2502}\n\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2534}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}\n`a",
        "`c\n\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{252C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}\n\u{2502} \\`!bo\\`!\u{2026} \u{2502} \\`BT383838\\`Fdddco\\`f\\`b\u{2026} \u{2502}\n\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}\n\u{2502} `_`!`[`_`!\u{2026} \u{2502} 2   \u{2502}\n\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2534}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}\n`a",
      ]
    ),
    (
      3, 48,
      [
        "`c\n\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{252C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}\n\u{2502} \\`!bo\\`!\u{2026} \u{2502} \\`BT383838\\`Fdddco\\`f\\`b\u{2026} \u{2502}\n\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}\n\u{2502} `_`!`[`!`_\u{2026} \u{2502} 2   \u{2502}\n\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2534}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}\n`a",
        "`c\n\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{252C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}\n\u{2502} \\`!bo\\`!\u{2026} \u{2502} \\`BT383838\\`Fdddco\\`f\\`b\u{2026} \u{2502}\n\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}\n\u{2502} `_`!`[`_`!\u{2026} \u{2502} 2   \u{2502}\n\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2534}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}\n`a",
      ]
    ),
  ]

  /// Every input under every config folds to the digest the reference produced.
  func testCuratedBlocksMatchTheReferenceDigest() {
    let skipped = Set(Self.unstable.map { $0.config * Self.inputs.count + $0.input })
    var hasher = SHA256()
    var digested = 0

    for (config, settings) in Self.configs.enumerated() {
      for (index, input) in Self.inputs.enumerated() {
        if skipped.contains(config * Self.inputs.count + index) { continue }
        let micron = Self.converter(settings).formatBlock(input)
        hasher.update(data: Data("\(config):\(index):\(micron)\n".utf8))
        digested += 1
      }
    }

    XCTAssertEqual(digested, 1790)
    XCTAssertEqual(
      hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      "48d8bd0e73b650205a8a919a5214373ed685ef010c726cbf84381262013865d4")
  }

  /// The truncation whose closers the reference orders at random gives one of its orderings.
  func testUnstableTruncationGivesARecordedOrdering() {
    for entry in Self.unstable {
      let micron = Self.converter(Self.configs[entry.config]).formatBlock(
        Self.inputs[entry.input])
      XCTAssertTrue(
        entry.outputs.contains(micron),
        "\(micron.debugDescription) is none of \(entry.outputs.map(\.debugDescription))")
    }
  }

  /// The readable vectors match byte for byte, so a digest failure has somewhere to start.
  func testVectorsMatchTheReference() {
    let converter = Self.converter(Self.configs[0])
    for vector in Self.vectors {
      XCTAssertEqual(
        converter.formatBlock(Self.inputs[vector.input]), vector.expected,
        Self.inputs[vector.input].debugDescription)
    }
  }

  /// Both line modes fold to the digest the reference produced.
  func testLinesMatchTheReferenceDigest() {
    let converter = Self.converter(Self.configs[0])
    var hasher = SHA256()

    for (index, input) in Self.lineInputs.enumerated() {
      let normal = converter.formatLine(input)
      let code = converter.formatLine(input, mode: .codeBlock)
      hasher.update(data: Data("\(index):\(normal):\(code)\n".utf8))
    }

    XCTAssertEqual(Self.lineInputs.count, 254)
    XCTAssertEqual(
      hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      "172cc367d126fc80b6e2acb0daf489b69ba2025d2af7f80cfcce644fefbad135")
  }

  /// Both table entry points fold to the digest the reference produced.
  func testTablesMatchTheReferenceDigest() {
    var hasher = SHA256()
    var digested = 0

    for rows in Self.tableRows {
      for config in Self.tableConfigs {
        for align in ["c", "l", ""] {
          let converter = Self.converter(Self.configs[config])
          let table = converter.formatTable(rows, align: align).joined(separator: "\n")
          let raw = converter.formatTableRaw(rows, align: align).joined(separator: "\n")
          hasher.update(data: Data("\(digested):\(table)\n\(raw)\n".utf8))
          digested += 1
        }
      }
    }

    XCTAssertEqual(digested, 156)
    XCTAssertEqual(
      hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      "fa230f809b75262551db453a80146d4daf679a6a052cffb525d7f1f52676caa4")
  }

  /// The first table matches byte for byte, so a digest failure has somewhere to start.
  func testFirstTableMatchesTheReference() {
    let converter = Self.converter(Self.configs[0])
    XCTAssertEqual(
      converter.formatTable(Self.tableRows[0], align: "c"),
      [
        "`c",
        "\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{252C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}",
        "\u{2502} a   \u{2502} b   \u{2502}",
        "\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}",
        "\u{2502} 1   \u{2502} 2   \u{2502}",
        "\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2534}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}",
        "`a",
      ])
    XCTAssertEqual(
      converter.formatTableRaw(Self.tableRows[0], align: "c"),
      [
        "`c",
        "\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{252C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}",
        "\u{2502} a   \u{2502} b   \u{2502}",
        "\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}",
        "\u{2502} 1   \u{2502} 2   \u{2502}",
        "\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2534}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}",
        "`a",
      ])
  }

  /// A scope set for one page is dropped again when the page's own scope is restored.
  func testURLScopeMatchesTheReference() {
    let converter = MarkdownToMicron(urlScope: ":/one/")
    XCTAssertEqual(converter.formatBlock("[a](b)"), "`_`!`[a`:/one/b]`!`_")
    converter.setURLScope(":/two/")
    XCTAssertEqual(converter.formatBlock("[a](b)"), "`_`!`[a`:/two/b]`!`_")
    converter.restoreURLScope()
    XCTAssertEqual(converter.formatBlock("[a](b)"), "`_`!`[a`:/one/b]`!`_")
  }
}
