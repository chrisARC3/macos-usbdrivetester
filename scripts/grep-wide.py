#!/usr/bin/env python3
#
# grep-wide.py — grep the live documents and sources for a claim, across line breaks, so a status
# claim is found in every place it is written and not only where it happens to sit on one line.
#
# WHY THIS EXISTS
#
# CLAUDE.md's rule for retiring a claim is to grep for it in every wording, the sources and their
# doc comments included. Almost no claim in these files sits on one line: prose is filled to about
# 100 columns, inside `>` quotes and `///` comments, so "green 2026-09-24 on `77275be`'s sources"
# can break at any space and `grep` finds neither half. This joins each file's lines, drops each
# line's leading `>`, `//`, `///`, `*` and `#` markers, collapses every run of whitespace to one
# space, and matches each PATTERN against the result as a case-insensitive Python regex — so
# `.{0,300}` reaches across lines, and a hit reports the line its match starts on.
#
# It began 2026-09-29 as grep-wide-root.py in a session scratchpad under /private/tmp, and the greps
# recorded in 670c8f5, c2f193d and 331ba6a were made with it, over a fixed list of 194 files: 14
# documents and 180 sources. It moved here 2026-09-30, before a restart that would have wiped it.
# The one change is where the list comes from: `git ls-files`, read each run, so a file is searched
# from the day it is tracked. At 331ba6a it searched the same 194 files as the scratchpad version,
# and its output was byte-identical in seventeen runs, among them every count 331ba6a records.
#
# WHAT IT SEARCHES
#
#   --docs   every tracked .md except claude-md-test/, a test's fixtures that are stale on purpose,
#            and the archived progress/step-NN.md records, which say what was true and are left
#            alone. The checklists, progress/step-NN-human-checklist.md, are searched.
#   --srcs   every tracked .swift, .sh, .py, .plist, .txt, .json and .strings file except
#            claude-md-test/ and this script, whose own patterns would otherwise find themselves.
#   neither  both.
#
# It reads the working tree, not the index, so an edit is searched before it is committed; a file
# not yet tracked is not searched at all.
#
# OUTPUT
#
#   path:line: [pattern] …context…    one line per hit, the path relative to the repository root
#   == N hit(s) over M file(s)         on stderr, every run
#
# ⚠️ A count of 0 is a finding only beside a positive control: a pattern that must hit, run the same
# way over the same files (CLAUDE.md, *How to grep*). The exit status is 0 whatever the count, as it
# was in the scratchpad; 2 is a usage error.
#
# USAGE
#
#   scripts/grep-wide.py [--docs | --srcs] PATTERN...
#
# from any directory. Quote each PATTERN for the shell; several run in one pass over the files.

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SELF = os.path.relpath(os.path.abspath(__file__), ROOT)

args = sys.argv[1:]
only = args.pop(0) if args and args[0] in ('--docs', '--srcs') else None
if not args:
    print('usage: scripts/grep-wide.py [--docs | --srcs] PATTERN...', file=sys.stderr)
    sys.exit(2)

tracked = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT, check=True,
                         capture_output=True).stdout.decode('utf-8').split('\0')
docs = [f for f in tracked if f.endswith('.md') and not f.startswith('claude-md-test/')
        and not re.fullmatch(r'progress/step-\d\d\.md', f)]
srcs = [f for f in tracked if re.search(r'\.(swift|sh|py|plist|txt|json|strings)$', f)
        and not f.startswith('claude-md-test/') and f != SELF]
files = (docs if only != '--srcs' else []) + (srcs if only != '--docs' else [])

marker = re.compile(r'^\s*(>\s?|///?\s?|\*\s?|#\s?)+')
total = 0
for f in files:
    try:
        raw = open(os.path.join(ROOT, f), encoding='utf-8').read()
    except (FileNotFoundError, UnicodeDecodeError):
        continue
    lines = raw.split('\n')

    # Each line without its markers, joined by one space; `where` maps every character kept back to
    # its offset in `raw`, so a match in the flattened text still knows its line.
    starts, offset = [], 0
    for line in lines:
        starts.append(offset)
        offset += len(line) + 1
    chars, where = [], []
    for i, line in enumerate(lines):
        m = marker.match(line)
        cut = m.end() if m else 0
        for j, ch in enumerate(line[cut:]):
            chars.append(ch)
            where.append(starts[i] + cut + j)
        chars.append(' ')
        where.append(starts[i] + len(line))

    # Every run of whitespace down to one space.
    out, kept, in_space = [], [], False
    for ch, pos in zip(chars, where):
        if ch.isspace():
            if in_space:
                continue
            in_space = True
            out.append(' ')
            kept.append(pos)
        else:
            in_space = False
            out.append(ch)
            kept.append(pos)
    flat = ''.join(out)

    for pattern in args:
        for m in re.finditer(pattern, flat, flags=re.I):
            total += 1
            line_number = raw.count('\n', 0, kept[m.start()]) + 1
            context = flat[max(0, m.start() - 90):m.end() + 60]
            print(f'{f}:{line_number}: [{pattern}] …{context}…')

print(f'== {total} hit(s) over {len(files)} file(s)', file=sys.stderr)
