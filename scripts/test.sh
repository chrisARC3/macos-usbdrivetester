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
# PARALLELISM IS OFF (added Step 8, 2026-08-02). Swift Testing runs tests concurrently
# *within one process* by default. Several assertions in this suite read process-global
# counters — `ChunkBuffers.liveAllocatedBytes` and `peakAllocatedBytes`, which BUILD-PLAN
# 7.6's gate asks to be instrumented and confirmed — and no assertion on a global counter
# can be sound while another test may be mutating it. Step 7 saw this coming and wrote the
# warning into `ChunkBuffersInstrumentationTests`: "Nothing else in the suite allocates
# ChunkBuffers today; if a future test does, it must either live here or the assertions
# below must be loosened." Step 8's cycle tests allocate buffers in forty-odd tests, so the
# condition arrived.
#
# Measured 2026-08-02: 9.7 s parallel, 18.8 s serialised. Nine seconds is a small price for
# removing a class of results that depend on scheduling — and a green that depends on
# scheduling is not evidence. Verified to take effect rather than assumed: the suite runs in
# a single process either way, and disabling this doubles the wall clock.
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
    -parallel-testing-enabled NO \
    test
