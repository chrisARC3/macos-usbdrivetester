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
#   scripts/render-ui.sh [output.png] [width] [height] [view] [light|dark]
#
# APPEARANCE IS PINNED TO `light` BY DEFAULT, AND THAT IS A BUG FIX (2026-08-10).
#   Renders used to inherit whatever the machine was set to. When this Mac switched to dark
#   appearance mid-session, `content` and `devices` rendered as a device list and NOTHING ELSE —
#   no header, no selected-device pane, no metrics panel. The elements were laid out and drawing;
#   they were invisible against the ground. It reproduced at a clean HEAD, on the commit that had
#   rendered correctly that morning, so it was the probe and not the app.
#   A layout instrument that silently reports fewer elements than exist, depending on the time of
#   day, is worse than no instrument: it produced a wrong conclusion before it was caught. Pass
#   `dark` to inspect dark appearance ON PURPOSE — useful for NFR-USE-8's contrast question.
#   The probe prints `appearance=` in its diagnostic line so every render carries its provenance.
#
#   Dark renders were broken until 2026-08-10 and the cause was NOT the appearance. `cacheDisplay`
#   captures the CONTENT VIEW's drawing and never the window's background, so every region where
#   SwiftUI draws no background of its own landed in the PNG TRANSPARENT. Light mode hid it: black
#   text over transparency composites readably in any viewer. Dark mode did not: white text over
#   transparency vanished, leaving only the List, which draws its own opaque background. The probe
#   now gives the captured view an opaque window-background layer, resolved inside the pinned
#   appearance. Both appearances are verified against the shipped app.
#
# `view` is one of: content (default, the whole window), content-quitting, devices,
#   diagnostics, diagnostics-held, diagnostics-quitting, empty, metrics, metrics-idle,
#   report, report-empty, report-failures, report-qualified, report-stopped,
#   report-unidentified, devices-unmounted, diagnostics-warnings-suppressed, warnings,
#   warnings-ticked, warnings-confirm,
#   warnings-unidentified.
# The `warnings*` views are Step 14's pre-run dialog. It ships as a SwiftUI **sheet**, which
#   gets its own window and can therefore never be captured *in place* — so it is written as a
#   standalone view precisely so these renders can exist. They check its layout; a person still
#   has to confirm the sheet presents at all.
# `empty` renders the device list with NO drives connected — the FR-SAFE-5 no-selection
# state, which cannot otherwise be reached on a machine that has drives attached.
# Rendering a sub-view matters once one is behind a disclosure — the composition root
# cannot show it, and compiling is not evidence that it lays out.
#
# RENDER ONLY AS TALL AS YOU NEED (2026-08-11). A render is read by a person or by an agent and
#   both pay for the whole image. Rendering 1800 pt to inspect a 200 pt section — which happened
#   repeatedly during Step 14 — is waste with no upside. The height argument is the lever: find the
#   section once with a tall render, then iterate at the smallest height that still contains it.
#
#   Renders are 1x, so pixel coordinates equal point coordinates.
#
#   ON CROPPING WITH `sips`, MEASURED 2026-08-11 rather than assumed, because the first version of
#   this note shipped a recipe that did not work:
#     * `sips -c <height> <width>` CENTRE-crops and is reliable. Use it when the region is central.
#     * `--cropOffset <y> <x>` IS NOT RELIABLE. It was observed ignored when the crop fits inside
#       the source, and in one invocation it returned the SOURCE IMAGE UNCHANGED at full size.
#       **Neither failure reports an error** — you get a plausible-looking PNG of the wrong thing,
#       which is the one output an instrument must never produce. Do not build a check on it.
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
APPEARANCE="${5:-light}"

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

"$BUILD_DIR/ui-probe" "$OUT" "$WIDTH" "$HEIGHT" "$VIEW" "$APPEARANCE"
