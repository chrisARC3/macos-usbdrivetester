#!/bin/bash
#
# lifecycle-check.sh — assert the privileged helper's system-side state.
#
# Step 4's gate requires that after an uninstall "the daemon process is gone
# (verified via launchctl)". Eyeballing that is exactly the kind of check that
# quietly passes when it shouldn't, so this makes it mechanical: it inspects the
# launchd system domain and the process table and exits non-zero on a mismatch.
#
# Usage:
#   scripts/lifecycle-check.sh present   # expect the helper installed and running
#   scripts/lifecycle-check.sh absent    # expect no trace of it
#   scripts/lifecycle-check.sh           # just report, always exit 0
#
# No sudo required: reading a system-domain service's state is unprivileged.
#
set -uo pipefail

LABEL="com.arc3solutions.USBDriveTester.Helper"
EXPECT="${1:-report}"

echo "=============================================================="
echo " Helper lifecycle state — $LABEL"
echo "=============================================================="
echo

# --- launchd system domain ---------------------------------------------------
if PRINT_OUT="$(launchctl print "system/$LABEL" 2>&1)"; then
    REGISTERED=1
    echo "launchd:  REGISTERED in the system domain"
    echo "$PRINT_OUT" | grep -E "^[[:space:]]+(state|managed_by|active count) =" | sed 's/^/          /'
    echo "$PRINT_OUT" | grep -E "^[[:space:]]+program identifier =" | sed 's/^/          /'
else
    REGISTERED=0
    echo "launchd:  not present in the system domain"
fi
echo

# --- process table -----------------------------------------------------------
# Match the executable name rather than a path, so a helper running from either
# /Applications or a DerivedData build is caught — and match it on the EXECUTABLE, the end of
# `ps -o comm`. Not `pgrep -f`, which also matches any process whose ARGUMENTS contain that
# path — an `nm`, a `codesign`, an editor — and would fail `absent` with no daemon running.
# Found 2026-09-10.
PIDS="$(/bin/ps -axo pid=,comm= | /usr/bin/awk -v want="MacOS/$LABEL" '
    substr($0, length($0) - length(want) + 1) == want { printf "%s%s", sep, $1; sep = " " }')"
if [[ -n "$PIDS" ]]; then
    RUNNING=1
    echo "process:  RUNNING (pid(s): $PIDS)"
    ps -o pid,uid,user,lstart,comm -p ${PIDS// /,} 2>/dev/null | sed 's/^/          /'
else
    RUNNING=0
    echo "process:  not running"
fi
echo

# --- leftovers from pre-SMAppService days ------------------------------------
# Steps 1-2 used a manual launchctl bootstrap. Those artefacts would collide with
# the SMAppService daemon over the same Label, so their absence is worth asserting.
LEFTOVERS=0
for path in "/Library/LaunchDaemons/$LABEL.plist" "/Library/PrivilegedHelperTools/$LABEL"; do
    if [[ -e "$path" ]]; then
        echo "LEFTOVER: $path exists — a manual install would collide with SMAppService"
        LEFTOVERS=1
    fi
done
[[ $LEFTOVERS -eq 0 ]] && echo "leftover: none (no manual LaunchDaemon or PrivilegedHelperTools artefacts)"
echo

# --- verdict -----------------------------------------------------------------
echo "--------------------------------------------------------------"
case "$EXPECT" in
    present)
        if [[ $REGISTERED -eq 1 && $LEFTOVERS -eq 0 ]]; then
            echo " PASS — helper is registered as expected."
            exit 0
        fi
        echo " FAIL — expected the helper to be registered." >&2
        exit 1
        ;;
    absent)
        # Both must be clear. A registered-but-not-running service is normal (launchd
        # starts these on demand), but a RUNNING process after an uninstall means the
        # daemon outlived its registration and is still holding whatever it held.
        if [[ $REGISTERED -eq 0 && $RUNNING -eq 0 && $LEFTOVERS -eq 0 ]]; then
            echo " PASS — no trace of the helper remains."
            exit 0
        fi
        echo " FAIL — expected no trace of the helper:" >&2
        [[ $REGISTERED -eq 1 ]] && echo "        still registered in the launchd system domain" >&2
        [[ $RUNNING -eq 1 ]]    && echo "        process still running (pid(s): $PIDS)" >&2
        [[ $LEFTOVERS -eq 1 ]]  && echo "        manual-install artefacts present" >&2
        exit 1
        ;;
    *)
        echo " (report only — pass 'present' or 'absent' to assert)"
        exit 0
        ;;
esac
