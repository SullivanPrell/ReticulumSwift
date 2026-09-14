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

/// Metadata's share of a resource's size, in the advertisement and in the split.
///
/// Python counts the metadata block as part of the resource
/// (`total_size = data_size + metadata_size`, `Resource.py:297`), and gives segment 1
/// that much less room for data (`first_read_size = MAX_EFFICIENT_SIZE - metadata_size`,
/// `Resource.py:311`). This port counted neither, so a resource carrying metadata
/// advertised a short size and split on different boundaries than the reference. Nothing
/// in the port sent metadata alongside a payload over `MAX_EFFICIENT_SIZE`, so a
/// Swift-to-Swift transfer still round-tripped and the divergence stayed invisible.
final class ResourceMetadataSegmentationTests: XCTestCase {

  final class LoopbackInterface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    weak var paired: LoopbackInterface?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
      let raw = try packet.pack()
      let copy = try Packet.unpack(raw)
      paired?.inboundHandler?(copy, paired!)
    }
  }

  var aT: Transport!
  var bT: Transport!

  private func makeLink() throws -> Link {
    aT = Transport()
    bT = Transport()
    let bId = Identity()
    let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "meta")
    bT.ownerIdentity = bId
    bT.register(destination: bDest)
    let a = LoopbackInterface(name: "a")
    let b = LoopbackInterface(name: "b")
    a.paired = b
    b.paired = a
    aT.register(interface: a)
    bT.register(interface: b)
    let aE = expectation(description: "aE")
    let bE = expectation(description: "bE")
    aT.onLinkEstablished = { _ in aE.fulfill() }
    bT.onLinkEstablished = { _ in bE.fulfill() }
    let link = try Link.initiate(destination: bDest, transport: aT)
    wait(for: [aE, bE], timeout: 2.0)
    return link
  }

  // MARK: - Advertised size

  /// The advertised data size counts the metadata block.
  ///
  /// Python: `self.d = resource.total_size`, and `total_size = data_size + metadata_size`
  /// where `metadata_size` includes the 3-byte length prefix (`Resource.py:267-268, 326`).
  func testAdvertisedDataSizeCountsTheMetadataBlock() throws {
    let link = try makeLink()
    let payload = Data(repeating: 0x5A, count: 500)
    let metadata = Data(repeating: 0x11, count: 40)
    let resource = try Resource(link: link, payload: payload, metadata: metadata)

    XCTAssertEqual(
      resource.dataSize, payload.count + 3 + metadata.count,
      "the advertisement understates the resource by the metadata block")
  }

  /// Without metadata the advertised size is unchanged.
  func testAdvertisedDataSizeIsThePayloadWhenThereIsNoMetadata() throws {
    let link = try makeLink()
    let payload = Data(repeating: 0x5A, count: 500)
    let resource = try Resource(link: link, payload: payload, metadata: nil)

    XCTAssertEqual(resource.dataSize, payload.count)
  }

  // MARK: - Segment boundaries

  /// Segment 1 gives up the metadata block's bytes; later segments are full.
  ///
  /// Python: `first_read_size = MAX_EFFICIENT_SIZE - metadata_size`, then
  /// `segment_read_size = MAX_EFFICIENT_SIZE` for every segment after it
  /// (`Resource.py:311-320`).
  func testFirstSegmentYieldsItsRoomToTheMetadataBlock() {
    let lengths = ResourceTransfer.segmentDataLengths(
      dataSize: 9_000, metadataBlockSize: 10, maxSegment: 4_000)

    XCTAssertEqual(lengths, [3_990, 4_000, 1_010])
    XCTAssertEqual(lengths.reduce(0, +), 9_000, "the split must cover the whole payload")
  }

  /// The metadata block alone can force a second segment.
  ///
  /// Python decides on `total_size`, so a payload that exactly fills a segment splits
  /// once metadata is added to it.
  func testMetadataAlonePushesAFullPayloadIntoTwoSegments() {
    let lengths = ResourceTransfer.segmentDataLengths(
      dataSize: 4_000, metadataBlockSize: 10, maxSegment: 4_000)

    XCTAssertEqual(lengths, [3_990, 10])
  }

  /// A payload that exactly fills a segment and carries no metadata stays whole.
  func testExactlyFullPayloadWithoutMetadataStaysOneSegment() {
    let lengths = ResourceTransfer.segmentDataLengths(
      dataSize: 4_000, metadataBlockSize: 0, maxSegment: 4_000)

    XCTAssertEqual(lengths, [4_000])
  }

  /// The segment count matches Python's `((total_size-1)//MAX_EFFICIENT_SIZE)+1`.
  func testSegmentCountMatchesTheReferenceFormula() {
    for dataSize in [1, 999, 4_000, 4_001, 12_345] {
      for metadataBlockSize in [0, 3, 10, 3_999] {
        let total = dataSize + metadataBlockSize
        let expected = total <= 4_000 ? 1 : ((total - 1) / 4_000) + 1
        let lengths = ResourceTransfer.segmentDataLengths(
          dataSize: dataSize, metadataBlockSize: metadataBlockSize, maxSegment: 4_000)
        XCTAssertEqual(
          lengths.count, expected,
          "wrong segment count for data \(dataSize) metadata \(metadataBlockSize)")
        XCTAssertEqual(
          lengths.reduce(0, +), dataSize,
          "split lost bytes for data \(dataSize) metadata \(metadataBlockSize)")
      }
    }
  }

  // MARK: - Compression limit

  /// `auto_compress` accepts a byte limit, not only a flag.
  ///
  /// Python: an integer turns compression on with that ceiling
  /// (`Resource.py:372-376`), and compression is attempted only when
  /// `data_size <= auto_compress_limit` (`Resource.py:392`).
  func testCompressionLimitSkipsPayloadsOverTheCeiling() throws {
    let link = try makeLink()
    let payload = Data(repeating: 0x42, count: 8_000)

    let under = try Resource(
      link: link, payload: payload, autoCompress: .upTo(8_000))
    XCTAssertTrue(under.isCompressed, "a payload at the ceiling must still be compressed")

    let over = try Resource(
      link: link, payload: payload, autoCompress: .upTo(7_999))
    XCTAssertFalse(over.isCompressed, "a payload over the ceiling must be sent uncompressed")
  }

  /// The flag forms keep working, and a bool literal still satisfies the parameter.
  func testCompressionFlagsStillApply() throws {
    let link = try makeLink()
    let payload = Data(repeating: 0x42, count: 8_000)

    XCTAssertTrue(try Resource(link: link, payload: payload, autoCompress: true).isCompressed)
    XCTAssertFalse(try Resource(link: link, payload: payload, autoCompress: false).isCompressed)
  }

  /// The ceiling is measured on the payload, not on the payload plus its metadata.
  ///
  /// Python compares `data_size`, which it sets before the metadata block exists
  /// (`Resource.py:392`).
  func testCompressionLimitMeasuresThePayloadAlone() throws {
    let link = try makeLink()
    let payload = Data(repeating: 0x42, count: 8_000)
    let metadata = Data(repeating: 0x11, count: 40)

    let resource = try Resource(
      link: link, payload: payload, metadata: metadata, autoCompress: .upTo(8_000))
    XCTAssertTrue(
      resource.isCompressed,
      "the metadata block must not count against the compression ceiling")
  }
}
