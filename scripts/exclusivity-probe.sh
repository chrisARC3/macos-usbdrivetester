#!/bin/bash
#
# exclusivity-probe.sh — measure what "exclusive whole-disk access" means here.
#
# Step 6 has to distinguish "volumes still mounted" from "the node is claimed by another
# process" (FR-SAFE-4). Which mechanism actually provides exclusivity — a plain O_RDWR
# open, O_EXLOCK, or DADiskClaim — decides both the acquire path and whether that second
# case is detectable at all. This measures it instead of assuming it.
#
# Runs the probe twice: once with the disk's volumes mounted, once with them unmounted,
# then restores the mounts. The compile runs as you; only the probe itself runs as root,
# because /dev/rdiskN is root:operator.
#
# THE PROBE NEVER WRITES TO THE DEVICE. It opens, locks, claims, then releases.
#
# Usage:
#   scripts/exclusivity-probe.sh [--device <serial|diskN>]
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

# --- Preflight: this needs an interactive terminal -----------------------------------
#
# The probe runs as root because /dev/rdiskN is root:operator. If sudo has no cached
# credentials and there is no TTY to prompt on — which is the case when this is launched
# from a "run" button rather than a terminal — sudo cannot ask for a password and the
# script would otherwise stall or die with nothing useful on screen. Say so instead.
if ! sudo -n true 2>/dev/null && [[ ! -t 0 ]]; then
    cat >&2 <<'MSG'
error: this script needs an interactive terminal.

  It runs one command as root (the probe itself), because /dev/rdiskN is
  root:operator. sudo has no cached credentials and there is no terminal to
  prompt for a password on.

  Open Terminal and run it there:

      cd /Volumes/1TB_Samsung/AI_Stuff/claude-code-folder/USBDriveTester
      ./scripts/exclusivity-probe.sh

MSG
    exit 2
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Built outside the repo: this volume is removable, and root's access to binaries on it
# is gated (the same gotcha that bit scripts/negative-test.sh in Step 3).
BUILD_DIR="/tmp/usbdrivetester-exclusivity-probe"
mkdir -p "$BUILD_DIR"

WAS_MOUNTED=0
restore() {
    if [[ "$WAS_MOUNTED" == "1" ]]; then
        echo
        echo "Restoring mounts on ${DISK}..."
        diskutil mountDisk "$DISK" >/dev/null 2>&1 || true
    fi
}
trap restore EXIT

echo "Compiling probe…"
xcrun swiftc \
    -swift-version 5 \
    -target arm64-apple-macos26.0 \
    -o "$BUILD_DIR/exclusivity-probe" \
    "$REPO_ROOT/tools/exclusivity-probe/main.swift"

echo
echo "############ PHASE 1 — volumes MOUNTED ############"
if mount | grep -q "^/dev/${DISK}s"; then
    WAS_MOUNTED=1
else
    echo "(note: nothing is mounted on $DISK, so phase 1 is not the mounted case)"
fi
sudo "$BUILD_DIR/exclusivity-probe" "$DISK" || true

echo
echo "############ PHASE 2 — volumes UNMOUNTED ############"
echo "Unmounting ${DISK}..."
diskutil unmountDisk "$DISK"
sudo "$BUILD_DIR/exclusivity-probe" "$DISK" || true

echo
echo "############ PHASE 3 — UNMOUNTED, another PROCESS holding ############"
echo "This is the FR-SAFE-4(b) case: the volumes are unmounted but a different"
echo "process holds the device. A second session inside one process is not the"
echo "same thing and can behave differently."
echo
# Re-unmount first. On the previous run macOS silently remounted the volume between
# phases — the moment phase 2's probe exited and released its claim — so the holder's
# open failed on a mounted disk and this phase measured nothing. That remount is itself
# the reason FR-SAFE-3 requires a claim, and it is why the holder below claims *before*
# opening and keeps the claim for its whole life.
echo "Re-unmounting ${DISK} (it may have been auto-remounted)..."
diskutil unmountDisk "$DISK" || true

HOLD_LOG="$(mktemp -t usbdt-hold)"
sudo "$BUILD_DIR/exclusivity-probe" "$DISK" --hold 20 > "$HOLD_LOG" 2>&1 &
HOLD_PID=$!

# Wait for the holder to report that it has actually acquired the device, rather
# than racing it with a fixed sleep. NOT-HOLDING means it failed to acquire, and
# proceeding then would measure contention that does not exist.
for _ in $(seq 1 60); do
    grep -qE "HOLDING|NOT-HOLDING" "$HOLD_LOG" && break
    sleep 0.5
done

if grep -q "^HOLDING" "$HOLD_LOG"; then
    echo "--- what the holding process got ---"
    sed 's/^/  /' "$HOLD_LOG"
    echo
    echo "--- what a second process sees while that is held ---"
    sudo "$BUILD_DIR/exclusivity-probe" "$DISK" || true
else
    echo "the holder did not acquire the device, so there is no contention to measure."
    echo "its output was:"
    sed 's/^/  /' "$HOLD_LOG"
fi

sudo kill "$HOLD_PID" 2>/dev/null || true
wait "$HOLD_PID" 2>/dev/null || true
rm -f "$HOLD_LOG"
