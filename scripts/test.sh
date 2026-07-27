#!/bin/bash
#
# test.sh — run the Swift Testing unit suite (core algorithm) for the project.
#
# Like build.sh, this points xcodebuild at the full Xcode via DEVELOPER_DIR (the
# active developer dir on this machine is Command Line Tools).
#
# Scoped with -only-testing to the USBDriveTesterTests (Swift Testing) target: the
# hardware-independent core tests that this project is built around (NFR-MAINT-2).
# The template USBDriveTesterUITests target is intentionally excluded — it is unused
# and only slows the TDD loop. To run everything, drop the -only-testing line.
#
# Usage: scripts/test.sh [Debug|Release]
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/USBDriveTester/USBDriveTester.xcodeproj"
SCHEME="USBDriveTester"
CONFIG="${1:-Debug}"

echo "Using Xcode at: $DEVELOPER_DIR"
echo "Testing scheme '$SCHEME' ($CONFIG), target USBDriveTesterTests…"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS,arch=arm64' \
    -allowProvisioningUpdates \
    -only-testing:USBDriveTesterTests \
    test
