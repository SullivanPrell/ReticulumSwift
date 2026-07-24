import XCTest
@testable import ReticulumSwift

/// The `argparse` error page every utility prints when parsing fails.
///
/// Python's `ArgumentParser.error()` writes the **usage block** — never the full options
/// table — followed by `prog: error: <detail>`, to stderr, and exits 2. Each assertion here
/// was checked against the installed Python tool before it was written; the reference
/// wording appears in the comments.
final class UtilityErrorPageTests: XCTestCase {

    // MARK: - The usage block is the first paragraph of the help text

    /// A utility's error page must reuse its help text's usage block verbatim. Deriving it
    /// rather than restating it is what stops the two drifting apart when a flag is added.
    private func assertUsageIsHelpsFirstParagraph(_ usage: String, _ help: String,
                                                  file: StaticString = #filePath,
                                                  line: UInt = #line) {
        XCTAssertTrue(usage.hasPrefix("usage: "), "usage block must start with 'usage: '",
                      file: file, line: line)
        XCTAssertFalse(usage.contains("\n\n"), "usage block is a single paragraph",
                       file: file, line: line)
        XCTAssertTrue(help.hasPrefix(usage), "usage block must open the help text",
                      file: file, line: line)
        // The options table belongs to --help only.
        XCTAssertFalse(usage.contains("show this help message"),
                       "usage block must not carry the options table", file: file, line: line)
    }

    func testRNStatusUsageBlock() {
        assertUsageIsHelpsFirstParagraph(RNStatusApp.usageText, RNStatusApp.helpText)
    }

    func testRNPathUsageBlock() {
        assertUsageIsHelpsFirstParagraph(RNPathApp.usageText, RNPathApp.helpText)
    }

    func testRNIDUsageBlock() {
        assertUsageIsHelpsFirstParagraph(RNIDCommandLine.usageText, RNIDCommandLine.helpText)
    }

    // MARK: - The error line

    func testRNStatusErrorPageShape() {
        // Python: `rnstatus --bogus` → usage block, then
        // "rnstatus: error: unrecognized arguments: --bogus", exit 2.
        let page = RNStatusApp.errorText("unrecognized arguments: --bogus")
        XCTAssertTrue(page.hasPrefix(RNStatusApp.usageText))
        XCTAssertTrue(page.hasSuffix("\nrnstatus: error: unrecognized arguments: --bogus"), page)
    }

    func testRNPathErrorPageShape() {
        let page = RNPathApp.errorText("unrecognized arguments: --bogus")
        XCTAssertTrue(page.hasPrefix(RNPathApp.usageText))
        XCTAssertTrue(page.hasSuffix("\nrnpath: error: unrecognized arguments: --bogus"), page)
    }

    func testRNIDErrorPageShape() {
        // Regression: this used to print the entire help text — options table and all —
        // where Python prints four lines of usage and one line of error.
        let page = RNIDCommandLine.errorText("unrecognized arguments: --bogus")
        XCTAssertTrue(page.hasPrefix(RNIDCommandLine.usageText))
        XCTAssertTrue(page.hasSuffix("\nrnid: error: unrecognized arguments: --bogus"), page)
        XCTAssertFalse(page.contains("show this help message and exit"), page)
    }

    // MARK: - Detail lines, as the parser renders them

    func testRNStatusNamesOptionsByEverySpelling() {
        // Python: "rnstatus: error: argument -s/--sort: expected one argument", but plain
        // "argument -w:" because rnstatus declares -w with no long form.
        let parser = RNStatusApp.makeParser()
        XCTAssertEqual(parser.message(for: .missingValue("--sort")),
                       "argument -s/--sort: expected one argument")
        XCTAssertEqual(parser.message(for: .missingValue("-w")),
                       "argument -w: expected one argument")
        XCTAssertEqual(parser.message(for: .missingValue("--monitor-interval")),
                       "argument -I/--monitor-interval: expected one argument")
    }

    func testUnrecognisedArgumentsIsAlwaysPlural() {
        // argparse never says "unrecognized argument" in the singular, even for one token.
        let parser = RNStatusApp.makeParser()
        XCTAssertEqual(parser.message(for: .unrecognisedOption("-Z")),
                       "unrecognized arguments: -Z")
    }

    // MARK: - Abbreviation reaches every utility

    /// `allow_abbrev` is an `argparse` default that none of the RNS tools disable, so it is
    /// the shared parser's job, not any one utility's. Before this was hoisted, only `rnsd`
    /// accepted `--conf`, and the other eight rejected it as unrecognised.
    func testEveryUtilityParserAbbreviatesConfig() throws {
        let parsers: [(String, ArgumentParser)] = [
            ("rnstatus", RNStatusApp.makeParser()),
            ("rnprobe",  NetworkProbe.Arguments.makeParser()),
            ("rnid",     RNIDCommandLine.makeParser()),
        ]
        for (name, parser) in parsers {
            let parsed = try parser.parse(["--conf", "/tmp/x"])
            XCTAssertEqual(parsed.value("--config"), "/tmp/x", "\(name) should accept --conf")
        }
    }

    func testAmbiguousAbbreviationIsRejectedEverywhere() {
        // Python: "ambiguous option: --ver could match --version, --verbose" — candidates
        // in declaration order.
        for (name, parser) in [("rnstatus", RNStatusApp.makeParser()),
                               ("rnprobe", NetworkProbe.Arguments.makeParser())] {
            XCTAssertThrowsError(try parser.parse(["--ver"]), name) { error in
                guard case .ambiguousOption(let given, let candidates)? = error as? ArgumentError
                else { return XCTFail("\(name): expected ambiguousOption, got \(error)") }
                XCTAssertEqual(given, "--ver")
                XCTAssertEqual(candidates, ["--version", "--verbose"], name)
            }
        }
    }
}
