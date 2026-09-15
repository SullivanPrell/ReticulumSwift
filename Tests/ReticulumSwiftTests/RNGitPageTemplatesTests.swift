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

/// The templates a page is rendered into, as Python RNS 1.5.4 fills them.
final class RNGitPageTemplatesTests: XCTestCase {

  /// A templates directory holding a static, a dynamic, an unrunnable and a directory entry.
  private func scratch() throws -> String {
    let directory = NSTemporaryDirectory() + "/rngit-templates-" + UUID().uuidString
    try FileManager.default.createDirectory(
      atPath: directory, withIntermediateDirectories: true)
    try "A static template\n  {PAGE_CONTENT}  \n\n".write(
      toFile: directory + "/static.mu", atomically: true, encoding: .utf8)
    try "#!/bin/sh\nprintf 'made at run time\\n{PAGE_CONTENT}\\n\\n'\n".write(
      toFile: directory + "/dynamic.mu", atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: directory + "/dynamic.mu")
    try "#!/nonexistent/interpreter\n".write(
      toFile: directory + "/broken.mu", atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: directory + "/broken.mu")
    try FileManager.default.createDirectory(
      atPath: directory + "/adirectory.mu", withIntermediateDirectories: true)
    return directory
  }

  /// Templates read out of a scratch directory, named as the reference named its node.
  private func templates() throws -> (RNGitPageTemplates, String) {
    let directory = try scratch()
    return (
      RNGitPageTemplates(
        directory: directory, nodeName: "A Node", version: "1.5.4"),
      directory
    )
  }

  /// Every shipped template is the one the reference ships.
  func testEveryShippedTemplateMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageTemplate.base.shipped,
      "#!c=0\n> {NODE_NAME}\n\n{NAVIGATION}\n{PAGE_CONTENT}\n<\n-\n`a`F666`[Served by rngit {VERSION}`:/page/index.mu] - {GEN_TIME}`f"
    )
    XCTAssertEqual(RNGitPageTemplate.front.shipped, "> Groups\n\n{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.group.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.repo.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.releases.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.release.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.tree.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.blob.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.commits.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.commit.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.refs.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.stats.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.work.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(RNGitPageTemplate.workDocument.shipped, "{PAGE_CONTENT}")
    XCTAssertEqual(
      RNGitPageTemplate.noIdentity.shipped,
      ">>No Identity\n\nThis page requires identification, and none was received.\n")
  }

  /// The `static` template reads as the reference read it.
  func testTemplateStaticReadsAsTheReferenceReadIt() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(templates.custom("static"), "A static template\n  {PAGE_CONTENT}")
  }

  /// The `dynamic` template reads as the reference read it.
  func testTemplateDynamicReadsAsTheReferenceReadIt() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(templates.custom("dynamic"), "made at run time\n{PAGE_CONTENT}")
  }

  /// The `broken` template reads as the reference read it.
  func testTemplateBrokenReadsAsTheReferenceReadIt() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(templates.custom("broken"), nil)
  }

  /// The `adirectory` template reads as the reference read it.
  func testTemplateAdirectoryReadsAsTheReferenceReadIt() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(templates.custom("adirectory"), nil)
  }

  /// The `absent` template reads as the reference read it.
  func testTemplateAbsentReadsAsTheReferenceReadIt() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(templates.custom("absent"), nil)
  }

  /// A `bare` page renders as the reference rendered it.
  func testRenderBareMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(
      String(data: templates.render("Body here\n"), encoding: .utf8),
      "#!c=0\n> A Node\n\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// A `navigated` page renders as the reference rendered it.
  func testRenderNavigatedMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(
      String(data: templates.render("Body here\n", navigation: "Nav here\n"), encoding: .utf8),
      "#!c=0\n> A Node\n\nNav here\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// A `tabbed` page renders as the reference rendered it.
  func testRenderTabbedMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(
      String(data: templates.render("Before\n\tafter a tab\n"), encoding: .utf8),
      "#!c=0\n> A Node\n\n\nBefore\n   after a tab\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// A `shippedTemplate` page renders as the reference rendered it.
  func testRenderShippedTemplateMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(
      String(data: templates.render("Body here\n", template: "front"), encoding: .utf8),
      "#!c=0\n> A Node\n\n\n> Groups\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// A `customTemplate` page renders as the reference rendered it.
  func testRenderCustomTemplateMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(
      String(data: templates.render("Body here\n", template: "static"), encoding: .utf8),
      "#!c=0\n> A Node\n\n\nA static template\n  Body here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// A `dynamicTemplate` page renders as the reference rendered it.
  func testRenderDynamicTemplateMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(
      String(data: templates.render("Body here\n", template: "dynamic"), encoding: .utf8),
      "#!c=0\n> A Node\n\n\nmade at run time\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// A `unknownTemplate` page renders as the reference rendered it.
  func testRenderUnknownTemplateMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(
      String(data: templates.render("Body here\n", template: "nosuchthing"), encoding: .utf8),
      "#!c=0\n> A Node\n\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// A `emptyBody` page renders as the reference rendered it.
  func testRenderEmptyBodyMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(
      String(data: templates.render(""), encoding: .utf8),
      "#!c=0\n> A Node\n\n\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// A page names how long it took to generate, as the reference named it.
  func testTheGenerationTimeMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let cases: [(TimeInterval, String)] = [
      (
        0.0,
        "#!c=0\n> A Node\n\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in 0s`f"
      ),
      (
        0.25,
        "#!c=0\n> A Node\n\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in 0.25s`f"
      ),
      (
        1.5,
        "#!c=0\n> A Node\n\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in 1.5s`f"
      ),
      (
        12.0,
        "#!c=0\n> A Node\n\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in 12.0s`f"
      ),
      (
        90.0,
        "#!c=0\n> A Node\n\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in 1m and 30.0s`f"
      ),
      (
        3725.0,
        "#!c=0\n> A Node\n\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in 1h, 2m and 5.0s`f"
      ),
    ]
    for (elapsed, expected) in cases {
      XCTAssertEqual(
        String(
          data: templates.render("Body here\n", startedAt: 1000 - elapsed, now: 1000),
          encoding: .utf8),
        expected, "after \(elapsed) seconds")
    }
  }

  /// The base template a node keeps of its own stands in for the shipped one.
  func testACustomBaseTemplateStandsInForTheShippedOne() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    try "{NODE_NAME} at {VERSION}: {PAGE_CONTENT}".write(
      toFile: directory + "/base.mu", atomically: true, encoding: .utf8)
    XCTAssertEqual(
      String(data: templates.render("body"), encoding: .utf8),
      "A Node at 1.5.4: body")
  }

  /// Every template is named as the reference names it.
  func testEveryTemplateIsNamedAsTheReferenceNamesIt() {
    XCTAssertEqual(
      RNGitPageTemplate.allCases.map(\.rawValue),
      [
        "base", "front", "group", "repo", "releases", "release", "tree", "blob", "commits",
        "commit", "refs", "stats", "work", "work_doc", "no_ident",
      ])
  }

  /// A page asked for under no name at all is rendered on its own.
  func testAPageAskedForUnderNoNameIsRenderedOnItsOwn() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    try "A nameless template: {PAGE_CONTENT}\n".write(
      toFile: directory + "/.mu", atomically: true, encoding: .utf8)
    XCTAssertEqual(
      String(data: templates.render("Body here\n", template: ""), encoding: .utf8),
      "#!c=0\n> A Node\n\n\nBody here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// The template that stands in for a page asked for without an identity is the shipped one.
  func testAPageRenderedWithoutAnIdentityMatchesTheReference() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    XCTAssertEqual(
      String(
        data: templates.render("Body here\n", template: RNGitPageTemplate.noIdentity.rawValue),
        encoding: .utf8),
      "#!c=0\n> A Node\n\n\n>>No Identity\n\nThis page requires identification, and none was received.\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }

  /// A work document's own template is looked for under the name the reference looks under.
  func testAWorkDocumentTemplateIsFoundUnderItsOwnName() throws {
    let (templates, directory) = try templates()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    try "A work document: {PAGE_CONTENT}\n".write(
      toFile: directory + "/work_doc.mu", atomically: true, encoding: .utf8)
    XCTAssertEqual(
      String(
        data: templates.render("Body here\n", template: RNGitPageTemplate.workDocument.rawValue),
        encoding: .utf8),
      "#!c=0\n> A Node\n\n\nA work document: Body here\n\n<\n-\n`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Unknown generation time`f"
    )
  }
}
