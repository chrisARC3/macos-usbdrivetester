#!/bin/bash
#
# sleep-assertion-check.sh — settles how Step 13's verification gate can be read, before any of
# Step 13 is wired.
#
# WHY THIS EXISTS
#
# NFR-REL-9 holds an idle-system-sleep assertion while a run is executing, and BUILD-PLAN's Step 13
# gate is read ENTIRELY through `pmset -g assertions`. The gate therefore rests on four unmeasured
# claims about an instrument, and this project's standing lesson is that three of the four defects
# found in the week of 2026-09-04 were in the instrument rather than the product:
#
#   1. That `ProcessInfo.beginActivity(options: [.idleSystemSleepDisabled])` publishes an assertion
#      `pmset` calls `PreventUserIdleSystemSleep` — the string the gate greps for. The API is
#      documented in terms of behaviour and never in terms of the assertion it creates.
#   2. That the `reason:` string survives to `pmset`'s `named:` field, which with the pid is one of
#      only two axes the gate has for attributing an assertion to THIS app.
#   3. That the system-wide summary count is not the evidence. `powerd` holds a
#      PreventUserIdleSystemSleep whenever the display is on, so that line already reads 1 with
#      nothing of ours loaded — and a gate item read off it may pass without the product.
#   4. That we do not prevent DISPLAY sleep (BUILD-PLAN step 3), which is a question about what our
#      pid publishes, not about a system-wide count another app can move.
#
# It also measures the release latency, because the gate asks a person to press Pause and then read
# `pmset`, and an item that does not say how long to wait is an item whose answer depends on typing
# speed.
#
# WHAT IT DOES TO THE MACHINE
#
# Holds an idle-sleep assertion for a few seconds and lets it go. No device is opened, nothing is
# written, no drive is needed, and nothing here needs `sudo` — `pmset -g assertions` is readable by
# any user. This is the rare gate in this project that can run on a laptop with nothing plugged in.
#
# Usage:
#   scripts/sleep-assertion-check.sh [--hold <seconds>]
#
#     --hold  pass through to the probe: hold the assertion this long so a person can read
#             `/usr/bin/pmset -g assertions` in another window and see what the gate asks for.
#
set -uo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Built outside the repo, like every other probe here: this volume is removable and macOS gates
# access to removable volumes.
BUILD_DIR="/tmp/usbdrivetester-sleep-assertion"
PROBE="$BUILD_DIR/sleep-assertion-probe"
PROBE_SRC="$REPO_ROOT/tools/sleep-assertion-probe/main.swift"
OUTPUT="$BUILD_DIR/probe-output.txt"

HOLD=()
if [[ "${1:-}" == "--hold" ]]; then
    [[ -n "${2:-}" ]] || { echo "usage: $0 [--hold <seconds>]" >&2; exit 2; }
    HOLD=(--hold "$2")
fi

FAILURES=0

check() {
    if [[ "$1" == "pass" ]]; then
        echo "  PASS  $2"
    else
        echo "  FAIL  $2"
        FAILURES=$((FAILURES + 1))
    fi
}

# A finding is not a failure. These record what the instrument does so the gate can be WRITTEN
# against it; the script fails only when the mechanism itself does not work.
note() {
    echo "  NOTE  $1"
}

mkdir -p "$BUILD_DIR"

[[ -f "$PROBE_SRC" ]] || { echo "error: probe source not found at $PROBE_SRC" >&2; exit 1; }

echo "Building the probe…"
if ! xcrun swiftc -swift-version 5 -O "$PROBE_SRC" -o "$PROBE"; then
    echo "error: the probe did not build" >&2
    exit 1
fi

echo "Running…"
echo
"$PROBE" ${HOLD[@]+"${HOLD[@]}"} 2>&1 | tee "$OUTPUT"
PROBE_STATUS="${PIPESTATUS[0]}"
echo

field() { grep -m1 "^finding: $1=" "$OUTPUT" | sed "s/^finding: $1=//"; }

echo "Results"
echo

if [[ "$PROBE_STATUS" -ne 0 ]]; then
    check fail "the probe exited ${PROBE_STATUS} — see ${OUTPUT}"
    echo
    echo "  ${FAILURES} failure(s) — the mechanism NFR-REL-9 depends on did not work."
    exit "$FAILURES"
fi

TYPE="$(field type)"
NAME_CARRIES="$(field nameCarriesReason)"
MATCHES_PLAN="$(field typeMatchesBuildPlan)"
DISPLAY_UNTOUCHED="$(field displaySleepUntouched)"
SUMMARY="$(grep -m1 '^finding: summaryCountDiscriminates=' "$OUTPUT" | sed 's/^finding: summaryCountDiscriminates=//')"
PER_TOKEN="$(grep -m1 '^finding: perTokenEntries=' "$OUTPUT" | sed 's/^finding: perTokenEntries=//')"
SURVIVES="$(field survivesPartialRelease)"
RELEASE="$(field releaseVisibleAfter)"

# --- what must be true for Step 13 to be buildable at all -------------------------------------

[[ -n "$TYPE" ]] \
    && check pass "beginActivity publishes an assertion pmset attributes to the pid (${TYPE})" \
    || check fail "beginActivity published nothing readable by pid"

[[ "$DISPLAY_UNTOUCHED" == "yes" ]] \
    && check pass "our pid publishes no display-sleep assertion (BUILD-PLAN step 3)" \
    || check fail "our pid published a display-sleep assertion — step 3 forbids it"

READ_COST="$(grep -m1 '^probe: pmsetReadCost=' "$OUTPUT" | sed 's/^probe: pmsetReadCost=//')"

[[ -n "$RELEASE" && "$RELEASE" != "NEVER" ]] \
    && check pass "endActivity is visible in pmset after ${RELEASE} (one pmset read costs ${READ_COST:-?})" \
    || check fail "the assertion outlived endActivity"

# --- what the gate has to be WRITTEN around ---------------------------------------------------

if [[ "$MATCHES_PLAN" == "yes" ]]; then
    note "the type is PreventUserIdleSystemSleep — BUILD-PLAN's gate string is correct as written"
else
    note "the type is ${TYPE}, NOT the PreventUserIdleSystemSleep the gate greps for — the gate's"
    note "wording must be corrected before it is walked, or it will fail a working product"
fi

if [[ "$NAME_CARRIES" == "yes" ]]; then
    note "the reason string survives to pmset's named: field — the gate can read by name AND pid"
else
    note "the reason string does NOT reach pmset — the gate must attribute by pid alone"
fi

if [[ "$SUMMARY" == no* ]]; then
    note "the system-wide summary line does NOT move when we take one: ${SUMMARY}"
    note "so the gate MUST read the 'Listed by owning process' section. An item answered from the"
    note "summary count is answered by powerd, and passes with the app not running at all."
else
    note "the system-wide summary line moves with our assertion: ${SUMMARY}"
fi

if [[ "$PER_TOKEN" == yes* ]]; then
    note "two activities from one process show as two entries (${PER_TOKEN}) — a leak is VISIBLE"
    note "in pmset, and gate item 3 can be read there"
else
    note "two activities from one process collapse to one entry (${PER_TOKEN}) — a leaked second"
    note "assertion is INVISIBLE to pmset, so gate item 3 cannot be read there and must be"
    note "answered by the suite's counting double and the acquire/release log lines"
fi

[[ "$SURVIVES" == "yes" ]] \
    && note "ending one of two left the other held — the token, not a per-process flag" \
    || note "ending one of two dropped the assertion entirely — NOT per-token"

echo
cat <<EOF
  ---------------------------------------------------------------------------
  What this settles for Step 13

  The gate is read by PID plus the 'Listed by owning process' section, never
  from the system-wide summary count. The assertion type and name above are
  what the checklist must tell a person to look for, and ${RELEASE:-?} is how
  long they may have to wait after pressing Pause before it disappears.

  Read that last number against the ${READ_COST:-?} one pmset invocation costs.
  A latency at or near the read cost means the change was ALREADY TRUE on the
  first read — an upper bound set by the instrument, not a latency the
  mechanism produced. Do not quote it as one.

  This measurement is about an OS mechanism, not about this app, so it does not
  lapse when the app's commit moves. It lapses on a macOS update — re-run it
  then, and re-run it before walking Step 13's gate on a machine that has been
  updated since.

  Full output: ${OUTPUT}
  ---------------------------------------------------------------------------

EOF

if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${FAILURES} failures."
else
    echo "  ${FAILURES} failure(s) — see FAIL lines above."
fi

exit "$FAILURES"
