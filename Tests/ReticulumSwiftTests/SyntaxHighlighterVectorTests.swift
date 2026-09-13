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
import XCTest

@testable import ReticulumSwift

/// Micron captured from `SyntaxHighlighter` in Python RNS 1.5.4.
///
/// Pygments is not an RNS dependency, so the token streams here were taken from pygments
/// 2.15.1 and fed to the reference's own formatter. Comparing against that recording
/// rather than against another Swift call is what makes a transcription error visible.
final class SyntaxHighlighterVectorTests: XCTestCase {

  private struct Stream {
    let language: String
    let tokens: [(type: String, value: String)]
    let expected: String
  }

  private struct Lookup {
    let content: String
    let filename: String?
    let language: String?
    let byName: [(type: String, value: String)]?
    let byFilename: [(type: String, value: String)]?
    let guessed: [(type: String, value: String)]?
    let namesAsked: [String]
    let filenamesAsked: [String]
    let guesses: Int
    let expected: String
  }

  /// Answers the three lexer lookups from a recording, and records what it was asked for.
  private final class RecordedLexer: MicronLexing {
    private let lookup: Lookup
    private(set) var namesAsked: [String] = []
    private(set) var filenamesAsked: [String] = []
    private(set) var guesses = 0

    init(_ lookup: Lookup) { self.lookup = lookup }

    func tokens(for code: String, lexerNamed name: String) throws -> [MicronToken]? {
      namesAsked.append(name)
      return Self.convert(lookup.byName)
    }

    func tokens(for code: String, filename: String) throws -> [MicronToken]? {
      filenamesAsked.append(filename)
      return Self.convert(lookup.byFilename)
    }

    func tokens(guessedFor code: String) throws -> [MicronToken]? {
      guesses += 1
      return Self.convert(lookup.guessed)
    }

    private static func convert(_ pairs: [(type: String, value: String)]?) -> [MicronToken]? {
      pairs.map { $0.map { MicronToken(type: $0.type, value: $0.value) } }
    }
  }

  /// Fails every lookup, as a lexer raising anything but "no such lexer" does.
  private struct FailingLexer: MicronLexing {
    struct Failure: Error {}

    func tokens(for code: String, lexerNamed name: String) throws -> [MicronToken]? {
      throw Failure()
    }

    func tokens(for code: String, filename: String) throws -> [MicronToken]? { throw Failure() }

    func tokens(guessedFor code: String) throws -> [MicronToken]? { throw Failure() }
  }

  private static let themeVectors: [(key: String, color: String?)] = [
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

  private static let tokenMapVectors: [(type: String, key: String)] = [
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

  private static let colorKeyVectors: [(type: String, key: String?)] = [
    ("Token", nil),
    ("Token.Comment", "comment"),
    ("Token.Comment.Hashbang", "comment"),
    ("Token.Comment.Multiline", "comment_doc"),
    ("Token.Comment.Preproc", "comment_preproc"),
    ("Token.Comment.PreprocFile", "comment"),
    ("Token.Comment.Single", "comment"),
    ("Token.Comment.Special", "comment"),
    ("Token.Error", nil),
    ("Token.Escape", nil),
    ("Token.Generic", "text"),
    ("Token.Generic.Deleted", "generic_deleted"),
    ("Token.Generic.Emph", "text"),
    ("Token.Generic.EmphStrong", "text"),
    ("Token.Generic.Error", "generic_error"),
    ("Token.Generic.Heading", "generic_heading"),
    ("Token.Generic.Inserted", "generic_inserted"),
    ("Token.Generic.Output", "generic_output"),
    ("Token.Generic.Prompt", "generic_prompt"),
    ("Token.Generic.Strong", "text"),
    ("Token.Generic.Subheading", "generic_subheading"),
    ("Token.Generic.Traceback", "generic_error"),
    ("Token.Keyword", "keyword"),
    ("Token.Keyword.Constant", "keyword_constant"),
    ("Token.Keyword.Declaration", "keyword_declaration"),
    ("Token.Keyword.Namespace", "keyword_control"),
    ("Token.Keyword.Pseudo", "keyword_control"),
    ("Token.Keyword.Removed", "keyword"),
    ("Token.Keyword.Reserved", "keyword_control"),
    ("Token.Keyword.Type", "type_builtin"),
    ("Token.Literal", "string"),
    ("Token.Literal.Date", "string"),
    ("Token.Literal.Number", "number"),
    ("Token.Literal.Number.Bin", "number"),
    ("Token.Literal.Number.Float", "number_float"),
    ("Token.Literal.Number.Hex", "number_hex"),
    ("Token.Literal.Number.Integer", "number_integer"),
    ("Token.Literal.Number.Integer.Long", "number_integer"),
    ("Token.Literal.Number.Oct", "number"),
    ("Token.Literal.Scalar.Plain", "string"),
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
    ("Token.Name", "name"),
    ("Token.Name.Attribute", "attribute"),
    ("Token.Name.Builtin", "function_builtin"),
    ("Token.Name.Builtin.Pseudo", "constant_builtin"),
    ("Token.Name.Class", "class_ref"),
    ("Token.Name.Constant", "constant"),
    ("Token.Name.Decorator", "decorator"),
    ("Token.Name.Entity", "name"),
    ("Token.Name.Exception", "exception_builtin"),
    ("Token.Name.Function", "function_call"),
    ("Token.Name.Function.Magic", "function_magic"),
    ("Token.Name.Label", "name"),
    ("Token.Name.Namespace", "namespace"),
    ("Token.Name.Other", "name"),
    ("Token.Name.Tag", "keyword"),
    ("Token.Name.Variable", "variable"),
    ("Token.Name.Variable.Class", "variable"),
    ("Token.Name.Variable.Magic", "function_magic"),
    ("Token.Operator", "operator"),
    ("Token.Operator.Arithmetic", "operator_arithmetic"),
    ("Token.Operator.Assignment", "operator_assignment"),
    ("Token.Operator.Comparison", "operator_comparison"),
    ("Token.Operator.Word", "operator_word"),
    ("Token.Other", nil),
    ("Token.Punctuation", "punctuation"),
    ("Token.Punctuation.Brace", "punctuation_brace"),
    ("Token.Punctuation.Bracket", "punctuation_brace"),
    ("Token.Punctuation.Colon", "punctuation_colon"),
    ("Token.Punctuation.Comma", "punctuation_comma"),
    ("Token.Punctuation.Indicator", "punctuation"),
    ("Token.Punctuation.Marker", "punctuation"),
    ("Token.Punctuation.Parenthesis", "punctuation_paren"),
    ("Token.Text", "text"),
    ("Token.Text.Whitespace", "whitespace"),
  ]

  /// Token streams with the Micron the reference's formatter wrote for each.
  ///
  /// The last three carry a carriage return, which `pygments.lex` folds to a line feed
  /// before any lexer sees it. They were fed to the reference formatter directly, as
  /// `format` takes any sequence of pairs and ``MicronLexing`` allows a lexer that does
  /// not fold.
  private static let streams: [Stream] = [
    Stream(
      language: "python",
      tokens: [
        ("Token.Keyword.Namespace", "import"),
        ("Token.Text", " "),
        ("Token.Name.Namespace", "os"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name.Decorator", "@decorator"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Keyword", "class"),
        ("Token.Text", " "),
        ("Token.Name.Class", "Foo"),
        ("Token.Punctuation", "("),
        ("Token.Name", "Bar"),
        ("Token.Punctuation", ")"),
        ("Token.Punctuation", ":"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text.Whitespace", "    "),
        ("Token.Literal.String.Doc", "\"\"\"Doc.\"\"\""),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text", "    "),
        ("Token.Keyword", "def"),
        ("Token.Text", " "),
        ("Token.Name.Function.Magic", "__init__"),
        ("Token.Punctuation", "("),
        ("Token.Name.Builtin.Pseudo", "self"),
        ("Token.Punctuation", ","),
        ("Token.Text", " "),
        ("Token.Name", "x"),
        ("Token.Punctuation", ":"),
        ("Token.Text", " "),
        ("Token.Name.Builtin", "int"),
        ("Token.Text", " "),
        ("Token.Operator", "="),
        ("Token.Text", " "),
        ("Token.Literal.Number.Integer", "3"),
        ("Token.Punctuation", ")"),
        ("Token.Punctuation", ":"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text", "        "),
        ("Token.Name.Builtin.Pseudo", "self"),
        ("Token.Operator", "."),
        ("Token.Name", "x"),
        ("Token.Text", " "),
        ("Token.Operator", "="),
        ("Token.Text", " "),
        ("Token.Name", "x"),
        ("Token.Text", "  "),
        ("Token.Comment.Single", "# note"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text", "        "),
        ("Token.Name", "s"),
        ("Token.Text", " "),
        ("Token.Operator", "="),
        ("Token.Text", " "),
        ("Token.Literal.String.Affix", "f"),
        ("Token.Literal.String.Double", "\""),
        ("Token.Literal.String.Double", "a"),
        ("Token.Literal.String.Interpol", "{"),
        ("Token.Name", "x"),
        ("Token.Literal.String.Interpol", "}"),
        ("Token.Literal.String.Double", "b"),
        ("Token.Literal.String.Escape", "\\n"),
        ("Token.Literal.String.Double", "\""),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text", "        "),
        ("Token.Keyword", "return"),
        ("Token.Text", " "),
        ("Token.Name", "os"),
        ("Token.Operator", "."),
        ("Token.Name", "path"),
        ("Token.Operator", "."),
        ("Token.Name", "join"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "a"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Punctuation", ","),
        ("Token.Text", " "),
        ("Token.Literal.String.Double", "\""),
        ("Token.Literal.String.Double", "b"),
        ("Token.Literal.String.Double", "\""),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTff7b72import`f `FT7ee787os`f\n\n`FTf0883e@decorator`f\n`FTff7b72class`f `",
        "FT56d364Foo`f`FTb4b4b4(`f`FTe6edf3Bar`f`FTb4b4b4)`f`FTb4b4b4:`f\n    `FT8b94",
        "9e\"\"\"Doc.\"\"\"`f\n    `FTff7b72def`f `FTff7b72__init__`f`FTb4b4b4(`f`FTf",
        "f7b72self`f`FTb4b4b4,`f `FTe6edf3x`f`FTb4b4b4:`f `FTffa657int`f `FTff7b72=`f",
        " `FT79c0ff3`f`FTb4b4b4)`f`FTb4b4b4:`f\n        `FTff7b72self`f`FTff7b72.`f`F",
        "Td2a8ffx`f `FTff7b72=`f `FTe6edf3x`f  `FT8b949e# note`f\n        `FTe6edf3s`",
        "f `FTff7b72=`f `FTa5d6fff`f`FTa5d6ff\"`f`FTa5d6ffa`f`FTffd700{`f`FTe6edf3x`f",
        "`FTffd700}`f`FTa5d6ffb`f`FTffea00\\\\n`f`FTa5d6ff\"`f\n        `FTff7b72retu",
        "rn`f `FTe6edf3os`f`FTff7b72.`f`FTd2a8ffpath`f`FTff7b72.`f`FTd2a8ffjoin`f`FTb",
        "4b4b4(`f`FTa5d6ff'`f`FTa5d6ffa`f`FTa5d6ff'`f`FTb4b4b4,`f `FTa5d6ff\"`f`FTa5d",
        "6ffb`f`FTa5d6ff\"`f`FTb4b4b4)`f\n",
      ].joined()),
    Stream(
      language: "python",
      tokens: [
        ("Token.Name", "x"),
        ("Token.Text", " "),
        ("Token.Operator", "="),
        ("Token.Text", " "),
        ("Token.Literal.Number.Hex", "0xFF"),
        ("Token.Text", " "),
        ("Token.Operator", "+"),
        ("Token.Text", " "),
        ("Token.Literal.Number.Float", "1.5e3"),
        ("Token.Text", " "),
        ("Token.Operator", "-"),
        ("Token.Text", " "),
        ("Token.Literal.Number.Bin", "0b1010"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Keyword", "if"),
        ("Token.Text", " "),
        ("Token.Name", "x"),
        ("Token.Text", " "),
        ("Token.Operator.Word", "is"),
        ("Token.Text", " "),
        ("Token.Operator.Word", "not"),
        ("Token.Text", " "),
        ("Token.Keyword.Constant", "None"),
        ("Token.Text", " "),
        ("Token.Operator.Word", "and"),
        ("Token.Text", " "),
        ("Token.Keyword.Constant", "True"),
        ("Token.Punctuation", ":"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text", "    "),
        ("Token.Keyword", "raise"),
        ("Token.Text", " "),
        ("Token.Name.Exception", "ValueError"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "bad"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTe6edf3x`f `FTff7b72=`f `FT79c0ff0xFF`f `FTff7b72+`f `FT79c0ff1.5e3`f `FTf",
        "f7b72-`f `FT79c0ff0b1010`f\n`FTff7b72if`f `FTe6edf3x`f `FTff7b72is`f `FTff7b",
        "72not`f `FTff7b72None`f `FTff7b72and`f `FTff7b72True`f`FTb4b4b4:`f\n    `FTf",
        "f7b72raise`f `FTf85149ValueError`f`FTb4b4b4(`f`FTa5d6ff'`f`FTa5d6ffbad`f`FTa",
        "5d6ff'`f`FTb4b4b4)`f\n",
      ].joined()),
    Stream(
      language: "bash",
      tokens: [
        ("Token.Comment.Hashbang", "#!/bin/bash\n"),
        ("Token.Name.Builtin", "export"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Variable", "A"),
        ("Token.Operator", "="),
        ("Token.Literal.Number", "1"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Keyword", "if"),
        ("Token.Text.Whitespace", " "),
        ("Token.Operator", "["),
        ("Token.Text.Whitespace", " "),
        ("Token.Text", "-f"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String.Double", "\""),
        ("Token.Name.Variable", "$A"),
        ("Token.Literal.String.Double", "\""),
        ("Token.Text.Whitespace", " "),
        ("Token.Operator", "]"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", " "),
        ("Token.Keyword", "then"),
        ("Token.Text.Whitespace", "\n  "),
        ("Token.Name.Builtin", "echo"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String.Single", "'hi'"),
        ("Token.Text.Whitespace", " "),
        ("Token.Punctuation", "|"),
        ("Token.Text.Whitespace", " "),
        ("Token.Text", "grep"),
        ("Token.Text.Whitespace", " "),
        ("Token.Text", "-v"),
        ("Token.Text.Whitespace", " "),
        ("Token.Text", "x"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Keyword", "fi"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FT8b949e#!/bin/bash`f\n`FTffa657export`f `FTe6edf3A`f`FTff7b72=`f`FT79c0ff1",
        "`f\n`FTff7b72if`f `FTff7b72[`f -f `FTa5d6ff\"`f`FTe6edf3$A`f`FTa5d6ff\"`f `F",
        "Tff7b72]`f`FTb4b4b4;`f `FTff7b72then`f\n  `FTffa657echo`f `FTa5d6ff'hi'`f `F",
        "Tb4b4b4|`f grep -v x\n`FTff7b72fi`f\n",
      ].joined()),
    Stream(
      language: "diff",
      tokens: [
        ("Token.Generic.Deleted", "--- a/x"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Generic.Inserted", "+++ b/x"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Generic.Subheading", "@@ -1,2 +1,2 @@"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Generic.Deleted", "-old line"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Generic.Inserted", "+new line"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text.Whitespace", " "),
        ("Token.Text", "context"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTf85149--- a/x`f\n`FT7ee787+++ b/x`f\n`FTc9d1d9@@ -1,2 +1,2 @@`f\n`FTf8514",
        "9-old line`f\n`FT7ee787+new line`f\n context\n",
      ].joined()),
    Stream(
      language: "markdown",
      tokens: [
        ("Token.Generic.Heading", "# Head"),
        ("Token.Text", "\n"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Keyword", "-"),
        ("Token.Text.Whitespace", " "),
        ("Token.Text", "item"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Keyword", "> "),
        ("Token.Generic.Emph", "quote\n"),
        ("Token.Text", "\n"),
        ("Token.Literal.String.Backtick", "`code`"),
        ("Token.Text", " "),
        ("Token.Text", "and"),
        ("Token.Text", " "),
        ("Token.Generic.Strong", "**bold**"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTc9d1d9# Head`f\n\n`FTff7b72-`f item\n`FTff7b72> `fquote\n\n`FTa5d6ff\\`co",
        "de\\``f and **bold**\n",
      ].joined()),
    Stream(
      language: "html",
      tokens: [
        ("Token.Punctuation", "<"),
        ("Token.Name.Tag", "div"),
        ("Token.Text", " "),
        ("Token.Name.Attribute", "class"),
        ("Token.Operator", "="),
        ("Token.Literal.String", "\"a\""),
        ("Token.Punctuation", ">"),
        ("Token.Text", "\n  "),
        ("Token.Punctuation", "<"),
        ("Token.Name.Tag", "span"),
        ("Token.Punctuation", ">"),
        ("Token.Text", "text"),
        ("Token.Punctuation", "<"),
        ("Token.Punctuation", "/"),
        ("Token.Name.Tag", "span"),
        ("Token.Punctuation", ">"),
        ("Token.Text", "\n"),
        ("Token.Punctuation", "<"),
        ("Token.Punctuation", "/"),
        ("Token.Name.Tag", "div"),
        ("Token.Punctuation", ">"),
        ("Token.Text", "\n"),
      ],
      expected: [
        "`FTb4b4b4<`f`FTff7b72div`f `FTe6edf3class`f`FTff7b72=`f`FTa5d6ff\"a\"`f`FTb4",
        "b4b4>`f\n  `FTb4b4b4<`f`FTff7b72span`f`FTb4b4b4>`ftext`FTb4b4b4<`f`FTb4b4b4/",
        "`f`FTff7b72span`f`FTb4b4b4>`f\n`FTb4b4b4<`f`FTb4b4b4/`f`FTff7b72div`f`FTb4b4",
        "b4>`f\n",
      ].joined()),
    Stream(
      language: "json",
      tokens: [
        ("Token.Punctuation", "{"),
        ("Token.Name.Tag", "\"a\""),
        ("Token.Punctuation", ":"),
        ("Token.Text.Whitespace", " "),
        ("Token.Punctuation", "["),
        ("Token.Literal.Number.Integer", "1"),
        ("Token.Punctuation", ","),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.Number.Float", "2.5"),
        ("Token.Punctuation", ","),
        ("Token.Text.Whitespace", " "),
        ("Token.Keyword.Constant", "null"),
        ("Token.Punctuation", ","),
        ("Token.Text.Whitespace", " "),
        ("Token.Keyword.Constant", "true"),
        ("Token.Punctuation", "],"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Tag", "\"b\""),
        ("Token.Punctuation", ":"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String.Double", "\"str\""),
        ("Token.Punctuation", "}"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTb4b4b4{`f`FTff7b72\"a\"`f`FTb4b4b4:`f `FTb4b4b4[`f`FT79c0ff1`f`FTb4b4b4,`",
        "f `FT79c0ff2.5`f`FTb4b4b4,`f `FTff7b72null`f`FTb4b4b4,`f `FTff7b72true`f`FTb",
        "4b4b4],`f `FTff7b72\"b\"`f`FTb4b4b4:`f `FTa5d6ff\"str\"`f`FTb4b4b4}`f\n",
      ].joined()),
    Stream(
      language: "c",
      tokens: [
        ("Token.Comment.Preproc", "#"),
        ("Token.Comment.Preproc", "include"),
        ("Token.Text.Whitespace", " "),
        ("Token.Comment.PreprocFile", "<stdio.h>"),
        ("Token.Comment.Preproc", "\n"),
        ("Token.Keyword.Type", "int"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Function", "main"),
        ("Token.Punctuation", "("),
        ("Token.Keyword.Type", "void"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", " "),
        ("Token.Punctuation", "{"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text.Whitespace", "    "),
        ("Token.Name", "printf"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String", "\""),
        ("Token.Literal.String", "hi"),
        ("Token.Literal.String.Escape", "\\n"),
        ("Token.Literal.String", "\""),
        ("Token.Punctuation", ")"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text.Whitespace", "    "),
        ("Token.Keyword", "return"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.Number.Integer", "0"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Punctuation", "}"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTff7b72#`f`FTff7b72include`f `FT8b949e<stdio.h>`f\n`FTffa657int`f `FTd2a8f",
        "fmain`f`FTb4b4b4(`f`FTffa657void`f`FTb4b4b4)`f `FTb4b4b4{`f\n    `FTe6edf3pr",
        "intf`f`FTb4b4b4(`f`FTa5d6ff\"`f`FTa5d6ffhi`f`FTffea00\\\\n`f`FTa5d6ff\"`f`FT",
        "b4b4b4)`f`FTb4b4b4;`f\n    `FTff7b72return`f `FT79c0ff0`f`FTb4b4b4;`f\n`FTb4",
        "b4b4}`f\n",
      ].joined()),
    Stream(
      language: "text",
      tokens: [
        ("Token.Text", "plain text\nno tokens here\n")
      ],
      expected: "plain text\nno tokens here\n"),
    Stream(
      language: "python",
      tokens: [
        ("Token.Name", "a"),
        ("Token.Operator", "."),
        ("Token.Name", "b"),
        ("Token.Operator", "."),
        ("Token.Name", "c"),
        ("Token.Punctuation", "("),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name", "d"),
        ("Token.Text", " "),
        ("Token.Operator", "."),
        ("Token.Text", " "),
        ("Token.Name", "e"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name", "obj"),
        ("Token.Operator", "."),
        ("Token.Name", "attr"),
        ("Token.Operator", "."),
        ("Token.Name", "method"),
        ("Token.Punctuation", "("),
        ("Token.Literal.Number.Integer", "1"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTe6edf3a`f`FTff7b72.`f`FTd2a8ffb`f`FTff7b72.`f`FTd2a8ffc`f`FTb4b4b4(`f`FTb",
        "4b4b4)`f\n`FTe6edf3d`f `FTff7b72.`f `FTe6edf3e`f\n`FTe6edf3obj`f`FTff7b72.`f",
        "`FTd2a8ffattr`f`FTff7b72.`f`FTd2a8ffmethod`f`FTb4b4b4(`f`FT79c0ff1`f`FTb4b4b",
        "4)`f\n",
      ].joined()),
    Stream(
      language: "python",
      tokens: [
        ("Token.Name", "s"),
        ("Token.Text", " "),
        ("Token.Operator", "="),
        ("Token.Text", " "),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "back`tick"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Text", " "),
        ("Token.Operator", "+"),
        ("Token.Text", " "),
        ("Token.Literal.String.Double", "\""),
        ("Token.Literal.String.Double", "back"),
        ("Token.Literal.String.Escape", "\\\\"),
        ("Token.Literal.String.Double", "slash"),
        ("Token.Literal.String.Double", "\""),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTe6edf3s`f `FTff7b72=`f `FTa5d6ff'`f`FTa5d6ffback\\`tick`f`FTa5d6ff'`f `FT",
        "ff7b72+`f `FTa5d6ff\"`f`FTa5d6ffback`f`FTffea00\\\\\\\\`f`FTa5d6ffslash`f`FT",
        "a5d6ff\"`f\n",
      ].joined()),
    Stream(
      language: "yaml",
      tokens: [
        ("Token.Name.Tag", "key"),
        ("Token.Punctuation", ":"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.Scalar.Plain", "value"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name.Tag", "list"),
        ("Token.Punctuation", ":"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text.Whitespace", "  "),
        ("Token.Punctuation.Indicator", "-"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.Scalar.Plain", "one"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text.Whitespace", "  "),
        ("Token.Punctuation.Indicator", "-"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.Scalar.Plain", "two"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTff7b72key`f`FTb4b4b4:`f `FTa5d6ffvalue`f\n`FTff7b72list`f`FTb4b4b4:`f\n  ",
        "`FTb4b4b4-`f `FTa5d6ffone`f\n  `FTb4b4b4-`f `FTa5d6fftwo`f\n",
      ].joined()),
    Stream(
      language: "sql",
      tokens: [
        ("Token.Keyword", "SELECT"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name", "a"),
        ("Token.Punctuation", ","),
        ("Token.Text.Whitespace", " "),
        ("Token.Name", "b"),
        ("Token.Text.Whitespace", " "),
        ("Token.Keyword", "FROM"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name", "t"),
        ("Token.Text.Whitespace", " "),
        ("Token.Keyword", "WHERE"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name", "x"),
        ("Token.Text.Whitespace", " "),
        ("Token.Operator", "="),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.Number.Integer", "1"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTff7b72SELECT`f `FTe6edf3a`f`FTb4b4b4,`f `FTe6edf3b`f `FTff7b72FROM`f `FTe",
        "6edf3t`f `FTff7b72WHERE`f `FTe6edf3x`f `FTff7b72=`f `FT79c0ff1`f`FTb4b4b4;`f",
        "\n",
      ].joined()),
    Stream(
      language: "javascript",
      tokens: [
        ("Token.Keyword.Declaration", "const"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Other", "f"),
        ("Token.Text.Whitespace", " "),
        ("Token.Operator", "="),
        ("Token.Text.Whitespace", " "),
        ("Token.Punctuation", "("),
        ("Token.Name.Other", "a"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", " "),
        ("Token.Punctuation", "=>"),
        ("Token.Text.Whitespace", " "),
        ("Token.Punctuation", "{"),
        ("Token.Text.Whitespace", " "),
        ("Token.Keyword", "return"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Other", "a"),
        ("Token.Operator", "?"),
        ("Token.Punctuation", "."),
        ("Token.Name.Other", "b"),
        ("Token.Text.Whitespace", " "),
        ("Token.Operator", "??"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.Number.Float", "1"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", " "),
        ("Token.Punctuation", "}"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTff7b72const`f `FTe6edf3f`f `FTff7b72=`f `FTb4b4b4(`f`FTe6edf3a`f`FTb4b4b4",
        ")`f `FTb4b4b4=>`f `FTb4b4b4{`f `FTff7b72return`f `FTe6edf3a`f`FTff7b72?`f`FT",
        "b4b4b4.`f`FTe6edf3b`f `FTff7b72??`f `FT79c0ff1`f`FTb4b4b4;`f `FTb4b4b4}`f`FT",
        "b4b4b4;`f\n",
      ].joined()),
    Stream(
      language: "ini",
      tokens: [
        ("Token.Keyword", "[section]"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name.Attribute", "key"),
        ("Token.Text.Whitespace", " "),
        ("Token.Operator", "="),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String", "value"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Comment.Single", "; comment"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTff7b72[section]`f\n`FTe6edf3key`f `FTff7b72=`f `FTa5d6ffvalue`f\n`FT8b949",
        "e; comment`f\n",
      ].joined()),
    Stream(
      language: "rst",
      tokens: [
        ("Token.Generic.Heading", "Title"),
        ("Token.Text", "\n"),
        ("Token.Generic.Heading", "====="),
        ("Token.Text", "\n"),
        ("Token.Text", "\n"),
        ("Token.Literal.Number", "-"),
        ("Token.Text", " bullet"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: "`FTc9d1d9Title`f\n`FTc9d1d9=====`f\n\n`FT79c0ff-`f bullet\n"),
    Stream(
      language: "python",
      tokens: [
        ("Token.Operator", "-"),
        ("Token.Name", "leading"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Operator", ">"),
        ("Token.Name", "angle"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Operator", "<"),
        ("Token.Name", "less"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTff7b72-`f`FTe6edf3leading`f\n`FTff7b72>`f`FTe6edf3angle`f\n`FTff7b72<`f`F",
        "Te6edf3less`f\n",
      ].joined()),
    Stream(
      language: "text",
      tokens: [
        ("Token.Text", "-dash start\n>gt start\n<lt start\nnormal\n")
      ],
      expected: "\\-dash start\n\\>gt start\n\\<lt start\nnormal\n"),
    Stream(
      language: "python",
      tokens: [
        ("Token.Name", "obj"),
        ("Token.Operator", "."),
        ("Token.Name.Function.Magic", "__init__"),
        ("Token.Punctuation", "("),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name.Builtin.Pseudo", "self"),
        ("Token.Operator", "."),
        ("Token.Name.Variable.Magic", "__dict__"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name", "a"),
        ("Token.Operator", "."),
        ("Token.Name.Variable.Magic", "__name__"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: [
        "`FTe6edf3obj`f`FTff7b72.`f`FTd2a8ff__init__`f`FTb4b4b4(`f`FTb4b4b4)`f\n`FTff",
        "7b72self`f`FTff7b72.`f`FTd2a8ff__dict__`f\n`FTe6edf3a`f`FTff7b72.`f`FTd2a8ff",
        "__name__`f\n",
      ].joined()),
    Stream(
      language: "bash",
      tokens: [
        ("Token.Text", "-x"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text", "ls"),
        ("Token.Text.Whitespace", " "),
        ("Token.Text", "-l"),
        ("Token.Text.Whitespace", " "),
        ("Token.Text", "-a"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: "\\-x\nls -l -a\n"),
    Stream(
      language: "diff",
      tokens: [
        ("Token.Generic.Strong", "! changed"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text", "<lt line"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Generic.Deleted", "-gone"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Generic.Inserted", "+added"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Text", "plain"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: "! changed\n\\<lt line\n`FTf85149-gone`f\n`FT7ee787+added`f\nplain\n"),
    Stream(
      language: "markdown",
      tokens: [
        ("Token.Keyword", "-"),
        ("Token.Text.Whitespace", " "),
        ("Token.Text", "item"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Keyword", "> "),
        ("Token.Generic.Emph", "quote\n"),
        ("Token.Text", "<tag>"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: "`FTff7b72-`f item\n`FTff7b72> `fquote\n\\<tag>\n"),
    Stream(
      language: "perl",
      tokens: [
        ("Token.Keyword", "print"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String.Other", "qq{"),
        ("Token.Literal.String.Other", "\nmulti\n"),
        ("Token.Literal.String.Other", "}"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: "`FTff7b72print`f `FTa5d6ffqq{`f\n`FTa5d6ffmulti`f\n`FTa5d6ff}`f`FTb4b4b4;`f\n"),
    Stream(
      language: "perl",
      tokens: [
        ("Token.Keyword", "print"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String.Other", "qq{"),
        ("Token.Literal.String.Other", "\n\n"),
        ("Token.Literal.String.Other", "}"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", "\n"),
      ],
      expected: "`FTff7b72print`f `FTa5d6ffqq{`f\n\n`FTa5d6ff}`f`FTb4b4b4;`f\n"),
    Stream(
      language: "text",
      tokens: [
        ("Token.Text", "-dash\n")
      ],
      expected: "-dash\n"),
    Stream(
      language: "text",
      tokens: [
        ("Token.Text", ">gt\n")
      ],
      expected: ">gt\n"),
    Stream(
      language: "text",
      tokens: [
        ("Token.Text", "<lt\n")
      ],
      expected: "<lt\n"),
    Stream(
      language: "text",
      tokens: [
        ("Token.Text", "x\n\u{B}-vt\n\u{C}>ff\n\u{1C}<fs\n\u{2028}-ls\n\u{85}>nel\n")
      ],
      expected: "x\n\n\\-vt\n\n\\>ff\n\n\\<fs\n\n\\-ls\n\n\\>nel\n"),
    Stream(
      language: "carriage return pair",
      tokens: [
        ("Token.Text", "a\r\n-b\n")
      ],
      expected: "a\n\\-b\n"),
    Stream(
      language: "carriage return alone",
      tokens: [
        ("Token.Text", "a\r-b\n")
      ],
      expected: "a\n\\-b\n"),
    Stream(
      language: "trailing carriage return",
      tokens: [
        ("Token.Text", "-a\n-b\r")
      ],
      expected: "\\-a\n\\-b"),
  ]

  /// Each content with the block the reference wrote for it, with no lexer available.
  private static let fallbacks: [(content: String, bare: String, named: String, typed: String)] = [
    (
      content: "",
      bare: "`=\n\n`=",
      named: "`=\n\n`=",
      typed: "`=\n\n`="
    ),
    (
      content: "a",
      bare: "`=\na\n`=",
      named: "`=\na\n`=",
      typed: "`=\na\n`="
    ),
    (
      content: "print('hi')\n",
      bare: "`=\nprint('hi')\n\n`=",
      named: "`=\nprint('hi')\n\n`=",
      typed: "`=\nprint('hi')\n\n`="
    ),
    (
      content: "back`tick",
      bare: "`=\nback\\\\`tick\n`=",
      named: "`=\nback\\\\`tick\n`=",
      typed: "`=\nback\\\\`tick\n`="
    ),
    (
      content: "back\\slash",
      bare: "`=\nback\\\\slash\n`=",
      named: "`=\nback\\\\slash\n`=",
      typed: "`=\nback\\\\slash\n`="
    ),
    (
      content: "`!both\\`!",
      bare: "`=\n\\\\`!both\\\\\\\\`!\n`=",
      named: "`=\n\\\\`!both\\\\\\\\`!\n`=",
      typed: "`=\n\\\\`!both\\\\\\\\`!\n`="
    ),
    (
      content: "line one\nline two\n",
      bare: "`=\nline one\nline two\n\n`=",
      named: "`=\nline one\nline two\n\n`=",
      typed: "`=\nline one\nline two\n\n`="
    ),
    (
      content: "\n",
      bare: "`=\n\n\n`=",
      named: "`=\n\n\n`=",
      typed: "`=\n\n\n`="
    ),
    (
      content: "tab\there",
      bare: "`=\ntab\there\n`=",
      named: "`=\ntab\there\n`=",
      typed: "`=\ntab\there\n`="
    ),
  ]

  private static let lookups: [Lookup] = [
    Lookup(
      content: "print('hello world')\nx = 1\n",
      filename: nil,
      language: "python",
      byName: [
        ("Token.Name.Builtin", "print"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "hello world"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name", "x"),
        ("Token.Text", " "),
        ("Token.Operator", "="),
        ("Token.Text", " "),
        ("Token.Literal.Number.Integer", "1"),
        ("Token.Text.Whitespace", "\n"),
      ],
      byFilename: nil,
      guessed: [
        ("Token.Text", "print('hello world')\nx = 1\n")
      ],
      namesAsked: ["python"],
      filenamesAsked: [],
      guesses: 0,
      expected: [
        "`FTffa657print`f`FTb4b4b4(`f`FTa5d6ff'`f`FTa5d6ffhello world`f`FTa5d6ff'`f`F",
        "Tb4b4b4)`f\n`FTe6edf3x`f `FTff7b72=`f `FT79c0ff1`f\n",
      ].joined()),
    Lookup(
      content: "export A=1\necho \"$A\"\n",
      filename: nil,
      language: "env",
      byName: [
        ("Token.Name.Builtin", "export"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Variable", "A"),
        ("Token.Operator", "="),
        ("Token.Literal.Number", "1"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name.Builtin", "echo"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String.Double", "\""),
        ("Token.Name.Variable", "$A"),
        ("Token.Literal.String.Double", "\""),
        ("Token.Text.Whitespace", "\n"),
      ],
      byFilename: nil,
      guessed: [
        ("Token.Keyword", "export"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name", "A"),
        ("Token.Operator", "="),
        ("Token.Literal.Number.Integer", "1"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name", "echo"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String.Double", "\""),
        ("Token.Literal.String.Double", "$A"),
        ("Token.Literal.String.Double", "\""),
        ("Token.Text.Whitespace", "\n"),
      ],
      namesAsked: ["bash"],
      filenamesAsked: [],
      guesses: 0,
      expected: [
        "`FTffa657export`f `FTe6edf3A`f`FTff7b72=`f`FT79c0ff1`f\n`FTffa657echo`f `FTa",
        "5d6ff\"`f`FTe6edf3$A`f`FTa5d6ff\"`f\n",
      ].joined()),
    Lookup(
      content: "export A=1\necho \"$A\"\n",
      filename: nil,
      language: "environment",
      byName: [
        ("Token.Name.Builtin", "export"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Variable", "A"),
        ("Token.Operator", "="),
        ("Token.Literal.Number", "1"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name.Builtin", "echo"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String.Double", "\""),
        ("Token.Name.Variable", "$A"),
        ("Token.Literal.String.Double", "\""),
        ("Token.Text.Whitespace", "\n"),
      ],
      byFilename: nil,
      guessed: [
        ("Token.Keyword", "export"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name", "A"),
        ("Token.Operator", "="),
        ("Token.Literal.Number.Integer", "1"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name", "echo"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.String.Double", "\""),
        ("Token.Literal.String.Double", "$A"),
        ("Token.Literal.String.Double", "\""),
        ("Token.Text.Whitespace", "\n"),
      ],
      namesAsked: ["bash"],
      filenamesAsked: [],
      guesses: 0,
      expected: [
        "`FTffa657export`f `FTe6edf3A`f`FTff7b72=`f`FT79c0ff1`f\n`FTffa657echo`f `FTa",
        "5d6ff\"`f`FTe6edf3$A`f`FTa5d6ff\"`f\n",
      ].joined()),
    Lookup(
      content: "print('hello world')\nx = 1\n",
      filename: "script.py",
      language: "nosuchlanguage",
      byName: nil,
      byFilename: [
        ("Token.Name.Builtin", "print"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "hello world"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name", "x"),
        ("Token.Text", " "),
        ("Token.Operator", "="),
        ("Token.Text", " "),
        ("Token.Literal.Number.Integer", "1"),
        ("Token.Text.Whitespace", "\n"),
      ],
      guessed: [
        ("Token.Text", "print('hello world')\nx = 1\n")
      ],
      namesAsked: ["nosuchlanguage"],
      filenamesAsked: ["script.py"],
      guesses: 0,
      expected: [
        "`FTffa657print`f`FTb4b4b4(`f`FTa5d6ff'`f`FTa5d6ffhello world`f`FTa5d6ff'`f`F",
        "Tb4b4b4)`f\n`FTe6edf3x`f `FTff7b72=`f `FT79c0ff1`f\n",
      ].joined()),
    Lookup(
      content: "def m; 1; end\nputs m\n",
      filename: "script.rb",
      language: nil,
      byName: nil,
      byFilename: [
        ("Token.Keyword", "def"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Function", "m"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.Number.Integer", "1"),
        ("Token.Punctuation", ";"),
        ("Token.Text.Whitespace", " "),
        ("Token.Keyword", "end"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name.Builtin", "puts"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name", "m"),
        ("Token.Text.Whitespace", "\n"),
      ],
      guessed: [
        ("Token.Name.Variable", "def"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Variable", "m"),
        ("Token.Comment.Single", "; 1; end"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name.Variable", "puts"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Variable", "m"),
        ("Token.Text.Whitespace", "\n"),
      ],
      namesAsked: [],
      filenamesAsked: ["script.rb"],
      guesses: 0,
      expected: [
        "`FTff7b72def`f `FTd2a8ffm`f`FTb4b4b4;`f `FT79c0ff1`f`FTb4b4b4;`f `FTff7b72en",
        "d`f\n`FTffa657puts`f `FTe6edf3m`f\n",
      ].joined()),
    Lookup(
      content: "#include <stdio.h>\nint main(void){return 0;}\n",
      filename: nil,
      language: nil,
      byName: nil,
      byFilename: nil,
      guessed: [
        ("Token.Comment.Preproc", "#"),
        ("Token.Comment.Preproc", "include"),
        ("Token.Text.Whitespace", " "),
        ("Token.Comment.PreprocFile", "<stdio.h>"),
        ("Token.Comment.Preproc", "\n"),
        ("Token.Keyword.Type", "int"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name.Function", "main"),
        ("Token.Punctuation", "("),
        ("Token.Keyword.Type", "void"),
        ("Token.Punctuation", ")"),
        ("Token.Punctuation", "{"),
        ("Token.Keyword", "return"),
        ("Token.Text.Whitespace", " "),
        ("Token.Literal.Number.Integer", "0"),
        ("Token.Punctuation", ";"),
        ("Token.Punctuation", "}"),
        ("Token.Text.Whitespace", "\n"),
      ],
      namesAsked: [],
      filenamesAsked: [],
      guesses: 1,
      expected: [
        "`FTff7b72#`f`FTff7b72include`f `FT8b949e<stdio.h>`f\n`FTffa657int`f `FTd2a8f",
        "fmain`f`FTb4b4b4(`f`FTffa657void`f`FTb4b4b4)`f`FTb4b4b4{`f`FTff7b72return`f ",
        "`FT79c0ff0`f`FTb4b4b4;`f`FTb4b4b4}`f\n",
      ].joined()),
    Lookup(
      content: "x = 1\n",
      filename: nil,
      language: nil,
      byName: nil,
      byFilename: nil,
      guessed: nil,
      namesAsked: [],
      filenamesAsked: [],
      guesses: 0,
      expected: "`=\nx = 1\n\n`="),
    Lookup(
      content: "x = 1\n",
      filename: "note.unknownext",
      language: "nosuchlanguage",
      byName: nil,
      byFilename: nil,
      guessed: nil,
      namesAsked: ["nosuchlanguage"],
      filenamesAsked: ["note.unknownext"],
      guesses: 0,
      expected: "`=\nx = 1\n\n`="),
    Lookup(
      content: "print('no trailing newline')",
      filename: nil,
      language: "python",
      byName: [
        ("Token.Name.Builtin", "print"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "no trailing newline"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
      ],
      byFilename: nil,
      guessed: [
        ("Token.Text", "print('no trailing newline')\n")
      ],
      namesAsked: ["python"],
      filenamesAsked: [],
      guesses: 0,
      expected: [
        "`FTffa657print`f`FTb4b4b4(`f`FTa5d6ff'`f`FTa5d6ffno trailing newline`f`FTa5d",
        "6ff'`f`FTb4b4b4)`f",
      ].joined()),
    Lookup(
      content: "print('trailing newline')\n",
      filename: nil,
      language: "python",
      byName: [
        ("Token.Name.Builtin", "print"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "trailing newline"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
      ],
      byFilename: nil,
      guessed: [
        ("Token.Text", "print('trailing newline')\n")
      ],
      namesAsked: ["python"],
      filenamesAsked: [],
      guesses: 0,
      expected: [
        "`FTffa657print`f`FTb4b4b4(`f`FTa5d6ff'`f`FTa5d6fftrailing newline`f`FTa5d6ff",
        "'`f`FTb4b4b4)`f\n",
      ].joined()),
    Lookup(
      content: "",
      filename: nil,
      language: "python",
      byName: [
        ("Token.Text.Whitespace", "\n")
      ],
      byFilename: nil,
      guessed: nil,
      namesAsked: [],
      filenamesAsked: [],
      guesses: 0,
      expected: "`=\n\n`="),
    Lookup(
      content: "a",
      filename: nil,
      language: nil,
      byName: nil,
      byFilename: nil,
      guessed: nil,
      namesAsked: [],
      filenamesAsked: [],
      guesses: 0,
      expected: "`=\na\n`="),
    Lookup(
      content: "print('x')\nimport os\n",
      filename: "script.rb",
      language: "python",
      byName: [
        ("Token.Name.Builtin", "print"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "x"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Keyword.Namespace", "import"),
        ("Token.Text", " "),
        ("Token.Name.Namespace", "os"),
        ("Token.Text.Whitespace", "\n"),
      ],
      byFilename: [
        ("Token.Name.Builtin", "print"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "x"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Name", "import"),
        ("Token.Text.Whitespace", " "),
        ("Token.Name", "os"),
        ("Token.Text.Whitespace", "\n"),
      ],
      guessed: [
        ("Token.Name.Builtin", "print"),
        ("Token.Punctuation", "("),
        ("Token.Literal.String.Single", "'"),
        ("Token.Literal.String.Single", "x"),
        ("Token.Literal.String.Single", "'"),
        ("Token.Punctuation", ")"),
        ("Token.Text.Whitespace", "\n"),
        ("Token.Keyword.Namespace", "import"),
        ("Token.Text", " "),
        ("Token.Name.Namespace", "os"),
        ("Token.Text.Whitespace", "\n"),
      ],
      namesAsked: ["python"],
      filenamesAsked: [],
      guesses: 0,
      expected: [
        "`FTffa657print`f`FTb4b4b4(`f`FTa5d6ff'`f`FTa5d6ffx`f`FTa5d6ff'`f`FTb4b4b4)`f",
        "\n`FTff7b72import`f `FT7ee787os`f\n",
      ].joined()),
    Lookup(
      content: "x = 1 + 2 + 3 + 4 + 5\n",
      filename: nil,
      language: "",
      byName: nil,
      byFilename: nil,
      guessed: [
        ("Token.Text", "x = 1 + 2 + 3 + 4 + 5\n")
      ],
      namesAsked: [],
      filenamesAsked: [],
      guesses: 1,
      expected: "x = 1 + 2 + 3 + 4 + 5\n"),
  ]

  private static let raising: [(content: String, expected: String)] = [
    (
      content: "print('hi')\n",
      expected: "`=\nprint('hi')\n\n`="
    ),
    (
      content: "back\\slash",
      expected: "`=\nback\\\\slash\n`="
    ),
  ]

  private static let markdown: [(input: String, expected: String)] = [
    (
      input: "```python\nprint('hi')\n```",
      expected: "`BT282828`Fddd\n`=\nprint('hi')\n`=\n`f`b"
    ),
    (
      input: "```RawMu\n`!bold`!\n```",
      expected: "`!bold`!"
    ),
    (
      input: "```rawmu\n`Fddd x\n```",
      expected: "`Fddd x"
    ),
    (
      input: "```RAWMU\nraw\n```",
      expected: "raw"
    ),
    (
      input: "```rawmuX\nnot raw\n```",
      expected: "`BT282828`Fddd\n`=\nnot raw\n`=\n`f`b"
    ),
    (
      input: "```\nno language\n```",
      expected: "`BT282828`Fddd\n`=\nno language\n`=\n`f`b"
    ),
    (
      input: "```   \nblank language\n```",
      expected: "`BT282828`Fddd\n`=\nblank language\n`=\n`f`b"
    ),
    (
      input: "```text\nback\\slash and `tick`\n```",
      expected: "`BT282828`Fddd\n`=\nback\\\\slash and \\\\`tick\\\\`\n`=\n`f`b"
    ),
    (
      input: "text before\n\n```sh\necho hi\n```\n\ntext after",
      expected: "text before\n\n`BT282828`Fddd\n`=\necho hi\n`=\n`f`b\n\ntext after"
    ),
    (
      input: "```python\n```",
      expected: ""
    ),
  ]

  /// Every color the reference's default theme carries is the color this port carries.
  func testDefaultThemeMatchesTheReference() {
    XCTAssertEqual(SyntaxHighlighter.defaultTheme.count, Self.themeVectors.count)
    for vector in Self.themeVectors {
      guard let color = SyntaxHighlighter.defaultTheme[vector.key] else {
        XCTFail("theme is missing \(vector.key)")
        continue
      }
      XCTAssertEqual(color, vector.color, vector.key)
    }
  }

  /// Every token type the reference maps is mapped to the same theme key here.
  func testTokenMapMatchesTheReference() {
    XCTAssertEqual(MicronFormatter.granularTokenMap.count, Self.tokenMapVectors.count)
    for vector in Self.tokenMapVectors {
      XCTAssertEqual(MicronFormatter.granularTokenMap[vector.type], vector.key, vector.type)
    }
  }

  /// Walking a token type up to a mapped parent picks the key the reference picked.
  func testColorKeyResolutionMatchesTheReference() {
    for vector in Self.colorKeyVectors {
      XCTAssertEqual(MicronFormatter.colorKey(for: vector.type), vector.key, vector.type)
    }
  }

  /// Each recorded token stream renders to the Micron the reference's formatter wrote.
  func testFormattedStreamsMatchTheReference() {
    let formatter = MicronFormatter(theme: SyntaxHighlighter.defaultTheme)
    for stream in Self.streams {
      let tokens = stream.tokens.map { MicronToken(type: $0.type, value: $0.value) }
      XCTAssertEqual(formatter.format(tokens), stream.expected, stream.language)
    }
  }

  /// With no lexer, every call shape gives the escaped literal block the reference gives.
  func testPlainFallbackMatchesTheReference() {
    let highlighter = SyntaxHighlighter()
    for vector in Self.fallbacks {
      let label = vector.content.debugDescription
      XCTAssertEqual(
        highlighter.highlight(vector.content, filename: nil, language: nil), vector.bare, label)
      XCTAssertEqual(
        highlighter.highlight(vector.content, filename: "x.py", language: nil), vector.named,
        label)
      XCTAssertEqual(
        highlighter.highlight(vector.content, language: "python"), vector.typed, label)
    }
  }

  /// The lookups are tried in the reference's order, and produce the reference's Micron.
  func testLexerLookupOrderMatchesTheReference() {
    for lookup in Self.lookups {
      let lexer = RecordedLexer(lookup)
      let highlighter = SyntaxHighlighter(lexer: lexer)
      let label = lookup.content.debugDescription

      XCTAssertEqual(
        highlighter.highlight(lookup.content, filename: lookup.filename, language: lookup.language),
        lookup.expected, label)
      XCTAssertEqual(lexer.namesAsked, lookup.namesAsked, label)
      XCTAssertEqual(lexer.filenamesAsked, lookup.filenamesAsked, label)
      XCTAssertEqual(lexer.guesses, lookup.guesses, label)
    }
  }

  /// A lexer that fails takes the same escaped literal block the reference falls back to.
  func testFailingLexerMatchesTheReference() {
    let highlighter = SyntaxHighlighter(lexer: FailingLexer())
    for vector in Self.raising {
      XCTAssertEqual(
        highlighter.highlight(vector.content, language: "python"), vector.expected,
        vector.content.debugDescription)
    }
  }

  /// A converter holding a highlighter renders fenced blocks as the reference renders them.
  func testMarkdownWithHighlighterMatchesTheReference() {
    for vector in Self.markdown {
      let converter = MarkdownToMicron(syntaxHighlighter: SyntaxHighlighter())
      XCTAssertEqual(
        converter.formatBlock(vector.input), vector.expected, vector.input.debugDescription)
    }
  }
}
