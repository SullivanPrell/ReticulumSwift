# Changelog

All notable changes to ReticulumSwift are documented here. This project follows
[Semantic Versioning](https://semver.org).

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
