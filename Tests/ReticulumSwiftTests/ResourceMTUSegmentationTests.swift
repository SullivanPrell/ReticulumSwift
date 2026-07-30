import XCTest
@testable import ReticulumSwift

/// Resource segmentation derives from the negotiated link MTU — `bugs/016`, tasks 6.2–6.4.
///
/// The reference sizes every part from the per-link MTU on **both** sides
/// (`Resource.py:335`: `link.mtu - HEADER_MAXSIZE - IFAC_MIN_SIZE`) and the receiver does not
/// trust the advertised part count — it recomputes `total_parts = ceil(size / sdu)` from its own
/// `sdu` (`:187`).
///
/// This port split at a fixed `Constants.mdu` (464), which equals the reference's value only at
/// the base MTU of 500. Once MTU discovery raises a link above that, the two sides compute
/// different part counts: the receiver's `hashmap_update` walks off the end of its map, the
/// `IndexError` is swallowed at debug level (`Resource.py:240`), and the fetch simply times out
/// with the link still ACTIVE. A transfer that never happens, silently — design D1 records why
/// that makes this a correctness break rather than the "efficiency, deferred" it was filed as.
///
/// Swift↔Swift never noticed because the Swift receiver trusted `adv.partCount`: two
/// consistently-wrong halves interoperate with each other and with nothing else. Both halves are
/// asserted here.
final class ResourceMTUSegmentationTests: XCTestCase {

    /// Python's `sdu` for a link, spelled exactly as the reference spells it.
    private func referenceSDU(mtu: Int) -> Int {
        mtu - Constants.headerMaxSize - Constants.ifacMinSize
    }

    // MARK: - The sender

    /// Spec: "Resource segmentation SHALL derive from the negotiated link MTU."
    func testPartSizeFollowsTheNegotiatedMTURatherThanTheBaseConstant() throws {
        // A link that negotiated well above the base MTU, as MTU discovery produces on any
        // interface with a real hardware MTU.
        let link = try makeActiveLink(mtu: 8156)

        XCTAssertEqual(Resource.segmentSize(for: link), referenceSDU(mtu: 8156),
                       "part size must come from this link, not from the 500-byte base constant")
        XCTAssertNotEqual(Resource.segmentSize(for: link), Constants.mdu,
                          "464 is the reference's answer only at MTU 500 — if these are equal "
                          + "the value is not being derived at all")
    }

    /// At the base MTU the derived value must still be exactly the old constant, or this change
    /// would be a wire change against every peer on an un-upgraded link.
    func testPartSizeAtTheBaseMTUIsUnchanged() throws {
        let link = try makeActiveLink(mtu: Constants.mtu)
        XCTAssertEqual(Resource.segmentSize(for: link), Constants.mdu)
    }

    /// The part count a sender advertises must be the one a reference receiver derives.
    ///
    /// Incompressible payload on purpose: compression is what hid this in the interop suite,
    /// where `test_nomadnet.py:90`'s payload bz2-compresses to under one part so no mismatch can
    /// occur however the parts are sized.
    func testAdvertisedPartCountMatchesWhatAReferenceReceiverDerives() throws {
        let mtu = 8156
        let link = try makeActiveLink(mtu: mtu)
        let payload = Self.incompressibleData(count: 200_000)

        let resource = try Resource(link: link, payload: payload,
                                    segmentSize: Resource.segmentSize(for: link),
                                    autoCompress: false)

        let sdu = referenceSDU(mtu: mtu)
        let derived = Int((Double(resource.transferSize) / Double(sdu)).rounded(.up))
        XCTAssertEqual(resource.partCount, derived,
                       "the sender advertises \(resource.partCount) parts where a receiver "
                       + "deriving from its own sdu computes \(derived) — the disagreement that "
                       + "makes the transfer time out with the link still up")
    }

    // MARK: - The receiver

    /// Spec: "A receiver derives the part count independently" — and "a mismatch between the two
    /// is surfaced rather than silently accepted".
    ///
    /// Trusting the advertisement is exactly why two consistently-wrong implementations
    /// interoperate with each other and with nothing else.
    func testReceiverDerivesThePartCountAndSurfacesADisagreement() throws {
        let mtu = 8156
        let sdu = referenceSDU(mtu: mtu)
        let size = 200_000

        let derived = ResourceTransfer.derivedPartCount(size: size, segmentSize: sdu)
        XCTAssertEqual(derived, Int((Double(size) / Double(sdu)).rounded(.up)),
                       "must be ceil(size / sdu), as Resource.py:187 computes it")

        // What a sender still splitting at 464 would advertise for the same resource.
        let advertisedByAStaleSender = Int((Double(size) / Double(Constants.mdu)).rounded(.up))
        XCTAssertNotEqual(derived, advertisedByAStaleSender,
                          "this scenario is only meaningful if the two disagree")
        XCTAssertTrue(ResourceTransfer.partCountDisagrees(advertised: advertisedByAStaleSender,
                                                          derived: derived),
                      "a receiver that accepts a part count it did not derive cannot notice the "
                      + "mismatch, and the transfer dies as a timeout instead of an error")
    }

    // MARK: - Helpers

    /// Random bytes, so bz2 cannot shrink the payload below one part and hide the defect.
    private static func incompressibleData(count: Int) -> Data {
        var bytes = Data(count: count)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return bytes
    }

    /// An established link whose negotiated MTU is `mtu`.
    ///
    /// Two transports on paired interfaces: a link needs a real peer to answer the request, and
    /// a self-delivering loopback never completes the handshake.
    private func makeActiveLink(mtu: Int) throws -> Link {
        let initiatorTransport = Transport()
        let responderTransport = Transport()

        let responderIdentity = Identity()
        let destination = try Destination(identity: responderIdentity, direction: .in, kind: .single,
                                          appName: "test", aspects: ["resource"])
        responderTransport.ownerIdentity = responderIdentity
        responderTransport.register(destination: destination)

        let a = MTULoopbackIface(name: "a")
        let b = MTULoopbackIface(name: "b")
        a.paired = b
        b.paired = a
        initiatorTransport.register(interface: a)
        responderTransport.register(interface: b)

        let established = expectation(description: "link established")
        initiatorTransport.onLinkEstablished = { _ in established.fulfill() }
        let link = try Link.initiate(destination: destination, transport: initiatorTransport)
        wait(for: [established], timeout: 2.0)

        // Both ends must agree, exactly as MTU discovery leaves them; sizing from one side only
        // is the defect, so a test that raised only the sender's could not see it.
        link.establishedMtu = mtu
        responderTransport.links[link.linkID!]?.establishedMtu = mtu
        transportsUnderTest.append(contentsOf: [initiatorTransport, responderTransport])
        return link
    }

    /// Held so the transports outlive the link for the duration of the test.
    private var transportsUnderTest: [Transport] = []
}

/// Loopback that hands each packet to its paired interface on the other transport.
private final class MTULoopbackIface: Interface {
    let name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    weak var paired: MTULoopbackIface?

    init(name: String) { self.name = name }

    func send(_ packet: Packet) throws {
        let raw = try packet.pack()
        let copy = try Packet.unpack(raw)
        paired?.inboundHandler?(copy, paired!)
    }
    func start() throws {}
    func stop() {}
}
