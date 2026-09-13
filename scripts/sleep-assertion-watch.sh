#!/bin/bash
#
# sleep-assertion-watch.sh — a timestamped transcript of what idle-sleep assertions
# USBDriveTester holds, so Step 13's gate is read by an instrument rather than by a person
# racing `pmset` against a state transition.
#
# WHY THIS EXISTS
#
# BUILD-PLAN's Step 13 gate asks a person to press Pause and then observe that the assertion is
# released. That instruction has two problems a script can remove:
#
#   1. **The reading is a race.** Release happens on the transition out of `running`, which is
#      milliseconds after the press; a person opening a terminal and typing `pmset -g assertions`
#      is sampling a second or two later and can only report the end state. If the release were
#      late, or briefly doubled, nothing about the typing speed would reveal it. This polls at
#      4 Hz and prints a line on every CHANGE, so the transcript holds the transitions themselves.
#
#   2. **The obvious reading is answered by `powerd`, not by us.** `pmset -g assertions` opens with
#      a system-wide summary in which `PreventUserIdleSystemSleep` reads **1** whenever the display
#      is on, with nothing of ours loaded — measured 2026-09-12, and it is a FLAG, NOT A COUNT: 1 at
#      baseline, 1 holding one, 1 holding two, 1 after release (`CONSTRAINTS.md` §1, *Idle-sleep
#      assertions*). **This script never reads that line.** Everything below comes from the
#      `Listed by owning process:` section, matched on the app's pid.
#
# It is also the thing that makes gate item 3 — "exactly one assertion is held at a time (no leaks
# across pause/resume cycles)" — answerable at all. A leak is a property of a SEQUENCE, and a person
# sampling after three pause/resume cycles sees the same one entry whether the count went 1,0,1,0,1
# or 1,2,3. This prints the count on every change and reports the maximum at the end.
#
# WHAT IT DOES TO THE MACHINE
#
# Nothing. It reads `pmset -g assertions` in a loop. No sudo, no drive, no writes — it does not
# even need the app to be running when it starts; it waits, and it keeps running across a relaunch.
#
# Usage:
#   scripts/sleep-assertion-watch.sh [--for <seconds>] [--interval <seconds>] [--name <process>]
#
#     --for       stop after this many seconds and print the summary (default: until Ctrl-C)
#     --interval  seconds between samples (default: 0.25)
#     --name      process to watch (default: USBDriveTester)
#
# Ctrl-C prints the summary too — that is the ordinary way to end it.
#
set -uo pipefail

INTERVAL=0.25
DURATION=0
PROCESS_NAME="USBDriveTester"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --for)      DURATION="${2:-}"; shift 2 ;;
        --interval) INTERVAL="${2:-}"; shift 2 ;;
        --name)     PROCESS_NAME="${2:-}"; shift 2 ;;
        -h|--help)  sed -n '2,42p' "$0"; exit 0 ;;
        *)          echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# The two strings the gate greps for. Kept here as data so the summary can say which one it saw:
# holding the DISPLAY one instead would satisfy every unit test in the project and fail the
# requirement (BUILD-PLAN Step 13 step 3), and it is visible only here.
WANTED_TYPE="PreventUserIdleSystemSleep"
DISPLAY_TYPE="PreventUserIdleDisplaySleep"

SAMPLES=0
CHANGES=0
MAX_HELD=0
EVER_HELD=0
SAW_DISPLAY=0
LAST_KEY="<start>"
LAST_PID=""
STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"

summarise() {
    echo
    echo "── summary ──────────────────────────────────────────────────────────────────"
    echo "  watched          ${PROCESS_NAME} from ${STARTED_AT} to $(date '+%H:%M:%S')"
    echo "  samples          ${SAMPLES} at ${INTERVAL}s"
    echo "  changes          ${CHANGES}"
    echo "  held at all      $( ((EVER_HELD)) && echo yes || echo "NO — nothing was ever held" )"
    echo "  most at once     ${MAX_HELD}  (${WANTED_TYPE} only)"
    if (( MAX_HELD > 1 )); then
        echo "                   ⚠️  MORE THAN ONE AT A TIME. Gate item 3 fails on this transcript."
    fi
    if (( SAW_DISPLAY )); then
        echo "                   ⚠️  a ${DISPLAY_TYPE} was held by this pid."
        echo "                       BUILD-PLAN Step 13 step 3 says display sleep must not be prevented."
    fi
    echo
    echo "  Paste this whole transcript into progress/step-13-human-checklist.md's walk record."
    exit 0
}
trap summarise INT TERM

echo "sleep-assertion-watch — ${PROCESS_NAME}, sampling every ${INTERVAL}s"
echo "  reading the 'Listed by owning process:' section only; the system-wide summary line is"
echo "  a flag held by powerd and is never consulted. Ctrl-C to stop."
echo
printf '%-8s  %-6s  %-5s  %s\n' "time" "pid" "held" "assertions this pid owns"
printf '%-8s  %-6s  %-5s  %s\n' "--------" "------" "-----" "------------------------"

END_AT=0
if [[ "$DURATION" != "0" ]]; then
    END_AT=$(( $(date +%s) + DURATION ))
fi

while true; do
    # Re-resolved every sample: a relaunch gives a new pid, and an assertion held by a pid that no
    # longer exists is not evidence about the app now on screen.
    PIDS="$(/usr/bin/pgrep -x "$PROCESS_NAME" 2>/dev/null || true)"
    PID_COUNT="$(wc -w <<< "$PIDS" | tr -d ' ')"

    if [[ -z "$PIDS" ]]; then
        KEY="not running"
        HELD=0
        DETAIL="(${PROCESS_NAME} is not running)"
        PID_SHOWN="—"
    elif (( PID_COUNT > 1 )); then
        # Two copies of the app — /Applications and a DerivedData build, say. Which one holds the
        # assertion is exactly the question, so refuse to average them. Same trap as the daemon's
        # "which copy did launchctl start" check in Step 12's checklist.
        KEY="ambiguous"
        HELD=0
        PID_SHOWN="$(tr '\n' ',' <<< "$PIDS" | sed 's/,$//')"
        DETAIL="⚠️  ${PID_COUNT} processes named ${PROCESS_NAME}; quit the one you are not testing"
    else
        PID="$PIDS"
        PID_SHOWN="$PID"
        LINES="$(/usr/bin/pmset -g assertions 2>/dev/null \
                 | /usr/bin/grep -F "pid ${PID}(" || true)"

        if [[ -z "$LINES" ]]; then
            HELD=0
            DETAIL="—"
        else
            # **Counted by TYPE, not by line.** A pid can own assertions this gate is not about: the
            # smoke test of this script against `powerd` showed it holding a
            # `PreventUserIdleSystemSleep` AND an `ExternalMedia` at once, and this app is in the
            # business of mounting and unmounting external media. Counting lines would have reported
            # "2 held — gate item 3 fails" for a machine behaving perfectly. Everything the pid owns
            # is still printed; only the count is narrowed.
            # The type is the last token before ` named: "`, and the name is what follows in
            # quotes. Parsed with awk rather than a regex for the probe's reason: a wrong regex
            # here fails silently to an empty result, which reads exactly like an assertion that
            # was never published.
            DETAIL="$(awk -F' named: "' '
                {
                    split($1, head, " ");
                    type = head[length(head)];
                    name = $2; sub(/".*$/, "", name);
                    printf "%s \"%s\"  ", type, name;
                }' <<< "$LINES")"
            HELD="$(/usr/bin/grep -c -- "$WANTED_TYPE" <<< "$LINES" || true)"
        fi
        KEY="${PID}:${DETAIL}"
    fi

    if [[ "$KEY" != "$LAST_KEY" ]]; then
        (( CHANGES++ ))
        MARK=" "
        (( HELD > MAX_HELD )) && MAX_HELD=$HELD
        (( HELD > 0 )) && EVER_HELD=1
        (( HELD > 1 )) && MARK="!"
        [[ "$DETAIL" == *"$DISPLAY_TYPE"* ]] && SAW_DISPLAY=1
        if [[ -n "$LAST_PID" && -n "${PID_SHOWN:-}" && "$PID_SHOWN" != "$LAST_PID" && "$PID_SHOWN" != "—" ]]; then
            printf '%-8s  %-6s  %-5s  %s\n' "$(date '+%H:%M:%S')" "$PID_SHOWN" "" \
                   "── pid changed (${LAST_PID} → ${PID_SHOWN}): the app was relaunched"
        fi
        printf '%-8s  %-6s  %s%-4s  %s\n' "$(date '+%H:%M:%S')" "$PID_SHOWN" "$MARK" "$HELD" "$DETAIL"
        LAST_KEY="$KEY"
        LAST_PID="$PID_SHOWN"
    fi

    (( SAMPLES++ ))
    if (( END_AT )) && (( $(date +%s) >= END_AT )); then
        summarise
    fi
    sleep "$INTERVAL"
done
