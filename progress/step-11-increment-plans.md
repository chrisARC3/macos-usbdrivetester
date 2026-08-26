# Step 11 — increments 9, 10 and 11, planned and approved

**Written 2026-08-25/26, before any code.** Every decision below was taken by the user during
scoping and is **settled**. This file exists so a cold session can execute them without
re-deriving them, and without re-opening choices that were already argued through.

**This is a plan, not history.** When an increment is built, its full account goes in its commit
message and its summary into `PROGRESS.md`, as always. Delete the section from here when it lands.

> **Read `CONSTRAINTS.md` and `PROGRESS.md` first.** This file assumes both. It carries only what
> is not yet anywhere else.

---

## Where this came from

Increment 8 ended with the negotiated USB link speed moved into the **Selected device** pane and
the standing backup advice deleted from it. Walking the human checklist for that change
(chunk 12, passed in full 2026-08-25, `e0f4415`) put the user in front of the pane and the metrics
panel, and three separate requests came out of it:

1. the **readiness banner** is legacy and should go — mounted volumes are named in three places;
2. the **helper being unreachable** is app-wide and fatal, and does not belong in a per-device pane;
3. **Covering** is mislabelled, the row should go, and the metric the user actually wants does not
   exist.

Those became increments 9, 10 and 11. They are ordered so that **the two app-only increments land
before the one that costs a protocol version**.

---

## Increment 9 — the launch-time helper gate

### What it is

A new **pure** type, `HelperAvailability`, and one modal raised at launch. The type is a plain enum
plus a pure function; no SwiftUI, no XPC, no I/O in it.

```swift
static func diagnose(status: SMAppService.Status,
                     version: Result<ProtocolVersionCheck, Error>?) -> HelperAvailability
```

Resolved **in this order**, mirroring the helper's own "ordered by what the user must fix first"
rule in `main.swift`'s readiness check:

| # | Condition | Case | Actions |
|---|---|---|---|
| 1 | `.notFound` | `.notFound` | **Quit** |
| 2 | `.notRegistered` | `.notRegistered` | Register Helper · Quit |
| 3 | `.requiresApproval` | `.requiresApproval` | Open Login Items… · Quit |
| 4 | `.enabled`, version `.failure` | `.unreachable(detail:)` | Retry · Quit |
| 5 | `.enabled`, `.mismatch` | `.versionMismatch(helper:app:)` | Register Helper · Quit |
| 6 | `.enabled`, `.match` | `.available` | *none — no modal* |

**Each case carries its own actions.** The modal therefore contains no branching, which is what
makes the whole decision unit-testable — the thing the banner it replaces never was.

### Why it is not Quit-only

The user's first proposal was a fatal modal offering **only Quit**. That was rejected on evidence,
by the user, once the evidence was shown:

* `Button("Register helper")` lives at `HelperDiagnosticsView.swift:140` — **inside this app**.
* `SMAppService.openSystemSettingsLoginItems()` is called from `HelperRegistration.swift:249`.

A Quit-only modal produces **quit → relaunch → still not registered → same modal → quit**, with the
dialog's own remedy text naming a window the dialog prevents reaching.

**`.notFound` is the only genuinely Quit-only state** — the daemon plist is missing, which is a
broken install and nothing in-app can repair. A **version mismatch is NOT Quit-only**: the project's
own wording, `ProtocolVersionCheck.mismatch.description`, already prescribes *"Re-register the
helper so the installed daemon matches this app."*

### Why it is diagnosed app-wide, not from a failed readiness call

`readinessError` — the string the deleted banner showed — comes from `withProxy`'s error handler in
`HelperConnection.swift`, which catches **any** XPC transport error. The code's own comment names
them: *"no helper, wrong version, connection dropped"*. It therefore conflates five conditions,
including a **transient blip while the daemon restarts** — which `install-app.sh` warns happens on
every helper change. A fatal modal fired on that would go off during a routine reinstall.

`SMAppService.status` is a **local** query needing no daemon, and `checkProtocolVersion` is
NFR-MAINT-1's handshake. Together they separate all five. A failed per-device call separates none.

`AppModel.swift:25` already carries this lesson in its own words, about `helperHoldsDevice`:

> deleted rather than fixed. It was written from `checkDeviceReadiness`'s `helperHoldsThisDevice`,
> a *per-device* answer, and read at every use site as "the helper holds *some* device".
> **Do not reintroduce a selection-scoped flag.**

### The modal is declarative, not an event

Shown whenever `helperAvailability != .available`. Every action re-runs `diagnose` and rewrites the
state. It disappears only when the state reaches `.available`, or the app quits.

Three consequences, all wanted:

* **Escape is harmless** — a dismissal re-raises it, because the modal is a function of state.
* **Register Helper chains naturally** — `.notRegistered` → press → re-diagnose → `.requiresApproval`
  → *"Open Login Items…"*. The user is walked forward one step at a time.
* **The app cannot be entered in a broken state**, which is the property the user asked for, without
  the dead end.

### The one edit to working code

`HelperDiagnosticsView.swift:86` owns its own registration:

```swift
@State private var registration = HelperRegistration()
```

The gate needs `register()` too, and a second instance would be **two registration states that can
disagree** — exactly what `USBDriveTesterApp.swift:126` warns about when it explains why the
diagnostics panel is a `Window` and not a `WindowGroup`.

So **`HelperRegistration` moves to `AppModel`**, which already owns *the* `HelperConnection` for the
same reason, and the diagnostics view receives it. That is one argument back into a call site whose
comment notes it has seven fewer than it used to. **User approved 2026-08-26**, having been shown
the trade.

### Files

**New — no Xcode work** (file-system synchronized groups):

* `USBDriveTester/HelperAvailability.swift`
* `USBDriveTesterTests/HelperAvailabilityTests.swift`

**Modified:**

* `AppModel.swift` — owns the registration, holds `helperAvailability`, runs the check
* `HelperDiagnosticsView.swift` — takes the registration instead of constructing one
* `USBDriveTesterApp.swift` — passes it through; attaches the modal to `ContentView`
* `tools/ui-probe/main.swift` + `scripts/render-ui.sh` — new `helper-gate` case, **31 → 32**
* NFR amendment (NFR-INST-1 gains a surface), `PROGRESS.md`, `CONSTRAINTS.md`, checklist chunk

### The gate

**Unit tests** — every status × version outcome maps to the specified case; every non-available case
offers Quit; **only `.notFound` offers Quit alone**; `.available` offers nothing; and, mirroring
`everyRefusalInTheWholeTableIsASentence` in `PreRunControlsTests`, **every message is a sentence that
names a corrective step** (NFR-USE-5).

**Mutations, with predictions stated in advance** as the project's rules require:

| | Mutation | Prediction |
|---|---|---|
| M1 | `.requiresApproval` → `.available` | caught by the mapping tests |
| M2 | drop Quit from `.notFound` | caught by the actions test |
| M3 | reorder so `.notRegistered` beats `.notFound` | caught by the mapping tests |
| M4 | **the modal is never presented at all** | **EXPECTED TO SURVIVE** — view wiring has no unit cover |

M4 is the honest one, and it is why this increment needs a human chunk rather than a green suite.
It is the same blind spot the link speed had.

**Builds** — clean Debug *and* Release, zero Swift source warnings. **Clean, not incremental**: an
incremental build does not re-emit warnings for files it did not recompile, and a bare grep for
`warning:` also matches `appintentsmetadataprocessor` lines naming no `.swift` file.

**Renders** — the new `helper-gate` case, light and dark.

**Human** — a normal launch shows **no modal**, plus two induced states, both reversible from inside
the app. **Ask the user before either; both temporarily disable the helper, and neither touches a
drive:**

* **`.notRegistered`** — unregister from the diagnostics window (NFR-INST-3), relaunch. Undone by the
  modal's own Register Helper button.
* **`.versionMismatch`** — bump `TesterProtocol.version`, build, install the app **without restarting
  the daemon**. The running daemon still answers v12 while the app expects v13. That is the exact
  real-world scenario the state exists for, and it is undone by rebuilding.

---

## Increment 10 — FDA moves to Start; the readiness banner and the Covering row are deleted

### The readiness banner, branch by branch

`DeviceListView.readinessBanner(for:)` renders five mutually exclusive states, driven by the
helper's `blockingCause`. The user's request was to delete it; the analysis found only two branches
load-bearing:

| State | What it says | Decision |
|---|---|---|
| **Volumes mounted** | *"…has 3 mounted volumes (…). They must be unmounted before a test can start."* | **DELETE — it is now false.** Start owns the unmount since increment 5, so this instructs the user to do what the app does, wearing an `exclamationmark.shield` on a healthy drive |
| **Ready** | *"…has no mounted volumes. Exclusive access has not been attempted yet…"* | **DELETE** — a paragraph saying nothing is wrong |
| **Already held** | *"This app holds exclusive access to diskN…"* | **DELETE** — `DeviceListView.swift:210` sets `.selectionDisabled(discovery.isRunActive)`, so the other-device case is unreachable; the same-device case restates a visibly running run |
| **Checking…** | transient spinner text | **DELETE** |
| **Full Disk Access** | the message **and the button** | **MOVES to Start** — see below |
| **Helper unreachable** | *"The helper could not be asked… ⇧⌘D"* | **Superseded by increment 9** |

Once increment 9 has landed and FDA has moved, **every branch has a home or is dead**, so
`readinessBanner(for:)`, `readiness`, `readinessError`, `refreshReadiness()` and both `.onChange`
triggers all go. The `.onChange(of: mountedVolumeNames)` trigger exists solely to keep the
mounted-volumes message fresh and has no surviving dependant.

### FDA moves into the preparation sequence

**Decision A, taken 2026-08-26**, over the alternative of making Start's gate asynchronous.

A new injected operation in `DevicePreparationOperations`, **placed before `unmount`**. On denied,
`.aborted` with `restore: nil` — the case `DevicePreparationFailure` already documents as *"nothing
had been unmounted yet — which is a different fact from 'the rollback succeeded' and must not read
as one."* No new type is needed.

**The ordering is not optional.** If the check runs after the unmount, a multi-volume drive is taken
down, the modal says Cancel, and the volumes are remounted for nothing.

The heading goes in `OutcomePresentation` as a new case beside `.unmount` / `.mount` / `.acquire` /
`.release`, so the compiler enforces every use site. That file already owns *"what does a failed X
call itself"*, and two copies of that sentence is the drift it exists to prevent.

**The modal: "Open Full Disk Access Settings…" · "Cancel Test".** Two buttons, **decided
2026-08-26** after the user's initial one-button proposal. NFR-INST-4 is **M (Mandatory)** and its
third clause is *"guide the user to System Settings › Privacy & Security › Full Disk Access"* — a
message naming the path satisfies the letter, so one button would not have breached it, but it would
delete a working one-click remedy and contradict the remedy-first choice made for increment 9.

`HelperRegistration.openFullDiskAccessSettings()` keeps a caller — now the modal. Before this
increment its **only** caller is `DeviceListView.swift:606`.

### Why moving it is an improvement, not just a relocation

1. **It gains 60 tests.** In view code the FDA check has *zero* cover — any mutation survives all
   1025 tests. `DevicePreparation.swift`'s own header says a test *"builds this with stubs and
   asserts which of them ran, in which order, and which did not."* Cover today:
   `DevicePreparationTests` (20 `@Test`) + `RunControllerTests` (40).
2. **The answer becomes fresh.** The pane's verdict is a snapshot from selection time, refreshed only
   on selection change and mount change — **grant FDA with the app open and the pane never notices.**
3. **`DevicePreparationOperations` has only two construction sites** — `RunControllerWiring.swift`
   and `DevicePreparationTests.swift` — so adding a field is cheap.

**FDA is not per-device.** The grant is machine-wide for the helper binary; what is per-device is
only the moment it bites. The helper's message is already app-scoped, so nothing needs rewording.

**An inconclusive probe already behaves correctly.** `needsFullDiskAccess` is true only when the
state `isDenied`, so a `.unknown` probe will not raise the modal; the run proceeds and `acquire`
refuses if it must. Pin this with a test rather than assuming it.

### The Covering row is deleted

**Decided 2026-08-26.** It is always equal to the slower of Read and Write — necessarily, not
coincidentally — and the time-remaining estimate is what the figure was for. See increment 11 for
the full argument.

**Safe for the ETA**: `estimatedRemaining` is computed helper-side in `RunMetrics` from
`rangeBytesCovered` and arrives as its own wire field. The internal quantity stays; only the display
goes. **No protocol change.**

The definition paragraph in `RunMetricsView` must be rewritten with it — it currently explains the
Read ≈ 2 × Covering ≈ 2 × Write relationship, and two of those three names are changing.

### The gate

* **New tests**: the FDA check runs **before** the unmount; `unmount` never ran on refusal; `restore`
  is nil; an `.unknown` probe does **not** abort
* All **60** existing preparation/controller tests still green
* `window-fit-check.sh --limits` **re-measured** — NFR-USE-9, measured not estimated. The pane loses
  an estimated 55–60 pt at the 3-volume fixture against a 613 pt worst case; **that estimate is from
  line counts and must not be reported as a measurement**
* `devices*` and `content*` renders re-taken
* Requirements amendment: NFR-INST-4 rehomed and still discharged
* A new human checklist chunk

**No protocol change. v12 stands, helper source hash unmoved, app target only.** `DeviceReadiness`
keeps arriving over the wire with fields the app stops reading.

---

## Increment 11 — `R-W-R-C speed`, protocol v13

### The finding that produced it

The user observed from the metrics panel that **Covering always equals Write** and judged it
suspicious. It is not an implementation error — the two share a numerator and a denominator, because
a cycle writes each covered byte exactly once, so for N bytes in wall time T: Read = 2N/T,
Write = N/T, Covering = N/T.

But the user then insisted the term be defined **without using the word "covered" in it**, and that
exposed a real discrepancy. `RunMetrics.swift:118`:

> `rangeBytesCovered` and `currentBlock` count **attempted** work, not successful work.

So the displayed figure is **sectors attempted per second**, under a label that plainly reads as
successful work.

**The arithmetic is right for both its consumers.** The ETA denominator and the progress fraction
(`min(1, rangeBytesCovered / deviceBytesTotal)`) each *need* attempted — otherwise a drive with a bad
region shows a bar that never reaches 100% and an ETA that never converges. **The defect is the
name**, which is why increment 10 deletes the row rather than changing the number.

### The new figure

**Bytes whose chunk outcome is `.completed`, per second**, divided by running time to match the other
displayed rates.

**Only `.completed` counts.** From `RetentionRun.swift:635` there are five outcomes:

| Outcome | Counts? | |
|---|---|---|
| `.completed` | ✅ | all four steps, compare passed |
| `.verifyMismatch` | ❌ | all four ran, **bytes differed** — the failure this tool exists to find |
| `.failedReading` / `.failedWriting` / `.failedVerifying` | ❌ | I/O stopped partway |

⚠️ **`.verifyMismatch` is deliberately not an `isPhaseFailure`.** A bare `!isPhaseFailure` test would
score a retention failure as a success. It must be excluded explicitly.

The quantity exists nowhere today. `bytesVerified` is **not** it — it counts bytes that completed a
verify *read*, and a `.verifyMismatch` still adds to it.

### The name

**`R-W-R-C speed`**, the user's own. **Not "Progress speed"** — the progress bar and the ETA are both
driven by attempted bytes, so that name would promise `ETR = remaining ÷ rate` and break it
**precisely when a drive is failing**, which is the one time anyone looks hard. That is the same
class of error as the mislabel this increment exists to fix.

*"Verified throughput"* was considered as plainer English and set aside — it risks reading as "the
verify phase only", which is a third thing again.

### Know this before building it

**On a healthy run, `R-W-R-C speed` will read exactly the same as Write** — successful bytes =
attempted bytes = written bytes when nothing fails. Deleting Covering for duplicating Write and
adding a figure that also duplicates Write does **not** remove the duplication. It makes it *mean*
something: a divergence now says "a chunk failed I/O **or** the data came back wrong", where
Covering's said only "a write did not happen". The user was told this and accepted it.

**Keep Write.** It and Read are what reconcile against Activity Monitor — the property added after
the 2026-08-17 defect report, when v11's phase-isolated figures read 1.5× and 3.4× high.

### The cost — the reason this increment is last

* new accumulator in `RunMetrics`, new wire field → **protocol v12 → v13**
* **helper source hash moves** (currently `73990c90d6a5b43a9dc2b3791284b33501acbe7f6752c38bfdde266b9d696cbb`)
* **13 gate clients** rebuilt via `build-tools.sh`
* `metrics-check.sh` and `retention-cycle-check.sh` both assert v12 explicitly
* daemon restart, and the **Step 10 hardware gates re-run**

---

## Settled — do not re-open

| Decision | Date |
|---|---|
| Remedy-first, not Quit-only; `.notFound` alone is Quit-only | 2026-08-26 |
| The gate fires at **launch/initialization** | 2026-08-26 |
| Diagnosed from `SMAppService.status` + the version handshake | 2026-08-26 |
| FDA stays a Start-time check (**option A**, inside preparation) | 2026-08-26 |
| The FDA modal has **two** buttons | 2026-08-26 |
| Increment 10 keeps the FDA move and the banner deletion **together** | 2026-08-26 |
| The `Covering` row is deleted; `R-W-R-C speed` is a separate increment | 2026-08-26 |

**The user was warned that a launch-time fatal modal costs the helper-free link-speed check** —
enumeration, capacity, serial and link speed are all app-side IOKit reads and work without the
helper — and chose launch anyway. That trade is made; do not re-raise it.
