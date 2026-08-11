# Step 10 — Failure modes, bad-block report, and Markdown export

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

---

## Step 10 — COMPLETE AND COMMITTED (2026-08-09) — READ THIS FIRST FOR A COLD START

**Step 10 is done, verified on hardware, and committed in two commits.**

> **The order changed on 2026-08-09: STEP 14 IS NEXT, NOT STEP 11** (user decision). Step 11's
> deletion of the `Unmount All` / `Acquire` / `Release` controls was always *gated* on Step 14's
> warnings existing, and the gate was settled by building Step 14 first rather than by splitting
> Step 11 or landing both together. Neither step has been started. See "Step 14 — scoping and
> authoring log (started 2026-08-09)" below for the seven decisions and the increment plan.

| | |
|---|---|
| `15dbc40` | `Step 10: failure modes, bad-block report, and Markdown export` |
| `9d1f3d3` | `Fix: unmount per volume by node — a whole-disk unmount skips APFS volumes` |

**744 tests, 0 failures, 88 suites.** Zero source warnings from three clean builds. Helper source
hash `737e6972bfdec1c5c1901a27bd5a00da2fed413166c909fc6639666c38e8907e` — unchanged since the
gates, so all three still apply. Release build installed at `/Applications`.

**The unmount rollback is verified.** It was the one outstanding item at the 2026-08-07 session
end; verifying it exposed a **pre-existing Step 6 defect** — `DADiskUnmount` with
`kDADiskUnmountOptionWhole` does not unmount APFS volumes in containers on the disk, and reports
success having skipped them. Fixed in `9d1f3d3`. **Step 11's Start sequence depends on that fix**
and on the fixture built to reach it. Full account below at "Step 10 — the unmount rollback,
verified (2026-08-09)".

**The hardware fixture for it is built and must not be re-formatted casually**: the 4 TB T5 EVO,
serial `00000S7CLNJ0WC02266P`, carries GPT + EFI(unmounted) + `Vol_ExFAT` + `Vol_APFS` +
`Vol_HFS`. Step 11 needs exactly this layout — its Start owns unmount → acquire → run and its
abort path reaches the identical partial-unmount state with no manual control at all. Rebuilt by
`scripts/make-unmount-fixture.sh` if lost.

> **The section below is the 2026-08-07 snapshot, kept for audit.** Its "nothing is committed"
> and "one fix is unverified" statements were true on that date and are **superseded by the
> block above** — both were discharged on 2026-08-09.

### Where the work stood on 2026-08-07 — SUPERSEDED

| | |
|---|---|
| Increments 1–5 | complete — vocabulary, mode logic, protocol v9, report model + Markdown, report window + export + mode picker |
| Increment 6 | three clean builds; **all three hardware gates passed** |
| Post-gate work | the window-close behaviour, the "Last run" pane, and the unmount rollback — all from the user exercising the shipped app |
| **Commit** | **NONE. The working tree holds the entire step**, 32 modified files + 7 new (`Report/` and six test files). Last commit is still `8567e88`. |

### Verified state

**722 tests, 0 failures, 86 suites** (was 551/65 at the start of the step). Zero source warnings
from three clean builds — `build.sh Debug`, `build.sh Release`, `test.sh`, DerivedData wiped
before each. **Protocol v9.** The Release build is installed at `/Applications`, and the helper
was re-registered from it and confirmed at v9 by the user.

**Hardware gates, all on the scratch device (serial `12345686DAA9`), 2026-08-07:**

| gate | result |
|---|---|
| `xpc-concurrency-check.sh` | 0 failures; daemon confirmed at v9 |
| `metrics-check.sh` | 0 failures, all four I/O sizes, **including the three new v9 assertions** |
| `retention-cycle-check.sh` | **15 checks, 0 failures** — all 932 whole-device fingerprints unchanged (NFR-REL-1) |

The retention gate **failed on its first attempt** for a reason that was not a code defect: the
drive de-enumerated mid-run (`errno 6`, `ENXIO`). It passed after the user re-seated the cable and
moved it to a different port. Both runs are worth reading — the failure is what produced Step 12's
most important inherited note.

**The helper's source has not changed since the gates ran**, and that is checkable rather than
asserted: the twenty files that compile into the helper hash to
`737e6972bfdec1c5c1901a27bd5a00da2fed413166c909fc6639666c38e8907e`. Every install since has been
verified against it. All post-gate work is app-target only.

### THE ONE THING THAT WAS NOT VERIFIED — DISCHARGED 2026-08-09

**The unmount rollback's fourth and current version is installed but has not been tested by the
user.** Everything else in this step has been exercised on hardware or in simulation.

To verify it: re-register the helper, select a multi-volume drive, hold a file open on one volume,
press **Unmount All**. Expected — an error naming the volume that stayed mounted; only the volumes
that actually went are remounted; **the EFI partition is not mounted**; and a clean unmount on a
drive with nothing open simply succeeds with no remount at all.

**Two things about it are honestly unresolved:**

1. **The missing error message has a mechanism, not a confirmed cause.** The postcondition check
   used to call `discovery.refresh()`, which rebuilds the device list under the `List`; a
   selection binding that round-trips fires `.onChange(of: selectedDeviceID)`, whose handler does
   `lastOutcome = nil`. That would erase the message, and the settle loop would have run it up to
   twelve times per unmount. The call is gone — the mount table is read directly instead — but
   **this was found by reading, not by observing**, so the user's next test is what settles it.
2. **`mountOne`'s `kDADiskMountOptionDefault` is not covered by any test.** Swapping it for
   `…Whole` would bring the EFI defect back and the suite would stay green, because that call
   needs DiskArbitration and a real drive. The *decision* above it — which volumes get restored —
   is tested. Recorded at the call site.

### What to do first in a new session — DONE 2026-08-09, kept for audit

1. **Ask the user to verify the unmount rollback** (above). Do not commit before that.
2. If it passes, the step is complete and ready to commit as
   `Step 10: failure modes, bad-block report, and Markdown export`.
3. If it does not, the log is the instrument: `/usr/bin/log show --last 30m --style compact
   --predicate 'subsystem == "com.arc3solutions.USBDriveTester" and category == "safety"'`. It has
   settled every one of this control's four rounds.

### What Step 10 changed outside its own scope, and why a cold start should know

- **Protocol v9** — `runRetentionCycle` takes a failure mode and returns the report's raw
  material. Three tools and two gate scripts moved with it.
- **`AppModel.heldDevice`/`lastRunDevice`** replaced four parallel optionals with one record.
- **`DiscoveredDevice.mountedVolumeBSDNames`** added — a name cannot be mounted and a node can.
- **Closing the main window quits the app** — `QuitPolicy` gained `allowCloseAndQuit`.
- **The "Last run" pane is gone**; the metrics panel is live-only and the report window owns the
  finished run.
- **Three gate-script defects fixed**, all stale instructions: `retention-cycle-check.sh`'s re-run
  hint used a form its own parser rejects; `xpc-concurrency-check.sh`'s verdict told the reader to
  build the push channel Step 9 measured and *rejected*; `metrics-check.sh`'s protocol-mismatch
  advice named the wrong step.

---

## Step 10 — scoping and authoring log (started 2026-08-06)

**IN PROGRESS.** Failure modes + end-of-run bad-block report + Markdown export
(FR-FAIL-1..7, FR-RPT-1..5, FR-TEST-9, NFR-USE-7). Step 9 is complete and committed at `c6ec234`;
this step starts from a clean tree at `8567e88`, 551 tests / 65 suites.

### A correction to what Step 9 handed over, found by reading the code rather than the notes

Step 9's closing notes, and the brief written from them, say:

> *"Final throughput and latency are on the wire already — `runRetentionCycle`'s reply carries
> them, so the report assembles from measured values rather than re-deriving any."*

**They are not in that reply.** `TesterControl.swift`'s `runRetentionCycle` and the helper's
implementation of it send `completed, chunksProcessed, failedRangeCount, failureSummary,
cacheBypassCode, fastestObservedBytesPerSecond, bufferBytesHeld, hostOverheadFraction,
helperCoreFraction, message`. The only rate among them is **FR-TEST-9's falsifier figure — the
fastest observed *read*, not an average** — and `HelperConnection` discards it with a `_`.

The *conclusion* the note drew was still right: the figures are measured and must not be
re-derived. What was wrong was **where they are**. They live on `runProgress`, which returns the
last run's completed snapshot after the cycle ends, because `MetricsChannel.begin()` replaces the
slot and nothing clears it.

**And that location carries a defect the report would have inherited.** `MetricsChannel.begin()`
is step 7 of `RunCoordinator.runCycle`, after every validation refusal has already returned. That
ordering is *correct* — a refused run must not wipe the previous run's figures, and Step 9
recorded it as the cause of the "100% then dropped to 3%" first row in every sweep table. But it
means a **refused run leaves the previous run's throughput and latency installed**. A report
assembled by "the cycle replied, now poll `runProgress`" would then export the wrong run's
measurements, correctly formatted and authoritative-looking, into the only artefact this product
persists. That is this project's most expensive recurring bug — a value that reads as data when it
means something else — arriving in the worst possible place.

It is also the exact shape of Step 9's own probe defect #3, where the polling loop exited the
instant the cycle replied and nobody ever asked what the completed state was.

### Decisions (all user decisions, 2026-08-06, taken before a line was written)

1. **Protocol v9 carries the final figures back in `runRetentionCycle`'s own reply**, atomically
   with the run they describe. The alternative was to keep polling and add a run-identity token so
   the app could prove the snapshot belonged to the run that just finished. Chosen because it
   removes the wrong-run's-numbers hazard **by construction** rather than detecting it — a refused
   run simply has no figures to misattribute — and the version was bumping for the failure mode
   regardless. *Prevent, don't undo.*
2. **"Stopped by user" is deferred to Step 11**, and "terminated by device loss" to Step 12. Step
   10 ships only the outcomes reachable today: completed clean, completed with failures, stopped
   on error. The alternative was to build the case now and unit-test it, with the gate stating
   plainly that it was not hardware-observed. The user chose that **nothing untriggerable ships**
   — *a sound mechanism behind a trigger that never fires looks exactly like a broken mechanism*.
   Recorded as inherited notes on Steps 11 and 12, and as a struck-through checkbox on Step 10's
   gate so the item is visibly moved rather than quietly gone.
3. **The report gets its own `Window` scene.** Considered against a panel in the main window and a
   sheet. The main window is already at `minHeight: 700` with a ~300 pt metrics panel during a run,
   and Step 9 moved the diagnostics form out precisely because one column could no longer hold
   everything. The deciding argument was **verification**: a `Window` is renderable by
   `tools/ui-probe`, and a sheet is not — a SwiftUI `alert` gets its own window, which is why Step
   9's quit confirmation always needed a person at the keyboard. Cost: a third automatic
   Window-menu entry beside the known cosmetic duplicate.

### Two things settled by checking, not by reasoning

- **`failureSummary` stays in the reply.** Three tools call `runRetentionCycle`
  (`mount-guard-client`, `metrics-probe`, `xpc-concurrency-probe`) and two gate scripts parse
  `FAILED_RANGES` / `FAILURE_SUMMARY` out of their output. Dropping the summary as "a second
  representation of one fact" would have meant rewriting two gate scripts' parsing for no gain —
  and the gate scripts are the apparatus. The encoded ranges are added *beside* it: the summary is
  the human line, the encoding is the machine one, and both come from `FailureLog`.
- **The new wire vocabulary goes into `Shared/TesterControl.swift`, not a new `Shared/` file.**
  Seven scripts name that file as a single `SHARED=` in their standalone `swiftc` lines, so a
  second file would mean editing all seven *and* asking for a helper-target membership tick. Core
  keeps the domain types, Shared keeps the wire mirrors, a test pins them — the existing
  `DeviceAccessRefusal.causeCode` ↔ `DeviceAccessRefusalCause` pattern. The one genuinely
  two-sided thing, the failed-range codec, lives in Shared as a **single** implementation, because
  the helper encodes and the app decodes and neither can see Core's types on both sides.

### The increment plan

| | | GUI step | writes to a drive |
|---|---|---|---|
| **1** | Vocabulary + wire codec; nothing calls it yet | no | no |
| **2** | The helper honours the mode; FR-FAIL-2/3 proven in simulation with injected faults | no | no |
| **3** | Protocol **v9** — mode in, ranges + counters + final figures out; three tools updated | no | no |
| **4** | Report model + Markdown renderer, pure and app-side | no | no |
| **5** | Report `Window`, export, mode picker, wiring, `os_log` | likely no | no |
| **6** | Three clean builds; hardware gate | no | **yes** |

> **Increment 3 owes one thing this plan did not originally contain, added after increment 2.**
> The cycle's reply must also **name the failure mode the run actually used**. `RunCoordinator` is
> not in the test target, so "the deciding observer really is installed in the shipped run path"
> is otherwise a code-level inference — and on a healthy drive there is no failure to not-stop on,
> so nothing would ever reveal it. Echoing the mode back is the only evidence available without a
> bad drive, and it costs one integer on a reply that is being widened anyway. See increment 2's
> "A hole found by asking what the tests could not see".

**The injected-fault gate items can only be discharged in simulation.** A healthy scratch device
produces no failures and this project does not manufacture one on real hardware.
`InMemoryBlockDevice` already carries `injectReadFault`, `injectWriteFault` and
`injectSilentCorruption`. The hardware half of Step 10's gate is therefore small by construction:
a clean bounded run producing a report, and an export that opens in a Markdown viewer.

### Increment 1 — COMPLETE (2026-08-06)

The vocabulary and the codec, with nothing calling either. Deliberately inert: no helper, engine,
app or script path changed, so a defect introduced here cannot reach a drive.

**Core (`Core/RetentionRun.swift`) — `FailureMode`,** placed next to `FailureDisposition`, which
Step 8 left with the comment "the **modes** themselves (FR-FAIL-1/2/3) are Step 10's". Two cases
and **no unrecognised member**: a run that does not know its mode must not start, and the place
that refuses is the trust boundary. An enum with an unknown case lets one travel inward and get
resolved by whichever branch a `default:` happened to name first.

`disposition(for kind:)` takes the failure's kind rather than being a constant, and that is the
one design choice in this increment worth defending. **FR-FAIL-2 says stop on "any I/O failure";
FR-TEST-8 and FR-FAIL-6 make a verify mismatch a block-range failure.** A verify mismatch is not
an I/O failure in the ordinary sense — the read succeeded, the write succeeded, and the drive
returned different bytes — so a narrow reading of FR-FAIL-2 would let a mismatch *continue* in the
mode whose whole promise is that it stops. Taking the kind is what lets a test assert the
conjunction per kind instead of leaving it implicit in a constant.

**Shared (`Shared/TesterControl.swift`) — the wire side:** `FailureModeCode` (with an
`unrecognised` case, because an unknown code must be *representable in order to be refused*, and
**never defaulted** — resolving it to FR-FAIL-4's default would answer "stop on the first error"
with a run that writes to the whole drive), `FailedBlockRangeKind`, `FailedBlockRange` and
`FailedRangeCoding`.

Two properties of the codec are load-bearing:

- **A malformed record fails the whole decode.** Skipping it would produce a shorter list that
  still reads as complete — `FailureLog.isTruncated`'s hazard arriving by a different door, into
  the artefact that outlives the session. A report listing eleven bad ranges when the run found
  twelve looks exactly like a report that found eleven.
- **`FailedBlockRange.init` is failable**, refusing a zero-length range and one whose `endBlock`
  would overflow. `endBlock` is a trapping `+` and the report prints it, so a record of
  `18446744073709551615:2:1` from a mismatched helper would trap the process that formatted it.
  Same move as `LoadedChunk`: unrepresentable beats checked-at-every-use-site.

**Verified.** **584 tests, 0 failures, 67 suites** — up from 551/65; +33 tests, +2 suites, and the
number *moving* is the check that the files landed in a directory something compiles. Count taken
from the xcresult's top-level `totalTestCount`, not the console. Zero warnings from a **Release**
build and from a test compile with all four changed files `touch`ed first, so every one of them
was genuinely recompiled rather than skipped. `Shared/TesterControl.swift` still compiles
standalone with `tools/negative-client` and links — the path seven gate scripts depend on.

**Seven mutations, seven catches.** Each defect introduced deliberately and the two suites re-run:

| defect introduced | caught by |
|---|---|
| `decode` **skips** a bad record instead of failing the list | `aSingleBadRecordFailsTheWholeDecode`, + 5 more |
| the `endBlock` overflow guard is removed | `aRangeThatWouldOverflowIsRefused`, `anInvalidRangeIsRefusedOnDecodeToo` |
| `digits()` trusts `UInt64(_:)` instead of checking the accept-set | `onlyPlainAsciiDigitsAreAccepted` (it takes `+100`) |
| stop-on-first-error **continues** on a verify mismatch | `aVerifyMismatchStopsARunInStopOnFirstErrorMode`, `dispositionsAreCoveredForEveryModeAndKind` |
| an unknown wire code **defaults** to log-and-continue | `unknownWireCodeDoesNotBecomeAMode`, + 9 issues |
| the zero-length-range guard is removed | `aZeroLengthRangeIsRefused`, `anInvalidRangeIsRefusedOnDecodeToo` |
| an unknown **kind** code silently becomes a read error | `anUnknownKindCodeIsRefused`, `aSingleBadRecordFailsTheWholeDecode` |

The third of those is the one that would not have been caught by a round-trip suite: `UInt64("+100")`
returns `100`, so a codec that trusted the standard library would accept `+100:8:1` and report a
failure at block 100 that the helper never sent. It is why `digits()` spells its accept-set out
rather than delegating.

### Increment 2 — COMPLETE (2026-08-06) — the helper obeys the mode

**FR-FAIL-2 and FR-FAIL-3, proven against injected faults.** These are two of Step 10's gate
items and **they can only be discharged in simulation**: a healthy scratch drive produces no
failures and this project does not manufacture one on real hardware.

**What was built.** `Core/FailureModeObserver` — one method, one expression — plus
`Core/RunObservers.forRun(mode:watchedBy:)`, and `RunCoordinator.runCycle` gained a `failureMode`
parameter with no default value. `main.swift` passes `.standard` explicitly until increment 3 puts
the mode on the wire, so **nothing about the shipped behaviour changed in this increment**.

**Why the mode is not in `RunLogger`, which is where Step 8 said it would go.** Two reasons, and
the second one only became visible while writing the first.

1. **It would not be testable.** The test target compiles the fourteen `Core/` files and nothing
   else from the helper, by explicit membership exception in `project.pbxproj`. A decision that
   governs whether a run keeps writing to a failing drive must not live where no test can reach.
2. **`RunLogger.failureDetected` has bookkeeping in it** — a counter, a 64-failure limit and a
   once-only truncation notice — and a `return` on the wrong side of that `if` would answer
   "carry on" to a run that had been asked to stop. A safety decision does not belong inside a
   branch about how many log lines have been emitted.

`RunLogger` still holds the mode, but only to **name it** in the run-start line (BUILD-PLAN 10.6,
NFR-OBS-1). Both observers are constructed from one value on one line, so the mode that is logged
is necessarily the mode that ran.

#### A hole found by asking what the tests could not see, and closed rather than noted

The first version of this increment had `RunCoordinator` assemble the fan-out as an array literal:
`ObserverFanOut([RunLogger(…), FailureModeObserver(…), metrics])`. The suite was green.

**But `RunCoordinator` is not in the test target, and the other two observers both answer a
failure with the neutral `.continueRun`.** So the entire behaviour of stop-on-first-error rested on
one element of a hand-written array — and an edit that dropped it would have turned FR-FAIL-2 into
FR-FAIL-3 **on real hardware, with no test failing anywhere, and no way to notice**: the run would
complete, the report would be honest about a run that had ignored the mode it was given, and on a
healthy drive there would be no failure to not-stop on in the first place.

That is the same shape as *a sound mechanism behind a trigger that never fires*, and as Step 9's
`chunkCompleted` firing only on the paths somebody remembered.

Closed by moving the composition into Core as `RunObservers.forRun`, so the assembly is tested and
what remains outside the tested boundary is a single call. **Verified by mutation:** dropping the
deciding observer from the composition was *not* catchable before this change and is caught by
four tests after it.

**A second, independent check is owed and is now designed in.** Increment 3's reply will name the
mode the run actually used, so a hardware gate can confirm the mode reached the run path even on a
drive with nothing wrong with it — which is the only evidence available when there is no fault to
stop on. Recorded here because "the composition is right" is otherwise a code-level inference.

**Verified.** **606 tests, 0 failures, 72 suites** — up from 584/67; +22 tests, +5 suites, count
from the xcresult's `totalTestCount`. Zero warnings from a Release build and from a test compile
with all four changed files `touch`ed first. No caller of `runCycle` or `RunLogger` was left
behind (checked across `USBDriveTester/`, `tools/` and `scripts/`).

**Six mutations, six catches:**

| defect introduced | caught by |
|---|---|
| the deciding observer is **dropped from the composition** | `theModeSurvivesAListOfPurelyPassiveWatchers`, + 3 |
| `ObserverFanOut` short-circuits instead of stop-wins | `aPassiveObserverCannotOverrideAStop`, + 3 |
| `FailureModeObserver` ignores its mode | 14 tests |
| the engine ignores a stop after a failed **read** | `aReadFailureHaltsTheRunAtTheOffendingRange`, + 1 |
| the engine ignores a stop after a **verify mismatch** | `aVerifyMismatchHaltsTheRunAtTheOffendingRange`, `theTwoModesDivergeOnIdenticalHardware`, + 1 |
| log-and-continue stops on a failure | 10 tests |

**Two tests earn their place beyond the requirement text.**

- **`theTwoModesDivergeOnIdenticalHardware`** runs the same device with the same faults twice, once
  per mode, and requires the results to differ. Each mode's own suite could pass against a run that
  ignored the mode entirely; two runs required to diverge cannot.
- **`theRestOfTheDeviceIsActuallyRefreshed`** checks FR-FAIL-3's "continue refreshing the
  remainder" against the **device recorder**, not a chunk count. A run that walked to the end
  without writing anything would satisfy a count and fail the requirement — and refreshing is the
  half of this product that still works when fault detection does not (FR-TEST-9).

### Increment 3 — COMPLETE (2026-08-06) — protocol v9

**The mode goes in; the report's raw material comes back.** `runRetentionCycle` takes a
`failureModeCode` and its reply carries the failed ranges (FR-RPT-1), the total failing block
count, the final throughput and read-latency figures (FR-RPT-2/3), and **the mode the run actually
used**. A signature change on both sides, so the bump is mandatory rather than merely cheap.

**Reply width: nineteen positional values.** Consistent with the file's stated design — every
parameter an ObjC-representable primitive, so the interface needs no `NSSecureCoding` whitelist —
and with `runProgress`, which already carries eleven including three adjacent `UInt64` latencies.
`failureSummary` **stayed**, because two gate scripts parse it out of two tools.

#### What a refused run now replies, and why that was the whole point

Every refusal path answers with **no figures at all**: rates `-1`, latency sample count `0`, no
ranges, and a `failureModeUsedCode` of `0` because no run happened.

That is the hazard decision 1 was taken to remove, now closed by construction. `MetricsChannel`'s
slot is replaced when a run *starts*, which is after validation — so at the instant a refusal
returns, the slot still holds the **previous** run's numbers. A caller polling `runProgress` after
the reply would find them, correctly formatted and entirely plausible, and put another run's
measurements into an exported report. In the reply, they belong to this run or they do not exist.

`metrics-check.sh` now asserts exactly that on hardware, against three deliberately-refused runs
issued *after* four completed ones — so the stale figures are genuinely sitting there to be
wrongly reported.

#### The transposition problem, and the three things done about it

Nineteen positional values include **two adjacent `Double` rates and four adjacent `UInt64`
latency figures**. The reply is assembled in the helper's `main.swift` and consumed inside an XPC
reply closure — neither reachable by any unit test. A read rate arriving in the write slot
compiles, runs, and puts the wrong number under the wrong heading in the one artefact this product
persists.

1. **`RunCycleOutcome.init` takes labelled parameters**, so the untestable closure is a
   pass-through with each value's name beside it, one per line.
2. **Every test uses values distinguishable from one another.** A suite decoding `1.0` into
   `readBytesPerSecond` and `1.0` into `writeBytesPerSecond` passes with the two swapped — the
   same vacuity as comparing a buffer with itself. Three mutations (rates, latencies, NFR-PERF-3's
   fractions) confirm each pair is caught.
3. **`metrics-check.sh` compares the reply's six figures against a `runProgress` poll taken after
   the same run.** Two independent routes to one set of numbers, which is what makes a
   transposition in the helper's assembly visible on hardware. Plus `min <= max` and `min <= p99`,
   which catch a swap that somehow travelled identically down both routes.

#### Two smaller decisions worth their lines

- **`BlockFailureKind.wireCode`, rather than a `switch` at the reply site.** The mapping from
  Core's classification to the wire's had to happen somewhere the helper can see both. Written in
  `main.swift` it would have been **untestable**, and a transposition — a read error travelling as
  a write error — would compile and put a wrong classification in a report somebody may act on by
  discarding a drive. As a `wireCode` it is the project's existing pinned pattern.
- **`WireSentinel`.** From v9 there are *two* replies carrying rates and latencies, and both must
  read `-1` and a zero sample count the same way, or one drive would read one way live and another
  way in the exported report. Two copies of "`-1` means nil" is the kind of duplication that
  survives until somebody fixes one of them.

**And `failedRanges` is an optional array on purpose.** `[]` means the run found nothing; `nil`
means this build could not decode what the helper sent. Collapsing them would let a decode failure
render as a clean drive.

#### The documented gotcha, met in the wild

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` made the new Shared types main-actor-isolated, so
`RunCycleOutcome`'s `nonisolated` init could not call them — three warnings, no errors. Fixed by
marking `FailureModeCode`, `FailedBlockRangeKind`, `FailedBlockRange`, `FailedRangeCoding` and
`CacheBypassOutcome` `nonisolated`, exactly as BUILD-PLAN's "Working on this project" says to.
It surfaced only because the changed files were recompiled — which is the reason that rule is
written the way it is.

**Verified.** **628 tests, 0 failures, 74 suites** — up from 606/72; +22 tests, +2 suites, count
from the xcresult. Zero warnings from a **Release** build and a test compile with all seven changed
source files `touch`ed first. **All five standalone tools compile and link warning-free**
(`negative-client`, `mount-guard-client`, `metrics-probe`, `xpc-concurrency-probe`,
`media-digest`) — the path seven gate scripts depend on. Three gate scripts parse.

**Nine mutations, nine catches:**

| defect introduced | caught by |
|---|---|
| the two **throughput rates** are transposed | `theTwoThroughputRatesAreNotInterchangeable`, +1 |
| latency **min and max** are transposed | `theThreeLatencyFiguresAreNotInterchangeable`, +2 |
| NFR-PERF-3's **two fractions** are transposed | `theTwoPerformanceFractionsAreNotInterchangeable`, +1 |
| an undecodable range list becomes **empty** instead of `nil` | `anUndecodableListIsNilAndNotEmpty` |
| the `-1` rate sentinel is dropped | `unmeasuredRatesBecomeNilRatherThanNegativeNumbers`, +1 |
| latency gated on its **value** instead of the sample count | `latencyFiguresAreNilWithoutSamplesWhateverTheyContain`, +1 |
| an unrecognised mode code becomes runnable | `unknownWireCodeDoesNotBecomeAMode`, +1 |
| the protocol version is not bumped | `theProtocolVersionIsNine` |
| the dropped-range count is not floored at zero | `anInconsistentCountCannotProduceANegativeDropCount` |

#### Owed to the hardware gate (increment 6)

The installed helper at `/Applications` is **v8** and this app is now v9. The version handshake
will refuse it (NFR-MAINT-1) — which is the mechanism working — but the Release build must be
installed and the helper unregistered and re-registered before any hardware gate runs.

Three new hardware assertions are in place and **have not been run**: the mode echo, the
reply-versus-poll agreement, and the refused-run-carries-no-figures check. `metrics-check.sh`
writes to the scratch device, so that is increment 6 and needs asking first.

### Increment 4 — COMPLETE (2026-08-06) — the report and its Markdown

**`Report/RunReport.swift`** (the model) and **`Report/RunReportMarkdown.swift`** (the renderer),
both app-side, both pure, both new files under the app target — so no Xcode step. The renderer is
a pure function of a report: no file system, no save panel, no clock of its own. Increment 5 owns
where the string goes, and that separation is what makes every claim below assertable.

#### Four decisions in the model

1. **A refused call produces no report at all** — `init?` returns `nil`. FR-FAIL-5 requires every
   *run* to end with a report; a request the helper refused is not a run, and writing a file for
   one would put a description of a test that never touched the hardware on somebody's disk. The
   discriminator is **the mode echo** — the helper stating what it did — rather than the chunk
   count, which would be the app inferring it from an implementation detail.
2. **Four outcomes, not the five BUILD-PLAN lists.** Stopped-by-user is Step 11's and device loss
   is Step 12's, by the 2026-08-06 decision. The fourth, `incomplete`, is **not** an untriggerable
   mechanism: it is how the report refuses to classify a reply it cannot rule out — the helper is
   a separately installed artefact, and a run that did not cover its range while recording no
   failure is neither "completed" nor "stopped on error". Naming it costs one case and keeps a
   wrong claim out of a persisted file.
3. **`failedRanges` is an optional array.** `[]` means the run found nothing; `nil` means the list
   could not be read. The renderer prints a warning for `nil` that says in terms *"do not read
   this section as no failures"*.
4. **`ioSizesUsed` is a list**, per Step 9's inherited note. One element today; Step 11's mid-run
   size change makes it several, and the renderer already emits the bimodality caveat when it is.

#### A defect found by rendering, in the requirement that matters most

The suite was green and the document was correctly ordered — outcome, then the FR-TEST-9
qualification, then everything else. Then the four sample renders were read, and the qualified one
led with:

> **Completed — no currently-unreadable blocks were found**

…in bold, with the paragraph saying that finding may be worthless directly underneath it.

Every word true. Correct order. **And wrong**, because FR-TEST-9 does not ask for the
qualification to be *present* — it asks for it to be **prominent enough that it cannot be read
past**, and a reader skimming a report for its verdict takes the bold line. A qualification one
paragraph below the conclusion it undermines is a footnote to a conclusion already drawn.

Fixed by moving it into the headline itself: *"Completed — no currently-unreadable blocks were
found — but this result is NOT VERIFIED (see below)"*. It applies to **every** outcome and not
only the clean one, because a cached read cannot invent a mismatch but it can hide one — so a
failure count under an unverified bypass is a floor, not a count.

**Found by looking at the artefact, exactly as three defects in Step 9 were.** No assertion I had
written would have caught it; the document satisfied every one of them.

#### Verified

**686 tests, 0 failures, 82 suites** — up from 628/74; +58 tests, +8 suites, from the xcresult.
Zero warnings from a Release build and a test compile with the three new/changed files `touch`ed.
Four sample reports rendered and read: clean, with-failures, stopped-on-error, and
cache-qualified.

**Fourteen mutations, fourteen catches.** Each is a way for a plausible, correctly-formatted file
to be wrong:

| defect introduced | caught by |
|---|---|
| an undecodable failure list renders as "no failures" | `anUndecodableListIsNeverPrintedAsNoFailures` |
| the truncation notice is dropped | `aTruncatedListSaysItIsTruncated` |
| the FR-TEST-9 statement prints **only when it failed** | `everyVerdictProducesAStatement` |
| the qualification drops out of the headline | `aQualifiedCleanRunSaysSoInTheHeadlineItself` |
| an unrecognised cache verdict reads as verified | 3 tests |
| a clean outcome is worded "the drive is healthy" | `aCleanOutcomeIsNeverWordedAsAHealthCertificate`, +1 |
| a refused call produces a report anyway | `aRefusedCallProducesNoReport`, +1 |
| a run that stopped is reported as completed | 3 tests |
| the file name is keyed on the **BSD name** | `theSuggestedFileNameIsKeyedOnTheSerialAndNotTheBsdName`, +1 |
| the no-serial caveat is dropped | `aDriveWithNoSerialIsLabelledAsUnidentifiable` |
| the bounded-range caveat is dropped (a partial run reads as whole-drive) | `aPartialRangeIsNotAllowedToReadAsAWholeDrivePass` |
| p99 prints as a point rather than an upper bound | `theP99IsPrintedAsAnUpperBoundAndNeverAsAPoint` |
| the multi-I/O-size caveat is dropped | `severalSizesAreNamedAndTheDistributionIsFlaggedAsSpanningThem` |
| the throughput not-graded statement is dropped | `throughputIsReportedAndExplicitlyNotGraded` |

**Three of my own test expectations were wrong and the code was right** — `MetricsFormatting`
renders `517 MB/s` with no decimal, a zero rate falls through to `kB/s`, and the fixture timestamp
is 2026-07-25 rather than the date I assumed. Corrected in the tests.

#### What the report will not say, and where each refusal is pinned

- **No health verdict.** "Completed clean" reads as *no currently-unreadable blocks were found*.
  The honest framing (FR-WARN-3/4, NFR-USE-6) is echoed **into the document**, because the report
  is the copy that gets forwarded and re-read detached from whatever was on screen.
- **No grade on throughput** (D9). The document says so in terms, and names what a reader would
  need in order to judge it — a bare pair of numbers in a file invites the reader to supply the
  missing verdict themselves.
- **No p99 as a point.**
- **Identity is the serial.** The BSD name appears in one row, labelled *"a locator, not an
  identity; it may name a different drive after a replug or a reboot"*. The **export file name is
  keyed on the serial** too: a folder of `disk4-…` reports would be a folder of files that no
  longer say which drive each is about.
- **A bounded run is not a whole-drive pass**, and says so. Whole-device runs arrive with Step 11.

### Increment 5 — COMPLETE (2026-08-06) — the report window, the export, the mode picker

**A third `Window` scene** (`WindowID.report`, ⇧⌘R), opened when a run ends and reachable from
the Window menu afterwards. `Report/RunReportView.swift` holds the view, the export and the
app-side `os_log` points (BUILD-PLAN 10.6). The **mode picker** sits beside the bounded-cycle
button; Step 11 moves it to the real pre-run controls with Start (FR-CTRL-7).

**`AppModel`'s device fields collapsed into one record.** `heldDeviceName` + `heldDeviceSerial`
became `heldDevice: ReportedDevice?`, because the report needs the model name, capacity and block
size too — and four parallel optionals that must be set and cleared together are four things that
can disagree. The old names survive as computed accessors, so nothing that only wanted the BSD
name had to change. Identity is captured **at claim time**: the enumeration that produced it can
be gone by the time a report is written.

#### Two defects found by rendering, neither catchable by any assertion

**1. The report displayed raw Markdown source.** The first version showed
`RunReportMarkdown.render(report)` through `AttributedString(markdown:)`, reasoning that one
source cannot disagree with itself. `render-ui.sh report-qualified` showed what that actually
looks like: `## Outcome` and `| Model | Samsung Portable SSD T5 |` on screen, pipes and hashes
included. `.inlineOnlyPreservingWhitespace` interprets bold and code spans and leaves **every
block-level construct** — headings, tables, block quotes — literal, and SwiftUI's `Text` cannot
render presentation intents even with `.full`. The "one source" was a source *listing*, shown to
a user in place of a report.

Rebuilt as a native layout: real section headings, a `Grid` for each table, a real bad-block
table. The Markdown is now export-only. **What must not fork is the wording, and it does not** —
every string comes from `RunReport`, where it is tested.

**2. Then the model's prose showed its asterisks.** `**Cache bypass verified.**` rendered
literally, because those strings carry inline Markdown for the exported file and a plain
`Text(String)` prints it. Fixed with `Text(LocalizedStringKey:)`, the one `Text` initialiser that
parses inline Markdown — which is all these strings contain.

**Every test passed against both versions.** This is the fourth and fifth defect this project has
found by looking at a render, and the reason the report is a `Window` rather than a sheet: a sheet
gets its own window and `render-ui.sh` cannot capture it, so every check of this surface would
have needed a person, and neither of these would have been found today.

#### And one found by a test, which was really a design defect

`RunReportExport.write` presented an `NSAlert` on failure. The test for the failure path **hung
the test runner on a modal dialog** — which is the shape of the problem rather than an
inconvenience: a function that writes a file *and* puts a window on screen cannot be exercised
anywhere a window would be wrong, and the failure path is precisely the one worth exercising.

`write` now throws and never presents; `presentSavePanel` catches and alerts. An export that
failed silently would leave a user believing they had a file — and since each run stands alone,
that file is the only copy that was ever going to exist.

#### Renders added, and what each is for

`report`, `report-failures`, `report-stopped`, `report-qualified`, `report-unidentified`,
`report-empty`, and `diagnostics-stop-on-error`. Every one was looked at. Two carry states no
drive on this machine can produce: `report-unidentified` (a drive reporting no usable serial,
where the report must admit it cannot identify what it tested) and `report-qualified` (FR-TEST-9
not verified, where the qualification must be **in the headline**).

`diagnostics-stop-on-error` exists because the explanatory line under the picker changes with the
selection — *"Everything past it is left untested — which is not the same as passed"* — and that
line is the whole reason the control is a radio group with prose rather than a checkbox. It was
added after a comment in `ui-probe` referred to a render that did not exist.

#### Verified

**695 tests, 0 failures, 83 suites** — up from 686/82. Zero warnings from a Release build and a
test compile with all six changed files `touch`ed. Seven renders inspected.

**Five mutations, five catches:** a failed write swallowed; the export writing a summary instead
of the report; a lossy encoding (which loses the `≤` that makes p99 a bound); the file name losing
its extension; an awkward serial not made file-name-safe.

**`MemberImportVisibility` again**, exactly as BUILD-PLAN describes: `UTType.conforms(to:)` needed
`import UniformTypeIdentifiers` directly in the test file, not transitively.

#### Still owed

The `Window` menu now has a third automatic entry beside the known cosmetic duplicate. Not chased
— `.commandsRemoved()` was measured in Step 9 to take the main window's way back with it.

### Increment 6 — IN PROGRESS (2026-08-06) — clean builds, hardware gate

**Three clean builds: zero warnings, 695 tests, 0 failures, 83 suites.** `build.sh Debug`,
`build.sh Release`, `test.sh`, DerivedData wiped before each. Release installed to
`/Applications` and verified newer than every source; the user unregistered and re-registered the
helper, and **Check protocol version reported v9**.

| gate | result |
|---|---|
| `xpc-concurrency-check.sh` | **0 failures.** Confirms the live daemon at **v9**. Same-connection delivery serialized, second connection answered in 5.2 ms — unchanged from Step 9. |
| `metrics-check.sh` | **0 failures**, all four I/O sizes. |
| `retention-cycle-check.sh` | **FAILED on the first attempt — device loss, not a code defect** (see below). **PASSED on re-run after a cable and port change: 15 checks, 0 failures.** |

#### retention-cycle-check, re-run — PASSED

After the user re-seated the cable at both ends and moved it to a different port. Pre-flight on
the new port: **10 Gb/s** (no link downgrade), correct serial and block count, `fill.bin` intact
at 930 GB. Fresh random placement — blocks **585,670,656**, well away from the 392,503,296 that
failed, so a repeat at the same *block address* and a repeat at the same *depth into the
fingerprint pass* would have been distinguishable.

**15 checks, 0 failures**, and the item the gate actually owed is the last of them:

- **every one of the 932 whole-device window fingerprints unchanged (NFR-REL-1)** — the
  non-destructiveness regression, which is the only thing simulation cannot discharge and the
  reason the gate had to be re-run rather than argued away;
- 256 chunks, **255 full + 1 short** (FR-TEST-5);
- no failed block ranges; FR-TEST-9's verdict survived the run (`bypassed`);
- fastest read 494,608,871 B/s — transport-plausible, not RAM-plausible;
- buffers 2 × the I/O size (NFR-PERF-1);
- and on the wire, **`FAILURE_MODE_USED=2`** again, with **`FAILED_RANGES_ENCODED=`** empty and
  `FAILED_BLOCKS=0` — protocol v9's failed-range encoding exercised on hardware in its clean-run
  case, which is the case the codec's `decode("") == []` path serves.

**One clean run is not proof the drop is fixed.** It is the evidence available: the same gate, on
the same drive, at a new placement, on a different port, with no `ENXIO`. If it recurs, the user
has a spare Samsung drive available, which would discriminate between the T5/its enclosure,
this Mac's USB, and this tool's access pattern — a more useful role than replacing the
characterised scratch device.

> **Corrected 2026-08-09.** This paragraph called it "a second 1 TB Samsung drive" and quoted the
> cost of promoting it to a gate target as "~1 TB of `/dev/urandom`". Both were wrong. It is a
> **Samsung PSSD T5 EVO, 4 TB**, serial **`00000S7CLNJ0WC02266P`**, 7,814,037,168 × 512 B — a
> different model line at four times the capacity, so the refill cost is **~4 TB**. Its serial
> and block count are now in `scripts/lib/device-identity.sh` and it has a row in BUILD-PLAN's
> hardware table, so what a gate target still needs is the fill data. It has since acquired a
> second role — the multi-volume unmount fixture — recorded with the table row.
>
> Worth reading as an instance of this file's own lesson rather than as a typo. The drive was
> identified here by **model and capacity from memory**, which is an assigned identifier wearing
> different clothes: nothing announced that it was wrong, and the error propagated straight into
> a cost estimate for a future step. The serial and the block count are the intrinsic facts, and
> `resolve_target` cross-checks the second against the first for exactly this reason.

#### metrics-check: the three v9 assertions, on hardware

All new, all passing, at every I/O size:

- **`the run used failure mode 2 (log and continue), as requested`.** This is the check increment
  2 designed the mode echo for. `RunCoordinator` is not in the test target and the drive is
  healthy, so there is no failure for the mode to act on — the echo is the *only* available
  evidence that the deciding observer is installed in the shipped run path.
- **All five compared figures agree exactly across the reply and the `runProgress` poll** — e.g.
  read throughput `489811282.3250407` identical on both routes. Two independent paths to one set
  of numbers is what makes a transposition in the helper's nineteen-value reply visible, and it is
  the only check that reaches an assembly no unit test can.
- **All three refused runs reported no mode and no figures**, issued *after* four completed runs
  so the previous run's numbers were genuinely sitting in `MetricsChannel`'s slot to be
  misattributed. This is the hazard that drove protocol v9, shown closed on hardware.
- And **an unrecognised failure-mode code was refused** (FR-FAIL-1) — shown refusing, not shown
  not-refusing.

NFR-PERF-3 held: host overhead 1.5–1.8% across the sweep, µs/MiB varying 1.12× against µs/chunk
7.71× — host cost still follows bytes moved, as Step 9 measured.

#### retention-cycle-check: a real device loss, mid-gate

**The gate failed and Step 10's gate is NOT discharged.** What happened, from the log rather than
from reasoning:

`errno 6` — **`ENXIO`, "Device not configured"** — on every read from ~63.8 GB into the pre-run
fingerprint onward, **including offset 0**. A bad block gives `EIO` on that block; `ENXIO` on
offset 0 of a descriptor that had been working means the descriptor is dead. The drive
re-enumerated about two seconds later and is healthy: correct serial, correct block count,
**10 Gb/s** link, volume mounted.

**Not attributable to Step 10.** `RetentionTestEngine.swift` and the entire I/O path are
byte-identical to Step 9 (`git diff` against `c6ec234`), and `metrics-check.sh` had passed minutes
earlier with four full read→write→verify cycles — ~12 GiB of I/O. No USB-level disconnect message
is visible at default log level, and today's only mount/unmount events are the gate scripts' own,
so **the root cause is not established and is deliberately not guessed at**. The drive had taken
sustained load immediately before, which is suggestive and nothing more.

**What Step 10's machinery did, unrehearsed, under a real fault** — evidence worth having, and
*not* a substitute for the gate:

- log-and-continue recorded every failing chunk and **completed all 256** rather than freezing —
  which is the defect Step 9 found in `chunkCompleted`, not recurring;
- `FailureLog` coalesced 256 failing chunks into **one range**, on real data rather than a fixture;
- `FAILURE_MODE_USED=2` survived a device that vanished;
- and the figures came back **`-1` with a sample count of `0`, not `0 MB/s`**. Nothing was
  measured, so nothing was claimed.

**The finding that matters more than the gate, and it belongs to Step 12.** The reply was
*"Cycle completed: 256 of 256 chunks; 2095104 block(s) in 1 range(s): read error"*. A report built
from that would say **"Completed with failures"** and tabulate one range of **2,095,104 bad
blocks**. The drive does not have two million bad blocks — it went away. **That is a false
accusation about somebody's hardware, in a file that outlives the session**, and it is the same
class of error `RunAbort` exists to prevent when the fault is ours. Recorded as an inherited note
on Step 12 with this log as the real instance.

#### Two stale instructions the run exposed, both fixed

Both from the 2026-08-06 serial migration, which changed conventions but not the messages that
print them — the project's own "a corrective instruction pointing where the control is not is
worse than none", twice:

- `retention-cycle-check.sh` printed **`Re-run this exact placement with: $0 disk8 392503296`**,
  and its own parser rejects any non-numeric argument. Following the script's advice produced
  `unrecognised argument 'disk8'`.
- `xpc-concurrency-check.sh`'s verdict still read **"D1 resolves to PUSH … Step 9 must build the
  reverse channel"** — the *pre-flight's* reading, written before the second-connection number
  existed. Step 9 measured that number and went the other way. A reader following it would have
  built a channel the product does not have.

#### Closing the MAIN window now quits the app — two rounds, both settled by observation

**This took two goes, and the second one is the lesson.**

Reported as a regression during this increment; it is not one. `Quit/` and `ContentView.swift` are
byte-identical to Step 9's commit, `QuitPolicy` has returned `.allowClose` for idle-and-no-run
since Step 9 with `QuitPolicyTests:102` pinning it, and `USBDriveTesterApp.swift` documented the
behaviour as intended. What it *was*, was **never observed** — Step 9 recorded the whole window
layer as measured-on-a-probe-but-not-seen-in-the-product, and this is the first look.

Seen, it is wrong: **the helper's claim outlives the window.** Until Step 11 gives the run
ownership of the claim, a device acquired earlier stays acquired, so the app could sit invisibly
with somebody's drive unmounted and no UI to release it from.

**Round one — `applicationShouldTerminateAfterLastWindowClosed = true`.** Built, tested, mutation-
checked, installed. The user then exercised both cases, and the second is the one that mattered:
closing the main window with the diagnostics window still open left the app running.

> *"I don't think that this is an intuitive user experience. I think closing the main window
> should always try to terminate the app."* — user, 2026-08-06

**And that is right.** The flag fires only when **no window at all** is left, so the behaviour was
keyed on AppKit's window count rather than on anything the user did: closing the main window quit
the app, or did not, depending on whether a panel they had opened earlier happened to still be up.
The rule was an implementation detail leaking into behaviour.

**Round two — the main window's close IS the quit request.** A fourth case,
`WindowCloseDisposition.allowCloseAndQuit`, in `QuitPolicy` where the truth table is tested. The
diagnostics and report windows are what they look like: panels belonging to the app, which go when
it goes, and closing one of them does nothing.

Three details worth the space:

- **"Try to terminate", precisely.** The guard *requests* a termination — `NSApp.terminate(_:)`,
  which lands in `applicationShouldTerminate` and meets the same guard ⌘Q does — rather than
  performing one. `QuitPolicy` only produces this case from idle, so it will be allowed today; but
  routing through rather than around means closing a window can never abandon a run even if that
  table is later changed. `aRunBeginningBetweenTheCloseAndTheQuitIsStillProtected` asserts it.
- **After the close, not during it.** `windowShouldClose` is asked *whether* the window may close.
  Terminating from inside the answer would have AppKit tearing the app down through a delegate
  call it is still waiting on, so the request goes out one run-loop turn later.
- **`.allowClose` — close but stay — now survives for exactly one state**: `.terminating`, where
  AppKit is closing every window on its way out and a second termination request would be wrong.
  `plainAllowCloseIsReachableOnlyWhileTerminating` pins that it is unreachable everywhere else.

The last-window flag stays, **re-documented as a backstop** rather than the rule: one declarative
line that catches ending up with no UI by some route nobody enumerated, failing in the safe
direction.

**701 tests. Six mutations, six catches**, including the two that carry the safety property —
closing during a run quitting silently instead of asking, and the wind-down letting its window go.

**Both rounds were settled by looking, not by reasoning.** Round one's design was sound, tested and
mutation-verified, and wrong about what a person would expect; nothing but running it would have
shown that. Same shape as the two render defects in increment 5 — and Step 9 had recorded this
whole area as *"measured in isolation, not yet observed in the product"* precisely because the
distinction was already known to matter.

#### Two more found in real use, after the gates passed (2026-08-06)

Both reported by the user from actually using the app, not from reading it.

**1. A refused unmount left no way back.** A multi-volume drive, "Unmount All" pressed with the
*wrong drive selected*, one volume refused — and the control went on reading "Unmount All",
offering to repeat what had just failed, while volumes that had already gone stayed gone.

> *"I very much wanted an easy way to restore the mounted volumes."*

`DADiskUnmount` with `kDADiskUnmountOptionWhole` dissents as a unit, but volumes it already
unmounted **stay unmounted** — so a refusal leaves a partially mounted drive and no offered route
back.

**Two attempts, and the second is the user's and is better.**

*First attempt — flip the label.* `MountControlPolicy` took an "an unmount was refused" input and
answered "Mount All", putting the way back one press away. Built, tested, mutation-checked. The
one thing it got right is worth keeping in mind for anyone tempted by the shorter version: reading
the direction off *"fewer volumes mounted than the drive has"* would flip on the **normal resting
state of a GPT drive** — the scratch device is EFI + one exFAT volume and macOS leaves EFI
unmounted — so that rule would have it reading "Mount All" at rest, with no way to unmount without
mounting first. Mount state cannot distinguish *"partial because that is how it came"* from
*"partial because we just failed"*.

**It did not work in the product**, reported by the user; and rather than debug a mechanism about
to be replaced, the user specified a better one:

> *"if any volume unmount operation fails for any reason, just post an error message with the
> error code (stated in english if available) and remount any volumes that did unmount
> successfully. This will restore everything to the previous state before the unmounts were
> attempted."*

*Second attempt — undo the unmount.* The operation now either fully succeeds or **puts the drive
back as it found it**. The elegance is that it needs **no new control state at all**: with the
drive restored, `mountedVolumeCount` is what it was, so the existing label rule is correct again
and the first attempt's input was deleted. Which is precisely why it "integrates seamlessly when
the buttons go away" — the rollback is a behaviour, not a control.

Two things the message does deliberately. It **keeps the original DiskArbitration reason**
(`DAStatus.explain` already renders the code in English and often names the blocking process), and
it says *"asked to remount … the list above shows what is mounted now"* rather than *"restored"* —
the mount is asynchronous and the device list is what actually shows the result. Claiming an
observed restoration would be the same error as a report saying "0 bad blocks" without saying
whether it could tell. The rollback-also-failed case reads unmistakably differently and points at
Disk Utility.

**A mutation found the same hole increment 2 found.** Written inline in `DeviceListView`, deleting
the rollback outright — the entire point of the change — was **caught by nothing**, because no test
can reach a closure inside a SwiftUI view's action. Moved to `VolumeMounter.restoringUnmount` with
both operations injected, the same shape `QuitSequence` uses and for the same reason. Now caught,
along with two inverses that matter as much: rolling back a **successful** unmount (undoing what
the user asked for) and reporting the rollback as a success.

*Third attempt — and the real defect, which both earlier ones were built on top of.* The rollback
did not fire either. The user reported that the app believed the unmount had succeeded while the
device pane beside it correctly showed a volume still mounted. **The unified log settled it in one
query**, as it has every other time reasoning and the logs have disagreed in this project:

```
11:11:47  unmount succeeded on disk6: Unmounted every volume on disk6: 1TB_Samsung.
```

`1TB_Samsung` on `disk6` is **the volume this repository lives on**, mounted and in active use at
that moment and for hours after. `disk4` — the Time Machine drive — produced the same line.

**`DADiskUnmount` can call back with no dissenter while a volume is still mounted.** A `nil`
dissenter means *nothing refused the request*, not *the volumes are unmounted*. Both earlier
attempts keyed on `isSuccess` and were therefore **inert by construction** — the label could not
flip and the rollback could not fire, because the app believed it had succeeded. Two features
built, tested and mutation-verified on a signal that does not mean what its name says.

**The postcondition is now checked rather than inferred**: the mount table is read back through
`DeviceDiscovery.refresh()` — synchronous, and re-running the enumerator's own IOKit subtree walk,
which is what maps an APFS volume to its physical disk (a BSD-name prefix match would not; that is
why `1TB_Samsung` on `disk6` is mounted from a synthesised disk at all). A reported success with
volumes remaining is a **failure**, and rolls back.

The message for that case quotes no cause, because there is none to quote — nothing refused. It
says what was asked, what was observed, names the volumes, and offers the likeliest explanation
as an explanation rather than a finding.

**This is `fcntl(F_NOCACHE)` returning 0 on `/dev/null` again** — the measurement that created
FR-TEST-9. *An API accepting a request is not the request having had its intended effect*, and the
only way to know is to check the thing the request was supposed to change. It is the same lesson
this project has now paid for in four places: the cache-bypass flag, the empty `ioreg` query, the
probe measuring itself, and here.

*Fourth attempt — two more defects, both consequences of the third.* The user reported the EFI
partition being mounted by the rollback, and no error message appearing. The log showed something
neither symptom named: **every** unmount was being rolled back, including `disk8`'s, which had
succeeded and was undone three seconds later.

Both symptoms were one bug. **The mount table lags DiskArbitration's callback**, so reading it
immediately still listed the volume; the check called a successful unmount a failure; and the
rollback — a *whole-disk* mount — then mounted every mountable volume, EFI included.

Two changes, and each fixes a class rather than a case:

- **Restore exactly what went.** `mountedBefore` minus what is still mounted, remounted by device
  node. EFI cannot appear because it was never in `mountedBefore` — it was not mounted. This
  required `DiscoveredDevice.mountedVolumeBSDNames`, from the same IOKit subtree walk that
  produces the names, because **a name cannot be mounted and a BSD name can**, and an APFS volume's
  node is not derivable from the physical disk by prefix.
- **Look again before concluding.** The table is re-read up to twelve times at 150 ms. A drive that
  really unmounted clears on an early pass and costs nothing; one that did not spends the budget.

**And a third defect, found by asking why the message was missing rather than by observing it.**
The postcondition check called `discovery.refresh()` — which rebuilds the device list under the
`List`, and a selection binding that round-trips fires `.onChange(of: selectedDeviceID)`, whose
handler does `lastOutcome = nil`. The settle would have run that up to twelve times per unmount,
erasing the very message the path exists to produce. Removed entirely: `before` already holds this
device's volume nodes, so the attribution question is answered and `getfsstat` is the whole
remaining question. Cheaper, and it touches nothing the UI is rendering.

**Whether that was the cause of the missing message is not established** — it is a mechanism that
would produce exactly the symptom, found by reading, and the code that could do it is gone.

**722 tests, 86 suites.** Ten mutations across the two rounds, nine caught: trusting the dissenter
again (fails three tests); reading the table once instead of retrying; the whole-disk restore
returning; reporting a genuine success as failure; and the message defects.

**One is not caught and is recorded as such.** Swapping `kDADiskMountOptionDefault` for `…Whole`
inside `mountOne` — which would bring EFI back — is invisible to the suite, because that call needs
DiskArbitration and a real drive. What *is* tested is the decision above it, which is where the
volume set is determined. The line rests on the API contract and on observation, the same standing
as `TableSelectionPolicy` depending on `List` being `NSTableView`-backed.

#### What three rounds on one control actually cost, and what it bought

Four attempts, three of them wrong, on a control **Step 11 deletes**. The failures were not
independent — each was hidden by the one beneath it:

1. Flip the label ← inert, because
2. `DADiskUnmount` reports success while a volume is still mounted ← so the rollback never fired
3. Reading the table immediately misjudges a good unmount ← so every unmount rolled back
4. A whole-disk restore mounts EFI ← so the rollback did visible damage

**Every layer was tested and mutation-verified before the layer beneath it was known to be
false.** That is the sharpest form of this project's oldest lesson: a green suite over a wrong
premise is exactly as green as one over a right premise, and the only thing that distinguished
them was running the app and reading the log.

What it bought is not the control. It is `mountedVolumeBSDNames`, the restore-exactly-what-went
rule, and the finding that the unmount's success signal cannot be believed — all of which
**Step 11's Start needs**, where the same sequence runs with no button to press and no user
watching. Recorded there.

**And the durable half belongs to Step 11**, which deletes this control: a Start that unmounts
volume A, fails on volume B and aborts strands the user in exactly this position with no manual
control left at all. Recorded there as a requirement on the abort path.

**2. The "Last run" pane is redundant now the report window exists.**

> *"I see no reason to retain the Last Run pane since all the information is redundant and the
> separate window & file exporting is far more valuable."*

Right, with one boundary that had to be stated rather than assumed: **FR-METR-2/4/5/6 are
mandatory and require throughput, latency, progress and ETA to be displayed *during* a run**, and
no report exists while one is under way. So the live half stays and the retained half goes —
which is exactly what "redundant with the report" can mean, since the report only exists after a
run.

`runProgress` keeps returning a finished run's figures until the next run replaces them, so
`isAvailable` alone had the panel displaying a completed run indefinitely. The condition is now
`isAvailable && isRunning`, and the idle placeholder says **where the result went** — a
placeholder that only said "nothing is under way" would read as the run's result having been lost.

The condition was **extracted to `RunMetricsView.showsMeasurements`** rather than left as an `if`
inside a `body`. Two inputs, four rows, every one a state a user reaches — and this project's
record with view conditions verified by reading them is poor: three SwiftUI modifiers in Step 9
compiled, rendered and did nothing. A render proves it once; a test keeps it proved. A new
`metrics-finished` render covers the combination the change turns on, which no existing view
exercised.

**716 tests, 86 suites.** Nine mutations across the two changes, all caught: the rollback deleted;
a *successful* unmount rolled back; the rollback reported as success; the original reason dropped
from the message; a failed rollback reading like a successful one; a successful rollback claiming
an observed restoration; and — on the panel — dropping either input from its condition.

#### The final install, and why the gates still hold for it

The window-close change is app-target only, but installing it **rebuilds the embedded helper
binary too**, so "the gates still apply" is a claim about the helper's *source* being unchanged.
Made checkable rather than asserted: the 20 files that compile into the helper — its own target
plus `Shared/TesterControl.swift` — were hashed **before** the gate ran and again before the
install.

```
737e6972bfdec1c5c1901a27bd5a00da2fed413166c909fc6639666c38e8907e   (identical)
```

So the installed helper is a rebuild of exactly the code the three gates passed against. The
installed binary was then verified newer than every source, as in Step 9.

**The hash recipe, recorded 2026-08-09 because it was not.** The figure above was quoted without
saying how to reproduce it, which makes it an assertion rather than a check — a hash nobody can
re-derive is worth exactly as much as a claim. It is:

```
{ find USBDriveTester/com.arc3solutions.USBDriveTester.Helper -name '*.swift'; \
  echo "USBDriveTester/USBDriveTester/Shared/TesterControl.swift"; } \
  | sort | xargs shasum -a 256 | shasum -a 256
```

Twenty files: the helper target's nineteen plus `Shared/TesterControl.swift`. Note it hashes the
**per-file digest list**, so the file *names* are part of the input — a renamed or added file
changes the result even if no byte of code did, which is what is wanted. Re-derived 2026-08-09
and still `737e6972…`, so all post-gate work remains app-target only.

#### Step 10 — the unmount rollback, verified (2026-08-09)

The one thing Step 10 left unverified. The procedure is written here rather than in a scratch note
because **Step 11 needs it again**: its Start owns unmount → acquire → run and its abort path
reaches the identical partial-unmount state with no manual control at all.

**The scratch device cannot exercise this and that is not obvious.** The T5 has exactly one
mounted volume, so `mountedBefore` has one entry, the restore set `before − still mounted` is
always **empty**, `mount(volumeBSDNames:)` short-circuits on its `isEmpty` guard, and `mountOne`
is **never called**. A run on it passes while leaving the half the fix was written for untouched —
the same shape as increment 2's observer composition and Step 9's `chunkCompleted`: a mechanism
behind a trigger that never fires. The only other multi-volume drive on this machine is the live
Time Machine disk, hence a purpose-built fixture.

**The fixture** — `scripts/make-unmount-fixture.sh`, on the T5 EVO (serial
`00000S7CLNJ0WC02266P`). Confirmed through the app's own enumerator with
`render-ui.sh devices`, not by reading `diskutil`:

```
disk8 — Samsung PSSD T5 EVO
4.00 TB · S/N 00000S7CLNJ0WC02266P · Vol_ExFAT, Vol_APFS, Vol_HFS
```

| node | volume | why it is in the layout |
|---|---|---|
| `disk8s1` | EFI, **unmounted** | the trap. It is absent from `mountedBefore`, so it can only reach a restore via a whole-disk mount — the third attempt's defect. |
| `disk8s2` | `Vol_ExFAT` | a **direct partition**: `…Whole` on this node reaches *up* to `disk8` and takes EFI with it. |
| `disk9s1` | `Vol_APFS` | on a **synthesized** disk. Not derivable from `disk8` by prefix — the case `DiscoveredDevice.mountedVolumeBSDNames` exists for. |
| `disk8s4` | `Vol_HFS` | a second direct partition, so a restore set can hold more than one node and a "restore exactly what went" bug cannot hide behind a set of size one. |

**The three cases.** Only case 2 discriminates `kDADiskMountOptionDefault` from `…Whole`, which
is the line recorded at `mountOne` as covered by no test.

| # | setup | expected |
|---|---|---|
| 1 | nothing held open | plain success; **nothing remounted**, EFI stays down. The case the third attempt got wrong — it judged a good unmount failed and undid it 3 s later. |
| 2 | `cd /Volumes/Vol_APFS` held in Terminal | error naming `Vol_APFS`; `Vol_ExFAT` **and** `Vol_HFS` restored by node; **EFI does not appear**. `mountOne` runs twice on direct partitions, where `…Whole` would raise EFI. |
| 3 | `cd /Volumes/Vol_ExFAT` held in Terminal | error naming `Vol_ExFAT`; `Vol_APFS` restored — an APFS volume on a synthesized disk put back **by node**. |

**Two things to watch beyond pass/fail.** Whether the error message *appears and then vanishes*
rather than never appearing — those are different causes, and the removed `discovery.refresh()`
only explains the second. And roughly how long case 2 takes: the settle budget is 12 × 150 ms
≈ 1.8 s before it concludes, so a near-instant result means the settle loop is not running.

#### Case 1 FAILED, and the cause is a fifth layer beneath the other four

**`DADiskUnmount` with `kDADiskUnmountOptionWhole` does not unmount APFS volumes in containers on
the disk.** It unmounts the disk's **direct partitions only**, reports **success with no
dissenter**, and leaves the container's volumes mounted. From `diskarbitrationd`'s own log:

```
09:16:52.256  unmounted disk, id = /dev/disk8s2, success.        <- Vol_ExFAT, direct partition
09:16:52.462  unmounted disk, id = /dev/disk8s4, success.        <- Vol_HFS,   direct partition
09:16:52.465  USBDriveTester  unmount succeeded on disk8: … Vol_ExFAT, Vol_APFS, Vol_HFS.
              ── no line for /dev/disk9s1. Vol_APFS was never attempted. ──
09:16:54.197  USBDriveTester queued … disk mount, disk = /dev/disk8s2, options = 0x00000000
09:16:54.208  USBDriveTester queued … disk mount, disk = /dev/disk8s4, options = 0x00000000
```

**This is the true mechanism behind the 2026-08-06 note.** That entry records *"`DADiskUnmount`
can call back with no dissenter while a volume is still mounted"* and treats it as a property of
the success signal. True, but too broad to act on — and the narrower statement is the actionable
one. `1TB_Samsung` is an APFS volume on synthesized `disk7`; it was **never unmounted**, not
slowly unmounted. The fourth attempt's settle loop was therefore tuned against a symptom whose
cause was still unknown, which is why it waited 1.8 s for a state that could never arrive.

**Pre-existing, not Step 10's.** `git diff 8567e88 -- VolumeMounter.swift` shows Step 10 added
only the message helpers; `unmountAll`'s body and its whole-disk option are unchanged since
Step 6.

**And no gate could have caught it.** Every write gate targets the scratch T5, whose only volume
is exFAT — a direct partition. The one drive the apparatus is permitted to touch cannot exhibit
the bug. It took building a fixture with an APFS container on it to make the defect reachable at
all, which is the argument for the fixture existing.

#### What the failing case nevertheless proved

All three of the fourth attempt's own fixes are now **confirmed on hardware**, by the same log:

| property | evidence |
|---|---|
| the settle loop runs its budget | `52.465 → 54.197` = **1.732 s**, against 11 × 150 ms + 12 table reads |
| restore exactly what went | solicitations for `disk8s2` and `disk8s4` only — **none for `disk8s1`, EFI** |
| `mountOne` uses `kDADiskMountOptionDefault` | **`options = 0x00000000`** on the wire, per node |

That last row is the line recorded at `mountOne` as *"not covered by a test — a mutation swapping
it for `…Whole` is caught by nothing"*. It is still not covered by a test, but it now has an
observation from **outside the process**, which is better standing than an API-contract argument.
It took a failing case to obtain it.

#### The fix (user decision 2026-08-09: fix it in Step 10)

**Unmount is now per volume, by node**, from `DiscoveredDevice.mountedVolumeBSDNames` — a volume
that is mounted is by definition in the mount table, so it can always be enumerated and always
has a node. `VolumeMounter.unmountEach` holds the fan-out, static with its operation injected,
the same shape as `restoringUnmount` and `RunObservers.forRun` and for the same reason: written
inline it would need DiskArbitration and a real drive, which is exactly how the whole-disk unmount
survived three steps under a green suite.

**`mountAll` keeps `kDADiskMountOptionWhole`, and that asymmetry is not an inconsistency.** The
mount table cannot list the volumes that are *not* mounted, so "mount every mountable volume" has
nothing to enumerate. Unmount can always enumerate; Mount All never can. Stated at the top of the
file, because the old header's reasoning — *"letting `diskarbitrationd` resolve the relationship
is both less code and correct"* — is what produced the defect and had to be replaced rather than
amended.

**A better message falls out of it.** The whole-disk version named every volume on the drive
whatever had actually happened, so one busy volume told the user all three had failed and left
them guessing which to close. Per-volume dissenters name only the volumes that refused, each with
its own reason (NFR-USE-5).

**And the `os_log` gap that made this nearly undiagnosable is closed.** `mountOne` had its own
hand-rolled session/box/timeout with **no logging at all**, so the entire rollback path — the one
this control has now cost five attempts on — was invisible to the unified log. The 2026-08-09
failure could only be reconstructed because `diskarbitrationd` happens to log on our behalf.
`perform` now takes a BSD name instead of a `DiscoveredDevice`, and `mountOne`/`unmountOne` both
route through it, so they inherit the logging instead of duplicating the plumbing without it
(NFR-OBS-1).

**Verified. 731 tests, 0 failures, 87 suites** — up from 722/86; count from the xcresult's
`totalTestCount`. Zero source warnings from all three clean builds (`build.sh Debug`,
`build.sh Release`, `test.sh`, DerivedData wiped before each). **The helper source hash is
unchanged at `737e6972…`**, so the fix is app-target only and the three hardware gates still
apply. All five standalone tools still compile and link.

**Eight mutations, six caught, two not — and the two are recorded rather than glossed:**

| defect introduced | caught by |
|---|---|
| only volumes whose node prefixes the physical disk are attempted (**the defect itself**) | `everyMountedVolumeIsAttemptedByItsOwnNode`, +21 issues |
| a refusal reported as overall success | `severalRefusalsAreAllNamed`, +5 |
| short-circuits on the first refusal | `theCallerIsToldExactlyOnce`, `aRefusalTellsTheUserWhatToDo` |
| the refusal names every volume, not only those that refused | `onlyTheRefusingVolumeIsNamedAndItQuotesItsOwnReason`, +3 |
| an empty set claims an unmount happened | `nothingMountedSucceedsWithoutClaimingAnUnmountHappened` |
| completion fires once per volume | `theCallerIsToldExactlyOnce` |
| **`unmountOne` reverts to `…Whole`** | **NOT CAUGHT** — needs DiskArbitration and a real drive |
| **`mountOne` reverts to `…Whole`** | **NOT CAUGHT** — as recorded since 2026-08-06 |

The two uncaught mutations are the option constants. `unmountOne`'s is a **new** uncovered line,
noted at the call site rather than left implicit; both are pinned by the file header, by the
fan-out being tested where the volume set is actually decided, and by hardware observation of the
option value in `diskarbitrationd`'s log.

#### RESULTS of the re-run: the fix works; one defect remains, and it is not where anyone looked

**Cases 1 and 2 passed exactly as specified; case 3 behaved correctly.** The per-volume unmount is
confirmed on hardware, from the app's own log:

```
10:46:09.314  unmount succeeded on disk9s1: unmounted                         <- Vol_APFS, synthesized disk
10:46:09.383  unmount failed on disk8s2: DiskArbitration refused it (0xc010)  <- Vol_ExFAT, held open
10:46:09.434  unmount succeeded on disk8s4: unmounted                         <- Vol_HFS
10:46:11.245  mount succeeded on disk8s4: mounted
10:46:11.290  mount succeeded on disk9s1: mounted
              ── no line for disk8s1. EFI was not restored, because it never went. ──
```

`disk9s1` is the volume the whole-disk unmount silently skipped for three steps. It now gets its
own attempt and succeeds. The rollback put back exactly the two that went. This is also the first
time the rollback has been legible in the log at all — the `os_log` added to `mountOne`/
`unmountOne` is what makes these six lines exist.

**And the missing error message is NOT a state problem.** With every write to `lastOutcome`
funnelled through `present`/`clearOutcome`:

```
10:46:11.290  outcome shown (error): Could not unmount Vol_ExFAT: DiskArbitration refused it
              (status 0xc010). Close any open files or applications using the drive, then try
              again.  ⏎⏎  Any volumes that had already unmounted have been asked to remount…
```

**There is no `outcome cleared` line after it — none at all.** The message is set, is correct,
and is never erased. The user still does not see it.

**So the mechanism this file has been carrying as the suspected cause is positively excluded.**
The 2026-08-06 entry blamed `discovery.refresh()` inside the settle loop → a round-tripping
selection binding → `.onChange(of: selectedDeviceID)` → `lastOutcome = nil`, and recorded honestly
that it was *"a mechanism that would produce exactly the symptom, found by reading, not by
observing"*. It is now ruled out by observation rather than left unconfirmed. Nothing clears the
message; it is not drawn.

That is worth the space because the reasoning was sound and the code change it produced was
correct on its own terms — and it was still an explanation for the wrong defect. **A plausible
mechanism that would produce the observed symptom is not the cause of the observed symptom**,
and the only thing that separates them is an instrument that can tell the two states apart. There
was no such instrument until the funnel existed, which is why four rounds of this control were
argued about rather than measured.

#### The message was below the fold — and the fix is a modal, for a reason beyond prominence

**Confirmed by the user: scrolling the detail pane revealed it.** The text was rendering
correctly, in the right place, the whole time. It is the last element inside the detail pane's
`ScrollView`, below a device-identity block that is tall when the selected drive has several
mounted volumes — so on the four-partition fixture it drew just past the bottom edge, in a scroll
region that does not advertise itself as scrollable.

**Two reasons for a modal, and the first is structural rather than cosmetic** (user, 2026-08-09):

1. **Step 11 deletes the pane this message lives in.** Start takes over unmount → acquire → run →
   release, and the "Mounting & exclusive access" section goes with the three buttons. An error
   surface attached to a view that is about to be removed is not a surface.
2. > *"if I missed the error message multiple times, and I'm the owner of this project, a user is
   > also very likely to miss it — so it needs to be way more prominent."*

**Failures interrupt; successes do not; the inline copy is kept either way.** A modal on every
successful unmount trains the user to dismiss the dialog unread, which spends the prominence
exactly when it is next needed. Keeping the inline copy means the text can still be re-read and
text-selected after the dialog is gone — it is already `.textSelection(.enabled)`.

**The cost, stated because it is the one Step 10 deliberately avoided elsewhere.** A SwiftUI
`alert` gets its **own window**, so `scripts/render-ui.sh` cannot capture it. That is precisely
why increment 5 gave the run report a `Window` scene rather than a sheet — two of that
increment's defects were found only by looking at a render, and neither would have been found
behind an alert. **This surface will always need a person to confirm the dialog appears.** What
was done about it: the *decision* is a pure type (`OutcomePresentation`) tested where a mutation
can reach it, and the route taken is logged, so the only thing left to a human is "did a dialog
show up" rather than "was the right thing decided".

`OutcomeAlert` is deliberately **separate state** from `lastOutcome`, not derived from it: the
dialog is dismissed while the inline copy stays, so one value cannot represent both, and deriving
presentation from `lastOutcome != nil && !ok` would re-raise the dialog on the next unrelated
redraw.

**Verified. 739 tests, 0 failures, 88 suites** — up from 731/87; count from the xcresult. Zero
source warnings from all three clean builds. Helper source hash unchanged at `737e6972…`.

**Five mutations, five catches:**

| defect introduced | caught by |
|---|---|
| failures do **not** interrupt (**the original defect**) | `everyFailureInterrupts`, +13 issues |
| successes interrupt too | `noSuccessInterrupts`, +12 |
| every failure gets one generic title | `everyOperationHasItsOwnFailureTitle` |
| the title never reaches the presentation | `theFailureTitleReachesThePresentation`, +3 |
| both routes log the same name | `theTwoRoutesAreDistinguishableInTheLog`, +1 |

**Not covered, and recorded as such:** the one line in `DeviceListView.present` that hands the
title to `@State` — the same untestable-boundary as `unmountAll`'s single call to `unmountEach`,
and covered instead by the human confirmation below.

**What this cost, and what the shape of it was.** Five rounds on this control, and the last two
defects were not in the mechanism at all: the fourth attempt's logic was correct and the message
it produced was correct, and the user still could not act on either, because one was invisible to
the log and the other was invisible on screen. **A correct value that nobody can observe is
indistinguishable from a wrong one** — which is the same lesson as `DADiskUnmount` reporting
success, arriving from the opposite direction. The instruments came last again; they should have
come first.

**Human confirmation of the dialog: PASSED.** Both cases — a busy volume and a clean drive —
confirmed by the user 2026-08-09. The modal appears, headed with the operation, and the inline
copy remains after dismissal.

#### And then the success message was removed (user decision 2026-08-09)

> *"there is no reason to post any result message for a successful unmount all"*

Three reasons, and the first is structural rather than a matter of taste:

1. **Step 11 folds unmounting into the start of a run**, so there will be no "Mounting & exclusive
   access" pane to report into. The message is one that step deletes anyway.
2. **Finder already says it** — the volume disappears from the desktop.
3. **The Selected device pane already says it**, in standing text rather than transient:
   `Mounted volumes — None mounted`.

Reason 3 was **checked against the code before acting on it**, not taken on recollection —
`DeviceListView` renders `device.mountedVolumesDescription ?? "None mounted"` from the live device
record. Removing a message in favour of one that does not exist is this project's own "a
corrective instruction pointing where the control is not is worse than none", and it has already
happened twice in gate scripts.

**Implemented as a third route on `OutcomePresentation`, not an `if` at the call site.** The rule
is now: *failures always interrupt; successes are shown in place unless that operation's success
is already evident elsewhere, in which case nothing is shown.* Only the **success** branch
consults the operation — a per-operation exemption on the failure branch is how the one outcome a
user must act on gets suppressed, and mutation **S3** confirms the suite catches exactly that.

**The asymmetry with `mountAll` is deliberate and is the load-bearing part.** A successful mount
can mount **nothing** — an unformatted drive, or a filesystem macOS cannot read — with no
dissenter either way, and the standing pane reads "None mounted" for both *"nothing was asked"*
and *"everything was asked and nothing could"*. Its message is the only thing separating them, so
silencing it would delete an explanation rather than a duplicate.

**`.silent` is silent to the user, never to the log.** An outcome nobody was told about and nobody
recorded is precisely the state that cost this control two extra rounds, so the route is still
logged and its name differs from `inline`'s (mutation **S4**).

**Verified. 744 tests, 0 failures, 88 suites** — up from 739/88, count from the xcresult. Zero
source warnings from all three clean builds. Helper source hash unchanged at `737e6972…`.

**Four more mutations, four catches:**

| defect introduced | caught by |
|---|---|
| the unmount success message comes back | `aSuccessfulUnmountIsNotReportedAtAll` |
| every success is silenced (over-applied) | `aSuccessfulMountIsStillReported`, +2 |
| **silencing leaks into the failure branch** | `aFailedUnmountIsNeverSilent`, +8 |
| a silent outcome logs the same as inline | `aSilentOutcomeIsStillDistinguishableInTheLog` |

---
