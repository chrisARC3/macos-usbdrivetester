# Step 9 — Metrics, live monitoring, and the window layer

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

---

## Step 9 — GATE DISCHARGED (2026-08-05) — the metrics work

> **Read this together with "Step 9 — UI work folded in after the gate", below.** Everything in
> *this* section is the metrics work and its Verification Gate, which is fully discharged. After it
> passed, the user reviewed the shipped window and a body of **UI work was folded into Step 9 by
> decision** rather than deferred. The figures below (497 tests) are the gate's as it stood on
> 2026-08-05; the final count for the step is **551**.
>
> **Step 9 is COMPLETE and COMMITTED** — `c6ec234`, 2026-08-06, with `4be5766` recording the two
> decisions that followed. Anything below saying otherwise is describing a moment that has passed.

Every gate item discharged. **The step's own pre-flight overturned the design the plan assumed,
and the number this project had carried as an estimate for three steps turned out to be wrong by
11×.**

**Delivered.** Live metrics, measured helper-side and displayed GUI-side. `Core/LatencyHistogram`
— a constant-memory percentile in **17,920 fixed bytes**, selected with integer arithmetic alone
and reported as an *upper bound* rather than a point. `Core/RunMetrics` — the accumulator, keeping
three distinct rates apart and denominating progress in **bytes, never chunks**. A rewritten engine
inner loop where `chunkMeasured` fires **once per chunk on every path**, the three failure branches
included, and where host overhead is the chunk's whole span minus its device phases. `RunPlacement`
— FR-TEST-10's 1 MiB rule, enforced at the trust boundary. Protocol **v8**. And on the app side:
one hoisted `AppModel`, the `Metrics/` panel that is a pure function of a snapshot, a diagnostics
**window** rather than a disclosure, and a GUI that polls progress on a **second, non-owning XPC
connection** — because the run's own connection provably cannot answer while the run holds it.

**Final state.** **497 tests, 0 failures.** Zero source warnings from clean **Debug**, clean
**Release** *and* a clean **test-target** compile, DerivedData wiped before each.
`./scripts/xpc-concurrency-check.sh` **0 failures** on the scratch device (read-only).
`./scripts/metrics-check.sh` **0 failures** on the scratch device, all four I/O sizes.
`./scripts/retention-cycle-check.sh` **15/15** on the scratch device, all **932** whole-device fingerprints
unchanged. NFR-PERF-4 observed by the user on hardware.

**Requirements affected.** **FR-TEST-10 added** (1 MiB alignment, helper-enforced) and
**FR-CTRL-8 revised** (I/O size configurable while paused or stopped), both with full amendment
entries dated 2026-08-04. **NFR-PERF-3 measured**, wording unchanged, recorded in the NFR
document's amendments. The ADR's sixteen checkboxes remain untouched, as they have been for every
step — it is a decision record, and BUILD-PLAN is the tracker.

### The hardware result

`metrics-check.sh disk4` — the same gibibyte from block 0, four times, which is an **8× lever on
chunk count at constant bytes**:

| | 1 MiB | 2 MiB | 4 MiB | 8 MiB |
|---|---|---|---|---|
| chunks | 1024 | 512 | 256 | 128 |
| progress reached | 100.00% | 100.00% | 100.00% | 100.00% |
| mid-run snapshots | 14 | 13 | 14 | 13 |
| widest gap | 505.4 ms | 505.3 ms | 505.3 ms | 505.4 ms |
| read / write | 517 / 491 | 516 / 491 | 488 / 492 | 501 / 492 MB/s |
| p99 (min ≤ p99 ≤ max) | 2.195 ms | 4.162 ms | 9.175 ms | 17.302 ms |

**NFR-PERF-5 is discharged with a factor of two in hand**, and 13–14 of those snapshots arrived
*while the privileged call was blocking* — the property the whole second-connection design exists
to provide, which no amount of simulation could have shown. **FR-TEST-10 was shown refusing**, not
merely shown not-refusing: a start at block 1 and a length one block short of a whole MiB were both
refused with **zero chunks processed**.

**NFR-PERF-3, final:** at the 4 MiB default with the device moving ~470 MB/s, in-span host overhead
is **2.55%** of device I/O time and daemon CPU **4.22% of one core** — the run is **97.4%
device-bound**, cross-checked by an independent `ps` sampler peaking at 8.5%. **Host cost follows
bytes moved, not chunk count**: µs/MiB varied **1.32×** across the 8× range while µs/chunk varied
**8.65×**, so a larger I/O size does not reduce it. Because the cost is per-byte its share rises
with transport speed — ~10.9% at USB 3.2 Gen 2×2, ~20.6% at USB4 — which makes Step 16's
release-note item **unconditional** rather than contingent.

### What this step cost, and what it bought

**A pre-flight reversed the design before a line of it was written.** BUILD-PLAN 9.4 assumed the
helper would *push* snapshots; scoping recommended a *poll*. Both were guesses about whether a
daemon inside a blocking call answers a second message. Twenty minutes of `xpc-concurrency-probe`
settled it: on the run's own connection **0 of 24** pings were answered during a 2,827.9 ms call —
the whole queue draining in ~0.6 ms *afterwards* — while a **second connection** answered **24 of
24** in 0.2–0.3 ms. So the daemon is not blocked; the connection is. That ruled out the recommended
option *and* priced a third one the probe's pre-written verdict branches had not contained, because
the second-connection number did not exist until it was measured.

**Twelve defects, none of which reached a gate as a false pass.** Four are worth naming:

1. **`chunkCompleted` fired only for chunks that got through every phase** — all three `catch`
   blocks `continue` past it. Harmless while nothing computed statistics from it; a defect the
   instant something did, and it would have frozen percent-complete and run the ETA away **on
   exactly the drive this tool exists to find**. Replaced wholesale rather than patched.
2. **Step 8's gate would have been refused by FR-TEST-10, ~35 minutes in.** Its `1 GiB − 512 KiB`
   constant is 1023.5 MiB. Found by *reading the new rule against the existing script*, not by
   losing an hour to it. Both constants are now pinned by `StepEightGateCompatibilityTests`, so the
   compatibility is a test rather than a memory.
3. **The probe reported `samples ÷ chunks` as every run's final figure** — 987/1024, 488/512,
   240/256, 123/128. The polling loop exited the instant the cycle replied, so **nobody ever asked
   the helper what the completed state was**. The runs had all completed. A failure off by an
   arbitrary amount is a mystery; one off by exactly the polling granularity at four different
   chunk counts is a measurement artefact, and the arithmetic is what identified it.
4. **The bounded-cycle button was pressable with no device held.** Reported as "appears to do
   nothing"; it was working perfectly and failing in **25 ms**, which the unified log settled in one
   query after several paragraphs of my speculation had settled nothing.

The other eight, in the order they were found. **Two of them are the same failure mode as each
other and as this project's most expensive recurring bug — a value that reads as a pass when it
means "no data":** the D1 probe printed **"0.0 ms"** under *worst reply during the call* when no
reply had arrived during the call at all, and the first row of every sweep table read **100% then
dropped to 3%**, because `MetricsChannel.begin()` runs *after* validation — correctly, so a refused
run does not wipe the previous run's figures — leaving a few milliseconds in which a poll still saw
the **previous** size's completed snapshot. Fixed by spelling out the no-data case, and by settling
250 ms before the first poll.

The remaining six were mine and caught early: a `%s` format specifier given a Swift `String`
segfaulting a scratch harness (the same bug I had removed an hour earlier), `#expect`'s comment
argument being a `Comment` rather than a `String` expression, a `Duration` extension needing
`nonisolated`, `Timer.publish(…).autoconnect()` needing an explicit `import Combine` under
`MemberImportVisibility`, an idle placeholder implemented as an **overlay** — which left a row of
em-dashes visible behind it, so the panel showed empty measurements *and* a note saying there were
none, one of which looked like data — and **two stale spatial references** ("install the helper
below", "the metrics panel above") left pointing at a panel that had become a window, both found by
rendering rather than by reading. A corrective instruction pointing where the control is not is
worse than none.

**Three lessons this step earned, all paid for.**

**Measure, don't estimate.** "Order 40–80 µs of host work per chunk" stood for three steps and
appears in BUILD-PLAN as a parenthetical. The measurement is **683 µs** against 25.44 ms of I/O —
wrong by 11×, and it survived only because nobody measured it. The replacement figure is not
re-estimated: what the residual ~209 µs-per-chunk term in daemon CPU actually *is* has been
measured and is deliberately **not guessed at**.

**A pre-flight before a design is committed to is almost free; the same discovery afterwards is
not.** True twice here — the D1 probe, and reading FR-TEST-10 against Step 8's gate script.

**Prose is not a precondition.** A control that states its requirement in body text and then looks
live is a control that fails on press. Every other control in this app disables itself and names
the corrective step.

**And a correction to my own arithmetic, recorded rather than edited away.** I reported the daemon
saturating one core near **4.7 GB/s**. That was a stray factor of 0.5; the figure is **11.1 GB/s**,
more than double the headroom. It also rested on a single 4 MiB point and used the *fastest observed
read* rather than the run's actual rate. The percentage columns survived the correction; the
saturation point did not.

### Carried into Step 10 (the report this step feeds)

- **Final throughput and latency are on the wire already** — `runRetentionCycle`'s reply carries
  them, so the report assembles from measured values rather than re-deriving any.
- **p99 must reach the report as an upper bound.** "p99 ≤ x" is what the histogram knows; a report
  printing "p99 = x" would dress a bracketing interval as a measurement, which is the same class of
  error as a verdict the tool is not entitled to.
- **The report records which I/O sizes were used**, because FR-CTRL-8's mid-run change makes the
  latency distribution bimodal and the statistics deliberately **keep accumulating** across it.

### Not discharged by this step, and not to be mistaken for covered

- **Whole-device progress and ETA.** This step's are **per-call**, honestly labelled, because a run
  is one bounded call until Step 11 sequences them. The multi-hour convergence observation the
  gate's original wording implies is unreachable under the 1 GiB cap and belongs to Step 11.
- **The final chunk at the physical end of the scratch device, and a whole-device traversal.** Unchanged from
  Step 8: neither is reachable under the placement rules used so far, and both belong to a later,
  separately agreed run.
- **What the ~209 µs per-chunk term in the daemon's CPU is.** Measured, not explained.
- **The `File ▸ New Window` defect, found 2026-08-05 and not fixed here.** The main scene is a
  `WindowGroup`, so macOS offers ⌘N — and a second main window would build a second
  `DeviceDiscovery` with its own selection while sharing one claim, so the two windows could
  disagree about *which drive is selected* while only one is actually held. That is NFR-USE-3's
  hazard, and it is the same one-truth-two-views problem the diagnostics scene already solved by
  being a `Window`. Recorded here as found-and-open rather than folded into this step.

**One measured behaviour confirmed from the product's own surface.** Releasing the device
auto-remounts `Test_Drive` with no user action — `Mount All` is not needed after a release. This
was already measured in Steps 6 and 7 (releasing an `O_EXLOCK` open or a `DADiskClaim` makes
DiskArbitration remount within milliseconds) but had only ever been seen from probes and scripts;
2026-08-05 is the first time it was observed through the shipped Release button, with FR-SAFE-5's
control correctly re-evaluating its label afterwards.

---

## Step 9 — COMPLETE (2026-08-06) — the UI work folded in after the gate

Written for a cold start. The gate above is discharged; this is what happened next.

> **Committed as `c6ec234` on 2026-08-06** ("Step 9: metrics, live monitoring, and the window
> layer"), followed by `4be5766` ("Docs: record when a BSD name may be used, and FR-DEV-3
> confirmed"). **Step 10 is next and has not been started.** The "What is left" table that used to
> sit at the end of this section is now "Increment 5 — closed".

### Why this work is in Step 9 at all

With the gate passed, the user reviewed the running app and raised a series of UI defects and one
product-design change. Asked whether to commit Step 9 first or fold the work in, the user chose
**fold in** (2026-08-05). So Step 9's commit will cover the metrics work *and* this.

### Verified state right now

**551 tests, 0 failures, 65 suites** (was 516/62 before increment 4; +35 tests, +3 suites).
**Zero source warnings from all three clean builds** — `build.sh Debug`, `build.sh Release` and
`test.sh`, DerivedData wiped before each, run 2026-08-05 after increments 3 and 4.

`metrics-check.sh`, `retention-cycle-check.sh` and `xpc-concurrency-check.sh` results are unchanged
from the gate — **no helper, `Core/` or `Shared/` file has been touched by any of this work**; it is
app target, `tools/ui-probe` and documents only.

> **What is still owed, and it needs the machine's owner.** The Release build has not been
> **installed** (the app was running, and `install-app.sh` refuses to replace a live bundle), the
> helper has not been re-registered from it, and **NFR-PERF-4 has not been re-checked against the
> new binary**. Increments 3 and 4 touch the window layer, which is what that requirement is about,
> so the re-check is earned rather than pedantic. See "What is left".

### Increments done

| | |
|---|---|
| **1** | `tools/ui-probe`'s `devices` view never called `discovery.start()`, so it had **always** rendered the no-devices state — identical to the `empty` view it sits beside. Two named views collapsed into one, and nothing failed. Also added a `appActive / windowKey / firstResponder` diagnostic line, which went on to settle three later questions. |
| **2** | The device list is **focused on launch**, so FR-DEV-3's default selection draws blue rather than grey. The **Refresh button is removed**. |
| **2.5** | Panes merged; deselection implemented and auto-releasing; selection frozen during a run; run timestamp; **drives identified by USB serial number**. |
| **3** | The main scene is a **`Window`, not a `WindowGroup`** — `File ▸ New Window` is gone, and with it the possibility of two `DeviceDiscovery` instances with independent selections sharing one claim (NFR-USE-3's hazard). |
| **4** | **Quit/close confirmation during a run**, with the wind-down that keeps its promise: `Quit/QuitPolicy`, `Quit/QuitSequence`, `Quit/MainWindowCloseGuard`, `Quit/AppLifecycleDelegate`, plus the state and the sequencing in `AppModel`. **+35 tests, five mutations, all caught.** |
| **5** | The three clean builds above. Install, re-register and the NFR-PERF-4 re-check are outstanding — they need the app quit and a person at the keyboard. |

### Decisions taken (all user decisions, 2026-08-05)

1. **FR-SAFE-5 withdrawn, FR-SAFE-6 reversed, FR-SAFE-7 moot, FR-SAFE-4(a)'s remedy revised.** The
   `Unmount All` / `Acquire exclusive access` / `Release` buttons go, and **Start owns**
   unmount → acquire → run → release. Full amendment in the FR document; Step 11 inherits the work
   and Step 12 inherits FR-DEV-8 details. **Gated on Step 14's warnings existing first** — removing
   the explicit unmount before any confirmation exists would leave the product briefly less guarded
   than either the current design or the intended one.
2. **The claim follows the selection.** Deselecting, or selecting another drive, releases the
   device. Interim; Step 11 subsumes it.
3. **The selection is frozen while a run is active** — otherwise rule 2 would release a device
   under an active write.
4. **Drives are identified by USB serial number**, never by BSD name. Selection identity stays
   `registryEntryID` (its instability across replug is deliberate).
5. **Deselection is allowed** and is *not* durable across a device-set change — any hot-plug
   re-applies FR-DEV-3's default. Pinned by test, because it is surprising in use.
6. **Quitting mid-run: stop at the call boundary, then quit** — issue no further work, wait for the
   in-flight call to return, release cleanly, terminate. Same confirmation for window-close and
   ⌘Q. **Built in increment 4; see below.**

### Increments 3 and 4 — the window layer (2026-08-05)

#### The pre-flight, which settled five questions and killed one design

A scratch SwiftUI scene probe (two `Window` scenes, the app's own `.commands` shape, run
`.accessory` so it never took focus), because every question below had a plausible answer that
would have been wrong to build on. macOS 26, this machine:

| question | measured |
|---|---|
| what `WindowGroup` gives us today | File menu: **New Window ⌘N**, Close ⌘W, Close All ⇧⌘W |
| what `Window` gives us | **no File menu at all** — ⌘N, ⌘W and ⇧⌘W all disappear |
| is a closed `Window` recoverable | **yes** — SwiftUI adds a permanent Window-menu item per `Window` scene that brings it back |
| SwiftUI's own window delegate | `AppKitWindowController`, on an `AppKitWindow` |
| a forwarding proxy over it | intercepts `windowShouldClose:`; refuse keeps the window, allow closes it — **and the window still reopens from the menu afterwards**, so SwiftUI's own bookkeeping survived being proxied |
| `applicationShouldTerminate` via `@NSApplicationDelegateAdaptor` | fires; `.terminateCancel` keeps the app alive |
| main-queue delivery during `.terminateLater` | **delivered**, on time |
| run-loop `Timer` during `.terminateLater` | **never fired** — AppKit runs that wait in its own run-loop mode |

Two of those rows changed the design. The last one **rejected `.terminateLater`**, which was the
obvious API for "wait, then quit": the live metrics panel is `Timer`-driven, so the seconds spent
waiting for the boundary would have been exactly the seconds where the display of the operation
being waited on stops moving — a window that looks wedged at the moment the app is asking to be
trusted. `.terminateCancel` plus a wind-down in the app's ordinary run loop has no such mode.

**And the probe's own first answer was wrong, which is the more useful half of this.** Round 1
reported that main-queue blocks are *not* delivered during `.terminateLater` — a negative that
would have disqualified the mechanism for a completely fictitious reason. It called
`NSApp.terminate(nil)` from inside a GCD main-queue block, so the main queue was still occupied
when AppKit spun its nested wait: no other main-queue block could start, whatever the run-loop mode.
A real ⌘Q arrives from the run loop with the queue free. Round 2 drove every terminate from a
`Timer` and got the opposite result. **The probe was measuring itself.**

#### What increment 4 actually promises, and why it is worded that way

There is no cancellation of a privileged call once issued — that is Step 11's work, and it is why
the 1 GiB cap exists. So "Cancel and Quit" promises the two things the trust boundary can deliver:
**issue nothing further**, and **wait rather than walk away**. It does not claim to stop the run.

Quitting *without* waiting was never unsafe: the helper releases a claim when the connection that
took it goes away (NFR-REL-5), so an abrupt exit still ends with the device released and the volumes
remounted. What the wait buys is a release that is **issued and acknowledged** rather than inferred
from a socket closing — and, from Step 11 onward, a whole-device run that cannot be abandoned half
way by a keystroke that looks like housekeeping.

**The order is forced by measurement, not by taste.** `releaseDevice` goes out on the owning
connection, and D1 established that a second message on a connection with a blocking call in flight
is not delivered until that call returns. Releasing mid-run would queue the release behind the very
call it was meant to shorten. Waiting for the boundary is the only order in which these two
messages can happen at all.

**Two questions, deliberately answered by different state.** *Whether to ask* uses `runIsActive` —
the real cycle **or** the Step 4/5 stand-in toggle, because that toggle already means "a run is
active" everywhere else in the app, and a stand-in honoured in two places out of three teaches the
wrong lesson. It also makes the dialog exercisable without writing a gibibyte to a drive. *When to
quit* uses `cycleIsRunning` alone: there is nothing to wait for when the only run is a toggle.

#### The state machine, and the row that stops it deadlocking against itself

`QuitState` is `.idle → .confirming → .windingDown → .terminating`, and the last state exists for
exactly one reason: **the wind-down's own `NSApp.terminate(_:)` comes back through the same guard
that refused the user's.** Without a state that says "this one is mine", an app that reached the
boundary with the run-state stand-in still on would answer every termination — including its own —
with "wait for the boundary", forever. `theAppsOwnTerminationIsNotRefusedByItsOwnGuard` is that row.

#### Five mutations, five catches

The suite is green, which is not evidence. Each of these defects was introduced deliberately and
the suite re-run:

| defect introduced | caught by |
|---|---|
| policy loses its `.terminating` row | 3 tests, including the deadlock one |
| "Cancel and Quit" ignores an already-finished run | 2 tests |
| the call boundary never triggers the release | 2 tests |
| the sequence can terminate twice | 3 tests |
| the deadline is armed *after* the release is issued | 1 test — the ordering assertion exists precisely because it is invisible |

The last two are the ones no amount of clicking could produce: they need a daemon that accepts a
message and never replies. Both closures are injected, so neither test sleeps.

#### A defect found by rendering, in a path increment 3 changes

`ContentView` told the device-list store about run state through `onChange(of:)` only — and
`onChange` fires on a **transition**, while the store is built fresh with the view. A main window
appearing *while a run is already under way* was therefore never told: the list stayed live during
a run (FR-DEV-7), and `select`/`deselect` stayed willing to change the selection — which releases
the claim, **under an active write**.

Not hypothetical, and not only in the probe: the bounded cycle is started from the *diagnostics*
window, so the main window can be closed, a run started, and the main window reopened from the
Window menu. Fixed by seeding the state in `onAppear` as well; `setRunActive` ignores a value it
already holds, so it costs nothing when nothing is running. Found because the `content-quitting`
render showed a device list cheerfully advertising that it updates as drives come and go, while
the model said a run was in flight.

#### What was left alone, with the measurement that says why

`.commandsRemoved()` looked like the fix for a cosmetic duplicate: SwiftUI generates a Window-menu
item per `Window` scene, so the app's own **⇧⌘D "Privileged Helper & Diagnostics"** command sits
next to an automatic entry with the same title. Applying it to the diagnostics scene removed the
automatic items for **both** windows — including the main window's, which is the only way back to a
closed main window. Rejected: the duplicate is cosmetic, and the thing it would have cost is not.

### Increment 5 — closed (2026-08-06)

| | |
|---|---|
| **three clean builds** | `build.sh Debug`, `build.sh Release`, `test.sh`, DerivedData wiped before each. **Zero source warnings. 551 tests, 0 failures, 65 suites.** |
| **install** | `install-app.sh Release`, run by the user once the app was quit. Verified afterwards that the installed binary is **newer than every app-target source**, so what is installed is what was tested. |
| **re-register** | Unregistered and re-registered from `/Applications`, confirmed with **Check version** — `install-app.sh` only copies files, so this is what makes the running daemon the new one. |
| **NFR-PERF-4** | **Re-checked and passed**, user-observed against the new binary: a live bounded cycle over the scratch device while scrolling, drag-selecting, resizing, holding a menu open and switching windows, with the metrics still **advancing during** the gestures. |
| **the confirmation** | **Observed in the product**, both entry points. Not renderable — a SwiftUI `alert` gets its own window — so this one always needed a person. |

**No figures are claimed for the last two.** They are observations of behaviour, reported by the
user; nothing was re-measured, and inventing a number for them would be exactly the kind of
authoritative-looking value this project keeps catching itself producing.

### Learnings this work paid for, all of them the same shape

**An empty result is not a finding.** `ioreg -rn "SSD 990 EVO Plus"` returned *nothing*, and it was
read as "this drive has no serial number" — then a comparison table and a design argument were
built on top of it. `-n` matches a registry entry *name*; that string is a property *value*. The
drive has a serial (`013117100578`, on its Ugreen enclosure). A query that matched nothing looks
exactly like a fact about the world.

**Three SwiftUI modifiers compiled, rendered, and did nothing.** `.defaultFocus(…)` on a `List`
left `firstResponder` as the `NSWindow`. `.selectionDisabled(…)` on the `List` *container* instead
of on its rows had no effect at all. `.id(…)` driven by a change token did not make a `List`
re-assert its selection. None produced a warning; each was found only by a person using the app, or
by the probe's `firstResponder` line.

**A sound mechanism behind a trigger that never fires looks exactly like a broken mechanism.** Two
fixes for the selection desync were wired to `selectedDeviceID != requested` — and a ⌘-click on the
already-selected row arrives as `select(thatSameID)`, not as `nil`. The condition was false every
time, so the resync never ran once. Measured from the unified log, after three rounds of reasoning
had produced three wrong answers.

**Prevent, don't undo.** What finally worked was `NSTableView.allowsEmptySelection = false` while a
run is active — stopping the deselection rather than restoring the highlight afterwards.

**A claim about an instrument's limits is itself a claim, and needs measuring.** `ui-probe` was
documented as unable to decide the highlight question because it runs as a parked `.accessory` app.
The diagnostic added alongside that note refuted it in one run — `appActive=true windowKey=true`.
Had the claim stood, every check of that behaviour would have gone to a human forever.

**A placeholder that looks like data.** The Ugreen bridge reports a SCSI INQUIRY serial of
`0000000000000000`. Accepted, it would have become an identifier every drive behind that bridge
model shares — a *wrong* identity that reads as authoritative, which is worse than the transient
BSD name it replaces. Rejected by rule ("a single repeated character"), and `INQUIRY` is
deliberately not used as a fallback: a second source that can return sixteen zeros is not a
fallback.

**And once more: the unified log settles in one query what reasoning does not.** It identified the
⌘-click's true shape, and confirmed that the store refused every mid-run change while the picture
was wrong — which is what established that the *safety* property held throughout, and only the
picture was broken.

**An instrument can measure itself and report the result as a fact about the world.** The
`.terminateLater` probe returned a clean, plausible negative that was entirely an artefact of how
the probe invoked it — and that negative would have disqualified a mechanism for a fictitious
reason, with a comment recording the false finding for whoever came next. What caught it was
asking *why* the mechanism would behave that way and finding an answer that implicated the probe
rather than the framework. This is the same shape as "an empty result is not a finding", one level
up: **a measurement is a claim about the apparatus as much as about the thing measured.**

**A promise the trust boundary cannot keep must not be made, even when the honest one is weaker.**
"Cancel and Quit" cannot stop a run — the helper is inside `pread`/`pwrite` on a raw device and
will finish the chunk plan it was given. So the dialog promises what is deliverable (issue nothing
further, wait rather than walk away) and the code is named for it (`waitForBoundary`, not
`cancelRun`). A "Stop" that does not stop is the throughput-verdict problem in another costume: a
judgement the tool is not entitled to make, dressed as a capability.

### Known-not-discharged, carried forward from this work

- **The NFR-PERF-4 re-check** against the post-increment-3/4 binary, and the **confirmation dialog
  itself** — both need the installed Release build and a person. See "What is left".
- **The `Window` menu behaviour is measured in isolation, not yet observed in the product.** The
  scene probe establishes what `Window` does on this OS; that the app's own File and Window menus
  now read that way is a code-level inference until someone looks at the running app.
- **A main window reopened *during* a run comes back frozen but with no highlighted row.** The
  rows are `selectionDisabled` from the first frame, so the `List` never applies the initial
  selection to its table. The selected-device detail — the surface NFR-USE-3 is actually about —
  is correct throughout, and the model's selection is untouched. Not chased: three earlier attempts
  to make a `List` re-assert a selection all failed and are recorded above.
- **`tools/ui-probe`'s `devices` render cannot show a focus fix in the real app**, because it hosts
  views in a raw `NSWindow` with no SwiftUI `Scene`. First responder is the common ground.
- **`TableSelectionPolicy` depends on `List` being backed by an `NSTableView`.** True on macOS 26,
  not contractual. It **fails safe**: finding no table sets nothing and degrades to a list that can
  look deselected during a run while the model holds. It cannot fail into releasing a device — the
  store's refusals do that, and they are tested and mutation-verified.
- **`MainWindowCloseGuard` depends on SwiftUI routing closes through the window's delegate.**
  Measured on macOS 26, not contractual. It **fails open**: if the guard cannot install, the window
  closes without asking — which is what the app did before it existed, and closing the main window
  does not end a run. The path that *can* abandon a run is termination, and that is guarded
  separately in `applicationShouldTerminate` with no AppKit archaeology in it.
- **The duplicate Window-menu item** for the diagnostics window (SwiftUI's automatic entry plus the
  app's own ⇧⌘D command). Cosmetic, pre-existing, and left alone deliberately — see above for the
  measurement that rejected the obvious fix.

---

## Step 9 — scoping, decisions and authoring log

### Scoping, 2026-08-04

Eight decisions taken before any code. Seven were agreed from the analysis; the eighth (D1) was
deliberately deferred to a measurement, and **the measurement reversed the recommendation**.

| | Decision | Outcome |
|---|---|---|
| **D1** | Progress channel mechanism | **Measured, not chosen.** See below. |
| **D2** | Where the GUI's run trigger lives | Split: the **metrics panel** goes in the main window (real product surface, FR-METR-2/4/5/6, NFR-USE-1/2); the **trigger** goes inside the "Privileged helper & diagnostics" disclosure, bounded to 1 GiB, no pause/resume/stop. Step 11 *deletes* it rather than inheriting it. |
| **D3** | p99 method (NFR-PERF-7) | **Octave-bucketed histogram, 64 sub-buckets per octave**, over 0 … 2⁴⁰ ns (≈18.3 min) = **2,240 buckets × 8 B = 17.5 KiB**, fixed at compile time. Bucket selection is integer-only (`leadingZeroBitCount` + shift + mask) — no floating point, no division, no lookup table. p99 is reported as a *bracketing interval*, not a point estimate. min/max/count kept **exact**. Explicit **overflow counter**, surfaced. |

> **Correction to the D3 figures as first stated (2026-08-04).** Scoping quoted "2,560 buckets,
> 20 KiB, 1.09% max relative width". Those numbers describe *geometric* spacing — 2^(1/64) per
> bucket — which needs floating point or a lookup table to select a bucket. The scheme actually
> built is **linear within each octave** (HdrHistogram's), which keeps bucket selection to a
> handful of integer instructions. Its buckets are therefore 1/64 of the octave's base wide, so
> the relative width runs from **1.5625%** at the start of an octave down to **0.78%** at the
> end — worse than the figure first quoted, and worth the trade: the integer-only hot path is
> worth far more than half a percent of an interval that is already reported as an interval.
> Bucket count and footprint change with it: 2,240 and 17.5 KiB, because the bottom 64 buckets
> hold the values 0–63 exactly rather than being spent on sub-nanosecond octaves that no clock
> can resolve.
| **D4** | Which read is "read latency" | **Both.** The original read is FR-METR-3's (BUILD-PLAN 9.2 says "each original read", and for a *retention* tester it is the meaningful one — it measures the device reading data it has been holding, where the verify read measures data written milliseconds ago and plausibly served from the drive's own DRAM/SLC cache). A **second histogram for the verify read** is carried as well, at 20 KiB, because a cached verify would show as a visibly different distribution — a useful complement to FR-TEST-9. |
| **D5** | The failing-chunk progress gap | Additive `RunObserver` method reporting **every** chunk's outcome with whatever phases were timed. |
| **D6** | ETA scope | **Per-call**, honestly labelled. Whole-device progress and ETA recorded as **not discharged**, carried to Step 11. |
| **D7** | Hardware regression | Step 9 modifies the engine's inner loop, which re-opens NFR-REL-1 — so `retention-cycle-check.sh disk4` is re-run as part of the gate. |
| **D8** | Protocol version | **v8.** |
| **D9** | What throughput reporting is *for*, and how narrow the live reply should be | **A heuristic for the user, not a verdict from the tool** — see below. |

### D9 — throughput is a heuristic the user judges (user decision, 2026-08-04)

Recorded because it constrains this step's protocol surface, Step 10's report wording and Step 14's
honest framing, and because the opposite reading — that a drive tester measuring MB/s is a
benchmark — is the natural assumption for anyone joining cold.

> *"I don't intend this tool to be a performance benchmarking program. The main purpose behind
> i/o rate reporting is more of a heuristic one: the device should have an advertised sustained
> read and write speed from the manufacturer. If we measure something significantly below the
> advertised rate, and after accounting for negotiated speed limits the device is significantly
> underperforming, this can be an indication of excessive wear or impending failure. But this
> judgement will be up to the user to make, not the tool."* — user, 2026-08-04

**Four consequences.**

1. **The tool never grades throughput.** No "healthy"/"slow"/"degraded" verdict, no comparison
   against a built-in expectation, no threshold. It reports what it measured. The manufacturer's
   advertised figure is not something this tool knows, and inventing one would be a judgement
   dressed as a measurement — the same failure mode FR-WARN-3 exists to prevent for a clean pass.
2. **The negotiated link speed must be presented beside the measured rate.** "After accounting for
   negotiated speed limits" is the user's stated method, and they cannot apply it without both
   numbers.

   > **Corrected while building increment 4.** This was first written as "the app *already has*
   > the link speed from `deviceProfile`". It does not: `deviceProfile` has existed on the
   > protocol since Step 7, but `HelperConnection` never calls it — the only callers are
   > `tools/mount-guard-client` and the gate scripts. The claim that this costs **no new
   > privileged surface** still holds, because the method is already there and is passive and
   > side-effect-free; what was wrong is that the app needs to start calling it, which is work
   > rather than a presentation detail.
3. **The live reply stays narrow.** A proposed run sequence number and `isActive` flag were
   dropped: the app issues the run on its own connection and receives its completion there, so it
   already knows the run's lifecycle and does not need the helper to restate it. The reply carries
   what FR-METR-2/4/5/6 require and nothing else.
4. **NFR-PERF-3's diagnostic figures do not belong in a once-a-second reply.** The host-overhead
   ratio and the helper's CPU share are read once, by a gate and by Step 16's release note — not
   watched. They ride on `runRetentionCycle`'s end-of-run reply, where the run's other results
   already are.

**Why D3 rejected the alternatives.** `t-digest` needs floating-point merge invariants and is hard
to pin against an exact answer. `P²` (Jain & Chlamtac) is O(1) memory but is a heuristic with no
statable error bound and known bad behaviour on multimodal distributions — and a drive with a slow
tail *is* multimodal. The deciding property is that a histogram can be validated against an
exactly-computed answer, so **the check can fail**.

**Why D5 exists — a hazard not in the plan.** A chunk whose read, write, or verify-read
*hard-errors* never reaches `observer?.chunkCompleted(...)`: all three `catch` blocks `continue`
past it. (A verify *mismatch* does still emit, having completed all three phases.) So an
observer-based accumulator would see the chunk counter stall while the engine walks on — percent
complete frozen, ETA running away, throughput reading low — **on exactly the drive this tool
exists to find**, and precisely when a user is watching hardest. `failureDetected` cannot fill the
gap: it carries no timing and can fire many times per chunk. On a hard read error there is no
timing at all, because `readNanoseconds` is computed *after* the read, on the success path only.

### D1 — measured, and it reversed the recommendation

**The question.** Step 9 must refresh live metrics at least once per second (NFR-PERF-5). BUILD-PLAN
9.4 assumes a **push** ("the helper sends a metrics snapshot to the GUI over the XPC progress
callback"). A **poll** — one additive query method the GUI calls on a 1 Hz timer — is a far smaller
change, but only works if the daemon will service that second message while it is inside a blocking
privileged call. **Nothing in this project had ever established that.** The only statement about
concurrent delivery is a comment in `HelperActivity`, and it is about two *connections*, not two
messages on one.

Scoping recommended the poll. That was a guess, and it was wrong.

**How it was measured.** `tools/xpc-concurrency-probe` + `scripts/xpc-concurrency-check.sh disk4`,
run 2026-08-04. **Read-only** — the long call underneath the pings is `digestRange`, one SHA-256
read pass, deliberately *not* `runRetentionCycle`: the XPC delivery question is identical for both
(a blocking privileged call holding the device-operation slot) and answering it does not require
putting a byte on the drive. Pings every 100 ms on two connections, each timestamped twice — when
sent and when its reply arrived — both relative to the digest being issued. **0 failures.**

| | same connection (A) | second connection (B) |
|---|---|---|
| pings sent during the call | 24 | 24 |
| answered **during** | **0** | **24** |
| answered **after** | 24 | 0 |
| worst reply during the call | n/a | **7.5 ms** (first), then 0.2–0.3 ms |
| verdict | **serialized** | **concurrent** |

The digest replied at **2,827.9 ms**. Connection A's twenty-four replies landed between **2,828.0
and 2,828.5 ms** — the whole queue draining in ~0.6 ms *after* the call returned. They were queued
and waiting, not lost. Connection B was answered throughout the same window in a fifth of a
millisecond.

**So the daemon is not blocked — the connection is.** That is the finding, and it is more useful
than the yes/no the probe was written to get: it ruled out the recommended option *and* priced a
third one the pre-written verdict branches had not, because the second-connection number did not
exist until the probe produced it.

| Mechanism | Status |
|---|---|
| poll on the run's own connection | **Ruled out.** Measured impossible. |
| push on the run's own connection (BUILD-PLAN 9.4's assumption) | Still rests on a **further unmeasured assumption** — that an outbound send succeeds on a connection whose inbound queue is blocked. |
| **poll on a second connection** | **Measured working.** 24/24 at 0.2–0.3 ms during a live in-flight privileged call. |

**Decided: poll on a second connection (user decision, 2026-08-04).** It is the only one of the
three resting on no unmeasured assumption, and it is also the smaller change: one additive query
method rather than a reverse `@objc` protocol plus an exported object on the app side. The root
daemon keeps the property that it **never initiates traffic to a client**, and the ≥1/s cadence of
NFR-PERF-5 is owned by the GUI's own timer rather than by the daemon. The second connection is
**non-owning** — it never acquires, so `releaseIfOwned(by:)` means its death releases nothing —
and both connections live inside the app's single `HelperConnection`, hoisted to one shared
instance in Step 6 exactly so the device has one owner.

**Two things this establishes beyond D1, which matter to Steps 4, 11 and 12.**

1. **During a run, the run's own connection is unusable for anything else.** `releaseDevice`'s
   carefully worded "the device is in use — try again shortly" refusal, and `prepareForShutdown`'s
   busy refusal, **cannot be delivered** on the connection that started the run. They queue. Those
   messages are only reachable from a *different* connection. This is not a defect — the behaviour
   is correct and Step 8's gate drives one command at a time — but it was an undocumented property
   of the trust boundary, and Step 11's pause/stop and Step 12's device-loss handling both have to
   be designed knowing it.
2. **A second justification for the 1 GiB cap, which nobody had written down.** The cap was
   understood as "do not wedge a root daemon for hours". It is also "do not make the run's own
   connection unanswerable for hours". At ~7 s per call the queueing above is survivable; at
   whole-device scale it would not be.

**One incidental number, recorded so it is not later mistaken for jitter.** Connection B's *first*
ping took 7.5 ms against 0.2–0.3 ms for every subsequent one — the cold start of a fresh connection
(accept, code-signing requirement evaluation, exported object vend). A progress channel's first
sample is ~25× slower than the rest, and that is the reason.

**A defect found in the probe's own reporting, and fixed.** The "worst reply during the call"
figure is a maximum over replies that arrived *during* the window. When none did, that maximum is
`0.0` — and "0.0 ms" printed under that heading reads as *excellent* when it means *never
happened*. A number that reads as a pass when it means "no data" is this project's most expensive
recurring defect, so the no-data case is now spelled out instead of printed as a zero.

### Increment 1 — `Core/LatencyHistogram.swift` (2026-08-04)

D3's constant-memory percentile, plus `LatencyHistogramTests`. **425 tests, 0 failures**
(was 403; +22 test functions, 26 executed cases — one is parameterised over five fractions).
Suite **18.8 s → 20.7 s**, the extra being the constant-memory test.

**Shape, as built and verified.** 2,240 buckets × 8 B = **17,920 bytes**, fixed at compile time.
Values **0–63 ns are exact**, one bucket each; from 64 ns up, each octave is split into 64 equal
sub-buckets selected by `clz` + shift + mask — no floating point, no division, no lookup table.

**Measured on this machine** (`-O`, host-side only, no device involved):

| | |
|---|---|
| `record()` | **2.9 ns** — and flat: 2.96 ns on realistic 4 MiB latencies vs 2.80 ns across every octave |
| `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` | **8.32 ns** |
| worst-case bucket width | **1.5625%** (1/64 at an octave's start, 1/128 at its end) |

That clock figure is the calibration NFR-PERF-3's overhead measurement needs: timing a ~40–80 µs
compare with an 8.3 ns clock costs ~0.02% of the thing being measured, so the measurement does not
distort what it measures. Both numbers are host-side; the **ratio** NFR-PERF-3 actually states
still requires hardware.

**How the tests avoid being vacuous.** Every percentile assertion is against a value computed by
**sorting the samples in the test**, independently of the code under test — and the interval is
additionally required to be tight enough to *exclude the wrong answer*
(`p99ExcludesTheFastPopulationEntirely`, `p50ExcludesTheSlowTailEntirely`). An interval wide
enough to contain both the fast and the slow population would bracket the truth while
distinguishing nothing, which is a green result indistinguishable from a histogram that returns a
constant. The bucket arithmetic is walked **exhaustively** over all 2,240 buckets rather than
sampled, because an off-by-one in bucket selection produces no crash and no error — just a
percentile that is quietly one bucket wrong forever.

**Better than designed, incidentally.** Intersecting a bucket's range with the exact minimum and
maximum is sound (the true value is in both) and tightens the answer for free: p99 of the slow-tail
fixture comes back as **99,614,720–100,000,000 ns**, where the upper bound is the *exact* maximum
rather than the bucket edge, and p100 collapses onto the exact maximum entirely.

**Two errors of my own, both caught before they reached a gate.** A `%s` format specifier given a
Swift `String` segfaulted a scratch harness — the identical bug I had removed from the probe an
hour earlier, reintroduced from muscle memory. And `#expect`'s comment argument is a `Comment`,
expressible by a string *literal*: `"a" + "b"` is a `String` expression and will not convert. Both
were in scratch/test code, neither reached the repo's product path.

### Increment 2 — `Core/RunMetrics.swift` (2026-08-04)

The accumulator: `RunMetrics`, `MetricsSnapshot`, `LatencySummary`, `ChunkMeasurement`,
`ChunkOutcome`. Plus `RunMetricsTests`. **443 tests, 0 failures** (was 425; +18 test functions).
Zero warnings. No engine or observer changes yet — those are increment 3.

**Three rates, and collapsing them is the easy mistake.** A cycle moves **3×** the range it
covers, so there are three different rates and only one of them can drive an ETA:

| Rate | Definition | For |
|---|---|---|
| `readBytesPerSecond` | bytes read ÷ **time spent reading** | FR-METR-1, the device's read speed |
| `writeBytesPerSecond` | bytes written ÷ **time spent writing** | FR-METR-1 |
| `coverageBytesPerSecond` | range bytes ÷ **wall-clock elapsed** | FR-METR-5, and the *only* correct ETA denominator |

Using the read rate for the ETA would make every estimate ~3× too optimistic and would look
entirely plausible. `coverageIsAboutOneThirdOfTheReadRateAndTheyAreNotInterchangeable` is the
assertion that catches it.

**Progress advances on failure**, by counting *attempted* work — the A7 hazard as an assertion
(`progressAdvancesThroughAChunkThatFailed`).

**The histograms hold only reads that returned data.** A failed read's duration is a failure
duration, possibly a long controller retry; folding it into "read latency" would make p99 report
a broken drive as a slow one. That time is reported as `failedPhaseNanoseconds`, not dropped
(`aFailedReadsDurationIsNotReadLatency`, using a 30-second injected failure against 8 ms reads).

**NFR-PERF-3 finally has a shape.** `hostOverheadFraction` = host work ÷ device I/O time, measured
in the product's own run path rather than inferred from a CPU percentage — and
`unaccountedNanoseconds` sits beside it as the completeness check, because an overhead fraction
computed from a small accounted slice would be measuring a fraction of the story.

**ETA convergence, which the 1 GiB cap makes unobservable on hardware.** `RunMetrics` calls no
clock — every entry point is handed the reading — so a run of any shape is synthesisable exactly.
A 100-chunk run whose rate changes partway (20 chunks at 20 ms, then 80 at 5 ms; true total
800 ms):

| chunk | elapsed | ETA | true remaining | error |
|---|---|---|---|---|
| 1 | 20 ms | 1980 ms | 780 ms | 1200.00 ms |
| 20 | 400 ms | 1600 ms | 400 ms | 1200.00 ms |
| 40 | 500 ms | 750 ms | 300 ms | 450.00 ms |
| 60 | 600 ms | 400 ms | 200 ms | 200.00 ms |
| 80 | 700 ms | 175 ms | 100 ms | 75.00 ms |
| 99 | 795 ms | 8 ms | 5 ms | **3.03 ms** |
| 100 | 800 ms | 0 ms | 0 ms | 0.00 ms |

The error is **flat at 1200 ms through the constant-rate opening**, and that is correct rather
than a defect: while the rate is steady the cumulative average equals the current rate, so the
estimate is exactly right *for a run that continues as it has been*, and the whole error is the
future rate change that no measured-throughput ETA can predict (NFR-COMPAT-7 forbids assuming
one). Convergence starts when the rate actually changes. The test's first sample point sits at
chunk 20 deliberately; a sample point inside the flat opening would compare 1200 against 1200 and
fail the strictly-decreasing check for a reason unrelated to convergence.

This discharges the *arithmetic* half of BUILD-PLAN gate item 3. The observed-on-real-media half
is still owed, and the multi-hour observation the gate's wording implies remains **not
dischargeable** under the 1 GiB cap — see conflict 2.

### Increment 3 — the engine and observer wiring (2026-08-04)

No new files, so no GUI ticks — but this is the increment that **changes the write loop**, which
re-opens NFR-REL-1. **460 tests, 0 failures** (was 443; +17), zero warnings.

**`ChunkTiming` is gone; `ChunkMeasurement` replaces it.** Step 8's `chunkCompleted(_:timing:)`
fired **only for chunks that got through every phase** — all three `catch` blocks `continue` past
the emission. Harmless while nothing computed statistics from it; a defect the moment something
did. `chunkMeasured(_:measurement:)` fires **once per chunk, whatever happened**, and says which
phase was reached. It carries a strict superset of what `ChunkTiming` did, which is why that type
was removed rather than kept alongside — two representations of one fact are two things that can
drift. Blast radius was one test recorder: `timings` and `completedChunks` both had **zero**
consumers outside it.

**`RunStart` gained `logicalBlockSize`.** Without it an observer cannot turn `blockCount` into
bytes, and every FR-METR metric is denominated in bytes — so a run's size was not derivable from
what Step 8 handed over. `rangeByteCount` comes with it.

**`ObserverFanOut`.** The engine takes one observer and the helper now needs two — the one that
logs (NFR-OBS-1) and the one that accumulates (FR-METR-*). Composing them beats having the logger
forward, which is the same forget-a-method hazard in miniature. **Stop wins**, and every observer
is asked with no short-circuiting: a passive observer answering the default `.continueRun` must
never be able to override a decision to stop.

**Host overhead is the chunk's whole span minus its device phases.** That captures *everything* in
the iteration that is not a device call — the write-guard re-check, the compare, the loop's own
bookkeeping — rather than only the parts somebody remembered to time. It costs **one extra clock
read per chunk** (~8.3 ns, measured in increment 1). The span is captured *before* the observer is
called, so the figure does not vary with what the observer costs; nothing is hidden by that,
because `unaccountedNanoseconds` measures the wall clock independently and would show an expensive
observer as unaccounted time. One documented exception: for a *mismatching* chunk the scan has
already called the observer once per differing range, so those chunks' overhead includes it. On a
healthy drive the scan is a single `memcmp` that calls nobody, which is the case NFR-PERF-3 is
about.

**The mutation test — this is the evidence, not the green suite.** BUILD-PLAN's Step 7 lesson is
that a check never shown capable of failing is a substitute for a test. So the `measure(...)` call
was deliberately deleted from the failed-read path and the suite re-run. **Six tests across four
suites caught it:**

- `aReadFaultStillProducesAMeasurementForThatChunk`
- `everyMixOfOutcomesStillMeasuresEveryChunkExactlyOnce`
- `theChunkAStopHappenedOnIsStillMeasured`
- `aFailedReadsOverheadIsMeasuredFromItsShorterSpan`
- `everyEventReachesEveryObserver`
- `progressReachesTheEndEvenWhenChunksFail`

The last one matters most: it is the **actual hazard** — a run with two failing chunks must still
reach 100% and still finish at the last block — rather than a proxy for it. The engine was
restored and the suite is green at 460.

**The overhead subtraction is asserted exactly, without any real timing.** The engine reads its
clock a fixed number of times per chunk — 8 for one that completes, 3 for one whose read failed —
so under a constant-step clock the overhead is exactly 4 steps and 1 step respectively. The 4:3
host-to-device ratio that implies is nonsense as a performance figure, because a stepping clock
gives a `memcmp` the same duration as a device read; what is asserted is that the *subtraction* is
right. NFR-PERF-3's real number still comes from hardware.

**All of Step 8's simulation proof passes unchanged** — non-destructiveness, verify mismatch, hard
errors, one-chunk-in-flight, bounded range, write guard, stop path, cache bypass. D7's hardware
regression (`retention-cycle-check.sh disk4`) is still owed, because simulation passing is not
evidence about real media.

### Increment 4a — protocol v8 and the helper side (2026-08-04)

No new Core files, so no GUI ticks. Debug builds, **460 tests still green**, zero warnings, and
all three protocol-dependent tools typecheck against v8.

**Protocol v8.** Adds `runProgress` (11 primitives) and widens `runRetentionCycle`'s reply from 8
to 10 with NFR-PERF-3's two figures. A signature change, so the bump is mandatory rather than
merely cheap — a v7 daemon would decode the cycle's reply block differently.

**No sentinel means two things.** Every "not yet known" is `-1` for a rate and a sample count of
`0` for the latency figures — never a `0` rate. Zero MB/s means *stalled*, which is real and
alarming; using it for "nothing has happened yet" would print an alarm to report an absence. This
is the same defect found in the D1 probe's own reporting a few hours earlier, avoided by having
just been bitten by it.

**Two simplifications fell out of D9.** An earlier sketch had a `MetricsPublisher` copying a
computed `MetricsSnapshot` into a box after every chunk, with a 100 ms throttle so it would not
recompute a percentile forty times a second. Both were solving a problem the design created: hold
the **accumulator** behind the lock instead, and the snapshot — percentile included — is computed
once per *poll*, on the poller's thread, about once a second. The run's per-chunk cost is one
uncontended lock acquisition around ~3 ns of histogram work; nothing is computed for a reader that
has not asked. No throttle, no copying, no publisher.

**And the lock has no logic to test.** `SynchronizedMetricsObserver` is a lock around Core's
already-tested `RunMetricsObserver`, so the helper file needs no test-target membership and no GUI
tick. Anything with a decision in it that ends up in `MetricsChannel.swift` is in the wrong file.

**NFR-PERF-3's CPU figure** is `getrusage(RUSAGE_SELF)` bracketing the cycle — two syscalls per
run, not per chunk — reported as a fraction of one core, `nil`/`-1` when it cannot be established.
Process-wide, which is the honest scope: during a cycle the daemon does nothing else except answer
progress polls, and those polls are part of what the product costs. It replaces the figure that
came from watching Activity Monitor, which was measuring the gate's SHA-256 rather than the
product.

**`metrics` is now a live `os_log` category** — the last of the six named in `HelperIdentity`.
One line per run, never per chunk, and carrying **no verdict** (D9).

### D10 — whole device, block 0, and 1 MiB placement (user decisions, 2026-08-04)

Four decisions taken after a proposal to let the user type a starting block was rejected. Two of
them are **requirements amendments**, recorded in the FR document (2026-08-04 entry): **FR-TEST-10
added**, **FR-CTRL-8 revised**.

| | Decision |
|---|---|
| Placement | **Whole device only, always start at block 0.** Random placement was a *gate* technique for testing a bounded region without writing a terabyte; it was never a product policy, and I had wrongly carried it across. |
| Alignment | All I/O begins on a **1 MiB boundary**; a bounded call covers whole MiB units unless it ends at the device's last block. **The helper enforces both.** |
| Progress control | A **progress bar with a live percentage**, not a slider — a slider implies a draggable thumb, and the starting block is never user-selectable. |
| I/O size | Changeable while **paused or stopped**, fixed while running; a resumed run continues from its pause point at the newly selected size (FR-CTRL-8, revised). |
| Latency across a size change | **Keep accumulating**, do not reset. |

**Why 1 MiB is a correctness rule and not a tidiness one.** A misaligned start makes the device
read-modify-write internally, which depresses measured throughput and adds wear. Throughput here
is a **wear heuristic the user judges** (D9), so accepting a misaligned start would manufacture the
exact signal the measurement exists to detect — a systematic bias toward "this drive looks worn",
on a tool whose output is a judgement about somebody's hardware.

**Why the length rule, not just the start.** A whole-device run is a *sequence* of ≤1 GiB calls.
A call covering a partial MiB leaves the next one misaligned, so enforcing only the start would let
a caller walk itself out of alignment one call at a time.

**It is self-maintaining, which is the point.** Runs begin at block 0 and every permitted transfer
size is a whole number of MiB, so every position reachable — under any mix of sizes, including a
change on resume — is an integer number of MiB. The helper's check is a guard against a **caller**,
never against the engine's own arithmetic. `SelfMaintainingAlignmentTests` asserts this over 500
steps with a size change at every one, rather than arguing it.

**Why latency keeps accumulating across a size change.** An 8 MiB read takes roughly twice as long
as a 4 MiB one, so a run whose size changed has a bimodal distribution and p99 can be dominated by
whichever size ran longer. Resetting would make each statistic describe the size currently in use —
but it would also **delete the evidence** of a 30-second read that happened before the change, which
is precisely the retry behaviour this tool exists to surface. Losing evidence is the worse failure.

**The rule broke an existing gate, and reading caught it rather than hardware.** Step 8's
`retention-cycle-check.sh` requested `1 GiB − 512 KiB` — deliberately, to force a short final chunk
on real media — which is **1023.5 MiB**, in the middle of the device, and would have been refused.
It would have been refused roughly **35 minutes in**, immediately after the before-fingerprint pass:
the same failure shape the D1 pre-flight was written to avoid. Changed to `1 GiB − 1 MiB`, which
still yields 255 full 4 MiB chunks plus a short 3 MiB one, so FR-TEST-5 is still exercised and the
expected chunk count is unchanged at 256. Both constants are now pinned by
`StepEightGateCompatibilityTests`, so the compatibility is a test rather than a memory.

### Increment 4b — the app side, and the GUI (2026-08-04)

**497 tests, 0 failures** (was 460), zero source warnings, Debug builds.

**Presentation is a pure function of a snapshot.** `RunMetricsView` owns no timer, no connection
and no state, which is what lets `scripts/render-ui.sh metrics` render it from a fixture and check
the layout headlessly; `LiveRunMetricsPanel` is the thin shell that owns the 1 Hz timer. A view
that fetched its own data could only ever be seen by running the signed app against a live daemon.

**The wire's sentinels stop at one place.** `RunProgressSnapshot`'s decoding init is the only code
that interprets `-1` and a zero sample count; every consumer above it sees `nil`. Verified visually
as well as by test — the `metrics-idle` render shows **every unmeasured value as an em-dash**, and
`MetricsFormatting` has no path from `nil` to a digit.

**Throughput is decimal MB, not MiB**, because the point of showing it is comparison against a
figure quoted in decimal megabytes on the box (D9). Using 2²⁰ would make every reading ~4.8% lower
than the advertised number for no reason the user could see — a bias in the "looks worn" direction.

**The GUI trigger is deliberately unconfigurable**: block 0, 4 MiB, 1 GiB, no controls. The
dropdown is Step 11's, because its whole behaviour is defined in terms of pause and resume. It
fetches `deviceProfile` first — not politeness, but because 1 GiB is a byte figure and the request
is in blocks, and assuming 512 would ask for eight times the intended range on 4,096-byte geometry.

**Three defects found and fixed in this increment.** The `Duration` extension needed `nonisolated`
(the app's MainActor default reaching an extension on a standard-library type — the Steps 5/6
gotcha in a new place). `Timer.publish(…).autoconnect()` needed an explicit `import Combine`, because
the project builds with `MemberImportVisibility` enabled and SwiftUI re-exporting it is not enough.
And the idle placeholder was an **overlay**, leaving a row of em-dashes visible behind it — the
panel showed empty measurements *and* a note saying there were none, one of which looked like data.
Replaced rather than overlaid.

### Increment 5 — the hardware gate, authored (2026-08-04)

`tools/metrics-probe` and `scripts/metrics-check.sh <disk>`. **Not yet run** — it needs a v8
daemon, which needs an install.

Structured the way the app is, because that is the only way to test what the app does: connection
A issues `runRetentionCycle` and blocks; connection B polls `runProgress` twice a second and
timestamps every reply. **It writes** — the first 1 GiB from block 0 — and it deliberately does
**not** re-prove non-destructiveness; `retention-cycle-check.sh` is what fingerprints the device
either side of a run, and that is the Step 9 regression D7 asks for.

Two anti-vacuity guards, both learned from earlier steps:

- **Mid-run snapshots are counted separately.** Snapshots arriving only before or after the run
  would prove nothing about delivery *during* a blocking privileged call, which is the entire
  question. The gate requires at least five with `0 < fraction < 1`.
- **The latency distribution must have spread.** `min <= p99 <= max` is satisfied trivially by a
  degenerate distribution where every read is identical, so `max > min` is asserted separately.

And the CPU figure is **cross-checked from outside**: a `ps` sampler runs alongside the cycle,
because a self-reported number that nothing can contradict is a number rather than evidence.

### Verification status — 2026-08-04, before the hardware session

**497 tests, 0 failures.** Zero source warnings from **all three** clean builds with DerivedData
wiped before each: `build.sh Debug`, `build.sh Release`, `test.sh`. (The three-command form is
Step 8's lesson — `build.sh` does not compile the test target, and two of the three had been the
whole check for seven steps.)

Everything that can be verified without hardware is verified. What remains needs a v8 daemon and
the drive:

| | |
|---|---|
| Install + register v8 | `scripts/install-app.sh Release`, then unregister/re-register in the app and confirm with **Check version** |
| Step 9's gate | `scripts/metrics-check.sh disk4` — **writes** the first 1 GiB, ~15 s |
| D7's regression | `scripts/retention-cycle-check.sh disk4` — **writes**, ~70 min with the fingerprint passes |
| GUI items | Live metrics refreshing ≥ 1/s and the window staying responsive during a real run — observed, not rendered |

### D7's regression — PASSED on hardware (2026-08-04)

`./scripts/retention-cycle-check.sh disk4` — **15 checks, 0 failures**, against the live **v8**
daemon. Placement block **309,460,992**, drawn at random from 238,212 chunk-aligned positions.

**The check that mattered: `every one of the 932 window fingerprints is unchanged (NFR-REL-1)`.**
Step 9 rewrote the engine's inner loop — a span timer, an outcome-carrying measurement emitted on
every path including the three failure branches — and the whole terabyte is byte-identical after
writing 1,072,693,248 bytes. Also confirmed: 256 chunks (255 full + 1 short, FR-TEST-5), cache
bypass still `bypassed`, buffers still 2 × I/O size, fastest read 494,579,710 B/s.

**FR-TEST-10 was live and this run satisfied it.** Start offset 158,444,027,904 bytes is exactly
151,104 MiB; length 1,072,693,248 bytes is exactly 1023 MiB. The run does **not** end at the
device's last block, so it passed on the length rule alone — the old `1 GiB − 512 KiB` constant
would have been refused, as predicted.

> **But a passing run is not evidence a guard is enforced.** It shows the rule did not get in the
> way. An unenforced guard looks exactly like an enforced one until something misaligned arrives.
> So `metrics-probe` now asks for **both** forbidden placements explicitly — a start one block past
> zero, and a length one block short of a whole MiB in the middle of the device — and
> `metrics-check.sh` requires both to be refused **with zero chunks processed**. Neither performs
> any I/O: placement is validated before a block device is vended.

### NFR-PERF-3 — the number it has never had (measured 2026-08-04)

Measured **in the product's own run path**, not inferred from a CPU percentage and not from the
gate's SHA-256:

| | |
|---|---|
| host overhead ÷ device I/O time | **2.686%** — the run is **97.3% device-bound** |
| daemon CPU | **5.269% of one core** at ~495 MB/s |

For comparison, the figure this replaces: 36–39% of one core, observed in Activity Monitor during
Step 8's gate, which was the *fingerprint's* SHA-256 and is not in the product at all. The product's
run path is roughly seven times cheaper.

**My estimate was wrong by 11×, and recording that is the point of having measured it.** Step 8's
note predicted "order 40–80 µs [of host work] against ~25 ms of I/O"; the measurement is
**683 µs per chunk** against 25.44 ms. A `memcmp` over two 4 MiB buffers touches 8 MiB and is
memory-bandwidth bound, which plausibly accounts for much of it — but that is a hypothesis, and the
only reason the 40–80 µs figure survived this long is that nobody had measured it. It is not
re-estimated here.

**This triggers BUILD-PLAN 9.5a's release-note item.** The gate item says: *if the ratio implies
the host becomes the limit at a transport speed the product plausibly meets, that is a release-note
item, carried to Step 16.* Holding host work per chunk constant:

| transport | device time / chunk | host overhead as % of it |
|---|---|---|
| USB 3.1 Gen 2 (measured) | 25.44 ms | **2.7%** |
| USB 3.2 Gen 2×2 | 6.29 ms | **10.9%** |
| USB4 / Thunderbolt | 3.31 ms | **20.6%** |

The daemon saturates one core at roughly **4.7 GB/s**, and host work equals device time at roughly
**18.4 GB/s**. USB4 enclosures exist and this product plausibly meets them, and 20.6% is not
"negligible" in NFR-PERF-3's sense. **Carried to Step 16 as a release-note item.**

> **Superseded and partly WRONG — corrected 2026-08-05 by the four-size sweep.** Left in place
> rather than edited, because the error is the point: **"4.7 GB/s" was an arithmetic mistake**, a
> stray factor of 0.5. The correct figure is **11.1 GB/s** — more than double the headroom. The
> figure also rested on a single 4 MiB point and used the *fastest observed read* as the
> throughput rather than the run's actual rate. See "The sweep, and NFR-PERF-3 finalised" below.
> The percentage columns above survived the correction; the saturation point did not.

### Increment 6 — the I/O-size sweep, and the diagnostics window (2026-08-04)

**The gate now sweeps all four I/O sizes** (user decision). It runs the same gibibyte at 1, 2, 4
and 8 MiB, which gives an **8× lever on chunk count at constant bytes** — enough to settle the
question the 4 MiB-only measurement left open: does host cost follow **bytes moved** or **chunk
count**? The two imply opposite advice about I/O size, so the Step 16 release note could not say
anything until this was measured. It also exercises the chunk plan at every size the UI offers, on
real media, which nothing had done.

The analysis reports µs/chunk and µs/MiB per size and states which normalisation is flat.
**Verified against synthetic data before the hardware run** — fed a pure-bytes profile, a
pure-chunks profile and a mixed one, it returns all three verdicts correctly. A verdict that can
only reach one conclusion is not a verdict.

**The diagnostics panel is now its own window** (user decision: the main window's vertical space
had become excessive).

> **Not a sheet, and the reason is functional.** The control that *starts* a run lives in
> diagnostics; the metrics panel that *displays* it lives in the main window. A modal would cover
> the one thing worth watching, for the whole of the run it had just started. A separate
> non-modal window sits beside it.

**One connection, hoisted into `AppModel`.** This is a correctness requirement, not tidiness: the
helper releases a device claim when the connection that acquired it goes away (NFR-REL-5), so two
scenes each building their own `HelperConnection` would be two owners — and closing the diagnostics
window could drop a claim out from under a run in the main window. It is the same hazard Step 6
hit when the device list gained its own reason to talk to the helper, solved the same way, one
level up. Step 11's state machine replaces the run-state fields this class currently stands in for.

`Window` rather than `WindowGroup`: there is one helper and one registration state, so a second
copy of the panel would be two views of one truth that could disagree. Opened from the Window menu
or **⇧⌘D**.

**A stale instruction found by rendering.** The device panel's readiness banner told the user to
install the helper *"under 'Privileged helper & diagnostics' **below**"* — which stopped being
true the moment the panel became a window. NFR-USE-5 asks for the corrective step, and a
corrective step pointing somewhere the control is not is worse than none. Now points at the window
and names the shortcut.

**And the height was measured rather than guessed.** At 620 pt the mount controls fall below the
fold; 700 pt is where the idle window stops clipping. That is only 20 less than Step 6's 720 —
moving the diagnostics form out bought back roughly what the metrics panel spends. The panel is
~55 pt idle and ~300 pt with a run in progress, so the *running* window wants nearer 900. If that
proves excessive the next lever is making the selected-device detail collapsible, rather than
shrinking anything that carries a warning.

### First hardware run of `metrics-check.sh` — 8 failures, all mine, none in the product

**What passed, and it is the substance of the step.** At every one of the four I/O sizes: the
cycle completed every planned chunk (1024 / 512 / 256 / 128), no failed ranges, FR-TEST-9 still
`bypassed`, buffers exactly 2 × the I/O size, **13–16 snapshots delivered mid-run while the
privileged call was blocking**, widest gap **505 ms** against NFR-PERF-5's 1000, progress
monotonic, `min ≤ p99 ≤ max` with real spread, and transport-plausible throughput.

**And FR-TEST-10 was shown refusing**, which a passing run cannot show: a start at block 1 and a
length one block short of a whole MiB were both refused, **with zero chunks processed**, each with
a message naming the rule and the reason.

**The 8 failures were one probe bug.** Every "final" figure was exactly `samples ÷ chunks` —
96.39% = 987/1024, 95.31% = 488/512, 93.75% = 240/256, 96.09% = 123/128. The polling loop exits
the instant the cycle replies, so its newest snapshot was the one caught up to a poll interval
*before* the end; **nobody ever asked the helper what the completed state was.** The runs had all
completed. Fixed by issuing one more `runProgress` after the reply — `MetricsChannel` keeps the
finished run's accumulator until the next run replaces it, so that final ask is the run's real
end state.

The arithmetic is what identified it. A failure that is off by an arbitrary amount is a mystery;
one that is off by exactly the polling granularity, at four different chunk counts, is a
measurement artefact.

**A second probe artefact, fixed in the same place.** Each table's first row read 100% and then
dropped to 3%, because `MetricsChannel.begin()` runs inside `runCycle` *after* validation —
correctly, so a refused run does not wipe the previous run's figures — leaving a few milliseconds
in which a poll still sees the **previous** size's completed snapshot. The probe now settles 250 ms
before its first poll, the same fix and the same reasoning as the D1 pre-flight.

### "The Run one bounded cycle button appears to do nothing" — it worked; the button was wrong

The unified log settled it in one query:

```
07:28:51.596  deviceProfile from pid 49059: no device is held
07:28:51.625  discovery frozen (run active)      <- cycleIsRunning went true
07:28:51.650  discovery resumed                  <- and false again, 25 ms later
```

Three presses, three identical sequences. The binding propagated, the call went out, the helper
answered truthfully, and the whole thing was over in **25 ms** — a spinner for one frame and a
failure message.

**The defect is that the button was pressable at all.** Every other control in this app disables
itself and names the corrective step (FR-SAFE-4, NFR-USE-5); the connection section literally says
"These are disabled until the helper is enabled above". This one stated its precondition **in
prose** and then looked live. *Prose is not a precondition.*

Fixed: the button is disabled unless a device is held, with the corrective step spelled out
underneath. That required `helperHoldsDevice` to move into `AppModel` — the device is acquired in
the **main** window and the cycle is started in the **diagnostics** window, so neither view can own
it. `DeviceListView` now reads it through the model rather than keeping a `@State` mirror, because
a second copy of that answer would eventually disagree with the first about whether a run may be
offered.

**Two stale spatial references, both found by rendering rather than by reading.** The device
panel's readiness banner said to install the helper *"under 'Privileged helper & diagnostics'
**below**"*, and the bounded-cycle section said it would give *"the metrics panel **above**"* a run
to display. Neither was true once the panel became a window. A corrective instruction pointing
where the control is not is worse than none — the first told the user to look somewhere the thing
had never been.

`ui-probe` gained a `diagnostics-held` view so both states of the button are renderable, since the
disabled one is what a user meets first and is the one that was reported as broken.

**497 tests, 0 failures; zero source warnings from all three clean builds** after these fixes.

### The sweep, and NFR-PERF-3 finalised — `metrics-check.sh disk4`, **0 failures** (2026-08-05)

Every hardware-only gate item discharged, at **all four** I/O sizes.

| | 1 MiB | 2 MiB | 4 MiB | 8 MiB |
|---|---|---|---|---|
| chunks | 1024 | 512 | 256 | 128 |
| progress reached | 100.00% | 100.00% | 100.00% | 100.00% |
| latency samples | 1024 | 512 | 256 | 128 |
| mid-run snapshots | 14 | 13 | 14 | 13 |
| widest gap | 505.4 ms | 505.3 ms | 505.3 ms | 505.4 ms |
| read / write | 517 / 491 | 516 / 491 | 488 / 492 | 501 / 492 MB/s |
| p99 (min ≤ p99 ≤ max) | 2.195 ms | 4.162 ms | 9.175 ms | 17.302 ms |

**NFR-PERF-5 is discharged with a factor of two in hand**: the widest gap between live snapshots
was **505 ms** against a 1000 ms requirement, and 13–14 of them arrived *while the privileged call
was blocking* — which is the property the whole second-connection design exists to provide, and
which no amount of simulation could have shown.

**FR-TEST-10 was shown refusing**, not merely shown not-refusing: a start at block 1 and a length
one block short of a whole MiB were both refused with **zero chunks processed**, each naming the
rule and the reason.

**The open question is answered: host cost follows BYTES MOVED.** µs/MiB varied **1.32×** across an
8× range of I/O size while µs/chunk varied **8.65×**. A larger I/O size does **not** reduce host
overhead. Step 16's release note can now say something true instead of nothing.

**NFR-PERF-3, final:** at the 4 MiB default with the device moving ~470 MB/s, in-span overhead is
**2.55%** and daemon CPU **4.22% of one core** — the run is **97.4% device-bound**. The independent
`ps` sample peaked at **8.5%**, the same order as the self-reported figure, which is what that
cross-check exists to establish.

**A correction to what I reported yesterday.** I said the daemon saturates one core near
**4.7 GB/s**. That was an arithmetic error — a stray factor of 0.5 — and it understated the
headroom by more than half; the figure is **11.1 GB/s**. It also rested on a single 4 MiB point and
used the *fastest observed read* rather than the run's actual throughput. Both are fixed above and
in BUILD-PLAN Step 16.

**And one thing measured but not explained.** Total daemon CPU fits roughly **209 µs fixed per
chunk + 207 µs per MiB**, while the *in-span* overhead follows bytes alone. The difference is work
outside the timed span — which the span is documented to exclude, since it stops before the
observer is called. What that per-chunk term is has not been measured and is **not guessed at
here**: the 40–80 µs estimate that stood for three steps was wrong by 11× for exactly the want of
measuring rather than reasoning.

**D7's regression still stands.** Verified rather than assumed: **no file in the helper, `Core/` or
`Shared/` has changed** since `retention-cycle-check.sh disk4` passed 15/15 with all 932 window
fingerprints unchanged. Everything modified since is app-target UI, a tool, or a script.

---
