# Build Progress Log — the step in progress

**This file holds the current step and nothing else.** It was 7,156 lines on 2026-08-11 and was
split, because a log a cold start is told not to read is a log that is not doing its job.

| where | what lives there |
|---|---|
| **PROGRESS.md** (this file) | the step in progress |
| **[CONSTRAINTS.md](CONSTRAINTS.md)** | **read this in full** — what binds future work: measured behaviour, settled decisions, lessons |
| **[BUILD-PLAN.md](BUILD-PLAN.md)** | the plan, the per-step gates, the process gotchas, the test hardware |
| `progress/step-NN.md` | archived history, for *"why was it done that way?"* |

**The full account of an increment goes in its commit message**, with this file carrying a summary
and the hash. Writing it twice at length produced two long prose accounts of one increment that
could drift; the commit is the immutable, greppable one.

---

## Step 11 — IN PROGRESS. Scoped 2026-08-12; no code written yet

Run-control state machine: start / pause / resume / stop / restart. FR-CTRL-1…9, NFR-REL-10.

**Its gating precondition is discharged** — Step 14 completed 2026-08-11 (`f082716`), which is why
it was built out of numeric order. This step deletes the `Unmount All` / `Acquire` / `Release`
controls, after which FR-DEV-3's default selection is one deliberate click from a write, and on this
machine that default is the 22 TB Seagate with Backup and Time Machine mounted. The warnings are the
only thing standing there.

### The starting point, re-derived rather than quoted

| | |
|---|---|
| **Tree** | `c278df9`, clean, on `main`. Step 14 archived to [`progress/step-14.md`](progress/step-14.md) |
| **Verified** | 801 tests, 0 failures, 93 suites; zero source warnings from three clean builds |
| **Helper** | source hash `737e6972bfdec1c5c1901a27bd5a00da2fed413166c909fc6639666c38e8907e`, **re-derived 2026-08-12 and unchanged** — so Step 10's three hardware gates (`xpc-concurrency-check.sh`, `metrics-check.sh`, `retention-cycle-check.sh`) apply until increment 2 moves the hash |
| **Protocol** | v9 |
| **Fixture** | the 4 TB T5 EVO (`00000S7CLNJ0WC02266P`) is attached and its **layout is intact** — GPT + EFI (unmounted) + `Vol_ExFAT` + `Vol_APFS` + `Vol_HFS`. No rebuild needed |
| **FR-DEV-3's default** | confirmed from `BSDDeviceName`, which orders **numerically**: the first USB drive is `disk4`, the 22 TB Seagate |

### The five scoping decisions (user decisions, 2026-08-12, taken before a line was written)

1. **A run is a sequence of bounded calls, and the session is the claim.** Start takes the claim
   once, holds it for the whole run, and releases it once — *never* a claim per chunk, which is
   unbuildable anyway: macOS remounts the volume **~4 ms** after a release (measured Step 6), so a
   per-chunk release would race its own remount tens of thousands of times. The metrics and failure
   accumulators therefore move onto `AcquiredDevice`, opened by `acquireDevice` and closed by
   `releaseDevice`. That gives whole-device progress and ETA, a **true whole-run p99** (percentiles
   do not compose, so app-side aggregation of per-call p99s cannot produce one), a `FailureLog` cap
   that applies once per run rather than per call, and cumulative figures arriving in the cycle's own
   reply — which preserves protocol v9's property (*the figures belong to this run or they do not
   exist*) at run scope, **with no new lifecycle methods**.

   The alternative considered and rejected was one long cancellable call, which needs no session at
   all. It was rejected because it bets a multi-hour run on an NSXPC reply nothing here has measured,
   makes `prepareForShutdown`'s and `releaseDevice`'s busy refusals hours-long instead of seconds,
   and turns FR-CTRL-8's mid-pause I/O-size change into engine surgery.

2. **Pause is enforced helper-side, at the chunk boundary**, as `control: () -> RunControlSignal`
   consulted at the **top of each chunk iteration** — the sibling of the `grant` closure the engine
   already recomputes before every write. The previous chunk's full read → write → verify is complete
   and nothing is in flight, so NFR-REL-10 holds by construction rather than by care. The signal
   travels on the app's **second, non-owning connection**: a message on the run's own connection
   provably cannot be delivered while `runRetentionCycle` blocks (measured 2026-08-04).

3. **The pre-flight sits inside increment 2, before increments 3–7 are designed.** Build the smallest
   helper-side control that can be measured, measure it on the 1 TB T5 scratch drive, then design the
   rest around the number. A wrong number found in increment 7 is six increments built on it.

4. **`maximumBytesPerCall` is decided by measurement, not by argument.** A change to 8 MiB was
   proposed, to align the cap with the largest UI I/O size and shorten pause latency. The latency
   half does not hold: once the chunk-boundary check exists, **pause latency is set by the chunk, not
   the call** — ~27 ms at the 4 MiB default and ~63 ms at a 200 MB/s floor, and an 8 MiB cap is
   *worse* than the chunk check at a 1 MiB I/O size, where one call is eight chunks. The cost half is
   unmeasured: 8 MiB means **119,234 calls** for the 1 TB T5 and **476,935** for the 4 TB T5 EVO,
   each an XPC round trip plus a buffer allocate/free pair, a geometry read and an observer
   construction — a per-*call* term where NFR-PERF-3's measured 2.55% follows bytes moved. So
   increment 2's pre-flight sweeps 8 MiB / 64 MiB / 256 MiB / 1 GiB in the same session and the cap
   is set from that. The sequencer works with any value.

   What *is* accepted: the cap's stated justification — *"what makes an uncancellable privileged
   call survivable"* — lapses in this step, because this is the step that makes it cancellable. Its
   remaining jobs are bounding the reply, the per-call failure list, and how long a wedged call can
   occupy the daemon. CONSTRAINTS is rewritten in the docs pass rather than left contradicting it.

5. **The three deletions land in increment 5**, at the same time Start takes ownership — not last.
   There is then never a build in which the run needs a claim nobody can grant, and never one in
   which two paths can both claim the device. The nine-item human checklist runs that same day.

### Three defaults recorded rather than decided

Raised during scoping and not contradicted, so they stand until they are:

- **The claim is held through a pause.** Releasing would remount the volumes and force a second
  unmount on resume.
- **A quit during a run issues a stop** rather than waiting for a call boundary. This makes the
  existing "stop at the call boundary" promise stronger, not weaker — the wait shortens from one
  call to one chunk — and it is what stops a paused run leaving the wind-down waiting forever.
- **Restart re-uses the held claim** rather than releasing and re-acquiring.

### Increments

| # | what | gate |
|---|---|---|
| **1 ✅** | `RunControlState` — the pure state machine, FR-CTRL-6's legal transitions, and each control's disabled **reason** (dimming is not a message). Nothing calls it. | **done 2026-08-12** — see below |
| 2 | Helper-side control: `RunControlSignal` in `Core/`, the engine's chunk-boundary check, new `RunOutcome` cases, protocol **v10**. **Then the pre-flight** — pause-settle latency and the cap sweep. | unit + mutations + a **new hardware gate**; needs an Xcode target-membership tick |
| 3 | The run session scoped to the claim; cumulative figures in the cycle reply; `runProgress` reports the whole device | unit + `metrics-check.sh` |
| 4 | The whole-device sequencer, app-side: whole-MiB slicing with only the final call short (FR-TEST-10), `mayIssueNewWork` checked before **every** call, `stopOnFirstError` meaning stop the *run* | unit, with an injected caller |
| 5 | **Start owns unmount → acquire → run → release.** Deletes the three controls; relocates the pre-run gate; the abort path rolls the unmounts back and verifies the **mount table** rather than the unmount's reply; deletes the follow-the-selection rule and `helperHoldsDevice` | renders + the **nine-item human checklist** + the 4 TB T5 EVO fixture |
| 6 | Pre-run controls relocated: the I/O-size dropdown (FR-CTRL-8) and the failure-mode picker (FR-CTRL-7); diagnostics scaffolding deleted | renders + unit |
| 7 | "Stopped by user" in the report (FR-RPT-4); Restart (FR-CTRL-5); three clean builds; all three Step 10 gates re-run; the docs pass | full |

### Increment 1 — done 2026-08-12, `c89ed5c`

`RunControl/RunControlState.swift` + `RunControlPolicyTests.swift`. App target and test target only,
both file-system synchronized, so **no Xcode work was needed** — verified rather than assumed, since
`@testable import` resolving `RunControlPolicy` is what proves the file joined the app target.

| | |
|---|---|
| **Verified** | **828 tests, 0 failures, 94 suites** (from the xcresult's top-level `totalTestCount`). 801 → 828 is exactly the 27 tests written, and 93 → 94 exactly the one new suite — the check that the files landed somewhere that compiles |
| **Warnings** | zero from source; the two in the log are the pre-existing AppIntents-toolchain lines |
| **Helper** | untouched. Hash still `737e6972…907e` |
| **Mutations** | **12 introduced, 11 caught, 1 survived** — see below |

**Eight states, not BUILD-PLAN's five**, and the differences are recorded in the source file's header:
no `Configured` (FR-FAIL-4's default means it is never observably distinct from `idle`), one terminal
state rather than three (the outcome is `RunReport`'s, FR-RPT-4), and Restart offered from `running`
and `paused` but not from `finished`, where it would duplicate Start. `pausing` and `stopping` are
their own states because the interval between a request and the helper's settle is real, and
collapsing it is exactly the claim NFR-REL-10 forbids.

**The mutation that survived, and what it found.** M9 blanked a disabled control's reason and passed
all 827 tests. The check walked the *rendered controls* — and the single Pause/Resume control asks
for `.resume` while paused, so `pause(in: .paused)`'s refusal never reaches a button. The row is
reachable all the same: a menu item or a keyboard shortcut issues a command without consulting the
control that would have offered it. **A real hole in the test, not a formality.** Fixed by walking
the whole table instead of the surface (`everyRefusalInTheWholeTableIsASentence`), and M9 re-run
against the fix — now caught. The note is on `RunControlPolicy.controls` so the next person does not
re-derive it.

### Increment 2 — code done 2026-08-12, **pre-flight not yet run**, not committed

Helper-side pause/stop at the chunk boundary, and protocol **v10**.

| | |
|---|---|
| **Verified** | **855 tests, 0 failures, 96 suites**; app and helper build clean on v10 |
| **Helper** | **hash moved to `c0ec07ae6cf746fb105446064ad584e391769a706e451ed1435a23c076f19702`.** Step 10's three hardware gates (`xpc-concurrency-check.sh`, `metrics-check.sh`, `retention-cycle-check.sh`) **no longer apply** and must be re-run before this step closes (increment 7) |
| **Mutations** | **12 introduced, 11 caught, 1 survived — and the survivor was predicted** |
| **Xcode work** | **none.** See the note below; BUILD-PLAN's summary of this is imprecise |

**No Xcode target-membership tick was needed, and BUILD-PLAN is wrong about why.** Read from
`project.pbxproj` rather than trusted: the helper folder is a `PBXFileSystemSynchronizedRootGroup`
for the **helper** target, so a new file there joins it automatically — `RunControlChannel.swift`
did. What needs a manual tick is the **test target**, which picks up `Core/` through an explicit
14-file `membershipExceptions` list. The control vocabulary went into the existing
`Core/RetentionRun.swift`, already on that list, beside `FailureMode` and `RunOutcome` where the
run's vocabulary lives. Correct BUILD-PLAN's "Working on this project" wording in the docs pass.

**What was built.** `RunControlSignal` and `RunControl.uninterrupted` in Core; the engine's
`control: () -> RunControlSignal` consulted at the **top of each chunk iteration**, so a pause
settles after the previous chunk's full read → write-back → verify with nothing in flight;
`RunOutcome.pausedByUser(atBlock:)` and `.stoppedByUser(atBlock:)`, only the first offering a
`resumeBlock`; `RunControlChannel` in the helper; and protocol v10 — `setRunControl` on the second
connection, plus the reply carrying `RunOutcomeCode` and the resume block.

**Two judgment calls, recorded because both cost something.**

- **`control:` is required with no default**, unlike `observer:`. It cost 31 call-site edits. A run
  that silently could not be interrupted is the `RunObservers.forRun` failure exactly: no test
  failing anywhere, and nothing visible until somebody presses Pause on hardware and watches it do
  nothing. `grant:` — the other safety-critical closure in that signature — is already required.
- **The reply's `completed` boolean was REPLACED, not supplemented.** FR-CTRL-2/4 give a run four
  endings, so a boolean beside a separate "why" would be two statements of one fact — the
  `helperHoldsDevice` defect by another door. `didComplete` survives as a derived property, so
  `RunReport` needed no change at all.

**The survivor, and why it was run anyway.** M12 — the helper reporting a pause as a stop — passed
the whole suite, **as predicted before the run**. `main.swift`'s outward `RunOutcome → RunOutcomeCode`
mapping is not in the test target, the same hole `RunObservers.forRun` had. Running the mutation
anyway is the point: it confirms the hole is where the code comments claim it is rather than
somewhere else. Two covers, neither of them a unit test: the mapping is an exhaustive `switch` (Step
12's device-loss case will be a compile error, not a silent `unrecognised`), and **the pre-flight
asserts the observed outcome is `pausedByUser`** — `run-control-check.sh` prints a note naming this
exact mutation when it sees outcome 4.

#### The pre-flight — RUN AND PASSED, 2026-08-12, on the 1 TB T5 scratch drive (`12345686DAA9`)

`scripts/run-control-check.sh` + `tools/run-control-probe`. Protocol v10 daemon, 1 GiB region
64 GiB into the drive, one uninterrupted control run then one paused run per I/O size.
**All four settled; 0 inconclusive.**

| I/O size | chunks done | covered | 1-chunk bound | **settle** | fraction of bound | daemon ack |
|---|---|---|---|---|---|---|
| 1 MiB | 298 | 298 MiB | 6.71 ms | **5.83 ms** | 0.87 | 0.62 ms |
| 2 MiB | 149 | 298 MiB | 13.41 ms | **10.13 ms** | 0.76 | 0.52 ms |
| 4 MiB | 75 | 300 MiB | 26.83 ms | **6.19 ms** | 0.23 | 0.56 ms |
| 8 MiB | 38 | 304 MiB | 53.66 ms | **42.45 ms** | 0.79 | 0.46 ms |

Calibration from the control run: 1 GiB of coverage in **6,868 ms** = 149.1 MiB/s of coverage,
i.e. **469 MB/s** of device I/O across read + write + verify — which matches this drive's
independently measured ~470 MB/s. The chunk counts imply a pre-pause interval of 1,999–2,039 ms
against an actual wait of 2,000 ms, so the four cases cross-check against the calibration and
against each other.

**What it establishes.** A `setRunControl` on the second connection reaches a helper inside a
blocking `runRetentionCycle`, the engine acts on it, and the run settles **within one chunk** —
every sample is a fraction of its own bound. The resume point matched
`startBlock + chunksProcessed × blocksPerChunk` **exactly** in all four cases and was 1 MiB-aligned
in all four, so it is proven rather than plausible. NFR-REL-10 holds on hardware.

**It also discharges M12's cover.** The observed outcome was `pausedByUser` (3) in every case; a
helper with the outward mapping swapped would have reported 4, and the script names that mutation
by hand when it sees one. The mutation the unit suite provably cannot catch is caught here.

**A claim of mine was wrong in the details, and the correction matters for the cap argument.** I
said pause latency would be *"~27 ms at the 4 MiB default"*. That figure is the **bound** — one
chunk — not the typical value: the pause lands at a uniformly random point inside a chunk, so the
expected settle is about **half** the bound, and a single sample scatters across it. That is why
2 MiB (10.13 ms) came out *higher* than 4 MiB (6.19 ms), which is not a defect and not noise in the
mechanism — it is two draws from two different uniform distributions. The right statement is
**"bounded by one chunk, typically half of one"**.

The conclusion the cap argument rested on is unaffected and is now measured rather than asserted:
**latency is set by the chunk, not the call.** A cap of 8 MiB would have produced these same
figures, because the settle happens at a chunk boundary *inside* the call either way. `maximumBytesPerCall`
stays at 1 GiB. Part 2 of the pre-flight — the per-call overhead sweep that would have set the cap
on its remaining jobs — was deferred by user decision 2026-08-12; the sequencer works with any value.

**For the docs pass (increment 7):** this measurement belongs in CONSTRAINTS section 1, and
CONSTRAINTS' existing sentence *"the cap … is what makes an uncancellable privileged call
survivable"* needs rewriting, since this step is what made the call cancellable.

### What this step must not lose

- **The gate is RELOCATED, not re-implemented**, and `runBoundedCycle(authorisedBy:)`'s
  `PreRunOutcome` parameter keeps its shape — it is what makes "wire Start straight to a run" a
  deliberate act visible in a diff rather than a one-word edit. The mutation is not catchable by the
  suite, so prevention is the only cover it has.
- **A partial unmount that fails must not strand the user.** Step 10 fixed this on the control this
  step deletes, so the fix goes with the control. Start's abort path reaches the identical state with
  nothing left to press.
- **`AppModel.mayIssueNewWork` is a precondition, not a hint** — checked before every call the
  sequencer issues, not once when the run starts.
- **The quit boundary moves with the run-state source**, and
  `quittingAfterTheRunHasAlreadyFinishedDoesNotWaitForever` must survive the move.
- **`AppModel.helperHoldsDevice` is deleted, not fixed** — a per-device answer read everywhere as an
  any-device one. Do not reintroduce a selection-scoped flag.
- **The 4 TB T5 EVO fixture is required, not optional.** `VolumeMounter.restoringUnmount` cannot be
  exercised end to end on a single-volume drive.

---

## Known loose ends carried into later steps

- **Step 12 inherits the worst one:** a drive that drops off the bus is reported as a drive with
  ~2 million bad blocks. See [CONSTRAINTS.md](CONSTRAINTS.md), "Device loss".
- **Every first-run report between Step 10 and 2026-08-11 was unattributable** — model, serial and
  capacity were missing. Fixed in `e61c4f0`. The run data in any such exported file is sound; its
  identity is not.
- `mountOne` / `unmountOne`'s DiskArbitration option constants are covered by no test.
- A cosmetic duplicate Window-menu entry, now three. `.commandsRemoved()` is measured **not** to be
  the fix.
- A main window reopened **during** a run comes back with no highlighted row (model and detail are
  correct).
- What the ~209 µs per-chunk term in the daemon's CPU actually is: measured, not explained.
- The root cause of the scratch drive's mid-gate de-enumeration is **not** established. One clean
  re-run after a cable and port change is the evidence available; it is not proof.
- **Light-appearance contrast is marginal in two places** — faint body text at 3.41:1 and the status
  glyph tints at 2.22–2.31:1, both under WCAG AA. **Recorded, not a defect** (user decision
  2026-08-11): these are macOS's own semantic colours, which is why the app inherits the system-wide
  "Increase contrast" setting for free. Dark appearance measures 6.61:1 and 7.47–8.25:1.
