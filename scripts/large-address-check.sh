#!/bin/bash
#
# large-address-check.sh — discharges NFR-COMPAT-6 on hardware that can actually test it.
#
# WHY THIS EXISTS
#
# Step 7's gate ran on disk4, which is 1,953,525,168 blocks — BELOW 2^32. A USB bridge that
# truncated its block count to 32 bits would be indistinguishable there from a correct one, and
# the failure would be silent: the tool would test the first portion of a larger drive and
# report a clean pass. disk8 is 42,970,644,479 blocks, ten times past the boundary, and a
# truncation would report 20,971,519 blocks — 10.7 GB instead of 22 TB.
#
# READ-ONLY, AND NOTHING IS UNMOUNTED.
#
# This is the one script in the project that touches a drive other than the designated scratch
# device, so it is built to the opposite posture from the rest:
#
#   * The probe opens O_RDONLY. The descriptor CANNOT write — the kernel refuses with EBADF —
#     so no bug in the probe can damage the drive.
#   * No O_EXLOCK, so no volume has to be unmounted and there is no exclusive lock whose
#     release would trigger DiskArbitration's re-probe-and-remount.
#   * The mount state is not touched at all. The drive is left exactly as found.
#
# That departs from DeviceClaim's O_RDWR|O_EXLOCK|O_NONBLOCK deliberately, and the reasoning is
# in tools/large-address-probe/main.swift: whether the ioctls report a 64-bit count and whether
# pread reaches a block above 2^32 are properties of the device, bridge and kernel, not of the
# open mode.
#
# PREREQUISITES
#   * An interactive Terminal: the probe runs under sudo and sudo needs a TTY.
#
# Usage:
#   scripts/large-address-check.sh disk8
#
set -euo pipefail

DISK="${1:-}"
if [[ -z "$DISK" ]]; then
    echo "usage: $0 <whole-disk-bsd-name>   e.g. $0 disk8" >&2
    exit 2
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="/tmp/usbdrivetester-large-address"
PROBE="$BUILD_DIR/large-address-probe"
PROBE_SRC="$REPO_ROOT/tools/large-address-probe/main.swift"
OUTPUT="$BUILD_DIR/large-address-output.txt"

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

if [[ ! "$DISK" =~ ^disk[0-9]+$ ]]; then
    echo "refusing: \"${DISK}\" is not a canonical whole-disk name (expected e.g. disk8)" >&2
    exit 2
fi

if [[ "$DISK" == "disk0" || "$DISK" == "disk6" ]]; then
    echo "refusing: ${DISK} is excluded by name — disk0 is the internal disk and disk6 holds" >&2
    echo "          the source tree." >&2
    exit 2
fi

DU_INFO="$(diskutil info "$DISK" 2>&1 || true)"

if ! grep -q "Whole: *Yes" <<< "$DU_INFO"; then
    echo "refusing: ${DISK} does not report itself as a whole disk" >&2
    exit 2
fi
if ! grep -q "Protocol: *USB" <<< "$DU_INFO"; then
    echo "refusing: ${DISK} is not behind a USB transport" >&2
    exit 2
fi

DU_MEDIA_NAME="$(sed -n 's/.*Device \/ Media Name: *//p' <<< "$DU_INFO" | head -1)"
DU_BLOCK_SIZE="$(awk -F: '/Device Block Size/ { gsub(/[^0-9]/, "", $2); print $2 }' <<< "$DU_INFO")"
DU_BYTES="$(sed -n 's/.*Disk Size:.*(\([0-9][0-9]*\) Bytes).*/\1/p' <<< "$DU_INFO" | head -1)"

if [[ -z "$DU_BLOCK_SIZE" || -z "$DU_BYTES" ]]; then
    echo "refusing: could not read ${DISK}'s geometry from diskutil" >&2
    exit 2
fi
DU_BLOCK_COUNT=$(( DU_BYTES / DU_BLOCK_SIZE ))

if [[ "$DU_BLOCK_COUNT" -le 4294967296 ]]; then
    echo "refusing: ${DISK} is ${DU_BLOCK_COUNT} blocks, at or below 2^32." >&2
    echo "          It cannot test the boundary this script exists to test." >&2
    exit 2
fi

# Show the user exactly what is mounted from this device, by name. This script is pointed at a
# drive that is NOT the expendable scratch device, so the volumes at risk — none, but the point
# is that they are visible — are named rather than counted.
MOUNTED="$(mount | grep "^/dev/${DISK}s" || true)"

cat <<EOF

  large-address-check.sh — NFR-COMPAT-6 on hardware that can test it

  Device       ${DISK}  (${DU_MEDIA_NAME})
  diskutil     ${DU_BYTES} bytes, ${DU_BLOCK_SIZE}-byte blocks, ${DU_BLOCK_COUNT} blocks
  Boundary     2^32 = 4294967296 blocks; this device is $(( DU_BLOCK_COUNT / 4294967296 ))x past it
  If truncated $(( DU_BLOCK_COUNT & 4294967295 )) blocks would be reported instead

  Mounted volumes on this device:
EOF

if [[ -n "$MOUNTED" ]]; then
    sed 's/^/    /' <<< "$MOUNTED"
else
    echo "    (none)"
fi

cat <<EOF

  THIS IS READ-ONLY AND NON-DISRUPTIVE:
    * the probe opens the raw node O_RDONLY — the descriptor cannot write
    * nothing is unmounted; the volumes above stay mounted throughout
    * no exclusive lock is taken, so nothing is remounted afterwards either

  Press Return to continue, or Ctrl-C to abort.

EOF
read -r _

# ---------------------------------------------------------------------------------------
# Build, and assert the probe has no write path before running it
# ---------------------------------------------------------------------------------------

echo "  building the probe …"
mkdir -p "$BUILD_DIR"
if [[ ! -f "$PROBE_SRC" ]]; then
    echo "  FAIL  probe source not found at ${PROBE_SRC}" >&2
    exit 1
fi
xcrun swiftc -swift-version 5 -O "$PROBE_SRC" -o "$PROBE"

# Comments are stripped first. The earlier version of this guard, in nocache-calibration.sh,
# fired on the probe's own header sentence "no pwrite, no write, no O_TRUNC" — a guard that
# cannot tell code from prose has to be silenced to run, and silencing it is how it stops
# guarding. `.write(` is allowed: that is FileHandle.standardError.write.
CODE_ONLY="$(sed -e 's://.*::' "$PROBE_SRC")"
WRITE_HITS="$(grep -nE '(^|[^A-Za-z_.])(pwrite|write)[[:space:]]*\(|O_TRUNC|O_CREAT|O_RDWR' <<< "$CODE_ONLY" || true)"
if [[ -n "$WRITE_HITS" ]]; then
    echo "  FAIL  the probe source can write or opens for writing — refusing to run it:" >&2
    echo "$WRITE_HITS" >&2
    exit 1
fi

# Anti-vacuousness: prove the guard can still fire.
CANARY='let fd = open(path, O_RDWR); pwrite(fd, p, n, 0)'
if grep -qE '(^|[^A-Za-z_.])(pwrite|write)[[:space:]]*\(|O_TRUNC|O_CREAT|O_RDWR' <<< "$CANARY"; then
    check pass "probe contains no write path and does not open O_RDWR — and the guard demonstrably still fires"
else
    check fail "the write-path guard matched nothing, including a deliberate pwrite — it is not guarding"
fi

# ---------------------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------------------

echo
echo "  running the probe under sudo (it will prompt for your password) …"
echo "  a 22 TB HDD seeking to its last block takes a moment."
echo

set +e
sudo "$PROBE" "$DISK" | tee "$OUTPUT"
PROBE_STATUS="${PIPESTATUS[0]}"
set -e

value_of() {
    local key="$1" out
    out="$(grep "^${key}=" "$OUTPUT" || true)"
    sed "s/^${key}=//" <<< "$out" | head -1
}

echo
PROBE_BLOCK_COUNT="$(value_of geometry.blockCount)"
if [[ "$PROBE_BLOCK_COUNT" == "$DU_BLOCK_COUNT" ]]; then
    check pass "ioctl block count ${PROBE_BLOCK_COUNT} matches diskutil"
else
    check fail "ioctl block count ${PROBE_BLOCK_COUNT:-<none>} != diskutil ${DU_BLOCK_COUNT}"
fi

if [[ "$(value_of geometry.exceeds32Bit)" == "true" ]]; then
    check pass "the reported block count is above 2^32, so it was not truncated"
else
    check fail "the reported block count is NOT above 2^32 — a truncation would look like this"
fi

for probe_label in block0 last32BitBlock firstBlockPast32Bit wellPast32Bit lastBlock; do
    if [[ "$(value_of "${probe_label}.result")" == "ok" ]]; then
        check pass "read succeeded at ${probe_label} (block $(value_of "${probe_label}.block"))"
    else
        check fail "read at ${probe_label} → $(value_of "${probe_label}.result")"
    fi
done

PAST_END="$(value_of pastEnd.result)"
case "$PAST_END" in
    "correctly refused"*) check pass "a read one block past the end was refused — the device does not address past its own end" ;;
    *)                    check fail "past-the-end read: ${PAST_END}" ;;
esac

ALIASING="$(value_of aliasing.result)"
case "$ALIASING" in
    "distinct"*)     check pass "the last block is not an alias of its 32-bit-wrapped twin" ;;
    "inconclusive"*) echo "  NOTE  aliasing check inconclusive: both blocks are all zeroes, so a match" ;
                     echo "        proves nothing either way. The past-the-end refusal above is the" ;
                     echo "        decisive evidence and it passed." ;;
    *)               check fail "aliasing check: ${ALIASING}" ;;
esac

echo
if [[ "$PROBE_STATUS" != "0" ]]; then
    check fail "the probe exited ${PROBE_STATUS}"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${FAILURES} failures. NFR-COMPAT-6 now has hardware evidence:"
    echo "  ${DISK} is addressable end to end above the 32-bit block boundary."
else
    echo "  ${FAILURES} failure(s) — see FAIL lines above."
fi
echo "  Full output: ${OUTPUT}"
echo
echo "  ${DISK} was not written to and was not unmounted. Current mount state:"
mount | grep "^/dev/${DISK}s" | sed 's/^/    /' || echo "    (no volumes mounted)"

exit "$FAILURES"
