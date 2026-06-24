import Foundation

/// Transport extension: interface-discovery + blackhole-updater lifecycle.
///
/// Mirrors Python's `Transport.enable_discovery()`, `Transport.discover_interfaces()`,
/// and `Transport.enable_blackhole_updater()` — see `RNS/Transport.py` lines 449–463.
extension Transport {

    // MARK: - Interface discovery (receiver side)

    /// Start listening for on-network interface discovery announces.
    ///
    /// Creates an `InterfaceAnnounceHandler` (registered with this transport) and an
    /// `InterfaceDiscovery` persistent store. Discovered interfaces are persisted to
    /// `storagePath` and forwarded to `callback`.
    ///
    /// Idempotent — a second call while already running is a no-op.
    ///
    /// Mirrors Python's `Transport.discover_interfaces()` which creates an
    /// `InterfaceDiscovery(discover_interfaces=True)`.
    ///
    /// - Parameters:
    ///   - storagePath: Directory path where discovered interfaces are persisted (one file each).
    ///   - requiredValue: Minimum PoW stamp value to accept. Defaults to `Reticulum.requiredDiscoveryValue()`.
    ///   - stampValidator: Validates incoming discovery stamps. Inject `LXStamper` in production.
    ///   - callback: Called with each valid `DiscoveredInterfaceInfo` when it arrives.
    public func discoverInterfaces(
        storagePath: String,
        requiredValue: Int = Reticulum.requiredDiscoveryValue(),
        stampValidator: DiscoveryStampValidator,
        callback: ((DiscoveredInterfaceInfo) -> Void)? = nil
    ) {
        guard discoveryHandler == nil else { return }   // idempotent

        let discovery = InterfaceDiscovery(storagePath: storagePath)

        let handler = InterfaceAnnounceHandler(
            requiredValue: requiredValue,
            stampValidator: stampValidator,
            callback: { [weak discovery] info in
                discovery?.interfaceDiscovered(info)
                callback?(info)
            }
        )

        register(announceHandler: handler)
        discoveryHandler       = discovery
        discoveryAnnounceHandler = handler
    }

    /// Stop listening for interface discovery announces and release all associated state.
    ///
    /// Idempotent — safe to call when discovery was never started.
    public func stopDiscoverInterfaces() {
        if let h = discoveryAnnounceHandler {
            deregister(announceHandler: h)
        }
        discoveryAnnounceHandler = nil
        discoveryHandler         = nil
    }

    /// List all persisted discovered interfaces, delegating to `discoveryHandler`.
    ///
    /// Returns `[]` when `discoverInterfaces` has not been called.
    /// Mirrors `Reticulum.list_discovered_interfaces()` which creates a temporary
    /// `InterfaceDiscovery(discover_interfaces=False)` for a one-shot listing.
    ///
    /// - Parameters:
    ///   - onlyAvailable: When `true`, include only recently heard interfaces.
    ///   - onlyTransport: When `true`, include only transport-enabled interfaces.
    public func listDiscoveredInterfaces(onlyAvailable: Bool = false,
                                         onlyTransport: Bool = false) -> [DiscoveredInterfaceInfo] {
        discoveryHandler?.listDiscoveredInterfaces(onlyAvailable: onlyAvailable,
                                                   onlyTransport: onlyTransport) ?? []
    }

    // MARK: - Blackhole updater

    /// Create and start the background blackhole-list updater.
    ///
    /// Uses `Reticulum.blackholeSources()` as the list of trusted source identities.
    /// Idempotent — a second call while already running is a no-op.
    ///
    /// Mirrors Python's `Transport.enable_blackhole_updater()`.
    public func enableBlackholeUpdater() {
        guard blackholeUpdater == nil else { return }   // idempotent
        let updater = BlackholeUpdater(transport: self)
        updater.start()
        blackholeUpdater = updater
    }

    /// Stop the blackhole-list updater and release it.
    ///
    /// Idempotent — safe to call when the updater was never started.
    public func disableBlackholeUpdater() {
        blackholeUpdater?.stop()
        blackholeUpdater = nil
    }
}
