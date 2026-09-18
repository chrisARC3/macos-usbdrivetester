#!/bin/bash
#
# test.sh — run the Swift Testing unit suite (core algorithm) for the project.
#
# Like build.sh, this points xcodebuild at the full Xcode via DEVELOPER_DIR (the
# active developer dir on this machine is Command Line Tools).
#
# Scoped with -only-testing to the USBDriveTesterTests (Swift Testing) target: the
# hardware-independent core tests that this project is built around (NFR-MAINT-2).
# The template USBDriveTesterUITests target is intentionally excluded — it is unused
# and only slows the TDD loop. To run everything, drop the -only-testing line.
#
# PARALLELISM IS OFF (added Step 8, 2026-08-02). Swift Testing runs tests concurrently
# *within one process* by default. Several assertions in this suite read process-global
# counters — `ChunkBuffers.liveAllocatedBytes` and `peakAllocatedBytes`, which BUILD-PLAN
# 7.6's gate asks to be instrumented and confirmed — and no assertion on a global counter
# can be sound while another test may be mutating it. Step 7 saw this coming and wrote the
# warning into `ChunkBuffersInstrumentationTests`: "Nothing else in the suite allocates
# ChunkBuffers today; if a future test does, it must either live here or the assertions
# below must be loosened." Step 8's cycle tests allocate buffers in forty-odd tests, so the
# condition arrived.
#
# Measured 2026-08-02: 9.7 s parallel, 18.8 s serialised. Nine seconds is a small price for
# removing a class of results that depend on scheduling — and a green that depends on
# scheduling is not evidence. Verified to take effect rather than assumed: the suite runs in
# a single process either way, and disabling this doubles the wall clock.
#
# THE COUNT IS PART OF THE RESULT (added 2026-08-18)
#
# On 2026-08-18 this script printed `✔ Test run with 624 tests in 98 suites passed` on a suite
# of 964 tests in 122 suites. **340 tests did not run and the output said "passed".** The cause
# was a build race: `install-app.sh` had built into the same DerivedData moments earlier, and
# the test build picked up a bundle missing 24 suites. Re-running clean gave 964 twice.
#
# A green tick is therefore not evidence on its own — it means "everything that ran, passed",
# which is a different claim from "the suite passed". The floor below closes that gap: the run
# fails if fewer tests execute than the most this repo has ever seen.
#
# It RATCHETS UPWARD BY ITSELF. Adding tests raises the floor on the next green run, so nobody
# has to remember to bump it and it cannot go stale-low, which is what would make it stop
# catching anything. It only ever refuses to go DOWN.
#
# ONLY A GREEN RUN RAISES IT (fixed 2026-09-18). Until then the raise came before the failure
# check, so any run that printed a summary could raise the floor, red or not, and the paragraph
# above was wrong about its own code. A red run's count is the wrong number to keep: failing
# exploratory tests that are then deleted would leave the floor above the suite, and the first
# run on a new toolchain (Xcode 27, 2026-09-18) is exactly when a count should be looked at
# before it becomes the floor.
#
# Deleting tests on purpose is the one case that needs a human: delete the floor file and the
# next run re-establishes it. That is deliberate friction — a suite getting smaller should be
# a decision somebody took, not something a script absorbs silently.
#
# Usage: scripts/test.sh [Debug|Release]
#
set -uo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/USBDriveTester/USBDriveTester.xcodeproj"
SCHEME="USBDriveTester"
CONFIG="${1:-Debug}"

echo "Using Xcode at: $DEVELOPER_DIR"
echo "Testing scheme '$SCHEME' ($CONFIG), target USBDriveTesterTests…"

FLOOR_FILE="$REPO_ROOT/scripts/.test-floor"
OUTPUT="$(mktemp)"
trap 'rm -f "$OUTPUT"' EXIT

# `set -e` is off for this pipeline on purpose: a failing test run must still reach the count
# check below, or a partial run that also failed would report only the failure and hide the gap.
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS,arch=arm64' \
    -allowProvisioningUpdates \
    -only-testing:USBDriveTesterTests \
    -parallel-testing-enabled NO \
    test 2>&1 | tee "$OUTPUT"
STATUS="${PIPESTATUS[0]}"

SUMMARY="$(grep -oE 'Test run with [0-9]+ tests? in [0-9]+ suites?' "$OUTPUT" | tail -1 || true)"
COUNT="$(sed -nE 's/Test run with ([0-9]+) tests?.*/\1/p' <<< "$SUMMARY")"
SUITES="$(sed -nE 's/.* in ([0-9]+) suites?/\1/p' <<< "$SUMMARY")"
FLOOR="$(cat "$FLOOR_FILE" 2>/dev/null || echo 0)"

echo
if [[ -z "$COUNT" ]]; then
    # No summary line at all. Not a pass and not a failure — an unknown, which is the one
    # verdict that must never be mistaken for either.
    echo "  ✖ INCONCLUSIVE: no test-run summary was printed. Nothing can be concluded from this"
    echo "    run, including that it failed. Look for a build error above."
    exit 1
fi

if (( COUNT < FLOOR )); then
    echo "  ✖ INCOMPLETE RUN: ${COUNT} tests in ${SUITES} suites, but this repo has run ${FLOOR}."
    echo "    $(( FLOOR - COUNT )) test(s) did not execute. A green tick here would mean"
    echo "    \"everything that ran, passed\" — which is not the same as the suite passing."
    echo
    echo "    Most likely a build race: do not build and test into the same DerivedData"
    echo "    back to back. Re-run this script on its own first."
    echo
    echo "    If tests were deleted deliberately: rm ${FLOOR_FILE}"
    exit 1
fi

if [[ "$STATUS" -ne 0 ]]; then
    echo "  ✖ ${COUNT} tests in ${SUITES} suites ran; the run FAILED. See the failures above."
    if (( COUNT > FLOOR )); then
        echo "    The floor stays at ${FLOOR}: it rises only on a green run."
    fi
    exit "$STATUS"
fi

if (( COUNT > FLOOR )); then
    echo "$COUNT" > "$FLOOR_FILE"
    echo "  floor raised ${FLOOR} → ${COUNT} (${SUITES} suites)"
fi

echo "  ✔ ${COUNT} tests in ${SUITES} suites — complete and green."
