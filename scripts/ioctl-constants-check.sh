#!/bin/bash
#
# ioctl-constants-check.sh — re-measures the disk ioctl request numbers against the SDK
# actually installed, and compares them with the literals Core asserts.
#
# WHY THIS EXISTS
#
# DKIOCGETBLOCKSIZE and friends are _IOR(...) macros, which the Swift importer refuses:
#
#     error: cannot find 'DKIOCGETBLOCKSIZE' in scope
#     note: macro 'DKIOCGETBLOCKSIZE' unavailable: structure not supported
#
# So Core/DiskIOControl.swift re-derives them, and DiskIOControlTests pins the derivation
# against four hex literals. That protects the CODE from drifting away from the literals.
# It cannot protect the LITERALS from drifting away from the SDK: a header change would
# leave the tests happily green while a root daemon sent a request number the driver no
# longer recognises.
#
# This script closes that side. It compiles <sys/disk.h> against whatever SDK is selected
# and prints what the macros expand to TODAY, then diffs against the recorded values.
#
# It is not part of the unit-test suite on purpose: a Swift test cannot see a C macro, which
# is the whole reason this problem exists.
#
# NON-DESTRUCTIVE. Touches no device, needs no root, needs no drive attached.
#
# Usage:
#   scripts/ioctl-constants-check.sh
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_FILE="$REPO_ROOT/USBDriveTester/com.arc3solutions.USBDriveTester.Helper/Core/DiskIOControl.swift"
TEST_FILE="$REPO_ROOT/USBDriveTester/USBDriveTesterTests/DiskIOControlTests.swift"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

FAILURES=0

check() {
    if [[ "$1" == "pass" ]]; then
        echo "  PASS  $2"
    else
        echo "  FAIL  $2"
        FAILURES=$((FAILURES + 1))
    fi
}

# The values recorded in Core and asserted by the tests. Kept here as the third copy on
# purpose: if any one of the three drifts, this script says which.
EXPECTED_BLOCK_SIZE="0x40046418"      # DKIOCGETBLOCKSIZE
EXPECTED_BLOCK_COUNT="0x40086419"     # DKIOCGETBLOCKCOUNT
EXPECTED_PHYSICAL="0x4004644d"        # DKIOCGETPHYSICALBLOCKSIZE
EXPECTED_MAX_READ="0x40086446"        # DKIOCGETMAXBYTECOUNTREAD
EXPECTED_MAX_WRITE="0x40086447"       # DKIOCGETMAXBYTECOUNTWRITE (added Step 8)

cat > "$WORK_DIR/probe.c" <<'EOF'
#include <stdio.h>
#include <sys/disk.h>
int main(void) {
    printf("DKIOCGETBLOCKSIZE=0x%lx\n",         (unsigned long)DKIOCGETBLOCKSIZE);
    printf("DKIOCGETBLOCKCOUNT=0x%lx\n",        (unsigned long)DKIOCGETBLOCKCOUNT);
    printf("DKIOCGETPHYSICALBLOCKSIZE=0x%lx\n", (unsigned long)DKIOCGETPHYSICALBLOCKSIZE);
    printf("DKIOCGETMAXBYTECOUNTREAD=0x%lx\n",  (unsigned long)DKIOCGETMAXBYTECOUNTREAD);
    printf("DKIOCGETMAXBYTECOUNTWRITE=0x%lx\n", (unsigned long)DKIOCGETMAXBYTECOUNTWRITE);
    return 0;
}
EOF

SDK_PATH="$(xcrun --show-sdk-path)"
SDK_VERSION="$(xcrun --show-sdk-version)"

echo
echo "  ioctl-constants-check — SDK ${SDK_VERSION}"
echo "  ${SDK_PATH}"
echo

xcrun clang "$WORK_DIR/probe.c" -o "$WORK_DIR/probe"
MEASURED="$("$WORK_DIR/probe")"

value_of() {
    local key="$1" line
    line="$(grep "^${key}=" <<< "$MEASURED" || true)"
    sed "s/^${key}=//" <<< "$line" | head -1
}

compare() {
    local macro="$1" expected="$2" actual
    actual="$(value_of "$macro")"
    if [[ -z "$actual" ]]; then
        check fail "${macro} — the SDK did not define it at all"
    elif [[ "$actual" == "$expected" ]]; then
        check pass "${macro} = ${actual}"
    else
        check fail "${macro} = ${actual}, but Core records ${expected}"
    fi
}

compare DKIOCGETBLOCKSIZE          "$EXPECTED_BLOCK_SIZE"
compare DKIOCGETBLOCKCOUNT         "$EXPECTED_BLOCK_COUNT"
compare DKIOCGETPHYSICALBLOCKSIZE  "$EXPECTED_PHYSICAL"
compare DKIOCGETMAXBYTECOUNTREAD   "$EXPECTED_MAX_READ"
compare DKIOCGETMAXBYTECOUNTWRITE  "$EXPECTED_MAX_WRITE"

# The literals must actually still be present in the Swift sources this claims to guard.
# Without this, deleting an assertion would make the guard silently vacuous — the failure
# mode negative-test.sh's inverted pipefail guard had for three steps.
#
# The files are confirmed to exist FIRST, and reported distinctly if they do not. Grepping a
# path that is not there returns no hits, which is indistinguishable from "the assertion was
# deleted" — a misdiagnosis that would send someone looking at the wrong file (NFR-USE-5).
echo
for required in "$CORE_FILE" "$TEST_FILE"; do
    if [[ ! -f "$required" ]]; then
        check fail "source not found at ${required} — this guard cannot inspect what it claims to guard"
    fi
done
if [[ "$FAILURES" -gt 0 ]]; then
    echo
    echo "  Refusing to report on assertions in files that were not found."
    exit "$FAILURES"
fi

for pair in "$EXPECTED_BLOCK_SIZE:0x4004_6418" \
            "$EXPECTED_BLOCK_COUNT:0x4008_6419" \
            "$EXPECTED_PHYSICAL:0x4004_644d" \
            "$EXPECTED_MAX_READ:0x4008_6446" \
            "$EXPECTED_MAX_WRITE:0x4008_6447"; do
    swift_literal="${pair##*:}"
    hits="$(grep -c -- "$swift_literal" "$TEST_FILE" || true)"
    if [[ "${hits:-0}" -ge 1 ]]; then
        check pass "the test suite still asserts ${swift_literal}"
    else
        check fail "no assertion of ${swift_literal} remains in DiskIOControlTests.swift"
    fi
done

# And Core must still be deriving rather than pasting — the derivation is what a reader can
# check against <sys/ioccom.h>.
if grep -q "0x4000_0000" "$CORE_FILE" && grep -q "IOCPARM_MASK" "$CORE_FILE"; then
    check pass "Core still derives the requests from IOC_OUT and IOCPARM_MASK"
else
    check fail "Core no longer shows the _IOR derivation; the numbers became unverifiable literals"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo "  ${FAILURES} failures — the recorded request numbers match this SDK."
else
    echo "  ${FAILURES} failure(s). A mismatch means a root daemon would send a request the"
    echo "  driver may not recognise. Update Core/DiskIOControl.swift AND DiskIOControlTests"
    echo "  together, and record the SDK version that changed them."
fi

exit "$FAILURES"
