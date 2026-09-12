//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

/// The `interface_stats` payload, in the exact shape Python's
/// `Reticulum.get_interface_stats()` produces (`RNS/Reticulum.py:1314-1410`).
///
/// This lives on its own rather than inside ``RPCServer`` because three separate callers
/// need the identical dictionary and must not drift apart:
///
/// - ``RPCServer`` answering `{"get": "interface_stats"}` over the instance-control socket
/// - `Transport`'s `/status` remote-management request handler, which Python's
///   `remote_status_handler` answers with `get_interface_stats()` verbatim
///   (`RNS/Transport.py:2855`)
/// - `rnstatus` running against its own in-process stack, where there is no RPC hop at all
///
/// `rnstatus` branches on `if "key" in ifstat` for eighteen different fields, so which keys
/// are *present* is as much a part of the contract as their values.
public enum InterfaceStatsPayload {
    /// The payload served when no stack is running.
    public static var empty: MsgPack.Value {
        var pairs: [(MsgPack.Value, MsgPack.Value)] = [
            (.string("interfaces"), .array([])),
            (.string("rxb"),        .int(0)),
            (.string("txb"),        .int(0)),
            (.string("rxs"),        .double(0)),
            (.string("txs"),        .double(0)),
        ]
        for key in ["arxb", "atxb"] { pairs.append((.string(key), .int(0))) }
        for key in ["arxs", "atxs", "arxf", "atxf"] { pairs.append((.string(key), .double(0))) }
        for key in ["prxb", "ptxb"] { pairs.append((.string(key), .int(0))) }
        for key in ["prxs", "ptxs", "prxf", "ptxf"] { pairs.append((.string(key), .double(0))) }
        for key in ["rxpps", "txpps"] { pairs.append((.string(key), .int(0))) }
        for key in ["rxqt", "rxqd", "rxqa", "rxqp", "rxqil",
                    "rxqtd", "rxqdd", "rxqad", "rxqpd", "rxqild"] {
            pairs.append((.string(key), .int(0)))
        }
        for key in ["tqpressure", "dqpressure", "aqpressure", "pqpressure", "ilqpressure"] {
            pairs.append((.string(key), .double(0)))
        }
        pairs.append((.string("txq"), .nil))
        pairs.append((.string("rss"), .nil))
        return .map(pairs)
    }

    /// Builds the `ifstats` payload from a live transport.
    public static func build(_ t: Transport) -> MsgPack.Value {
        let now = Date().timeIntervalSince1970

        // Snapshot the interface list under Transport's lock (register/deregister
        // mutate it on network-callback threads).
        t.lock.lock()
        let ifaces = t.interfaces
        t.lock.unlock()
        let interfaceValues: [MsgPack.Value] = ifaces.map { iface in
            var pairs: [(MsgPack.Value, MsgPack.Value)] = []

            func kv(_ k: String, _ v: MsgPack.Value) { pairs.append((.string(k), v)) }

            // The key ORDER below is Python's insertion order in `get_interface_stats`
            // (Reticulum.py:1326-1443), not an arbitrary one. `rnstatus -j` serialises the
            // dictionary with `json.dumps`, which preserves insertion order, so the order is
            // part of the `-j` output contract just as the top-level `rss`-goes-last note
            // further down records. Verified by pointing the real Python `rnstatus -j` at a
            // Swift `rnsd` and diffing the key sequence against a Python daemon's.

            // TCPServerInterface / PosixTCPServer: connected client count.
            if let srv = iface as? TCPServerInterface {
                kv("clients", .int(Int64(srv.clientCount)))
            } else if let srv = iface as? PosixTCPServer {
                kv("clients", .int(Int64(srv.clientCount)))
            } else if let i2p = iface as? I2PInterface {
                kv("clients", .int(Int64(i2p.clients)))
            } else {
                kv("clients", .nil)
            }

            // Spawned interfaces: parent_interface_name/hash, emitted between `clients` and the
            // I2P block. Upstream reaches the parent through `hasattr(interface,
            // "parent_interface") and interface.parent_interface != None`
            // (`Reticulum.py:1412-1414`); here the same reach is a protocol so the set of types
            // that publish a parent is the set that declares one, not a list maintained here.
            if let spawned = iface as? any SpawnedInterface, let parent = spawned.spawningInterface {
                kv("parent_interface_name", .string(parent.displayName))
                kv("parent_interface_hash", .bytes(Hashes.fullHash(Data(parent.displayName.utf8))))
            }

            if let i2p = iface as? I2PInterface {
                kv("i2p_connectable", .bool(i2p.connectable))
                kv("i2p_b32",     i2p.b32.map { .string($0 + ".b32.i2p") } ?? .nil)
                kv("tunnelstate", i2p.tunnelState.map { .string($0) } ?? .nil)
            }

            // RNodeInterface: airtime, channel load, noise, interference, then battery.
            if let rnode = iface as? RNodeInterface {
                kv("airtime_short",      .double(rnode.rAirtimeShort))
                kv("airtime_long",       .double(rnode.rAirtimeLong))
                kv("channel_load_short", .double(rnode.rChannelLoadShort))
                kv("channel_load_long",  .double(rnode.rChannelLoadLong))
                kv("noise_floor",        rnode.rNoiseFloor.map { .int(Int64($0)) } ?? .nil)
                kv("interference",       rnode.rInterference.map { .int(Int64($0)) } ?? .nil)
            }

            // Processor temperature and switch load. Upstream guards each with a bare `hasattr`
            // (`Reticulum.py:1443-1445`), so `cpu_temp` rides on RNode interfaces and the two
            // load figures on Weave ones. `cpu_temp` is null until the radio first reports;
            // the loads read 0 until the switch does, matching the attributes upstream
            // initialises to 0.
            if let rnode = iface as? RNodeInterface {
                kv("cpu_temp", rnode.cpuTemp.map { .int(Int64($0)) } ?? .nil)
            }
            //
            // The three Weave identifiers follow, each on the type that declares it upstream:
            // `switch_id` and `endpoint_id` are properties of `WeaveInterface`
            // (`WeaveInterface.py:838-845`), while `via_switch_id` is an attribute of
            // `WeaveInterfacePeer` alone (`:1014`). A peer therefore publishes only the switch
            // it arrived through, and the interface publishes the switch behind it. Every one
            // is colon-delimited hex, because upstream passes them through `RNS.hexrep`, whose
            // `delimit` defaults to true (`Reticulum.py:1451-1461`).
            if let weave = iface as? WeaveInterface {
                kv("cpu_load",    .double(weave.cpuLoad))
                kv("mem_load",    .double(weave.memLoad))
                kv("switch_id",   weave.switchID.map   { .string(RNSUtilities.hexrep($0)) } ?? .nil)
                kv("endpoint_id", weave.endpointID.map { .string(RNSUtilities.hexrep($0)) } ?? .nil)
            }
            if let peer = iface as? WeaveInterfacePeer {
                kv("via_switch_id", peer.viaSwitchID.map { .string(RNSUtilities.hexrep($0)) } ?? .nil)
            }

            if let rnode = iface as? RNodeInterface,
               rnode.getBatteryState() != RNodeInterface.batteryStateUnknown {
                kv("battery_state",   .string(rnode.getBatteryStateString()))
                kv("battery_percent", .int(Int64(rnode.getBatteryPercent())))
            }

            kv("bitrate", .int(Int64(iface.bitrate)))
            kv("rxs",     .double(t.currentRxSpeed(for: iface)))
            kv("txs",     .double(t.currentTxSpeed(for: iface)))

            // Announce and path-request speeds. Python reads `current_arx_speed` and its
            // three siblings behind a `hasattr`, falling through to 0 in the `else`
            // (`Reticulum.py:1481-1502`), so the keys are always present. The `else` is
            // effectively dead on a running daemon: `count_traffic_loop` assigns all four on
            // every interface it has sampled twice (`Transport.py:631-636`), so a Python peer
            // reports live rates here, not zeros.
            let speeds = t.announceSpeeds(for: iface)
            kv("arxs", .double(speeds.announceRx))
            kv("atxs", .double(speeds.announceTx))
            kv("prxs", .double(speeds.pathRequestRx))
            kv("ptxs", .double(speeds.pathRequestTx))

            // Peer count, published for every interface that keeps a peer table
            // (`Reticulum.py:1501-1503`). `rnstatus` prints it as "N reachable" and also falls
            // back to it for the client column when an interface reports no `clients`
            // (`rnstatus.py:555, 617, 642`), so an interface that keeps peers and stays silent
            // here reads as having none.
            if let auto = iface as? AutoInterface {
                kv("peers", .int(Int64(auto.peerCount)))
            } else if let weave = iface as? WeaveInterface {
                kv("peers", .int(Int64(weave.peers.count)))
            }

            // IFAC fields. Python's order is signature, size, netname.
            if let ifacIdentity = iface.ifacIdentity {
                // Python: interface.ifac_signature = ifac_identity.sign(full_hash(ifac_key))
                // (Reticulum.py:933). This is a signature over the key, not the key itself—rnstatus
                // prints its last 5 bytes as the network's "Access" fingerprint, so
                // reporting the raw key here makes a Swift node's access code differ from a
                // Python node's on the very same IFAC network.
                let signature: MsgPack.Value = iface.ifacKey
                    .flatMap { key -> MsgPack.Value? in
                        (try? ifacIdentity.sign(Identity.fullHash(key))).map { .bytes($0) }
                    } ?? .nil
                kv("ifac_signature", signature)
                kv("ifac_size",      .int(Int64(iface.ifacSize)))
            } else {
                kv("ifac_signature", .nil)
                kv("ifac_size",      .nil)
            }
            // Python: `interface.ifac_netname` (`Reticulum.py:955`). Hardcoded nil until
            // `bugs/015`, because nothing stored it—so an operator couldn't see which IFAC
            // segment an interface was on, where a Python daemon reports it.
            kv("ifac_netname", iface.ifacNetname.map { .string($0) } ?? .nil)
            kv("autoconnect_source", .nil)

            // Python creates `announce_queue` lazily, the first time an announce is actually
            // queued on an interface (Transport.py:1277, 2827), and emits the key only when
            // `hasattr` succeeds. rnstatus tests `if "announce_queue" in ifstat`, so emitting
            // it unconditionally would claim a queue that Python would not have reported.
            if let qCount = t.announceQueueCount(for: iface) {
                kv("announce_queue", .int(Int64(qCount)))
            }

            kv("name",       .string(iface.displayName))
            kv("short_name", .string(iface.statsShortName))
            kv("hash",       .bytes(Hashes.fullHash(Data(iface.displayName.utf8))))
            kv("type",       .string(iface.statsTypeName))

            // Python emits `interface.HW_MTU`, a class attribute every interface defines
            // (`Reticulum.py:1531`). rnstatus prints it beside the bitrate and reads it
            // without a membership guard once `bitrate` is present, so it cannot be omitted.
            kv("mtu",        iface.hwMtu.map { .int(Int64($0)) } ?? .nil)
            kv("rxb",        .int(Int64(iface.rxBytes)))
            kv("txb",        .int(Int64(iface.txBytes)))

            let counts = t.interfaceCounts(for: iface)
            kv("arxb", .int(Int64(counts.announceRxBytes)))
            kv("atxb", .int(Int64(counts.announceTxBytes)))
            kv("arxc", .int(Int64(counts.announceRxCount)))
            kv("atxc", .int(Int64(counts.announceTxCount)))
            kv("prxb", .int(Int64(counts.pathRequestRxBytes)))
            kv("ptxb", .int(Int64(counts.pathRequestTxBytes)))
            kv("prxc", .int(Int64(counts.pathRequestRxCount)))
            kv("ptxc", .int(Int64(counts.pathRequestTxCount)))

            // Transmit-drop accounting. `rnstatus` reads `ifstat["txdrp"]` as a bare
            // subscript (`rnstatus.py:495`)—note the `if "bitrate" in ifstat` guard on the
            // very next line, which is what marks this one as an upstream oversight rather
            // than a contract. Omitting the key makes the reference utility raise KeyError
            // and print nothing for any interface.
            //
            // Only `LocalInterface` and `BackboneInterface`'s epoll dataplane ever move
            // these off their defaults (`LocalInterface.py:223`, `BackboneInterface.py:1036`),
            // both through the `TransmitBuffer` this port deliberately does not have. For
            // every other interface a Python daemon reports exactly these values.
            kv("txdrp",      .int(0))
            kv("txdrb",      .int(0))
            kv("txstalled",  .bool(false))
            kv("txbuffered", .int(0))

            kv("incoming_announce_frequency",  .double(t.incomingAnnounceFrequency(for: iface)))
            kv("outgoing_announce_frequency",  .double(t.outgoingAnnounceFrequency(for: iface)))
            kv("incoming_pr_frequency",        .double(t.incomingPathRequestFrequency(for: iface)))
            kv("outgoing_pr_frequency",        .double(t.outgoingPathRequestFrequency(for: iface)))

            if let target = iface.announceRateTarget {
                kv("announce_rate_target", .double(target))
            } else {
                kv("announce_rate_target", .nil)
            }
            kv("announce_rate_penalty", .double(iface.announceRatePenalty))
            kv("announce_rate_grace",   .int(Int64(iface.announceRateGrace)))
            kv("held_announces",        .int(Int64(t.heldAnnounceCount(for: iface))))

            let ingress = t.ingressState(for: iface)
            kv("burst_active",       .bool(ingress?.burstActive      ?? false))
            kv("burst_activated",    .double(ingress?.burstActivated ?? 0))
            // Python's base `Interface.ic_burst_count` is a property returning None
            // (`Interface.py:341`); only a `BackboneInterface` *server* overrides it, to count
            // how many of its spawned interfaces are bursting (`BackboneInterface.py:189`).
            // This port's Backbone is client-only and spawns nothing, so nil is what a Python
            // daemon reports for every interface this port can have.
            kv("burst_count",        .nil)
            kv("pr_burst_active",    .bool(ingress?.prBurstActive      ?? false))
            kv("pr_burst_activated", .double(ingress?.prBurstActivated ?? 0))
            kv("pr_burst_count",     .nil)

            kv("status", .bool(iface.isOnline))
            kv("mode",   .int(Int64(iface.mode.rawValue)))

            // RNS 1.4.1 added both keys to `get_interface_stats()`; Python's rnstatus
            // reads them and sorts interfaces by gravity when they're present.
            kv("gravity", .int(Int64(iface.gravity)))
            kv("announces_to_internal",
               iface.announcesToInternal.map { MsgPack.Value.bool($0) } ?? .nil)

            kv("protocol_violations", .int(Int64(counts.protocolViolations)))
            kv("ifac_violations",     .int(Int64(counts.ifacViolations)))
            kv("packet_filter_hits",  .int(Int64(counts.packetFilterHits)))

            return .map(pairs)
        }

        let tStats = t.getTransportStats()
        var topPairs: [(MsgPack.Value, MsgPack.Value)] = [
            (.string("interfaces"), .array(interfaceValues)),
            (.string("rxb"),        .int(Int64(tStats.trafficRxBytes))),
            (.string("txb"),        .int(Int64(tStats.trafficTxBytes))),
            (.string("rxs"),        .double(tStats.speedRx)),
            (.string("txs"),        .double(tStats.speedTx)),
            // The announce and path-request aggregates `rnstatus -t -A` and `-t -P` read.
            // Python indexes several of these with no presence guard, so a daemon that omits
            // them makes the peer's own tool raise KeyError and print nothing at all.
            (.string("arxb"),       .int(Int64(tStats.announceRxBytes))),
            (.string("atxb"),       .int(Int64(tStats.announceTxBytes))),
            (.string("arxs"),       .double(tStats.announceSpeedRx)),
            (.string("atxs"),       .double(tStats.announceSpeedTx)),
            (.string("arxf"),       .double(tStats.announceFreqRx)),
            (.string("atxf"),       .double(tStats.announceFreqTx)),
            (.string("prxb"),       .int(Int64(tStats.prRxBytes))),
            (.string("ptxb"),       .int(Int64(tStats.prTxBytes))),
            (.string("prxs"),       .double(tStats.prSpeedRx)),
            (.string("ptxs"),       .double(tStats.prSpeedTx)),
            (.string("prxf"),       .double(tStats.prFreqRx)),
            (.string("ptxf"),       .double(tStats.prFreqTx)),
            (.string("rxpps"),      .int(Int64(tStats.rxPPS))),
            (.string("txpps"),      .int(Int64(tStats.txPPS))),
        ]

        // Inbound queue depths and pressures, read by `rnstatus -q` (`rnstatus.py:784-800`),
        // again without presence guards.
        //
        // Python fills these from `Transport.inbound_queues.snapshot()`—the traffic-class
        // worker queues. This port has no such queues: `handleIncoming` runs the frame to
        // completion on the receiving interface's own thread, so the momentary depth really
        // is zero and no frame is ever dropped for want of queue space. Zero is therefore
        // the accurate reading, not a placeholder, and it stops a Python peer's `-q` from
        // failing outright. If the queues are ever ported, these read from the snapshot and
        // the pressures gain real denominators.
        //
        // The pressures go out as floats. Python's `x/tql if x else 0` idiom emits an *int*
        // zero on an idle node and a float otherwise, so every reader already handles both;
        // a ratio that keeps one type is the better of the two behaviours to copy.
        for key in ["rxqt", "rxqd", "rxqa", "rxqp", "rxqil",
                    "rxqtd", "rxqdd", "rxqad", "rxqpd", "rxqild"] {
            topPairs.append((.string(key), .int(0)))
        }
        for key in ["tqpressure", "dqpressure", "aqpressure", "pqpressure", "ilqpressure"] {
            topPairs.append((.string(key), .double(0)))
        }
        // `stats["txq"] = None` unconditionally in Python too (`Reticulum.py:1613`).
        topPairs.append((.string("txq"), .nil))

        if t.transportEnabled, let tid = t.transportIdentity {
            topPairs.append((.string("transport_id"), .bytes(tid.hash)))
            if let netID = t.networkIdentity {
                topPairs.append((.string("network_id"), .bytes(netID.hash)))
            } else {
                topPairs.append((.string("network_id"), .nil))
            }
            let uptime = t.startTime > 0 ? now - t.startTime : 0
            topPairs.append((.string("transport_uptime"), .double(uptime)))
            if let probe = t.probeDestination {
                topPairs.append((.string("probe_responder"), .bytes(probe.hash)))
            } else {
                topPairs.append((.string("probe_responder"), .nil))
            }
        }

        // Python emits `rss` LAST, after the optional transport block
        // (Reticulum.py:1459-1467). `rnstatus -j` preserves dict insertion order, so the
        // position is part of the output contract. Swift has no psutil equivalent, so the
        // value is always nil—matching Python's `find_spec('psutil') == None` branch.
        topPairs.append((.string("rss"), .nil))

        return .map(topPairs)
    }
}
