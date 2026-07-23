import XCTest
@testable import ReticulumSwift

/// Tests for the `-E`/`--embed-meta` metadata parser.
///
/// Python reference: RNS/Utilities/rnid.py — `rsg_meta_from_file` (:566-575) and
/// `rsg_meta_from_str` (:577-586), which parse with RNS's vendored ConfigObj and optionally
/// coerce through `Validator()`.
final class RNIDMetaTests: XCTestCase {

    private let sample = """
    name = testpkg
    version = 1.2.3
    tags = alpha, beta, gamma
    empty =
    [origin]
      host = example.com
      port = 4242
      [[nested]]
        k = v
    """

    func testParsePreservesOrderAndConfigObjScalarRules() {
        let parsed = RNIDMeta.parse(sample)
        XCTAssertEqual(parsed.map { $0.0 }, ["name", "version", "tags", "empty", "origin"])

        XCTAssertEqual(parsed[0].1, .string("testpkg"))
        XCTAssertEqual(parsed[1].1, .string("1.2.3"))
        // ConfigObj: an unquoted comma-separated value becomes a list of strings.
        XCTAssertEqual(parsed[2].1, .array([.string("alpha"), .string("beta"), .string("gamma")]))
        // ConfigObj: `k =` yields the empty string, not nil.
        XCTAssertEqual(parsed[3].1, .string(""))

        guard case .map(let origin) = parsed[4].1 else { return XCTFail("origin is not a section") }
        XCTAssertEqual(origin.map { $0.0 }, [.string("host"), .string("port"), .string("nested")])
        XCTAssertEqual(origin[0].1, .string("example.com"))
        // Without a spec everything stays a string, including numeric-looking values.
        XCTAssertEqual(origin[1].1, .string("4242"))
        XCTAssertEqual(origin[2].1, .map([(.string("k"), .string("v"))]))
    }

    func testSpecCoercesOnlyTheDeclaredKeys() throws {
        let spec = """
        [origin]
          port = integer
        """
        let parsed = try RNIDMeta.parse(sample, spec: spec)
        guard case .map(let origin)? = parsed.first(where: { $0.0 == "origin" })?.1 else {
            return XCTFail("origin is not a section")
        }
        XCTAssertEqual(origin.first { $0.0 == .string("port") }?.1, .int(4242))
        // Unspecced siblings stay strings.
        XCTAssertEqual(origin.first { $0.0 == .string("host") }?.1, .string("example.com"))
        XCTAssertEqual(parsed.first { $0.0 == "name" }?.1, .string("testpkg"))
    }

    func testSpecCoercesFloatsBooleansAndLists() throws {
        let text = """
        ratio = 1.5
        enabled = yes
        single = one
        """
        let spec = """
        ratio = float
        enabled = boolean
        single = string_list
        """
        let parsed = try RNIDMeta.parse(text, spec: spec)
        XCTAssertEqual(parsed[0].1, .double(1.5))
        XCTAssertEqual(parsed[1].1, .bool(true))
        XCTAssertEqual(parsed[2].1, .array([.string("one")]))
    }

    func testSpecFailureRaisesTheSameErrorPythonDoes() {
        // Python: ValueError("Metadata did not pass spec validation")
        XCTAssertThrowsError(try RNIDMeta.parse("port = notanumber", spec: "port = integer")) { error in
            XCTAssertEqual(error as? RNIDMeta.MetaError, .specValidationFailed)
            XCTAssertEqual("\(error)", "Metadata did not pass spec validation")
        }
    }

    func testUnknownSpecCheckIsRejectedRatherThanSilentlyAccepted() {
        // Full Validator parity is out of scope; an unrecognised check must not pass silently.
        XCTAssertThrowsError(try RNIDMeta.parse("x = 1", spec: "x = ip_addr")) { error in
            XCTAssertEqual(error as? RNIDMeta.MetaError, .unsupportedCheck("ip_addr"))
        }
    }

    func testCommentsAndBlankLinesAreIgnored() {
        let parsed = RNIDMeta.parse("""
        # a comment

        name = x
        """)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].0, "name")
    }

    func testQuotedValuesAreUnquoted() {
        let parsed = RNIDMeta.parse("name = \"quoted value\"")
        XCTAssertEqual(parsed[0].1, .string("quoted value"))
    }

    /// `create_rsg` relies on ConfigObj's file order when merging into the envelope's meta
    /// map, so order must survive all the way to the wire bytes.
    func testParsedOrderSurvivesIntoTheEnvelope() throws {
        let identity = Identity()
        let meta = RNIDMeta.parse("alpha = 1\nbravo = 2\ncharlie = 3")
        guard case .binary(let rsg) = try RSG.create(signer: identity, message: .text("m"),
                                                     embed: true, meta: meta, output: .bin)
        else { return XCTFail("expected binary output") }

        let envelope = rsg.subdata(in: RSG.signatureLength..<rsg.count)
        let decoded = try RSG.SignedData.decode(envelope: envelope)
        XCTAssertEqual(decoded.meta.map { $0.0 }, ["signer", "pubkey", "alpha", "bravo", "charlie"])
    }
}
