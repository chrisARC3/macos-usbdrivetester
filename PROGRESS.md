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

> **Cold start? Step 12 began 2026-09-05.** Chunks 0–6 of 8 are done, and **chunk 7 is under
> way**: 7a (the full increment gate), 7b (the mutation round) and 7c (the human checklist) are
> done, **7d is DONE, and 7e is UNDER WAY**. The app is reinstalled and verified, the daemon is
> kickstarted — but ⛔ **the 16:01:04 kickstart came back out of DerivedData, not `/Applications`, and 7e is blocked on re-registering from the installed app**; the binaries are byte-identical so nothing is wrong with the code, only with where it is being run from (see the Installed app row). The
> thumb is back with both slices, and **all four hardware gates were re-run 2026-09-07 against
> helper hash `e19b0b3c…` and passed with zero failures**. 7e walks the five-chunk checklist:
> **chunks 1 and 2 walked and passed 2026-09-08** — the alert by eye, and the report's device-loss
> face. **Chunk 3 aborted the same day having found a shipped defect**, fixed at **7f**: route (b)
> accepted a *slice* disappearance as the drive leaving, and the run's own exclusive whole-disk
> open is what makes the slices disappear, so the app ended healthy runs ten milliseconds in on any
> partitioned drive. **Chunk 3 must be re-walked from the top**, then chunks 4 and 5.
> Step 11 closed 2026-09-05 and its account was archived to
> [`progress/step-11.md`](progress/step-11.md) the same day. Nothing below is a snapshot; all of it
> is current as of **2026-09-08**.
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
> 4. **[`progress/step-12-human-checklist.md`](progress/step-12-human-checklist.md)** — written at
>    chunk 7c. **Chunks 1 and 2 were walked and passed 2026-09-08; chunks 3, 4 and 5 are not
>    walked** and all three pull a cable out of a running machine. Its *"What has no automated
>    cover"* list is the honest account of what
>    1,297 tests do not reach in this step. Item 4.9 (the multi-slice idempotency check) **was**
>    blocked for want of a partitioned drive; the user decision of 2026-09-07 settled it, and the
>    125.8 MB thumb now holds the `multislice` role with its geometry confirmed on hardware.

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

### Current state — 2026-09-08, at Step 12 chunk 7f (the false-positive device loss, fixed)

| | |
|---|---|
| **Working tree** | clean, on `main`. **Ahead of `origin/main` by Step 12's commits** — nothing is pushed unless asked |
| **Verified** | **1301 tests, 0 failures, 153 suites** (floor `scripts/.test-floor` = **1301**, ratcheted at 7f), run green **2026-09-08 at chunk 7f** — which added 5 and rewrote 3 that had asserted the defect. Before that, **1297** run green 2026-09-07 at chunk 7b. Chunk 1 added **19 tests in 4 suites**; chunk 2 added **12 in 2**; chunk 3 added **13 in 1**; chunk 4 added **49 in 2** — `DeviceLossWindDownTests` (13) and `RunControllerDeviceLossTests` (23), plus 6 policy rows and 7 sequencer tests into existing suites; chunk 5 added **42 in 4** — `DeviceLossAccountTests` (11, displayed as *"Device-loss account (Step 12, FR-DEV-8)"*), `DeviceLostOutcomeTests` (9), `DeviceLostMarkdownTests` (7) and `RunControllerDeviceLossReportTests` (7), plus 8 into `HonestFramingTests`; chunk 6 added **26 in 3** — `RunControllerDeviceLossSurfaceTests` (9), `DeviceLossMessageTests` (10, displayed as *"Device-loss alert (Step 12, FR-DEV-8)"*) and `AppModelDeviceLossTests` (5, *"Device loss rebuilds the list (Step 12, FR-DEV-8)"*), plus 2 more into `HonestFramingTests`, which now stands at 29; **chunk 7b added 9 in 1** — `ShortTransferIsNotDeviceLossTests` (4) plus 5 into `InMemoryBlockDeviceTests`. **13/13** gate clients type-check. The full increment gate — DerivedData wiped before *each* of `build.sh Debug`, `build.sh Release` and `test.sh` — was run at 7a and **re-run at 7b, because 7b moved the helper source hash and 7a's figures were recorded against the old one**; see the chunk 7 section |
| **Helper** | source hash **`e19b0b3c972d4b5bf9e052d087df231d34c8eee65aaddb9d772ce338db35edb9`**, **moved 2026-09-07 by chunk 7b**. The trail: `e6888aa5…` → `a951e527…` (chunk 1) → `42774589…` (chunk 3) → **`e19b0b3c…`** (chunk 7b). Chunks 2, 4, 5 and 6 did not move it, being app-target only — **and this row predicted chunk 4 would**, which was wrong, then predicted chunk 6 would not, which held, then predicted chunk 7 could, which held. **Re-derive it before trusting any hardware gate result below** — the recipe is `find USBDriveTester/com.arc3solutions.USBDriveTester.Helper USBDriveTester/USBDriveTester/Shared -name '*.swift' \| sort \| xargs cat \| shasum -a 256`. ⚠️ **What moved it at 7b is a test fake**: `Core/InMemoryBlockDevice.swift` is a membership exception in `project.pbxproj` — built into `USBDriveTesterTests` **as well as** the helper — so its two new hooks link into the daemon binary (`nm` finds `injectShortRead` and `injectShortWrite` in it) even though nothing outside the test target ever instantiates the class. The hash therefore moved for a change that **cannot** alter what the running daemon does. That is not a reason to discount it: the recipe is defined by path, the binary really is different, and the four gates below had already lapsed at chunk 1, so 7b's move costs nothing that was not owed. It is a reason not to be surprised by it |
| **Protocol** | **v15**, since chunk 3 (2026-09-05). **The installed daemon serves v15 as of 2026-09-08 12:14:01** (pid 84459, resolved from `/Applications`; ⛔ the current daemon, pid 88873 at 16:01:04, resolves from **DerivedData** — same v15, byte-identical binary, wrong provenance, see the Installed app row; the four hardware gates below were served by its predecessor pid 69701, also v15 and also from `/Applications`), confirmed by its own start line and asserted independently by three of the four gates. The cycle reply went from 22 arguments to 23, so a v14 app and a v15 daemon **cannot** decode each other — loud, unlike the v13→v14 bump. ⚠️ Reinstall **and kickstart** before any gate (`scripts/install-app.sh`); copying files never reloads a running daemon, and **a kickstart can relaunch the DerivedData copy** — check the `to program:` resolve line, not just the version |
| **Hardware gates** | ✅ **ALL FOUR RE-RUN AND PASSED 2026-09-07**, against helper hash **`e19b0b3c…`**, protocol **v15**, daemon pid 69701 started 15:25:16 and resolved from `/Applications`, on the 1 TB scratch T5 (serial `12345686DAA9`): `metrics-check.sh` **128 assertions / 0 failures**, `xpc-concurrency-check.sh` **0 failures**, `retention-cycle-check.sh` **15 checks / 0 failures**, `run-control-check.sh` **14 assertions / 0 failures** — **zero failures across all four**. Every figure is identical to what the same gate last reported at `e6888aa5…`, which is the expected outcome and not a reason the re-run could have been skipped. They had **ALL FOUR LAPSED 2026-09-05 at chunk 1** when the hash moved, and lapsed again at 7b; this row is now evidence about the current build. ⚠️ **They lapse again the moment the helper source hash moves** — re-derive it from the Helper row before citing any figure here |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, **reinstalled 2026-09-08 15:09 at chunk 7f part 2** from `0b37afd` — ship code, the chunk-1 debug hook reverted. **Proved by content, not by timestamp**: in `Contents/MacOS/USBDriveTester.debug.dylib`, the string added by this very commit — `a slice of the drive under test disappeared and was ignored` → **1** — alongside `the drive under test left the machine while` → **1** and `a disk disappeared` → **1**; **5,624** strings total, and the dylib is **byte-identical to the DerivedData copy** (`6e2f8612…`). *That new string is the strongest content proof this row has ever carried: it cannot be present in any build older than this commit, so unlike a symbol that has existed for weeks it distinguishes THIS build from its immediate predecessor.* Before this, reinstalled 2026-09-08 10:38 at chunk 7e from `55a5c71`. Helper binary sha256 **`7590b920…`** (was `ab4b6957…`), byte-identical to the DerivedData copy, which is why provenance has to come from the resolve line and cannot come from the bytes. ⚠️ **Grep the dylib, not `Contents/MacOS/USBDriveTester`** — that is a **59 KB launcher stub** with 79 strings in it against the dylib's **5,600-odd** — a figure that moves with every commit, so read it as an order of magnitude and not as a checkable constant. A content proof aimed at the stub returns 0 for everything and reads exactly like a failed install. Measured 2026-09-08, after one such false negative. ⛔ **The running daemon is resolving out of DerivedData and the walk is BLOCKED on fixing that** — kickstarted 2026-09-08 16:01:04 (pid 88873), and `xpcproxy` logged `to program: /Users/christopherkarr/Library/Developer/Xcode/DerivedData/…/Debug/USBDriveTester.app/…` where 12:14:01 (pid 84459) had logged `/Applications/…`. **Not a correctness risk** — the helper binary is byte-identical in both bundles (`7590b920…`), as is the app dylib (`6e2f8612…`), so the daemon is running exactly the code under test. It is a **provenance** risk, and a live one: DerivedData is rebuilt at every chunk, so the daemon's own bundle can be replaced underneath a multi-hour hardware walk, and no gate result could name the bundle it ran against. Cause: BTM's DerivedData app record is the one listing the helper under `Embedded Item Identifiers` — see `CONSTRAINTS.md` §1 *The BTM record is keyed by bundle IDENTIFIER*, which has the four-record dump. **Fix (GUI): launch `/Applications/USBDriveTester.app`, Step 3 panel → Unregister → Register, then kickstart, then re-read the resolve line.** ⚠️ Do **not** delete the DerivedData bundle to force it — that strands the BTM record and the only cleanup is machine-wide `sfltool resetbtm`. Last confirmed resolving from `/Applications` 2026-09-08 12:14:01: protocol **v15**, and `xpcproxy` logged `to program: /Applications/USBDriveTester.app/…` — checked from the unified log, which needs no `sudo`: `/usr/bin/log show --last 5m --predicate 'eventMessage CONTAINS "to program: " AND eventMessage CONTAINS "USBDriveTester"'`. **Two lessons this row was bought with, both still live:** copying files never reloads a running daemon, and a kickstart can relaunch the **DerivedData** copy — on 2026-09-07 one did, and the version handshake could not tell, because the source was identical. |
| **Fixture** | 1 TB scratch T5, **serial `12345686DAA9`** (`disk7` on 2026-09-05 — BSD names move across a replug, so scripts resolve by serial). Its **`fill.bin` was restored 2026-09-04 18:19**: 999,947,239,424 bytes, volume 100% used, three samples digesting distinctly. **Invalidated by** unlinking the file or erasing the volume — **not** by `retention-cycle-check.sh` or `run-control-check.sh`, which write back exactly the bytes they read. Also attached as of 2026-09-07: the 4 TB T5 EVO (`disk6`, serial `00000S7CLNJ0WC02266P`) and the 125.8 MB UDisk thumb (serial `2211190533300386001515`). **The thumb became a declared role — `multislice` — on 2026-09-07**, repartitioned for checklist item 4.9. It **de-enumerated during that repartition and was physically replugged the same day**, coming back complete: `resolve_target multislice` reports `/dev/disk4`, General UDisk, serial `2211190533300386001515`, 245760 × 512 B, slices `disk4s1` **59.8 MB** and `disk4s2` **64.0 MB**. The role's geometry is therefore **confirmed on hardware**, not merely expected. ⚠️ The slices are 59.8/64.0 MB, **not** the even 60/60 the repartition asked for — `Slice_B` took the remainder — so anything checking for *"two 60 MB slices"* should check for **two slices** |
| **Owed** | **The four hardware gates**, all lapsed at chunk 1 and re-run at chunk 7. `progress/step-12-human-checklist.md` was written at 7c and **its chunks 1 and 2 were walked and passed 2026-09-08** — the alert by eye, and the report's device-loss face. **Chunk 3 aborted on 2026-09-08** having found the 7f defect, and is owed a **re-walk from item 1** against the fixed build. **What is still owed is its chunks 3, 4 and 5**: the unplug during write-back, the unplug while paused (including 4.7, which produces the real paused report chunk 2 could only read off a render, and 4.9, the multi-slice idempotency check on the thumb), and chunk 5's two measurements. All three write to the scratch drive. That is the hardware gate with no substitute — **a person pulling a real drive out of a real port**, the only thing that can measure what chunk 4's 3-second deadline was chosen without. Chunk 7's checklist also inherits **three declared-uncoverable survivors** for its *"What has no automated cover"* list: `deviceUnderTest = nil` in `driveIsBack()` (chunk 4), the identity of the device-loss SF Symbol (chunk 5), and **`RunControllerWiring`'s `onDeviceLost:` closure** (chunk 6) — the composition root, where a decision has no cover but a person at the keyboard. **And one thing only a person can see at all: the device-loss alert itself**, which `render-ui.sh` cannot capture because an `.alert` takes its own window. Nothing else — Step 11 closed with its checklist complete, and chunks 0–6 closed green |
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
| **7** | Mutation round, `progress/step-12-human-checklist.md`, the physical-unplug hardware gate, **and all four hardware gates re-run** against the moved hash and v15 | **in progress**, split into 7a–7e. **7a done 2026-09-07**, `76f5ad9` — the full increment gate. **7b done 2026-09-07** — the mutation round over chunks 1–3's surface: 12 mutations, **11 killed as declared, one unexpected survivor**, now closed. **Moves the helper hash to `e19b0b3c…`.** **7c done 2026-09-07** — `progress/step-12-human-checklist.md`, five chunks, unwalked at the time. **7d DONE 2026-09-07**: app reinstalled and verified by symbol, the daemon kickstarted (twice — see below), the thumb replugged with both slices intact, and **all four hardware gates re-run against `e19b0b3c…`/v15 with zero failures**. **7e UNDER WAY**: the five-chunk checklist walk, of which **chunks 1 and 2 passed 2026-09-08** against `55a5c71` — and both of chunk 2's unwalked items turned out to be **instrument defects, reworded rather than failed**. **7f DONE 2026-09-08**: the false-positive device loss that walk found — route (b) accepted a slice disappearance as the drive leaving, and the run's own exclusive whole-disk open is what produces those slices, so any partitioned drive ended its run ten milliseconds after the claim. One guard, six tests killing the mutation, **helper hash unmoved so the four gates stand**. Chunks 3 (re-walk), 4 and 5 — the physical unplugs and the never-made measurements — are **all that remains of Step 12** |

### Chunk 7 — the gate, the mutation round, and the gap that was in the fake

Split into five: **7a** the full increment gate, **7b** the mutation round, **7c** the human
checklist, **7d** install plus the four lapsed hardware gates, **7e** walking that checklist,
**7f** the defect that walk found. **7a–7d and 7f are done; 7e is under way** — its chunks 1 and 2
passed 2026-09-08, its chunk 3 aborted on the defect and is owed a re-walk, and chunks 4 and 5 are
the remaining physical unplugs.

**7a** (`76f5ad9`) ran the gate in its full form — DerivedData wiped before *each* of `build.sh
Debug`, `build.sh Release` and `test.sh`, rather than once before all three. It also found that
**Release's `SwiftCompile` task count cannot detect a cached build**: WMO emits one task per module,
so 2 is what Release reports whether it compiled seventy files or none. Counting distinct project
sources works for both configurations — 70 of 70 in each. Recipe in `BUILD-PLAN.md`.

**7b** mutated chunks 1–3's surface — the `ENXIO` discriminator, `DeviceUnderTest.wasLost`, and the
v15 wire. **Twelve mutations, eleven killed as declared, one unexpected survivor.**

The survivor, **m5**: moving `.shortTransfer` from the block-failure arm of
`RetentionTestEngine.classify` into `.deviceLost` passed all 1,288 tests. So did the reverse
reading — nothing pinned the engine's treatment of a short transfer **in either direction**.

**The gap was in the test double, not in the tests.** `InMemoryBlockDevice` is the only device the
engine tests run against, and it had four fault hooks — read error, write error, silent corruption,
device loss — and **none that could produce a short transfer**, because Step 2 reserved that case
for the real device and nothing revisited it. `FileDescriptorBlockDeviceTests` pins what *produces*
a short transfer, which is a fact about the descriptor and says nothing about what the engine does
with one. No test could have been written to close this without first giving the fake the
capability, which is why a round that asks *"is this line load-bearing?"* found it and eight steps
of test-writing did not. Written up as a `CONSTRAINTS.md` §3 lesson.

The fix is `injectShortRead(blocks:transferring:)` and `injectShortWrite(blocks:transferring:)`,
which deliver or persist their prefix and *then* throw — as the real device does, where
`transferred` bytes are already in the caller's buffer when the guard fires. Nine tests: four in
`ShortTransferIsNotDeviceLossTests`, whose load-bearing one runs the same offset on the same fixture
**three ways** — bad block, short read, absent device — and asserts the first two agree and both
differ from the third; five in `InMemoryBlockDeviceTests` on the fake's own fidelity. Re-running m5
against them now fails all four engine tests, with twenty issues.

**Two things this leaves standing.** The physics is still open: whether a real de-enumerating drive
produces a short read before it produces `ENXIO` is what 7e can answer and nothing here can. And the
cost if it does is now itself a test — one spurious range and the run still ends — so the open
question is bounded rather than unbounded.

⚠️ **7b moves the helper source hash**, and therefore **7a's gate figures lapsed with it**. The gate
was re-run at 7b's end rather than carried forward: 7a's numbers were recorded against `42774589…`
at `9d0a1e0`, and this is exactly the shape of stale claim this project has paid for eight times.
What moved the hash is a test fake that the daemon links but never instantiates — see the Helper row
above for why that is bookkeeping rather than a behaviour change, and why it is recorded anyway.

**The re-run, 2026-09-07, at helper hash `e19b0b3c…`, protocol v15** — DerivedData wiped before each
of the three:

| | exit | `SwiftCompile` tasks | project sources named | source warnings |
|---|---|---|---|---|
| `build.sh Debug` | 0 | 92 | **70 of 70** | 0 |
| `build.sh Release` | 0 | 2 (WMO — one per module) | **70 of 70** | 0 |
| `test.sh` | 0 | 182 | — | 0 |

**1297 tests / 153 suites / 0 failures**, floor 1297 — **the figures at that gate, 2026-09-07;
7f took the suite to 1301 and the floor with it.** **13/13** gate clients type-check. The only
`warning:` lines in any of the three logs are `appintentsmetadataprocessor`'s "No AppIntents.framework
dependency", a toolchain notice rather than a source warning. Every figure is identical to 7a's,
which is the expected result and not a reason to skip the run: 7b edited existing sources and added
no new ones to either target, so a *changed* count would have been the finding.

**⚠️ What invalidates this**: any source change in 7c, 7d or 7e. 7c is a document, 7d installs and
runs scripts, 7e is a measurement — none should touch Swift. If one does, the gate is re-run again
before Step 12 closes.

**7c** wrote [`progress/step-12-human-checklist.md`](progress/step-12-human-checklist.md) — five
chunks, unwalked **at the time**, modelled on Step 11's sixteen. Two dry (the alert by eye; the
report's device-loss face), three that pull a cable out of a running machine. **The two dry ones
were walked at 7e and passed, 2026-09-08.**

Its *"What has no automated cover"* list has **seven** entries, and each was declared in a mutation
round before it was written down rather than found afterwards: the `RunControllerWiring` closure
(chunk 6's m17), the SF Symbol names, the alert in its entirety, `deviceUnderTest = nil` in
`driveIsBack()`, which log **level** a device-loss line carries, the three-second deadline as a
*duration*, and that a real drive returns `ENXIO` at all.

Three things came out of writing it that are not checklist items:

- **Chunk 4.9 is blocked on a user decision, and says so rather than quietly directing a write.**
  The multi-slice idempotency check needs a **partitioned** drive; the only one attached is the 4 TB
  T5 EVO, which holds data, and the 1 TB scratch T5 has one volume. Three options are written out —
  repartition the 125.8 MB thumb, repartition the scratch T5 (destroying `fill.bin`), or accept it
  as hardware-uncovered on the strength of `threeCallbacksFromOneUnplugArmOneDeadline`. **The
  decision and its date go in that item before Step 12 closes.**
- **The alert chunk cannot be walked from a build run in place.** `SMAppService` records the path of
  the app that registered the daemon, so a DerivedData build has no helper — and the launch-time
  gate is `.interactiveDismissDisabled()`, so the app sits behind a sheet that cannot be dismissed
  and SwiftUI queues the second one invisibly. The chunk therefore installs a temporarily edited
  build to `/Applications` and **ends by reverting and reinstalling**, because otherwise chunks 3–5
  measure a binary with a debug hook in it.
- **A stale test name, found while writing the entry that depended on it.**
  `theFourVerifiedOutcomesHaveFourDistinctSymbols` has always read `RunReportOutcome.allCases`; chunk
  5 added the sixth case and the name went stale with nothing failing. Renamed to
  `noTwoVerifiedOutcomesShareASymbol` — the property rather than the tally — so the next case cannot
  repeat it. Test count unchanged at 1,297.

**7d is DONE.** The app is reinstalled and the install is *proved*, the two things that needed the
user were done by them on 2026-09-07, and all four hardware gates were re-run and passed.

**The reinstall, verified by symbol rather than by timestamp.** `install-app.sh Debug` from
`77edc94`, then:

```bash
nm -U /Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper | grep -c injectShort
```

**2.** Those symbols exist only in chunk 7b's source, so the installed helper provably contains this
commit — a stronger claim than any file date, and it works precisely *because* 7b moved the hash.
Binary sha256 `ab4b6957…`, was `ef6ce121…`.

**⚠️ THE RUNNING DAEMON WAS TWO DAYS AND EIGHT CHUNKS STALE, AND NOBODY HAD NOTICED.** pid 97558
started **2026-09-04 17:01:05**, three minutes after `213735a` — which is *before Step 12's first
commit*. It predates chunk 1, the v15 bump at chunk 3, and every chunk since. The 2026-09-06 install
did not restart it and neither did anything else, so the whole of chunks 4, 5 and 6 sat beside a
**protocol v14 daemon**. This row said until today that the daemon "may already be protocol-correct";
it was not, and could not have been. What found it was checking the **daemon's** start time rather
than the **bundle's** mtime — `install-app.sh` has printed that warning at every install since
2026-08-18 and it had simply not been acted on.

**Run by the user 2026-09-07 — and it took two.**

```bash
sudo /bin/launchctl kickstart -k system/com.arc3solutions.USBDriveTester.Helper
```

The **first**, at **11:07:38**, produced a protocol v15 daemon — and `xpcproxy` resolved the label
to the **DerivedData** build rather than to `/Applications`:

> `Resolved (com.arc3solutions.USBDriveTester, 1, Contents/MacOS/…Helper, …) to program:`
> `/Users/…/DerivedData/USBDriveTester-…/Build/Products/Debug/USBDriveTester.app/Contents/MacOS/…`

Harmless on the day — the two binaries were byte-identical, sha256 `ab4b6957…` — but this is
`SMAppService`'s recorded-path hazard showing itself, and **the gate recipe wipes DerivedData**, so
four gate results would otherwise have carried provenance pointing into a directory the recipe
deletes. `backgroundtaskmanagementd` re-pointed the record to `/Applications` 102 seconds later,
when the installed app was launched — but a running daemon does not re-exec on its own, so the
**second** kickstart at **15:25:16** is the one that resolved to `/Applications/USBDriveTester.app/…`,
and it is what all four gates ran against.

**The lesson, and it is new: check the *resolve* line, not only the version.** A v15 answer says the
source is right and says nothing whatever about which copy of it is running — the two builds share a
source hash, so the handshake cannot tell them apart.

```bash
/usr/bin/log show --last 5m --predicate 'eventMessage CONTAINS "to program: " AND eventMessage CONTAINS "USBDriveTester"'
```

**All four hardware gates re-run 2026-09-07, and all four passed.** Against helper hash
`e19b0b3c…`, protocol **v15**, daemon pid 69701 (started 15:25:16, resolved from `/Applications`),
on the 1 TB scratch T5, serial `12345686DAA9`:

| Gate | Result | Writes? | What it establishes here |
|---|---|---|---|
| `metrics-check.sh` | **128 assertions / 0 failures** | yes | live delivery, cumulative progress over four calls, NFR-PERF-3 device-bound at 2.377% host overhead |
| `xpc-concurrency-check.sh` | **0 failures** | no | same connection **serialized**, second connection **concurrent** (worst 6.0 ms) — D1 unchanged |
| `retention-cycle-check.sh` | **15 checks / 0 failures** | yes | 932 window fingerprints unchanged after writing 1,072,693,248 B at block 1855897600 (NFR-REL-1) |
| `run-control-check.sh` | **14 assertions / 0 failures** | yes | all four I/O sizes settled at a chunk boundary with the exact resume point |

**Every figure is identical to what the same gate last reported at `e6888aa5…`.** That is the
expected outcome, and it is not an argument that the re-run could have been skipped — it is what
being able to say so costs. Three of the four assert the daemon's protocol version themselves, so
v15 is established from inside the product and not only from a log line.

⚠️ **Counting assertions is an instrument, and it misread once here.** A first tally of
`run-control-check.sh` gave **16**, against **14** in the record, with the script provably unchanged
since `a6e3bb0`. The two extra were preamble checks — probe signing and unmount — outside the
`---- assertions ----` block the recorded figure counts. Nothing had changed; the grep was wider
than the convention. Recorded because a figure that disagrees with an earlier one is exactly the
shape of a real finding, and the cost of checking was two minutes.

**The multi-slice fixture, and an accident that confirmed its premise.** User decision 2026-09-07:
checklist item 4.9 gets the **125.8 MB "General UDisk" thumb**, serial `2211190533300386001515`,
repartitioned into two 60 MB exFAT slices, rather than repartitioning the scratch T5 or accepting
the item as hardware-uncovered. It is now a declared role, `multislice`, in
`scripts/lib/device-identity.sh`, with the resolver wired and its refusal path checked.

The repartition was:

```bash
/usr/sbin/diskutil unmount force /dev/disk4s1
/usr/sbin/diskutil partitionDisk /dev/disk4 GPT ExFAT Slice_A 60M ExFAT Slice_B R
```

⚠️ **It did not finish.** `partitionDisk` wrote the GPT and both slices — `disk4`, `disk4s1` and
`disk4s2` all appear in the StorageKit log — and then the storage stack **vanished mid-format while
the USB device stayed enumerated in IOKit with no `IOMedia` under it**. `diskutil` hung and was
killed. **The thumb was physically replugged 2026-09-07 and came back complete** — the GPT and
both slices survived, so `partitionDisk` had got further than the hang suggested. The geometry
recorded for the role is now **confirmed** rather than expected: `resolve_target multislice`
resolves `/dev/disk4`, General UDisk, serial `2211190533300386001515`, 245760 × 512 B. The slices
came back **59.8 MB and 64.0 MB** rather than the even 60/60 asked for — `Slice_A`'s `60M` rounded
down and `Slice_B`'s `R` took the remainder.

Two things worth keeping from it:

- **Three `Operation = Disappear` notifications for one drive going away** — `disk4s1`, `disk4s2`,
  `disk4` — which is exactly the count BUILD-PLAN records for a two-partition drive, observed here
  at the StorageKit layer rather than DiskArbitration's. The fixture demonstrated the premise it
  was bought to test before it was asked to.
- **The shape matches the carried-forward loose end**, without explaining it. The 2026-08-06
  scratch-drive de-enumeration whose root cause is still open looked like this: storage gone, and
  the run's descriptor answering for a device that was not there. A cheap 125.8 MB thumb dropping
  off under a repartition is far more likely to be the drive than anything systemic, so this is
  **one more observation of the shape and not a diagnosis** — recorded because the loose end has
  had exactly one observation behind it until now, and now has a second of a different drive.

#### 7e — walking the checklist: chunks 1 and 2, and two defects that were in the instrument

**Chunk 1 — the device-loss alert, by eye. All 8 items passed, 2026-09-08.** The alert is the one
surface `scripts/render-ui.sh` cannot reach — an `.alert` gets its own window and takes
`ViewBuilder`s AppKit consumes — so this walk is the *only* evidence it renders at all, and it is
evidence about one build on one day. Reaching it needed a temporary `CommandMenu("Debug")` hook,
placed deliberately in `USBDriveTesterApp.swift` and **not** in `Shared/`, so the helper source hash
did not move and 7d's four gate results did not lapse for it. The hook was reverted **from a saved
pristine copy**, never `git checkout`, and never committed.

**Chunk 2 — the report's device-loss face. Items 1, 2 and 5 passed; items 3 and 4 were reworded.**
Read off `render-ui.sh` renders of `report-device-lost` and `report-device-lost-paused` — the
product's own `RunReportPresentation`, not a mock-up. Item 5 is the one BUILD-PLAN asks for by name,
and the two accounts discriminate correctly: the write-back case says *"that chunk may hold partly
written data"*, the paused case says *"nothing was left half-written"* and warns of nothing.

⚠️ **Both unwalked items were instrument defects. Neither described a fault in the app** — the third
and fourth of that kind since 2026-09-04, and the ratio now stands at five of six defects found that
week being in the checklist or the logging rather than the product.

- **Item 3** demanded the device-loss symbol be *"a different shape … not a variation on a mark
  inside a circle"*. **Six of the seven outcome symbols are a mark inside a filled circle by
  design** — only `exclamationmark.triangle.fill` breaks that outline — so a walker following it
  literally would have recorded a FAIL against correct behaviour. Reworded to NFR-USE-8's actual
  condition: no two collide in greyscale, by interior mark **or** by outline. `RunReportPresentation`
  carries the same overstatement in a comment, calling `eject.circle.fill` a *"distinct silhouette
  at 16pt"* when the silhouette is a circle like five others; **left uncorrected, and owed.**
- **Item 4** asked that the drive be named by model and serial *"in the headline and the explanation
  below it"* — neither of the two places it actually appears. It is on the subtitle line beneath the
  headline and again in the Drive table. Reworded to say so.

**Three working facts this chunk paid for.**

1. **Builds are now installed automatically before any hands-on test, and never asked about** —
   user instruction, 2026-09-08. Only the `sudo` kickstart is still handed over.
2. ⚠️ **A content proof must grep `USBDriveTester.debug.dylib`, not `Contents/MacOS/USBDriveTester`.**
   This is a debug-dylib build: the app binary is a **59 KB launcher stub** holding 79 strings
   against the dylib's 5,600-odd, so a proof aimed at it returns 0 for every product string and reads
   exactly like a failed install. One such false negative was taken at face value here before the
   instrument was checked.
3. **The `to program:` resolve line can be read headlessly and needs no `sudo`** — `xpcproxy` logs
   it to the unified log at spawn. After the 12:14:01 kickstart it read
   `/Applications/USBDriveTester.app/…`, which is what 7d had to kickstart twice to achieve. The
   binaries were byte-identical again (`7590b920…`), so the bytes could not have answered it.

**Still owed: chunks 3, 4 and 5** — the unplug during write-back, the unplug while paused (with 4.7,
which produces the real paused report chunk 2 could only read off a render, and 4.9, the multi-slice
idempotency check on the thumb), and chunk 5's two measurements. All three write to the scratch T5.

#### 7f — the app ended its own run, and had been doing it for three days

**Chunk 3 of the walk never reached an unplug.** The run ended **ten milliseconds after the claim
was granted**, before the cable was touched, and the alert said the drive had been disconnected. It
had not: the T5 was enumerated throughout, and the run the app discarded went on to finish
**128/128 chunks, 1,073,741,824 B read, written back and verified, no failed block ranges**, six
seconds later.

**What happened**, from the app's own log:

```
14:28:23.876  APP     unmount succeeded on disk7s2: unmounted        <- the app's own doing
14:28:23.885  HELPER  acquired disk7: claim held, /dev/rdisk7 open exclusively (fd 4)
14:28:23.886  HELPER  acquire GRANTED
14:28:23.888  HELPER  retention cycle START: 128 chunks
14:28:23.896  APP     a disk disappeared: disk7s1 (slice)
14:28:23.896  APP     the drive under test left the machine while running    <- FALSE
14:28:23.896  APP     a disk disappeared: disk7s2 (slice)
14:28:27.045  APP     no reply after 3.000000s — ending the run on the removal callback alone
14:28:30.561  HELPER  retention cycle END: completed; 128/128 chunks; no failed block ranges
```

**The whole disk never disappeared** — zero `disk7` events in the capture. Taking exclusive
whole-disk access tears the partition scheme down, the slices' `IOMedia` nodes terminate, and
DiskArbitration reports each one. **The run's own claim fired route (b).**

`DeviceUnderTest.wasLost(whenDiskDisappeared:)` accepted a slice, and its header argued for it:

> the device under test is unmounted and exclusively claimed, so nothing can be repartitioning it,
> and therefore a slice of it vanishing can only mean the drive vanished

The premise is not weak, it is **inverted** — the exclusive claim is the cause, not the alibi. The
fix is one guard, `guard disk.isWholeDisk else { return false }`, placed before the identity checks
because it asks a different question: not *which* drive, but whether the event can mean a drive left
at all. A whole-disk disappearance is what an unplug produces; a slice-only one is what this app
produces.

**Why three days of green did not find it.** Every test of route (b) synthesises its own
`DisappearedDisk`, so the suite could only check the rule it had been told — it could not observe
which events a real claim produces. And the four hardware gates drive the **helper** through probe
tools, while route (b) lives in the **app**: the coverage that looked strongest could not reach the
code. Chunk 7b's mutation round did not touch it either, because a mutation of a rule the tests
agree with is killed by tests that are themselves wrong. **What found it was a person pressing
Start once, on a drive with a partition table** — which is the argument for the human checklist,
made by the checklist, on its third chunk.

**Cover added.** Four new tests and three rewritten that had asserted the defect —
`aSliceOfTheDriveDisappearingIsNotTheDriveBeingLost`, `theRunsOwnClaimTearingDownItsSlicesEndsNothing`
(the logged sequence, in order), `onlyAWholeDiskDisappearanceCanMeanTheDriveWasLost`,
`theGateReadsTheFlagRatherThanTheNamesShape`, `aSliceOfTheDriveUnderTestDoesNotEndTheRun` and its
companion `theWholeDiskDisappearingStillEndsAPausedRun`. **Deleting the wholeness test is killed by seven of
them.** Suite **1301 / 153 / 0**, floor ratcheted 1297 → 1301.

**And the refusal is no longer silent.** `wasLost` was split into two predicates — `isWholeDisk &&
namesThisDrive`, with `isASliceOfThisDrive` as its complement — so the controller can log the
interesting refusal and stay quiet about other drives:

```
a slice of the drive under test disappeared and was ignored: disk7s1 — this run's own exclusive
whole-disk claim is what removes it, and the drive itself is still here: <model, serial, locator>
```

At **notice**, because on a partitioned drive it fires once per slice as a matter of course. It is
there for the same reason `driveCannotBeWatchedForRemoval` is: **a guard that refuses silently cannot
be told apart from a callback that never fired**, and telling those two apart is precisely the
reading chunk 3's re-walk has to take. `everyDisappearanceIsLostOrIgnoredOrNotOurs` pins that the
two predicates partition the cases, so a refusal is never ambiguous.

**The helper source hash did not move** — `DeviceUnderTest.swift` is in `RunControl/`, outside the
recipe — so 7d's four hardware gate results stand.

⚠️ **What this fix assumes, and chunk 3's re-walk must measure.** That the whole-disk event still
fires **while the claim is held**. 2026-09-05 measured disappearances with nothing claimed;
2026-09-08 saw only slices go. The inference is reasonable — the same channel delivered the slice
events under an active claim — but the whole of route (b) now rests on it, and if it is wrong a
*paused* run is blind, which is chunk 4's subject. A new reading was added to checklist chunk 3 and
it is taken before anything else there.

**Two readings the aborted walk produced anyway.** Item 11's two log lines are **not** either/or —
both fired, 3.5 s apart, and the item's wording is corrected. And 5.1's deadline: the helper was
inside `runRetentionCycle` for **6.67 s** and could not answer on that connection until it returned,
so the 3-second deadline expired. **The constant is shorter than one 8 MiB × 128-chunk call**, not
generous by three orders of magnitude as its own comment supposes.

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

- **Step 12 inherits the worst one, and chunks 1–6 have now closed it end to end:** a drive that
  drops off the bus was reported as a drive with ~2 million bad blocks. The engine no longer does
  this (chunk 1), route (b) covers a **paused** run where route (a) is blind (chunk 2), the ending
  travels on the wire (chunk 3, v15), both routes wind one run down exactly once (chunk 4), the
  report carries a four-case `DeviceLossAccount` that refuses to over-warn (chunk 5), and the one
  path that produced no message at all now raises an alert (chunk 6). **What remains is chunk 7:
  none of it has been confirmed against a real drive leaving a real port.** See
  [CONSTRAINTS.md](CONSTRAINTS.md), "Device loss".
  ⚠️ **This bullet said *"What remains: nothing acts on route (b) and the report has no device-loss
  verdict — chunks 4 and 5"* until 2026-09-07** — wrong from 2026-09-06, when both landed.
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
