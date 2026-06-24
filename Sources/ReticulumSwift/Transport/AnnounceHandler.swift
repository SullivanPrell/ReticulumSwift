import Foundation

/// Protocol for objects that want to be notified of incoming announces.
///
/// Mirrors Python's announce handler contract: the handler exposes an
/// optional `aspectFilter` string (e.g. `"lxmf.delivery"`) and a
/// `receivedAnnounce` callback. When `aspectFilter` is non-nil, Transport
/// computes the expected destination hash for that app/aspect combination
/// paired with the announcing identity and only calls the handler when
/// the hashes match — matching Python's `Transport._announce_handlers`
/// dispatch logic exactly.
public protocol AnnounceHandler: AnyObject {
    /// If non-nil, only announces whose destination hash matches
    /// `Destination.computeHash` for this filter + the announcing identity
    /// will be dispatched. A nil filter receives every announce.
    var aspectFilter: String? { get }

    /// Set to `true` to also receive announces that are path responses.
    /// When `false` (the default), path-response announces are filtered out.
    /// Mirrors Python's optional `receive_path_responses` attribute.
    var receivePathResponses: Bool { get }

    /// Called when a matching announce arrives. Mirrors Python's
    /// `received_announce(destination_hash, announced_identity, app_data, announce_packet_hash, is_path_response)`.
    ///
    /// - Parameters:
    ///   - destinationHash: 16-byte truncated hash of the announced destination.
    ///   - identity: The announcing identity (public key only).
    ///   - appData: Optional app data attached to the announce.
    ///   - announcePacketHash: 4-byte truncated hash of the announce packet itself.
    ///   - isPathResponse: True when the announce arrived in response to a path request.
    func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?,
                          announcePacketHash: Data, isPathResponse: Bool)
}

public extension AnnounceHandler {
    // Default: do not filter path-response announces (handlers opt in by overriding to true).
    var receivePathResponses: Bool { false }

    // Backwards-compatible shim: if the full signature is not overridden,
    // fall back through the chain to the no-arg baseline.
    func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?,
                          announcePacketHash: Data, isPathResponse: Bool) {
        receivedAnnounce(destinationHash: destinationHash, identity: identity,
                         appData: appData, isPathResponse: isPathResponse)
    }
    func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?, isPathResponse: Bool) {
        receivedAnnounce(destinationHash: destinationHash, identity: identity, appData: appData)
    }
    func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?) {}
}
