# Changelog

All notable changes to ReticulumSwift are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [1.5.0] — The `rn*` command-line utilities

Ports of the tools in `RNS/Utilities`, each split into a testable library type under
`Sources/ReticulumSwift/Utilities/` and a thin executable target that only parses
arguments, prints, and sets an exit code. No SPM dependency was added; the `argparse`
subset the tools need is implemented in-package.

Every claim below was checked against the **installed Python tools**, not against the
reference source alone: help text and error pages byte-for-byte, live rendering against a
running daemon, and — for the payload fixes — a Swift `rnsd` on isolated ports driven by
the real Python `rnstatus` and `rnpath`.

### Added

- **`rnstatus`** — interface and transport status, JSON mode, sorting and filtering,
  monitor mode, and remote status over a management link.
- **`rnpath`** — path table, announce-rate table, path requests, drop path / all-via /
  announce queues, and blackhole listing and management.
- **`rnprobe`** — probe a destination and report round-trip time and physical-layer stats.
- **`rncp`** — authenticated file transfer over the Resource API, both directions,
  including fetch mode.
- **`rnid`** — identity generation, import/export, RSG signatures, signed messages, ASCII
  armour, and chunked file encryption and decryption.
- **`rnx`** — remote command execution. The listener half executes commands and is
  macOS-only.
- **`rnsd`** — brought to parity with `rnsd.py`: service mode, log destinations, verbosity
  arithmetic, and `--exampleconfig` (byte-identical, 14,960 bytes).
- **`rnir`, `rnpkg`** — the two placeholder tools, which only bring up an instance.

Supporting API:

- `InstanceConnection` — resolves the config directory the way Python does, then either
  becomes the shared instance, attaches to a running one as a local client, or runs
  standalone. The Swift equivalent of `RNS.Reticulum(require_shared_instance=…)` plus the
  `is_connected_to_shared_instance` branch.
- `RPCClient` — client for the instance-control channel, counterpart to `RPCServer`.
- `MultiprocessingAuth` — CPython's `multiprocessing.connection` handshake, both the
  pre-3.12 and 3.12+ generations.
- `ArgumentParser` — the `argparse` subset the utilities need, including `allow_abbrev`.
- `UtilityFormatting` — the utilities' own `size_str` / `speed_str` / `pretty_date`, which
  differ from the `RNSUtilities` helpers in ways that show up in output.
- `InterfaceStatsPayload` — the `get_interface_stats()` dictionary, shared by the RPC
  server, the `/status` request handler, and `rnstatus` running in-process.
- `Interface.statsTypeName` / `statsShortName` — what a Python peer should be told this
  interface is called.
- `MsgPack.Value` scalar accessors (`asInt`, `asDouble`, `asString`, `asData`, `asBool`,
  `asArray`, `asDictionary`, `isNil`) are now public.
- `ReticulumConfig` parses `shared_instance_port` and `instance_control_port`.

### Fixed

These are interop defects that predate the utilities: Swift produced something a Python
client indexes directly, so the Python side raised rather than degrading.

- **Instance-control authentication rejected CPython 3.12 and newer.** `RPCServer` only
  implemented the legacy handshake — a 20-byte challenge answered with a bare HMAC-MD5
  digest — and hard-rejected anything that was not exactly `#CHALLENGE#` plus 20 bytes.
  CPython 3.12 changed the format to `{digest}` plus 40 random bytes, with the MAC covering
  the whole prefixed message, so a modern `rnstatus` or `rnpath` could not authenticate
  against a Swift `rnsd` **at all**. Both generations now work in both directions.
- **Blackhole source files were written as JSON where Python writes msgpack.** Python's
  `reload_blackhole` unpacks each file with msgpack, so it could not read a Swift-written
  list, and Swift silently ignored every list Python published.
- **`Transport.isConnectedToSharedInstance` was never assigned.** It was declared and read
  in three places but set nowhere, so it was false in every process. A stack attached as a
  local client therefore redid work the shared instance had already done: `filterAndRecord`
  re-ran the HEADER_2 transport-id filter and dropped packets that had been forwarded *to
  us*, `shouldApplyDelta` applied the local hops delta a second time, and `rnprobe` took the
  standalone branch and never reported RSSI, SNR or Link Quality.
- **`blackholed_identities` returned `{hash: true}`.** Python returns the entry dictionary
  `{"source", "until", "reason"}` verbatim, and `rnpath -b` reads all three fields.
- **The `/path` remote-management handler dropped keys.** `timestamp` and `interface` were
  missing from table entries, `blocked_until` and `timestamps` from rate entries, though
  `rnpath` prints `path["interface"]` and derives the announce rate from
  `entry["timestamps"]`. It also ignored the `max_hops` element of the request.
- **The `/status` remote-management handler returned a summary.** Python's
  `remote_status_handler` appends `get_interface_stats()` verbatim; this returned a list of
  `{name, rxb, txb}`, leaving `rnstatus -R` with nothing to read.
- **`ifac_signature` reported the IFAC key.** Python reports
  `ifac_identity.sign(full_hash(ifac_key))` — different bytes, whose last five `rnstatus`
  prints as the network's "Access" fingerprint. A Swift node and a Python node on the same
  IFAC network displayed different access codes.
- **`drop:path` over RPC returned nil** instead of the bool from `expire_path`, which
  `rnpath` uses to choose between "Path to … was dropped" and "No path known".
- **Interface `type` and `short_name` published Swift class names.** A Python client saw
  `PosixTCPServer` where a Python daemon reports `LocalServerInterface`, and would have seen
  `LocalInterface` for what Python calls `LocalClientInterface`; `short_name` reported
  "Shared Instance" where Python hardcodes "Reticulum".
- **Per-interface key order in the stats payload did not match Python's.** `rnstatus -j`
  serialises with `json.dumps`, which preserves insertion order, so the order is part of the
  `-j` output contract. `announce_queue` was also emitted unconditionally, where Python
  creates the attribute lazily and `rnstatus` branches on its presence.
- **`ResourceTransfer.onProgress` was never invoked**, so every progress readout sat at 0%.
- **`Link.handleIncomingRequestResource` unwrapped the request payload only for `.bytes`**
  and dropped the raw value, breaking large requests from Python peers.
- **`argparse` behaviour across all nine tools.** `allow_abbrev` is an `argparse` default
  that none of the RNS utilities disable, but only `rnsd` implemented it, so eight tools
  rejected `--conf` and `--vers`. Unrecognised options were reported in the singular where
  `argparse` always uses the plural; options were named by the spelling typed rather than
  by every spelling (`argument -s:` instead of `argument -s/--sort:`); `rnstatus` printed no
  usage block at all and `rnid` printed its entire help text where `argparse` prints four
  lines of usage and one of error; and `rnstatus -w`, `rnstatus -I`, `rncp -w` and `rncp -b`
  accepted non-numeric values and silently fell back to defaults.
- **`rnpath` could not be interrupted.** `signal(SIGINT, SIG_IGN)` disabled the default
  terminate action while the `DispatchSource` meant to replace it was scheduled on the main
  queue, which `rnpath`'s blocking wait never services — so Ctrl-C was a complete no-op.

### Known divergences

- **`rnpath`'s exit codes reach the shell and Python's do not.** `RNS/__init__.py` defines
  its own `exit(code)` ending in `os._exit(code)`, and the `atexit` teardown's `os._exit(0)`
  overrides the pending `SystemExit`, so every `exit(1)` / `exit(20)` inside `program_setup`
  is discarded — measured 0 where the source asks for 1 or 20. Matching that would mean
  `rnpath` could never signal failure to a script, so the codes its own source asks for are
  used instead. `argparse` errors agree exactly (exit 2), because those are raised before
  the stack starts.
- **`--version` reports this port's release**, not the RNS protocol version it is
  wire-compatible with. All nine tools answer identically.
- **`rnprobe`'s spinner is gated on a TTY**, where Python writes backspaces and raw glyphs
  unconditionally and makes redirected output unusable for scripting.
- **A Swift shared instance does not enumerate a per-client interface entry.** Python
  creates a `LocalClientInterface` object per connected client, which appears in `rnstatus`
  output; Swift's server handles clients internally, so `rnstatus` against a Swift daemon
  lists fewer interfaces. The client count itself is reported correctly.

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
