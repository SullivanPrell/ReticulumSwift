import XCTest
@testable import ReticulumSwift

/// Every key Python's `get_interface_stats` emits unconditionally must appear in this
/// port's payload, in Python's order.
///
/// `rnstatus` guards most of its reads with `if "key" in ifstat`, which is why a missing
/// optional key degrades gracefully. It doesn't guard all of them. `ifstat["txdrp"]` is a
/// bare subscript (`rnstatus.py:495`)—and the `if "bitrate" in ifstat` on the very next
/// line is what marks that as an upstream oversight rather than a contract. Against a
/// daemon that omits the key, the reference utility raises `KeyError` and prints nothing
/// at all, so a single absent key takes out the whole interface listing.
///
/// The expected list below is the unconditional tail of `get_interface_stats`
/// (`Reticulum.py:1527-1566`), transcribed in source order. Order matters as much as
/// presence: `rnstatus -j` serialises the dictionary with `json.dumps`, which preserves
/// insertion order, so the key sequence is part of the `-j` output contract.
final class InterfaceStatsKeyParityTests: XCTestCase {

    /// `Reticulum.py:1527-1566`, in source order.
    private static let pythonMandatoryKeys = [
        "name", "short_name", "hash", "type", "mtu", "rxb", "txb",
        "arxb", "atxb", "arxc", "atxc", "prxb", "ptxb", "prxc", "ptxc",
        "txdrp", "txdrb", "txstalled", "txbuffered",
        "incoming_announce_frequency", "outgoing_announce_frequency",
        "incoming_pr_frequency", "outgoing_pr_frequency",
        "announce_rate_target", "announce_rate_penalty", "announce_rate_grace",
        "held_announces",
        "burst_active", "burst_activated", "burst_count",
        "pr_burst_active", "pr_burst_activated", "pr_burst_count",
        "status", "mode", "gravity", "announces_to_internal",
        "protocol_violations", "ifac_violations", "packet_filter_hits",
    ]

    private func emittedKeys() throws -> [String] {
        let transport = Transport()
        let udp = UDPInterface(name: "Key Parity", listenPort: 4242, forwardPort: 4243)
        transport.register(interface: udp)
        defer { transport.deregister(interface: udp) }

        let payload = InterfaceStatsPayload.build(transport)
        let interfaces = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray)
        let first = try XCTUnwrap(interfaces.first)
        guard case .map(let pairs) = first else {
            XCTFail("an interface entry must be a map"); return []
        }
        return pairs.compactMap { pair in
            if case .string(let k) = pair.0 { return k }
            return nil
        }
    }

    func testPayloadCarriesEveryKeyPythonEmitsUnconditionally() throws {
        let emitted = Set(try emittedKeys())
        let missing = Self.pythonMandatoryKeys.filter { !emitted.contains($0) }
        XCTAssertEqual(missing, [],
                       "Python's rnstatus reads txdrp without a membership guard, so any of "
                       + "these missing takes out the interface listing with a KeyError")
    }

    func testTheMandatoryKeysAppearInPythonsOrder() throws {
        let emitted = try emittedKeys()
        let positions = Self.pythonMandatoryKeys.compactMap { emitted.firstIndex(of: $0) }
        XCTAssertEqual(positions.count, Self.pythonMandatoryKeys.count,
                       "every mandatory key must be present before order can be checked")
        XCTAssertEqual(positions, positions.sorted(),
                       "rnstatus -j preserves dict insertion order, so the sequence is part "
                       + "of the output contract")
    }
}
