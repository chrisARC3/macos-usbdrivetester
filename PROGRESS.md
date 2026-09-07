# Build Progress Log — the step in progress

**This file holds the current step and nothing else.** It was 7,156 lines on 2026-08-11 and was
split, because a log a cold start is told not to read is a log that is not doing its job.

| where | what lives there |
|---|---|
| **PROGRESS.md** (this file) | the step in progress |
| **[CONSTRAINTS.md](CONSTRAINTS.md)** | **read this in full** — what binds future work: measured behaviour, settled decisions, lessons |
| **[BUILD-PLAN.md](BUILD-PLAN.md)** | the plan, the per-step gates, the process gotchas, the test hardware |
| [`progress/step-11.md`](progress/step-11.md) | **Step 11's full account, archived 2026-09-05** — twelve increments, the defects each one found, and the reasoning. Read it for *"why was it done that way?"*, not as current |
| [`progress/step-11-increment-plans.md`](progress/step-11-increment-plans.md) | **the settled decisions from increments 9–12 — nothing is planned in it.** Deliberately not archived: some of it binds Step 12. **Read before re-opening one of those decisions** |
| [`progress/step-11-human-checklist.md`](progress/step-11-human-checklist.md) | Step 11's keyboard checks — what no test can reach. **All 16 chunks passed.** ⚠️ **Those passes do not transfer**: re-walk what later work touches |
| `progress/step-NN.md` | archived history, for *"why was it done that way?"* |

**The full account of an increment goes in its commit message**, with this file carrying a summary
and the hash. Writing it twice at length produced two long prose accounts of one increment that
could drift; the commit is the immutable, greppable one.

---

## Step 12 — Device-loss handling (hot-unplug / de-enumeration mid-run). **IN PROGRESS**

> **Cold start? Step 12 began 2026-09-05.** Chunks 0–6 of 8 are done; **chunk 7 is not**.
> Step 11 closed 2026-09-05 and its account was archived to
> [`progress/step-11.md`](progress/step-11.md) the same day. Nothing below is a snapshot; all of it
> is current as of **2026-09-07**.
>
> ⚠️ **This block said *"chunk 1 … is done; chunks 2–7 are not"* until 2026-09-06** — three chunks
> and a protocol bump stale, in the file whose entire job is to say where the work is, and it read
> as current because it carried a date. That is the **seventh** time this repository has shipped a
> status block disagreeing with the body under it, and **the first one outside `BUILD-PLAN.md`**,
> which is where the habit of looking had been built. The block below it was edited every chunk;
> this one was never the block anyone was looking at. **Grep for the claim, not the filename** —
> `grep -rn "chunks 0–" *.md` finds every instance of this claim in one line of effort.

> **Read before designing anything here**, in this order:
>
> 1. **[`BUILD-PLAN.md`](BUILD-PLAN.md)'s Step 12 section** — it is unusually well supplied. It
>    carries **three decisions taken during Step 9** (user decision 2026-08-05) that must not be
>    re-derived, and a **real device loss that happened on hardware 2026-08-06**, mid-gate, with the
>    errno the product actually saw.
> 2. **[`CONSTRAINTS.md`](CONSTRAINTS.md)**, in full — its *"Device loss"* entry is the measured
>    behaviour this step has to accommodate, and §2 and §3 are working practice and lessons already
>    paid for.
> 3. **[`progress/step-11-increment-plans.md`](progress/step-11-increment-plans.md)** — the settled
>    decisions from increments 9–12. Some bind here; `QuitSequence`'s shape especially.

### What Step 12 inherits, in one paragraph

A drive that drops off the bus is currently reported as **a drive with ~2 million bad blocks**. On
2026-08-06 the scratch device de-enumerated part-way through `retention-cycle-check.sh` and the
helper saw **`errno 6` — `ENXIO`, *"Device not configured"* — on every read including offset 0**.
That is the discriminator: `EIO` on one block is a bad block; `ENXIO` on offset 0 of a working
descriptor means the descriptor is dead. Nothing detected it, so log-and-continue did exactly what
it is built to do with a failing drive. The drive re-enumerated healthy about two seconds later.
**Step 12 is what turns that into a terminated run and an honest error** (FR-DEV-8). The three
inherited decisions — wait for the in-flight I/O to time out rather than aborting it, rebuild the
device list from scratch, and let the rebuild re-apply FR-DEV-3's default — are in BUILD-PLAN with
their reasoning.

### Current state — 2026-09-07, at Step 12 chunk 6

| | |
|---|---|
| **Working tree** | clean, on `main`. **Ahead of `origin/main` by Step 12's commits** — nothing is pushed unless asked |
| **Verified** | **1288 tests, 0 failures, 152 suites** (floor `scripts/.test-floor` = 1288), run green 2026-09-07 at chunk 6. Chunk 1 added **19 tests in 4 suites**; chunk 2 added **12 in 2**; chunk 3 added **13 in 1**; chunk 4 added **49 in 2** — `DeviceLossWindDownTests` (13) and `RunControllerDeviceLossTests` (23), plus 6 policy rows and 7 sequencer tests into existing suites; chunk 5 added **42 in 4** — `DeviceLossAccountTests` (11, displayed as *"Device-loss account (Step 12, FR-DEV-8)"*), `DeviceLostOutcomeTests` (9), `DeviceLostMarkdownTests` (7) and `RunControllerDeviceLossReportTests` (7), plus 8 into `HonestFramingTests`; chunk 6 added **26 in 3** — `RunControllerDeviceLossSurfaceTests` (9), `DeviceLossMessageTests` (10, displayed as *"Device-loss alert (Step 12, FR-DEV-8)"*) and `AppModelDeviceLossTests` (5, *"Device loss rebuilds the list (Step 12, FR-DEV-8)"*), plus 2 more into `HonestFramingTests`, which now stands at 29. Build figures re-derived 2026-09-07: DerivedData wiped, then `build.sh Debug`, `build.sh Release` and `test.sh` in sequence — **zero source warnings from all three** (the only `warning:` lines in any log are `appintentsmetadataprocessor`'s "No AppIntents.framework dependency", which is a toolchain notice and not a source warning), **13/13** gate clients type-check. ⚠️ **This is not the increment gate**: that wipes DerivedData before *each* of the three and records the `SwiftCompile` task counts to prove none was cached. One wipe, three builds. The full form is chunk 7's |
| **Helper** | source hash **`4277458911ad3b1ed1f52c5a43ab9d9e1fdc593724fb7a6ac723105f45e769f3`** — moved twice on 2026-09-05: `e6888aa5…` → `a951e527…` (chunk 1) → **`42774589…`** (chunk 3). Chunks 2, 4 and 5 did not move it, being app-target only — **and this row predicted that chunk 4 would**, which was wrong: chunk 4 is the state machine and the wind-down, entirely inside the app, and chunk 5 is the report. Re-derived at chunk 5 and again at chunk 6 (2026-09-07), unchanged both times. The four gates below lapsed at chunk 1 and have not compounded since. **Re-derive it before trusting any hardware gate result below** — the recipe is `find USBDriveTester/com.arc3solutions.USBDriveTester.Helper USBDriveTester/USBDriveTester/Shared -name '*.swift' \| sort \| xargs cat \| shasum -a 256`. **Chunk 6 was app-target too, as this row predicted** — the first prediction in this row that held. The next thing that can move it is chunk 7 |
| **Protocol** | **v15**, since chunk 3 (2026-09-05). ⚠️ **The installed daemon is older than this.** The cycle reply went from 22 arguments to 23, so a v14 app and a v15 daemon **cannot** decode each other — loud, unlike the v13→v14 bump. Reinstall and kickstart before any gate: `scripts/install-app.sh` |
| **Hardware gates** | ⚠️ **ALL FOUR LAPSED 2026-09-05, at chunk 1, exactly as the plan predicted** — the helper hash moved and every result recorded against `e6888aa5…` went with it. What each one *last* said, and what it is no longer evidence about: `metrics-check.sh` **128/0**, `xpc-concurrency-check.sh` **0 failures**, `retention-cycle-check.sh` **15/15** over the whole device — all three 2026-09-03 at `e6888aa5…`; `run-control-check.sh` **14 assertions / 0 failures**, twice on 2026-09-05 at the same hash. **None of these describes the current build.** They are re-run at chunk 7, against the moved hash and v15, and **a gate that has not been re-run cannot report anything** — do not cite the figures above as current |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, reinstalled 2026-09-04. ⚠️ **Always kickstart the daemon after `install-app.sh`** — it replaces the helper binary underneath the running one, and *nothing announces the mismatch when the helper source has not moved*. **Verify a reinstall took with `nm -U` on `Contents/MacOS/USBDriveTester.debug.dylib`**, not by timestamp: on 2026-09-04 a checklist chunk was nearly walked against a stale build |
| **Fixture** | 1 TB scratch T5, **serial `12345686DAA9`** (`disk7` on 2026-09-05 — BSD names move across a replug, so scripts resolve by serial). Its **`fill.bin` was restored 2026-09-04 18:19**: 999,947,239,424 bytes, volume 100% used, three samples digesting distinctly. **Invalidated by** unlinking the file or erasing the volume — **not** by `retention-cycle-check.sh` or `run-control-check.sh`, which write back exactly the bytes they read. Also attached as of 2026-09-04: the 4 TB T5 EVO (`disk6`) and the 125.8 MB UDisk thumb (`disk4`) |
| **Owed** | **The four hardware gates**, all lapsed at chunk 1 and re-run at chunk 7. Also owed at chunk 7: `progress/step-12-human-checklist.md`, which does not exist yet, and the hardware gate that has no substitute — **a person pulling a real drive out of a real port**, the only thing that can measure what chunk 4's 3-second deadline was chosen without. Chunk 7's checklist also inherits **three declared-uncoverable survivors** for its *"What has no automated cover"* list: `deviceUnderTest = nil` in `driveIsBack()` (chunk 4), the identity of the device-loss SF Symbol (chunk 5), and **`RunControllerWiring`'s `onDeviceLost:` closure** (chunk 6) — the composition root, where a decision has no cover but a person at the keyboard. **And one thing only a person can see at all: the device-loss alert itself**, which `render-ui.sh` cannot capture because an `.alert` takes its own window. Nothing else — Step 11 closed with its checklist complete, and chunks 0–6 closed green |
| **Remote** | private **`chrisARC3/macos-usbdrivetester`**, branch `main`. Commit straight to `main`; **nothing is pushed unless asked** |

### The one open measurement — CLOSED 2026-09-05, before Step 12 began

`run-control-check.sh`'s 1 MiB settle exceeding its own one-chunk bound is **explained and no longer
open.** The experiment CONSTRAINTS §1 called for was run on 2026-09-05 against the **v14** daemon at
helper hash `e6888aa5…`, on the 1 TB T5 scratch drive — `--repeat-1mib 8`, the 1 MiB case alone,
eight times, each self-calibrated from its own pre-pause window.

**The settle has a floor: it is the remainder of the current chunk plus a fixed ~3.5 ms.** No sample
fell below **0.65** of its own bound, which under a uniform draw is a one-in-4,400 event, and three
of the eight exceeded 1.0, which a uniform draw cannot produce at all. Mean, minimum and maximum
give the fixed term as 3.3 / 3.6 / 3.5 ms independently, and a 3.5 ms constant places **all twenty**
samples across four runs inside their predicted bands. **What the 3.5 ms is made of is measured, not
explained** — it is not transport latency, since the ack on the same XPC takes 0.36–0.53 ms. Full
tables, the arithmetic and that caution are in `CONSTRAINTS.md` §1.

It was never an NFR-REL-10 failure and still is not: that requirement fixes *where* the settle
happens, not *when*, and the resume arithmetic was exact in every case of all four runs.

**That run also re-passed the whole gate** — 14 assertions, 0 failures, all four I/O sizes settled,
protocol v14 — so the Step 11 gate row above rests on a second, independent v14 pass at the same
helper hash.

### Step 12's chunks

The approved shape is eight chunks. The full account of each is in its commit message.

| # | what | state |
|---|---|---|
| **0** | The carried-forward settle measurement. Instrument only — `tools/run-control-probe` and `scripts/run-control-check.sh` grew `--repeat-1mib N`; no product code | **done 2026-09-05**, `a6e3bb0` (+ `0356ecb`, a pointer fix). Helper hash **unmoved**. See the section above |
| **1** | **Route (a), the `ENXIO` discriminator.** Core only, no wire change | **done 2026-09-05**, `368bec6`. See below |
| **2** | Route (b), the DiskArbitration removal callback — `VolumeChangeWatcher` learns *which* disk went, and the "is this the device under test" predicate becomes a pure testable type | **done 2026-09-05**, `9242d6c`. See below. Helper hash **unmoved** — app target only |
| **3** | The wire: protocol **v15**, the fifth `RunOutcomeCode`, and all 13 gate clients rebuilt | **done 2026-09-05**, `15f8e3e`. See below. **Moves the helper hash to `42774589…`** |
| **4** | The state machine and wind-down: the sixth `RunControlEvent`, three ways in and one out, and a deadline that does **not** fail open | **done 2026-09-06**, `8ba574b`. See below. Helper hash **unmoved** — app target only |
| **5** | The report: the **sixth** `RunReportOutcome`, `DeviceLossAccount`, `HonestFraming`, presentation, Markdown | **done 2026-09-06**, `4b72d13`. See below. Helper hash **unmoved** — app target only |
| **6** | The error surface and FR-DEV-8's discovery re-run; the modal interaction and its ⌘Q truth-table row | **done 2026-09-07**, `1de0d53`. See below. Helper hash **unmoved** — app target only |
| **7** | Mutation round, `progress/step-12-human-checklist.md`, the physical-unplug hardware gate, **and all four hardware gates re-run** against the moved hash and v15 | not started |

### Chunk 6 — the run that said nothing now says something, and the list stops showing a drive that left

FR-DEV-8 asks for three things: end the run, present a suitable error message, and re-run discovery.
Chunks 4 and 5 did the first and — almost — the second. **The user decision that shaped this chunk
was "the report *is* the message":** no new modal on the ordinary path, because
`AppModel.presentedModals` flags `.runReport` and `.runFailure` independently and
`QuitPolicy.disposition(underModals:)` refuses ⌘Q outright when more than one is flagged. Raising
both would have rebuilt increment 12's defect on the new feature's **normal** path.
`theReportAndTheAlertAreNeverBothRaised` is the test that keeps it that way.

**Almost, because one path produced no message at all.** `makeReport` returns `nil` when the
sequence has no final reply, and `RunSequencer.lastReply` starts `nil`. A drive leaving during the
very first call, with the helper never answering, therefore produced no report, no alert, and a log
line reading *"the helper refused the call, so no run took place"* — false twice over: a run took
place and nothing was refused. That is not the exotic case. **The first call covers a whole slice,
up to a gibibyte, with every chunk read, written back and verified inside it** — so it is exactly
where a write-back is most likely to be in flight when somebody pulls the cable. The one case that
said nothing was the one where the most was at stake.

`DeviceLossMessage` closes it, as a pure value rather than a string at the call site, for the reason
`OutcomePresentation` is a type: **an `.alert` cannot be rendered by `scripts/render-ui.sh`** — it
takes its own window and `ViewBuilder`s AppKit consumes — so everything about the dialog that is not
a pure value is covered by a person at a keyboard and nothing else. What it *says* is decided where
a test can read it.

**The text carries no Markdown, and that is a constraint rather than a style.** `RunControlsView`
renders it as `Text(failure.text)` — a `String`, which SwiftUI does not parse; only
`LocalizedStringKey` does. A `**` copied across from `HonestFraming`'s prose would be shown to the
user literally. `noMessageCarriesMarkdownTheAlertCannotRender` pins it, and it is the exact mirror of
chunk 5's opposite defect, where the report's callout was passed `.plain` and lost emphasis it
should have had. **Same fault line, both directions: the surface decides whether Markdown is text or
formatting, and the string has to know which surface it is going to.**

**`releaseCannotBeConfirmed` reaches a person for the first time** — derived, not carried. It is set
from `ending == .theHelperNeverAnswered`, and that account arises from that same ending whenever
route (a) supplied nothing, which the deadline expiring already guarantees. So `RunReport` gains no
field; the report's sentence and the alert's third paragraph both say it, and both are asserted
**exclusively** — `onlyTheUnansweredCallReportsOnTheClaimAsWellAsTheData` fails if any other account
starts claiming it, which would tell a paused run whose release completed normally that exclusive
access might still be held.

**FR-DEV-8's third obligation fires from `driveIsBack`, not at run end**, because FR-DEV-7's freeze
has lifted by then, and it is passed as a **parameter** rather than read from a field:
`deviceLossEnding` is `nil` for a route (a) loss, and a field consulted after the run that set it is
chunk 5's surviving mutation. `onDeviceLost` is the one closure of the four with **no default
value** — doing nothing is a legitimate configuration for `onRunBegan`, `onRunSettled` and
`onFailure`, but omitting this one would silently drop an obligation. Three call sites failed to
compile, which is the compiler doing the remembering.

**The bench counts rather than flags.** `discoveryReRuns` is an `Int`, because chunk 4's measurement
says one unplug of a partitioned drive delivers a callback for the whole disk *and* one per slice;
`oneUnplugReRunsDiscoveryOnce` is the test that would catch a rebuild per slice.

**A gap was nearly written off as uncoverable and was not.** `AppModel.deviceUnderTestWasLost()`
looked like it needed a real `IOKitDeviceEnumerator` to observe. It does not — `AppModel.init` takes
a `DeviceSource` and `StubDeviceSource` already counts enumerations. `AppModelDeviceLossTests` (5
tests) pins the rebuild, the departed row disappearing, the selection being re-derived, the deferred
change being cleared, and **the freeze bypass** — discovery is deliberately still frozen when this
runs, since nothing has told it the run ended. The gap was in the reach of the bench, not in the
code, which is the distinction the mutation-round rule asks for before anything goes on the human
checklist.

#### The mutation round — 17 mutations, 14 killed, 3 survived, all three declared in advance

Survivors, exactly as predicted: **m6**, a wording-only edit inside a clause no test pins; **m15**,
`refresh(reason:)`'s log-only reason string, which no assertion should pin by text; and **m17**,
`RunControllerWiring`'s `onDeviceLost:` closure — the composition root, which has no cover but a
person at the keyboard. **m17 goes on chunk 7's checklist**, joining chunk 4's `deviceUnderTest =
nil` and chunk 5's SF Symbol identity. No unexpected survivors.

**The round found a defect in the test suite rather than in the app**, which is the third time in
this project that an instrument was the thing at fault. Three mutations that stop the alert being
raised all land on `theAlertNamesTheEndingThatProducedIt`, which read
`try! #require(bench.failures.first?.text)`. **`try!` on a failed requirement traps, killing the
test process** — xcodebuild printed *"Restarting after unexpected exit, crash, or test timeout"* and
the run ended having executed **321 of 1288 tests, with a green tick on the 321**. The other 967
reported nothing, so the one question a mutation round asks was unanswerable for three of seventeen
rows. `scripts/test.sh`'s floor check refused it — *"INCOMPLETE RUN: 321 tests in 54 suites, but
this repo has run 1288"* — which is the only reason it was noticed. All nine `try!` sites in the
test target were converted to `try #require` in throwing tests, and the three contaminated rows were
re-run clean. Written up as a `CONSTRAINTS.md` §3 lesson.

### Chunk 5 — the report says which route accounted for the loss, and refuses to over-warn

`RunReportOutcome.deviceLost` is the **sixth** outcome, not a shade of `incomplete` — the approved
chunk scope said *"fifth"*, which was a miscount of the enum rather than a decision, and the
presentation doc comment that already read *"six outcomes, six distinguishable symbols"* is the
authority. Chunk 3's interim is gone: `incomplete` asserts that **nothing accounts for the ending**,
and now something does.

**The centrepiece is `DeviceLossAccount`, and the reason it has four cases rather than one hedged
sentence is the paused run.** Route (a) can say *where* and *in which phase*; route (b) knows only
*that*, and route (b) has two ways of knowing it. Collapsing those would put *"a chunk may hold
partly written data"* into the report of a run that was demonstrably **paused with nothing in
flight** — a false alarm in a document somebody keeps, which is how a reader learns to discount the
warnings that are real. So the four cases are named:

| account | how it arises | `aWriteBackMayBeUnfinished` |
|---|---|---|
| `theHelperSaidWhere(block:phase:)` | route (a)'s reply landed | `true` only for `writingBack` and `unrecognised` |
| `nothingWasInFlight` | route (b), run paused — no reply *could* arrive | **`false`** |
| `theHelperNeverAnswered` | route (b), the deadline expired | `true` |
| `noRouteSaidAnything` | neither said when | `true` |

The verdict table is pinned row by row by `theWriteBackTableIsPinned`, and `unrecognised` reads as
**unsafe** for the same reason `CacheBypassOutcome.unrecognised` does: a helper newer than this app
naming a phase this build cannot map is not evidence of anything good.

**`removalCallbackSaid` is a required parameter of `RunReport.init` with no default**, and that is
the whole trick. `nil` is a perfectly safe value, which is exactly the trap — a caller that forgot
it would compile, produce a report, export a file, and simply decline to say whether a chunk was
mid-write. Ten call sites had to be updated one file at a time, which is the compiler doing the
remembering. `deviceLossAccountAgreesWithTheOutcome` closes the other half: an account exists
**exactly** when the outcome is `deviceLost`.

**Two defects were found by instruments rather than by reasoning.**

- A test caught the report printing `4194304` in a sentence and `4,194,304` in the table row
  immediately below it — one document, two spellings of one number. `HonestFraming.claim(about:)`
  now formats through the same `MetricsFormatting.blockOffset` the row uses.
- Reading the render caught the callout passing `.plain` with `emphasised: true`, which made the
  whole paragraph semibold and flattened the hierarchy the Markdown export had: the urgent clause
  read exactly like the rest of it. It now passes `.markdown` through `LocalizedStringKey` with no
  blanket emphasis, and the on-screen bolding matches the exported file clause for clause. **This is
  the only callout in the report that carries Markdown**, and the reason is in a comment beside it.

**The mutation round: 11 mutations, 9 killed outright, one predicted survivor, one finding.**

- **Predicted and confirmed:** changing `eject.circle.fill` to any other unique symbol survives. The
  presentation tests pin **distinguishability, not identity**, deliberately — chunk 7's checklist
  gets the eyeball check.
- **The finding:** deleting `deviceLossEnding = nil` from `driveIsBack()` survived all 1261 tests,
  **and `theEndingDoesNotSurviveIntoTheNextRun` existed to prevent exactly that**. The test drove a
  second run to a *clean* finish — and `DeviceLossAccount.forRun` reads the removal callback's
  ending only when the run ended `deviceLost`, so on any other ending a leftover value is never
  consulted and the green tick meant nothing about the line it was named after. It is now
  `aCleanRunAfterALostOneGetsNoAccount`, which is what it actually pins, and
  `aLeftoverEndingIsNotBelievedByTheNextLostRun` drives a **second losing run** through route (b)'s
  shape. Under the mutation the first run's `nothingWasInFlight` accounts for the second run's loss
  and `aWriteBackMayBeUnfinished` flips `true` → **`false`** — a false all-clear about half-written
  data, the one direction this type must never be wrong in. Killed on both assertions.
  **What today's wire makes of that is written into the test rather than left implied:** a real
  `deviceLost` reply always carries a block and a phase, and route (b) always writes the field
  before ending the run, so the two halves cannot currently meet in production. The clear is kept
  and pinned because the field's lifetime is the only thing holding them apart.

**The round also produced an instrument failure worth more than the mutations.** A background job
running m1–m6 was still alive while a foreground runner started at m3, so **two mutation runners
mutated and restored one working tree at the same time for four mutations.** The results looked
plausible — m5 reported three failures in two device-loss tests — and were nonsense; re-run alone,
m5 fails **29** assertions. Nothing in the output said the tree was shared. See `CONSTRAINTS.md` §3.

**Markdown placement is a requirement, not a preference.** The account sits *below* FR-TEST-9's
cache-bypass statement — the file header already forbids anything coming between the outcome line
and whether the check behind it can be trusted — and *above* everything else, because it is the only
part of the document a reader cannot reconstruct once the drive is gone.

**Renders read, not assumed.** `tools/ui-probe` grew `report-device-lost`,
`report-device-lost-paused` and `report-device-lost-silent`; all three were captured and read. Three
genuinely different accounts under one headline, and the paused one is calm.

**Chunk 6 still owes the user-facing half**: `releaseCannotBeConfirmed` and `DeviceLossEnding` reach
the report but not yet the error surface.

### Chunk 4 — the two routes meet, and only one run ends

The sixth `RunControlEvent`, `deviceLost`, and `DeviceLossWindDown` — the type that stops routes (a)
and (b) ending one run twice, and stops route (b) throwing away route (a)'s detail in the ordinary
case where the reply is milliseconds behind the callback.

**The deadline does not fail open, and `QuitSequence`'s own argument is why not.** `QuitSequence`
terminates the app when its deadline expires, on the grounds that the helper releases a claim when
the connection holding it goes away (NFR-REL-5) — **process death is itself the fallback release**.
None of that carries over here: the app is not dying, it is finishing a run and giving a drive back
while staying alive. Treating silence as "never mind" would leave a paused run holding an exclusive
claim on a drive DiskArbitration has already said is gone, which is the exact failure FR-DEV-8
exists to prevent. Silence is not evidence the drive came back, so the deadline ends the run.

**What it must not do is claim the drive was released.** The 2026-08-04 concurrency measurement
settles this: a second message on a connection with a blocking call in flight is not delivered until
that call returns. So a deadline expiring means the owning connection is *still blocked*, and the
`releaseDevice` that follows cannot be delivered — let alone acknowledged. The controller therefore
issues it and does **not** wait, reaching `finished` rather than wedging in `finishing` over a drive
that is not attached; `releaseCannotBeConfirmed` records that the claim's fate is unknown, and a late
acknowledgement is logged rather than acted on. The recovery is real without being claimed: the next
`acquireDevice` is refused by the helper, with its own reason, if the claim is still held. **Chunk 6
surfaces this to a person.** Three seconds is chosen to be uncontroversially generous rather than
tuned, and is documented as **not yet measured** — only chunk 7's physical unplug can measure it.

**One call site for the sixth event.** Both routes funnel through `sequencerReported(.runEnded)`, so
the log says the same thing either way and the `paused` row — where an ordinary `runEnded` is
ignored — is exercised by route (b). `RunControlPolicy.deviceLossWouldEndTheRun(in:)` derives route
(b)'s guard from the event table rather than restating it, and a test asserts the two agree.

**Two mutations survived, and both were findings rather than noise.**

- Deleting `windDown?.standDown()` broke nothing, because the sequencer's `.ended` phase already
  refuses a second ending. What it actually buys is the **log**: without it, a run that route (a)
  resolved cleanly gets an error-level line three seconds later accusing the helper of never
  answering. That is false evidence on the one path where a person is reading the log to find out
  what happened to their drive. The doc comments claiming it prevented a double-ending were
  **overclaiming and were corrected**; two tests now pin the real property.
- Building a fresh wind-down per callback also survived — because the bench held only the *latest*
  one. One unplug delivers three callbacks, so that defect arms three deadlines and leaves two of
  them running with nothing tracking them. The bench now keeps **every** wind-down it builds, and
  `threeCallbacksFromOneUnplugArmOneDeadline` drives three callbacks at a run that is still
  **running** — the paused walk could not cover it, because there the first callback ends the run
  and the state guard absorbs the rest. Re-run: killed, on both assertions.

**Known survivor, for chunk 7's checklist.** `deviceUnderTest = nil` in `driveIsBack()` is
defence in depth that no test can reach — the state guard refuses first, every time.

### Chunk 3 — protocol v15: the wire can say the device went away

`RunOutcomeCode.deviceLost = 5`, and chunk 1's interim `unrecognised` mapping is gone. The reply
gains **one argument**, `deviceLossPhaseCode` (23); the block the run died at travels in the
existing `interruptedAtBlock` slot.

**The one design decision worth stating.** That slot now carries two things depending on the outcome
code, and they say *opposite* things about what may happen next: under `pausedByUser` it is a resume
point, under `deviceLost` it is where the run died inside a chunk and FR-FAIL-7 forbids continuing
across it. Sharing the slot is right — it is the same quantity — but one app-side optional meaning
either would be **one field stating two facts**. `RunCycleOutcome` splits it into `resumeBlock` and
`deviceLostAtBlock`, each `nil` unless its own code arrived, and the load-bearing test asserts the
two are **never both non-nil** for any code and any block. The mutation that makes a lost device
offer a resume point kills four tests.

**The phase gets a field rather than being folded into the message**, because it is the one fact
about a device loss that changes what a person should do: a drive that vanished during the
**write-back** is the only case where this tool held the chunk's only copy of the original and had
not finished putting it back.

**v15 restores the property v14 lost.** v14 was the first bump whose reply did not change shape, so
a v13 app and a v14 daemon decode cleanly and display wrong numbers. v15 changes the arity, so the
mismatch is loud again — it broke **four gate clients and a dozen fixtures**, which is the compiler
doing work the handshake had to do alone last time. That is luck rather than design; the handshake
stays the guard that is not allowed to depend on it.

**Two protocol-pinning tests fired, as designed.** `theProtocolVersionIsFourteen` became
`…Fifteen`, and `anUnknownCodeFromANewerPeerIsNeverActionable` had been asserting that wire value
`5` decodes to `unrecognised` — **true until `5` became `deviceLost`**. A value chosen as "unknown"
stops being unknown the moment the protocol grows; it now uses `6`.

**Interim, and chunk 5 replaced it — 2026-09-06.** At v15 `RunReportOutcome.forRun` answered
`.incomplete` for device loss. That is the honest answer available at v15 — the run did not cover the drive, and it makes no
claim about the drive's condition — where `stoppedOnError` would accuse the drive of the very thing
this step exists to stop reporting and `stoppedByUser` would credit a person with an unplug.

### Chunk 2 — the removal callback names the disk, and route (b)'s question is a pure type

`VolumeChangeWatcher` registered `DARegisterDiskDisappearedCallback` **with the appearance
handler** and threw the `DADisk` away, because "something changed, re-read the mount table" was all
anything needed. It now has its own handler and reports *which* disk, with a whole/slice flag.
`DeviceUnderTest.wasLost(whenDiskDisappeared:)` is the pure predicate; the NFR-OBS-1 log line is
live today.

**Four DiskArbitration facts were measured rather than assumed** — first against a raw `DASession`
driven by `hdiutil` ram disks, then through the app's own watcher via
`scripts/device-probe.sh --watch`, which logged `a disk disappeared: disk13 (whole disk)` and
`disk13s1 (slice)`. They are in `CONSTRAINTS.md`, with the boundary stated: a ram disk detaching
cleanly is not a USB drive being pulled, and chunk 7's gate is what closes that.

The load-bearing one: **an unmounted whole disk does fire the callback.** A claimed device is
unmounted before the run, so "nothing left to report" would have sunk route (b) entirely.

**The prefix trap is the predicate's whole difficulty.** `disk7` and `disk70` share a prefix and
are different drives; a `hasPrefix` check — the obvious way to write "is this a slice of mine" —
ends a healthy run when an unrelated drive is unplugged. Matching is on the *parsed unit number*,
and the mutation that swaps it for `hasPrefix` is killed by five cases (`disk70`, `disk71`,
`disk700`, `disk79`, `disk130`).

**Matching on a BSD name does not break the 2026-08-06 identity rule**, and the reason is lifetime:
the question is asked only while a run holds an exclusive claim, about an event delivered during
that same claim. A BSD name cannot be reassigned while the device holding it is still enumerated.
The serial is carried anyway and is what the log line leads with.

**A layering defect that only the narrow build could find.** The predicate was first written into
`Discovery`, where it read `ReportedDevice` from `Report`. The app target compiled it and the whole
suite passed; `scripts/device-probe.sh` — which compiles `Discovery/*.swift` and one `Shared` file
and nothing else — failed instantly. The *event* type now sits with the watcher and the *question*
sits in `RunControl`. Recorded as a lesson: a layering rule nothing compiles against is a comment.

**Deliberately not built:** the predicate has **no production caller yet.** Chunk 4 is what acts on
the answer — ending the run, releasing a claim on an already-absent device, and doing it **once**,
which matters because one unplug produces one event per slice plus one for the whole disk.

### Chunk 1 — a lost device is no longer a drive with two million bad blocks

**The discriminator is `ENXIO` alone** (user decision 2026-09-05). Classified at the syscall site
by a pure function, `FileDescriptorBlockDevice.ioError(forErrno:operation:atByteOffset:length:)`,
into a new `DeviceIOError.deviceLost`; the engine's `failureKind` became `classify` and returns a
third answer; `RunOutcome` gained a fifth case, `deviceLost(atBlock:phase:)`. **Failures found
before the loss are carried through untouched** — they were real readings of a real drive.

**`EIO` is deliberately not treated as loss**, and BUILD-PLAN's Step 12 detailed step 1 was
corrected in the same commit because it said `ENXIO`/`EIO` — contradicting the incident note two
paragraphs above it, which has said since 2026-08-06 that `EIO` is a bad block. Two further lines
deferred to the wrong half, so it was stated three times and the right half once. Treating `EIO`
as loss would end a run at the first genuine bad block.

**The mutation check that matters**: reverting `classify` to send device loss back to a block
failure kills five tests, and one failure message is the original defect at fixture scale — 65
read-error ranges covering blocks 0–8192 on a device that is not there.

**What chunk 1 deliberately did not do.** The wire has no code for device loss until chunk 3, so
`main.swift` maps the new outcome to `RunOutcomeCode.unrecognised` — an **interim** answer, marked
as such at the site. It cannot mislead in the dangerous direction (never a completion, nothing
recorded against the drive) and the honest sentence still travels, because the reply's message is
built from `RunOutcome.description`. What it costs until chunk 3: the app cannot tell this from a
refusal, so no FR-DEV-8 discovery re-run and no device-loss verdict in the report.

**Two things carried into later chunks rather than assumed:**

- **`shortTransfer` still classifies as a bad block.** A device vanishing mid-transfer could
  plausibly produce a short read with `errno 0` *before* it produces `ENXIO`, which would record
  one spurious range before the run ended. That is one range rather than two million, so it is not
  the defect this step is for — but it is unverified, and **only the hardware gate can answer it**.
- **Route (a) is blind while a run is paused.** A paused run has returned from its call and issues
  no syscalls, so there is no `errno` to classify — the helper sits holding the claim and the fd.
  Only route (b) can see a device unplugged while paused, which makes **chunk 2 load-bearing
  rather than a second opinion**. Recorded in BUILD-PLAN's risks, which did not name it.

## Known loose ends carried into later steps

- **Step 12 inherits the worst one, and chunk 1 fixed the engine's half of it:** a drive that drops
  off the bus was reported as a drive with ~2 million bad blocks. The **engine** no longer does
  this, chunk 2 built the detection route that covers a **paused** run, and chunk 3 put the ending
  on the wire so the app can tell it from a refusal. What remains: **nothing acts on route (b)**
  and the report has no device-loss verdict — chunks 4 and 5. See
  [CONSTRAINTS.md](CONSTRAINTS.md), "Device loss".
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
