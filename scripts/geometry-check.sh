#!/bin/bash
#
# geometry-check.sh — Step 7's hardware gate, mechanised.
#
# Drives the LIVE privileged helper through an acquire, asks it what it established about the
# device, and asserts every answer against an independent source:
#
#   1. GEOMETRY (gate item 1). The ioctl-derived block size, block count and byte count must
#      match `diskutil info` exactly.
#   2. RECONCILIATION (BUILD-PLAN 7.3). The helper's own IOKit reading is reported alongside
#      the ioctl values, so agreement is visible rather than assumed.
#   3. UNCACHED I/O (gate item 4, FR-TEST-9). The cache-bypass verdict must be `bypassed` — the
#      helper opened the raw CHARACTER device and both fcntl calls succeeded.
#   4. LINK SPEED. The negotiated USB speed the throughput falsifier derives its ceiling from,
#      cross-checked against tools/usb-speed-probe.
#
# Gate items 2 (chunk plan) and 3 (bounded memory) are discharged by unit tests — they need no
# hardware and asserting them here would be weaker, not stronger.
#
# READ-ONLY. Step 7 writes nothing to the device: the first byte written to real media is
# Step 8's, and NFR-REL-1 puts the simulation proof of non-destructiveness ahead of it. This
# script acquires, reads properties, and releases. It DOES change mount state — the exclusive
# open requires the disk unmounted — and restores it on every exit path.
#
# PREREQUISITES
#   * The helper must be registered and enabled via SMAppService, and running from
#     /Applications (see scripts/install-app.sh). This tests a live daemon; it cannot install
#     one.
#   * The helper needs FULL DISK ACCESS (NFR-INST-4) or the acquire fails EPERM. Running as
#     root is not sufficient.
#   * An interactive Terminal, for `codesign`'s keychain access when signing the client.
#     (Corrected 2026-08-03: this line used to say sudo needs a TTY. It does not — this script
#     never invokes sudo. The helper is already root and does every device access; the client
#     runs unprivileged. Inherited wording from the probe scripts, which genuinely do run under
#     sudo: claim-contention-test.sh, large-address-check.sh, nocache-calibration.sh.)
#
# Usage:
#   scripts/geometry-check.sh [--device <serial|diskN>]
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
BUILD_DIR="/tmp/usbdrivetester-geometry"
CLIENT="$BUILD_DIR/mount-guard-client"
SPEED_PROBE="$BUILD_DIR/usb-speed-probe"
OUTPUT="$BUILD_DIR/profile-output.txt"

SHARED="$REPO_ROOT/USBDriveTester/USBDriveTester/Shared/TesterControl.swift"
CLIENT_SRC="$REPO_ROOT/tools/mount-guard-client/main.swift"
SPEED_SRC="$REPO_ROOT/tools/usb-speed-probe/main.swift"

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
DU_BLOCK_SIZE="$(awk -F: '/Device Block Size/ { gsub(/[^0-9]/, "", $2); print $2 }' <<< "$DU_INFO")"
DU_BYTES="$(sed -n 's/.*Disk Size:.*(\([0-9][0-9]*\) Bytes).*/\1/p' <<< "$DU_INFO" | head -1)"

if [[ -z "$DU_BLOCK_SIZE" || -z "$DU_BYTES" ]]; then
    echo "refusing: could not read ${DISK}'s geometry from diskutil; nothing to compare against" >&2
    exit 2
fi
DU_BLOCK_COUNT=$(( DU_BYTES / DU_BLOCK_SIZE ))

# The "not disk4" warning that used to live here is gone: `resolve_target scratch` establishes
# the drive by serial number before anything runs, so there is no longer a case where this script
# is pointed at a drive nobody meant. Warning about a BSD name would now warn about the wrong
# thing — it was disk4 that stopped being the scratch device, not the drive that changed.

cat <<EOF

  geometry-check.sh — Step 7 hardware gate

  Device     ${DISK}  (${DU_MEDIA_NAME})
  diskutil   ${DU_BYTES} bytes, ${DU_BLOCK_SIZE}-byte blocks, ${DU_BLOCK_COUNT} blocks

  This will UNMOUNT ${DISK}'s volumes, have the helper acquire it, read its properties, and
  release. NOTHING IS WRITTEN to the device. Press Return to continue, or Ctrl-C to abort.

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
# Build and sign the client
# ---------------------------------------------------------------------------------------

echo "  building the client …"
mkdir -p "$BUILD_DIR"
for src in "$SHARED" "$CLIENT_SRC" "$SPEED_SRC"; do
    if [[ ! -f "$src" ]]; then
        echo "  FAIL  source not found: ${src}" >&2
        exit 1
    fi
done

xcrun swiftc -swift-version 5 -O "$SHARED" "$CLIENT_SRC" -o "$CLIENT"
xcrun swiftc -swift-version 5 -O "$SPEED_SRC" -o "$SPEED_PROBE"

# The helper pins callers to the Team ID and invalidates anything else on its first message.
# An unsigned client would make every result read as a transport failure, so the signature is
# asserted rather than assumed — the inverse of the check negative-test.sh makes.
codesign --force --sign "Apple Development" --timestamp=none "$CLIENT" 2>/dev/null \
    || codesign --force --sign - "$CLIENT" >/dev/null 2>&1 || true

SIGNING="$(codesign -dv --verbose=4 "$CLIENT" 2>&1 || true)"
if grep -q "TeamIdentifier=${TEAM_ID}" <<< "$SIGNING"; then
    check pass "client is signed under team ${TEAM_ID}, so the helper will accept it"
else
    check fail "client is NOT signed under team ${TEAM_ID} — every result would be a transport failure"
    echo "        $(grep -i 'TeamIdentifier' <<< "$SIGNING" || echo 'no TeamIdentifier present')" >&2
    exit 1
fi

# ---------------------------------------------------------------------------------------
# Unmount, acquire, profile, release
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
echo "  acquiring and profiling …"
echo

# One invocation, one connection: the helper releases on connection loss (NFR-REL-5), so
# `acquire` and `profile` must share a process or the device would be gone in between.
set +e
"$CLIENT" "$DISK" acquire profile release | tee "$OUTPUT"
CLIENT_STATUS="${PIPESTATUS[0]}"
set -e

echo
if [[ "$CLIENT_STATUS" != "0" ]]; then
    check fail "the client exited ${CLIENT_STATUS} — see its TRANSPORT_ERROR lines above"
else
    check pass "acquire, profile and release all completed"
fi

value_of() {
    local key="$1" out
    out="$(grep -- "$key=" "$OUTPUT" || true)"
    sed "s/.*${key}=//" <<< "$out" | head -1
}

ACQUIRED="$(value_of 'ACQUIRED')"
if [[ "$ACQUIRED" == "1" ]]; then
    check pass "the helper acquired ${DISK}"
else
    check fail "the helper did NOT acquire ${DISK} (cause $(value_of 'CAUSE'))"
    echo "        $(value_of 'MESSAGE')" >&2
    exit 1
fi

# ---------------------------------------------------------------------------------------
# 1. Geometry vs diskutil (gate item 1)
# ---------------------------------------------------------------------------------------

IOCTL_BLOCK_SIZE="$(value_of 'IOCTL_BLOCK_SIZE')"
IOCTL_BLOCK_COUNT="$(value_of 'IOCTL_BLOCK_COUNT')"
IOCTL_BYTE_COUNT="$(value_of 'IOCTL_BYTE_COUNT')"
IOKIT_BLOCK_SIZE="$(value_of 'IOKIT_BLOCK_SIZE')"
IOKIT_BLOCK_COUNT="$(value_of 'IOKIT_BLOCK_COUNT')"

echo
echo "  geometry: ioctl vs diskutil vs the helper's own IOKit reading"
printf '    %-14s ioctl %-14s diskutil %-14s IOKit %s\n' \
    "block size"  "${IOCTL_BLOCK_SIZE:-<none>}"  "$DU_BLOCK_SIZE"  "${IOKIT_BLOCK_SIZE:-<none>}"
printf '    %-14s ioctl %-14s diskutil %-14s IOKit %s\n' \
    "block count" "${IOCTL_BLOCK_COUNT:-<none>}" "$DU_BLOCK_COUNT" "${IOKIT_BLOCK_COUNT:-<none>}"
printf '    %-14s ioctl %-14s diskutil %-14s\n' \
    "byte count"  "${IOCTL_BYTE_COUNT:-<none>}"  "$DU_BYTES"
echo

if [[ "$IOCTL_BLOCK_SIZE" == "$DU_BLOCK_SIZE" ]]; then
    check pass "DKIOCGETBLOCKSIZE matches diskutil (${IOCTL_BLOCK_SIZE})"
else
    check fail "DKIOCGETBLOCKSIZE ${IOCTL_BLOCK_SIZE:-<none>} != diskutil ${DU_BLOCK_SIZE}"
fi

if [[ "$IOCTL_BLOCK_COUNT" == "$DU_BLOCK_COUNT" ]]; then
    check pass "DKIOCGETBLOCKCOUNT matches diskutil (${IOCTL_BLOCK_COUNT})"
else
    check fail "DKIOCGETBLOCKCOUNT ${IOCTL_BLOCK_COUNT:-<none>} != diskutil ${DU_BLOCK_COUNT}"
fi

if [[ "$IOCTL_BYTE_COUNT" == "$DU_BYTES" ]]; then
    check pass "capacity matches diskutil (${IOCTL_BYTE_COUNT} bytes)"
else
    check fail "capacity ${IOCTL_BYTE_COUNT:-<none>} != diskutil ${DU_BYTES}"
fi

# ---------------------------------------------------------------------------------------
# 2. Reconciliation (BUILD-PLAN 7.3)
# ---------------------------------------------------------------------------------------

if [[ "$IOKIT_BLOCK_SIZE" == "$IOCTL_BLOCK_SIZE" && "$IOKIT_BLOCK_COUNT" == "$IOCTL_BLOCK_COUNT" ]]; then
    check pass "the helper's IOKit reading agrees with the ioctls"
else
    # Not a failure: the ioctl values are authoritative and are what the kernel enforces on
    # every transfer. But a disagreement must never be silent.
    echo "  NOTE  the helper's IOKit reading DISAGREES with the ioctls."
    echo "        ioctl: ${IOCTL_BLOCK_COUNT} x ${IOCTL_BLOCK_SIZE}"
    echo "        IOKit: ${IOKIT_BLOCK_COUNT} x ${IOKIT_BLOCK_SIZE}"
    echo "        The ioctl values are used (BUILD-PLAN 7.3). Worth investigating."
fi

# ---------------------------------------------------------------------------------------
# 3. Uncached I/O (gate item 4, FR-TEST-9)
# ---------------------------------------------------------------------------------------

CACHE_BYPASS="$(value_of 'CACHE_BYPASS')"
echo
case "$CACHE_BYPASS" in
    1) check pass "cache bypass VERIFIED — raw character device, both fcntl calls succeeded" ;;
    2) check fail "cache bypass reports LIKELY CACHED — the verify comparison would be unreliable" ;;
    3) check fail "cache bypass INCONCLUSIVE — see the profile message above" ;;
    *) check fail "cache bypass returned an unrecognised code '${CACHE_BYPASS}'" ;;
esac

# ---------------------------------------------------------------------------------------
# 4. Link speed, cross-checked against an independent read
# ---------------------------------------------------------------------------------------

HELPER_SPEED="$(value_of 'LINK_SPEED_CODE')"
PROBE_SPEED="$("$SPEED_PROBE" "$DISK" 2>/dev/null | sed -n "s/^${DISK}\.deviceSpeed\.code=//p" | head -1)"

echo
if [[ -z "$HELPER_SPEED" || "$HELPER_SPEED" == "-1" ]]; then
    echo "  NOTE  the helper found no Device Speed for ${DISK}. FR-TEST-9's falsifier falls"
    echo "        back to its fixed 8 GB/s ceiling and says so in the report."
elif [[ "$HELPER_SPEED" == "$PROBE_SPEED" ]]; then
    check pass "link speed code ${HELPER_SPEED} agrees with tools/usb-speed-probe"
else
    check fail "link speed: helper says ${HELPER_SPEED}, usb-speed-probe says ${PROBE_SPEED:-<none>}"
fi

MAX_READ="$(value_of 'MAX_BYTE_COUNT_READ')"
if [[ -n "$MAX_READ" && "$MAX_READ" != "0" ]]; then
    echo "  NOTE  the device advertises a maximum read of ${MAX_READ} bytes. This is"
    echo "        diagnostic only — measured 2026-08-02, the kernel returns a full 8 MiB"
    echo "        pread in one call regardless."
fi

# ---------------------------------------------------------------------------------------
# Release
# ---------------------------------------------------------------------------------------

RELEASED="$(value_of 'RELEASED')"
if [[ "$RELEASED" == "1" ]]; then
    check pass "the helper released ${DISK}"
else
    check fail "the helper did not confirm release — the disk may still be claimed"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${FAILURES} failures. Step 7 gate items 1 and 4 are discharged on hardware."
    echo "  Items 2 (chunk plan) and 3 (bounded memory) are discharged by unit tests."
else
    echo "  ${FAILURES} failure(s) — see FAIL lines above."
fi
echo "  Full output: ${OUTPUT}"

exit "$FAILURES"
