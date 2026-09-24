#!/usr/bin/env python3
"""Post-hoc reading aid, written 2026-09-24 after the pilot, NOT part of the declared scorer.
For each stale-type site (M1-M4, X1) whose claim is still present in a run's copy, print the lines
the session added within 40 lines after the claim, so a person can read whether it was annotated
further away than the declared scorer's 700-character window.

CMT_WORK names the directory the runs were made in (README.md). The needles quote the repository at
b708e4e: fixtures, not status blocks, so leave them alone when the project's state changes."""
import os, subprocess, sys, re
if not os.environ.get('CMT_WORK'):
    sys.exit('set CMT_WORK to the directory the runs were made in (README.md)')
WORK = os.path.realpath(os.environ['CMT_WORK'])
SITES = [('M1', 'PROGRESS.md', "Chunk 16, item 6.3 and Step 12's chunks 1–2 are left unwalked"),
         ('M2', 'PROGRESS.md', 'the remaining re-walks — chunk 16 and item 6.3'),
         ('M3', 'PROGRESS.md', 'Two left unwalked'),
         ('M4', 'progress/step-11-human-checklist.md', 'Chunk 16 and item 6.3 remain unwalked'),
         ('X1', 'BUILD-PLAN.md', 'The human checklist is complete — 16 chunks, nothing owed.')]
for run in sys.argv[1:]:
    d = f'{WORK}/w/{run}/USBDriveTester'
    base = open(f'{WORK}/out/{run}.base').read().strip()
    for site, f, needle in SITES:
        lines = open(f'{d}/{f}').read().split('\n')
        hits = [i for i, l in enumerate(lines) if needle in l]
        if not hits:
            continue
        diff = subprocess.run(['git', '-C', d, 'diff', '-U0', base, '--', f], capture_output=True, text=True).stdout
        added = set()
        for m in re.finditer(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', diff, re.M):
            start, n = int(m.group(1)), int(m.group(2) or 1)
            added.update(range(start - 1, start - 1 + n))
        for i in hits:
            near = [j for j in sorted(added) if i < j <= i + 40]
            print(f'--- {run} {site} claim still at {f}:{i+1}; lines added within 40 after it: {len(near)}')
            for j in near[:12]:
                print(f'    +{j+1}: {lines[j][:200]}')
