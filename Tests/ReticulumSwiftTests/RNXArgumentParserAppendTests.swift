import XCTest
@testable import ReticulumSwift

/// The `action="append"` support rnx's repeatable `-a` needs, plus the flag spellings rnx
/// relies on staying distinct.
/// Python reference: RNS/Utilities/rnx.py:555-576.
final class RNXArgumentParserAppendTests: XCTestCase {

    private func rnxParser() -> ArgumentParser {
        var parser = ArgumentParser(program: "rnx", overview: "Reticulum Remote Execution Utility")
        parser.counted(["-v", "--verbose"], help: "increase verbosity")
        parser.counted(["-q", "--quiet"], help: "decrease verbosity")
        parser.appending(["-a"], metavar: "allowed_hash", help: "accept from this identity")
        parser.flag(["-n", "--noauth"], help: "accept commands from anyone")
        parser.flag(["-N", "--noid"], help: "don't identify to listener")
        parser.flag(["-d", "--detailed"], help: "show detailed result output")
        parser.option(["-w"], metavar: "seconds", help: "connect and request timeout")
        return parser
    }

    private let hashA = String(repeating: "a", count: 32)
    private let hashB = String(repeating: "b", count: 32)

    func testRepeatedAppendCollectsInOrder() throws {
        // Python: `-a` is action="append", so every occurrence contributes an entry.
        let parsed = try rnxParser().parse(["-a", hashA, "-a", hashB])
        XCTAssertEqual(parsed.values("-a"), [hashA, hashB])
    }

    func testSingleAppendYieldsOneValue() throws {
        let parsed = try rnxParser().parse(["-a", hashA])
        XCTAssertEqual(parsed.values("-a"), [hashA])
    }

    func testAbsentAppendYieldsNil() throws {
        // Python leaves args.allowed as None when the option never appeared, and
        // `values(_:)` mirrors that with nil rather than [].
        //
        // The distinction is not cosmetic: rnid's `nargs="*"` options rely on it, because
        // a bare `-e` yields a *falsy* empty list that skips the operation entirely and
        // does not count toward rnid's mutual-exclusion tally. Collapsing nil into []
        // would erase that. rnx does not care either way and coalesces at its call site.
        let parsed = try rnxParser().parse([])
        XCTAssertNil(parsed.values("-a"))
    }

    func testAppendMissingValueIsAUsageError() {
        XCTAssertThrowsError(try rnxParser().parse(["-a"])) { error in
            XCTAssertEqual(error as? ArgumentError, .missingValue("-a"))
        }
    }

    func testShortFlagsStayCaseSensitive() throws {
        // -n (noauth) and -N (noid) are different options and must not collide.
        let lower = try rnxParser().parse(["-n"])
        XCTAssertTrue(lower.flag("--noauth"))
        XCTAssertFalse(lower.flag("--noid"))

        let upper = try rnxParser().parse(["-N"])
        XCTAssertTrue(upper.flag("--noid"))
        XCTAssertFalse(upper.flag("--noauth"))
    }

    func testBundlingStillWorksAlongsideAppend() throws {
        // argparse accepts "-vv" as count 2 and "-Nd" as two store_true flags.
        let counted = try rnxParser().parse(["-vv"])
        XCTAssertEqual(counted.count("--verbose"), 2)

        let bundled = try rnxParser().parse(["-Nd"])
        XCTAssertTrue(bundled.flag("--noid"))
        XCTAssertTrue(bundled.flag("--detailed"))
    }

    func testNegativeOptionValueIsConsumed() throws {
        // argparse's negative-number heuristic lets `-w -1` through because the parser
        // declares no negative-number-looking options.
        let parsed = try rnxParser().parse(["-w", "-1"])
        XCTAssertEqual(parsed.double("-w"), -1)
    }

    func testAppendUsageLineShowsItsMetavar() {
        XCTAssertTrue(rnxParser().usage.contains("-a allowed_hash"))
    }
}
