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

/// Colours a fenced code block for ``MarkdownToMicron``.
///
/// A throw takes the converter's literal-block fallback.
public protocol MicronSyntaxHighlighting {

  /// Returns `code` marked up in Micron, for `language`.
  func highlight(_ code: String, language: String?) throws -> String
}

/// Renders markdown as Micron, the markup a NomadNet browser displays.
///
/// An `rngit` page node converts a repository's README, release notes and work-item bodies with
/// this, so the output has to match byte for byte across implementations or the same page renders
/// differently depending on which node serves it.
public final class MarkdownToMicron {

  /// Micron markup the converter emits.
  private enum Markup {
    static let bold = "`!"
    static let italic = "`*"
    static let underline = "`_"
    static let codeBackground = "`BT282828"
    static let inlineCodeBackground = "`BT383838"
    static let codeForeground = "`Fddd"
    static let codeReset = "`f`b"
    static let literal = "`="
    static let bullet = "\u{2022}"
  }

  /// The box-drawing characters a rendered table is built from.
  private enum Box {
    static let horizontal = "\u{2500}"
    static let vertical = "\u{2502}"
    static let topLeft = "\u{250C}"
    static let topRight = "\u{2510}"
    static let bottomLeft = "\u{2514}"
    static let bottomRight = "\u{2518}"
    static let middleLeft = "\u{251C}"
    static let middleRight = "\u{2524}"
    static let topMiddle = "\u{252C}"
    static let bottomMiddle = "\u{2534}"
    static let cross = "\u{253C}"
  }

  /// How a table column's cells sit in their width.
  public enum Alignment: String {
    case left
    case center
    case right
  }

  /// Whether a line is rendered as markdown or passed through as code.
  public enum LineMode {
    case normal
    case codeBlock
  }

  /// The narrowest a table column may be squeezed to.
  private static let minimumColumnWidth = 3

  private static let whitespace = MicronPattern.whitespace
  private static let header = MicronPattern("^(#{1,6})\(whitespace)+(.+)$")
  private static let codeFence = MicronPattern("^(\(whitespace)*)```(.*)$")
  private static let horizontalRule =
    MicronPattern("^(\(whitespace)*)(---+|===+|\\*\\*\\*+|___+)\(whitespace)*$")
  private static let unorderedList = MicronPattern("^(\(whitespace)*)([-*+])\(whitespace)+(.+)$")
  private static let tableRow = MicronPattern("^\(whitespace)*\\|?(.+?)\\|?\(whitespace)*$")
  private static let tableSeparator =
    MicronPattern("^\(whitespace)*\\|?(?:\(whitespace)*:?-+:?\(whitespace)*\\|)+\(whitespace)*$")
  private static let quote = MicronPattern("^>\(whitespace)?(.*)$")
  private static let link = MicronPattern("\\[([^\\]]+)\\]\\(([^)]+)\\)")
  private static let inlineCode = MicronPattern("`([^`]+)`")
  private static let bold = MicronPattern("\\*\\*(.+?)\\*\\*|__(.+?)__")
  private static let italic = MicronPattern("\\*(.+?)\\*|_(.+?)_")
  private static let linkPlaceholder = MicronPattern("\\u0000LINK(\\d+)\\u0000")
  private static let codePlaceholder = MicronPattern("\\u0000CODE(\\d+)\\u0000")

  /// The Micron tags ``visibleWidth(of:)`` discounts, in the order they are applied.
  private static let invisibleTags = [
    MicronPattern("`[FB][0-9a-fA-F]{3}"),
    MicronPattern("`[FB]T[0-9a-fA-F]{6}"),
    MicronPattern("`[!*_=]"),
    MicronPattern("`f`b"),
    MicronPattern("`f"),
    MicronPattern("`b"),
  ]

  /// The widest line the converter emits.
  public let maxWidth: Int

  /// The highlighter fenced code blocks are passed to, if any.
  public let syntaxHighlighter: MicronSyntaxHighlighting?

  /// The scope prepended to a link target that carries no scheme.
  public private(set) var localURLScope: String

  /// Whether a link is rendered bold.
  public var boldLinks = true

  /// Whether a link is rendered underlined.
  public var underlineLinks = true

  /// A three or six digit hex color applied to links, if any.
  public var linkColor: String?

  private let defaultURLScope: String

  /// Creates a converter.
  ///
  /// An empty `urlScope` also takes the default.
  public init(
    maxWidth: Int = 100, syntaxHighlighter: MicronSyntaxHighlighting? = nil,
    urlScope: String? = nil
  ) {
    self.maxWidth = maxWidth
    self.syntaxHighlighter = syntaxHighlighter
    let scope = (urlScope?.isEmpty == false) ? (urlScope ?? "") : ":/page/"
    localURLScope = scope
    defaultURLScope = scope
  }

  /// Points link targets without a scheme at `scope`.
  public func setURLScope(_ scope: String) { localURLScope = scope }

  /// Restores the scope this converter was created with.
  public func restoreURLScope() { localURLScope = defaultURLScope }

  // MARK: - Blocks

  /// Returns `text` rendered as Micron.
  public func formatBlock(_ text: String) -> String {
    var result: [String] = []

    var inCodeBlock = false
    var codeBlockLanguage: String?
    var codeBuffer: [String] = []
    var inTable = false
    var tableBuffer: [String] = []
    var inQuote = false
    var quoteBuffer: [String] = []

    func flushQuoteBuffer() {
      if quoteBuffer.isEmpty {
        inQuote = false
        return
      }

      let paragraph = quoteBuffer.joined(separator: " ")
      let formatted = formatInline(paragraph)
      let effectiveWidth = max(maxWidth - 3, 1)
      for wrapped in wrap(formatted, to: effectiveWidth) {
        result.append(" \(Box.vertical) \(wrapped)")
      }

      quoteBuffer = []
      inQuote = false
    }

    func flushTableBuffer() {
      if tableBuffer.isEmpty {
        inTable = false
        return
      }

      if tableBuffer.count >= 2, isTableSeparator(tableBuffer[1]) {
        result.append(contentsOf: formatTable(tableBuffer))
      } else {
        for line in tableBuffer { result.append(formatLine(line)) }
      }

      tableBuffer = []
      inTable = false
    }

    func flushCodeBlock() {
      if codeBuffer.isEmpty { return }
      let code = codeBuffer.joined(separator: "\n")

      func appendLiteral() {
        result.append("\(Markup.codeBackground)\(Markup.codeForeground)")
        result.append(Markup.literal)
        result.append(escapeLiterals(code))
        result.append(Markup.literal)
        result.append(Markup.codeReset)
      }

      if let highlighter = syntaxHighlighter, let language = codeBlockLanguage, !language.isEmpty {
        if language.lowercased() == "rawmu" {
          result.append(code)
        } else if let highlighted = try? highlighter.highlight(code, language: language) {
          result.append("\(Markup.codeBackground)\(Markup.codeForeground)")
          result.append(highlighted)
          result.append(Markup.codeReset)
        } else {
          appendLiteral()
        }
      } else {
        appendLiteral()
      }

      codeBuffer = []
    }

    for line in text.components(separatedBy: "\n") {
      let (isFence, languageHint) = detectCodeFence(line)

      if isFence {
        flushQuoteBuffer()
        flushTableBuffer()

        if !inCodeBlock {
          inCodeBlock = true
          codeBlockLanguage = languageHint.isEmpty ? nil : languageHint.trimmedForMicron
          codeBuffer = []
        } else {
          flushCodeBlock()
          inCodeBlock = false
          codeBlockLanguage = nil
        }
        continue
      }

      if inCodeBlock {
        codeBuffer.append(line)
        continue
      }

      if let quoteMatch = Self.quote.match(line) {
        if !inQuote {
          flushTableBuffer()
          inQuote = true
          quoteBuffer = []
        }
        quoteBuffer.append(quoteMatch[1] ?? "")
        continue
      }

      if inQuote {
        flushQuoteBuffer()
        if line.trimmedForMicron.isEmpty {
          result.append("")
        } else if isTableRow(line) {
          inTable = true
          tableBuffer = [line]
        } else {
          result.append(formatLine(line))
        }
        continue
      }

      if isTableRow(line) {
        if !inTable {
          inTable = true
          tableBuffer = [line]
        } else {
          tableBuffer.append(line)
        }
        continue
      }

      if inTable { flushTableBuffer() }
      result.append(formatLine(line))
    }

    if inQuote { flushQuoteBuffer() }
    if inTable { flushTableBuffer() }
    if inCodeBlock { flushCodeBlock() }

    return result.joined(separator: "\n")
  }

  // MARK: - Lines

  /// Returns one line rendered as Micron.
  public func formatLine(_ line: String, mode: LineMode = .normal) -> String {
    if mode == .codeBlock { return escapeLiterals(line) }

    var line = line.replacingOccurrences(of: "\\", with: "\\\\")

    if line.hasPrefix("-"), !line.hasPrefix("---"), !line.hasPrefix("- ") { line = "\\\(line)" }
    if line.hasPrefix("<") { line = "\\\(line)" }

    if Self.horizontalRule.matches(line) { return "-" }
    if let match = Self.header.match(line) { return formatHeader(match) }
    if let match = Self.unorderedList.match(line) { return formatListItem(match) }

    return formatInline(line)
  }

  private func formatHeader(_ match: [String?]) -> String {
    let level = min((match[1] ?? "").count, 6)
    return String(repeating: ">", count: level) + formatInline(match[2] ?? "")
  }

  private func formatListItem(_ match: [String?]) -> String {
    "\(match[1] ?? "") \(Markup.bullet) \(formatInline(match[3] ?? ""))"
  }

  private func detectCodeFence(_ line: String) -> (isFence: Bool, languageHint: String) {
    guard let match = Self.codeFence.match(line) else { return (false, "") }
    return (true, match[2] ?? "")
  }

  private func escapeLiterals(_ text: String) -> String {
    text.replacingOccurrences(of: "`", with: "\\`")
  }

  // MARK: - Inline markup

  /// Returns `text` with links, code spans, bold and italic rendered.
  ///
  /// Links and code spans are lifted out before bold and italic run, so emphasis markers inside
  /// them survive literally, and they are put back afterwards.
  private func formatInline(_ text: String) -> String {
    var links: [(text: String, url: String)] = []
    var codeSpans: [String] = []

    var text = Self.link.replacingMatches(in: text) { groups in
      links.append((groups[1] ?? "", groups[2] ?? ""))
      return "\u{0}LINK\(links.count - 1)\u{0}"
    }
    text = Self.inlineCode.replacingMatches(in: text) { groups in
      codeSpans.append(groups[1] ?? "")
      return "\u{0}CODE\(codeSpans.count - 1)\u{0}"
    }
    text = Self.bold.replacingMatches(in: text) { groups in
      "\(Markup.bold)\(groups[1] ?? groups[2] ?? "")\(Markup.bold)"
    }
    text = Self.italic.replacingMatches(in: text) { groups in
      "\(Markup.italic)\(groups[1] ?? groups[2] ?? "")\(Markup.italic)"
    }

    text = Self.linkPlaceholder.replacingMatches(in: text) { groups in
      guard let slot = Self.placeholderSlot(groups) else { return "" }
      return self.renderLink(links[slot])
    }
    text = Self.codePlaceholder.replacingMatches(in: text) { groups in
      guard let slot = Self.placeholderSlot(groups) else { return "" }
      let content = codeSpans[slot].replacingOccurrences(of: "`", with: "\\`")
      return
        "\(Markup.inlineCodeBackground)\(Markup.codeForeground)\(content)\(Markup.codeReset)"
    }
    return text
  }

  /// Returns the slot a placeholder carries, which ``formatInline(_:)`` wrote itself.
  private static func placeholderSlot(_ groups: [String?]) -> Int? {
    guard let digits = groups[1] else { return nil }
    return Int(digits)
  }

  /// Returns a link target rendered with its scope, anchor and styling.
  ///
  /// An anchor survives only on a target that takes the local scope; one that carries a scheme
  /// keeps just the part before the `#`.
  private func renderLink(_ entry: (text: String, url: String)) -> String {
    let components = entry.url.components(separatedBy: "#")
    var url = components[0]
    let anchor = components.count > 1 ? components[1] : ""

    if !url.contains(":/") {
      url = "\(localURLScope)\(url)"
      if !anchor.isEmpty { url = "\(url)|anchor=\(anchor)" }
    }

    let underline = underlineLinks ? Markup.underline : ""
    let emphasis = boldLinks ? Markup.bold : ""
    let label = entry.text.replacingOccurrences(of: "`", with: "")
    var link = "\(underline)\(emphasis)`[\(label)`\(url)]\(emphasis)\(underline)"

    if let color = linkColor, color.count == 3 { link = "`F\(color)\(link)`f" }
    if let color = linkColor, color.count == 6 { link = "`FT\(color)\(link)`f" }
    return link
  }

  // MARK: - Tables

  private func isTableRow(_ line: String) -> Bool {
    guard line.contains("|"), let match = Self.tableRow.match(line) else { return false }
    return (match[1] ?? "").contains("|") || line.trimmedForMicron.hasPrefix("|")
  }

  private func isTableSeparator(_ line: String) -> Bool {
    line.contains("|") && Self.tableSeparator.matches(line)
  }

  /// Returns the rows rendered as a boxed table, with each cell's markdown converted.
  public func formatTable(_ rows: [String], align: String = "c") -> [String] {
    buildTable(rows, align: align, convertCells: true)
  }

  /// Returns the rows rendered as a boxed table, with each cell passed through as written.
  ///
  /// Leaves the header line unescaped where ``formatTable(_:align:)`` escapes it.
  public func formatTableRaw(_ rows: [String], align: String = "c") -> [String] {
    buildTable(rows, align: align, convertCells: false)
  }

  private func buildTable(_ rows: [String], align: String, convertCells: Bool) -> [String] {
    if rows.count < 2 { return rows }

    let headerCells = parseTableRow(rows[0])
    var alignments = parseTableAlignments(rows[1])
    while alignments.count < headerCells.count { alignments.append(.left) }
    alignments = Array(alignments.prefix(headerCells.count))

    var dataRows: [[String]] = []
    for index in 2..<rows.count {
      var cells = parseTableRow(rows[index])
      while cells.count < headerCells.count { cells.append("") }
      dataRows.append(Array(cells.prefix(headerCells.count)))
    }

    let columns = headerCells.count
    var widths = [Int](repeating: 0, count: columns)
    for row in [headerCells] + dataRows {
      for (index, cell) in row.enumerated() {
        let measured = convertCells ? formatInline(cell) : cell
        widths[index] = max(widths[index], visibleWidth(of: measured))
      }
    }
    widths = widths.map { max($0, Self.minimumColumnWidth) }

    var excess = widths.reduce(0, +) + (columns * 3) + 1 - maxWidth
    if excess > 0 {
      // Widest first, and ties in column order: Python's sort is stable.
      let order = widths.enumerated()
        .sorted { $0.element != $1.element ? $0.element > $1.element : $0.offset < $1.offset }
        .map(\.offset)
      for index in order {
        if excess <= 0 { break }
        let reduction = min(excess, widths[index] - Self.minimumColumnWidth)
        widths[index] -= reduction
        excess -= reduction
      }
    }

    func rule(left: String, joint: String, right: String) -> String {
      var line = left
      for (index, width) in widths.enumerated() {
        line += String(repeating: Box.horizontal, count: width + 2)
        line += index < widths.count - 1 ? joint : right
      }
      return line
    }

    var result: [String] = []
    if !align.isEmpty { result.append("`\(align)") }
    result.append(
      escapeLiterals(rule(left: Box.topLeft, joint: Box.topMiddle, right: Box.topRight)))

    var headerLine = Box.vertical
    for (index, cell) in headerCells.enumerated() {
      let content = convertCells ? formatInline(cell) : cell
      headerLine += " \(pad(content, to: widths[index], align: .left)) \(Box.vertical)"
    }
    result.append(convertCells ? escapeLiterals(headerLine) : headerLine)

    result.append(
      escapeLiterals(rule(left: Box.middleLeft, joint: Box.cross, right: Box.middleRight)))

    for row in dataRows {
      var line = Box.vertical
      for (index, cell) in row.enumerated() {
        let content = convertCells ? formatInline(cell) : cell
        line += " \(pad(content, to: widths[index], align: alignments[index])) \(Box.vertical)"
      }
      result.append(line)
    }

    result.append(
      escapeLiterals(rule(left: Box.bottomLeft, joint: Box.bottomMiddle, right: Box.bottomRight)))
    if !align.isEmpty { result.append("`a") }
    return result
  }

  /// A backslash escapes the next character and is itself dropped.
  private func parseTableRow(_ line: String) -> [String] {
    var line = line.trimmedForMicron
    if line.hasPrefix("|") { line.removeFirst() }
    if line.hasSuffix("|") { line.removeLast() }

    var cells: [String] = []
    var current = ""
    var escaped = false
    for character in line {
      if escaped {
        current.append(character)
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "|" {
        cells.append(current.trimmedForMicron)
        current = ""
      } else {
        current.append(character)
      }
    }
    cells.append(current.trimmedForMicron)
    return cells
  }

  private func parseTableAlignments(_ line: String) -> [Alignment] {
    parseTableRow(line).map { cell in
      let cell = cell.trimmedForMicron
      if cell.hasPrefix(":") && cell.hasSuffix(":") { return .center }
      if cell.hasSuffix(":") { return .right }
      return .left
    }
  }

  // MARK: - Measurement

  /// The cells `text` occupies once its Micron tags are discounted.
  private func visibleWidth(of text: String) -> Int {
    var stripped = text
    for pattern in Self.invisibleTags { stripped = pattern.removingMatches(in: stripped) }
    return DisplayWidth.display(of: stripped)
  }

  /// Returns `text` laid into `width` cells under `align`.
  ///
  /// A cell wider than its column is truncated first, which can leave no padding at all.
  private func pad(_ text: String, to width: Int, align: Alignment) -> String {
    let text = truncate(text, to: width)
    let padding = max(width - visibleWidth(of: text), 0)

    switch align {
    case .right:
      return String(repeating: " ", count: padding) + text
    case .center:
      let left = padding / 2
      return String(repeating: " ", count: left) + text
        + String(repeating: " ", count: padding - left)
    case .left:
      return text + String(repeating: " ", count: padding)
    }
  }

  /// Returns `text` cut to `width` cells, with an ellipsis in place of what was dropped.
  ///
  /// Cutting a cell can leave a Micron tag open, so the tags still active at the cut are closed
  /// before the ellipsis.
  private func truncate(_ text: String, to width: Int) -> String {
    if visibleWidth(of: text) <= width { return text }

    let scalars = Array(text.unicodeScalars)
    func prefix(_ count: Int) -> String {
      var view = String.UnicodeScalarView()
      for index in 0..<count { view.append(scalars[index]) }
      return String(view)
    }

    var point = scalars.count
    while point > 0, visibleWidth(of: prefix(point)) >= width { point -= 1 }
    let truncated = prefix(point)

    var openTags: [Unicode.Scalar] = []
    var foregroundActive = false
    var backgroundActive = false
    let kept = Array(truncated.unicodeScalars)

    var index = 0
    while index < kept.count {
      if kept[index] == "`", index + 1 < kept.count {
        let tag = kept[index + 1]
        switch tag {
        case "!", "*", "_", "=":
          if let existing = openTags.firstIndex(of: tag) {
            openTags.remove(at: existing)
          } else {
            openTags.append(tag)
          }
          index += 2
          continue
        case "f":
          foregroundActive = false
          index += 2
          continue
        case "b":
          backgroundActive = false
          index += 2
          continue
        case "F", "B":
          if tag == "F" { foregroundActive = true } else { backgroundActive = true }
          index += (index + 2 < kept.count && kept[index + 2] == "T") ? 8 : 5
          continue
        default:
          break
        }
      }
      index += 1
    }

    var closers = ""
    if foregroundActive { closers += "`f" }
    if backgroundActive { closers += "`b" }
    for tag in openTags { closers += "`\(tag)" }
    return truncated + closers + "\u{2026}"
  }

  /// Returns `text` broken into lines of at most `width` cells.
  ///
  /// A word wider than the line is broken by binary search on how much of it fits.
  private func wrap(_ text: String, to width: Int) -> [String] {
    if text.isEmpty { return [""] }

    var lines: [String] = []
    var current = ""
    var currentWidth = 0

    for word in text.components(separatedBy: " ") where !word.isEmpty {
      let wordWidth = visibleWidth(of: word)

      if wordWidth > width {
        if !current.isEmpty {
          lines.append(current)
          current = ""
          currentWidth = 0
        }

        var remaining = Array(word.unicodeScalars)
        while !remaining.isEmpty {
          func prefix(_ count: Int) -> String {
            var view = String.UnicodeScalarView()
            for index in 0..<count { view.append(remaining[index]) }
            return String(view)
          }

          var low = 1
          var high = remaining.count
          var fits = 0
          while low <= high {
            let middle = (low + high) / 2
            if visibleWidth(of: prefix(middle)) <= width {
              fits = middle
              low = middle + 1
            } else {
              high = middle - 1
            }
          }
          if fits == 0 { fits = 1 }

          lines.append(prefix(fits))
          remaining.removeFirst(fits)
        }
        continue
      }

      let spacing = current.isEmpty ? 0 : 1
      if currentWidth + spacing + wordWidth <= width {
        if current.isEmpty {
          current = word
          currentWidth = wordWidth
        } else {
          current += " " + word
          currentWidth += spacing + wordWidth
        }
      } else {
        lines.append(current)
        current = word
        currentWidth = wordWidth
      }
    }

    if !current.isEmpty { lines.append(current) }
    return lines.isEmpty ? [""] : lines
  }
}

/// Returns `text` rendered as Micron with the converter's defaults.
public func convertMarkdownToMicron(_ text: String) -> String {
  MarkdownToMicron().formatBlock(text)
}
