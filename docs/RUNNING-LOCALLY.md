# Running ReticulumSwift locally

This guide takes you from a fresh checkout to a running Reticulum node that
talks to other nodes — including Python ones.

## 1. Prerequisites

- **Xcode 15+** (or the Swift 5.9+ toolchain) on macOS.
- Clone the repo. The prebuilt i2pd binary (~90 MB) is committed directly, so a
  normal clone is all you need:
  ```sh
  git clone https://github.com/SullivanPrell/ReticulumSwift.git
  cd ReticulumSwift
  ```

## 2. Build & test

```sh
swift build                 # debug build
swift build -c release      # optimized
swift test                  # runs the full test suite
```

> Hitting `SwiftShims` module-cache errors? `rm -rf .build && swift test`.

## 3. Run the `rnsd` daemon

`rnsd` is a Reticulum node daemon. It is configuration-compatible with Python's
`rnsd`, and uses the same default config directory:

```sh
swift run rnsd              # uses ~/.reticulum/config
swift run rnsd -d /path/to/configdir
swift run rnsd -c /path/to/config -v     # alternate config file + info logging
swift run rnsd --help
```

On first run, if no config exists at `~/.reticulum/config`, `rnsd` writes a
default one and starts with sane defaults. It will:

- create `~/.reticulum/storage/` for identity, path table, and ratchet state;
- if `share_instance` is enabled, bind the **shared-instance** port `37428` and
  the **RPC** port `37429` (same as Python — so a Python `rnsd` and a Swift
  `rnsd` will not both try to be the shared instance);
- bring up every interface declared in the config file.

## 4. Configuration

The config file is the same INI format as Python Reticulum. A minimal config
that joins the public testnet over TCP looks like:

```ini
[reticulum]
  enable_transport = No
  share_instance = Yes

[logging]
  loglevel = 4

[interfaces]

  [[Default Interface]]
    type = AutoInterface
    enabled = Yes

  [[RNS Testnet Dublin]]
    type = TCPClientInterface
    enabled = Yes
    target_host = dublin.connect.reticulum.network
    target_port = 4965
```

- `AutoInterface` discovers peers on your LAN over IPv6 multicast — two nodes on
  the same network find each other with no further config.
- A `TCPClientInterface` reaches a remote hub or another node over the internet.

See [docs/INTERFACES.md](INTERFACES.md) for every interface type and its options.

## 5. Two nodes on one machine

To watch routing happen locally, run two daemons with separate config dirs:

```sh
swift run rnsd -d ~/.reticulum-a &
swift run rnsd -d ~/.reticulum-b &
```

Give each an `AutoInterface` (they will discover each other on the loopback /
LAN), or point a `TCPClientInterface` in one at a `TCPServerInterface` in the
other. With `-v` you will see announces propagate between them.

## 6. Talking to a Python node

Because ReticulumSwift is wire-compatible, a Python `rnsd` and a Swift `rnsd`
interoperate directly — put them on the same `AutoInterface` LAN, or connect one
to the other over TCP. Announces, links, and resource transfers cross the
boundary transparently. See [docs/INTEROP.md](INTEROP.md) for details and for how
the project verifies this automatically.

## 7. Using the library instead of the daemon

`rnsd` is a thin wrapper around the library. For embedding the stack in your own
app, see the **Quick start** in the [README](../README.md) and
[docs/ARCHITECTURE.md](ARCHITECTURE.md).
