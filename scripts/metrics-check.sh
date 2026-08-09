#!/bin/bash
#
# metrics-check.sh — Step 9's hardware gate.
#
# Runs a real bounded cycle at **every** I/O size FR-CTRL-8 offers — 1, 2, 4 and 8 MiB — over the
# same gibibyte, polling each one's live metrics from a SECOND connection the way the GUI does,
# then asserts the things that can only be established on real media:
#
#   1. LIVE DELIVERY (NFR-PERF-5). Snapshots arrive at least once per second *while a blocking
#      privileged call is in flight*. This is a property of the transport, not of the metrics
#      code — and it is why the poll goes out on a second connection at all (measured
#      2026-08-04, scripts/xpc-concurrency-check.sh).
#   2. PROGRESS (FR-METR-5/6). Advances monotonically, reaches 100%, ends at the right block.
#   3. LATENCY (FR-METR-3). min <= p99 <= max, one sample per chunk, nothing in histogram
#      overflow — i.e. the range chosen actually covers real read latencies.
#   4. THROUGHPUT (FR-METR-1). Transport-plausible rather than RAM-plausible.
#   5. NFR-PERF-3, which has never had a number: host overhead as a fraction of device I/O time,
#      and the daemon's CPU as a fraction of one core, both at a stated MB/s.
#   6. FR-TEST-10 SHOWN REFUSING. A run that satisfies the placement rule proves the rule did not
#      get in the way; it says nothing about whether it is enforced. Both forbidden placements are
#      asked for explicitly and both must be refused with zero chunks processed.
#
# The CPU figure is ALSO sampled independently with `ps` while the run is in flight, because a
# self-reported number that nothing can contradict is a number, not evidence.
#
# ## Why every I/O size, and not just the default
#
# NFR-PERF-3's host-overhead figure was measured at 4 MiB only (2026-08-04), which left the Step 16
# release note unable to say whether that cost follows **bytes moved** or **chunk count**. The two
# imply opposite advice about I/O size, so guessing is worse than not saying. Sweeping all four
# sizes over the same gibibyte gives an 8x lever on chunk count at constant bytes, which settles
# it — and incidentally exercises the chunk plan at every size the UI can select, on real media.
#
# The 40-80 us estimate that stood for three steps was wrong by 11x for want of exactly this.
#
# ⚠️  THIS WRITES TO THE DRIVE.
#   The cycle covers the FIRST 1 GiB, starting at block 0 — where a real run begins (FR-TEST-4),
#   1 MiB-aligned by construction (FR-TEST-10). It writes back exactly the bytes it read.
#
#   This script does NOT re-prove non-destructiveness: `scripts/retention-cycle-check.sh` is what
#   fingerprints the device either side of a run, and it should be run as the Step 9 regression
#   because Step 9 changed the engine's inner loop.
#
# PREREQUISITES
#   * The helper must be registered, enabled, running from /Applications, and at **protocol v8**.
#     Step 9 changed `runRetentionCycle`'s signature, so a v7 daemon fails that call as a
#     transport error. Re-install and re-register before running this.
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

  ⚠️  THIS WRITES TO ${DISK}. It runs the read → write-back → verify cycle over the FIRST
     1 GiB, from block 0, FOUR TIMES — once at each I/O size the UI offers (1, 2, 4, 8 MiB) —
     polling each one's live metrics from a second connection.

     The cycle writes back exactly the bytes it read. That is proven in simulation and was
     verified byte-for-byte on this drive in Step 8 — but this script does not re-prove it.
     Run scripts/retention-cycle-check.sh for the fingerprinted proof.

  Requires the helper at protocol v8. Expect about a minute.

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
    echo "        runRetentionCycle's signature changed in protocol v8 (Step 9) and again in v9" >&2
    echo "        (Step 10, which added the failure mode and the report's figures)." >&2
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

    [[ "$(size_value "$SIZE" COMPLETED)" == "1" ]] \
        && check pass "${MIB} MiB: the cycle completed every planned chunk" \
        || check fail "${MIB} MiB: the cycle did not complete"

    CHUNKS="$(size_value "$SIZE" CHUNKS)"
    EXPECTED="$(size_value "$SIZE" EXPECTED_CHUNKS)"
    [[ "$CHUNKS" == "$EXPECTED" && -n "$CHUNKS" ]] \
        && check pass "${MIB} MiB: processed ${CHUNKS} chunks, as planned" \
        || check fail "${MIB} MiB: processed ${CHUNKS:-?} chunks, expected ${EXPECTED:-?}"

    [[ "$(size_value "$SIZE" FAILED_RANGES)" == "0" ]] \
        && check pass "${MIB} MiB: no failed block ranges" \
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
    #    poll issued after it. The reply is nineteen positional values assembled in the helper's
    #    `main.swift` — six of them adjacent same-typed numbers — and no unit test can reach that
    #    assembly. A transposition there compiles, runs, and puts read throughput under "write"
    #    in an exported report. This is what makes it visible.
    for FIELD in READ_BYTES_PER_SECOND WRITE_BYTES_PER_SECOND \
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

    # NFR-PERF-1: buffers are 2 x the I/O size, whatever the range's size.
    BUFFERS="$(size_value "$SIZE" BUFFER_BYTES)"
    [[ "$BUFFERS" == "$(( SIZE * 2 ))" ]] \
        && check pass "${MIB} MiB: buffers held ${BUFFERS} B = 2 x the I/O size (NFR-PERF-1)" \
        || check fail "${MIB} MiB: buffers held ${BUFFERS:-?} B, expected $(( SIZE * 2 ))"

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
    [[ "$(size_value "$SIZE" MONOTONIC)" == "1" ]] \
        && check pass "${MIB} MiB: progress advanced monotonically" \
        || check fail "${MIB} MiB: progress went backwards at least once"

    FINAL_FRACTION="$(size_value "$SIZE" FINAL_FRACTION)"
    if python3 -c "import sys; sys.exit(0 if float('${FINAL_FRACTION:-0}') >= 99.99 else 1)"; then
        check pass "${MIB} MiB: progress reached ${FINAL_FRACTION}%"
    else
        check fail "${MIB} MiB: progress ended at ${FINAL_FRACTION:-?}%, not 100%"
    fi

    # --- Latency (FR-METR-3)
    LAT_SAMPLES="$(size_value "$SIZE" FINAL_LATENCY_SAMPLES)"
    LAT_MIN="$(size_value "$SIZE" FINAL_LATENCY_MIN_NS)"
    LAT_MAX="$(size_value "$SIZE" FINAL_LATENCY_MAX_NS)"
    LAT_P99="$(size_value "$SIZE" FINAL_LATENCY_P99_NS)"

    [[ "$LAT_SAMPLES" == "$EXPECTED" ]] \
        && check pass "${MIB} MiB: one read-latency sample per chunk (${LAT_SAMPLES})" \
        || check fail "${MIB} MiB: ${LAT_SAMPLES:-?} latency samples for ${EXPECTED:-?} chunks"

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
    if python3 -c "import sys; sys.exit(0 if 0 < float('${READ_RATE:--1}') < 8e9 else 1)"; then
        check pass "${MIB} MiB: read $(python3 -c "print(f\"{float('$READ_RATE')/1e6:.0f}\")") MB/s, write $(python3 -c "print(f\"{float('${WRITE_RATE:--1}')/1e6:.0f}\")") MB/s — transport-plausible"
    else
        check fail "${MIB} MiB: read throughput ${READ_RATE:-?} B/s is not transport-plausible"
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

python3 - "$OUTPUT" "$DETAILED" "$PS_PEAK" "$PS_COUNT" <<'PY'
import re, sys
path, detailed, ps_peak, ps_count = sys.argv[1:5]
text = open(path).read()

def per_size(key):
    out = {}
    for m in re.finditer(rf"\[(?:size|scaling):(\d+)\] {key}=(\S+)", text):
        out[int(m.group(1))] = m.group(2)
    return out

overhead   = per_size("HOST_OVERHEAD_FRACTION")
core       = per_size("HELPER_CORE_FRACTION")
per_chunk  = per_size("US_PER_CHUNK")
per_mib    = per_size("US_PER_MIB")
read_rate  = per_size("FINAL_READ_BYTES_PER_SECOND")

sizes = sorted(overhead)
print(f"    {'I/O size':<11}{'overhead %':<13}{'CPU % core':<13}{'us/chunk':<12}{'us/MiB':<10}read MB/s")
for s in sizes:
    try:
        o, c = float(overhead[s]), float(core[s])
    except (ValueError, KeyError):
        continue
    r = float(read_rate.get(s, -1))
    print(f"    {s>>20:>2} MiB     {o*100:<13.3f}{c*100:<13.3f}"
          f"{float(per_chunk.get(s,0)):<12.1f}{float(per_mib.get(s,0)):<10.1f}"
          f"{r/1e6:.0f}" if r >= 0 else "")

def spread(d):
    vals = [float(v) for v in d.values() if float(v) > 0]
    return (max(vals) / min(vals)) if len(vals) >= 2 and min(vals) > 0 else float("nan")

sc, sm = spread(per_chunk), spread(per_mib)
print()
print(f"    us/chunk varies by {sc:.2f}x across the sweep; us/MiB varies by {sm:.2f}x.")
print(f"    (the I/O size itself varies by {max(sizes)/min(sizes):.0f}x)")
print()
if sc == sc and sm == sm:
    if sm < sc / 2:
        print("    => Host cost follows BYTES MOVED. A larger I/O size will NOT reduce it.")
    elif sc < sm / 2:
        print("    => Host cost follows CHUNK COUNT. A larger I/O size reduces it proportionally.")
    else:
        print("    => Neither normalisation is clearly flat; the cost has both components.")
        print("       Report the numbers in the release note rather than a rule of thumb.")
print()
print(f"    daemon CPU, independent ps sample (peak of {ps_count}): {ps_peak or 'not sampled'}%")
PY
echo

if [[ -n "$PS_PEAK" ]]; then
    check pass "an independent ps sample exists to cross-check the self-reported CPU"
else
    check fail "no independent CPU sample — the self-reported figure stands uncorroborated"
fi

for SIZE in $SWEEP; do
    OH="$(size_value "$SIZE" HOST_OVERHEAD_FRACTION)"
    if python3 -c "import sys; sys.exit(0 if float('${OH:--1}') >= 0 else 1)"; then
        :
    else
        check fail "$(( SIZE / 1048576 )) MiB: the host-overhead ratio was not established"
    fi
done
check pass "the host-overhead ratio was established at every I/O size"

# The requirement's own claim, at the default size the product ships with.
DEFAULT_OH="$(size_value "$DETAILED" HOST_OVERHEAD_FRACTION)"
if python3 -c "import sys; sys.exit(0 if float('${DEFAULT_OH:--1}') < 0.05 else 1)"; then
    check pass "at the default I/O size, host overhead is under 5% of device I/O time — device-bound"
else
    check fail "at the default I/O size, host overhead is $(python3 -c "print(f\"{float('$DEFAULT_OH')*100:.2f}%\")") — investigate before claiming device-bound"
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
    && check pass "the refused misaligned request processed no chunks" \
    || check fail "the misaligned request processed ${MISALIGNED_CHUNKS} chunk(s) before refusing"

[[ "$PARTIAL_REFUSED" == "1" ]] \
    && check pass "a length short of a whole MiB, mid-device, was refused (FR-TEST-10)" \
    || check fail "a partial-MiB length was NOT refused — the length guard is not enforced"

[[ "${PARTIAL_CHUNKS:-1}" == "0" ]] \
    && check pass "the refused partial-length request processed no chunks" \
    || check fail "the partial-length request processed ${PARTIAL_CHUNKS} chunk(s) before refusing"

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
    && check pass "the refused bad-mode request processed no chunks" \
    || check fail "the bad-mode request processed ${BADMODE_CHUNKS} chunk(s) before refusing"

# --- A REFUSED RUN CARRIES NO FIGURES. This is the hardware evidence for why protocol v9 puts
# the final throughput and latency in the cycle's own reply instead of leaving a caller to poll
# `runProgress` after it.
#
# At this instant the helper's `MetricsChannel` slot still holds the numbers from the four
# completed sweep runs above, because `begin()` runs after validation and a refusal returns before
# it. A caller that polled would get them — correctly formatted, plausible, and belonging to a
# different run — and put them in a report that outlives the session. In the reply they belong to
# this run or they do not exist.
for LABEL in misaligned partial badmode; do
    MODE_USED="$(grep -m1 -- "\[$LABEL\] MODE_USED=" "$OUTPUT" | sed 's/.*=//' || true)"
    READ_RATE="$(grep -m1 -- "\[$LABEL\] READ_BYTES_PER_SECOND=" "$OUTPUT" | sed 's/.*=//' || true)"
    WRITE_RATE="$(grep -m1 -- "\[$LABEL\] WRITE_BYTES_PER_SECOND=" "$OUTPUT" | sed 's/.*=//' || true)"
    SAMPLES="$(grep -m1 -- "\[$LABEL\] LATENCY_SAMPLES=" "$OUTPUT" | sed 's/.*=//' || true)"
    RANGES="$(grep -m1 -- "\[$LABEL\] RANGES_ENCODED=" "$OUTPUT" | sed 's/.*=//' || true)"

    if [[ "$MODE_USED" == "0" && "$READ_RATE" == "-1.0" && "$WRITE_RATE" == "-1.0" \
          && "$SAMPLES" == "0" && -z "$RANGES" ]]; then
        check pass "the refused '${LABEL}' run reported no mode and no figures"
    else
        check fail "the refused '${LABEL}' run reported figures — mode=${MODE_USED:-?} read=${READ_RATE:-?} write=${WRITE_RATE:-?} samples=${SAMPLES:-?} ranges='${RANGES}'"
    fi
done

[[ "$(value_of 'RELEASED=')" == "1" ]] \
    && check pass "the helper released ${DISK}" \
    || check fail "the helper did not confirm release"

echo
if [[ "$PROBE_STATUS" != "0" && "$FAILURES" -eq 0 ]]; then
    check fail "the probe exited ${PROBE_STATUS} but every assertion passed; investigate"
fi

if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${FAILURES} failures. Step 9's hardware-only gate items are discharged."
    echo
    echo "  Still owed: scripts/retention-cycle-check.sh ${DISK} as the Step 9 regression —"
    echo "  this step changed the engine's inner loop, which re-opens NFR-REL-1."
else
    echo "  ${FAILURES} failure(s) — see FAIL lines above."
fi
echo "  Full output: ${OUTPUT}"

exit "$FAILURES"
