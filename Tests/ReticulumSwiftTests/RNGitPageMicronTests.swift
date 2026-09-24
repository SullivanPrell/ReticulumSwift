//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest

@testable import ReticulumSwift

/// The micron a page is written in, as Python RNS 1.5.4 writes it.
final class RNGitPageMicronTests: XCTestCase {

  /// Every recorded piece of markup reads as the reference wrote it.
  func testEveryPieceOfMarkupMatchesTheReference() {
    XCTAssertEqual(RNGitPageMicron.heading("Repositories", level: 1), ">Repositories\n", "heading")
    XCTAssertEqual(RNGitPageMicron.heading("Group", level: 2), ">>Group\n", "heading")
    XCTAssertEqual(
      RNGitPageMicron.heading("A `tricky` one", level: 3), ">>>A `tricky` one\n", "heading")
    XCTAssertEqual(RNGitPageMicron.heading("", level: 1), ">\n", "heading")
    XCTAssertEqual(RNGitPageMicron.bold("bold"), "`!bold`!", "bold")
    XCTAssertEqual(RNGitPageMicron.italic("bold"), "`*bold`*", "italic")
    XCTAssertEqual(RNGitPageMicron.underline("bold"), "`_bold`_", "underline")
    XCTAssertEqual(RNGitPageMicron.bold("with `tick"), "`!with `tick`!", "bold")
    XCTAssertEqual(RNGitPageMicron.italic("with `tick"), "`*with `tick`*", "italic")
    XCTAssertEqual(RNGitPageMicron.underline("with `tick"), "`_with `tick`_", "underline")
    XCTAssertEqual(RNGitPageMicron.bold(""), "`!`!", "bold")
    XCTAssertEqual(RNGitPageMicron.italic(""), "`*`*", "italic")
    XCTAssertEqual(RNGitPageMicron.underline(""), "`_`_", "underline")
    XCTAssertEqual(RNGitPageMicron.colorForeground("dim", "666"), "`F666dim`f", "colorFg")
    XCTAssertEqual(RNGitPageMicron.colorForeground("", "0a0"), "`F0a0`f", "colorFg")
    XCTAssertEqual(RNGitPageMicron.colorForeground("x", "T537855"), "`FT537855x`f", "colorFg")
    XCTAssertEqual(RNGitPageMicron.divider("─"), "-─\n", "divider")
    XCTAssertEqual(RNGitPageMicron.divider("-"), "--\n", "divider")
    XCTAssertEqual(RNGitPageMicron.divider("·"), "-·\n", "divider")
    XCTAssertEqual(RNGitPageMicron.divider(), "-─\n", "dividerDefault")
    XCTAssertEqual(RNGitPageMicron.escape("plain"), "plain", "escape")
    XCTAssertEqual(RNGitPageMicron.escape("a `b` c"), "a \\`b\\` c", "escape")
    XCTAssertEqual(RNGitPageMicron.escape("``"), "\\`\\`", "escape")
    XCTAssertEqual(RNGitPageMicron.escape(""), "", "escape")
    XCTAssertEqual(RNGitPageMicron.align("mid", "center"), "`cmid`a", "align")
    XCTAssertEqual(RNGitPageMicron.align("l", "left"), "`ll`a", "align")
    XCTAssertEqual(RNGitPageMicron.align("r", "right"), "`rr`a", "align")
    XCTAssertEqual(RNGitPageMicron.align("x", "weird"), "`ax`a", "align")
    XCTAssertEqual(RNGitPageMicron.align("d"), "`ld`a", "alignDefault")
    XCTAssertEqual(
      RNGitPageMicron.requestLink("Home", "/page/index.mu", []), "`[Home`:/page/index.mu]", "linkR")
    XCTAssertEqual(
      RNGitPageMicron.link("Home", "/page/index.mu", []), "`!`[Home`:/page/index.mu]`!", "link")
    XCTAssertEqual(
      RNGitPageMicron.externalLink("Home", remote: "aabbcc", "/page/index.mu", []),
      "`!`[Home`aabbcc:/page/index.mu]`!", "linkE")
    XCTAssertEqual(
      RNGitPageMicron.requestLink("A [label] with `ticks", "/page/repo.mu", []),
      "`[A label with ticks`:/page/repo.mu]", "linkR")
    XCTAssertEqual(
      RNGitPageMicron.link("A [label] with `ticks", "/page/repo.mu", []),
      "`!`[A label with ticks`:/page/repo.mu]`!", "link")
    XCTAssertEqual(
      RNGitPageMicron.externalLink("A [label] with `ticks", remote: "aabbcc", "/page/repo.mu", []),
      "`!`[A label with ticks`aabbcc:/page/repo.mu]`!", "linkE")
    XCTAssertEqual(
      RNGitPageMicron.requestLink(
        "Tree", "/page/tree.mu", [("group", "public"), ("repo", "my repo"), ("ref", "main")]),
      "`[Tree`:/page/tree.mu`group=public|repo=my+repo|ref=main]", "linkR")
    XCTAssertEqual(
      RNGitPageMicron.link(
        "Tree", "/page/tree.mu", [("group", "public"), ("repo", "my repo"), ("ref", "main")]),
      "`!`[Tree`:/page/tree.mu`group=public|repo=my+repo|ref=main]`!", "link")
    XCTAssertEqual(
      RNGitPageMicron.externalLink(
        "Tree", remote: "aabbcc", "/page/tree.mu",
        [("group", "public"), ("repo", "my repo"), ("ref", "main")]),
      "`!`[Tree`aabbcc:/page/tree.mu`group=public|repo=my+repo|ref=main]`!", "linkE")
    XCTAssertEqual(
      RNGitPageMicron.requestLink(
        "Blob", "/page/blob.mu", [("path", "src/a b/c.swift"), ("n", "42")]),
      "`[Blob`:/page/blob.mu`path=src%2Fa+b%2Fc.swift|n=42]", "linkR")
    XCTAssertEqual(
      RNGitPageMicron.link("Blob", "/page/blob.mu", [("path", "src/a b/c.swift"), ("n", "42")]),
      "`!`[Blob`:/page/blob.mu`path=src%2Fa+b%2Fc.swift|n=42]`!", "link")
    XCTAssertEqual(
      RNGitPageMicron.externalLink(
        "Blob", remote: "aabbcc", "/page/blob.mu", [("path", "src/a b/c.swift"), ("n", "42")]),
      "`!`[Blob`aabbcc:/page/blob.mu`path=src%2Fa+b%2Fc.swift|n=42]`!", "linkE")
    XCTAssertEqual(
      RNGitPageMicron.requestLink(
        "Unicode", "/page/x.mu", [("q", "æøå/☃"), ("plus", "a+b"), ("tilde", "~x~")]),
      "`[Unicode`:/page/x.mu`q=%C3%A6%C3%B8%C3%A5%2F%E2%98%83|plus=a%2Bb|tilde=~x~]", "linkR")
    XCTAssertEqual(
      RNGitPageMicron.link(
        "Unicode", "/page/x.mu", [("q", "æøå/☃"), ("plus", "a+b"), ("tilde", "~x~")]),
      "`!`[Unicode`:/page/x.mu`q=%C3%A6%C3%B8%C3%A5%2F%E2%98%83|plus=a%2Bb|tilde=~x~]`!", "link")
    XCTAssertEqual(
      RNGitPageMicron.externalLink(
        "Unicode", remote: "aabbcc", "/page/x.mu",
        [("q", "æøå/☃"), ("plus", "a+b"), ("tilde", "~x~")]),
      "`!`[Unicode`aabbcc:/page/x.mu`q=%C3%A6%C3%B8%C3%A5%2F%E2%98%83|plus=a%2Bb|tilde=~x~]`!",
      "linkE")
    XCTAssertEqual(
      RNGitPageMicron.requestLink("Empty", "/page/e.mu", [("empty", "")]),
      "`[Empty`:/page/e.mu`empty=]", "linkR")
    XCTAssertEqual(
      RNGitPageMicron.link("Empty", "/page/e.mu", [("empty", "")]),
      "`!`[Empty`:/page/e.mu`empty=]`!", "link")
    XCTAssertEqual(
      RNGitPageMicron.externalLink("Empty", remote: "aabbcc", "/page/e.mu", [("empty", "")]),
      "`!`[Empty`aabbcc:/page/e.mu`empty=]`!", "linkE")
  }

  /// A field's value is carried in the order it was given, not the order a name sorts in.
  func testFieldsAreCarriedInTheOrderTheyWereGiven() {
    let forwards = RNGitPageMicron.requestLink(
      "L", "/page/x.mu", [("a", "1"), ("b", "2"), ("c", "3")])
    let backwards = RNGitPageMicron.requestLink(
      "L", "/page/x.mu", [("c", "3"), ("b", "2"), ("a", "1")])
    XCTAssertEqual(forwards, "`[L`:/page/x.mu`a=1|b=2|c=3]")
    XCTAssertEqual(backwards, "`[L`:/page/x.mu`c=3|b=2|a=1]")
  }

  /// Every byte outside the unreserved set is written as the bytes of its encoding.
  func testEveryByteOutsideTheUnreservedSetIsPercentEncoded() {
    let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~"
    XCTAssertEqual(RNGitPageMicron.quotePlus(unreserved), unreserved)
    XCTAssertEqual(RNGitPageMicron.quotePlus(" "), "+")
    XCTAssertEqual(RNGitPageMicron.quotePlus("/?&=#%"), "%2F%3F%26%3D%23%25")
    XCTAssertEqual(RNGitPageMicron.quotePlus("\u{00E6}"), "%C3%A6")
    XCTAssertEqual(RNGitPageMicron.quotePlus("\u{2603}"), "%E2%98%83")
  }

  /// A field reads back as `urllib.parse.unquote_plus` reads it in Python RNS 1.5.4: `+` as a
  /// space, each run of escapes decoded as UTF-8 with whatever does not decode replaced, and an
  /// escape that is not two hexadecimal digits left as it stands.
  func testAFieldReadsBackAsTheReferenceReadsIt() {
    let recorded: [(String, String)] = [
      ("", ""),
      ("plain", "plain"),
      ("a+b", "a b"),
      ("a%2Bb", "a+b"),
      ("a%20b%", "a b%"),
      ("100%", "100%"),
      ("%zz", "%zz"),
      ("%FF", "\u{FFFD}"),
      ("%ff%FE", "\u{FFFD}\u{FFFD}"),
      ("%C3%A9", "\u{E9}"),
      ("%c3%a9", "\u{E9}"),
      ("%E2%82", "\u{FFFD}"),
      ("caf%C3%A9+%E2", "caf\u{E9} \u{FFFD}"),
      ("%2", "%2"),
      ("+%2B+", " + "),
      ("a%2fb", "a/b"),
      ("%00x", "\u{0}x"),
      ("%41%4g", "A%4g"),
      ("%C3\u{E9}%A9", "\u{FFFD}\u{E9}\u{FFFD}"),
      ("\u{E9}+%C3%A9", "\u{E9} \u{E9}"),
      ("%ED%A0%80", "\u{FFFD}\u{FFFD}\u{FFFD}"),
      ("%C0%80", "\u{FFFD}\u{FFFD}"),
      ("%F4%90%80%80", "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}"),
      ("%F0%9F%98%80", "\u{1F600}"),
      ("%%41", "%A"),
      ("src%2Fmain.swift", "src/main.swift"),
      ("notes+v1.txt", "notes v1.txt"),
      ("%E2%82%AC%E2", "\u{20AC}\u{FFFD}"),
      ("+\u{301}%41", " \u{301}A"),
    ]
    for (field, read) in recorded {
      XCTAssertEqual(RNGitPageMicron.unquotePlus(field), read, field)
    }
  }
}
