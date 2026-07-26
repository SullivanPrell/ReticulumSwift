# Changelog

All notable changes to ReticulumSwift are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [1.5.0] — RNS 1.4.1 parity: interface gravity and dynamic path re-balancing

Brings the port up to Python RNS 1.4.1 (released 2026-07-24). The two headline
features both change how paths are chosen, so a mixed Swift/Python mesh will
converge differently than before — in the same direction Python now does.

### Added

- **Interface gravity.** Every interface carries an integer `gravity`
  (default 0, negative values allowed) expressing routing preference. When an
  announce arrives that is *the same announce* already recorded for a
  destination — same emission timebase, equal or fewer hops — the path now
  moves to the interface with the strictly higher gravity. Configurable per
  interface (`gravity`) and globally (`default_gravity`), and inherited by
  spawned child interfaces (TCP server clients, I2P peers, Weave peers), which
  is essential because the child, not the parent, is what Transport records as
  a path's receiving interface.

  A gravity takeover deliberately does **not** reset the path's responsiveness
  state; Python's gravity branch is the one place that omits
  `mark_path_unknown_state`, so a working path keeps its known-good status
  across the swap.
- **Dynamic link path re-balancing.** A link-request proof that arrives over a
  different number of hops than the path table predicted now corrects both
  `Link.expectedHops` and the path table's hop count, once the proof's
  signature has validated. A link request is the first real round-trip to a
  destination, so its proof is the earliest trustworthy hop measurement —
  previously the port waited for the next announce to converge. Latched by the
  new `Link.rebalanced` timestamp so each link re-balances at most once, and
  gated by `Transport.allowLinkPathRebalance`.
- **`Destination.setMaxRequestSize(_:)`** caps inbound requests served by
  registered handlers. Oversized single-packet requests are dropped before the
  msgpack body is unpacked; oversized requests advertised as a Resource are
  rejected at advertisement time, so nothing transfers at all.
- **`maxResponseSize:` on `Link.request(...)`** caps the response a caller will
  accept, with the same two enforcement points. An over-size response fails the
  receipt (new `RequestReceipt.responseRejected()`) rather than delivering
  truncated data.
- **`announces_to_internal`** per-interface option. Set on the interface an
  announce arrived over, it lets that interface's announces onto internal-mode
  interfaces even when it is itself in boundary mode.
- **Boundary-mode path requests.** Boundary interfaces may now trigger
  recursive path requests, restricted to boundary and gateway peers via the new
  `InterfaceMode.boundarySearchModes`.
- **`autoconnect_interface_mode` / `autoconnect_interface_gravity` /
  `autoconnect_announces_to_internal`** config options, plus `gravity` and
  `announces_to_internal` keys in the interface-stats payload (Python's
  `rnstatus` reads both, and sorts by gravity).

### Fixed

- **Ingress burst control could latch on indefinitely.** Clearing the burst
  flag required 6 samples (`IC_BURST_MIN_SAMPLES`) in a frequency deque that a
  *subsiding* burst never refills — so the flag could only clear if new
  announces arrived, which is exactly what it was suppressing. It now needs 2
  (`IC_DEQUE_MIN_SAMPLE`), matching the upstream fix.
- **Ingress limiting released one call early.** The call that clears the burst
  flag now still reports "limited"; Python's `return True` sits outside the
  deactivation branch, so only the *following* call passes. Applies to both
  announce and path-request limiting.
- **Egress path-request limiting triggered far too easily**, using the 2-sample
  minimum that merely makes a frequency computable instead of
  `IC_BURST_MIN_SAMPLES` (6) — throttling ordinary discovery bursts.
- **Channel accepted arbitrarily far-future sequence numbers**, letting a peer
  make the receive ring buffer grow on its say-so. Sequences beyond
  `nextRxSequence + WINDOW_MAX` are now dropped.
- **Channel's stale-sequence wraparound test was inverted and used the wrong
  constant** (`SEQ_MODULUS/2` instead of `WINDOW_MAX`), so near the top of the
  sequence space it dropped legitimate wrapped-*future* frames and accepted
  genuinely stale ones.
- **Discovered peers were dialled as `BackboneInterface` on Apple platforms.**
  Upstream excludes Darwin from backbone support — the client side relies on
  polling semantics that do not hold there — so a discovered
  Backbone/TCPServer peer must be connected as a `TCPClientInterface`. Since
  Darwin is this port's whole target, every discovered peer was taking the
  wrong path.
- **Persisted interface discoveries were never re-checked against the
  blackhole list**, so an identity blackholed after its record was written
  stayed connectable forever. Records lacking a transport or network identity,
  or whose network identity is not in `interface_discovery_sources`, are now
  pruned too.
- **Config log levels were not clamped**, so an out-of-range value silently
  fell back to the default instead of saturating. The cap is now 8, matching
  RNS 1.4.1 raising it from 7 so `LOG_EXTREME` is reachable from a config file.

#### Resource progress reporting was entirely inert

- **`ResourceTransfer.onProgress` was never called from anywhere.** It was
  declared, public, forwarded by `Link.request(progressCallback:)` into
  `RequestReceipt`, and consumed downstream — but nothing invoked it, so every
  progress observer in the stack silently read zero forever. Python fires it for
  each newly-accepted part on the receiver and once per outgoing batch on the
  sender; both now do.
- **`progress` measured received parts for senders too**, so a sender reported
  0.0 for an entire transfer and then jumped to 1.0. Python's `get_progress`
  branches on `initiator` and counts parts *sent*.
- **`RequestReceipt.responseSize` was unreadable mid-transfer.** It is now
  populated from the response advertisement as soon as one arrives, which is the
  only window in which a progress display can use it.

#### Multi-segment (>1 MB) resource transfers were broken end to end

- **The sender stalled after the first segment.** Each segment is a distinct
  Resource with its own hashmap, but the per-segment part-serving cursors
  (`sentMapHashes`, the collision-guard window's lower bound) carried the
  previous segment's progress forward — so for a two-segment transfer the search
  window started past the shorter second segment's part count, `handleRequest`
  matched nothing, and zero parts were served.
- **The receiver misparsed every segment after the first.** Metadata rides only
  in segment 1's plaintext, but the advertisement's metadata flag is set on all
  of them; gating on the flag alone made a later segment's first three payload
  bytes read as a metadata length. Now gated on segment index, as Python does.
- **A completed transfer was reported under the wrong advertisement.** The
  concluding callback passed the *first* segment's advertisement while the
  receiver's resource hash had advanced to the last, so a listener matching on
  that hash missed — the file arrived intact and was discarded as invalid.

#### Other

- **A resource-started observer was handed an unpopulated hash.** The callback
  fired before the advertisement was parsed, so `resourceHash` was still empty.
  Python calls it from inside `Resource.accept`, after the hash is assigned;
  anything keying on that value (LXMF's inbound registry does) collapsed every
  concurrent transfer onto one key.
- **A transport header was stamped on zero-hop paths.** A destination zero hops
  away is directly reachable and must go out as `HEADER_1`, even when a next-hop
  transport ID is on file — which happens for exactly one topology, a shared
  instance's own local clients seen from a sibling client. The stray transport
  header made a Python peer drop the packet, so a Swift client behind a shared
  instance could never open a link to one.
- **`LocalInterface.start()` returned before the connection was usable.**
  `NWConnection` is asynchronous and `send()` discards while offline, so the
  announce every client fires immediately after attaching went nowhere: the
  daemon reported the client as connected while its path table stayed empty.
  `start()` now waits for readiness (up to `connectTimeout`, 5 s) and throws
  `ConnectionError.couldNotConnect` otherwise, matching Python's blocking
  `socket.connect()`.
- **An embedded i2pd crashed the host process at exit.** i2pd's router lives on
  dylib-scope C++ singletons served by its own threads, so any `exit()` that had
  not called `I2PDaemon.stop()` destroyed them underneath live threads — a
  reproducible `SIGSEGV` in `i2p::tunnel::Tunnels`, and a router that never
  flushed its netDb or dropped its leaseSets. An `atexit` handler registered on
  first start now performs the ordered shutdown.
- **`I2PDaemon` treated process-global state as per-instance.** `C_InitI2P`
  initialises singletons and `C_TerminateI2P` retires them for the life of the
  process, so a second daemon silently reconfigured a running one and a daemon
  started after any stop re-initialised torn-down globals. Both are refused with
  a specific error; `I2PDaemon.isTerminatedForProcess` lets a caller check first.
- **`BackboneInterface` config ignored the `remote`/`port` aliases** that Python
  normalises before constructing the interface, so a config written the
  documented way — including the one RNS's own discovery emits — parsed to
  nothing and the interface was silently skipped.
- **`interface_discovery_sources` was only enforced when pruning stored
  records**, leaving an unauthorised peer discoverable and dialable until the
  next prune. It is now checked at announce reception, as Python does.
- **A split request or response resource delivered only its last segment.**
  Segments 2..N carry the same request/response flags and request ID as segment
  1, so the advertisement dispatch built a fresh transfer for each one. The
  caller received the tail chunk *as a successful response* — a truncated
  payload merely fails to decode as the `[request_id, response]` envelope and
  falls back to raw bytes, so this was silent corruption rather than an error,
  on the LXMF propagation-sync and NomadNet file-fetch paths. Continuation
  advertisements are now routed to the transfer holding the earlier segments.
- **A receiver parked between segments adopted unrelated advertisements.** It
  stays registered so the next segment reaches it, but the link hands every
  advertisement to every registered receiver — so a different resource
  advertised in that window was downloaded into the segment buffer and spliced
  into the middle of the delivered payload, bypassing `resourceStrategy` and
  never firing `onResourceStarted`. A transfer now accepts only its own next
  segment.
- **Sender progress was measured per segment**, so a split transfer reported
  0→1 once per segment — reaching 1.0 while still running, then going
  backwards. Python folds the segment position in; the per-segment figure is a
  separate method there (`get_segment_progress`).
- **`LocalInterface.start()` stalled for the full connect timeout when nothing
  was listening.** A refused connection surfaces as `.waiting`, not `.failed`,
  and only `.failed`/`.cancelled` released the caller — so the normal
  standalone launch paid 5 s, serialized ahead of every later interface, on the
  main thread if that is where the caller ran. `.waiting` on the initial connect
  now fails fast, as Python's blocking `socket.connect()` does.
- **A superseded connection could take down its replacement.** After any
  `stop()`/`start()`, the old connection's terminal callback still ran, marked
  the *healthy* new connection offline and scheduled a reconnect that abandoned
  it uncancelled — a leaked socket the shared instance still counted as an
  attached client, and two concurrent receive loops on one HDLC decoder. State
  callbacks now ignore a connection that is no longer the current one.

### Added — public API

`InterfaceMode.init?(configName:)`, `InterfaceMode.defaultGravity`,
`InterfaceMode.boundarySearchModes`, `IngressControlState.icBurstMinSamples`,
`InterfaceDiscovery.isBlackholed`, `Destination.maxRequestSize` /
`setMaxRequestSize(_:)` / `DestinationError.invalidMaxRequestSize`,
`Link.rebalanced`, `LocalInterface.connectTimeout` /
`LocalInterface.ConnectionError`, `I2PDaemon.isTerminatedForProcess`,
`Transport.allowLinkPathRebalance`.

Note for consumers that switch exhaustively over `Destination.DestinationError`:
this minor version adds a case.

### Known limitations

- A Swift shared instance still cannot relay between two of its own local
  clients: every client is served by one interface, and both relay paths refuse
  to send back out the interface a packet arrived on. Client-to-client traffic
  across a *Python* shared instance is unaffected.
- Announces forwarded to local clients pass their hop count through unchanged,
  matching Python's `new_announce.hops = packet.hops` — but Python's value has
  already been incremented on inbound and this port does no inbound increment.
  A destination one hop beyond a Swift shared instance therefore reads as
  directly reachable to a sibling client. Harmless with the default
  `allowLinkPathRebalance` (the first link re-balances and proceeds); with it
  disabled, such a link stays pending.

## [1.4.3] — Thread-safe traffic counters and packet-handle state

Data races only, no wire-format or behavioural change. Every reported number is
computed exactly as before; the difference is that reading one no longer races
the thread writing it. Verified with `swift test --sanitize=thread` over the
full suite.

### Fixed

- **Interface traffic counters raced their readers.** `rxBytes` / `txBytes` /
  `rxPackets` / `txPackets` are written from whichever queue an interface's I/O
  runs on — CoreBluetooth's queue for `BLEMeshInterface`, an `NWConnection` queue
  for the TCP/UDP family, a serial read thread for `SerialInterface` — and read
  from another (an app polls them to draw its interface list; `rnstatus`-style
  reporting reads them from the caller's thread). `Int` is not atomic and
  `counter += 1` is a load-modify-store, so concurrent increments silently lost
  updates and a concurrent read could observe a torn value: undefined behaviour
  under the Swift memory model, not merely an inaccurate statistic.

  This affected **thirteen** interfaces, not one. The counters now live in a
  single lock-guarded `InterfaceCounters` type that every interface holds, so
  the next interface added inherits the fix instead of rediscovering the bug.
  `I2PInterfacePeer` previously took a lock on write only, which left every
  *reader* racing regardless — it is fixed too.
- **`Link` traffic statistics raced their readers.** `tx` / `rx` / `txBytes` /
  `rxBytes` were written under `stateLock` but exposed as stored properties, so
  a reader on another thread raced every write. Now routed through the same
  guarded counters.
- **`Link.establishmentTimeout` and `Link.onTimeout` raced the watchdog.**
  `Link.initiate` starts the watchdog before returning, so the watchdog thread
  was already reading both by the time the caller assigned them on the very next
  line — which is the normal usage pattern. Both are now guarded by `stateLock`,
  matching how `status` and `teardownReason` already worked.
- **`ChannelPacketHandle.state` raced its readers.** `markDelivered()` /
  `markFailed()` wrote it under a lock, but `state` was a stored property that
  `Channel` polls via `ChannelOutlet.getPacketState` and `Link` filters its proof
  waiters on. Its `deliveredCallback` and `timeoutWork` were likewise assigned
  directly by outlets while the delivery thread cleared them under the lock;
  those now go through guarded setters.
- **`I2PInterface` always reported zero traffic.** It declared all four counters
  but never incremented them — the parent performs no I/O of its own, and every
  byte moves through a dialed or accepted peer. It now sums its peers, which is
  what the numbers were always meant to show.
- **`Interface.isOnline` raced its readers.** Every interface flips it from its
  own I/O queue (an `NWConnection` state handler, a CoreBluetooth callback, a
  serial reader) while `Transport` consults it before routing and apps read it
  for every row of an interface list. All 20 declarations across 16 files now
  sit over a lock-guarded `LockedFlag`. Because they became *computed*
  properties keeping the same access level, all 51 assignment sites are
  unchanged — the setter is simply guarded now.

### Known remaining race

- **`RNodeInterface` radio telemetry** (`rStatRssi`, `rStatSnr`,
  `rBatteryState`, `rFrequency`, …) is written on the radio read thread and read
  by UI. Deferred rather than rushed: it is entangled with the radio state
  machine, and verifying a fix needs real RNode hardware. It is also why the
  radio-parameter readout on a connected RNode can show stale values.

## [1.4.2] — bz2 compression on by default; request-timeout fix

### Fixed

- **Compressed Resources from Python peers could not be received.**
  `Resource.compressor` defaulted to `NoCompressor`, whose `decompress` returns
  `nil`. Python RNS bz2-compresses any resource-sized payload and sets the
  per-resource `compressed` flag, so every compressed Resource a peer sent (large
  NomadNet pages, large LXMF messages, RRC notices — anything over the link MDU)
  failed to assemble and tore the link down. The default is now `BZip2Compressor`,
  matching Python. On send, a resource is compressed only when bz2 actually
  shrinks it (the `compressed` flag records the choice), so **the wire format is
  unchanged** and stays compatible with every RNS implementation. `StreamDataMessage.compressor`
  (Buffer streams) likewise defaults to `BZip2Compressor`; compression on send
  there remains opt-in per write. Install `NoCompressor()` / `nil` to opt out.
- **A request whose response arrived as a Resource could time out mid-transfer.**
  A link request armed a single fixed-timeout timer that fired `fail("timeout")`
  unconditionally at `sentAt + timeout`; when the response came back as a Resource
  (any multi-KB payload — e.g. a real NomadNet page), the timer fired while the
  transfer was still in flight and tore the link down. Following Python
  (`RequestReceipt.response_resource_progress`), the request timeout is now
  disarmed the moment the response enters RECEIVING, handing the transfer's
  lifetime to the Resource's own watchdog. A stalled transfer still concludes the
  receipt via the transfer's failure hook. Fixes NomadNet "pages won't load" for
  real pages over slower / multi-hop meshes.

## [1.4.1] — Correct the reported library version

### Fixed

- **`Reticulum.version` was stuck at `"0.1.0"`.** The constant was never bumped
  past the initial value, so `rnsd --version` and RetiOS's Settings ▸ About both
  reported "ReticulumSwift 0.1.0" despite the package being released through
  1.4.0. It now reports the real release version. (`version` is informational
  only — it never travels on the wire.)

### Added

- **`Reticulum.rnsProtocolVersion`** — the Python RNS release whose wire protocol
  this port matches (currently `"1.4.0"`), kept distinct from the library's own
  release `version`. Mirrors Python's single `RNS.__version__` as a parity
  reference.

## [1.4.0] — Large link packets, response Resources & RNS 1.4.0 parity

### Fixed

- **Inbound link packets larger than the base MTU were silently dropped.**
  `Packet.pack()` enforces a 500-byte (`Constants.mtu`) transmit cap, and
  `Packet.hashablePart()` computed the packet hash through `pack()` — so hashing
  threw for any packet over 500 B, and `Transport.filterAndRecord()` treated the
  failed hash as a duplicate and dropped the packet before it reached
  `Link.receive`. Because links negotiate their MTU upward (a TCP link commonly
  reaches 8192), a peer legitimately sends single link packets far larger than
  500 B — e.g. a NomadNet node serving any real page. **Every such packet was
  discarded**, so browsing NomadNet pages timed out. Packet identity and byte
  accounting are now MTU-independent (new `Packet.packedBytes()`), matching Python
  (`get_hashable_part` slices the already-packed bytes; only `pack()` checks the
  MTU). (bugs/010)
- **Over-MDU request responses sent as Resources used the wrong payload envelope.**
  The responder resourced the bare response value and the initiator delivered it
  un-decoded, so a large response either arrived msgpack-wrapped (Swift↔Swift) or
  timed out (a Python fetcher's `unpackb([id, response])` threw). Both sides now
  use the `[request_id, response]` envelope — identical to the single-packet path —
  matching Python `Link.handle_request` / `response_resource_concluded`. (bugs/011)

### Changed — RNS 1.4.0 parity

- **Link keepalive** is now sent when *either* the inbound *or* the outbound
  direction has been idle for `keepalive` (previously inbound only), so a
  receive-only initiator no longer has its link torn down as stale by the peer.
  The responder rate-limits its `0xFE` keepalive echo (skips it when it has sent
  something within `keepalive`). (RNS commit e64d8150)
- **Default interface-discovery stamp value raised 14 → 16**
  (`DEFAULT_STAMP_VALUE`, RNS commit be36abd8).

### Tests

- Unit: `PacketOversizeMTUTests`, `LinkRequestTests.testLargeResponseViaResource*`,
  updated `KeepaliveTests`. Interop: tri-test `test_nomadnet_get_large` (py/swift
  matrix over a ~2 KB page) closes the blind spot where the suites only ever served
  a 20-byte page.

## [1.0.0] — Initial public release

First public release of ReticulumSwift — a from-scratch Swift port of the
[Reticulum Network Stack](https://reticulum.network), wire-compatible with the
Python reference implementation (RNS 1.3.0).

### Highlights

- **Cryptography** — Curve25519 (X25519 + Ed25519), HMAC-SHA256, HKDF, SHA-256/512
  via CryptoKit; AES-CBC + PKCS#7 via CommonCrypto; Reticulum Token.
- **Identity / Destination / Packet / Announce** — byte-identical wire format.
- **Transport** — routing, path table, announce relaying and dedup, ratchet
  rotation/learning, blackholing, announce rate-limiting, multi-hop links.
- **Link** — full handshake, keepalive, MTU signalling, request/response.
- **Resource** — segmented transfers with hashmap-windowed retransmit.
- **Channel / Buffer** — reliable ordered messaging and stream wrappers.
- **Interfaces** — TCP client/server, UDP, AutoInterface (mDNS), Backbone,
  Local, RNode (+ RNodeMulti), I2P (embedded i2pd), Serial, KISS, AX.25 KISS,
  Weave. (PipeInterface is intentionally out of scope on Apple platforms.)
- **`rnsd`** — a Reticulum daemon executable, config-compatible with Python's.
- **IFAC** — deterministic Ed25519, wire-compatible with Python's pure25519.

Covered by 2,145 unit tests (~78% line coverage) plus a live Python↔Swift
interoperability suite.
