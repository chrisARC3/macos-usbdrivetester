#!/bin/zsh
# run_wave.sh <run-id> [<run-id> ...] — the given runs in parallel; returns when all have finished.
S=/private/tmp/claude-501/-Volumes-1TB-UGreen-AI-Stuff-claude-code-folder-USBDriveTester/9b3706ab-cf2e-4a65-9796-e2d7dba5cabb/scratchpad
for r in "$@"; do $S/f4test/run_one.sh $r & done
wait
