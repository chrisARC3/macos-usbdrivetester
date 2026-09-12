# Build Progress Log — the step in progress

**This file holds the current step and nothing else.** It was 7,156 lines on 2026-08-11 and was
split, because a log a cold start is told not to read is a log that is not doing its job.

| where | what lives there |
|---|---|
| **PROGRESS.md** (this file) | the step in progress |
| **[CONSTRAINTS.md](CONSTRAINTS.md)** | **read this in full** — what binds future work: measured behaviour, settled decisions, lessons |
| **[BUILD-PLAN.md](BUILD-PLAN.md)** | the plan, the per-step gates, the process gotchas, the test hardware |
| [`progress/step-12.md`](progress/step-12.md) | **Step 12's full account, archived 2026-09-11** — nine chunks, the shipped defect its own checklist walk found, and the mutation survivor that fix created. Read it for *"why was it done that way?"*, not as current |
| [`progress/step-12-human-checklist.md`](progress/step-12-human-checklist.md) | Step 12's keyboard checks — five chunks, **all closed**, eight cable pulls on two drives. ⚠️ **Those passes do not transfer**: re-walk what later work touches |
| [`progress/step-11.md`](progress/step-11.md) | **Step 11's full account, archived 2026-09-05** — twelve increments, the defects each one found, and the reasoning |
| [`progress/step-11-increment-plans.md`](progress/step-11-increment-plans.md) | **the settled decisions from increments 9–12 — nothing is planned in it.** Deliberately not archived: some of it binds Steps 12 and 13. **Read before re-opening one of those decisions** |
| [`progress/step-11-human-checklist.md`](progress/step-11-human-checklist.md) | Step 11's keyboard checks — what no test can reach. **All 16 chunks passed.** ⚠️ **Those passes do not transfer**: re-walk what later work touches |
| `progress/step-NN.md` | archived history, for *"why was it done that way?"* |

**The full account of an increment goes in its commit message**, with this file carrying a summary
and the hash. Writing it twice at length produced two long prose accounts of one increment that
could drift; the commit is the immutable, greppable one.

---

## Step 13 — System-sleep prevention (NFR-REL-9). **NOT STARTED**

> **Cold start? Step 12 CLOSED 2026-09-11** — all four verification-gate items ticked in
> `BUILD-PLAN.md` against `7e51398`, app installed from `abc07e3`. Its full account is
> [`progress/step-12.md`](progress/step-12.md); **nothing in Step 13 has begun.** The suite is
> **1302 / 153 / 0**, floor **1302**. The protocol is **v15** and the helper source hash is
> **`e19b0b3c…`**, unmoved since chunk 7b on 2026-09-07.
>
> ⚠️ **Do not kickstart the helper.** BTM record #11 has pointed at **DerivedData** since a
> 2026-09-09 test run; the running daemon (pid 89541, started 2026-09-08 16:22:50) came from
> `/Applications` and is unaffected, but **the next kickstart would come up from DerivedData** with
> byte-identical binaries and a matching protocol saying nothing is wrong. The re-register command
> needs `sudo` and is in the checklist's Prerequisites — **hand it over, do not run it**. See
> `CONSTRAINTS.md` §1, *It does not stay fixed* and *The BTM record is keyed by bundle IDENTIFIER*.
>
> **Step 13 is small and is mostly a wiring question**, which is why it comes after Step 12 rather
> than before: it holds an idle-system-sleep assertion while `state == .running` and releases it on
> every exit from running — pause, stop, completion, failure **and device loss**. Step 12 is what
> made the last of those a real path with a real state machine behind it, so Step 13 has exactly one
> acquire/release site to wire rather than a branch per ending.

### Current state — 2026-09-11, at the close of Step 12, before Step 13 begins

| | |
|---|---|
| **Step 13** | **not started.** No code, no tests, no plan chunks. Its objective, four detailed steps, three gate items and its one named risk are in `BUILD-PLAN.md` — **read those before planning chunks**, and note that the risk (*a leaked assertion on an error path*) is the whole of why the plan says to route acquire and release exclusively through the Step 11 state machine |
| **Verified** | **1302 tests, 0 failures, 153 suites** (floor `scripts/.test-floor` = **1302**, ratcheted at Step 12 chunk 7h — the floor raises itself on a green run), run green **2026-09-11 16:29**, zero Swift warnings in the build and the test build. **13/13** gate clients type-check. ⚠️ `scripts/build-tools.sh` is what catches those: the app build does not compile `tools/`, so a new `RunController` parameter without a default breaks `ui-probe` and nothing else would find it — that happened at Step 12 chunk 6 |
| **Helper** | source hash **`e19b0b3c972d4b5bf9e052d087df231d34c8eee65aaddb9d772ce338db35edb9`**, unmoved since **2026-09-07** (Step 12 chunk 7b). **Re-derive it before trusting any hardware gate result** — `find USBDriveTester/com.arc3solutions.USBDriveTester.Helper USBDriveTester/USBDriveTester/Shared -name '*.swift' \| sort \| xargs cat \| shasum -a 256`. Step 13 is described as **GUI-side** in `BUILD-PLAN.md`, so it should not move the hash; if a chunk of it does, say so before writing the code, because **four hardware gates and the whole of Step 12's checklist are recorded against this hash** |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, **installed 2026-09-11 11:02:01** from `abc07e3`. Proved by content: `diff -rq` against DerivedData **0** differ, dylib **`c08f95ad…`** (re-checked 18:0x on 2026-09-11, unchanged), helper binary **`7590b920…`** byte-identical. Daemon **pid 89541**, uid 0, ppid 1, started **2026-09-08 16:22:50**, protocol **v15**, resolved from `/Applications`. ⚠️ **Grep `Contents/MacOS/USBDriveTester.debug.dylib`, never `Contents/MacOS/USBDriveTester`** — the latter is a 59 KB launcher stub and a content proof aimed at it returns 0 for everything, reading exactly like a failed install. ⚠️ **Prove an install by content, never by timestamp**, and take the DerivedData hash *after* the install: `install-app.sh` rebuilds through `build.sh` |
| **Owed, carried out of Step 12** | **(a) `RetentionTestEngine.classify`'s *"What remains open"* note is stale** — no short transfer, six of six, checklist 5.2 measured it 2026-09-09. It is **helper source**, so fixing it moves the hash and lapses four hardware gates for a comment. **User decision 2026-09-11: it waits for the next helper-source change.** Whichever chunk first touches `Helper/` or `Shared/` pays it. **(b) The build flavour is coverage-instrumented** — user decision 2026-09-11, left as is until the next helper-source change or Step 16, whichever comes first (`CONSTRAINTS.md` §1, *Every scheme build is coverage-instrumented*); **Step 16 must build without it**. **(c) Noticed, not changed:** `DeviceDiscovery.deselect()`'s doc and `DeviceDiscoveryTests.swift:205` still justify refusing a deselection during a run by *"the helper's claim follows the selection"* — a rule Step 11 increment 5 retired (`DeviceListView.swift`: *"The claim no longer follows the selection"*). The refusal may still be right; its stated reason is not, and naming the real one is a **design question**, not a comment fix. And `scripts/mount-change-test.sh:46` kills with `pkill -f`, the matcher `install-app.sh` and `lifecycle-check.sh` were both fixed away from on 2026-09-11 — it would also kill any process whose *arguments* carry the name |
| **No automated cover** | Four things, inherited and still true — they are in `progress/step-12-human-checklist.md`'s own list with what a person checks instead: `deviceUnderTest = nil` in `driveIsBack()`; the identity of the device-loss SF Symbol; **`RunControllerWiring`'s `onDeviceLost:` closure**, the composition root, where mutation m17 deletes the call and the whole suite passes; and **the device-loss alert itself**, which `render-ui.sh` cannot capture because an `.alert` takes its own window. **Step 13's assertion is likely to join this list** — `pmset -g assertions` is a system reading, not something a unit test can see — so plan its checklist alongside its code, not after |

### What Step 13 inherits from Step 12, in one paragraph

The run-control state machine is the thing Step 13 wires into, and Step 12 finished making it
honest. Every state change now logs — events through `RunController.report(_:)` and commands
through `apply(_:movingTo:)`, as `run control: A → B on the <Start|Pause|Resume|Stop> command` —
so an assertion that leaks will be diagnosable from the log rather than from a hunch, and all four
command labels were watched on hardware on 2026-09-11. There are **two** routes out of a run and
Step 13 must release on both: route (a), the helper's reply carrying the ending, and route (b), the
removal callback with a three-second wind-down behind it, which is the only route that can see a
drive unplugged **while paused** because a paused run issues no syscalls and so produces no `errno`.
`.finishing` and `.finished` both exist, and `deviceReleased` is what moves between them — if the
assertion is released on `.finished` alone, a run whose release is never confirmed
(`releaseCannotBeConfirmed`) would hold it forever, which is exactly the leaked-assertion risk
`BUILD-PLAN.md` names. Read `progress/step-12.md`'s chunk 4 section before choosing the release
site.

---

## Known loose ends carried into later steps

- ✅ **CLOSED 2026-09-11 — this was the worst one this project carried.** A drive that drops off
  the bus was reported as a drive with ~2 million bad blocks. The engine no longer does this
  (chunk 1), route (b) covers a **paused** run where route (a) is blind (chunk 2), the ending
  travels on the wire (chunk 3, v15), both routes wind one run down exactly once (chunk 4), the
  report carries a four-case `DeviceLossAccount` that refuses to over-warn (chunk 5), and the one
  path that produced no message at all now raises an alert (chunk 6). **Chunk 7 confirmed it
  against a real drive leaving a real port** — eight cable pulls on two drives, 2026-09-09 and
  2026-09-11, all four gate items ticked. See [CONSTRAINTS.md](CONSTRAINTS.md), "Device loss", and
  [`progress/step-12.md`](progress/step-12.md).
  ⚠️ **This bullet said *"What remains: nothing acts on route (b) and the report has no device-loss
  verdict — chunks 4 and 5"* until 2026-09-07** — wrong from 2026-09-06, when both landed. **And it
  said *"What remains is chunk 7: none of it has been confirmed against a real drive leaving a real
  port"* until 2026-09-11**, which was true when written and outlived its truth by two days: chunk
  3's six pulls landed on 2026-09-09. Twice now this one bullet has been the last place a retired
  claim survived, because it reads as background rather than as status. **It is status.**
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
