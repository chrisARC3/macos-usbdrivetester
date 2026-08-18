#!/bin/bash
#
# install-app.sh — build the app and install it to /Applications.
#
# Why this exists
# ---------------
# SMAppService records the PATH of the app that registered a daemon. Registering from
# a DerivedData build directory works once, but that path is rebuilt and replaced
# constantly, which strands the registration pointing at a binary that no longer
# exists. The symptom is a status that will not move off .notFound or
# .requiresApproval no matter how often you re-register, and the only sanctioned
# cleanup for a wedged Background Task Management record is `sfltool resetbtm`, which
# resets it for EVERY app on the machine.
#
# Installing to a stable /Applications path avoids the whole problem: rebuild, re-run
# this script, and the registration keeps pointing at the same place.
#
# Usage: scripts/install-app.sh [Debug|Release]
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/USBDriveTester/USBDriveTester.xcodeproj"
SCHEME="USBDriveTester"
CONFIG="${1:-Debug}"
DEST="/Applications/USBDriveTester.app"

if pgrep -x "USBDriveTester" >/dev/null 2>&1; then
    echo "error: USBDriveTester is running. Quit it first, or the bundle will be" >&2
    echo "       replaced underneath a live process." >&2
    exit 1
fi

echo "Building scheme '$SCHEME' ($CONFIG)…"
"$REPO_ROOT/scripts/build.sh" "$CONFIG" >/dev/null

BPD="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')"
SRC="$BPD/USBDriveTester.app"

if [[ ! -d "$SRC" ]]; then
    echo "error: built app not found at $SRC" >&2
    exit 1
fi

echo "Installing to ${DEST}..."
# ditto preserves the code signature and extended attributes; a plain cp -R does not
# reliably preserve resource forks on all volumes.
rm -rf "$DEST"
ditto "$SRC" "$DEST"

echo
echo "--- Installed app signature ---"
codesign -dvvv "$DEST" 2>&1 | grep -E "Identifier|TeamIdentifier|Authority=Apple Dev|Signature|Runtime" || true
echo
echo "--- Embedded helper signature ---"
codesign -dvvv "$DEST/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper" 2>&1 \
    | grep -E "Identifier|TeamIdentifier|Authority=Apple Dev|Signature|Runtime" || true
echo
echo "--- Embedded LaunchDaemon plist ---"
ls -l "$DEST/Contents/Library/LaunchDaemons/" 2>/dev/null || echo "(missing!)"
echo
echo "Installed. Launch it from /Applications and use the Step 3 panel to register."

# THE RUNNING DAEMON IS NOT RELOADED BY COPYING FILES, and on 2026-08-18 that cost a full
# hardware gate run: metrics-check.sh was run twice against a daemon started before the fix it
# was meant to verify, and the version handshake could not catch it because the PROTOCOL had not
# changed — only the arithmetic behind one field had.
#
# So the check is on the binary's own timestamp, not on the version. If a daemon is running from
# an older binary than the one just installed, say so loudly and give the exact command.
HELPER_BIN="$DEST/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper"
HELPER_PID="$(pgrep -f 'USBDriveTester.Helper' | head -1 || true)"
if [[ -n "$HELPER_PID" && -f "$HELPER_BIN" ]]; then
    BIN_EPOCH="$(stat -f '%m' "$HELPER_BIN")"
    PID_START="$(ps -o lstart= -p "$HELPER_PID" 2>/dev/null || true)"
    PID_EPOCH="$(date -j -f '%a %b %e %T %Y' "$PID_START" '+%s' 2>/dev/null || echo 0)"
    if [[ "$PID_EPOCH" -gt 0 && "$PID_EPOCH" -lt "$BIN_EPOCH" ]]; then
        echo
        echo "  ⚠️  A helper daemon (pid ${HELPER_PID}) is still running the PREVIOUS binary."
        echo "      Copying files does not reload it. Until it restarts, the app and every gate"
        echo "      are talking to the old code — and if the protocol version did not change,"
        echo "      nothing will tell you."
        echo
        echo "      sudo /bin/launchctl kickstart -k system/com.arc3solutions.USBDriveTester.Helper"
        echo
        echo "      (or unregister and re-register in the app's Step 3 panel)"
    fi
fi
