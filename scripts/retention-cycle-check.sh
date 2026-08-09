#!/bin/bash
#
# retention-cycle-check.sh — Step 8's hardware gate. THIS SCRIPT WRITES TO THE DRIVE.
#
# It is the first thing in this project that has ever written to real media. Everything before
# it — device discovery, the mount guard, the exclusive claim, geometry, the cache-bypass check,
# the 64-bit addressing probe — was read-only.
#
# WHAT IT DOES
#
#   1. Confirms the live daemon speaks the protocol this build expects (v7). A daemon that is
#      too old fails the call as a transport error, which reads like a broken connection rather
#      than "the installed helper is out of date".
#   2. Draws a RANDOM start LBA, aligned to one 4 MiB chunk and at least 1 GiB clear of the end
#      of the drive. Random to spread NAND wear over repeated runs; printed and recorded so a
#      failure can be re-run in exactly the same place (pass it as $2).
#   3. Unmounts the drive's volumes, and acquires it through the helper.
#   4. Samples three chunks INSIDE the range and requires their fingerprints to differ — a
#      cycle over a uniform region proves nothing, and on a near-empty drive that is what a
#      random placement gets. See the CONTENT check.
#   5. Fingerprints the device — a SHA-256 per 1 GiB window, taken by the helper.
#   6. Runs the read -> write-back -> read-verify cycle over 1 GiB - 512 KiB from the drawn LBA.
#   7. Fingerprints it AGAIN, and requires every window to be identical.
#   8. Releases, and restores the mount state on every exit path.
#
# WHY THE HELPER TAKES THE FINGERPRINTS, NOT THIS SCRIPT
#
# Both fingerprints must be taken while the claim is held: releasing makes DiskArbitration
# remount the volume ~4 ms later (measured 2026-08-01), and a mounted exFAT volume writes to
# itself, so an "after" fingerprint taken post-release would differ for reasons unrelated to the
# cycle.
#
# The original design had a separate process take them. Measured on hardware 2026-08-02: THAT
# IS NOT POSSIBLE. While the helper holds O_EXLOCK, a second process — root, carrying Terminal's
# Full Disk Access grant, requesting no lock at all — is refused EBUSY. That fact was not in the
# 2026-07-30 exclusivity matrix, which only ever tested O_EXLOCK against O_EXLOCK.
#
# So the fingerprints come from the helper's own descriptor, one bounded call per window
# (protocol v7's digestRange). A fingerprint taken by the same process on both sides of a cycle
# is only evidence if the fingerprint function is known to work, which is why the digest lives
# in Core/DeviceDigest.swift and is unit-tested against known SHA-256 vectors: a digest that
# returned a constant would make "before == after" pass unconditionally.
#
# One consequence of the helper doing the work: this script needs no sudo at all.
#
# WHY A WHOLE-DEVICE DIGEST AND NOT THE RUN'S OWN RESULT
#
# The cycle's verify compares what came back *at the offset it meant to write*. A write that
# lands somewhere else is invisible to it — demonstrated in simulation by
# `RetentionCycleTests.aMisdirectedWriteIsDetectedByTheSameAssertion`, where only a whole-device
# comparison catches it. A run can report "0 bad blocks" and still have moved data. So the
# evidence here is the fingerprint, not the run's own verdict.
#
# COST
#
# Two full read passes. On the scratch device (1 TB at ~475 MB/s) that is roughly 35 minutes
# each, so about
# 70 minutes, plus ~7 seconds of actual cycle. `--quick` fingerprints only a 1 GiB margin either
# side of the tested range; it is MUCH weaker evidence — it cannot see a write that landed
# elsewhere, which is the whole point — and the summary says loudly which mode ran.
#
# PREREQUISITES
#   * The helper registered and enabled via SMAppService, running from /Applications
#     (scripts/install-app.sh), at protocol v7.
#   * FULL DISK ACCESS (NFR-INST-4) for the app, so the helper's acquire works. Root is not
#     sufficient on its own.
#   * An interactive Terminal (for the confirmation prompt and for codesign's keychain access).
#     No sudo: the helper is already root and does every device access.
#   * A drive whose contents are EXPENDABLE **and non-trivial**. The Samsung T5, serial
#     12345686DAA9, is the designated scratch device and this script resolves it by that serial
#     rather than by name; it must hold real data, not empty space, or the run cannot demonstrate
#     anything (see the CONTENT check). Fill it once with:
#         dd if=/dev/urandom of=/Volumes/Test_Drive/fill.bin bs=4m status=progress
#     and KEEP the file: the gate needs the blocks written, and deleting it may let the drive
#     discard them.
#
# Usage:
#   scripts/retention-cycle-check.sh [startBlock] [--quick] [--device <serial|diskN>]
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

FIXED_START=""
QUICK=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick) QUICK=1 ;;
        *[!0-9]*) echo "unrecognised argument '$1'" >&2; exit 2 ;;
        *) FIXED_START="$1" ;;
    esac
    shift
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="5JC55GTLZA"

# Built outside the repo: this volume is removable and macOS gates daemon access to it.
BUILD_DIR="/tmp/usbdrivetester-cycle"
CLIENT="$BUILD_DIR/mount-guard-client"
CLIENT_OUT="$BUILD_DIR/client-output.txt"
BEFORE="$BUILD_DIR/digest-before.txt"
AFTER="$BUILD_DIR/digest-after.txt"

SHARED="$REPO_ROOT/USBDriveTester/USBDriveTester/Shared/TesterControl.swift"
CLIENT_SRC="$REPO_ROOT/tools/mount-guard-client/main.swift"

FAILURES=0
CHECKS=0

check() {
    CHECKS=$((CHECKS + 1))
    if [[ "$1" == "pass" ]]; then
        echo "  PASS  $2"
    else
        echo "  FAIL  $2"
        FAILURES=$((FAILURES + 1))
    fi
}

UNMOUNTED=0

cleanup() {
    if [[ "$UNMOUNTED" -eq 1 ]]; then
        echo
        echo "  Restoring mount state…"
        diskutil mountDisk "/dev/${DISK}" >/dev/null 2>&1 || true
        diskutil list "/dev/${DISK}" 2>/dev/null | sed 's/^/    /' || true
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------- build

mkdir -p "$BUILD_DIR"
rm -f "$CLIENT_OUT" "$BEFORE" "$AFTER"

echo
echo "  retention-cycle-check — ${DISK}"
echo

xcrun swiftc -swift-version 5 -O "$SHARED" "$CLIENT_SRC" -o "$CLIENT"

# Signed under the real Team ID, or the helper invalidates the connection on the first
# message and every result below would read as a transport failure.
codesign --force --sign "Apple Development" --timestamp=none "$CLIENT" 2>/dev/null \
    || codesign --force --sign - "$CLIENT"
CLIENT_TEAM="$(codesign -dvv "$CLIENT" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)"
if [[ "$CLIENT_TEAM" == "$TEAM_ID" ]]; then
    check pass "the client is signed under team ${TEAM_ID}"
else
    check fail "the client's TeamIdentifier is '${CLIENT_TEAM}', not ${TEAM_ID} — the helper will reject it"
    exit "$FAILURES"
fi

# ------------------------------------------------------------------- geometry & plan

# From diskutil, unprivileged and with nothing unmounted. The helper validates the range it is
# given against its own ioctl geometry regardless (NFR-REL-7), so this only has to be good
# enough to *plan* with.
BLOCK_SIZE="$(diskutil info -plist "$DISK" | plutil -extract DeviceBlockSize raw - 2>/dev/null || echo 0)"
TOTAL_SIZE="$(diskutil info -plist "$DISK" | plutil -extract TotalSize raw - 2>/dev/null || echo 0)"
if [[ "$BLOCK_SIZE" -le 0 || "$TOTAL_SIZE" -le 0 ]]; then
    check fail "could not read geometry for ${DISK} from diskutil"
    exit "$FAILURES"
fi
BLOCK_COUNT=$((TOTAL_SIZE / BLOCK_SIZE))

IO_SIZE=$((4 * 1024 * 1024))                      # FR-CTRL-8's default
ALIGN_BLOCKS=$((IO_SIZE / BLOCK_SIZE))            # one chunk
# 1 GiB - 1 MiB. Still 255 full 4 MiB chunks plus a short 3 MiB one, so FR-TEST-5 is exercised
# on real media exactly as before and EXPECTED_CHUNKS is still 256.
#
# Was `1 GiB - 512 KiB` until 2026-08-04. FR-TEST-10 now requires a run to cover a whole number
# of 1 MiB units unless it ends at the device's last block, and this run is deliberately placed
# 1 GiB clear of the end — so 1023.5 MiB would be REFUSED by the helper. It would have been
# refused about 35 minutes in, right after the before-fingerprint pass. Caught by reading the
# rule against the script rather than by running it.
RUN_BYTES=$(( (1024 * 1024 * 1024) - (1024 * 1024) ))   # 1 GiB - 1 MiB
RUN_BLOCKS=$((RUN_BYTES / BLOCK_SIZE))
MARGIN_BLOCKS=$(( (1024 * 1024 * 1024) / BLOCK_SIZE )) # the user's "1 GiB clear of the end"
EXPECTED_CHUNKS=$(( (RUN_BYTES + IO_SIZE - 1) / IO_SIZE ))

if [[ "$BLOCK_COUNT" -le "$MARGIN_BLOCKS" ]]; then
    check fail "${DISK} is only ${BLOCK_COUNT} blocks — too small to place a 1 GiB run clear of the end"
    exit "$FAILURES"
fi

MAX_START=$(( ((BLOCK_COUNT - MARGIN_BLOCKS) / ALIGN_BLOCKS) * ALIGN_BLOCKS ))

if [[ -n "$FIXED_START" ]]; then
    START_BLOCK="$FIXED_START"
    if (( START_BLOCK % ALIGN_BLOCKS != 0 )); then
        check fail "start block ${START_BLOCK} is not a multiple of ${ALIGN_BLOCKS} (one ${IO_SIZE}-byte chunk)"
        exit "$FAILURES"
    fi
    if (( START_BLOCK > MAX_START )); then
        check fail "start block ${START_BLOCK} is past the latest legal start (${MAX_START})"
        exit "$FAILURES"
    fi
    ORIGIN="given on the command line (re-running a previous draw)"
else
    # 32 bits of randomness from /dev/urandom. NOT 64: bash arithmetic is *signed* 64-bit, so a
    # value above 2^63 reads as negative and `RAW % POSITIONS` then yields a negative start
    # block. Measured on the first dry run of this script — it planned a run at block
    # -893,534,208. $RANDOM is no good either, being 15 bits: every run would land in the first
    # 32,768 chunk positions. 2^32 over ~238,000 positions leaves a modulo bias around 5e-5,
    # which is nothing next to what this is for (spreading NAND wear).
    RAW="$(od -An -N4 -tu4 < /dev/urandom | tr -d ' ')"
    POSITIONS=$(( (MAX_START / ALIGN_BLOCKS) + 1 ))
    START_BLOCK=$(( (RAW % POSITIONS) * ALIGN_BLOCKS ))
    ORIGIN="drawn at random from ${POSITIONS} chunk-aligned positions"
fi

# The placement is what decides where this script writes, so it is checked rather than trusted —
# including on the path that just computed it. The negative start above was arithmetic that
# looked perfectly reasonable in the source.
if (( START_BLOCK < 0 || START_BLOCK > MAX_START )); then
    check fail "computed start block ${START_BLOCK} is outside [0, ${MAX_START}] — refusing to write anywhere"
    exit "$FAILURES"
fi
if (( START_BLOCK % ALIGN_BLOCKS != 0 )); then
    check fail "computed start block ${START_BLOCK} is not chunk-aligned — refusing to write anywhere"
    exit "$FAILURES"
fi
if (( START_BLOCK + RUN_BLOCKS > BLOCK_COUNT )); then
    check fail "the run would end at block $((START_BLOCK + RUN_BLOCKS)), past the device's ${BLOCK_COUNT} — refusing"
    exit "$FAILURES"
fi

END_BLOCK=$((START_BLOCK + RUN_BLOCKS))

echo
echo "  Device       ${DISK}: ${BLOCK_COUNT} blocks of ${BLOCK_SIZE} B (${TOTAL_SIZE} bytes)"
echo "  I/O size     ${IO_SIZE} B  (${ALIGN_BLOCKS} blocks per chunk)"
echo "  Run          blocks ${START_BLOCK} … $((END_BLOCK - 1))  (${RUN_BLOCKS} blocks, ${RUN_BYTES} bytes)"
echo "               ${EXPECTED_CHUNKS} chunks — the last one short, on purpose, to exercise FR-TEST-5"
echo "  Start        ${ORIGIN}"
# NOT "$0 ${DISK} ${START_BLOCK}" — that was the pre-2026-08-06 form, and the argument parser
# below now refuses any non-numeric argument, so following it produced "unrecognised argument
# 'disk8'". The device is resolved by SERIAL and takes no positional argument at all.
echo "  Re-run this exact placement with:  $0 ${START_BLOCK}"
if (( START_BLOCK < 34 )); then
    echo
    echo "  NOTE: this run covers block 0 — the protective MBR, the GPT and the boot sector."
    echo "        That is a legal draw and is deliberate: it is the one case where 'a torn"
    echo "        write bricks the drive' is real rather than hypothetical. ${DISK}'s contents"
    echo "        are expendable, and it can be reformatted."
fi
echo

# A randomly placed run on a near-empty drive lands on unwritten space, and a cycle over an
# all-zero region proves nothing: writing zeros back over zeros is non-destructive however
# wrongly the code addresses the device. Measured 2026-08-02, when exactly that happened and the
# gate reported 15/15 anyway. The CONTENT check below is the authority; this is the early
# warning, so a doomed run can be avoided before anything is unmounted.
USED_PERCENT="$(df -k "/dev/${DISK}s2" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')"
if [[ -n "${USED_PERCENT:-}" ]] && (( USED_PERCENT < 25 )); then
    echo "  ⚠️  ${DISK} is only ${USED_PERCENT}% used. A randomly placed run will very likely land on"
    echo "      unwritten space, where the cycle reads zeros, writes zeros, and verifies zeros"
    echo "      against zeros — which proves nothing about non-destructiveness. The content check"
    echo "      will fail the gate if that happens. Fill the volume with data first:"
    echo
    echo "          dd if=/dev/urandom of=/Volumes/Test_Drive/fill.bin bs=4m status=progress"
    echo
fi

echo "  ⚠️  THIS WILL WRITE TO ${DISK}. Its contents must be expendable."
read -r -p "  Type the disk name to continue: " CONFIRM
if [[ "$CONFIRM" != "$DISK" ]]; then
    echo "  Aborted — nothing was unmounted and nothing was written."
    exit 2
fi

# ------------------------------------------------------------------- protocol version

VERSION_OUT="$("$CLIENT" "$DISK" version 2>&1 || true)"
PROTOCOL="$(sed -n 's/^\[version\] PROTOCOL=//p' <<< "$VERSION_OUT" | head -1)"
EXPECTED_PROTOCOL="$(sed -n 's/^\[version\] EXPECTED=//p' <<< "$VERSION_OUT" | head -1)"
if [[ -n "$PROTOCOL" && "$PROTOCOL" == "$EXPECTED_PROTOCOL" ]]; then
    check pass "the live daemon speaks protocol v${PROTOCOL}"
else
    check fail "the live daemon reports protocol '${PROTOCOL}', this build expects '${EXPECTED_PROTOCOL}' — install and re-register the helper"
    exit "$FAILURES"
fi

# ------------------------------------------------------------------------- unmount

echo
echo "  Unmounting ${DISK}…"
if diskutil unmountDisk "/dev/${DISK}" >/dev/null 2>&1; then
    UNMOUNTED=1
    check pass "${DISK} unmounted"
else
    check fail "could not unmount ${DISK} — something is using it"
    exit "$FAILURES"
fi

# --------------------------------------------------------- acquire, digest, cycle, digest

# ONE invocation, ONE connection: the helper releases the device when the connection that
# acquired it goes away (NFR-REL-5), so acquire, fingerprint, cycle, fingerprint and release must
# all happen here. The helper takes the fingerprints itself — no separate process can read the
# device while it holds O_EXLOCK (measured EBUSY, 2026-08-02).
#
# Coverage: the whole device by default; a margin around the tested range under --quick.
if [[ "$QUICK" -eq 1 ]]; then
    MARGIN=$(( (1024 * 1024 * 1024) / BLOCK_SIZE ))
    COVER_START=$(( START_BLOCK > MARGIN ? START_BLOCK - MARGIN : 0 ))
    COVER_BLOCKS=$(( END_BLOCK + MARGIN - COVER_START ))
    if (( COVER_START + COVER_BLOCKS > BLOCK_COUNT )); then
        COVER_BLOCKS=$(( BLOCK_COUNT - COVER_START ))
    fi
    echo
    echo "  ⚠️  --quick: fingerprinting only blocks ${COVER_START} … $((COVER_START + COVER_BLOCKS - 1))."
    echo "      A write landing outside that range would NOT be detected. This is not the full gate."
else
    COVER_START=0
    COVER_BLOCKS=0            # 0 == to the end of the device
fi

WINDOW_BYTES=$(( 1024 * 1024 * 1024 ))

echo
echo "  Acquiring, fingerprinting, running the cycle, fingerprinting again…"
echo "  The two fingerprint passes are the slow part; progress is reported every 50 windows."
echo

set +e
# Three whole chunks from inside the run, fingerprinted BEFORE anything is written. They must
# differ from each other, or the region under test is uniform and no misdirected write within it
# could be detected — by the verify or by the window fingerprints.
PROBE_A=$START_BLOCK
PROBE_B=$(( START_BLOCK + 127 * ALIGN_BLOCKS ))
PROBE_C=$(( START_BLOCK + 254 * ALIGN_BLOCKS ))

"$CLIENT" "$DISK" \
    acquire \
    "digest:${PROBE_A}:${ALIGN_BLOCKS}" \
    "digest:${PROBE_B}:${ALIGN_BLOCKS}" \
    "digest:${PROBE_C}:${ALIGN_BLOCKS}" \
    "digest-all:${WINDOW_BYTES}:${BEFORE}:${COVER_START}:${COVER_BLOCKS}" \
    "cycle:${START_BLOCK}:${RUN_BLOCKS}:${IO_SIZE}" \
    "digest-all:${WINDOW_BYTES}:${AFTER}:${COVER_START}:${COVER_BLOCKS}" \
    release 2>&1 | tee "$CLIENT_OUT"
CLIENT_STATUS=${PIPESTATUS[0]}
set -e

# ------------------------------------------------------------------------- results

ACQUIRED="$(sed -n 's/^\[acquire\] ACQUIRED=//p' "$CLIENT_OUT" | head -1)"
if [[ "$ACQUIRED" == "1" ]]; then
    check pass "helper acquired ${DISK} (claim + O_EXLOCK held)"
else
    check fail "helper did not acquire ${DISK}: $(sed -n 's/^\[acquire\] MESSAGE=//p' "$CLIENT_OUT" | head -1)"
    exit "$FAILURES"
fi

BEFORE_WINDOWS="$(grep -c '^window ' "$BEFORE" 2>/dev/null || echo 0)"
AFTER_WINDOWS="$(grep -c '^window ' "$AFTER" 2>/dev/null || echo 0)"

if [[ "${BEFORE_WINDOWS:-0}" -gt 0 ]]; then
    check pass "before-fingerprint: ${BEFORE_WINDOWS} windows"
else
    check fail "the before-fingerprint did not complete; see ${CLIENT_OUT}"
    exit "$FAILURES"
fi

# THE CHECK THAT DECIDES WHETHER THIS RUN PROVES ANYTHING.
#
# Three whole chunks from inside the tested range, fingerprinted before the cycle wrote a byte.
# If they are not all distinct, the region under test is uniform — and a cycle over a uniform
# region is non-destructive no matter how wrongly it addresses the device. The verify would
# compare identical bytes against identical bytes, and the window fingerprints would match
# whether or not a write landed where it was meant to.
#
# An earlier version compared *window* fingerprints instead, and passed vacuously on 2026-08-02:
# all three windows were entirely zeros, and two of them differed only because the windows had
# different lengths. That run reported 15 checks, 0 failures, and proved nothing about
# non-destructiveness. This checks the property that actually matters.
PROBE_DIGESTS="$(sed -n 's/^\[digest\] SHA256=//p' "$CLIENT_OUT" | head -3)"
PROBE_COUNT="$(grep -c . <<< "$PROBE_DIGESTS" || true)"
DISTINCT_PROBES="$(sort -u <<< "$PROBE_DIGESTS" | grep -c . || true)"

if [[ "$PROBE_COUNT" -eq 3 && "$DISTINCT_PROBES" -eq 3 ]]; then
    check pass "the tested region holds distinguishable data (3 sampled chunks, 3 distinct fingerprints)"
else
    check fail "the tested region is UNIFORM — ${DISTINCT_PROBES} distinct fingerprint(s) across ${PROBE_COUNT} sampled chunks (blocks ${PROBE_A}, ${PROBE_B}, ${PROBE_C}). A cycle over a uniform region cannot demonstrate non-destructiveness: writing those bytes back is a no-op however wrongly they are addressed."
    echo "        Put real data on the volume and run again:"
    echo "          dd if=/dev/urandom of=/Volumes/Test_Drive/fill.bin bs=4m status=progress"
fi

CYCLE_COMPLETED="$(sed -n 's/^\[cycle\] COMPLETED=//p' "$CLIENT_OUT" | head -1)"
CYCLE_CHUNKS="$(sed -n 's/^\[cycle\] CHUNKS=//p' "$CLIENT_OUT" | head -1)"
CYCLE_RANGES="$(sed -n 's/^\[cycle\] FAILED_RANGES=//p' "$CLIENT_OUT" | head -1)"
CYCLE_BYPASS="$(sed -n 's/^\[cycle\] CACHE_BYPASS=//p' "$CLIENT_OUT" | head -1)"
CYCLE_RATE="$(sed -n 's/^\[cycle\] FASTEST_BYTES_PER_SECOND=//p' "$CLIENT_OUT" | head -1)"
CYCLE_BUFFERS="$(sed -n 's/^\[cycle\] BUFFER_BYTES=//p' "$CLIENT_OUT" | head -1)"
CYCLE_SUMMARY="$(sed -n 's/^\[cycle\] FAILURE_SUMMARY=//p' "$CLIENT_OUT" | head -1)"

if [[ "$CYCLE_COMPLETED" == "1" ]]; then
    check pass "the cycle completed every planned chunk"
else
    check fail "the cycle did not complete: $(sed -n 's/^\[cycle\] MESSAGE=//p' "$CLIENT_OUT" | head -1)"
fi

if [[ "$CYCLE_CHUNKS" == "$EXPECTED_CHUNKS" ]]; then
    check pass "processed ${CYCLE_CHUNKS} chunks, as planned (255 full + 1 short)"
else
    check fail "processed ${CYCLE_CHUNKS} chunks, expected ${EXPECTED_CHUNKS}"
fi

if [[ "$CYCLE_RANGES" == "0" ]]; then
    check pass "no failed block ranges — ${CYCLE_SUMMARY}"
else
    check fail "${CYCLE_RANGES} failed block range(s): ${CYCLE_SUMMARY}"
fi

# 1 == CacheBypassOutcome.bypassed
if [[ "$CYCLE_BYPASS" == "1" ]]; then
    check pass "FR-TEST-9: the cache-bypass verdict survived the run (bypassed)"
else
    check fail "FR-TEST-9: the run ended with cache-bypass code ${CYCLE_BYPASS}, not 1 (bypassed)"
fi

# The falsifier's own evidence: the fastest read must look like a USB transport, not like RAM.
# 8 GB/s is CacheBypassCheck.fallbackImplausibleThroughputBytesPerSecond; 10 MB/s is a floor
# that only a read which never happened could fall below.
if [[ -n "$CYCLE_RATE" ]] && (( CYCLE_RATE > 10000000 && CYCLE_RATE < 8000000000 )); then
    check pass "fastest read ${CYCLE_RATE} B/s — transport-plausible, not RAM-plausible"
else
    check fail "fastest read ${CYCLE_RATE} B/s is outside the plausible transport range"
fi

EXPECTED_BUFFERS=$((2 * IO_SIZE))
if [[ "$CYCLE_BUFFERS" == "$EXPECTED_BUFFERS" ]]; then
    check pass "the run held ${CYCLE_BUFFERS} B of buffers = 2 x the I/O size (NFR-PERF-1)"
else
    check fail "the run held ${CYCLE_BUFFERS} B of buffers, expected ${EXPECTED_BUFFERS}"
fi

if [[ "${AFTER_WINDOWS:-0}" == "${BEFORE_WINDOWS}" ]]; then
    check pass "after-fingerprint: ${AFTER_WINDOWS} windows, same coverage as before"
else
    check fail "after-fingerprint covered ${AFTER_WINDOWS} windows, before covered ${BEFORE_WINDOWS}"
fi

# The whole point. Per-window, so a difference names the gibibyte it is in.
CHANGED="$(diff "$BEFORE" "$AFTER" | grep '^<' || true)"
if [[ -z "$CHANGED" && "${AFTER_WINDOWS:-0}" -gt 0 ]]; then
    check pass "every one of the ${BEFORE_WINDOWS} window fingerprints is unchanged (NFR-REL-1)"
else
    check fail "window fingerprints CHANGED:"
    sed 's/^/      /' <<< "$CHANGED"
fi

RELEASED="$(sed -n 's/^\[release\] RELEASED=//p' "$CLIENT_OUT" | head -1)"
if [[ "$RELEASED" == "1" ]]; then
    check pass "the helper released ${DISK}"
else
    check fail "the helper did not report a clean release"
fi

if [[ "$CLIENT_STATUS" -ne 0 ]]; then
    check fail "the client exited with status ${CLIENT_STATUS} — a transport error occurred somewhere above"
fi

# ------------------------------------------------------------------------- summary

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${CHECKS} checks, 0 failures."
    if [[ "$QUICK" -eq 1 ]]; then
        echo "  NOTE: --quick was used. The fingerprint covered blocks ${COVER_START} …"
        echo "        $((COVER_START + COVER_BLOCKS - 1)) only, so a write landing outside that"
        echo "        range would not have been detected. This is NOT the full gate."
    else
        echo "  The cycle wrote ${RUN_BYTES} bytes at block ${START_BLOCK} and the whole device"
        echo "  is byte-identical afterwards."
    fi
else
    echo "  ${CHECKS} checks, ${FAILURES} FAILURES."
    echo "  Client output:  ${CLIENT_OUT}"
    echo "  Fingerprints:   ${BEFORE}  ${AFTER}"
fi
echo

exit "$FAILURES"
