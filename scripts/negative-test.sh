#!/bin/bash
#
# negative-test.sh — Step 3 security gate (FR-ARCH-5, NFR-SEC-2).
#
# Builds an ADHOC-SIGNED XPC client and proves the privileged helper refuses to serve
# it, then shows the helper's own log entries for the attempt.
#
# The client is built with swiftc rather than as an Xcode target on purpose: an Xcode
# target under automatic signing would carry our Team ID, satisfy the helper's
# requirement, and prove nothing. See tools/negative-client/main.swift.
#
# PREREQUISITE: the helper must be registered and enabled via SMAppService — run the
# app, choose "Register helper", and approve it in System Settings first. This script
# tests a live daemon; it cannot install one.
#
# Exit status: 0 = gate passed (client rejected), 1 = gate FAILED (client served),
#              2 = could not run the test.
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.arc3solutions.USBDriveTester.Helper"
SUBSYSTEM="com.arc3solutions.USBDriveTester"
# Built OUTSIDE the repo, in a world-readable location, and deliberately so.
#
# This repo lives on an external volume. macOS gates daemon access to removable
# volumes, so the root helper cannot read a binary built here — which does not affect
# the security decision (that is made from the peer's audit token, not the file), but
# it does blank out the advisory signing details in the rejection log, turning
# "team none — unsigned or adhoc" into "signing information unavailable". Building to
# /tmp keeps the log evidence legible.
BUILD_DIR="/tmp/usbdrivetester-negative-client"
CLIENT="$BUILD_DIR/negative-client"

SHARED="$REPO_ROOT/USBDriveTester/USBDriveTester/Shared/TesterControl.swift"
CLIENT_SRC="$REPO_ROOT/tools/negative-client/main.swift"

echo "=============================================================="
echo " Step 3 security gate — foreign-client rejection"
echo "=============================================================="
echo

# --- 1. Is the daemon actually there? ---------------------------------------
echo "--- Checking the helper is registered ---"
# No sudo needed: reading a system-domain service's state is unprivileged.
if ! launchctl print "system/$LABEL" >/dev/null 2>&1; then
    echo "error: LaunchDaemon '$LABEL' is not loaded in the system domain." >&2
    echo "       Run the app, choose 'Register helper', and approve it in" >&2
    echo "       System Settings > General > Login Items & Extensions first." >&2
    exit 2
fi
echo "ok: $LABEL is loaded in the system domain."

# Confirm SMAppService owns it, not a manual `launchctl bootstrap`. The Step 3 gate
# requires the round-trip to go through the *registered* daemon, so a hand-loaded
# service would invalidate the whole result.
if launchctl print "system/$LABEL" 2>/dev/null | grep -q "managed_by = com.apple.xpc.ServiceManagement"; then
    echo "ok: managed by ServiceManagement (SMAppService), not a manual bootstrap."
else
    echo "warning: the service is loaded but NOT managed by ServiceManagement." >&2
    echo "         Step 3 requires an SMAppService-registered daemon." >&2
fi
echo

# --- 2. Build the foreign client --------------------------------------------
echo "--- Building the adhoc-signed client ---"
mkdir -p "$BUILD_DIR"
xcrun swiftc \
    -swift-version 5 \
    -target arm64-apple-macos26.0 \
    -O \
    -o "$CLIENT" \
    "$SHARED" "$CLIENT_SRC"

# Force an adhoc signature. swiftc already produces one on Apple silicon; doing it
# explicitly makes the test's premise deliberate rather than incidental.
codesign --force --sign - "$CLIENT"
echo "ok: built $CLIENT"
echo

# --- 3. Prove the client is NOT ours ----------------------------------------
echo "--- Client signature (must NOT carry team 5JC55GTLZA) ---"
codesign -dvvv "$CLIENT" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true
echo

# Captured first, then matched against a here-string — NOT `codesign … | grep -q`.
#
# Under `set -o pipefail` that pipeline is non-zero exactly when grep MATCHES: grep -q
# exits on the first hit, codesign dies of SIGPIPE writing the rest of its output, and
# pipefail promotes that. So this guard — "refuse to run a security test that cannot
# fail" — could never fire, which is the one condition it exists to catch. Found
# 2026-08-01 when the identical pattern aborted claim-contention-test.sh.
CLIENT_SIGNATURE="$(codesign -dvvv "$CLIENT" 2>&1 || true)"
if grep -q "TeamIdentifier=5JC55GTLZA" <<<"$CLIENT_SIGNATURE"; then
    echo "error: the client is signed with our own Team ID — this test would be vacuous." >&2
    exit 2
fi
echo "ok: client carries no Team ID; it is a foreign caller."
echo

# --- 4. Run it ---------------------------------------------------------------
# Timestamp for the log query. `log show --start` wants local time in this format.
LOG_START="$(date '+%Y-%m-%d %H:%M:%S')"
sleep 1

echo "--- Running the client against the live helper ---"
CLIENT_OUT="$BUILD_DIR/last-run.txt"
set +e
"$CLIENT" | tee "$CLIENT_OUT"
RESULT=${PIPESTATUS[0]}
set -e
echo

CLIENT_PID="$(awk '/^negative-client: pid /{print $3; exit}' "$CLIENT_OUT")"

# --- 5. Show what the helper logged (NFR-OBS-1) ------------------------------
# --info is required: Logger.info entries sit below the default `log show` level.
echo "--- Helper log for this attempt ---"
LOG_OUT="$BUILD_DIR/last-run.log"
log show \
    --predicate "subsystem == \"$SUBSYSTEM\"" \
    --start "$LOG_START" \
    --info --debug \
    --style compact >"$LOG_OUT" 2>/dev/null || true
grep -Ev "^(Filtering|Timestamp|$)" "$LOG_OUT" || true
echo

# --- 6. Did the helper actually SEE us? --------------------------------------
#
# This is what separates a genuine rejection from an absence. "The client got no
# reply" is also what happens when no daemon is installed at all, so a bare
# non-response is not evidence of enforcement. Requiring the helper's own log to
# name this client's pid means the daemon demonstrably received the connection and
# then declined to serve it.
SAW_US=0
if [[ -n "${CLIENT_PID:-}" ]] && grep -q "pid $CLIENT_PID" "$LOG_OUT"; then
    SAW_US=1
fi

# --- 7. Verdict --------------------------------------------------------------
echo "=============================================================="
if [[ $RESULT -eq 1 ]]; then
    echo " GATE FAILED — the helper SERVED the foreign client."
    VERDICT=1
elif [[ $RESULT -ne 0 ]]; then
    echo " INCONCLUSIVE — the client could not run (exit $RESULT)."
    VERDICT=2
elif [[ $SAW_US -eq 0 ]]; then
    echo " INCONCLUSIVE — the client was not served, but the helper logged no"
    echo " connection from pid ${CLIENT_PID:-?}, so we cannot tell a rejection from"
    echo " an absent daemon. Confirm the helper is enabled and re-run."
    VERDICT=2
else
    echo " GATE PASSED — the helper received the connection from pid $CLIENT_PID"
    echo " and refused to serve it (FR-ARCH-5, NFR-SEC-2)."
    VERDICT=0
fi
echo "=============================================================="
exit $VERDICT
