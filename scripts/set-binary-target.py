#!/usr/bin/env python3
"""Rewrite a Package.swift `.binaryTarget(name: "<NAME>", ...)` to the remote
url+checksum form. Idempotent: works whether the target currently uses `path:`
or already uses `url:`/`checksum:`. Used by the build-binaries workflow after it
publishes a release asset.

Usage: set-binary-target.py <NAME> <URL> <CHECKSUM> [Package.swift]
"""
import re
import sys
import pathlib

if len(sys.argv) < 4:
    sys.exit("usage: set-binary-target.py <NAME> <URL> <CHECKSUM> [Package.swift]")

name, url, checksum = sys.argv[1], sys.argv[2], sys.argv[3]
pkg = pathlib.Path(sys.argv[4] if len(sys.argv) > 4 else "Package.swift")
text = pkg.read_text()

# binaryTarget args contain no nested parens, so match up to the first ")".
pattern = re.compile(
    r'\.binaryTarget\(\s*name:\s*"' + re.escape(name) + r'"[^)]*?\)',
    re.DOTALL,
)
replacement = (
    '.binaryTarget(\n'
    f'            name: "{name}",\n'
    f'            url: "{url}",\n'
    f'            checksum: "{checksum}"\n'
    '        )'
)
new_text, n = pattern.subn(replacement, text)
if n != 1:
    sys.exit(f"error: expected exactly one binaryTarget named {name!r}, found {n}")
pkg.write_text(new_text)
print(f"updated binaryTarget {name} -> {url} (checksum {checksum[:12]}…)")
