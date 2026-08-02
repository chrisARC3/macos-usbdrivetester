#!/bin/bash
#
# usb-speed-check.sh — dumps the "Device Speed" code every attached USB device reports, and
# checks the mapping Core/USBLinkSpeed.swift relies on still looks right.
#
# WHY THIS EXISTS
#
# FR-TEST-9's throughput falsifier derives its ceiling from the device's negotiated USB link
# speed, read from the IORegistry key "Device Speed". That key's enumeration is NOT defined
# in any SDK header:
#
#   * IOUSBHostFamilyDefinitions.h defines tIOUSBHostConnectionSpeed as
#       None=0, Full=1, Low=2, High=3, Super=4, SuperPlus=5, SuperPlusBy2=6
#     ...but that documents kUSBHostMatchingPropertySpeed, a DIFFERENT property.
#   * The key actually present on these devices is the legacy IOUSBFamily "Device Speed",
#     whose enum is
#       Low=0, Full=1, High=2, Super=3, SuperPlus=4, SuperPlusBy2=5
#     and which the SDK does not declare at all.
#
# The legacy mapping was established on 2026-08-02 by reading the live registry and checking
# each device against the standard it is known to implement. That is evidence, not a
# specification — so it can drift, and drifting by one in the wrong direction would put the
# ceiling BELOW every legitimate read and flag every run as cached.
#
# This script is what makes that drift visible. Run it whenever macOS is updated, or whenever
# the cache-bypass check starts reporting something surprising.
#
# NON-DESTRUCTIVE. Reads the registry only. No device is opened, no root needed, no drive
# state changes.
#
# Usage:
#   scripts/usb-speed-check.sh              # every USB device with a Device Speed
#   scripts/usb-speed-check.sh disk4 disk8  # also resolve these disks to their link speed
#
set -euo pipefail

FAILURES=0

check() {
    if [[ "$1" == "pass" ]]; then
        echo "  PASS  $2"
    else
        echo "  FAIL  $2"
        FAILURES=$((FAILURES + 1))
    fi
}

# The mapping Core/USBLinkSpeed.swift implements. Restated here so a drift shows up as a
# disagreement between two places rather than as a silent change in one.
speed_name() {
    case "$1" in
        0) echo "Low (1.5 Mb/s)" ;;
        1) echo "Full (12 Mb/s)" ;;
        2) echo "High (480 Mb/s)" ;;
        3) echo "SuperSpeed (5 Gb/s)" ;;
        4) echo "SuperSpeed+ (10 Gb/s)" ;;
        5) echo "SuperSpeed+ (20 Gb/s)" ;;
        *) echo "UNRECOGNISED" ;;
    esac
}

echo
echo "  usb-speed-check — IORegistry \"Device Speed\" codes"
echo "  macOS $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"
echo

# ---------------------------------------------------------------------------------------
# Every USB device that reports a speed
# ---------------------------------------------------------------------------------------

echo "  All attached USB devices:"
echo

REGISTRY="$(ioreg -c IOUSBHostDevice -r -l 2>/dev/null || true)"

# Pair each "USB Product Name" with the "Device Speed" that follows it in the same entry.
# awk rather than a grep pipeline: under `set -o pipefail`, a producer feeding a grep that
# exits early returns non-zero and would abort the script (this repo has been bitten by
# exactly that interaction).
awk '
    /"USB Product Name"/ {
        line = $0
        sub(/.*"USB Product Name" = "/, "", line)
        sub(/".*/, "", line)
        name = line
    }
    /"Device Speed"/ && name != "" {
        line = $0
        sub(/.*"Device Speed" = /, "", line)
        gsub(/[^0-9].*/, "", line)
        if (line != "") { print line "\t" name; name = "" }
    }
' <<< "$REGISTRY" | sort -u | while IFS=$'\t' read -r code name; do
    printf '    code %-3s %-28s %s\n' "$code" "$(speed_name "$code")" "$name"
done

# ---------------------------------------------------------------------------------------
# Sanity checks on the mapping itself
# ---------------------------------------------------------------------------------------

echo
echo "  Mapping sanity:"
echo

CODES="$(awk '/"Device Speed"/ { line = $0; sub(/.*"Device Speed" = /, "", line); gsub(/[^0-9].*/, "", line); if (line != "") print line }' <<< "$REGISTRY" | sort -u)"

if [[ -z "$CODES" ]]; then
    check fail "no USB device reported a Device Speed — nothing to check against"
else
    UNKNOWN=""
    while read -r code; do
        [[ -z "$code" ]] && continue
        if [[ "$(speed_name "$code")" == "UNRECOGNISED" ]]; then
            UNKNOWN="${UNKNOWN} ${code}"
        fi
    done <<< "$CODES"

    if [[ -z "$UNKNOWN" ]]; then
        check pass "every observed code ($(tr '\n' ' ' <<< "$CODES" | sed 's/ $//')) maps to a known speed"
    else
        check fail "unrecognised Device Speed code(s):${UNKNOWN} — Core/USBLinkSpeed.swift would fall back to the fixed ceiling for these"
    fi
fi

# The tell-tale of a shifted enum: under the SDK's tIOUSBHostConnectionSpeed, code 0 means
# "no device connected". A device that is plainly present and reports 0 therefore proves the
# legacy mapping is the one in force — this is the observation the whole mapping rests on.
if grep -q '"Device Speed" = 0' <<< "$REGISTRY"; then
    check pass "a connected device reports code 0, which is Low Speed here and \"no device connected\" under the SDK enum — the legacy mapping is in force"
else
    echo "  NOTE  no device currently reports code 0 (typically a keyboard or mouse), so the"
    echo "        strongest single check of the mapping is unavailable right now. Plug in a"
    echo "        USB keyboard or mouse and re-run to confirm it."
fi

# ---------------------------------------------------------------------------------------
# Resolve specific disks, the way the helper does
# ---------------------------------------------------------------------------------------

if [[ $# -gt 0 ]]; then
    echo
    echo "  Disks resolved through their IOKit ancestry (the search the helper performs):"
    echo

    # `ioreg -n disk4` cannot answer this: a disk's IOMedia entry does not carry the USB
    # device's properties — they are several levels up the IOService plane, past the
    # block-storage driver and the SCSI peripheral. Reaching them needs an upward recursive
    # search (IORegistryEntrySearchCFProperty with kIORegistryIterateParents), which is code,
    # not a shell pipeline. tools/usb-speed-probe performs exactly the search
    # HelperDeviceRegistry performs, so this verifies the real mechanism rather than an
    # approximation of it.
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    PROBE_SRC="$REPO_ROOT/tools/usb-speed-probe/main.swift"
    BUILD_DIR="/tmp/usbdrivetester-usb-speed"
    PROBE="$BUILD_DIR/usb-speed-probe"

    if [[ ! -f "$PROBE_SRC" ]]; then
        check fail "probe source not found at ${PROBE_SRC}"
    else
        export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"
        mkdir -p "$BUILD_DIR"
        xcrun swiftc -swift-version 5 -O "$PROBE_SRC" -o "$PROBE"

        set +e
        PROBE_OUTPUT="$("$PROBE" "$@" 2>&1)"
        PROBE_STATUS=$?
        set -e

        sed 's/^/    /' <<< "$PROBE_OUTPUT"

        if [[ "$PROBE_STATUS" -eq 0 ]]; then
            check pass "every named disk resolved to a recognised link speed (or is not USB)"
        else
            check fail "at least one disk could not be resolved to a recognised link speed"
        fi
    fi
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${FAILURES} failures."
else
    echo "  ${FAILURES} failure(s). If the mapping has shifted, Core/USBLinkSpeed.swift and its"
    echo "  tests must be updated together, and the macOS version that changed it recorded."
fi

exit "$FAILURES"
