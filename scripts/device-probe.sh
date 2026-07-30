#!/bin/bash
#
# device-probe.sh — run the app's real device discovery from the command line.
#
# Compiles the app target's Discovery sources together with tools/device-probe and
# prints what discovery returns for the drives currently attached. Lets most of the
# Step 5 Verification Gate be checked against real hardware without building,
# installing or looking at the GUI — see tools/device-probe/main.swift for why.
#
# This runs the SAME sources the app compiles, picked up by glob, so a file added in a
# later step is included automatically. It is not a reimplementation.
#
# Usage:
#   scripts/device-probe.sh              enumerate once
#   scripts/device-probe.sh --watch      keep printing as devices come and go
#   scripts/device-probe.sh --all        also show what was excluded, and why
#   scripts/device-probe.sh --watch --all
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/USBDriveTester/USBDriveTester"
BUILD_DIR="/tmp/usbdrivetester-device-probe"

mkdir -p "$BUILD_DIR"

# The Discovery folder plus Shared/TesterControl.swift, which carries the logging
# subsystem name. Deliberately NOT the whole app target: the views would drag in
# SwiftUI and the helper-registration types for no benefit here.
SOURCES=()
while IFS= read -r -d '' f; do
    SOURCES+=("$f")
done < <(find "$APP_DIR/Discovery" -name '*.swift' -print0)
SOURCES+=("$APP_DIR/Shared/TesterControl.swift")

if [[ ${#SOURCES[@]} -le 1 ]]; then
    echo "error: no discovery sources found under $APP_DIR/Discovery" >&2
    exit 1
fi

# -default-isolation MainActor mirrors the app target's SWIFT_DEFAULT_ACTOR_ISOLATION
# so the probe compiles these files under the same rules the real build uses. If this
# script compiles and the app does not, the flags have drifted.
xcrun swiftc \
    -swift-version 5 \
    -target arm64-apple-macos26.0 \
    -default-isolation MainActor \
    -O \
    -o "$BUILD_DIR/device-probe" \
    "${SOURCES[@]}" \
    "$REPO_ROOT/tools/device-probe/AllWholeMediaProbe.swift" \
    "$REPO_ROOT/tools/device-probe/main.swift"

exec "$BUILD_DIR/device-probe" "$@"
