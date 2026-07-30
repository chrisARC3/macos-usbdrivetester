#!/bin/bash
#
# render-ui.sh — capture the app's SwiftUI layout to a PNG, headlessly.
#
# Compiles the app target's view sources together with tools/ui-probe and renders
# ContentView into an offscreen window. Lets GUI layout be inspected without an
# interactive session — see tools/ui-probe/main.swift for the rationale.
#
# This is a LAYOUT probe, not a functional test: the rendered view cannot reach a real
# daemon, so registration will read .notFound. To exercise behaviour, build and run the
# real app (scripts/install-app.sh).
#
# Usage:
#   scripts/render-ui.sh [output.png] [width] [height] [view]
#
# `view` is one of: content (default, the whole window), devices, diagnostics.
# Rendering a sub-view matters once one is behind a disclosure — the composition root
# cannot show it, and compiling is not evidence that it lays out.
#
# Defaults to /tmp so renders never land in the repo.
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/USBDriveTester/USBDriveTester"
BUILD_DIR="/tmp/usbdrivetester-ui-probe"

OUT="${1:-$BUILD_DIR/ui.png}"
WIDTH="${2:-600}"
HEIGHT="${3:-1000}"
VIEW="${4:-content}"

mkdir -p "$BUILD_DIR" "$(dirname "$OUT")"

# Every app-target Swift file except USBDriveTesterApp.swift, whose @main would clash
# with the probe's own top-level entry point. Collected by glob rather than listed, so
# files added in later steps are picked up automatically.
SOURCES=()
while IFS= read -r -d '' f; do
    [[ "$(basename "$f")" == "USBDriveTesterApp.swift" ]] && continue
    SOURCES+=("$f")
done < <(find "$APP_DIR" -name '*.swift' -print0)

if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "error: no app sources found under $APP_DIR" >&2
    exit 1
fi

echo "Compiling ${#SOURCES[@]} app source(s) + ui-probe…"
# -default-isolation MainActor mirrors the app target's SWIFT_DEFAULT_ACTOR_ISOLATION,
# so the probe compiles the views under the same rules the real build uses.
xcrun swiftc \
    -swift-version 5 \
    -target arm64-apple-macos26.0 \
    -default-isolation MainActor \
    -o "$BUILD_DIR/ui-probe" \
    "${SOURCES[@]}" \
    "$REPO_ROOT/tools/ui-probe/main.swift"

"$BUILD_DIR/ui-probe" "$OUT" "$WIDTH" "$HEIGHT" "$VIEW"
