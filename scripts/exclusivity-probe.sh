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
#   scripts/exclusivity-probe.sh disk4
#
set -euo pipefail

DISK="${1:-}"
if [[ -z "$DISK" ]]; then
    echo "usage: $0 <whole-disk-bsd-name>   e.g. $0 disk4" >&2
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
        echo "Restoring mounts on $DISK…"
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
echo "Unmounting $DISK…"
diskutil unmountDisk "$DISK"
sudo "$BUILD_DIR/exclusivity-probe" "$DISK" || true
