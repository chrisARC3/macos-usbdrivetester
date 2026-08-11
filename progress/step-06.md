# Step 6 — Mount-guard: unmount verification + exclusive claim

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

---

## Step 6 — Mount-guard: unmount verification + exclusive claim — AUTHORED, GATE OUTSTANDING

**AI-4 / satisfies FR-SAFE-1…7; NFR-REL-3, NFR-USE-5.**

Scoped 2026-07-30: requirements amended, decisions taken, exclusivity semantics measured
on real hardware, and the file plan approved by the user. **All source authored 2026-07-31**
(see "Authored" below). Unit tests and the headless checks are green; the hardware and
interactive gate items have **not** been run yet, and one pre-existing build defect must
be fixed before the Global DoD can pass — both tracked at the end of this section.

### Requirements amended this step (2026-07-30)

The mount/unmount control was specified by the user during scoping and changed the
baselined functional spec. Recorded in
[functional-requirements](functional-requirements-usb-drive-tester.md#amendments-to-the-baseline):

- **FR-SAFE-5 revised, C → M.** One control acting on *all* volumes of the selected
  device, label and action always in agreement: `Unmount All` when any volume is
  mounted, `Mount All` when none is, disabled with no selection. **Mounting was not
  previously a requirement at all** — the baseline covered unmounting only.
- **FR-SAFE-6 added.** Nothing mounts or unmounts implicitly; starting a test never
  changes mount state. This closes a real conflict between FR-SAFE-4(a) (refuse and
  instruct) and BUILD-PLAN Step 6.2 as written (unmount as part of acquiring). BUILD-PLAN
  Step 6.2 was amended to match.
- **FR-SAFE-7 added, derived not requested.** The control is also disabled during a run
  or while the helper holds the claim, because mounting the device under test would
  violate NFR-REL-3. Marked as derived so it is easy to identify and reverse.

A useful consequence: the control's state comes from `DiscoveredDevice.mountedVolumeNames`,
which live-updates through the `VolumeChangeWatcher` added to fix the Step 5 defect. The
label re-evaluates itself when the action completes, with no extra plumbing — yesterday's
bug fix is now load-bearing for this feature.

### Decisions taken (2026-07-30)

1. **Never unmount implicitly** — now FR-SAFE-6 rather than a design preference.
2. **The mount/unmount control is app-side**, using unprivileged DiskArbitration, keeping
   the privileged XPC surface to check/acquire/release (NFR-SEC-3). Evidence:
   `diskutil unmountDisk` succeeds without `sudo` on an external drive, so an
   unprivileged process can do it.
3. **Protocol → v3, three methods:** `checkDeviceReadiness` (read-only, safe to poll for
   display), `acquireDevice`, `releaseDevice`. The check must be side-effect-free because
   the GUI has to show "2 volumes mounted" *before* Start, and a check with side effects
   cannot drive a display.
4. **The write-path guard is a type, not a flag (NFR-REL-3).** The helper holds an
   `AcquiredDevice` value constructible only by a successful acquire; Steps 7/8's write
   path takes it as a parameter. No value, no write path — the guard cannot be forgotten
   at a call site. Classification logic goes in `Core/` as a pure
   `DeviceAccessPrecondition`, unit-tested exhaustively like `UninstallPrecondition`.
5. **`HelperActivity` finally gets a body.** Acquiring marks the helper busy, so
   `prepareForShutdown` genuinely refuses and `releaseAll()` releases the claim — closing
   the loop deliberately left open in Step 4.
6. **A partially-mounted device reads `Unmount All`.** Any mounted volume selects the
   unmount direction; confirmed with the user.
7. **A device with nothing mountable keeps the control enabled** and reports honestly
   afterwards, rather than being disabled via DiskArbitration's `VolumeMountable` flag.
   Faithful to the stated rule (only "no selection" disables), and avoids relying on a
   flag that can be conservative for third-party filesystems.

### Exclusivity semantics — MEASURED (2026-07-30)

Took three runs; the first two produced answers that did not follow from their evidence,
which is recorded below because the failures were more instructive than the successes.

**Findings, all from `scripts/exclusivity-probe.sh disk4` on the real device:**

| Question | Answer |
|---|---|
| `open(rdiskN, O_RDWR)` while a volume is mounted | fails `EBUSY` — **the mount guard is kernel-enforced** |
| `open(rdiskN, O_RDWR)` unmounted | succeeds |
| Two independent `O_RDWR` opens, unmounted | **both succeed — a plain open is not exclusive** |
| `O_EXLOCK` | first succeeds, second fails `EBUSY` — **this is the exclusivity mechanism** |
| Another **process** holding claim + `O_EXLOCK` | second process gets `EBUSY`, nothing mounted — **FR-SAFE-4(b) is detectable** |
| Contended `DADiskClaim` | **PENDING forever** — never granted, never dissented |
| Volume left unmounted with no claim | **macOS silently remounted it** |

**Consequences, all now reflected in BUILD-PLAN:**

1. **Step 7 amended: the raw open must be `O_RDWR | O_EXLOCK | O_NONBLOCK`.** It
   specified a plain `O_RDWR`, which would have let two processes write the same device
   simultaneously — the failure would have been silent and intermittent.
2. **The claim needs a timeout**, and a timeout *means* FR-SAFE-4(b). A blocking claim
   would wedge the helper, and no dissenter ever arrives to tell it otherwise.
3. **Both FR-SAFE-4 causes present as the same `EBUSY`.** Only the mount check separates
   them — which the app can do unprivileged, and which is why `checkDeviceReadiness`
   must return mount state rather than an error code.
4. **The claim is mandatory, not defensive.** Auto-remount was observed, not theorised.
5. **Release is asynchronous** — an open straight after `DADiskUnclaim` can still see
   `EBUSY`, so the release path must not assume instant reusability (NFR-REL-5).

**Probe defects found and fixed along the way** — worth keeping, because each one
produced a *plausible but wrong* answer rather than an obvious failure:

- Printed "open IS exclusive" when a second open failed, in a phase where both opens
  failed because a volume was mounted. A verdict is now printed only when the first open
  succeeded.
- Passed the DiskArbitration claim context `passUnretained`, so a callback arriving after
  the timeout dereferenced a deallocated object — a segfault mid-measurement. Retained
  now, released in the callback.
- Had the holder process open with a plain `O_RDWR`, so it held nothing and the
  contention phase measured an uncontended disk.
- Ran its FR-SAFE-4 classification at the *end* of the battery, where it reported "held
  by another process" in a phase in which nothing else held the disk. It was measuring
  the probe's own leftover pending claim. **Now measured first, before the probe touches
  anything.**
- `$DISK` followed by a UTF-8 ellipsis made bash absorb those bytes into the variable
  name under `set -u`, aborting before the most important phase. Locale-dependent, so it
  ran here and failed on the user's terminal. The same latent bug was fixed in
  `install-app.sh` and `mount-change-test.sh`.

**Still unresolved, and not blocking.** Whether phase 3's exclusion came from the
holder's `DADiskClaim` or its `O_EXLOCK` cannot be told apart from this data. It does not
change the design, because the helper holds both regardless — the claim for anti-remount
(mandatory per finding 4) and `O_EXLOCK` for write exclusion.


### Approved file plan (2026-07-30) — NOT YET AUTHORED

Confirmed by the user. Author in this order: pure logic + its tests first, then the
privileged side, then the UI — the Step 5 order, which kept the hardware-dependent
surface small.

**Core** — `com.arc3solutions.USBDriveTester.Helper/Core/`
- `DeviceAccessPrecondition.swift` — pure classification of (mount state, claim outcome,
  open `errno`) → decision + message, distinguishing FR-SAFE-4(a) from (b). Mirrors
  `UninstallPrecondition`. **This is what gate item 4 verifies.**
  ⚠️ **Needs an Xcode target-membership tick** for `USBDriveTesterTests`, exactly as the
  Step 2/3 Core files did. It is the only GUI action Step 6 requires.

**Helper** — `com.arc3solutions.USBDriveTester.Helper/`
- `DeviceClaim.swift` *(new)* — DA session, mount check, claim-with-timeout, exclusive
  open, and the `AcquiredDevice` value.
- `main.swift` *(edit)* — the v3 methods; `HelperActivity` finally gets a body.

**Shared** — `USBDriveTester/Shared/`
- `TesterControl.swift` *(edit)* — protocol **v2 → v3**: `checkDeviceReadiness`
  (read-only, safe to poll), `acquireDevice`, `releaseDevice`.

**App** — `USBDriveTester/`
- `Discovery/VolumeMounter.swift` *(new)* — unprivileged mount/unmount-all via
  DiskArbitration.
- `MountControlState.swift` *(new)* — **pure** mapping of (selection, mounted count, run
  active) → button label + enabled state. FR-SAFE-5/7 encoded as testable logic rather
  than inline view conditionals.
- `HelperConnection.swift` *(edit)* — typed v3 calls.
- `DeviceListView.swift` *(edit)* — the Mount All / Unmount All button and the readiness
  banner.

**Tests** — `USBDriveTesterTests/`
- `DeviceAccessPreconditionTests.swift`, `MountControlStateTests.swift`.

**Tooling** — `scripts/claim-contention-test.sh`, reusing `exclusivity-probe --hold` to
assert the helper reports cause (b) rather than cause (a).

### The acquire sequence, as designed

1. Check mounted volumes → any ⇒ refuse, **cause (a)**, naming them (FR-SAFE-4(a)).
2. `DADiskClaim` **with a 5 s timeout** → pending ⇒ refuse, **cause (b)**.
3. `open(rdiskN, O_RDWR | O_EXLOCK | O_NONBLOCK)` → `EBUSY` ⇒ refuse, **cause (b)**;
   another `errno` ⇒ a specific error naming it.
4. Success ⇒ construct `AcquiredDevice` — the only value that unlocks the Steps 7/8 write
   path (NFR-REL-3).

**Release:** close fd → `DADiskUnclaim` → mark `HelperActivity` idle, without assuming the
device is instantly reusable (release is asynchronous — see the measurements above).

### Verification split for the gate

| Unit-testable | CLI + root | Needs a person |
|---|---|---|
| Classification of both causes; the guard tripping when access is absent; the button label/state matrix | `claim-contention-test.sh`; `exclusivity-probe.sh` | Both refusal messages in the GUI; the button toggling; release restoring normal use |

### State this step begins from

- Helper **uninstalled** (Step 4 left it that way; Step 5 never needed it).
  `/Applications/USBDriveTester.app` holds the **Step 5** build.
- Protocol at **v2**; Step 6 takes it to v3.
- `git` clean on `main`; Step 5 committed at `cbd3a39`, scoping commits after it.
- Hardware attached: `disk4` (Samsung Portable SSD T5, 1 TB, 512 B, one exFAT volume
  `Test_Drive` — **the designated scratch device**), `disk6` (holds this source tree —
  never test it), `disk8` (Seagate 22 TB).
- 171 tests passing, zero warnings from a clean build, Debug and Release.

---

### Authored (2026-07-31)

Written in the Step 5 order — pure logic and its tests first, verified green, then the
privileged side, then the UI.

**Core** — `com.arc3solutions.USBDriveTester.Helper/Core/`
- `DeviceAccessPrecondition.swift` *(new)* — the whole decision, pure and Foundation-only:
  - `WholeDiskName` — boundary validation of the caller-supplied BSD name (NFR-REL-7).
    Accepts only a canonical `disk<N>`; the canonicity check is one comparison against the
    round-trip of the parsed number, which rejects `disk04`, `disk4s2`, `rdisk4`, paths and
    oversized unit numbers in a single rule rather than one per attack shape. This is the
    string that becomes `/dev/rdiskN` in a root process.
  - `MountState` / `DiskClaimOutcome` / `ExclusiveOpenOutcome` — the three measured facts,
    as types. `MountState(mountedVolumeNames:)` maps an empty list to `.unmounted`, so
    "mounted, with nothing mounted" is unrepresentable.
  - `DeviceAccessRefusal` (+ `causeCode`) and `DeviceAccessPrecondition.evaluate(…)` — the
    classification, and the FR-SAFE-4 messages.
  - `DeviceAccessGrant` / `WritePrecondition` — the runtime half of NFR-REL-3.
  - *This was the one file needing a target-membership tick; done and verified in
    `project.pbxproj` (it now sits alongside the four Step 2/3 Core files in the
    `USBDriveTesterTests` exception set, and in no app-target set).*

**Helper** — `com.arc3solutions.USBDriveTester.Helper/`
- `DeviceClaim.swift` *(new)* — `HelperDeviceRegistry` (the helper's own IOKit identity
  re-check), `HelperMountTable` (its own `getfsstat` read), the claim-with-timeout, the
  `O_EXLOCK` open, and `AcquiredDevice`.
- `main.swift` *(edit)* — the three v3 methods; `HelperActivity` given a body; release on
  connection loss.

**Shared** — `Shared/TesterControl.swift` *(edit)* — protocol **v2 → v3**
(`checkDeviceReadiness`, `acquireDevice`, `releaseDevice`), plus `DeviceAccessRefusalCause`.

**App** — `USBDriveTester/`
- `MountControlState.swift` *(new)* — the pure FR-SAFE-5/7 truth table.
- `Discovery/VolumeMounter.swift` *(new)* — unprivileged mount/unmount-all.
- `HelperConnection.swift` *(edit)* — typed v3 calls, `DeviceReadiness`, `DeviceAcquisition`.
- `DeviceListView.swift` *(edit)* — the mount control, readiness banner, acquire/release.
- `ContentView.swift` *(edit)* — owns the single `HelperConnection`; window min height
  620 → 720.
- `HelperDiagnosticsView.swift` *(edit)* — takes the shared connection.

**Tests** — `DeviceAccessPreconditionTests.swift` (49), `MountControlStateTests.swift` (15).

**Tooling** — `tools/mount-guard-client/main.swift` *(new)*,
`scripts/claim-contention-test.sh` *(new)*, `tools/ui-probe` updated for the new view
signatures.

### Design decisions taken while authoring

Beyond the nine taken during scoping:

10. **The helper re-checks device *identity*, not just mount state.** BUILD-PLAN Step 3.5
    asks for it and it turns out to matter a great deal here: without it, any client that
    satisfies the Team-ID requirement could hand the root daemon `disk0`. `HelperDeviceRegistry`
    re-applies both Step 5 filters (immediate provider is an `IOBlockStorageDriver`,
    ancestor `Physical Interconnect == "USB"`) from the helper's own view of the registry.
    The registry-key literals are deliberately duplicated rather than shared: a shared
    filter would let one bug excuse itself on both sides of the trust boundary.
11. **A sixth refusal cause, `alreadyHeld`.** "The helper already holds a device" is not
    cause (b): the holder is us, so the corrective step is inside the app. Folding it into
    `claimedByAnotherProcess` would send the user hunting for a process that does not exist.
12. **A claim must not outlive the connection that took it (NFR-REL-5).** Each acquisition
    records an owner `UUID`; the connection's `invalidationHandler` releases only what that
    connection acquired. Without this, a force-quit GUI would strand the claim — and because
    macOS only remounts once a claim is dropped, the symptom would be a drive that has
    silently stopped mounting with no process visibly responsible. A `UUID` rather than the
    peer's pid, because pids are reused.
13. **One `HelperConnection` for the app, owned by `ContentView`.** Not merely tidier than
    one per view: with decision 12, two connections would mean two owners, and tearing down
    a view could release a claim another part of the app believed it held.
14. **The mount/unmount control renders even with no selection.** FR-SAFE-5 specifies the
    no-selection state — *disabled*, labelled "Unmount All" — and a control that is absent
    is not a control that is disabled. This was caught by re-reading the requirement against
    the first draft, which only rendered the control inside the selected-device panel.
15. **`checkDeviceReadiness` cannot detect cause (b), and says so.** Establishing that
    another process holds the node requires actually claiming and opening the device, which
    are side effects — and the claim in particular would stop the disk remounting. So
    `ready == true` means "nothing known would refuse an acquire", never "an acquire will
    succeed". Documented on the protocol method, because a future caller treating it as a
    promise would move the safety decision app-side.

### Verified (headless, 2026-07-31)

- **`./scripts/test.sh` from a CLEAN build → `** TEST SUCCEEDED **`, 235 test cases
  (226 `@Test` declarations), 0 failures, zero warnings.** Up from 171/162 at Step 5.
  Counted from the result bundle rather than the log: parallel test output tore a line and
  made a naive `grep -c` read 231. Step 5's "171" is the same executed-case measure, so the
  comparison is like-for-like.
- **`./scripts/build.sh` (Debug) → `** BUILD SUCCEEDED **`, zero warnings from a clean
  build.** Three warnings appeared first time round in `VolumeMounter` (two non-Sendable
  captures and an unused result) and were fixed rather than suppressed.
- **Core logic proven before the target-membership tick** by a throwaway `swiftc` harness
  over the real Core source — 64/64 checks. Two properties worth keeping: of the 40 input
  combinations to `evaluate`, **exactly one** grants access; of the 8 grant/target
  combinations, **exactly one** permits a write.
- **Layout rendered headlessly** at 640×720 (`content`). The first render at the old
  620-point minimum put the refusal message — the thing FR-SAFE-4 exists to communicate —
  below the fold, which is the same class of defect Step 4 hit. Window minimum raised.
- **`scripts/claim-contention-test.sh`** passes `bash -n`, and its client compiles and
  signs. Every `$VAR` before a non-ASCII character is brace-delimited; confirmed
  empirically that braces are sufficient (the unbraced form is locale-dependent, which is
  why it ran here and failed on the user's terminal last time).

### A pre-existing defect found by the clean Release build — NEEDS A GUI FIX

**Symptom.** `./scripts/build.sh Release` fails after a DerivedData wipe:
`error: The file "com.arc3solutions.USBDriveTester.Helper" couldn't be opened because
there is no such file.`

**Cause.** The app target's **Embed Helper** copy-files phase references the wrong file
object. `project.pbxproj` contains *two* references to the helper executable:

- `FE6097482FEECD1D0091C1E0` — correct: `path = com.arc3solutions.USBDriveTester.Helper;
  sourceTree = BUILT_PRODUCTS_DIR;`
- `FE6097752FEF20FC0091C1E0` — wrong, and the one the phase actually uses:
  `sourceTree = "<group>"` with the path hard-coded to
  `…/DerivedData/USBDriveTester-fndvzobcvvrsxwfjhtiawbpirxmt/Build/Products/**Debug**/…`

It is the shape you get from dragging the built binary in from Finder rather than picking
the helper's product from the target's Products group — so it dates from Step 1.

**Why it went unnoticed until now, and why it matters more than the error message
suggests.** Debug builds copy `Products/Debug → Products/Debug/…app`, so Debug is
*accidentally* correct. Release builds copy `Products/Debug → Products/Release/…app`, which
succeeds whenever stale Debug products happen to exist — and silently embeds the **Debug**
helper in the Release app. Measured: the Release `.app` contains a **958,720**-byte helper,
byte-for-byte the size of the Debug build, against **584,128** for the Release build.
So every "Release builds clean" recorded in Steps 3–5 was true of the app and produced a
Release bundle wrapping an unoptimised helper.

Three consequences:
1. **Release ships a Debug helper.** Relevant now, and load-bearing for Step 16 — the
   embedded binary is the one that gets signed, sealed and notarized.
2. **The build is not reproducible (NFR-MAINT-3).** The path embeds this machine's
   DerivedData hash; the project would not build on another Mac, or after a DerivedData
   reset, which is exactly what exposed it.
3. **It masks itself.** The failure only appears from a genuinely clean state. Another
   entry in this project's running theme: every defect so far came from trusting a
   substitute — here, an incremental build standing in for a clean one.

**Not caused by Step 6**, but it blocks Step 6's Global DoD ("builds Debug **and**
Release").

**FIXED 2026-08-01.** The Embed Helper phase now references
`FE6097482FEECD1D0091C1E0` (`sourceTree = BUILT_PRODUCTS_DIR`) with Code Sign On Copy, and
the stray hard-coded reference is gone — `project.pbxproj` no longer contains the string
`DerivedData` anywhere. Verified from a wiped DerivedData:

| Check | Result |
|---|---|
| Clean Debug build | `** BUILD SUCCEEDED **`, 0 warnings |
| Clean **Release** build | `** BUILD SUCCEEDED **`, 0 warnings |
| What Release copies | `Products/**Release**/com.arc3solutions.USBDriveTester.Helper` |
| Embedded helper size | **584,128** = the Release build (was 958,720, the Debug one) |
| Embedded helper signature | `Identifier=…Helper`, `TeamIdentifier=5JC55GTLZA` |
| Embedded helper contents | contains `acquireDevice` — genuinely the v3 build |

This is the first Release build in the project's history that embeds the binary it was
supposed to. Steps 3–5's recorded "Release builds clean" were true of the app and wrapped
an unoptimised helper.

**An incident during the fix, worth recording.** The GUI instructions issued for it had a
sixth step — "delete any leftover stray reference in the Project navigator" — which did not
distinguish between two objects **with identical names**: the stray `PBXFileReference` (a
built binary) and `FE6097492FEECD1D0091C1E0`, the helper's *synchronized source folder
group*. The folder group was deleted instead. Symptom: `Undefined symbols: _main` — the
helper target had no sources at all, because the group is what feeds `main.swift`,
`DeviceClaim.swift` and `Core/*.swift` into it. It also silently removed the Core files'
`USBDriveTesterTests` membership, since the group carried that exception set.

No source was lost — only project references. Repaired by restoring the four deleted
objects directly in `project.pbxproj` (the exception set, now listing **five** Core files
including `DeviceAccessPrecondition.swift`; the synchronized root group; its entry in the
main group; and the helper target's `fileSystemSynchronizedGroups`), rather than by more
GUI steps that could go the same way. `plutil -lint` passes and the clean builds and tests
above confirm it.

Two lessons: **never issue a delete instruction for an object identified only by a name
that another object also has** — say what kind of object it is and what it looks like. And
a deletion in the Project navigator can remove a *synchronized group*, which is not
recoverable by re-ticking a checkbox the way a membership change is.

### A `pipefail` defect that made a guard fire only when it succeeded (2026-08-01)

**Symptom.** The first real run of `claim-contention-test.sh` aborted at its own preflight:
*"error: the client is not signed under team 5JC55GTLZA"* — while the client sitting on
disk was, verifiably, signed under exactly that team.

**Cause.** `codesign -dvvv "$CLIENT" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID"` under
`set -o pipefail`. `grep -q` exits on the **first match** and closes the pipe; `codesign`
then dies of `SIGPIPE` writing the rest of its (long) output; `pipefail` promotes that
non-zero status to the whole pipeline. **The check therefore failed precisely when the
match succeeded** — an inverted guard, not a flaky one.

**Why the pre-flighting missed it.** The signing path *was* exercised before handing the
script over, and it passed — but as loose commands in a shell **without** `set -o
pipefail`, not inside the script. So what was verified was the commands, not the script.
The same substitution error this project keeps producing, in a new costume.

**The same pattern audited across every script.** Only the `codesign -dvvv` sites are
actually broken; the others (`launchctl print`, `mount`, `printf`, `grep -A6`) return 0
today because their output fits the pipe buffer and the producer finishes before `grep`
exits. Tested rather than reasoned about, since it depends on output size:

| Site | Under pipefail |
|---|---|
| `codesign -dvvv \| grep -q` — claim-contention:139, negative-test:88 | **BROKEN** |
| `launchctl print \| grep -q` — negative-test:59 | OK today |
| `mount \| grep -q` — exclusivity-probe:77 | OK today |
| `printf \| grep -qF` — claim-contention:193, 240 | OK today |
| `… \| grep -A6 \| grep -q` — mount-change-test:83 | OK today |

**Fixed** by capturing first and matching against a here-string, which has no upstream
producer and so cannot `SIGPIPE`. Applied to both `codesign` sites and to
`claim-contention-test.sh`'s two `printf` sites. The three remaining latent uses are left
alone and recorded here: all three fail **closed** (a false non-match reads as a FAIL, not
a PASS), and rewriting working verification code that cannot be fully re-exercised right
now carries its own risk.

**The second site was worse than the first.** `negative-test.sh:88` is the Step 3 security
gate's own anti-vacuousness guard — *"refuse to run this test if the client is signed with
our own Team ID"*. Being inverted, it could **never fire**, which is the single condition
it exists to catch.

**Both fixes proven to discriminate**, in both directions, against a properly-signed and an
adhoc-signed client:

| Client | `claim-contention` guard | `negative-test` guard |
|---|---|---|
| Apple Development, team 5JC55GTLZA | proceeds | **aborts** (correctly: test would be vacuous) |
| adhoc | **aborts** (correctly: results would be transport failures) | proceeds |

**`negative-test.sh` re-run against the live v3 daemon → GATE PASSED.** The helper's log
also settles independently that the installed daemon is the new one:
`exporting TesterControl v3`.

### First real-hardware evidence (2026-08-01, live v3 daemon, `disk4`)

Obtained directly, without the script, using the signed `mount-guard-client`. Both calls
are safe to make with a volume mounted: the readiness check is side-effect-free by
construction, and an acquire with anything mounted is guaranteed to refuse (FR-SAFE-4(a)),
kernel-enforced as well as by policy.

**`checkDeviceReadiness disk4`** — `READY=0`, `MOUNTED_COUNT=1`, `MOUNTED=Test_Drive`,
`HELD=0`, message *"disk4 has 1 mounted volume (Test_Drive). It must be unmounted before a
test can start."* The helper's **independent** mount detection (its own `getfsstat` plus
the IOKit subtree walk) agrees exactly with `mount`, which reports
`/dev/disk4s2 on /Volumes/Test_Drive (exfat …)`. Singular agreement is right too — "1
mounted volume … It must be unmounted".

**`acquireDevice disk4`, with `Test_Drive` mounted** — the FR-SAFE-4(a) path, on hardware:

| Assertion | Result |
|---|---|
| refused | `ACQUIRED=0` |
| cause is **2** (volumes mounted), not 3 | `CAUSE=2` |
| names the volume and the corrective step | *"…the volume Test_Drive is still mounted. Unmount it first — use Unmount All, or unmount in Disk Utility…"* |
| **FR-SAFE-6: nothing was unmounted** | mount count `1 -> 1`, `disk4s2` still on `/Volumes/Test_Drive` |

The message also states FR-SAFE-6 to the user outright — *"Nothing was unmounted for you;
starting a test never changes what is mounted."*

`claim-contention-test.sh`'s output parser was checked against this real output rather than
against assumed output, including the trap where `MOUNTED` could swallow `MOUNTED_COUNT`.
`mounted_volume_count()` and the helper's own count agree (1 and 1).

Still unexercised on hardware: **cause (b)** (needs the `--hold` process under `sudo`, so a
Terminal), a **successful acquire**, **release**, and **release-on-connection-loss** — all
of which require unmounting the scratch drive, which is the script's job under supervision
rather than something to do unasked.

### THE MAJOR FINDING: the helper needs Full Disk Access (2026-08-01)

**Running as root is not sufficient to open `/dev/rdiskN` on an external drive.** This is
not in BUILD-PLAN, the FRs or the NFRs anywhere, and nothing in Steps 1–5 could have
surfaced it — Step 6 is the first time the helper tries to open a device.

**How it presented.** `claim-contention-test.sh` phases C and E failed with
`errno 1 (Operation not permitted)` — with nothing mounted and nothing contending. Both
FR-SAFE-4 causes were correctly excluded, so the refusal fell through to the generic
device-error case.

**The evidence.** `tccd`, at the exact instant of a clean, isolated acquire attempt:

```
08:51:32.318  Handling access request to kTCCServiceSystemPolicyAllFiles,
              from Sub:{com.arc3solutions.USBDriveTester}
              Resp:{…USBDriveTester.Helper, pid=72951, auid=0, euid=0}
              ReqResult(Auth Right: Denied (Service Policy))
08:51:32.320  kTCCServiceSystemPolicyRemovableVolumes denied by TCC
              for com.arc3solutions.USBDriveTester
```

So the raw open is gated by **TCC**, not by uid. Two details matter:

1. **`exclusivity-probe` succeeds at the identical sequence** — claim, then
   `O_RDWR|O_EXLOCK|O_NONBLOCK` — only because `sudo` from Terminal inherits **Terminal's**
   TCC grant. Every exclusivity measurement on 2026-07-30 was made through that borrowed
   permission. The measurements themselves stand (they were about exclusivity semantics,
   which are unaffected); but "a root process can open the raw device" was never true of a
   *daemon*, and was never tested as one.
2. **TCC attributes the request to the app bundle** (`Sub:{com.arc3solutions.USBDriveTester}`),
   not to the helper. So the grant belongs to the containing app and travels with it.

**Ruled out before concluding.** The obvious rival explanation was a claim leaked by the
timeout in phase B poisoning later attempts. Tested directly: with `disk4` remounted
beforehand (which proves no claim was held, since a claim is what prevents mounting), a
single clean acquire on an unmounted, uncontended disk still returned `EPERM`. The helper
has, in fact, **never once successfully opened a raw device**.

**Product change made in response.** `EPERM` now has its own refusal case,
`DeviceAccessRefusal.accessNotPermitted` (cause 7), instead of falling into the generic
device error. The old message read *"the device itself refused the open"* — which sends
someone to check the cable or suspect a failing drive when the fix is a checkbox. It now
names Full Disk Access, the exact System Settings path, and states that administrator
rights are not sufficient (NFR-USE-5). Four tests cover it, including that `EPERM` and
`EACCES` do not collapse into one classification.

**Consequences beyond Step 6 — these need a decision:**

- **Step 7 cannot work without this.** Raw I/O is the entire step.
- **This is a new install-time requirement.** NFR-INST-1 covers guiding the user through
  helper approval; it says nothing about Full Disk Access. Probably wants a requirements
  amendment, like FR-SAFE-5 got.
- **Step 16** must cover it in the clean-machine test: a fresh Mac will deny this by
  default, so "it works here" would be a false pass.
- **The app should detect and guide, not just report.** The refusal message is a stopgap;
  a first-run check that surfaces the requirement before the user reaches a failure would
  be better. Deferred pending the decision above.

### A second defect the same logs exposed: a stranded claim on timeout

Independent of the TCC finding, and real. From `diskarbitrationd`:

```
08:43:56.862  exclusivity-probe  claimed disk /dev/disk4, success
08:43:56.984  …Helper            queued solicitation, disk claim /dev/disk4   (pending)
08:44:02.059  unable to unclaim disk /dev/disk4 (status code 0xF8DA0003)
08:44:02.102  claimed disk /dev/disk4, success                                (43 ms later)
```

The timeout path called `DADiskUnclaim` immediately, on the assumption — written into a
code comment as though established — that this cancels a pending claim so a late grant
cannot strand the disk. It does not. The claim was still *pending*, the unclaim failed
with `kDAReturnBadArgument`, and the grant then landed into a session nobody was watching.

**Fixed.** On timeout the claim box is now *abandoned* rather than discarded: it keeps the
session and disk alive so DiskArbitration can still deliver the grant, and releases it the
moment it arrives (`ClaimOutcomeBox.claimArrived(granted:)`). The session is deliberately
**not** torn down on the timeout path, since tearing it down is what stranded the claim.
Logged when it happens, so the case is observable rather than inferred.

Not yet re-exercised on hardware — it needs a contended claim that later becomes
available, which is exactly what phase B of `claim-contention-test.sh` produces.

### NFR-INST-4 added, and detection built (2026-08-01)

Both approved by the user in response to the finding above.

**Requirement.** `NFR-INST-4` added to the non-functional set, priority **M**, with the
measured `tccd` evidence recorded in that document's new *Amendments to the Baseline*
section. It requires the permission, **and** requires the app to detect its absence and
report it *before* a run is attempted rather than as a run failure. Priority M rather than
S because without it the tool cannot perform its primary function at all — no raw open
means no read, no write-back, no verify. It is a prerequisite, not a degradation.

**Protocol v3 → v4.** `checkDeviceReadiness` gains a `blockingCause`
(a `DeviceAccessRefusalCause` raw value, `0` when nothing blocks). A signature change, so
the bump is mandatory rather than merely cheap — a v3 daemon would decode the reply block
differently. Folded into the existing read-only query rather than given its own method:
it answers the same question that method already asks, and a second privileged entry point
would be the wrong trade (NFR-SEC-3).

**Detection.** `DeviceClaim.fullDiskAccessState(for:)` opens the raw node **read-only** and
closes it immediately — no claim, no `O_EXLOCK`, nothing written, no mount state touched —
so it is safe to run on every selection change. Probing the real device rather than the
usual `TCC.db` proxy is deliberate: it tests exactly the capability needed on exactly the
device needed, and the measured denial named **two** TCC services
(`…AllFiles` *and* `…RemovableVolumes`), only one of which a `TCC.db` probe exercises.

**Classification** is pure and in Core: `FullDiskAccessState` is a three-state enum, not a
`Bool`. The probe is conclusive in only two directions, and `EACCES` in particular must not
read as "denied" — Full Disk Access is not the fix for ordinary filesystem permissions, and
saying so would send the user to grant something that changes nothing. Nine tests.

**Guidance.** The readiness banner shows the explanation and, when the grant is missing,
an **Open Full Disk Access settings…** button. Deliberately separate from the existing
Login Items button: those are different panes and different permissions, neither implies
the other, and being sent to the wrong one is a dead end. Ordering matters too — Full Disk
Access is reported ahead of a mounted volume, since telling someone to unmount when the
permission is *also* missing sends them round twice.

**Verified:** clean Debug tests `** TEST SUCCEEDED **`, **247 test cases** (238 `@Test`
declarations), 0 failures, 0 warnings; clean **Release** build succeeds, 0 warnings; the
CLI client, `negative-client` and `ui-probe` all recompile against v4.

**The first probe was wrong, and hardware caught it (2026-08-01).** With Full Disk Access
*not* granted, the banner showed the mounted-volume message instead of the permission
message. The helper's own log gave the reason immediately —
`readiness check for disk4: ready=false, 1 mounted volume(s), full-disk-access=granted`.

The probe opened `O_RDONLY`, chosen to be maximally side-effect-free. **Reading a raw
device is permitted; only writing is gated.** So it reported `granted` on a machine that
had been granted nothing — a probe that cannot fail on the condition it exists to detect,
which is worse than no probe at all: the banner stays silent and the user still learns the
truth from a failed acquire, which is precisely what NFR-INST-4 forbids.

The same substitution error as the rest of this session, one layer down: a safer stand-in
was chosen for the real operation, and it answered a different question. Note also what
did *not* fail — the app, the wire format, the ordering and the UI were all correct, and
faithfully reported a wrong input.

**Fixed:** the probe now opens `O_RDWR`, matching the acquire's access mode. It still omits
`O_EXLOCK` — the exclusive lock is what makes the acquire *exclusive*, not what makes it
authorised, and taking one here could make a concurrent acquire fail spuriously. It is also
skipped in two cases where it could not answer anyway: while a volume is mounted (the
kernel fails `O_RDWR` with `EBUSY` before TCC is consulted) and while the helper already
holds the device (it demonstrably opened it, and probing would collide with its own lock).

**The probe is advisory; `acquireDevice` remains the authority.** If the inference behind
it — that TCC gates on write access — is wrong in some case, the cost is a silent banner,
not a wrong answer.

**Consequence for the UI flow, worth knowing before testing:** with a volume mounted the
banner reports the *mount* (the actual blocker); the permission message appears once the
device is unmounted. Two steps, but each names the thing that is genuinely in the way at
that moment, and both still come before any run is attempted.

**Wrong a second time, and the flag that actually matters (2026-08-01).** The `O_RDWR`
probe *also* reported `granted`:

```
14:01:54.550  readiness check for disk4: ready=true, 0 mounted volume(s), full-disk-access=granted
```

Three measurements on the same machine, Full Disk Access **not** granted throughout:

| Flags | Result |
|---|---|
| `O_RDONLY` | succeeds |
| `O_RDWR \| O_NONBLOCK` | succeeds |
| `O_RDWR \| O_EXLOCK \| O_NONBLOCK` | **`EPERM`**, with `tccd` denying `…AllFiles` and `…RemovableVolumes` |

**TCC gates `O_EXLOCK`, not the access mode.** Neither reading nor writing is refused —
what is refused is *taking the exclusive lock*, which is the operation that amounts to
claiming ownership of the whole device. Sensible in hindsight, and not what either guess
predicted.

**The probe now uses exactly the flags `acquire` uses.** The cost is a lock held for the
microseconds between `open` and `close`; a concurrent acquire in that window would see
`EBUSY` and report cause (b). Accepted, and bounded by the two existing skips (mounted, or
already held by us).

**The lesson, stated plainly because it has now cost two rounds:** every approximation of
the real operation reported success on a machine where the real operation fails. First
`O_RDONLY` because it was maximally side-effect-free, then `O_RDWR` because "write access
must be the trigger" — reasoning, not measurement. This is the project's recurring theme
appearing at the level of a single `open(2)` flag. **Probe with the exact call.**

### The faithful probe had to be abandoned — it remounted the drive (2026-08-01)

Fixing the probe to use `O_EXLOCK` made it correct and simultaneously made it harmful.
Measured immediately after an Unmount All:

```
14:47:00.184  unmounted disk /dev/disk4s2, success
14:47:00.185  app: "Unmounted every volume on disk4: Test_Drive."
14:47:00.198  readiness check … full-disk-access=granted   <- the probe opened and closed
14:47:00.202  probed disk /dev/disk4s1 …                   <- 4 ms later
14:47:00.425  mounted disk /dev/disk4s2, success           <- the user's unmount undone
```

**Releasing an exclusive lock makes DiskArbitration re-probe and remount** — the same
behaviour measured on 2026-07-30 for a released `DADiskClaim`, reproduced with `O_EXLOCK`
instead. A readiness check that is documented as safe to poll was quietly defeating
FR-SAFE-5: press Unmount All, and the volume returns a heartbeat later. Strictly worse
than the bug it fixed, because it broke a working feature.

**The genuine conflict.** `O_EXLOCK` is the only device open that reaches the TCC gate, and
touching `O_EXLOCK` remounts the drive. The faithful test cannot live in a polled check.

**Resolution.** The probe no longer touches the device at all: it opens the protected TCC
database read-only and closes it, never reading a byte. That is gated by exactly the grant
the user makes (`kTCCServiceSystemPolicyAllFiles`), and nothing about it can cause a mount.

**This is a proxy, and the file says so.** Three device probes were wrong before it, so the
limits are stated rather than glossed: it establishes whether the *app holds Full Disk
Access*, not whether *this device* can be opened. `acquire` remains the only authority and
still reports the condition precisely from the real open. The probe is permitted to be
silent when it should not be; it is not permitted to remount a drive.

**The pattern, four probes in.** `O_RDONLY` (too weak), `O_RDWR` (still too weak),
`O_RDWR|O_EXLOCK` (faithful, unusable), and finally a non-device check with its limits
declared. Each earlier version was chosen by reasoning about what *ought* to trigger TCC;
each was settled by reading `diskarbitrationd` and `tccd` logs. **The logs answered every
question that reasoning got wrong.**

### An earlier remount, which was Finder rather than the app

Reported as "the volume remounts very quickly after unmounting", which looked like the
measured auto-remount-on-claim-release. It is not. `diskarbitrationd`:

```
14:01:54.148  USBDriveTester  disk unmount, /dev/disk4, options = 0x1 (Whole)   <- our button
14:01:54.420  app log: "Unmounted every volume on disk4: Test_Drive."
14:01:54.550  readiness: ready=true, 0 mounted volume(s)                        <- banner updated
   … 30 seconds pass, disk stays unmounted …
14:02:23.975  Finder [694]   disk eject, /dev/disk4
14:02:25.253  mounted disk /dev/disk4s2, success                                <- re-probe + auto-mount
```

**FR-SAFE-5's control works**, and the banner refreshed correctly within 130 ms. What
remounts the drive is a Finder **eject** on a device that cannot actually be detached:
DiskArbitration re-probes the media and auto-mounts it ~1.3 s later. The same pattern
appears twice in the log, each time following a Finder eject and never following our
unmount.

Worth keeping for Step 12 (device loss) and for the user-facing guidance: *unmount* and
*eject* are different operations here, and eject is counter-productive — it puts the volume
straight back.

### THE GUARD WORKS END TO END ON HARDWARE (2026-08-01)

With Full Disk Access granted to `USBDriveTester` and `disk4` unmounted, against the live
v4 daemon:

```
[check]   READY=1  MOUNTED_COUNT=0  HELD=0  BLOCKING_CAUSE=0
[acquire] ACQUIRED=1  CAUSE=0
          "Exclusive whole-disk access to disk4 is held: no volumes are mounted, the
           DiskArbitration claim is in place so the system cannot remount them, and
           /dev/rdisk4 is open exclusively."
[check]   HELD=1  BLOCKING_CAUSE=6
          "This app holds exclusive access to disk4. Release it before starting another run."
[release] RELEASED=1
          "Released exclusive access to disk4: the raw device was closed and the
           DiskArbitration claim dropped."
```

`disk4` then remounted normally. That discharges, on real hardware: the **successful
acquire** (FR-SAFE-3), **release restoring normal use**, the `alreadyHeld` cause
(FR-CTRL-9) with its own message, and the readiness check reporting held state correctly.

**Full Disk Access was the whole of it.** Once granted, the helper opens
`O_RDWR | O_EXLOCK | O_NONBLOCK` without complaint. NFR-INST-4 is confirmed as a genuine
hard prerequisite rather than an artefact of some other misconfiguration.

**Two false alarms in the same round, both mine, both worth recording:**

1. *"Unmount All fails"* — it did not. With the grant already in place there was no
   permission warning left to show, so the banner correctly read "disk4 has no mounted
   volumes…". The instruction to expect a permission message was written against a stale
   assumption about the machine's state, not against what was actually configured.
2. A `TRANSPORT_ERROR` on the first attempt to test this: the CLI client had been
   recompiled for v4 and not re-signed, so it was adhoc and the helper refused it —
   the Step 3 security gate working exactly as designed, mistaken for a fault.

**Still to verify:** the corrected `O_EXLOCK` probe (the installed build predates it, and
with the grant in place every probe variant agrees, so it can only be distinguished by
temporarily revoking Full Disk Access), phase B's cause 3 under the fixed harness, and the
stranded-claim fix.

**Note for Step 16:** re-registering the helper no longer prompts for approval on this
machine. That is the stable `BTM uuid` remembering prior consent, recorded in Step 4. A
clean Mac **will** prompt, so approval cannot be regarded as tested here — exactly the
false-pass hazard NFR-INST-2's clean-system clause exists to catch.

### `claim-contention-test.sh disk4` — FULL PASS (2026-08-01)

All four phases, 12/12 checks, against the live v4 daemon on the real exFAT scratch drive.

| Phase | Result |
|---|---|
| **A** — volumes mounted | refused, `CAUSE=2`, names `Test_Drive`, **mount state unchanged** (FR-SAFE-6) |
| **B** — unmounted, another process holding | `MOUNTED_COUNT=0` with `CAUSE=3`, message names another process |
| **C** — unmounted and free | `ACQUIRED=1`, then `HELD=1`/`CAUSE=6`, then `RELEASED=1` |
| **E** — connection loss | acquired, client exited without releasing, helper then holds nothing |

**Phase B is the one that matters most.** `MOUNTED_COUNT=0` paired with `CAUSE=3` is the
whole point of the step: both underlying failures are the same `EBUSY`, and only the mount
check separates them. Cause 2 and cause 3 have now each been produced on hardware, from the
same device, minutes apart.

**The three fixes made during this session were all exercised**, confirmed from the helper's
own log rather than inferred from the script's verdict:

- **Stranded claim on timeout** —
  `late DiskArbitration grant for disk4 arrived after the claim had timed out; released it
  immediately so it cannot strand the disk`. Phase B produces exactly the contended-then-
  released claim that caused the original defect, and the fix fired on it.
- **Full Disk Access probe** — `full-disk-access=granted` on every check, with the grant in
  place. No false warning, and the TCC-database proxy does inherit the app's grant when
  called from the helper, which had been an open question.
- **The remount regression** — a readiness check on an unmounted disk is now followed by
  the acquire, not by a re-probe. The drive stays unmounted.

**Release-on-connection-loss corroborated twice over.** The helper logged
`released on connection loss from pid 81836`, and phase E's follow-up check reported
`MOUNTED_COUNT=1` — the volume came back, which can only happen once the claim is genuinely
gone. State evidence and log evidence agreeing is stronger than either alone.

**Geometry sanity, incidentally confirmed:** the acquire logged
`IOKit reports 1000204886016 bytes in 512-byte blocks` for `disk4`, matching Step 5's
recorded figures exactly.

### Verification Gate — status

- [x] **Mounted volume ⇒ refusal naming the volume** (FR-SAFE-4(a)) — phase A, on hardware.
- [x] **Unmounted but held ⇒ "device node is claimed", distinct from the above**
      (FR-SAFE-4(b)) — phase B, on hardware.
- [x] **On success the helper holds claim + exclusive `rdiskN` open; releasing makes the
      disk normally usable again** — phase C, and the volume remounted afterwards.
- [x] **The write path has an enforced guard, verified by a check that trips when access is
      absent** (NFR-REL-3) — `WritePrecondition`, exhaustive over all 8 grant/target
      combinations; exactly one permits a write.
- [x] **Nothing mounts or unmounts implicitly** (FR-SAFE-6) — phase A asserts the mount
      count is identical before and after a refusal.
- [x] **Mount/unmount control (FR-SAFE-5/6/7)** — closed 2026-08-01. The label/enabled
      matrix is exhaustively unit-tested (15 tests over the full cross-product), and all
      three interactive parts are now confirmed: **Unmount All** unmounts and the label
      flips to **Mount All**; **Mount All** remounts `Test_Drive` and the label flips back
      — the genuinely new half of the FR-SAFE-5 amendment, exercised for the first time; a
      **failed unmount** (forced by holding a file open on the volume) names the volume
      *and* the reason (NFR-USE-5); and the **no-selection** state renders disabled with
      the default label "Unmount All" plus a stated reason.

      The no-selection state was verified by **render**, not by clicking. It is reachable
      only with no USB drive present at all — clicking blank space in the list is a
      deliberate no-op, because the selection binding discards `nil` so that a stale tap
      arriving as a device disappears cannot silently deselect (Step 5). Confirming it on
      this machine would have meant unplugging every USB device, one of which holds the
      source tree, so `scripts/render-ui.sh … empty` was added: it drives `DeviceListView`
      through an empty `DeviceSource`, which is the one state hardware here cannot
      produce.
- [x] **Global DoD** — clean Debug **and** Release builds, zero warnings; 247 test cases,
      0 failures.

### Outstanding before the gate can close

- [x] **Fix the Embed Helper phase** (above) — done 2026-08-01; clean Debug **and**
      Release both build with zero warnings, and Release now embeds the Release helper.
- [x] **Install and register the helper** — done 2026-08-01. `install-app.sh` installed the
      Debug build; both signatures carry `TeamIdentifier=5JC55GTLZA`. Verified from the
      binaries themselves that the helper contains `checkDeviceReadiness`/`acquireDevice`/
      `releaseDevice`, `DeviceClaim` and `WholeDiskName`, and that the app's code (which
      lives in `USBDriveTester.debug.dylib`, not the 59 KB launcher stub) contains the
      Step 6 UI. The daemon is registered and its own log reports
      `exporting TesterControl v3`.
- [x] **`./scripts/claim-contention-test.sh disk4` — run on hardware 2026-08-01.**
      Phase A **4/4 PASS** (cause 2, names the volume, FR-SAFE-6 holds). Phase B **3/4** —
      including the assertion the whole step exists for: `MOUNTED_COUNT=0` with `CAUSE=3`,
      cause (b) correctly told apart from cause (a) when both are the same `EBUSY`
      underneath. Its 4th check failed on a **harness** bug, not the product (below).
      Phases C and E failed on the Full Disk Access finding above.
- [x] **Harness bug in phase B fixed** — `value_of()` is now scoped by command. It had
      taken the *first* matching line, so `MESSAGE` resolved to the **check** message
      ("…confirm no **other** process holds the device") rather than the acquire refusal
      ("…held by **another** process"). The product was right; the assertion read the wrong
      line. Phase A's equivalent check had passed only because both messages happen to
      contain the volume name — luck, not correctness. Re-run: PASS.
- [x] **Full Disk Access granted; helper re-registered from `/Applications`.**
- [x] **Stranded-claim fix re-verified** on the hardware path that produced it (phase B).
- [x] **Interactive GUI items — all confirmed 2026-08-01.** Mount All, the failed-unmount
      message, the label toggling in both directions, both refusal messages, release
      restoring normal use, and the no-selection state (by render).

---

## Step 6 — COMPLETE (2026-08-01)

Every gate item is discharged. Summary of what the step delivered and what it cost.

**Delivered.** A helper-side mount guard that refuses a run unless every volume is
unmounted *and* it holds both a DiskArbitration claim and an `O_EXLOCK` open, telling the
two FR-SAFE-4 causes apart when the kernel reports both as the same `EBUSY`; a write-path
guard that is a type rather than a flag (`AcquiredDevice` is constructible only by a
successful acquire, and `WritePrecondition` re-checks at runtime what the type system
cannot see); a bidirectional Mount All / Unmount All control whose label and action are one
decision; and protocol v4.

**Requirements changed by this step.** FR-SAFE-5 revised and elevated C→M, FR-SAFE-6 and
FR-SAFE-7 added (all 2026-07-30, during scoping); **NFR-INST-4 added 2026-08-01**, the
Full Disk Access requirement, discovered only because Step 6 is the first step in which the
helper opens a device.

**Defects found in code that pre-dated this step:**

1. **The Embed Helper build phase** referenced a hard-coded DerivedData path, so every
   Release build since Step 1 embedded the *Debug* helper, and the project would not build
   on another machine (NFR-MAINT-3). Found only by building Release from a wiped
   DerivedData.
2. **`negative-test.sh`'s anti-vacuousness guard was inverted** by a `pipefail` +
   `grep -q` interaction, so the one condition it exists to catch could never fire. Present
   since Step 3.

**Defects found in this step's own code, all on hardware:** a stranded DiskArbitration
claim on the timeout path; a readiness probe that remounted the drive 4 ms after the user
unmounted it; and three successive versions of the Full Disk Access probe that reported
`granted` on a machine that had been granted nothing.

**The thread running through all of it.** Every one of those was found by reading
`diskarbitrationd`, `tccd` or the helper's own log, and every one had first been reasoned
about incorrectly. The project's standing lesson — never report a substitute's result as
the real thing — held at every scale this step, from a whole build configuration
(Debug helper standing in for Release) down to a single `open(2)` flag (`O_RDONLY`, then
`O_RDWR`, standing in for `O_RDWR|O_EXLOCK`). Logging that names the actual cause was what
made each one findable; NFR-OBS-1 paid for itself several times over.

**Carried into Step 7.**

- The helper must hold Full Disk Access or nothing works. Step 7's raw I/O is the whole
  point of the step, so this is a prerequisite, not a footnote.
- `AcquiredDevice.fileDescriptor` is the already-open, already-exclusive descriptor Step 7
  adds `F_NOCACHE`, `F_GLOBAL_NOCACHE` and the geometry ioctls to. It is opened
  `O_RDWR | O_EXLOCK | O_NONBLOCK`, as BUILD-PLAN Step 7 was amended to require.
- IOKit's geometry is recorded on `AcquiredDevice.geometry` and labelled provisional;
  Step 7's ioctls are the authority and BUILD-PLAN says to prefer them. The acquire log
  already prints it (`1000204886016 bytes in 512-byte blocks` for `disk4`) so the two can
  be compared directly.
- Releasing an exclusive lock or a claim makes macOS remount within milliseconds. Any Step 7
  code that opens and closes the raw device outside a held acquire will undo the user's
  unmount.
- **The test target is `disk4`, and disk images are no longer offered as an option.**
  BUILD-PLAN suggested attaching a disk image as a safer stand-in in Steps 7, 8 and
  Appendix B; that could never have been followed, because discovery lists USB
  mass-storage whole disks only and an image reports
  `Physical Interconnect == "Virtual Interface"` (measured, Step 5). The helper's own
  identity re-check would refuse it too. Amended 2026-08-01 by user decision: all
  real-hardware I/O uses `disk4`, whose contents are expendable, and a new "Test hardware"
  section near the top of BUILD-PLAN states this once for every step rather than per-gate.

  Recorded alongside it, because it is the part that is easy to misread: the drive being
  expendable relaxes the *consequence* of a bug, not the discipline. NFR-REL-1 still
  requires non-destructiveness to be proven in simulation before hardware (Step 8's gate),
  and FR-TEST-7 still requires the engine to write back the bytes it read rather than any
  pattern.

**State at completion.** Protocol v4. 247 test cases, 0 failures, zero warnings from clean
Debug **and** Release builds. Helper installed from `/Applications` and registered.
`claim-contention-test.sh disk4` passes 12/12.

### Also found: the registered daemon was running from DerivedData, not `/Applications`

`tccd` logged the helper's `binary_path` as
`…/DerivedData/USBDriveTester-…/Build/Products/Debug/USBDriveTester.app/Contents/MacOS/…`
— so the `SMAppService` registration in force was a stale one from an Xcode run, not from
the `/Applications` install. Step 3 recorded this exact hazard and added
`scripts/install-app.sh` because of it; it recurred anyway.

It did not invalidate the results above — that binary was rebuilt during this session and
was genuinely v3 (its log says `exporting TesterControl v3`) — but it must be corrected
before anything else, for two reasons: DerivedData is wiped routinely during clean-build
verification, which would delete the running daemon's binary out from under it; and a TCC
grant attaches to a bundle, so granting Full Disk Access to `/Applications/USBDriveTester.app`
while the daemon runs from DerivedData is at best confusing.

---
