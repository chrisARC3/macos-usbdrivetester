#!/bin/zsh
# run_waves.sh [first-wave] — the waves of assign.tsv in order, each wave's runs in parallel. A wave
# that holds one run per arm keeps a limit or an outage from falling on one arm alone. Stops after
# any wave in which a run ended without a clean result line (an error, a session limit, no result at
# all). Then move that wave's copies and outputs into out/, where no session can read them, re-make
# the copies, probe, and start again from that wave.
set -uo pipefail
HERE=${0:A:h}; source $HERE/common.sh
first=${1:-1}
ok() {  # every named run has a result line that is not an error
  for r in "$@"; do
    [[ -e $OUT/$r.end ]] || { print "STOP: $r has no end marker"; return 1 }
    python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; r=[o for o in r if o.get("type")=="result"]; sys.exit(0 if r and not r[-1].get("is_error") else 1)' $OUT/$r.jsonl \
      || { print "STOP: $r ended without a clean result"; return 1 }
  done
}
for w in $(awk -F'\t' 'NR > 1 { print $3 }' $HERE/assign.tsv | sort -nu); do
  (( w < first )) && continue
  runs=($(awk -F'\t' -v w=$w 'NR > 1 && $3 == w { print $1 }' $HERE/assign.tsv))
  print "wave $w ($runs) at $(date +%T)"
  for r in $runs; do $HERE/run_one.sh $r & done
  wait
  ok $runs || exit 5
done
print "every wave clean at $(date +%T)"
