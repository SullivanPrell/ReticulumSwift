import XCTest
@testable import ReticulumSwift

/// The path table routes by interface identity, not by interface name — `bugs/027`.
///
/// The reference stores the interface **object** in the path table and transmits through it
/// (`Transport.py:1639`, `:1693`), stringifying it only for display (`Reticulum.py:1532`).
/// Interface names are not unique by design: every connection accepted by one listening
/// interface is named `"Client on <server name>"` (`TCPInterface.py:590`), which this port
/// mirrors deliberately. Python can afford that because it never looks an interface up by name.
///
/// This port stored `nextHopInterfaceName` and resolved it with
/// `interfaces.first(where: { $0.name == … })`, so with two clients on one listening interface
/// every route resolved to whichever client was registered first — regardless of which one
/// actually heard the announce. Silent: the send succeeds and the packet goes to the wrong peer,
/// while the path table insists it has a route.
///
/// **Why no existing test could fail.** Every one attaches a single client, where
/// `first(where:)` is accidentally correct. A second client is the whole test.
final class PathTableInterfaceIdentityTests: XCTestCase {

    /// Records what it was asked to send. Two of these share one `name`, exactly as Python's
    /// spawned `"Client on <server>"` interfaces do.
    private final class RecordingInterface: Interface {
        let name: String
        let label: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []
        /// Announces are relayed to sibling interfaces, so total sends are noise. Routing is
        /// only ever a claim about where the *data* went.
        var dataSent: [Packet] { sent.filter { $0.packetType == .data } }

        init(name: String, label: String) { self.name = name; self.label = label }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    private func announcedDestination(_ aspect: String) throws -> (Destination, Packet) {
        let identity = Identity()
        let destination = try Destination(identity: identity, direction: .in, kind: .single,
                                          appName: "test", aspects: [aspect])
        return (destination, try Announce.make(for: destination))
    }

    private func dataPacket(to destination: Destination, _ body: String) -> Packet {
        Packet(destinationType: .single, packetType: .data,
               destinationHash: destination.hash, data: Data(body.utf8))
    }

    // MARK: - Two clients on one listening interface route independently

    /// Spec: "Two clients on one listening interface route independently."
    func testAPathLearnedViaTheSecondClientLeavesThroughTheSecondClient() throws {
        let transport = Transport()

        // Registered in this order, so a `first(where:)` on the shared name yields clientA.
        let clientA = RecordingInterface(name: "Client on hub", label: "A")
        let clientB = RecordingInterface(name: "Client on hub", label: "B")
        transport.register(interface: clientA)
        transport.register(interface: clientB)

        // A destination heard on clientB, and only on clientB.
        let (peer, announce) = try announcedDestination("identity-routing")
        clientB.inboundHandler?(announce, clientB)
        XCTAssertNotNil(transport.paths[peer.hash],
                        "the announce heard on clientB must install a path")

        // Now route to it. Nothing about the send says which client to use except the path.
        _ = try? transport.send(dataPacket(to: peer, "routed by identity"))

        XCTAssertEqual(clientB.dataSent.count, 1,
                       "the packet must leave through clientB, which is where the destination "
                       + "was heard")
        XCTAssertEqual(clientA.dataSent.count, 0,
                       "the packet left through clientA — the name-keyed lookup picked whichever "
                       + "client registered first, not the one that heard the announce")
    }

    /// The same defect from the other side: the *first*-registered client is not privileged, so
    /// learning via clientA must not start routing through clientB either.
    func testAPathLearnedViaTheFirstClientLeavesThroughTheFirstClient() throws {
        let transport = Transport()
        let clientA = RecordingInterface(name: "Client on hub", label: "A")
        let clientB = RecordingInterface(name: "Client on hub", label: "B")
        transport.register(interface: clientA)
        transport.register(interface: clientB)

        let (peer, announce) = try announcedDestination("identity-routing-first")
        clientA.inboundHandler?(announce, clientA)
        _ = try? transport.send(dataPacket(to: peer, "routed by identity"))

        XCTAssertEqual(clientA.dataSent.count, 1, "the packet must leave through clientA")
        XCTAssertEqual(clientB.dataSent.count, 0, "the packet must not leave through clientB")
    }

    /// Spec: "Route resolution does not depend on the display string."
    ///
    /// `Interface.hash` is `fullHash(displayName)`, so anything keyed on the display string moves
    /// when the string moves. Routing must not notice: the reference routes on the object.
    func testARouteSurvivesADisplayNameChange() throws {
        let transport = Transport()
        let client = RenamableInterface(name: "Client on hub")
        transport.register(interface: client)

        let (peer, announce) = try announcedDestination("display-name-change")
        client.inboundHandler?(announce, client)
        XCTAssertNotNil(transport.paths[peer.hash])

        // Renaming is an output-formatting change, not a routing event.
        client.displayNameOverride = "Client on hub/198.51.100.7:41000"

        _ = try? transport.send(dataPacket(to: peer, "still routable"))
        XCTAssertEqual(client.dataSent.count, 1,
                       "the route must still resolve after the published name changed")
    }

    private final class RenamableInterface: Interface {
        let name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var displayNameOverride: String?
        private(set) var sent: [Packet] = []
        var dataSent: [Packet] { sent.filter { $0.packetType == .data } }

        init(name: String) { self.name = name }
        var displayName: String { displayNameOverride ?? "RenamableInterface[\(name)]" }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    /// Spec: "Path display still names the interface" (`Reticulum.py:1532`).
    func testPathListingStillNamesTheInterface() throws {
        let transport = Transport()
        let client = RecordingInterface(name: "Client on hub", label: "only")
        transport.register(interface: client)

        let (peer, announce) = try announcedDestination("path-display")
        client.inboundHandler?(announce, client)

        XCTAssertEqual(transport.nextHopInterfaceName(for: peer.hash), client.name,
                       "a path listing must name the interface the route uses, as the reference "
                       + "does when it stringifies the stored object for display")
    }

    // MARK: - The structural guard

    /// No production code builds a path from an interface *name*.
    ///
    /// `PathEntry` keeps a name-only initialiser for table-bookkeeping tests and for the moment
    /// before persistence resolves a stored interface hash — such a path is deliberately not
    /// routable. But a production site reaching for it would silently create an unroutable
    /// route, and re-adding a name fallback to compensate is how `bugs/013` came back three
    /// times. So the assignment form is pinned, the way D7 pins `$HOME` resolution.
    func testNoProductionCodeBuildsAPathFromAnInterfaceName() throws {
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")

        var offences: [String] = []
        let walker = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let src = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in src.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else {
                    continue
                }
                // The declaration of the initialiser itself, and the display-name field, are not
                // constructions. A construction passes a value.
                guard code.contains("nextHopInterfaceName:"),
                      !code.contains("public var"), !code.contains("public let"),
                      !code.contains("self.nextHopInterfaceName"),
                      !code.hasSuffix("nextHopInterfaceName: String,"),
                      // The routable initialiser derives the display name from the object it was
                      // handed; that forwarding call is the correct form, not an offence.
                      !code.contains("nextHopInterfaceName: nextHopInterface" + ".name"),
                      !code.contains("path.nextHopInterfaceName,"),
                      !code.contains("entry.nextHopInterfaceName,")
                else { continue }
                offences.append("  \(url.lastPathComponent):\(index + 1) — \(code)")
            }
        }

        XCTAssertTrue(offences.isEmpty,
                      """
                      \(offences.count) production site(s) build a path table entry from an \
                      interface name:
                      \(offences.joined(separator: "\n"))
                      Names are not unique — every client of one listening interface shares one \
                      (TCPInterface.py:590) — so a name-built path is not routable, and routing \
                      has no name fallback by design. Pass the interface: \
                      `PathEntry(destinationHash:nextHopInterface:…)`.
                      """)
    }

    // MARK: - A vanished interface is not a routing target

    /// Spec: "A vanished client does not remain a routing target" — the deregistration half.
    /// A route through a client that is gone must stop resolving rather than silently falling
    /// back to a sibling that shares its name.
    func testARouteThroughADeregisteredClientDoesNotFallBackToItsSibling() throws {
        let transport = Transport()
        let clientA = RecordingInterface(name: "Client on hub", label: "A")
        let clientB = RecordingInterface(name: "Client on hub", label: "B")
        transport.register(interface: clientA)
        transport.register(interface: clientB)

        let (peer, announce) = try announcedDestination("vanished-client")
        clientB.inboundHandler?(announce, clientB)
        transport.deregister(interface: clientB)

        _ = try? transport.send(dataPacket(to: peer, "b is gone"))

        XCTAssertEqual(clientA.dataSent.count, 0,
                       "clientB is gone, so this destination has no route — handing the packet "
                       + "to a same-named sibling sends it to the wrong peer, which is the defect "
                       + "rather than a fallback")
    }
}
