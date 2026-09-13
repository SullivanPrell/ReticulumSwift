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

final class RequestHandlerAutoCompressTests: XCTestCase {

  func testDefaultAutoCompressIsTrue() throws {
    let dest = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "test", aspects: ["compress"])
    dest.registerRequestHandler(path: "/test", allow: .all) { _, _, _, _, _ in Data() }
    let key = Hashes.truncatedHash(Data("/test".utf8))
    XCTAssertEqual(
      dest.requestHandlers[key]?.autoCompress, .enabled,
      "Default autoCompress should be enabled")
  }

  func testAutoCompressFalsePreserved() throws {
    let dest = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "test", aspects: ["compress"])
    dest.registerRequestHandler(path: "/test", allow: .all, autoCompress: false) { _, _, _, _, _ in
      Data()
    }
    let key = Hashes.truncatedHash(Data("/test".utf8))
    XCTAssertEqual(
      dest.requestHandlers[key]?.autoCompress, .disabled,
      "autoCompress = false should be preserved")
  }

  func testAutoCompressTrueExplicit() throws {
    let dest = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "test", aspects: ["compress"])
    dest.registerRequestHandler(path: "/test", allow: .all, autoCompress: true) { _, _, _, _, _ in
      Data()
    }
    let key = Hashes.truncatedHash(Data("/test".utf8))
    XCTAssertEqual(dest.requestHandlers[key]?.autoCompress, .enabled)
  }

  func testMultipleHandlersIndependentAutoCompress() throws {
    let dest = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "test", aspects: ["compress"])
    dest.registerRequestHandler(path: "/yes", allow: .all, autoCompress: true) { _, _, _, _, _ in
      Data()
    }
    dest.registerRequestHandler(path: "/no", allow: .all, autoCompress: false) { _, _, _, _, _ in
      Data()
    }

    let yesKey = Hashes.truncatedHash(Data("/yes".utf8))
    let noKey = Hashes.truncatedHash(Data("/no".utf8))

    XCTAssertEqual(dest.requestHandlers[yesKey]?.autoCompress, .enabled)
    XCTAssertEqual(dest.requestHandlers[noKey]?.autoCompress, .disabled)
  }

  func testAutoCompressStoredInEntry() throws {
    let dest = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "test", aspects: ["compress"])
    dest.registerRequestHandler(path: "/data", allow: .all, autoCompress: false) { _, _, _, _, _ in
      nil
    }
    let key = Hashes.truncatedHash(Data("/data".utf8))
    let entry = dest.requestHandlers[key]
    XCTAssertNotNil(entry)
    XCTAssertEqual(entry?.autoCompress, false)
    XCTAssertEqual(entry?.path, "/data")
  }
}
