#!/bin/zsh
# run_one.sh <run-id> [--probe]
# One headless session in that run's private copy, inside a sandbox that keeps it off the real
# repository, the drives, /Applications, the machine's live state and every other run's copy.
# --probe sends a one-word prompt instead of the staged request and writes to <run>.probe.*
set -uo pipefail
S=/private/tmp/claude-501/-Volumes-1TB-UGreen-AI-Stuff-claude-code-folder-USBDriveTester/9b3706ab-cf2e-4a65-9796-e2d7dba5cabb/scratchpad
H=/Users/christopherkarr
# The desktop app's own copy of the CLI. ~/.local/bin/claude is 2.1.246, which claude-opus-5-5
# refuses (400: "version 2.1.280 or newer is required"); 2.1.280 is what the Code tab runs.
CLI="$H/Library/Application Support/Claude/claude-code/2.1.280/claude.app/Contents/MacOS/claude"
run=$1 probe=${2:-}
dir=$S/w/$run/USBDriveTester
out=$S/f4test/out/$run${probe:+.probe}
[[ -d $dir ]] || { echo "no copy for $run" >&2; exit 1 }
[[ -e $out.jsonl ]] && { echo "already ran: $out.jsonl" >&2; exit 1 }
# A logged-out CLI would spend a run on an auth error; refuse before any output exists.
"$CLI" auth status 2>/dev/null | grep -q '"loggedIn": true' \
  || { echo "the CLI is not logged in: run  claude auth login  first" >&2; exit 3 }

others=()
for d in $S/w/*(/N); do [[ ${d:t} != $run ]] && others+=("(subpath \"$d\")"); done

cat > $out.sb <<EOF
(version 1)
(allow default)
; Home is writable only where the CLI keeps its own state.
(deny file-write* (subpath "$H"))
(allow file-write* (regex #"^$H/\\.claude") (subpath "$H/Library/Caches") (subpath "$H/.cache")
  (subpath "$H/.local") (subpath "$H/.config"))
; No writes to external volumes (the real repository, every attached drive), /Applications, /Library.
(deny file-write* (subpath "/Volumes") (subpath "/Applications") (subpath "/Library"))
; Not readable: the real repository, its session transcripts and memory, this experiment's own
; files, every other run's copy, and the app's state on this machine — the walk being recorded is
; staged, and the machine would contradict it.
(deny file-read* file-write*
  (subpath "/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester")
  (subpath "$H/.claude/projects/-Volumes-1TB-UGreen-AI-Stuff-claude-code-folder-USBDriveTester")
  (subpath "$S/audit") (subpath "$S/f4test") (literal "$S/signals.sh")
  (regex #"^$H/Library/.*(com\\.arc3solutions|USBDriveTester)")
  ${others[*]})
; Nothing that reads the machine's live log or disks, drives the GUI, escalates, or builds.
(deny process-exec
  (literal "/usr/bin/log") (literal "/usr/sbin/diskutil") (literal "/usr/sbin/ioreg")
  (literal "/usr/sbin/system_profiler") (literal "/usr/bin/open") (literal "/usr/bin/osascript")
  (literal "/usr/bin/sudo") (literal "/bin/launchctl") (literal "/usr/bin/pmset")
  (literal "/usr/sbin/sfltool") (literal "/usr/bin/xcodebuild") (literal "/usr/bin/xcrun")
  (literal "/usr/bin/swift") (literal "/usr/sbin/lsof") (subpath "/Applications/Development"))
EOF

ALLOWED="Read,Grep,Glob,Edit,Write,MultiEdit,TodoWrite,Bash(grep *),Bash(egrep *),Bash(rg *),Bash(git *),Bash(sed *),Bash(awk *),Bash(wc *),Bash(head *),Bash(tail *),Bash(cat *),Bash(ls *),Bash(ls),Bash(find *),Bash(date *),Bash(date),Bash(diff *),Bash(sort *),Bash(uniq *),Bash(cut *),Bash(tr *),Bash(nl *),Bash(stat *),Bash(shasum *),Bash(python3 *),Bash(echo *),Bash(printf *),Bash(pwd),Bash(cmp *),Bash(file *),Bash(cd *),Bash(basename *),Bash(dirname *),Bash(xargs *)"

if [[ -n $probe ]]; then prompt_file=$S/f4test/probe.txt; secs=300; budget=1; effort=low
else prompt_file=$S/f4test/request.txt; secs=2400; budget=30; effort=high; fi

date +%F > $out.date
"$CLI" --version > $out.version 2>&1
date '+%F %T' > $out.start
cd $dir
env DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  sandbox-exec -f $out.sb \
  perl -e 'alarm shift; exec @ARGV or die "exec: $!"' $secs \
  "$CLI" -p \
    --model claude-opus-5-5 --effort $effort \
    --output-format stream-json --verbose \
    --strict-mcp-config --setting-sources project,local \
    --settings '{"agentPushNotifEnabled":false,"inputNeededNotifEnabled":false}' \
    --no-session-persistence --max-budget-usd $budget \
    --permission-mode acceptEdits \
    --allowedTools "$ALLOWED" \
    --debug-file $S/w/$run/cli-debug${probe:+-probe}.txt \
  < $prompt_file > $out.jsonl 2> $out.err
rc=$?
date '+%F %T' > $out.end
mv $S/w/$run/cli-debug${probe:+-probe}.txt $out.debug 2>/dev/null
echo "$run${probe:+ (probe)} rc=$rc $(tail -c 300 $out.jsonl | tr -d '\n' | grep -o '"result":"[^"]\{0,120\}')"
