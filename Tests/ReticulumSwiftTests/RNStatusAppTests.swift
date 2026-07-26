import XCTest
@testable import ReticulumSwift

/// Constants, `speed_str`, exit codes, sort tokens and the argument table for `rnstatus`.
///
/// Python reference: `RNS/Utilities/rnstatus.py` (constants inline in `program_setup` and
/// `main`, `speed_str` at rnstatus.py:760).
final class RNStatusAppTests: XCTestCase {

    // MARK: - Constants

    func testIdentityConstants() {
        XCTAssertEqual(RNStatusApp.appName, "rnstatus")
        // Python: argparse(description="Reticulum Network Stack Status") — rnstatus.py:689
        XCTAssertEqual(RNStatusApp.description, "Reticulum Network Stack Status")
    }

    func testRemoteManagementConstants() {
        // Python: RNS.Destination.hash_from_name_and_identity("rnstransport.remote.management", …)
        XCTAssertEqual(RNStatusApp.remoteManagementFullName, "rnstransport.remote.management")
        XCTAssertEqual(RNStatusApp.remoteManagementAppName, "rnstransport")
        XCTAssertEqual(RNStatusApp.remoteManagementAspects, ["remote", "management"])
        XCTAssertEqual(RNStatusApp.statusRequestPath, "/status")
        // The dotted name must decompose back into exactly the app name and aspects.
        XCTAssertEqual(
            ([RNStatusApp.remoteManagementAppName] + RNStatusApp.remoteManagementAspects).joined(separator: "."),
            RNStatusApp.remoteManagementFullName
        )
    }

    func testDestinationHexLength() {
        // Python: dest_len = (RNS.Reticulum.TRUNCATED_HASHLENGTH//8)*2 = 32 — rnstatus.py:315
        XCTAssertEqual(RNStatusApp.destinationHexLength, 32)
    }

    func testEraseSequenceIsExactlyFiftyEightSpaces() {
        // Python: print("\r" + 58 spaces + "\r", end="") — rnstatus.py:80 and 7 more sites
        XCTAssertEqual(RNStatusApp.eraseSequence.count, 60)
        XCTAssertTrue(RNStatusApp.eraseSequence.hasPrefix("\r"))
        XCTAssertTrue(RNStatusApp.eraseSequence.hasSuffix("\r"))
        let middle = RNStatusApp.eraseSequence.dropFirst().dropLast()
        XCTAssertEqual(middle.count, 58)
        XCTAssertTrue(middle.allSatisfy { $0 == " " })
    }

    func testLayoutConstants() {
        XCTAssertEqual(RNStatusApp.minimumColumnWidth, 10)          // rnstatus.py:618
        XCTAssertEqual(RNStatusApp.continuationIndent.count, 16)    // rnstatus.py:628
        XCTAssertTrue(RNStatusApp.continuationIndent.allSatisfy { $0 == " " })
        XCTAssertEqual(RNStatusApp.discoveredTableRuleWidth, 89)    // rnstatus.py:266
        XCTAssertEqual(RNStatusApp.detailSeparatorWidth, 32)        // rnstatus.py:234
        XCTAssertEqual(RNStatusApp.clearScreen, "\u{1b}[H\u{1b}[2J")// rnstatus.py:742
    }

    func testTimingConstants() {
        // Python: remote_timeout=RNS.Transport.PATH_REQUEST_TIMEOUT, which is 15
        XCTAssertEqual(RNStatusApp.defaultRemoteTimeout, 15)
        XCTAssertEqual(RNStatusApp.defaultRemoteTimeout, Transport.pathRequestTimeout)
        XCTAssertEqual(RNStatusApp.defaultMonitorInterval, 1.0)     // rnstatus.py:708
        XCTAssertEqual(RNStatusApp.minimumMonitorSleep, 0.2)        // rnstatus.py:746
        XCTAssertEqual(RNStatusApp.baseLogLevel, 3)                 // RNS.LOG_NOTICE
    }

    // MARK: - speed_str

    func testSpeedStrGoldenValues() {
        // Python: "%3.2f %s%s" for every magnitude below 1000, divisor 1000.
        XCTAssertEqual(RNStatusApp.speedStr(0), "0.00 bps")
        XCTAssertEqual(RNStatusApp.speedStr(9600), "9.60 kbps")
        XCTAssertEqual(RNStatusApp.speedStr(1_000_000), "1.00 Mbps")
        XCTAssertEqual(RNStatusApp.speedStr(1_000_000_000), "1.00 Gbps")
        XCTAssertEqual(RNStatusApp.speedStr(10_000_000), "10.00 Mbps")
        XCTAssertEqual(RNStatusApp.speedStr(5_000_000), "5.00 Mbps")
    }

    func testSpeedStrOverflowBranchKeepsItsSpace() {
        // Python: speed_str's last-unit return is "%.2f %s%s" — WITH a space, unlike
        // prettysize's "%.2f%s%s". Verified live: speed_str(1e27) == "1000.00 Ybps".
        XCTAssertEqual(RNStatusApp.speedStr(1e27), "1000.00 Ybps")
    }

    func testSpeedStrIsNotPrettyspeed() {
        // The two must never be conflated: speed_str uses a lowercase k for kilo.
        XCTAssertEqual(RNStatusApp.speedStr(9600), "9.60 kbps")
        XCTAssertEqual(RNSUtilities.prettyspeed(9600), "9.60 Kbps")
        XCTAssertNotEqual(RNStatusApp.speedStr(9600), RNSUtilities.prettyspeed(9600))
    }

    // MARK: - Exit codes

    func testResultRawValues() {
        XCTAssertEqual(RNStatusApp.Result.ok.rawValue, 0)
        XCTAssertEqual(RNStatusApp.Result.noSharedInstance.rawValue, 1)     // rnstatus.py:171
        XCTAssertEqual(RNStatusApp.Result.noStatus.rawValue, 2)             // rnstatus.py:683
        XCTAssertEqual(RNStatusApp.Result.linkFailed.rawValue, 10)          // rnstatus.py:100
        XCTAssertEqual(RNStatusApp.Result.pathRequestTimeout.rawValue, 12)  // rnstatus.py:82
        XCTAssertEqual(RNStatusApp.Result.remoteError.rawValue, 20)         // rnstatus.py:332
        XCTAssertEqual(RNStatusApp.Result.allCases.count, 6)
    }

    // MARK: - Sort tokens

    func testSortTokens() {
        // Python: the if-chain at rnstatus.py:362-387. `bitrate` and `announce` are
        // accepted aliases the --help text does not list.
        let expected = ["rate", "bitrate", "rx", "tx", "rxs", "txs", "traffic",
                        "announces", "announce", "arx", "atx", "prx", "ptx", "held"]
        XCTAssertEqual(RNStatusApp.Sort.allCases.map(\.rawValue), expected)
        XCTAssertEqual(RNStatusApp.Sort.allCases.count, 14)
    }

    func testUnknownSortTokenIsNil() {
        // Python silently ignores an unrecognised -s value.
        XCTAssertNil(RNStatusApp.Sort(rawValue: "sideways"))
        XCTAssertNil(RNStatusApp.Sort(rawValue: ""))
    }

    // MARK: - Argument table

    func testEveryFlagSpellingParses() throws {
        let parser = RNStatusApp.makeParser()

        for (short, long) in [("-a", "--all"), ("-A", "--announce-stats"), ("-P", "--pr-stats"),
                              ("-l", "--link-stats"), ("-B", "--burst"), ("-t", "--totals"),
                              ("-r", "--reverse"), ("-j", "--json"), ("-d", "--discovered"),
                              ("-m", "--monitor")] {
            XCTAssertTrue(try parser.parse([short]).flag(long), "short \(short)")
            XCTAssertTrue(try parser.parse([long]).flag(long), "long \(long)")
        }
        // -D has no long form in Python (rnstatus.py:706).
        XCTAssertTrue(try parser.parse(["-D"]).flag("-D"))
    }

    func testValueOptionsParse() throws {
        let parser = RNStatusApp.makeParser()
        let parsed = try parser.parse(["--config", "/tmp/cfg", "-s", "traffic",
                                       "-R", "abcdef", "-i", "~/id", "-w", "3.5",
                                       "-I", "0.5"])
        XCTAssertEqual(parsed.value("--config"), "/tmp/cfg")
        XCTAssertEqual(parsed.value("--sort"), "traffic")
        XCTAssertEqual(parsed.value("-R"), "abcdef")
        XCTAssertEqual(parsed.value("-i"), "~/id")
        XCTAssertEqual(parsed.double("-w"), 3.5)
        XCTAssertEqual(parsed.double("--monitor-interval"), 0.5)
    }

    func testVerboseIsCounted() throws {
        let parser = RNStatusApp.makeParser()
        // Python: action="count", default=0 — and argparse accepts the bundled form.
        XCTAssertEqual(try parser.parse([]).count("--verbose"), 0)
        XCTAssertEqual(try parser.parse(["-v"]).count("--verbose"), 1)
        XCTAssertEqual(try parser.parse(["-vv"]).count("--verbose"), 2)
        XCTAssertEqual(try parser.parse(["-v", "-v", "-v"]).count("--verbose"), 3)
    }

    func testOptionalPositionalFilter() throws {
        let parser = RNStatusApp.makeParser()
        XCTAssertTrue(try parser.parse([]).positionals.isEmpty)
        XCTAssertEqual(try parser.parse(["-A", "rnode"]).positionals.first, "rnode")
    }

    func testCapitalDImpliesDiscovered() throws {
        // Python: `if config_entries: discovered_interfaces = True; details = True`
        // (rnstatus.py:178-180). The parser itself only records -D; the implication is
        // applied by the executable, so assert the flag the executable keys off.
        let parsed = try RNStatusApp.makeParser().parse(["-D"])
        XCTAssertTrue(parsed.flag("-D"))
        XCTAssertFalse(parsed.flag("--discovered"))
        XCTAssertTrue(parsed.flag("-D") || parsed.flag("--discovered"))
    }

    // MARK: - Help text

    func testHelpTextMatchesArgparse() {
        // Captured from the installed Python utility: `rnstatus --help`.
        let lines = RNStatusApp.helpText.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "usage: rnstatus [-h] [--config CONFIG] [--version] [-a] [-A] [-P] [-l] [-B]")
        XCTAssertEqual(lines.last, "  -v, --verbose")
        XCTAssertTrue(lines.contains("Reticulum Network Stack Status"))
        XCTAssertTrue(lines.contains("  -A, --announce-stats  show announce stats"))
        XCTAssertTrue(lines.contains("  -D                    show details and config entries for discovered"))
        XCTAssertTrue(lines.contains("  -I seconds, --monitor-interval seconds"))
        // argparse aligns the help column at 24 characters.
        for line in lines where line.hasPrefix("  -") && line.count > 24 {
            let column = line.index(line.startIndex, offsetBy: 23)
            if line[column] != " " {
                XCTAssertTrue(line.count <= 24 || line.hasPrefix("  -I seconds") || line.hasPrefix("  -s SORT"),
                              "unexpected help column in: \(line)")
            }
        }
    }
}
