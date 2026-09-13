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

/// One token of a lexed source file, as a dotted type path and the text it covers.
///
/// The type is spelled `Token.Literal.String.Double`, and each level has the level above it as its
/// parent.
public struct MicronToken {

  /// The token type, spelled as pygments spells it.
  public let type: String

  /// The source text this token covers.
  public let value: String

  /// Creates a token of `type` covering `value`.
  public init(type: String, value: String) {
    self.type = type
    self.value = value
  }
}

/// Supplies the token stream ``SyntaxHighlighter`` colors.
///
/// A node with no lexer renders code as an uncolored literal block.
public protocol MicronLexing {

  /// Returns the tokens for `code` under the lexer named `name`, or `nil` if there is none.
  func tokens(for code: String, lexerNamed name: String) throws -> [MicronToken]?

  /// Returns the tokens for `code` under the lexer `filename` selects, or `nil` if there is none.
  func tokens(for code: String, filename: String) throws -> [MicronToken]?

  /// Returns the tokens for `code` under a lexer guessed from it, or `nil` if there is none.
  func tokens(guessedFor code: String) throws -> [MicronToken]?
}

/// Writes a token stream out as Micron, coloring each token by its type.
///
/// Micron has no style sheet, so the color is written inline at every token and closed again
/// straight after it.
public struct MicronFormatter {

  /// The theme key each token type takes its color from.
  static let granularTokenMap: [String: String] = Dictionary(
    uniqueKeysWithValues: tokenMapEntries)

  private static let tokenMapEntries: [(String, String)] = [
    ("Token.Keyword", "keyword"),
    ("Token.Keyword.Constant", "keyword_constant"),
    ("Token.Keyword.Declaration", "keyword_declaration"),
    ("Token.Keyword.Namespace", "keyword_control"),
    ("Token.Keyword.Pseudo", "keyword_control"),
    ("Token.Keyword.Reserved", "keyword_control"),
    ("Token.Keyword.Type", "type_builtin"),
    ("Token.Name.Function", "function_call"),
    ("Token.Name.Function.Magic", "function_magic"),
    ("Token.Name.Class", "class_ref"),
    ("Token.Name.Builtin", "function_builtin"),
    ("Token.Name.Builtin.Pseudo", "constant_builtin"),
    ("Token.Name.Exception", "exception_builtin"),
    ("Token.Name.Decorator", "decorator"),
    ("Token.Name.Namespace", "namespace"),
    ("Token.Name.Attribute", "attribute"),
    ("Token.Name.Variable", "variable"),
    ("Token.Name.Variable.Magic", "function_magic"),
    ("Token.Name.Other", "name"),
    ("Token.Name", "name"),
    ("Token.Name.Tag", "keyword"),
    ("Token.Name.Constant", "constant"),
    ("Token.Name.Label", "name"),
    ("Token.Name.Entity", "name"),
    ("Token.Literal.String", "string"),
    ("Token.Literal.String.Affix", "string"),
    ("Token.Literal.String.Backtick", "string"),
    ("Token.Literal.String.Char", "string"),
    ("Token.Literal.String.Delimiter", "string"),
    ("Token.Literal.String.Doc", "string_doc"),
    ("Token.Literal.String.Double", "string_quoted"),
    ("Token.Literal.String.Escape", "string_escape"),
    ("Token.Literal.String.Heredoc", "string"),
    ("Token.Literal.String.Interpol", "string_interpol"),
    ("Token.Literal.String.Other", "string"),
    ("Token.Literal.String.Regex", "string"),
    ("Token.Literal.String.Single", "string_quoted"),
    ("Token.Literal.String.Symbol", "string"),
    ("Token.Literal.Number", "number"),
    ("Token.Literal.Number.Bin", "number"),
    ("Token.Literal.Number.Float", "number_float"),
    ("Token.Literal.Number.Hex", "number_hex"),
    ("Token.Literal.Number.Integer", "number_integer"),
    ("Token.Literal.Number.Integer.Long", "number_integer"),
    ("Token.Literal.Number.Oct", "number"),
    ("Token.Literal", "string"),
    ("Token.Literal.Date", "string"),
    ("Token.Operator", "operator"),
    ("Token.Operator.Word", "operator_word"),
    ("Token.Operator.Comparison", "operator_comparison"),
    ("Token.Operator.Assignment", "operator_assignment"),
    ("Token.Operator.Arithmetic", "operator_arithmetic"),
    ("Token.Punctuation", "punctuation"),
    ("Token.Punctuation.Marker", "punctuation"),
    ("Token.Punctuation.Brace", "punctuation_brace"),
    ("Token.Punctuation.Bracket", "punctuation_brace"),
    ("Token.Punctuation.Parenthesis", "punctuation_paren"),
    ("Token.Punctuation.Colon", "punctuation_colon"),
    ("Token.Punctuation.Comma", "punctuation_comma"),
    ("Token.Comment", "comment"),
    ("Token.Comment.Hashbang", "comment"),
    ("Token.Comment.Multiline", "comment_doc"),
    ("Token.Comment.Preproc", "comment_preproc"),
    ("Token.Comment.Single", "comment"),
    ("Token.Comment.Special", "comment"),
    ("Token.Generic.Deleted", "generic_deleted"),
    ("Token.Generic.Emph", "text"),
    ("Token.Generic.Error", "generic_error"),
    ("Token.Generic.Heading", "generic_heading"),
    ("Token.Generic.Inserted", "generic_inserted"),
    ("Token.Generic.Output", "generic_output"),
    ("Token.Generic.Prompt", "generic_prompt"),
    ("Token.Generic.Strong", "text"),
    ("Token.Generic.Subheading", "generic_subheading"),
    ("Token.Generic.Traceback", "generic_error"),
    ("Token.Generic", "text"),
    ("Token.Text", "text"),
    ("Token.Text.Whitespace", "whitespace"),
  ]

  /// Colors by theme key, where a `nil` color leaves the token uncolored.
  public let theme: [String: String?]

  /// Creates a formatter that colors tokens by `theme`.
  public init(theme: [String: String?]) {
    self.theme = theme
  }

  /// Returns `tokens` written out as Micron.
  public func format(_ tokens: [MicronToken]) -> String {
    var parts: [String] = []
    var previousWasDot = false
    var lastEndedWithBreak = true

    for token in tokens {
      let isDot = token.type == "Token.Operator" && token.value == "."
      let endsWithBreak = token.value.hasSuffix("\n")

      if previousWasDot, token.type.hasPrefix("Token.Name"), !token.value.isEmpty {
        let escaped = Self.escape(token.value)
        if let color = color(forKey: "attribute_call"), !color.isEmpty {
          parts.append("`FT\(color)\(escaped)`f")
        } else {
          parts.append(escaped)
        }
      } else if let color = color(forKey: Self.colorKey(for: token.type)), !color.isEmpty,
        !token.value.isEmpty
      {
        parts.append(Self.colored(Self.escape(token.value), color: color))
      } else {
        parts.append(Self.uncolored(Self.escape(token.value), afterBreak: lastEndedWithBreak))
      }

      previousWasDot = isDot
      lastEndedWithBreak = endsWithBreak
    }

    return parts.joined()
  }

  /// Returns the color `key` names, or `nil` when the theme leaves it uncolored.
  func color(forKey key: String?) -> String? {
    guard let key, let color = theme[key] else { return nil }
    return color
  }

  /// Returns the theme key for `type`, walking up its parents until one is mapped.
  ///
  /// The walk stops before the root token, which names nothing.
  static func colorKey(for type: String) -> String? {
    var current = type
    while current != "Token" {
      if let key = granularTokenMap[current] { return key }
      guard let dot = current.lastIndex(of: ".") else { return nil }
      current = String(current[current.startIndex..<dot])
    }
    return nil
  }

  /// Returns `escaped` wrapped in `color`, with a line break at either end left outside it.
  ///
  /// A tag that spans a line break would color the next line's left margin, so the break
  /// is written before the tag opens and after it closes.
  private static func colored(_ escaped: String, color: String) -> String {
    var text = escaped
    let leading = text.hasPrefix("\n") ? "\n" : ""
    if !leading.isEmpty { text.removeFirst() }
    let trailing = text.hasSuffix("\n") ? "\n" : ""
    if !trailing.isEmpty { text.removeLast() }
    if text.isEmpty { return leading + trailing }
    return "\(leading)`FT\(color)\(text)`f\(trailing)"
  }

  /// Returns `escaped` with any line that Micron would read as markup escaped as well.
  ///
  /// A line opening with `-`, `>` or `<` starts a Micron divider, quote or alignment, so
  /// each such line is prefixed with a backslash.
  private static func uncolored(_ escaped: String, afterBreak: Bool) -> String {
    if escaped.contains("\n") {
      let lines = escaped.pythonLines
      guard lines.count > 1 else { return escaped }
      let prefixed = lines.map { startsMarkup($0) ? "\\" + $0 : $0 }
      return prefixed.joined(separator: "\n") + (escaped.hasSuffix("\n") ? "\n" : "")
    }
    if afterBreak, startsMarkup(escaped) { return "\\" + escaped }
    return escaped
  }

  private static func startsMarkup(_ line: String) -> Bool {
    line.hasPrefix("-") || line.hasPrefix(">") || line.hasPrefix("<")
  }

  /// Returns `text` with the Micron control character escaped.
  ///
  /// The backslash is escaped first, so the backslash then written before each backtick is left
  /// alone.
  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
      of: "`", with: "\\`")
  }

}

/// Colors source code for a Micron page.
///
/// An `rngit` page node renders every file it serves and every fenced code block through this, so
/// the colors a browser shows are decided here rather than by the browser.
public final class SyntaxHighlighter: MicronSyntaxHighlighting {

  /// The colors used when no theme is given.
  ///
  /// A `nil` color means the token is written out with no tag at all.
  public static let defaultTheme: [String: String?] = Dictionary(
    uniqueKeysWithValues: themeEntries)

  private static let themeEntries: [(String, String?)] = [
    ("keyword", "ff7b72"),
    ("keyword_constant", "ff7b72"),
    ("keyword_control", "ff7b72"),
    ("keyword_declaration", "ff7b72"),
    ("function_def", "79c0ff"),
    ("function_magic", "ff7b72"),
    ("function_call", "d2a8ff"),
    ("function_builtin", "ffa657"),
    ("class_def", "7ee787"),
    ("class_ref", "56d364"),
    ("self", "ff9bce"),
    ("cls", "ff9bce"),
    ("string", "a5d6ff"),
    ("string_quoted", "a5d6ff"),
    ("string_doc", "8b949e"),
    ("string_interpol", "ffd700"),
    ("string_escape", "ffea00"),
    ("number", "79c0ff"),
    ("number_float", "79c0ff"),
    ("number_integer", "79c0ff"),
    ("number_hex", "79c0ff"),
    ("comment", "8b949e"),
    ("comment_doc", "8b949e"),
    ("comment_preproc", "ff7b72"),
    ("operator", "ff7b72"),
    ("operator_arithmetic", "ff7b72"),
    ("operator_comparison", "ff7b72"),
    ("operator_assignment", "ff7b72"),
    ("operator_word", "ff7b72"),
    ("operator_dot", "c9d1d9"),
    ("punctuation", "b4b4b4"),
    ("punctuation_brace", "b4b4b4"),
    ("punctuation_paren", "b4b4b4"),
    ("punctuation_colon", "b4b4b4"),
    ("punctuation_comma", "8b949e"),
    ("decorator", "f0883e"),
    ("constant", "ff7b72"),
    ("constant_builtin", "ff7b72"),
    ("type_hint", "ffa657"),
    ("type_builtin", "ffa657"),
    ("exception", "f85149"),
    ("exception_builtin", "f85149"),
    ("name", "e6edf3"),
    ("attribute", "e6edf3"),
    ("attribute_call", "d2a8ff"),
    ("variable", "e6edf3"),
    ("parameter", "e6edf3"),
    ("namespace", "7ee787"),
    ("module", "a5d6ff"),
    ("generic_heading", "c9d1d9"),
    ("generic_subheading", "c9d1d9"),
    ("generic_prompt", "8b949e"),
    ("generic_error", "f85149"),
    ("generic_deleted", "f85149"),
    ("generic_inserted", "7ee787"),
    ("generic_output", "e6edf3"),
    ("text", nil),
    ("whitespace", nil),
  ]

  /// The colors this highlighter renders with.
  public let theme: [String: String?]

  /// The lexer whose tokens are colored, or `nil` to render plain literal blocks.
  public let lexer: MicronLexing?

  /// Creates a highlighter rendering with `theme` and lexing with `lexer`.
  public init(theme: [String: String?]? = nil, lexer: MicronLexing? = nil) {
    self.theme = theme ?? Self.defaultTheme
    self.lexer = lexer
  }

  /// Returns `content` marked up in Micron, lexed by `language` or else by `filename`.
  ///
  /// Without a lexer, and for any lexing failure, the content is written out as an escaped literal
  /// block.
  public func highlight(_ content: String, filename: String?, language: String?) -> String {
    if content.isEmpty { return Self.plainText(content) }

    guard let lexer else { return Self.escapedPlainText(content) }

    do {
      var highlighted = try render(content, filename: filename, language: language, lexer: lexer)
      if highlighted.hasSuffix("\n"), !content.hasSuffix("\n") { highlighted.removeLast() }
      return highlighted
    } catch {
      return Self.escapedPlainText(content)
    }
  }

  /// Returns `code` marked up in Micron, for `language`.
  public func highlight(_ code: String, language: String?) -> String {
    highlight(code, filename: nil, language: language)
  }

  /// Returns `content` colored by the first lexer the three lookups find.
  ///
  /// Guessing is only tried on content long enough for the guess to mean anything.
  private func render(
    _ content: String, filename: String?, language: String?, lexer: MicronLexing
  ) throws -> String {
    var tokens: [MicronToken]?

    if var name = language, !name.isEmpty {
      if name == "env" { name = "bash" }
      if name == "environment" { name = "bash" }
      tokens = try lexer.tokens(for: content, lexerNamed: name)
    }
    if tokens == nil, let filename, !filename.isEmpty {
      tokens = try lexer.tokens(for: content, filename: filename)
    }
    if tokens == nil, content.unicodeScalars.count > 20 {
      tokens = try lexer.tokens(guessedFor: content)
    }

    guard let tokens else { return Self.plainText(content) }
    return MicronFormatter(theme: theme).format(tokens)
  }

  /// Returns `content` as an uncolored Micron literal block.
  static func plainText(_ content: String) -> String {
    "`=\n\(escapeMicron(content))\n`="
  }

  /// Returns `text` with the Micron control character escaped.
  public static func escapeMicron(_ text: String) -> String {
    text.replacingOccurrences(of: "`", with: "\\`")
  }

  /// Returns the literal block every fallback path writes, with its backslashes doubled.
  ///
  /// Doubles the backslashes the backtick escape has just written as well.
  private static func escapedPlainText(_ content: String) -> String {
    plainText(content).replacingOccurrences(of: "\\", with: "\\\\")
  }
}
