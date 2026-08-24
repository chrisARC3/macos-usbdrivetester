#!/bin/bash
#
# run-control-check.sh — Step 11, increment 2's design pre-flight.
#
# THE QUESTION
#
#   Does a pause sent on a second XPC connection reach a helper that is inside a blocking
#   `runRetentionCycle`, and does the run then settle at a chunk boundary — with the resume point
#   exactly where it stopped (NFR-REL-10, FR-CTRL-2/3)?
#
#   The transport half is already measured: `scripts/xpc-concurrency-check.sh` established on
#   2026-08-04 that a second connection is answered in 0.2–0.3 ms while a privileged call blocks
#   the first. What that says nothing about is whether the ENGINE acts on what arrives. The control
#   is read at a chunk boundary inside a loop, wired up by `RunCoordinator`, which is not in the
#   test target — and the helper's outward outcome mapping in `main.swift` is not either. This is
#   the cover for both, and it is run BEFORE increments 3–7 are designed around the answer.
#
# THIS ONE WRITES TO THE DEVICE, unlike xpc-concurrency-check.sh
#
#   The question is about the RUN loop's chunk boundary, and only a run has one — so this uses
#   `runRetentionCycle`, not the read-only `digestRange`. The writes are the ordinary
#   non-destructive cycle: every byte written is a byte just read from that same offset
#   (FR-TEST-7, NFR-REL-1). But they are writes, and this script says so before it starts.
#
#   Five bounded calls at the 1 GiB per-call cap: one uninterrupted control run, then one per
#   permitted I/O size, each cut short by a pause about two seconds in. Roughly 90 seconds, and
#   well under 2 GB actually covered.
#
# WHAT IT ASSERTS, beyond "a number came back"
#
#   * The control run COMPLETES, so a bounded call is demonstrably longer than the pre-pause wait.
#     Without this, a drive fast enough to finish inside the wait would report `completed` for every
#     case and "the pause did nothing" would be indistinguishable from "the pause was too late".
#   * Every case settles as `pausedByUser` — not `completed`, and not `stoppedByUser`, which is what
#     a swapped mapping in the helper would produce.
#   * `resumeBlock == startBlock + chunksProcessed × blocksPerChunk`, exactly. This is what makes
#     the resume point PROVEN rather than plausible-looking.
#   * The resume point is 1 MiB-aligned (FR-TEST-10), or the resumed call would be refused.
#   * The settle latency is REPORTED at each I/O size rather than asserted against a threshold —
#     throughput is measured here, not graded, and the shape across the four sizes is the finding.
#
# Usage: ./scripts/run-control-check.sh              # resolves the scratch drive by serial
#        ./scripts/run-control-check.sh --device 12345686DAA9
#
set -euo pipefail

# Resolved by USB SERIAL NUMBER, never by a BSD name on the command line (2026-08-06). A reboot
# renumbers these; `disk4` was this project's scratch device until one did, and then named the
# 22 TB backup drive. A bare `diskN` is accepted only so an old command line is CHECKED and
# refused rather than silently obeyed.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/device-identity.sh"
parse_device_flag "$@" || exit 2
set -- ${DEVICE_FLAG_REMAINING[@]+"${DEVICE_FLAG_REMAINING[@]}"}
DISK="$(resolve_target scratch "$DEVICE_ARGUMENT")" || exit 1

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="5JC55GTLZA"

# Built outside the repo: this volume is removable and macOS gates daemon access to it.
BUILD_DIR="/tmp/usbdrivetester-run-control"
PROBE="$BUILD_DIR/run-control-probe"
OUTPUT="$BUILD_DIR/probe-output.txt"

SHARED="$REPO_ROOT/USBDriveTester/USBDriveTester/Shared/TesterControl.swift"
PROBE_SRC="$REPO_ROOT/tools/run-control-probe/main.swift"

FAILURES=0

check() {
    if [[ "$1" == "pass" ]]; then
        echo "  PASS  $2"
    else
        echo "  FAIL  $2"
        FAILURES=$((FAILURES + 1))
    fi
}

# ---------------------------------------------------------------------------------------
# Safety
# ---------------------------------------------------------------------------------------

DU_INFO="$(diskutil info "$DISK" 2>&1 || true)"

if ! grep -q "Whole: *Yes" <<< "$DU_INFO"; then
    echo "refusing: ${DISK} does not report itself as a whole disk" >&2
    exit 2
fi
if ! grep -q "Protocol: *USB" <<< "$DU_INFO"; then
    echo "refusing: ${DISK} is not behind a USB transport (NFR-COMPAT-4)" >&2
    exit 2
fi

DU_MEDIA_NAME="$(sed -n 's/.*Device \/ Media Name: *//p' <<< "$DU_INFO" | head -1)"

cat <<EOF

  run-control-check.sh — Step 11, increment 2 design pre-flight

  Device     ${DISK}  (${DU_MEDIA_NAME})

  This will UNMOUNT ${DISK}'s volumes, have the helper acquire it, and run FIVE bounded
  read -> write-back -> verify passes over a 1 GiB region 64 GiB into the drive — one
  uninterrupted, then one per I/O size, each paused about two seconds in.

  *** THIS WRITES TO THE DEVICE. *** The cycle writes back exactly the bytes it reads from
  each offset, which is non-destructive by design and verified byte-for-byte — but it is a
  write, on a drive whose contents are expendable by prior agreement.

  Expect about ninety seconds.

  Press Return to continue, or Ctrl-C to abort.

EOF
read -r _

# ---------------------------------------------------------------------------------------
# Mount-state bookkeeping, restored on every exit path
# ---------------------------------------------------------------------------------------

mounted_count() {
    local table count
    table="$(mount)"
    count="$(grep -c "^/dev/${DISK}s" <<< "$table" || true)"
    echo "${count:-0}"
}

MOUNTED_BEFORE="$(mounted_count)"

cleanup() {
    local status=$?
    echo
    echo "  restoring ${DISK} …"
    diskutil mountDisk "$DISK" >/dev/null 2>&1 || true
    sleep 1
    local now
    now="$(mounted_count)"
    echo "  ${DISK}: ${now} volume(s) mounted (was ${MOUNTED_BEFORE} before this run)"
    if [[ "$now" -lt "$MOUNTED_BEFORE" ]]; then
        echo "  NOTE: fewer volumes are mounted than when this started. Remount in Disk Utility."
    fi
    exit "$status"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------------------
# Build and sign the probe
# ---------------------------------------------------------------------------------------

echo "  building the probe …"
mkdir -p "$BUILD_DIR"
for src in "$SHARED" "$PROBE_SRC"; do
    if [[ ! -f "$src" ]]; then
        echo "  FAIL  source not found: ${src}" >&2
        exit 1
    fi
done

xcrun swiftc -swift-version 5 -O "$SHARED" "$PROBE_SRC" -o "$PROBE"

# The helper pins callers to the Team ID and invalidates anything else on its first message. An
# unsigned probe would make every result read as a transport failure — which here would look like
# "the pause never arrived", i.e. exactly the finding that would kill the design.
codesign --force --sign "Apple Development" --timestamp=none "$PROBE" 2>/dev/null \
    || codesign --force --sign - "$PROBE" >/dev/null 2>&1 || true

SIGNING="$(codesign -dv --verbose=4 "$PROBE" 2>&1 || true)"
if grep -q "TeamIdentifier=${TEAM_ID}" <<< "$SIGNING"; then
    check pass "probe is signed under team ${TEAM_ID}, so the helper will accept it"
else
    check fail "probe is NOT signed under team ${TEAM_ID} — every call would fail as a transport"
    echo "        error, which is indistinguishable from the pause never being delivered." >&2
    echo "        $(grep -i 'TeamIdentifier' <<< "$SIGNING" || echo 'no TeamIdentifier present')" >&2
    exit 1
fi

# ---------------------------------------------------------------------------------------
# Unmount and run
# ---------------------------------------------------------------------------------------

echo
echo "  unmounting ${DISK} …"
diskutil unmountDisk "$DISK"

STILL_MOUNTED="$(mounted_count)"
if [[ "$STILL_MOUNTED" != "0" ]]; then
    check fail "${DISK} still has ${STILL_MOUNTED} mounted volume(s); the acquire would be refused"
    exit 1
fi
check pass "${DISK} fully unmounted"

echo

set +e
"$PROBE" "$DISK" | tee "$OUTPUT"
PROBE_STATUS="${PIPESTATUS[0]}"
set -e

# ---------------------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------------------

value_of() {
    grep -m1 "^${1}=" "$OUTPUT" | cut -d= -f2- || true
}

echo
echo "  ---- assertions ----"

HELPER_PROTOCOL="$(value_of 'PROTOCOL')"
EXPECTED_PROTOCOL="$(value_of 'EXPECTED')"
if [[ -n "$HELPER_PROTOCOL" && "$HELPER_PROTOCOL" == "$EXPECTED_PROTOCOL" ]]; then
    check pass "protocol v${HELPER_PROTOCOL} — the installed daemon matches this source"
else
    check fail "protocol mismatch: helper v${HELPER_PROTOCOL:-?}, probe expects v${EXPECTED_PROTOCOL:-?}"
    echo "        Rebuild, reinstall to /Applications, then unregister and re-register the helper." >&2
    exit 1
fi

# The control run is what makes every case below meaningful rather than vacuous.
CONTROL_MS="$(value_of 'CONTROL_RUN_MS')"
WAIT_MS="$(value_of 'PRE_PAUSE_WAIT_MS')"
CONTROL_OUTCOME="$(value_of 'CONTROL_RUN_OUTCOME')"

if [[ "$CONTROL_OUTCOME" == "1" ]]; then
    check pass "an uninterrupted 1 GiB call completes (outcome 1) in ${CONTROL_MS} ms"
else
    check fail "the uninterrupted control run did not complete (outcome ${CONTROL_OUTCOME:-?})"
fi

# Bash arithmetic is integer; compare the millisecond figures with awk.
if awk -v c="${CONTROL_MS:-0}" -v w="${WAIT_MS:-0}" 'BEGIN { exit !(c > w * 1.5) }'; then
    check pass "a bounded call (${CONTROL_MS} ms) is comfortably longer than the ${WAIT_MS} ms wait"
else
    check fail "a bounded call (${CONTROL_MS} ms) is not much longer than the ${WAIT_MS} ms wait —"
    echo "        every pause below lands too near the end for the result to mean anything." >&2
fi

# --- the device-operation slot: a second run while one is in flight ------------------
#
# Added 2026-08-24. `beginDeviceOperation` refuses a second device operation while one holds the
# slot, and NOTHING covered it: `HelperActivity` lives in the helper's `main.swift`, which is
# top-level code and cannot be imported into a test target, and no test asserts the `.deviceBusy`
# refusal either. `claim-contention-test.sh` covers *acquire* contention, which is a different
# question — two clients wanting the drive, not two operations on a drive already held.
#
# It lives HERE rather than in xpc-concurrency-check.sh, which was the first idea and the wrong
# one: that script's headline promise is "READ-ONLY. NOTHING IS WRITTEN TO THE DEVICE", and the
# *failure* mode of this check is a run that escapes the guard and writes. A gate that can no
# longer be run casually is worth less than this check is worth. This script already writes,
# already holds the drive, and already has two connections.
#
# **The idle attempt is the half that makes the busy one mean anything.** Same request, same
# connection, one variable. A refusal on its own proves only that something refused.
SLOT_BUSY_OUTCOME="$(value_of 'SLOT_BUSY_OUTCOME')"
SLOT_BUSY_CHUNKS="$(value_of 'SLOT_BUSY_CHUNKS')"
SLOT_BUSY_MESSAGE="$(value_of 'SLOT_BUSY_MESSAGE')"
SLOT_IDLE_OUTCOME="$(value_of 'SLOT_IDLE_OUTCOME')"
SLOT_IDLE_CHUNKS="$(value_of 'SLOT_IDLE_CHUNKS')"
SLOT_CONTROL_SURVIVED="$(value_of 'SLOT_CONTROL_SURVIVED')"

if [[ "${SLOT_BUSY_OUTCOME:-}" == "0" ]]; then
    check pass "a second run issued while one was in flight was REFUSED"
else
    check fail "a second run issued mid-flight returned outcome ${SLOT_BUSY_OUTCOME:-?}, expected 0 (refused)"
    echo "        THE DEVICE-OPERATION SLOT DID NOT HOLD. Two runs shared one descriptor and one" >&2
    echo "        set of buffers. Run scripts/retention-cycle-check.sh before trusting this drive." >&2
fi

if [[ "${SLOT_BUSY_CHUNKS:-}" == "0" ]]; then
    check pass "the refused call reported no chunks — it did not partially run"
else
    check fail "the refused call reported ${SLOT_BUSY_CHUNKS:-?} chunks, expected 0"
fi

# The refusal must say WHICH operation holds the slot. A bare "busy" would pass the outcome check
# above while telling a user nothing, and this is the message that reaches them.
if grep -q "retention cycle" <<< "${SLOT_BUSY_MESSAGE:-}" && grep -q "${DISK}" <<< "${SLOT_BUSY_MESSAGE:-}"; then
    check pass "the refusal names the operation and the disk: ${SLOT_BUSY_MESSAGE}"
else
    check fail "the refusal does not name both the operation and ${DISK}: ${SLOT_BUSY_MESSAGE:-<empty>}"
fi

if [[ "${SLOT_IDLE_OUTCOME:-}" == "1" ]]; then
    check pass "the SAME call with nothing in flight was ACCEPTED (${SLOT_IDLE_CHUNKS:-?} chunk) — the check discriminates"
else
    check fail "the same call was refused when idle too (outcome ${SLOT_IDLE_OUTCOME:-?}) — INCONCLUSIVE"
    echo "        The busy refusal above proves nothing if this one is refused as well: it would" >&2
    echo "        mean something other than the slot is turning these calls away." >&2
fi

if [[ "${SLOT_CONTROL_SURVIVED:-}" == "1" ]]; then
    check pass "the in-flight run completed normally despite the refused second call"
else
    check fail "the in-flight run did not complete — the refusal disturbed the run it protected"
fi

# Each I/O size, in turn.
for MIB in 1 2 4 8; do
    VERDICT="$(value_of "CASE_${MIB}MIB_VERDICT")"
    OUTCOME="$(value_of "CASE_${MIB}MIB_OUTCOME")"
    CHUNKS="$(value_of "CASE_${MIB}MIB_CHUNKS")"
    RESUME="$(value_of "CASE_${MIB}MIB_RESUME_BLOCK")"
    EXPECTED_RESUME="$(value_of "CASE_${MIB}MIB_EXPECTED_RESUME_BLOCK")"
    ALIGNED="$(value_of "CASE_${MIB}MIB_RESUME_ALIGNED")"
    SETTLE="$(value_of "CASE_${MIB}MIB_SETTLE_MS")"
    ACK="$(value_of "CASE_${MIB}MIB_ACK_MS")"

    case "$VERDICT" in
        SETTLED)
            check pass "${MIB} MiB: settled after ${CHUNKS} chunks, ${SETTLE} ms (daemon acked in ${ACK} ms)"
            ;;
        INCONCLUSIVE_RUN_FINISHED_FIRST)
            check fail "${MIB} MiB: the run completed before the pause landed — INCONCLUSIVE, not a settle"
            ;;
        INCONCLUSIVE_PAUSE_BEFORE_FIRST_CHUNK)
            check fail "${MIB} MiB: no chunk had run when the pause was seen — INCONCLUSIVE"
            ;;
        WRONG_OUTCOME)
            check fail "${MIB} MiB: outcome ${OUTCOME}, expected 3 (pausedByUser)"
            echo "        Outcome 4 here means the helper's outward mapping has pause and stop" >&2
            echo "        swapped — the mutation the unit suite provably cannot catch." >&2
            ;;
        RESUME_POINT_WRONG)
            check fail "${MIB} MiB: resume block ${RESUME}, expected ${EXPECTED_RESUME} (aligned=${ALIGNED})"
            ;;
        *)
            check fail "${MIB} MiB: no verdict recorded"
            ;;
    esac
done

SETTLED="$(value_of 'SETTLED_CASES')"
TOTAL="$(value_of 'TOTAL_CASES')"
if [[ -n "$SETTLED" && "$SETTLED" == "$TOTAL" ]]; then
    check pass "all ${TOTAL} I/O sizes settled at a chunk boundary with the correct resume point"
else
    check fail "${SETTLED:-0} of ${TOTAL:-4} I/O sizes settled"
fi

RELEASED="$(value_of 'RELEASED')"
if [[ -n "$RELEASED" ]]; then
    check pass "device released: ${RELEASED}"
else
    check fail "no release was acknowledged — the claim may still be held"
fi

# ---------------------------------------------------------------------------------------
# The measurement, restated so it is what a reader takes away
# ---------------------------------------------------------------------------------------

echo
echo "  ---- the numbers ----"
echo
printf "  %-10s %10s %10s\n" "I/O size" "ack (ms)" "settle (ms)"
for MIB in 1 2 4 8; do
    printf "  %-10s %10s %10s\n" "${MIB} MiB" \
        "$(value_of "CASE_${MIB}MIB_ACK_MS")" "$(value_of "CASE_${MIB}MIB_SETTLE_MS")"
done
echo
echo "  'ack' is the daemon confirming it recorded the request; 'settle' is the run's own reply"
echo "  carrying pausedByUser. They are different facts and only the second is NFR-REL-10's"
echo "  guarantee — which is why a pause must never be shown as 'Paused' on the strength of the"
echo "  first. Settle latency should track the I/O SIZE, not the 1 GiB call cap."

echo
if [[ "$FAILURES" -eq 0 && "$PROBE_STATUS" -eq 0 ]]; then
    echo "  RESULT: pre-flight PASSED — the design holds."
    exit 0
fi
echo "  RESULT: ${FAILURES} assertion(s) failed (probe exit ${PROBE_STATUS})."
echo "  A failure here is a finding about the DESIGN, not a flaky test. Read the numbers above"
echo "  before changing anything."
exit 1
