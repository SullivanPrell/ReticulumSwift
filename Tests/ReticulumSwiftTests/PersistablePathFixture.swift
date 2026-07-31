import Foundation
@testable import ReticulumSwift

/// Install a path the way the stack actually learns one — with the announce that established it
/// sitting in the announce cache — so a persistence test exercises the state the reference
/// persists rather than a shape only the port could restore.
///
/// Before `bugs/029` the path table inlined the identity and the ratchet and carried no announce
/// reference at all, so a test could install
/// `PathEntry(destinationHash: Data(repeating: 0xAA, count: 16), …)` — a hash belonging to no
/// destination, established by no announce — and still watch it round-trip. Every persistence
/// test in the suite was built that way, and that is a large part of why four files could diverge
/// from the reference for the life of the port with the suite green: the tests round-tripped the
/// port's own shape through the port's own codec and never touched the property that mattered.
///
/// The reference discards any `destination_table` entry whose announce cannot be loaded
/// (`Transport.py:334-345`), so a synthetic entry is now — correctly — neither persisted nor
/// restored. A test that wants to observe persistence has to install a real one.
///
/// `transport.cacheDirectory` must be set; `Reticulum.start()` does it, a bare `Transport()` does
/// not.
@discardableResult
func installPersistablePath(
    on transport: Transport,
    through interface: any Interface,
    hops: UInt8 = 1,
    aspect: String = "path",
    lastHeard: Date = Date(),
    expires: Date? = nil,
    identity: Identity = Identity(),
    ratchet: Data? = nil
) throws -> (destinationHash: Data, identity: Identity, announceHash: Data) {
    let destination = try Destination(identity: identity, direction: .in, kind: .single,
                                      appName: "persistfixture", aspects: [aspect])
    let announce = try Announce.make(for: destination)
    let announceHash = Hashes.fullHash(try announce.hashablePart())
    try transport.cacheAnnounce(announce, receivingInterfaceName: interface.name)

    transport.restore(path: Transport.PathEntry(
        destinationHash: destination.hash,
        nextHopInterface: interface,
        hops: hops,
        lastHeard: lastHeard,
        identityHash: identity.hash,
        expires: expires,
        cachedAnnounceHash: announceHash
    ), forDestination: destination.hash)
    transport.restore(identity: identity, forDestination: destination.hash)
    if let ratchet { transport.restore(ratchet: ratchet, forDestination: destination.hash) }

    return (destination.hash, identity, announceHash)
}
