#!/usr/bin/env python3
"""Prove a style sweep touched only comments.

Strips every comment from the HEAD version and the working-tree version of each file
and compares what remains. Any difference means a transform reached actual code.
"""
import subprocess, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stylefix import swift_comment_spans

def strip(text):
    out, last = [], 0
    for s, e in swift_comment_spans(text):
        # swift_comment_spans returns the comment body, not its delimiters. Widen each
        # span over them, or adding and removing whole comment lines shows up here as a
        # code difference: the `//` markers would survive into the compared text.
        if text[s - 2:s] == '/*':
            s -= 2
            if text[e:e + 2] == '*/':
                e += 2
        else:
            while s > 0 and text[s - 1] == '/':
                s -= 1
        out.append(text[last:s]); last = e          # drop the comment
    out.append(text[last:])
    # Collapse whitespace: comment removal changes trailing space, never code tokens.
    return ' '.join(''.join(out).split())

bad = checked = 0
for path in sys.argv[1:]:
    if not path.endswith('.swift'):
        continue
    try:
        head = subprocess.run(['git', 'show', f'HEAD:{path}'], capture_output=True,
                              text=True, check=True).stdout
    except subprocess.CalledProcessError:
        continue                                    # new file, nothing to compare
    cur = open(path, encoding='utf-8').read()
    checked += 1
    if strip(head) != strip(cur):
        print(f"CODE CHANGED: {path}"); bad += 1

print(f"\nverified {checked} files; {bad} with code differences")
sys.exit(1 if bad else 0)
