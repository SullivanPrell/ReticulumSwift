import XCTest
@testable import ReticulumSwift

/// `bugs/025` — spawned-interface attribute inheritance.
///
/// Python copies nineteen attributes onto each accepted client
/// (`RNS/Interfaces/TCPInterface.py:594-641`), and the same block appears in
/// `BackboneInterface.py:467-485`, `AutoInterface.py:559` and `I2PInterface.py:846`.
/// This port propagated four — `ifacIdentity`, `ifacKey`, `ifacSize`, `gravity` — with `bitrate`
/// a fresh hardcoded `10_000_000` at `TCPServerInterface.swift:244` and the rest unpropagatable
/// because they were get-only.
///
/// A spawned client is the real routing endpoint on a server-side interface, so an attribute that
/// does not reach it is inert for every peer that dials in — which is the deployment a Swift hub or
/// RetiOS-on-macOS actually runs.
final class SpawnedInterfaceInheritanceTests: XCTestCase {

    /// Configure a parent the way a config file would, then check the spawned client carries it.
    func testSpawnedClientInheritsEveryConfiguredAttribute() {
        let server = TCPServerInterface(name: "hub", port: 4250)

        // Everything a config file can set on the listening interface.
        server.mode = .gateway
        server.bitrate = 4_242_000
        server.announceCap = 0.05
        server.announceRateTarget = 1800
        server.announceRateGrace = 4
        server.announceRatePenalty = 3600
        server.ingressControl = false
        server.egressControl = true
        server.ecPrFreq = 9.5
        server.gravity = 17
        server.interfaceState.icBurstFreq = 22
        server.interfaceState.icBurstFreqNew = 7
        server.interfaceState.icNewTime = 600
        server.interfaceState.icBurstHold = 30
        server.interfaceState.icBurstPenalty = 45
        server.interfaceState.icHeldReleaseInterval = 8
        server.interfaceState.icPrBurstFreq = 11
        server.interfaceState.icPrBurstFreqNew = 2
        server.ifacSize = 8
        server.ifacKey = Data(repeating: 0xAB, count: 64)

        let client = TCPServerClientInterface(name: "Client on hub",
                                              parentServer: server,
                                              peerHost: "10.0.0.9",
                                              peerPort: 51000)

        XCTAssertEqual(client.mode, .gateway,
                       "mode must reach the spawned client (TCPInterface.py:637)")
        XCTAssertEqual(client.bitrate, 4_242_000,
                       "bitrate must be the parent's, not a hardcoded default "
                       + "(TCPInterface.py:611)")
        XCTAssertEqual(client.announceCap, 0.05, "announceCap")
        XCTAssertEqual(client.announceRateTarget, 1800, "announceRateTarget")
        XCTAssertEqual(client.announceRateGrace, 4, "announceRateGrace")
        XCTAssertEqual(client.announceRatePenalty, 3600, "announceRatePenalty")
        XCTAssertFalse(client.ingressControl, "ingressControl")
        XCTAssertTrue(client.egressControl, "egressControl")
        XCTAssertEqual(client.ecPrFreq, 9.5, "ecPrFreq")
        XCTAssertEqual(client.gravity, 17, "gravity")

        XCTAssertEqual(client.interfaceState.icBurstFreq, 22, "ic_burst_freq")
        XCTAssertEqual(client.interfaceState.icBurstFreqNew, 7, "ic_burst_freq_new")
        XCTAssertEqual(client.interfaceState.icNewTime, 600, "ic_new_time")
        XCTAssertEqual(client.interfaceState.icBurstHold, 30, "ic_burst_hold")
        XCTAssertEqual(client.interfaceState.icBurstPenalty, 45, "ic_burst_penalty")
        XCTAssertEqual(client.interfaceState.icHeldReleaseInterval, 8, "ic_held_release_interval")
        XCTAssertEqual(client.interfaceState.icPrBurstFreq, 11, "ic_pr_burst_freq")
        XCTAssertEqual(client.interfaceState.icPrBurstFreqNew, 2, "ic_pr_burst_freq_new")

        XCTAssertEqual(client.ifacSize, 8, "ifacSize (already inherited before this change)")
        XCTAssertEqual(client.ifacKey, Data(repeating: 0xAB, count: 64), "ifacKey")
    }

    /// A tunnel belongs to the connection that established it. Python does not copy these, and
    /// inheriting them would attach the parent's tunnel identity to every client.
    func testSpawnedClientDoesNotInheritTunnelState() {
        let server = TCPServerInterface(name: "hub2", port: 4251)
        server.wantsTunnel = true
        server.tunnelID = Data(repeating: 0x01, count: 16)

        let client = TCPServerClientInterface(name: "Client on hub2",
                                              parentServer: server,
                                              peerHost: "10.0.0.10",
                                              peerPort: 51001)

        XCTAssertFalse(client.wantsTunnel, "wantsTunnel is per-connection, not inherited")
        XCTAssertNil(client.tunnelID, "tunnelID is per-connection, not inherited")
    }

    /// Inheritance is a copy, not a shared reference: reconfiguring the parent afterwards must not
    /// silently retune every already-connected client.
    func testInheritanceIsACopyNotAliasing() {
        let server = TCPServerInterface(name: "hub3", port: 4252)
        server.mode = .gateway

        let client = TCPServerClientInterface(name: "Client on hub3",
                                              parentServer: server,
                                              peerHost: "10.0.0.11",
                                              peerPort: 51002)
        XCTAssertEqual(client.mode, .gateway)

        server.mode = .roaming
        XCTAssertEqual(client.mode, .gateway,
                       "a spawned client keeps the values it inherited at spawn time")
    }
}
