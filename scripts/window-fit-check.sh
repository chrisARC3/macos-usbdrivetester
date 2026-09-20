#!/bin/bash
#
# window-fit-check.sh — does the main window still fit the smallest Mac we support?
#
# Step 11, increment 7. **The check behind NFR-USE-9.** This is the gate that stops `ContentView`'s
# minimum height becoming a
# number nobody rechecks. It does NOT read a constant out of the source — it asks the real view
# hierarchy, through `ui-probe --limits`, for the size limits it hands a window, and compares them
# against a screen budget declared below.
#
# ## Why a gate rather than a comment
#
# The height this replaces was a literal in `ContentView` that **expired three times**, silently
# each time: 700 was true when written and false once Step 10 added the mounted-volumes row; true
# again in increment 5; false the moment increment 6 put two picker rows above Start; and 760 was
# already false for the `starting` state when it was finally deleted. Nothing recomputes a literal,
# and nothing was watching. A row added three steps from now moves the real minimum, and this
# script is what says so.
#
# ## Points, not pixels — the correction this whole increment turned on
#
# macOS lays windows out in POINTS. A 13.3-inch Apple Silicon Mac has a 2560x1600 **pixel** panel
# but is **1440x900 points** at its default scaling, so the vertical budget is 900 and not 1600.
# Reasoning from the pixel number makes every figure here look comfortable by a factor of 1.8.
#
# Measured on the development Mac rather than recalled (2026-08-19):
#
#   * title bar               32 pt   `NSWindow.frameRect(forContentRect:)`
#   * menu bar                30 pt   `NSScreen.frame.height - visibleFrame.height`, Dock at side
#   * Dock, bottom, default  ~70 pt   the one estimated number here; a larger Dock takes more
#
# So the budget below is `points - menu bar - Dock`, and a window fits when
# `contentMinHeight + 32 <= budget`.
#
# ## Usage
#
#   scripts/window-fit-check.sh            # every state, at 1 and 6 attached drives
#   scripts/window-fit-check.sh --verbose  # also print the intrinsic and maximum sizes
#
# Exit 0 when every state fits the committed budget, or misses it by no more than the amount
# recorded in scripts/.window-fit-exceptions. Exit 1 when a state is too tall. **Exit 2 when the
# probe could not measure**, which is not a pass and not a failure.
#
# ## Why exit 2 exists (2026-09-19)
#
# On macOS 27 both halves of `ui-probe`'s measurement broke at once and `--limits` returned an
# overflow height of 1 pt for every state. `min=` is the larger of the declared and measured
# numbers, so this script silently fell back to the DECLARED minimum — 46 pt short of what the
# content needs with one drive, 57 pt short with six — and printed "every state fits" with a worst
# case of 556 pt where the last conclusive run had said 613. It had been reporting the wrong number
# for nineteen days, and nothing in its output said so.
#
# The probe now refuses to print a number it cannot stand behind: `min=<w>xunmeasured` plus
# `measurement=UNMEASURABLE(<why>)`. This script reports that as INCONCLUSIVE, per state and in the
# summary, and exits 2. **A gate that has not measured cannot report anything** — `CONSTRAINTS.md`
# §2 — and "it printed a number" is not the same as "it measured one".
#
# ## The width matters, and 640 is not arbitrary
#
# Required height depends on how the explanatory sentences wrap, and that depends on width. The
# `starting` state needs 675 pt at 640 wide, 645 at 700 and 631 at 900, because three
# disabled-reason sentences each gain a line as the window narrows. 640 is
# `WindowMetrics.minimumContentWidth` — the narrowest the window goes, and therefore the worst
# case. Measuring at any other width would flatter the result.
#
# **Until 2026-08-20 this paragraph was aspirational**: the number came from `contentMinSize`,
# which reported the same height at 640, 700 and 900. The width argument was inert and the figures
# quoted here (629, and "92 pt less at 700") were never produced by this script.
#
# ## What "the minimum" means here, after the 58 pt correction (2026-08-20)
#
# `--limits` reports **the larger of two numbers**, because each can be too small and neither can
# be too large:
#
#   * what SwiftUI **declares** (`window.contentMinSize`), which is built from the
#     `.frame(minHeight:)` each pane asks for; and
#   * the smallest height at which the laid-out content **stops overflowing** the space it is
#     given, found by driving the window down and measuring.
#
# The declared number was short by **58 pt** for every `content-*` state. `WindowMetrics`
# `deviceListFloor` asks the drive list for 46 pt — one row — and **the AppKit table backing that
# pane will not lay out below about 104 whatever it is told**. SwiftUI believed the 46, so the
# declared total described a height the content could not occupy; a render at it clips.
#
# Found by resizing the shipped window with accessibility scripting: the real app clamps at
# **575 pt** (543 of content plus a 32 pt title bar, both measured), where this script had been
# reporting 517. Confirmed by raising `deviceListFloor` to 104, which moves the declared number to
# 543 exactly. The gate now reports 542 for the same state — one point under the shipped clamp,
# which is AppKit rounding and is recorded rather than papered over.
#
# The overflow measurement alone is not enough either, and in the opposite direction: a view whose
# whole body is a scroll region never overflows, so `report` bottoms out at 24 pt against a
# declared 560. Hence the max.
#
# ## Drive count is an axis because it moved the answer by 168 pt
#
# `DeviceListView.listHeight` grew with the number of attached drives to a 260 pt cap, so the
# window's minimum used to depend on how many drives were plugged in. Increment 7 made the list a
# range rather than a fixed height, which is what removed that dependency — and 1 vs 6 drives is
# checked here so it stays removed. 6 is where the cap saturates.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/USBDriveTester/USBDriveTester"
BUILD_DIR="/tmp/usbdrivetester-window-fit"

# Like build.sh: point at the full Xcode without needing `sudo xcode-select`. The Previews macro
# plugin lives in Xcode and not in the Command Line Tools, so a machine whose xcode-select points
# at CommandLineTools cannot compile the app sources at all — it fails on `#Preview`.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# The budget. Change these only with a measurement, and say what it was.
# ---------------------------------------------------------------------------

TITLE_BAR=32

# name|points tall|budget after menu bar and a default bottom Dock
SCALINGS=(
    "13.3\" @ 1440x900 (default)|900|800"
    "13.3\" @ 1280x800|800|700"
    "13.3\" @ 1152x720|720|620"
)

# What the project commits to covering: **1280x800 with the Dock showing** (user decision,
# 2026-08-20), which is a 700 pt window.
#
# ## Why this moved, and why it is not backsliding
#
# It was 620 — the tightest scaling a 13.3-inch offers — from 2026-08-19 until the day after. That
# decision was taken on numbers this script was producing **incorrectly**: the declared minimum it
# read was 58 pt short in every state, so 620 looked met everywhere except `starting`. It never
# was. Corrected, `running` and `paused` miss 620 by 4 pt with six drives attached, and the honest
# figure for `starting` was 718 rather than the 661 recorded against it.
#
# 700 is where the decision started on 2026-08-19, before the broken numbers made a tighter target
# look free. Against it every state fits with at least 62 pt to spare, `.window-fit-exceptions` is
# empty, and NFR-USE-9 is a requirement the app meets rather than one carrying a standing
# allowance. A 1152x720 user gets a window that mostly fits and grows past the Dock during a run.
COMMITTED_BUDGET=700

EXCEPTIONS="$REPO_ROOT/scripts/.window-fit-exceptions"

VIEWS=(content content-starting content-running content-paused
       content-finished content-stop-on-error content-no-selection)
DRIVE_COUNTS=(1 6)
WIDTH=640

# ---------------------------------------------------------------------------

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
xcrun swiftc \
    -swift-version 5 \
    -target arm64-apple-macos26.0 \
    -default-isolation MainActor \
    -o "$BUILD_DIR/ui-probe" \
    "${SOURCES[@]}" \
    "$REPO_ROOT/tools/ui-probe/main.swift"

echo
echo "Screen budget (points, after menu bar and a default bottom Dock):"
for scaling in "${SCALINGS[@]}"; do
    IFS='|' read -r name points budget <<< "$scaling"
    printf "  %-28s %4s pt tall -> %3s pt for a window\n" "$name" "$points" "$budget"
done
echo "  Committed budget: ${COMMITTED_BUDGET} pt (window, including the ${TITLE_BAR} pt title bar)"
echo
printf "  %-24s %7s %8s %8s   %s\n" "state" "drives" "content" "window" "verdict"

FAILED=0
INCONCLUSIVE=0
WORST=0
WORST_STATE=""

for view in "${VIEWS[@]}"; do
    for drives in "${DRIVE_COUNTS[@]}"; do
        # `|| true` so a non-zero exit reaches the guard below. Without it `set -e` aborts on the
        # assignment and the diagnostic never prints — the script would die silently on an
        # unknown view name, which is the one case where saying which view is the whole value.
        line="$("$BUILD_DIR/ui-probe" --limits "$view" "$WIDTH" "$drives" 2>/dev/null || true)"
        if [[ -z "$line" ]]; then
            echo "error: ui-probe produced no output for view=$view drives=$drives" >&2
            exit 1
        fi

        # The probe says so itself when its measurement is invalid, and says why. Checked BEFORE
        # the height is parsed: an unmeasurable line carries `min=<w>xunmeasured`, and a parse that
        # cannot fail would otherwise be the thing standing between a broken instrument and a
        # verdict.
        if [[ "$line" == *"measurement=UNMEASURABLE"* ]]; then
            why="$(sed -E 's/.*measurement=UNMEASURABLE\((.*)\)$/\1/' <<< "$line")"
            printf "  %-24s %7s %8s %8s   %s\n" "$view" "$drives" "—" "—" "INCONCLUSIVE — ${why}"
            [[ $VERBOSE -eq 1 ]] && echo "      $line"
            INCONCLUSIVE=1
            continue
        fi

        # ## The second check, and the one that would have caught the OTHER half (2026-09-19)
        #
        # Two things broke in the probe that day. The clamp says so itself, above. The other — it
        # measured the wrong subview, and came back with that subview's own 24 pt height — produces
        # a perfectly well-formed line whose measured number is simply too small, and `min=` then
        # takes the declared one and reads as a pass.
        #
        # For the states in VIEWS there is an invariant to lean on: every one of them carries fixed
        # chrome above and below a scrollable drive list — a header, the selected-device pane, the
        # controls — and that chrome cannot compress. So the height at which the content stops
        # overflowing is at or above what SwiftUI declares: measured on macOS 27 at 570 with one
        # drive and 581 with six, both against a declared 524, and at 581 against 524 on macOS 26.
        # **A measurement BELOW the declaration here
        # means the measurement stopped working**, not that the window got smaller.
        #
        # This is not true of every view `--limits` accepts: `report` and `devices` are a scroll
        # region end to end and legitimately bottom out far below their declared minimum — 24 pt
        # against 560 for `report`. Which is why this check lives in the gate, next to the list of
        # states it holds for, and not in the probe.
        declared_h="$(sed -E 's/.* declared=[0-9]+x([0-9]+) .*/\1/' <<< "$line")"
        overflow_h="$(sed -E 's/.* overflowAt=([0-9]+) .*/\1/' <<< "$line")"
        if [[ "$declared_h" =~ ^[0-9]+$ ]] && [[ "$overflow_h" =~ ^[0-9]+$ ]] \
           && (( overflow_h < declared_h )); then
            printf "  %-24s %7s %8s %8s   %s\n" "$view" "$drives" "—" "—" \
                "INCONCLUSIVE — measured ${overflow_h} pt, below the declared ${declared_h}: this state's fixed chrome cannot compress that far, so the measurement is broken"
            [[ $VERBOSE -eq 1 ]] && echo "      $line"
            INCONCLUSIVE=1
            continue
        fi

        content_h="$(sed -E 's/.* min=[0-9]+x([0-9]+) .*/\1/' <<< "$line")"
        if ! [[ "$content_h" =~ ^[0-9]+$ ]]; then
            echo "error: could not read a minimum height from: $line" >&2
            exit 1
        fi
        window_h=$(( content_h + TITLE_BAR ))

        # An allowed shortfall is recorded per state, and it is a RATCHET: a state already known to
        # miss the budget may not miss it by more than it did when that was written down. A known
        # gap that quietly widens is the failure mode this file exists to prevent, and "it was
        # already failing" must not be a licence for it to get worse.
        allowed=""
        if [[ -f "$EXCEPTIONS" ]]; then
            allowed="$(awk -v v="$view" '$1 == v { print $2 }' "$EXCEPTIONS" | head -1)"
        fi

        if (( window_h <= COMMITTED_BUDGET )); then
            verdict="fits"
        elif [[ -n "$allowed" ]] && (( window_h <= allowed )); then
            verdict="KNOWN GAP — over by $(( window_h - COMMITTED_BUDGET )) pt, allowance ${allowed}"
        elif [[ -n "$allowed" ]]; then
            verdict="REGRESSED — ${window_h} exceeds its recorded allowance of ${allowed}"
            FAILED=1
        else
            verdict="TOO TALL — over the ${COMMITTED_BUDGET} pt budget by $(( window_h - COMMITTED_BUDGET )) pt"
            FAILED=1
        fi

        printf "  %-24s %7s %8s %8s   %s\n" "$view" "$drives" "$content_h" "$window_h" "$verdict"
        [[ $VERBOSE -eq 1 ]] && echo "      $line"

        if (( window_h > WORST )); then
            WORST=$window_h
            WORST_STATE="$view"
        fi
    done
done

echo
if [[ $INCONCLUSIVE -eq 1 ]]; then
    cat <<'EOF'
? window-fit-check INCONCLUSIVE.

At least one state was not measured: either `ui-probe --limits` said so itself, or its measured
number came back below the declaration, which for these states cannot happen while the measurement
works. No worst case is printed and no verdict is reached: `min=` would then be the DECLARED
minimum, short of the height the content can actually occupy, so a number here would be wrong in
the direction that reads as safe.

Fix the probe — `measuredMinimumHeight` in tools/ui-probe/main.swift, whose reasons are worded to
be printed above — and run this again. Do NOT record a figure from a run that says this.
EOF
    exit 2
fi

echo "Worst case: ${WORST_STATE} at ${WORST} pt."
for scaling in "${SCALINGS[@]}"; do
    IFS='|' read -r name points budget <<< "$scaling"
    if (( WORST <= budget )); then
        printf "  %-28s fits, %s pt spare\n" "$name" "$(( budget - WORST ))"
    else
        printf "  %-28s DOES NOT FIT, short by %s pt\n" "$name" "$(( WORST - budget ))"
    fi
done

echo
if [[ $FAILED -eq 0 ]]; then
    echo "✔ window-fit-check: every state fits, or misses by no more than its recorded allowance."
    exit 0
fi

cat <<'EOF'
✖ window-fit-check FAILED.

A state is taller than the committed budget and has no recorded allowance, or has grown past
the allowance it had. Either:

  * find the height — `ui-probe --limits <view> 640 <drives>` names the state, and
    `scripts/render-ui.sh <out.png> 640 <height> <view> light <drives>` shows where it went; or
  * record a deliberate allowance in scripts/.window-fit-exceptions, with the reason, if the
    shortfall is a decision rather than a defect.

Do NOT raise an allowance to make this pass. The allowance is a ratchet.
EOF
exit 1
