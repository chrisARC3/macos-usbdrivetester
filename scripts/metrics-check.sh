#!/bin/bash
#
# metrics-check.sh — Step 9's hardware gate, re-scoped for Step 11's run session.
#
# Runs ONE RUN of FOUR CALLS — one per I/O size FR-CTRL-8 offers, 1, 2, 4 and 8 MiB, each over its
# own gibibyte — polling live metrics from a SECOND connection the way the GUI does, then asserts
# the things that can only be established on real media:
#
#   1. LIVE DELIVERY (NFR-PERF-5). Snapshots arrive at least once per second *while a blocking
#      privileged call is in flight*. This is a property of the transport, not of the metrics
#      code — and it is why the poll goes out on a second connection at all (measured
#      2026-08-04, scripts/xpc-concurrency-check.sh).
#   2. PROGRESS (FR-METR-5/6). Advances monotonically ACROSS CALLS, tracks the whole device, and
#      ends each call at the right block.
#   3. LATENCY (FR-METR-3). min <= p99 <= max, one sample per chunk of the whole run, nothing in
#      histogram overflow — i.e. the range chosen actually covers real read latencies.
#   4. THROUGHPUT (FR-METR-1). Transport-plausible rather than RAM-plausible.
#   5. NFR-PERF-3: host overhead as a fraction of device I/O time, and the daemon's CPU as a
#      fraction of one core, both for the run as a whole.
#   6. FR-TEST-10 SHOWN REFUSING, and A REFUSED CALL CARRYING NO FIGURES.
#   7. THE SESSION DIES WITH THE CLAIM. A poll after the release must report nothing.
#
# The CPU figure is ALSO sampled independently with `ps` while the run is in flight, because a
# self-reported number that nothing can contradict is a number, not evidence.
#
# ## WHAT STEP 11 INCREMENT 3 CHANGED HERE, AND WHY
#
# A run is now a sequence of bounded calls and the accumulators live on the claim (CONSTRAINTS
# section 2). The four cycles below are therefore ONE RUN of four calls inside one `acquireDevice`,
# not four runs — so:
#
#   * **Every figure but the buffer size and the outcome code is cumulative.** The expectations are
#     running totals, computed independently by the probe rather than read back from the helper.
#   * **Each size runs over its own gibibyte**, advancing from block 0, so `currentBlock` and
#     `fractionComplete` are monotonic across the seam. That is the shape a real sequencer produces;
#     four calls over the same region is a shape nothing in the product creates.
#   * **Progress is against the WHOLE DEVICE.** Four gibibytes of the scratch drive is ~0.43%, not
#     100%. The old `FINAL_FRACTION >= 99.99` assertion is gone and is replaced by a comparison
#     against a fraction the probe computes from the ioctl block count — which is a stronger check,
#     because a helper that used the call's range as its denominator would report ~100% and be
#     caught instead of passing.
#   * **The per-size host-cost table is gone.** It existed to settle whether host cost follows
#     bytes moved or chunk count; that was measured on 2026-08-05 and is recorded in CONSTRAINTS
#     section 1 ("Host cost follows bytes moved, not chunk count"). Under a cumulative session the
#     per-size figures are running totals and cannot be compared with one another, so keeping the
#     table would mean printing a comparison that no longer means anything. NFR-PERF-3's own claim
#     is asserted on the run's cumulative fraction instead.
#
# ⚠️  THIS WRITES TO THE DRIVE.
#   The run covers the FIRST 4 GiB, starting at block 0 — where a real run begins (FR-TEST-4),
#   1 MiB-aligned by construction (FR-TEST-10). It writes back exactly the bytes it read.
#
#   This script does NOT re-prove non-destructiveness: `scripts/retention-cycle-check.sh` is what
#   fingerprints the device either side of a run, and it should be run as the Step 11 regression
#   because this step changed what the engine accumulates.
#
# PREREQUISITES
#   * The helper must be registered, enabled, running from /Applications, and at **protocol v12**.
#     v12 reshaped BOTH replies: the two throughput arguments became wall-clock figures under new
#     names and a third, `coverageBytesPerSecond`, was added. A v11 daemon replies with twenty
#     arguments where this expects twenty-one, so the decode fails outright — which is the loud
#     failure the handshake exists to produce. Before that, v11 changed the MEANING of nine
#     arguments without changing the signature, which would have been the quiet one.
#     Re-install (scripts/install-app.sh), then unregister and re-register in the app — the script
#     only copies files — and confirm with Check version.
#   * Full Disk Access (NFR-INST-4).
#   * An interactive Terminal, for codesign's keychain access.
#
# Usage:
#   scripts/metrics-check.sh [--device <serial|diskN>]
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

BUILD_DIR="/tmp/usbdrivetester-metrics"
PROBE="$BUILD_DIR/metrics-probe"
OUTPUT="$BUILD_DIR/metrics-output.txt"
PS_SAMPLES="$BUILD_DIR/daemon-cpu.txt"

SHARED="$REPO_ROOT/USBDriveTester/USBDriveTester/Shared/TesterControl.swift"
PROBE_SRC="$REPO_ROOT/tools/metrics-probe/main.swift"

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

# The "is this disk4?" refusal that used to live here is now `resolve_target scratch`, above: the
# drive is identified by serial 12345686DAA9 and its block count confirmed, so being pointed at
# another drive is refused before this script does anything at all.

cat <<EOF

  metrics-check.sh — Step 9 hardware gate

  Device     ${DISK}  (${DU_MEDIA_NAME})

  ⚠️  THIS WRITES TO ${DISK}. It runs ONE RUN of FOUR CALLS over the FIRST 4 GiB, from
     block 0 — a gibibyte at each I/O size the UI offers (1, 2, 4, 8 MiB), each over its own
     region — polling live metrics from a second connection throughout.

     The cycle writes back exactly the bytes it read. That is proven in simulation and was
     verified byte-for-byte on this drive in Step 8 — but this script does not re-prove it.
     Run scripts/retention-cycle-check.sh for the fingerprinted proof.

  Requires the helper at protocol v12. Expect about a minute.

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
    exit "$status"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------------------
# Build and sign
# ---------------------------------------------------------------------------------------

echo "  building the probe …"
mkdir -p "$BUILD_DIR"
for src in "$SHARED" "$PROBE_SRC"; do
    [[ -f "$src" ]] || { echo "  FAIL  source not found: ${src}" >&2; exit 1; }
done

xcrun swiftc -swift-version 5 -O "$SHARED" "$PROBE_SRC" -o "$PROBE"

codesign --force --sign "Apple Development" --timestamp=none "$PROBE" 2>/dev/null \
    || codesign --force --sign - "$PROBE" >/dev/null 2>&1 || true

SIGNING="$(codesign -dv --verbose=4 "$PROBE" 2>&1 || true)"
if grep -q "TeamIdentifier=${TEAM_ID}" <<< "$SIGNING"; then
    check pass "probe is signed under team ${TEAM_ID}"
else
    check fail "probe is NOT signed under team ${TEAM_ID} — every call would be a transport error"
    exit 1
fi

# ---------------------------------------------------------------------------------------
# Unmount, then run with an independent CPU sampler alongside
# ---------------------------------------------------------------------------------------

echo
echo "  unmounting ${DISK} …"
diskutil unmountDisk "$DISK"

if [[ "$(mounted_count)" != "0" ]]; then
    check fail "${DISK} still has mounted volumes; the acquire would be refused"
    exit 1
fi
check pass "${DISK} fully unmounted"

# The daemon's CPU, sampled from outside. The helper reports its own figure via getrusage; a
# self-report nothing can contradict is a number rather than evidence, so this is the check on it.
: > "$PS_SAMPLES"
(
    while true; do
        ps -Ao pcpu,comm 2>/dev/null | grep "USBDriveTester.Helper" | awk '{print $1}' \
            >> "$PS_SAMPLES" || true
        sleep 0.5
    done
) &
SAMPLER_PID=$!
trap 'kill "$SAMPLER_PID" 2>/dev/null || true; cleanup' EXIT INT TERM

echo
set +e
"$PROBE" "$DISK" | tee "$OUTPUT"
PROBE_STATUS="${PIPESTATUS[0]}"
set -e

kill "$SAMPLER_PID" 2>/dev/null || true
trap cleanup EXIT INT TERM

value_of() {
    local line
    line="$(grep -m1 -- "$1" "$OUTPUT" || true)"
    sed 's/.*=//' <<< "$line"
}

# ---------------------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------------------

echo
echo "  ── assertions ──────────────────────────────────────────────────────────────────"
echo

HELPER_PROTOCOL="$(value_of 'PROTOCOL=')"
EXPECTED_PROTOCOL="$(value_of 'EXPECTED=')"
if [[ "$HELPER_PROTOCOL" == "$EXPECTED_PROTOCOL" && -n "$HELPER_PROTOCOL" ]]; then
    check pass "the running daemon implements protocol v${HELPER_PROTOCOL}"
else
    check fail "protocol mismatch: daemon v${HELPER_PROTOCOL:-<none>}, expected v${EXPECTED_PROTOCOL:-?}"
    echo "        v12 (Step 11 increment 6) reshaped BOTH replies: the two throughput arguments" >&2
    echo "        became wall-clock figures under new names, and coverageBytesPerSecond was added." >&2
    echo "        A v11 daemon sends twenty arguments where this expects twenty-one, so the decode" >&2
    echo "        fails outright — the loud failure. v11 before it was the quiet kind: it changed" >&2
    echo "        the MEANING of nine arguments without changing the signature, so a v10 daemon" >&2
    echo "        answered with figures that were well-formed, plausible and wrong." >&2
    echo "        Re-install (scripts/install-app.sh), then unregister and re-register in the app" >&2
    echo "        — install-app.sh only copies files — and confirm with Check protocol version." >&2
    exit 1
fi

[[ "$(value_of 'ACQUIRED=')" == "1" ]] \
    && check pass "the helper acquired ${DISK}" \
    || { check fail "the helper did not acquire ${DISK}"; exit 1; }

# Per-size facts. `grep -m1` on the size-qualified key, so no `head` is needed and the pipefail
# gotcha cannot bite.
size_value() {
    local line
    line="$(grep -m1 -- "\[size:$1\] $2=" "$OUTPUT" || true)"
    sed 's/.*=//' <<< "$line"
}

SWEEP="$(value_of 'SWEEP_SIZES=' | tr ',' ' ')"
DETAILED="$(value_of 'DETAILED_SIZE=')"

if [[ -z "$SWEEP" ]]; then
    check fail "the probe reported no I/O sizes to sweep"
    exit 1
fi

for SIZE in $SWEEP; do
    MIB=$(( SIZE / 1048576 ))
    echo
    echo "  ── ${MIB} MiB I/O ──"

    # Protocol v10: how THIS CALL ended. 1 is RunOutcomeCode.completed — and it is the one figure
    # in the reply that is still per-call, because it is what a sequencer branches on.
    OUTCOME="$(size_value "$SIZE" OUTCOME_CODE)"
    EXPECTED_OUTCOME="$(size_value "$SIZE" EXPECTED_OUTCOME_CODE)"
    [[ "$OUTCOME" == "$EXPECTED_OUTCOME" && -n "$OUTCOME" ]] \
        && check pass "${MIB} MiB: the call completed every planned chunk (outcome ${OUTCOME})" \
        || check fail "${MIB} MiB: outcome code ${OUTCOME:-?}, expected ${EXPECTED_OUTCOME:-?}"

    # `interruptedAtBlock` means something only for `pausedByUser`. A completed call must report 0,
    # or the app would have a resume point for a run that was never paused.
    [[ "$(size_value "$SIZE" INTERRUPTED_AT_BLOCK)" == "0" ]] \
        && check pass "${MIB} MiB: a completed call carries no resume block" \
        || check fail "${MIB} MiB: a completed call reported resume block $(size_value "$SIZE" INTERRUPTED_AT_BLOCK)"

    # CUMULATIVE from v11: the chunks the RUN has attempted, against a running total the probe
    # computed itself. A helper that reset its accumulator at each call would report this call's
    # count and be caught here at every size after the first.
    CHUNKS="$(size_value "$SIZE" CHUNKS)"
    EXPECTED="$(size_value "$SIZE" EXPECTED_CHUNKS)"
    [[ "$CHUNKS" == "$EXPECTED" && -n "$CHUNKS" ]] \
        && check pass "${MIB} MiB: ${CHUNKS} chunks for the run so far, as planned" \
        || check fail "${MIB} MiB: ${CHUNKS:-?} cumulative chunks, expected ${EXPECTED:-?}"

    [[ "$(size_value "$SIZE" FAILED_RANGES)" == "0" ]] \
        && check pass "${MIB} MiB: no failed block ranges in the run so far" \
        || check fail "${MIB} MiB: $(size_value "$SIZE" FAILED_RANGES) failed range(s) — $(size_value "$SIZE" FAILURE_SUMMARY)"

    [[ "$(size_value "$SIZE" CACHE_BYPASS)" == "1" ]] \
        && check pass "${MIB} MiB: FR-TEST-9 verdict is 'bypassed'" \
        || check fail "${MIB} MiB: cache-bypass verdict is $(size_value "$SIZE" CACHE_BYPASS), not 1"

    # --- Protocol v9 (Step 10). Two checks the wire could not support before.
    #
    # 1. THE MODE REACHED THE RUN. `RunCoordinator` is not in the test target, so nothing in the
    #    unit suite can show that the deciding observer was installed — and this device is
    #    healthy, so there is no failure for the mode to act on and reveal it. The helper echoing
    #    back which mode it ran in is the only evidence available here.
    MODE_USED="$(size_value "$SIZE" REPLY_FAILURE_MODE_USED)"
    [[ "$MODE_USED" == "2" ]] \
        && check pass "${MIB} MiB: the run used failure mode 2 (log and continue), as requested" \
        || check fail "${MIB} MiB: the run reports failure mode ${MODE_USED:-?}, expected 2"

    # 2. THE REPLY'S FIGURES AGREE WITH THE POLL'S. Same six numbers by two independent routes:
    #    `REPLY_*` came back inside `runRetentionCycle`'s reply, `FINAL_*` from a `runProgress`
    #    poll issued after it. The reply is twenty-one positional values assembled in the helper's
    #    `main.swift` — seven of them adjacent same-typed numbers from v12 — and no unit test can
    #    reach that assembly. A transposition there compiles, runs, and puts read throughput under
    #    "write" in an exported report. This is what makes it visible.
    for FIELD in READ_BYTES_PER_SECOND WRITE_BYTES_PER_SECOND COVERING_BYTES_PER_SECOND \
                 LATENCY_SAMPLES LATENCY_MIN_NS LATENCY_MAX_NS; do
        REPLY_VALUE="$(size_value "$SIZE" "REPLY_${FIELD}")"
        POLL_VALUE="$(size_value "$SIZE" "FINAL_${FIELD}")"
        [[ -n "$REPLY_VALUE" && "$REPLY_VALUE" == "$POLL_VALUE" ]] \
            && check pass "${MIB} MiB: ${FIELD} agrees across the reply and the poll (${REPLY_VALUE})" \
            || check fail "${MIB} MiB: ${FIELD} is '${REPLY_VALUE:-?}' in the reply but '${POLL_VALUE:-?}' from the poll"
    done

    # 3. AND THE LATENCIES ARE ORDERED. min <= max is the cheapest transposition detector there
    #    is, and it is independent of the agreement check above — the two figures could be
    #    consistently swapped on both paths if the helper built both from the same wrong place.
    LAT_MIN="$(size_value "$SIZE" REPLY_LATENCY_MIN_NS)"
    LAT_MAX="$(size_value "$SIZE" REPLY_LATENCY_MAX_NS)"
    LAT_P99="$(size_value "$SIZE" REPLY_LATENCY_P99_NS)"
    if [[ -n "$LAT_MIN" && -n "$LAT_MAX" && "$LAT_MIN" -le "$LAT_MAX" && "$LAT_MIN" -le "$LAT_P99" ]]; then
        check pass "${MIB} MiB: latency figures are ordered — min ${LAT_MIN} <= max ${LAT_MAX}, min <= p99 ${LAT_P99}"
    else
        check fail "${MIB} MiB: latency figures are not ordered — min ${LAT_MIN:-?}, max ${LAT_MAX:-?}, p99 ${LAT_P99:-?}"
    fi

    # 4. NO FAILING BLOCKS, counted the way the report will count them (FR-RPT-1). Distinct from
    #    FAILED_RANGES above: that is a range count, this is every failing block including any
    #    the retention cap dropped.
    [[ "$(size_value "$SIZE" REPLY_FAILED_BLOCKS)" == "0" ]] \
        && check pass "${MIB} MiB: no failing blocks" \
        || check fail "${MIB} MiB: $(size_value "$SIZE" REPLY_FAILED_BLOCKS) failing block(s)"

    # NFR-PERF-1: buffers are 2 x the I/O size, whatever the range's size — and this is one of the
    # two figures that stayed PER CALL under v11, deliberately: FR-CTRL-8 lets the I/O size change
    # mid-run, so a cumulative buffer figure would describe no call in particular. That it tracks
    # this call's size while everything around it accumulates is the assertion.
    BUFFERS="$(size_value "$SIZE" BUFFER_BYTES)"
    EXPECTED_BUFFERS="$(size_value "$SIZE" EXPECTED_BUFFER_BYTES)"
    [[ "$BUFFERS" == "$EXPECTED_BUFFERS" && -n "$BUFFERS" ]] \
        && check pass "${MIB} MiB: buffers held ${BUFFERS} B = 2 x this call's I/O size (NFR-PERF-1)" \
        || check fail "${MIB} MiB: buffers held ${BUFFERS:-?} B, expected ${EXPECTED_BUFFERS:-?}"

    # --- Live delivery (NFR-PERF-5). The vacuity guard first: snapshots arriving only before or
    # after a run prove nothing about delivery DURING a blocking privileged call.
    MID_RUN="$(size_value "$SIZE" SAMPLES_MID_RUN)"
    if [[ "${MID_RUN:-0}" -ge 5 ]]; then
        check pass "${MIB} MiB: ${MID_RUN} snapshots arrived mid-run, while the call was blocking"
    else
        check fail "${MIB} MiB: only ${MID_RUN:-0} mid-run snapshots — too few to establish live delivery"
    fi

    GAP="$(size_value "$SIZE" WIDEST_GAP_MS)"
    if python3 -c "import sys; sys.exit(0 if float('${GAP:-99999}') <= 1000 else 1)"; then
        check pass "${MIB} MiB: widest gap between snapshots ${GAP} ms (NFR-PERF-5 requires <= 1000)"
    else
        check fail "${MIB} MiB: widest gap ${GAP} ms, over NFR-PERF-5's 1000 ms"
    fi

    # --- Progress (FR-METR-5/6)
    #
    # Monotonic ACROSS THE WHOLE RUN, not within one call. The probe carries the high-water mark
    # from call to call, so a fraction or a block position that fell at a call boundary fails here
    # — and that fall is exactly what an accumulator reset at each call would produce.
    [[ "$(size_value "$SIZE" MONOTONIC)" == "1" ]] \
        && check pass "${MIB} MiB: progress and position advanced monotonically across the run" \
        || check fail "${MIB} MiB: progress or block position went backwards at a call boundary"

    # THE DENOMINATOR IS THE WHOLE DEVICE. The probe computes the expected fraction from the ioctl
    # block count and the bytes the run has asked for, so this is not the helper agreeing with
    # itself. A helper still dividing by the CALL's range would report ~100% here — which is what
    # the code did before Step 11 increment 3, and what the old `>= 99.99` assertion accepted.
    FINAL_FRACTION="$(size_value "$SIZE" FINAL_FRACTION)"
    EXPECTED_FRACTION="$(size_value "$SIZE" EXPECTED_FRACTION)"
    if python3 -c "import sys
a, b = float('${FINAL_FRACTION:--1}'), float('${EXPECTED_FRACTION:--2}')
sys.exit(0 if a >= 0 and abs(a - b) <= 0.0001 else 1)"; then
        check pass "${MIB} MiB: progress is ${FINAL_FRACTION}% of the device, as expected"
    else
        check fail "${MIB} MiB: progress reads ${FINAL_FRACTION:-?}% of the device, expected ${EXPECTED_FRACTION:-?}%"
    fi

    # And the position is where this call ended, absolutely — not where it ended within its own
    # range. Advancing per size is what makes this assertable at all.
    CURRENT_BLOCK="$(size_value "$SIZE" FINAL_CURRENT_BLOCK)"
    EXPECTED_BLOCK="$(size_value "$SIZE" EXPECTED_CURRENT_BLOCK)"
    [[ "$CURRENT_BLOCK" == "$EXPECTED_BLOCK" && -n "$CURRENT_BLOCK" ]] \
        && check pass "${MIB} MiB: the run's position is block ${CURRENT_BLOCK}, as expected" \
        || check fail "${MIB} MiB: position is block ${CURRENT_BLOCK:-?}, expected ${EXPECTED_BLOCK:-?}"

    # --- Latency (FR-METR-3)
    LAT_SAMPLES="$(size_value "$SIZE" FINAL_LATENCY_SAMPLES)"
    LAT_MIN="$(size_value "$SIZE" FINAL_LATENCY_MIN_NS)"
    LAT_MAX="$(size_value "$SIZE" FINAL_LATENCY_MAX_NS)"
    LAT_P99="$(size_value "$SIZE" FINAL_LATENCY_P99_NS)"

    # One sample per chunk OF THE WHOLE RUN. This is where a true whole-run p99 is visible on
    # hardware: percentiles do not compose, so the distribution has to be the union, and the union
    # is what a sample count equal to the run's cumulative chunk count says it is.
    [[ "$LAT_SAMPLES" == "$EXPECTED" ]] \
        && check pass "${MIB} MiB: one read-latency sample per chunk of the run (${LAT_SAMPLES})" \
        || check fail "${MIB} MiB: ${LAT_SAMPLES:-?} latency samples for ${EXPECTED:-?} cumulative chunks"

    if [[ -n "$LAT_MIN" && -n "$LAT_P99" && -n "$LAT_MAX" \
          && "$LAT_MIN" -le "$LAT_P99" && "$LAT_P99" -le "$LAT_MAX" ]]; then
        check pass "${MIB} MiB: min <= p99 <= max ($(python3 -c "print(f\"{int('$LAT_MIN')/1e6:.3f} / {int('$LAT_P99')/1e6:.3f} / {int('$LAT_MAX')/1e6:.3f} ms\")"))"
    else
        check fail "${MIB} MiB: latency ordering wrong — min ${LAT_MIN:-?}, p99 ${LAT_P99:-?}, max ${LAT_MAX:-?} ns"
    fi

    # A degenerate distribution satisfies the ordering above while saying nothing.
    [[ -n "$LAT_MAX" && -n "$LAT_MIN" && "$LAT_MAX" -gt "$LAT_MIN" ]] \
        && check pass "${MIB} MiB: the latency distribution has real spread (max > min)" \
        || check fail "${MIB} MiB: min == max — the distribution is degenerate"

    # --- Throughput (FR-METR-1). Above 8 GB/s no USB link of any generation carries it; that
    # would be a host answer, not a device one (the ceiling CacheBypassCheck uses as a backstop).
    READ_RATE="$(size_value "$SIZE" FINAL_READ_BYTES_PER_SECOND)"
    WRITE_RATE="$(size_value "$SIZE" FINAL_WRITE_BYTES_PER_SECOND)"
    COVER_RATE="$(size_value "$SIZE" FINAL_COVERING_BYTES_PER_SECOND)"
    if python3 -c "import sys; sys.exit(0 if 0 < float('${READ_RATE:--1}') < 8e9 else 1)"; then
        check pass "${MIB} MiB: read $(python3 -c "print(f\"{float('$READ_RATE')/1e6:.0f}\")") MB/s, write $(python3 -c "print(f\"{float('${WRITE_RATE:--1}')/1e6:.0f}\")") MB/s — transport-plausible"
    else
        check fail "${MIB} MiB: read throughput ${READ_RATE:-?} B/s is not transport-plausible"
    fi

    # --- THE THREE RATES SHARE ONE DENOMINATOR (protocol v12, FR-METR-1/5).
    #
    # This is the assertion that would have caught the 2026-08-17 report on hardware. Until v12
    # the app divided read and write by *phase* time and covering by the wall clock, so the three
    # were not on one scale and nothing here could have compared them. They now all divide by the
    # wall clock, which forces an arithmetic identity on a healthy run:
    #
    #     read ≈ 2 × covering     (the original read and the verify read)
    #     write ≈ 1 × covering    (one write per covered byte)
    #
    # A 10% band, because a run with failed chunks legitimately reads less than twice its coverage
    # — that is the signal, not noise — and this gate runs on a healthy drive. If this fails on
    # good hardware, a rate has gone back to dividing by something other than the wall clock, and
    # the figure on the user's screen no longer matches what Activity Monitor shows them.
    if python3 - "$READ_RATE" "$WRITE_RATE" "$COVER_RATE" <<'RATIO'; then
import sys
read, write, cover = (float(v) for v in sys.argv[1:4])
sys.exit(0 if cover > 0
         and abs(read / cover - 2.0) <= 0.2
         and abs(write / cover - 1.0) <= 0.1 else 1)
RATIO
        check pass "${MIB} MiB: read/write/covering share one denominator — $(python3 -c "print(f\"{float('$READ_RATE')/float('$COVER_RATE'):.2f}x / {float('$WRITE_RATE')/float('$COVER_RATE'):.2f}x covering\")")"
    else
        check fail "${MIB} MiB: the rates do not share a denominator — read=${READ_RATE:-?} write=${WRITE_RATE:-?} covering=${COVER_RATE:-?}; expected read≈2x and write≈1x covering"
    fi
done

# ---------------------------------------------------------------------------------------
# NFR-PERF-3, and the question the sweep exists to settle
# ---------------------------------------------------------------------------------------

PS_PEAK="$(sort -rn "$PS_SAMPLES" 2>/dev/null | head -1 || echo "")"
PS_COUNT="$(wc -l < "$PS_SAMPLES" 2>/dev/null | tr -d ' ' || echo 0)"

echo
echo "  ── NFR-PERF-3: device-bound, or host-bound? ────────────────────────────────────"
echo

# The per-size normalisation table that used to live here is gone, and the reason is in this
# script's header: it existed to settle whether host cost follows bytes moved or chunk count, that
# was measured on 2026-08-05, and CONSTRAINTS section 1 records the answer. Under a cumulative
# session the per-size figures are running totals of one run and cannot be compared with one
# another — printing the comparison anyway would be a table that looks like evidence and is not.
#
# What is asserted instead is the requirement's own claim, on the run as a whole.

value_at_end() {
    local line
    line="$(grep -m1 -- "\[run\] $1=" "$OUTPUT" || true)"
    sed 's/.*=//' <<< "$line"
}

RUN_OVERHEAD="$(value_at_end CUMULATIVE_HOST_OVERHEAD_FRACTION)"
RUN_CORE="$(value_at_end CUMULATIVE_HELPER_CORE_FRACTION)"
RUN_CHUNKS="$(value_at_end CUMULATIVE_CHUNKS)"
RUN_EXPECTED_CHUNKS="$(value_at_end CUMULATIVE_EXPECTED_CHUNKS)"
RUN_SAMPLES="$(value_at_end CUMULATIVE_LATENCY_SAMPLES)"

python3 - "${RUN_OVERHEAD:--1}" "${RUN_CORE:--1}" "${RUN_CHUNKS:-0}" "${PS_PEAK:-}" "${PS_COUNT:-0}" <<'PY'
import sys
overhead, core, chunks, ps_peak, ps_count = sys.argv[1:6]
o, c = float(overhead), float(core)
print(f"    the run, cumulative over four calls and {chunks} chunks:")
print()
print(f"      host overhead   {o*100:.3f}% of device I/O time" if o >= 0 else
      "      host overhead   not established")
print(f"      daemon CPU      {c*100:.3f}% of one core" if c >= 0 else
      "      daemon CPU      not established")
print(f"      ps cross-check  peak {ps_peak or 'not sampled'}% of one core, over {ps_count} samples")
PY
echo

if [[ -n "$PS_PEAK" ]]; then
    check pass "an independent ps sample exists to cross-check the self-reported CPU"
else
    check fail "no independent CPU sample — the self-reported figure stands uncorroborated"
fi

# The run's totals, against the running totals the probe computed for itself. This is the
# whole-session claim in one line: four calls, one accumulator.
[[ "$RUN_CHUNKS" == "$RUN_EXPECTED_CHUNKS" && -n "$RUN_CHUNKS" ]] \
    && check pass "the run accumulated ${RUN_CHUNKS} chunks across its four calls, as planned" \
    || check fail "the run reports ${RUN_CHUNKS:-?} cumulative chunks, expected ${RUN_EXPECTED_CHUNKS:-?}"

[[ "$RUN_SAMPLES" == "$RUN_EXPECTED_CHUNKS" && -n "$RUN_SAMPLES" ]] \
    && check pass "one read-latency sample per chunk of the whole run (${RUN_SAMPLES}) — a true whole-run p99" \
    || check fail "the run reports ${RUN_SAMPLES:-?} latency samples for ${RUN_EXPECTED_CHUNKS:-?} chunks"

# The requirement's own claim, on the run rather than on one call.
if python3 -c "import sys; sys.exit(0 if float('${RUN_OVERHEAD:--1}') >= 0 else 1)"; then
    check pass "the host-overhead ratio was established for the run"
else
    check fail "the host-overhead ratio was not established"
fi

if python3 -c "import sys; sys.exit(0 if 0 <= float('${RUN_OVERHEAD:--1}') < 0.05 else 1)"; then
    check pass "over the whole run, host overhead is under 5% of device I/O time — device-bound"
else
    check fail "over the whole run, host overhead is ${RUN_OVERHEAD:-?} of device I/O time — investigate before claiming device-bound"
fi

# --- 6. FR-TEST-10, shown refusing -------------------------------------------------------
#
# The successful run above satisfies the placement rule, which proves the rule did not get in the
# way — and says nothing about whether it is enforced. An unenforced guard looks exactly like an
# enforced one right up until something misaligned arrives. Neither request below performs any
# I/O: placement is validated before a block device is vended.

echo
MISALIGNED_REFUSED="$(grep -m1 -- '\[misaligned\] REFUSED=' "$OUTPUT" | sed 's/.*=//' || true)"
MISALIGNED_CHUNKS="$(grep -m1 -- '\[misaligned\] CHUNKS=' "$OUTPUT" | sed 's/.*=//' || true)"
PARTIAL_REFUSED="$(grep -m1 -- '\[partial\] REFUSED=' "$OUTPUT" | sed 's/.*=//' || true)"
PARTIAL_CHUNKS="$(grep -m1 -- '\[partial\] CHUNKS=' "$OUTPUT" | sed 's/.*=//' || true)"

[[ "$MISALIGNED_REFUSED" == "1" ]] \
    && check pass "a start off the 1 MiB boundary was refused (FR-TEST-10)" \
    || check fail "a start at block 1 was NOT refused — the alignment guard is not enforced"

[[ "${MISALIGNED_CHUNKS:-1}" == "0" ]] \
    && check pass "the refused misaligned call reported no chunks" \
    || check fail "the refused misaligned call reported ${MISALIGNED_CHUNKS} chunk(s) — a refusal contributed none"

[[ "$PARTIAL_REFUSED" == "1" ]] \
    && check pass "a length short of a whole MiB, mid-device, was refused (FR-TEST-10)" \
    || check fail "a partial-MiB length was NOT refused — the length guard is not enforced"

[[ "${PARTIAL_CHUNKS:-1}" == "0" ]] \
    && check pass "the refused partial-length call reported no chunks" \
    || check fail "the refused partial-length call reported ${PARTIAL_CHUNKS} chunk(s) — a refusal contributed none"

# --- FR-FAIL-1's mode, which protocol v9 made a required parameter (Step 10).
#
# An unrecognised mode code is REFUSED, never defaulted. That direction matters: quietly resolving
# an unknown code to FR-FAIL-4's default would answer a caller asking to stop on the first error
# with a run that writes to the whole drive — a request silently met by a larger action. The
# placement in this request is valid, so a refusal can only be the mode.
BADMODE_REFUSED="$(grep -m1 -- '\[badmode\] REFUSED=' "$OUTPUT" | sed 's/.*=//' || true)"
BADMODE_CHUNKS="$(grep -m1 -- '\[badmode\] CHUNKS=' "$OUTPUT" | sed 's/.*=//' || true)"

[[ "$BADMODE_REFUSED" == "1" ]] \
    && check pass "an unrecognised failure-mode code was refused (FR-FAIL-1)" \
    || check fail "failure-mode code 99 was NOT refused — an unknown mode is being defaulted"

[[ "${BADMODE_CHUNKS:-1}" == "0" ]] \
    && check pass "the refused bad-mode call reported no chunks" \
    || check fail "the refused bad-mode call reported ${BADMODE_CHUNKS} chunk(s) — a refusal contributed none"

# --- A REFUSED CALL CARRIES NO FIGURES, AND THIS IS NOW THE SHARPEST CHECK IN THE FILE.
#
# Under protocol v9 the guard was structural: the observer a call read its figures from did not
# exist until that call had passed validation, so a refusal had nothing to misattribute. Step 11
# moved the accumulators onto the claim, so they now predate the call — at this instant the
# session holds four gibibytes of entirely plausible measurements — and what keeps the property is
# only that `RunCoordinator` returns a `CycleResult` on the success path alone, leaving
# `main.swift`'s refusal path with nothing to read from.
#
# That is a weaker guard than v9's, said plainly rather than rounded up. `main.swift` is not in the
# test target, so no unit test compiles that reply assembly. **These four lines are the only check
# anywhere that reaches it**, and the figures a regression would leak are no longer some previous
# run's — they are this run's, which is exactly what makes them believable in a report.
for LABEL in misaligned partial badmode; do
    OUTCOME="$(grep -m1 -- "\[$LABEL\] OUTCOME_CODE=" "$OUTPUT" | sed 's/.*=//' || true)"
    CHUNKS_SEEN="$(grep -m1 -- "\[$LABEL\] CHUNKS=" "$OUTPUT" | sed 's/.*=//' || true)"
    MODE_USED="$(grep -m1 -- "\[$LABEL\] MODE_USED=" "$OUTPUT" | sed 's/.*=//' || true)"
    READ_RATE="$(grep -m1 -- "\[$LABEL\] READ_BYTES_PER_SECOND=" "$OUTPUT" | sed 's/.*=//' || true)"
    WRITE_RATE="$(grep -m1 -- "\[$LABEL\] WRITE_BYTES_PER_SECOND=" "$OUTPUT" | sed 's/.*=//' || true)"
    COVER_RATE="$(grep -m1 -- "\[$LABEL\] COVERING_BYTES_PER_SECOND=" "$OUTPUT" | sed 's/.*=//' || true)"
    SAMPLES="$(grep -m1 -- "\[$LABEL\] LATENCY_SAMPLES=" "$OUTPUT" | sed 's/.*=//' || true)"
    RANGES="$(grep -m1 -- "\[$LABEL\] RANGES_ENCODED=" "$OUTPUT" | sed 's/.*=//' || true)"

    if [[ "$OUTCOME" == "0" && "$CHUNKS_SEEN" == "0" && "$MODE_USED" == "0" \
          && "$READ_RATE" == "-1.0" && "$WRITE_RATE" == "-1.0" && "$COVER_RATE" == "-1.0" \
          && "$SAMPLES" == "0" && -z "$RANGES" ]]; then
        check pass "the refused '${LABEL}' call reported no outcome, no mode and no figures"
    else
        check fail "the refused '${LABEL}' call reported figures — outcome=${OUTCOME:-?} chunks=${CHUNKS_SEEN:-?} mode=${MODE_USED:-?} read=${READ_RATE:-?} write=${WRITE_RATE:-?} covering=${COVER_RATE:-?} samples=${SAMPLES:-?} ranges='${RANGES}'"
    fi
done

[[ "$(value_of 'RELEASED=')" == "1" ]] \
    && check pass "the helper released ${DISK}" \
    || check fail "the helper did not confirm release"

# --- 7. THE SESSION DIES WITH THE CLAIM.
#
# Under protocol v9 a poll after a run returned that run's final figures for as long as the daemon
# lived, because nothing ever cleared the slot — which is what made a REFUSED run able to hand back
# a previous one's numbers. The session is a property of the claim, so `releaseDevice` destroyed the
# accumulators and there is nothing left to report.
#
# This is the assertion that makes "a poll cannot return a previous run's figures" a fact about the
# object graph rather than about somebody remembering to clear something — and it is the one thing
# in this gate that would have been impossible to state before this increment.
AFTER_AVAILABLE="$(grep -m1 -- '\[after-release\] AVAILABLE=' "$OUTPUT" | sed 's/.*=//' || true)"
AFTER_SAMPLES="$(grep -m1 -- '\[after-release\] LATENCY_SAMPLES=' "$OUTPUT" | sed 's/.*=//' || true)"
AFTER_RATE="$(grep -m1 -- '\[after-release\] READ_BYTES_PER_SECOND=' "$OUTPUT" | sed 's/.*=//' || true)"

if [[ "$AFTER_AVAILABLE" == "0" && "$AFTER_SAMPLES" == "0" && "$AFTER_RATE" == "-1.0" ]]; then
    check pass "a poll after the release reports nothing — the session died with the claim"
else
    check fail "a poll after the release still has figures — available=${AFTER_AVAILABLE:-?} samples=${AFTER_SAMPLES:-?} read=${AFTER_RATE:-?}"
fi

echo
if [[ "$PROBE_STATUS" != "0" && "$FAILURES" -eq 0 ]]; then
    check fail "the probe exited ${PROBE_STATUS} but every assertion passed; investigate"
fi

if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${FAILURES} failures. Step 9's hardware-only gate items are discharged, and so is"
    echo "  Step 11 increment 3's: the run session, cumulative figures in the cycle's reply, and"
    echo "  whole-device progress, all on real media."
    echo
    echo "  Still owed at Step 11 increment 7, with the other two Step 10 gates:"
    echo "  scripts/retention-cycle-check.sh, because the helper binary moved."
    echo
    echo "  Note it is owed for THAT reason and not because the write path changed. Increment 3"
    echo "  did not touch RetentionTestEngine: it changed what the observers accumulate and what"
    echo "  the reply reports. Accumulating is not writing, and NFR-REL-1 is about the bytes."
else
    echo "  ${FAILURES} failure(s) — see FAIL lines above."
fi
echo "  Full output: ${OUTPUT}"

exit "$FAILURES"
