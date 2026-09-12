#!/usr/bin/env python3
"""Apply or verify the repository license header on every source file.

The template is `scripts/license-header.txt`; `${year}` is filled with the current
year at apply time so the attribution cannot go stale. Generated sources and build
directories are excluded. Run with --check to verify without writing.
"""
import argparse
import datetime
import os
import re
import sys

EXTENSIONS = (".swift", ".h", ".c", ".cpp", ".m", ".mm", ".sh")
EXCLUDE_DIRS = {".build", ".build-linux", ".git", ".swiftpm", "checkouts", "Pods",
                "DerivedData", "build", ".spm", ".spm-local", ".vale", ".trunk", ".dd",
                ".dd-ios", ".dd-mac", "Frameworks", "node_modules", "__pycache__"}
EXCLUDE_SUFFIXES = (".pb.swift", ".grpc.swift")
BANNER = "//===---"
MARKER = "SPDX-License-Identifier: LicenseRef-Reticulum"


def template(root):
    path = os.path.join(root, "scripts", "license-header.txt")
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    return text.replace("${year}", str(datetime.date.today().year))


def sources(root, roots):
    for top in roots:
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, top)):
            dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
            for name in sorted(filenames):
                if not name.endswith(EXTENSIONS):
                    continue
                if name.endswith(EXCLUDE_SUFFIXES):
                    continue
                yield os.path.join(dirpath, name)


def has_header(text):
    return MARKER in text[:2000]


def strip_stale_header(text):
    """Remove a previously applied banner block so the year can be refreshed."""
    match = re.match(r"(?:#![^\n]*\n)?(//===-+===//\n(?://[^\n]*\n)*?//===-+===//\n)", text)
    if match and MARKER in match.group(1):
        start, end = match.span(1)
        return text[:start] + text[end:].lstrip("\n")
    return text


def apply(path, header, check):
    with open(path, encoding="utf-8") as handle:
        original = handle.read()
    if not original.strip():
        return False
    comment = header if not path.endswith(".sh") else header.replace("//", "#")
    body = strip_stale_header(original)
    shebang = ""
    if body.startswith("#!"):
        shebang, _, body = body.partition("\n")
        shebang += "\n"
        body = body.lstrip("\n")
    updated = shebang + comment + "\n" + body
    if updated == original:
        return False
    if not check:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(updated)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report, change nothing")
    parser.add_argument("roots", nargs="*", default=None,
                        help="directories to walk, relative to the repository root")
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    roots = args.roots or [d for d in ("Sources", "Tests", "scripts") if os.path.isdir(os.path.join(root, d))]
    header = template(root)

    changed = [path for path in sources(root, roots) if apply(path, header, args.check)]
    if args.check and changed:
        print(f"{len(changed)} file(s) missing or holding a stale license header:", file=sys.stderr)
        for path in changed[:20]:
            print("  " + os.path.relpath(path, root), file=sys.stderr)
        if len(changed) > 20:
            print(f"  ... and {len(changed) - 20} more", file=sys.stderr)
        return 1
    print(f"{len(changed)} file(s) updated." if not args.check else "License headers are current.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
