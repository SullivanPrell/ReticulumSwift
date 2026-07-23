import XCTest
@testable import ReticulumSwift

/// Pure-logic tests for the `rncp` port.
///
/// Python reference: `RNS/Utilities/rncp.py` (Reticulum File Transfer Utility).
/// Golden byte strings and formatted values were produced by running the real
/// Python — `RNS.vendor.umsgpack.packb`, `hashlib.sha256`, `os.path.*` and rncp's own
/// `size_str` — against the installed RNS on this machine.

// MARK: - File-system double

/// In-memory ``RNCopyFileSystem`` so every path/save/fetch decision is assertable with no
/// disk. File-scope because the suite has no shared helper file and none should be added.
/// Non-final so a test can subclass it to make one operation fail.
class MockRNCopyFileSystem: RNCopyFileSystem {

    var homeDirectoryPath: String
    var currentDirectoryPath: String
    var files: [String: Data]
    var directories: Set<String>
    var nonWritableDirectories: Set<String>

    /// When true, ``removeFile(atPath:)`` throws — used to prove `-O` falls back to renaming.
    var removeFails = false
    /// When true, ``writeFile(_:toPath:)`` throws.
    var writeFails = false

    private(set) var writtenPaths: [String] = []
    private(set) var removedPaths: [String] = []

    struct MockError: Swift.Error, CustomStringConvertible {
        let description: String
    }

    init(home: String = "/h",
         cwd: String = "/cwd",
         files: [String: Data] = [:],
         directories: Set<String> = [],
         nonWritableDirectories: Set<String> = []) {
        self.homeDirectoryPath = home
        self.currentDirectoryPath = cwd
        self.files = files
        self.directories = directories
        self.nonWritableDirectories = nonWritableDirectories
    }

    convenience init(home: String = "/h", cwd: String = "/cwd", filePaths: [String]) {
        self.init(home: home, cwd: cwd,
                  files: Dictionary(uniqueKeysWithValues: filePaths.map { ($0, Data()) }))
    }

    func fileExists(atPath path: String) -> Bool { files[path] != nil }
    func isDirectory(atPath path: String) -> Bool { directories.contains(path) }
    func isWritableDirectory(atPath path: String) -> Bool {
        directories.contains(path) && !nonWritableDirectories.contains(path)
    }

    func readFile(atPath path: String) throws -> Data {
        guard let data = files[path] else { throw MockError(description: "no such file: \(path)") }
        return data
    }

    func writeFile(_ data: Data, toPath path: String) throws {
        if writeFails { throw MockError(description: "write refused") }
        files[path] = data
        writtenPaths.append(path)
    }

    func removeFile(atPath path: String) throws {
        if removeFails { throw MockError(description: "unlink refused") }
        files.removeValue(forKey: path)
        removedPaths.append(path)
    }
}

// MARK: - size_str

final class RNCopySizeStrTests: XCTestCase {

    func testBaseUnitNoDecimals() {
        // Python: size_str(512) == '512 B'  (rncp.py:898-899 — the empty-unit branch)
        XCTAssertEqual(RNCopyApp.sizeStr(512), "512 B")
        XCTAssertEqual(RNCopyApp.sizeStr(0), "0 B")
        XCTAssertEqual(RNCopyApp.sizeStr(999), "999 B")
    }

    func testPrefixedUnitsTwoDecimals() {
        // Python: '%.2f %s%s', divisor 1000 (SI), never 1024.
        XCTAssertEqual(RNCopyApp.sizeStr(1000), "1.00 KB")
        XCTAssertEqual(RNCopyApp.sizeStr(1536), "1.54 KB")
        XCTAssertEqual(RNCopyApp.sizeStr(1_000_000), "1.00 MB")
        XCTAssertEqual(RNCopyApp.sizeStr(1_500_000_000), "1.50 GB")
    }

    func testBitSuffixMultipliesByEight() {
        // Python: if suffix == 'b': num *= 8  (rncp.py:891-892)
        XCTAssertEqual(RNCopyApp.sizeStr(125, suffix: "b"), "1.00 Kb")
        XCTAssertEqual(RNCopyApp.sizeStr(100, suffix: "b"), "800 b")
        // Python composes rate strings as size_str(v, "b") + "ps" (rncp.py:582).
        XCTAssertEqual(RNCopyApp.speedStr(125), "1.00 Kbps")
    }

    func testOverflowBranchHasNoSpace() {
        // Python: return "%.2f%s%s" — the ONE branch with no space before the unit.
        // Verified against the real helper: size_str(1e27) == '1000.00YB'.
        let rendered = RNCopyApp.sizeStr(1e27)
        XCTAssertEqual(rendered, "1000.00YB")
        XCTAssertFalse(rendered.contains(" "), "the yotta branch omits the space")
        // This is the single place rncp's size_str diverges from RNSUtilities.prettysize.
        XCTAssertNotEqual(rendered, RNSUtilities.prettysize(1e27))
    }

    func testTransferStatLine() {
        // Python: stat_str = f"{percent}% - {ps} of {ts} - {ss}ps{phy_str}" (rncp.py:583)
        XCTAssertEqual(
            RNCopyApp.transferStat(progress: 0.5, totalSize: 2000, speed: 125),
            "50.0% - 1.00 KB of 2.00 KB - 1.00 Kbps")
        // -P adds " (<rate>ps at physical layer)" (rncp.py:577)
        XCTAssertEqual(
            RNCopyApp.transferStat(progress: 1.0, totalSize: 1000, speed: 125, phySpeed: 250),
            "100.0% - 1.00 KB of 1.00 KB - 1.00 Kbps (2.00 Kbps at physical layer)")
        // The fetch completion line inserts " in <prettytime>" (rncp.py:590)
        XCTAssertEqual(
            RNCopyApp.transferStat(progress: 1.0, totalSize: 1000, speed: 125, elapsed: 2),
            "100.0% - 1.00 KB of 1.00 KB in \(RNSUtilities.prettytime(2)) - 1.00 Kbps")
    }
}

// MARK: - Path helpers

final class RNCopyPathHelperTests: XCTestCase {

    func testBasenamePosixRule() {
        // Python posixpath.basename is p[p.rfind('/')+1:] — no backslash handling.
        XCTAssertEqual(RNCopyApp.basename("a/b/c.txt"), "c.txt")
        XCTAssertEqual(RNCopyApp.basename("c.txt"), "c.txt")
        XCTAssertEqual(RNCopyApp.basename("a/b/"), "")
        XCTAssertEqual(RNCopyApp.basename(""), "")
        // This is what neutralises a hostile filename in the received metadata.
        XCTAssertEqual(RNCopyApp.basename("../../etc/passwd"), "passwd")
        XCTAssertEqual(RNCopyApp.basename("a\\b.txt"), "a\\b.txt")
    }

    func testExpandUserOnlyLeadingTilde() {
        XCTAssertEqual(RNCopyApp.expandUser("~/x", home: "/h"), "/h/x")
        XCTAssertEqual(RNCopyApp.expandUser("~", home: "/h"), "/h")
        XCTAssertEqual(RNCopyApp.expandUser("a/~/b", home: "/h"), "a/~/b")
        XCTAssertEqual(RNCopyApp.expandUser("/abs", home: "/h"), "/abs")
    }

    func testAbsolutePathLexical() {
        // Python: os.path.abspath == normpath(join(cwd, path)); purely lexical.
        XCTAssertEqual(RNCopyApp.absolutePath("a/../b", cwd: "/c"), "/c/b")
        XCTAssertEqual(RNCopyApp.absolutePath("/x/./y/", cwd: "/c"), "/x/y")
        // Verified against Python: os.path.abspath('/x/../..') == '/'
        XCTAssertEqual(RNCopyApp.absolutePath("/x/../..", cwd: "/c"), "/")
        // Verified against Python: os.path.abspath('/s/..') == '/'; abspath('/s/') == '/s'
        XCTAssertEqual(RNCopyApp.absolutePath("/s/..", cwd: "/c"), "/")
        XCTAssertEqual(RNCopyApp.absolutePath("/s/", cwd: "/c"), "/s")
    }
}

// MARK: - Metadata

final class RNCopyMetadataTests: XCTestCase {

    func testEncodeMatchesUmsgpackGoldenBytes() {
        // Golden from the installed Python:
        //   RNS.vendor.umsgpack.packb({"name": b"test.txt"}).hex()
        //   == '81a46e616d65c408746573742e747874'
        XCTAssertEqual(RNCopyApp.encodeMetadata(name: "test.txt"),
                       Data(hex: "81a46e616d65c408746573742e747874"))
    }

    func testDecodeRoundTrip() {
        let name = "ünïcode file.bin"
        XCTAssertEqual(RNCopyApp.decodeMetadataName(RNCopyApp.encodeMetadata(name: name)), name)
    }

    func testDecodeAcceptsStringValue() {
        // Python requires a bin (it calls .decode("utf-8")); tolerating a str keeps a peer
        // that used one interoperable.
        let packed = MsgPack.encode(.map([(.string("name"), .string("a.txt"))]))
        XCTAssertEqual(RNCopyApp.decodeMetadataName(packed), "a.txt")
    }

    func testDecodeRejectsGarbage() {
        XCTAssertNil(RNCopyApp.decodeMetadataName(Data([0xFF])))
        XCTAssertNil(RNCopyApp.decodeMetadataName(MsgPack.encode(.array([]))))
        XCTAssertNil(RNCopyApp.decodeMetadataName(MsgPack.encode(.map([(.string("other"), .bytes(Data()))]))))
    }
}

// MARK: - Wire constants

final class RNCopyPathHashTests: XCTestCase {

    func testFetchFilePathHash() {
        // Python: hashlib.sha256(b"fetch_file").hexdigest()[:32]
        XCTAssertEqual(RNCopyApp.fetchRequestPathHash.hexString, "4ce505754cbdc8c2c8775a3006a712f0")
        XCTAssertEqual(RNCopyApp.fetchRequestPath, "fetch_file")
    }

    func testDestinationNameHash() {
        // Python: name_hash = sha256("rncp.receive")[:10] → full name rncp.receive.<id hash>
        XCTAssertEqual(
            Destination.computeNameHash(appName: RNCopyApp.appName,
                                        aspects: [RNCopyApp.receiveAspect]).hexString,
            "3e4bcdfc941d6f4fc33e")
    }

    func testDestinationHexLength() {
        // Python: dest_len = (RNS.Reticulum.TRUNCATED_HASHLENGTH//8)*2 == 32
        XCTAssertEqual(RNCopyApp.destinationHexLength, 32)
    }

    func testSpinnerAndEraseConstants() {
        // Python: syms = "⢄⢂⢁⡁⡈⡐⡠" (rncp.py:403), erase_str = "\33[2K\r" (rncp.py:73)
        XCTAssertEqual(RNCopyApp.spinnerFrames.count, 7)
        XCTAssertEqual(String(RNCopyApp.spinnerFrames), "\u{2884}\u{2882}\u{2881}\u{2841}\u{2848}\u{2850}\u{2860}")
        XCTAssertEqual(RNCopyApp.eraseString, "\u{1B}[2K\r")
        XCTAssertEqual(RNCopyApp.endSpace, " ")
        // Python: stats_max = 32 (rncp.py:325)
        XCTAssertEqual(RNCopyApp.statsMax, 32)
    }
}

// MARK: - Allowed identities

final class RNCopyAllowedIdentitiesTests: XCTestCase {

    func testParseKeepsOnly32CharLines() {
        // Python: af.read().replace("\r","").split("\n"), keep len(a) == dest_len.
        let good = String(repeating: "a", count: 32)
        let contents = "# comment\r\n" + good + "\n\n" + String(repeating: "b", count: 31)
        XCTAssertEqual(RNCopyApp.parseAllowedIdentitiesFile(contents), [good])
    }

    func testDecodeRejectsWrongLength() {
        XCTAssertThrowsError(try RNCopyApp.decodeAllowedIdentity("abc")) { error in
            guard let error = error as? RNCopyApp.AllowedIdentityError else {
                return XCTFail("wrong error type")
            }
            guard case .invalidLength = error else { return XCTFail("expected .invalidLength") }
            // Python: "Allowed destination length is invalid, must be {hex} hexadecimal
            //          characters ({byte} bytes)." with hex=32, byte=16 (rncp.py:159)
            XCTAssertEqual(error.message,
                           "Allowed destination length is invalid, must be 32 hexadecimal characters (16 bytes).")
        }
    }

    func testDecodeRejectsNonHex() {
        XCTAssertThrowsError(try RNCopyApp.decodeAllowedIdentity(String(repeating: "z", count: 32))) { error in
            guard let error = error as? RNCopyApp.AllowedIdentityError else {
                return XCTFail("wrong error type")
            }
            guard case .invalidHex = error else { return XCTFail("expected .invalidHex") }
            // Python: "Invalid destination entered. Check your input." (rncp.py:164)
            XCTAssertEqual(error.message, "Invalid destination entered. Check your input.")
        }
    }

    func testDecodeAccepts32Hex() throws {
        XCTAssertEqual(try RNCopyApp.decodeAllowedIdentity("00112233445566778899aabbccddeeff").count, 16)
    }

    func testDestinationArgumentSharesTheSameRules() {
        // Python literally repeats the same block for the `destination` positional
        // (rncp.py:377-387, 622-632).
        XCTAssertThrowsError(try RNCopyApp.decodeDestinationArgument("nope"))
        XCTAssertNoThrow(try RNCopyApp.decodeDestinationArgument("00112233445566778899aabbccddeeff"))
    }

    func testSearchOrderIsEtcThenXdgThenDotDir() {
        // Python: /etc/rncp → ~/.config/rncp → ~/.rncp, first hit wins (rncp.py:126-131).
        XCTAssertEqual(RNCopyApp.allowedIdentitiesSearchPaths(home: "/h"),
                       ["/etc/rncp/allowed_identities",
                        "/h/.config/rncp/allowed_identities",
                        "/h/.rncp/allowed_identities"])
    }

    // MARK: File load / merge

    private func allowListFS(_ path: String, _ body: String) -> MockRNCopyFileSystem {
        MockRNCopyFileSystem(home: "/h", cwd: "/cwd", files: [path: Data(body.utf8)])
    }

    func testFileEntriesReplaceAnEmptyCommandLineList() {
        let a = String(repeating: "a", count: 32)
        let fs = allowListFS("/h/.rncp/allowed_identities", a)
        let load = RNCopyApp.loadAllowedIdentities(commandLineEntries: [], fileSystem: fs)
        // Python: if not allowed: allowed = ali  (rncp.py:141-142)
        XCTAssertEqual(load.merged, [a])
        XCTAssertEqual(load.fileEntryCount, 1)
        XCTAssertEqual(load.sourcePath, "/h/.rncp/allowed_identities")
        XCTAssertEqual(load.logMessage, "Loaded 1 allowed identity from /h/.rncp/allowed_identities")
    }

    func testFileEntriesExtendANonEmptyCommandLineList() {
        let a = String(repeating: "a", count: 32)
        let b = String(repeating: "b", count: 32)
        let fs = allowListFS("/h/.rncp/allowed_identities", b)
        let load = RNCopyApp.loadAllowedIdentities(commandLineEntries: [a], fileSystem: fs)
        // Python: else: allowed.extend(ali)  (rncp.py:143-144)
        XCTAssertEqual(load.merged, [a, b])
        XCTAssertEqual(load.logMessage, "Loaded 1 allowed identity from /h/.rncp/allowed_identities")
    }

    func testEtcCandidateWinsOverHomeCandidates() {
        let a = String(repeating: "a", count: 32)
        let b = String(repeating: "b", count: 32)
        let fs = MockRNCopyFileSystem(home: "/h", cwd: "/cwd", files: [
            "/etc/rncp/allowed_identities": Data(a.utf8),
            "/h/.config/rncp/allowed_identities": Data(b.utf8),
            "/h/.rncp/allowed_identities": Data(b.utf8)
        ])
        let load = RNCopyApp.loadAllowedIdentities(commandLineEntries: [], fileSystem: fs)
        XCTAssertEqual(load.sourcePath, "/etc/rncp/allowed_identities")
        XCTAssertEqual(load.merged, [a])
    }

    func testLogLineIsEmittedEvenWhenTheFileYieldsNothing() {
        // Python emits the "Loaded N allowed identities" line for ANY located file, including
        // one whose every line was dropped by the length filter — with the plural "ies".
        let fs = allowListFS("/h/.rncp/allowed_identities", "# only a comment\n")
        let load = RNCopyApp.loadAllowedIdentities(commandLineEntries: [], fileSystem: fs)
        XCTAssertEqual(load.fileEntryCount, 0)
        XCTAssertEqual(load.logMessage, "Loaded 0 allowed identities from /h/.rncp/allowed_identities")
        XCTAssertNil(load.failure)
    }

    func testNoFileMeansNoLogLine() {
        let load = RNCopyApp.loadAllowedIdentities(commandLineEntries: ["x"],
                                                   fileSystem: MockRNCopyFileSystem())
        XCTAssertNil(load.sourcePath)
        XCTAssertNil(load.logMessage)
        XCTAssertEqual(load.merged, ["x"])
    }

    func testReadFailureIsReportedButDoesNotExit() {
        // Python catches every exception, logs it at ERROR and carries on with the -a list.
        final class UnreadableFS: MockRNCopyFileSystem {
            override func readFile(atPath path: String) throws -> Data {
                throw MockError(description: "boom")
            }
        }
        let fs = UnreadableFS(home: "/h", cwd: "/cwd",
                              files: ["/h/.rncp/allowed_identities": Data()])
        let load = RNCopyApp.loadAllowedIdentities(commandLineEntries: ["x"], fileSystem: fs)
        XCTAssertEqual(load.failure, "boom")
        XCTAssertEqual(load.merged, ["x"])
    }

    func testRepeatedOptionCollection() {
        // argparse `-a` is action="append"; the shared parser has no append action, so the
        // executable collects occurrences itself.
        let argv = ["-a", "aa", "-l", "-a", "bb", "--", "-a", "cc"]
        XCTAssertEqual(RNCopyApp.collectRepeatedOption("-a", in: argv), ["aa", "bb"])
    }
}

// MARK: - Fetch jail

final class RNCopyFetchJailTests: XCTestCase {

    func testNoJailResolvesAbsolute() {
        let fs = MockRNCopyFileSystem(home: "/h", filePaths: ["/h/a.txt"])
        XCTAssertEqual(RNCopyApp.resolveFetchPath(requested: "~/a.txt", jail: nil, fileSystem: fs),
                       .serve(path: "/h/a.txt"))
    }

    func testNoJailAllowsAnyReadablePath() {
        // Python: without a jail the client may request ANY absolute path (rncp.py:184-185).
        let fs = MockRNCopyFileSystem(filePaths: ["/etc/passwd"])
        XCTAssertEqual(RNCopyApp.resolveFetchPath(requested: "/etc/passwd", jail: nil, fileSystem: fs),
                       .serve(path: "/etc/passwd"))
    }

    func testJailStripsPrefixOccurrences() {
        let fs = MockRNCopyFileSystem(filePaths: ["/j/sub/x"])
        XCTAssertEqual(RNCopyApp.resolveFetchPath(requested: "/j/sub/x", jail: "/j", fileSystem: fs),
                       .serve(path: "/j/sub/x"))
    }

    func testJailEscapeReturnsNotAllowed() {
        let fs = MockRNCopyFileSystem(filePaths: ["/etc/passwd"])
        // "../etc/passwd" → abspath("/j/../etc/passwd") == "/etc/passwd", outside the jail.
        XCTAssertEqual(RNCopyApp.resolveFetchPath(requested: "../etc/passwd", jail: "/j", fileSystem: fs),
                       .notAllowed(path: "/etc/passwd"))
        // A leading ".." that climbs out of the jail after the join also escapes.
        XCTAssertEqual(RNCopyApp.resolveFetchPath(requested: "/../etc/passwd", jail: "/j", fileSystem: fs),
                       .notAllowed(path: "/etc/passwd"))
    }

    func testBareAbsolutePathIsRebasedUnderTheJailNotRejected() {
        // Quirk worth pinning down: a request that does NOT start with "<jail>/" is joined
        // under the jail regardless, so "/etc/passwd" becomes abspath("/j//etc/passwd")
        // == "/j/etc/passwd" — inside the jail, hence "not found" rather than "not allowed".
        // Confirmed against Python's fetch_request (rncp.py:177-183).
        let fs = MockRNCopyFileSystem(filePaths: ["/etc/passwd"])
        XCTAssertEqual(RNCopyApp.resolveFetchPath(requested: "/etc/passwd", jail: "/j", fileSystem: fs),
                       .notFound(path: "/j/etc/passwd"))
    }

    func testJailedMissingFileReturnsNotFound() {
        let fs = MockRNCopyFileSystem()
        XCTAssertEqual(RNCopyApp.resolveFetchPath(requested: "a.txt", jail: "/j", fileSystem: fs),
                       .notFound(path: "/j/a.txt"))
    }

    func testReplaceAllSemantics() {
        // Python: data.replace(fetch_jail+"/", "") is a replace-ALL, not a prefix strip.
        // Verified against Python: '/j//j/x'.replace('/j/', '') == 'x',
        // so file_path = abspath('/j/' + 'x') == '/j/x'.
        let fs = MockRNCopyFileSystem(filePaths: ["/j/x"])
        XCTAssertEqual(RNCopyApp.resolveFetchPath(requested: "/j//j/x", jail: "/j", fileSystem: fs),
                       .serve(path: "/j/x"))
    }
}

// MARK: - Save target

final class RNCopySaveTargetTests: XCTestCase {

    func testNoSavePathIsRelative() {
        // Python: saved_filename = filename — a RELATIVE path, so the file lands in the CWD.
        let fs = MockRNCopyFileSystem()
        XCTAssertEqual(RNCopyApp.resolveSaveTarget(filename: "a.txt", savePath: nil,
                                                   allowOverwrite: false, fileSystem: fs),
                       .write(path: "a.txt", unlinkFirst: nil))
    }

    func testSavePathContainment() {
        let fs = MockRNCopyFileSystem()
        // Python: abspath("/s" + "/" + "..") == "/", which does not start with "/s/".
        XCTAssertEqual(RNCopyApp.resolveSaveTarget(filename: "..", savePath: "/s",
                                                   allowOverwrite: false, fileSystem: fs),
                       .rejected(path: "/"))
        // Python: abspath("/s" + "/" + "") == "/s", which also does not start with "/s/".
        XCTAssertEqual(RNCopyApp.resolveSaveTarget(filename: "", savePath: "/s",
                                                   allowOverwrite: false, fileSystem: fs),
                       .rejected(path: "/s"))
    }

    func testSavePathAcceptsPlainName() {
        let fs = MockRNCopyFileSystem()
        XCTAssertEqual(RNCopyApp.resolveSaveTarget(filename: "a.txt", savePath: "/s",
                                                   allowOverwrite: false, fileSystem: fs),
                       .write(path: "/s/a.txt", unlinkFirst: nil))
    }

    func testRenameCounter() {
        // Python: while os.path.isfile(...): counter += 1; full = saved + "." + str(counter)
        let fs = MockRNCopyFileSystem(filePaths: ["/s/a.txt", "/s/a.txt.1"])
        XCTAssertEqual(RNCopyApp.resolveSaveTarget(filename: "a.txt", savePath: "/s",
                                                   allowOverwrite: false, fileSystem: fs),
                       .write(path: "/s/a.txt.2", unlinkFirst: nil))
    }

    func testOverwriteUnlinksFirst() {
        let fs = MockRNCopyFileSystem(filePaths: ["/s/a.txt"])
        XCTAssertEqual(RNCopyApp.resolveSaveTarget(filename: "a.txt", savePath: "/s",
                                                   allowOverwrite: true, fileSystem: fs),
                       .write(path: "/s/a.txt", unlinkFirst: "/s/a.txt"))
        XCTAssertEqual(fs.removedPaths, ["/s/a.txt"])
    }

    func testOverwriteFailureFallsBackToRename() {
        // Python logs "Could not overwrite existing file …, renaming instead" and falls
        // through to the counter loop.
        let fs = MockRNCopyFileSystem(filePaths: ["/s/a.txt"])
        fs.removeFails = true
        var reported: String?
        XCTAssertEqual(RNCopyApp.resolveSaveTarget(filename: "a.txt", savePath: "/s",
                                                   allowOverwrite: true, fileSystem: fs,
                                                   onOverwriteFailure: { reported = $0 }),
                       .write(path: "/s/a.txt.1", unlinkFirst: nil))
        XCTAssertEqual(reported, "/s/a.txt")
    }

    func testSaveDirectoryValidation() {
        // Python: isdir → W_OK → save_path; else exit 4; not a dir → exit 3 (rncp.py:96-108).
        let fs = MockRNCopyFileSystem(home: "/h", cwd: "/cwd", files: [:],
                                      directories: ["/s", "/ro"], nonWritableDirectories: ["/ro"])
        XCTAssertEqual(RNCopyApp.resolveSaveDirectory("/s", fileSystem: fs), .ok(path: "/s"))
        XCTAssertEqual(RNCopyApp.resolveSaveDirectory("/ro", fileSystem: fs), .notWritable)
        XCTAssertEqual(RNCopyApp.resolveSaveDirectory("/nope", fileSystem: fs), .notFound)
    }

    func testSaveHelperCollapsesHostileName() {
        // The metadata name goes through basename() first, so "../../etc/passwd" can only
        // ever land as "passwd" inside the save directory.
        let fs = MockRNCopyFileSystem()
        let result = RNCopyApp.saveReceivedResource(
            payload: Data("x".utf8),
            metadata: RNCopyApp.encodeMetadata(name: "../../etc/passwd"),
            savePath: "/s", allowOverwrite: false, fileSystem: fs)
        XCTAssertEqual(try? result.get(), "/s/passwd")
    }

    func testSaveHelperReportsMissingMetadata() {
        let fs = MockRNCopyFileSystem()
        let result = RNCopyApp.saveReceivedResource(payload: Data(), metadata: nil,
                                                    savePath: nil, allowOverwrite: false,
                                                    fileSystem: fs)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .missingMetadata)
    }

    func testSaveHelperReportsMissingNameKeyLikePythonKeyError() {
        // Python raises KeyError('name'), reported as
        // "An error occurred while saving received resource: 'name'".
        let fs = MockRNCopyFileSystem()
        let result = RNCopyApp.saveReceivedResource(payload: Data(),
                                                    metadata: MsgPack.encode(.map([])),
                                                    savePath: nil, allowOverwrite: false,
                                                    fileSystem: fs)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error.exceptionText, "'name'")
    }
}

// MARK: - Progress meter

final class RNCopyProgressMeterTests: XCTestCase {

    func testZeroSpanYieldsZeroSpeeds() {
        // Python: if span == 0: speed = 0; phy_speed = 0 (rncp.py:340-342)
        var meter = RNCopyProgressMeter()
        meter.update(now: 100, got: 500, phyGot: 900)
        XCTAssertEqual(meter.speed, 0)
        XCTAssertEqual(meter.phySpeed, 0)
        meter.update(now: 100, got: 900, phyGot: 1800)
        XCTAssertEqual(meter.speed, 0)
        XCTAssertEqual(meter.phySpeed, 0)
    }

    func testSpeedIsWindowDelta() {
        var meter = RNCopyProgressMeter()
        meter.update(now: 0, got: 0, phyGot: 0)
        meter.update(now: 2, got: 1000, phyGot: 2000)
        XCTAssertEqual(meter.speed, 500, accuracy: 0.0001)
        XCTAssertEqual(meter.phySpeed, 1000, accuracy: 0.0001)
    }

    func testWindowCapsAt32() {
        // Python: while len(stats) > stats_max: stats.pop(0) — 40 updates keep the last 32,
        // so the span is measured from sample 8, not sample 0.
        var meter = RNCopyProgressMeter()
        for index in 0..<40 {
            meter.update(now: TimeInterval(index), got: Double(index) * 100, phyGot: Double(index) * 200)
        }
        XCTAssertEqual(meter.sampleCount, 32)
        // Window is samples 8…39: span 31 s, delta 3100 bytes → 100 B/s.
        XCTAssertEqual(meter.speed, 100, accuracy: 0.0001)
        XCTAssertEqual(meter.phySpeed, 200, accuracy: 0.0001)
    }

    func testNonPositivePhyDiffLeavesPhySpeedUnchanged() {
        // Python: `if phy_diff > 0:` — otherwise phy_speed keeps its previous value
        // rather than being zeroed (rncp.py:348-350).
        var meter = RNCopyProgressMeter()
        meter.update(now: 0, got: 0, phyGot: 400)
        meter.update(now: 1, got: 100, phyGot: 800)   // phy_diff = 400 over 1 s
        XCTAssertEqual(meter.phySpeed, 400, accuracy: 0.0001)
        // Window head is still (t=0, phy=400), so phy_diff is now 0 — Python's
        // `if phy_diff > 0:` leaves phy_speed at its previous value instead of zeroing it,
        // while the application-layer speed keeps being recomputed.
        meter.update(now: 2, got: 200, phyGot: 400)
        XCTAssertEqual(meter.phySpeed, 400, accuracy: 0.0001)
        XCTAssertEqual(meter.speed, 100, accuracy: 0.0001)
    }
}

// MARK: - Fetch response classification

final class RNCopyFetchStatusTests: XCTestCase {

    func testClassifyBoolFalseIsNotFound() {
        // Python: if request_receipt.response == False: "not_found" (rncp.py:463)
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(MsgPack.encode(.bool(false))), .notFound)
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(Data([0xC2])), .notFound)
    }

    func testClassifyIntZeroIsNotFound() {
        // Python treats 0 == False, so an integer zero also lands in "not_found".
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(MsgPack.encode(.uint(0))), .notFound)
    }

    func testClassifyNilIsRemoteError() {
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(Data([0xC0])), .remoteError)
    }

    func testClassify0xF0IsFetchNotAllowed() {
        // Python: umsgpack.packb(0xF0) == cc f0
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(Data([0xCC, 0xF0])), .fetchNotAllowed)
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(MsgPack.encode(.uint(240))), .fetchNotAllowed)
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(MsgPack.encode(.int(240))), .fetchNotAllowed)
    }

    func testClassifyTrueIsFound() {
        // True == 1 never equals 240, so it falls through to "found".
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(Data([0xC3])), .found)
    }

    func testClassifyUndecodableIsFound() {
        // Must not crash; Python's else-branch is "found".
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(Data([0xC1])), .found)
        XCTAssertEqual(RNCopyApp.classifyFetchResponse(Data()), .found)
    }

    func testRawValuesMatchPythonStrings() {
        XCTAssertEqual(RNCopyFetchStatus.notFound.rawValue, "not_found")
        XCTAssertEqual(RNCopyFetchStatus.remoteError.rawValue, "remote_error")
        XCTAssertEqual(RNCopyFetchStatus.fetchNotAllowed.rawValue, "fetch_not_allowed")
        XCTAssertEqual(RNCopyFetchStatus.unknown.rawValue, "unknown")
        XCTAssertEqual(RNCopyFetchStatus.found.rawValue, "found")
    }
}

// MARK: - Identity bootstrap

final class RNCopyIdentityTests: XCTestCase {

    private var storage: URL!

    override func setUpWithError() throws {
        storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("rncp-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storage)
    }

    func testDefaultIdentityPath() {
        // Python: RNS.Reticulum.identitypath + "/" + APP_NAME, where identitypath is
        // <configdir>/storage/identities.
        XCTAssertEqual(RNCopyApp.defaultIdentityPath(storagePath: URL(fileURLWithPath: "/s")).path,
                       "/s/identities/rncp")
    }

    func testPrepareIdentityCreatesAndReloads() throws {
        let first = try RNCopyApp.prepareIdentity(storagePath: storage)
        let path = RNCopyApp.defaultIdentityPath(storagePath: storage)
        // Python writes the raw 64-byte private key blob (X25519 || Ed25519), no header.
        let bytes = try Data(contentsOf: path)
        XCTAssertEqual(bytes.count, 64)

        let second = try RNCopyApp.prepareIdentity(storagePath: storage)
        XCTAssertEqual(first.hexHash, second.hexHash)
    }

    func testCorruptIdentityFileThrows() throws {
        let path = RNCopyApp.defaultIdentityPath(storagePath: storage)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data([0x01, 0x02, 0x03]).write(to: path)

        XCTAssertThrowsError(try RNCopyApp.prepareIdentity(storagePath: storage)) { error in
            guard let error = error as? RNCopyApp.IdentityError else {
                return XCTFail("wrong error type")
            }
            XCTAssertEqual(error, .corruptIdentityFile(path.path))
            // Python: RNS.log(f"Could not load identity for rncp. The identity file at
            //          \"{identity_path}\" may be corrupt or unreadable.") then exit(2)
            XCTAssertEqual(error.message,
                           "Could not load identity for rncp. The identity file at \"\(path.path)\" may be corrupt or unreadable.")
        }
    }
}

// MARK: - Exit codes, log level, CLI surface

final class RNCopyExitCodeTests: XCTestCase {

    func testResultRawValues() {
        XCTAssertEqual(RNCopyApp.Result.ok.rawValue, 0)
        XCTAssertEqual(RNCopyApp.Result.generalError.rawValue, 1)
        XCTAssertEqual(RNCopyApp.Result.identityError.rawValue, 2)
        XCTAssertEqual(RNCopyApp.Result.outputDirNotFound.rawValue, 3)
        XCTAssertEqual(RNCopyApp.Result.outputDirNotWritable.rawValue, 4)
    }

    func testLogLevelFormula() {
        // Python: targetloglevel = 3 + verbosity - quietness; 3 == RNS.LOG_NOTICE.
        XCTAssertEqual(RNCopyApp.logLevel(verbosity: 0, quietness: 0), .notice)
        XCTAssertEqual(RNCopyApp.logLevel(verbosity: 2, quietness: 0), .verbose)
        XCTAssertEqual(RNCopyApp.logLevel(verbosity: 0, quietness: 1), .warning)
        // Clamped into the LogLevel range (-1…8).
        XCTAssertEqual(RNCopyApp.logLevel(verbosity: 0, quietness: 99), .none)
        XCTAssertEqual(RNCopyApp.logLevel(verbosity: 99, quietness: 0), .extreme)
    }
}

final class RNCopyHelpTextTests: XCTestCase {

    /// Byte-for-byte against `rncp --help` captured from the installed Python utility.
    func testHelpTextMatchesArgparseOutput() {
        let expected = """
        usage: rncp [-h] [--config path] [-v] [-q] [-S] [-l] [-C] [-F] [-f] [-j path]
                    [-s path] [-O] [-b seconds] [-a allowed_hash] [-n] [-p]
                    [-i identity] [-w seconds] [-P] [--version]
                    [file] [destination]

        Reticulum File Transfer Utility

        positional arguments:
          file                  file to be transferred
          destination           hexadecimal hash of the receiver

        options:
          -h, --help            show this help message and exit
          --config path         path to alternative Reticulum config directory
          -v, --verbose         increase verbosity
          -q, --quiet           decrease verbosity
          -S, --silent          disable transfer progress output
          -l, --listen          listen for incoming transfer requests
          -C, --no-compress     disable automatic compression
          -F, --allow-fetch     allow authenticated clients to fetch files
          -f, --fetch           fetch file from remote listener instead of sending
          -j path, --jail path  restrict fetch requests to specified path
          -s path, --save path  save received files in specified path
          -O, --overwrite       Allow overwriting received files, instead of adding
                                postfix
          -b seconds            announce interval, 0 to only announce at startup
          -a allowed_hash       allow this identity (or add in
                                ~/.rncp/allowed_identities)
          -n, --no-auth         accept requests from anyone
          -p, --print-identity  print identity and destination info and exit
          -i identity           path to identity to use
          -w seconds            sender timeout before giving up
          -P, --phy-rates       display physical layer transfer rates
          --version             show program's version number and exit
        """
        XCTAssertEqual(RNCopyApp.helpText, expected)
    }

    func testParserAcceptsEveryDocumentedFlag() throws {
        let parser = RNCopyApp.makeArgumentParser()
        let parsed = try parser.parse([
            "remote.txt", "00112233445566778899aabbccddeeff",
            "--config", "/cfg", "-vv", "-q", "-S", "-l", "-C", "-F", "-f",
            "-j", "/jail", "-s", "/save", "-O", "-b", "30",
            "-a", "00112233445566778899aabbccddeeff", "-n", "-p",
            "-i", "/id", "-w", "5", "-P"
        ])
        XCTAssertEqual(parsed.positionals, ["remote.txt", "00112233445566778899aabbccddeeff"])
        XCTAssertEqual(parsed.value("--config"), "/cfg")
        XCTAssertEqual(parsed.count("--verbose"), 2)
        XCTAssertEqual(parsed.count("--quiet"), 1)
        XCTAssertTrue(parsed.flag("--silent"))
        XCTAssertTrue(parsed.flag("--listen"))
        XCTAssertTrue(parsed.flag("--no-compress"))
        XCTAssertTrue(parsed.flag("--allow-fetch"))
        XCTAssertTrue(parsed.flag("--fetch"))
        XCTAssertEqual(parsed.value("--jail"), "/jail")
        XCTAssertEqual(parsed.value("--save"), "/save")
        XCTAssertTrue(parsed.flag("--overwrite"))
        XCTAssertEqual(parsed.int("-b"), 30)
        XCTAssertTrue(parsed.flag("--no-auth"))
        XCTAssertTrue(parsed.flag("--print-identity"))
        XCTAssertEqual(parsed.value("-i"), "/id")
        XCTAssertEqual(parsed.double("-w"), 5)
        XCTAssertTrue(parsed.flag("--phy-rates"))
    }

    func testDefaultsMatchArgparse() throws {
        let parser = RNCopyApp.makeArgumentParser()
        let parsed = try parser.parse([])
        // Python: -b default=-1, -w default=RNS.Transport.PATH_REQUEST_TIMEOUT (15).
        XCTAssertEqual(parsed.int("-b"), -1)
        XCTAssertEqual(parsed.double("-w"), Transport.pathRequestTimeout)
        XCTAssertTrue(parsed.positionals.isEmpty)
        XCTAssertFalse(parsed.flag("--listen"))
    }

    func testLimitFlagIsNotImplemented() throws {
        // `--limit` is commented out upstream in both the parser and the listen() call.
        let parser = RNCopyApp.makeArgumentParser()
        XCTAssertThrowsError(try parser.parse(["--limit", "3"]))
    }
}
