import XCTest
@testable import ReticulumSwift

/// Shutdown tears links down before exiting — `bugs/028`.
///
/// The reference tears interfaces down first in both signal handlers (`Reticulum.py:196-205`
/// calling `Transport.py:3171-3183`): each established link is closed, the queue is allowed to
/// drain, then each interface is stopped. This port had that function, written correctly, with
/// **zero callers** — so a Swift node exiting cleanly emitted no `LINK_CLOSE` and every peer held
/// the link ACTIVE until its own keepalive watchdog expired, up to 360 s, with the LXMF, NomadNet
/// and LXST sessions riding those links hanging rather than failing.
///
/// **Why the obvious test does not help.** A test that calls `detachInterfaces()` directly and
/// asserts it works already passes — the function was never broken. The missing assertion is that
/// *stopping the stack reaches it*, which is what both tests here are about.
final class ShutdownTeardownTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shutdown-teardown-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// Delivers to its pair, and logs the order of what happened to it.
    ///
    /// The log, rather than a "was anything sent after stop?" flag, because Transport filters its
    /// broadcast on `isOnline` — a close emitted after the interface was stopped never reaches
    /// `send(_:)` at all, so its absence there is indistinguishable from a close that was never
    /// emitted. The sequence is the only thing that tells those apart.
    private final class PairedInterface: Interface {
        enum Event: Equatable { case sent(Packet.Context), stopped }

        let name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        weak var paired: PairedInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var log: [Event] = []

        var stopCount: Int { log.filter { $0 == .stopped }.count }

        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { log.append(.stopped); isOnline = false }
        func send(_ packet: Packet) throws {
            log.append(.sent(packet.context))
            let raw = try packet.pack()
            paired?.inboundHandler?(try Packet.unpack(raw), paired!)
        }
    }

    // MARK: - A peer observes the close promptly

    /// Spec: "A peer observes a link closing promptly" — and not after a keepalive watchdog
    /// timeout.
    func testStoppingAStackClosesItsLinksOnThePeer() throws {
        let aDir = tmpDir.appendingPathComponent("a")
        let bDir = tmpDir.appendingPathComponent("b")
        let rnsA = Reticulum(configuration: .init(storagePath: aDir))
        let rnsB = Reticulum(configuration: .init(storagePath: bDir))

        let aIface = PairedInterface(name: "a-side")
        let bIface = PairedInterface(name: "b-side")
        aIface.paired = bIface; bIface.paired = aIface
        rnsA.transport.register(interface: aIface)
        rnsB.transport.register(interface: bIface)
        try rnsA.start()
        try rnsB.start()
        defer { rnsB.stop() }

        let bIdentity = Identity()
        let bDest = try Destination(identity: bIdentity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["shutdown"])
        rnsB.transport.ownerIdentity = bIdentity
        rnsB.transport.register(destination: bDest)

        let established = expectation(description: "responder side sees the link")
        var responderLink: Link?
        rnsB.transport.onLinkEstablished = { link in
            responderLink = link
            established.fulfill()
        }
        let initiatorLink = try Link.initiate(destination: bDest, transport: rnsA.transport)
        wait(for: [established], timeout: 2.0)

        let peerLink = try XCTUnwrap(responderLink)
        XCTAssertEqual(peerLink.status, .active)
        XCTAssertEqual(initiatorLink.status, .active)

        let closed = expectation(description: "peer observes the close")
        peerLink.onClosed = { _ in closed.fulfill() }

        rnsA.stop()

        // Promptly: the reference's keepalive watchdog would take up to KEEPALIVE_MAX = 360 s to
        // notice. Anything in that range is the defect, so the timeout here is deliberately far
        // below it — if this needs seconds, nothing was torn down and the peer is merely timing
        // out on its own.
        wait(for: [closed], timeout: 2.0)
        XCTAssertNotEqual(peerLink.status, .active,
                          "the peer must not still consider the link active after its counterpart "
                          + "shut down")
    }

    /// The ordering half: teardown has to happen while the interfaces can still carry the close.
    /// Stopping the transport first silently satisfies "detachInterfaces was called" while
    /// emitting nothing, which is the same shape of failure as never calling it.
    func testTheCloseGoesOutBeforeInterfacesAreStopped() throws {
        let aDir = tmpDir.appendingPathComponent("order-a")
        let bDir = tmpDir.appendingPathComponent("order-b")
        let rnsA = Reticulum(configuration: .init(storagePath: aDir))
        let rnsB = Reticulum(configuration: .init(storagePath: bDir))

        let aIface = PairedInterface(name: "a-side")
        let bIface = PairedInterface(name: "b-side")
        aIface.paired = bIface; bIface.paired = aIface
        rnsA.transport.register(interface: aIface)
        rnsB.transport.register(interface: bIface)
        try rnsA.start()
        try rnsB.start()
        defer { rnsB.stop() }

        let bIdentity = Identity()
        let bDest = try Destination(identity: bIdentity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["shutdown-order"])
        rnsB.transport.ownerIdentity = bIdentity
        rnsB.transport.register(destination: bDest)

        let established = expectation(description: "responder side sees the link")
        rnsB.transport.onLinkEstablished = { _ in established.fulfill() }
        _ = try Link.initiate(destination: bDest, transport: rnsA.transport)
        wait(for: [established], timeout: 2.0)

        rnsA.stop()

        XCTAssertGreaterThan(aIface.stopCount, 0, "shutdown must stop the interface")

        let closeIndex = aIface.log.firstIndex(of: .sent(.linkClose))
        let stopIndex = aIface.log.firstIndex(of: .stopped)
        XCTAssertNotNil(closeIndex,
                        "no LINKCLOSE was ever handed to the interface during shutdown — either "
                        + "teardown was not reached, or it ran after the interface was stopped and "
                        + "Transport dropped the packet on the isOnline filter. Log: \(aIface.log)")
        if let closeIndex, let stopIndex {
            XCTAssertLessThan(closeIndex, stopIndex,
                              "the LINKCLOSE must be sent before the interface is stopped, or it "
                              + "goes nowhere and the peer waits out its keepalive watchdog. "
                              + "Log: \(aIface.log)")
        }
    }

    // MARK: - The guard: every stop path reaches teardown

    /// Spec: "Every stop path reaches interface teardown", falsifiability note: "a test that calls
    /// interface teardown directly and asserts it works already passes. The missing assertion is
    /// that stopping the stack reaches it."
    ///
    /// Structural, and deliberately so (D9). There are at least three exit paths — `rnsd`'s signal
    /// handlers, the shared-instance stop, and an application's own teardown — and this subsystem
    /// has form: RetiOS shipped `StackController.tearDown()` with no callers until v0.3.9, and
    /// `detachInterfaces()` itself sat here with none. What must hold is that they all funnel
    /// through one place and that place tears down *before* it stops the transport, so the
    /// ordering is checked too.
    func testReticulumStopReachesInterfaceTeardownBeforeStoppingTransport() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        let body = try functionBody(named: "public func stop()",
                                    in: sources.appendingPathComponent("ReticulumSwift/Reticulum.swift"))

        // Comments stripped first. The first draft of this guard searched the raw body and was
        // satisfied by the comment above the call that *mentions* `detachInterfaces()` — so it
        // passed with the two calls in the wrong order. Caught by swapping them deliberately;
        // a guard that cannot fail is worse than no guard, and its own documentation is the
        // likeliest thing to fool it.
        let code = body.components(separatedBy: .newlines)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("//") ? "" : line
            }
            .joined(separator: "\n")

        let detachIndex = code.range(of: "detachInterfaces()")
        XCTAssertNotNil(detachIndex,
                        """
                        Reticulum.stop() does not reach Transport.detachInterfaces().
                        Every exit path funnels through here — rnsd's signal handlers via
                        InstanceConnection.stop(), and an application's own teardown — so a node
                        that stops without it emits no LINK_CLOSE and its peers hold the link
                        ACTIVE for up to KEEPALIVE_MAX = 360 s (bugs/028).
                        """)

        if let detachIndex, let transportStop = code.range(of: "transport.stop()") {
            XCTAssertLessThan(detachIndex.lowerBound, transportStop.lowerBound,
                              """
                              detachInterfaces() runs after transport.stop(), which has already \
                              stopped every interface — so the close packets are handed to dead \
                              interfaces and no peer hears them. Teardown must come first, as it \
                              does in Reticulum.py:196-205.
                              """)
        }
    }

    /// The shared-instance exit path funnels into `Reticulum.stop()` rather than tearing down its
    /// own way, so the guard above covers it too.
    func testTheSharedInstanceStopPathFunnelsThroughReticulumStop() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        let body = try functionBody(
            named: "public func stop()",
            in: sources.appendingPathComponent("ReticulumSwift/Utilities/InstanceConnection.swift"))
        XCTAssertTrue(body.contains("reticulum.stop()"),
                      "InstanceConnection.stop() must funnel into Reticulum.stop(), or rnsd's "
                      + "signal handlers bypass interface teardown (bugs/028, D9)")
    }

    /// Extract a function body by brace matching from its declaration line.
    private func functionBody(named declaration: String, in file: URL) throws -> String {
        let src = try String(contentsOf: file, encoding: .utf8)
        guard let start = src.range(of: declaration) else {
            XCTFail("could not find \(declaration) in \(file.lastPathComponent)")
            return ""
        }
        var depth = 0
        var body = ""
        var started = false
        for character in src[start.upperBound...] {
            if character == "{" { depth += 1; started = true }
            if started { body.append(character) }
            if character == "}" {
                depth -= 1
                if depth == 0 { break }
            }
        }
        return body
    }
}
