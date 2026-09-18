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
# EVERY LINE CARRIES ITS OWN READING — rewritten 2026-09-18 after the first walk
#
# The first version printed a header row (`time  pid  held  assertions…`) and then bare columns.
# Checklist chunk 1, walked 2026-09-18, found that **the word "held" appeared on no line at all** —
# the checklist told a person to look for `held 0`, and the transcript carried `0` under a header,
# misaligned by two columns because bash's `printf %-6s` pads BYTES and the em-dash placeholder was
# three of them. During a run lasting hours the header scrolls away and a bare `1` means nothing.
# That is the shape of one of the defects found in the week of 2026-09-04 (CLAUDE.md): an item
# asking for a reading off a line that does not carry it. Now every line reads `pid N  held N  …` in
# ASCII, and the header is gone.
#
# Two more things the first walk showed a transcript needs:
#
#   * **Which copy of the app is this?** Printed on every new pid, from the kernel (`lsof`'s txt
#     mapping, falling back to `ps`), with a warning if it is not `/Applications`. NOT from the
#     unified log: `log show`'s `processImagePath` is resolved through a cache keyed by the binary's
#     UUID, and on 2026-09-18 it attributed the installed app to a DerivedData folder that no longer
#     existed (`CONSTRAINTS.md` §1).
#   * **Was it watching when the thing happened?** A change-only log cannot show that it covered an
#     event which changed nothing — item 1.3 selects a drive and expects NO line. So a heartbeat line
#     is printed every `--heartbeat` seconds (default 60) whether or not anything changed.
#
# WHAT IT DOES TO THE MACHINE
#
# Nothing. It reads `pmset -g assertions` in a loop. No sudo, no drive, no writes — it does not
# even need the app to be running when it starts; it waits, and it keeps running across a relaunch.
#
# Usage:
#   scripts/sleep-assertion-watch.sh [--for <s>] [--interval <s>] [--heartbeat <s>] [--name <process>]
#
#     --for        stop after this many seconds and print the summary (default: until Ctrl-C)
#     --interval   seconds between samples (default: 0.25)
#     --heartbeat  seconds between "still watching" lines when nothing changes (default: 60; 0 = off)
#     --name       process to watch (default: USBDriveTester)
#
# Ctrl-C prints the summary too — that is the ordinary way to end it. Paste the summary with the
# transcript: its start and end times are what show the transcript covered the walk.
#
set -uo pipefail

INTERVAL=0.25
DURATION=0
HEARTBEAT=60
PROCESS_NAME="USBDriveTester"
INSTALLED_PREFIX="/Applications/USBDriveTester.app/"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --for)       DURATION="${2:-}"; shift 2 ;;
        --interval)  INTERVAL="${2:-}"; shift 2 ;;
        --heartbeat) HEARTBEAT="${2:-}"; shift 2 ;;
        --name)      PROCESS_NAME="${2:-}"; shift 2 ;;
        -h|--help)   sed -n '2,70p' "$0"; exit 0 ;;
        *)           echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# The two strings the gate greps for. Kept here as data so the summary can say which one it saw:
# holding the DISPLAY one instead would satisfy every unit test in the project and fail the
# requirement (BUILD-PLAN Step 13 step 3), and it is visible only here — mutation m8 of Step 13
# chunk 4's round passes all 1,323 tests.
WANTED_TYPE="PreventUserIdleSystemSleep"
DISPLAY_TYPE="PreventUserIdleDisplaySleep"

SAMPLES=0
CHANGES=0
MAX_HELD=0
EVER_HELD=0
SAW_DISPLAY=0
SAW_ELSEWHERE=0
SAW_AMBIGUOUS=0
LAST_KEY="<start>"
LAST_PID=""
STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
LAST_PRINT_AT=$(date +%s)

# The executable behind a pid, from the kernel. `lsof`'s first txt mapping is the main executable's
# vnode; `ps -o comm=` (argv[0]) is the fallback. Never the unified log — see the header.
executable_of() {
    local path
    path="$(/usr/sbin/lsof -a -p "$1" -d txt -Fn 2>/dev/null | /usr/bin/sed -n 's/^n//p' | head -1)"
    [[ -z "$path" ]] && path="$(/bin/ps -o comm= -p "$1" 2>/dev/null)"
    echo "${path:-(unknown)}"
}

summarise() {
    echo
    echo "== summary ======================================================================"
    echo "  watched          ${PROCESS_NAME} from ${STARTED_AT} to $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  samples          ${SAMPLES} at ${INTERVAL}s"
    echo "  changes          ${CHANGES}"
    echo "  held at all      $( ((EVER_HELD)) && echo yes || echo "NO - nothing was ever held" )"
    echo "  most at once     held ${MAX_HELD}  (${WANTED_TYPE} only)"
    if (( MAX_HELD > 1 )); then
        echo "                   !! MORE THAN ONE AT A TIME. Gate item 3 fails on this transcript."
    fi
    if (( SAW_DISPLAY )); then
        echo "                   !! a ${DISPLAY_TYPE} was held by this pid."
        echo "                      BUILD-PLAN Step 13 step 3 says display sleep must not be prevented."
    fi
    if (( SAW_AMBIGUOUS )); then
        echo "                   !! for part of the watch more than one ${PROCESS_NAME} was running, and"
        echo "                      nothing was read while they were ('held ?'). The maximum above"
        echo "                      does not cover those lines."
    fi
    if (( SAW_ELSEWHERE )); then
        echo "                   !! at least one pid watched was NOT the installed app under"
        echo "                      ${INSTALLED_PREFIX} - see the 'exe' lines above. Readings taken"
        echo "                      from another copy are about another build."
    fi
    echo
    echo "  Paste the whole transcript AND this summary into the checklist's walk record."
    exit 0
}
trap summarise INT TERM HUP

echo "sleep-assertion-watch: ${PROCESS_NAME}, sampling every ${INTERVAL}s, heartbeat every ${HEARTBEAT}s"
echo "  Reads only the 'Listed by owning process:' section. The system-wide summary line is a"
echo "  flag powerd holds while the display is on, and is never consulted. Ctrl-C to stop."
echo

END_AT=0
if [[ "$DURATION" != "0" ]]; then
    END_AT=$(( $(date +%s) + DURATION ))
fi

while true; do
    # Re-resolved every sample: a relaunch gives a new pid, and an assertion held by a pid that no
    # longer exists is not evidence about the app now on screen.
    PIDS="$(/usr/bin/pgrep -x "$PROCESS_NAME" 2>/dev/null || true)"
    PID_COUNT="$(wc -w <<< "$PIDS" | tr -d ' ')"
    PID_SHOWN="-"
    HELD_SHOWN=""

    if [[ -z "$PIDS" ]]; then
        KEY="not running"
        HELD=0
        DETAIL="(${PROCESS_NAME} is not running)"
    elif (( PID_COUNT > 1 )); then
        # Two copies of the app — /Applications and a DerivedData build, say. Which one holds the
        # assertion is exactly the question, so refuse to average them.
        PID_SHOWN="$(tr '\n' ',' <<< "$PIDS" | sed 's/,$//')"
        KEY="ambiguous:${PID_SHOWN}"
        # No reading is taken, so none is printed: `held ?`, never `held 0`. The first version of
        # this branch printed 0 — the very defect this rewrite exists to remove.
        HELD=0
        HELD_SHOWN="?"
        SAW_AMBIGUOUS=1
        DETAIL="!! ${PID_COUNT} processes named ${PROCESS_NAME}; quit the one you are not testing"
    else
        PID="$PIDS"
        PID_SHOWN="$PID"
        LINES="$(/usr/bin/pmset -g assertions 2>/dev/null \
                 | /usr/bin/grep -F "pid ${PID}(" || true)"

        if [[ -z "$LINES" ]]; then
            HELD=0
            DETAIL="(owns no assertions)"
        else
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
            # **Counted by TYPE, not by line.** A pid can own assertions this gate is not about:
            # the first smoke test of this script, against `powerd`, showed it holding a
            # `PreventUserIdleSystemSleep` AND an `ExternalMedia` at once, and this app is in the
            # business of mounting and unmounting external media. Counting lines would have
            # reported "held 2 — gate item 3 fails" for a machine behaving perfectly. Everything the
            # pid owns is still printed; only the count is narrowed.
            HELD="$(/usr/bin/grep -c -- "$WANTED_TYPE" <<< "$LINES" || true)"
        fi
        KEY="${PID}:${DETAIL}"
    fi
    [[ -z "$HELD_SHOWN" ]] && HELD_SHOWN="$HELD"

    NOW=$(date +%s)
    if [[ "$KEY" != "$LAST_KEY" ]]; then
        (( CHANGES++ ))
        (( HELD > MAX_HELD )) && MAX_HELD=$HELD
        (( HELD > 0 )) && EVER_HELD=1
        [[ "$DETAIL" == *"$DISPLAY_TYPE"* ]] && SAW_DISPLAY=1

        # A new pid: say which copy of the app it is before saying anything about what it holds.
        if [[ "$PID_SHOWN" != "-" && "$PID_SHOWN" != *,* && "$PID_SHOWN" != "$LAST_PID" ]]; then
            EXE="$(executable_of "$PID_SHOWN")"
            printf '%s  pid %s  exe %s\n' "$(date '+%H:%M:%S')" "$PID_SHOWN" "$EXE"
            if [[ "$EXE" != "$INSTALLED_PREFIX"* ]]; then
                SAW_ELSEWHERE=1
                printf '%s  pid %s  !! NOT THE INSTALLED APP. Quit it and launch %s\n' \
                       "$(date '+%H:%M:%S')" "$PID_SHOWN" "${INSTALLED_PREFIX%/}"
            fi
        fi

        FLAG=""
        (( HELD > 1 )) && FLAG="  !! MORE THAN ONE"
        printf '%s  pid %s  held %s  %s%s\n' "$(date '+%H:%M:%S')" "$PID_SHOWN" "$HELD_SHOWN" "$DETAIL" "$FLAG"
        LAST_KEY="$KEY"
        LAST_PID="$PID_SHOWN"
        LAST_PRINT_AT=$NOW
    elif (( HEARTBEAT > 0 )) && (( NOW - LAST_PRINT_AT >= HEARTBEAT )); then
        # Unchanged, and said so — this is what shows the transcript was watching during an event
        # that was supposed to change nothing.
        printf '%s  pid %s  held %s  (unchanged)\n' "$(date '+%H:%M:%S')" "$PID_SHOWN" "$HELD_SHOWN"
        LAST_PRINT_AT=$NOW
    fi

    (( SAMPLES++ ))
    if (( END_AT )) && (( NOW >= END_AT )); then
        summarise
    fi
    sleep "$INTERVAL"
done
