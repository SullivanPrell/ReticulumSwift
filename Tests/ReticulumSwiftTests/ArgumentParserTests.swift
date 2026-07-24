import XCTest
@testable import ReticulumSwift

/// Tests for ``ArgumentParser`` — the `argparse` subset the `rn*` utilities need.
///
/// Python reference: the `argparse` setup in each of `RNS/Utilities/rn*.py`.
/// Flag spellings are user-facing contract, so these tests pin the behaviours the
/// Python tools depend on rather than a convenient Swift-shaped alternative.
final class ArgumentParserTests: XCTestCase {

    /// A parser shaped like the flags every RNS utility shares.
    private func makeParser() -> ArgumentParser {
        var parser = ArgumentParser(program: "rntest", overview: "Test utility")
        parser.option(["--config"], metavar: "PATH", help: "path to alternative config directory")
        parser.counted(["-v", "--verbose"], help: "increase verbosity")
        parser.counted(["-q", "--quiet"], help: "decrease verbosity")
        parser.flag(["-j", "--json"], help: "output as JSON")
        parser.option(["-w", "--timeout"], metavar: "SECONDS", help: "timeout", default: "12")
        parser.positional("destination", help: "destination hash")
        return parser
    }

    // MARK: - Flags

    func testFlag_absent() throws {
        let result = try makeParser().parse([])
        XCTAssertFalse(result.flag("--json"))
    }

    func testFlag_longForm() throws {
        let result = try makeParser().parse(["--json"])
        XCTAssertTrue(result.flag("--json"))
    }

    func testFlag_shortFormResolvesToSameKey() throws {
        // A caller should be able to ask by the long name regardless of which
        // spelling the user typed — argparse stores under a single dest.
        let result = try makeParser().parse(["-j"])
        XCTAssertTrue(result.flag("--json"))
    }

    // MARK: - Counted flags

    func testCount_absentIsZero() throws {
        // Python: action="count", default=0
        let result = try makeParser().parse([])
        XCTAssertEqual(result.count("--verbose"), 0)
    }

    func testCount_repeatedLongForm() throws {
        let result = try makeParser().parse(["--verbose", "--verbose", "--verbose"])
        XCTAssertEqual(result.count("--verbose"), 3)
    }

    func testCount_repeatedShortForm() throws {
        let result = try makeParser().parse(["-v", "-v"])
        XCTAssertEqual(result.count("--verbose"), 2)
    }

    func testCount_bundledShortForm() throws {
        // argparse accepts "-vvv" as three occurrences.
        let result = try makeParser().parse(["-vvv"])
        XCTAssertEqual(result.count("--verbose"), 3)
    }

    func testCount_mixedBundle() throws {
        // "-vvq" is two verbose and one quiet.
        let result = try makeParser().parse(["-vvq"])
        XCTAssertEqual(result.count("--verbose"), 2)
        XCTAssertEqual(result.count("--quiet"), 1)
    }

    func testCount_bundledFlagsAndCounts() throws {
        let result = try makeParser().parse(["-jv"])
        XCTAssertTrue(result.flag("--json"))
        XCTAssertEqual(result.count("--verbose"), 1)
    }

    func testVerbosityArithmetic() throws {
        // Python: targetverbosity = verbosity - quietness
        let result = try makeParser().parse(["-vvv", "-q"])
        XCTAssertEqual(result.count("--verbose") - result.count("--quiet"), 2)
    }

    // MARK: - Options with values

    func testOption_separateValue() throws {
        let result = try makeParser().parse(["--config", "/etc/reticulum"])
        XCTAssertEqual(result.value("--config"), "/etc/reticulum")
    }

    func testOption_inlineValue() throws {
        let result = try makeParser().parse(["--config=/etc/reticulum"])
        XCTAssertEqual(result.value("--config"), "/etc/reticulum")
    }

    func testOption_inlineValueContainingEquals() throws {
        // Only the first '=' separates; the rest belongs to the value.
        let result = try makeParser().parse(["--config=a=b"])
        XCTAssertEqual(result.value("--config"), "a=b")
    }

    func testOption_shortFormWithValue() throws {
        let result = try makeParser().parse(["-w", "30"])
        XCTAssertEqual(result.int("--timeout"), 30)
    }

    func testOption_default() throws {
        let result = try makeParser().parse([])
        XCTAssertEqual(result.value("--timeout"), "12")
    }

    func testOption_defaultIsOverridden() throws {
        let result = try makeParser().parse(["--timeout", "45"])
        XCTAssertEqual(result.int("--timeout"), 45)
    }

    func testOption_missingValue_throws() {
        XCTAssertThrowsError(try makeParser().parse(["--config"])) { error in
            XCTAssertEqual(error as? ArgumentError, .missingValue("--config"))
        }
    }

    func testOption_valueOnFlag_throws() {
        XCTAssertThrowsError(try makeParser().parse(["--json=yes"])) { error in
            XCTAssertEqual(error as? ArgumentError, .unexpectedValue("--json"))
        }
    }

    func testDoubleParsing() throws {
        let result = try makeParser().parse(["--timeout", "2.5"])
        XCTAssertEqual(result.double("--timeout"), 2.5)
    }

    func testIntParsing_nonNumeric_returnsNil() throws {
        let result = try makeParser().parse(["--timeout", "soon"])
        XCTAssertNil(result.int("--timeout"))
    }

    // MARK: - Positionals

    func testPositional_collected() throws {
        let result = try makeParser().parse(["a1b2c3d4"])
        XCTAssertEqual(result.positionals, ["a1b2c3d4"])
    }

    func testPositional_orderPreservedAroundOptions() throws {
        let result = try makeParser().parse(["first", "--json", "second"])
        XCTAssertEqual(result.positionals, ["first", "second"])
        XCTAssertTrue(result.flag("--json"))
    }

    func testPositional_bareDashIsPositional() throws {
        // "-" conventionally means stdin/stdout; rncp and rnid both accept it.
        let result = try makeParser().parse(["-"])
        XCTAssertEqual(result.positionals, ["-"])
    }

    func testDoubleDashTerminatesOptionParsing() throws {
        let result = try makeParser().parse(["--", "--json", "-v"])
        XCTAssertEqual(result.positionals, ["--json", "-v"])
        XCTAssertFalse(result.flag("--json"))
        XCTAssertEqual(result.count("--verbose"), 0)
    }

    func testNegativeNumberAfterOptionIsTakenAsValue() throws {
        let result = try makeParser().parse(["--timeout", "-1"])
        XCTAssertEqual(result.int("--timeout"), -1)
    }

    // MARK: - Errors

    func testUnrecognisedOption_throws() {
        XCTAssertThrowsError(try makeParser().parse(["--nonsense"])) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedOption("--nonsense"))
        }
    }

    func testUnrecognisedBundle_throws() {
        // "-vz" — z is not declared, so the whole bundle is rejected rather than
        // silently applying the half that parsed.
        XCTAssertThrowsError(try makeParser().parse(["-vz"])) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedOption("-vz"))
        }
    }

    func testBundleContainingValueOption_throws() {
        // "-wj" cannot bundle, because -w consumes a value.
        XCTAssertThrowsError(try makeParser().parse(["-wj"]))
    }

    // MARK: - Help

    func testHelpFlag_isImplicit() throws {
        // argparse adds -h/--help unless the program declares them itself.
        XCTAssertTrue(try makeParser().parse(["--help"]).wantsHelp)
        XCTAssertTrue(try makeParser().parse(["-h"]).wantsHelp)
        XCTAssertFalse(try makeParser().parse([]).wantsHelp)
    }

    func testUsageMentionsProgramAndOptions() {
        let usage = makeParser().usage
        XCTAssertTrue(usage.contains("usage: rntest"))
        XCTAssertTrue(usage.contains("Test utility"))
        XCTAssertTrue(usage.contains("--config"))
        XCTAssertTrue(usage.contains("-v, --verbose"))
        XCTAssertTrue(usage.contains("destination"))
        XCTAssertTrue(usage.contains("-h, --help"))
    }

    // MARK: - Long-option abbreviation
    //
    // `argparse` defaults to `allow_abbrev=True`, and none of the RNS utilities turn it
    // off, so every one of them accepts any unambiguous prefix of a long option. Verified
    // against the installed Python tools:
    //
    //   rnstatus --j       →  runs, as though --json
    //   rnprobe  --si      →  "argument -s/--size: expected one argument"
    //   rnprobe  --v       →  "ambiguous option: --v could match --version, --verbose"
    //   rnstatus --hel     →  prints help, exit 0

    func testAbbreviation_unambiguousPrefixResolves() throws {
        let result = try makeParser().parse(["--js"])
        XCTAssertTrue(result.flag("--json"))
    }

    func testAbbreviation_worksForValueOptions() throws {
        let result = try makeParser().parse(["--conf", "/tmp/x"])
        XCTAssertEqual(result.value("--config"), "/tmp/x")
    }

    func testAbbreviation_worksWithInlineValue() throws {
        let result = try makeParser().parse(["--conf=/tmp/x"])
        XCTAssertEqual(result.value("--config"), "/tmp/x")
    }

    func testAbbreviation_missingValueNamesTheFullOption() {
        XCTAssertThrowsError(try makeParser().parse(["--conf"])) { error in
            // The error carries the option's canonical name, not the typed abbreviation.
            XCTAssertEqual(error as? ArgumentError, .missingValue("--config"))
        }
    }

    func testAbbreviation_exactMatchWinsOverLongerCandidates() throws {
        // "--verbose" is also a prefix of nothing else, but the point is that an exact
        // hit is never treated as an ambiguous prefix of itself plus a longer sibling.
        var parser = ArgumentParser(program: "rntest", overview: "Test utility")
        parser.flag(["--log"], help: "log")
        parser.flag(["--logfile"], help: "logfile")
        let result = try parser.parse(["--log"])
        XCTAssertTrue(result.flag("--log"))
        XCTAssertFalse(result.flag("--logfile"))
    }

    func testAbbreviation_ambiguousPrefixThrowsWithCandidatesInDeclarationOrder() {
        var parser = ArgumentParser(program: "rntest", overview: "Test utility")
        parser.flag(["--version"], help: "version")
        parser.counted(["-v", "--verbose"], help: "verbose")
        XCTAssertThrowsError(try parser.parse(["--ver"])) { error in
            XCTAssertEqual(error as? ArgumentError,
                           .ambiguousOption("--ver", ["--version", "--verbose"]))
        }
    }

    func testAbbreviation_appliesToImplicitHelp() throws {
        XCTAssertTrue(try makeParser().parse(["--hel"]).wantsHelp)
        XCTAssertTrue(try makeParser().parse(["--h"]).wantsHelp)
    }

    func testAbbreviation_doesNotApplyToShortOptions() {
        // argparse abbreviates long options only; "-co" is a bundle attempt, not "--config".
        XCTAssertThrowsError(try makeParser().parse(["-co"]))
    }

    func testAbbreviation_unknownPrefixIsStillUnrecognised() {
        XCTAssertThrowsError(try makeParser().parse(["--zzz"])) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedOption("--zzz"))
        }
    }

    // MARK: - argparse error wording

    func testUnrecognisedOptionRendersAsPlural() {
        // argparse always says "unrecognized arguments" — plural, even for a single token.
        XCTAssertEqual(ArgumentError.unrecognisedOption("--bogus").description,
                       "unrecognized arguments: --bogus")
    }

    func testMessageNamesAnOptionByEverySpelling() {
        // Python: "argument -w/--timeout: expected one argument". The parser owns the
        // declarations, so it is the only thing that can expand a name into that form.
        let parser = makeParser()
        XCTAssertEqual(parser.message(for: .missingValue("--timeout")),
                       "argument -w/--timeout: expected one argument")
        XCTAssertEqual(parser.message(for: .unexpectedValue("--json")),
                       "argument -j/--json: ignored explicit argument")
    }

    func testMessageLeavesSingleSpellingOptionsAlone() {
        XCTAssertEqual(makeParser().message(for: .missingValue("--config")),
                       "argument --config: expected one argument")
    }

    func testMessagePassesThroughNonOptionErrors() {
        let parser = makeParser()
        XCTAssertEqual(parser.message(for: .unrecognisedOption("--bogus")),
                       "unrecognized arguments: --bogus")
        XCTAssertEqual(parser.message(for: .ambiguousOption("--ver", ["--version", "--verbose"])),
                       "ambiguous option: --ver could match --version, --verbose")
    }
}
