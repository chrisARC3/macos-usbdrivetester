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

# Samsung PSSD T5 EVO, 4 TB, contents EXPENDABLE. Two roles, added 2026-08-09:
#
#   * the multi-volume fixture for the unmount-rollback checks (`make-unmount-fixture.sh`), which
#     the single-volume scratch device cannot exercise — its restore set is always empty;
#   * the reserve discriminator for the unexplained mid-gate de-enumeration (BUILD-PLAN Step 12).
#
# NOT a retention-gate target: it holds no /dev/urandom fill, so a random placement could land on
# all-zero space and report a clean pass having proved nothing. `FIXTURE_BLOCKS` is here so that
# the identification is cross-checked, not so that a write gate can point at it.
#
# It was recorded project-wide as "a second 1 TB Samsung" until 2026-08-09 (user correction). The
# capacity was remembered rather than read, and a remembered capacity is an assigned identifier
# wearing different clothes — which is the same failure mode as the BSD name this file exists to
# eliminate. The serial and the block count below were read from the drive.
# ITS USB LINK CEILING IS 5 Gb/s, AND THAT IS THE PRODUCT — not the cable, not the port, not a hub
# in the way (settled 2026-08-25, user finding). The T5 EVO is specified as USB 3.2 **Gen 1** and
# rated around 460 MB/s: Samsung sells it as the high-capacity, lower-cost line and left out the
# faster bridge, which costs nothing the NAND behind it could have used. Tested here across two
# built-in Mac mini ports and two cables — the negotiated speed never moved off code 3. So a
# reading of `5 Gb/s (USB 3.0)` for this drive is CORRECT, and every throughput figure this project
# has ever taken from the EVO was bounded near 500 MB/s by the link before the drive was the limit.
# The 1 TB scratch T5 is the Gen 2 drive on this bench — code 4, 10 Gb/s. DO NOT RE-DIAGNOSE THIS.

readonly FIXTURE_SERIAL="00000S7CLNJ0WC02266P"
readonly FIXTURE_MODEL="Samsung PSSD T5 EVO"
readonly FIXTURE_BLOCKS=7814037168
readonly FIXTURE_BLOCK_SIZE=512

# Generic "UDisk" thumb, 125.8 MB, contents EXPENDABLE — THE MULTI-SLICE FIXTURE, added
# 2026-09-07 (user decision) for Step 12 checklist item 4.9.
#
# WHY A THIRD EXPENDABLE DRIVE. One unplug is several events: a partitioned drive fires
# `DADiskDisappeared` once for the whole disk and once per slice (measured 2026-09-05), so the
# wind-down has to be idempotent. Nothing on this bench could check that on hardware — the
# designated scratch T5 has ONE volume, and the only partitioned drive here is the 4 TB T5 EVO,
# which holds data that a run would write over. Two 60 MB exFAT slices on a disposable thumb is
# the smallest thing that can ask the question.
#
# ⚠️ CORRECTED 2026-09-10 — BOTH PREMISES WERE WRONG, AND THE THUMB CANNOT ASK THE QUESTION.
# The scratch T5 is GPT with an EFI slice beside its exFAT volume: one volume, but TWO slices, so
# it was a partitioned drive all along. And "whole disk plus slices" holds only with nothing
# claimed: a run's exclusive open tears the slices down at the claim, so a claimed drive's unplug
# fires ONE whole-disk event (measured 2026-09-09, six of six). A paused run keeps its claim, so
# the thumb behaves exactly as the T5 does. Multi-slice idempotency has no hardware path in this
# design; `threeCallbacksFromOneUnplugArmOneDeadline` pins it on the bench, and nothing else does.
# See CONSTRAINTS.md §1, "Under a claim, an unplug fires the WHOLE DISK only", and checklist
# item 4.9, which carries this as a prediction and leaves whether to walk it to the user.
# (✅ WALKED 2026-09-11, user decision, and the prediction HELD: both slices went at the claim,
# 09:43:12.584, and a paused run's unplug fired exactly ONE `disk4 (whole disk)` and no slice
# line — one loss line, one `run ended`, one report. So 4.9 passed without exercising any
# idempotency, as declared. The role's use is spent; keep it for a future unclaimed-drive question.)
#
# NOT a retention-gate target and never a write-gate target in the product's sense: 125.8 MB is
# too small to say anything about throughput, and it holds no /dev/urandom fill, so a placement
# could land on all-zero space and report a clean pass having proved nothing. It exists to be
# unplugged.
#
# ⚠️ **IT DE-ENUMERATED DURING ITS OWN REPARTITION, 2026-09-07 10:44.** `diskutil partitionDisk`
# wrote the GPT and both slices — the log shows `disk4`, `disk4s1` and `disk4s2` all present —
# and the storage stack then vanished mid-format while the USB device stayed enumerated in IOKit
# with no `IOMedia` under it. `diskutil` hung and was killed. **A physical replug is needed
# before this role can be used**, and the block count below is what the geometry is EXPECTED to
# be, unconfirmed until then. See `progress/step-12-human-checklist.md` item 4.9.
# (✅ Replugged the same day and CONFIRMED, 2026-09-07: `resolve_target multislice` reported
# /dev/disk4, 245760 × 512 B, slices 59.8 MB and 64.0 MB — not the even 60/60 asked for, so
# check for TWO slices, never for two 60 MB ones. Re-verified by serial 2026-09-10.)
# (⚠️ AND NOT TWO exFAT SLICES, found 2026-09-11: `disk4s2` has no volume — no name, not mounted,
# `diskutil` personality `MS-DOS` with no FAT variant. Its format is most likely what the hang cut
# off. Only `disk4s1` is `Slice_A`, exFAT. Two slices is what the role needs; two volumes it never
# did, since a slice is an IOMedia whether or not it holds a filesystem.)
readonly MULTISLICE_SERIAL="2211190533300386001515"
readonly MULTISLICE_MODEL="General UDisk"
readonly MULTISLICE_BLOCKS=245760
readonly MULTISLICE_BLOCK_SIZE=512

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
#   role      `scratch` (the T5, the only retention-gate write target), `bulk` (the Seagate,
#             read-only) or `fixture` (the T5 EVO, erasable, no fill data — see its constants).
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
        fixture) want_serial="$FIXTURE_SERIAL"; want_model="$FIXTURE_MODEL"; want_blocks="$FIXTURE_BLOCKS" ;;
        multislice)
                 want_serial="$MULTISLICE_SERIAL"; want_model="$MULTISLICE_MODEL"; want_blocks="$MULTISLICE_BLOCKS" ;;
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
            elif [[ "$actual_serial" == "$SCRATCH_SERIAL" ]]; then
                echo "    that serial is $SCRATCH_MODEL — the scratch device, which holds fill.bin." >&2
            elif [[ "$actual_serial" == "$FIXTURE_SERIAL" ]]; then
                echo "    that serial is $FIXTURE_MODEL — the unmount fixture. It carries NO fill" >&2
                echo "    data, so a retention gate on it would report a clean pass over zeroes." >&2
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
    #
    # It is CORROBORATION, NOT IDENTIFICATION, and this machine proves the distinction rather
    # than merely illustrating it: the scratch device and the drive HOLDING THE SOURCE TREE both
    # report exactly 1,953,525,168 blocks (observed 2026-08-09, both attached at once). Block
    # count alone cannot tell those two apart — only the serial can. So this check catches a
    # serial that resolved to *differently sized* hardware; it must never be relaxed into an
    # identity of its own, and nothing here may fall back to it when a serial is unavailable.
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
