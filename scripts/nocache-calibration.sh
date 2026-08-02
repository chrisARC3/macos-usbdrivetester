#!/bin/bash
#
# nocache-calibration.sh — measures whether F_NOCACHE changes anything on a raw device,
# and establishes the numeric thresholds for FR-TEST-9's run-start cache-bypass check.
#
# WHY THIS EXISTS
#
# FR-TEST-9 (added 2026-08-02) has the tool verify at run start that its reads are not being
# served from the host buffer cache, by reading one chunk twice and comparing durations. Two
# things about that plan are unmeasured, and this script settles both:
#
#   1. Whether the comparison can discriminate AT ALL. /dev/rdiskN is the character device
#      and is inherently unbuffered — the reason FR-TEST-6 specifies it over /dev/diskN. If
#      the timings match whether or not F_NOCACHE was set, the check passes vacuously, which
#      is the very defect shape FR-TEST-9 exists to catch.
#   2. What "similar" and "much faster" are in nanoseconds ON THIS HARDWARE. The classifier's
#      thresholds must be measured, not invented.
#
# It also prints the geometry read through DKIOCGETBLOCKSIZE / DKIOCGETBLOCKCOUNT and diffs
# it against diskutil, which pre-validates Step 7's first gate item before any of it is wired
# into a root daemon.
#
# NON-DESTRUCTIVE. The probe contains no write syscall against the device — no pwrite, no
# write, no O_TRUNC, no O_CREAT (audited 2026-08-02). It DOES change mount state: the raw
# exclusive open requires the disk unmounted, so this script unmounts the disk and restores
# it on exit, including on failure and on Ctrl-C.
#
# PREREQUISITES
#   * An interactive Terminal. The probe runs under sudo, and sudo needs a TTY to prompt on.
#     A run button has no TTY.
#   * Root alone is not sufficient for the raw open (NFR-INST-4) — but a sudo process
#     inherits Terminal's own TCC grant, which is what stands in here for the helper's Full
#     Disk Access.
#
# Usage:
#   scripts/nocache-calibration.sh disk4 [ioSizeMiB] [readsPerPhase]
#
set -euo pipefail

DISK="${1:-}"
IO_SIZE_MIB="${2:-4}"
READS_PER_PHASE="${3:-4}"

if [[ -z "$DISK" ]]; then
    echo "usage: $0 <whole-disk-bsd-name> [ioSizeMiB] [readsPerPhase]   e.g. $0 disk4" >&2
    exit 2
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Built outside the repo: this volume is removable, and macOS gates access to removable
# volumes. Same reason claim-contention-test.sh builds to /tmp.
BUILD_DIR="/tmp/usbdrivetester-nocache"
PROBE="$BUILD_DIR/nocache-probe"
PROBE_SRC="$REPO_ROOT/tools/nocache-probe/main.swift"
OUTPUT="$BUILD_DIR/calibration-output.txt"

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
# Safety. The named disk is turned into /dev/rdiskN and opened for exclusive access, so it
# is checked here rather than trusted. Mistyping "disk6" would target the source tree.
# ---------------------------------------------------------------------------------------

if [[ ! "$DISK" =~ ^disk[0-9]+$ ]]; then
    echo "refusing: \"${DISK}\" is not a canonical whole-disk name (expected e.g. disk4)" >&2
    exit 2
fi

if [[ "$DISK" == "disk0" || "$DISK" == "disk6" ]]; then
    echo "refusing: ${DISK} is excluded by name — disk0 is the internal disk and disk6 holds" >&2
    echo "          the source tree. BUILD-PLAN 'Test hardware': all testing uses disk4." >&2
    exit 2
fi

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

if [[ "$DISK" != "disk4" ]]; then
    cat <<EOF

  WARNING: ${DISK} is not disk4.

  BUILD-PLAN "Test hardware", amended 2026-08-02 by user decision, restricts testing to
  disk4 — the designated scratch device, whose contents are expendable. Using anything else
  was to be agreed case by case. This run is read-only and will restore the mount state,
  but check the device below is genuinely the one you meant.

EOF
fi

cat <<EOF

  nocache-calibration.sh — FR-TEST-9 threshold measurement

  Device       ${DISK}  (${DU_MEDIA_NAME})
  diskutil     ${DU_BYTES} bytes, ${DU_BLOCK_SIZE}-byte blocks, ${DU_BLOCK_COUNT} blocks
  I/O size     ${IO_SIZE_MIB} MiB
  Reads/phase  ${READS_PER_PHASE}

  This will UNMOUNT ${DISK}'s volumes, run a read-only probe under sudo, and remount them.
  Nothing is written to the device. Press Return to continue, or Ctrl-C to abort.

EOF
read -r _

# ---------------------------------------------------------------------------------------
# Mount-state bookkeeping. Restored on every exit path, including Ctrl-C and failure.
# ---------------------------------------------------------------------------------------

mounted_count() {
    local table count
    table="$(mount)"
    # grep -c exits non-zero on zero matches; capture first so `set -e` cannot fire, and so
    # the count is not lost to a `|| true` on the pipeline itself.
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
# Build
# ---------------------------------------------------------------------------------------

echo "  building the probe …"
mkdir -p "$BUILD_DIR"
if [[ ! -f "$PROBE_SRC" ]]; then
    echo "  FAIL  probe source not found at ${PROBE_SRC}" >&2
    exit 1
fi
xcrun swiftc -swift-version 5 -O "$PROBE_SRC" -o "$PROBE"
echo "  built ${PROBE}"

# The probe must contain no device write path. Asserted here rather than assumed, because
# this is the one script in the project that unmounts a drive and hands a raw exclusive
# descriptor to a binary.
#
# Comments are stripped BEFORE matching. The first version of this guard grepped raw source
# and fired on the probe's own header comment — the sentence "no `pwrite`, no `write`, no
# `O_TRUNC`" contains all three tokens. It failed closed, which was the right direction, but
# a guard that cannot distinguish code from prose would have had to be silenced to run at
# all, and silencing it is how a guard stops guarding.
#
# `.write(` is expected and allowed: FileHandle.standardError.write is how this tool reports
# errors. A bare `write(` or any `pwrite(` is not, hence the `[^A-Za-z_.]` before the name.
CODE_ONLY="$(sed -e 's://.*::' "$PROBE_SRC")"
WRITE_HITS="$(grep -nE '(^|[^A-Za-z_.])(pwrite|write)[[:space:]]*\(|O_TRUNC|O_CREAT' <<< "$CODE_ONLY" || true)"
if [[ -n "$WRITE_HITS" ]]; then
    echo "  FAIL  the probe source contains a device write path — refusing to run it:" >&2
    echo "$WRITE_HITS" >&2
    exit 1
fi

# Anti-vacuousness: prove the guard can still fire. A pattern that matches nothing would
# report the same PASS as a genuinely clean file, which is the defect negative-test.sh's
# inverted `pipefail` guard had for three steps.
CANARY='let x = pwrite(fd, p, n, 0)'
if grep -qE '(^|[^A-Za-z_.])(pwrite|write)[[:space:]]*\(|O_TRUNC|O_CREAT' <<< "$CANARY"; then
    check pass "probe source contains no device write path (read-only, NFR-REL-1) — and the guard demonstrably still fires"
else
    check fail "the write-path guard matched nothing at all, including a deliberate pwrite — it is not guarding"
fi

# ---------------------------------------------------------------------------------------
# Unmount, measure, restore
# ---------------------------------------------------------------------------------------

echo
echo "  unmounting ${DISK} …"
diskutil unmountDisk "$DISK"

STILL_MOUNTED="$(mounted_count)"
if [[ "$STILL_MOUNTED" != "0" ]]; then
    echo "  FAIL  ${DISK} still has ${STILL_MOUNTED} mounted volume(s); the raw open would" >&2
    echo "        fail EBUSY and the measurement would be meaningless" >&2
    exit 1
fi
check pass "${DISK} fully unmounted (the mount guard is kernel-enforced)"

echo
echo "  running the probe under sudo (it will prompt for your password) …"
echo
set +e
sudo "$PROBE" "$DISK" "$IO_SIZE_MIB" "$READS_PER_PHASE" | tee "$OUTPUT"
PROBE_STATUS="${PIPESTATUS[0]}"
set -e

echo
if [[ "$PROBE_STATUS" != "0" ]]; then
    check fail "the probe exited ${PROBE_STATUS} — see its errno lines above"
else
    check pass "the probe completed both phases"
fi

# ---------------------------------------------------------------------------------------
# Geometry cross-check — Step 7 gate item 1, pre-validated before the helper depends on it
# ---------------------------------------------------------------------------------------

value_of() {
    local key="$1" out
    out="$(grep "^${key}=" "$OUTPUT" || true)"
    sed "s/^${key}=//" <<< "$out" | head -1
}

PROBE_BLOCK_SIZE="$(value_of geometry.logicalBlockSize)"
PROBE_BLOCK_COUNT="$(value_of geometry.blockCount)"
PROBE_BYTE_COUNT="$(value_of geometry.byteCount)"

echo
echo "  geometry: ioctl vs diskutil"
echo "    DKIOCGETBLOCKSIZE   ${PROBE_BLOCK_SIZE:-<none>}   diskutil ${DU_BLOCK_SIZE}"
echo "    DKIOCGETBLOCKCOUNT  ${PROBE_BLOCK_COUNT:-<none>}  diskutil ${DU_BLOCK_COUNT}"
echo "    byte count          ${PROBE_BYTE_COUNT:-<none>}   diskutil ${DU_BYTES}"

if [[ "$PROBE_BLOCK_SIZE" == "$DU_BLOCK_SIZE" ]]; then
    check pass "logical block size matches diskutil"
else
    check fail "logical block size ${PROBE_BLOCK_SIZE:-<none>} != diskutil ${DU_BLOCK_SIZE}"
fi

if [[ "$PROBE_BLOCK_COUNT" == "$DU_BLOCK_COUNT" ]]; then
    check pass "block count matches diskutil"
else
    check fail "block count ${PROBE_BLOCK_COUNT:-<none>} != diskutil ${DU_BLOCK_COUNT}"
fi

if [[ "$PROBE_BYTE_COUNT" == "$DU_BYTES" ]]; then
    check pass "byte count matches diskutil"
else
    check fail "byte count ${PROBE_BYTE_COUNT:-<none>} != diskutil ${DU_BYTES}"
fi

# ---------------------------------------------------------------------------------------
# The measurement, restated
# ---------------------------------------------------------------------------------------

UNFLAGGED_SPEEDUP="$(value_of unflagged.rereadSpeedup)"
FLAGGED_SPEEDUP="$(value_of flagged.rereadSpeedup)"
DELTA="$(value_of discrimination.speedupDelta)"

cat <<EOF

  ---------------------------------------------------------------------------
  FR-TEST-9 CALIBRATION RESULT

    re-read speed-up, F_NOCACHE not set : ${UNFLAGGED_SPEEDUP:-<none>}
    re-read speed-up, F_NOCACHE set     : ${FLAGGED_SPEEDUP:-<none>}
    difference                          : ${DELTA:-<none>}

  A large first number with a second near 1.0 means re-read timing discriminates and
  FR-TEST-9's check is real. Both near 1.0 means /dev/r${DISK} was never cached and the
  check CANNOT discriminate — record that as the finding rather than shipping a check
  that always passes. Both large means something caches despite F_NOCACHE, which would
  make Step 8's verify vacuous.

  BEFORE RE-RUNNING THIS: unplug and replug ${DISK} first.

  F_GLOBAL_NOCACHE sets its flag on the VNODE, not on the descriptor, so it can outlive
  this process. A second run on the same vnode may therefore measure an "unflagged" phase
  that is still globally no-cached — which would report "cannot discriminate" whether or
  not that is true. Replugging forces a fresh vnode. This is the one way this measurement
  can quietly lie to us, so it is worth the ten seconds.

  Full output: ${OUTPUT}
  ---------------------------------------------------------------------------

EOF

if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${FAILURES} failures."
else
    echo "  ${FAILURES} failure(s) — see FAIL lines above."
fi

exit "$FAILURES"
