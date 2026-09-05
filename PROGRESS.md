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

## Step 12 — Device-loss handling (hot-unplug / de-enumeration mid-run). **NOT STARTED**

> **Cold start? This whole file is short on purpose — Step 12 has not begun.** Step 11 closed
> 2026-09-05 and its account was archived to [`progress/step-11.md`](progress/step-11.md) the same
> day. Nothing below is a snapshot; all of it is current as of **2026-09-05**.

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
| **Verified** | **1127 tests, 0 failures, 136 suites** (floor `scripts/.test-floor` = 1127), re-run green 2026-09-05. The build figures are **increment 12's gate, 2026-09-04**, not re-derived since: three clean builds with DerivedData wiped before each — `build.sh Debug`, `build.sh Release`, `test.sh` — **zero source warnings from all three**, 88 per-file `SwiftCompile` tasks Debug, 2 whole-module Release, 171 for the test target, **13/13** gate clients type-check |
| **Helper** | source hash **`e6888aa5af72b433cd5b33cf18b98a0bab5d330e1fb058277e23aae82813f627`**, unmoved since increment 11. **Re-derive it before trusting any hardware gate result below** — the recipe is `find USBDriveTester/com.arc3solutions.USBDriveTester.Helper USBDriveTester/USBDriveTester/Shared -name '*.swift' \| sort \| xargs cat \| shasum -a 256`. **Step 12 will move it**, and every gate result recorded against it lapses when it does |
| **Protocol** | **v14** |
| **Hardware gates** | **all four current.** `metrics-check.sh` **128/0**, `xpc-concurrency-check.sh` **0 failures**, `retention-cycle-check.sh` **15/15** over the whole device — all three 2026-09-03 at this helper hash. `run-control-check.sh` **14 assertions / 0 failures**, run **twice** on 2026-09-05 against the v14 daemon at this hash — the second with `--repeat-1mib 8`, which closed the settle measurement below. **Each one is invalidated by the next protocol bump or any move of the helper hash**, neither of which is announced — **and Step 12's chunk 1 moves the hash**, so all four lapse there by design |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, reinstalled 2026-09-04. ⚠️ **Always kickstart the daemon after `install-app.sh`** — it replaces the helper binary underneath the running one, and *nothing announces the mismatch when the helper source has not moved*. **Verify a reinstall took with `nm -U` on `Contents/MacOS/USBDriveTester.debug.dylib`**, not by timestamp: on 2026-09-04 a checklist chunk was nearly walked against a stale build |
| **Fixture** | 1 TB scratch T5, **serial `12345686DAA9`** (`disk7` on 2026-09-05 — BSD names move across a replug, so scripts resolve by serial). Its **`fill.bin` was restored 2026-09-04 18:19**: 999,947,239,424 bytes, volume 100% used, three samples digesting distinctly. **Invalidated by** unlinking the file or erasing the volume — **not** by `retention-cycle-check.sh` or `run-control-check.sh`, which write back exactly the bytes they read. Also attached as of 2026-09-04: the 4 TB T5 EVO (`disk6`) and the 125.8 MB UDisk thumb (`disk4`) |
| **Owed** | **Nothing.** Step 11 closed with every gate current and its checklist complete |
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
