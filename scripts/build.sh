#!/bin/bash
#
# build.sh — build the app (and embedded helper) using the *installed* Xcode.
#
# The active developer dir on this machine is Command Line Tools, so we point
# xcodebuild at the full Xcode via DEVELOPER_DIR (no `sudo xcode-select` needed).
# Override by exporting DEVELOPER_DIR yourself.
#
# Usage: scripts/build.sh [Debug|Release]
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/USBDriveTester/USBDriveTester.xcodeproj"
SCHEME="USBDriveTester"
CONFIG="${1:-Debug}"

echo "Using Xcode at: $DEVELOPER_DIR"
echo "Building scheme '$SCHEME' ($CONFIG)…"

# -allowProvisioningUpdates: from Step 3 the app is signed as Apple Development
# rather than adhoc, and automatic signing needs permission to create/refresh the
# signing assets when invoked from the command line rather than from Xcode.
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS,arch=arm64' \
    -allowProvisioningUpdates \
    build

BPD="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')"
echo
echo "Built products dir: $BPD"
echo "App bundle:         $BPD/USBDriveTester.app"
