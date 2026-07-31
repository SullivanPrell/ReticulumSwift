import XCTest
@testable import ReticulumSwift

/// The announce cache must be the file the reference writes, not merely a file by the same name.
///
/// `bugs/029` — this is the fifth divergence, and it **gates the fourth**. The reference stores a
/// path table entry's announce by hash in `storage/cache/announces/` and discards any entry whose
/// announce cannot be loaded (`Transport.py:334-345`). So a correctly-encoded `destination_table`
/// beside a JSON announce cache restores *nothing*: the names would look right, the path table
/// would parse, and every path would still be dropped. The cache comes first.
final class AnnounceCacheParityTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-announce-parity-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func makeAnnounce(aspect: String) throws -> (Packet, Data) {
        let dest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                   appName: "cacheparity", aspects: [aspect])
        let announce = try Announce.make(for: dest)
        return (announce, Hashes.fullHash(try announce.hashablePart()))
    }

    /// Python `Transport.cache`: `umsgpack.packb([packet.raw, interface_reference])`, written to
    /// `cachepath/announces/<hexrep(packet.get_hash(), delimit=False)>` (`Transport.py:2646-2657`).
    func testEntryIsMsgpackPairKeyedByFullHash() throws {
        let transport = Transport()
        transport.cacheDirectory = tmpDir

        let (announce, hash) = try makeAnnounce(aspect: "pair")
        try transport.cacheAnnounce(announce)

        let file = tmpDir.appendingPathComponent("announces")
            .appendingPathComponent(hash.hexString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "the entry must be keyed by the full packet hash in lowercase hex, as "
                      + "`RNS.hexrep(packet_hash, delimit=False)` produces (Transport.py:2648)")

        let raw = try Data(contentsOf: file)
        let decoded = try MsgPack.decode(raw)

        guard case .array(let fields) = decoded else {
            return XCTFail("""
                the entry must be a msgpack array — Python writes \
                `umsgpack.packb([packet.raw, interface_reference])` (Transport.py:2655) and reads \
                it back with `umsgpack.unpackb` (:2672). Got: \(decoded)
                """)
        }
        XCTAssertEqual(fields.count, 2,
                       "the entry is a two-element pair: raw packet bytes, then the receiving "
                       + "interface reference (Transport.py:2655)")

        guard case .bytes(let storedRaw) = fields[0] else {
            return XCTFail("field 0 must be the raw packet bytes, not \(fields[0]) — Python "
                           + "reconstructs with `RNS.Packet(None, cached_data[0])` "
                           + "(Transport.py:2675)")
        }
        XCTAssertEqual(storedRaw, try announce.pack(),
                       "the stored bytes must be the packet's raw wire form")
    }

    /// An announce cached with no receiving interface stores `None` in field 1, not a placeholder:
    /// Python initialises `interface_reference = None` and only assigns when the packet has one
    /// (`Transport.py:2650-2651`).
    func testAbsentInterfaceIsStoredAsNil() throws {
        let transport = Transport()
        transport.cacheDirectory = tmpDir

        let (announce, hash) = try makeAnnounce(aspect: "nointerface")
        try transport.cacheAnnounce(announce)

        let raw = try Data(contentsOf: tmpDir.appendingPathComponent("announces")
            .appendingPathComponent(hash.hexString))
        guard case .array(let fields) = try MsgPack.decode(raw), fields.count == 2 else {
            return XCTFail("entry is not the two-element msgpack pair the reference writes")
        }
        XCTAssertEqual(fields[1], .nil,
                       "with no receiving interface the reference stores None (Transport.py:2650)")
    }

    /// Python resolves the stored reference back to a live interface on read:
    /// `for interface in Transport.interfaces: if str(interface) == interface_reference:
    /// packet.receiving_interface = interface` (`Transport.py:2680-2683`).
    ///
    /// Swift decodes the entry and drops the name on the floor, so a packet restored from cache
    /// has no receiving interface even when the interface is registered.
    func testReceivingInterfaceIsResolvedOnRead() throws {
        let transport = Transport()
        transport.cacheDirectory = tmpDir
        let iface = LoopbackInterface(name: "CacheIface")
        transport.register(interface: iface)

        let (announce, hash) = try makeAnnounce(aspect: "resolve")
        try transport.cacheAnnounce(announce, receivingInterfaceName: iface.name)

        let restored = try XCTUnwrap(transport.getCachedAnnounce(hash: hash))
        XCTAssertEqual(restored.receivingInterface?.name, iface.name,
                       """
                       a packet restored from cache must carry the interface it was received on. \
                       Python looks the stored name up in `Transport.interfaces` and assigns \
                       `receiving_interface` (Transport.py:2680-2683); dropping it leaves the \
                       restored packet unable to say where it came from.
                       """)
    }

    /// A stored name that matches no registered interface leaves the packet without one, rather
    /// than failing the read — Python's loop simply finds no match (`Transport.py:2680-2683`).
    func testUnknownInterfaceNameLeavesPacketWithoutOne() throws {
        let transport = Transport()
        transport.cacheDirectory = tmpDir

        let (announce, hash) = try makeAnnounce(aspect: "unknown")
        try transport.cacheAnnounce(announce, receivingInterfaceName: "InterfaceThatIsGone")

        let restored = try XCTUnwrap(transport.getCachedAnnounce(hash: hash),
                                     "the packet must still be readable")
        XCTAssertNil(restored.receivingInterface,
                     "an unresolvable interface name must leave the packet without one")
    }
}
