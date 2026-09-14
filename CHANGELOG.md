# Changelog

All notable changes to ReticulumSwift are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Reading a repository for a page

`RNGitRepositoryReader` runs `git` and answers what a page needs from it: what the repository
says it is, its branches and tags with the subject and any tag message each points at, the object
a ref names, what a directory holds, what is known about a file, what that file holds, the
readme under whichever of eleven names it carries one, how many commits a ref has behind it, a
page of those commits, everything a commit page prints, and what a commit's signature says.

A signature is read as the signature it is: the envelope's namespace is not asked about, so one
made for something other than `git` still reaches a verdict. The verdicts are the eight the
reference reaches, down to their wording.

`RNGitCommandRunner` gained a second call that answers bytes rather than text, because a file is
binary when its first 8 KiB carry a zero byte, and a run that could not start and a run whose
output is not text are not the same answer.

A repository's description is read from its configuration, and from the file beside the
repository rather than inside it where the configuration carries none.

`get_blob_stream` and `get_webp_stream` are not part of this: both hand back an open handle whose
lifetime belongs to the link that asked, which is the page server's to own.

### What a page is made of

The micron a page is built out of, as pieces that join: headings, bold, italics, underlines,
foreground colour, dividers, alignment, escaping, and the three link forms—one bold, one drawn as
body text, and one naming another node. A link's fields are carried in the order they are given
and written the way a query string writes them, a space as `+` and everything else outside
letters, digits and `_.-~` as `%XX`, because a link is compared by the text it reads as.

The paths of the seventeen things a node serves, the limits it serves them under—256 KiB before a
file is offered as a download rather than rendered, 1,000 directory entries and 100 commits to a
page, 8 seconds for one `git` call, 100 columns wide, a tab drawn as three spaces—the colours a
page and a chart draw with, and the ten icons in both the Nerd Font and the plain Unicode
tables.

Sizes, absolute and relative timestamps, tab expansion, and the colouring of a diff and of a
commit message.

### Converting an image for a reader

`RNGitMediaEncoder` converts an image to WebP through whichever of `magick`, `convert`, `gm`,
`ffmpeg` and `avconv` stands on the search path, in that order. `RNGIT_MEDIA_BACKEND` names one
and makes it the only one tried. Otherwise the backend that last converted something is tried
before the rest. A quality outside one to a hundred is brought inside it, a size below one pixel
is not asked for, and each family takes its options at the one place the rest of its words still
read the same way afterwards.

A conversion is given 8 seconds. What is left at the output path is a WebP file or nothing: a run
that timed out, failed, could not start, or wrote something whose header does not read as WebP
has its output taken away. The header is read from all three chunk kinds, each of which carries
the size in a different place and to a different width.

A machine carrying none of the five backends is told so once rather than on every conversion.

No WebP encoding backend stands on the machine this was recorded on: the only one of the five on
the search path is `ffmpeg`, and this build of it carries no WebP encoder. The conversion command
lines are pinned by 175 recorded rows and the outcome handling by a scripted converter, so a
conversion through a real encoder is pinned rather than run.

Behavior is pinned by 62 readings of a deterministic repository, 85 micron and formatter rows,
both icon tables and the class constants, and the 175 conversion command lines, all recorded from
Python RNS 1.5.4. An 82-mutant sweep leaves four survivors, each of which is the same program:
the `git diff --numstat --no-index` fallback cannot report a revision as binary, because `git`
cannot reach a revision as a path; zeroing a `-` before reading it as a number changes nothing,
because a number that will not read falls back to zero anyway; dropping the one space a
signature's continuation line carries changes nothing, because the armour reader trims every line
it takes; and `git ls-tree <ref>:` lists the tree `git ls-tree <ref>` lists. 4,109 tests, 0
failures.

### The `rngit` executable

A twelfth executable product, and the node behind it. `rngit node` brings a repository node up
out of what stands in its configuration directory and serves repositories on a destination the
node's own identity names; every other subcommand asks a node to do one thing and stops.

A node keeps four files: the log `server_log`, the configuration `config`, the identity
`repositories_identity` and the statistics `stats`. It reads `/etc/rngit` before anything under
the user's home, so one machine can serve repositories for everyone on it, and keeps its files
under `~/.rngit/reticulum` where a client's own configuration stands at `~/.config/rngit/config`.
A directory holding no configuration is given the shipped one, and one holding no identity is
given a new one.

Eleven request paths are served on an inbound single destination, each to any peer, with every
handler settling for itself what the peer that asked may do. The node holds the one store, the
one set of statistics and the one set of temporary directories the handlers read and write, so
what a handler changed is read back before its answer goes out. A peer is held from the moment it
identifies until its link is no longer up, and the directories made for a link go with it.

Between requests the node wakes every 5 seconds and runs what has come due: announcing itself on
the configured interval, writing its statistics out every 180 seconds, bringing mirrors up to
their upstreams every 900 seconds, and sweeping links every 5 seconds. A mirror whose interval
has not passed is left where it is, and a repository that mirrors nothing is never reached for.

`rngit node --print-identity` prints the peer identity, the node identity, the repositories
destination and, where the node serves pages, the Nomad Network destination, and stops without
bringing the stack up. A node that cannot be brought up far enough to say what it is stops the
run with 255, as a node that cannot be brought up at all does.

The page server a node can run alongside its repositories is not part of this; the
`serve_nomadnet` setting is read and carried, and the destination it names is printed, but
nothing serves on it yet.

### Exit statuses `rngit` stops on

A run that gives up part way now stops with 1 rather than 255. `rngit` and `git-remote-rns` stop
on different statuses, and the helper's had been carried across to both; the helper keeps its
255. A client configuration that will not parse stops the run with 255, where it had stopped
with 1.

A sync request is written to the node's log as an upstream sync, which is what it is.

Behavior is pinned by the eleven recorded request-handler registrations and the 26-row task
dispatch, both recorded from Python RNS 1.5.4, and by the shipped configuration file's text. An
80-mutant sweep leaves two survivors, both inside the handlers registered on the destination, and
both needing a link a peer has identified over to tell apart. 4,046 tests, 0 failures.

### The `git-remote-rns` executable

An eleventh executable product. Git runs it for an `rns://` remote, handing it the remote's name
and the URL, and it takes `RNGIT_CONFIG` and `RNS_CONFIG` from its environment. It reads its own
configuration, brings Reticulum up with its log written to a file rather than the stream git is
reading, opens a link to the node the URL names, and answers git over that link.

A run that cannot bring itself up exits 1: two words git did not give, a URL under another
scheme, a URL naming no repository, or a configuration file that will not parse. A run that gives
up part way writes `git-remote-rns failed: <reason>` where its failures go and exits 255.

### Where a client keeps its files

A client keeps three files under `~/.rngit`: the log `client_log`, the configuration
`client_config` and the identity `client_identity`. They stand under `~/.rngit/reticulum`
instead where a node's own configuration stands at `~/.config/rngit/config`, so the two do not
share a directory. A directory named on the command line or in the environment is taken as it
stands. The client
writes the default configuration where it finds none, and generates an identity where it finds
none, keeping it for the next run.

### A client reaches a node over a link

`RNGitLinkTransport` carries a request to a node, and is the first type to do so outside the
test stubs. It waits for a path for the longer of 15 seconds and the slowest interface's own
timeout, recalls the node's identity, opens a link, identifies over it, and waits for the link
for the longer of 15 seconds and the link's own establishment timeout. A response carrying
metadata is a file, and its bytes are written under a directory the run makes and removes, so
they outlive the request; a response carrying none is bytes.

### The `rngit` argument surface

Eight subcommands, `node`, `release`, `perms`, `work`, `create`, `fork`, `sync` and `mirror`,
each carrying its own options, positionals, usage block and help text. A first word naming none of
them leaves the run on `node`, which refuses it as an unrecognized argument. The `rngit`
executable itself waits on the node runtime; what lands here is the reading, as library types.

Behavior is pinned by 71 `rngit` command lines, 13 `git-remote-rns` command lines, 7
configuration-directory resolutions and the default configuration file's text, all recorded from
Python RNS 1.5.4. A 74-mutant sweep leaves five survivors: four inside the one function that
needs a live link behind it, and the line that joins the two tested halves of the run once the
stack is up. 3,991 tests, 0 failures.

### `git-remote-rns`

The remote helper git runs for an `rns://` remote, ported from
`RNS/Utilities/rngit/client.py`. It reads git's commands on standard input and answers on
standard output: `capabilities` names what it supports, `list` reads the node's refs, `fetch`
asks the node for a bundle carrying the objects a ref needs and hands it to `git bundle
unbundle`, and `push` builds a bundle of what the node does not hold and sends it. A batch ends
at a blank line, and `fetch` and `push` clear each other's queue, so one batch carries only one
of the two.

A URL names a destination, a group and a repository as `rns://<hash>/<group>/<repo>`, where the
destination may be a name the configuration file aliases. Everything past the group is the
repository, so a repository name may carry slashes.

A push whose ref reaches nothing the node lacks builds no bundle, and the helper asks the node
to move the ref instead. A push git cannot be told about any other way is answered with `error
<ref> "<reason>"`, quoted the way git reads a quoted string: every scalar outside printable
ASCII is written as its hexadecimal.

The link comes down when git stops sending commands, and when the helper stops on a failure it
reports. A command carrying fewer words than the command it names leaves the link standing,
which is what the reference does.

The helper reads `ref_batch_size` out of the `[client]` section of its configuration file. An
`rngit` client reads the same file and passes that section over, so the two read it through
separate types.

Behavior is pinned by 96 runs, 20 URLs, 13 configurations, and 17 quoted values recorded from
Python RNS 1.5.4. An 84-mutant sweep over the helper leaves two survivors, neither of which can
change what the helper writes: `fetch` and `push` swapped where a batch ends, which is a no-op
because each clears the other's queue, and a strip applied a second time. 3,970 tests, 0
failures.

### The `rngit` client keeps work documents

The work-document commands are the client half of a repository's proposal and review flow,
ported from `RNS/Utilities/rngit/server.py`. `list` and `view` read what a repository holds;
`create`, `propose`, `edit`, `comment` and `permissions` hand the operator an editor and send
back what they wrote; `delete` asks the operator to confirm, and `complete` and `activate`
move a document between scopes. Each opens a link, sends one request on the node's
`/mgmt/work` path, and tears the link down on the way out. The client signs a document the
operator writes, and `view` validates that signature over the document's content and prints
the signer's hash in place of the author the node claims.

Where a node answers with a value that cannot stand where it sent it—a listing that is no map,
a title that is no text, content that is no text under a signature—the client refuses the
answer and closes the link. Python RNS 1.5.4 reads those answers without checking them and
raises out of the interpreter, so the text it prints names CPython's own types and is no
contract. What is pinned here is the refusal.

Behavior is pinned by 323 runs recorded from Python RNS 1.5.4, and eight malformed answers
recorded alongside them. A 33-mutant sweep over the commands leaves no survivors; three of the
runs were recorded to close what it found. 3,963 tests, 0 failures.

### The `rngit` client fetches a release

`fetch-release` is the client half of a release download, ported from
`RNS/Utilities/rngit/server.py`. It reads the release manifest, resolves the origin the
manifest names, asks the node for each artifact the target selects, and validates what
arrives against the manifest's hashes. A manifest already on disk is read rather than
fetched, which is what an offline verification runs on.

Artifact selection is `fnmatch`, ported as `FileNameMatching`: a pattern matches a whole
name, `*` stands for any run of characters, `?` for one, and `[abc]` for one of the
characters a set holds, which `[!abc]` turns around. Consecutive `*` collapse into one and a
reversed range such as `[c-a]` matches nothing, as they do in CPython's `fnmatch.translate`.

A request that carries a resource reports its progress as it arrives, rendered the way the
reference renders it, so `RNGitClientTransport.request` now takes a progress callback and
answers with the node's metadata alongside the result.

Behavior is pinned by 66 runs recorded from Python RNS 1.5.4 and 2,028 name-and-pattern pairs
recorded from CPython's own `fnmatch`. 3,961 tests, 0 failures.

### The storage-inventory guard reads paths built by concatenation

`StorageInventoryTests` holds the claim that every persisted path is declared in
`StorageInventory` rather than composed at a call site. Its scan matched one form,
`appendingPathComponent("literal")`, so a path built as `base + "/name"` was invisible to it.
No file under `Utilities/RNGit` calls `appendingPathComponent` with a literal at all, so the
whole subsystem passed a guard that never looked at it.

The scan now reads both forms. Thirty-three sites across the `rngit` node surface, and the two
`<root>/rngit-<uuid>` scratch directories, are outside a Reticulum configuration directory—an
`rngit` repository group is wherever the node configuration's `repositories` section puts it
(`server.py:2246`)—so they are exempted by name, in two sets stating why, alongside the
existing exemption for the components that find the configuration directory itself.

### The `rngit` node: eleven request handlers, its permission model, and its stores

`rngit` serves git repositories over Reticulum. The node half of it is now ported from
`RNS/Utilities/rngit/server.py`, as the library types a node is built from.

Every request path the reference registers is answered: `/git/list`, `/git/fetch`,
`/git/push`, `/git/create`, `/git/fork`, `/git/mirror`, `/git/sync`, `/git/delete`,
`/mgmt/release`, `/mgmt/work` and `/mgmt/perms`. `RNGitCloneHandler` answers the fork and
mirror paths, which the reference routes into one routine, and it is the only handler that
reads the link a request arrived over, because it builds the repository in a directory
belonging to that link.

`RNGitAccessControl` is the permission model: nine permissions over three targets, resolved
at repository level with a fallback to the group, and separately at group level, where the
blocklist does not apply. `RNGitPermissionSet` reads the `allowed` file beside a group or a
repository, which may be a program the node runs rather than a file it reads.

Four stores carry what the handlers read and write: `RNGitRepositoryStore` for the groups
and repositories, `RNGitWorkStore` for the work documents, `RNGitReleaseStore` for the
releases, and `RNGitStatsStore` for the counts a node keeps. `RNGitConfigFile` parses the
node configuration and `RNGitNodeSettings` reads every section of it.

The page-rendering primitives a node serves Nomad Network with are here as well:
`GitReferenceNames`, `DisplayWidth`, `MarkdownToMicron` and `SyntaxHighlighter`.

Behaviour is pinned by vectors recorded from Python RNS 1.5.4, run against the reference's
own routines rather than written by hand. 3,937 tests, 0 failures.

The `rngit` command line and `git-remote-rns` are not here yet, so
`Reticulum.rnsProtocolVersion` stays at 1.5.2.

### Request handlers can answer with a file, and responses carry metadata

RNS 0.9.6 (`594f5fba`) let a response generator return `(file_handle, metadata)`: the file is
sent as a resource whose payload is its raw bytes, the metadata rides in the resource's
metadata block, and the requester reads it off `RequestReceipt.metadata`
(`Link.py:836-846`, `902-903`, `1437-1441`). None of it was ported. `rngit` serves a git
bundle this way, with the fetch result code in the metadata
(`Utilities/rngit/server.py:3001`), so the whole fetch path depended on it.

`Destination.registerResponseGenerator` registers a handler returning
`Destination.RequestResponse`, either a `.value` or a `.file`. A file response is streamed
from disk one segment at a time rather than read whole into memory, matching the reference's
per-segment seek (`Resource.py:307-322`). On the receiving side a resource that carries
metadata is delivered as a file response: its payload has no `[request_id, response]`
envelope, because the request ID rode in the advertisement.

`auto_compress` is polymorphic in the reference—a flag, or an integer byte ceiling
(`Resource.py:372-376`)—and is now `Resource.AutoCompress` here, accepting both literal forms.

### A resource's advertised size counts its metadata

The reference advertises `total_size = data_size + metadata_size` (`Resource.py:297`) and
gives segment 1 that much less room for data
(`first_read_size = MAX_EFFICIENT_SIZE - metadata_size`, `Resource.py:311`). This port counted
neither: a resource carrying metadata advertised a short size and split on boundaries the
reference does not use. Both ends of a Swift-to-Swift transfer agreed on the same wrong
boundaries, so it round-tripped and the divergence stayed invisible.

`data_size` is also the whole resource's size on every segment of a split transfer, not the
segment's own share, and the metadata flag stays set on segments 2 and later through
`sent_metadata_size` (`Resource.py:259-272`, `791-792`).

`rncp` reports the advertised size, so a transfer now prints the same total the Python tool
prints (`rncp.py:582`).

### A tenth utility: `rngcs` signs git commits with a Reticulum identity

`rngit` serves git repositories over Reticulum, and `rngcs` is the piece git itself runs.
Named in `gpg.ssh.program`, it lets git sign a commit against a Reticulum identity rather
than an SSH key (`Utilities/rngit/commitsigs.py`). All four operations git invokes are
present: `sign`, `verify`, `find-principals` and `check-novalidate`.

The signature is an `rsg`—the format `rnid` already produces—carried in the `signature` field
of an ordinary `SSHSIG` envelope, so git stores and hands back a blob it understands while the
trust decision stays Reticulum's. `SSHSignature` builds and reads that envelope;
`GitCommitSignature` is the four operations over it.

Validity alone does not make a commit signed: the author field has to be the signer's identity
hash, or on a tag the tagger field, which is the convention `rngit` repositories are built on
(`commitsigs.py:288-290`). A commit signed by someone other than its author is refused.

Verified against the reference in both directions. A commit the Python `rngcs` signs verifies
here and reports the same signer, one signed here verifies there, and the signed envelope is
byte-identical across the two—only the Ed25519 signature differs, because CryptoKit randomises
where the reference does not. A signature captured from Python 1.5.4 is pinned in the suite.

### A failed RNode bring-up redials instead of parking the interface

RNS 1.5.3 hardened the BLE arm of the RNode bring-up: a detect timeout now forces the link
down so the next attempt connects afresh instead of reusing a wedged one
(`RNodeInterface.py:446-450`).

The reference reaches its retry loop by closing the port, which ends the read loop and lands
in `reconnect_port`—a 5 s ladder that re-runs the whole `configure_device` gate
(`:1172-1187`). Every failed exit from a bring-up takes that path: no detect answer, a radio
that cannot be configured, echoed parameters that do not match the configuration. This port
closed the transport on all three and returned, leaving the interface offline until something
called `start()` again, so an RNode that was slow to boot never joined at all.

Both `RNodeInterface` and `RNodeMultiInterface` now redial on those exits, on the same ladder
device loss already used, and `stop()` ends it—the reference gates its retry on `detached` for
the same reason. `RNodeTransport.close()` is documented as releasing the device: a conformer
that only pauses delivery hands the next attempt the same dead link.

### RNS 1.5.4 audit

The rest of the release is already present or does not apply:

- `HDLC.frame()` and its use in `BackboneClientInterface` / `LocalClientInterface`: this port
  has framed through `HDLC.frame` since it had those interfaces.
- `Packet.py:305-310`, suppressing an outbound-failure log when the packet named an
  interface: this port logs nothing on that path.
- `Link.get_expected_rate`'s docstring typo: never carried here.
- `_get_windows_paired_ble_addresses`, which is WinRT and has no Apple-platform
  equivalent.

`Reticulum.rnsProtocolVersion` stays at 1.5.2 until the rest of `rngit` lands, which is the
remainder of 1.5.3.

## [1.20.0]—Interface discovery publishes, and path requests batch

The two areas 1.19.0 listed as outstanding are now ported. Nothing in the wire protocol
changes for a node that leaves both switched off.

### Publishing

Interface discovery has had a complete receive side since RNS 1.4.0: this port parsed a
neighbour's announcement, validated its stamp, and rendered it. It had no publish side. A
config carrying `discoverable = yes` moved from a Python node to a Swift one produced a
stack that read every key and announced nothing, and the interface it described stayed
invisible to every peer looking for it.

`InterfaceAnnouncer` closes that. It announces `rnstransport.discovery.interface` once per
`discovery_announce_interval`, choosing the interface that has waited longest, and emits
msgpack in upstream's field order so a Python peer decodes it field for field. The
`discoverable` block now parses in full: `discovery_name`, `discovery_stamp_value`,
`discovery_encrypt`, `reachable_on`, `publish_ifac`, `location_cmd`, `latitude`,
`longitude`, `height`, `discovery_lxmf_address`, and the three RNode radio keys. An
announcing interface has to route for the peers that find it, so a mode that doesn't
gets corrected the way `Reticulum.py:927-934` corrects it.

Announcing costs a proof-of-work stamp, and generating one belongs to LXMF, which this
package can't depend on. `Configuration.discoveryStampGenerator` inverts that: a host
supplies the generator, and a stack configured as discoverable without one logs an error
and announces nothing rather than putting an unstamped announcement on the wire.

The autoconnect half dials what it hears. It connects discovered Backbone and TCP server
endpoints under `Reticulum.maxAutoconnectedInterfaces`, skips `.onion` addresses,
Yggdrasil `200::/7` addresses and the two invalid IP literals, monitors what it dialed,
tears down an endpoint that stays down past the threshold, and re-enables the bootstrap
interfaces when nothing it dialed survives.

### A receive-side defect

`sanitizeName` built its allowed set from two ASCII ranges where upstream's `san_map` uses
three (`Discovery.py:898-901`), dropping lowercase. Every ordinary name truncated to its
first character: a neighbour announcing `Example hub` arrived as `E`. The test covering
this came from the implementation rather than the reference, so it asserted the
truncation.

### Batching

A transport node that can't answer a path request from its own tables amplifies it: one
inbound request becomes one outbound request per other interface. `inflight_path_requests`
marks a destination as already under search, so requests arriving during that search join
it, and `discovery_path_requests` records who joined so the announce that resolves the
search replays to each of them as a path response. Both halves land together: batching
alone would drop those duplicates with nothing to answer them.

`Transport.pathRequestGateTimeout`, ported in 1.19.0, gets its first consumer here.

### Breaking

`InterfaceAnnouncer` is now the interface-discovery announcer. The unrelated type that
held the name—a periodic announcer for a single destination, which nothing in this package
or its dependents constructed—is now `DestinationAnnouncer`.

## [1.19.0]—reference parity moves to RNS 1.5.2

`Reticulum.rnsProtocolVersion` names the Python RNS release whose wire protocol and
behavior this port matches. It has read `1.4.2` since that audit. It now reads `1.5.2`.

The transport half of 1.5.0 through 1.5.2 landed over the preceding releases: packet
validation and hop limits, the inclusive `optimise_mtu` ladder, the announce and
path-request burst detectors with their trailing-edge hold and cooldown, ingress-limited
path requests, and `medium_path_timeout` flooring every utility's path deadline. What held
the constant back was observability, not transport. Python 1.5.2's `rnstatus` subscripts
`ifstat["txdrp"]` with no presence check, so a daemon that omits the key makes the
operator's own tool raise `KeyError` instead of printing a listing.

### The gate

`tri-test`'s `make test-utilities` runs Python 1.5.2's `rn*` utilities against this port's
daemon, and this port's utilities against a Python daemon: 136 passed, 1 xfailed.
`test_json_payload_shape_is_identical` compares `rnstatus -j` key by key in order, so the
payload matches the reference field for field, not only in the fields some renderer happens
to read.

### Keys this port emits

Of upstream's 77 per-interface `ifstats` keys this port emits 73, and adds none of its own.
All 28 top-level keys are present. Four omissions are deliberate:

- `interference_last_ts` and `interference_last_dbm` are dead upstream. Upstream comments
  out every writer (`RNodeInterface.py:957-966`), and the guard tests `type(...) == list`
  against an attribute that starts as `None`, so a Python daemon never emits them either.
- `blocked_ips` and `blocked_ip_list` are `BackboneInterface` server-side state. This
  port's Backbone is client-only and holds nothing to report. `RNStatusRenderer` still
  renders both when a Python daemon supplies them.

`rnstatus.py` guards all four with `if "key" in ifstat`, so their absence costs a display
line rather than the listing.

### Still outstanding

Interface-discovery *publishing* stays unimplemented (`publishesInterfaceDiscovery` reads
`false`). The receive side is complete. `discovery_path_requests` batching needs an
announce handler that replays to `requesting_interfaces`. Three areas stay unported on
purpose because the seam differs, and a test pins each one: traffic classes, `ifac_handled`,
and the adaptive dataplane controls.

## [1.18.0]—the conditional half of the interface stats payload

`get_interface_stats` publishes two kinds of key: the ones every interface has, and the
ones it reaches through `hasattr(interface, …)` because only some types carry them
(`Reticulum.py:1409-1526`). This port covered the first kind. This release covers the
second, and corrects two places where a key this port already emitted did not match what a
Python daemon puts in the same field.

`Reticulum.rnsProtocolVersion` stays at 1.4.2. None of this is a 1.5.x delta; these are
divergences that reading 1.5.2's stats surface brought to light.

### Interfaces that keep peers report how many

`rnstatus` prints a peer count as `N reachable`, and also falls back to it for the client
column when an interface reports no clients (`rnstatus.py:555, 617, 642`). Upstream
publishes it for the two interface types that keep a peer table, `AutoInterface` and
`WeaveInterface` (`Reticulum.py:1501-1503`). This port published neither, so a Swift daemon
with a busy AutoInterface described it to a Python operator as having no peers and no
clients.

### A spawned interface names the interface that spawned it

Clients of one server share a display name by design, so the parent is the only thing in
the listing that says which server, radio, or tunnel each row belongs to. Upstream reaches
it through `hasattr(interface, "parent_interface")` and publishes the name and hash
(`:1412-1414`).

Duck typing makes that uniform for free in Python. Here it needs a declaration, so this
release adds a `SpawnedInterface` protocol and conforms the four types that hold a parent:
`TCPServerClientInterface`, `I2PInterfacePeer`, `RNodeSubInterface` and
`WeaveInterfacePeer`. The payload makes one cast against the protocol rather than one cast
per type, so the set of interfaces that publish a parent is the set that declares one. A
test enumerates the conformers from the type system and pins the set, which is what keeps a
fifth spawned type from reaching the payload silently parentless.

### A radio reports its temperature, and a Weave switch its load

`cpu_temp` rides on RNode interfaces and reads null until the radio first reports
(`RNodeInterface.py:237, 1067`). `cpu_load` and `mem_load` ride on Weave interfaces and
read 0 until the switch does, because upstream initialises both device attributes to 0 and
assigns the device unconditionally during `final_init` (`WeaveInterface.py:584-588, 883`).
Publishing null in that state would have made this port's listing disagree with a Python
daemon describing the same silent switch.

`mem_load` is a percentage rounded to two decimals, mirroring
`round((memory_used/memory_total)*100, 2)` (`:763`). A switch reporting a zero total
divides by zero upstream, so this port guards it: the field reads 0 rather than reaching
`rnstatus` as a printed NaN.

### Two Weave identifiers move to the interface that owns them

`switch_id` and `endpoint_id` are properties of `WeaveInterface` (`:838-845`);
`via_switch_id` is an attribute only `WeaveInterfacePeer` declares (`:1014`). This port
published all three from the peer. That described each peer as the switch and left the
interface actually attached to that switch reporting nothing, which is the row an operator
reads the switch identity from (`rnstatus.py:543-553`).

Each identifier also now goes through `RNSUtilities.hexrep`, matching `RNS.hexrep`, whose
`delimit` argument defaults to true (`__init__.py:168-174`). An operator sees
`de:ad:be:ef` on both implementations instead of plain hex on one.

### Four keys stay unemitted

`interference_last_ts` and `interference_last_dbm` come from `r_interference_l`, which
upstream initialises to `None` and never assigns—every write is commented out
(`RNodeInterface.py:281, 957-966`). The guard is `type(...) == list`, so upstream's own keys
never appear either. Emitting them would put this port ahead of the reference for a field
with no settled meaning.

`blocked_ips` and `blocked_ip_list` come from `BackboneInterface.blocked_ip_count`, which
lives on upstream's server side. This port's Backbone support is client-only, so there is
no ingress blocking to report. `RNStatusRenderer` already renders both keys when a Python
daemon supplies them, which is the half that matters here.

Tests pin all four as absent, so a later change that starts emitting one has to say why.

## [1.17.0]—the rest of the protocol-violation sites, and three upstream never reaches

1.16.0 landed the announce violation. This release finishes the survey of the other six
sites in `Transport.py`: three land here, and three stay out with the reason recorded.
Reading them also turned up a counter that isn't about violations at all: this port
counted path requests on arrival rather than when the node acted on one.

`Reticulum.rnsProtocolVersion` stays at 1.4.2. As in 1.16.0, none of this is a 1.5.x
delta. These are pre-existing divergences that reading 1.5.2's transport surfaced.

### A tagless path request counts a violation

A path request carries a destination hash and a tag, and the tag is what distinguishes one
request from a replay of itself. Without it, nothing can deduplicate a request, so upstream
refuses to act on it and charges the sender
`protocol_violation("Tagless path request")` (`Transport.py:1838-1840`). This port dropped
the frame silently.

The two lengths on either side of that boundary are one byte apart and upstream treats
them differently: a body too short to hold a destination hash returns earlier and costs
nothing (`:1830`). Both boundaries now have a test.

### An oversized path request tag counts a violation

Upstream truncates a tag longer than the hash length and counts
`protocol_violation("Excessive path request tag size")` (`:1843-1845`). This port
truncated and said nothing. The truncation is the part that matters for correctness—keyed
on untruncated bytes, a sender defeats deduplication for free by varying a tail nothing
reads—and this port already did it. The counter is the only trace a peer trying leaves behind.

### The path-request counter counts requests this node acted on

`received_path_request(size=…)` sits below the length guard, both tag checks, and the
duplicate check (`:1857`). This port called it on the opening line of the handler, so the
path-request columns described path-request-shaped frames that arrived. On any interface
seeing replays that's a different number: a request repeated ten times moved the counter
ten times and provoked one lookup. Same shape as the announce counter in 1.16.0, same fix.

### A transport node no longer relays link traffic before validation

A link-table entry appears when a transport node relays a link request, and becomes
validated only once that node verifies the responder's proof. Upstream refuses to carry
traffic before that and counts
`protocol_violation("Link packet received before link validation")`
(`Transport.py:2124-2128`). This port had no such gate: it relayed on any route it held.

Anyone can create the half-open entry, because pushing a link request through a transport
node takes no credential. A node that then carries traffic on the resulting route forwards
packets for a link that may never complete.

Upstream's condition exempts ANNOUNCE, LINKREQUEST and link-request proofs (`:2122`), and
only the proof reaches this path. A test pins the exemption.

Adding the gate also exposed an ordering assumption worth recording. This port marked a
route validated on the line after it relayed the proof, matching upstream's line order.
Upstream can afford that order because its transmit leaves through a socket, so the
initiator's answer arrives on a later pass. An in-process interface calls straight through:
the initiator receives the proof and answers with a link RTT packet *inside* the forward,
and that reply reached the new gate before the flag landed. Five relayed-link test
classes broke. The flag now goes up before the transmit—the verification it records has happened
either way, since the signature check precedes both.

### Three upstream counters stay unported

Each of these is reachable in upstream only through behaviour this port doesn't share, so
porting the counter would charge peers for frames that are fine.

* **Undecodable path MTU** (`:2086`, `:2563`). Upstream reaches these through
  `min()` raising on a `None`, which happens because it hands the raw field around before
  decoding it. This port decodes at the boundary and has no such value to trip over. The
  violation would only ever fire on a peer that had done nothing wrong.
* **Announce without a random blob** (`:2218`). Unreachable: anything arriving here has
  already passed a signature gate that requires at least 148 bytes, which is more than
  enough to contain the blob.
* **Invalid tunnel synthesis packet** (`:2808-2810`). Fires from the handler's `except`,
  and once the frame length matches nothing inside can raise. `load_public_key` swallows
  its own exception, and neither X25519 nor Ed25519 rejects a 32-byte value at
  construction—Ed25519 defers point decoding to verification time. CryptoKit agrees, so
  degenerate key bytes load, fail verification, and go unremarked on both sides. A test
  pins that silence.

## [1.16.0]—announce admission runs in upstream's order

The announce counter, the blackhole list and the protocol-violation counter all hang off
one gate in Python (`Transport.py:1806-1811`). This port ran the three checks in three
different places, in a different order, and dropped one of them entirely.

`Reticulum.rnsProtocolVersion` stays at 1.4.2. Nothing here is a 1.5.x delta—these are
pre-existing divergences that reading 1.5.2's transport surfaced.

### An unverifiable announce is now a protocol violation

Upstream answers a bad announce signature with
`protocol_violation("Invalid announce signature for …")` (`Transport.py:1809`). This port
caught the validation error and returned, so a peer putting forgeries on the wire looked
exactly like a quiet peer. The operator's only signal was an absence of traffic.

### The announce counter counts announces the node accepted

`received_announce(size=…)` sits below the signature gate (`Transport.py:1811`). This port
called it at the top of `handleAnnounce`, before any validation ran, so the announce
columns described announce-shaped frames that arrived rather than announces the node took.
A blackholed peer and a peer sending garbage both still moved the counter.

### The blackhole test runs before the signature check

Python tests the blackhole list inside `validate_announce`, after the public key loads and
before it checks the signature (`Identity.py:551-556`). This port tested it much later,
past the deduplication cache. Two consequences, both now gone:

* A blackholed announce still cost a full signature verification.
* A blackholed announce that also failed to verify would have cost that peer a protocol
  violation once the counter landed. A blackholed peer isn't misbehaving on the wire, and
  upstream charges it nothing.

Moving the test ahead of the cache also narrows a divergence this port had documented and left
alone: a blackholed announce no longer leaves a cache entry for a later copy to collide
with. The ingress-burst and announce-rate filters still sit below the cache, so that note
now covers those two only.

### A single announce parser

`Identity.validateAnnounce`'s signature-only path carried its own copy of the announce
layout, separate from `Announce.validate`'s, and the two had drifted. The copy read a
ratchet only when the body was long enough to hold one, and it never checked that the
packet was an announce at all, so a DATA packet whose payload happened to be a well-formed
announce body validated as an announce.

Both now read the wire through `Announce.parse`, which mirrors the parse at the top of
Python's `validate_announce` (`Identity.py:510-548`). That function was dead code until
this release—the transport had never called it—which is how the drift went unnoticed.

### A single signature verification per announce

Splitting the admission gate off from the full validation puts two Ed25519
verifications on the path an announce takes. Upstream avoids the second with the
`packet.announce_signature_validated` flag (`Identity.py:559-560`), which the full
validation reads instead of re-verifying. This port carries the mark as an argument
on an internal overload of `Announce.validate` rather than a field on `Packet`, so
no caller outside the module can ask to skip a signature check.

The skip scopes to the signature alone. The destination hash still has to match
`truncated_hash(name_hash || identity_hash)`, because a signature is valid over
whatever destination hash the signer chose and says nothing about which hash the
announce should carry.

### Blackhole reporting reaches the API

`Identity.validateAnnounce(_:onlyValidateSignature:isBlackholed:)` returns
`AnnounceAdmission`—`.valid`, `.invalid` or `.blackholed`—mirroring the `"blackholed"`
string upstream returns under `signal_blackholed=True` (`Identity.py:555`). Python reads a
global blackhole list at that point. This port has a per-instance transport, so the caller
passes the test in. The existing `Bool`-returning overload keeps its behaviour and reports
a blackholed announcer as a plain failure, matching upstream without the flag.

## [1.15.0]—the `packet_filter` surface matches upstream again

Found while reading `Transport.py` for the protocol-violation counters: the packet filter
itself had drifted from the Python function it mirrors, in four places, none of them
visible from outside.

`Reticulum.rnsProtocolVersion` stays at 1.4.2. Nothing here is a 1.5.x delta—these are
pre-existing divergences the 1.5.2 read surfaced.

### Six contexts no longer deduplicate

Upstream answers `True` for `KEEPALIVE`, `RESOURCE_REQ`, `RESOURCE_PRF`, `RESOURCE`,
`CACHE_REQUEST` and `CHANNEL` before it consults the hashlist (`Transport.py:1635-1640`).
This port ran all six through the duplicate check.

The hashable part of a packet excludes the hop count, so two sightings of one frame hash
identically. That's what the exemption is for: every one of these contexts repeats
legitimately, and on shared media the copy a node must forward can arrive after a copy it
has already seen.

The cost was smaller than it looks, and the reason is worth stating plainly. A fresh random
IV encrypts every link packet, so an endpoint retransmitting its own keepalive or resource
part produced a different ciphertext that the filter never caught. The exposure covered
relayed link traffic over shared media—the case upstream's own comment names.

### PLAIN and GROUP packets are no longer deduplicated either

Both branches return before the duplicate check upstream (`Transport.py:1654-1655`,
`:1667-1668`). The filter now drops a PLAIN or GROUP announce regardless of hop count,
rather than passing it through for announce validation to reject later.

### A client of a shared instance filters nothing

`packet_filter` returns on its first line for a client (`Transport.py:1625-1627`), and
`add_packet_hash` is a no-op there too (`:1619-1621`). This port honoured the flag only in
the transport-id branch, so a client re-filtered traffic its instance had already vetted and
kept a hashlist it had no use for.

### A packet for a link this node carries stays out of the hashlist

Upstream defers recording when the destination is in the link table (`Transport.py:1944-1952`):
on shared media the node can see the packet before its turn to route it, and recording the
hash then filters the copy it must forward. This port had the link-request-proof half of
that guard and not the link-table half.

### Five violation counters upstream can't reach, deliberately not ported

Python counts a protocol violation at five points inside `packet_filter`. All five are
unreachable: an `if packet.receiving_interface` guards each one, `Packet.__init__` leaves
that `None` (`Packet.py:166`), `unpack()` never sets it, and the function's only caller
assigns it after the filter returns (`Transport.py:1795-1799`). Counting them here would
make this port's `Violatns.` column report events the daemon it mirrors reports as zero.

### The public filter and the live filter are one function

`Transport.packetFilter(_:)` was a second public implementation of the same decision,
carrying none of these fixes and called by nothing but its own tests. Both spellings now run
one implementation.

## [1.14.0]—the `rnstatus` and `rnir` command surfaces at RNS 1.5.2

1.13.0 taught the daemon to publish the traffic aggregates a Python `rnstatus` reads. This
release is the other half: the client that renders them, and the flags that ask for them.

`Reticulum.rnsProtocolVersion` stays at 1.4.2. These are the `rnstatus` and `rnir` parts of
RNS 1.5.2, not the whole release—the traffic-class queues, the path-request gate and the
`Reticulum.py` changes are still outstanding.

### `rnir` no longer advertises an option the real tool rejects

`rnsd`, `rnpkg` and `rnir` share one option table, gated by a single `allowServiceFlags`
boolean. That boolean described one of two independent axes: `rnsd` takes `-s`/`-i` and
`--exampleconfig`, `rnpkg` takes only `--exampleconfig`, and `rnir` (`rnir.py:54-58`) takes
neither. The port gave `rnir` an `--exampleconfig` that the real tool rejects.

An `RNSDApp.Variant` enum now carries each tool's whole identity, so a third axis can't
repeat the mistake. A string substitution had produced the `rnpkg` help expectation from the
`rnir` one, so it could never have caught this. Both are literal captures now.

### `rnstatus` gains `-b`, `-p`, `-q` and `-z`

- `-b, --blocked-ips` lists the blocked addresses a `BackboneInterface` server reports,
  under the `Blocked` count that already printed.
- `-p, --pps` appends the packet rates to both `-t` totals lines.
- `-q, --queues` prints the five `Qu. Pressure` rows: total, data, announce, path request,
  and ingress limiter. Each row carries a depth and a drop count.
- `-z, --profiling` parses. This port instruments nothing, so it prints nothing—the same
  output an uninstrumented Python daemon gives, because `RNS.Profiler.ran()` is false there
  too. The RPC server answers the `profiling_results` verb explicitly rather than letting it
  reach the unknown-verb warning.

The `--sort` vocabulary was twelve keys short: `arxc`, `atxc`, `prxc`, `ptxc`, `pvs`, `ivs`,
`flt`, `gravity` (and its `g` alias), `txdrp`, `txdrb` and `txbuf`, plus `anns` alongside
`announces`. It also accepted `announce`, which Python has never had—`-s announce` sorted
here and left the order untouched there. This release removes that alias.

### The per-interface block was missing six of its lines

Against RNS 1.5.2 the port dropped `TX Drops`, `Violatns.`, `Flt. Hits`, the `, MTU n`
suffix on `Rate`, the `, gravity n` suffix on `Status`, and the `n↓ m↑ total` header that
`Path Rqs.` and `Announces` grow once both lifetime counters are non-zero. The `-t` totals
block was missing the `% data` share, and the whole `Path Rqs.`/`Announces` aggregate
blocks under `-P` and `-A`. The `-d`/`-D` details never rendered `LXMF address`.

Two of these carried a hazard worth naming. Python builds `pc_str` and `rpc_str` with a
**leading** space and interpolates them with one more. The port dropped the leading space
and compensated with a second literal space at each print site. The two errors cancelled
while the string was always non-empty, and the announce and path-request percentage
suffixes introduced here are the case where it isn't. The strings now carry the leading
space, every print site uses one separator, and this release corrects the three goldens
that had recorded the extra space.

The other is a copy-and-paste in Python worth reproducing rather than fixing. Python guards
the announce `% of flow` suffix on the **path-request** speed keys while its body reads the
announce ones (`rnstatus.py:621-626`). An interface reporting `arxs` but not `prxs` prints
no suffix on Python, and now prints none here.

Where Python subscripts a stats key without a presence test, the port reads it with a zero
default. `rnstatus -q` against a peer that predates these counters renders zeros here and
raises a `KeyError` there.

## [1.13.0]—Traffic aggregates a Python `rnstatus` reads without asking

`Reticulum.get_interface_stats()` publishes thirty-one top-level fields this port never
emitted: the announce and path-request byte, speed and frequency totals, packets per second,
and the inbound queue depths and pressures.

Presence isn't optional for most of them. `rnstatus` guards the per-interface fields with
`if "key" in ifstat`, but subscripts the top-level ones bare—`stats['rxpps']` under `-p`,
`stats['rxqt']` under `-q` (`rnstatus.py:740`, `:785`). An operator running their own Python
`rnstatus` against a Swift daemon got a `KeyError` traceback and no output at all, which is
the failure a missing `txdrp` produced in 1.11.0.

`sampleInterfaceSpeeds` derives the announce and path-request aggregates in the pass that
already computes `rxs`/`txs` from the same per-interface counters, so `arxb` and `arxs` can
never describe different traffic. Byte totals accumulate, and each pass reassigns the
speeds and frequencies, matching `Transport.py:645-671`—an accumulating speed would keep
climbing after the traffic stopped.

`rxpps` and `txpps` needed transport-level packet counters. The inbound one increments after
the duplicate filter, where Python has it, so a replayed frame counts as a filter hit rather
than as received traffic. The outbound one needed a seam: Python funnels every send through
`Transport.transmit`, while this port called `interface.send` from eighteen places. All
eighteen now route through `Transport.transmit(_:on:)`, and a structural test fails if a
nineteenth ever calls an interface directly. Rates round half-to-even, the way Python's
`int(round())` does.

The queue depths and pressures report zero. This port has no traffic-class worker queues:
`handleIncoming` runs each frame to completion on the receiving interface's thread, so the
momentary depth really is zero and nothing is ever dropped for want of queue space. Zero is
the accurate reading rather than a placeholder, and porting the queues turns these into reads
of the snapshot.

`Reticulum.rnsProtocolVersion` stays at 1.4.2.

## [1.12.0]—relays now check the proofs they forward

A transport node relaying a link-request proof forwarded it without looking at the signature.
Python validates every one against the responder's recalled identity and branches hard on the
result (`Transport.py:2641-2669`): a valid proof goes on and marks the link-table entry
validated, and the receiving interface drops an invalid one and raises a protocol violation.
It also requires the proof to arrive on the link's next-hop interface, the side facing the
responder, since that's the only direction a proof can legitimately travel.

This port applied none of the three checks. A link endpoint still validates, so a forged proof
could never establish a link. What the gap bought an attacker was a Swift transport node that
would carry the forgery to the initiator for them, from either direction, and never count it.
The gap dated back to 1.4.2.

All three checks now sit together in `handleLinkRequestProof`, the only place this port can
examine a relayed proof. `Link.proofSignatureIsValid(_:responderIdentity:)` is the relay
form of the terminus check. A transport node holds a routing entry and an identity from an
earlier announce rather than a `Link`, and an LRPROOF's destination hash is the link ID, which
makes the packet self-describing enough to verify without any link state. Python has the same
split—`Link.validate_proof` at the terminus, an open-coded copy in `Transport.inbound`.

A relay that can't recall the responder's identity drops the proof without raising a violation,
matching the Python path where `recall` returns `None` and the enclosing `except Exception`
swallows the failure. Five existing tests seeded a relay's path table but no identity and so
went quiet under the new gate. A real relay always has the identity, because the announce that
taught it the path is the packet that carried the keys. Confirmed against live Python peers: a
20 KB file still crosses two Python daemons through a Swift hub.

### `active_link_count`

With `LinkRoute.validated` set at the one place this port checks a signature, RNS 1.5.0's
`active_link_count` becomes portable. `getActiveLinkCount()`, the `active_link_count` RPC verb
and the `(N active)` suffix `rnstatus` renders beside the table size are all present.

The count deliberately differs from upstream's. `sum(1 for e in (True for entry in
Transport.link_table if entry[IDX_LT_VALIDATED]))` (`Transport.py:3215`) iterates a dict, so
`entry` is a link ID and `entry[7]` is that ID's eighth byte rather than the validated flag. It
reports roughly 255 of every 256 entries as active however many the relay verified. This port
counts the entries that expression aimed at. Reproducing the bug would put a number
in front of an operator that tracks nothing at all.

Nil and 0 both render no suffix, matching Python's truthiness guard, so a daemon predating the
verb prints exactly what it printed before.

`Reticulum.rnsProtocolVersion` stays at 1.4.2.

## [1.11.1]—`link_count` reported the wrong links

Python's `Transport.link_count()` is `len(Transport.link_table)` (`Transport.py:3211`). The
link table holds one entry per link a node *relays*, so the count measures transit load. A
link the node terminates never enters it. This port returned the number of active links it
held an endpoint of, which is a different quantity and, on a transport node carrying traffic
for others, an unrelated one.

`rnstatus` prints the value as "N entries in link table" (`rnstatus.py:711`), so two nodes
with a direct link between them each claimed one entry while relaying nothing, and a busy
transport node reported its own handful of links instead of the hundreds it was carrying.

`getLinkCount()` now returns `linkRoutes.count`. The links a node terminates are still
reachable through `activeLinks`, and the tests that used `getLinkCount()` as a stand-in for
the link registry now assert against `activeLinks` directly.

### Not ported: `active_link_count`

RNS 1.5.0 added `Transport.active_link_count()` and an `rnstatus` suffix that renders it as
`(N active)`. Two things block a faithful port:

Upstream counts the wrong thing. `sum(1 for e in (True for entry in Transport.link_table if
entry[IDX_LT_VALIDATED]))` (`Transport.py:3215`) iterates a dict, so `entry` is a link ID and
`entry[7]` is that ID's eighth byte rather than the validated flag. The expression reports
roughly 255 of every 256 table entries as active however many the relay actually validated.

Counting the entries upstream *meant* to count needs a `validated` flag, and that flag is only
honest where the proof signature is actually checked. This port forwards a relayed
link-request proof without validating it, so it has nowhere truthful to set the flag. Adding
the validation is a change to what a relay forwards, and it belongs in its own change with its
own interop run—see the note below.

Python's `rnstatus` wraps the query in `try/except` and the unknown-verb path already answers
`nil`, so a Python peer querying a Swift daemon omits the "(N active)" suffix rather than
failing.

### Known gap: relayed link-request proofs aren't validated

Python validates the signature on every link-request proof it relays and, on failure, drops
the proof and raises a protocol violation (`Transport.py:2666-2669`). It also requires the
proof to arrive on the link's next-hop interface specifically. This port forwards any
well-formed proof whose link ID is in the table, from either side. Link endpoints do validate,
so a forged proof can't establish a link—the gap is that a Swift transport node relays it
instead of dropping and counting it. Present since 1.4.2, and unchanged here.

`Reticulum.rnsProtocolVersion` stays at 1.4.2.

## [1.11.0]—the Python `rnstatus` couldn't display a Swift daemon at all

`rnstatus` reads most of the interface-stats dictionary defensively, guarding each lookup
with `if "key" in ifstat`. It doesn't guard `ifstat["txdrp"]` (`rnstatus.py:495`), and the
`if "bitrate" in ifstat` on the very next line is what marks that as an upstream oversight
rather than a contract. This port emitted no such key, so the reference status tool raised
`KeyError` partway through rendering and printed nothing further:

```
 Shared Instance[38911]
    Status    : Up
    Serving   : 0 programs
Traceback (most recent call last):
  File ".../RNS/Utilities/rnstatus.py", line 495, in program_setup
    if ifstat["txdrp"]:
KeyError: 'txdrp'
```

Twenty-two of the keys Python emits unconditionally were missing. `rnstatus -j` serialises
the dictionary with `json.dumps`, which preserves insertion order, so their positions are
part of the output contract too—`mtu` belongs between `type` and `rxb`, and each burst
counter interleaves with its own pair rather than appending at the end. The payload now
carries all fifty-two keys in Python's order, verified by pointing the real Python 1.5.2
`rnstatus` at a Swift `rnsd`.

### The counters behind the new keys

A key that's emitted but never incremented reports a wrong answer rather than a missing
one: an operator reading `protocol_violations: 0` concludes the interface has seen no
malformed traffic. So each new counter sits on the site that already makes the decision
it reports.

- **Announce and path-request byte and frame totals** (`arxb`, `atxb`, `arxc`, `atxc`,
  `prxb`, `ptxb`, `prxc`, `ptxc`). Python bumps these in the same four methods that append
  to the frequency deques (`Interface.py:302-323`), so an event and its count can't drift
  apart. `InterfaceFreqTracker` now does both under one lock acquisition, and the five
  production notification sites pass the frame's real byte count.
- **Announce and path-request rates** (`arxs`, `atxs`, `prxs`, `ptxs`). These are the
  derivative of the preceding totals, computed in the same pass that already produces `rxs` and
  `txs` (`Transport.py:605-640`). A hardcoded zero would have contradicted the `arxb` total
  published beside it.
- **`protocol_violations` and `ifac_violations`**, wired at the four inbound checks that
  already reject a frame: a failed IFAC unwrap, a frame past the interface MTU, a packet
  that fails to unpack, and an oversized announce.
- **`packet_filter_hits`**, wired to the `filterAndRecord` guard in `handleIncoming`.
  That's this port's live filter. The public `packetFilter` covers only the hashlist
  branch and no production path calls it, so counting there would have left the key at
  zero forever.

`burst_count` and `pr_burst_count` report `nil`, matching the base-class properties Python
returns for every interface except a Backbone *server* (`Interface.py:341,344`), which this
port doesn't implement. `txdrp`, `txdrb`, `txstalled` and `txbuffered` report zero and
false: Python mutates them only from the `TransmitBuffer` dataplane in `LocalInterface` and
`BackboneInterface`, which this port deliberately doesn't carry.

`Reticulum.rnsProtocolVersion` stays at 1.4.2. This closes one 1.5.2 gap, not all of them.

## [1.10.3]

### Regressions this day's own releases introduced, found by the post-release audit

- **The RNode redial loop decided success from state it couldn't yet have.** 1.10.1 made
  `start()` asynchronous; the redial predicate still read `isOnline` on the next line, so it
  always saw `false` and always fired a second, spurious bring-up over a radio that had
  already recovered—`resetRadioState()` wiping the validated parameters mid-flight while
  `isOnline` was still true. Both RNode interfaces now wait for the outcome the attempt
  actually produced.
- **A config-constructed `RNodeMultiInterface` transmitted nothing.** 1.10.0 began
  registering the parent object with `Transport`, and the parent's `send(_:)` was an empty
  body—100% silent outbound loss, the exact `bugs/013` shape inside the change that
  closed `bugs/031`. Both `send` bodies now have a real transmit path.
- **`Reticulum.version` reported 1.9.0 from a 1.10.2 build**—every `rn*` tool, `--version`
  and the RetiOS About screen. Now pinned to this file's newest released heading by a test
  that reads the file, because all six existing version tests interpolate the constant
  they're supposed to be checking and none of them can fail.

## [1.10.2]—every idle low-RTT initiator link died after ten seconds


`Link.watchdogMaxSleep = 5` was declared and **never used**—its only reference in the whole
package was a test asserting its value. Python clamps *every* watchdog sleep to it
(`RNS/Link.py:775`), so a status change is observed within five seconds no matter what the
previous state scheduled. Without the clamp, a link that established scheduled its next tick at
`requestTime + establishmentTimeout` (~10.4 s) and slept straight through the window in which
the initiator's keepalive was due (the interval floors at 5 s). No keepalive was ever sent, so
the first tick after establishment found the link idle past `stale_time` and tore it down
immediately.

Every idle initiator link on a low-RTT path therefore died at about ten seconds. It surfaced as
`bugs/034`—intermittent RRC chat-message loss—because the receiver's link expired in the gap
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
and closed—its peer is told rather than left to time out on its own.

Found by attributing `bugs/034` rather than by a failing test; the defect predates the initial
public release.

## [1.10.1]—the RNode bring-up must not block its caller's thread


1.10.0's bring-up gate (`bugs/057`) waited for the device's detect response on the thread that
called `start()`. That's safe for a config-file interface, and **deadlocks** for the port's only
real BLE transport: `RNodeScannerController` hands `CBCentralManager` one serial queue and calls
`start()` from `onGATTReady`, which arrives on it—so every subsequent delegate callback,
including the `didUpdateValueFor` that sets `detected`, is queued behind the wait. The wait was
starving the response it was waiting for: it could only ever time out, close the transport, and
leave the interface offline for good.

`start()` now performs open and detect and returns; the rest of the sequence runs on a queue the
interface owns, which by construction is never a transport's delivery queue. A caller that wants
the reference's synchronous `__init__` semantics—`rnsd` bringing up a config-file radio—calls
the new `waitUntilOnline(timeout:)` explicitly, and `synthesizeInterfaces` does. Same shape for
`RNodeMultiInterface`.

The fix is the same lesson `bugs/058` records, turned on the fix for `bugs/057`: a component must
not depend on a scheduling property its callers can't be relied on to have.

## [1.10.0]—interface construction, bring-up, and device loss

### Every documented interface type constructs from a config file (`bugs/031`)

`RNodeInterface`, `KISSInterface`, `AX25KISSInterface` and `I2PInterface` fell through
`synthesizeInterfaces` to `iface = nil`—no throw, no log—so an operator who uncommented a
documented radio block got a daemon that started, reported healthy, and had no radio.

The four types construct through **`InterfaceTransportFactories`**: device strings resolve
through per-platform factory registrations, so the construction switch carries no platform
conditionals and the split (serial on macOS, BLE from the application, embedded i2pd
everywhere) is expressed as which factories are registered. The unavailable path throws naming
the family, the device string and where to register support; a missing or out-of-range radio
parameter throws per the reference's `validcfg` gates, and the propagated throw is this port's
`RNS.panic()`. Absent *hardware* isn't a construction failure: transports open at `start()`,
so a discovery-written entry with an unfilled `port =` constructs and fails at bring-up with a
real cause, matching the reference's retry posture.

Ships the package's first concrete serial transport (`POSIXSerialPort`, termios, macOS), the
serial-backed `RNodeTransport` adapter, RNode station identification
(`id_callsign`/`id_interval`, the reference's `first_tx` machinery), and all 18 previously
unread interface-block keys—including `device`, which now binds the named network device's
address on UDP and TCP server instead of the wildcard. An unknown interface type is a loud
error naming the type, matching the current reference's external-module miss
(`Reticulum.py:1055-1061`); it no longer silently vanishes.

New storage inventory entry: `storage/i2p` (`I2PInterface.py:90-91`), the embedded daemon's
data directory when a config block constructs the interface.

**The rest of the types followed.** `SerialInterface`, `RNodeMultiInterface` and
`WeaveInterface` construct too—Weave being the aggravated case, since this port's own
discovery emits `type = WeaveInterface` entries its config path then rejected. The config
parser gained configobj's third section level: a `[[[sub]]]` line begins with `[[` and ends
with `]]`, so every RNodeMulti radio row had been leaking out as a *top-level* interface named
`[sub]` with type Unknown. `PipeInterface` keeps taking the loud unknown-type path by
documented design (POSIX subprocess pipes, no mobile use case), now pinned by a test.

### An RNode reports online only after a validated bring-up

`start()` was `open(); isOnline = true`, with `detect`, `initRadio` and `validateRadioState`
carrying **zero production callers**—only tests called them by hand. A host-mode RNode was
therefore never sent `CMD_FREQUENCY`/…/`CMD_RADIO_STATE ON`: its radio stayed off while
`rnstatus` reported the interface Up and Transport routed packets into it. `start()` now runs
the reference's `configure_device` gate (`RNodeInterface.py:424-467`)—detect, bounded wait,
`initRadio`, validate the echoed parameters, and only then online; any failure closes the
transport and stays offline. `RNodeMultiInterface` gets the same gate. `validateRadioState`
now `None`-guards only the frequency comparison as the reference does, because guarding all
five made validation vacuously true against a device that answered nothing.

### Serial-family interfaces notice device loss, and redial

Nothing in the port could observe a USB flap: the transport seams had no error surface,
`POSIXSerialPort` discarded device-gone reads and never checked `write()`'s `-1`, and no
serial-family interface went offline except an explicit `stop()`. The interface stayed Up with
growing TX counters while every packet went into a dead descriptor—where a Python node
resumes within ~5 s. Both transport protocols now require `onTransportError`; one shared
reconnect loop serves all five interfaces, re-running the full `start()` (an RNode re-runs its
whole bring-up—a re-powered modem lost its configuration with its power); and a failed write
is no longer counted as transmitted bytes.

### Hardware MTU follows bitrate

`optimise_mtu` (`Interface.py:205-217`) had no port, and the class constants were `let`s that
couldn't be recomputed. Swift advertised 262144/1048576 in `LINKREQUEST` MTU signalling where
Python advertises 8192/16384 in the identical topology. The ladder now runs after the
configured bitrate and on every spawned server-side client. `LocalInterface` gains the
`HW_MTU`/`AUTOCONFIGURE_MTU` it never had, which had disabled link-MTU discovery for every
link crossing a Swift shared instance.

### Two attributes that were written but never read, and one never written

- **`wants_tunnel`**: a TCP or Backbone client never requested tunnel synthesis, so the remote
  transport never rebuilt the paths it held and every reconnect silently lost them. Requested
  on connect, served from the jobs loop.
- **`announce_cap`**: parsed, validated, written onto the interface, inherited by spawned
  clients—and then every rate computation divided by a hardcoded 2%. Both `AnnounceQueue`
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

## [1.9.0]—persisted state, and a node that listened to itself

A minor rather than a patch release: **every persisted state file changes name, encoding or
both**, so a config directory written by 1.8.0 or earlier isn't read by this version. See
*Upgrading* below—the cost is one cold start, and nothing is destroyed.

### Changed—persisted state is now the reference's, byte for byte (`bugs/029`)

A Reticulum config directory is a shared surface the moment `rnsd` can be either
implementation, which is what the RetiOS macOS daemon probe and the interop suite already
assume. Four files diverged from the Python reference in name *and* encoding for the whole
life of the port, and a fifth wasn't written at all. None of it was visible: the names
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
a file Python still couldn't read—the worst available outcome, because it looks right.

Three fields of the known-destinations entry weren't being persisted at all and now are:
the last-announce time (previously overwritten with "now" on every save, so
`UNUSED_DESTINATION_LINGER` could never expire anything), the last-use time, and the
retention sentinel (so a pinned destination was eligible for the next sweep).

`storage/ratchets/` is the one to note if you run both implementations: the port wrote JSON
where the reference writes msgpack, at the same path under the same filename, and **both
implementations delete what they can't parse there**—so each side was destroying the
other's forward-secrecy state on every switch (`bugs/039`).

### Fixed—the path table now actually restores (`bugs/041`)

`Reticulum.start()` reads the path table and resolves each entry's interface; `rnsd`
synthesises the configured interfaces *after* `start()` returns. So the restore ran against
an empty interface set and dropped every entry, on every start, under every on-disk format.
A Swift daemon had never restored a path table. Entries whose interface hasn't appeared yet
are now held and installed as interfaces register, with a bounded give-up matching the
reference's outcome for an interface that isn't there.

This is why the format work above is necessary but not sufficient: with `029` fixed and this
not, the daemon writes a perfectly correct `destination_table` and still starts with no paths.

### Fixed—a node acted on its own announces (`bugs/047`)

A transport-enabled neighbour reflects announces back to the node that originated them, by
design: `Transport.outbound`'s broadcast loop (`Transport.py:1197`) has no receiving-interface
exclusion, and the PATHFINDER_R retransmission re-sends with `attached_interface = None`
(`:604-637`). Every node hears its own announces come back, and every node is expected to ignore
them.

The reference ignores them with one test—`local_destination` is looked up in
`destinations_map` and the **entire** announce block hangs off it being nil
(`Transport.py:1767-1772`), with the ownership check repeated at the path-table admission test
(`:1806-1807`). This port had no equivalent anywhere in `handleAnnounce`. The one place it
consulted `registeredDestinations` in that path was an ingress-limit *exemption*—the opposite
polarity, making the node more eager to process its own announce, not less.

So a node learned a path to itself, re-cached its own identity from the wire, handed its own
announce to every registered handler, and could relay it onward. For most destination types that
is invisible: a delivery destination re-learning its own stamp cost changes nothing. It became
visible only when a handler that *creates state* appeared—an LXMF propagation node, which
peers. A lone one, on a mesh with nobody else on it, ended with exactly one peer: itself.

Three existing tests were passing only because the gate was missing; each registered the
destination it then announced to itself, which was never what they were testing. A fourth
asserted "the handler was NOT called" and would have started passing for the gate's reason rather
than the path-response filter's—it's fixed too.

### Fixed—a control listener that reported a bind it didn't achieve (`bugs/040`)

`NWListener` reports bind failures asynchronously through `stateUpdateHandler`. None was set,
so a listener that never bound still logged `RPC server started on port N`, and the caller
discarded the errors that *were* raised. The daemon then ran normally while `rnstatus`,
`rnpath`, `rnprobe`, `rnid -r` and `rnx` all answered "Couldn't connect to instance control
socket"—from the utility's side, indistinguishable from no daemon at all. The failure is
now detected and logged at CRITICAL, naming what has become unreachable.

### Upgrading

**Expect one cold start.** A daemon upgrading past this release meets none of its own
previous state files and starts with an empty path table, no known destinations, and an
empty replay window, relearning them from announces. That's exactly what the reference does on a
fresh install, and what it does for any file it can't find (`Identity.py:238-240`,
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

They aren't read, not written and not deleted—removing an operator's files to tidy up is
not a decision this release makes. Learned peer ratchets under `storage/ratchets/` *are*
removed as they're encountered, because they sit at a name the reference uses and a Python
daemon deletes them anyway.

Rolling back is symmetric: the reference-format files a rolled-back build leaves behind
become orphans in their turn, and the older build starts empty. No data is destroyed in
either direction.

## [1.8.0]—the bugs/013 defect class: config, transport identity, delivery truth

A minor rather than a patch release, for the same reason 1.7.0 was: `displayName` changes
for eleven more interface types and `Interface.hash` is `fullHash(displayName)`, so
interface identity changes again.

### Corrections to 1.7.0

Two claims in the 1.7.0 notes below were wrong when published. The 2026-07-29 audit
falsified both. They're corrected here rather than edited out of history.

- **"All config-directory resolution now goes through
  `InstanceConnection.homeDirectory(environment:)`"**—it didn't. One resolver was
  converted; **fourteen** other sites still reached a platform home API. `rnir` and `rnpkg`
  passed `FileManager.homeDirectoryForCurrentUser` into the config resolver;
  `RNCopyDiskFileSystem.homeDirectoryPath`—which is where `rncp`'s `$HOME/.rncp` identity
  and allow-list come from, and which the same 1.7.0 note describes as a problem—was still
  `NSHomeDirectory()`; and eleven `expandingTildeInPath` sites across `rnid`, `rnpath`,
  `rnstatus`, `rnx` and two library files resolved every user-supplied `~` against the
  account's real home. So the failure the note describes—a utility under a relocated
  `HOME` reading the real `~/.reticulum`, finding the live daemon's identity and
  authenticating to the live daemon—remained reachable through all of them. Fixed below,
  with a structural guard so the claim is now checkable rather than asserted.

- **"Python sets `SO_KEEPALIVE` and the probe timers on every TCP socket it opens … this
  port set none"**—the statement about Python is right; what shipped covered the two
  *dialing* paths. `TCPServerInterface.start()` still passed `.tcp` to `NWListener`, so every
  connection a listening interface accepted took Network.framework's defaults with keepalive
  **off**—which is the case Python's own `connected_socket` branch exists to handle
  (`TCPInterface.py:241`, `:259-261`, reached from `:591`). Three further sites were also
  never covered. Fixed below.

### Fixed

- **A packet on an MTU-upgraded link couldn't be sent at all** (`bugs/033`). `pack()` capped
  every packet at the global 500-byte MTU. Python carries a *per-packet* cap and takes it from
  the destination—`self.MTU = destination.mtu` for LINK-typed packets (`Packet.py:153-154`)—so
  once MTU discovery raised a link, the resource parts `bugs/016` sizes from that negotiated
  MTU exceeded the global cap and every one of the thirteen interfaces refused to transmit
  them. The sender advertised a resource and then sent nothing; the peer timed out. This is the
  outbound half of `bugs/010`. `Packet.mtu` is now set from the link in `Transport.send`, and
  from the packet's own size in `unpack` so a relay forwards an upgraded link's traffic without
  re-capping it. **Found by the interop suite, not by any unit test**—there was no
  package-level test of an over-MDU request response, which is why it survived.

- **The path table and the link table routed by interface name** (`bugs/027`). Both stored
  `Interface.name` and resolved it with `first(where:)`, and every connection accepted by one
  `TCPServerInterface` is named `"Client on <server>"` by design (`TCPInterface.py:590`). With
  two clients attached, every route resolved to whichever registered first—regardless of
  which one heard the announce—so traffic went to the wrong peer while the table insisted it
  had a route. Both tables now hold weak references to the interface object, as the reference
  does (`Transport.py:1639`, `:1693`), and keep the name for display only (`Reticulum.py:1532`).
  Persistence stores `Interface.hash` and resolves it through the new
  `Transport.findInterface(fromHash:)`; an entry whose interface is gone isn't persisted
  (`:3374`) and one whose hash resolves to nothing is dropped on load rather than restored
  unroutable. **The link-table half was found only by the new interop cell**: link
  *establishment* routes through the path table, so a relayed link came up normally and only
  the traffic afterwards was misrouted—it read as a resource bug.

- **Shutdown never tore links down** (`bugs/028`). `Transport.detachInterfaces()` was a
  faithful port with zero callers, so a node exiting cleanly emitted no `LINK_CLOSE` and every
  peer held the link ACTIVE until its own keepalive watchdog expired—up to 360 s—with the
  sessions riding those links hanging rather than failing. `Reticulum.stop()` now calls it,
  **before** `transport.stop()`: running it after would hand the closes to already-stopped
  interfaces, satisfying "teardown was called" while emitting nothing.

- **Discarding an unstarted dispatch source killed the process** (`bugs/032`). A source from
  `DispatchSource.make…Source` begins suspended, and libdispatch traps when a suspended
  object's last reference is released—cancelled or not. `Link.rescheduleWatchdog` and
  `TCPClientInterface.scheduleReconnect` released one after only `cancel()`, on paths reached
  by ordinary link teardown and by a `stop()` landing during a failed dial. `SIGTRAP`, nothing
  thrown or logged. Both now use `DispatchSourceProtocol.cancelUnstarted()`.

- **Link data packets generated no receipt** (`bugs/014`, the transport half). `Transport.send`
  gated receipt creation on `destinationType == .single`, and `Link.send` hardcoded
  `generateReceipt: false`, so nothing above the link could learn whether a packet arrived.
  Receipts are now generated for link packets matching the reference's predicate
  (`Transport.py:1113-1124`), and `Link.receive` routes a context-`.none` PROOF to the
  packet-receipt table when no channel-proof waiter matches.

- **Eleven interface types published a name Python doesn't** (`bugs/022`). `displayName`
  defaulted to the bare configured `name`, and 1.7.0 corrected it for the TCP and UDP
  families by adding per-type overrides—so every type it didn't touch kept the wrong
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

  The last two weren't in the audit's list. `PosixTCPServer` built Python's literal
  `"Shared Instance[<port>]"` (`LocalInterface.py:496-498`) out of `name`, so it matched only
  because its one caller happens to pass that string. `WeaveInterfacePeer` published
  undelimited hex where `RNS.hexrep` delimits with `:` (`RNS/__init__.py:176-183`)—a
  correct-looking string with a different hash.

  `RNodeSubInterface` gained the `parentInterface` back-reference Python passes into its
  `__init__` (`RNodeMultiInterface.py:939`), assigned when the multi-interface adopts its
  sub-interfaces, since Swift constructs them before the parent exists.

- **A non-connectable I2P interface was never hidden from status output** (`bugs/022`).
  The suppression gate was a faithful port of `rnstatus.py:393-403` and its tests passed—against
  a hand-built stats dict named `"I2PInterface["`, the string the gate keys on. A
  real interface published its bare configured name, so the prefix never matched and the
  gate suppressed nothing. Fixed by the published-name change above; now asserted from a
  real interface through the rendered output, for any configured name.

- **Sockets this port accepted or listened on took Network.framework's defaults**
  (`bugs/023`). Python configures the socket it accepts exactly as the one it dials, so
  direction must not decide whether the options apply. All socket options now come from a
  single `RNSSocketOptions` factory, and a structural test fails if any other file
  constructs them. Six sites were bypassing it:

  - `TCPServerInterface.start()`—the listener, and so every connection accepted from it.
  - `LocalInterface.connect()`—missing the `TCP_NODELAY` Python sets at
    `LocalInterface.py:147`.
  - `TCPClientInterface`—built its own; now delegates.
  - `RPCServer.start()`—`.tcp` on the loopback control listener.
  - `SAMSocket.connect()`—`.tcp`, so a SAM bridge that stopped answering left the I2P peer
    online forever. It now takes Python's **I2P** timing set (`I2P_USER_TIMEOUT` 45,
    `I2P_PROBE_AFTER` 10, `I2P_PROBE_INTERVAL` 9, `I2P_PROBES` 5), selected by
    `i2p_tunneled = True` at `TCPInterface.py:190-194`—a distinction this port did not
    previously have, and the direct-TCP timers would tear down a healthy tunnel.
  - `PosixTCPServer.acceptOne()`—set only `SO_NOSIGPIPE` where Python sets `TCP_NODELAY`
    on every accepted shared-instance socket (`LocalInterface.py:98-100`).

  The last three weren't in the audit's list. The shared-instance option set is
  `TCP_NODELAY` **only**, matching Python: `LocalClientInterface` calls no `set_timeouts_*`
  on either direction, so enabling keepalive there would exceed the reference.

- **Fourteen sites resolved a home path without honouring `$HOME`** (`bugs/024`)—see the
  1.7.0 correction above. `InstanceConnection.expandTilde` is now the single expansion, with
  `posixpath.expanduser`'s semantics including the `rstrip('/')` on the home;
  `RNCopyDiskFileSystem` takes an injected environment. `rncp` already had a correct
  `$HOME`-aware expansion and now delegates to the shared one rather than keeping a second
  copy of the rules. The unset-`HOME` fallback in `InstanceConnection` is the one sanctioned
  exception, and a test pins it at exactly one occurrence.

### Changed

- **Resource part size, and every payload limit on a link, now derive from the negotiated
  per-link MTU** rather than the base constant (`bugs/016`)—resource segmentation, channel
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
  downstream conformer that relied on publishing a bare name—including test doubles—publishes
  `TypeName[name]` now.
- `TCPClientInterface.tcpOptions()` / `.tcpParameters` and `BackboneInterface`'s equivalents
  are removed; use `RNSSocketOptions`.
- `RNCopyDiskFileSystem.init()` gains an `environment:` parameter (defaulted, so existing
  callers are unaffected).

## [1.7.0]—TCP interface naming, reconnection, and keepalive

A minor rather than a patch release: the fixes add public API (`reconnectWait`,
`maxReconnectTries`, `bindIP`, `HDLC.FrameDecoder.reset()`) and change what every TCP and
UDP interface calls itself—and therefore its `Interface.hash`, which is
`fullHash(displayName)`.

### Fixed

- **Configured TCP interfaces were invisible to `rnstatus`** (`bugs/013`).
  `TCPClientInterface.displayName` emitted `TCPInterface[Client on <host>:<port>]` for
  every client. In Python that form belongs only to a *server-spawned* client—the
  spawned interface's `name` is `"Client on "+servername` (`TCPInterface.py:590`)—and
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
  a Python daemon on the same network—previously the two disagreed for every TCP
  interface. `TCPServerInterface` gained a `bindIP` (default `0.0.0.0`), and interface
  synthesis now reads `listen_ip` for it.

- **`TCPClientInterface` never reconnected** (`bugs/013`). It dialed once from `start()`;
  on peer FIN the receive loop set `isOnline = false` and returned—no log line, no
  `cancel()`, no redial. A peer that accepts and immediately hangs up (ordinary churn on
  the public transit nodes) took the node permanently offline with nothing in the log,
  while the dead connection sat in `CLOSE_WAIT` for the life of the process. Python has
  retried since forever (`RECONNECT_WAIT = 5`, `RECONNECT_MAX_TRIES = None`,
  `TCPInterface.py:270-293`), and every other reconnecting interface in this port already
  did too—the TCP client was the only one that didn't.

  Adds `reconnectWait` (default 5 seconds) and `maxReconnectTries` (default nil = unlimited,
  config key `max_reconnect_tries`), cancels the superseded connection before each redial,
  and logs Python's `Reconnected socket for …` and `Max reconnection attempts reached for …`.
  `.waiting` is no longer swallowed: a refused peer is retried on Python's clock instead of
  silently inside `NWConnection`.

- **No TCP keepalive on the dialing interfaces.** *(Corrected in 1.8.0—this covered the
  two dialing paths only; the listener and three other sites still took framework defaults.)*
  Python sets `SO_KEEPALIVE` and the probe
  timers on every TCP socket it opens (`TCPInterface.set_timeouts_osx` /
  `set_timeouts_linux`, `BackboneInterface.py:655`); this port set none, because
  `NWConnection(to:using: .tcp)` takes Network.framework's defaults and those have keepalive
  off. A peer that vanished *without sending FIN*—a machine that slept, a NAT that dropped
  the mapping, a peer that was hard-killed—therefore left the connection `.ready` forever:
  no event fired, the interface kept reporting `Up`, and everything sent through it was
  silently discarded. Reported as "RetiOS doesn't reconnect to the mesh after the laptop
  sleeps", and the reason the reconnect fix above couldn't cover that case on its own—nothing
  ever triggered it.

  The values live in `TCPClientInterface.tcpOptions()`, separately from the `NWParameters`
  built around them, because that object is the only place they can be read back at all:
  `NWParameters.defaultProtocolStack.transportProtocol` returns a *different*
  `NWProtocolTCP.Options` instance than the one passed to `NWParameters(tls:tcp:)`—`===`
  is false on every OS tested—and on macOS 14 that re-wrapped instance reports framework
  defaults rather than the configured values. Network.framework publishes no getters for TCP
  options at the C level either, so no readback anywhere is authoritative. The tests
  therefore assert the object this port constructs and hands over, and additionally verify
  the round trip through `NWParameters` on platforms where a control value proves the
  readback can be trusted.

  `TCPClientInterface` and `BackboneInterface` now dial with Python's values:
  `keepaliveIdle = 5`, `keepaliveInterval = 2`, `keepaliveCount = 12`,
  `connectionDropTime = 24`, and `noDelay = true` (`TCP_NODELAY`, which Python sets on every
  socket on both platforms).

- **Swift utilities ignored `$HOME`.** *(Corrected in 1.8.0—"all config-directory
  resolution" was one resolver; fourteen other sites still reached a platform home API,
  including the `rncp` allow-list this very note describes.)*
  Python expands `~` with `os.path.expanduser`, which
  returns `$HOME` when it's set; `NSHomeDirectory()`—and
  `FileManager.homeDirectoryForCurrentUser`, which `rnsd` used—always reports the
  account's real home on macOS. A utility launched with `HOME` pointed at a sandbox
  therefore read and wrote the developer's actual `~/.reticulum`, picked up the real
  transport identity, and could authenticate to the real daemon on 37428. Utilities that
  keep state in `$HOME` directly (`rncp`'s `$HOME/.rncp` identity and allow-list) wrote to
  the developer's real files. All config-directory resolution now goes through
  `InstanceConnection.homeDirectory(environment:)`.

- **`UDPInterface` hardcoded `0.0.0.0` as its bind address** instead of reporting the
  configured `listen_ip`, as Python does (`UDPInterface.py:63`, `:131-132`)—so a
  loopback-bound interface published a different name, and a different `Interface.hash`,
  than the Python interface beside it. Gained a `bindIP`, which synthesis now populates.

- **A server-spawned client published `type = "TCPServerClientInterface"`**, which isn't an
  RNS interface class. Python builds a plain `TCPClientInterface` from the accepted socket
  (`TCPInterface.py:591`), so `type` now says that.

- `HDLC.FrameDecoder.reset()`—drops a partially received frame, so a half-decoded frame
  can't be prepended to the first bytes of a reconnected session.

## [1.6.0]—the `rn*` command-line utilities

Ports of the tools in `RNS/Utilities`, each split into a testable library type under
`Sources/ReticulumSwift/Utilities/` and a thin executable target that only parses
arguments, prints, and sets an exit code. No SPM dependency was added; the `argparse`
subset the tools need is implemented in-package.

Every claim below was checked against the **installed Python tools**, not against the
reference source alone: help text and error pages byte-for-byte, live rendering against a
running daemon, and—for the payload fixes—a Swift `rnsd` on isolated ports driven by
the real Python `rnstatus` and `rnpath`.

### Added

- **`rnstatus`**—interface and transport status, JSON mode, sorting and filtering,
  monitor mode, and remote status over a management link.
- **`rnpath`**—path table, announce-rate table, path requests, drop path / all-via /
  announce queues, and blackhole listing and management.
- **`rnprobe`**—probe a destination and report round-trip time and physical-layer stats.
- **`rncp`**—authenticated file transfer over the Resource API, both directions,
  including fetch mode.
- **`rnid`**—identity generation, import/export, RSG signatures, signed messages, ASCII
  armour, and chunked file encryption and decryption.
- **`rnx`**—remote command execution. The listener half executes commands and is
  macOS-only.
- **`rnsd`**—brought to parity with `rnsd.py`: service mode, log destinations, verbosity
  arithmetic, and `--exampleconfig` (byte-identical, 14,960 bytes).
- **`rnir`, `rnpkg`**—the two placeholder tools, which only bring up an instance.

Supporting API:

- `InstanceConnection`—resolves the config directory the way Python does, then either
  becomes the shared instance, attaches to a running one as a local client, or runs
  standalone. The Swift equivalent of `RNS.Reticulum(require_shared_instance=…)` plus the
  `is_connected_to_shared_instance` branch.
- `RPCClient`—client for the instance-control channel, counterpart to `RPCServer`.
- `MultiprocessingAuth`—CPython's `multiprocessing.connection` handshake, both the
  pre-3.12 and 3.12+ generations.
- `ArgumentParser`—the `argparse` subset the utilities need, including `allow_abbrev`.
- `UtilityFormatting`—the utilities' own `size_str` / `speed_str` / `pretty_date`, which
  differ from the `RNSUtilities` helpers in ways that show up in output.
- `InterfaceStatsPayload`—the `get_interface_stats()` dictionary, shared by the RPC
  server, the `/status` request handler, and `rnstatus` running in-process.
- `Interface.statsTypeName` / `statsShortName`—what a Python peer should be told this
  interface is called.
- `MsgPack.Value` scalar accessors (`asInt`, `asDouble`, `asString`, `asData`, `asBool`,
  `asArray`, `asDictionary`, `isNil`) are now public.
- `ReticulumConfig` parses `shared_instance_port` and `instance_control_port`.

### Fixed

These are interop defects that predate the utilities: Swift produced something a Python
client indexes directly, so the Python side raised rather than degrading.

- **Instance-control authentication rejected CPython 3.12 and newer.** `RPCServer` only
  implemented the legacy handshake—a 20-byte challenge answered with a bare HMAC-MD5
  digest—and hard-rejected anything that wasn't exactly `#CHALLENGE#` plus 20 bytes.
  CPython 3.12 changed the format to `{digest}` plus 40 random bytes, with the MAC covering
  the whole prefixed message, so a modern `rnstatus` or `rnpath` couldn't authenticate
  against a Swift `rnsd` **at all**. Both generations now work in both directions.
- **Blackhole source files were written as JSON where Python writes msgpack.** Python's
  `reload_blackhole` unpacks each file with msgpack, so it couldn't read a Swift-written
  list, and Swift silently ignored every list Python published.
- **`Transport.isConnectedToSharedInstance` was never assigned.** It was declared and read
  in three places but set nowhere, so it was false in every process. A stack attached as a
  local client therefore redid work the shared instance had already done: `filterAndRecord`
  re-ran the HEADER_2 transport-id filter and dropped packets that had been forwarded *to
  us*, `shouldApplyDelta` applied the local hops delta a second time, and `rnprobe` took the
  standalone branch and never reported RSSI, SNR, or Link Quality.
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
  `ifac_identity.sign(full_hash(ifac_key))`—different bytes, whose last five `rnstatus`
  prints as the network's "Access" fingerprint. A Swift node and a Python node on the same
  IFAC network displayed different access codes.
- **`drop:path` over RPC returned nil** instead of the bool from `expire_path`, which
  `rnpath` uses to choose between `Path to … was dropped` and `No path known`.
- **Interface `type` and `short_name` published Swift class names.** A Python client saw
  `PosixTCPServer` where a Python daemon reports `LocalServerInterface`, and would have seen
  `LocalInterface` for what Python calls `LocalClientInterface`; `short_name` reported
  `Shared Instance` where Python hardcodes `Reticulum`.
- **Per-interface key order in the stats payload didn't match Python's.** `rnstatus -j`
  serialises with `json.dumps`, which preserves insertion order, so the order is part of the
  `-j` output contract. `announce_queue` was also emitted unconditionally, where Python
  creates the attribute lazily and `rnstatus` branches on its presence.
- **`ResourceTransfer.onProgress` was never invoked**, so every progress readout sat at 0%.
- **`Link.handleIncomingRequestResource` unwrapped the request payload only for `.bytes`**
  and dropped the raw value, breaking large requests from Python peers.
- **`argparse` behaviour across all nine tools.** `allow_abbrev` is an `argparse` default
  that none of the RNS utilities disable, but only `rnsd` implemented it, so eight tools
  rejected `--conf` and `--vers`. Unrecognized options were reported in the singular where
  `argparse` always uses the plural; options were named by the spelling typed rather than
  by every spelling (`argument -s:` instead of `argument -s/--sort:`); `rnstatus` printed no
  usage block at all and `rnid` printed its entire help text where `argparse` prints four
  lines of usage and one of error; and `rnstatus -w`, `rnstatus -I`, `rncp -w` and `rncp -b`
  accepted non-numeric values and silently fell back to defaults.
- **`rnpath` couldn't be interrupted.** `signal(SIGINT, SIG_IGN)` disabled the default
  terminate action while the `DispatchSource` meant to replace it was scheduled on the main
  queue, which `rnpath`'s blocking wait never services—so Ctrl-C was a complete no-op.
- **A short option's value may be attached to it.** `argparse` accepts `-s16` as `-s 16`,
  and accepts it at the end of a bundle (`-vvs16` is verbose twice plus size 16). The
  in-package parser only understood bundles of pure flags, so every attached value was
  rejected as an unrecognized argument, exit 2—across `rnprobe -s`/`-n`, `rnpath -m`/`-w`,
  `rncp -b`, `rnx -w` and `rnstatus -w`. A cluster now resolves left to right and the first
  value-taking option in it claims the remainder of the token, which is `argparse`'s rule.
- **`--help` and `--version` are reached by abbreviation.** `rnprobe` scans `argv` for those
  two before parsing, to reproduce `argparse` firing their actions the moment it reaches
  them. The scan compared exact tokens, so `--hel` and `--vers`—both unambiguous, both
  expanded by `allow_abbrev`—fell through to the ordinary parse and took a different code
  path entirely, printing the help page in place of the version.
- **`rnsd --exampleconfig` was 25 lines short of Python's.** RNS 1.4.1 added
  `default_gravity`, `autoconnect_interface_mode`, `autoconnect_announces_to_internal` and
  `autoconnect_interface_gravity` to `__example_rns_config__`. This blob is a document users
  copy verbatim, so it's compared byte for byte and is identical again (15663 bytes).
- **`interface_stats` was missing RNS 1.4.1's `gravity` and `announces_to_internal`.** Both
  are appended after `mode`, exactly where Python emits them: `rnstatus -j` serialises the
  dictionary in insertion order, so position is part of the contract, and Python's own
  `rnstatus` sorts interfaces by `gravity` when the key is present.

### RNS 1.4.2

Audited, no port required—`rnsProtocolVersion` moves to `1.4.2` on that basis rather than
on a changeset. The release is three core diffs against 1.4.1 plus `rnsh`, which isn't
ported:

- `Transport.py:3126` began skipping offline interfaces when fanning a recursive path
  request out. Every fan-out loop here already filtered on `isOnline`, so the port was
  ahead of Python rather than behind. Now pinned by a test.
- `Transport.py:1841` moved a gravity-replacement log line from `LOG_DEBUG` to
  `LOG_PATHING`. This port doesn't emit that line.
- `Discovery.py` began caching the blackholed identity set for 60 s inside
  `list_discovered_interfaces`. Python pays an RPC round-trip to the shared instance per
  `is_blackholed` call; here it's a dictionary lookup under a lock, so the cache would buy
  nothing and would delay a fresh blackhole by up to a minute. Deliberately not adopted,
  and a test now pins the immediacy that decision preserves.

### Known divergences

- **Failure exit codes reach the shell here and don't in Python.** Once a Python utility
  has started a stack, the code it asks for is discarded and the process exits 0. The cause
  is `Reticulum.exit_handler`, registered with `atexit` (`Reticulum.py:369`): isolated by
  unregistering it, after which the very same `sys.exit(2)` exits 2. It applies to every
  post-stack exit in every tool—`rnstatus`'s `exit(2)` on `Could not get RNS status`,
  `rnpath`'s `exit(1)` and `exit(20)`—so `rnstatus; echo $?` reports success when the
  status was never fetched. Matching that would mean no Swift utility could signal failure
  to a script either, so the codes each tool's own source asks for are used instead.
  `argparse` errors agree exactly (exit 2), because those are raised before the stack
  starts.
- **`--version` reports this port's release**, not the RNS protocol version it's
  wire-compatible with. All nine tools answer identically.
- **`rnprobe`'s spinner is gated on a TTY**, where Python writes backspaces and raw glyphs
  unconditionally and makes redirected output unusable for scripting.
- **A Swift shared instance doesn't enumerate a per-client interface entry.** Python
  creates a `LocalClientInterface` object per connected client, which appears in `rnstatus`
  output; Swift's server handles clients internally, so `rnstatus` against a Swift daemon
  lists fewer interfaces. The client count itself is reported correctly.

## [1.5.0]—RNS 1.4.1 parity: interface gravity and dynamic path re-balancing

Brings the port up to Python RNS 1.4.1 (released 2026-07-24). The two headline
features both change how paths are chosen, so a mixed Swift/Python mesh
converges differently than before—in the same direction Python now does.

### Added

- **Interface gravity.** Every interface carries an integer `gravity`
  (default 0, negative values allowed) expressing routing preference. When an
  announce arrives that's *the same announce* already recorded for a
  destination—same emission timebase, equal or fewer hops—the path now
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
  destination, so its proof is the earliest trustworthy hop measurement—previously
  the port waited for the next announce to converge. Latched by the
  new `Link.rebalanced` timestamp so each link re-balances at most once, and
  gated by `Transport.allowLinkPathRebalance`.
- **`Destination.setMaxRequestSize(_:)`** caps inbound requests served by
  registered handlers. Oversized single-packet requests are dropped before the
  msgpack body is unpacked; oversized requests advertised as a Resource are
  rejected at advertisement time, so nothing transfers at all.
- **`maxResponseSize:` on `Link.request(...)`** caps the response a caller
  accepts, with the same two enforcement points. An over-size response fails the
  receipt (new `RequestReceipt.responseRejected()`) rather than delivering
  truncated data.
- **`announces_to_internal`** per-interface option. Set on the interface an
  announce arrived over, it lets that interface's announces onto internal-mode
  interfaces even when it's itself in boundary mode.
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
  *subsiding* burst never refills—so the flag could only clear if new
  announces arrived, which is exactly what it was suppressing. It now needs 2
  (`IC_DEQUE_MIN_SAMPLE`), matching the upstream fix.
- **Ingress limiting released one call early.** The call that clears the burst
  flag now still reports "limited"; Python's `return True` sits outside the
  deactivation branch, so only the *following* call passes. Applies to both
  announce and path-request limiting.
- **Egress path-request limiting triggered far too easily**, using the 2-sample
  minimum that merely makes a frequency computable instead of
  `IC_BURST_MIN_SAMPLES` (6)—throttling ordinary discovery bursts.
- **Channel accepted arbitrarily far-future sequence numbers**, letting a peer
  make the receive ring buffer grow on its say-so. Sequences beyond
  `nextRxSequence + WINDOW_MAX` are now dropped.
- **Channel's stale-sequence wraparound test was inverted and used the wrong
  constant** (`SEQ_MODULUS/2` instead of `WINDOW_MAX`), so near the top of the
  sequence space it dropped legitimate wrapped-*future* frames and accepted
  genuinely stale ones.
- **Discovered peers were dialled as `BackboneInterface` on Apple platforms.**
  Upstream excludes Darwin from backbone support—the client side relies on
  polling semantics that don't hold there—so a discovered
  Backbone/TCPServer peer must be connected as a `TCPClientInterface`. Since
  Darwin is this port's whole target, every discovered peer was taking the
  wrong path.
- **Persisted interface discoveries were never re-checked against the
  blackhole list**, so an identity blackholed after its record was written
  stayed connectable forever. Records lacking a transport or network identity,
  or whose network identity isn't in `interface_discovery_sources`, are now
  pruned too.
- **Config log levels weren't clamped**, so an out-of-range value silently
  fell back to the default instead of saturating. The cap is now 8, matching
  RNS 1.4.1 raising it from 7 so `LOG_EXTREME` is reachable from a config file.

#### Resource progress reporting was entirely inert

- **`ResourceTransfer.onProgress` was never called from anywhere.** It was
  declared, public, forwarded by `Link.request(progressCallback:)` into
  `RequestReceipt`, and consumed downstream—but nothing invoked it, so every
  progress observer in the stack silently read zero forever. Python fires it for
  each newly accepted part on the receiver and once per outgoing batch on the
  sender; both now do.
- **`progress` measured received parts for senders too**, so a sender reported
  0.0 for an entire transfer and then jumped to 1.0. Python's `get_progress`
  branches on `initiator` and counts parts *sent*.
- **`RequestReceipt.responseSize` was unreadable mid-transfer.** It's now
  populated from the response advertisement as soon as one arrives, which is the
  only window in which a progress display can use it.

#### Multi-segment (>1 MB) resource transfers were broken end to end

- **The sender stalled after the first segment.** Each segment is a distinct
  Resource with its own hashmap, but the per-segment part-serving cursors
  (`sentMapHashes`, the collision-guard window's lower bound) carried the
  previous segment's progress forward—so for a two-segment transfer the search
  window started past the shorter second segment's part count, `handleRequest`
  matched nothing, and zero parts were served.
- **The receiver misparsed every segment after the first.** Metadata rides only
  in segment 1's plaintext, but the advertisement's metadata flag is set on all
  of them; gating on the flag alone made a later segment's first three payload
  bytes read as a metadata length. Now gated on segment index, as Python does.
- **A completed transfer was reported under the wrong advertisement.** The
  concluding callback passed the *first* segment's advertisement while the
  receiver's resource hash had advanced to the last, so a listener matching on
  that hash missed—the file arrived intact and was discarded as invalid.

#### Other

- **A resource-started observer was handed an unpopulated hash.** The callback
  fired before the advertisement was parsed, so `resourceHash` was still empty.
  Python calls it from inside `Resource.accept`, after the hash is assigned;
  anything keying on that value (LXMF's inbound registry does) collapsed every
  concurrent transfer onto one key.
- **A transport header was stamped on zero-hop paths.** A destination zero hops
  away is directly reachable and must go out as `HEADER_1`, even when a next-hop
  transport ID is on file—which happens for exactly one topology, a shared
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
  not called `I2PDaemon.stop()` destroyed them underneath live threads—a
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
  documented way—including the one RNS's own discovery emits—parsed to
  nothing and the interface was silently skipped.
- **`interface_discovery_sources` was only enforced when pruning stored
  records**, leaving an unauthorised peer discoverable and dialable until the
  next prune. It's now checked at announce reception, as Python does.
- **A split request or response resource delivered only its last segment.**
  Segments 2..N carry the same request/response flags and request ID as segment
  1, so the advertisement dispatch built a fresh transfer for each one. The
  caller received the tail chunk *as a successful response*—a truncated
  payload merely fails to decode as the `[request_id, response]` envelope and
  falls back to raw bytes, so this was silent corruption rather than an error,
  on the LXMF propagation-sync and NomadNet file-fetch paths. Continuation
  advertisements are now routed to the transfer holding the earlier segments.
- **A receiver parked between segments adopted unrelated advertisements.** It
  stays registered so the next segment reaches it, but the link hands every
  advertisement to every registered receiver—so a different resource
  advertised in that window was downloaded into the segment buffer and spliced
  into the middle of the delivered payload, bypassing `resourceStrategy` and
  never firing `onResourceStarted`. A transfer now accepts only its own next
  segment.
- **Sender progress was measured per segment**, so a split transfer reported
  0→1 once per segment—reaching 1.0 while still running, then going
  backwards. Python folds the segment position in; the per-segment figure is a
  separate method there (`get_segment_progress`).
- **`LocalInterface.start()` stalled for the full connect timeout when nothing
  was listening.** A refused connection surfaces as `.waiting`, not `.failed`,
  and only `.failed`/`.cancelled` released the caller—so the normal
  standalone launch paid 5 s, serialized ahead of every later interface, on the
  main thread if that's where the caller ran. `.waiting` on the initial connect
  now fails fast, as Python's blocking `socket.connect()` does.
- **A superseded connection could take down its replacement.** After any
  `stop()`/`start()`, the old connection's terminal callback still ran, marked
  the *healthy* new connection offline and scheduled a reconnect that abandoned
  it uncancelled—a leaked socket the shared instance still counted as an
  attached client, and two concurrent receive loops on one HDLC decoder. State
  callbacks now ignore a connection that's no longer the current one.

### Added—public API

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

- A Swift shared instance still can't relay between two of its own local
  clients: every client is served by one interface, and both relay paths refuse
  to send back out the interface a packet arrived on. Client-to-client traffic
  across a *Python* shared instance is unaffected.
- Announces forwarded to local clients pass their hop count through unchanged,
  matching Python's `new_announce.hops = packet.hops`—but Python's value has
  already been incremented on inbound and this port does no inbound increment.
  A destination one hop beyond a Swift shared instance therefore reads as
  directly reachable to a sibling client. Harmless with the default
  `allowLinkPathRebalance` (the first link re-balances and proceeds); with it
  disabled, such a link stays pending.

## [1.4.3]—thread-safe traffic counters and packet-handle state

Data races only, no wire-format or behavioural change. Every reported number is
computed exactly as before; the difference is that reading one no longer races
the thread writing it. Verified with `swift test --sanitize=thread` over the
full suite.

### Fixed

- **Interface traffic counters raced their readers.** `rxBytes` / `txBytes` /
  `rxPackets` / `txPackets` are written from whichever queue an interface's I/O
  runs on—CoreBluetooth's queue for `BLEMeshInterface`, an `NWConnection` queue
  for the TCP/UDP family, a serial read thread for `SerialInterface`—and read
  from another (an app polls them to draw its interface list; `rnstatus`-style
  reporting reads them from the caller's thread). `Int` isn't atomic and
  `counter += 1` is a load-modify-store, so concurrent increments silently lost
  updates and a concurrent read could observe a torn value: undefined behaviour
  under the Swift memory model, not merely an inaccurate statistic.

  This affected **thirteen** interfaces, not one. The counters now live in a
  single lock-guarded `InterfaceCounters` type that every interface holds, so
  the next interface added inherits the fix instead of rediscovering the bug.
  `I2PInterfacePeer` previously took a lock on write only, which left every
  *reader* racing regardless—it's fixed too.
- **`Link` traffic statistics raced their readers.** `tx` / `rx` / `txBytes` /
  `rxBytes` were written under `stateLock` but exposed as stored properties, so
  a reader on another thread raced every write. Now routed through the same
  guarded counters.
- **`Link.establishmentTimeout` and `Link.onTimeout` raced the watchdog.**
  `Link.initiate` starts the watchdog before returning, so the watchdog thread
  was already reading both by the time the caller assigned them on the very next
  line—which is the normal usage pattern. Both are now guarded by `stateLock`,
  matching how `status` and `teardownReason` already worked.
- **`ChannelPacketHandle.state` raced its readers.** `markDelivered()` /
  `markFailed()` wrote it under a lock, but `state` was a stored property that
  `Channel` polls via `ChannelOutlet.getPacketState` and `Link` filters its proof
  waiters on. Its `deliveredCallback` and `timeoutWork` were likewise assigned
  directly by outlets while the delivery thread cleared them under the lock;
  those now go through guarded setters.
- **`I2PInterface` always reported zero traffic.** It declared all four counters
  but never incremented them—the parent performs no I/O of its own, and every
  byte moves through a dialed or accepted peer. It now sums its peers, which is
  what the numbers were always meant to show.
- **`Interface.isOnline` raced its readers.** Every interface flips it from its
  own I/O queue (an `NWConnection` state handler, a CoreBluetooth callback, a
  serial reader) while `Transport` consults it before routing and apps read it
  for every row of an interface list. All 20 declarations across 16 files now
  sit over a lock-guarded `LockedFlag`. Because they became *computed*
  properties keeping the same access level, all 51 assignment sites are
  unchanged—the setter is simply guarded now.

### Known remaining race

- **`RNodeInterface` radio telemetry** (`rStatRssi`, `rStatSnr`,
  `rBatteryState`, `rFrequency`, …) is written on the radio read thread and read
  by UI. Deferred rather than rushed: it's entangled with the radio state
  machine, and verifying a fix needs real RNode hardware. It's also why the
  radio-parameter readout on a connected RNode can show stale values.

## [1.4.2]—bz2 compression on by default; request-timeout fix

### Fixed

- **Compressed Resources from Python peers couldn't be received.**
  `Resource.compressor` defaulted to `NoCompressor`, whose `decompress` returns
  `nil`. Python RNS bz2-compresses any resource-sized payload and sets the
  per-resource `compressed` flag, so every compressed Resource a peer sent (large
  NomadNet pages, large LXMF messages, RRC notices—anything over the link MDU)
  failed to assemble and tore the link down. The default is now `BZip2Compressor`,
  matching Python. On send, a resource is compressed only when bz2 actually
  shrinks it (the `compressed` flag records the choice), so **the wire format is
  unchanged** and stays compatible with every RNS implementation. `StreamDataMessage.compressor`
  (Buffer streams) likewise defaults to `BZip2Compressor`; compression on send
  there remains opt-in per write. Install `NoCompressor()` / `nil` to opt out.
- **A request whose response arrived as a Resource could time out mid-transfer.**
  A link request armed a single fixed-timeout timer that fired `fail("timeout")`
  unconditionally at `sentAt + timeout`; when the response came back as a Resource
  (any multi-KB payload—for example, a real NomadNet page), the timer fired while the
  transfer was still in flight and tore the link down. Following Python
  (`RequestReceipt.response_resource_progress`), the request timeout is now
  disarmed the moment the response enters RECEIVING, handing the transfer's
  lifetime to the Resource's own watchdog. A stalled transfer still concludes the
  receipt via the transfer's failure hook. Fixes NomadNet "pages won't load" for
  real pages over slower / multi-hop meshes.

## [1.4.1]—correct the reported library version

### Fixed

- **`Reticulum.version` was stuck at `"0.1.0"`.** The constant was never bumped
  past the initial value, so `rnsd --version` and RetiOS's Settings ▸ About both
  reported "ReticulumSwift 0.1.0" despite the package being released through
  1.4.0. It now reports the real release version. (`version` is informational
  only—it never travels on the wire.)

### Added

- **`Reticulum.rnsProtocolVersion`**—the Python RNS release whose wire protocol
  this port matches (currently `"1.4.0"`), kept distinct from the library's own
  release `version`. Mirrors Python's single `RNS.__version__` as a parity
  reference.

## [1.4.0]—large link packets, response Resources & RNS 1.4.0 parity

### Fixed

- **Inbound link packets larger than the base MTU were silently dropped.**
  `Packet.pack()` enforces a 500-byte (`Constants.mtu`) transmit cap, and
  `Packet.hashablePart()` computed the packet hash through `pack()`—so hashing
  threw for any packet over 500 B, and `Transport.filterAndRecord()` treated the
  failed hash as a duplicate and dropped the packet before it reached
  `Link.receive`. Because links negotiate their MTU upward (a TCP link commonly
  reaches 8192), a peer legitimately sends single link packets far larger than
  500 B—for example, a NomadNet node serving any real page. **Every such packet was
  discarded**, so browsing NomadNet pages timed out. Packet identity and byte
  accounting are now MTU-independent (new `Packet.packedBytes()`), matching Python
  (`get_hashable_part` slices the already-packed bytes; only `pack()` checks the
  MTU). (bugs/010)
- **Over-MDU request responses sent as Resources used the wrong payload envelope.**
  The responder resourced the bare response value and the initiator delivered it
  un-decoded, so a large response either arrived msgpack-wrapped (Swift↔Swift) or
  timed out (a Python fetcher's `unpackb([id, response])` threw). Both sides now
  use the `[request_id, response]` envelope—identical to the single-packet path—matching
  Python `Link.handle_request` / `response_resource_concluded`. (bugs/011)

### Changed—RNS 1.4.0 parity

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

## [1.0.0]—initial public release

First public release of ReticulumSwift—a from-scratch Swift port of the
[Reticulum Network Stack](https://reticulum.network), wire-compatible with the
Python reference implementation (RNS 1.3.0).

### Highlights

- **Cryptography**—Curve25519 (X25519 + Ed25519), HMAC-SHA256, HKDF, SHA-256/512
  via CryptoKit; AES-CBC + PKCS#7 via CommonCrypto; Reticulum Token.
- **Identity / Destination / Packet / Announce**—byte-identical wire format.
- **Transport**—routing, path table, announce relaying and dedup, ratchet
  rotation/learning, blackholing, announce rate-limiting, multi-hop links.
- **Link**—full handshake, keepalive, MTU signalling, request/response.
- **Resource**—segmented transfers with hashmap-windowed retransmit.
- **Channel / Buffer**—reliable ordered messaging and stream wrappers.
- **Interfaces**—TCP client/server, UDP, AutoInterface (mDNS), Backbone,
  Local, RNode (+ RNodeMulti), I2P (embedded i2pd), Serial, KISS, AX.25 KISS,
  Weave. (PipeInterface is intentionally out of scope on Apple platforms.)
- **`rnsd`**—a Reticulum daemon executable, config-compatible with Python's.
- **IFAC**—deterministic Ed25519, wire-compatible with Python's pure25519.

Covered by 2,145 unit tests (~78% line coverage) plus a live Python↔Swift
interoperability suite.
