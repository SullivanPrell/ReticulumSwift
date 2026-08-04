import XCTest
@testable import ReticulumSwift

/// `Reticulum.version` is what every `rn*` tool prints for `--version`, what `rnsd` logs at
/// startup and what the RetiOS About screen shows. Its doc comment says "bump this on every
/// release", and it was left at 1.9.0 across three releases — so a 1.10.2 build introduced
/// itself as 1.9.0 everywhere.
///
/// It survived because **every existing test interpolates the constant it is checking**:
/// `XCTAssertFalse(Reticulum.version.isEmpty)`, `Reticulum.version.split(separator: ".")`, and a
/// log-format test that builds its expected string from `Reticulum.version` itself. All six pass
/// for any value, including a stale one. A version test that cannot detect staleness is not a
/// version test.
///
/// So this compares the constant against something outside the source: the newest released
/// heading in `CHANGELOG.md`, which a release has to touch anyway.
final class VersionConstantTests: XCTestCase {

    /// The newest `## [x.y.z]` heading in the CHANGELOG, ignoring `## [Unreleased]`.
    private func newestReleasedHeading() throws -> String {
        // #filePath is this file inside the package, so the package root is three levels up
        // (Tests/ReticulumSwiftTests/<file>).
        let changelog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CHANGELOG.md")
        let text = try String(contentsOf: changelog, encoding: .utf8)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("## [") else { continue }
            let inner = line.dropFirst(4).prefix { $0 != "]" }
            if inner == "Unreleased" { continue }
            return String(inner)
        }
        throw XCTSkip("no released version heading found in CHANGELOG.md")
    }

    func testTheVersionConstantMatchesTheNewestReleasedChangelogHeading() throws {
        let heading = try newestReleasedHeading()
        XCTAssertEqual(Reticulum.version, heading,
                       """
                       `Reticulum.version` is \(Reticulum.version) while the newest released \
                       CHANGELOG heading is \(heading). One of them is wrong, and every tool \
                       that prints a version is reporting the constant — which is how three \
                       releases shipped introducing themselves as 1.9.0.
                       """)
    }

    /// The protocol version is a *different* contract — the Python RNS release whose wire
    /// behaviour the port matches — and must not be quietly dragged along by a library bump.
    func testTheProtocolVersionIsNotTheLibraryVersion() {
        XCTAssertNotEqual(Reticulum.version, Reticulum.rnsProtocolVersion,
                          "the library version and the RNS protocol version advance "
                          + "independently; if they have been made equal, one of them was "
                          + "probably edited by mistake")
    }
}
