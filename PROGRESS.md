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

## Step 13 — System-sleep prevention (NFR-REL-9). **IN PROGRESS — chunks 1–4 of 5 done**

> **Cold start? Step 12 CLOSED 2026-09-11** — all four verification-gate items ticked in
> `BUILD-PLAN.md` against `7e51398`, app installed from `abc07e3`. Its full account is
> [`progress/step-12.md`](progress/step-12.md); **Step 13 is planned in five chunks and chunk 1 —
> the instrument — chunk 2 — the rule and the seam — chunk 3 — the one acquire/release path — and
> chunk 4 — the mutation round and the human checklist — are done (chunks 1–3 on 2026-09-12,
> chunk 4 on 2026-09-13). What remains is chunk 5 alone: the hardware walk and the gate.** The
> walk is written and unwalked in
> [`progress/step-13-human-checklist.md`](progress/step-13-human-checklist.md), and its instrument
> is `scripts/sleep-assertion-watch.sh`. The suite is
> **1323 / 157 / 0**, floor **1323**. The protocol is **v15** and the helper source hash is
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

### Current state — 2026-09-13, Step 13 chunks 1–4 done

| | |
|---|---|
| **Step 13** | **in progress — five chunks, 1–4 done (1–3 on 2026-09-12, 4 on 2026-09-13).** (1) the instrument, ✅ done — `tools/sleep-assertion-probe` + `scripts/sleep-assertion-check.sh`, findings in `CONSTRAINTS.md` §1 *Idle-sleep assertions*; (2) the rule and the seam, ✅ done — `RunControlPolicy.preventsIdleSleep(in:)`, `IdleSleepPreventing` / `IdleSleepPreventer` in `RunControl/SleepPrevention.swift`, and `CountingIdleSleepPrevention` in the test target for chunk 3 to inject; (3) the one acquire/release path, ✅ done — `report(_:)` and `apply(_:movingTo:)` both go through a private `move(to:)`, the sole assignment to `state`, which asks the rule about the destination; init parameter `sleepPrevention` **with a default** (Step 12 chunk 6: one without a default breaks `ui-probe` and only `build-tools.sh` finds it), and **`RunControllerWiring` is deliberately unchanged** — the composition root has no automated cover (m17), so nothing there is required for the assertion to work; (4) mutation round + `progress/step-13-human-checklist.md`, ✅ done — **17 mutations, 13 killed, 4 survived, all four declared in advance**, no unexpected survivor and no inconclusive row; the checklist was written alongside the round rather than after it, so its items are built around measured holes; **`scripts/sleep-assertion-watch.sh` is new** — the gate asks a person to press Pause and then read `pmset`, which is a race they cannot win, so the walk gets a 4 Hz change-log instead; (5) hardware walk and the gate, **all that remains**. **No chunk touches `Helper/` or `Shared/`**, so the helper hash does not move and the four gates recorded against it do not lapse — owed items (a) and (b) therefore stay owed. Objective, four detailed steps, three gate items and the one named risk are in `BUILD-PLAN.md` |
| **Step 13's one scoping decision** | **The assertion is held while `state == .running` and in no other state — user decision 2026-09-12.** BUILD-PLAN says `Running`; NFR-REL-9 says *"actively executing"*, and `.pausing`/`.stopping` are states where the helper is still finishing a chunk (bounded by one call of at most `maximumBytesPerCall` = 1 GiB), so the two documents differ on two states. `.running` alone was chosen because pressing Pause or Stop is HID input, which resets the idle timer for the whole settle that press begins; because an item whose reading depends on *when* you look is a bad gate item; and because holding iff `.running` makes the release happen on the transition **out of** running — so `.finished` is never the release site and the leaked-assertion risk `BUILD-PLAN.md` names cannot reach it. The one exit with no HID input in front of it is device loss → `.finishing`, where the drive is already gone. ⚠️ **Corrected 2026-09-12 at chunk 3:** that risk was handed over named as `releaseCannotBeConfirmed`, and measurement says otherwise — *that* path reaches `.finished` synchronously. The state a run can sit in indefinitely is **`.finishing`**, by the opposite path: a release that can be confirmed and is never answered. See the annotation under *What Step 13 inherits* |
| **Verified** | **1323 tests, 0 failures, 157 suites** (floor `scripts/.test-floor` = **1323**, ratcheted at Step 13 chunk 3 — the floor raises itself), run green **2026-09-13 10:29**, zero Swift warnings in the build and the test build. **Chunk 4's mutation round ran the suite 17 more times** — every run complete at 1323, no incomplete run and no inconclusive row. **14/14** gate clients type-check. ⚠️ `scripts/build-tools.sh` is what catches those: the app build does not compile `tools/`, so a new `RunController` parameter without a default breaks `ui-probe` and nothing else would find it — that happened at Step 12 chunk 6 |
| **Helper** | source hash **`e19b0b3c972d4b5bf9e052d087df231d34c8eee65aaddb9d772ce338db35edb9`**, unmoved since **2026-09-07** (Step 12 chunk 7b). **Re-derive it before trusting any hardware gate result** — `find USBDriveTester/com.arc3solutions.USBDriveTester.Helper USBDriveTester/USBDriveTester/Shared -name '*.swift' \| sort \| xargs cat \| shasum -a 256`. Step 13 is described as **GUI-side** in `BUILD-PLAN.md`, so it should not move the hash; if a chunk of it does, say so before writing the code, because **four hardware gates and the whole of Step 12's checklist are recorded against this hash** |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, **installed 2026-09-11 11:02:01** from `abc07e3`. Proved by content: `diff -rq` against DerivedData **0** differ, dylib **`c08f95ad…`** (re-checked 18:0x on 2026-09-11, unchanged), helper binary **`7590b920…`** byte-identical. Daemon **pid 89541**, uid 0, ppid 1, started **2026-09-08 16:22:50**, protocol **v15**, resolved from `/Applications`. ⚠️ **Grep `Contents/MacOS/USBDriveTester.debug.dylib`, never `Contents/MacOS/USBDriveTester`** — the latter is a 59 KB launcher stub and a content proof aimed at it returns 0 for everything, reading exactly like a failed install. ⚠️ **Prove an install by content, never by timestamp**, and take the DerivedData hash *after* the install: `install-app.sh` rebuilds through `build.sh` |
| **Owed, carried out of Step 12** | **(a) `RetentionTestEngine.classify`'s *"What remains open"* note is stale** — no short transfer, six of six, checklist 5.2 measured it 2026-09-09. It is **helper source**, so fixing it moves the hash and lapses four hardware gates for a comment. **User decision 2026-09-11: it waits for the next helper-source change.** Whichever chunk first touches `Helper/` or `Shared/` pays it. **(b) The build flavour is coverage-instrumented** — user decision 2026-09-11, left as is until the next helper-source change or Step 16, whichever comes first (`CONSTRAINTS.md` §1, *Every scheme build is coverage-instrumented*); **Step 16 must build without it**. **(c) Noticed, not changed:** `DeviceDiscovery.deselect()`'s doc and `DeviceDiscoveryTests.swift:205` still justify refusing a deselection during a run by *"the helper's claim follows the selection"* — a rule Step 11 increment 5 retired (`DeviceListView.swift`: *"The claim no longer follows the selection"*). The refusal may still be right; its stated reason is not, and naming the real one is a **design question**, not a comment fix. And `scripts/mount-change-test.sh:46` kills with `pkill -f`, the matcher `install-app.sh` and `lifecycle-check.sh` were both fixed away from on 2026-09-11 — it would also kill any process whose *arguments* carry the name |
| **No automated cover** | Four things, inherited and still true — they are in `progress/step-12-human-checklist.md`'s own list with what a person checks instead: `deviceUnderTest = nil` in `driveIsBack()`; the identity of the device-loss SF Symbol; **`RunControllerWiring`'s `onDeviceLost:` closure**, the composition root, where mutation m17 deletes the call and the whole suite passes; and **the device-loss alert itself**, which `render-ui.sh` cannot capture because an `.alert` takes its own window. ✅ **Step 13's assertion joined this list on 2026-09-13, as predicted, and measurement says which half**: it is not the *decision* that has no cover but the **effect**. Mutation **m7** — delete `endActivity(token)`, keep `token = nil` — passes all 1323 tests, and that is NFR-REL-9's defect exactly; **m8** — hold the display-sleep assertion instead of the system one — passes all 1323 too. Both are in `progress/step-13-human-checklist.md`'s own list with the items that check them |

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

> ⚠️ **The last sentence but one is WRONG, and chunk 3 measured it so — 2026-09-12.** The risk is
> real and it is in the wrong place. A run that ends on the wind-down's deadline **does** reach
> `.finished`: `releaseTheDrive` issues the release it cannot wait for and then calls `driveIsBack`
> **synchronously** (`RunController.swift`, `if !canBeConfirmed { driveIsBack(…) }`), so
> `deviceReleased` is reported and the machine lands in `.finished` in the same turn.
> `aRunWhoseReleaseCannotBeConfirmedHasAlreadyReleasedTheAssertion` pins it.
>
> **The state that can be sat in indefinitely is `.finishing`, and by the opposite path**: a release
> that *can* be confirmed and is then never answered, where `driveIsBack` is only ever called from
> inside the completion. So a `.finished`-based rule would still leak — on a run the handoff did not
> name. Step 13 does not have the question either way, because the rule is *held only in
> `.running`*, and the release therefore happens on the way out of it.
>
> Kept as written above rather than rewritten, per this repository's rule: a dated claim corrected in
> place destroys the record of when it stopped being true. The error is instructive — it was reasoned
> from `releaseCannotBeConfirmed`'s name rather than read off the code path.
>
> ⚠️ **2026-09-13, chunk 4: the same claim was still standing in a third place** — the doc comment on
> `RunControlPolicy.preventsIdleSleep(in:)` itself, which is the most load-bearing home it has. Chunk
> 3 corrected this file and `SleepPreventionTests.swift` and did not grep for it in the source of the
> rule. **Eleventh lapse of this shape, second in two commits.** Annotated in place there too.

### Chunk 4 — the mutation round, and the two rows that justify a checklist

**17 mutations, 13 killed, 4 survived, every survivor declared in advance** (in the harness file,
before the first run), no unexpected survivor, no inconclusive row, and all seventeen runs complete
at 1323 tests.

**m7 is the result of this chunk.** Deleting `ProcessInfo.processInfo.endActivity(token)` from
`IdleSleepPreventer.end()` while keeping `token = nil` **passes all 1,323 tests**. That is NFR-REL-9's
defect exactly — the leaked assertion on an exit path, the one risk `BUILD-PLAN.md` names for this
step — and the suite cannot see it: `isHeld` reads the field rather than the OS, the counting double
never touches `ProcessInfo`, and no API asks whether a token is still active. **m8** is the same
shape: `.idleDisplaySleepDisabled` in place of `.idleSystemSleepDisabled` compiles, holds a token,
sets `isHeld`, increments the counter, passes everything — and keeps the screen awake for hours while
letting the machine sleep mid-write. Those two are the first two entries in the checklist's *"What
has no automated cover"* list.

The other two survivors are both declared holes of a familiar kind: **m11**, the `sleepLog.error`
text inside `begin()`'s guard, which no assertion should pin (contrast **m9**, `IdleSleepPreventer.reason`,
which *is* pinned by a test and dies — because a person is told to grep for that string in checklist
item 0.1); and **m17**, the gate's own probe in `tools/`, which the test target does not compile.

**The funnel held.** m14 and m15 put a bare `state = next` back on the command side and the event
side; both die, on `theAssertionFollowsTheStateThroughEveryTransition` among others. m13 — asking the
rule about the state being *left* rather than the destination — dies too. So the chunk 3 claim that a
third assignment to `state` fails in the suite rather than in `pmset` three weeks later is measured
rather than asserted.

**A new instrument, `scripts/sleep-assertion-watch.sh`.** The gate asks a person to press Pause and
then read `pmset`; release happens milliseconds after the press, and gate item 3 asks about a
*sequence* a later sample cannot see. The watcher polls at 4 Hz and prints a line on every change.
⚠️ **Its own smoke test found a defect in it before it ever saw the app**: pointed at `powerd` it
reported *"2 held — gate item 3 fails"* on a correct machine, because `powerd` holds an
`ExternalMedia` assertion beside its sleep one and the script was counting **lines**. This app mounts
and unmounts external media, so that false failure was waiting for the walk. It counts by **type**
now and still prints everything the pid owns.

**And one more instrument note, found while proving the checklist's own log predicate.** The unified
log cannot tell the app from the test host by process name — both are `USBDriveTester` — so
`scripts/test.sh` emits hundreds of genuine `run control: … → running` / `sleep prevention: holding …`
pairs. Observed at 09:59:42 on 2026-09-13, from this very round. Checklist item 2.2 says to match the
pid the watcher printed, and not to run the suite during a walk.

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
