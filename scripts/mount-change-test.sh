#!/bin/bash
#
# mount-change-test.sh — regression test for the stale mounted-volume defect.
#
# Mounting and unmounting a volume does NOT change the IOKit whole-media set, so a
# device list watching IOKit alone never notices. Found on 2026-07-30 when a replugged
# drive's volumes auto-mounted and the UI went on showing it as unmounted.
#
# This drives the real discovery code (scripts/device-probe.sh) through an unmount and
# a remount, and asserts both that a refresh fires and that the reported state actually
# changes. Two assertions on purpose: an event with no state change would mean the
# watcher fires but the mount table is read wrong, and a state change with no event
# would mean it only works because something else happened to trigger a rebuild.
#
# Non-destructive: it unmounts and remounts one volume and restores the starting state
# on exit, including on failure. It writes nothing to the device.
#
# Proven to discriminate: with the VolumeChangeWatcher disabled, 3 of the 4 checks fail.
# The fourth ("reports its mounted volume again") passes either way, and inherently so —
# a view that never updates is accidentally correct once the state returns to where it
# started. It is kept because it catches the opposite regression, where a refresh fires
# but the mount table is misread.
#
# Usage:
#   scripts/mount-change-test.sh [--device <serial|diskN>]
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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$REPO_ROOT/scripts/device-probe.sh"
LOG="$(mktemp -t usbdt-mount-change)"
PROBE_PID=""
MOUNT_POINT=""

cleanup() {
    [[ -n "$PROBE_PID" ]] && kill "$PROBE_PID" 2>/dev/null || true
    pkill -f "usbdrivetester-device-probe" 2>/dev/null || true
    # Restore the volume if we left it unmounted.
    if [[ -n "$MOUNT_POINT" && ! -d "$MOUNT_POINT" ]]; then
        echo "restoring: remounting ${DISK}'s volume"
        diskutil mount "$DEVICE_NODE" >/dev/null 2>&1 || true
    fi
    rm -f "$LOG"
}
trap cleanup EXIT

# --- Preconditions -----------------------------------------------------------

DEVICE_NODE="$(mount | awk -v d="/dev/${DISK}s" 'index($1, d) == 1 { print $1; exit }')"
if [[ -z "$DEVICE_NODE" ]]; then
    echo "error: no mounted volume found on $DISK." >&2
    echo "       This test needs one mounted volume to unmount and remount." >&2
    exit 2
fi
MOUNT_POINT="$(mount | awk -v n="$DEVICE_NODE" '$1 == n { print $3; exit }')"
echo "Using $DEVICE_NODE mounted at $MOUNT_POINT"

# `grep -c` prints 0 *and* exits non-zero when there are no matches, so a naive
# `|| echo 0` emits "0\n0" and every later arithmetic comparison is a syntax error.
events() {
    local n
    n=$(grep -c 'device set changed' "$LOG" 2>/dev/null) || n=0
    echo "${n:-0}"
}

# The most recent report block from the *running* watcher — i.e. what the user would be
# looking at right now.
#
# Deliberately not a fresh `device-probe` invocation: a new process re-enumerates from
# scratch and therefore reports the correct mount state whether or not live updating
# works, so it would pass against the very defect this tests for.
latest_report() {
    awk '/^\[/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
}

reports_mounted() {
    latest_report | grep -A6 -- "$DISK —" | grep -q "mounted"
}

# Wait until the watch log gains an event, or time out.
wait_for_event() {
    local baseline="$1" deadline=$((SECONDS + 8))
    while (( SECONDS < deadline )); do
        (( $(events) > baseline )) && return 0
        sleep 0.25
    done
    return 1
}

# --- Arrange -----------------------------------------------------------------

echo "Starting the watcher…"
"$PROBE" --watch > "$LOG" 2>&1 &
PROBE_PID=$!
# Detach from job control so killing it during cleanup does not print "Terminated"
# over the test's own result.
disown "$PROBE_PID" 2>/dev/null || true

# The probe compiles before it runs; wait for it to be watching.
for _ in $(seq 1 120); do
    grep -q "Watching for device changes" "$LOG" && break
    sleep 1
done
grep -q "Watching for device changes" "$LOG" || { echo "FAIL: probe never started"; exit 1; }

FAILURES=0
check() {
    if [[ "$1" == "pass" ]]; then echo "  PASS  $2"; else echo "  FAIL  $2"; FAILURES=$((FAILURES + 1)); fi
}

# --- Act & assert: unmount ---------------------------------------------------

echo
echo "Unmounting ${MOUNT_POINT}..."
BASELINE="$(events)"
diskutil unmount "$MOUNT_POINT" >/dev/null

if wait_for_event "$BASELINE"; then
    check pass "a refresh fired on unmount"
else
    check fail "a refresh fired on unmount (this is the original defect)"
fi
if reports_mounted; then
    check fail "$DISK no longer reports a mounted volume"
else
    check pass "$DISK no longer reports a mounted volume"
fi

# --- Act & assert: remount ---------------------------------------------------

echo
echo "Remounting ${DEVICE_NODE}..."
BASELINE="$(events)"
diskutil mount "$DEVICE_NODE" >/dev/null

if wait_for_event "$BASELINE"; then
    check pass "a refresh fired on mount"
else
    check fail "a refresh fired on mount"
fi
if reports_mounted; then
    check pass "$DISK reports its mounted volume again"
else
    check fail "$DISK reports its mounted volume again"
fi

echo
if (( FAILURES == 0 )); then
    echo "mount-change-test: PASS"
else
    echo "mount-change-test: FAIL ($FAILURES check(s))"
    exit 1
fi
