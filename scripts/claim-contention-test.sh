#!/bin/bash
#
# claim-contention-test.sh — Step 6 mount guard, mechanised (FR-SAFE-1/2/3/4, NFR-REL-5).
#
# Drives the LIVE privileged helper through the three outcomes the gate cares about and
# asserts the cause code it reports for each:
#
#   A. volumes mounted           -> refused, cause 2 (FR-SAFE-4(a))
#   B. unmounted, another        -> refused, cause 3 (FR-SAFE-4(b))
#      process holding the disk
#   C. unmounted, nothing else   -> ACQUIRED, then released cleanly
#      holding it
#
# and two properties that are easy to get wrong and invisible from the GUI:
#
#   D. starting a test never unmounts anything (FR-SAFE-6) — the mount state after a
#      refusal is identical to the mount state before it.
#   E. a claim does not outlive the connection that took it (NFR-REL-5) — a client that
#      acquires and exits without releasing leaves the helper holding nothing.
#
# The cause code is asserted, not the prose. A human comparing two messages can only
# confirm they differ; the app branches on the code, so that is what is checked.
#
# PREREQUISITES
#   * The helper must be registered and enabled via SMAppService. Run the installed app,
#     choose "Register helper", approve it in System Settings. This script tests a live
#     daemon; it cannot install one.
#   * An interactive Terminal: phase B runs the holder as root, and sudo needs a TTY to
#     prompt on.
#
# NON-DESTRUCTIVE. Nothing is ever written to the device. It unmounts and remounts the
# scratch drive's volumes and restores them on exit, including on failure.
#
# Usage:
#   scripts/claim-contention-test.sh [--device <serial|diskN>]
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
LABEL="com.arc3solutions.USBDriveTester.Helper"
TEAM_ID="5JC55GTLZA"

# Built outside the repo: this volume is removable and macOS gates daemon access to it.
BUILD_DIR="/tmp/usbdrivetester-mount-guard"
CLIENT="$BUILD_DIR/mount-guard-client"
PROBE="$BUILD_DIR/exclusivity-probe"

SHARED="$REPO_ROOT/USBDriveTester/USBDriveTester/Shared/TesterControl.swift"

FAILURES=0
HOLD_PID=""

check() {
    if [[ "$1" == "pass" ]]; then
        echo "  PASS  $2"
    else
        echo "  FAIL  $2"
        FAILURES=$((FAILURES + 1))
    fi
}

cleanup() {
    if [[ -n "$HOLD_PID" ]]; then
        sudo kill "$HOLD_PID" 2>/dev/null || true
        wait "$HOLD_PID" 2>/dev/null || true
    fi
    echo
    echo "Restoring mounts on ${DISK}…"
    # Best effort: the helper may still hold the disk if a phase died mid-way, and
    # release is asynchronous, so give it a moment before remounting.
    "$CLIENT" "$DISK" release >/dev/null 2>&1 || true
    sleep 2
    diskutil mountDisk "$DISK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- Preflight ---------------------------------------------------------------

if ! sudo -n true 2>/dev/null && [[ ! -t 0 ]]; then
    # Derived, not hard-coded: this repository lives on a removable volume and has
    # already moved once (1TB_Samsung -> 1TB_UGreen, 2026-09-04), which turned a
    # pasteable instruction into a path that does not exist.
    cat >&2 <<MSG
error: this script needs an interactive terminal.

  Phase B runs a holder process as root, because /dev/rdiskN is root:operator.
  sudo has no cached credentials and there is no terminal to prompt on.

  Open Terminal and run it there:

      cd $(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
      ./scripts/claim-contention-test.sh

MSG
    exit 2
fi

echo "=============================================================="
echo " Step 6 mount guard — cause classification on real hardware"
echo "=============================================================="
echo

echo "--- Checking the helper is registered ---"
if ! launchctl print "system/$LABEL" >/dev/null 2>&1; then
    echo "error: LaunchDaemon '$LABEL' is not loaded in the system domain." >&2
    echo "       Run the app, choose 'Register helper', and approve it in" >&2
    echo "       System Settings > General > Login Items & Extensions first." >&2
    exit 2
fi
echo "ok: $LABEL is loaded."
echo

# --- Build and sign the client ------------------------------------------------

echo "--- Building the test client ---"
mkdir -p "$BUILD_DIR"
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -O \
    -o "$CLIENT" "$SHARED" "$REPO_ROOT/tools/mount-guard-client/main.swift"
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 \
    -o "$PROBE" "$REPO_ROOT/tools/exclusivity-probe/main.swift"

# Sign with the real Apple Development identity. Unlike negative-test.sh, this client
# MUST satisfy the helper's Team-ID requirement — an adhoc one would be invalidated on
# its first message and every phase below would read as a transport failure rather than
# as the refusal it is supposed to be measuring.
IDENTITY="$(security find-identity -v -p codesigning \
            | awk '/Apple Development/ { print $2; exit }')"
if [[ -z "$IDENTITY" ]]; then
    echo "error: no 'Apple Development' codesigning identity found." >&2
    exit 2
fi
codesign --force --sign "$IDENTITY" --options runtime "$CLIENT"

# Captured first, then matched against a here-string — NOT `codesign … | grep -q`.
#
# Under `set -o pipefail` that pipeline reports failure exactly when it succeeds:
# `grep -q` exits on the first match and closes the pipe, `codesign` dies of SIGPIPE
# writing the rest of its (long) output, and pipefail promotes that non-zero status to
# the whole pipeline. So the check fired only when the client WAS correctly signed —
# which is what aborted the first real run of this script on 2026-08-01.
CLIENT_SIGNATURE="$(codesign -dvvv "$CLIENT" 2>&1 || true)"
if ! grep -q "TeamIdentifier=$TEAM_ID" <<<"$CLIENT_SIGNATURE"; then
    echo "error: the client is not signed under team $TEAM_ID, so the helper would" >&2
    echo "       reject it and every result below would be a transport failure." >&2
    echo "       Its actual signature:" >&2
    sed 's/^/         /' <<<"$CLIENT_SIGNATURE" >&2
    exit 2
fi
echo "ok: client signed under team $TEAM_ID."
echo

# --- Helpers ------------------------------------------------------------------

# Run the client and capture its output. Never aborts the script: a non-zero exit is
# itself a result worth asserting on.
run_client() {
    local out
    set +e
    out="$("$CLIENT" "$DISK" "$@" 2>&1)"
    set -e
    printf '%s\n' "$out"
}

# Extract KEY=value from the client's output, scoped to the command that printed it.
#
# The command scope is not optional. A single invocation runs several commands on one
# connection, so `check` and `acquire` each print a MESSAGE — and an unscoped match took
# the first, which is `check`'s. That is what made phase B report "the refusal does not
# say another process holds the node" when the refusal said exactly that: it was reading
# the readiness message ("...confirm no OTHER process holds the device") instead of the
# acquire refusal ("...held by ANOTHER process"). Phase A's equivalent assertion passed
# only because both messages happen to contain the volume name — luck, not correctness.
#
# Usage: value_of <output> <command> <key>
value_of() {
    printf '%s\n' "$1" | sed -n "s/^\[$2\] $3=//p" | head -1
}

mounted_volume_count() {
    mount | grep -c "^/dev/${DISK}s" || true
}

# --- Phase A: volumes mounted -> cause 2 (FR-SAFE-4(a)) -----------------------

echo "--- Phase A: volumes MOUNTED (expect refusal, cause 2) ---"
diskutil mountDisk "$DISK" >/dev/null 2>&1 || true
sleep 1

BEFORE_A="$(mounted_volume_count)"
if [[ "$BEFORE_A" -eq 0 ]]; then
    echo "  SKIP  $DISK has no mountable volumes, so cause (a) cannot be produced."
    echo "        Use a drive with a filesystem on it (the exFAT scratch drive)."
    FAILURES=$((FAILURES + 1))
else
    OUT_A="$(run_client check acquire)"
    printf '%s\n' "$OUT_A" | sed 's/^/    /'

    [[ "$(value_of "$OUT_A" acquire ACQUIRED)" == "0" ]] \
        && check pass "acquire refused while a volume is mounted" \
        || check fail "acquire refused while a volume is mounted"

    [[ "$(value_of "$OUT_A" acquire CAUSE)" == "2" ]] \
        && check pass "cause is 2 (volumes mounted), not 3" \
        || check fail "cause is 2 (volumes mounted), got '$(value_of "$OUT_A" acquire CAUSE)'"

    # The message must name the volume, or the user has nothing to act on (NFR-USE-5).
    VOLUME_NAME="$(value_of "$OUT_A" check MOUNTED)"
    # Here-string, not a pipe: see the note on the Team-ID check above.
    if [[ -n "$VOLUME_NAME" ]] && grep -qF "$VOLUME_NAME" <<<"$(value_of "$OUT_A" acquire MESSAGE)"; then
        check pass "the refusal names the mounted volume ($VOLUME_NAME)"
    else
        check fail "the refusal names the mounted volume"
    fi

    # FR-SAFE-6: the refusal changed nothing.
    AFTER_A="$(mounted_volume_count)"
    [[ "$AFTER_A" -eq "$BEFORE_A" ]] \
        && check pass "the refusal did not unmount anything (FR-SAFE-6)" \
        || check fail "the refusal changed the mount state: $BEFORE_A -> $AFTER_A"
fi
echo

# --- Phase B: unmounted, another process holding -> cause 3 (FR-SAFE-4(b)) ----

echo "--- Phase B: UNMOUNTED, another process holding (expect refusal, cause 3) ---"
echo "Unmounting ${DISK}…"
diskutil unmountDisk "$DISK" >/dev/null

HOLD_LOG="$BUILD_DIR/hold.log"
sudo "$PROBE" "$DISK" --hold 30 > "$HOLD_LOG" 2>&1 &
HOLD_PID=$!

for _ in $(seq 1 60); do
    grep -qE "HOLDING|NOT-HOLDING" "$HOLD_LOG" && break
    sleep 0.5
done

if grep -q "^HOLDING" "$HOLD_LOG"; then
    OUT_B="$(run_client check acquire)"
    printf '%s\n' "$OUT_B" | sed 's/^/    /'

    [[ "$(value_of "$OUT_B" check MOUNTED_COUNT)" == "0" ]] \
        && check pass "the helper sees no mounted volumes" \
        || check fail "the helper sees no mounted volumes"

    [[ "$(value_of "$OUT_B" acquire ACQUIRED)" == "0" ]] \
        && check pass "acquire refused while another process holds the disk" \
        || check fail "acquire refused while another process holds the disk"

    # The assertion this whole script exists for: with nothing mounted, the helper must
    # report cause 3 and NOT cause 2. Both underlying failures are the same EBUSY.
    [[ "$(value_of "$OUT_B" acquire CAUSE)" == "3" ]] \
        && check pass "cause is 3 (held by another process), not 2" \
        || check fail "cause is 3 (held by another process), got '$(value_of "$OUT_B" acquire CAUSE)'"

    grep -q "another process" <<<"$(value_of "$OUT_B" acquire MESSAGE)" \
        && check pass "the refusal says another process holds the node" \
        || check fail "the refusal says another process holds the node"
else
    check fail "the holder acquired the device (nothing to contend with)"
    sed 's/^/    /' "$HOLD_LOG"
fi

sudo kill "$HOLD_PID" 2>/dev/null || true
wait "$HOLD_PID" 2>/dev/null || true
HOLD_PID=""
echo

# --- Phase C: unmounted, uncontended -> ACQUIRED, then released ---------------

echo "--- Phase C: UNMOUNTED and free (expect ACQUIRED, then a clean release) ---"
# The holder released a moment ago and release is asynchronous — an open straight after
# DADiskUnclaim can still see EBUSY (measured 2026-07-30). Give it a beat, and re-unmount
# in case macOS remounted the volumes the instant the claim dropped (also measured).
sleep 3
diskutil unmountDisk "$DISK" >/dev/null 2>&1 || true
sleep 1

OUT_C="$(run_client acquire check release)"
printf '%s\n' "$OUT_C" | sed 's/^/    /'

[[ "$(value_of "$OUT_C" acquire ACQUIRED)" == "1" ]] \
    && check pass "acquire succeeded on an unmounted, uncontended disk" \
    || check fail "acquire succeeded on an unmounted, uncontended disk"

[[ "$(value_of "$OUT_C" check HELD)" == "1" ]] \
    && check pass "the helper reports it holds the device" \
    || check fail "the helper reports it holds the device"

[[ "$(value_of "$OUT_C" release RELEASED)" == "1" ]] \
    && check pass "release succeeded" \
    || check fail "release succeeded"
echo

# --- Phase E: a claim does not outlive its connection (NFR-REL-5) -------------

echo "--- Phase E: connection loss releases the claim ---"
sleep 3
diskutil unmountDisk "$DISK" >/dev/null 2>&1 || true
sleep 1

# Acquire and exit WITHOUT releasing. The client deliberately does not invalidate its
# connection on the way out, so this is the same shape as the GUI being force-quit.
OUT_E1="$(run_client acquire)"
printf '%s\n' "$OUT_E1" | sed 's/^/    /'

if [[ "$(value_of "$OUT_E1" acquire ACQUIRED)" == "1" ]]; then
    sleep 2   # the helper releases on invalidation, which is not instantaneous
    OUT_E2="$(run_client check)"
    printf '%s\n' "$OUT_E2" | sed 's/^/    /'

    [[ "$(value_of "$OUT_E2" check HELD)" == "0" ]] \
        && check pass "the claim was released when the client exited (NFR-REL-5)" \
        || check fail "the claim was released when the client exited — it is STILL held"
else
    check fail "could not acquire, so connection-loss release was not exercised"
fi
echo

# --- Verdict ------------------------------------------------------------------

echo "=============================================================="
if (( FAILURES == 0 )); then
    echo " claim-contention-test: PASS"
else
    echo " claim-contention-test: FAIL ($FAILURES check(s))"
fi
echo "=============================================================="
exit $(( FAILURES == 0 ? 0 : 1 ))
