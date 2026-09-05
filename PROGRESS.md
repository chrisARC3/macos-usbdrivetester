# Build Progress Log — the step in progress

**This file holds the current step and nothing else.** It was 7,156 lines on 2026-08-11 and was
split, because a log a cold start is told not to read is a log that is not doing its job.

| where | what lives there |
|---|---|
| **PROGRESS.md** (this file) | the step in progress |
| **[CONSTRAINTS.md](CONSTRAINTS.md)** | **read this in full** — what binds future work: measured behaviour, settled decisions, lessons |
| **[BUILD-PLAN.md](BUILD-PLAN.md)** | the plan, the per-step gates, the process gotchas, the test hardware |
| **[`progress/step-11-increment-plans.md`](progress/step-11-increment-plans.md)** | **increments 10–12: planned, approved, unwritten.** Read before building any of them |
| [`progress/step-11-human-checklist.md`](progress/step-11-human-checklist.md) | the keyboard checks — what no test can reach. **Complete: every chunk walked and passed, chunk 15 on 2026-09-03** |
| `progress/step-NN.md` | archived history, for *"why was it done that way?"* |

**The full account of an increment goes in its commit message**, with this file carrying a summary
and the hash. Writing it twice at length produced two long prose accounts of one increment that
could drift; the commit is the immutable, greppable one.

---

## Step 11 — IN PROGRESS. **Increments 1–12 done and gated**; the step's own verification gate is owed a re-run

> **Cold start? Read *Current state — increment 12 done and gated* below** — it is the only status
> block in this file that is current, re-derived 2026-09-04 at increment 12's close. Every
> *"Where increment N starts"* block above it is a dated snapshot of an earlier moment.

> ⚠️ **Nothing is planned. Increments 1–12 are done and gated.** The decisions taken along the
> way, and what must not be re-opened, are in
> **[`progress/step-11-increment-plans.md`](progress/step-11-increment-plans.md)**.
> **Read it before starting it** — the decisions were argued through at length and
> re-deriving them will not reach the same answers. **All four sections — 9, 10, 11 and 12 — have
> been deleted from that file**, as its header instructs, now that those increments have landed.
> What is left there is the settled-decision table, and **no increment is planned in it right now**.
>
> ⚠️ **This block said "increments 1–10 done; increment 11 is next" and "increments 11 and 12 are
> unwritten" until 2026-09-03, with increment 11 committed at `05b7ea7` and its docs commit at
> `c0d2596`.** That docs commit updated `BUILD-PLAN.md`'s lead block and missed this one — **the
> same defect, in the same pass that was correcting it elsewhere.** The index row three lines above
> was stale in the other direction, still claiming the checklist complete as of 2026-09-01 while
> chunk 15 was owed. **When a status block is edited, every other status block in the repository is
> edited in the same commit**; `grep -rn "increment 1[01]" *.md` is the check, and this project has
> now paid for skipping it four times.

Run-control state machine: start / pause / resume / stop / restart. FR-CTRL-1…9, NFR-REL-10.

**Its gating precondition is discharged** — Step 14 completed 2026-08-11 (`f082716`), which is why
it was built out of numeric order. This step deletes the `Unmount All` / `Acquire` / `Release`
controls and gives Start ownership of the whole sequence.

**That deletion is settled and will not be re-visited** (user decision 2026-08-12; full entry in
[CONSTRAINTS.md](CONSTRAINTS.md) section 2). It leaves **two** clicks between FR-DEV-3's default
selection and a write — Start, then Proceed on a dialog that names the drive by model and USB serial
and cannot be switched off to nothing. This document said "one deliberate click" until 2026-08-12
and was wrong. A third click would be a guard with no evidence behind it; what actually addresses
mis-identification is the dialog naming the drive by the identifier that survives a renumbering.

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
| **2 ✅** | Helper-side control: `RunControlSignal` in `Core/`, the engine's chunk-boundary check, new `RunOutcome` cases, protocol **v10**, then the pre-flight. **No Xcode tick was needed** and the cap sweep was deferred — both differ from what this row predicted; see below. | **done 2026-08-12** — see below |
| **3 ✅** | The run session scoped to the claim; cumulative figures in the cycle reply; `runProgress` reports the whole device. Protocol **v11**, which this row did not predict — nine reply arguments changed meaning. Two gate clients had to be rebuilt before the gate could run at all. | **done 2026-08-14** — see below |
| **4 ✅** | The whole-device sequencer, app-side. The I/O size ended up **fixed for the run** and the per-call cap **injected**, neither of which this row predicted; and a documented justification for FR-TEST-10 was measured and found wrong. | **done 2026-08-14** — see below |
| **5 ✅** | **Start owns unmount → acquire → run → release.** Deletes the three controls; relocates the pre-run gate; the abort path rolls the unmounts back and verifies the **mount table** rather than the unmount's reply; deletes the follow-the-selection rule and `helperHoldsDevice` | **done 2026-08-18 `0e09e5d`** — the checklist passed in seven chunks and found **three defects 964 tests could not reach**; see `progress/step-11-human-checklist.md` |
| **6 ✅** | Pre-run controls relocated: the I/O-size dropdown (FR-CTRL-8), built for the first time, and the failure-mode picker (FR-CTRL-7); diagnostics scaffolding deleted. FR-CTRL-8's 2026-08-14 amendment was **built and then reversed on sight** — both controls are now dead for the whole of a run, `paused` included, and the confirmation machinery went with it as untriggerable. Neither this row nor the requirement predicted that | **done 2026-08-19 `321a820`** — see below |
| **7 ✅** | **The main window's size.** It opened at screen height and its minimum did not fit a 13.3-inch Mac. `ContentView`'s height literal is deleted outright and each scrolling pane declares its own floor instead. **Unplanned** — it came out of looking at increment 6 on real hardware | **gated 2026-08-20**: chunk 9 passed in full, three clean builds, 991 tests. `321a820` + `5a4a76f` + **`faf9a93`** |
| **8 ✅** | FR-RPT-4's "stopped by user"; FR-CTRL-5 **built and then withdrawn** — the control was redundant with Stop-then-Start, so the requirement is met by composition; the Run Report becomes a **sheet on the main window**. Two user decisions arrived mid-increment that this row did not predict: the refusal lines under the run buttons deleted, and the negotiated **USB link speed moved to before the run** | **code done 2026-08-22/23** — `0f65be4` + `916a630`. **Gated 2026-08-24** — three clean builds, all three Step 10 hardware gates at 0 failures, and the docs pass. **Chunk 12 passed in full 2026-08-25** — all eight items, `e0f4415`. **Item 7.5 and the chunk 8 item 3 recheck closed 2026-09-01** |
| **9 ✅** | **The launch-time helper gate.** `HelperAvailability` — a pure enum + pure diagnosis over `SMAppService.status` and NFR-MAINT-1's version handshake — and one remedy-first modal raised at launch. `HelperRegistration` moves to `AppModel`. Six scoping decisions the plan did not settle were taken first; **five render cases rather than one**, and the `⇧⌘R` clause the plan did not name | **code done 2026-08-27** — see below. **Chunk 13 passed in full 2026-08-27/09-01**, and found five defects; `8b0db53`, `bd8281d`, `2ed5984` |
| **10 ✅** | **FDA moves to Start; two rows of clutter deleted.** The Full Disk Access check is an injected operation in `DevicePreparation`, **before the unmount**, with a two-button alert. The **readiness banner** is gone entirely, and `DeviceListView` no longer holds an XPC connection at all — which the plan did not predict. **`Covering` was deleted from three surfaces, not one** | **done 2026-09-02 `6b809cc`** — see below. Built in three chunks, suite green between each. App target only; v12 stands |
| **11 ✅** | **`R-W-R-C speed`.** Bytes whose chunk outcome is `.completed`, per second — the figure the user actually wanted, which existed nowhere. **FR-METR-1 was then amended mid-increment**: the displayed rates divide by *phase* time, not running time, so Read and Write no longer share a denominator and "Read is about twice Write" stopped being a counting identity. **Protocol v13 → v14**, not folded into v13 | **done 2026-09-03 `05b7ea7`**, docs `c0d2596`. **Chunk 15 written and walked the same day, `d155eef`** — five items, all passed; two of its original seven were deleted before either could be walked. ⚠️ **This row said "planned and approved, unwritten" until 2026-09-04**, five days after the increment landed and one day after the status block above was corrected for exactly this — found by increment 12's stale-claim sweep, which is what the `grep -rn` check in that block exists to do |
| **12 ✅** | **⌘Q works under every modal.** `NSApp.terminate(_:)` is a silent no-op while a sheet is attached, so ⌘Q ran **no code of this app's at all** under any of its window-modal surfaces — **five of them, not the three the plan named**, because a SwiftUI `.alert` on macOS is presented as a sheet. The app now declares its **own** Quit command (the only route that is entered under a sheet) and asks a per-surface truth table. **Unplanned**: produced by walking chunk 13, and it is the true cause of increment 5's check 6.1 | **done and gated 2026-09-04.** App target only; **helper hash unmoved** at `e6888aa5…`, so increment 11's three hardware gates stand untouched. **Chunk 16 passed in full** the day it was written, and 6.1, 11.7 and 6.3 re-walked and passed. It found `Cancel and Quit` had not quit since increment 8 |

> **Renumbered 2026-08-19.** Increment 7 was unplanned. What the rest of these documents still call
> *"increment 7"* — the docs pass, the Step 10 gate re-runs, FR-RPT-4 and Restart — is now increment
> **8**. The scattered references are left for the docs pass to sweep rather than half-corrected
> here, which would leave no single place saying what happened.

### Where increment 8 starts

> **A dated snapshot, not the current state.** For that, read *Current state — increment 12 done
> and gated* below.

Re-derived on 2026-08-20 rather than quoted. **No tree hash is named on purpose** — it would be
stale by the next commit, which is the failure mode this project keeps paying for. `git log
--oneline -6` shows increment 7's three commits.

| | |
|---|---|
| **Tree** | clean, on `main` |
| **Verified** | **991 tests, 0 failures, 129 suites**; zero source warnings across three clean builds with DerivedData wiped before **each** — Debug 86 SwiftCompile tasks, Release 2, test 167 |
| **Helper** | source hash `058fb2c0767af72a38299e4f133d98053e2b42b73958437813dc1b0420202781`, **unchanged since increment 6**. ⚠️ **This is where increment 8 *started*. The current hash is `73990c90…`** — it moved at the gate for a comment-only change, 2026-08-24 |
| **Protocol** | **v12** |
| **Gates** | `window-fit-check.sh` passes against a 700 pt budget with an **empty** `.window-fit-exceptions` |
| **Fixture** | the 4 TB T5 EVO (`00000S7CLNJ0WC02266P`). **The 1 TB T5's `/dev/urandom` fill file must be kept** |

**How to re-derive the helper hash**, which was recorded in a commit message and nowhere a cold
start would look:

```
find USBDriveTester/com.arc3solutions.USBDriveTester.Helper USBDriveTester/USBDriveTester/Shared \
     -name '*.swift' | sort | xargs cat | shasum -a 256
```

Helper **plus `Shared/`**. The recipe behind hashes recorded before 2026-08-19 is not written down
anywhere and does not reproduce; only hashes from `a36c4f77…` onward are checkable.

### Where increment 11 starts

> **A dated snapshot, not the current state.** For that, read *Current state — increment 12 done
> and gated* below.

Re-derived 2026-09-02. **No tree hash is named on purpose** — it would be stale by the next commit,
which is the failure mode this project keeps paying for.

| | |
|---|---|
| **Tree** | clean, on `main` |
| **Verified** | **1088 tests, 0 failures, 135 suites** (floor 1088); zero Swift source warnings, Debug and Release, DerivedData wiped; **13/13** gate clients type-check |
| **Helper** | source hash **`73990c90…`**, unchanged since 2026-08-24. Bumped to v13 and back three times on 2026-09-01 for chunk 13 item 7 and returns byte-identical. So **Step 10's `xpc-concurrency-check.sh` and `retention-cycle-check.sh` are still owed** — because the binary moved at increment 8's gate, not because anything failed; `metrics-check.sh` was re-run and passes |
| **Protocol** | **v12** |
| **Gates** | `window-fit-check.sh` worst case **613 pt**, `.window-fit-exceptions` empty — **unchanged across increment 10**, as predicted. **37** render cases; the script's list and `tools/ui-probe`'s own unknown-view message are both hand-maintained and have drifted three times — re-derive, never hand-edit |
| **Human checklist** | **complete at this point: chunks 1–14 walked and passed, nothing owed.** Chunk 14 passed in full 2026-09-02, all seven items; chunks 1–13 by 2026-09-01. Chunk 15 did not exist yet — increment 11 wrote it and then walked it, both on 2026-09-03; **that walk is recorded in increment 11's own section, not here.** Four items elsewhere were later found stale and corrected 2026-09-03 — 2.3, 7.2 and 13.7 named the `Covering` row deleted by increment 10, and 2.3 also asserted Activity Monitor agrees with the panel, which FR-METR-1's amendment reversed. ⚠️ **This row described 2026-09-03 state inside a block titled "where increment 11 starts" until 2026-09-03**; a snapshot block that gets edited with later news stops being a snapshot |
| **Fixture** | the 4 TB T5 EVO (`00000S7CLNJ0WC02266P`) is **not attached** — still true on 2026-09-02, read off a live `devices` render: `General UDisk`, `Samsung Flash Drive`, two Seagate Expansions, the 1 TB Portable SSD T5 and the 990 EVO Plus. **The 1 TB T5's `/dev/urandom` fill file must be kept** |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, built **2026-09-02 13:22**, daemon kickstarted after. Current as of increment 10 — **increment 11 moves the helper hash, so it must be reinstalled and the daemon kickstarted again before any hardware gate or checklist walk.** See BUILD-PLAN's "Verifying a step" |
| **Remote** | private **`chrisARC3/macos-usbdrivetester`**, branch `main`, added 2026-09-02. `LICENSE` (MIT) and `README.md` exist at the root. Commit straight to `main`; nothing is pushed unless asked. Distribution is unchanged — source only, Step 16 |

**The run is read → write-back → verify**, so a test run refreshes a drive rather than erasing it —
recorded because the opposite was said out loud on 2026-09-01 and it changes which drive somebody is
willing to point the tool at. Not risk-free: a write failing mid-cycle can still cost data.

### Where increment 12 starts

**Re-derived 2026-09-04, and this is the block a cold start should read.** The two above it are
dated snapshots of earlier moments and are not current. No tree hash is named, on purpose.

| | |
|---|---|
| **Working tree** | clean, on `main`, nothing unpushed. ⚠️ **The repository moved on 2026-09-04** from `/Volumes/1TB_Samsung/AI_Stuff/claude-code-folder/USBDriveTester` to **`/Volumes/1TB_UGreen/…`**, same path below the volume. It is still on a **removable volume**, so builds still go outside it. Two pasteable checklist commands and two gate-script error messages named the old path and were corrected; the scripts now derive it |
| **Verified** | **1093 tests, 0 failures, 135 suites in 49 s — re-run 2026-09-04 on the new volume**, so the move is proven not to have broken the build rather than assumed (floor `scripts/.test-floor` = 1093). Zero Swift source warnings Debug and Release with DerivedData wiped, and 13/13 gate clients type-checking, are increment 11's gate figures and were not re-measured today |
| **Helper** | source hash **`e6888aa5af72b433cd5b33cf18b98a0bab5d330e1fb058277e23aae82813f627`**, re-derived 2026-09-04 and unchanged since `05b7ea7`. **All three of Step 10's hardware gates pass at this hash** — `metrics-check.sh` 128/0, `xpc-concurrency-check.sh` 0 failures, `retention-cycle-check.sh` 15/15 whole-device |
| **Protocol** | **v14** |
| **Gates** | `window-fit-check.sh` worst case **613 pt**, `content-starting`; **37** render cases, 74 renders in both appearances |
| **Human checklist** | **complete — 15 chunks, nothing owed.** Chunk 15 was written and walked 2026-09-03 |
| **Owed** | **nothing.** First time since increment 8 |
| **Fixture** | all three test drives attached 2026-09-04: **`disk6`** PSSD T5 EVO 4 TB, **`disk7`** Portable SSD T5 1 TB (the scratch, serial `12345686DAA9`), **`disk4`** UDisk 125.8 MB thumb (serial `2211190533300386001515`). ⚠️ **The 1 TB T5's `fill.bin` is deleted** — the retention gate passed on the residual `/dev/urandom` pattern, which survived the unlink. Restore it before that gate is needed again **[annotated 2026-09-04 18:19: `fill.bin` has since been restored — see the Current state block. The row is left as written, because it was true of the moment this snapshot was taken.]** |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, built **2026-09-03 12:52**; daemon **PID 71058 since 13:08:46**, still running 2026-09-04. Current for the helper hash above — **increment 12 is app-side and will not move it**, so a reinstall is only needed to see the app change |
| **Remote** | private **`chrisARC3/macos-usbdrivetester`**, branch `main`. Commit straight to `main`; **nothing is pushed unless asked** |

**Increment 12 is app-side only.** It touches no file in the helper hash set, so every gate result
in this block stands until it does — and if a change makes the hash move, the three hardware gates
lapse with it. Check the hash before assuming they hold.

### Current state — increment 12 done and gated

**Re-derived 2026-09-04 at increment 12's close, and this is the block a cold start should read.** Every
*"Where increment N starts"* block above it is a dated snapshot of an earlier moment.

**A separate block rather than an edit to the one above**, deliberately: that one is titled *where
increment 12 starts* and it is true of that moment. Editing a snapshot with later news is the defect
this file's own ⚠️ describes, and increment 11's block was caught doing it on 2026-09-03. **This
block is not a snapshot** — it is the current state, and it is the one to edit when things change.

| | |
|---|---|
| **Working tree** | clean, on `main`. Chunks 0–2 pushed; this chunk is not |
| **Verified** | **1123 tests, 0 failures, 136 suites** (floor `scripts/.test-floor` = 1123). **Three clean builds with DerivedData wiped before each — `build.sh Debug`, `build.sh Release`, `test.sh` — zero source warnings from all three**, and genuinely clean rather than cached: 88 per-file `SwiftCompile` tasks Debug, 2 whole-module Release, 171 for the test target. **13/13 gate clients type-check** |
| **Helper** | source hash **`e6888aa5af72b433cd5b33cf18b98a0bab5d330e1fb058277e23aae82813f627`** — **re-derived after every chunk of increment 12 and unchanged**, so increment 11's three hardware gate results still stand |
| **Protocol** | **v14** |
| **Human checklist** | **complete — 16 chunks, nothing owed.** Chunk 16 passed in full 2026-09-04, all nine items, the day it was written; it found **one defect in the product** (*Cancel and Quit* did not quit, since increment 8) **and three in itself**. **6.1, 11.7 and 6.3 re-walked and passed** at expectations increment 12 changed |
| **Owed** | ⚠️ **Step 11's verification gate needs re-running before Step 11 can close.** It passed 2026-08-24 at increment 8; **four increments have landed since, and increment 11 took the protocol v12 → v14 and moved the helper hash.** Its items **2**, **3** and the helper-side half of **5** all rest on `scripts/run-control-check.sh`, last run 2026-08-24 **against a v12 daemon**. That check **writes to the scratch drive**, so it must not overlap the `fill.bin` restore — **that restore finished 2026-09-04 18:19:30, so nothing now blocks this gate on the fixture's account.** No increment is planned |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, reinstalled 2026-09-04 for the chunk 16 walk and again for the 6.1/11.7 re-walks, daemon kickstarted each time. ⚠️ **Always kickstart after `install-app.sh`** — it replaces the helper binary underneath the running daemon, and BUILD-PLAN is explicit that *nothing announces the mismatch when the helper source has not moved*, which is exactly an app-only increment's case. **Verify a reinstall took with `nm -U` on `Contents/MacOS/USBDriveTester.debug.dylib`** rather than by the timestamp: `strings` cannot settle it, and on 2026-09-04 chunk 16 was nearly walked against chunk 0's build |
| **Fixture** | drives unchanged from the block above. **The 1 TB T5's `fill.bin` was restored 2026-09-04 18:19**, against the scratch device identified by **serial `12345686DAA9`** (`/dev/disk7` that day — BSD names move): 999,947,239,424 bytes of `/dev/urandom` in 57m43s at 288.8 MB/s, `dd` ending on `No space left on device` as intended. The volume reads **100% used**, so the gate's `df` early warning no longer fires the false alarm it fired on 2026-08-25 and 2026-09-03; three 1 MiB samples at 1 GiB, 476811 MiB and 953622 MiB digest distinctly, and none is the all-zero block. **Invalidated by** unlinking the file or erasing the volume — **not** by `retention-cycle-check.sh` or `run-control-check.sh`, which write back exactly the bytes they read |
| **Remote** | private **`chrisARC3/macos-usbdrivetester`**, branch `main`. Commit straight to `main`; **nothing is pushed unless asked** |

### What increment 8 owes

1. ~~**FR-RPT-4** — "Stopped by user" in the report.~~ **Done, `0f65be4`.** Deferred out of
   Step 10 (user decision 2026-08-06); Step 10's gate carries it struck through.
2. ~~**FR-CTRL-5** — Restart.~~ **Built in `0f65be4`, withdrawn in `916a630`.** The scoping decision
   recorded here — that it would **re-use the held claim** rather than release and re-acquire — is
   now moot: there is no Restart control. The requirement is met by Stop then Start, and carries a
   2026-08-22 amendment saying so. Do not re-derive the control from the requirement row.
3. ~~**The Run Report window becomes modal to the main window**~~ (user decision 2026-08-19).
   **Done, `916a630`** — a sheet on the main window, which is what forces the report closed before a
   new run can start; a run starting under an open report cleared its contents, observed on hardware.
4. ~~**All three Step 10 hardware gates re-run**~~ — **all three passed 2026-08-23/24**, with
   0 failures each. `metrics-check.sh` failed 40 assertions on its first attempt for a reason that
   was **not the product**; see the increment 8 section.
5. ~~**Three clean builds**~~ **passed 2026-08-24** — Debug 86 SwiftCompile tasks, Release 2, test
   168, DerivedData wiped before each, zero Swift source warnings. The test figure was 167 before
   `AppModelReportTests.swift`. ~~**The docs pass**~~ — **this is it.**
6. ~~**The human checklist owes chunk 12 and item 7.5**~~ — **the checklist is complete as of
   2026-09-01.** Chunk 12 passed in full 2026-08-25, all eight items; it was the only cover the new
   link-speed read has. **7.5** ran on 2026-09-01 — a whole-device pass on the 125.8 MB thumb drive
   (serial `2211190533300386001515`), 30/30 chunks in 39 s, `Completed` with no range caveat,
   exported and compared — followed ten minutes later by a stopped run on the same drive, so the
   wording was seen to **change** rather than merely to read correctly once. The **8.3 recheck**
   confirmed the sentence unconditional and above the I/O size row, identical before a run and while
   paused at a settled block.

**Debts the docs pass must clear.** Each is recorded where it was found as well as here, so this
list is a checklist rather than the only witness:

* **Chunk 9.7 has never been walked.** It covers the refusals collapsed in `faf9a93` and was written
  after chunk 9 was signed off. `disabledReasons` is private to its view, so no test reaches it and
  the `content-starting` render is its only automated cover.
* **The renumbering of 2026-08-19** left the words "increment 7" in documents that now mean
  increment 8. The note under the increments table is deliberately the only correction made so far;
  sweeping the rest is this pass's job.
* ~~**BUILD-PLAN is wrong about why increment 2 needed no Xcode tick.**~~ **Already discharged
  on 2026-08-14** and this entry was stale from the day it was written — BUILD-PLAN's own "Last
  amended" note carries the correction, and its target-membership section reads the answer out of
  `project.pbxproj`. Checked rather than assumed, 2026-08-24. **A debt list is a claim like any
  other, and this one had been false for ten days.**
* ~~**`starting` misses the 1152x720 scaling by 18 pt.**~~ **Cleared, not documented.** Deleting
  the refusal lines under the run buttons (2026-08-22) took the worst case from 638 to 613 pt, and
  1152x720 allows 620 — so `starting` now fits it with **7 pt to spare** and the non-goal has
  nothing left to state. NFR-USE-9's amendment said a user at that scaling "gets a window that fits
  at rest and grows behind the Dock for the few seconds a run spends starting"; that sentence was
  true when written and is now false. Corrected there, 2026-08-24.

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

### Increment 2 — done 2026-08-12, `e13d3e8`

Helper-side pause/stop at the chunk boundary, and protocol **v10**.

| | |
|---|---|
| **Verified** | **855 tests, 0 failures, 96 suites**; app and helper build clean on v10 |
| **Helper** | **hash moved to `c0ec07ae6cf746fb105446064ad584e391769a706e451ed1435a23c076f19702`.** Step 10's three hardware gates (`xpc-concurrency-check.sh`, `metrics-check.sh`, `retention-cycle-check.sh`) **no longer apply** and must be re-run before this step closes (**increment 8** — renumbered) |
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

**For the docs pass (increment 8):** this measurement belongs in CONSTRAINTS section 1, and
CONSTRAINTS' existing sentence *"the cap … is what makes an uncancellable privileged call
survivable"* needs rewriting, since this step is what made the call cancellable.

### Increment 3 — done 2026-08-14, `4c84329`

The metrics and failure accumulators moved onto the **claim**. `acquireDevice` opens the session,
`releaseDevice` closes it, no lifecycle method was added.

| | |
|---|---|
| **Verified** | **873 tests, 0 failures, 102 suites**; `metrics-check.sh` **0 failures** on hardware at v11; zero warnings from source |
| **Helper** | hash **`b804178ddea31cc521983e5ee343c6d5c50b3a73c7708294741a8f6decb31124`** |
| **Protocol** | **v11** — nine reply arguments changed *meaning* with no signature change |
| **Mutations** | **10 introduced, 9 caught, 1 survived — and the survivor was predicted** |
| **Xcode work** | **none**, read from `project.pbxproj` rather than assumed |

**The session is stored on the claim rather than kept in step with it.** `AcquiredDevice` gains one
`RunSession` property; `MetricsChannel` loses `begin()` and its process-wide slot and becomes a
lookup. A fresh claim therefore starts empty and a released claim answers nothing *by construction*
— the alternative (keep the slot, add an `end()`) is two things stating one fact, which is what
`helperHoldsDevice` is being deleted for. The accumulating logic is `RunSessionObserver` in Core so
a test can reach it; `DeviceClaim.swift` gains a property and no logic, because it is not in the
test target.

**Protocol v9's property survived, by a weaker guard, and that is written at the site.** v9 read the
figures from an observer that did not exist until a call passed validation. The session predates the
call, so what replaces it is the result type: figures come from a `CycleResult`, which exists only on
the success path. Weaker, because they now exist one line from the refusal path and `main.swift` is
not in the test target. `metrics-check.sh`'s three *"reported no figures"* assertions are the only
cover anywhere — **verified, not assumed**: mutation H1 wrote that exact defect and the gate killed
it. What *did* improve: a poll can no longer return a *previous* run's figures at all, because they
died with the claim.

**A defect found while scoping, not on the increment's list.** `CacheBypassAssessment` was re-seeded
every call, so FR-TEST-9's *only ever downgrades* contract broke across calls — a `likelyCached`
verdict earned at 40% of a drive would be gone by 41%. Invisible at one call per run; live from
increment 4's ~1,000. The session now carries it.

**The gate could not run at all, inherited from increment 2.** `tools/metrics-probe` and
`tools/mount-guard-client` did not *compile* against v10. Both rebuilt; all five gate clients now
compile clean against v11.

**What the gate measured** — 1 TB T5 scratch drive (`12345686DAA9`), one run of four calls, each
size over its own gibibyte so the shape matches what increment 4's sequencer will produce:

| call | I/O | cumulative chunks | % of device | latency min / p99 / max |
|---|---|---|---|---|
| 1 | 1 MiB | 1024 | 0.107352 | 1.949 / 2.163 / 5.379 ms |
| 2 | 2 MiB | 1536 | 0.214704 | 1.949 / 4.260 / 12.723 ms |
| 3 | 4 MiB | 1792 | 0.322057 | 1.949 / 9.044 / 28.525 ms |
| 4 | 8 MiB | 1920 | 0.429409 | 1.949 / 17.039 / 30.145 ms |

**The latency column is the evidence and it is independently predictable.** The minimum held at
1,948,666 ns through all four calls — the run's fastest read was set in call 1 and survived, which a
per-call accumulator cannot report. The p99 lands on one read at whichever I/O size is currently
largest (2.16 / 4.26 / 9.04 / 17.04 ms against 2.10 / 4.19 / 8.39 / 16.78 predicted at 500 MB/s),
because the top 1% of a union is dominated by the biggest reads present — and slightly above each,
as an octave-bucketed upper bound must be. Host overhead 2.620% of device I/O time over the run,
against Step 9's 2.55% at 4 MiB.

**Two findings from the mutation pass, neither about the helper.** The harness nearly recorded a
false survivor: M3's anchor occurs twice in `RunMetrics.swift`, the wrong site was patched, the build
failed, and the classifier reported *"SURVIVED: all 0 tests passed"*. A suite that did not run is the
number-that-did-not-move trap; a total of `0` is now INCONCLUSIVE regardless of the failure count,
and anchors are asserted unique. And H1 exposed the **probe** conflating two facts — `REFUSED` was
`outcome == unrecognised && chunks == 0`, so a correct refusal carrying leaked figures was reported
as *"the alignment guard is not enforced"*, pointing at innocent code. Split in two.

**For the docs pass (increment 8), beyond what increment 2 already left:**

- **`HELPER_CORE_FRACTION` changed meaning and CONSTRAINTS must say which figure is which.**
  Bracketed from acquire, it is now a run average **diluted by the idle between calls** —
  7.73% → 6.50% → 5.44% → 4.85% across the four, falling as idle accumulates — where Step 9's
  4.22% was per-call. Step 16's release note wants the during-I/O figure. Two numbers that measure
  different things must not sit side by side as though they did not.
- **`retention-cycle-check.sh` is owed because the helper binary moved, *not* because the write
  path changed.** `RetentionTestEngine` was not touched; this increment changed what the observers
  accumulate. Accumulating is not writing, and NFR-REL-1 is about the bytes. The gate script said
  otherwise and was corrected in this commit.

**Full account, including the restore mistake and how the hash caught it: commit `4c84329`.**

### Increment 4 — done 2026-08-14, `c8bcc2a`

The app-side sequencer: `RunControl/RunSlicing.swift` and `RunControl/RunSequencer.swift`, plus two
test suites. **No Xcode work**, read from `project.pbxproj` rather than assumed.

| | |
|---|---|
| **Verified** | **913 tests, 0 failures, 112 suites**. 873 → 913 is exactly the 40 tests written and 102 → 112 exactly the 10 new suites |
| **Warnings** | zero from source across three clean builds, DerivedData wiped before each. SwiftCompile tasks Debug 80 / Release 2 / test 158 |
| **Helper** | **untouched** — hash still `b804178d…31124`, so Step 10's three gates are exactly as owed as they were |
| **Mutations** | **14 introduced, 13 caught, 1 survived — and the survivor was predicted** |

**A documented justification for FR-TEST-10 was measured and found wrong.** CONSTRAINTS section 1
and BUILD-PLAN Step 11 both say a sequencer advancing by *"1 GiB or whatever is left"* is *"refused
on its last-but-one call"*. The claim is in no `progress/` archive, so it was checked: walked four
real geometries through `RunPlacement.validate` and that sequencer produces **0 refusals on all
four**, slicing identically to this increment's. It is safe only because `maximumBytesPerCall` is
itself a whole multiple of 1 MiB — give it a ragged cap and it is refused on **call 2**. What *is*
refused last-but-one is a different sequencer, one that backs the final call up to a full 1 GiB
(#931/#932 on the 1 TB T5). **The design was unaffected; the test was not.** The two forms agree on
every real geometry, so the cap became a required parameter and the suite slices with ragged ones —
without which the rounding is correct-but-unobservable. Mutation M1 confirmed exactly that: it is
killed by the ragged-cap cases and **not** by the walk over the real drives at the real cap.

**Two user decisions that differ from what was offered.** The I/O size is **fixed for the run**, and
**changing it ends the run** rather than resuming with a new one — which gives the next Start clean
accumulators *by construction*, the property Shape A was chosen for, with no protocol change, no
v12 and no split accumulator lifetimes. It reverses the 2026-08-04 decision that latency statistics
keep accumulating across a size change; the amendment and the control are increment 6's. And the
sequencer **owns no run state** — `RunControlState` stays with increment 5's coordinator, since
`starting` / `claimEstablished` / `deviceReleased` are states this type can neither cause nor
observe.

**The predicted survivor, and the decision it leaves open.** M13 removes the late-reply guard in
`callReturned`. Nothing in increment 4 can end a run with a call outstanding — increment 8's
Restart-from-`running` was what could, **and that control was withdrawn on 2026-08-22**, so
nothing in the product reaches it now — so the unit suite cannot reach it either, though a real
`NSXPCConnection` can if a reply block and the error handler both fire. That makes it
*un-unit-testable* rather than unreachable, the same category as increment 2's M12, and the guard
was kept on that basis. **Increment 7 should pin it** when Restart makes it reachable.

**Four mutations would not have compiled**, caught by reading them back before the run rather than
by the harness: a `where` clause on an enum case makes a `switch` non-exhaustive, and `>= 0` on a
`UInt64` is an always-true warning. Both score INCONCLUSIVE under increment 3's rules, not CAUGHT.
Restored from saved pristine copies with a `cmp` guard and rewritten; anchor uniqueness asserted for
all 14 before and after.

**Docs owed by this increment: all discharged 2026-08-14, before increment 5**, rather
than deferred to increment 8's docs pass. A cold start is told to read CONSTRAINTS in full and trust it, so
leaving a claim in it that had been *measured false* would have defeated the file's purpose for
three increments. Corrected: the "last-but-one" claim in CONSTRAINTS section 1 and BUILD-PLAN
Step 11; FR-CTRL-8 and its 2026-08-04 consequences in the FR document, with a new 2026-08-14
amendment; the metrics bullet in CONSTRAINTS section 1 that assumed a mid-run size change; Shape A's
third rejection ground, which lapsed with that amendment; and `RunReport.ioSizesUsed`'s comment.
**Increments 2 and 3's items are still owed** — see their entries above.

### Increment 6 — done 2026-08-19, `321a820`

The two pre-run controls moved to the main window: the I/O-size dropdown built for the first time
(FR-CTRL-8) and the failure-mode picker relocated from the diagnostics window (FR-CTRL-7).
`RunControl/PreRunControls.swift` + `PreRunControlsTests.swift`.

| | |
|---|---|
| **Verified** | **985 tests, 0 failures, 127 suites**. Down from 964, deliberately: see the reversal below, where the arithmetic is reconciled |
| **Warnings** | zero from source across three clean builds, DerivedData wiped before each — **re-run after the reversal**. SwiftCompile Debug 85 / Release 2 / test 165 |
| **Helper** | **hash moved `f983b4e5…` → `058fb2c0…`** — and Step 10's three gates **still apply**, proven rather than argued; see below |
| **Protocol** | **v12, unchanged.** No helper logic was touched |
| **Mutations** | **two rounds.** Round 1 against the first shape: 16 introduced, 14 caught, 2 survived, both predicted. Round 2 against the shipped shape: **10 introduced, 8 caught, 2 survived, both predicted** |
| **Xcode work** | **none**, read from `project.pbxproj` rather than assumed: neither new file is named in it, so both joined through their synchronized root groups |
| **Renders** | 29 view cases, both appearances. `diagnostics-stop-on-error` replaced by `content-stop-on-error`; `content-finished` added |

**The user decisions taken at scoping, before a line was written.** Both controls sit **inside
`RunControlsView`** above Start, and the I/O size **persists across launches**. Two further
decisions — that the size stayed live while paused, and that changing it there was confirmed first —
**were reversed on 2026-08-19 after the built control was looked at on hardware**; see below.

**THE SHAPE CHANGED HALF-WAY THROUGH, AND THE TRIGGER WAS A PERSON LOOKING AT IT.** The increment
was first built to FR-CTRL-8 as it read after 2026-08-14: the size live while paused, the mode dead,
and a size change ending the run behind a confirmation. All of that passed 998 tests, three clean
builds, both appearances and a 16-mutation pass. **Then chunk 8 item 3 of the human checklist put a
real paused run on screen**:

> *"Having seen it in real life, I no longer like the idea of those two controls having different
> behavior after pausing the test. The user should either be able to change both or neither."*
> — user, 2026-08-19

**Both went to the dead side, and the analysis of why is worth keeping**, because "make them agree
on the live side" was the obvious answer and it does not work. The size cannot resume across a
change — percentiles do not compose. The **mode can**, and that was checked against the code rather
than assumed: it is passed per call, it is a stored property on `RunSequencer` set once at
`start()`, and it contaminates no measurement, because it changes what happens *on* a failure
rather than how bytes are read or written. What stops it is not mechanism. It is that
`RunReport.failureMode` is a **single field taken from the last call's reply**, so a run that
logged-and-continued for hours and then switched would be reported as `stopOnFirstError` throughout;
and that **`stopOnFirstError` selected after failures already exist has no defined meaning** — stop
now, or stop at the next one? So "both live" bought an ambiguity with no principled answer and a
report that would have to be widened to stay honest. **Both dead is the consistency that costs
nothing.** Full account in the FR document's 2026-08-19 amendment; FR-CTRL-7 was amended to match.

**What the reversal deleted, and why that is the right outcome rather than waste.**
`IOSizeChangePrompt`, its alert, `IOSizeChangeDisposition`, `IOSizeControlRule`,
`RunController.endRunForIOSizeChange()`, two log routes and **three test suites** — all
untriggerable the moment no state could reach them. *Nothing untriggerable is built in advance*: a
sound mechanism behind a trigger that never fires looks exactly like a broken one. The two controls'
rules collapsed into **one** `PreRunControls.availability(in:)`, derived from
`RunControlState.isRunActive` rather than restating it, and the two disabled sentences became one.
**The increment ended smaller than its first version**, which is the signal that the simpler product
was also the simpler build.

**The test count went DOWN, and the floor caught it** — 998 → 985, 130 → 127 suites. That is
`test.sh`'s one case needing a human, and the arithmetic was reconciled before the floor was reset
rather than after: 22 tests removed across five suites, 9 added across two, net −13; five suites
removed, two added, net −3. Both numbers land exactly, which is the check that what was deleted is
what was meant to be.

**The size is captured once, onto `PendingStart`, when the gate is answered.** The closure was being
called twice — for the log line at authorisation and for `sequencer.start` when the drive came back
prepared, with the whole unmount-and-claim sequence in between. Harmless while it returned a
constant; with a live control it is two properties naming one fact at two instants, which is the
shape of the *"Unidentified drive"* defect. Mutation M10 pins it. **This survived the reversal
unchanged** and is the one piece of the first shape that is strictly better for having been built.

#### Three findings, none of them on the increment's list

- **`TesterProtocol` had to become `nonisolated`, and that moved the helper source hash.** It is the
  first `nonisolated` type in the app target to need one of its constants, and the app target's
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` made that six warnings. Six sibling enums in the same
  file already carry the keyword; the helper target does not set that flag, so the constants were
  already nonisolated there. **Verified rather than asserted**, with the comparison CONSTRAINTS
  names for *"did this change behaviour"*: the helper binary's `__TEXT,__text` is **byte-identical
  across 709,012 bytes** of instruction text and `__TEXT,__cstring` is identical, while the whole
  binary differs — which is exactly what a debug build does for an annotation-only edit. **So
  `metrics-check.sh`, `retention-cycle-check.sh` and `xpc-concurrency-check.sh` still apply.**
- **`scripts/render-ui.sh`'s view list had drifted from the probe for the second time, and worse
  than the first.** It listed **24** cases against the probe's **28**, named two
  (`diagnostics-held`, `diagnostics-quitting`) that increment 5 had made the probe **refuse with
  exit 2**, and omitted all six `content-*` run states. The header already records this exact drift
  being fixed on 2026-08-11. Corrected, diffed clean against the probe, and the re-derivation
  one-liner is now in the header so the next person does not hand-edit it.
- **`ContentView`'s `minHeight` had expired again**, for the second time silently. Re-measured
  rather than adjusted by eye: 740 cuts the device-detail paragraph mid-sentence, 760 does not. Now
  **760**, with the caveat written at the site that this number is not what makes the run controls
  reachable — being outside the scroll region is, and it holds by construction.

#### The mutation pass, twice

**Round 1, against the first shape: 16 introduced, 14 caught, 2 survived, both predicted.** The
reversal then deleted the code six of them targeted, so the round is evidence about a shape that no
longer exists and cannot stand as this increment's cover.

**Round 2, against what shipped: 10 introduced, 8 caught, 2 survived — both declared in advance.**
The survivors are in `RunControlsView`: N9 makes the dropdown do nothing at all, N10 makes a change
issued *during* a run be applied instead of refused. No test drives a SwiftUI binding, so the suite
provably cannot reach either — the same category as increment 2's M12 and increment 4's M13. Their
cover is the renders and human-checklist chunk 8, and running them is what confirms the hole is
where the code says it is rather than somewhere nobody has looked.

**N5 was killed by four tests, two of which this increment did not write.** Mutating
`IOSizeSelection.label` to divide by 1 << 10 failed `aSingleSizeIsNamedPlainly` and
`severalSizesAreNamedAndTheDistributionIsFlaggedAsSpanningThem` — pre-existing *report* suites. That
is the retrofit of the report window and the Markdown export onto the shared label paying for
itself: one spelling of "N MiB", covered in all three places that render it, where before there were
three literals and the report's two were the only ones under test.

**The anchor-uniqueness guard earned its place before a single mutation ran.** M10's anchor was a
28-space argument line that is a **substring** of the 34-space one six lines above it in the log
call, so `count(old) == 1` failed and nothing was applied — increment 3's false-survivor trap,
stopped by the check that exists because of it. Re-anchored on unique surrounding text.

Every one of the 16 runs executed the full **998** tests: no INCONCLUSIVE, no build failure, no
partial run. All four mutated files were confirmed byte-identical to their saved pristine copies
afterwards, and the helper source hash re-derived to `058fb2c0…`.

**Worth knowing for increment 8** (this paragraph said 7 before the renumber): the report's outcome
wording for a run ended this way is FR-RPT-4's *"stopped by user"*, which that increment owns. Until
then a size change reports as whatever a Stop press reports as — the same path, correctly, because
it is the same act.

### Increment 7 ✅ — done 2026-08-20, `5a4a76f` + `faf9a93` (first half at `321a820`)

**Unplanned, and it exists because increment 6 was looked at on hardware.** The window opened far
larger than it needed to, and the question that followed was whether it fits a 13.3-inch Mac at all.

**Full account: commits `321a820`, `5a4a76f` and `faf9a93`.** What is worth carrying here is the shape of the
answer, and the two things it leaves standing on purpose.

The measurements, taken with a width-constrained variant of `ui-probe` that asks the real view
hierarchy for the limits it hands a window:

The middle column is what increment 7 reported on the day. **It was wrong by 58 pt in every row**
— see the correction below — so the honest figures are carried beside it rather than quietly
substituted.

| | before | as reported 2026-08-19 | measured 2026-08-20 |
|---|---|---|---|
| enforced minimum, idle | 760 | 485 | **531–542** |
| enforced minimum, running | 760 | 535 | **581–592** |
| enforced minimum, `starting` | 760 — **and the content wanted 775, so it clipped** | 629 | 675–686, then **595–606** once the duplicate refusals were collapsed |
| swing with attached drive count | 168 pt | none | **11 pt** — the declared number ignored drive count too |
| swing with failure mode selected | 15 pt | none | none |
| declared maximum | infinite, with no `.defaultSize` — so it opened at screen height | unchanged maximum, `.defaultSize` declared |

**macOS lays windows out in points, not pixels.** A 13.3-inch Apple Silicon Mac is 2560x1600 pixels
but **1440x900 points** at its default scaling, so the budget is 900 and not 1600. Measured on the
development Mac rather than recalled: title bar 32 pt, menu bar 30 pt, bottom Dock ~70. Getting this
wrong by a factor of 1.8 would have made every number on this page look comfortable.

`ContentView` now declares **no minimum height at all**, and that is the point rather than an
omission. The literal it carried had expired three times, silently each time, because nothing
recomputes a literal. The floors belong to the panes that can scroll (`WindowMetrics`) and SwiftUI
sums them.

### The gate — `321a820` was the halfway point

**`scripts/window-fit-check.sh` is the part that lasts.** It asks the real view hierarchy, through
the new `ui-probe --limits`, for the size limits it hands a window, and compares them to the screen
budget for every state at 1 and 6 attached drives. Four mutations: raising a pane floor was caught
as TOO TALL; raising it *slightly* was caught as REGRESSED against the recorded allowance and
nothing else, so the ratchet isolates; an unknown view name was caught by a guard that had to be
fixed first (under `set -e` the failing assignment aborted before the diagnostic could print);
and **lowering** a floor survived, as predicted — this is a ceiling check, not a floor check.

`WindowMetricsTests` — 6 tests, 2 suites, floor ratcheted 985 → 991. Its header says plainly what it
is not: a unit test cannot lay out SwiftUI, so it cannot check the thing the increment is about, and
a test asserting `metricsFloor == 97` would restate the source while making the file look like cover
it is not. What it pins is the relationships — a default below the minimum, an ideal below its own
floor, a zero length. Six mutations, each caught by exactly the intended test.

**A defect found by the new drive-count axis, within minutes of it existing.** The metrics panel and
the device detail are both `ScrollView`s and both were greedy, so spare height split evenly between
them: at 700 pt with six drives the window showed **two drives of six** beside a metrics panel
spending 265 pt on a single sentence. The ceiling is now conditional on `showsMeasurements` — greed
is right when there are figures worth over 400 pt and wrong when there is one sentence.

**Three clean builds**, DerivedData wiped before **each** rather than once before the three:
Debug **86** SwiftCompile tasks (85 + `WindowMetrics`), Release **2**, test **167**. Zero source
warnings in all three. 991 tests green.

The test figure was recorded as 81 the first time round and is not a regression — 81 is the test
target alone, which is what a test build costs when it can reuse a Debug build's app-target objects.
Wiped first, it recompiles both: 86 + 81 = 167, exactly. Release is 2 because whole-module
optimisation compiles each target in a single task — app and helper. Worth writing down because
"the number went up" is otherwise indistinguishable from something having been added.

**The docs pass found that the requirement did not exist.** This increment was built against "the
window must fit a 13.3-inch Mac", and neither requirements document said what it had to fit — while
three source citations of `NFR-USE-8` had already been written, pointing at an *accessibility*
requirement that says nothing about window size. **NFR-USE-9** now exists, with an amendment
recording the decision, the points-versus-pixels correction and the known shortfall. The citations
are corrected. A second wrong claim went with it: `deviceListFloor`'s comment said it tracked the
body text size, which a plain `CGFloat` does not — and CONSTRAINTS already records that Dynamic Type
moves no font in this app on macOS.

### 2026-08-20 — two corrections from running the checklist

**9.1 was recorded as failed, and had never run.** The setup step told the user to clear the saved
window frame with `defaults delete com.arc3solutions.USBDriveTester "NSWindow Frame main"`. That
form resolves to a **stale sandbox container** under `~/Library/Containers/` (7 July, from before
App Sandbox was turned off): it deleted nothing, reported nothing, and the window restored its old
frame — which was then read as `.defaultSize` not working. Increment 6 had already been bitten by
the same container on a `defaults READ` and written it up as a read problem; it is not. It applies
to every `defaults` operation on this bundle ID. The checklist now addresses the plist by path and
verifies with `plutil -p` before launching. Re-run: **9.1 passes**, the window opens at 720 x 700.

**The idle metrics panel is now sized to its content** (user decision, on seeing it). It was capped
at `metricsIdeal` and still showed ~140 pt of empty box; finding and choosing a drive is the first
thing a user does, so the drive panes get the height. The fix is that the idle branch has **no
`ScrollView`** — with nothing greedy inside it, the `GroupBox` sizes to the placeholder and stops,
at any window height. The running panel's policy is unchanged, and both `metrics` probe cases report
identical limits before and after.

**A false economy went with it and was reverted the same day — worth recording because it
measured well.** Dropping the idle *floor* as well took 30 pt off every state's reported minimum
(485 -> 455) and `window-fit-check.sh` passed on the new number. It was wrong: with no floor this
became the only pane without one, so at the window's own minimum it absorbed the whole shortfall and
the placeholder's second line was cut in half. **A smaller reported minimum is not automatically a
better one** — it can mean the window is now permitted to be too small.

**The gate cannot see that class of defect at all.** `window-fit-check.sh` checks the minimum is
small enough to fit a screen; nothing checks it is large enough to fit the content. Chunk 9.2 caught
it at the keyboard in about a minute, which is the clearest justification the human checklist has
had this step.

**The list can fall to one row, so it has to keep the right one on screen** (user request,
2026-08-20, out of 9.3). At the window's minimum the drive list showed whichever row its scroll
offset happened to land on, and the "Selected device" pane below it could name a drive that was
nowhere in the list. `DeviceListView` now scrolls the minimum distance needed to bring the
selection into view whenever that pane's height changes — no anchor, so it does nothing when the
row is already visible, and unanimated, because a drag changes the height on every frame.

It costs **no height at all**: every state's minimum is unchanged at 485 / 535 / 629. The selection
capsule measures 45 pt against the 46 pt floor, so one whole row already fitted at the bottom of the
range and `deviceListFloor` did not have to move — which matters, because moving it would have
pushed `starting` past its recorded allowance and failed the ratchet.

This is increment 7's own doing rather than something it merely uncovered. Until this increment the
list was rigid at up to 260 pt, so losing the selection needed six drives and an already-scrolled
list; making the list the pane that yields height first is what put it one drag away with two.

**The large case passed for the wrong reason and nearly hid the real bug.** Called straight from the
geometry action, the scroll runs against the *pre-change* viewport — so a row needing only a few
points of movement reads as already visible and nothing happens. Six drives did not show this: the
scroll needed there is large enough to saturate at the content's maximum offset, and a clamp does
not care which viewport height produced it. Two drives did show it. The fix is a one-run-loop-turn
deferral, the **third** instance of that shape in `DeviceListView` alone, after the focus request at
`onAppear` and `TableSelectionPolicy`'s search for its table.

**New render case `content-selection-below-fold`**, which selects the *last* drive rather than the
first. Every render this project has ever taken had its selection on row 1 — visible at any pane
height, and therefore structurally blind to this. Mutation-tested at two drives x 485 pt: deleting
the geometry trigger is **caught**, scrolling to the wrong row is **caught**, deleting the deferral
is **caught**. Deleting the *selection* trigger is a **deliberate survivor** — a render establishes
its layout once, so the geometry trigger always fires — and is recorded in the checklist's no-cover
list rather than left to be discovered.

**Chunk 9 passed in full on 2026-08-20**, all six items, including 9.6 — the drive-list auto-scroll
added the same day, which had no cover before it. Committed at `5a4a76f`. **A 9.7 was added after
that commit**, covering the collapsed refusals, and has not been walked yet.

**One thing carried forward, and it is not a defect.** At a very tall window the *selected-device*
pane holds the leftover height — the waste moved rather than went, which is inherent: at 1200 pt
something has to absorb 400 pt, and the only question is which pane absorbs it.

The `starting` overage that used to sit here is **gone**: it was 41 pt against a budget that state
never met, it was really 98, and collapsing the duplicate refusals plus moving the committed budget
to 700 clears it by 62. `scripts/.window-fit-exceptions` is empty.

### The 58 pt correction (2026-08-20) — the gate was measuring the wrong thing — `faf9a93`

**`window-fit-check.sh` was answering "does it fit" with a height at which it demonstrably does
not.** It read `NSWindow.contentMinSize`, which SwiftUI builds from the `.frame(minHeight:)` each
pane asks for. `WindowMetrics.deviceListFloor` asks the drive list for 46 pt — one row — and **the
AppKit table backing that pane will not lay out below about 104 whatever it is told.** SwiftUI
believed the 46, so the declared total was 58 pt short of any height the content can occupy.

Found by driving the shipped window with accessibility scripting: the app clamps at **575 pt**
where the gate said 517. Confirmed twice more — a render at the declared minimum clips its header,
and setting `deviceListFloor` to 104 moves the declared number to 543, which is the app's clamp on
the nose.

**The gate now measures the layout rather than the declaration.** `--limits` reports the larger of
the declared minimum and the smallest height at which the laid-out content stops overflowing the
space it is given. Both can be too small in different ways — a floor a control ignores, or a view
whose whole body is a scroll region and so never overflows, which bottoms `report` out at 24 pt
against a declared 560 — and neither can be too large.

A side effect worth having: **the width argument now bites.** `starting` measures 675 at 640 wide,
645 at 700 and 631 at 900. It was inert before, and the figures the gate's own header quoted for it
had never been produced by the gate.

**The duplicate refusals were collapsed**, which the 2026-08-19 write-up called worth ~80 pt and
deferred. It was worth exactly that: `starting` 718 → **638**. In the four transient states
(`starting`, `pausing`, `stopping`, `finishing`) the run state is itself the reason every control
refuses and the status line already names it, so one sentence draws where three did. Each sentence
measures 40 pt. The surviving one is Start's, which keeps "Start's refusal is always shown" true by
construction — the invariant that stops this narrowing reaching `content-quit-pending`, where the
wider rule tried in increment 5 left Start disabled with nothing saying why.

**The committed budget moved 620 → 700** (user decision, 2026-08-20): a 13.3-inch at 1280x800 with
the Dock, rather than every scaling it offers. Not a retreat from a met commitment — 620 was chosen
from the broken numbers and no state ever met it. Against 700 every state fits with at least 62 pt
to spare, and `scripts/.window-fit-exceptions` is **empty for the first time since it was created**.

Uncovered by the suite: `disabledReasons` is private to its view, so no test reaches the collapse.
The `content-starting` render is its only cover, and chunk 9.7 is the keyboard check.

### Increment 8 ✅ — done 2026-08-22/23, gated 2026-08-24. `0f65be4` + `916a630` + the gate commit

The three planned pieces landed, one of them was then **withdrawn**, and two unplanned user
decisions arrived from looking at the built thing. Split across two commits: `0f65be4` has FR-RPT-4
and Restart; `916a630` has everything else, including Restart's removal.

| | |
|---|---|
| **Verified** | **1025 tests, 0 failures, 131 suites**; zero source warnings; 13/13 gate clients type-check |
| **Helper** | `058fb2c0…` for the whole of the code work — **unchanged since increment 6**, so Step 10's three gates were no more stale than they already were. It moved to `73990c90…` at the gate, for a comment-only change; see below |
| **Protocol** | **v12**, unchanged |
| **Window** | `window-fit-check.sh` worst case **613 pt** (`content-starting`), down from 638. All three 13.3-inch scalings fit; 1152x720 by 7 pt |
| **Probe** | 34 render cases → **31** |

**FR-RPT-4** is in the report. **The report is now a sheet** on the main window rather than a
`Window` scene, which is what forces it closed before a new run can start — a run beginning under an
open report cleared that report's contents, seen on hardware. The 2026-08-06 note claiming "a sheet
cannot be rendered" was measurably wrong and is corrected where it was written.

**FR-CTRL-5 was built and then withdrawn** (user decision, 2026-08-22). Stop then Start reaches the
same place; the dedicated control cost a command, a state, a purpose dimension on the pre-run dialog
and a discard warning — 222 references across 16 files — to offer a second route to one outcome.

> A requirement is a capability, not a control. Building a control per requirement is how a state
> machine acquires states that exist only to carry an intent from one half of an operation to the
> other, which is exactly what `restarting` was.

**Two unplanned decisions.** The refusal lines under the run buttons were deleted as inferable from
the surrounding UI — every sentence was checked against the status line, the Unusable badge and the
quit banner first, and no mandatory requirement compelled any of them. That is what bought 638 →
613 pt. Then the **negotiated USB link speed moved to the Selected device pane** (2026-08-23), so
the question *did this drive negotiate the link I expected, and is there any point starting?* can be
answered before a run. It could not be a moved label: `deviceProfile` **requires a device to be
held**, so the app now reads the IORegistry `Device Speed` key itself at enumeration. See the FR
document's 2026-08-23 amendment for the two-source consequence and why the report stays the
authority.

**A defect the increment found, and what found it.** Shift-Cmd-R during the pre-run dialog ran,
queued a second sheet and presented it on cancel — SwiftUI queues rather than shows a second sheet
on one window. It was caught by a probe **written as "not a regression check"**, which is the second
time in this step that an instrument built for one purpose has been the only thing looking at
another.

**Where the cover is, and where it is not — measured, not assumed.** No unit test covers the new
registry read and none can, because `IOKitDeviceEnumerator` needs hardware. The mutation round
demonstrated this rather than asserting it: a misspelled registry key and a pane wired to a constant
both **survived the full 1025-test suite**, and the live-hardware `devices` render caught both.

> **One declared not-caught that is still not caught.** Changing the `?? -1` fallback to `?? 4` —
> reporting an unreadable link as a confident 10 Gb/s — survived the suite *and* the render. Every
> USB device on this machine reports a `Device Speed`, so the honest-unknown arm is never taken
> here; it became visible only by breaking the read at the same time. **A drive that reports no link
> speed has never been seen by this project.** Recorded in the human checklist's blind-spot list.

`scripts/usb-speed-check.sh` reads the same key straight from `ioreg` and agreed with the app
exactly — the 4 TB PSSD T5 EVO reports code 3 (SuperSpeed, 5 Gb/s) while the 1 TB Portable SSD T5 on
the same hub reports code 4. That is an independent instrument confirming a read that has no test.

**Two stale counts corrected on the way past**, both of the kind this project keeps paying for:
`render-ui.sh` still claimed 34 view cases against the probe's 31 — the third such drift its own
comment block warns about — and the human checklist's closing line still said "three blind spots"
against a list that had grown to ten.

### The gate — 2026-08-24

| | |
|---|---|
| **Clean builds** | three, DerivedData wiped before **each**: Debug 86 SwiftCompile tasks, Release 2, test 168. **Zero Swift source warnings.** The test figure was 167 before `AppModelReportTests.swift`, so it reconciles exactly |
| **Suite** | 1025 tests, 131 suites, complete and green |
| `xpc-concurrency-check.sh` | **0 failures.** Digest held the daemon 2563.9 ms; same connection **serialized**, second connection **concurrent**, 22/22 answered, worst reply 5.8 ms. Finding unchanged |
| `metrics-check.sh` | **0 failures** on the second attempt — see below. 1920 chunks over four calls, host overhead **3.014%** of device I/O time (device-bound), daemon CPU 6.125% of one core against an independent `ps` peak of 12.5% |
| `retention-cycle-check.sh` | **0 failures**, 15 checks. 932 whole-device fingerprint windows before and after, **every one unchanged** (NFR-REL-1). 256 chunks — 255 full plus one short, so FR-TEST-5 was exercised. 1,072,693,248 bytes written at block 1818476544; the whole 1 TB device byte-identical afterwards |

**`metrics-check.sh` failed 40 assertions on its first run, and the product was not at fault.**
`RunControlChannel` is a process-wide slot on the daemon that nothing clears but the caller. The app
had left `stop` in it at 09:11:29 during a GUI session. The probe then acquired the drive and issued
four bounded calls, each returning `stoppedByUser` after **0.5 ms having processed zero chunks** —
and all forty failures were downstream consequences of that one value. **Not one of them named it.**

`run-control-probe` has cleared the level since increment 2; `metrics-probe` predates the channel and
never did. The probe was fixed, not the class — the design is right, the caller does own the level.
What was wrong was the class's own comment, which argued from the app's behaviour that a stale value
was *harmless*. Every gate script in this project is a client that is not the app.

> **The helper source hash moved for a comment-only change.** Correcting that comment took the hash
> from `058fb2c0767af72a38299e4f133d98053e2b42b73958437813dc1b0420202781` to
> `73990c90d6a5b43a9dc2b3791284b33501acbe7f6752c38bfdde266b9d696cbb`. **The three gates above still
> stand**, and the evidence is mechanical: every changed line in `RunControlChannel.swift` begins
> with `//`, so no executable line moved and the compiled daemon is behaviourally identical. Re-run
> the gates on the next hash move that is *not* provably comment-only. Recorded here rather than
> assumed, because a hash that moves for a reason nobody wrote down is a hash nobody can trust.

**Two content checks that mattered.** The scratch drive's `fill.bin` had been deleted, and the gate's
early warning — which reads `df` — said the drive was 1% used and a random run would land on zeroes.
It was a false alarm: an unlink clears the directory entry and the allocation table, not the media.
The **CONTENT check is the authority**, it samples raw blocks through the helper, and its three
sampled chunks returned three distinct fingerprints. The residual `/dev/urandom` pattern was intact.

**Owed as human items** as of 2026-08-25, and **both closed 2026-09-01**: **item 7.5** (a run allowed to complete) and a
**one-off recheck of chunk 8 item 3's moved sentence**. Chunk 8 items 3–7 passed 2026-08-24; chunk
12 passed in full 2026-08-25.

### Checklist chunk 12 — WALKED AND PASSED 2026-08-25, all eight

The only cover the link-speed registry read has. Two mutations — a misspelled key, and the pane
wired to a constant — survive all 1025 tests, because `IOKitDeviceEnumerator` needs hardware and
the suite has none. Both are now dead by measurement.

**Items 1–4, the read itself.** Six drives read at the keyboard against `usb-speed-check.sh`'s
independent registry read: **three distinct speeds, six agreements, no exceptions.** A constant
cannot produce three values and a misspelled key cannot produce six correct ones. Item 4 then moved
the 1 TB Portable SSD T5 from a 10 Gb/s port to a 5 Gb/s one and the row followed it down.

**Items 5–8, what the change cost.** The pane lost the advice with no gap left behind; FR-WARN-1 is
still discharged by the dialog in all three of its paths; the metrics panel lost the row and nothing
else; the report kept `Negotiated USB link speed` where the 2026-08-04 decision put it.

**Two findings the walk produced that the items did not ask for:**

1. **The 4 TB T5 EVO negotiates 5 Gb/s because it is a USB 3.2 Gen 1 product**, not because of a
   cable, a port or a hub. Settled by the user across two built-in Mac mini ports and two cables.
   It is the obvious drive to suspect — it reads 5 Gb/s while 10 Gb/s ports stand free — so it
   invites a hunt that has now been done once and must not be repeated. Recorded in the FIXTURE
   block of `scripts/lib/device-identity.sh` and at chunk 12 item 4. Its consequence for old
   numbers: **every throughput figure this project has taken from the EVO was bounded near
   500 MB/s by the link**, before the drive was ever the limit.

2. **The two-source link speed agrees on hardware.** `DiscoveredDevice.usbLinkSpeedCode` (the app's
   enumeration read) and the report's `deviceProfile` figure (the helper's claim-time read) had
   only ever been *argued* to agree. Item 8 checked them after a port change — the one condition
   that would expose a stale app-side read — and the pane, the report and the exported Markdown all
   read `5 Gb/s (USB 3.0)`. Recorded on the property itself.

~~**Still owed after this**: item 7.5, and a one-off recheck of chunk 8 item 3's moved sentence.~~
**Both closed 2026-09-01 — the human checklist is complete.**

### Covering is mislabelled — found 2026-08-25, **row deleted 2026-09-02 (increment 10)**

Raised by the user from the metrics panel: *Covering* always equals *Write*, which looked like an
implementation error. It is not — the two share a numerator and a denominator, because a cycle
writes each covered byte exactly once. But pinning the definition down without using the word
"covered" in it exposed a real discrepancy:

> `rangeBytesCovered` and `currentBlock` count **attempted** work, not successful work.

So the displayed figure is **sectors attempted per second**, under a label that reads as successful
work. The arithmetic is right for its two consumers — the ETA denominator and the progress fraction
both *need* attempted, or a failing drive would show a bar that never reaches 100% and an ETA that
never converges. **The defect is the name.**

Three decisions followed, and they are scheduled as increments below:

* ~~**The `Covering` row is deleted.**~~ **Done, increment 10 (2026-09-02) — and it was three rows,
  not one.** The panel, the report sheet and the exported Markdown all carried it, and the prose
  explaining it existed twice. All three went together. App-target only; the internal quantity and
  the ETA are untouched, and the wire field stays, documented as deliberately undisplayed.
* **A new figure, `R-W-R-C speed`** — bytes whose chunk outcome is `.completed`, per second. Only
  that one outcome counts: `.verifyMismatch` ran all four steps and failed the compare, and it is
  deliberately **not** an `isPhaseFailure`, so a bare `!isPhaseFailure` test would score a retention
  failure as a success. Not currently computed in bytes anywhere. **Protocol v12 → v13.**
* **Not called "Progress speed"** — the progress bar and ETA are driven by attempted bytes, so that
  name would promise `ETR = remaining ÷ rate` and break it exactly when a drive is failing.

### Increment 9 ✅ — the launch-time helper gate. Code done 2026-08-27

`HelperAvailability.swift` (the pure decision) + `HelperGateSheet.swift` (the modal) +
`HelperAvailabilityTests.swift`. `HelperRegistration` moved from `HelperDiagnosticsView`'s `@State`
onto `AppModel`.

| | |
|---|---|
| **Verified** | **1058 tests, 0 failures, 134 suites.** 1025 → 1058 is exactly the 33 tests written and 131 → 134 exactly the three new suites |
| **Warnings** | zero from source across three clean builds, DerivedData wiped before **each**. SwiftCompile Debug **88** / Release **2** / test **171** — reconciles exactly against increment 8's 86 / 2 / 168: two new app files and one new test file |
| **Helper** | **untouched** — hash still `73990c90…`, so Step 10's three gates are exactly as owed as they were. One candidate change was declined to keep it that way; see below |
| **Protocol** | **v12, unchanged.** App target only |
| **Xcode work** | **none**, read from `project.pbxproj` rather than assumed: `membershipExceptions` covers only `Helper/Core/`, and both new files are in synchronized root groups |
| **Renders** | 31 view cases → **36** |
| **Window** | `window-fit-check.sh` worst case **613 pt**, `content-starting` — **unchanged**, which is the measurement that says a `.sheet` modifier costs no layout rather than the assumption |
| **Mutations** | **12 introduced, 9 caught, 3 survived — all three declared in advance** |

**Six decisions the approved plan did not settle were taken before a line was written.** The plan's
"Settled — do not re-open" table was honoured in full; these are the gaps beside it. Two of them
changed the shape of what landed.

1. **A sheet with a real `View`, not an `.alert`.** The plan promised a `helper-gate` render case,
   and **an alert cannot be rendered at all** — `.alert(_:isPresented:actions:message:)` takes
   `ViewBuilder`s of buttons and text that AppKit consumes, so there is no value to hand an
   `NSHostingView`. A sheet's content is a `View`, capturable *out* of place exactly as
   `PreRunPromptSheet` is. Choosing the alert would have made every word and every button
   human-only, on top of the wiring already being so.
2. **The trigger goes in `USBDriveTesterApp.swift`; the modifier goes on `ContentView`.** See
   CONSTRAINTS section 2 — this is the finding worth carrying, and it removed a problem rather than
   adding one. The alternative was a fourth injected dependency on `AppModel.init`.
3. **`.enabled` with the handshake in flight is `available`.** Not a row in the plan's table, and
   something has to be true during that interval. A `checking` case would exist only to be switched
   over, since no modal is shown for it either way.
4. **`@unknown default` → `unreachable`, not a seventh case.** And see below: the arm turned out to
   be *testable*, which is the opposite of what was expected.
5. **Five render cases, not one** (31 → 36). The states differ in message length, in **button
   count** — `notFound` is the only one-button footer — and `unreachable` is the only surface in
   this app rendering a string whose length the app does not choose. The precedent is the
   `warnings*` family: four renders over a two-case type.
6. **`helper.invalidate()` before re-registering, in the gate's action only.** Only one path reaches
   it with a connection in existence — `versionMismatch`, where the proxy points at the old daemon.
   It is **not** moved into `HelperRegistration.register()`: the diagnostics window's Register button
   is not disabled during a run, so an unconditional invalidate there would drop a live claim.

**A seventh thing the plan did not name, and it is owed either way.**
`AppModel.reportMayBeRaisedFromMenu` gains `&& helperAvailability.isAvailable`. At launch
`runIsActive` is false and `pendingPrompt` is nil, so ⇧⌘R is **enabled** — and a window-modal gate no
more swallows menu commands than the pre-run dialog does. Without the clause the empty report queues
behind the gate and presents itself when the gate is answered: chunk 11.11's defect, in a new place.
**A first framing of this as a cost of choosing the sheet was wrong** — both kinds of modal are
window-modal, and what 11.11 established is about menu commands.

#### The mutation pass — 12 introduced, 9 caught, 3 survived, every verdict as predicted

| | Mutation | Predicted | Result |
|---|---|---|---|
| M1 | `.requiresApproval` → `.available` | CAUGHT | caught, 5 tests |
| M2 | drop Quit from `.notFound` | CAUGHT | caught, 7 tests |
| M3 | reorder so `.notFound` diagnoses as `.notRegistered` | CAUGHT | caught, 3 tests |
| **M4** | **the `.sheet` modifier deleted — the modal is never presented** | **SURVIVES** | **survived, all 1058** |
| M5 | the `@unknown default` arm returns `.available` | CAUGHT | caught, 3 tests |
| M6 | `.enabled` with no answer yet → `.notRegistered` | CAUGHT | caught, 3 tests |
| M7 | blank `.unreachable`'s message | CAUGHT | caught, 13 tests |
| M8 | `reportMayBeRaisedFromMenu` drops the gate clause | CAUGHT | caught, 11 tests |
| **M9** | **`helper.invalidate()` removed from the register path** | **SURVIVES** | **survived, all 1058** |
| M10 | Quit put before the remedy in `.notRegistered` | CAUGHT | caught, 4 tests |
| M11 | the trailing-period trim removed from `.unreachable` | CAUGHT | caught, 8 tests |
| **M12** | **the launch trigger never called** | **SURVIVES** | **survived, all 1058** |

**The three survivors are the increment's whole blind spot, and they are all one thing**: the wiring
lives in `USBDriveTesterApp.swift` and in a SwiftUI modifier, neither of which any harness compiles
or any test drives. M4 and M12 are that by *placement*, chosen deliberately — see decision 2 above.
M9 is the register path's `invalidate()`, unreachable by a test because reaching it means registering
a real daemon. **Chunk 13 of the human checklist is the cover for all three.**

**The harness reported a false disagreement, and that is worth recording.** Its agreement check was
`verdict.startswith(prediction)` — the prediction reads `SURVIVES` and the verdict reads `SURVIVED`,
so **every correctly predicted survivor was flagged as DISAGREEING**. It fired first on M4, the one
mutation whose survival is the *expected* result and therefore the one where a false alarm is most
likely to be read as a real finding. Fixed. Same family as increment 3's *"SURVIVED: all 0 tests
passed"* and the two stale probes of 2026-08-24 — **the instrument, not the product**, which is now
the fourth time in this step.

#### Four findings, none of them on the increment's list

- **A `nonisolated` type reading a `MainActor` computed property warns, and what it costs depends
  entirely on which file the property is in.** The first clean build produced exactly two source
  warnings, both in the new file. `ProtocolVersionCheck` is declared in an app-target file that
  nothing in `Shared/` or the helper references, so marking it `nonisolated` was **free**.
  `HelperIdentity.daemonPlistName` is a computed `static var` in `Shared/TesterControl.swift`, which
  the **helper compiles** — so the same keyword there moves the helper source hash and puts Step
  10's three hardware gates back in question. Increment 6 made exactly that change to
  `TesterProtocol` and verified the gates still stood by comparing `__TEXT,__text`, so the precedent
  and the method both exist. **It was declined here as disproportionate**: the message was naming
  the plist file, the remedy is "reinstall" and needs no filename, and
  `HelperRegistration.statusExplanation` already gives the full path in a window ⇧⌘D reaches from
  behind the gate. The message points there instead. Worth knowing why only *one* of the two
  references warned: `loggingSubsystem` is a `static let` of a `Sendable` type and is nonisolated
  already; only the computed property is not.
- **`SMAppService.Status`'s unknown arm is mandatory, reachable AND testable.** Measured rather than
  assumed, and it was about to be recorded as a blind spot. A switch over the four named statuses
  without `@unknown default` **warns** — failing the zero-warnings gate — and **traps at runtime**:
  `Fatal error: unexpected enum case 'SMAppServiceStatus(rawValue: 99)'`. And
  `SMAppService.Status(rawValue: 99)` **constructs**, so a unit test drives the arm directly. Both
  halves are now in BUILD-PLAN's Swift list.
- **Two punctuation defects that a full table walk could not see, both found by the first renders.**
  The messages passed every assertion — a sentence, ending in a full stop, naming its own remedy —
  and rendered as *"Sandbox restriction.. Choose Retry"* and *"Choose Open Login Items…, enable…"*.
  Both came from composing prose with a **fragment that punctuates itself**: a transport error's
  `localizedDescription`, and a button label carrying a platform ellipsis. Every assertion about
  those strings was a `contains`, which is blind to what sits either side. Fixed, and pinned by two
  tests written *after* the render found them.
- **The accent leak has a second reproduction and now a method.** `helper-gate-not-registered` and
  `helper-gate-version-mismatch` rendered their prominent button at **`#0079FF`** in one batch and
  **grey** in another — same commit, same `light`, minutes apart — while three consecutive renders of
  one view inside a batch were **byte-identical**. So it varies between invocations, not between
  views, which is what makes it read as a per-view defect. Diagnosed by sampling the most saturated
  pixel in the footer rather than by looking, which is twenty lines and turns "that looks grey" into
  a number. Full entry in CONSTRAINTS section 1.

#### One check failed and was corrected rather than loosened

`everyRemedyIsNamedInItsOwnMessage` demanded that each message contain its remedy button's **label**.
`versionMismatch` reuses `ProtocolVersionCheck.mismatch.description` — deliberately, so the wording
exists once — and that sentence reads *"Re-register the helper…"*. Insisting on the literal
"Register Helper" would have forced either a second copy of that sentence or a worse one chosen to
satisfy a test.

The fix is `HelperGateAction.messageStem`, matched case-insensitively — the precedent being
`PreRunControlsTests.theOneReasonNamesBothControls`, which matches substrings for the same reason.
**And a stem is only a check if it discriminates**, so `aMessageDoesNotNameARemedyItDoesNotOffer`
asserts the other way round: no message names a remedy it does not offer. Without that half, a stem
of `""` would pass everything. Same rule the device-operation slot check was built on — show it
answering both ways.

#### Checklist chunk 13 — items 1–6 and 8 PASS (2026-08-27/31). Three defects, two predictions falsified

~~**Item 7 is the only one left.**~~ **Item 7 passed 2026-09-01 — the chunk is complete.** It found
the `versionMismatch` remedy inert; see below.

Items 5, 6 and 8 passed on 2026-08-31 after the two fixes below landed, in one pass:

* **5** — *Run Report* is greyed in the Window menu under the gate, ⇧⌘R does nothing, and **nothing
  appeared when the gate cleared**. That is the check for chunk 11.11's defect: a window-modal sheet
  does not swallow menu commands, so without the gate clause ⇧⌘R would have queued a second sheet
  and presented it the moment the gate was answered. This item is the only cover that rule has.
* **6** — ⇧⌘D opens the diagnostics window from behind the gate. Wanted, not a leak.
* **8** — Refresh in that panel agrees with what the gate acted on. The log shows **one process
  throughout**, so one `HelperRegistration`; before increment 9 the panel built its own.

The transition item 3 ends on, read off the corrected instrument:

```
daemon status changed requiresApproval -> enabled
helper gate: available — modal dismissed, was requiresApproval
terminate requested: runIsActive=false disposition=quitImmediately
```

**Item 1 covers M12, not M4** — the checklist said M4 and was wrong. M4 replaces the `.sheet` with
`EmptyView` and prints `helper gate: available — no modal raised` unchanged; only a person seeing
the modal in item 3 covers it, and they now have.

**Item 3's own prediction was falsified.** Register Helper from `notRegistered` went **straight to
`available`**, not to `requiresApproval`: the BTM record survives an unregister — same `BTM uuid`
either side — so re-registering the same bundle path needs no fresh approval on a Mac that has
approved before. Item 3 therefore does **not** chain into item 4 here; `requiresApproval` is induced
with the Login Items toggle instead. Not an app defect; a checklist that only worked on a virgin Mac.

**Escape does nothing, before or after dismissal** — as the checklist said and *against* the
increment plan's prediction that it would dismiss and re-raise. The plan was reasoning about the
presentation layer from model code, which is the shape check 6.1 falsified.

Three defects, all reported at the keyboard:

| # | Defect | Fix |
|---|---|---|
| 1 | **The gate's Quit button was dead.** Pressed four times, all four presses on the log, app still running | **Took three attempts** — see below. Fixed by taking the sheet down through SwiftUI |
| 2 | **Returning from System Settings changed nothing** — the gate stayed up until Open Login Items was pressed a second time | Re-check on `didBecomeActive` while gated; message reworded |
| 3 | **The readiness banner still said the helper could not be asked** after it was working | **Not fixed — increment 10 deletes the banner**, and its plan already names this staleness |

**Defect 1's cause is bigger than the gate, and was measured rather than reasoned.**
`NSApp.terminate(_:)` is a silent no-op while a sheet is attached: AppKit refuses it *before*
`applicationShouldTerminate`, so `QuitPolicy` is never asked. **⌘Q was dead under every window-modal
surface in this app** — and there are **five**, not the three named here at the time: a SwiftUI
`.alert` is presented as a sheet, so the quit confirmation and the failure alert blocked it too.
That is the true cause of increment 5's check 6.1, which had a *guessed* cause sitting beside it in
`AppModel` for two increments. Fixed locally for the gate by user decision (*"fix the gate only and
proceed"*); **built app-wide as increment 12 on 2026-09-04**, which is where the count of five was
established.

Three earlier versions of the probe measured **nothing** — a SwiftUI `Window` scene launched from a
CLI binary never materialises a window, so every mode reported `sheets = 0` — and were caught only
because the probe asserted the sheet was attached before trusting its own verdict. The fourth,
in AppKit, gave the table now in CONSTRAINTS §1.

#### Defect 1 took three attempts, and the first two were wrong for the same reason

| # | Fix | Result |
|---|---|---|
| 1 | `terminateAction()` alone | Dead. AppKit refuses `NSApp.terminate(_:)` while a sheet is attached, before the delegate |
| 2 | `AttachedSheets.endAll()` then terminate | **Still dead.** `endSheet(_:)` does not take down a sheet SwiftUI presented |
| 3 | `helperGateIsPresented` goes false → SwiftUI dismisses → terminate next turn | **Works.** One press, verified on the log |

**Both failed fixes were built on probes that did not reproduce the app.** A plain AppKit sheet and a
SwiftUI sheet inside an `NSHostingView` each quit on the first attempt; the app uses a SwiftUI
`Window` **scene**, and three attempts to probe that shape measured nothing at all — such a scene
never materialises its window outside Xcode, run directly or through `open`, so `onAppear` never
fires. **What diagnosed it was logging in the shipped app.** The quit path emitted nothing until
2026-08-31; `applicationShouldTerminate` and `AttachedSheets.endAll()` now both report, and the
absence of `terminate requested` is itself the diagnosis. NFR-OBS-1, and owed anyway.

The confirmed sequence, one press, three consecutive runs:

```
helper gate action: quit from requiresApproval
ending sheets: 2 window(s), 1 sheet(s), 0 with no parent; 1 still flagged afterwards
terminate requested: runIsActive=false disposition=quitImmediately
```

`1 still flagged afterwards` survives the fix, which confirms `isSheet` was never the discriminator.

**Defect 2's fix retires the question increment 9 owed the user** — one button doing double duty
versus a third button on `requiresApproval`. Neither: the re-check has no button, and the action
table approved 2026-08-26 is unchanged.

#### And a test written for defect 1 changed machine state, and was rewritten

`noRemedyEndsTheSheet` walked `[.registerHelper, .openLoginItems, .retry]`, went green, and had
**really registered the daemon and really opened System Settings** — `register() succeeded` on the
log. `HelperRegistration` is built inside `AppModel` rather than injected, so those two cases reach
the real `SMAppService`. It would have done that on every run of `test.sh` from then on. Rewritten to
drive `.retry` only; the two undriveable cases are in the checklist's no-cover list, with items 3
and 4 as their cover.

**State after the follow-up:** 1064 tests / 134 suites, floor 1064. Zero Swift source warnings,
Debug and Release, DerivedData wiped. 13/13 gate clients. `window-fit-check` worst case **613 pt,
unchanged**. Render case list re-derived and identical to the probe at 36. Helper source hash
**unmoved at `73990c90…`**; protocol **v12** unchanged; app target only.

#### Chunk 13 item 7 — PASSED 2026-09-01, and it found the remedy inert

**Chunk 13 is now complete: all eight items pass.**

The four checks the item listed passed first time — the gate, both version numbers named, the
two-button footer, and Quit working from `versionMismatch` (a state the quit fix had not been
exercised against). **The item never asked anyone to press Register Helper**; it checked only that
the buttons existed in the right order. Pressed for the first time — to cover mutation M9 — it
**did nothing**, and the item now requires the remedy to actually clear the gate.

| # | Found | Fixed by |
|---|---|---|
| 1 | **`register()` on an already-`enabled` service is a no-op.** Same pid, same protocol version, `register() succeeded` on the log. The one state whose message prescribes re-registering was the one where re-registering could not work | `HelperRegistrationRemedy.forGate(_:)` → unregister-then-register |
| 2 | **A `register()` immediately after the removal settles is refused** (`Operation not permitted`), dropping the gate to `notRegistered` and costing a second press | `registerUntilAccepted(timeout:)` polls; the first attempt is refused and the second, 500 ms later, is accepted |

Both are now in CONSTRAINTS §1, with the measurements. The project already knew the answer to the
first: `install-app.sh` has printed *"(or unregister and re-register in the app's Step 3 panel)"*
since Step 4, and the app had never done the two-step.

**Confirmed by hand, one press, 732 ms end to end.**

#### The gate gained a busy state — user request, 2026-09-01

> *"I'm uncomfortable with the application letting the user perform a new action before the first
> one is completed."*

Correct, and it was a re-entrancy hole rather than a polish item: the remedy is a multi-step
sequence and every button stayed pressable throughout it, including during a real window where the
status is momentarily `notRegistered` — so a second press would have taken a different branch than
the one pressed.

Remedies are disabled while one runs, a spinner and a label appear, and **Quit stays live** — nobody
is trapped behind a modal, and a remedy whose callback never arrived would otherwise leave every
control dead. The label distinguishes *replacing* a running daemon from *installing* an absent one,
because those are genuinely different operations.

**The suggested hourglass cursor was declined.** macOS has no hourglass, the nearest equivalent is
the system's "not responding" cursor, and a cursor cannot be captured by the render harness — where
this is case 37, `helper-gate-busy`.

**The busy window is 732 ms and cannot be judged by eye.** The user watched for the buttons to grey
out, saw the progress label appear, and could not see the disable — which is drawn by the same
evaluation of the same view body. The log now brackets the window (`gate busy:` / `gate idle: …
finished after N ms`), because a state too short to watch is a state only an instrument can confirm.

**Quit landing inside that window is accepted rather than defended against** (user decision): the
registration still completes, the user is free to leave whenever they choose, and quitting
mid-replacement lands the next launch on `notRegistered`, whose remedy works.

#### The readiness banner's helper-unreachable branch is deleted

Reported three times while walking chunk 13 — *"The helper could not be asked…"* standing over a
working helper with ⇧⌘D showing `enabled` beside it. It is a snapshot taken at selection time,
refreshed only on selection change and mount change. Increment 10's plan already marked this branch
*"Superseded by increment 9"*; deleted early rather than ship another session with a banner that
lies. A failed readiness check now shows nothing — the gate carries that story app-wide, and Start's
own preparation refuses a run that cannot proceed. **The rest of the banner still goes in increment
10**, which is unchanged apart from having one fewer branch to delete.

#### Items 7.5 and 8.3 — PASSED 2026-09-01. The human checklist is complete

The last two debts, carried since increment 8.

**7.5 — a run allowed to reach its end.** Runs are whole-device and there is no size control, so the
drive chooses the duration: the **125.8 MB thumb drive** (serial `2211190533300386001515`) is the
only attached drive that finishes quickly. The 4 TB T5 EVO was not attached and is not needed —
7.5 reads report wording, not the restore set — and the **1 TB T5 (`12345686DAA9`) was excluded**
because its `/dev/urandom` fill file is a fixture this file says must be kept.

```
run authorised: drive serial 2211190533300386001515; I/O size 4194304 bytes
retention cycle END: completed; 30/30 chunks; read/wrote/verified 125829120 B each
run report: Completed — no currently-unreadable blocks were found
run report exported: outcome Completed; 3416 bytes
```

Whole device, 39 s, released cleanly, exported and compared against the screen. **A stopped run ten
minutes later on the same drive** then gave the comparison the item actually wants — the headline,
the row label and the caveat **change** between the two, rather than one of them being printed
unconditionally. That is the only cover `RunReportView` has: three mutations to it passed the whole
suite, two against 1,013 tests.

**8.3 — the moved sentence.** *"I/O size and failure handling are fixed once a run starts — stop the
run to change them."* is present before any run, sits directly above the I/O size row, and reads
identically while paused at a settled block (`run paused and settled at block 24576`, 3/30 chunks).
It does not move, change or disappear between the two states. **"Both controls" means the two
dropdowns**, not the run buttons — Resume and Stop stay live during a pause, and this was asked at
the keyboard because the wording did not say so.

**A correction made during this walk.** The tester was described to the user as destroying the
drive's contents. **It does not.** The cycle is read → write-back → verify (helper, "Step 8"), so the
same bytes are rewritten to refresh charge: `128MB_Thumb` remounted afterwards with its data intact.
Not risk-free — a write failing mid-cycle could still cost data — but "destroys the contents" is
materially wrong for a retention tester, and it is the kind of claim that changes which drive
somebody is willing to point it at.

### Increment 10 ✅ — FDA moves to Start; the readiness banner and the `Covering` row deleted. 2026-09-02, `6b809cc`

Built in three chunks with the suite green between each, at the user's direction. **App target only:
protocol v12 unchanged, helper source hash re-derived to `73990c90…` and unmoved**, so the two owed
Step 10 gates are exactly as owed as they were.

| | |
|---|---|
| **Verified** | **1088 tests, 0 failures, 135 suites** (floor 1088). 1073 → 1088 is exactly the 15 tests written and 134 → 135 exactly the one new suite |
| **Warnings** | zero from source, Debug and Release, DerivedData wiped. SwiftCompile Debug **88** / Release **2** — unchanged from increment 9, correct because no file was added |
| **Helper** | **untouched**, hash `73990c90…` |
| **Window** | `window-fit-check.sh` worst case **613 pt**, `content-starting` — **unchanged**, and that was predicted before it was measured; see below |
| **Renders** | **37 cases, unchanged.** An `.alert` cannot be rendered, so the new modal adds none |
| **Gate clients** | 13/13 type-check |

**Two things the plan did not predict, and one prediction that held.**

#### `Covering` was on three surfaces, not one

The plan's section is headed *"The `Covering` row is deleted"* and names only `RunMetricsView`. The
row was also on the **report sheet** and in the **exported Markdown**, and the prose explaining it
existed twice — once inline in the panel and once in `ThroughputFraming.definition`, which opens
*"All three rates…"* and feeds both report renderers.

**All three went** (user decision, taken at scoping 2026-09-02). Deleting two of three would have
left the report naming a figure the live panel refuses to name — and the report is the artefact a
drive's history is kept in, so the mislabel would have survived in the copy that gets forwarded and
re-read months later. `ThroughputFraming.definition` now says *"Both rates…"*.

**The wire field stays and is documented as deliberately undisplayed.** `coverageBytesPerSecond` is
still the ETA's quantity helper-side and still arrives in every reply; what changed is that no screen
shows it. CONSTRAINTS records *"a wire field nothing displays"* as a hazard — this is that field, and
the difference now is that its absence is a decision written at the site rather than an oversight.

#### `DeviceListView` no longer holds an XPC connection at all

Deleting the banner left `let helper: HelperConnection` unread — the banner was its only consumer.
Removing it changed five call sites (one in the app, four in `ui-probe`) and is worth more than the
tidiness: **the `devices*` renders no longer construct a connection**, so a render cannot reach this
machine's live daemon by accident. That is the ambient-state leak CONSTRAINTS records twice, closed
by construction here rather than by care.

It also **retired a note in the probe that had gone false**. The `devices` case carried a comment
explaining that the banner would render its *"could not ask the helper"* state offscreen — so one
region of every `devices` capture was showing a state peculiar to being rendered. That is gone: what
the render shows is now what a user sees.

#### The window-fit prediction held exactly

Predicted at scoping: the gate would barely move, and a null result would not be a failure. It
**did not move at all** — 613 pt before and after.

The plan estimated the pane loses "55–60 pt at the 3-volume fixture" and correctly flagged that as a
line count. Sharper than that, and now measured: **the harness has no daemon, so no render can ever
show a mounted-volumes banner** — every render showed the one-line *"Checking with the helper…"*
placeholder. And the banner sat inside the device-detail `ScrollView`, whose declared
`deviceDetailFloor` of 104 pt is what SwiftUI sums; deleting content inside a scroll region does not
move a declared floor. The real-hardware saving is on a state the gate cannot produce.

#### A live defect the deletion removed rather than fixed

PROGRESS and the source both claimed that after 2026-09-01 *"a failed readiness check now shows
nothing."* It did not: `readiness = nil` fell to the `else` branch and rendered **"Checking with the
helper…" indefinitely**. Harmless, and gone with the banner — recorded so the claim is not carried
forward as though it had been true.

#### What the FDA move actually gained

The check runs **after the selection check and before the unmount**. Three decisions taken at
scoping that the plan did not settle:

- **After the selection check**, not before it: that check is local and free, this one is an XPC
  round trip, and there is no reason to pay it for a drive that has gone.
- **Only a `denied` probe stops a run.** `.unknown` and a **transport failure** both carry on, and
  the acquire's helper-side precondition decides. Aborting on "could not ask" would make an
  unreachable helper indistinguishable from a missing permission and offer a remedy for a problem
  the user does not have.
- **A two-button `.alert`, not a sheet.** Precedent both ways — `ContentView`'s quit confirmation is
  a two-button alert and the existing preparation-failure path is an alert — against increment 9's
  renderable gate sheet. The alert keeps one modal idiom for one class of outcome; the cost is
  stated rather than discovered: **the dialog has no render cover at all** and chunk 14 item 4 is
  the whole of it.

`RunFailureMessage` gains a defaulted `remedy`, and `OutcomeOperation.remedy` is the exhaustive
mapping that decides it — so a future operation with a fix is a compile error rather than a
button-less dialog. `RunFailureRemedy` owns **both** labels, and `dismissLabel` — *"Cancel Test"* —
is where "both buttons end the run" is written down: by the time the dialog is up the start has been
abandoned, and "OK" would leave that ambiguous.

**`OutcomeOperation.fullDiskAccess` is the first case there that can only fail**, and
`successIsSelfEvident` returns `true` with the asymmetry stated at the site. Nothing constructs a
success outcome for a precondition, and answering `false` would invent an "access was granted"
message no code path can produce.

#### Two traps paid for, both already written down

- **`#expect`'s comment argument is a `Comment`, expressible by a string *literal*.** `"a" + "b"` is
  a `String` expression and will not convert. It cost two failed compiles, in new test comments.
  BUILD-PLAN's Swift list already says this.
- **`sips --cropOffset` was silently ignored**, returning the source image unchanged with no error —
  exactly as CONSTRAINTS records. Reading the full-height render is the way round it.

#### A recorded blind spot is smaller than it says

CONSTRAINTS and the checklist both list the report body under *"no automated cover, and will not get
any"*, because *"a render stops at `## Measurements`"*. **That is a function of the height renders
were taken at, not of the scroll region.** At `render-ui.sh out.png 720 1500 report` the region has
nothing left to hide and the **whole** body renders — claim sentences, both framing paragraphs and
the closing section. That is how this increment's rewrite of `ThroughputFraming.definition` was
checked, and it is the first time that wording has been read in the artefact rather than the source.
Corrected in both places.

#### Still owed

~~**Chunk 14 of the human checklist**, added by this increment and unwalked.~~ **Walked and passed
in full 2026-09-02**, all seven items, no product defect. Item 4 was the only cover the FDA modal
has and the only check anywhere that the remedy button *does anything* — the launch gate shipped a
remedy whose first press, in chunk 13, did nothing at all. This one opened System Settings at the
right pane, and **no volume had been unmounted**, which is the ordering the placement decision
rests on.

**It needed a rebuild before it could start.** `/Applications` held a build from 2026-09-01 15:24,
predating this increment; the first three items would have been walked against the build the chunk
was written to test the replacement of. `strings` could not settle it either way — the control
literals were absent too, so the test was inert — and the timestamp was the evidence. **Reinstall
before walking a chunk that covers an increment**, and kickstart the daemon after: `install-app.sh`
replaces the helper binary underneath a running daemon and nothing announces the mismatch when the
helper source has not moved.

**No mutation round has been run for this increment.**



### Increment 11 ✅ — `R-W-R-C speed`, then FR-METR-1 amended mid-increment. Protocol v14. 2026-09-02/03, `05b7ea7`

**Two changes in one increment, and the second reversed part of the first.** Built in eight chunks
with the suite green between each. Chunks 1–3 added `R-W-R-C speed` on protocol v13; chunks 4–8
amended FR-METR-1 and moved the three displayed rates onto phase time, taking the protocol to v14.
The requirement change is recorded in
[functional-requirements](functional-requirements-usb-drive-tester.md), *2026-09-02 — FR-METR-1
revised*, including why it is not a reversion to the 2026-08-18 defect.

| | |
|---|---|
| **Verified** | **1093 tests, 0 failures, 135 suites** (floor 1093). 1088 → 1093 is +2 (chunk 1), +1 (chunk 3), +1 net (chunk 4: one test replaced, two added), +1 (chunk 6). No new suite |
| **Warnings** | zero **from source** across three clean builds with DerivedData wiped before each. SwiftCompile **Debug 88 / Release 2 / test 171** — Debug unchanged from increments 9 and 10, correct because no file was added to the app target. The one `warning:` line in a clean build is `appintentsmetadataprocessor`, a toolchain notice with no source location |
| **Helper** | hash moved three times across the increment: `73990c90…` → `827b3760…` (v13, chunk 2) → `417c55ae…` (chunk 4) → **`e6888aa5…`** (v14, chunk 5). **`e6888aa5af72…3f627` at `05b7ea7`** — the tree `metrics-check.sh` actually ran against. **Still `e6888aa5…` at `9fead44`**, the app-icon commit on top of it: that commit's diff contains no `.swift` file at all, so every gate result in this table still stands at `HEAD`. Recipe: `find <helper> <Shared> -name '*.swift' \| sort \| xargs cat \| shasum -a 256` |
| **Window** | `window-fit-check.sh` worst case **613 pt**, `content-starting` — **unchanged**, predicted before measured, twice |
| **Renders** | **37 cases, unchanged** across both changes; **74/74 taken at the gate**, every case in both appearances, none blank |
| **Gate clients** | 13/13 type-check |
| **Hardware** | `metrics-check.sh` **128 PASS / 0 FAIL** on the 1 TB scratch T5 (`disk7`, serial `12345686DAA9`), daemon at **v14**. The reciprocal identity holds at all four I/O sizes with a **residual of 0.00000%** — see below |
| **Mutations** | **9 in the gate round, 7 caught, 2 survived — both declared in advance.** Covers increments 11 and 10 in one round, at the user's direction. Eight more were run during the chunks; two of those found real gaps rather than confirming cover — see below |
| **Human checklist** | **chunk 15 walked 2026-09-03 — five items, all passed, no product defect.** Two of its original seven were deleted unwalked. Written at chunk 15 of this increment and walked after the commit; the walk is recorded below |

#### The mid-increment reversal, in one paragraph

The user asked why displayed Write was about half displayed Read. The answer is that it was not a
property of the drive: both rates divided by running time, and a cycle reads every byte twice and
writes it once, so the 2:1 came from the cycle's shape on any medium. The 4 TB T5 EVO's *phase*
rates were logged the whole time at `read 375.8, write 418.9` — **it writes faster than it reads**,
and the displayed pair inverted that. The user's conclusion was that the figures answered the wrong
question, and FR-METR-1 was amended.

#### Two mutations found gaps instead of confirming cover

**The disclaimer was unasserted.** `ThroughputFraming.definition`'s "not comparable to Activity
Monitor" clause is the entire reason the amendment is defensible — an undisclaimed figure 3.4× what
another window shows is how the 2026-08-17 report happened. Deleting the sentence outright left all
1092 tests green: the rate-naming test checks *which* rates are named, and the framing test compares
the document against the constant, so both move together when the constant is edited. Closed by
`theDefinitionWarnsThatTheFiguresDoNotMatchAnOutsideObserver`, which requires the tool to be named
**and** the sentence naming it to be a denial — naming alone passes on the pre-v14 wording, which
named the same tool to promise agreement.

**`metrics-check.sh`'s first replacement assertion was worthless.** The reciprocal identity does not
contain covering, so moving covering to phase time too would have passed every check in the file
while inflating the ETA's denominator — the 2026-08-18 pause defect in a new place. The first attempt
anchored covering against the read rate, where running time gives 0.33× and phase time gives 0.35×:
any band loose enough for a real drive contains both. Re-anchored against `R-W-R-C`, which counts the
same bytes on a clean run, so the ratio *is* the I/O fraction of running time (0.944 measured) and the
defect lands exactly on 1.0.

#### What replaced the equality R-W-R-C was built on

Increment 11's own settled premise — *on a healthy run the new figure reads exactly the same as
Write* — held only while both divided by running time. It is gone. All three displayed rates now
share a denominator, so on a clean run:

    1 / R-W-R-C  =  2 / Read  +  1 / Write

**Exact, not a band**, because host overhead is in none of the three. This replaced
`metrics-check.sh`'s `read ≈ 2 × covering, write ≈ 1 × covering`, which needed ±10–20% because
covering carries overhead the rates do not. Measured against it: reverting R-W-R-C to running time
moves the figure by **0.2%** and is caught four orders of magnitude inside tolerance; the old band
would have missed the same defect by a factor of fifty.

The cost is on screen. `R-W-R-C` is a per-cycle rate beside two per-phase rates, so a **flawless**
run reads about `Read 376, Write 419, R-W-R-C 130`. A row a third the size of its neighbours on good
hardware is the shape of the original bug report, which is why the definition paragraph states the
healthy case before it names the gap.

#### Protocol v14 is the quiet kind of bump

**Both replies kept their arity** — 22 and 13. Slots 14/15 swapped the wall-clock pair for the phase
rates; slot 17 kept its name and changed its denominator. Every previous version changed shape
somewhere, so a mismatched pair failed to decode. **A v13 app against a v14 daemon decodes cleanly
and shows numbers low by the ratio of running time to phase time.** When the constant moved, exactly
one test in 1092 failed; the compiler had nothing to object to. `metrics-check.sh`'s prerequisite
note now says not to read its numbers until the daemon is reinstalled, because they will look almost
right.

#### The identity, measured

`metrics-check.sh` on the 1 TB scratch T5, all four I/O sizes, `chunksFailed` 0 throughout:

| I/O | Read | Write | R-W-R-C | identity predicts | covering ÷ R-W-R-C |
|---|---|---|---|---|---|
| 1 MiB | 486.7 | 489.6 | 162.6 | 162.6 | 0.972 |
| 2 MiB | 486.6 | 488.8 | 162.4 | 162.4 | 0.975 |
| 4 MiB | 479.1 | 489.0 | 160.8 | 160.8 | 0.975 |
| 8 MiB | 480.4 | 488.4 | 161.0 | 161.0 | 0.975 |

**The residual is 0.00000%**, not "within tolerance". The gate allows 2% for a real drive's jitter
and did not need any of it: the three rates are computed from the same accumulators with host
overhead in none of their denominators, so on a run where nothing fails the identity is exact to
floating point. **A band could not have done this.** The `read ≈ 2 × covering` check it replaced ran
at ±10–20% because covering carries overhead the rates do not; here the same 2.5% of running time
that is *not* I/O shows up cleanly as the covering ratio instead of contaminating the assertion.

**This drive reads and writes at nearly the same speed** — 487 against 489 — where the 4 TB T5 EVO
writes markedly faster than it reads, 376 against 419. Both are correct and the difference is the
hardware's. Worth knowing before reading chunk 15, whose expected figures are the T5 EVO's: **"Write
above Read" is a property of that drive, not of the amendment.**

#### The identity, measured

`metrics-check.sh` on the 1 TB scratch T5, all four I/O sizes, `chunksFailed` 0 throughout:

| I/O | Read | Write | R-W-R-C | identity predicts | covering ÷ R-W-R-C |
|---|---|---|---|---|---|
| 1 MiB | 486.7 | 489.6 | 162.6 | 162.6 | 0.972 |
| 2 MiB | 486.6 | 488.8 | 162.4 | 162.4 | 0.975 |
| 4 MiB | 479.1 | 489.0 | 160.8 | 160.8 | 0.975 |
| 8 MiB | 480.4 | 488.4 | 161.0 | 161.0 | 0.975 |

**The residual is 0.00000%**, not "within tolerance". The gate allows 2% for a real drive's jitter
and did not need any of it: the three rates are computed from the same accumulators with host
overhead in none of their denominators, so on a run where nothing fails the identity is exact to
floating point. **A band could not have done this.** The `read ≈ 2 × covering` check it replaced ran
at ±10–20% because covering carries overhead the rates do not; here the same 2.5% of running time
that is *not* I/O shows up cleanly as the covering ratio instead of contaminating the assertion.

**This drive reads and writes at nearly the same speed** — 487 against 489 — where the 4 TB T5 EVO
writes markedly faster than it reads, 376 against 419. Both are correct and the difference is the
hardware's. Worth knowing before reading chunk 15, whose expected figures are the T5 EVO's: **"Write
above Read" is a property of that drive, not of the amendment.**

#### The gate's mutation round — increments 11 and 10 together

| | Increment | Mutation | Predicted | Actual |
|---|---|---|---|---|
| M1 | 11 | successful work counted as `!isPhaseFailure` | caught | caught — 3 tests |
| M2 | 11 | `R-W-R-C` reverted to the v13 denominator | caught | caught — 2 tests |
| M3 | 11 | failed-phase time folded into `R-W-R-C`'s denominator | caught | caught — 1 test |
| M4 | 11 | pooled read bytes over one phase's time | caught | caught — 4 tests |
| M5 | 11 | **helper sends the v13 wall-clock pair on the wire** | **SURVIVES** | survived |
| M6 | 11 | **panel row wired to Write** | **SURVIVES** | survived |
| M7 | 11 | the disclaimer inverted back to the v13 promise | caught — 1 test | caught |
| M8 | 10 | Full Disk Access widened to "not known to be granted" | caught | caught — 1 test |
| M9 | 10 | the deleted `Covering` row returns to the export only | caught | caught — 3 tests |

**Both survivals were declared before the round and are structural, not gaps.** M5 sits in the
helper's reply assembly, which no unit test can reach — `metrics-check.sh`'s REPLY/FINAL agreement
loop is its only cover, on hardware. M6 is a SwiftUI binding, which nothing drives — the renders are
its only cover, which is why `ui-probe`'s running fixture carries a deliberate visible divergence.

**M8 had to be run twice, and the first attempt is the more useful result.** It was written as
`blockingCause != .none`, which does not compile: the enum has no such case. The round recorded it as
"caught" because the suite did not succeed — and that is the wrong conclusion from the right
observation. **A mutation that does not compile is not a result**: it proves the anchor was wrong,
not that anything is covered. Re-run as `== .accessNotPermitted || == .checkIncomplete` — the exact
widening `needsFullDiskAccess`'s doc comment forbids — it was caught by
`onlyTheDeniedCauseStopsTheRun`, a test named for the invariant. A driver that reports pass/fail
without distinguishing a build break from a test failure will manufacture confidence; this one now
prints the test count, which is what exposed it.

#### Three smaller findings

- **A count in prose had been wrong through two edits.** `RunMetrics.swift`'s rate table read "Five
  rates" over six rows at `HEAD`, and chunk 1 made it "Six" over seven. Removed rather than
  incremented, in both that file and `RunMetricsTests`.
- **A blanket rename rewrote history.** Renaming the app-side `sustained*` properties to match what
  they now carry also rewrote a sentence in `RunCycleOutcomeTests` recording what those names *used
  to be*, into nonsense — and it compiled, because prose does not. Repaired; the rest of the rename
  set was audited for the same damage and that was the only site.
- **A render fixture contradicted its own headline.** The clean `report` case was first given a
  divergent R-W-R-C, rendering a sheet that said "every comparison matched" above a rate that only
  falls when comparisons did not. Caught by reading the rendered sheet. The rate is now a parameter,
  clean by default, with `report-failures` passing a degraded one.

#### Corrections to earlier records

**Increment 10's `metrics-finished` claim was wrong, and this increment repeated it before catching
it.** That render case carries a fully populated snapshot and renders the **placeholder** — that is
the assertion it exists to make — so its figures never reach a pixel. A comment claiming both the
clean and divergent panel states were "on a render" was inherited and restated in chunk 3 before
being checked. Corrected in `ui-probe`. The clean case is on the report render instead.

**Still owed, unchanged by this increment:** no mutation round for increment 10;
`xpc-concurrency-check.sh` and `retention-cycle-check.sh` from increment 8. The helper hash moved
again here, so both remain owed on the same terms.

> **Both were run on 2026-09-03, at this increment's hash `e6888aa5…`, and both passed** — see
> *The last two hardware gates* below. Increment 10's mutation round was folded into increment 11's
> at the user's direction and is recorded in this increment's table.
>
> ⚠️ **This said "nothing is owed for Step 11 any more: not a checklist chunk, not a gate script",
> and that was wrong on the day it was written** (2026-09-03), corrected 2026-09-04. It counted
> Step 10's three gates and forgot Step 11's own — **`run-control-check.sh`**, which had last run
> on 2026-08-24 against a **v12** daemon. This very increment took the protocol to **v14**, so the
> sentence was made false by the commit it was written to describe. Step 11's verification gate
> rests on that script for items 2, 3 and the helper-side half of 5, so **Step 11 has not been able
> to close since increment 11 landed** and nobody noticed for a day.
>
> The pattern is this file's own and it is now on its fourth outing: a status claim written from
> the increment in front of you, counting the things that increment touched and silently omitting
> the ones it did not.

#### Chunk 15 walked — 2026-09-03, after the commit. Five items, all passed

Against the build installed at 12:52 and daemon PID 71058, up since 13:08:46 — the same daemon that
passed `metrics-check.sh` 128/0. **The build was proved to be v14 before the walk started, by symbol
rather than by timestamp**: `deviceReadBytesPerSecond` present 30 times in the installed binary,
`sustainedReadBytesPerSecond` **zero** times, `not comparable to Activity Monitor` present,
`directly comparable` absent. That pre-flight exists because chunk 14's walk was blocked by a stale
`/Applications` build and had to be restarted; it costs seconds and it settles the question a
timestamp only suggests.

| | 4 TB T5 EVO | 125.8 MB thumb |
|---|---|---|
| `Read` / `Write` / `R-W-R-C` | 344 / 419 / 122 MB/s | 17 / 5 / 3 MB/s |
| Activity Monitor read / write | 232 / 118 MB/s | not read |
| identity residual | **0.047%**, and **0.19%** on a second run | unresolvable at 1 MB/s granularity |

**The disclaimer is true, which is what the chunk existed to establish.** App Read ÷ Activity
Monitor read = **1.48×** against the ~1.5× the report claims; app Write ÷ its write = **3.55×**
against ~3.4×. Nothing in the suite can produce those four numbers, and until this walk the report
had been asserting a disagreement that had never been observed.

**Activity Monitor turned out to be worth more than the item asked of it, in three ways.**

* **232 ÷ 118 = 1.966.** An instrument outside the app confirming the cycle moves two reads per
  write. Nothing else in the project checks the cycle's shape from outside.
* **Its write figure *is* `coverageBytesPerSecond`** — the `Covering` row increment 10 deleted —
  recovered from an instrument sharing no code with the app, and landing **inside
  `metrics-check.sh`'s own band**: 118/122 = 0.967 against a band of 0.80–0.995.
* **Host overhead measured 3.28% of running time.** The whole amendment rests on that overhead
  being present in the running-time denominator and absent from the phase-time one. It had been an
  argument; it is now a number.

**Read and Write no longer share a ratio, and two drives demonstrate it in opposite directions.**
The thumb drive reads at 3.4× its write speed; the T5 EVO writes at 1.2× its read speed. Under v13
both would have read exactly 2:1, because that ratio was a property of the cycle rather than of the
hardware. That is the amendment's whole purpose, observed rather than reasoned.

**Both exports matched `ThroughputFraming.definition` character for character** — 819 chars, two
drives, diffed against source reconstructed from the Swift literals rather than compared by eye. The
sheet's own rendering was confirmed from a `render-ui.sh out.png 720 1500 report` that was **looked
at**, not merely produced, and the sheet was separately confirmed to display the thumb drive run's
real values (`17 / 5 / 3 MB/s`, `480 Mb/s`) — the row wiring on real data, which no test reaches.

**The pause item passed with corroboration from the export.** 40.0 s of I/O reconstructed from the
report's own rates, against check 7.5's independent record of *30 chunks in 39 s* on that drive;
elapsed 83 s, leaving 43 s of pause and overhead. Had running time counted the pause, coverage would
have fallen about 1.9× and taken the ETA with it.

##### No product defect. One defect in the checklist, and it was inverted

**Item 4 — "the idle panel shows dashes, not zeroes or minus ones" — was deleted mid-walk.** There
are no rate rows before a run: `RunMetricsView` shows `idlePlaceholder` instead, and the
rows-behind-the-placeholder state the item described is **a defect that was found and fixed** — the
placeholder is *"replaced rather than overlaid"* precisely because an overlay once left em-dashes
visible behind it. **So the item would have passed on the broken build and invited a false failure
report on the correct one.** The walker read the screen, recognised the placeholder as correct, and
reported the item rather than the app.

**This file already contained the correct description.** Check 11.4, walked and passed 2026-08-20,
says the idle panel is *"exactly its two lines of copy"* — 600 lines from the item that contradicted
it. Writing a new checklist item did not include reading what the checklist already said about the
same screen. And the em dash was never uncovered:
`unmeasuredFiguresRenderAsAnEmDashAndNeverAsZero` drives the wire sentinel `-1` through `RunReport`
into the rendered markdown and asserts `—` on all three rows, end to end.

**Two stale cross-references were found in the same chunk**, both left by the *first* deletion:
the "what no test can see" bullet still said the Activity Monitor check was "item 3" when it had
become item 2, and de-numbering item 4 left two entries numbered `4.` until it was caught. **Three
numbering defects in one chunk of five items** — a deletion is not finished when the item is gone.

**Item 1's expected figures were point values and have been widened to bands.** They were taken from
`ui-probe`'s fixtures (376/419/130); the walk read 344/419/122, and the walker reported Read as
"about 10% too high", which is a defect report against healthy hardware. Write landed exactly and
`R-W-R-C` moved *because* Read did — the identity predicts 121.9 from 344 and 419. One figure
drifted and the other two followed it correctly. **Item 3 is the test; the absolute figures are
not.**

**Item 3 cannot be walked on a slow drive**, and that is arithmetic rather than a fault: at 17/5/3
MB/s every figure is rounded to a whole MB/s before display, which puts the prediction anywhere in
`[2.912, 3.377]` against an observed bucket of `[2.5, 3.5)`. Recorded at the item.


#### The last two hardware gates — run and passed 2026-09-03, at hash `e6888aa5…`

Owed since increment 8, and owed the whole time because the **helper binary moved**, never because
anything failed. Both were run against the daemon installed at 12:52 and kickstarted at 13:08:46.

**`xpc-concurrency-check.sh` — 0 failures. The increment 8 finding is unchanged.**

| | |
|---|---|
| same connection | **serialized** — 25 pings, 0 answered during the call, 25 after |
| second connection | **concurrent** — 24 pings, all 24 answered during, worst 5.0 ms |

Read-only; it changed mount state and restored it (1 volume before, 1 after). The digest held the
daemon for 2865.6 ms, a wide enough window to test, and 49 pings were issued underneath it. **This
is the measurement Step 9's design rests on** — a poll on the run's own connection cannot be
answered mid-call, which is why the GUI polls `runProgress` on a second, non-owning connection.

**`retention-cycle-check.sh` — 15 checks, 0 failures, over the WHOLE DEVICE.**

    The cycle wrote 1072693248 bytes at block 1482268672 and the whole device
    is byte-identical afterwards.

932 window fingerprints before, 932 after, `COVER_START=0`, `COVER_BLOCKS=1953525168` — the full
gate, not `--quick`. 256 chunks (255 full + 1 short, exercising FR-TEST-5), 0 failed ranges, cache
bypass verified, fastest read 491,438,414 B/s, buffers 2 × the I/O size (NFR-PERF-1).

**The fill-file alarm fired again and was again a false alarm.** `df` reported `disk7` 1% used and
the script warned that a random placement would land on unwritten space. It did not: the three
sampled chunks returned three distinct fingerprints, so the residual `/dev/urandom` pattern is
intact — the same finding as 2026-08-25, and for the same reason. **An unlink clears the allocation
table, not the media.** The `fill.bin` fixture is still worth restoring, because a drive that
decides to discard those blocks would put the next run straight back to zeros with no warning.

##### The first full attempt produced complete evidence and no verdict

The first run of the full gate did all 88 minutes of work — acquire, both fingerprint passes, the
cycle, release, mount restore — and then **exited 1 at its very first assertion**, because
`/tmp/usbdrivetester-cycle/client-output.txt` did not exist when `sed` read it. `tee` holds that
file open for the whole run and its stdout still reached the log, so the mechanism is consistent
with the file being **unlinked mid-run** while tee went on writing to a detached inode. **What
unlinked it is not established**, and is not guessed at here: `tee` to that exact path succeeds
foreground, background, and in a reproduction of the script's exact pipeline shape, and a
`--quick` re-run over the same placement printed its full 15/15 verdict a minute later.

Every assertion was recoverable from the artefacts — the two digest files were byte-identical with
matching SHA-256, the three probe digests were distinct, the cycle reported 256/256 and 0 failed
ranges — **and that hand-evaluation was not treated as the gate passing.** A gate that did not
print its verdict has not passed; that is this project's own standard, recorded in `CONSTRAINTS.md`
for mutations that do not compile. The full gate was re-run at the same start block, which is what
the 15/15 above is.

**Cheap protection for the next long gate:** `--quick` at the same placement exercises the whole
harness path in about a minute. It is not evidence — the script says so loudly, and it cannot see a
write that landed outside the margin — but it establishes whether the reporting path works before
88 minutes are spent on a run that may not be able to report.


### Increment 12 🟨 — ⌘Q under every modal. Built 2026-09-04, walk owed. `7860f54` + `a0d8881` + `7106dd3` + this commit

**The full account of each chunk is in its commit message; this is the summary.** App target only,
**helper hash unmoved** at `e6888aa5…13f627` — checked after every chunk, because if it moved,
increment 11's three hardware gates would lapse with it.

#### What the defect actually was, which is not what the plan said

`NSApp.terminate(_:)` is a silent no-op while a sheet is attached — AppKit refuses it *before*
`applicationShouldTerminate`, so `QuitPolicy` never voted. The plan's fix was *"a rule per sheet"*,
and the load-bearing fact underneath that was never written down: **⌘Q under a sheet runs no code of
this app's at all**, so there is no quit path to put a rule in. What *does* run under a sheet is an
**app-declared menu command** — measured for ⇧⌘R on 2026-08-21 and for a declared ⌘Q in chunk 0. So
the increment is a `CommandGroup(replacing: .appTermination)` first, and a rule second.

**Two of the plan's statements were wrong and are corrected at their sites:**

| Plan said | Actually |
|---|---|
| three sheets: the pre-run dialog, the report, the gate | **five window-modal surfaces** — a SwiftUI `.alert` on macOS is presented as a sheet, so the quit confirmation and the failure/FDA alert block ⌘Q identically. Found by grepping for every modal rather than trusting the list |
| *"no delay is needed and none should be used"* | one `scheduleOnNextTurn` hop **is** required. That bullet was the AppKit probe's measurement; a sheet SwiftUI owns comes down only when its presentation state reads `false`, measured in the shipped app 2026-08-31. The hop is not a wait for an animation |

#### Which modals a quit may discard — user decision, 2026-09-04

The report and the launch gate: discarded, and the app goes. The pre-run prompt, the failure alert
and the quit confirmation: **refused visibly**, with the menu item greyed. More than one flagged:
refused, because the model cannot see SwiftUI's presentation queue and so does not know which one is
on screen.

**The failure alert is the only modal a user did not open**, so a ⌘Q at that instant is now refused
rather than obeyed. That was flagged at the time and chosen anyway; chunk 16 item 4 asks a person
whether it reads well at the keyboard.

**It answers a question checklist 11.7 left open on 2026-08-21** — *"whether the report ought to
block quitting … deliberately left open until this has been seen"*. It has been seen; it ought not.

#### The four chunks

| | | |
|---|---|---|
| **0** | `7860f54` | The app's own Quit command, behaviour-neutral. A pre-flight: the whole design rests on a *declared* ⌘Q firing under a sheet, and that was measured for ⇧⌘R only. **Walked at the keyboard, five surfaces, all five fired.** 1093 → 1097 |
| **1** | `a0d8881` | `AppModal` + `QuitPolicy.disposition(underModals:)` — the truth table, pure and exhaustive. 1097 → 1112; mutation 3/3 caught |
| **2** | `7106dd3` | The wiring: `presentedModals`, `mayQuitFromMenu`, `dismissThenTerminate(_:)`, `dismissForQuit(_:)`, and the log instruments. 1112 → 1121; mutation **6/6 caught** |
| **3** | this commit | Docs and the stale-claim sweep. No behaviour change |

**1121 tests, 0 failures, 136 suites in 49.5 s**, floor ratcheted at every chunk. Two of the new
tests walk **all 32 combinations** of the five surfaces rather than the ones someone thought of —
which is the mistake this increment exists to correct: three sheets were added over three increments
and each silently killed ⌘Q, because nothing had to have an opinion about the new one.

#### A design flaw caught before it was written

Chunk 1 was first specified with the precedence order alone deciding everything, on the claim that
*"a `dismiss` answer implies exactly one modal flagged"*. It does not: `topmost` of
`{helperGate, runReport}` returns `.helperGate`, which is discardable, with two flagged. The table
now takes the whole `Set` and refuses outright when more than one is present, so the property is
**structural** rather than argued, and `everyAmbiguousSetIsRefused` walks all 32 subsets to say so.
Precedence's only remaining job is choosing which sentence a refusal gives.

#### The gate's own Quit button shares the mechanism and not the decision

`quitFromGate()` is one line into `dismissThenTerminate(.helperGate)` and deliberately does **not**
consult the table. That button *is* the decision, taken by a user looking at a screen they cannot get
past; routing it through the policy would make it refuse whenever a second modal happened to be
flagged. Mutation **M6** is exactly that tidiness, and it is caught.

#### Chunk 16 — WALKED AND PASSED IN FULL, all nine items, 2026-09-04

Written and walked the same day. **It found one defect in the product and three in the checklist**,
and it settled a belief the app had acted on for three increments without measuring.

**The open observation carried into the walk was the defect.** It was recorded as *"the wind-down's
own terminate fires while the confirmation alert may still be dismissing, and `QuitSequence` logs
nothing, so that path has no observability"* — and 16.5 found that **`Cancel and Quit` did not
quit**. `RunController` raises the report sheet before it releases the drive, so the wind-down asked
AppKit to terminate with a sheet attached and was refused before `applicationShouldTerminate`. Every
other route was fixed by increment 12; this one was never routed through the fix. **Since increment
8 (2026-08-22), thirteen days.** Chunk 6.3 passed on 2026-08-18, four days before the report became
a sheet, and was never re-walked. Fixed in `8f6be8e`; 6.3 re-walked and passes, in the hardest form
of the state — the confirmation left up until the run finished under it, so the report was raised
behind it.

**A SwiftUI `.alert` IS a window-modal sheet**, measured by 16.7 at the keyboard:
`state=confirming; 2 window(s), 1 sheet(s) [_NSAlertPanel]; key=_NSAlertPanel`. So the **five**
surfaces this increment claims are right and the increment plan's *"three sheets"* was wrong. The
class name differs from a `.sheet`'s `SheetPresentationWindow`, which is why the inventory prints
names rather than a bare count. CONSTRAINTS §1 carries both.

**Three defects in the checklist itself, all found on first walk:**

| Item | What was wrong | Fix |
|---|---|---|
| **16.4**, and **7.8** it was copied from | The induction no longer works: pulling a *selected* drive moves the selection, and Start runs a good test on the next drive. 7.8 has said it since increment 5 | Pull it while the pre-run dialog waits — the device is captured in `PendingStart` at the press |
| **16.7** | Unwalkable. It asked for a reading off a log line that carried no inventory — that was on the `error` branch only, and this is the `notice` branch | Inventory on both branches, plus `state=` |
| **16.8** | Unusable. **112 false errors in six hours**, 17 per run of `test.sh`: the suite is hosted inside the app, stubs `terminateAction`, and so trips a backstop whose premise is that the termination is real | `terminationIsInjected`. The report belongs with the real termination, not with its callers |

**16.5 failed once and did not reproduce.** The second ⌘Q under the confirmation was not greyed, and
the model read `confirming=false`. With 16.7's measurement in hand the failing log can be read: it
showed `0 sheet(s)`, and an alert on screen reads `1 sheet(s)`, so the dialog really had gone and
the model was right. **Something dismissed it, and that is not explained.** Recorded at the item
rather than deleted.

#### What is owed

**Re-walks of 6.1 and 11.7** at expectations increment 12 changed, and increment 12's close (three
clean builds, DerivedData wiped, hash re-derived). **A reinstall comes first** — `/Applications`
predates `863d59f`.


### Step 11's verification gate — WALKED AND PASSED 2026-08-24, all five. ⚠️ **THREE ITEMS ARE NOW STALE**

> ⚠️ **Re-run items 2, 3 and 5 before Step 11 closes (noted 2026-09-04).** All three rest on
> `scripts/run-control-check.sh`, which last ran on 2026-08-24 **against a protocol v12 daemon**.
> The protocol is **v14** since increment 11, and the helper hash moved with it — so the daemon that
> evidence was taken from no longer exists.
>
> **This is the same staleness the gate itself corrected once already**, and it wrote the rule down
> at item 2: *"The evidence this replaces was taken 2026-08-12 against a v10 daemon, two protocol
> bumps back"*, and *"a gate that has not been re-run cannot report anything."* Two protocol bumps
> back is exactly where it is again.
>
> Items **1** and **4** are unaffected: item 1 is unit tests over `RunControlPolicy`, which run on
> every build, and item 4 is checklist chunk 7.4, an app-side observation with no daemon in it.
>
> **`run-control-check.sh` writes to the scratch drive**, so it must not run while the 1 TB T5's
> `fill.bin` is being restored. **That restore finished 2026-09-04 18:19:30, so it no longer blocks
> this check.** Nor is the check a threat to the fixture once it runs: its cycle writes back exactly
> the bytes it reads, which is the property it exists to test.


BUILD-PLAN's five items, each ticked against named evidence rather than recollection. The walk is
recorded at the gate itself.

Four were discharged in the morning. **Item 5 took the rest of the day** and needed two things that
did not exist: a check for the device-operation slot, which had no cover at all (`cbb1b3b`), and a
human walk of the checklist's chunk 8, whose items 3–7 had been unrun since 2026-08-19 while the
file's summary line claimed otherwise.

**Chunk 8 item 7 is the check that mattered most.** It follows a chosen I/O size from the dropdown,
through the pre-run gate, into every bounded call, onto the report screen and into the exported
Markdown — four surfaces, and the only place anything sees all four at once. They agreed on `8 MiB`.
Mutation M15, *the dropdown does nothing at all*, passes the entire 1025-test suite; no test drives
a SwiftUI binding, so this chunk is the whole of that control's cover.

**It needed one re-run, and the re-run found the second stale probe of the week.**
`run-control-check.sh` had last run on **2026-08-12 against a protocol v10 daemon**. Re-running it
against v12 produced five failures, all of the form *resume block X, expected Y* — and the product
was correct in every case.

`RunControlProbe` computed `expectedResume = startBlock + report.chunksProcessed * blocksPerChunk`.
**`chunksProcessed` became cumulative across the session in increment 3**; `startBlock` and
`blocksPerChunk` are still per-call. So the prediction inflated with each case. The reported totals
reconciled exactly as differences — 555, +150, +74, +37, each about 300 MiB of covering work in the
2 s window — and that reconciliation is what proved the counter cumulative rather than the resume
points wrong.

> **Two probes, one cause, and one of them was updated at the time.** Increment 3's move of the
> accumulators onto the claim broke `metrics-probe` and `run-control-probe` in the same way.
> `metrics-probe` was updated then and documents the change at length in its header;
> `run-control-probe` was missed. Nothing caught it for **twelve days**, because a gate that is not
> re-run cannot report anything. Both defects this week were instruments, not product — and both
> were found only by running gates that had been left standing on old evidence.

After the fix: **all four I/O sizes settled at a chunk boundary with the correct resume point.**
300 / 147 / 73 / 38 chunks; settle 6.4 / 3.1 / 9.8 / 20.1 ms; ack 0.34–0.58 ms. Settle tracks the
I/O size and not the 1 GiB call cap, which is the shape NFR-REL-10 predicts.

**The concurrent-run guard now has cover, and it had none.** Gate item 5's second clause was
discharged on 2026-08-24 by adding a check to `run-control-check.sh`. Two things had to be corrected
before it could be written: the guard is the **device-operation slot** (`beginDeviceOperation`,
taken by `runRetentionCycle` and by `digestRange`), not `HelperActivity.isBusy` — that one guards
*release*; and no unit test can reach it, because `HelperActivity` is in the helper's `main.swift`
(top-level code, not importable by a test target) and `RetentionCycleRefusal` is in
`RunCoordinator.swift`, which the test target does not compile. A live check was the only option
available, not the cheapest of several.

> **The idle attempt is the half that makes the check a check.** It issues the same 1 MiB call on
> the same connection with nothing in flight and asserts it is *accepted*. A refusal on its own
> proves only that something refused — connection ownership, the request, an arithmetic slip — and a
> check that cannot be seen answering both ways is not one. It also settled empirically what reading
> the source had not: `runRetentionCycle` does not gate on connection ownership. **No mutation round
> was run, deliberately**: mutating the guard would mean rebuilding and reinstalling a privileged
> daemon to test it live, and the idle attempt already buys the evidence a mutation would.

**And the new check immediately found a bug in the change that added it.** The first run reported
the 1 MiB case's resume point 2048 blocks too far — exactly one chunk. The idle attempt does 1 MiB
of real work *after* the control run and before the case loop, and the loop's baseline was still
being read from the control run, so the first case differenced against a total that predated it.
The same stale-baseline class fixed forty minutes earlier, reintroduced by adding a new contributor
to a cumulative counter. The baseline now reads from the last thing to run rather than naming a
particular call, and the comment says why.

**Two things the walk found that were not failures of anything mechanical.** The gate's fourth item
still read *"Restart begins from block 0"*, naming a control withdrawn on 2026-08-22 — amended in
place, because a gate item naming a control is how a withdrawn one comes back. And the human
checklist's summary line claimed everything in it had been walked while its own header, four lines
above, said chunk 8 was not. That sentence was carried forward and **bolded** by the previous day's
docs pass without the body being read. Corrected, with the reason recorded there.

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
- **The sequencer must not re-derive what the session already reports** (from increment 3). Whole-
  device progress, the ETA and the whole-run p99 come from `runProgress` and from the cycle's reply,
  already cumulative and already denominated in the whole device. An app that summed per-call
  figures would be building a second source for facts that now have one — and for the p99 it would
  simply be wrong, because percentiles do not compose. The two reply fields that are still *per
  call* and that a sequencer legitimately branches on are `runOutcomeCode` / `interruptedAtBlock`
  and `bufferBytesHeld`.

### Increment 5's gate — passed 2026-08-18, `0e09e5d`

Run in **seven small chunks, one at a time**, because the first attempt ran the nine items in one
go, hit "numerous problems", and stopped — and the problems were never enumerated. The full list
is `progress/step-11-human-checklist.md`; it replaces the nine-item list in `step-14.md`, which
increment 5 made partly unrunnable.

**It found three defects after every automated instrument was green** — 964 tests, three
zero-warning clean builds, 56 renders, 13 type-checked gate clients, 9 of 10 mutations caught.

| | |
|---|---|
| **Pause blanked the measurements panel** | `paused` was grouped with the states that have nothing to show. It is the one where a claim is held and the figures are this run's. `isMeasuring` → `hasLiveSession` |
| **⌘Q during a run ended the run** before the user answered | One flag answering two questions. Splitting out `mayContinueRun` is the fix; asking must not answer |
| **Window and exported report disagreed** | Two literals, already drifted in one day — the defect `HonestFraming` exists to end, in the area it did not cover. `ThroughputFraming` now holds both paragraphs once |

**Two checklist items were wrong rather than the app.** Old item 7 (a quit pending while the
dialog is open) is now *unproducible*, because Start enters `starting` only when the dialog is
answered — a consequence of increment 5 working. Old item 9 guarded a section increment 5 deleted;
the hazard moved to the run controls and the check moved with it.

**And 6.1 failed against a prediction I derived from `QuitPolicy`'s truth table** — which is never
reached, because the sheet is window-modal and intercepts ⌘Q first. An acceptance criterion
derived from model code alone carries that risk; the sheet's modality is now recorded as wanted
(user decision) at `RunControlsView`.

**What has no automated cover and will not get any:** the report body (inside a scroll region, so
even a render stops at `## Measurements`), the live metrics panel (needs a real helper to poll),
and sheet modality (the policy is never consulted). Three defects, three blind spots, one pass.

### Unplanned, between increments 5 and 6 — the throughput denominator, protocol v12. 2026-08-18, `1a10438`

**Not a planned increment.** A bug report interrupted increment 5's gate: *"our speed measurements
are way off. Reported read speeds are about 50% above actual and reported write speeds are over 3x
above actual."* Against the 4 TB T5 EVO the app claimed 375.8 MB/s read and 418.9 write where
DriveSpeed and Activity Monitor — agreeing exactly — showed about 245 and 122.

Not a regression and nothing miscounted. The rates divided by **phase** time, so "write speed"
described the drive during the ~29% of the run it was writing. Every other tool divides by the wall
clock, because that is the only denominator an outside observer has.

**`coverageBytesPerSecond` had existed since Step 9** — computed, unit-tested, logged every call —
and had never been put on the wire, so no screen could show it. *A measurement that is not on the
wire does not exist as far as the user is concerned, however well tested it is.*

| | |
|---|---|
| **Verified** | **959 tests, 0 failures, 122 suites** |
| **Warnings** | zero from source across three clean builds. SwiftCompile Debug 83 / Release 2 / test 162 |
| **Helper** | **hash `a36c4f77…5a40` at `1a10438`** — the tree `metrics-check.sh` actually ran against. Recipe, because the older recorded hashes' recipe is written down nowhere: `find <helper> <Shared> -name '*.swift' \| sort \| xargs cat \| shasum -a 256`. Step 10's three gates no longer apply; `metrics-check.sh` was re-run and passes, the other two are owed |
| **Helper, now** | `0d727d98…b29c`, moved by `1237c5f`. **Comment-only** — every changed line in that commit's Swift diff is a `///` line, so the gate above still stands. A source hash answers "did the source change"; it does not answer "did behaviour change", and the two must not be confused (CONSTRAINTS section 1) |
| **Gate** | `metrics-check.sh` **120 PASS / 0 FAIL** on hardware |
| **Mutations** | **10 introduced, 9 caught, 1 survived — predicted** (the panel row, whose only cover is a render) |

**THREE DENOMINATORS, TWO REFUTED ON HARDWARE.** The gate is what refuted them, and no unit test
could have: unit tests drive a deterministic clock and never ask the same run twice.

| denominator | call 1 covering | vs. the reply's own wall clock |
|---|---|---|
| `now - start`, at the reply | 159.0 MB/s | — |
| `now - start`, at a later poll | 133.2 MB/s | **-16.2%** ← the defect |
| device + host overhead | 161.1 MB/s | +1.35% |
| **wall clock − gaps between calls** | 158.8 MB/s | **-0.11%** ← shipped |

`now - start` kept growing after a call ended, so a finished run's throughput **decayed on screen**
and a reply disagreed with a poll 1.31 s later. Device-plus-host fixed that but excluded scheduling
*inside* a call that an outside observer counts. What shipped subtracts exactly one span: time
between calls — which is where a **pause** lives (FR-CTRL-3), and the only interval in which the
drive does nothing on the run's behalf.

**A correction worth keeping.** 133.2 was briefly treated as a "wall clock baseline" and it is not
— it is the broken poll. That made device-plus-host look 19% high when it was 1.35% high, and drove
one whole design iteration on a misreading. The table above is in the source for that reason.

**Two findings from the tooling, both pre-existing:**

- **`tools/nocache-probe` had not compiled since Step 9** (`c6ec234`, 2026-08-06) — a `//` at column
  zero *inside* a multi-line string literal, so not a comment but string content indented less than
  the closing delimiter. Same shape as `ui-probe`'s three-increment breakage. Found by the new
  `scripts/build-tools.sh`, which type-checks all 13 gate clients against the current protocol in
  seconds. **That script exists because this trap has now bitten three times.**
- **`install-app.sh` does not reload the running daemon**, and two of four gate runs measured stale
  code while returning entirely plausible numbers. The version handshake cannot catch it — v12 is
  v12 either way. The script now compares the daemon's start time against the binary's and prints
  the `launchctl kickstart` command.

**Mutation M3 survived UNpredicted:** `idleNanoseconds = ` versus `&+=` is indistinguishable when a
run has only one gap, and the pause test used two calls. A whole-device run is ~1,000 calls, so a
user pausing twice would have had the first pause charged to the drive. Now killed by
`idleAccumulatesAcrossEveryGapAndNotJustTheLast`.

**A `/verify` pass found the exported report contradicting itself** about its own denominator —
"the time the run spent working" in one paragraph, "against the wall clock" in the next. Visible
only in the rendered artefact; the source read fine either side. Fixed.

**For the docs pass (increment 8):**

- **The helper source hash recipe is written down nowhere.** Eight derivations were tried and none
  reproduced `b804178d…`. A token that gates whether three hardware gates still apply, and that
  nobody can recompute, is not a check. The recipe is now stated wherever the new hash appears.
- **The render harness pins appearance but not accent or activation.** The progress bar's fill
  measured `#3e99fd` and then `#bdbdbd` across two runs on the same day with nothing in the diff
  touching it — ambient machine state leaking into an offscreen render. Same family as the
  2026-08-10 appearance bug that block was written to fix, incompletely closed. Render-to-render
  **colour** comparisons are not currently trustworthy.

**Full account: commit `1a10438`.**

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
