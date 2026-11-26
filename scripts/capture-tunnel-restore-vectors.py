#!/usr/bin/env python3
"""Print what Python's Transport.handle_tunnel does with each tunnel path, as JSON.

Captured from RNS 1.6.1 for `TunnelPathRestoreTests`. It fills `Transport.tunnels` and
`Transport.path_table` per case, calls `handle_tunnel` for a known tunnel without starting
`Reticulum`, and prints whether the path table took the tunnel's path, the table's hop count
afterwards, and whether the path stayed in the tunnel. Hops are Python's count, `IDX_PT_HOPS`.
`handle_tunnel` never reads the interface, so a local-client interface gives the same result as
any other and has no case of its own.

Usage: <reticulum-interop>/.venv/bin/python -I scripts/capture-tunnel-restore-vectors.py
"""
import json
import os
import time

import RNS
from RNS.Transport import Transport


class _Interface:
    tunnel_id = None

    def __str__(self):
        return "Stub"


def _blob(emitted):
    return os.urandom(5) + int(emitted).to_bytes(5, "big")


def _entry(hops, expires, emitted, interface):
    return [time.time(), os.urandom(16), hops, expires, [_blob(emitted)], interface, os.urandom(32), None]


now = time.time()
later = now + 3600
CASES = {
    # name: (tunnel path hops, tunnel path expired, table path hops or None, table expired, table newer)
    "absent": (2, False, None, False, False),
    "absent_expired": (2, True, None, False, False),
    "more_hops_in_table": (2, False, 4, False, False),
    "fewer_hops_in_table": (3, False, 1, False, False),
    "fewer_hops_in_table_expired": (3, False, 1, True, False),
    "newer_table_announce": (2, False, 4, False, True),
    "equal_hops_equal_timebase": (2, False, 2, False, False),
}

print(f"RNS {RNS.__version__}")
results = {}
for name, (hops, tunnel_expired, table_hops, table_expired, table_newer) in CASES.items():
    destination = os.urandom(16)
    tunnel_id = os.urandom(32)
    tunnel_path = _entry(hops, now - 1 if tunnel_expired else later, now, None)
    Transport.tunnels = {tunnel_id: [tunnel_id, None, {destination: tunnel_path}, later]}
    Transport.path_table = {}
    if table_hops is not None:
        Transport.path_table[destination] = _entry(
            table_hops, now - 1 if table_expired else later, now + 100 if table_newer else now, object())
    Transport.handle_tunnel(tunnel_id, _Interface())
    entry = Transport.path_table.get(destination)
    results[name] = {
        "restored": entry is not None and entry[2] == hops and isinstance(entry[5], _Interface),
        "table_hops": None if entry is None else entry[2],
        "in_tunnel": destination in Transport.tunnels[tunnel_id][2],
    }
print(json.dumps(results, indent=1, sort_keys=True))
