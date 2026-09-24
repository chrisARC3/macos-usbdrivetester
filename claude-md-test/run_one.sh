#!/bin/zsh
# run_one.sh <run-id> [--probe] — one headless session in that run's private copy, inside a sandbox
# that keeps it off the real repository, the drives, /Applications, the machine's live state, every
# output and every other run's copy. --probe sends probe.txt instead of the staged request, at low
# effort, and writes <run>.probe.*: a cheap check of the login, the session limit and the sandbox
# before a wave.
set -uo pipefail
HERE=${0:A:h}; source $HERE/common.sh
run=$1 probe=${2:-}
dir=$WORK/w/$run/USBDriveTester
out=$OUT/$run${probe:+.probe}
[[ -d $dir ]] || { print -u2 "no copy for $run: make_clone.sh $run <arm> first"; exit 1 }
[[ -e $out.jsonl ]] && { print -u2 "already ran: $out.jsonl"; exit 1 }
[[ -x $CLI ]] || { print -u2 "no CLI at $CLI: set CMT_CLI"; exit 3 }
# A logged-out CLI would spend a run on an auth error; refuse before any output exists.
"$CLI" auth status 2>/dev/null | grep -q '"loggedIn": true' \
  || { print -u2 "the CLI is not logged in: run  claude auth login  first"; exit 3 }
# Every session starts with empty auto-memory. A copy's path is its project's key, so a CMT_WORK
# used before could hand a run whatever an earlier run wrote there.
mem=$(project_dir $dir)/memory
[[ -n $(ls -A $mem 2>/dev/null) ]] && { print -u2 "$mem is not empty: use a fresh CMT_WORK"; exit 3 }

$HERE/sandbox_profile.sh $run > $out.sb || exit 4
if ! $HERE/check_sandbox.sh $run $out.sb > $out.sandbox-check 2>&1; then
  cat $out.sandbox-check >&2
  print -u2 "$run: the sandbox failed its controls, so no session was started"
  exit 4
fi

if [[ -n $probe ]]; then
  cp $HERE/probe.txt $out.request; secs=300; budget=1; effort=low
else
  # Only the text after the scissors line goes to the session. The header above it says the walk
  # is staged, and it must never reach one.
  sed '1,/^--- 8< ---$/d' $HERE/staged-request.txt > $out.request
  [[ $(shasum -a 256 < $out.request | cut -d' ' -f1) == $(sed -n 's/^body sha256: //p' $HERE/staged-request.txt) ]] \
    || { print -u2 "the request body is not the one staged-request.txt names"; exit 4 }
  secs=2400; budget=30; effort=$EFFORT
fi

ALLOWED="Read,Grep,Glob,Edit,Write,MultiEdit,TodoWrite,Bash(grep *),Bash(egrep *),Bash(rg *),Bash(git *),Bash(sed *),Bash(awk *),Bash(wc *),Bash(head *),Bash(tail *),Bash(cat *),Bash(ls *),Bash(ls),Bash(find *),Bash(date *),Bash(date),Bash(diff *),Bash(sort *),Bash(uniq *),Bash(cut *),Bash(tr *),Bash(nl *),Bash(stat *),Bash(shasum *),Bash(python3 *),Bash(echo *),Bash(printf *),Bash(pwd),Bash(cmp *),Bash(file *),Bash(cd *),Bash(basename *),Bash(dirname *),Bash(xargs *)"

date +%F > $out.date
"$CLI" --version > $out.version 2>&1
print -r -- "$MODEL effort=$effort" > $out.model
date '+%F %T' > $out.start
cd $dir
env DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  sandbox-exec -f $out.sb \
  perl -e 'alarm shift; exec @ARGV or die "exec: $!"' $secs \
  "$CLI" -p \
    --model $MODEL --effort $effort \
    --output-format stream-json --verbose \
    --strict-mcp-config --setting-sources project,local \
    --settings '{"agentPushNotifEnabled":false,"inputNeededNotifEnabled":false}' \
    --no-session-persistence --max-budget-usd $budget \
    --permission-mode acceptEdits \
    --allowedTools "$ALLOWED" \
    --debug-file $WORK/w/$run/cli-debug${probe:+-probe}.txt \
  < $out.request > $out.jsonl 2> $out.err
rc=$?
date '+%F %T' > $out.end
mv $WORK/w/$run/cli-debug${probe:+-probe}.txt $out.debug 2>/dev/null
print -r -- "$run${probe:+ (probe)} rc=$rc $(tail -c 300 $out.jsonl | tr -d '\n' | grep -o '"result":"[^"]\{0,120\}')"
