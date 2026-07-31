import XCTest
@testable import ReticulumSwift

/// Guards the claim that there is exactly one place naming the files we persist.
///
/// `bugs/029` — four persisted files diverged from the reference in name *and* encoding for the
/// whole life of the port, under 3400 passing tests and a green interop suite. Nothing found them
/// because nothing could: each name was a string literal at its own call site, and no place in the
/// code held the claim "this is the set of files we persist." A test can compare an inventory
/// against the reference's; it cannot compare scattered literals.
final class StorageInventoryTests: XCTestCase {

    /// Components that name *where the config directory is*, not a file inside it. Resolving the
    /// config directory is `InstanceConnection`'s job and is already pinned by `HomeResolutionTests`.
    private static let configDirectoryDiscovery: Set<String> = [
        ".reticulum",
        ".config/reticulum",
    ]

    // MARK: - The guard

    func testEveryPersistedPathIsDeclared() throws {
        var undeclared: [String] = []
        let declared = StorageInventory.declaredComponents

        for site in try Self.pathComponentLiterals() {
            if declared.contains(site.literal) { continue }
            if Self.configDirectoryDiscovery.contains(site.literal) { continue }
            undeclared.append("  \(site.file):\(site.line) — \"\(site.literal)\"")
        }

        XCTAssertTrue(undeclared.isEmpty,
                      """
                      \(undeclared.count) site(s) name a config-directory path that \
                      `StorageInventory` does not declare:
                      \(undeclared.joined(separator: "\n"))
                      A persisted path composed at its call site cannot be compared against the \
                      reference's, which is how all four files in bugs/029 diverged unnoticed. \
                      Declare it in StorageInventory — with the Python file:line it mirrors, or \
                      an explicit reason if it is port-only — and resolve it from there.
                      """)
    }

    /// The inventory is only worth having if it is complete, so a declaration with no citation is
    /// as bad as an undeclared literal: it records a name without recording what makes it correct.
    func testEveryDeclarationCitesItsAuthority() {
        let uncited = StorageInventory.entries.filter { $0.authority.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertTrue(uncited.isEmpty,
                      "\(uncited.count) inventory entr(ies) carry no authority: "
                      + uncited.map(\.relativePath).joined(separator: ", ")
                      + ". Cite the Python file:line the name mirrors, or state that it is "
                      + "port-only and why — an undocumented divergence is the one outcome "
                      + "bugs/029 rules out.")
    }

    func testNoTwoEntriesResolveToTheSamePath() {
        let paths = StorageInventory.entries.map(\.relativePath)
        XCTAssertEqual(Set(paths).count, paths.count,
                       "two inventory entries resolve to the same path; "
                       + "the inventory must be a set of distinct files")
    }

    // MARK: - Source scan

    private struct Site {
        let file: String
        let line: Int
        let literal: String
    }

    /// Every `appendingPathComponent("literal")` in production sources, outside comments.
    ///
    /// Interpolated components are skipped: they name per-invocation temporaries (`rnid-<uuid>.tmp`)
    /// rather than a persisted path, and there is nothing stable to declare.
    private static func pathComponentLiterals() throws -> [Site] {
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")

        var sites: [Site] = []
        let walker = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            // The inventory is where these names are allowed to be written down.
            guard url.lastPathComponent != "StorageInventory.swift" else { continue }
            let src = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in src.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else {
                    continue
                }
                for literal in Self.literals(inCallsOn: code) {
                    guard !literal.contains("\\(") else { continue }
                    sites.append(Site(file: url.lastPathComponent,
                                      line: index + 1,
                                      literal: literal))
                }
            }
        }
        return sites
    }

    /// Extract each `"…"` passed directly to `appendingPathComponent` on one line.
    private static func literals(inCallsOn code: String) -> [String] {
        let marker = "appendingPathComponent(\""
        var found: [String] = []
        var search = code[...]
        while let start = search.range(of: marker) {
            let afterQuote = start.upperBound
            guard let closing = search[afterQuote...].firstIndex(of: "\"") else { break }
            found.append(String(search[afterQuote..<closing]))
            search = search[closing...]
        }
        return found
    }
}
