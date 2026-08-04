import XCTest
@testable import ReticulumSwift

/// The round trip that would have caught the whole of `bugs/030`: generate the port's own
/// example config, feed it back to the parser, and assert every key it emits is a key the
/// parser reads and applies (design D8).
///
/// Spec: `interface-configuration` — "The generated config template makes no promise it does
/// not keep". Advertising a control that is silently ignored is worse than omitting it,
/// because an absent key fails visibly and an ignored one does not.
///
/// Why this shape. The existing guard for this exact path,
/// `RNSConfigTemplatesTests.testExampleConfigRoundTripsThroughParser`, asserts the interface
/// *names* the template declares and three booleans. It passes identically whether the parser
/// understands four keys or twenty-four, so it cannot fail for the reason `bugs/030` predicts —
/// the D10 pathology, in the very test named "round trips through parser".
///
/// The key list here is derived mechanically from `RNSConfigTemplates` rather than written out,
/// so a key added to a template cannot escape the check by nobody remembering to list it.
final class ConfigTemplateRoundTripTests: XCTestCase {

    // MARK: - Extracting what the templates actually emit

    /// One `key = value` line in a template, with the section it belongs to.
    private struct TemplateKey: Hashable {
        let section: String     // "reticulum", "logging", or "" for an interface subsection
        let key: String
        var qualified: String { section.isEmpty ? "interface.\(key)" : "\(section).\(key)" }
    }

    /// Every `key = value` the two templates emit, **commented or not**.
    ///
    /// Commented keys count. The spec says so explicitly, and the reason is that a commented
    /// directive in an example config is not a comment — it is documentation of a supported
    /// control, which a user uncomments. `RNSConfigTemplatesTests` currently reasons the other
    /// way round ("They are commented out, so nothing parses them"), which is precisely the
    /// premise D8 rejects.
    private func templateKeys() -> (top: Set<TemplateKey>, interface: Set<String>,
                                    interfaceTypes: Set<String>) {
        var top: Set<TemplateKey> = []
        var interface: Set<String> = []
        var types: Set<String> = []

        for blob in [RNSConfigTemplates.exampleConfig, RNSConfigTemplates.defaultConfig] {
            var section = ""
            var inInterfaceBlock = false

            for rawLine in blob.components(separatedBy: .newlines) {
                // A commented directive is still a directive; strip the marker, not the line.
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                    .drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }

                if line.hasPrefix("[[") && line.hasSuffix("]]") {
                    inInterfaceBlock = true
                    continue
                }
                if line.hasPrefix("[") && line.hasSuffix("]") {
                    section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                    inInterfaceBlock = false
                    continue
                }

                guard let eq = line.range(of: "=") else { continue }
                let key = String(line[line.startIndex..<eq.lowerBound])
                    .trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
                // Prose that happens to contain "=" is not a directive.
                guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
                else { continue }

                if inInterfaceBlock {
                    if key == "type" { types.insert(value) } else { interface.insert(key) }
                } else if !section.isEmpty {
                    top.insert(TemplateKey(section: section, key: key))
                }
            }
        }
        return (top, interface, types)
    }

    // MARK: - The primary gate: nothing emitted is discarded

    /// Every top-level key either template emits must be one the parser recognises.
    ///
    /// This is the assertion with no coverage hole in it: the parser reports what it discarded,
    /// so a key nobody thought to probe still fails here.
    func testTemplatesEmitNoKeyTheParserDiscards() {
        var discarded: [String] = []

        for (label, blob) in [("example", RNSConfigTemplates.exampleConfig),
                              ("default", RNSConfigTemplates.defaultConfig)] {
            // Parse the template with every commented directive uncommented, so the documented
            // controls are exercised as a user who uncomments them would exercise them.
            let uncommented = blob.components(separatedBy: .newlines).map { line -> String in
                let stripped = line.trimmingCharacters(in: .whitespaces)
                guard stripped.hasPrefix("#") else { return line }
                let body = stripped.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                // Only uncomment things that are actually `key = value` directives.
                guard let eq = body.range(of: "="),
                      case let key = String(body[body.startIndex..<eq.lowerBound])
                          .trimmingCharacters(in: .whitespaces),
                      !key.isEmpty,
                      key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
                else { return line }
                return body
            }.joined(separator: "\n")

            for key in ReticulumConfig.parse(uncommented).unrecognisedKeys {
                discarded.append("  \(key)  (\(label) config)")
            }
        }

        XCTAssertTrue(discarded.isEmpty, """
            \(discarded.count) key(s) the port's own config templates emit are silently \
            discarded by its parser:
            \(discarded.sorted().joined(separator: "\n"))
            Each is a control the generated config advertises and the daemon ignores. An
            operator who sets one gets no error, no warning and no effect. Either the parser
            reads it, or it stops being emitted (design D8).
            """)
    }

    // MARK: - Reading is not applying

    /// A key the parser recognises must also *land* somewhere: parsing a config that sets it
    /// must produce a different result from parsing one that does not.
    ///
    /// The gate above proves a branch matched the key. It cannot prove the branch did anything,
    /// and a branch that matches and discards is the same defect wearing a different hat.
    func testEveryTopLevelTemplateKeyChangesTheParsedResult() {
        var inert: [String] = []
        var unprobed: [String] = []

        for templateKey in templateKeys().top.sorted(by: { $0.qualified < $1.qualified }) {
            guard let probe = Self.probes[templateKey.qualified] else {
                unprobed.append("  \(templateKey.qualified)")
                continue
            }
            guard case .value(let probeValue) = probe else { continue }

            let baseline = ReticulumConfig.parse("[\(templateKey.section)]\n")
            let probed = ReticulumConfig.parse(
                "[\(templateKey.section)]\n\(templateKey.key) = \(probeValue)\n")

            if Self.dump(baseline, section: templateKey.section)
                == Self.dump(probed, section: templateKey.section) {
                inert.append("  \(templateKey.qualified) = \(probeValue)")
            }
        }

        XCTAssertTrue(unprobed.isEmpty, """
            \(unprobed.count) template key(s) have no probe value in this test:
            \(unprobed.joined(separator: "\n"))
            A key the templates emit that nothing here exercises is a coverage hole, not a pass.
            Add it to `probes` with a value that differs from the parser's default.
            """)

        XCTAssertTrue(inert.isEmpty, """
            \(inert.count) key(s) are recognised by the parser but change nothing:
            \(inert.joined(separator: "\n"))
            Setting each of these in a config file produces exactly the same parsed state as
            omitting it, so the control is advertised, matched, and dropped.
            """)
    }

    // MARK: - Interface blocks

    /// Every interface type the templates document must be one the config path can actually
    /// bring up.
    ///
    /// `synthesizeInterfaces` switches on `type` and falls through to `iface = nil` for anything
    /// it does not know — no throw, no log. So an operator who enables a documented interface
    /// block gets a daemon that starts, reports healthy, and does not have that interface. That
    /// is this change's defect class exactly, applied to the interface the operator cares most
    /// about: the radio.
    ///
    /// Asserted structurally, against the `case` labels of the switch itself. Driving
    /// `synthesizeInterfaces` for real would bind sockets and open serial ports for the types
    /// that *do* construct, which is a high price for an answer the switch states plainly.
    ///
    /// **Skipped against `bugs/031`, not deleted.** It failed on first run naming
    /// `RNodeInterface`, `KISSInterface`, `AX25KISSInterface` and `I2PInterface`. Closing it needs
    /// config-string → transport factories (`ble://` and `/dev/tty…` → `RNodeTransport`, and the
    /// serial families are desktop-only while BLE is not), which is a design decision rather than
    /// four switch cases — so it was scoped out of `fix-013-defect-class-core` deliberately.
    /// Removing the assertion would have left the finding in a session transcript. Deleting the
    /// skip is the RED gate for the fix.
    func testEveryInterfaceTypeTheTemplatesDocumentCanBeBroughtUp() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/ReticulumSwift/Reticulum.swift"),
            encoding: .utf8)

        // The body of `synthesizeInterfaces`, so a `case "RNodeInterface"` belonging to some
        // other switch in the file cannot be mistaken for config-path support.
        guard let start = source.range(of: "public func synthesizeInterfaces(from cfg:") else {
            return XCTFail("synthesizeInterfaces not found — this guard has stopped guarding")
        }
        let body = source[start.lowerBound...].prefix(while: { _ in true })
        let end = body.range(of: "\n    // MARK: - Path and interface queries")
            ?? body.range(of: "\n    }\n\n    // MARK:")
        let switchBody = String(body[body.startIndex..<(end?.lowerBound ?? body.endIndex)])

        let unconstructible = templateKeys().interfaceTypes
            .filter { !switchBody.contains("\"\($0)\"") }
            .sorted()

        XCTAssertTrue(unconstructible.isEmpty, """
            \(unconstructible.count) interface type(s) the config templates document cannot be \
            constructed from a config file:
            \(unconstructible.map { "  \($0)" }.joined(separator: "\n"))
            `synthesizeInterfaces` has no case for these, so the block falls through to
            `iface = nil` and is skipped — no throw, no log. The daemon starts, reports healthy,
            and the interface simply is not there.
            """)
    }

    /// Every key an interface block emits must be read by something.
    ///
    /// Weaker than the top-level gate on purpose: interface keys are kept verbatim in
    /// `parameters`, so the parser discards nothing and "did the parser read it" is vacuously
    /// true. What matters is whether any construction path consults the key, which is a
    /// structural question — the same admission `HomeResolutionTests`' guard makes for `$HOME`.
    ///
    /// **Skipped against `bugs/031`**, for the same reason as the type check above: sixteen of the
    /// eighteen belong to the four types that cannot be constructed at all, so this cannot go
    /// green before that does. The two that do not — `device` on the constructible UDP and TCP
    /// server interfaces, which Python resolves to a named device's address — are recorded in
    /// `bugs/031` rather than split into a separate entry for two lines.
    func testEveryInterfaceBlockKeyIsConsultedBySomeConstructionPath() throws {
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ReticulumSwiftTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Sources")

        var sources = ""
        let files = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            // The templates themselves mention every key they emit; reading them back as
            // evidence that the key is consumed would make this test prove itself.
            guard url.lastPathComponent != "RNSConfigTemplates.swift" else { continue }
            sources += try String(contentsOf: url, encoding: .utf8)
        }

        let ignored: Set<String> = [
            // Handled structurally by the parser itself, not by a keyed lookup.
            "type", "enabled",
        ]

        let unread = templateKeys().interface
            .subtracting(ignored)
            .filter { !sources.contains("\"\($0)\"") }
            .sorted()

        XCTAssertTrue(unread.isEmpty, """
            \(unread.count) interface-block key(s) the config templates emit are read by \
            nothing in Sources/:
            \(unread.map { "  \($0)" }.joined(separator: "\n"))
            Each is documented in the config the port itself generates and has no reader, so
            configuring it has no effect of any kind.
            """)
    }

    // MARK: - Task 4.4: what the resolution had to be

    /// The templates stay byte-identical to Python's, so "stop emitting the key" was never an
    /// available resolution — every unimplemented key had to be implemented instead.
    ///
    /// Task 4.4 says to remove any key that remains unimplemented. Taken literally that would
    /// delete four interface blocks and eighteen keys from `exampleConfig`, breaking the
    /// byte-for-byte transcription of Python's `__example_rns_config__` that
    /// `RNSConfigTemplatesTests` pins with a SHA-256, a byte length and a newline count, and that
    /// the 1.7.0 CHANGELOG advertises as a parity win. The two instructions cannot both hold.
    ///
    /// They only conflict in one direction, though: Python implements every key Python emits, so
    /// as long as the templates *are* Python's, "implement it" is always the correct resolution
    /// and "remove it" would be a divergence. This test pins that reasoning so a later reader does
    /// not resolve 4.4 the other way.
    func testTheTemplatesRemainPythonsOwnBytes() {
        XCTAssertEqual(RNSConfigTemplates.exampleConfig.utf8.count, 15663,
                       "the example config is Python's literal; trimming keys from it is a "
                       + "divergence, not a fix (task 4.4)")
        for documented in ["rpc_key", "instance_name", "shared_instance_type", "network_identity"] {
            XCTAssertTrue(RNSConfigTemplates.exampleConfig.contains(documented),
                          "'\(documented)' was implemented in 4.2, so it stays documented")
        }
    }

    // MARK: - Probe table

    private enum Probe {
        /// Set the key to this value and require the parsed result to change.
        case value(String)
        /// The key is read, but its effect is not observable in the parsed structure.
        /// Carries why, so an exemption cannot be silent.
        case notObservableInParsedState(String)
    }

    /// A value per template key that differs from the parser's default for it.
    ///
    /// Hand-written, and guarded: a template key missing from this table fails
    /// `testEveryTopLevelTemplateKeyChangesTheParsedResult` as a coverage hole rather than
    /// being skipped.
    private static let probes: [String: Probe] = [
        "reticulum.enable_transport": .value("yes"),
        "reticulum.share_instance": .value("no"),
        "reticulum.instance_name": .value("alternate"),
        "reticulum.shared_instance_port": .value("47428"),
        "reticulum.instance_control_port": .value("47429"),
        "reticulum.shared_instance_type": .value("tcp"),
        "reticulum.rpc_key": .value("e5c032d3ec4e64a6aca9927ba8ab73336780f6d71790"),
        "reticulum.enable_remote_management": .value("yes"),
        "reticulum.network_identity": .value("~/.reticulum/storage/identity/network"),
        "reticulum.default_gravity": .value("7"),
        "reticulum.discover_interfaces": .value("yes"),
        "reticulum.interface_discovery_sources": .value("78616ff7c4b8d3886d67d494b440f333"),
        "reticulum.autoconnect_discovered_interfaces": .value("3"),
        "reticulum.required_discovery_value": .value("21"),
        "reticulum.panic_on_interface_error": .value("yes"),
        "reticulum.autoconnect_interface_mode": .value("gateway"),
        "reticulum.autoconnect_announces_to_internal": .value("yes"),
        "reticulum.autoconnect_interface_gravity": .value("5"),
        "reticulum.respond_to_probes": .value("yes"),
        "reticulum.publish_blackhole": .value("yes"),
        "reticulum.blackhole_sources": .value("521c87a83afb8f29e4455e77930b973b"),
        "reticulum.blackhole_update_interval": .value("90"),
        "reticulum.static_transport_identity": .value("yes"),
        "logging.loglevel": .value("6"),
        "logging.logtimestamps": .value("no"),

        // Python appends the raw hash bytes to its ACL (`Reticulum.py:545-552`); this port
        // resolves each hash to a known `Identity` first, so an entry for an identity the node
        // has not yet heard from lands nowhere. Probing it here would assert that resolution
        // failed, not that the key was read — so it is exempted, and the divergence recorded.
        "reticulum.remote_management_allowed":
            .notObservableInParsedState("resolves through Identity.recall, which needs a known identity"),
    ]

    /// `String(describing:)` of every stored property of one parsed section.
    ///
    /// Reflection rather than `Equatable` so a field added to `ReticulumSection` is compared
    /// without anyone updating this test — the same reason the key list is derived rather than
    /// listed.
    private static func dump(_ config: ReticulumConfig, section: String) -> String {
        let subject: Any = section == "logging" ? config.logging : config.reticulum
        return Mirror(reflecting: subject).children
            .map { "\($0.label ?? "?")=\(String(describing: $0.value))" }
            .joined(separator: "|")
    }
}
