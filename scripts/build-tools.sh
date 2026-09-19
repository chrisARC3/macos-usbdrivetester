#!/bin/bash
#
# build-tools.sh — type-check every gate client against the CURRENT protocol.
#
# ## Why this exists
#
# The gate clients under `tools/` are separately compiled artefacts that decode the same XPC
# replies the app does. A protocol change breaks them — but only when somebody happens to build
# them, and nothing builds them except the gate that uses them, which needs hardware and a
# deliberate decision to run.
#
# **That gap has now bitten twice.** Increment 3's v10 → v11 bump rebuilt `metrics-probe` and
# `mount-guard-client` but not `ui-probe`, which then sat uncompilable for three increments —
# `RunCycleOutcome` had lost `didComplete` at e13d3e8 — and was discovered only when increment 5's
# render gate tried to use it. Before that, the v9 → v10 bump missed a client the same way.
#
# So this script is the cheap, hardware-free answer to "did that protocol change break anything I
# am not going to compile for another month". It runs in seconds and needs no drive.
#
# `-typecheck`, not a link: the question is whether these sources still agree with the protocol,
# not whether a binary runs. That keeps it fast enough to run after every wire change.
#
# ## Three recipes, because the tools are not all the same shape
#
#   * **protocol clients** — the shared `TesterControl.swift` plus the tool's own sources. Most of
#     them.
#   * **app-module clients** — `ui-probe`, `device-probe` and `device-id` compile the *whole app
#     target*, so they see `DiscoveredDevice`, `IOKitDeviceEnumerator` and the views. They need
#     `-default-isolation MainActor` to match `SWIFT_DEFAULT_ACTOR_ISOLATION`, and they must
#     exclude `USBDriveTesterApp.swift`, whose `@main` clashes with a tool's top-level code.
#   * **standalone** — `nocache-probe` and `sleep-assertion-probe` take no protocol at all; their
#     gates build them from their own source alone, and handing them the shared file is not what
#     the gate does.
#
# The recipes must match what each gate actually uses. They are duplicated here rather than
# sourced, because the gates build inside `set -e` pipelines with their own temp dirs — but a
# recipe that drifts silently is a check that passes while proving nothing, so if you change how a
# gate compiles its client, change it here too.
#
# Getting a recipe wrong shows up as a compile error that has nothing to do with the protocol —
# `cannot find type 'DiscoveredDevice' in scope` means this script is wrong, not the tool.
#
set -uo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/USBDriveTester/USBDriveTester"
SHARED="$APP_DIR/Shared/TesterControl.swift"
TOOLS="$REPO_ROOT/tools"

[[ -f "$SHARED" ]] || { echo "error: shared protocol not found at $SHARED" >&2; exit 1; }

VERSION="$(grep -m1 'public static let version = ' "$SHARED" | sed 's/.*= //')"
echo "Type-checking gate clients against TesterProtocol.version = ${VERSION}"
echo

# The app sources `ui-probe` needs, collected the same way render-ui.sh collects them:
# every app-target file except the one carrying @main, which would clash with the probe's
# own top-level code.
APP_SOURCES=()
while IFS= read -r -d '' f; do
    [[ "$(basename "$f")" == "USBDriveTesterApp.swift" ]] && continue
    APP_SOURCES+=("$f")
done < <(find "$APP_DIR" -name '*.swift' -print0)

passed=0
failed=()
skipped=()
# Warnings are shown, counted and named, and do not fail the run. Until 2026-09-19 this loop
# printed `ok` and deleted each log unread, so it said nothing about warnings at all: three Swift 6
# warnings sat in `run-control-probe` unseen, printed on every run by its own gate into a
# transcript nobody reads for warnings (the move to Xcode 27's chunk 4).
warned=()
warnings=0

for dir in "$TOOLS"/*/; do
    name="$(basename "$dir")"
    main="$dir/main.swift"
    [[ -f "$main" ]] || { skipped+=("$name (no main.swift)"); continue; }

    # Every Swift file in the tool's own directory — `device-probe` has two.
    own=()
    while IFS= read -r -d '' f; do own+=("$f"); done < <(find "$dir" -name '*.swift' -print0)

    log="$(mktemp)"
    case "$name" in
        ui-probe|device-probe|device-id)
            xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 \
                -default-isolation MainActor -typecheck \
                "${APP_SOURCES[@]}" "${own[@]}" > "$log" 2>&1
            ;;
        nocache-probe|sleep-assertion-probe)
            xcrun swiftc -swift-version 5 -typecheck "${own[@]}" > "$log" 2>&1
            ;;
        *)
            xcrun swiftc -swift-version 5 -typecheck "$SHARED" "${own[@]}" > "$log" 2>&1
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        # ': warning: ' is the diagnostic's own line. The source excerpt under it repeats the text
        # after "`- warning: ", which this pattern does not match, so each warning counts once.
        n="$(grep -c ': warning: ' "$log")"
        if [[ "$n" -eq 0 ]]; then
            printf "  \033[32mok\033[0m    %s\n" "$name"
        else
            printf "  \033[33mok\033[0m    %s — %d warning(s)\n" "$name" "$n"
            while IFS= read -r line; do
                printf "          %s\n" "${line#"$REPO_ROOT/"}"
            done < <(grep ': warning: ' "$log")
            warned+=("$name")
            warnings=$((warnings + n))
        fi
        passed=$((passed + 1))
    else
        printf "  \033[31mFAIL\033[0m  %s\n" "$name"
        sed 's|^|          |' "$log" | grep -E "error:" | head -6
        failed+=("$name")
    fi
    rm -f "$log"
done

echo
echo "${passed} type-checked, ${#failed[@]} failed, ${#skipped[@]} skipped; ${warnings} warning(s)"
[[ ${#skipped[@]} -gt 0 ]] && printf "  skipped: %s\n" "${skipped[*]}"
[[ ${#warned[@]} -gt 0 ]] && printf "  warnings in: %s\n" "${warned[*]}"

if [[ ${#failed[@]} -gt 0 ]]; then
    echo
    echo "FAILED: ${failed[*]}"
    echo "A gate client that does not compile is a gate that cannot run. Fix before the bump lands."
    exit 1
fi
