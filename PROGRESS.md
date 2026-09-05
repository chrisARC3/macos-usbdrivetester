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

> **Cold start? Step 12 began 2026-09-05.** Chunk 0 (a measurement, no product change) and
> **chunk 1 (the `ENXIO` discriminator)** are done; chunks 2–7 are not. Step 11 closed 2026-09-05
> and its account was archived to [`progress/step-11.md`](progress/step-11.md) the same day.
> Nothing below is a snapshot; all of it is current as of **2026-09-05**.

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

### Current state — 2026-09-05, at Step 11's close

| | |
|---|---|
| **Working tree** | clean, on `main`, level with `origin/main` |
| **Verified** | **1158 tests, 0 failures, 142 suites** (floor `scripts/.test-floor` = 1158), run green 2026-09-05 at chunk 2. Chunk 1 added **19 tests in 4 suites**; chunk 2 added **12 in 2**. Build figures re-derived the same day: DerivedData wiped, then `build.sh Debug`, `build.sh Release` and `test.sh` in sequence — **zero source warnings from all three** (the only `warning:` lines in any log are `appintentsmetadataprocessor`'s "No AppIntents.framework dependency", which is a toolchain notice and not a source warning), **13/13** gate clients type-check. ⚠️ **This is not the increment gate**: that wipes DerivedData before *each* of the three and records the `SwiftCompile` task counts to prove none was cached. One wipe, three builds. The full form is chunk 7's |
| **Helper** | source hash **`a951e527c52384fc24de5eaaa613fe5872d463130f8dccb5a2f2fadcc20966c6`** — **moved 2026-09-05 by Step 12 chunk 1**, from `e6888aa5af72b433cd5b33cf18b98a0bab5d330e1fb058277e23aae82813f627`, which it had been since increment 11. **Re-derive it before trusting any hardware gate result below** — the recipe is `find USBDriveTester/com.arc3solutions.USBDriveTester.Helper USBDriveTester/USBDriveTester/Shared -name '*.swift' \| sort \| xargs cat \| shasum -a 256`. It will move again at chunks 2, 3 and 4 |
| **Protocol** | **v14.** Chunk 3 takes it to v15 |
| **Hardware gates** | ⚠️ **ALL FOUR LAPSED 2026-09-05, at chunk 1, exactly as the plan predicted** — the helper hash moved and every result recorded against `e6888aa5…` went with it. What each one *last* said, and what it is no longer evidence about: `metrics-check.sh` **128/0**, `xpc-concurrency-check.sh` **0 failures**, `retention-cycle-check.sh` **15/15** over the whole device — all three 2026-09-03 at `e6888aa5…`; `run-control-check.sh` **14 assertions / 0 failures**, twice on 2026-09-05 at the same hash. **None of these describes the current build.** They are re-run at chunk 7, against the moved hash and v15, and **a gate that has not been re-run cannot report anything** — do not cite the figures above as current |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, reinstalled 2026-09-04. ⚠️ **Always kickstart the daemon after `install-app.sh`** — it replaces the helper binary underneath the running one, and *nothing announces the mismatch when the helper source has not moved*. **Verify a reinstall took with `nm -U` on `Contents/MacOS/USBDriveTester.debug.dylib`**, not by timestamp: on 2026-09-04 a checklist chunk was nearly walked against a stale build |
| **Fixture** | 1 TB scratch T5, **serial `12345686DAA9`** (`disk7` on 2026-09-05 — BSD names move across a replug, so scripts resolve by serial). Its **`fill.bin` was restored 2026-09-04 18:19**: 999,947,239,424 bytes, volume 100% used, three samples digesting distinctly. **Invalidated by** unlinking the file or erasing the volume — **not** by `retention-cycle-check.sh` or `run-control-check.sh`, which write back exactly the bytes they read. Also attached as of 2026-09-04: the 4 TB T5 EVO (`disk6`) and the 125.8 MB UDisk thumb (`disk4`) |
| **Owed** | **The four hardware gates**, all lapsed at chunk 1 and re-run at chunk 7. Nothing else — Step 11 closed with its checklist complete, and chunks 0 and 1 closed green |
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
| **1** | **Route (a), the `ENXIO` discriminator.** Core only, no wire change | **done 2026-09-05.** See below |
| **2** | Route (b), the DiskArbitration removal callback — `VolumeChangeWatcher` learns *which* disk went, and the "is this the device under test" predicate becomes a pure testable type | **done 2026-09-05.** See below. Helper hash **unmoved** — app target only |
| **3** | The wire: protocol **v15**, the fifth `RunOutcomeCode`, and all 13 gate clients rebuilt | not started |
| **4** | The state machine and wind-down: the sixth `RunControlEvent`, three ways in and one out, and a deadline that does **not** fail open | not started |
| **5** | The report: the fifth `RunReportOutcome`, `HonestFraming`, presentation, Markdown | not started |
| **6** | The error surface and FR-DEV-8's discovery re-run; the modal interaction and its ⌘Q truth-table row | not started |
| **7** | Mutation round, `progress/step-12-human-checklist.md`, the physical-unplug hardware gate, **and all four hardware gates re-run** against the moved hash and v15 | not started |

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
  this, and chunk 2 built the detection route that covers a **paused** run. The **app** still
  cannot tell device loss from a refusal until chunk 3 puts it on the wire, and **nothing acts on
  route (b) yet** — chunk 4 is what turns the removal callback into a terminated run. See
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
