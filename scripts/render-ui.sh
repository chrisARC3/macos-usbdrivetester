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
#   scripts/render-ui.sh [output.png] [width] [height] [view] [light|dark] [drives]
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
# `view` is one of the 40 cases below, grouped by family so the list can be counted against
#   `makeRootView` in tools/ui-probe/main.swift.
#
#   THIS LIST HAS DRIFTED FROM THE PROBE FOUR TIMES. This header said "twice" until 2026-08-27 and
#   "three times" until 2026-09-19 — a count that had itself gone stale, which is the failure it
#   exists to warn about.
#   (1) On 2026-08-11 it was missing `diagnostics-stop-on-error` and `metrics-finished`.
#   (2) By increment 6 it still named `diagnostics-held` and `diagnostics-quitting`, which the probe
#   had **stopped accepting** in increment 5, and it was missing all six `content-*` run-state cases
#   that replaced them — so it listed 24 where the probe had 28, and two of the 24 would have been
#   refused with exit 2. (3) On 2026-08-23 it still said 34 against the probe's 31, the Restart
#   removal having deleted three. CONSTRAINTS records all three; only two had reached this file.
#   (4) Step 12 chunk 5 (`4b72d13`, 2026-09-06) added the three `report-device-lost*` cases to the
#   probe and to neither this list nor the probe's own message. `2086090` (2026-09-09) added them
#   here and left "37" standing, above and in the `helperAvailability` note below, and the message
#   went on naming 37 of the 40. Found 2026-09-19 by the move to Xcode 27's chunk 4, which
#   rendered all 40.
#   Re-derive rather than hand-edit; the probe is authoritative:
#     grep -oE '^    case "[a-z0-9-]+":' tools/ui-probe/main.swift | sed 's/.*"\(.*\)":/\1/' | sort
#
#   (Increment 9's follow-up added `helper-gate-busy` on 2026-09-01 the same way: re-derived with
#   the one-liner, and the probe's own message extended in the same edit — the two lists are
#   hand-maintained and drift apart the moment one is edited alone.)
#
#   (Increment 8 re-derived it with that line rather than adding its case by hand, and found the
#   PROBE'S OWN "unknown view" message had drifted the same way — missing
#   `content-selection-below-fold` and `devices-unusable`. Both lists are hand-maintained and
#   neither is checkable by a compiler; this one at least has a one-liner that regenerates it.
#   Increment 9 added five cases and did the same: the list below is that one-liner's output, and
#   the probe's own message was extended in the same edit.)
#
#     content              content-starting     content-running            content-paused
#     content-finished     content-stop-on-error
#     content-no-selection content-quit-pending content-quitting
#     content-selection-below-fold
#     devices              devices-unmounted    devices-unusable           empty
#     diagnostics          diagnostics-run-active
#                          diagnostics-warnings-suppressed
#     helper-gate-not-found                     helper-gate-not-registered
#     helper-gate-requires-approval             helper-gate-unreachable
#     helper-gate-version-mismatch             helper-gate-busy
#     metrics              metrics-finished     metrics-idle
#     report               report-empty         report-failures
#                          report-qualified     report-stopped             report-stopped-by-user
#                          report-unidentified
#     report-device-lost   report-device-lost-paused                       report-device-lost-silent
#     warnings             warnings-ticked      warnings-confirm           warnings-unidentified
#
#   The `helper-gate-*` family is Step 11 increment 9's: the launch-time modal raised when the
#   privileged helper cannot be used. FIVE cases for one view, which is one per non-available state
#   rather than one for the family (approved 2026-08-27, departing from the increment's written
#   plan). They differ in message length, in BUTTON COUNT — `helper-gate-not-found` is the only
#   Quit-only state and so the only one-button footer — and in which remedy is emphasised. And
#   `helper-gate-unreachable` is the only surface in this app rendering a string whose length the
#   app does not choose: it is a transport error's `localizedDescription`.
#
#   FOUR OF THE FIVE CANNOT BE PRODUCED ON THIS MACHINE without deliberately breaking the install,
#   which is the same reason `empty`, `devices-unmounted` and `devices-unusable` exist.
#
#   THE GATE APPEARS IN NO OTHER RENDER, and that is by placement rather than by luck. The modifier
#   that presents it is on `ContentView`, so every `content-*` render compiles it — but the trigger
#   that would ever set the state is at `ContentView`'s call site in `USBDriveTesterApp.swift`,
#   which this script excludes by name (see SOURCES below). Nothing in a render writes
#   `helperAvailability`, so the sheet's `isPresented` binding is false in all 40 cases. Moving the
#   trigger into `ContentView` would put this machine's live `SMAppService` status into every
#   render — the ambient-state leak the appearance note above exists for.
#
#   The `content-*` family is Step 11's. Increment 5 added the run states; increment 6 added
#   `content-finished` (FR-CTRL-8's "or stopped" window, which no render reached on its own) and
#   `content-stop-on-error`, which replaces `diagnostics-stop-on-error` — the failure-mode picker
#   moved to the main window and the panel that render pointed at no longer has one.
#
#   `content-paused` earns its place as the state whose rules were got wrong once and reversed on
#   sight. This note used to say it was "the only state where the two pre-run controls disagree —
#   the I/O-size dropdown live, the failure-mode picker not". **That shape was reversed on
#   2026-08-19**: both controls are dead for the whole of a run, `paused` included, under one rule
#   and one sentence. What this render is now for is that the sentence is there and reads as a
#   rule rather than as a control being broken.
#
#   The `report-*` family gained `report-stopped-by-user` in increment 8, when FR-CTRL-4's stop
#   control finally gave FR-RPT-4's fourth outcome a trigger. It renders a stopped run that had
#   **already logged a bad block**, because that is the one page where "the headline does not
#   mention failures" and "there were none" are different statements.
#
#   THREE OF THESE RENDER A STATE THIS MACHINE CANNOT PRODUCE, and each exists because a state
#   nobody can observe is a state nobody has checked:
#     * `empty`            — no drives attached (one of them holds the source tree)
#     * `devices-unmounted`— a drive with no mounted volumes
#     * `devices-unusable` — added 2026-08-11 by Step 14's accessibility audit. `isSelectable` is
#       false only when `geometryProblem != nil`, so the unusable row's icon, dimming and
#       "Unusable" badge had never been rendered at all. Lists a usable drive first (FR-DEV-3
#       selects it, as on a real machine) then one drive per geometry problem.
# The `warnings*` views are Step 14's pre-run dialog. It ships as a SwiftUI **sheet**, which
#   gets its own window and can therefore never be captured *in place* — so it is written as a
#   standalone view precisely so these renders can exist. They check its layout; a person still
#   has to confirm the sheet presents at all.
# WHAT A RENDER CANNOT ANSWER, and what to use instead (Step 11 increment 7). A render shows a view
#   at a size you chose. It cannot say what sizes the WINDOW is willing to be — which is the
#   question behind whether this app fits a 13.3-inch Mac, and which is answered by
#   `ui-probe --limits <view> <width> <drives>` and, with a screen budget beside it, by
#   `scripts/window-fit-check.sh`. Reach for that gate rather than eyeballing a render at a small
#   height: a render at 500 pt looks fine right up until you learn the window refuses to be 500 pt.
#
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
#   BUT THE HEIGHT ARGUMENT IS A FLOOR, NOT A CEILING (measured 2026-08-11, correcting the
#   paragraph above, which had claimed it was simply "the lever"). The capture is of the hosting
#   view's own bounds, and `NSHostingView` sizes itself to its content — so a view with no
#   intrinsic height cap ignores the number entirely and renders as tall as it wants. Asking the
#   `metrics*` family for 460 pt returned **2,876 pt**, with the content in a narrow band and
#   emptiness above and below. The `report*`, `warnings*`, `devices*` and `diagnostics*` families
#   do honour it.
#
#   THE `report*` FAMILY HONOURS IT FOR A DIFFERENT REASON SINCE INCREMENT 8. It used to be the
#   view's own `.frame(minWidth: 620, minHeight: 560)` — which is also why `report-empty` once
#   asked for 400 and got 560 — and that floor went when the report became a sheet sized by its
#   presenter. **Deleting it made `report` at 700x1100 render 700x5167**, the whole document, in
#   every case in the family: measured both ways on 2026-08-21. `RunReportHost` now applies an
#   exact frame of the requested size, which is exactly what `ContentView` hands the sheet, so
#   these renders show what a user sees and any height is honoured — 461 pt included.
#   When a family ignores the height, centre-crop with `sips -c <h> <w>` (see below) rather than
#   re-rendering at a smaller number that will be ignored again.
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
# NFR-USE-8's DYNAMIC TYPE HALF IS NOT CHECKABLE HERE. MEASURED 2026-08-11, NOT ASSUMED.
#   A sixth `dynamicTypeSize` argument was built for exactly this, and then removed. Rendering
#   `warnings` at `large` and at `accessibility5` produced BYTE-IDENTICAL PNGs — same MD5.
#
#   That result was discriminated before it was believed, because an identical render has at least
#   three causes and only one of them is "macOS ignores it":
#     * Passing a bogus size made the probe REFUSE with exit 2 → the argument reaches the parse.
#     * A temporary `.opacity()` keyed on the parsed value made the two renders DIVERGE, and the
#       `large` render stayed byte-identical to the pre-mutation one → the modifier reaches the
#       hierarchy, the two runs genuinely hold different values, and the harness is stable.
#   So macOS 26 does not resolve SwiftUI system fonts through `DynamicTypeSize` inside an
#   `NSHostingView`. The modifier compiles, applies, and changes nothing.
#
#   THE AXIS WAS REMOVED RATHER THAN KEPT. A lever that looks live and does nothing would let
#   somebody render at `accessibility5`, see no clipping, and conclude the layout is safe under
#   large text — the same wrong conclusion, from the same instrument, as the 2026-08-10 appearance
#   bug. Do not rebuild it without re-measuring first.
#
#   What IS established without a keyboard: every string in the app uses a SEMANTIC text style, so
#   there is no hard-coded text size to fail to scale. Re-derive with
#     grep -rn --include='*.swift' 'system(size:' USBDriveTester/USBDriveTester
#   which on 2026-08-11 returned two hits, both DECORATIVE SF Symbols (the empty-state drive glyph
#   and the report's header icon), and no text.
#
#   macOS's actual user-facing control is System Settings > Accessibility > Display > Text size,
#   which is system-wide. Confirming the app responds to it needs a person, and always will.
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

# How many drives the fixture presents, for the `content-*` family (Step 11 increment 7).
#
# THIS AXIS FOUND A DEFECT THE MOMENT IT EXISTED. Until it was added, every render this project
# had ever taken showed exactly ONE drive — so `DeviceListView`'s list, which grows to a 260 pt cap
# with the number attached, had never been looked at anywhere near that cap. The first six-drive
# render showed two rows of six beside a live-metrics panel spending 265 pt on one sentence: the
# panel and the device detail are both `ScrollView`s, both were greedy, and spare height was
# splitting evenly between them. Fixed by making the metrics ceiling conditional on there being
# measurements to show.
#
# 6 is where the cap saturates, so it is the number worth rendering alongside 1.
DRIVES="${6:-1}"

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

"$BUILD_DIR/ui-probe" "$OUT" "$WIDTH" "$HEIGHT" "$VIEW" "$APPEARANCE" "$DRIVES"
