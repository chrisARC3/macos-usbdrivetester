#!/bin/zsh
# sandbox_profile.sh <run-id> — print the sandbox-exec profile for that run's session. It keeps the
# session off the real repository (this harness included), the repository's transcripts, every
# output and every other run's copy, the drives, /Applications, and the machine's live state.
# check_sandbox.sh proves it before each session; run_one.sh runs both.
set -euo pipefail
HERE=${0:A:h}; source $HERE/common.sh
run=$1
H=$HOME
more=()
for d in $WORK/w/*(/N); do [[ ${d:t} != $run ]] && more+=("(subpath \"$d\")"); done
for p in ${(s.:.)CMT_DENY:-}; do more+=("(subpath \"${p:A}\")"); done

cat <<EOF
(version 1)
(allow default)
; Home is writable only where the CLI keeps its own state.
(deny file-write* (subpath "$H"))
(allow file-write* (regex #"^$H/\\.claude") (subpath "$H/Library/Caches") (subpath "$H/.cache")
  (subpath "$H/.local") (subpath "$H/.config"))
; No writes to external volumes (the real repository, every attached drive), /Applications, /Library.
(deny file-write* (subpath "/Volumes") (subpath "/Applications") (subpath "/Library"))
; Not readable: the real repository and this harness; the repository's session transcripts and
; memory, under its path now and under any earlier volume; every output; every other run's copy;
; and the app's state on this machine. The walk being recorded is staged, and the machine would
; contradict it.
(deny file-read* file-write*
  (subpath "$REAL")
  (subpath "$(project_dir $REAL)")
  (regex #"^$H/\\.claude/projects/-Volumes-[^/]*-${REAL:t}(/|\$)")
  (subpath "$OUT")
  (regex #"^$H/Library/.*(com\\.arc3solutions|USBDriveTester)")
  ${more[*]})
; Nothing that reads the machine's live log or disks, drives the GUI, escalates, or builds.
(deny process-exec
  (literal "/usr/bin/log") (literal "/usr/sbin/diskutil") (literal "/usr/sbin/ioreg")
  (literal "/usr/sbin/system_profiler") (literal "/usr/bin/open") (literal "/usr/bin/osascript")
  (literal "/usr/bin/sudo") (literal "/bin/launchctl") (literal "/usr/bin/pmset")
  (literal "/usr/sbin/sfltool") (literal "/usr/bin/xcodebuild") (literal "/usr/bin/xcrun")
  (literal "/usr/bin/swift") (literal "/usr/sbin/lsof") (subpath "/Applications/Development"))
EOF
