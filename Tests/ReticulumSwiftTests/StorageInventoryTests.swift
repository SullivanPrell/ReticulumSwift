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

    /// Nothing on disk bears a name the reference does not use.
    ///
    /// The guard above compares the *sources* against the inventory. This one compares the
    /// **filesystem** against it: a daemon runs against an empty directory, is exercised and
    /// stopped, and every path it left behind must be a declared entry — with a Python
    /// `file:line` behind it unless it is a declared divergence. A path composed somewhere the
    /// source scan cannot see (a computed name, a dependency, a future writer) shows up here and
    /// nowhere else.
    ///
    /// The live comparison against what a *Python* daemon writes from the same exercise is
    /// `tri-test/tests/test_state_roundtrip.py` (§4); this is its unit-level counterpart, and the
    /// two answer different questions — this one is about names we invent, that one about names
    /// the reference has that we do not.
    func testNoFileBearsANameTheReferenceDoesNotUse() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-created-set-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // A daemon that learns a path, an identity, a ratchet and a replay entry — so every
        // table has something to write, not just the directories.
        let rns = Reticulum(configuration: .init(storagePath: dir))
        try rns.start()
        let iface = LoopbackInterface(name: "created0")
        rns.transport.register(interface: iface)
        try installPersistablePath(on: rns.transport, through: iface, aspect: "createdset",
                                   ratchet: Data(repeating: 0x5A, count: 32))
        rns.transport.testInsertPacketHash(Hashes.fullHash(Hashes.randomHash()))
        rns.stop()

        let declared = Set(StorageInventory.Entry.all.map(\.relativePath))
        // The reference's own per-destination and per-source files live inside declared
        // directories under names that are hashes; the *directory* is the declared entry.
        let hashNamedContents: Set<String> = [
            StorageInventory.Entry.ratchets.relativePath,
            StorageInventory.Entry.announceCache.relativePath,
            StorageInventory.Entry.blackhole.relativePath,
            StorageInventory.Entry.identities.relativePath,
            StorageInventory.Entry.discoveredInterfaces.relativePath,
        ]

        var created: [String] = []
        // Resolved on both sides: on macOS the temporary directory is reached through the `/var`
        // symlink but the enumerator reports `/private/var`, so the prefix would never strip.
        let base = dir.resolvingSymlinksInPath().path + "/"
        let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            let resolved = url.resolvingSymlinksInPath().path
            guard resolved.hasPrefix(base) else {
                XCTFail("enumerated \(resolved), which is not under \(base)")
                continue
            }
            let relative = String(resolved.dropFirst(base.count))
            // `storagePath` *is* the storage directory here, so re-prefix to compare against the
            // inventory's config-directory-relative paths.
            let inventoryPath = StorageInventory.Entry.storage.relativePath + "/" + relative
            if declared.contains(inventoryPath) { continue }
            let parent = (inventoryPath as NSString).deletingLastPathComponent
            if hashNamedContents.contains(parent) { continue }
            created.append(relative)
        }

        XCTAssertTrue(created.isEmpty,
                      """
                      \(created.count) path(s) exist on disk that `StorageInventory` does not \
                      declare:
                      \(created.map { "  " + $0 }.joined(separator: "\n"))
                      A file the reference does not write is a compatibility defect even when \
                      nothing here reads it: a Python daemon pointed at the same directory has \
                      no idea what it is, and an operator diffing the two sides cannot tell it \
                      from state they should keep. Declare it — with the Python file:line, or as \
                      a divergence with its reason.
                      """)

        // And specifically none of the names this change retired. They are orphans by decision:
        // left alone if already present, never created again.
        for orphan in StorageInventory.preParityOrphans {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: dir.appendingPathComponent(orphan).path),
                "`\(orphan)` is a pre-parity name; nothing may write it again (bugs/029)")
        }
    }

    /// A declared divergence has to *be* declared as one. A port-only path recorded as if the
    /// reference backed it is the same undocumented divergence in a costume.
    func testPortOnlyEntriesAreMarkedRatherThanCitedAsReference() {
        let suspicious = StorageInventory.Entry.all.filter {
            guard case .reference(let cite) = $0.authority else { return false }
            return cite.lowercased().contains("port-only") || !cite.contains(".py")
        }
        XCTAssertTrue(suspicious.isEmpty,
                      "\(suspicious.map(\.relativePath)) claim a reference authority that is not "
                      + "a Python file:line. Use `.portOnly(reason:)` — a divergence recorded as "
                      + "parity is worse than one recorded as nothing.")
    }

    /// The inventory is only worth having if it is complete, so a declaration with no citation is
    /// as bad as an undeclared literal: it records a name without recording what makes it correct.
    func testEveryDeclarationCitesItsAuthority() {
        let uncited = StorageInventory.Entry.all.filter {
            $0.authority.citation.trimmingCharacters(in: .whitespaces).isEmpty
        }
        XCTAssertTrue(uncited.isEmpty,
                      "\(uncited.count) inventory entr(ies) carry no authority: "
                      + uncited.map(\.relativePath).joined(separator: ", ")
                      + ". Cite the Python file:line the name mirrors, or state that it is "
                      + "port-only and why — an undocumented divergence is the one outcome "
                      + "bugs/029 rules out.")
    }

    func testNoTwoEntriesResolveToTheSamePath() {
        let paths = StorageInventory.Entry.all.map(\.relativePath)
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
