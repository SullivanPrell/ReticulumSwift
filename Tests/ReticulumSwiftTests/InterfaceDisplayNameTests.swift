import XCTest
@testable import ReticulumSwift

/// `bugs/022` — every interface must publish the name its Python counterpart's `__str__`
/// produces, because `Interface.hash` is `fullHash(displayName)` and `rnstatus` filters and
/// hides rows by prefix. A bare configuration name is a different identity on the wire than
/// the Python interface sitting beside it.
///
/// This suite exists in this shape because the 1.7.0 fix covered the TCP/UDP families only and
/// the rest came straight back (`bugs/013` → `bugs/022`). It enumerates
/// `InterfaceConformers.everyConcreteInterface()` rather than a hand-listed subset, and a
/// conformer with no entry in the expectation table below is a **failure**, not a skip — so a
/// type added next month cannot escape the requirement by never being listed.
final class InterfaceDisplayNameTests: XCTestCase {

    /// The published form for each conformer, against the Python `__str__` it must match.
    ///
    /// Returns `nil` for a conformer with no entry, which the test reports as a coverage
    /// failure. Every entry cites the reference line it is transcribed from.
    private func expectedDisplayName(for iface: any Interface,
                                     among all: [any Interface]) -> String? {
        /// Python brackets an IPv6 literal before joining (`TCPInterface.py:457-460`).
        func ipString(_ host: String) -> String { host.contains(":") ? "[\(host)]" : host }

        switch iface {

        // MARK: – Class-qualified bare name: `Class[name]`

        case let i as AutoInterface:
            // AutoInterface.py:609
            return "AutoInterface[\(i.name)]"
        case let i as AX25KISSInterface:
            // AX25KISSInterface.py:400-401
            return "AX25KISSInterface[\(i.name)]"
        case let i as I2PInterface:
            // I2PInterface.py:890
            return "I2PInterface[\(i.name)]"
        case let i as I2PInterfacePeer:
            // I2PInterface.py:713-714
            return "I2PInterfacePeer[\(i.name)]"
        case let i as KISSInterface:
            // KISSInterface.py:387-388
            return "KISSInterface[\(i.name)]"
        case let i as RNodeInterface:
            // RNodeInterface.py:1247-1248
            return "RNodeInterface[\(i.name)]"
        case let i as RNodeMultiInterface:
            // RNodeMultiInterface.py:923-924
            return "RNodeMultiInterface[\(i.name)]"
        case let i as SerialInterface:
            // SerialInterface.py:226-227
            return "SerialInterface[\(i.name)]"
        case let i as WeaveInterface:
            // WeaveInterface.py:1005-1006
            return "WeaveInterface[\(i.name)]"
        case let i as BLEMeshInterface:
            // No Python counterpart — BLEMesh is Swift-only. Held to the same class-qualified
            // shape so it cannot become the one interface that publishes a bare name.
            return "BLEMeshInterface[\(i.name)]"

        // MARK: – Forms with a peer address in the tail

        case let i as BackboneInterface:
            // BackboneInterface.py:870-873 (the connecting form; Swift's BackboneInterface
            // dials a host and has no listener class, so this is the one that applies).
            return "BackboneInterface[\(i.name)/\(ipString(i.host)):\(i.port)]"
        case let i as TCPServerClientInterface:
            // A spawned client is a plain TCPClientInterface in Python
            // (TCPInterface.py:591), so it publishes that class's form
            // (TCPInterface.py:456-462) with the peer address in the tail.
            return "TCPInterface[\(i.name)/\(ipString(i.peerHost)):\(i.peerPort)]"
        case let i as TCPClientInterface:
            // TCPInterface.py:456-462 — note the string is "TCPInterface[…]", not the
            // Swift/Python class name "TCPClientInterface".
            return "TCPInterface[\(i.name)/\(ipString(i.host)):\(i.port)]"
        case let i as TCPServerInterface:
            // TCPInterface.py:680-686
            return "TCPServerInterface[\(i.name)/\(ipString(i.bindIP)):\(i.port)]"
        case let i as UDPInterface:
            // UDPInterface.py:131-132
            let port = i.listenPort ?? i.forwardPort ?? 0
            return "UDPInterface[\(i.name)/\(ipString(i.bindIP)):\(port)]"

        // MARK: – Forms that ignore `name` entirely

        case let i as LocalInterface:
            // LocalInterface.py:372-374 — the port, not the name.
            return "LocalInterface[\(i.port)]"
        case let i as PosixTCPServer:
            // Swift's PosixTCPServer is Python's LocalServerInterface, whose __str__ is
            // "Shared Instance[<bind_port>]" (LocalInterface.py:496-498) — a literal,
            // independent of `name`. Python hardcodes name = "Reticulum" (:391), so a Swift
            // form built from `name` only matches while the caller happens to pass
            // "Shared Instance".
            return "Shared Instance[\(i.port)]"

        // MARK: – Forms derived from a parent or a peer address

        case let i as RNodeSubInterface:
            // RNodeMultiInterface.py:1152-1153 — the *parent's* name, then the sub's own.
            // Resolved from the registry so this does not hardcode the parent's name.
            let parent = all.compactMap { $0 as? RNodeMultiInterface }.first
            guard let parentName = parent?.name else {
                XCTFail("Registry constructs no RNodeMultiInterface for the sub-interface to "
                        + "hang off; the expected form cannot be derived")
                return nil
            }
            return "\(parentName)[\(i.name)]"
        case let i as WeaveInterfacePeer:
            // WeaveInterface.py:1022-1023 — `RNS.hexrep(endpoint_addr)`, which is
            // colon-delimited by default (RNS/__init__.py:176-183).
            return "WeaveInterfacePeer[\(RNSUtilities.hexrep(i.endpointAddr))]"

        default:
            return nil
        }
    }

    func testEveryConformerPublishesThePythonDisplayName() throws {
        let all = try InterfaceConformers.everyConcreteInterface()

        var unmapped: [String] = []
        var mismatches: [String] = []

        for iface in all {
            let typeName = String(describing: type(of: iface))
            guard let expected = expectedDisplayName(for: iface, among: all) else {
                unmapped.append(typeName)
                continue
            }
            if iface.displayName != expected {
                mismatches.append("  \(typeName): published \"\(iface.displayName)\", "
                                  + "Python publishes \"\(expected)\"")
            }
        }

        XCTAssertTrue(unmapped.isEmpty,
                      """
                      Conformer(s) with no entry in the expectation table: \(unmapped.sorted()).
                      Add the Python `__str__` form, with the reference file:line it comes from.
                      An unlisted type is a coverage hole, not a pass — that hole is how
                      bugs/022 survived the 1.7.0 fix.
                      """)

        XCTAssertTrue(mismatches.isEmpty,
                      """
                      \(mismatches.count) interface(s) publish a name Python does not:
                      \(mismatches.joined(separator: "\n"))
                      `Interface.hash` is fullHash(displayName), so each of these is a different
                      interface identity on the wire than the Python interface beside it, and
                      rnstatus' prefix filters do not match it.
                      """)
    }

    /// The other half of "enforceable rather than defaulted": whatever the default is, it may
    /// not be the bare configuration name. A new conformer that declares nothing must still
    /// publish something class-qualified.
    func testNoConformerPublishesABareConfigurationName() throws {
        let bare = try InterfaceConformers.everyConcreteInterface()
            .filter { $0.displayName == $0.name }
            .map { "\(type(of: $0))(name: \"\($0.name)\")" }

        XCTAssertTrue(bare.isEmpty,
                      """
                      Interface(s) publishing their bare configuration name: \(bare.sorted()).
                      Python's `__str__` is class-qualified for every interface it ships; a bare
                      name is both the wrong hash and invisible to rnstatus' class filters.
                      """)
    }
}
