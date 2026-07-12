import XCTest
@testable import ReticulumSwift

/// RNS 1.3.7: a non-transport node runs behind a fresh ephemeral transport
/// identity for privacy, while keeping its persistent identity as
/// `internal_identity()` (used e.g. for the RPC auth key). The
/// `static_transport_identity` option restores the old stable-identity behavior.
final class RNS137EphemeralTransportIdentityTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns137-eti-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeReticulum(storage: URL, configText: String) throws -> Reticulum {
        let cfgPath = tmp.appendingPathComponent("config-\(UUID().uuidString)")
        try configText.write(to: cfgPath, atomically: true, encoding: .utf8)
        let cfg = Reticulum.Configuration(storagePath: storage, configPath: cfgPath, shareInstance: false)
        return Reticulum(configuration: cfg)
    }

    func testNonTransportNodeUsesEphemeralTransportIdentity() throws {
        let storage = tmp.appendingPathComponent("storage")
        let r = try makeReticulum(storage: storage, configText: "[reticulum]\nenable_transport = False\n")
        try r.start(); defer { r.stop() }

        let internalHash = r.transport.internalIdentity?.hash
        let transportHash = r.transport.transportIdentity?.hash
        XCTAssertNotNil(internalHash)
        XCTAssertNotNil(transportHash)
        XCTAssertNotEqual(internalHash, transportHash,
            "non-transport node must use an ephemeral transport identity distinct from its persistent one")
        XCTAssertEqual(r.transport.transportInstanceID, transportHash,
            "transportInstanceID must track the (ephemeral) transport identity")
    }

    func testStaticTransportIdentityUsesPersistentIdentity() throws {
        let storage = tmp.appendingPathComponent("storage")
        let r = try makeReticulum(storage: storage,
            configText: "[reticulum]\nenable_transport = False\nstatic_transport_identity = True\n")
        try r.start(); defer { r.stop() }

        XCTAssertEqual(r.transport.internalIdentity?.hash, r.transport.transportIdentity?.hash,
            "static_transport_identity must keep the transport identity equal to the persistent one")
    }

    func testTransportEnabledNodeUsesPersistentIdentity() throws {
        let storage = tmp.appendingPathComponent("storage")
        let r = try makeReticulum(storage: storage, configText: "[reticulum]\nenable_transport = True\n")
        try r.start(); defer { r.stop() }

        XCTAssertEqual(r.transport.internalIdentity?.hash, r.transport.transportIdentity?.hash,
            "a transport-enabled node keeps a stable transport identity")
    }

    func testEphemeralChangesAcrossRunsButInternalPersists() throws {
        let storage = tmp.appendingPathComponent("storage")
        let text = "[reticulum]\nenable_transport = False\n"

        func run() throws -> (internalHash: Data, transportHash: Data) {
            let r = try makeReticulum(storage: storage, configText: text)
            try r.start(); defer { r.stop() }
            return (r.transport.internalIdentity!.hash, r.transport.transportIdentity!.hash)
        }

        let a = try run()
        let b = try run()
        XCTAssertEqual(a.internalHash, b.internalHash,
            "persistent internal identity must be stable across runs")
        XCTAssertNotEqual(a.transportHash, b.transportHash,
            "ephemeral transport identity must be regenerated each run")
    }
}
