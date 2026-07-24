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
    public static var empty: MsgPack.Value {
        .map([
            (.string("interfaces"), .array([])),
            (.string("rxb"),        .int(0)),
            (.string("txb"),        .int(0)),
            (.string("rxs"),        .double(0)),
            (.string("txs"),        .double(0)),
            (.string("rss"),        .nil),
        ])
    }

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

            // RNodeSubInterface: parent_interface_name/hash (not yet wired — RNodeSubInterface
            // has no back-reference to the parent RNodeMultiInterface). Python emits them here,
            // between `clients` and the I2P block; rnstatus handles their absence.

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

            // WeaveInterfacePeer: switch_id, via_switch_id, endpoint_id.
            if let weave = iface as? WeaveInterfacePeer {
                kv("switch_id",     weave.switchID.map    { .string($0.hexString) } ?? .nil)
                kv("via_switch_id", weave.viaSwitchID.map { .string($0.hexString) } ?? .nil)
                kv("endpoint_id",   weave.endpointID.map  { .string($0.hexString) } ?? .nil)
            }

            if let rnode = iface as? RNodeInterface,
               rnode.getBatteryState() != RNodeInterface.batteryStateUnknown {
                kv("battery_state",   .string(rnode.getBatteryStateString()))
                kv("battery_percent", .int(Int64(rnode.getBatteryPercent())))
            }

            kv("bitrate", .int(Int64(iface.bitrate)))
            kv("rxs",     .double(t.currentRxSpeed(for: iface)))
            kv("txs",     .double(t.currentTxSpeed(for: iface)))

            // IFAC fields. Python's order is signature, size, netname.
            if let ifacIdentity = iface.ifacIdentity {
                // Python: interface.ifac_signature = ifac_identity.sign(full_hash(ifac_key))
                // (Reticulum.py:933). This is a signature over the key, not the key itself —
                // rnstatus prints its last 5 bytes as the network's "Access" fingerprint, so
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
            // ifac_netname is not stored in the Swift interface protocol; always nil
            kv("ifac_netname", .nil)
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
            kv("rxb",        .int(Int64(iface.rxBytes)))
            kv("txb",        .int(Int64(iface.txBytes)))

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
            kv("pr_burst_active",    .bool(ingress?.prBurstActive      ?? false))
            kv("pr_burst_activated", .double(ingress?.prBurstActivated ?? 0))

            kv("status", .bool(iface.isOnline))
            kv("mode",   .int(Int64(iface.mode.rawValue)))

            return .map(pairs)
        }

        let tStats = t.getTransportStats()
        var topPairs: [(MsgPack.Value, MsgPack.Value)] = [
            (.string("interfaces"), .array(interfaceValues)),
            (.string("rxb"),        .int(Int64(tStats.trafficRxBytes))),
            (.string("txb"),        .int(Int64(tStats.trafficTxBytes))),
            (.string("rxs"),        .double(tStats.speedRx)),
            (.string("txs"),        .double(tStats.speedTx)),
        ]

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
        // value is always nil — matching Python's `find_spec('psutil') == None` branch.
        topPairs.append((.string("rss"), .nil))

        return .map(topPairs)
    }
}
