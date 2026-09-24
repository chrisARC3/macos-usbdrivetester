#!/bin/zsh
# chain.sh — after wave 1 (r07 r02, plus the pilot r04) has ended, run waves 2 and 3 in order.
# Stops before a wave if any run of the previous one ended in an error result or no result.
S=/private/tmp/claude-501/-Volumes-1TB-UGreen-AI-Stuff-claude-code-folder-USBDriveTester/9b3706ab-cf2e-4a65-9796-e2d7dba5cabb/scratchpad
O=$S/f4test/out
ok() {  # every named run has a result line that is not an error
  for r in "$@"; do
    [[ -e $O/$r.end ]] || return 1
    python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; r=[o for o in r if o.get("type")=="result"]; sys.exit(0 if r and not r[-1].get("is_error") else 1)' $O/$r.jsonl \
      || { echo "STOP: $r ended without a clean result"; return 1 }
  done
}
for i in {1..240}; do [[ -e $O/r07.end && -e $O/r02.end ]] && break; sleep 5; done
ok r04 r07 r02 || exit 5
echo "wave 1 clean; wave 2 at $(date +%T)"
$S/f4test/run_wave.sh r05 r01 r09
ok r05 r01 r09 || exit 5
echo "wave 2 clean; wave 3 at $(date +%T)"
$S/f4test/run_wave.sh r08 r06 r03
ok r08 r06 r03 || exit 5
echo "wave 3 clean at $(date +%T)"
