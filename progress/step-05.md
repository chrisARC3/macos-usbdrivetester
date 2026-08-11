# Step 5 — Device discovery & selection

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

---

## Step 5 — Device discovery & selection — COMPLETE

**AI-3 / satisfies FR-DEV-1…7; NFR-USE-3, NFR-COMPAT-4/6.**

Scoped, decided and authored 2026-07-29; all CLI-verifiable gate items closed the same
day against **real hardware**, headlessly. The interactive pass on 2026-07-30 found one
genuine defect (stale mounted-volume state), which was fixed, given a discriminating
regression test, and re-confirmed on hardware. Gate closed 2026-07-30.

### Hardware on the development machine (2026-07-29)

Three USB whole disks are attached, which is the two-or-more the gate requires:

| BSD | Model | Capacity | Block size | Role |
|---|---|---|---|---|
| `disk4` | Samsung Portable SSD T5 | 1.00 TB | 512 | **the scratch/test drive** (user's choice) |
| `disk6` | Samsung SSD 990 EVO Plus | 1.00 TB | 512 | holds this source tree — must never be tested |
| `disk8` | Seagate Expansion HDD | 22.00 TB | 512 | rotational; 42,970,644,479 blocks exercises 64-bit (NFR-COMPAT-6) |

`disk0` (internal, Apple Fabric, 4096-byte blocks) is the exclusion case. Usefully,
`disk4` sorts first, so FR-DEV-3's default selection lands on the scratch drive rather
than on the working volume.

### Decisions taken (2026-07-29) — all nine as recommended

1. **USB detection → IOKit `Protocol Characteristics` → `Physical Interconnect == "USB"`**,
   found by searching *up* the parent chain with
   `IORegistryEntrySearchCFProperty(… kIORegistryIterateParents)`. Same framework as the
   enumeration and the notifications; DiskArbitration arrives in Step 6 for unmount/claim.
2. **Synthesized APFS containers excluded** by requiring the media's provider to conform
   to `IOBlockStorageDriver` — see "The finding" below.
3. **Capacity → base-10** ("1.00 TB"), matching the drive label, `diskutil` and Disk
   Utility, plus the **exact byte count** for the selected device so the rounding hides
   nothing. Base-2 would render a drive labelled 1 TB as "931.51 GiB" — correct and
   useless when the task is confirming you picked the right physical device.
4. **Live refresh → `IOServiceAddMatchingNotification`** (`kIOMatchedNotification` +
   `kIOTerminatedNotification`), re-enumerating **wholesale** rather than patching. No
   poll interval to tune against the gate's "within a second or two", and sort/selection
   stay single-path.
5. **No helper involvement.** IOKit's geometry is recorded and labelled as provisional;
   Step 7's ioctls remain the final authority. Adding a geometry XPC method now would
   widen the protocol before it is needed (NFR-SEC-3) and leave Step 7 reconciling two
   sources. Consequence worth having: **this entire gate passes with the helper
   uninstalled**, which is the state Step 4 left the machine in.
6. **Freeze source → the existing simulated-run toggle** from Step 4, now with two
   consumers (uninstall guard + discovery freeze). One simulation, not two.
7. **Odd geometry → listed but not selectable**, with the reason shown. FR-DEV-1 says
   enumerate all; silently hiding a drive the user can see in Disk Utility looks like a
   bug in discovery, whereas an explanation does not.
8. **Mounted volume names shown per row.** Not a gate item and **not** the mount guard
   (Step 6 owns that, helper-side). It earns its place because `disk6` — the drive
   holding this source tree — is in the list, and a list that shows it without saying so
   invites exactly one mistake.
9. **`ContentView` becomes a composition root**; the Step 3/4 harness is **moved, not
   deleted**, into `HelperDiagnosticsView` behind a collapsed disclosure. Step 6 needs a
   registered helper again and Step 11 needs the mid-run guard; deleting those controls
   now would mean rebuilding them to pass the next gate.

### The finding: `Whole = true` is not enough (and BUILD-PLAN Step 5 says it is)

BUILD-PLAN Step 5.1 says to match `kIOMediaClass` with `kIOMediaWholeKey = true` and
walk the parent chain to confirm a USB transport. Measured on this machine, that filter
is **not sufficient**: synthesized APFS containers also report `Whole = true`, and they
inherit the USB interconnect from the physical disk beneath them.

```
disk6  IOMedia         parent=IOBlockStorageDriver      link=USB  bs=512   1000204886016
disk7  AppleAPFSMedia  parent=AppleAPFSContainerScheme  link=USB  bs=4096   999995129856
disk8  IOMedia         parent=IOBlockStorageDriver      link=USB  bs=512  22000969973248
disk9  AppleAPFSMedia  parent=AppleAPFSContainerScheme  link=USB  bs=4096  2000624971776
```

So the plan's filter lists **every APFS-formatted USB drive twice** — once real, once
virtual — with different block sizes *and* different capacities, and the virtual entry
is the more plausible-looking of the two. Handing that to a raw block writer is not a
cosmetic defect. Fixed by requiring the media's **immediate provider** to conform to
`IOBlockStorageDriver`: a whitelist, so other virtual schemes are excluded too, and
specifically the *immediate* parent, because a synthesized container has an
`IOBlockStorageDriver` further up as well.

Corollary for Step 7: **disk images are excluded**, by the USB filter rather than this
one (they report `Physical Interconnect == "Virtual Interface"`). Step 7's gate suggests
attaching a disk image as a safe stand-in for a real device — such an image will not
appear in this list. Correct per FR-DEV-1, but plan for it.

> **Resolved 2026-08-01.** It was planned for. BUILD-PLAN has been amended to drop disk
> images as a test target entirely and fix all real-hardware I/O on `disk4`. This
> observation, made during Step 5, is what made the conflict visible two steps before it
> would have bitten.

### Two smaller findings

- **The IOMedia property constants are not bridged into Swift.** `kIOMediaClass`,
  `kIOMediaWholeKey`, `kIOMediaSizeKey`, `kIOMediaPreferredBlockSizeKey`, `kIOBSDNameKey`
  and the `kIOPropertyProtocolCharacteristicsKey` family are C `#define`s and do not
  compile. String literals are required; they are collected in one `RegistryKey` enum
  citing the headers. (`kIOServicePlane` and `kIOMainPortDefault` *are* bridged.)
- **The mount table does not name the physical disk.** `1TB_Samsung` is mounted from
  `/dev/disk7s1`, and only the IOKit registry connects `disk7` back to the physical
  `disk6`. Parsing `disk7s1` down to `disk7` — the obvious implementation — would make
  every APFS-formatted drive show no volumes at all. Resolved by walking the registry
  subtree *downward* from the whole disk and matching that set against the mount table.

### Authored

App target, `USBDriveTester/Discovery/` (all pure unless noted):
- `BSDDeviceName.swift` — numeric-aware **total** order (FR-DEV-2). Total, not merely
  numeric: `sorted()` is only deterministic when no two elements compare equal, and the
  list is rebuilt from scratch on every hot-plug.
- `CapacityFormatting.swift` — base-10 formatting and digit grouping. Not
  `ByteCountFormatter`: it is locale-dependent in separators *and* unit names, which
  would make capacities move with the user's region and make the tests assert whatever
  region the test machine is set to.
- `DiscoveredDevice.swift` — the value type, geometry sanity (`DeviceGeometryProblem`),
  presentation strings, ordering, and `DeviceSetChange` for connect/disconnect logging.
- `DeviceSelectionPolicy.swift` — selection across refreshes (FR-DEV-3/4/7).
- `MountedVolumes.swift` — `getfsstat` snapshot (not `getmntinfo`, whose static buffer is
  a poor fit for a hot-plug callback) plus pure parsing/attribution.
- `IOKitDeviceEnumerator.swift` *(impure)* — the two filters, geometry, registry-subtree
  walk, and the notification port. The only file in Step 5 that needs hardware.
- `DeviceDiscovery.swift` — `@MainActor @Observable` store: list, selection, freeze.

App target, top level:
- `DeviceListView.swift` *(new)* — `List` with a selection binding, plus the
  selected-device detail panel.
- `HelperDiagnosticsView.swift` *(new)* — the Step 3/4 harness, moved verbatim apart
  from the toggle's new second consumer.
- `ContentView.swift` *(rewritten)* — composition root; owns `simulatedRunActive`
  because both children need it.

Tests (`USBDriveTesterTests/`, via `@testable import USBDriveTester`) — **121 new**:
- `DeviceFixtures.swift` — fixtures taken from the real machine, not invented. The
  awkward cases (an **empty** vendor string on the internal SSD; a capacity that rounds
  up across a unit boundary) were found by probing hardware rather than imagined.
- `BSDDeviceNameTests` (18), `CapacityFormattingTests` (15), `DiscoveredDeviceTests` (26),
  `DeviceSelectionPolicyTests` (15), `MountedVolumesTests` (21), `DeviceSetChangeTests` (7),
  `DeviceDiscoveryTests` (19, driven through a `StubDeviceSource`).

Tooling:
- `tools/device-probe/` + `scripts/device-probe.sh` *(new)* — compiles the app's **real**
  Discovery sources and prints what they return. This is what moved four of the five gate
  items off "needs a person at the machine". `--watch` reprints on hot-plug; `--all`
  cross-checks against every whole media object in the registry.
- `tools/device-probe/AllWholeMediaProbe.swift` — deliberately **shares no code** with
  the enumerator. A filter bug that excluded everything would look identical to a correct
  exclusion if both views came from the same query, so the cross-check asks IOKit the
  broadest question independently.
- `tools/ui-probe` + `scripts/render-ui.sh` — gained a 4th argument selecting the view
  (`content` / `devices` / `diagnostics`). Once a view sits behind a disclosure, the
  composition root cannot show it, and "it compiled" is no evidence that a `Form` inside
  a `DisclosureGroup` inside a `VStack` lays out sanely. It did.

### On isolation, and a correction

The app target compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which makes
*every* unannotated declaration — including plain value types — main-actor-isolated. An
early spot-check suggested no annotation was needed; that check was too weak (it did not
exercise a protocol conformance across the module boundary) and an **incremental** test
run then hid the resulting warnings, because warnings are not re-emitted for files that
were not recompiled.

A clean rebuild showed the truth: `Equatable` conformances and initialisers were
unusable from the non-isolated test target. Fixed by marking the pure discovery types,
`DeviceSource`, `IOKitDeviceEnumerator` and its file-scope `Logger` **`nonisolated`**.
Two consequences worth keeping:

- `IOKitDeviceEnumerator` **cannot** be `MainActor`-isolated: IOKit reaches it through a
  C function pointer, and a global-actor-isolated function cannot be converted to
  `@convention(c)`. The test stub is non-isolated for the same reason — otherwise it
  would not be testing the same contract.
- The same latent warnings existed in Step 4's `UninstallPrecondition` and were fixed in
  passing. **Always verify "zero warnings" from a clean build**, not an incremental one.

### Verification done (CLI + real hardware, 2026-07-29)

- `./scripts/test.sh` → `** TEST SUCCEEDED **`, **171 test cases**, 0 failures,
  **zero warnings from a clean build**.
- `./scripts/build.sh` Debug **and** Release → `** BUILD SUCCEEDED **`, zero warnings
  (only the benign `appintentsmetadataprocessor` note).
- **Gate item 1 — all USB drives listed, internal/non-USB excluded.** `device-probe --all`
  lists `disk4`, `disk6`, `disk8` and reports every rejection with its cause: `disk0`
  "not USB (Apple Fabric)", and all five synthesized containers "not a physical disk
  (provider AppleAPFSContainerScheme)". Exclusion is a positive observation, not an
  absence of evidence — a filter that excluded everything would look identical in the
  device list alone.
- **Gate item 2 (partly) — order and default selection.** `disk4, disk6, disk8`, numeric
  and stable; `disk4` default-selected. Order proven independent of IOKit's iteration
  order (which is *not* sorted: it returns disk0, disk1, disk3, disk2, disk7, disk9,
  disk6, disk8 here).
- **Gate item 3 (content) — identity.** Every row carries BSD name, model and
  human-readable capacity; the detail panel repeats the identity and adds the exact byte
  count, geometry, raw device node, medium and mounted volumes. Confirmed by render.
- **Gate item 4 (mechanism) — live refresh.** Verified without hands by attaching and
  detaching a disk image, which publishes a whole-disk `IOMedia` and so fires the same
  notifications a USB drive does: rebuild **~50 ms** after attach, **~700 ms** after
  detach (200 ms of which is deliberate coalescing). The image was correctly **excluded**
  from the list while still triggering the refresh — both halves of the intended
  behaviour in one observation.
- **Gate item 5 — geometry.** `1,953,525,168 blocks × 512 bytes` for `disk4` and
  `42,970,644,479` for `disk8`, both matching `diskutil info`'s independently-reported
  512-byte-unit counts exactly. Displayed in the detail panel.
- **Layout** checked headlessly at 700×700 (`content`) and 700×900 (`diagnostics`).
  Fixed one real defect found this way: an uncapped `List` inside a `VStack` absorbed all
  spare height, leaving three drives above a large gap and pushing the selected-device
  detail — the thing that stops the wrong drive being tested — to the window edge. Now
  content-sized via `@ScaledMetric` so it tracks Dynamic Type rather than a hard-coded
  row height.
- **No Xcode GUI work was required.** Everything landed in the app folder or the test
  folder, both synchronized groups. Nothing new in `Core/`.

### Defect found by the interactive gate, and fixed (2026-07-30)

**Symptom (reported from item 1).** On replugging `disk4`, macOS auto-mounted its
volumes but the device list went on showing it as unmounted.

**Cause.** Mount state is not part of the IOKit *media* set, which is all the enumerator
was watching. Two failures in one:

1. On arrival the list rebuilds ~50 ms after the media appears, and
   `diskarbitrationd` mounts the volumes some time *after* that — the snapshot is taken
   before there is anything to see.
2. Nothing ever asks again, because a mount produces no whole-media notification.

Reproduced without touching the device set, which isolates cause from timing:

```
$ diskutil unmount /Volumes/Test_Drive
Volume Test_Drive on disk4s2 unmounted
   ... no refresh fired; the list still read "mounted  Test_Drive"
```

**Why the earlier verification missed it.** APFS hides the bug. Mounting an APFS volume
publishes a new `AppleAPFSMedia` object, which *is* a whole-media change and does fire
the IOKit notification — so `disk6` and `disk8` behaved correctly. The exFAT scratch
drive has no such side effect. Every check run on 2026-07-29 used either an APFS drive
or a disk image, and all of them passed. **A drive-image test is not a substitute for
the filesystem the user actually has.**

**Fix.** `Discovery/VolumeChangeWatcher.swift` *(new)* — a DiskArbitration session
watching `kDADiskDescriptionVolumePathKey` (plus disk appeared/disappeared), owned by
`IOKitDeviceEnumerator` and funnelled into the same 200 ms coalescing window. Both
sources now mean the same thing: the list needs rebuilding.

DiskArbitration rather than `NSWorkspace.didMountNotification`: NSWorkspace is fewer
lines but is AppKit-level and does not reliably deliver in a plain command-line process,
which would have left `device-probe` unable to reproduce or verify this exact defect. A
fix whose regression test cannot run headlessly is one that quietly rots. It also
matches Step 6, which uses DiskArbitration helper-side for the unmount and claim.

**Verified.** Mount → refresh in ~1.1 s; unmount → ~0.5 s; both directions show the
correct state. `scripts/mount-change-test.sh <disk>` *(new)* mechanises it, asserting
both that a refresh fires **and** that the live view's state changes — an event without a
state change would mean the mount table is misread, and a state change without an event
would mean something else happened to trigger the rebuild.

**The verifier was proven to discriminate**: with the watcher disabled, 3 of its 4 checks
fail. The 4th ("reports its mounted volume again") passes either way and inherently so —
a view that never updates is accidentally correct once the state returns to where it
started — so it is documented as catching the opposite regression rather than this one.
Writing the test also exposed two flaws in the test itself: a `grep -c` idiom emitting
`0\n0`, and state assertions that spawned a *fresh* probe process and so re-enumerated
correctly whether or not live updating worked. Both fixed; the assertions now read the
running watcher's latest output.

### Interactive gate — COMPLETE (2026-07-30)

Run on the installed `/Applications` build, all four confirmed by the user:

- [x] **Physically unplug and replug `disk4`** with no run active — confirmed
      2026-07-30. It leaves the list and rejoins within a second or two, and its
      auto-mounted volume now appears. This is the case that failed on the first
      attempt; the physical replug is the only thing that reproduces the
      arrival-then-mount ordering end to end, so it also closes out the
      `VolumeChangeWatcher` fix on real hardware rather than only under
      `mount-change-test.sh`.
- [x] **Click a different row** — selection moves and the detail panel follows
      (FR-DEV-4). The store's policy was unit-tested; this closes the `List` selection
      binding, which was the untested half.
- [x] **Toggle "Simulate an active run"**, then unplug a drive — the list does not
      change and says why; clearing the toggle catches it up (FR-DEV-7).
- [x] **The selected device reads unambiguously** (NFR-USE-3), including `disk6`
      showing that it holds the source tree.

### Verification Gate — COMPLETE (2026-07-30)

- [x] **Connecting two or more USB drives lists all of them; non-USB/internal disks are
      excluded.** Three USB whole disks listed (`disk4`, `disk6`, `disk8`); `disk0`
      excluded as "not USB (Apple Fabric)" and all five synthesized APFS containers as
      "not a physical disk". Exclusion verified as a *positive* observation by
      `device-probe --all`, whose cross-check shares no code with the enumerator — a
      filter that wrongly excluded everything would look identical in the device list
      alone.
- [x] **List order is stable and numeric-correct across refreshes; the first device is
      default-selected; selection can be changed.** Order proven independent of IOKit's
      iteration order, which is genuinely unsorted here. Default selection lands on
      `disk4`, the scratch drive. Re-selection confirmed in the GUI.
- [x] **Each row shows BSD name, model and human-readable capacity; the selected device
      is unambiguously identified.** Detail panel adds the exact byte count, geometry,
      raw device node, medium and mounted volumes.
- [x] **Plugging/unplugging a drive with no run active updates the list within a second
      or two.** Confirmed by physical replug, and mechanically by
      `mount-change-test.sh` and a disk-image attach/detach (~50 ms attach, ~700 ms
      detach). **Mounted-volume state updates too** — see the defect section above.
- [x] **The selected device's logical block size and block count are captured and
      displayed.** `1,953,525,168 × 512` (`disk4`) and `42,970,644,479 × 512`
      (`disk8`), both matching `diskutil info`'s independently-reported 512-byte-unit
      counts exactly.
- [x] **Global DoD:** builds arm64 / macOS 26.0 Debug **and** Release with no new
      warnings (verified from a *clean* build); `./scripts/test.sh` →
      `** TEST SUCCEEDED **`, **171 test cases**, 0 failures.

### Notes

- `HelperActivity` in the helper is still always idle; nothing acquires a device until
  Steps 6/7. Step 5 does not touch the helper at all.
- The mounted-volume warning on the selected device is **advisory**. Step 6 builds the
  real guard (FR-SAFE-1/2, NFR-REL-3) helper-side, and it is the only thing that may
  permit a run.
- `disk4` currently has a mounted `Test_Drive` volume (exFAT). Step 6's gate needs
  exactly this: a mounted volume present, so starting is refused by name.
- **Lesson carried forward:** the one defect this step produced was invisible to every
  substitute for the real thing — a disk image exercised the notification path without
  a filesystem, and APFS drives masked it by publishing media on mount. Steps 6, 7 and 8
  all have gates that are tempting to close against a disk image or a simulated device;
  do that first, but do not treat it as the hardware check it stands in for.

**Next: Step 6** (mount-guard: unmount verification + exclusive whole-disk claim) — the
first step where the helper does something privileged, and where DiskArbitration moves
from the app's read-only observation here to the helper's authoritative claim.

---
