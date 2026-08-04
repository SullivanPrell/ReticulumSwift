# Changelog

All notable changes to ReticulumSwift are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Every idle low-RTT initiator link died after ten seconds (`bugs/034`)

`Link.watchdogMaxSleep = 5` was declared and **never used** — its only reference in the whole
package was a test asserting its value. Python clamps *every* watchdog sleep to it
(`RNS/Link.py:775`), so a status change is observed within five seconds no matter what the
previous state scheduled. Without the clamp, a link that established scheduled its next tick at
`requestTime + establishmentTimeout` (~10.4 s) and slept straight through the window in which
the initiator's keepalive was due (the interval floors at 5 s). No keepalive was ever sent, so
the first tick after establishment found the link idle past `stale_time` and tore it down
immediately.

Every idle initiator link on a low-RTT path therefore died at about ten seconds. It surfaced as
`bugs/034` — intermittent RRC chat-message loss — because the receiver's link expired in the gap
between joining a room and the hub's fan-out, and the failure looked like message loss rather
than link loss. The Go hub independently stale-closed both Swift clients at ~17 s idle, having
received no keepalive from either.

Three Python behaviours were missing alongside the clamp, and are ported with it:

- The keepalive goes out **before** the stale check (`RNS/Link.py:749-751`), so a link crossing
  `stale_time` still probes its peer instead of being abandoned unasked.
- Crossing `stale_time` **marks** the link stale and schedules a grace tick
  (`rtt * KEEPALIVE_TIMEOUT_FACTOR + STALE_GRACE`, `:753-755`) rather than tearing down on the
  spot; only the tick that follows tears down.
- Inbound traffic on a stale link **recovers** it to active (`:939`). The port dropped all
  inbound on a non-active link, so a link that went stale could never come back.

A stale link now also emits `LINKCLOSE` on teardown, as Python does for every status but pending
and closed — its peer is told rather than left to time out on its own.

Found by attributing `bugs/034` rather than by a failing test; the defect predates the initial
public release.

### The RNode bring-up gate must not block its caller's thread

1.10.0's bring-up gate (`bugs/057`) waited for the device's detect response on the thread that
called `start()`. That is safe for a config-file interface, and **deadlocks** for the port's only
real BLE transport: `RNodeScannerController` hands `CBCentralManager` one serial queue and calls
`start()` from `onGATTReady`, which arrives on it — so every subsequent delegate callback,
including the `didUpdateValueFor` that sets `detected`, is queued behind the wait. The wait was
starving the response it was waiting for: it could only ever time out, close the transport, and
leave the interface offline for good.

`start()` now performs open and detect and returns; the rest of the sequence runs on a queue the
interface owns, which by construction is never a transport's delivery queue. A caller that wants
the reference's synchronous `__init__` semantics — `rnsd` bringing up a config-file radio — calls
the new `waitUntilOnline(timeout:)` explicitly, and `synthesizeInterfaces` does. Same shape for
`RNodeMultiInterface`.

The fix is the same lesson `bugs/058` records, turned on the fix for `bugs/057`: a component must
not depend on a scheduling property its callers cannot be relied on to have.

### Every documented interface type constructs from a config file (`bugs/031`)

`RNodeInterface`, `KISSInterface`, `AX25KISSInterface` and `I2PInterface` fell through
`synthesizeInterfaces` to `iface = nil` — no throw, no log — so an operator who uncommented a
documented radio block got a daemon that started, reported healthy, and had no radio.

The four types construct through **`InterfaceTransportFactories`**: device strings resolve
through per-platform factory registrations, so the construction switch carries no platform
conditionals and the split (serial on macOS, BLE from the application, embedded i2pd
everywhere) is expressed as which factories are registered. The unavailable path throws naming
the family, the device string and where to register support; a missing or out-of-range radio
parameter throws per the reference's `validcfg` gates, and the propagated throw is this port's
`RNS.panic()`. Absent *hardware* is not a construction failure: transports open at `start()`,
so a discovery-written entry with an unfilled `port =` constructs and fails at bring-up with a
real cause, matching the reference's retry posture.

Ships the package's first concrete serial transport (`POSIXSerialPort`, termios, macOS), the
serial-backed `RNodeTransport` adapter, RNode station identification
(`id_callsign`/`id_interval`, the reference's `first_tx` machinery), and all 18 previously
unread interface-block keys — including `device`, which now binds the named network device's
address on UDP and TCP server instead of the wildcard. An unknown interface type is a loud
error naming the type, matching the current reference's external-module miss
(`Reticulum.py:1055-1061`); it no longer silently vanishes.

New storage inventory entry: `storage/i2p` (`I2PInterface.py:90-91`), the embedded daemon's
data directory when a config block constructs the interface.

**The rest of the types followed.** `SerialInterface`, `RNodeMultiInterface` and
`WeaveInterface` construct too — Weave being the aggravated case, since this port's own
discovery emits `type = WeaveInterface` entries its config path then rejected. The config
parser gained configobj's third section level: a `[[[sub]]]` line begins with `[[` and ends
with `]]`, so every RNodeMulti radio row had been leaking out as a *top-level* interface named
`[sub]` with type Unknown. `PipeInterface` keeps taking the loud unknown-type path by
documented design (POSIX subprocess pipes, no mobile use case), now pinned by a test.

### An RNode reports online only after a validated bring-up

`start()` was `open(); isOnline = true`, with `detect`, `initRadio` and `validateRadioState`
carrying **zero production callers** — only tests called them by hand. A host-mode RNode was
therefore never sent `CMD_FREQUENCY`/…/`CMD_RADIO_STATE ON`: its radio stayed off while
`rnstatus` reported the interface Up and Transport routed packets into it. `start()` now runs
the reference's `configure_device` gate (`RNodeInterface.py:424-467`) — detect, bounded wait,
`initRadio`, validate the echoed parameters, and only then online; any failure closes the
transport and stays offline. `RNodeMultiInterface` gets the same gate. `validateRadioState`
now `None`-guards only the frequency comparison as the reference does, because guarding all
five made validation vacuously true against a device that answered nothing.

### Serial-family interfaces notice device loss, and redial

Nothing in the port could observe a USB flap: the transport seams had no error surface,
`POSIXSerialPort` discarded device-gone reads and never checked `write()`'s `-1`, and no
serial-family interface went offline except an explicit `stop()`. The interface stayed Up with
growing TX counters while every packet went into a dead descriptor — where a Python node
resumes within ~5 s. Both transport protocols now require `onTransportError`; one shared
reconnect loop serves all five interfaces, re-running the full `start()` (an RNode re-runs its
whole bring-up — a re-powered modem lost its configuration with its power); and a failed write
is no longer counted as transmitted bytes.

### Hardware MTU follows bitrate

`optimise_mtu` (`Interface.py:205-217`) had no port, and the class constants were `let`s that
could not be recomputed. Swift advertised 262144/1048576 in `LINKREQUEST` MTU signalling where
Python advertises 8192/16384 in the identical topology. The ladder now runs after the
configured bitrate and on every spawned server-side client. `LocalInterface` gains the
`HW_MTU`/`AUTOCONFIGURE_MTU` it never had, which had disabled link-MTU discovery for every
link crossing a Swift shared instance.

### Two attributes that were written but never read, and one never written

- **`wants_tunnel`**: a TCP or Backbone client never requested tunnel synthesis, so the remote
  transport never rebuilt the paths it held and every reconnect silently lost them. Requested
  on connect, served from the jobs loop.
- **`announce_cap`**: parsed, validated, written onto the interface, inherited by spawned
  clients — and then every rate computation divided by a hardcoded 2%. Both `AnnounceQueue`
  paths now use the interface's own cap.
- **`packetFilter`** (`bugs/038`): keyed on the 16-byte truncated hash against a list of
  32-byte full hashes, so "seen" was always false. Reader and writer now share one key.

### Smaller corrections

- The instance-control RPC listener binds loopback instead of the wildcard, matching
  `Reticulum.py:352`. It had been reachable from every network the host was attached to.
- A dialing backbone reports `BackboneClientInterface` in `ifstats["type"]`; it had been
  publishing the Python *listener*'s class name to every consumer keying on that field.
- `prettyshorttime`'s integer-microsecond rounding is recorded as a deliberate divergence with
  the reference's own float-artifact strings captured beside each pinned assertion, rather
  than sitting under a file header claiming Python parity it never had.

## [1.9.0] — persisted state, and a node that listened to itself

A minor rather than a patch release: **every persisted state file changes name, encoding or
both**, so a config directory written by 1.8.0 or earlier is not read by this version. See
*Upgrading* below — the cost is one cold start, and nothing is destroyed.

### Changed — persisted state is now the reference's, byte for byte (`bugs/029`)

A Reticulum config directory is a shared surface the moment `rnsd` can be either
implementation, which is what the RetiOS macOS daemon probe and the interop suite already
assume. Four files diverged from the Python reference in name *and* encoding for the whole
life of the port, and a fifth was not written at all. None of it was visible: the names
resembled the reference's closely enough to read as correct in a directory listing, and
3400 unit tests round-tripped the port's own shape through the port's own codec.

| was | is now | encoding |
|---|---|---|
| `storage/paths.json` | `storage/destination_table` | umsgpack, 8-element entries (`Transport.py:3390-3407`) |
| `storage/known_destinations.json` | `storage/known_destinations` | umsgpack dict → 5-element list (`Identity.py:107,198`) |
| `storage/packet_hashlist` | `storage/packet_hashlist.raw` | raw concatenated 32-byte hashes (`Transport.py:3323`) |
| *(not written)* | `storage/tunnels` | umsgpack, `[tunnel_id, interface_hash, paths, expires]` (`Transport.py:3487`) |
| `storage/cache/announces/<hash>` | unchanged name | umsgpack `[raw, interface_name]` (`Transport.py:2655`) |
| `storage/ratchets/<hash>` | unchanged name | umsgpack `{ratchet, received}` (`Identity.py:424-434`) |

The path table's *shape* changed as well as its encoding: an entry now references an
announce packet in `storage/cache/announces/` instead of inlining the destination's public
key and ratchet, which are resolved through `known_destinations` and `storage/ratchets/` as
the reference does. Re-encoding the old shape under the reference's name would have produced
a file Python still could not read — the worst available outcome, because it looks right.

Three fields of the known-destinations entry were not being persisted at all and now are:
the last-announce time (previously overwritten with "now" on every save, so
`UNUSED_DESTINATION_LINGER` could never expire anything), the last-use time, and the
retention sentinel (so a pinned destination was eligible for the next sweep).

`storage/ratchets/` is the one to note if you run both implementations: the port wrote JSON
where the reference writes msgpack, at the same path under the same filename, and **both
implementations delete what they cannot parse there** — so each side was destroying the
other's forward-secrecy state on every switch (`bugs/039`).

### Fixed — the path table now actually restores (`bugs/041`)

`Reticulum.start()` reads the path table and resolves each entry's interface; `rnsd`
synthesises the configured interfaces *after* `start()` returns. So the restore ran against
an empty interface set and dropped every entry, on every start, under every on-disk format.
A Swift daemon had never restored a path table. Entries whose interface has not appeared yet
are now held and installed as interfaces register, with a bounded give-up matching the
reference's outcome for an interface that is not there.

This is why the format work above is necessary but not sufficient: with `029` fixed and this
not, the daemon writes a perfectly correct `destination_table` and still starts with no paths.

### Fixed — a node acted on its own announces (`bugs/047`)

A transport-enabled neighbour reflects announces back to the node that originated them, by
design: `Transport.outbound`'s broadcast loop (`Transport.py:1197`) has no receiving-interface
exclusion, and the PATHFINDER_R retransmission re-sends with `attached_interface = None`
(`:604-637`). Every node hears its own announces come back, and every node is expected to ignore
them.

The reference ignores them with one test — `local_destination` is looked up in
`destinations_map` and the **entire** announce block hangs off it being nil
(`Transport.py:1767-1772`), with the ownership check repeated at the path-table admission test
(`:1806-1807`). This port had no equivalent anywhere in `handleAnnounce`. The one place it
consulted `registeredDestinations` in that path was an ingress-limit *exemption* — the opposite
polarity, making the node more eager to process its own announce, not less.

So a node learned a path to itself, re-cached its own identity from the wire, handed its own
announce to every registered handler, and could relay it onward. For most destination types that
is invisible: a delivery destination re-learning its own stamp cost changes nothing. It became
visible only when a handler that *creates state* appeared — an LXMF propagation node, which
peers. A lone one, on a mesh with nobody else on it, ended with exactly one peer: itself.

Three existing tests were passing only because the gate was missing; each registered the
destination it then announced to itself, which was never what they were testing. A fourth
asserted "the handler was NOT called" and would have started passing for the gate's reason rather
than the path-response filter's — it is fixed too.

### Fixed — a control listener that reported a bind it did not achieve (`bugs/040`)

`NWListener` reports bind failures asynchronously through `stateUpdateHandler`. None was set,
so a listener that never bound still logged "RPC server started on port N", and the caller
discarded the errors that *were* raised. The daemon then ran normally while `rnstatus`,
`rnpath`, `rnprobe`, `rnid -r` and `rnx` all answered "Could not connect to instance control
socket" — from the utility's side, indistinguishable from no daemon at all. The failure is
now detected and logged at CRITICAL, naming what has become unreachable.

### Upgrading

**Expect one cold start.** A daemon upgrading past this release meets none of its own
previous state files and starts with an empty path table, no known destinations and an empty
replay window, relearning them from announces. That is exactly what the reference does on a
fresh install, and what it does for any file it cannot find (`Identity.py:238-240`,
`Transport.py:243`).

There is deliberately **no migration reader**. A converter for the port's own earlier formats
would be implementation-specific code on the one seam this change exists to make
implementation-independent, and the reference has no counterpart to it.

**Three files are left behind as orphans and are safe to delete:**

```
~/.reticulum/storage/paths.json
~/.reticulum/storage/known_destinations.json
~/.reticulum/storage/packet_hashlist
```

They are not read, not written and not deleted — removing an operator's files to tidy up is
not a decision this release makes. Learned peer ratchets under `storage/ratchets/` *are*
removed as they are encountered, because they sit at a name the reference uses and a Python
daemon deletes them anyway.

Rolling back is symmetric: the reference-format files a rolled-back build leaves behind
become orphans in their turn, and the older build starts empty. No data is destroyed in
either direction.

## [1.8.0] — the bugs/013 defect class: config, transport identity, delivery truth

A minor rather than a patch release, for the same reason 1.7.0 was: `displayName` changes
for eleven more interface types and `Interface.hash` is `fullHash(displayName)`, so
interface identity changes again.

### Corrections to 1.7.0

Two claims in the 1.7.0 notes below were wrong when published. The 2026-07-29 audit
falsified both. They are corrected here rather than edited out of history.

- **"All config-directory resolution now goes through
  `InstanceConnection.homeDirectory(environment:)`"** — it did not. One resolver was
  converted; **fourteen** other sites still reached a platform home API. `rnir` and `rnpkg`
  passed `FileManager.homeDirectoryForCurrentUser` into the config resolver;
  `RNCopyDiskFileSystem.homeDirectoryPath` — which is where `rncp`'s `$HOME/.rncp` identity
  and allow-list come from, and which the same 1.7.0 note describes as a problem — was still
  `NSHomeDirectory()`; and eleven `expandingTildeInPath` sites across `rnid`, `rnpath`,
  `rnstatus`, `rnx` and two library files resolved every user-supplied `~` against the
  account's real home. So the failure the note describes — a utility under a relocated
  `HOME` reading the real `~/.reticulum`, finding the live daemon's identity and
  authenticating to the live daemon — remained reachable through all of them. Fixed below,
  with a structural guard so the claim is now checkable rather than asserted.

- **"Python sets `SO_KEEPALIVE` and the probe timers on every TCP socket it opens … this
  port set none"** — the statement about Python is right; what shipped covered the two
  *dialing* paths. `TCPServerInterface.start()` still passed `.tcp` to `NWListener`, so every
  connection a listening interface accepted took Network.framework's defaults with keepalive
  **off** — which is the case Python's own `connected_socket` branch exists to handle
  (`TCPInterface.py:241`, `:259-261`, reached from `:591`). Three further sites were also
  never covered. Fixed below.

### Fixed

- **A packet on an MTU-upgraded link could not be sent at all** (`bugs/033`). `pack()` capped
  every packet at the global 500-byte MTU. Python carries a *per-packet* cap and takes it from
  the destination — `self.MTU = destination.mtu` for LINK-typed packets (`Packet.py:153-154`) —
  so once MTU discovery raised a link, the resource parts `bugs/016` sizes from that negotiated
  MTU exceeded the global cap and every one of the thirteen interfaces refused to transmit
  them. The sender advertised a resource and then sent nothing; the peer timed out. This is the
  outbound half of `bugs/010`. `Packet.mtu` is now set from the link in `Transport.send`, and
  from the packet's own size in `unpack` so a relay forwards an upgraded link's traffic without
  re-capping it. **Found by the interop suite, not by any unit test** — there was no
  package-level test of an over-MDU request response, which is why it survived.

- **The path table and the link table routed by interface name** (`bugs/027`). Both stored
  `Interface.name` and resolved it with `first(where:)`, and every connection accepted by one
  `TCPServerInterface` is named `"Client on <server>"` by design (`TCPInterface.py:590`). With
  two clients attached, every route resolved to whichever registered first — regardless of
  which one heard the announce — so traffic went to the wrong peer while the table insisted it
  had a route. Both tables now hold weak references to the interface object, as the reference
  does (`Transport.py:1639`, `:1693`), and keep the name for display only (`Reticulum.py:1532`).
  Persistence stores `Interface.hash` and resolves it through the new
  `Transport.findInterface(fromHash:)`; an entry whose interface is gone is not persisted
  (`:3374`) and one whose hash resolves to nothing is dropped on load rather than restored
  unroutable. **The link-table half was found only by the new interop cell**: link
  *establishment* routes through the path table, so a relayed link came up normally and only
  the traffic afterwards was misrouted — it read as a resource bug.

- **Shutdown never tore links down** (`bugs/028`). `Transport.detachInterfaces()` was a
  faithful port with zero callers, so a node exiting cleanly emitted no `LINK_CLOSE` and every
  peer held the link ACTIVE until its own keepalive watchdog expired — up to 360 s — with the
  sessions riding those links hanging rather than failing. `Reticulum.stop()` now calls it,
  **before** `transport.stop()`: running it after would hand the closes to already-stopped
  interfaces, satisfying "teardown was called" while emitting nothing.

- **Discarding an unstarted dispatch source killed the process** (`bugs/032`). A source from
  `DispatchSource.make…Source` begins suspended, and libdispatch traps when a suspended
  object's last reference is released — cancelled or not. `Link.rescheduleWatchdog` and
  `TCPClientInterface.scheduleReconnect` released one after only `cancel()`, on paths reached
  by ordinary link teardown and by a `stop()` landing during a failed dial. `SIGTRAP`, nothing
  thrown or logged. Both now use `DispatchSourceProtocol.cancelUnstarted()`.

- **Link data packets generated no receipt** (`bugs/014`, the transport half). `Transport.send`
  gated receipt creation on `destinationType == .single`, and `Link.send` hardcoded
  `generateReceipt: false`, so nothing above the link could learn whether a packet arrived.
  Receipts are now generated for link packets matching the reference's predicate
  (`Transport.py:1113-1124`), and `Link.receive` routes a context-`.none` PROOF to the
  packet-receipt table when no channel-proof waiter matches.

- **Eleven interface types published a name Python does not** (`bugs/022`). `displayName`
  defaulted to the bare configured `name`, and 1.7.0 corrected it for the TCP and UDP
  families by adding per-type overrides — so every type it did not touch kept the wrong
  shape. Since `Interface.hash` is `fullHash(displayName)` and `rnstatus` filters and hides
  rows by class prefix, each was a different interface identity on the wire than the Python
  interface beside it, and invisible to a class-name filter.

  The default is now the composed `"\(statsTypeName)[\(name)]"`, so a new interface type
  gets the correct shape by declaring nothing. Overrides remain only where the reference
  string is genuinely a different shape:

  | | before | after |
  |---|---|---|
  | Serial, KISS, AX25KISS, RNode, RNodeMulti, I2P, Weave | `<name>` | `<Class>[<name>]` |
  | `BackboneInterface` | `<name>` | `BackboneInterface[<name>/<ip>:<port>]` |
  | `RNodeSubInterface` | `<name>` | `<parent name>[<name>]` |
  | `PosixTCPServer` | `<name>[<port>]` | `Shared Instance[<port>]` |
  | `WeaveInterfacePeer` | `WeaveInterfacePeer[01020304]` | `WeaveInterfacePeer[01:02:03:04]` |

  The last two were not in the audit's list. `PosixTCPServer` built Python's literal
  `"Shared Instance[<port>]"` (`LocalInterface.py:496-498`) out of `name`, so it matched only
  because its one caller happens to pass that string. `WeaveInterfacePeer` published
  undelimited hex where `RNS.hexrep` delimits with `:` (`RNS/__init__.py:176-183`) — a
  correct-looking string with a different hash.

  `RNodeSubInterface` gained the `parentInterface` back-reference Python passes into its
  `__init__` (`RNodeMultiInterface.py:939`), assigned when the multi-interface adopts its
  sub-interfaces, since Swift constructs them before the parent exists.

- **A non-connectable I2P interface was never hidden from status output** (`bugs/022`).
  The suppression gate was a faithful port of `rnstatus.py:393-403` and its tests passed —
  against a hand-built stats dict named `"I2PInterface["`, the string the gate keys on. A
  real interface published its bare configured name, so the prefix never matched and the
  gate suppressed nothing. Fixed by the published-name change above; now asserted from a
  real interface through the rendered output, for any configured name.

- **Sockets this port accepted or listened on took Network.framework's defaults**
  (`bugs/023`). Python configures the socket it accepts exactly as the one it dials, so
  direction must not decide whether the options apply. All socket options now come from a
  single `RNSSocketOptions` factory, and a structural test fails if any other file
  constructs them. Six sites were bypassing it:

  - `TCPServerInterface.start()` — the listener, and so every connection accepted from it.
  - `LocalInterface.connect()` — missing the `TCP_NODELAY` Python sets at
    `LocalInterface.py:147`.
  - `TCPClientInterface` — built its own; now delegates.
  - `RPCServer.start()` — `.tcp` on the loopback control listener.
  - `SAMSocket.connect()` — `.tcp`, so a SAM bridge that stopped answering left the I2P peer
    online forever. It now takes Python's **I2P** timing set (`I2P_USER_TIMEOUT` 45,
    `I2P_PROBE_AFTER` 10, `I2P_PROBE_INTERVAL` 9, `I2P_PROBES` 5), selected by
    `i2p_tunneled = True` at `TCPInterface.py:190-194` — a distinction this port did not
    previously have, and the direct-TCP timers would tear down a healthy tunnel.
  - `PosixTCPServer.acceptOne()` — set only `SO_NOSIGPIPE` where Python sets `TCP_NODELAY`
    on every accepted shared-instance socket (`LocalInterface.py:98-100`).

  The last three were not in the audit's list. The shared-instance option set is
  `TCP_NODELAY` **only**, matching Python: `LocalClientInterface` calls no `set_timeouts_*`
  on either direction, so enabling keepalive there would exceed the reference.

- **Fourteen sites resolved a home path without honouring `$HOME`** (`bugs/024`) — see the
  1.7.0 correction above. `InstanceConnection.expandTilde` is now the single expansion, with
  `posixpath.expanduser`'s semantics including the `rstrip('/')` on the home;
  `RNCopyDiskFileSystem` takes an injected environment. `rncp` already had a correct
  `$HOME`-aware expansion and now delegates to the shared one rather than keeping a second
  copy of the rules. The unset-`HOME` fallback in `InstanceConnection` is the one sanctioned
  exception, and a test pins it at exactly one occurrence.

### Changed

- **Resource part size, and every payload limit on a link, now derive from the negotiated
  per-link MTU** rather than the base constant (`bugs/016`) — resource segmentation, channel
  and buffer chunking, and request/response body limits. The receiver derives
  `total_parts = ceil(size / sdu)` itself instead of trusting the advertisement
  (`Resource.py:187`) and surfaces a disagreement at error level. **This is a wire change**: a
  1.8.0 node serving a resource over an upgraded link sizes parts differently from a 1.7.0
  peer. Old-receiver/new-sender works by accident (the old receiver follows the
  advertisement); new-receiver/old-sender now reports the mismatch instead of timing out.
- `Transport.PathEntry` and `Transport.LinkRoute` gain interface references and hand-written
  `==`; the name-only `PathEntry` initialiser still exists but builds a deliberately
  unroutable entry, and production code is forbidden from using it by a structural test.
- **Persisted path entries are keyed on `Interface.hash`.** Since that derives from
  `displayName` and eleven display names changed, a daemon upgrading across this release drops
  those paths and relearns them from announces. This mirrors the reference, which drops an
  entry whose interface hash is no longer active rather than misrouting it.
- `Interface.displayName`'s default is the class-qualified form rather than `name`. Any
  downstream conformer that relied on publishing a bare name — including test doubles —
  publishes `TypeName[name]` now.
- `TCPClientInterface.tcpOptions()` / `.tcpParameters` and `BackboneInterface`'s equivalents
  are removed; use `RNSSocketOptions`.
- `RNCopyDiskFileSystem.init()` gains an `environment:` parameter (defaulted, so existing
  callers are unaffected).

## [1.7.0] — TCP interface naming, reconnection and keepalive

A minor rather than a patch release: the fixes add public API (`reconnectWait`,
`maxReconnectTries`, `bindIP`, `HDLC.FrameDecoder.reset()`) and change what every TCP and
UDP interface calls itself — and therefore its `Interface.hash`, which is
`fullHash(displayName)`.

### Fixed

- **Configured TCP interfaces were invisible to `rnstatus`** (`bugs/013`).
  `TCPClientInterface.displayName` emitted `TCPInterface[Client on <host>:<port>]` for
  every client. In Python that form belongs only to a *server-spawned* client — the
  spawned interface's `name` is `"Client on "+servername` (`TCPInterface.py:590`) — and
  `rnstatus` hides every interface whose name starts with `TCPInterface[Client`
  (`rnstatus.py:397`), because those are per-connection sub-interfaces rather than
  anything an operator configured. So every interface from a config file was filtered out
  of every status report, by Python's `rnstatus` and this port's alike, while being online
  and passing traffic the whole time.

  The names now follow Python's `__str__` exactly:

  | | before | after (Python: `TCPInterface.py:456`, `:680`) |
  |---|---|---|
  | configured client | `TCPInterface[Client on 1.2.3.4:4242]` | `TCPInterface[<name>/1.2.3.4:4242]` |
  | listener | `TCPInterface[Server on 0.0.0.0:4242]` | `TCPServerInterface[<name>/<bind_ip>:4242]` |
  | spawned client | `TCPInterface[Client on <name>[client-N]]` | `TCPInterface[Client on <name>/<peer_ip>:<peer_port>]` |

  `Interface.hash` is `fullHash(displayName)`, so this also aligns interface identity with
  a Python daemon on the same network — previously the two disagreed for every TCP
  interface. `TCPServerInterface` gained a `bindIP` (default `0.0.0.0`), and interface
  synthesis now reads `listen_ip` for it.

- **`TCPClientInterface` never reconnected** (`bugs/013`). It dialed once from `start()`;
  on peer FIN the receive loop set `isOnline = false` and returned — no log line, no
  `cancel()`, no redial. A peer that accepts and immediately hangs up (ordinary churn on
  the public transit nodes) took the node permanently offline with nothing in the log,
  while the dead connection sat in `CLOSE_WAIT` for the life of the process. Python has
  retried since forever (`RECONNECT_WAIT = 5`, `RECONNECT_MAX_TRIES = None`,
  `TCPInterface.py:270-293`), and every other reconnecting interface in this port already
  did too — the TCP client was the only one that did not.

  Adds `reconnectWait` (default 5s) and `maxReconnectTries` (default nil = unlimited,
  config key `max_reconnect_tries`), cancels the superseded connection before each redial,
  and logs Python's "Reconnected socket for …" / "Max reconnection attempts reached for …".
  `.waiting` is no longer swallowed: a refused peer is retried on Python's clock instead of
  silently inside `NWConnection`.

- **No TCP keepalive on the dialing interfaces.** *(Corrected in 1.8.0 — this covered the
  two dialing paths only; the listener and three other sites still took framework defaults.)*
  Python sets `SO_KEEPALIVE` and the probe
  timers on every TCP socket it opens (`TCPInterface.set_timeouts_osx` /
  `set_timeouts_linux`, `BackboneInterface.py:655`); this port set none, because
  `NWConnection(to:using: .tcp)` takes Network.framework's defaults and those have keepalive
  off. A peer that vanished *without sending FIN* — a machine that slept, a NAT that dropped
  the mapping, a peer that was hard-killed — therefore left the connection `.ready` forever:
  no event fired, the interface kept reporting "Up", and everything sent through it was
  silently discarded. Reported as "RetiOS doesn't reconnect to the mesh after the laptop
  sleeps", and the reason the reconnect fix above could not cover that case on its own —
  nothing ever triggered it.

  The values live in `TCPClientInterface.tcpOptions()`, separately from the `NWParameters`
  built around them, because that object is the only place they can be read back at all:
  `NWParameters.defaultProtocolStack.transportProtocol` returns a *different*
  `NWProtocolTCP.Options` instance than the one passed to `NWParameters(tls:tcp:)` — `===`
  is false on every OS tested — and on macOS 14 that re-wrapped instance reports framework
  defaults rather than the configured values. Network.framework publishes no getters for TCP
  options at the C level either, so no readback anywhere is authoritative. The tests
  therefore assert the object this port constructs and hands over, and additionally verify
  the round trip through `NWParameters` on platforms where a control value proves the
  readback can be trusted.

  `TCPClientInterface` and `BackboneInterface` now dial with Python's values:
  `keepaliveIdle = 5`, `keepaliveInterval = 2`, `keepaliveCount = 12`,
  `connectionDropTime = 24`, and `noDelay = true` (`TCP_NODELAY`, which Python sets on every
  socket on both platforms).

- **Swift utilities ignored `$HOME`.** *(Corrected in 1.8.0 — "all config-directory
  resolution" was one resolver; fourteen other sites still reached a platform home API,
  including the `rncp` allow-list this very note describes.)*
  Python expands `~` with `os.path.expanduser`, which
  returns `$HOME` when it is set; `NSHomeDirectory()` — and
  `FileManager.homeDirectoryForCurrentUser`, which `rnsd` used — always reports the
  account's real home on macOS. A utility launched with `HOME` pointed at a sandbox
  therefore read and wrote the developer's actual `~/.reticulum`, picked up the real
  transport identity, and could authenticate to the real daemon on 37428. Utilities that
  keep state in `$HOME` directly (`rncp`'s `$HOME/.rncp` identity and allow-list) wrote to
  the developer's real files. All config-directory resolution now goes through
  `InstanceConnection.homeDirectory(environment:)`.

- **`UDPInterface` hardcoded `0.0.0.0` as its bind address** instead of reporting the
  configured `listen_ip`, as Python does (`UDPInterface.py:63`, `:131-132`) — so a
  loopback-bound interface published a different name, and a different `Interface.hash`,
  than the Python interface beside it. Gained a `bindIP`, which synthesis now populates.

- **A server-spawned client published `type = "TCPServerClientInterface"`**, which is not an
  RNS interface class. Python builds a plain `TCPClientInterface` from the accepted socket
  (`TCPInterface.py:591`), so `type` now says that.

- `HDLC.FrameDecoder.reset()` — drops a partially-received frame, so a half-decoded frame
  cannot be prepended to the first bytes of a reconnected session.

## [1.6.0] — The `rn*` command-line utilities

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
- **A short option's value may be attached to it.** `argparse` accepts `-s16` as `-s 16`,
  and accepts it at the end of a bundle (`-vvs16` is verbose twice plus size 16). The
  in-package parser only understood bundles of pure flags, so every attached value was
  rejected as an unrecognised argument, exit 2 — across `rnprobe -s`/`-n`, `rnpath -m`/`-w`,
  `rncp -b`, `rnx -w` and `rnstatus -w`. A cluster now resolves left to right and the first
  value-taking option in it claims the remainder of the token, which is `argparse`'s rule.
- **`--help` and `--version` are reached by abbreviation.** `rnprobe` scans `argv` for those
  two before parsing, to reproduce `argparse` firing their actions the moment it reaches
  them. The scan compared exact tokens, so `--hel` and `--vers` — both unambiguous, both
  expanded by `allow_abbrev` — fell through to the ordinary parse and took a different code
  path entirely, printing the help page in place of the version.
- **`rnsd --exampleconfig` was 25 lines short of Python's.** RNS 1.4.1 added
  `default_gravity`, `autoconnect_interface_mode`, `autoconnect_announces_to_internal` and
  `autoconnect_interface_gravity` to `__example_rns_config__`. This blob is a document users
  copy verbatim, so it is compared byte for byte and is identical again (15663 bytes).
- **`interface_stats` was missing RNS 1.4.1's `gravity` and `announces_to_internal`.** Both
  are appended after `mode`, exactly where Python emits them: `rnstatus -j` serialises the
  dictionary in insertion order, so position is part of the contract, and Python's own
  `rnstatus` sorts interfaces by `gravity` when the key is present.

### RNS 1.4.2

Audited, no port required — `rnsProtocolVersion` moves to `1.4.2` on that basis rather than
on a changeset. The release is three core diffs against 1.4.1 plus `rnsh`, which is not
ported:

- `Transport.py:3126` began skipping offline interfaces when fanning a recursive path
  request out. Every fan-out loop here already filtered on `isOnline`, so the port was
  ahead of Python rather than behind. Now pinned by a test.
- `Transport.py:1841` moved a gravity-replacement log line from `LOG_DEBUG` to
  `LOG_PATHING`. This port does not emit that line.
- `Discovery.py` began caching the blackholed identity set for 60 s inside
  `list_discovered_interfaces`. Python pays an RPC round-trip to the shared instance per
  `is_blackholed` call; here it is a dictionary lookup under a lock, so the cache would buy
  nothing and would delay a fresh blackhole by up to a minute. Deliberately not adopted,
  and a test now pins the immediacy that decision preserves.

### Known divergences

- **Failure exit codes reach the shell here and do not in Python.** Once a Python utility
  has started a stack, the code it asks for is discarded and the process exits 0. The cause
  is `Reticulum.exit_handler`, registered with `atexit` (`Reticulum.py:369`): isolated by
  unregistering it, after which the very same `sys.exit(2)` exits 2. It applies to every
  post-stack exit in every tool — `rnstatus`'s `exit(2)` on "Could not get RNS status",
  `rnpath`'s `exit(1)` and `exit(20)` — so `rnstatus; echo $?` reports success when the
  status was never fetched. Matching that would mean no Swift utility could signal failure
  to a script either, so the codes each tool's own source asks for are used instead.
  `argparse` errors agree exactly (exit 2), because those are raised before the stack
  starts.
- **`--version` reports this port's release**, not the RNS protocol version it is
  wire-compatible with. All nine tools answer identically.
- **`rnprobe`'s spinner is gated on a TTY**, where Python writes backspaces and raw glyphs
  unconditionally and makes redirected output unusable for scripting.
- **A Swift shared instance does not enumerate a per-client interface entry.** Python
  creates a `LocalClientInterface` object per connected client, which appears in `rnstatus`
  output; Swift's server handles clients internally, so `rnstatus` against a Swift daemon
  lists fewer interfaces. The client count itself is reported correctly.

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
