#!/bin/zsh
# check_sandbox.sh <run-id> <profile> — the profile's controls, which run_one.sh runs before every
# session. A profile that refuses nothing gives streams that read exactly like one that works, so
# each denial has to be seen failing with "Operation not permitted", and each thing the session
# needs has to be seen working. On 2026-09-24 three of them were run once, by hand: the repository,
# another run's copy and log.
set -uo pipefail
HERE=${0:A:h}; source $HERE/common.sh
run=$1 sb=$2
dir=$WORK/w/$run/USBDriveTester
bad=0
denied() {  # denied <what> <command ...>: must fail, and on the sandbox rather than anything else
  local what=$1 err; shift
  if err=$(sandbox-exec -f $sb "$@" 2>&1 >/dev/null); then
    print -u2 "  NOT DENIED   $what"; bad=1
  elif [[ $err == *'Operation not permitted'* ]]; then
    print "  denied       $what"
  else
    print -u2 "  NO CONTROL   $what: failed, but not on the sandbox: ${err//$'\n'/ }"; bad=1
  fi
}
allowed() {  # allowed <what> <command ...>: must succeed
  local what=$1; shift
  if sandbox-exec -f $sb "$@" >/dev/null 2>&1; then print "  allowed      $what"
  else print -u2 "  NOT ALLOWED  $what"; bad=1; fi
}

denied 'read the repository' /bin/cat $REAL/CLAUDE.md
denied 'read this harness' /bin/cat $HERE/assign.tsv
denied 'list the outputs' /bin/ls $OUT
typeset -U transcripts
transcripts=($(project_dir $REAL) $HOME/.claude/projects/-Volumes-*-${REAL:t}(/N))
for p in $transcripts; do [[ -d $p ]] && denied "list the transcripts in ${p:t}" /bin/ls $p; done
for d in $WORK/w/*(/N); do [[ ${d:t} != $run ]] && denied "list run ${d:t}'s copy" /bin/ls $d; done
for p in ${(s.:.)CMT_DENY:-}; do denied "list $p" /bin/ls $p; done
denied 'run log' /usr/bin/log help
allowed 'read its own copy' /bin/cat $dir/CLAUDE.md
allowed 'write in its own copy' /usr/bin/touch $dir/.git/cmt-sandbox-probe
rm -f $dir/.git/cmt-sandbox-probe
exit $bad
