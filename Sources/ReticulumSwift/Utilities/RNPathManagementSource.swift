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

/// Where `rnpath` reads and writes instance state.
///
/// Python hides this behind `RNS.Reticulum`: every `get_*` / `drop_*` / `blackhole_*`
/// method sits behind `if self.is_connected_to_shared_instance:` and silently proxies
/// over the management RPC socket when a daemon owns the state (`Reticulum.py:1470-1692`).
/// Swift keeps the two apart so the choice is explicit and testable—see
/// ``RNPathApp/managementSourceKind(role:hasRPC:)``, because getting it wrong makes
/// `-b`/`-t`/`-r` silently report the *client's* empty tables while a daemon is running.
public protocol RNPathManagementSource: AnyObject {

    /// Hash of the local transport identity—used only for the blackhole listing's
    /// "by <hash>" suffix, which is suppressed for entries this node issued itself.
    var localTransportIdentityHash: Data? { get }

    /// Python: `get_path_table(max_hops=None)`.
    func pathTable(maxHops: UInt8?) throws -> [RNPathTableEntry]

    /// Python: `get_rate_table()`.
    func rateTable() throws -> [RNPathRateEntry]

    /// Python: `get_blackholed_identities()`.
    func blackholedIdentities() throws -> [RNPathBlackholeEntry]

    /// Python: `drop_path(destination_hash)`—true when an entry actually existed.
    @discardableResult func dropPath(_ destinationHash: Data) throws -> Bool

    /// Python: `drop_all_via(transport_hash)`—the number of paths removed.
    @discardableResult func dropAllVia(_ transportHash: Data) throws -> Int

    /// Python: `drop_announce_queues()`. `rnpath` ignores the return value.
    func dropAnnounceQueues() throws

    /// Python: `blackhole_identity(...)`—`True` added, `None` already blackholed,
    /// `False` rejected. `rnpath -B` prints a different message for each.
    func blackholeIdentity(_ identityHash: Data, until: TimeInterval?, reason: String?) throws -> Bool?

    /// Python: `unblackhole_identity(...)`—`True` lifted, `None` not blackholed,
    /// `False` rejected.
    func unblackholeIdentity(_ identityHash: Data) throws -> Bool?

    /// Python: `get_next_hop(destination_hash)`.
    func nextHop(for destinationHash: Data) throws -> Data?

    /// Python: `get_next_hop_if_name(destination_hash)`.
    func nextHopInterfaceName(for destinationHash: Data) throws -> String?

    /// Python: `get_medium_path_timeout()`.
    ///
    /// Non-throwing, unlike its neighbours: Python catches every RPC failure here and returns
    /// `0` (`Reticulum.py:1780-1781`), because the value only ever raises a floor. A `rnpath`
    /// that aborted because it couldn't *ask* how slow the link is would be worse than one
    /// that used the user's timeout unchanged.
    func mediumPathTimeout() -> TimeInterval
}

// MARK: - Local

/// Reads the in-process stack directly.
///
/// Correct for ``InstanceConnection/Role/sharedInstance`` and
/// ``InstanceConnection/Role/standalone``. Using it while attached as a *local client*
/// would report this process's own (empty) tables rather than the daemon's.
public final class LocalManagementSource: RNPathManagementSource {

    private let reticulum: Reticulum

    /// Creates a source reading from an in-process Reticulum instance.
    public init(reticulum: Reticulum) {
        self.reticulum = reticulum
    }

    /// Hash of this instance's transport identity, or `nil` when it has none.
    public var localTransportIdentityHash: Data? { reticulum.transport.transportIdentity?.hash }

    /// Returns the path timeout used for a medium-bitrate interface.
    public func mediumPathTimeout() -> TimeInterval { reticulum.getMediumPathTimeout() }

    /// Returns the known paths, limited to `maxHops` when one is given.
    public func pathTable(maxHops: UInt8?) throws -> [RNPathTableEntry] {
        reticulum.getPathTable(maxHops: maxHops).map {
            RNPathTableEntry($0, resolvingNamesWith: reticulum.transport)
        }
    }

    /// Returns the announce rate table.
    public func rateTable() throws -> [RNPathRateEntry] {
        reticulum.getRateTable().map(RNPathRateEntry.init)
    }

    /// Returns the blackholed identities.
    public func blackholedIdentities() throws -> [RNPathBlackholeEntry] {
        RNPathBlackholeEntry.list(from: reticulum.getBlackholedIdentities())
    }

    /// Drops the known path to a destination.
    @discardableResult
    public func dropPath(_ destinationHash: Data) throws -> Bool {
        reticulum.dropPath(for: destinationHash)
    }

    /// Drops every path routed through a transport node.
    @discardableResult
    public func dropAllVia(_ transportHash: Data) throws -> Int {
        reticulum.dropAllVia(transportHash: transportHash)
    }

    /// Drops every queued announce.
    public func dropAnnounceQueues() throws {
        reticulum.dropAnnounceQueues()
    }

    /// Blackholes an identity, until a deadline when one is given.
    public func blackholeIdentity(_ identityHash: Data, until: TimeInterval?, reason: String?) throws -> Bool? {
        // Reticulum.blackholeIdentity takes a `Date?`, not a `TimeInterval?`.
        reticulum.blackholeIdentity(identityHash,
                                    until: until.map { Date(timeIntervalSince1970: $0) },
                                    reason: reason)
    }

    /// Removes an identity from the blackhole list.
    public func unblackholeIdentity(_ identityHash: Data) throws -> Bool? {
        reticulum.unblackholeIdentity(identityHash)
    }

    /// Returns the next hop toward a destination, or `nil` when no path is known.
    public func nextHop(for destinationHash: Data) throws -> Data? {
        reticulum.getNextHop(for: destinationHash)
    }

    /// Returns the interface the next hop toward a destination is reached on.
    public func nextHopInterfaceName(for destinationHash: Data) throws -> String? {
        reticulum.getNextHopIfName(for: destinationHash)
    }
}

// MARK: - RPC

/// Asks the running daemon over the instance-control socket.
///
/// Required when ``InstanceConnection/Role/localClient``. Python reaches the same place
/// through `Reticulum`'s `is_connected_to_shared_instance` branches.
///
/// `blackhole_identity` and `unblackhole_identity` are issued as raw calls rather than
/// through ``RPCClient``'s typed helpers, because those return `Void` and would discard the
/// `true` / `nil` / `false` tri-state the two `-B` / `-U` messages branch on.
public final class RPCManagementSource: RNPathManagementSource {

    private let client: RPCClient
    /// Hash of the local transport identity, or `nil` when it has none.
    public let localTransportIdentityHash: Data?

    /// Creates a source reading from a remote instance over RPC.
    public init(client: RPCClient, localTransportIdentityHash: Data?) {
        self.client = client
        self.localTransportIdentityHash = localTransportIdentityHash
    }

    /// Returns the path timeout used for a medium-bitrate interface.
    public func mediumPathTimeout() -> TimeInterval {
        InstanceConnection.mediumPathTimeout(rpc: client, transport: nil)
    }

    /// Returns the known paths, limited to `maxHops` when one is given.
    public func pathTable(maxHops: UInt8?) throws -> [RNPathTableEntry] {
        RNPathTableEntry.decodeTable(try client.pathTable(maxHops: maxHops)) ?? []
    }

    /// Returns the announce rate table.
    public func rateTable() throws -> [RNPathRateEntry] {
        RNPathRateEntry.decodeTable(try client.rateTable()) ?? []
    }

    /// Returns the blackholed identities.
    public func blackholedIdentities() throws -> [RNPathBlackholeEntry] {
        RNPathBlackholeEntry.list(from: try client.blackholedIdentities())
    }

    /// Drops the known path to a destination.
    @discardableResult
    public func dropPath(_ destinationHash: Data) throws -> Bool {
        try client.dropPath(destinationHash: destinationHash)
    }

    /// Drops every path routed through a transport node.
    @discardableResult
    public func dropAllVia(_ transportHash: Data) throws -> Int {
        try client.dropAllVia(transportHash: transportHash)
    }

    /// Drops every queued announce.
    public func dropAnnounceQueues() throws {
        try client.dropAnnounceQueues()
    }

    /// Blackholes an identity, until a deadline when one is given.
    public func blackholeIdentity(_ identityHash: Data, until: TimeInterval?, reason: String?) throws -> Bool? {
        // Python: {"blackhole_identity": bin16, "until": float|nil, "reason": str|nil}
        //         → true | nil | false, returned verbatim by the daemon's rpc_loop.
        let reply = try client.call(.map([
            (.string("blackhole_identity"), .bytes(identityHash)),
            (.string("until"),  until.map { .double($0) } ?? .nil),
            (.string("reason"), reason.map { .string($0) } ?? .nil),
        ]))
        return RPCManagementSource.triState(reply)
    }

    /// Removes an identity from the blackhole list.
    public func unblackholeIdentity(_ identityHash: Data) throws -> Bool? {
        let reply = try client.call(.map([
            (.string("unblackhole_identity"), .bytes(identityHash)),
        ]))
        return RPCManagementSource.triState(reply)
    }

    /// Returns the next hop toward a destination, or `nil` when no path is known.
    public func nextHop(for destinationHash: Data) throws -> Data? {
        try client.nextHop(destinationHash: destinationHash)
    }

    /// Returns the interface the next hop toward a destination is reached on.
    public func nextHopInterfaceName(for destinationHash: Data) throws -> String? {
        try client.nextHopInterfaceName(destinationHash: destinationHash)
    }

    /// `.bool(true)` → true, `.nil` → nil (Python's `None`), anything else → false.
    static func triState(_ value: MsgPack.Value) -> Bool? {
        if case .bool(let flag) = value { return flag }
        if case .nil = value { return nil }
        return false
    }
}

// MARK: - Selection

extension RNPathApp {

    /// Which management source a given attachment calls for.
    public enum ManagementSourceKind: Equatable {
        /// Read the in-process stack.
        case local
        /// Ask the daemon over the control socket.
        case rpc
    }

    /// Python: the `is_connected_to_shared_instance` branch inside every `Reticulum`
    /// accessor.
    ///
    /// A local client must go over RPC, or it reports its own empty tables.
    ///
    /// When the role is ``InstanceConnection/Role/localClient`` but no ``RPCClient`` could
    /// be built (an unreadable `transport_identity`, say), this falls back to `.local`—the
    /// utility still runs, but `-b`, `-t` and `-r` under-report.
    public static func managementSourceKind(role: InstanceConnection.Role,
                                            hasRPC: Bool) -> ManagementSourceKind {
        switch role {
        case .localClient:                 return hasRPC ? .rpc : .local
        case .sharedInstance, .standalone: return .local
        }
    }

    /// Build the right source for an attached connection.
    public static func makeManagementSource(for connection: InstanceConnection) -> RNPathManagementSource {
        let kind = managementSourceKind(role: connection.role, hasRPC: connection.rpc != nil)
        // `managementSourceKind` answers `.rpc` only when it was told `hasRPC`, so the
        // binding always succeeds there.
        if case .rpc = kind, let rpc = connection.rpc {
            return RPCManagementSource(
                client: rpc,
                localTransportIdentityHash: connection.reticulum.transport.transportIdentity?.hash
            )
        }
        return LocalManagementSource(reticulum: connection.reticulum)
    }
}
