#!/bin/bash
#
# make-unmount-fixture.sh — build the multi-volume drive the unmount-rollback check needs.
#
# WHY THIS EXISTS
# ---------------
# `VolumeMounter.restoringUnmount` can only be exercised end-to-end on a drive with **two or
# more mounted volumes**, because its whole subject is what happens when a whole-disk unmount
# takes some volumes and is refused on another. On a single-volume drive the restore set is
# empty, `mount(volumeBSDNames:)` short-circuits, and `mountOne` is never called at all — so a
# single-volume run looks like a pass while leaving the interesting half untouched.
#
# The designated scratch device (Samsung T5) has exactly one mounted volume, and the only
# multi-volume drive otherwise attached to this machine is the live Time Machine disk. Hence a
# purpose-built fixture on a drive whose contents are expendable.
#
# THE LAYOUT, AND WHY EACH PARTITION IS THERE
# -------------------------------------------
#   s1  EFI          created automatically by GPT, left UNMOUNTED — the trap. It must never
#                    appear in a restore, and `kDADiskMountOptionWhole` is what would put it
#                    there (observed 2026-08-06; the third attempt at the rollback did exactly
#                    that).
#   s2  Vol_ExFAT    a direct partition of the physical disk. Restoring it by node is the case
#                    where `…Whole` would reach UP to the whole disk and drag EFI along.
#   s3  Vol_APFS     an APFS container holding one volume, mounted from a *synthesized* disk.
#                    Its device node is not derivable from the physical disk by prefix, which is
#                    the entire reason `DiscoveredDevice.mountedVolumeBSDNames` exists.
#   s4  Vol_HFS      a second direct partition, so a restore set can hold more than one node and
#                    a "restore exactly what went" bug cannot hide behind a set of size one.
#
# WHAT IT REFUSES
# ---------------
# Everything that is not the designated fixture drive. The target goes through
# `resolve_target fixture` like every other hardware script's, so the serial must match
# `FIXTURE_SERIAL` **and** the block count must match `FIXTURE_BLOCKS` — a serial that resolved
# to the wrong hardware would otherwise look exactly like one that resolved correctly. The
# scratch device, the bulk/Time Machine device and the drive holding the source tree are each
# refused by name before that, so the refusal explains what the drive actually is.
#
# **A BSD name is refused outright**, not resolved. `resolve_target` accepts one elsewhere as a
# *confirmation* — the point being that a stale `disk4` from someone's shell history gets checked
# rather than obeyed. Here there is nothing to confirm against, and the operation erases a
# partition table, so the only safe answer is no. This is not hypothetical: on 2026-08-09 the
# scratch device was unplugged and **this drive took its `disk8`** inside a single session.
#
# Usage:  scripts/make-unmount-fixture.sh <serial>
#         scripts/make-unmount-fixture.sh --list      # what is attached, by serial
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/device-identity.sh
source "$REPO_ROOT/scripts/lib/device-identity.sh"

usage() {
    cat >&2 <<'EOF'
usage: make-unmount-fixture.sh <serial>
       make-unmount-fixture.sh --list

Builds a four-partition GPT fixture (EFI + exFAT + APFS + HFS+) for exercising the
unmount rollback. ERASES the named drive. The drive is named by USB SERIAL NUMBER;
a BSD name is not accepted, because it is not an identity.

Run with --list to see the serial of every attached external USB disk.
EOF
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

build_device_id || exit 1

if [[ "$1" == "--list" ]]; then
    echo "Attached external USB whole disks (serial  bsd  blocks  blockSize  model):" >&2
    "$DEVICE_ID_BIN" list
    exit 0
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

TARGET_SERIAL="$1"

# A BSD name here is refused rather than resolved. `resolve_target` accepts one as a
# *confirmation* because a stale command line is a real thing that happens; this script has no
# role to confirm against, so there is nothing for it to disagree with. Refuse it outright.
if [[ "$TARGET_SERIAL" =~ ^disk[0-9]+$ ]]; then
    echo "REFUSED — '$TARGET_SERIAL' is a BSD name, not an identity." >&2
    echo "    BSD names are assigned at enumeration and name a different drive after a" >&2
    echo "    replug or a reboot. This script erases a drive; name it by serial." >&2
    echo "    Run: $0 --list" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Refuse every drive this project already has a role for
# ---------------------------------------------------------------------------

case "$TARGET_SERIAL" in
    "$SCRATCH_SERIAL")
        echo "REFUSED — serial $TARGET_SERIAL is the DESIGNATED SCRATCH DEVICE" >&2
        echo "    ($SCRATCH_MODEL). Erasing it destroys fill.bin, without which a" >&2
        echo "    retention gate can land on all-zero space and report a clean pass having" >&2
        echo "    proved nothing. Rebuilding it is ~1-2.5 hours of /dev/urandom." >&2
        exit 1
        ;;
    "$BULK_SERIAL")
        echo "REFUSED — serial $TARGET_SERIAL is the BULK DEVICE ($BULK_MODEL)." >&2
        echo "    It holds a live HFS volume and Time Machine. It is never a write target," >&2
        echo "    and this script erases the partition table." >&2
        exit 1
        ;;
    "$SOURCE_TREE_SERIAL")
        echo "REFUSED — serial $TARGET_SERIAL is $SOURCE_TREE_MODEL." >&2
        echo "    IT HOLDS THE SOURCE TREE." >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Resolve through the shared machinery
# ---------------------------------------------------------------------------
#
# `resolve_target fixture` requires the serial to be FIXTURE_SERIAL and cross-checks the block
# count against FIXTURE_BLOCKS. Doing it here rather than with a local `find` means this script
# cannot drift from the resolver every other hardware script uses, and it means an unknown serial
# is refused rather than accepted as "some drive the project has no opinion about" — which is
# not a safe default for something that erases a partition table.
if ! BSD="$(resolve_target fixture "$TARGET_SERIAL")"; then
    exit 1
fi

RECORD="$("$DEVICE_ID_BIN" find "$FIXTURE_SERIAL")"
IFS=$'\t' read -r SERIAL RESOLVED_BSD BLOCKS BLOCK_SIZE MODEL <<< "$RECORD"

# Two routes to one answer, for the same reason `metrics-check.sh` compares the cycle's reply
# against a separate poll: a resolver that returned the wrong drive would otherwise be
# indistinguishable from one that returned the right one.
if [[ "$RESOLVED_BSD" != "$BSD" ]]; then
    echo "REFUSED — the two lookups disagree: resolve_target said /dev/$BSD," >&2
    echo "    device-id said /dev/$RESOLVED_BSD. Not proceeding." >&2
    exit 1
fi

CAPACITY_GB=$(( BLOCKS * BLOCK_SIZE / 1000000000 ))

# ---------------------------------------------------------------------------
# Say what will be destroyed, then require it to be typed
# ---------------------------------------------------------------------------

echo
echo "About to ERASE and repartition:"
echo
echo "    model     $MODEL"
echo "    serial    $SERIAL"
echo "    locator   /dev/$BSD    (a locator, not an identity — it may name another drive later)"
echo "    capacity  $BLOCKS x $BLOCK_SIZE B  (~${CAPACITY_GB} GB)"
echo
echo "Currently on it:"
/usr/sbin/diskutil list "/dev/$BSD" 2>&1 | sed 's/^/    /'
echo
echo "It will become: GPT + EFI(unmounted) + Vol_ExFAT + Vol_APFS + Vol_HFS."
echo "EVERYTHING ON IT WILL BE LOST."
echo
printf 'Type the serial number to confirm: '
read -r TYPED

if [[ "$TYPED" != "$SERIAL" ]]; then
    echo "Not confirmed — nothing was changed." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build it
# ---------------------------------------------------------------------------

echo
echo "Partitioning /dev/$BSD…"

# Sizes are deliberately modest and equal-ish: nothing here reads or writes the volumes'
# contents, so capacity is irrelevant and a smaller layout formats faster. The final `0`
# takes the remainder.
/usr/sbin/diskutil partitionDisk "/dev/$BSD" GPT \
    ExFAT Vol_ExFAT 100G \
    APFS  Vol_APFS  100G \
    JHFS+ Vol_HFS   0

echo
echo "--- Result ---"
/usr/sbin/diskutil list "/dev/$BSD"

echo
echo "--- Mounted volumes on this drive ---"
/sbin/mount | grep -E "/dev/disk" | sed 's/^/    /'

echo
cat <<EOF
Fixture built. EFI is partition 1 and should be UNMOUNTED — that is the trap the
rollback must not spring.

Next: launch /Applications/USBDriveTester.app, select this drive (serial $SERIAL),
and run the three cases in progress/step-10.md, "the unmount rollback, verified".
EOF
