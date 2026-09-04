import Foundation

/// Transport extension: interface-discovery + blackhole-updater lifecycle.
///
/// Mirrors Python's `Transport.enable_discovery()`, `Transport.discover_interfaces()`,
/// and `Transport.enable_blackhole_updater()`—see `RNS/Transport.py` lines 449–463.
extension Transport {

    // MARK: - Interface discovery (publish side)

    /// Start announcing this node's discoverable interfaces as reachable endpoints.
    ///
    /// Mirrors Python's `Transport.enable_discovery()` (`Transport.py:574-577`): build the
    /// announcer once, start it, and leave a second call alone.
    ///
    /// A stamp generator has to be injected because the proof-of-work lives in LXMF, which
    /// depends on this package rather than the other way round—the same inversion
    /// `discoverInterfaces` uses for its validator.
    ///
    /// A no-op when the transport has no identity to announce from, which is the state before
    /// `Reticulum.start()` loads one.
    public func enableDiscovery(stampGenerator: any DiscoveryStampGenerator) {
        guard interfaceAnnouncer == nil else { return }   // idempotent
        guard let announcer = InterfaceAnnouncer(transport: self, stampGenerator: stampGenerator)
        else {
            Reticulum.log("Could not start interface discovery announces: the transport has no "
                          + "identity to announce from", level: .error)
            return
        }
        announcer.start()
        interfaceAnnouncer = announcer
    }

    /// Stop announcing discoverable interfaces and release the announcer.
    ///
    /// Idempotent—safe to call when discovery announcing was never enabled.
    public func disableDiscovery() {
        interfaceAnnouncer?.stop()
        interfaceAnnouncer = nil
    }

    // MARK: - Interface discovery (receiver side)

    /// Start listening for on-network interface discovery announces.
    ///
    /// Creates an `InterfaceAnnounceHandler` (registered with this transport) and an
    /// `InterfaceDiscovery` persistent store. Discovered interfaces are persisted to
    /// `storagePath` and forwarded to `callback`.
    ///
    /// Idempotent—a second call while already running is a no-op.
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
        // Python reaches its Reticulum singleton for this
        // (`self.rns_instance.is_blackholed(...)`); Swift has none, so the check
        // is injected. Without this the RNS 1.4.1 pruning of blackholed
        // discoveries is dead code—the clauses are guarded on the closure
        // being non-nil. Weak self: the store outlives nothing here, but the
        // closure must not keep Transport alive.
        discovery.isBlackholed = { [weak self] hash in self?.isBlackholed(hash) ?? false }

        // Autoconnect reads the interface list and attaches what it dials. Python reaches the
        // `RNS.Transport` global for both (`Discovery.py:698`, `:777`).
        discovery.transport = self

        let handler = InterfaceAnnounceHandler(
            requiredValue: requiredValue,
            stampValidator: stampValidator,
            callback: { [weak discovery] info in
                discovery?.interfaceDiscovered(info)
                // Python calls `autoconnect` on every discovery, right after persisting it
                // (`Discovery.py:598`): an endpoint heard for the first time is dialled without
                // waiting for a restart. Every gate is inside `autoconnect`.
                discovery?.autoconnect(info)
                callback?(info)
            }
        )

        register(announceHandler: handler)
        discoveryHandler       = discovery
        discoveryAnnounceHandler = handler

        // Dial what was already persisted, so a restart doesn't have to re-hear every peer
        // (`Discovery.py:678-689`, called from `InterfaceDiscovery.__init__`).
        discovery.connectDiscovered()
    }

    /// Stop listening for interface discovery announces and release all associated state.
    ///
    /// Idempotent—safe to call when discovery was never started.
    public func stopDiscoverInterfaces() {
        if let h = discoveryAnnounceHandler {
            deregister(announceHandler: h)
        }
        discoveryAnnounceHandler = nil
        discoveryHandler?.stopMonitoring()
        discoveryHandler         = nil
    }

    /// List all persisted discovered interfaces, delegating to `discoveryHandler`.
    ///
    /// Returns `[]` when `discoverInterfaces` hasn't been called.
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
    /// Idempotent—a second call while already running is a no-op.
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
    /// Idempotent—safe to call when the updater was never started.
    public func disableBlackholeUpdater() {
        blackholeUpdater?.stop()
        blackholeUpdater = nil
    }
}
