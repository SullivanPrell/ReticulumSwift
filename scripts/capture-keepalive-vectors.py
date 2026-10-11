#!/usr/bin/env python3
"""Print the raw link keepalive packets Python RNS packs, as hex.

Captured from RNS 1.5.5 for `KeepaliveWireTests`. Python packs a KEEPALIVE
context packet without encryption (`Packet.py:209-212`), so the bytes depend
only on the link ID. The link ID here is 0x00 through 0x0f.

Usage: <reticulum-interop>/.venv/bin/python -I scripts/capture-keepalive-vectors.py
"""
import RNS
from RNS.Packet import Packet


class _Link:
    type = RNS.Destination.LINK
    hash = bytes(range(16))
    mtu = RNS.Reticulum.MTU


print(f"RNS {RNS.__version__}")
for byte in (0xFF, 0xFE):
    packet = Packet(_Link(), bytes([byte]), context=Packet.KEEPALIVE)
    packet.pack()
    print(f"{byte:#04x} {packet.raw.hex()}")
