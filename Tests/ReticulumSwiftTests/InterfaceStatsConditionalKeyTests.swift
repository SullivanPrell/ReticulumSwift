//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest
@testable import ReticulumSwift

/// The `hasattr`-guarded half of Python's `get_interface_stats`.
///
/// `InterfaceStatsKeyParityTests` covers the keys upstream emits for every interface. This
/// file covers the ones it emits only when the interface happens to carry the attribute:
/// `hasattr(interface, "peers")`, `hasattr(interface, "cpu_temp")`, and so on. `rnstatus`
/// guards each of these reads with `if "key" in ifstat`, so a missing one costs a display
/// line rather than the whole listing—but the line is the only place an operator reads a
/// peer count, a radio's temperature, or which parent spawned a client interface.
///
/// Two upstream keys stay deliberately unemitted, and the last two tests pin that.
final class InterfaceStatsConditionalKeyTests: XCTestCase {

    // MARK: - Helpers

    /// The payload row for `iface`, as a plain dictionary.
    private func row(for iface: any Interface) throws -> [String: MsgPack.Value] {
        let transport = Transport()
        transport.register(interface: iface)
        defer { transport.deregister(interface: iface) }

        let payload = InterfaceStatsPayload.build(transport)
        let interfaces = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray)
        let first = try XCTUnwrap(interfaces.first)
        guard case .map(let pairs) = first else {
            XCTFail("an interface entry must be a map")
            return [:]
        }
        var out: [String: MsgPack.Value] = [:]
        for (k, v) in pairs {
            if case .string(let key) = k { out[key] = v }
        }
        return out
    }

    private func stats(iface: any Interface, key: String) -> Double? {
        (try? row(for: iface))?[key]?.asDouble
    }

    private func weaveInterface(name: String) -> WeaveInterface {
        WeaveInterface(name: name, port: "/dev/null", transport: MockSerialPort())
    }

    // MARK: - peers

    /// `if hasattr(interface, "peers"): ifstats["peers"] = len(interface.peers)`. Upstream
    /// emits the key for every interface that tracks peers, whether or not it has any, so a
    /// freshly built one reports zero rather than omitting the line.
    func testAnAutoInterfaceReportsItsPeerCount() throws {
        let stats = try row(for: AutoInterface(name: "auto-peers"))
        XCTAssertEqual(stats["peers"]?.asInt, 0)
    }

    /// Python's `WeaveInterface` carries `self.peers` too, so the same key applies.
    func testAWeaveInterfaceReportsItsPeerCount() throws {
        let stats = try row(for: weaveInterface(name: "weave-peers"))
        XCTAssertEqual(stats["peers"]?.asInt, 0)
    }

    /// The control: an interface with no notion of peers omits the key entirely, the way
    /// `hasattr` does upstream. Emitting a hard zero here would tell an operator a UDP
    /// interface had lost its peers.
    func testAnInterfaceWithoutPeersOmitsTheKey() throws {
        let stats = try row(for: UDPInterface(name: "udp-nopeers", listenPort: 4271))
        XCTAssertNil(stats["peers"])
    }

    // MARK: - Device load

    /// `cpu_load` and `mem_load` are `@property` on Python's `WeaveInterface`, so `hasattr`
    /// is always true and the keys are always emitted. Both read through `self.device`, which
    /// `final_init` assigns unconditionally (`WeaveInterface.py:883`)—so the `if not
    /// self.device: return None` arm never runs for an interface old enough to appear in a
    /// stats payload, and the readings are the device's initialised zeros until the switch
    /// first reports. Publishing null here instead would put this port's listing at odds with
    /// a Python daemon describing the same silent switch.
    func testAWeaveInterfaceThatHasHeardNoStatsReportsZeroLoad() throws {
        let stats = try row(for: weaveInterface(name: "weave-noload"))
        XCTAssertEqual(stats["cpu_load"]?.asDouble, 0.0)
        XCTAssertEqual(stats["mem_load"]?.asDouble, 0.0)
    }

    /// Once the switch reports, both read through the device: `self.device.cpu_load` and
    /// `self.device.memory_used_pct`, the latter
    /// `round((memory_used/memory_total)*100, 2)`.
    func testAWeaveInterfaceReportsItsDeviceLoad() throws {
        let iface = weaveInterface(name: "weave-load")
        iface.device.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                             event: WeaveEvt.etStatCpu, data: Data([42])))
        // 1 MiB free of 4 MiB total: three quarters used.
        iface.device.handleLog(WeaveLogFrame(
            timestamp: 0, level: 0, event: WeaveEvt.etStatMemory,
            data: Data([0x00, 0x10, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00])))

        let stats = try row(for: iface)
        XCTAssertEqual(stats["cpu_load"]?.asDouble, 42.0)
        XCTAssertEqual(try XCTUnwrap(stats["mem_load"]?.asDouble), 75.0, accuracy: 0.01)
    }

    /// The percentage carries two decimals, because upstream rounds before storing and
    /// `rnstatus` prints whatever arrives. 1 byte free of 3 is 66.666…; both sides say
    /// 66.67.
    func testTheMemoryPercentageIsRoundedToTwoDecimals() throws {
        let iface = weaveInterface(name: "weave-round")
        iface.device.handleLog(WeaveLogFrame(
            timestamp: 0, level: 0, event: WeaveEvt.etStatMemory,
            data: Data([0, 0, 0, 1, 0, 0, 0, 3])))
        let stats = try row(for: iface)
        XCTAssertEqual(stats["mem_load"]?.asDouble, 66.67)
    }

    /// A switch that reports a zero total divides by zero upstream, so there is no reference
    /// behaviour to copy—only a hazard to avoid. A NaN would survive into the payload and
    /// reach `rnstatus` as a printed "nan %".
    func testAMemoryFrameReportingNoTotalDoesNotYieldANaN() throws {
        let iface = weaveInterface(name: "weave-zerototal")
        iface.device.handleLog(WeaveLogFrame(
            timestamp: 0, level: 0, event: WeaveEvt.etStatMemory,
            data: Data(repeating: 0, count: 8)))
        let load = try XCTUnwrap(stats(iface: iface, key: "mem_load"))
        XCTAssertFalse(load.isNaN)
        XCTAssertEqual(load, 0.0)
    }

    /// The control: an interface with no switch behind it omits both keys, the way `hasattr`
    /// does upstream for anything that isn't a Weave interface.
    func testANonWeaveInterfaceOmitsTheLoadKeys() throws {
        let stats = try row(for: UDPInterface(name: "udp-noload", listenPort: 4274))
        XCTAssertNil(stats["cpu_load"])
        XCTAssertNil(stats["mem_load"])
    }

    // MARK: - Radio temperature

    /// `self.cpu_temp = None` in `RNodeInterface.__init__` and `self.cpu_temp =
    /// self.r_temperature` once a stats frame lands. The attribute exists either way, so
    /// upstream always emits the key and `rnstatus` prints the line only when it isn't None.
    func testAnRNodeInterfaceWithNoReadingReportsNullTemperature() throws {
        let stats = try row(for: RNodeInterface(name: "rnode-notemp",
                                                transport: MockRNodeTransport()))
        XCTAssertEqual(stats["cpu_temp"], .nil)
    }

    func testAnRNodeInterfaceReportsAKnownTemperature() throws {
        let iface = RNodeInterface(name: "rnode-temp", transport: MockRNodeTransport())
        iface.rTemperature = 47
        let stats = try row(for: iface)
        XCTAssertEqual(stats["cpu_temp"]?.asInt, 47)
    }

    // MARK: - Parent interface

    /// `if hasattr(interface, "parent_interface") and interface.parent_interface != None`,
    /// then `str(...)` and `.get_hash()`. A spawned client interface is otherwise anonymous
    /// in the listing: several may share a display name, and the parent is the only field
    /// naming which server, radio or tunnel each one belongs to.
    func testEverySpawnedInterfaceNamesItsParent() throws {
        // Each case holds its parent for the length of the check: the back-references are weak,
        // and a parent collected mid-test would quietly turn this into an assertion about the
        // absent-parent path instead.
        let server = TCPServerInterface(name: "tcpserver-parent", port: 4246)
        let i2p    = I2PInterface(name: "i2p-parent", daemon: MockI2PDaemon(),
                                  dataDirectory: URL(fileURLWithPath: "/tmp"))
        let weave  = weaveInterface(name: "weave-parent")
        let sub    = RNodeSubInterface(name: "sub-parent", index: 0, interfaceType: "LoRa",
                                       frequency: 867_200_000, bandwidth: 125_000,
                                       txPower: 0, sf: 8, cr: 5)
        let multi  = try RNodeMultiInterface(name: "rnodemulti-parent",
                                             transport: MockRNodeTransport(),
                                             subInterfaces: [sub])

        let spawned: [any SpawnedInterface] = [
            TCPServerClientInterface(name: "Client on tcpserver-parent", parentServer: server,
                                     peerHost: "10.0.0.9", peerPort: 51000),
            I2PInterfacePeer(name: "i2ppeer-parent", targetI2PDestination: "abc.b32.i2p",
                             parentInterface: i2p),
            WeaveInterfacePeer(owner: weave, endpointAddr: Data([0x01, 0x02, 0x03, 0x04])),
            sub,
        ]

        // The enumeration decides the set; this list only supplies live parents for it. If the
        // two ever disagree, a conformer is going untested.
        XCTAssertEqual(Set(spawned.map { String(describing: type(of: $0)) }),
                       try spawnedConformerNames(),
                       "every SpawnedInterface conformer needs a case here")

        for iface in spawned {
            let parent = try XCTUnwrap(iface.spawningInterface,
                                       "\(type(of: iface)) was built without a live parent")
            let stats = try row(for: iface)
            XCTAssertEqual(stats["parent_interface_name"]?.asString, parent.displayName,
                           "\(type(of: iface)) must name its parent")
            guard case .bytes(let hash)? = stats["parent_interface_hash"] else {
                XCTFail("\(type(of: iface)) must publish its parent's hash")
                continue
            }
            XCTAssertEqual(hash, Hashes.fullHash(Data(parent.displayName.utf8)))
        }
        withExtendedLifetime((server, i2p, weave, multi)) {}
    }

    /// The control, and the reason the keys are conditional: upstream omits them when the
    /// interface has no parent rather than publishing an empty name.
    func testAnInterfaceWithNoParentOmitsTheParentKeys() throws {
        let stats = try row(for: UDPInterface(name: "udp-noparent", listenPort: 4272))
        XCTAssertNil(stats["parent_interface_name"])
        XCTAssertNil(stats["parent_interface_hash"])
    }

    /// A spawned interface whose parent has gone away publishes nothing rather than a
    /// placeholder—the references are weak, and upstream's `!= None` test has the same
    /// effect once Python collects the parent.
    func testASpawnedInterfaceWithADroppedParentOmitsTheKeys() throws {
        var peer: WeaveInterfacePeer! = nil
        do {
            let owner = weaveInterface(name: "weave-transient")
            peer = WeaveInterfacePeer(owner: owner, endpointAddr: Data([0x09]))
        }
        let stats = try row(for: peer)
        XCTAssertNil(stats["parent_interface_name"])
        XCTAssertNil(stats["parent_interface_hash"])
    }

    /// Adding a spawned interface type without conforming it leaves its rows parentless, and
    /// nothing else would say so. `InterfaceConformerCoverageTests` already forces every new
    /// conformer into the enumeration, so skipping the list here doesn't sidestep this pin.
    func testTheSpawnedProtocolCoversExactlyTheTypesThatHoldAParent() throws {
        XCTAssertEqual(try spawnedConformerNames(), [
            "I2PInterfacePeer",
            "RNodeSubInterface",
            "TCPServerClientInterface",
            "WeaveInterfacePeer",
        ])
    }

    /// Every conformer the type system can find, by name. `InterfaceConformerCoverageTests`
    /// already fails when a conformer in `Sources/` is missing from the enumeration, so a new
    /// spawned type can't reach the payload without passing through here first.
    private func spawnedConformerNames() throws -> Set<String> {
        Set(try InterfaceConformers.everyConcreteInterface()
            .filter { $0 is any SpawnedInterface }
            .map { String(describing: type(of: $0)) })
    }

    // MARK: - Weave identifiers

    /// The three identifiers aren't interchangeable, and upstream splits them across two
    /// types: `switch_id` and `endpoint_id` are properties of `WeaveInterface`
    /// (`WeaveInterface.py:838-845`), while `via_switch_id` is an attribute only
    /// `WeaveInterfacePeer` declares (`:1014`). Publishing all three from the peer describes
    /// each peer as the switch, and leaves the interface actually attached to that switch
    /// reporting nothing—`rnstatus` prints "Switch ID" from whichever row carries the key
    /// (`rnstatus.py:543-553`).
    func testAWeaveInterfacePublishesTheSwitchAndEndpointItIsAttachedTo() throws {
        let iface = weaveInterface(name: "weave-ids")
        let stats = try row(for: iface)
        XCTAssertNotNil(stats["switch_id"])
        XCTAssertNotNil(stats["endpoint_id"])
        XCTAssertNil(stats["via_switch_id"], "only a peer records the switch it arrived through")
    }

    /// The mirror image: a peer reports the switch it reached the fabric through and nothing
    /// else.
    func testAWeavePeerPublishesOnlyTheSwitchItArrivedThrough() throws {
        let owner = weaveInterface(name: "weave-idowner")
        let peer  = WeaveInterfacePeer(owner: owner, endpointAddr: Data([0x0a, 0x0b]))
        peer.viaSwitchID = Data([0xde, 0xad, 0xbe, 0xef])

        let stats = try row(for: peer)
        XCTAssertNil(stats["switch_id"])
        XCTAssertNil(stats["endpoint_id"])
        XCTAssertEqual(stats["via_switch_id"]?.asString, "de:ad:be:ef")
        withExtendedLifetime(owner) {}
    }

    /// Each identifier goes through `RNS.hexrep`, whose `delimit` argument defaults to true
    /// (`__init__.py:168-174`), so an operator reads `de:ad:be:ef`. Plain hex wouldn't match
    /// what the same switch shows on a Python daemon.
    func testTheIdentifiersAreColonDelimitedHex() throws {
        let iface = weaveInterface(name: "weave-hex")
        iface.device.switchID = Data([0x01, 0x23, 0x45, 0x67])
        let stats = try row(for: iface)
        XCTAssertEqual(stats["switch_id"]?.asString, "01:23:45:67")
    }

    /// Upstream emits the key with a null value rather than dropping it when the handshake
    /// hasn't produced an identifier yet, because the `hasattr` finds the property either way.
    func testAnUnhandshakenWeaveInterfaceReportsNullIdentifiers() throws {
        let stats = try row(for: weaveInterface(name: "weave-nohandshake"))
        XCTAssertEqual(stats["switch_id"], .nil)
        XCTAssertEqual(stats["endpoint_id"], .nil)
    }

    // MARK: - Keys this port deliberately leaves out

    /// `interference_last_ts` / `interference_last_dbm` come from `r_interference_l`, which
    /// upstream initialises to `None` and never assigns: a comment disables every write
    /// (`RNodeInterface.py:281,957-966`). The guard is `type(...) == list`, so upstream's own
    /// keys never appear. Emitting them here would put this port's listing ahead of the
    /// reference for a field with no defined meaning yet.
    func testTheInterferenceHistoryKeysStayUnemitted() throws {
        let stats = try row(for: RNodeInterface(name: "rnode-interference",
                                                transport: MockRNodeTransport()))
        XCTAssertNil(stats["interference_last_ts"])
        XCTAssertNil(stats["interference_last_dbm"])
    }

    /// `blocked_ips` / `blocked_ip_list` come from `BackboneInterface.blocked_ip_count`,
    /// which lives on upstream's *server* side. This port's Backbone support is client-only,
    /// so there is no ingress blocking to report. `RNStatusRenderer` already renders both
    /// keys when a Python daemon supplies them, which is the half that matters here.
    func testTheBlockedIPKeysStayUnemitted() throws {
        let stats = try row(for: BackboneInterface(name: "backbone-noblock",
                                                   host: "10.0.0.1", port: 4273))
        XCTAssertNil(stats["blocked_ips"])
        XCTAssertNil(stats["blocked_ip_list"])
    }
}
