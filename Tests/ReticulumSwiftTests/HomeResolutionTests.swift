import XCTest
@testable import ReticulumSwift

/// `bugs/024` — `$HOME` must determine every home-relative path, as `os.path.expanduser("~")`
/// does for the reference (`Reticulum.py:165`, `:234`, `:236`).
///
/// The 1.7.0 release fixed this and announced "all resolution". It fixed *one* resolver. Two
/// utilities still called `homeDirectoryForCurrentUser`, `rncp`'s allow-list still called
/// `NSHomeDirectory()`, and eleven `expandingTildeInPath` sites across five utilities still
/// resolved every user-supplied `~` against the account's real home. All of them are macOS APIs
/// that ignore `$HOME` by design.
///
/// The consequence was not theoretical: a Swift utility launched with `HOME` pointing at a
/// scratch directory read the developer's real `~/.reticulum`, found the live daemon's identity,
/// and authenticated to the live daemon on 37428 — while the harness believed it was sandboxed.
///
/// The structural test below is the one that would have caught it, and it is a coverage admission
/// rather than a behavioural check (design D7). Every behavioural home test in this package
/// injects the home it wants, so none can observe what a real invocation resolves.
final class HomeResolutionTests: XCTestCase {

    // MARK: - The shared resolver

    func testHomeDirectoryPrefersHOMEOverThePlatformHome() {
        let relocated = "/tmp/rns-home-probe"
        XCTAssertEqual(InstanceConnection.homeDirectory(environment: ["HOME": relocated]).path,
                       relocated)
    }

    /// The one sanctioned exception, which must keep working (`InstanceConnection.swift:116`).
    func testUnsetHOMEFallsBackToThePlatformHome() {
        XCTAssertEqual(InstanceConnection.homeDirectory(environment: [:]).path, NSHomeDirectory())
        // An empty HOME is falsy in Python too — `os.path.expanduser` ignores it.
        XCTAssertEqual(InstanceConnection.homeDirectory(environment: ["HOME": ""]).path,
                       NSHomeDirectory())
    }

    // MARK: - Tilde expansion

    func testExpandTildeHonoursHOME() {
        let env = ["HOME": "/tmp/rns-home-probe"]
        XCTAssertEqual(InstanceConnection.expandTilde("~", environment: env),
                       "/tmp/rns-home-probe")
        XCTAssertEqual(InstanceConnection.expandTilde("~/.reticulum", environment: env),
                       "/tmp/rns-home-probe/.reticulum")
        XCTAssertEqual(InstanceConnection.expandTilde("~/a/b", environment: env),
                       "/tmp/rns-home-probe/a/b")
    }

    func testExpandTildeMatchesExpanduserOnTheEdgeCases() {
        let env = ["HOME": "/tmp/slash/"]
        // No doubled separator. CPython: `userhome.rstrip('/') + path[i:]`.
        XCTAssertEqual(InstanceConnection.expandTilde("~/x", environment: env), "/tmp/slash/x")
        // Repeated trailing slashes are all stripped, not just one.
        XCTAssertEqual(InstanceConnection.expandTilde("~/x", home: "/tmp/slash//"), "/tmp/slash/x")
        // A root home does not produce a doubled leading slash.
        XCTAssertEqual(InstanceConnection.expandTilde("~/x", home: "/"), "/x")
        XCTAssertEqual(InstanceConnection.expandTilde("~", home: "/tmp/keep/"), "/tmp/keep/")
        // Not a tilde path: unchanged.
        XCTAssertEqual(InstanceConnection.expandTilde("/abs/path", environment: env), "/abs/path")
        XCTAssertEqual(InstanceConnection.expandTilde("relative/path", environment: env),
                       "relative/path")
        XCTAssertEqual(InstanceConnection.expandTilde("", environment: env), "")
        // `~user` is CPython's pwd-database lookup, which RNS never uses — left alone rather
        // than silently resolved to $HOME.
        XCTAssertEqual(InstanceConnection.expandTilde("~root/x", environment: env), "~root/x")
        // A tilde that is not leading is not special.
        XCTAssertEqual(InstanceConnection.expandTilde("/a/~/b", environment: env), "/a/~/b")
    }

    /// The whole point, stated against the API it replaces: `expandingTildeInPath` disagrees with
    /// `$HOME`, and that disagreement is the defect.
    func testExpandTildeDisagreesWithThePlatformExpansionUnderARelocatedHOME() {
        let relocated = "/tmp/rns-home-probe"
        let ours = InstanceConnection.expandTilde("~/.reticulum",
                                                  environment: ["HOME": relocated])
        let platform = ("~/.reticulum" as NSString).expandingTildeInPath
        XCTAssertEqual(ours, relocated + "/.reticulum")
        XCTAssertNotEqual(ours, platform,
                          "If these agree the probe is not measuring anything — the relocated "
                          + "HOME must differ from the account's real home")
    }

    // MARK: - `rncp`'s allow-list (task 2.7)

    /// `rncp` reads its identity store and its `~/.rncp` allow-list from the home directory.
    /// Applying the wrong allow-list silently accepts identities the operator never authorised
    /// for that environment, or refuses the ones they did, behind a normal-looking banner.
    func testRNCopyFileSystemHomeFollowsHOME() {
        let relocated = "/tmp/rns-home-probe"
        let fs = RNCopyDiskFileSystem(environment: ["HOME": relocated])
        XCTAssertEqual(fs.homeDirectoryPath, relocated,
                       """
                       RNCopyDiskFileSystem resolved the account's real home. It called \
                       NSHomeDirectory() (RNCopySupport.swift:419), which ignores $HOME, so \
                       rncp's allow-list came from the wrong environment (bugs/024).
                       """)
    }

    func testRNCopyFileSystemStillFallsBackWhenHOMEIsUnset() {
        XCTAssertEqual(RNCopyDiskFileSystem(environment: [:]).homeDirectoryPath,
                       NSHomeDirectory())
    }

    // MARK: - The structural guard (task 2.9)

    /// Fails on any platform home-directory API or non-`$HOME`-aware tilde expansion in
    /// `Sources/`, outside the single sanctioned fallback.
    ///
    /// Unusual, and deliberately so (D7). This is the only form of check that would have caught
    /// this defect: every behavioural home test injects the home it wants, so none can observe
    /// what a real invocation resolves — which is exactly how a release claiming to have fixed
    /// "all resolution" shipped with fourteen sites still wrong.
    func testNoSourceFileReachesAPlatformHomeAPI() throws {
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ReticulumSwiftTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Sources")

        let banned = [
            "NSHomeDirectory(":
                "reports the account's real home regardless of $HOME — use "
                + "DaemonBootstrap.homeDirectory()",
            "homeDirectoryForCurrentUser":
                "reports the account's real home regardless of $HOME, and is macOS-only — use "
                + "DaemonBootstrap.homeDirectory()",
            "expandingTildeInPath":
                "expands ~ against the account's real home, not $HOME — use "
                + "DaemonBootstrap.expandTilde(_:)",
        ]

        /// The documented fallback for `HOME` unset, and the only exception. It must keep
        /// working: `homeDirectoryForCurrentUser` was deliberately *not* used there because it is
        /// macOS-only and this type ships in the library for iOS, tvOS and watchOS too.
        let sanctionedFile = "InstanceConnection.swift"

        var offences: [String] = []
        let files = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let src = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in src.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                // These names are cited constantly in comments explaining why they are banned.
                guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else {
                    continue
                }
                for (pattern, why) in banned where code.contains(pattern) {
                    // One sanctioned fallback: the `NSHomeDirectory()` return in the resolver.
                    if url.lastPathComponent == sanctionedFile, pattern == "NSHomeDirectory(" {
                        continue
                    }
                    offences.append("  \(url.lastPathComponent):\(index + 1) — \(pattern) \(why)\n"
                                    + "      \(code)")
                }
            }
        }

        XCTAssertTrue(offences.isEmpty,
                      """
                      \(offences.count) site(s) resolve a home path without honouring $HOME:
                      \(offences.joined(separator: "\n"))
                      Python resolves every one of these through os.path.expanduser, which returns
                      $HOME when set. A utility that ignores it reads and writes the account's real
                      ~/.reticulum under a relocated HOME — and, finding the live daemon's identity
                      there, attaches to the live daemon. There is exactly one sanctioned
                      exception: the unset-HOME fallback in \(sanctionedFile).
                      """)
    }

    /// The sanctioned exception is sanctioned *once*. If a second one appears the guard above
    /// keeps passing while the invariant erodes, so the count is pinned.
    func testTheSanctionedFallbackIsASingleSite() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ReticulumSwift/Utilities/InstanceConnection.swift")
        let occurrences = try String(contentsOf: file, encoding: .utf8)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") }
            .filter { $0.contains("NSHomeDirectory(") }
        XCTAssertEqual(occurrences.count, 1,
                       "Expected exactly one sanctioned NSHomeDirectory() call, found "
                       + "\(occurrences.count): \(occurrences)")
    }
}
