#!/bin/bash
#
# xpc-concurrency-check.sh — Step 9's design pre-flight (decision D1).
#
# Answers one question, on the live daemon, before any of Step 9 is written:
#
#   While the helper is inside a long privileged call, will it service a SECOND XPC
#   message — (a) on the same connection, (b) on a second connection?
#
# If it will, Step 9's progress channel is a **poll**: one additive query method the GUI
# calls on a 1 Hz timer. If it will not, Step 9 must build a **push** — a reverse @objc
# protocol, an exported object on the app side, and the helper calling back into a client.
# BUILD-PLAN 9.4 assumes the push. Nothing has ever measured whether it is necessary.
#
# The cost of guessing is not hypothetical. Step 8 designed its gate around fingerprinting
# from a separate process, and that turned out to be impossible while `O_EXLOCK` is held
# (EBUSY, measured 2026-08-02). It cost nothing only because it was measured BEFORE the
# design was committed to. This is the same move, for the same reason.
#
# READ-ONLY. NOTHING IS WRITTEN TO THE DEVICE.
#   The long call underneath the pings is `digestRange` — SHA-256 over a bounded range, one
#   read pass — deliberately, and not `runRetentionCycle`. The XPC delivery question is
#   identical for both, and answering it does not require putting a byte on the drive.
#
#   It DOES change mount state: the exclusive open requires the disk unmounted. The mount
#   state is restored on every exit path, as in geometry-check.sh.
#
# PREREQUISITES
#   * The helper must be registered, enabled and running from /Applications
#     (scripts/install-app.sh). This tests a live daemon; it cannot install one.
#   * The helper needs FULL DISK ACCESS (NFR-INST-4) or the acquire fails EPERM. Root is
#     not sufficient.
#   * An interactive Terminal, for `codesign`'s keychain access when signing the probe.
#     This script does NOT use sudo — the helper is already root and does every device
#     access; the probe runs unprivileged.
#
# Usage:
#   scripts/xpc-concurrency-check.sh [--device <serial|diskN>]
#
set -euo pipefail

# The target drive is resolved by USB SERIAL NUMBER, not by the BSD name on the command line
# (2026-08-06). A reboot renumbers these; `disk4` was this project's scratch device until one did,
# and then named the 22 TB backup drive. An old-style bare `diskN` argument is still accepted —
# it is CHECKED against the serial, and refused if it names a different drive.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/device-identity.sh"
parse_device_flag "$@" || exit 2
set -- ${DEVICE_FLAG_REMAINING[@]+"${DEVICE_FLAG_REMAINING[@]}"}
DISK="$(resolve_target scratch "$DEVICE_ARGUMENT")" || exit 1

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="5JC55GTLZA"

# Built outside the repo: this volume is removable and macOS gates daemon access to it.
BUILD_DIR="/tmp/usbdrivetester-xpc-concurrency"
PROBE="$BUILD_DIR/xpc-concurrency-probe"
OUTPUT="$BUILD_DIR/probe-output.txt"

SHARED="$REPO_ROOT/USBDriveTester/USBDriveTester/Shared/TesterControl.swift"
PROBE_SRC="$REPO_ROOT/tools/xpc-concurrency-probe/main.swift"

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

# The name checks that used to live here — "is this a canonical whole-disk name", "is it disk0 or
# disk6" — are gone, and were not merely deleted. `resolve_target` has already established which
# physical drive this is BY SERIAL NUMBER and cross-checked its geometry, which is a stronger
# statement than any list of names can make. Those checks were also, by 2026-08-06, wrong: they
# were written when the scratch device was disk4, and a reboot made disk4 the backup drive.

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

# The "not disk4" warning that used to live here is gone: `resolve_target scratch` establishes
# the drive by serial number before anything runs, so there is no longer a case where this script
# is pointed at a drive nobody meant. Warning about a BSD name would now warn about the wrong
# thing — it was disk4 that stopped being the scratch device, not the drive that changed.

cat <<EOF

  xpc-concurrency-check.sh — Step 9 design pre-flight (decision D1)

  Device     ${DISK}  (${DU_MEDIA_NAME})

  This will UNMOUNT ${DISK}'s volumes, have the helper acquire it, run ONE read-only 1 GiB
  SHA-256 pass, ping the daemon underneath it on two connections, and release.

  NOTHING IS WRITTEN to the device. Expect it to take about ten seconds.

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

# The helper pins callers to the Team ID and invalidates anything else on its first message.
# An unsigned probe would make every result read as a transport failure — which would look
# exactly like "the daemon would not answer", i.e. the serialized verdict. Asserted, not
# assumed.
codesign --force --sign "Apple Development" --timestamp=none "$PROBE" 2>/dev/null \
    || codesign --force --sign - "$PROBE" >/dev/null 2>&1 || true

SIGNING="$(codesign -dv --verbose=4 "$PROBE" 2>&1 || true)"
if grep -q "TeamIdentifier=${TEAM_ID}" <<< "$SIGNING"; then
    check pass "probe is signed under team ${TEAM_ID}, so the helper will accept it"
else
    check fail "probe is NOT signed under team ${TEAM_ID} — every ping would fail as a transport"
    echo "        error, which is indistinguishable from the daemon refusing to answer." >&2
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

value_of() {
    local key="$1" out
    out="$(grep -- "$key=" "$OUTPUT" || true)"
    sed "s/.*${key}=//" <<< "$out" | head -1
}

# ---------------------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------------------

echo
echo "  ── assertions ──────────────────────────────────────────────────────────────────"
echo

HELPER_PROTOCOL="$(value_of 'PROTOCOL')"
EXPECTED_PROTOCOL="$(value_of 'EXPECTED')"
if [[ -n "$HELPER_PROTOCOL" && "$HELPER_PROTOCOL" == "$EXPECTED_PROTOCOL" ]]; then
    check pass "the running daemon implements protocol v${HELPER_PROTOCOL}, as this build expects"
else
    check fail "protocol mismatch: daemon v${HELPER_PROTOCOL:-<none>}, expected v${EXPECTED_PROTOCOL:-?}"
    echo "        Re-install and re-register the helper (scripts/install-app.sh), then use the" >&2
    echo "        app's Check version button to confirm the running daemon is the new one." >&2
fi

if [[ "$(value_of 'ACQUIRED')" == "1" ]]; then
    check pass "the helper acquired ${DISK}"
else
    check fail "the helper did NOT acquire ${DISK} (cause $(value_of 'CAUSE'))"
    echo "        $(value_of 'MESSAGE')" >&2
    exit 1
fi

if [[ "$(value_of 'DIGEST_OK')" == "1" ]]; then
    check pass "the read-only digest completed ($(value_of 'BYTES') bytes)"
else
    check fail "the digest did not complete — there was no long call to test against"
fi

# The vacuity guard. A digest that returned in 50 ms proves nothing about a call that is
# in flight, and "no ping was delayed" would be a pass that could not have failed.
WINDOW_MS="$(value_of 'WINDOW_MS')"
if [[ "$(value_of 'MEANINGFUL_WINDOW')" == "1" ]]; then
    check pass "the digest held the daemon for ${WINDOW_MS} ms — a wide enough window to test"
else
    check fail "the in-flight window was only ${WINDOW_MS:-?} ms; neither verdict is a result"
    echo "        $(value_of 'NOTE')" >&2
fi

ANSWERED="$(grep -c '\[during\]\|\[after\]' "$OUTPUT" || true)"
if [[ "${ANSWERED:-0}" -gt 0 ]]; then
    check pass "${ANSWERED} ping(s) issued during the call produced a timestamped reply"
else
    check fail "no ping produced a timestamped reply; there is no evidence either way"
fi

# ---------------------------------------------------------------------------------------
# The finding
# ---------------------------------------------------------------------------------------

# `grep -m1` rather than `… | head -1`: head exiting early can SIGPIPE the producer, which
# under `set -o pipefail` fails the pipeline on a SUCCESSFUL match. That is this project's
# recorded pipefail gotcha arriving by a slightly different door.
qualified_value_of() {
    local line
    line="$(grep -m1 -- "$1" "$OUTPUT" || true)"
    sed 's/.*=//' <<< "$line"
}

SAME_VERDICT="$(qualified_value_of 'SAME_CONNECTION] VERDICT=')"
SECOND_VERDICT="$(qualified_value_of 'SECOND_CONNECTION] VERDICT=')"
SAME_DURING="$(qualified_value_of 'SAME_CONNECTION] ANSWERED_DURING=')"
SECOND_DURING="$(qualified_value_of 'SECOND_CONNECTION] ANSWERED_DURING=')"

# The worst latency is computed over replies that arrived DURING the call. When none did,
# that maximum is 0.0 — and "0.0 ms" under a column headed "worst reply during the call"
# reads as excellent when it actually means "never happened". A number that reads as a pass
# when it means "no data" is this project's most expensive recurring defect, so the
# no-data case is spelled out rather than printed as a zero.
worst_reply() {
    local during="$1" key="$2"
    if [[ "${during:-0}" == "0" ]]; then
        echo "n/a — none answered during"
    else
        echo "$(qualified_value_of "$key") ms"
    fi
}

echo
echo "  ── the finding ─────────────────────────────────────────────────────────────────"
echo
printf '    same connection      %-14s  worst reply during the call: %s\n' \
    "${SAME_VERDICT:-<none>}" \
    "$(worst_reply "$SAME_DURING" 'SAME_CONNECTION] MAX_LATENCY_DURING_MS=')"
printf '    second connection    %-14s  worst reply during the call: %s\n' \
    "${SECOND_VERDICT:-<none>}" \
    "$(worst_reply "$SECOND_DURING" 'SECOND_CONNECTION] MAX_LATENCY_DURING_MS=')"
echo

case "$SAME_VERDICT" in
    concurrent)
        check pass "same-connection delivery is CONCURRENT"
        echo
        echo "    → D1 resolves to POLL. Step 9 adds ONE additive query method to TesterControl"
        echo "      (protocol v8) and the GUI calls it on a 1 Hz timer. No reverse protocol, no"
        echo "      exported object on the app side, and the ≥1/s cadence of NFR-PERF-5 is owned"
        echo "      by the GUI's own timer rather than by the daemon."
        ;;
    serialized)
        check pass "same-connection delivery is SERIALIZED (a definite finding, not a failure)"
        echo
        echo "    → A poll on the run's OWN connection cannot be answered while"
        echo "      runRetentionCycle is in flight. That is the finding, and it is unchanged."
        if [[ "$SECOND_VERDICT" == "concurrent" ]]; then
            echo
            echo "      A SECOND connection was answered concurrently, and that is what Step 9"
            echo "      built: the GUI polls runProgress on a separate, NON-OWNING connection."
            echo "      Release-on-connection-loss is scoped to the connection that acquired"
            echo "      (NFR-REL-5), so the progress connection dropping releases nothing."
            echo
            echo "      This branch used to end 'D1 resolves to PUSH … Step 9 must build the"
            echo "      reverse channel'. That was the PRE-FLIGHT's reading, written before the"
            echo "      second-connection number existed — and the decision went the other way."
            echo "      Corrected 2026-08-06: no reverse interface was built, the daemon still"
            echo "      never initiates traffic to a client, and a reader following the old text"
            echo "      would have built a channel the product does not have."
        else
            echo
            echo "      NOTE: the second connection was NOT answered concurrently this time."
            echo "      Step 9's progress design depends on it being so — investigate before"
            echo "      trusting any live-metrics result."
        fi
        ;;
    *)
        check fail "same-connection verdict is '${SAME_VERDICT:-<none>}' — no result to build on"
        echo
        echo "    → Do NOT pick a mechanism from this run. Read the per-ping table above: it"
        echo "      shows what actually happened, and a verdict this probe refuses to give is"
        echo "      one the evidence did not support."
        ;;
esac

echo
if [[ "$PROBE_STATUS" != "0" && "$FAILURES" -eq 0 ]]; then
    # The probe exits non-zero when it could not reach a definite verdict. If every
    # assertion above passed, that disagreement is itself worth surfacing rather than
    # absorbing — the two must not be allowed to drift apart silently.
    check fail "the probe exited ${PROBE_STATUS} but every assertion here passed; investigate"
fi

if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${FAILURES} failures. D1 is decided by the finding above."
else
    echo "  ${FAILURES} failure(s) — see FAIL lines above."
fi
echo "  Full output: ${OUTPUT}"

exit "$FAILURES"
