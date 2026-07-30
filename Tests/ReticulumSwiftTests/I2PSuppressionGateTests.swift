import XCTest
@testable import ReticulumSwift

/// `bugs/022` — the non-connectable-I2P suppression gate, driven from a **real** `I2PInterface`.
///
/// `RNStatusStats.shouldHide` is a faithful port of `rnstatus.py:393-403` and its own tests pass
/// (`RNStatusStatsTests.swift:115-123`). They pass against a hand-built stats dict whose `name`
/// they set to `"I2PInterface[x]"` — the string the gate keys on. Meanwhile the production path
/// published `I2PInterface.displayName == name`, so a real interface named `"I2P"` produced the
/// row name `"I2P"`, the prefix never matched, and the gate was **dead**: it proved its own
/// predicate while suppressing nothing.
///
/// So this suite never names a row. It registers the interface, builds the payload the way the
/// daemon does, and asserts on what `rnstatus` renders — which is the only place the defect was
/// observable.
final class I2PSuppressionGateTests: XCTestCase {

    private func makeI2P(name: String, connectable: Bool) -> I2PInterface {
        I2PInterface(name: name,
                     daemon: MockI2PDaemon(),
                     dataDirectory: URL(fileURLWithPath: "/tmp"),
                     connectable: connectable)
    }

    private func render(_ transport: Transport, showAll: Bool) -> String {
        let stats = RNStatusStats(InterfaceStatsPayload.build(transport))!
        var options = RNStatusRenderer.Options()
        options.showAll = showAll
        return RNStatusRenderer(options: options, now: 1_700_000_000)
            .render(stats: stats, linkCount: 0)
    }

    /// `rnstatus.py:403` re-applies the non-connectable-I2P test *outside* the `dispall` guard,
    /// so `-a` does not reveal the row.
    func testNonConnectableI2PRowIsHiddenIncludingUnderShowAll() {
        let transport = Transport()
        transport.transportIdentity = Identity()
        let iface = makeI2P(name: "I2P", connectable: false)
        transport.register(interface: iface)
        defer { transport.deregister(interface: iface) }

        for showAll in [false, true] {
            let rendered = render(transport, showAll: showAll)
            XCTAssertFalse(rendered.contains(iface.displayName),
                           """
                           A non-connectable I2PInterface rendered as \
                           "\(iface.displayName)" with showAll=\(showAll). rnstatus.py:401,:405 \
                           suppresses it in both cases. If this fails with the published name \
                           being the bare "\(iface.name)", the gate is not broken — the \
                           published name is, and it never matched the "I2PInterface[" prefix \
                           the gate keys on (bugs/022).
                           """)
        }
    }

    /// The other half: the gate must not swallow a *connectable* I2P interface, or "hidden"
    /// would be indistinguishable from "hides everything".
    func testConnectableI2PRowIsShown() {
        let transport = Transport()
        transport.transportIdentity = Identity()
        let iface = makeI2P(name: "I2P", connectable: true)
        transport.register(interface: iface)
        defer { transport.deregister(interface: iface) }

        for showAll in [false, true] {
            XCTAssertTrue(render(transport, showAll: showAll).contains(iface.displayName),
                          "A connectable I2PInterface must render (showAll=\(showAll))")
        }
    }

    /// The suppression must follow the *interface*, not a name an operator happened to choose.
    /// Before `bugs/022` the row name was the configured name, so whether the gate fired
    /// depended on the operator naming their interface `"I2PInterface[…]"` by hand.
    func testSuppressionDoesNotDependOnTheConfiguredName() {
        for configured in ["I2P", "i2p-hidden-service", "my tunnel", "I2PInterface"] {
            let transport = Transport()
            transport.transportIdentity = Identity()
            let iface = makeI2P(name: configured, connectable: false)
            transport.register(interface: iface)

            XCTAssertFalse(render(transport, showAll: true).contains(iface.displayName),
                           "Configured as \"\(configured)\", the row was still rendered — "
                           + "suppression is keyed on the published class prefix, so it must "
                           + "hold for any configured name")
            transport.deregister(interface: iface)
        }
    }

    /// And the published name is what makes it work, stated directly: the gate's predicate is a
    /// prefix of the class-qualified form.
    func testPublishedNameCarriesThePrefixTheGateKeysOn() {
        let iface = makeI2P(name: "I2P", connectable: false)
        XCTAssertTrue(iface.displayName.hasPrefix("I2PInterface["),
                      "rnstatus.py:401 keys suppression on the \"I2PInterface[\" prefix; the "
                      + "published name is \"\(iface.displayName)\"")
    }
}
