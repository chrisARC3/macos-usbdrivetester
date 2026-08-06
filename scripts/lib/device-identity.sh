#!/bin/bash
#
# device-identity.sh — resolve this project's test hardware by USB SERIAL NUMBER.
#
# Sourced, not run. Every script that touches real hardware gets its target through
# `resolve_target`, and none of them takes a BSD name as its identity any more.
#
# WHY (2026-08-06, and it is not hypothetical)
#
# A reboot renumbered this machine's drives. The designated scratch device stopped being `disk4`
# and became `disk8` — and `disk4` became the 22 TB Seagate holding **Backup and Time Machine**.
# Every gate script here took a BSD name on the command line and trusted it. Running the
# documented command `retention-cycle-check.sh disk4` after that reboot would have unmounted the
# backup drive and written a gibibyte to it.
#
# Nothing about that is exotic: the BSD name is assigned at enumeration and names a different
# drive after any replug. The product has identified drives by USB serial number since
# 2026-08-05 for exactly this reason. This applies the same rule to the apparatus.
#
# NOT AN ARGUMENT AGAINST SHOWING BSD NAMES
#
# The rule's test is *lifetime*, not surface. A script and its command line outlive the
# enumeration that produced them — someone re-runs a line from their history a week later — so
# here the identity must be the serial. A LIVE display is the other case entirely: the app shows
# the BSD name beside the serial on purpose, because it is one more axis a user can check against
# the machine in front of them, and it is what ties the window to `diskutil` and /dev/rdiskN.
# Hence `resolve_target` prints the BSD name it resolved *together with* the serial and model: at
# the moment it is printed it is live and useful, and the serial is what made it trustworthy.
# Full rule in the FR document's 2026-08-06 entry.
#
# WHAT IT GUARANTEES
#
#   * A script written for the scratch device cannot run against another drive, whether it was
#     pointed there by a stale BSD name in the documentation, by a stale one in someone's shell
#     history, or by a typo.
#   * The refusal names both serials, so the failure explains itself.
#   * The identity comes from `tools/device-id`, which is the *app's* enumerator — so "the serial
#     of this drive" has one definition in this project, not two.
#   * Resolution is cross-checked against the drive's expected model and block count, because a
#     serial that resolved to the wrong hardware would otherwise be indistinguishable from one
#     that resolved correctly.
#
# HOW IT FAILS
#
# Closed. Anything it cannot establish — the tool will not build, the serial is not connected,
# the geometry disagrees — is a refusal, never a fallback to a BSD name. There is no permissive
# reading of "I could not confirm which drive this is" on a tool that writes to drives.
#

# ---------------------------------------------------------------------------
# The hardware, by serial. BSD names are recorded only as "what it was called
# when this was written", and are never used to decide anything.
# ---------------------------------------------------------------------------

# Samsung Portable SSD T5, 1 TB, one exFAT volume `Test_Drive`, contents EXPENDABLE.
# THE designated scratch device: every write gate in this project targets this drive.
readonly SCRATCH_SERIAL="12345686DAA9"
readonly SCRATCH_MODEL="Samsung Portable SSD T5"
readonly SCRATCH_BLOCKS=1953525168
readonly SCRATCH_BLOCK_SIZE=512

# Seagate Expansion HDD, 22 TB, live HFS volume + Time Machine. NEVER a write target.
# Used once, read-only, to discharge NFR-COMPAT-6 (block counts above 2^32).
readonly BULK_SERIAL="00000000NT17XBRA"
readonly BULK_MODEL="Seagate Expansion HDD"
readonly BULK_BLOCKS=42970644479
readonly BULK_BLOCK_SIZE=512

# Samsung SSD 990 EVO Plus in a Ugreen enclosure — HOLDS THE SOURCE TREE. Never tested.
# Listed so that a script can name it when refusing, rather than reporting an unknown drive.
# The serial belongs to the *enclosure*: swapping the drive inside it would not change this.
readonly SOURCE_TREE_SERIAL="013117100578"
readonly SOURCE_TREE_MODEL="Samsung SSD 990 EVO Plus (Ugreen enclosure)"

# ---------------------------------------------------------------------------
# The resolver tool
# ---------------------------------------------------------------------------

# Built outside the repo: this volume is removable, and macOS gates access to removable volumes.
readonly DEVICE_ID_DIR="/tmp/usbdrivetester-device-id"
readonly DEVICE_ID_BIN="$DEVICE_ID_DIR/device-id"

# Compile `tools/device-id` if the binary is missing or older than any source it is built from.
#
# It compiles the app target's sources — the same trick `render-ui.sh` uses — so the serial it
# reports is the one the app reports, from the same IOKit ancestor search, through the same
# placeholder-rejecting sanitiser. `USBDriveTesterApp.swift` is excluded because its `@main`
# would clash with the tool's own top-level code.
build_device_id() {
    local repo_root app_dir newest
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    app_dir="$repo_root/USBDriveTester/USBDriveTester"

    mkdir -p "$DEVICE_ID_DIR"

    newest="$(find "$app_dir" -name '*.swift' -newer "$DEVICE_ID_BIN" -print -quit 2>/dev/null || true)"
    if [[ -x "$DEVICE_ID_BIN" && -z "$newest" ]] \
       && [[ ! "$repo_root/tools/device-id/main.swift" -nt "$DEVICE_ID_BIN" ]]; then
        return 0
    fi

    local sources=()
    while IFS= read -r -d '' f; do
        [[ "$(basename "$f")" == "USBDriveTesterApp.swift" ]] && continue
        sources+=("$f")
    done < <(find "$app_dir" -name '*.swift' -print0)

    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "device-identity: no app sources found under $app_dir" >&2
        return 1
    fi

    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"
    # -default-isolation MainActor mirrors the app target's SWIFT_DEFAULT_ACTOR_ISOLATION, so the
    # sources compile under the same rules the real build uses.
    xcrun swiftc \
        -swift-version 5 \
        -target arm64-apple-macos26.0 \
        -default-isolation MainActor \
        -O \
        -o "$DEVICE_ID_BIN" \
        "${sources[@]}" \
        "$repo_root/tools/device-id/main.swift" >/dev/null || {
            echo "device-identity: could not build tools/device-id" >&2
            return 1
        }
}

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------

# parse_device_flag "$@"
#
# Pulls an optional device argument out of a command line and leaves everything else in
# `DEVICE_FLAG_REMAINING`, so a script's other positional arguments keep their positions.
#
# Accepts `--device <x>`, `--device=<x>`, **and a bare `diskN`**. That last form is the old
# calling convention, and it is accepted here for one reason: so that a stale command line — the
# `disk4` written in six months of documentation and shell history — is **checked and refused**
# rather than silently reinterpreted as some other script's positional argument.
#
# Bash 3.2 is what `#!/bin/bash` gets on macOS, so the caller expands the remainder as
#     set -- ${DEVICE_FLAG_REMAINING[@]+"${DEVICE_FLAG_REMAINING[@]}"}
# because `"${empty[@]}"` is an unbound-variable error there under `set -u`.
DEVICE_ARGUMENT=""
DEVICE_FLAG_REMAINING=()

parse_device_flag() {
    DEVICE_ARGUMENT=""
    DEVICE_FLAG_REMAINING=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device)
                shift
                if [[ $# -eq 0 || -z "$1" ]]; then
                    echo "device-identity: --device needs a serial number or a BSD name" >&2
                    return 2
                fi
                DEVICE_ARGUMENT="$1"
                ;;
            --device=*)
                DEVICE_ARGUMENT="${1#--device=}"
                ;;
            disk[0-9]*)
                DEVICE_ARGUMENT="$1"
                ;;
            *)
                DEVICE_FLAG_REMAINING+=("$1")
                ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------

# resolve_target <role> [argument]
#
#   role      `scratch` (the T5, the only write target) or `bulk` (the Seagate, read-only).
#   argument  optional. A serial number or a BSD name. Either must AGREE with the role; it is a
#             confirmation, never an override. Omit it and the role's serial is used.
#
# Prints the resolved whole-disk BSD name on stdout — and nothing else, so it can be captured —
# with the identification on stderr where a human sees it. Returns non-zero, having explained
# itself, if the drive cannot be identified beyond doubt.
resolve_target() {
    local role="$1"
    local argument="${2:-}"
    local want_serial want_model want_blocks

    case "$role" in
        scratch) want_serial="$SCRATCH_SERIAL"; want_model="$SCRATCH_MODEL"; want_blocks="$SCRATCH_BLOCKS" ;;
        bulk)    want_serial="$BULK_SERIAL";    want_model="$BULK_MODEL";    want_blocks="$BULK_BLOCKS" ;;
        *)       echo "device-identity: unknown role '$role'" >&2; return 2 ;;
    esac

    build_device_id || return 1

    # An argument that is a BSD name is resolved to a serial and then required to agree. This is
    # the case that matters: it is what a stale command line looks like.
    if [[ -n "$argument" && "$argument" =~ ^disk[0-9]+$ ]]; then
        local actual_serial
        if ! actual_serial="$("$DEVICE_ID_BIN" serial-of "$argument" 2>&1)"; then
            echo "device-identity: REFUSED — $actual_serial" >&2
            return 1
        fi
        if [[ "$actual_serial" != "$want_serial" ]]; then
            echo "device-identity: REFUSED — /dev/$argument is NOT the $role device." >&2
            echo "    $argument reports serial $actual_serial" >&2
            echo "    the $role device is serial $want_serial ($want_model)" >&2
            if [[ "$actual_serial" == "$SOURCE_TREE_SERIAL" ]]; then
                echo "    that serial is $SOURCE_TREE_MODEL — IT HOLDS THE SOURCE TREE." >&2
            elif [[ "$actual_serial" == "$BULK_SERIAL" ]]; then
                echo "    that serial is $BULK_MODEL — a live backup volume, never a write target." >&2
            fi
            echo "    BSD names are assigned at enumeration and change across a reboot or replug." >&2
            echo "    Re-run with no argument and the drive will be found by serial." >&2
            return 1
        fi
    elif [[ -n "$argument" && "$argument" != "$want_serial" ]]; then
        echo "device-identity: REFUSED — serial $argument is not the $role device" >&2
        echo "    the $role device is serial $want_serial ($want_model)" >&2
        return 1
    fi

    local record
    if ! record="$("$DEVICE_ID_BIN" find "$want_serial" 2>&1)"; then
        echo "device-identity: REFUSED — $record" >&2
        echo "    expected the $role device: $want_model, serial $want_serial." >&2
        echo "    Connect it, or check that it enumerated (diskutil list external)." >&2
        return 1
    fi

    local serial bsd blocks block_size model
    IFS=$'\t' read -r serial bsd blocks block_size model <<< "$record"

    # Independent cross-checks. A serial lookup that returned the wrong hardware would otherwise
    # look exactly like one that returned the right hardware — the same reason `metrics-check.sh`
    # samples the daemon's CPU from outside as well as asking it.
    if [[ "$blocks" != "$want_blocks" ]]; then
        echo "device-identity: REFUSED — serial $want_serial resolved to /dev/$bsd, but its" >&2
        echo "    geometry is $blocks blocks and the $role device has $want_blocks." >&2
        echo "    Something is wrong with the identification; not proceeding." >&2
        return 1
    fi

    echo "device-identity: $role device is /dev/$bsd — $model," \
         "serial $serial, $blocks × $block_size B" >&2
    printf '%s\n' "$bsd"
}
