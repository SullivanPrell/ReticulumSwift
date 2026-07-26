import Foundation

/// The whole `rnstatus` rendering layer, as pure functions of a decoded stats snapshot.
///
/// Python reference: `RNS/Utilities/rnstatus.py`, `program_setup` (rnstatus.py:155-685).
/// Everything here returns a `String` instead of printing, so the golden output can be
/// asserted from XCTest with no terminal, no socket and no live stack. `now` is injected
/// for the same reason — several lines are age-dependent.
///
/// Trailing whitespace on the frequency and traffic lines is **significant**: Python pads
/// the columns to a common width and then appends possibly-empty suffixes, so those lines
/// routinely end in spaces. The renderer reproduces that byte for byte.
public struct RNStatusRenderer {

    // MARK: - Options

    /// The subset of `program_setup`'s parameters that affects rendering.
    public struct Options {
        /// `-a, --all`. Python: `dispall`.
        public var showAll: Bool = false
        /// `-A, --announce-stats`. Python: `astats`.
        public var announceStats: Bool = false
        /// `-P, --pr-stats`. Python: `pstats`.
        public var prStats: Bool = false
        /// `-l, --link-stats`. Python: `lstats`.
        public var linkStats: Bool = false
        /// `-B, --burst`. Python: `burst_filter`.
        public var burstFilter: Bool = false
        /// `-t, --totals`. Python: `traffic_totals`.
        public var trafficTotals: Bool = false
        /// Positional `filter`. Python: `name_filter`.
        public var nameFilter: String? = nil
        /// `-s, --sort`. Python: `sorting`.
        public var sort: RNStatusApp.Sort? = nil
        /// `-r, --reverse`. Python: `sort_reverse`.
        public var sortReverse: Bool = false

        public init() {}
    }

    public let options: Options
    public let now: TimeInterval

    public init(options: Options = Options(), now: TimeInterval = Date().timeIntervalSince1970) {
        self.options = options
        self.now = now
    }

    // MARK: - Top level

    /// Render everything `program_setup` prints for a successful stats fetch:
    /// the per-interface blocks, the optional `-t` totals, the transport footer (or the
    /// bare link-table line) and the unconditional trailing blank line.
    ///
    /// Python: rnstatus.py:361-675.
    public func render(stats: RNStatusStats, linkCount: Int?) -> String {
        var out = ""

        let ordered = stats.sortedInterfaces(by: options.sort, reverse: options.sortReverse)
        for ifstat in ordered {
            guard !RNStatusStats.shouldHide(ifstat, showAll: options.showAll) else { continue }
            guard RNStatusStats.passesFilters(ifstat,
                                              nameFilter: options.nameFilter,
                                              burstFilter: options.burstFilter) else { continue }
            out += renderInterface(ifstat)
        }

        // Python: lstr (rnstatus.py:642-648). Note the leading comma when a transport_id
        // exists — the suffix is designed to ride on the end of the "Uptime is …" line.
        var lstr = ""
        if let linkCount, options.linkStats {
            let plural = linkCount == 1 ? "y" : "ies"
            lstr = stats.hasTransportID
                ? ", \(linkCount) entr\(plural) in link table"
                : " \(linkCount) entr\(plural) in link table"
        }

        // Python: rnstatus.py:650-661.
        if options.trafficTotals {
            var rxbStr = "↓" + RNSUtilities.prettysize(stats.rxb)
            var txbStr = "↑" + RNSUtilities.prettysize(stats.txb)
            let difference = rxbStr.count - txbStr.count
            if difference > 0 {
                txbStr += String(repeating: " ", count: difference)
            } else if difference < 0 {
                rxbStr += String(repeating: " ", count: -difference)
            }
            let rxstat = rxbStr + "  " + RNSUtilities.prettyspeed(stats.rxs)
            let txstat = txbStr + "  " + RNSUtilities.prettyspeed(stats.txs)
            out += "\n Totals       : \(txstat)\n\(RNStatusApp.continuationIndent)\(rxstat)\n"
        }

        // Python: rnstatus.py:663-675.
        if let transportID = stats.transportID {
            out += "\n Transport Instance " + RNSUtilities.prettyhexrep(transportID) + " running\n"
            if let networkID = stats.networkID {
                out += " Network Identity   " + RNSUtilities.prettyhexrep(networkID) + "\n"
            }
            if let probeResponder = stats.probeResponder {
                out += " Probe responder at " + RNSUtilities.prettyhexrep(probeResponder) + " active\n"
            }
            if stats.transportUptime != nil {
                // NOTE: when transport_uptime is absent, lstr is never printed at all —
                // the link-table suffix only ever rides on this line.
                out += " Uptime is " + Self.prettytime(stats.raw("transport_uptime")) + lstr + "\n"
            }
        } else if !lstr.isEmpty {
            out += "\n\(lstr)\n"
        }

        out += "\n"     // Python's unconditional final print("")
        return out
    }

    // MARK: - One interface

    /// Render one interface block, including the blank line Python prints before it.
    /// Python: rnstatus.py:415-640.
    public func renderInterface(_ ifstat: RNStatusInterfaceStats) -> String {
        var out = "\n"
        let name = ifstat.name

        // --- Clients / Serving / Peers line (rnstatus.py:430-458) ---
        // Python leaves `clients_string` unbound when clients is None; the print site is
        // guarded by `clients != None`, so an Optional models it exactly.
        var clients: Int? = ifstat.int("clients")
        var clientsString: String? = nil
        if let count = clients {
            if name.hasPrefix("Shared Instance[") {
                // Python subtracts one for rnstatus's own local-client attachment.
                let visible = max(count - 1, 0)
                clientsString = "Serving   : \(visible)\(visible == 1 ? " program" : " programs")"
            } else if name.hasPrefix("I2PInterface[") {
                if ifstat.has("i2p_connectable"), ifstat.bool("i2p_connectable") == true {
                    clientsString = "Peers     : \(count)\(count == 1 ? " connected I2P endpoint" : " connected I2P endpoints")"
                } else {
                    clientsString = ""
                }
            } else {
                var text = "Clients   : \(count)"
                if ifstat.has("blocked_ips"), let blocked = ifstat.int("blocked_ips"), blocked > 0 {
                    // Python: `"…"+str(n)+" IP"+"s" if p else ""` — the conditional binds
                    // around the whole right-hand side and sits inside `if p:`, so the
                    // count is always pluralised.
                    text += "\n    Blocked   : \(blocked) IPs"
                }
                clientsString = text
            }
        }

        // --- Header lines (rnstatus.py:460-477) ---
        out += " \(name)\n"

        if ifstat.has("autoconnect_source"), let source = ifstat.string("autoconnect_source") {
            out += "    Source    : Auto-connect via <\(source)>\n"
        }
        if ifstat.has("ifac_netname"), let netname = ifstat.string("ifac_netname") {
            out += "    Network   : \(netname)\n"
        }
        out += "    Status    : \(ifstat.isUp ? "Up" : "Down")\n"

        if let clientsString, clients != nil, !clientsString.isEmpty {
            out += "    " + clientsString + "\n"
        }

        if !(name.hasPrefix("Shared Instance[")
             || name.hasPrefix("TCPInterface[Client")
             || name.hasPrefix("LocalInterface[")) {
            out += "    Mode      : \(ifstat.modeDescription)\n"
        }

        if ifstat.has("bitrate"), let bitrate = ifstat.double("bitrate") {
            out += "    Rate      : \(RNStatusApp.speedStr(bitrate))\n"
        }

        // --- Radio / host telemetry (rnstatus.py:479-519) ---
        if ifstat.has("noise_floor") {
            var nstr = ""
            if ifstat.has("interference") {
                let interference = ifstat.raw("interference") ?? .nil
                var lstr = ", no interference"
                if ifstat.has("interference_last_ts"), ifstat.has("interference_last_dbm") {
                    let ago = now - (ifstat.double("interference_last_ts") ?? 0)
                    let dbm = Self.pythonStr(ifstat.raw("interference_last_dbm") ?? .nil)
                    lstr = "\n    Intrfrnc. : \(dbm) dBm \(Self.prettytime(ago, isFloat: true, compact: true)) ago"
                }
                // Python: `f"…{nf} dBm" if nf else lstr` — nf == 0 is falsy too, so a
                // zero reading takes the "last seen" branch rather than printing "0 dBm".
                nstr = Self.isTruthy(interference) ? "\n    Intrfrnc. : \(Self.pythonStr(interference)) dBm" : lstr
            }
            if let floor = ifstat.raw("noise_floor"), !floor.isNil {
                out += "    Noise Fl. : \(Self.pythonStr(floor)) dBm\(nstr)\n"
            } else {
                out += "    Noise Fl. : Unknown\n"
            }
        }

        if ifstat.has("cpu_load") {
            if let value = ifstat.raw("cpu_load"), !value.isNil {
                out += "    CPU load  : \(Self.pythonStr(value)) %\n"
            } else {
                out += "    CPU load  : Unknown\n"
            }
        }

        if ifstat.has("cpu_temp") {
            if let value = ifstat.raw("cpu_temp"), !value.isNil {
                out += "    CPU temp  : \(Self.pythonStr(value))°C\n"
            } else {
                // PYTHON BUG, mirrored verbatim: the nil branch prints the label
                // "CPU load" rather than "CPU temp" (rnstatus.py:501).
                out += "    CPU load  : Unknown\n"
            }
        }

        if ifstat.has("mem_load") {
            // PYTHON BUG, mirrored: the line is gated on `ifstat["cpu_load"]`, not
            // `ifstat["mem_load"]` (rnstatus.py:504). DELIBERATE DIVERGENCE: Python raises
            // an uncaught KeyError — aborting the whole run — when `mem_load` is present
            // without `cpu_load`; Swift treats the absent key as nil and prints "Unknown".
            if let cpuLoad = ifstat.raw("cpu_load"), !cpuLoad.isNil {
                out += "    Mem usage : \(Self.pythonStr(ifstat.raw("mem_load") ?? .nil)) %\n"
            } else {
                out += "    Mem usage : Unknown\n"
            }
        }

        if ifstat.has("battery_percent"), let percent = ifstat.double("battery_percent") {
            // Python wraps this in try/except: a missing `battery_state` silently drops
            // just this line.
            if let state = ifstat.string("battery_state") {
                out += "    Battery   : \(Int(percent))% (\(state))\n"
            }
        }

        if ifstat.has("airtime_short"), ifstat.has("airtime_long") {
            out += "    Airtime   : \(Self.pythonStr(ifstat.raw("airtime_short") ?? .nil))% (15s), "
                 + "\(Self.pythonStr(ifstat.raw("airtime_long") ?? .nil))% (1h)\n"
        }
        if ifstat.has("channel_load_short"), ifstat.has("channel_load_long") {
            out += "    Ch. Load  : \(Self.pythonStr(ifstat.raw("channel_load_short") ?? .nil))% (15s), "
                 + "\(Self.pythonStr(ifstat.raw("channel_load_long") ?? .nil))% (1h)\n"
        }

        // --- Weave / I2P / IFAC (rnstatus.py:521-544) ---
        out += Self.optionalLine("    Switch ID : ", ifstat, "switch_id")
        out += Self.optionalLine("    Endpoint  : ", ifstat, "endpoint_id")
        out += Self.optionalLine("    Via       : ", ifstat, "via_switch_id")

        if ifstat.has("peers"), let peers = ifstat.raw("peers"), !peers.isNil {
            out += "    Peers     : \(Self.pythonStr(peers)) reachable\n"
        }
        if ifstat.has("tunnelstate"), let state = ifstat.raw("tunnelstate"), !state.isNil {
            out += "    I2P       : \(Self.pythonStr(state))\n"
        }
        if ifstat.has("ifac_signature"), let signature = ifstat.data("ifac_signature") {
            let sigstr = "<…" + RNSUtilities.hexrep(signature.suffix(5), delimit: false) + ">"
            let bits = (ifstat.int("ifac_size") ?? 0) * 8
            out += "    Access    : \(bits)-bit IFAC by \(sigstr)\n"
        }
        if ifstat.has("i2p_b32"), let endpoint = ifstat.raw("i2p_b32"), !endpoint.isNil {
            out += "    I2P B32   : \(Self.pythonStr(endpoint))\n"
        }

        // --- Announce queue / held (rnstatus.py:546-558), -A only ---
        if options.announceStats, ifstat.has("announce_queue"),
           let queued = ifstat.int("announce_queue"), queued > 0 {
            out += "    Queued    : \(queued)\(queued == 1 ? " announce" : " announces")\n"
        }
        if options.announceStats, ifstat.has("held_announces"),
           let held = ifstat.int("held_announces"), held > 0 {
            out += "    Held      : \(held)\(held == 1 ? " announce" : " announces")\n"
        }

        // --- Announce-rate suffix and burst strings (rnstatus.py:560-577) ---
        let target  = options.announceStats && ifstat.has("announce_rate_target")  ? ifstat.raw("announce_rate_target")  : nil
        let penalty = options.announceStats && ifstat.has("announce_rate_penalty") ? ifstat.raw("announce_rate_penalty") : nil
        let grace   = options.announceStats && ifstat.has("announce_rate_grace")   ? ifstat.raw("announce_rate_grace")   : nil

        // Python truthiness: `art == 0` and `arg == 0` are falsy; `arp` is tested against
        // None, so a zero penalty still counts.
        let hasTarget  = target.map(Self.isTruthy) ?? false
        let hasGrace   = grace.map(Self.isTruthy) ?? false
        let hasPenalty = penalty.map { !$0.isNil } ?? false

        var artStr = ""
        if hasTarget && hasPenalty && hasGrace {
            artStr = "(t:\(Self.prettytime(target))/p:\(Self.prettytime(penalty))"
                   + "/g:\(Self.pythonStr(grace ?? .nil)))"
        } else if hasTarget && hasPenalty {
            artStr = "(t:\(Self.prettytime(target))/p:\(Self.prettytime(penalty)))"
        } else if hasTarget {
            artStr = "(t:\(Self.prettytime(target)))"
        }

        // `time.time() - burst_activated` is always a float in Python, so the seconds
        // component renders in float form ("burst for 8.0s", not "8s").
        var burstStr = ""
        if ifstat.has("burst_active"), ifstat.bool("burst_active") == true {
            let elapsed = now - (ifstat.double("burst_activated") ?? 0)
            burstStr = " burst for \(Self.prettytime(elapsed, isFloat: true))"
        }
        var pburstStr = ""     // no leading space, unlike burstStr
        if ifstat.has("pr_burst_active"), ifstat.bool("pr_burst_active") == true {
            let elapsed = now - (ifstat.double("pr_burst_activated") ?? 0)
            pburstStr = "burst for \(Self.prettytime(elapsed, isFloat: true))"
        }

        // --- Frequency / traffic columns (rnstatus.py:579-640) ---
        var rxbStr = "↓" + RNSUtilities.prettysize(ifstat.int("rxb") ?? 0)
        var txbStr = "↑" + RNSUtilities.prettysize(ifstat.int("txb") ?? 0)

        func frequency(_ value: Double) -> String {
            RNSUtilities.prettyfrequency(value, d: 1, lpf: true)
        }

        var iaf = "", oaf = "", ipf = "", opf = ""
        var pcStr = "", rpcStr = ""
        var asr = false, psr = false

        if options.announceStats, ifstat.has("incoming_announce_frequency"),
           let incoming = ifstat.double("incoming_announce_frequency") {
            let rawOutgoing = ifstat.double("outgoing_announce_frequency") ?? 0
            var outgoing = rawOutgoing
            if name.hasPrefix("Shared Instance["), let count = clients, count > 0 {
                outgoing -= outgoing / Double(count)     // subtract rnstatus's own share
            }
            oaf = frequency(outgoing)
            iaf = frequency(incoming)

            var cspec = "c"
            // NOTE: this mutates `clients` and the mutation is visible to the
            // path-request block below — Python does the same.
            if clients == nil, ifstat.has("peers"), let peers = ifstat.int("peers"), peers != 0 {
                clients = peers
                cspec = "p"
            }
            if let count = clients, count > 0 {
                // Python divides the RAW outgoing frequency here, not the adjusted one.
                pcStr = "\(frequency(rawOutgoing / Double(count)))/\(cspec)"
            }
            asr = true
        }

        if options.prStats, ifstat.has("incoming_pr_frequency"),
           let incoming = ifstat.double("incoming_pr_frequency") {
            let rawOutgoing = ifstat.double("outgoing_pr_frequency") ?? 0
            var outgoing = rawOutgoing
            if name.hasPrefix("Shared Instance["), let count = clients, count > 0 {
                outgoing -= outgoing / Double(count)
            }
            if options.announceStats {
                opf = "↑" + frequency(outgoing)
                ipf = "↓" + frequency(incoming)
            } else {
                opf = frequency(outgoing) + "↑"
                ipf = frequency(incoming) + "↓"
            }
            var cspec = "c"
            if clients == nil, ifstat.has("peers"), let peers = ifstat.int("peers"), peers != 0 {
                clients = peers
                cspec = "p"
            }
            if let count = clients, count > 0 {
                rpcStr = "\(frequency(rawOutgoing / Double(count)))/\(cspec)"
            }
            psr = true
        }

        // Padding, in CHARACTERS — "↑"/"↓" are one character but three UTF-8 bytes.
        if !asr { iaf = ""; oaf = "" }
        if !psr { ipf = ""; opf = "" }
        let amlen = max(iaf.count, oaf.count)
        iaf += String(repeating: " ", count: amlen - iaf.count) + "↓"
        oaf += String(repeating: " ", count: amlen - oaf.count) + "↑"
        let mlen = max(max(iaf.count, oaf.count, rxbStr.count, txbStr.count, ipf.count, opf.count),
                       RNStatusApp.minimumColumnWidth)
        iaf    += String(repeating: " ", count: mlen - iaf.count)
        oaf    += String(repeating: " ", count: mlen - oaf.count)
        ipf    += String(repeating: " ", count: mlen - ipf.count)
        opf    += String(repeating: " ", count: mlen - opf.count)
        rxbStr += String(repeating: " ", count: mlen - rxbStr.count)
        txbStr += String(repeating: " ", count: mlen - txbStr.count)

        // Path Rqs. is printed BEFORE Announces even though the announce block above
        // computed first (rnstatus.py:626-632).
        if psr {
            out += "    Path Rqs. : \(opf)  \(rpcStr)\n"
            out += "\(RNStatusApp.continuationIndent)\(ipf)  \(pburstStr)\n"
        }
        if asr {
            out += "    Announces : \(oaf)  \(pcStr)\n"
            out += "\(RNStatusApp.continuationIndent)\(iaf) \(artStr)\(burstStr)\n"
        }

        var rxstat = rxbStr
        var txstat = txbStr
        if ifstat.has("rxs"), ifstat.has("txs") {
            rxstat += "  " + RNSUtilities.prettyspeed(ifstat.double("rxs") ?? 0)
            txstat += "  " + RNSUtilities.prettyspeed(ifstat.double("txs") ?? 0)
        }
        out += "    Traffic   : \(txstat)\n\(RNStatusApp.continuationIndent)\(rxstat)\n"

        return out
    }

    // MARK: - Discovered interfaces (-d)

    /// The `-d` table. Python: rnstatus.py:264-306.
    ///
    /// Column widths are Python `str.format` `<N` specifiers, which pad but **never
    /// truncate** — an over-long Type pushes the rest of the row right. Only Name is
    /// explicitly clipped. All widths count characters, so the ✓/×/… markers are 1 wide.
    ///
    /// The caller-supplied order is preserved; `listDiscoveredInterfaces()` has already
    /// sorted descending on `(statusCode, value, lastHeard)`.
    public func renderDiscoveredTable(_ interfaces: [DiscoveredInterfaceInfo]) -> String {
        var out = "\n"     // rnstatus.py:185 — unconditional, before any mode branch
        out += Self.pad("Name", 25) + " " + Self.pad("Type", 12) + " " + Self.pad("Status", 12)
             + " " + Self.pad("Last Heard", 12) + " " + Self.pad("Value", 8) + " "
             + Self.pad("Location", 15) + "\n"
        out += String(repeating: "-", count: RNStatusApp.discoveredTableRuleWidth) + "\n"

        for info in filtered(interfaces) {
            let name = info.name.count > 24 ? String(info.name.prefix(24)) + "…" : info.name
            let type = info.type.replacingOccurrences(of: "Interface", with: "")

            let statusDisplay: String
            switch info.status {
            case "available": statusDisplay = "✓ Available"
            case "unknown":   statusDisplay = "? Unknown"
            case "stale":     statusDisplay = "× Stale"
            default:          statusDisplay = info.status ?? ""
            }

            let difference = now - info.lastHeard
            let lastHeardDisplay: String
            if difference < 60         { lastHeardDisplay = "Just now" }
            else if difference < 3600  { lastHeardDisplay = "\(Int(difference / 60))m ago" }
            else if difference < 86400 { lastHeardDisplay = "\(Int(difference / 3600))h ago" }
            else                       { lastHeardDisplay = "\(Int(difference / 86400))d ago" }

            let location: String
            if let latitude = info.latitude, let longitude = info.longitude {
                location = "\(Self.pythonRound(latitude, 4)), \(Self.pythonRound(longitude, 4))"
            } else {
                location = "N/A"
            }

            out += Self.pad(name, 25) + " " + Self.pad(type, 12) + " " + Self.pad(statusDisplay, 12)
                 + " " + Self.pad(lastHeardDisplay, 12) + " " + Self.pad("\(info.value)", 8)
                 + " " + Self.pad(location, 15) + "\n"
        }
        return out
    }

    /// The `-D` detail view. Python: rnstatus.py:201-262.
    ///
    /// Python wraps each entry in a bare `try/except: pass` spanning the *whole* render,
    /// so an entry missing `config_entry` prints its full header block and then simply
    /// stops — no separator, no diagnostic. That behaviour is reproduced here.
    ///
    /// DELIBERATE DIVERGENCE, one case: a `KISSInterface` discovery record always carries a
    /// `frequency` key, sometimes with a null value. Python's `f"{None:,}"` then raises and
    /// the entry is abandoned just after `Location`, dropping its Stamp Value and
    /// Configuration Entry. `DiscoveredInterfaceInfo.frequency` is a `Double?`, which
    /// cannot tell present-and-null from absent, so Swift skips the Frequency line and
    /// renders the rest of the entry. Verified against the live store: this is the only
    /// difference in a 9,700-line `-D` dump.
    public func renderDiscoveredDetails(_ interfaces: [DiscoveredInterfaceInfo]) -> String {
        var out = "\n"
        for (index, info) in filtered(interfaces).enumerated() {
            if index > 0 {
                out += "\n" + String(repeating: "=", count: RNStatusApp.detailSeparatorWidth) + "\n\n"
            }

            let statusDisplay: String
            switch info.status {
            case "available": statusDisplay = "Available"
            case "unknown":   statusDisplay = "Unknown"
            case "stale":     statusDisplay = "Stale"
            default:          statusDisplay = info.status ?? ""
            }

            let location: String
            if let latitude = info.latitude, let longitude = info.longitude {
                let height = info.height.map { ", \(Self.pythonFloat($0))m h" } ?? ""
                location = "\(Self.pythonRound(latitude, 4)), \(Self.pythonRound(longitude, 4))\(height)"
            } else {
                location = "Unknown"
            }

            // Both IDs are undelimited hex STRINGS on disk, so this is a string compare
            // and the printed value carries no <> wrapper.
            let network = (!info.transportID.isEmpty && !info.networkID.isEmpty
                           && info.transportID != info.networkID) ? info.networkID : ""

            if !network.isEmpty            { out += "Network   ID : \(network)\n" }
            if !info.transportID.isEmpty   { out += "Transport ID : \(info.transportID)\n" }

            out += "Name         : \(info.name)\n"
            out += "Type         : \(info.type)\n"
            out += "Status       : \(statusDisplay)\n"
            out += "Transport    : \(info.transport ? "Enabled" : "Disabled")\n"
            out += "Distance     : \(info.hops) hop\(info.hops == 1 ? "" : "s")\n"
            out += "Discovered   : \(Self.prettytime(now - info.discovered, isFloat: true, compact: true)) ago\n"
            out += "Last Heard   : \(Self.prettytime(now - info.lastHeard, isFloat: true, compact: true)) ago\n"
            out += "Location     : \(location)\n"

            if let frequency = info.frequency { out += "Frequency    : \(Self.thousands(frequency)) Hz\n" }
            if let bandwidth = info.bandwidth { out += "Bandwidth    : \(Self.thousands(bandwidth)) Hz\n" }
            if let sf = info.sf               { out += "Sprd. Factor : \(sf)\n" }
            if let cr = info.cr               { out += "Coding Rate  : \(cr)\n" }
            if let modulation = info.modulation { out += "Modulation   : \(modulation)\n" }
            if let reachableOn = info.reachableOn { out += "Address      : \(reachableOn)\n" }
            if let port = info.port           { out += "Port         : \(port)\n" }

            out += "Stamp Value  : \(info.value)\n"

            // Python raises KeyError here when the entry has no config_entry, abandoning
            // the rest of the render with everything above already on screen.
            guard let configEntry = info.configEntry else { continue }
            out += "\nConfiguration Entry:\n"
            for line in configEntry.components(separatedBy: "\n") {
                out += "  \(line)\n"
            }
        }
        return out
    }

    /// Python: rnstatus.py:196-199 — case-insensitive substring on the discovered name.
    /// Neither the burst filter nor the interface hide list applies in discovered mode.
    private func filtered(_ interfaces: [DiscoveredInterfaceInfo]) -> [DiscoveredInterfaceInfo] {
        guard let filter = options.nameFilter, !filter.isEmpty else { return interfaces }
        return interfaces.filter { $0.name.lowercased().contains(filter.lowercased()) }
    }

    // MARK: - Formatting helpers

    /// Python `f"{value:<width}"` — pads with spaces, never truncates, counts characters.
    static func pad(_ value: String, _ width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }

    /// Python's `str()` of a decoded msgpack scalar.
    ///
    /// The stats dict carries ints, floats, strings, bools and None interchangeably in the
    /// same field depending on which node produced it, and rnstatus interpolates them with
    /// `str(...)`. Reproducing `str` — rather than a Swift `\(...)` of a coerced type — is
    /// what keeps `41` from becoming `41.0`.
    static func pythonStr(_ value: MsgPack.Value) -> String {
        switch value {
        case .nil:            return "None"
        case .bool(let b):    return b ? "True" : "False"
        case .int(let n):     return "\(n)"
        case .uint(let n):    return "\(n)"
        case .double(let d):  return pythonFloat(d)
        case .string(let s):  return s
        case .bytes(let d):   return RNSUtilities.hexrep(d, delimit: false)
        case .array, .map:    return "\(value)"
        }
    }

    /// Python truthiness for a numeric/None msgpack value: nil and zero are falsy.
    static func isTruthy(_ value: MsgPack.Value) -> Bool {
        switch value {
        case .nil:           return false
        case .bool(let b):   return b
        case .int(let n):    return n != 0
        case .uint(let n):   return n != 0
        case .double(let d): return d != 0
        case .string(let s): return !s.isEmpty
        case .bytes(let d):  return !d.isEmpty
        case .array(let a):  return !a.isEmpty
        case .map(let m):    return !m.isEmpty
        }
    }

    /// `RNS.prettytime`, preserving Python's int-vs-float seconds.
    ///
    /// `RNS/__init__.py:253` does `seconds = round(time, 2)`, which keeps the *type* of
    /// its argument: `prettytime(12)` is `"12s"` but `prettytime(12.0)` is `"12.0s"`.
    /// Verified live: `RNS.prettytime(90.0) == "1m and 30.0s"`.
    ///
    /// ``RNSUtilities/prettytime(_:verbose:compact:)`` takes a `TimeInterval` and always
    /// collapses whole values to `Int`, so it cannot express the float form — and its
    /// int-input behaviour is locked in by `PrettyTimeTests`. rnstatus needs both: the
    /// transport uptime and burst durations arrive as floats, while `announce_rate_target`
    /// is an int from the config file. So `isFloat` carries the wire type through.
    static func prettytime(_ time: Double, isFloat: Bool, compact: Bool = false) -> String {
        var remaining = abs(time)
        let negative = time < 0

        let days    = Int(remaining / 86400); remaining = remaining.truncatingRemainder(dividingBy: 86400)
        let hours   = Int(remaining / 3600);  remaining = remaining.truncatingRemainder(dividingBy: 3600)
        let minutes = Int(remaining / 60);    remaining = remaining.truncatingRemainder(dividingBy: 60)
        // Python: int(time) when compact, else round(time, 2) — banker's on the exact value.
        let seconds: Double = compact ? Double(Int(remaining))
                                      : (Double(String(format: "%.2f", remaining)) ?? remaining)

        var components: [String] = []
        var displayed = 0
        func add(_ value: Int, _ short: String) {
            guard value > 0, !compact || displayed < 2 else { return }
            components.append("\(value)\(short)")
            displayed += 1
        }
        add(days, "d")
        add(hours, "h")
        add(minutes, "m")
        if seconds > 0, !compact || displayed < 2 {
            let text = (compact || !isFloat) ? "\(Int(seconds))" : pythonFloat(seconds)
            components.append(text + "s")
            displayed += 1
        }

        guard !components.isEmpty else { return "0s" }
        var result = ""
        for (index, component) in components.enumerated() {
            if index == 0 { result += component }
            else if index < components.count - 1 { result += ", " + component }
            else { result += " and " + component }
        }
        return negative ? "-\(result)" : result
    }

    /// `prettytime` driven straight off a wire value, so the int/float distinction is kept.
    static func prettytime(_ value: MsgPack.Value?, compact: Bool = false) -> String {
        guard let value, let number = value.asDouble else { return "0s" }
        if case .double = value { return prettytime(number, isFloat: true, compact: compact) }
        return prettytime(number, isFloat: false, compact: compact)
    }

    /// Python `repr(float)` / `str(float)` — shortest representation that round-trips.
    /// Swift's default `Double` description has the same shortest-round-trip contract, so
    /// `55.0` renders as `"55.0"` and `55.6761` as `"55.6761"`, matching Python.
    static func pythonFloat(_ value: Double) -> String {
        if value.isNaN { return "nan" }
        if value.isInfinite { return value < 0 ? "-inf" : "inf" }
        return "\(value)"
    }

    /// Python `str(round(value, digits))`.
    ///
    /// `round(x, n)` rounds the *exact decimal expansion* of the binary double, half to
    /// even — not the scaled value. `(x * 1e4).rounded() / 1e4` gets a different answer
    /// for coordinates whose fifth decimal is a 5 (verified live: `round(3.07455, 4)` is
    /// `3.0745`, while the scale-and-round approach yields `3.0746`). Formatting with
    /// `%.*f` delegates to the C library, which rounds correctly and half-to-even, and
    /// parsing that back yields the same double `round()` returns.
    static func pythonRound(_ value: Double, _ digits: Int) -> String {
        let text = String(format: "%.\(digits)f", value)
        return pythonFloat(Double(text) ?? value)
    }

    /// Python `f"{value:,}"` — comma thousands separators.
    ///
    /// `DiscoveredInterfaceInfo.frequency`/`.bandwidth` are `Double?` in Swift where the
    /// wire carries an int, so an integral value is emitted as `867,200,000` rather than
    /// letting a spurious `.0` leak into the output.
    static func thousands(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return groupInteger("\(Int(value))")
        }
        let text = pythonFloat(value)
        guard let dot = text.firstIndex(of: ".") else { return groupInteger(text) }
        return groupInteger(String(text[text.startIndex..<dot])) + String(text[dot...])
    }

    private static func groupInteger(_ digits: String) -> String {
        var sign = ""
        var body = digits
        if body.hasPrefix("-") { sign = "-"; body.removeFirst() }
        guard body.count > 3 else { return sign + body }
        var grouped: [Character] = []
        for (offset, character) in body.reversed().enumerated() {
            if offset > 0 && offset % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        return sign + String(grouped.reversed())
    }

    /// Python's `if "key" in ifstat: print(label + str(v)) else: print(label + "Unknown")`
    /// shape, used by the Switch ID / Endpoint / Via lines (rnstatus.py:521-531).
    private static func optionalLine(_ label: String,
                                     _ ifstat: RNStatusInterfaceStats,
                                     _ key: String) -> String {
        guard ifstat.has(key) else { return "" }
        if let value = ifstat.raw(key), !value.isNil {
            return label + pythonStr(value) + "\n"
        }
        return label + "Unknown\n"
    }
}
