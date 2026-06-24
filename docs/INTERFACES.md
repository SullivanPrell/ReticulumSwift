# Interfaces

An *interface* is how a Reticulum node moves packets over a physical or virtual
medium. ReticulumSwift implements every standard Reticulum interface, each
wire-compatible with its Python counterpart, so a config that works with Python
`rnsd` works here too.

Interfaces can be brought up two ways:

- **From config** — declared in the `[interfaces]` section of the INI config and
  synthesized by `rnsd` / `Reticulum.synthesizeInterfaces(from:)`.
- **Programmatically** — instantiated and registered on `Transport`:
  ```swift
  let tcp = TCPClientInterface(name: "hub", host: "example.com", port: 4242)
  stack.transport.register(interface: tcp)
  try tcp.start()
  ```

## Support matrix

| Interface | Status | Typical use |
|-----------|--------|-------------|
| `TCPClientInterface` | ✅ | Dial a remote hub / node over TCP |
| `TCPServerInterface` | ✅ | Accept inbound TCP connections |
| `UDPInterface` | ✅ | LAN broadcast / unicast, one packet per datagram |
| `AutoInterface` | ✅ | Zero-config LAN discovery (IPv6 multicast) |
| `BackboneInterface` | ✅ | High-bandwidth TCP backbone links |
| `LocalInterface` | ✅ | Shared-instance loopback between processes |
| `RNodeInterface` | ✅ | LoRa via RNode hardware (BLE / serial) |
| `RNodeMultiInterface` | ✅ | Multiple sub-interfaces on one RNode |
| `I2PInterface` | ✅ | Anonymous transport over I2P (embedded i2pd) |
| `SerialInterface` | ✅ | Raw serial links |
| `KISSInterface` | ✅ | KISS TNCs |
| `AX25KISSInterface` | ✅ | AX.25 over KISS |
| `WeaveInterface` | ✅ | Weave links |
| `PipeInterface` | ⏭ not supported | POSIX subprocess pipes — no Apple-platform use case |

## Common config example

```ini
[interfaces]

  [[Default Interface]]
    type = AutoInterface
    enabled = Yes

  [[TCP Hub]]
    type = TCPClientInterface
    enabled = Yes
    target_host = dublin.connect.reticulum.network
    target_port = 4965

  [[My TCP Server]]
    type = TCPServerInterface
    enabled = Yes
    listen_ip = 0.0.0.0
    listen_port = 4242

  [[LAN UDP]]
    type = UDPInterface
    enabled = Yes
    listen_ip = 0.0.0.0
    listen_port = 4242
    forward_ip = 255.255.255.255
    forward_port = 4242
```

Every interface accepts the standard Reticulum knobs where applicable:
`enabled`, `interface_enabled`, `mode` (`full` / `gateway` / `access_point` /
`roaming` / `boundary`), `bitrate`, `announce_cap`, and IFAC settings
(`network_name`, `passphrase`, `ifac_size`). `ifac_size` is specified in **bits**.

## Platform notes

- **I2P** runs an embedded i2pd daemon (the `CI2PD` binary in `Resources/`).
  Outbound peer dialing (b32 / base64) is fully supported. The i2pd runtime
  initializes on macOS and iOS; see [docs/THIRD-PARTY.md](THIRD-PARTY.md) for the
  bundled-binary licensing.
- **RNode** interfaces require an `RNodeTransport` adapter that the host app
  supplies (e.g. a CoreBluetooth Nordic-UART transport, or a USB serial
  transport). The radio state machine lives in `RNodeInterface`; I/O is
  delegated to the transport, so the same interface drives BLE and USB radios.

For interface internals and the `Interface` protocol, see
[docs/ARCHITECTURE.md](ARCHITECTURE.md).
