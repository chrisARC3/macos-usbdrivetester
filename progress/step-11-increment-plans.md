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

> **Increment 9 landed on 2026-08-27 and its section has been deleted from this file**, as the
> header above instructs. Its account is in `PROGRESS.md` and in its commit message. Two things it
> settled that increment 10 depends on: the **helper-unreachable** branch of the readiness banner is
> now superseded in fact rather than in plan, and `HelperRegistration` lives on `AppModel`.
> Six decisions this plan did not cover were taken during its scoping — the one worth knowing here
> is that an app-wide **trigger** belongs in `USBDriveTesterApp.swift`, which no harness compiles,
> while the **presentation** belongs on `ContentView`, which all three do. See CONSTRAINTS section 2.

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
| **Helper unreachable** | *"The helper could not be asked… ⇧⌘D"* | ~~Superseded by increment 9~~ **ALREADY DELETED, 2026-09-01** — see the note below |

Once increment 9 has landed and FDA has moved, **every branch has a home or is dead**, so
`readinessBanner(for:)`, `readiness`, `refreshReadiness()` and both `.onChange` triggers all go.
The `.onChange(of: mountedVolumeNames)` trigger exists solely to keep the mounted-volumes message
fresh and has no surviving dependant.

> **The helper-unreachable branch and `readinessError` are already gone** (user decision,
> 2026-09-01). They were not merely redundant once the gate landed — they were **wrong**, and the
> user reported the message three times while walking chunk 13: it is a snapshot taken at selection
> time, refreshed only on selection change and mount change, so a helper fixed *afterwards* left the
> message standing over a working helper, with ⇧⌘D showing `enabled` beside it. Deleted early rather
> than ship another session with a banner that lies. A failed readiness check now shows nothing.
> **The rest of this section still applies unchanged** — there is simply one fewer branch to delete.

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

## Increment 12 — ⌘Q works under every sheet

**Not planned in advance; produced by walking chunk 13 on 2026-08-27.** Scoped here rather than
folded into increment 9 by explicit user decision the same day: *"fix the gate only and proceed."*

### The defect

`NSApp.terminate(_:)` is a **silent no-op while a sheet is attached** — measured on an AppKit probe,
recorded in CONSTRAINTS §1 with the table. AppKit refuses the termination *before*
`applicationShouldTerminate` is consulted, so `QuitPolicy` is never asked and nothing is logged.

**⌘Q is therefore dead under every sheet in this app**: the pre-run dialog, the report sheet, and
the launch gate. It fails safe — no run is ever abandoned — and it fails **silently**, which is the
part that matters: the app's stated contract is that ⌘Q during a run *asks first*, and what it
actually does is nothing at all.

This is the true cause of **check 6.1** from increment 5, which observed the symptom and had a
guessed cause sitting beside it in `AppModel` for two increments.

### What increment 9 already did, and why it is not enough

The gate's own Quit button calls `dismissAttachedSheets()` before `terminateAction()`, and a test
asserts the **order** because swapping the two lines restores the defect. That is deliberately local:
it is safe there because the gate is window-modal at launch, so no run can exist.

### Why the general fix is not the same edit

**`AttachedSheets.endAll()` cannot simply move into `terminateAction`'s default.** Ending the sheet
under the **pre-run dialog** dismisses a prompt the user never answered, and the prompt is the last
thing standing between a ⌘Q and a drive. The quit path must therefore decide *whether* the sheet may
go before it ends it, and the decision belongs in `QuitPolicy` where the truth table is tested —
not in an AppKit poke.

### Know this before building it

- **`isSheet` is not the test for "may I terminate now".** The probe measured `isSheet` still `true`
  immediately after `endSheet(_:)` returned, and terminating right then worked. The blocker is the
  live sheet *session*, closed synchronously by `endSheet(_:)`.
- **`endSheet(_:)` is not enough for a SwiftUI sheet, and this increment must not be built on it.**
  Measured in the shipped app 2026-08-31: it leaves the sheet attached and the termination still
  refused. Each sheet has to be taken down by **its own presentation state going false** — so this
  increment is not one AppKit call in `terminateAction`, it is a rule per sheet (the pre-run prompt,
  the report, the gate) plus a decision about which of them a quit is allowed to discard. The gate's
  is `AppModel.helperGateIsPresented`; the pre-run prompt is the hard one, because dismissing it
  discards a question the user never answered.
- **No delay is needed and none should be used.** A version that terminates "a run-loop turn later"
  rests on a dismissal animation nobody has measured. Same turn works; it was measured.
- **The quit path emits no log lines at all**, which is why the chunk 13 failure could not be
  diagnosed from the archive and needed a probe. Whatever this increment does, `applicationShouldTerminate`
  and `QuitPolicy.disposition` should say so on the log (NFR-OBS-1).
- The probe that established all of this is in the session scratchpad, not the repo. **Rebuild it
  rather than trusting this paragraph** if the behaviour is ever in doubt; three earlier versions of
  it measured *nothing* (a SwiftUI `Window` scene launched from a CLI binary never materialises a
  window, and every mode reported `sheets = 0`) and were only caught because the probe asserted the
  sheet was attached before trusting its own verdict.

### The human checks it owes

⌘Q under the pre-run dialog during a run, ⌘Q under the report sheet, ⌘Q under the gate, and the
existing chunk 6 quit boundary re-run unchanged.

---

## Settled — do not re-open

| Decision | Date |
|---|---|
| ~~Remedy-first, not Quit-only; `.notFound` alone is Quit-only~~ **built, increment 9** | 2026-08-26 |
| ~~The gate fires at **launch/initialization**~~ **built, increment 9** | 2026-08-26 |
| ~~Diagnosed from `SMAppService.status` + the version handshake~~ **built, increment 9** | 2026-08-26 |
| FDA stays a Start-time check (**option A**, inside preparation) | 2026-08-26 |
| The FDA modal has **two** buttons | 2026-08-26 |
| Increment 10 keeps the FDA move and the banner deletion **together** | 2026-08-26 |
| The `Covering` row is deleted; `R-W-R-C speed` is a separate increment | 2026-08-26 |
| The gate re-checks on app activation while gated; **no third button** on `requiresApproval` | 2026-08-27 |
| ⌘Q under a sheet is fixed **app-wide as increment 12**, not folded into increment 9 | 2026-08-27 |
| `versionMismatch` re-registers by **unregister-then-register**; no other state unregisters | 2026-09-01 |
| The gate shows a **busy state** — remedies disabled, spinner + label, **Quit stays live** | 2026-09-01 |
| A spinner, **not a wait cursor**: macOS has no hourglass, and a cursor cannot be rendered | 2026-09-01 |
| Quit landing inside the ~730 ms busy window is **accepted, not defended against** — the user is free to leave and the state is recoverable | 2026-09-01 |

**The user was warned that a launch-time fatal modal costs the helper-free link-speed check** —
enumeration, capacity, serial and link speed are all app-side IOKit reads and work without the
helper — and chose launch anyway. That trade is made; do not re-raise it.
