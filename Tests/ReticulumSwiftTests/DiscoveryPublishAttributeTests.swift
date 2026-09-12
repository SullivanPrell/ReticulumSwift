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

/// The interface-side attributes Python's discovery *publisher* reads.
///
/// `Reticulum.py:953-967` assigns fifteen of them onto every configured interface, and
/// `Interface.py:117-119` declares `supports_discovery`, `discoverable` and
/// `last_discovery_announce` as base defaults. `Discovery.InterfaceAnnouncer.job()` reads all
/// of them (`Discovery.py:82-92`). This port had none, which is why
/// `Reticulum.publishesInterfaceDiscovery` was a documented gap.
///
/// They live on `InterfaceState` for the reason the box exists at all: a config value with no
/// settable home is a value the parser can't deliver (`swift_devel/bugs/025-*.md`).
final class DiscoveryPublishAttributeTests: XCTestCase {

    // MARK: - Defaults

    /// Python's base `Interface.__init__` values, which are what an interface with no
    /// `discoverable` block in its config section keeps.
    func testFreshInterfaceCarriesTheReferenceDefaults() {
        let iface = TCPClientInterface(name: "tcp", host: "127.0.0.1", port: 4242)

        XCTAssertFalse(iface.discoverable,
                       "Interface.py:118 — discoverable defaults False")
        XCTAssertEqual(iface.lastDiscoveryAnnounce, 0,
                       "Interface.py:119 — last_discovery_announce defaults 0")

        // The fifteen `interface_post_init` assignments, at the values `Reticulum.py:885-899`
        // initialises the locals to before reading the config section.
        XCTAssertNil(iface.discoveryAnnounceInterval, "discovery_announce_interval")
        XCTAssertFalse(iface.discoveryPublishIfac, "discovery_publish_ifac")
        XCTAssertNil(iface.reachableOn, "reachable_on")
        XCTAssertNil(iface.discoveryName, "discovery_name")
        XCTAssertNil(iface.discoveryLxmfAddress, "discovery_lxmf_address")
        XCTAssertFalse(iface.discoveryEncrypt, "discovery_encrypt")
        XCTAssertNil(iface.discoveryStampValue, "discovery_stamp_value")
        XCTAssertNil(iface.discoveryLocation, "discovery_location")
        XCTAssertNil(iface.discoveryLatitude, "discovery_latitude")
        XCTAssertNil(iface.discoveryLongitude, "discovery_longitude")
        XCTAssertNil(iface.discoveryHeight, "discovery_height")
        XCTAssertNil(iface.discoveryFrequency, "discovery_frequency")
        XCTAssertNil(iface.discoveryBandwidth, "discovery_bandwidth")
        XCTAssertNil(iface.discoveryModulation, "discovery_modulation")
        XCTAssertNil(iface.discoveryChannel, "discovery_channel")
    }

    // MARK: - Settability

    /// Each attribute the config path writes has to be writable through `any Interface`, which
    /// is the type `Reticulum`'s parser holds. A `{ get }`-only port of these would compile and
    /// then have nowhere to put a parsed value.
    func testEveryDiscoveryAttributeIsSettable() throws {
        let concrete = TCPServerInterface(name: "hub", port: 4251)
        let iface: any Interface = concrete

        iface.discoverable = true
        iface.discoveryAnnounceInterval = 21_600
        iface.discoveryPublishIfac = true
        iface.reachableOn = "hub.example.net"
        iface.discoveryName = "Example hub"
        iface.discoveryLxmfAddress = Data(repeating: 0x5A, count: 16)
        iface.discoveryEncrypt = true
        iface.discoveryStampValue = 18
        iface.discoveryLocation = "~/bin/whereami"
        iface.discoveryLatitude = 55.6761
        iface.discoveryLongitude = 12.5683
        iface.discoveryHeight = 12.0
        iface.discoveryFrequency = 867_200_000
        iface.discoveryBandwidth = 125_000
        iface.discoveryModulation = 3
        iface.discoveryChannel = 7
        iface.lastDiscoveryAnnounce = 1_700_000_000

        XCTAssertTrue(concrete.discoverable)
        XCTAssertEqual(concrete.discoveryAnnounceInterval, 21_600)
        XCTAssertTrue(concrete.discoveryPublishIfac)
        XCTAssertEqual(concrete.reachableOn, "hub.example.net")
        XCTAssertEqual(concrete.discoveryName, "Example hub")
        XCTAssertEqual(concrete.discoveryLxmfAddress, Data(repeating: 0x5A, count: 16))
        XCTAssertTrue(concrete.discoveryEncrypt)
        XCTAssertEqual(concrete.discoveryStampValue, 18)
        XCTAssertEqual(concrete.discoveryLocation, "~/bin/whereami")
        XCTAssertEqual(try XCTUnwrap(concrete.discoveryLatitude), 55.6761, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(concrete.discoveryLongitude), 12.5683, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(concrete.discoveryHeight), 12.0, accuracy: 1e-9)
        XCTAssertEqual(concrete.discoveryFrequency, 867_200_000)
        XCTAssertEqual(concrete.discoveryBandwidth, 125_000)
        XCTAssertEqual(concrete.discoveryModulation, 3)
        XCTAssertEqual(concrete.discoveryChannel, 7)
        XCTAssertEqual(concrete.lastDiscoveryAnnounce, 1_700_000_000)
    }

    // MARK: - Spawned clients

    /// Python's spawn block copies nineteen attributes onto each accepted client
    /// (`TCPInterface.py:594-641`) and **none of them is a discovery attribute**. A spawned
    /// client that inherited `discoverable` would announce itself as a separately reachable
    /// endpoint for every peer that dialled in, advertising the *parent's* `reachable_on` once
    /// per connection.
    ///
    /// `InterfaceState.inherit(from:)` copies the whole box, so this is the same shape as the
    /// `wantsTunnel`/`tunnelID` exclusion already there: without an explicit reset, adding a
    /// field to the box silently makes it inheritable.
    func testSpawnedClientInheritsNoDiscoveryAttribute() {
        let server = TCPServerInterface(name: "hub", port: 4252)
        server.discoverable = true
        server.discoveryAnnounceInterval = 900
        server.discoveryPublishIfac = true
        server.reachableOn = "hub.example.net"
        server.discoveryName = "Example hub"
        server.discoveryLxmfAddress = Data(repeating: 0x5A, count: 16)
        server.discoveryEncrypt = true
        server.discoveryStampValue = 18
        server.discoveryLocation = "~/bin/whereami"
        server.discoveryLatitude = 55.6761
        server.discoveryLongitude = 12.5683
        server.discoveryHeight = 12.0
        server.discoveryFrequency = 867_200_000
        server.discoveryBandwidth = 125_000
        server.discoveryModulation = 3
        server.discoveryChannel = 7
        server.lastDiscoveryAnnounce = 1_700_000_000

        // Something inheritable, so a wholesale-copy regression stays distinguishable from
        // `inherit(from:)` not running at all.
        server.gravity = 17

        let client = TCPServerClientInterface(name: "Client on hub",
                                              parentServer: server,
                                              peerHost: "10.0.0.9",
                                              peerPort: 51000)

        XCTAssertEqual(client.gravity, 17, "the ordinary inheritance still has to happen")

        XCTAssertFalse(client.discoverable, "a spawned client must not announce itself")
        XCTAssertEqual(client.lastDiscoveryAnnounce, 0, "last_discovery_announce")
        XCTAssertNil(client.discoveryAnnounceInterval, "discovery_announce_interval")
        XCTAssertFalse(client.discoveryPublishIfac, "discovery_publish_ifac")
        XCTAssertNil(client.reachableOn, "reachable_on")
        XCTAssertNil(client.discoveryName, "discovery_name")
        XCTAssertNil(client.discoveryLxmfAddress, "discovery_lxmf_address")
        XCTAssertFalse(client.discoveryEncrypt, "discovery_encrypt")
        XCTAssertNil(client.discoveryStampValue, "discovery_stamp_value")
        XCTAssertNil(client.discoveryLocation, "discovery_location")
        XCTAssertNil(client.discoveryLatitude, "discovery_latitude")
        XCTAssertNil(client.discoveryLongitude, "discovery_longitude")
        XCTAssertNil(client.discoveryHeight, "discovery_height")
        XCTAssertNil(client.discoveryFrequency, "discovery_frequency")
        XCTAssertNil(client.discoveryBandwidth, "discovery_bandwidth")
        XCTAssertNil(client.discoveryModulation, "discovery_modulation")
        XCTAssertNil(client.discoveryChannel, "discovery_channel")
    }

    // MARK: - supports_discovery

    /// `supports_discovery` is a per-class capability, not a per-config choice: the announcer's
    /// job filter is `i.supports_discovery and i.discoverable` (`Discovery.py:82`), so a type
    /// that leaves it False never announces however it's configured.
    ///
    /// Two of upstream's entries look like they belong here and don't. `KISSInterface` is in
    /// `DISCOVERABLE_INTERFACE_TYPES` (`Discovery.py:47-48`) but no `KISSInterface` sets the
    /// flag, and Weave's only assignment is on the WDCL serial transport object rather than the
    /// interface (`WeaveInterface.py:102`, inside `class WDCL`, whose body runs from `:49`).
    /// Both therefore never announce upstream, and mirroring the assignment rather than the
    /// behaviour would make this port emit announces no Python node emits.
    func testSupportsDiscoveryMatchesTheReferenceClassAttribute() throws {
        let expectedTrue: Set<String> = [
            "BackboneInterface",        // BackboneInterface.py:154
            "I2PInterface",             // I2PInterface.py:762
            "RNodeInterface",           // RNodeInterface.py:302
            "TCPClientInterface",       // TCPInterface.py:134
            "TCPServerInterface",       // TCPInterface.py:528
            "TCPServerClientInterface", // spawned as a TCPClientInterface, TCPInterface.py:594
        ]

        for iface in try InterfaceConformers.everyConcreteInterface() {
            let typeName = String(describing: type(of: iface))
            XCTAssertEqual(iface.supportsDiscovery, expectedTrue.contains(typeName),
                           "\(typeName).supportsDiscovery")
        }
    }
}

/// The `discoverable` half of an interface config block (`Reticulum.py:900-934`).
///
/// Nothing read these keys before, so an operator moving a working Python config across got a
/// node that silently never announced. That's the second half of the `bugs/025` shape: a
/// settable attribute nothing writes is the same failure as an unsettable one.
final class DiscoveryPublishConfigTests: XCTestCase {

    private func configured(_ parameters: [String: String],
                            type: String = "TCPServerInterface") -> any Interface {
        let interface = TCPServerInterface(name: "hub", port: 4253)
        Reticulum.applyInterfaceConfiguration(to: interface,
                                              from: .init(name: "hub", type: type,
                                                          enabled: true,
                                                          parameters: parameters))
        return interface
    }

    /// Everything inside the block is read only when `discoverable` is on
    /// (`Reticulum.py:901-903`), so a half-edited config can't start announcing.
    func testTheBlockIsIgnoredUnlessDiscoverableIsSet() {
        let iface = configured(["discovery_name": "Example hub",
                                "reachable_on": "hub.example.net",
                                "announce_interval": "30"])

        XCTAssertFalse(iface.discoverable)
        XCTAssertNil(iface.discoveryName)
        XCTAssertNil(iface.reachableOn)
        XCTAssertNil(iface.discoveryAnnounceInterval)
    }

    func testEveryKeyReachesTheInterface() throws {
        let iface = configured(["discoverable": "yes",
                                "announce_interval": "30",
                                "discovery_stamp_value": "18",
                                "discovery_name": "Example hub",
                                "discovery_encrypt": "yes",
                                "reachable_on": "hub.example.net",
                                "publish_ifac": "yes",
                                "location_cmd": "~/bin/whereami",
                                "latitude": "55.6761",
                                "longitude": "12.5683",
                                "height": "12",
                                "discovery_frequency": "867200000",
                                "discovery_bandwidth": "125000",
                                "discovery_modulation": "3"])

        XCTAssertTrue(iface.discoverable)
        XCTAssertEqual(iface.discoveryAnnounceInterval, 1800, "announce_interval is in minutes")
        XCTAssertEqual(iface.discoveryStampValue, 18)
        XCTAssertEqual(iface.discoveryName, "Example hub")
        XCTAssertTrue(iface.discoveryEncrypt)
        XCTAssertEqual(iface.reachableOn, "hub.example.net")
        XCTAssertTrue(iface.discoveryPublishIfac)
        XCTAssertEqual(iface.discoveryLocation, "~/bin/whereami")
        XCTAssertEqual(try XCTUnwrap(iface.discoveryLatitude), 55.6761, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(iface.discoveryLongitude), 12.5683, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(iface.discoveryHeight), 12.0, accuracy: 1e-9)
        XCTAssertEqual(iface.discoveryFrequency, 867_200_000)
        XCTAssertEqual(iface.discoveryBandwidth, 125_000)
        XCTAssertEqual(iface.discoveryModulation, 3)
    }

    /// `announce_interval` is minutes with a five-minute floor, and an absent key means six
    /// hours (`Reticulum.py:905-909`).
    func testTheAnnounceIntervalFloorAndDefault() {
        XCTAssertEqual(configured(["discoverable": "yes",
                                   "announce_interval": "1"]).discoveryAnnounceInterval, 300,
                       "below the floor clamps to five minutes")
        XCTAssertEqual(configured(["discoverable": "yes"]).discoveryAnnounceInterval, 21_600,
                       "an absent key defaults to six hours")
    }

    /// The operator's LXMF address is a truncated destination hash, so it has to be exactly
    /// `TRUNCATED_HASHLENGTH//8*2` hex characters. Anything else logs and stays unset
    /// (`Reticulum.py:922-926`) rather than putting a malformed address on the wire.
    func testTheOperatorAddressIsLengthCheckedAndDecoded() {
        let valid = String(repeating: "5a", count: Constants.truncatedHashLength)
        XCTAssertEqual(configured(["discoverable": "yes",
                                   "discovery_lxmf_address": valid]).discoveryLxmfAddress,
                       Data(repeating: 0x5A, count: Constants.truncatedHashLength))

        XCTAssertNil(configured(["discoverable": "yes",
                                 "discovery_lxmf_address": "5a5a"]).discoveryLxmfAddress,
                     "too short")
        XCTAssertNil(configured(["discoverable": "yes",
                                 "discovery_lxmf_address": String(repeating: "zz", count: 16)])
                        .discoveryLxmfAddress,
                     "right length, not hex")
    }

    /// An announcing interface has to be reachable through this node, so a mode that doesn't
    /// route for others is auto-corrected: RNode types to access point, everything else to
    /// gateway (`Reticulum.py:927-934`). `ignore_config_warnings` opts out.
    func testDiscoveryAutoConfiguresAnUnroutableMode() {
        XCTAssertEqual(configured(["discoverable": "yes"]).mode, .gateway,
                       "an unset mode is MODE_FULL, which gets corrected")
        XCTAssertEqual(configured(["discoverable": "yes", "mode": "boundary"]).mode, .gateway)

        XCTAssertEqual(configured(["discoverable": "yes"], type: "RNodeInterface").mode,
                       .accessPoint, "RNodeInterface")
        XCTAssertEqual(configured(["discoverable": "yes"], type: "RNodeMultiInterface").mode,
                       .accessPoint, "RNodeMultiInterface")

        for kept in ["gateway", "accesspoint", "internal"] {
            XCTAssertEqual(configured(["discoverable": "yes", "mode": kept]).mode,
                           InterfaceMode(configName: kept),
                           "\(kept) already routes and must be left alone")
        }

        XCTAssertEqual(configured(["discoverable": "yes",
                                   "ignore_config_warnings": "yes"]).mode, .full,
                       "the operator opted out of the correction")
    }

    /// Python latches a module-level flag the moment any interface is discoverable, and starts
    /// the announcer from it at `Reticulum.py:370`. Without the flag the subsystem has no
    /// trigger, because the interfaces aren't built yet when the block is parsed.
    func testAnyDiscoverableInterfaceEnablesTheAnnouncer() {
        let saved = Reticulum.discoveryEnabled()
        defer { Reticulum.storedDiscoveryEnabled = saved }

        Reticulum.storedDiscoveryEnabled = false
        _ = configured(["discovery_name": "not discoverable"])
        XCTAssertFalse(Reticulum.discoveryEnabled())

        _ = configured(["discoverable": "yes"])
        XCTAssertTrue(Reticulum.discoveryEnabled())
    }
}
