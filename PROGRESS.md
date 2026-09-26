# Build Progress Log — the step in progress

**This file holds the current step and nothing else.** It was 7,156 lines on 2026-08-11 and was
split, because a log a cold start is told not to read is a log that is not doing its job.

| where | what lives there |
|---|---|
| **PROGRESS.md** (this file) | the step in progress |
| **[CONSTRAINTS.md](CONSTRAINTS.md)** | **read this in full** — what binds future work: measured behaviour, settled decisions, lessons |
| **[BUILD-PLAN.md](BUILD-PLAN.md)** | the plan, the per-step gates, the process gotchas, the test hardware |
| [`progress/step-12.md`](progress/step-12.md) | **Step 12's full account, archived 2026-09-11** — nine chunks, the shipped defect its own checklist walk found, and the mutation survivor that fix created. Read it for *"why was it done that way?"*, not as current |
| [`progress/step-12-human-checklist.md`](progress/step-12-human-checklist.md) | Step 12's keyboard checks — five chunks, **all closed**, eight cable pulls on two drives. ⚠️ **Those passes do not transfer**: re-walk what later work touches — and **chunks 1 and 2 are owed a re-walk on the Xcode 27 build** (user decision, 2026-09-19), **next** |
| [`progress/step-11.md`](progress/step-11.md) | **Step 11's full account, archived 2026-09-05** — twelve increments, the defects each one found, and the reasoning |
| [`progress/step-11-increment-plans.md`](progress/step-11-increment-plans.md) | **the settled decisions from increments 9–12 — nothing is planned in it.** Deliberately not archived: some of it binds Steps 12 and 13. **Read before re-opening one of those decisions** |
| [`progress/step-11-human-checklist.md`](progress/step-11-human-checklist.md) | Step 11's keyboard checks — what no test can reach. **All 16 chunks passed** on the Xcode 26 build. ⚠️ **Those passes do not transfer**: re-walk what later work touches — and on the Xcode 27 build **chunk 11's item 6 failed**, 2026-09-23, was fixed headlessly 2026-09-24, and **passed its re-walk 2026-09-25** on the build that carries the fix, with chunk 9's floor items 2, 3 and 6; **chunk 16 and item 6.3 passed theirs the same day**, so all four parts the move reopened are walked |
| `progress/step-NN.md` | archived history, for *"why was it done that way?"* |

**The full account of an increment goes in its commit message**, with this file carrying a summary
and the hash. Writing it twice at length produced two long prose accounts of one increment that
could drift; the commit is the immutable, greppable one.

---

## Step 13 — System-sleep prevention (NFR-REL-9). **IN PROGRESS — chunks 1–4 of 5 done; chunk 5's walk still paused, the move to Xcode 27 CLOSED 2026-09-19, Step 11's re-walks done 2026-09-25, Step 12's next**

> **Cold start? Step 12 CLOSED 2026-09-11** — all four verification-gate items ticked in
> `BUILD-PLAN.md` against `7e51398`, app installed from `abc07e3`. Its full account is
> [`progress/step-12.md`](progress/step-12.md); **Step 13 is planned in five chunks and chunk 1 —
> the instrument — chunk 2 — the rule and the seam — chunk 3 — the one acquire/release path — and
> chunk 4 — the mutation round and the human checklist — are done (chunks 1–3 on 2026-09-12,
> chunk 4 on 2026-09-13). What remains is chunk 5 alone: the hardware walk and the gate.** The
> walk is in [`progress/step-13-human-checklist.md`](progress/step-13-human-checklist.md) and its
> instrument is `scripts/sleep-assertion-watch.sh`: **item 0 passed 2026-09-13, and chunk 1 passed
> 2026-09-18 on its third walk** — the first could not show the reading its items asked for and the
> watcher was rewritten that morning; the second's paste ended before the selection. Chunk 2 was
> part-walked — 2.1–2.4 and 2.6 passed that afternoon — when the walk was **paused on 2026-09-18
> for the move to Xcode 27** (user decision; four chunks and a fifth, 4b — chunk 1 closed that day,
> chunks 2, 3, **4 and 4b all closed on 2026-09-19**: the four hardware gates passed against the
> Xcode 27 helper, 80 renders are whole, and `window-fit-check.sh`, whose probe had stopped
> measuring on Xcode 27 / macOS 27, was fixed that evening and **measures 613 pt again**, the same
> figure as on Xcode 26.6 *(614 since item 6's fix, 2026-09-24)* — *The move to Xcode 27*, below.
> **Nothing of the move is open.**)
> Chunk 3 installed the Xcode 27 build, and **every pass the walk had made lapsed with that
> install**. Item 0 was re-run against the new build that morning and passed *(and lapsed
> 2026-09-24 18:01:53, at the install of item 6's fix — below)*. **Then come the
> re-walks** of Step 11 and 12 items the user chose on 2026-09-19 — they need a person at the
> keyboard — and then the walk restarts at item 0, re-checked, then chunk 1. ✅ **Step 11's chunk 9
> walked 2026-09-21/22 and passed**, and the shipped window agrees with the gate's 613 pt to 2 pt.
> ❌ **Its chunk 11 was walked 2026-09-23 and did not pass**: ten of eleven items pass, and **item 6
> failed** — below about 600 pt the report sheet overhangs the main window, by 20 pt at the idle
> floor. 🔧 **Item 6 was diagnosed and fixed headlessly on 2026-09-24** (`77275be`): the window
> could be dragged 46–57 pt below the height its content fits, and now it cannot — its minimum is
> 600 pt with two or more drives and 614 while a run starts. NFR-USE-9 holds to 1280x800 alone
> from the same day. **The fix lapsed chunk 9's pass and chunk 11's ten by their own clauses.**
> ✅ **Re-walked 2026-09-25 on the build that carries it** — installed 2026-09-24 18:01:53 and
> proved by content, its binary's floor reading 104 (*Installed app*, below): **item 6 and chunk
> 9's items 2, 3 and 6 passed**, the items the user chose. The window stops at 600 pt with six
> drives and with two and at 588 with one, is pushed to 614 at Start and holds 615 while a run is
> on, and the report sheet sits 24 pt inside it at every size taken (*The re-walk of 2026-09-25*,
> below). **The running 615 is the spec since the same day**, by user decision; the gate still
> reads the probe's 614. ✅ **Chunk 16 and item 6.3 were walked the same day and PASSED**, on the
> same build — all nine of chunk 16's items, and 6.3 in its hardest form and its standard one
> (*The walk of chunk 16 and item 6.3*, below). **Step 12's chunks 1–2 are left unwalked, and
> are next**, with the user's go. The walk left **four findings**, none of them in the app's
> behaviour — *Owed* (h)–(k), below — **decided by the user 2026-09-26**: (h) and (i), in app
> source, wait for changes that pay their costs anyway, and (j) and (k), in the checklist, are fixed.
> The suite is **1323 / 157 / 0 on Xcode 27.0**, green again 2026-09-24 on the fix's tree, and
> 2026-09-19 against `d1ac7a6` with zero Swift warnings — once chunk 2's one warning was fixed in
> the test target — floor **1323**. The protocol
> is **v15** and the helper source hash is **`e19b0b3c…`**, unmoved since chunk 7b on 2026-09-07
> (re-derived 2026-09-19).
>
> ⚠️ **The daemon was kickstarted 2026-09-19 10:32:47 and came up from `/Applications`** — pid
> **95762**, running the installed Xcode 27 helper `ac4d5208…`, protocol v15. That was the move's
> chunk 3: launching the installed app moved BTM record #11 back from DerivedData at 10:27:22, the
> user's `sfltool dumpbtm` confirmed it at 10:27:44, and the user's kickstart relaunched the daemon
> through it — both `sudo`, both handed over, never run from here. Readings in the checklist's
> *The daemon*. Before it, pid 46679 ran the Xcode 26 helper `7590b920…` from `/Applications`, from
> a kickstart of 2026-09-18 13:06:19 that ended **Xcode 27's build out of DerivedData** (pid 12059,
> helper `32a647da…`), which had come up after the reboot into macOS 27.0 on 2026-09-16: a reboot is
> a kickstart nobody typed. **Running the test suite or the project from Xcode pulls the record back
> to DerivedData, and the next relaunch of the daemon follows it** — `CONSTRAINTS.md` §1, *A reboot
> is a kickstart nobody typed*. That keeps both out of the walk. **The record is on `/Applications`
> now**; after anything that runs the app from DerivedData, read it again before any kickstart, and
> treat a reboot as one. *(2026-09-24: **not now** — item 6's test runs moved it to DerivedData at
> 13:44:34.894, by BTM's own log. The daemon is still pid 95762 from `/Applications`, and launching
> the installed app moves the record back.)* *(2026-09-25: **now again** — the user's launch of the
> installed app moved it back at 02:56:15.630. The user's restart at 12:13 that day ended pid 95762;
> the daemon since 12:19:03 is **pid 1477**, from `/Applications` through that record — the same
> helper `ac4d5208…`, protocol v15, so no gate lapses with the pid.)* *(That evening chunk 16's
> item 3 switched the helper off in Login Items: launchd removed the service at 20:11:51.970, ending
> pid 1477, and re-enabled it at 20:12:19.998 when it was switched back on. The daemon since
> 20:12:28 is **pid 14761**, started on demand and resolved by `xpcproxy` to `/Applications` — the
> same helper, protocol v15.)*
>
> ⚠️ **Xcode 27.0 replaced Xcode 26.6 at the pinned path on 2026-09-15**, so any build or test run
> from here on is an Xcode 27 build. **Its project edits were settled 2026-09-18**, in the move's
> chunk 1: three taken, and its removal of `ARCHS = arm64` refused — measured, it makes Release
> builds universal. The per-user scheme-order file it kept rewriting is no longer tracked. See the
> *Toolchain* row below.
>
> **Step 13 is small and is mostly a wiring question**, which is why it comes after Step 12 rather
> than before: it holds an idle-system-sleep assertion while `state == .running` and releases it on
> every exit from running — pause, stop, completion, failure **and device loss**. Step 12 is what
> made the last of those a real path with a real state machine behind it, so Step 13 has exactly one
> acquire/release site to wire rather than a branch per ending.

### Current state — 2026-09-25, Step 13 chunks 1–4 done; the move to Xcode 27 closed, Step 11's re-walks done, Step 12's next

| | |
|---|---|
| **Now: the move to Xcode 27** | **Four chunks from 2026-09-18, user decision, and a fifth, 4b, from chunk 4's finding — ✅ ALL FIVE CLOSED 2026-09-19. What the move still owes is keyboard work: Step 12's re-walks — Step 11's four are walked, the last two on 2026-09-25.** (1) the project file, ✅ **closed 2026-09-18** — `b8015c7`, `14d2f79`; (2) build and test headless, ✅ **closed 2026-09-19** — clean Debug and Release builds 2026-09-18 against `d2950cf`, the clean test run and `build-tools.sh` 2026-09-19 against `d1ac7a6`, everything as expected once the test build's one Swift warning was fixed in the test target (`c47cbe7`, `d1ac7a6`); (3) install and kickstart, ✅ **closed 2026-09-19** — the Xcode 27 build installed 10:22:50 and proved by content, BTM's record back on `/Applications` at 10:27:22, the daemon kickstarted at 10:32:47 and resolved from `/Applications` as pid 95762; `install-app.sh`'s stale-daemon warning had been dying of SIGPIPE since 2026-09-11 and was fixed first (`ba97c0e`); (4) the hardware gates, `render-ui.sh` and `window-fit-check.sh`, ✅ **closed 2026-09-19 by 4b, after six hours open** — all four gates passed against pid 95762 and `ac4d5208…`, 80 renders of 80 are whole, and `window-fit-check.sh` was **INCONCLUSIVE**: its probe's measurement returned 1 pt for every state on Xcode 27 / macOS 27, so it reported the declared minimum, 556 pt, where its last conclusive run said 613 — **556 was never adopted**. Chunk 4's **two smaller findings are fixed** in `e144510` — three Swift 6 warnings in `run-control-probe`, and the case list's fourth drift — and `build-tools.sh` shows warnings now; (4b) the probe fix, ✅ **closed 2026-09-19, `d98b658`** — `.minSize` in the probe's own `sizingOptions` was putting the minimum back after the search cleared it (tested, where chunk 4 had inferred it), and `subviews.first` was a 24 pt focus proxy, which is the half that mattered; the fixed probe measures the **tallest** subview, reports `UNMEASURABLE(<why>)` when it cannot answer, the gate gained **exit 2, INCONCLUSIVE** on two independent detectors, and the re-run measures **613 pt** — the 2026-09-03 figure exactly. Four mutations, two killed and two survivors declared in advance; and `build-tools.sh` now fails unless the probe's `switch`, its own *unknown view* message and `render-ui.sh`'s list name the same **40** cases, with three negative controls behind it. **Then come the Step 11 and 12 re-walks the user chose on 2026-09-19** — keyboard work. ✅ **Step 11's chunk 9 — the window's size, and 4b's calibration against the real window — walked 2026-09-21/22 and PASSED**: the shipped window agrees with the probe to 2 pt (pushed to **615** at Start against 613), the probe's two numbers turn out to answer two different questions, `.defaultSize` sizes the frame rather than the content on macOS 27, and one unreproduced observation is open — the bottom edge refusing to shrink the window. Its record is *Chunk 9's calibration*, below. ❌ **Step 11's chunk 11 — the report as a sheet — walked 2026-09-23 and NOT PASSED**: ten of eleven items pass, and **item 6 failed**. Below about 600 pt the sheet is taller than the window leaves room for, and at the 542 pt idle floor it hangs **20 pt below the window**. It was owed (user decision), together with one observation for the same diagnosis: at a run's finish the window is pushed from 557 to 615 pt. Its record is *Chunk 11's walk*, below. 🔧 **Item 6 diagnosed and fixed headlessly 2026-09-24, `77275be`** (user decisions that day: diagnose item 6 first, then *"proceed with both recommendations"* — NFR-USE-9 held to 1280x800 alone, and the window's minimum raised to what its content measures). The window could be dragged 46–57 pt below the height its content fits, and the sheet copies the content's height; `WindowMetrics.deviceListFloor` goes 46 → 104, capped at the list's own height, and `window-fit-check.sh` now fails a state whose declared minimum is below its measured one. Its record is *Item 6's diagnosis and fix*, below. **It lapsed chunk 9's pass and chunk 11's ten.** ✅ **Installed 2026-09-24 18:01:53 and proved by content** — the binary's `deviceListFloor` reads 104 — which lapses Step 13's item 0 as well, by its own first clause (*Installed app*). ✅ **Re-walked on that build 2026-09-25 and PASSED — item 6, and chunk 9's floor items 2, 3 and 6** (user decision: *"re-walk 11.6, 9.2, 9.3 and 9.6"*): 600 pt idle with six drives and with two, 588 with one, pushed to 614 at Start and 615 while running, the sheet 24 pt inside the window at every size taken. The running floor's 615, 1 pt over the gate's 614, is **the spec since the same day** (user decision: *"Change the running height spec from 614 to 615"*). Its record is *The re-walk of 2026-09-25*, below. ✅ **Chunk 16 and item 6.3 walked the same day on the same build and PASSED** — all nine items, and 6.3 in both forms (*The walk of chunk 16 and item 6.3*, below). **Next: Step 12's chunks 1–2**, before Step 13's walk restarts at item 0. Each chunk is reported before the next starts, and the next needs the user's go. **The four findings the walk reported were decided by the user 2026-09-26** — (h) and (i) wait, and (j) and (k) are fixed in the checklist (*Owed* (h)–(k)). **Step 12's chunk 1 installs a temporary debug hook to `/Applications`, then reverts it and reinstalls ship code** (`progress/step-12-human-checklist.md`, chunk 1), so its plan settles one question first, with the user: whether a reinstall whose three hashes match *Installed app*'s leaves standing the passes recorded against the 2026-09-24 18:01:53 install — Step 11's four re-walks among them — or lapses them by their *another install* clause. The app and helper sources are unchanged since `77275be`: every commit after it is docs or `claude-md-test/` (read 2026-09-26 at `d1691ae`, and again at `caa7386`). ✅ **BTM record #11 is on `/Applications` again since 2026-09-25 02:56:15.630**, moved back by the user's launch of the installed app, as predicted (BTM's log, `process == "backgroundtaskmanagementd"`); item 6's test runs had moved it to DerivedData at 2026-09-24 13:44:34.894, and the install had not moved it back. **The daemon is pid 14761 since 2026-09-25 20:12:28**, from `/Applications` through that record, started on demand after chunk 16's item 3 switched the helper off and on in Login Items. That ended pid 1477 at 20:11:51.970, which had run since 12:19:03, after the user's restart at 12:13 ended pid 95762. The same helper `ac4d5208…`, protocol v15, throughout. Anything that runs the app from DerivedData moves the record again: read it before any kickstart, and treat a reboot as one. What each chunk must show is in *The move to Xcode 27*, below |
| **Step 13** | **in progress — five chunks, 1–4 done (1–3 on 2026-09-12, 4 on 2026-09-13).** (1) the instrument, ✅ done — `tools/sleep-assertion-probe` + `scripts/sleep-assertion-check.sh`, findings in `CONSTRAINTS.md` §1 *Idle-sleep assertions*; (2) the rule and the seam, ✅ done — `RunControlPolicy.preventsIdleSleep(in:)`, `IdleSleepPreventing` / `IdleSleepPreventer` in `RunControl/SleepPrevention.swift`, and `CountingIdleSleepPrevention` in the test target for chunk 3 to inject; (3) the one acquire/release path, ✅ done — `report(_:)` and `apply(_:movingTo:)` both go through a private `move(to:)`, the sole assignment to `state`, which asks the rule about the destination; init parameter `sleepPrevention` **with a default** (Step 12 chunk 6: one without a default breaks `ui-probe` and only `build-tools.sh` finds it), and **`RunControllerWiring` is deliberately unchanged** — the composition root has no automated cover (m17), so nothing there is required for the assertion to work; (4) mutation round + `progress/step-13-human-checklist.md`, ✅ done — **17 mutations, 13 killed, 4 survived, all four declared in advance**, no unexpected survivor and no inconclusive row; the checklist was written alongside the round rather than after it, so its items are built around measured holes; **`scripts/sleep-assertion-watch.sh` is new** — the gate asks a person to press Pause and then read `pmset`, which is a race they cannot win, so the walk gets a 4 Hz change-log instead; (5) hardware walk and the gate, **paused 2026-09-18 for the move to Xcode 27** — item 0 passed 2026-09-13, its daemon row lapsed 2026-09-16 and was restored by the kickstart at 2026-09-18 13:06:19; chunk 1 passed 2026-09-18 14:47–14:53 on its third walk (the first could not show its reading and the watcher was rewritten; the second's paste stopped short of the selection); chunk 2 part-walked 15:04–15:07 (2.1–2.4 and 2.6 passed; 2.5 was a cycle short, and its threshold, one short since it was written, is corrected). The walk restarts at item 0 after the Step 11 and 12 re-walks (user decision 2026-09-19; the move's chunk 4b closed that evening, so the re-walks are all that stand in front of it); every pass here was a fact about the Xcode 26 build `af09416` and **lapsed at the Xcode 27 install, 2026-09-19** — item 0 was re-run against the new one that morning and passed, and **lapsed again 2026-09-24 18:01:53** at the install of Step 11's item 6 fix, by its own first clause (*another install*). Chunk 3 of the walk gained item 3.7 that day, which carries Step 12's cable-pull items. **No chunk touches `Helper/` or `Shared/`**, so the helper hash does not move and the four gates recorded against it do not lapse — owed items (a) and (b) therefore stay owed. ⚠️ **From 2026-09-16 until the kickstart at 2026-09-18 13:06:19 the running daemon was an Xcode 27 build no gate had run against; then the installed Xcode 26 helper, `7590b920…`; and since the kickstart at 2026-09-19 10:32:47 the installed Xcode 27 helper, `ac4d5208…`, which all four gates passed against that day (the move's chunk 4)** — see *Installed app*. Objective, four detailed steps, three gate items and the one named risk are in `BUILD-PLAN.md` |
| **Step 13's one scoping decision** | **The assertion is held while `state == .running` and in no other state — user decision 2026-09-12.** BUILD-PLAN says `Running`; NFR-REL-9 says *"actively executing"*, and `.pausing`/`.stopping` are states where the helper is still finishing a chunk (bounded by one call of at most `maximumBytesPerCall` = 1 GiB), so the two documents differ on two states. `.running` alone was chosen because pressing Pause or Stop is HID input, which resets the idle timer for the whole settle that press begins; because an item whose reading depends on *when* you look is a bad gate item; and because holding iff `.running` makes the release happen on the transition **out of** running — so `.finished` is never the release site and the leaked-assertion risk `BUILD-PLAN.md` names cannot reach it. The one exit with no HID input in front of it is device loss → `.finishing`, where the drive is already gone. ⚠️ **Corrected 2026-09-12 at chunk 3:** that risk was handed over named as `releaseCannotBeConfirmed`, and measurement says otherwise — *that* path reaches `.finished` synchronously. The state a run can sit in indefinitely is **`.finishing`**, by the opposite path: a release that can be confirmed and is never answered. See the annotation under *What Step 13 inherits* |
| **Verified** | **1323 tests, 0 failures, 157 suites** (floor `scripts/.test-floor` = **1323**, ratcheted at Step 13 chunk 3 — the floor raises itself), run green **2026-09-24 14:04–14:05 against item 6's fix** — the sources `77275be` commits, checked unchanged by content from before the run to the commit but for one comment in `window-fit-check.sh`, after which that gate ran green again — with **Xcode 27.0 (27A266a) on macOS 27.0 (26A428)** and zero Swift warnings. On the same sources: `window-fit-check.sh` exit 0, declared equal to measured in all 14 rows, worst case **614**; `build-tools.sh` 14/14, 0 warnings, the case list agreeing at 40; 80 renders of 80 and 7 more at the new floors, none failed. A change to any source, the project file, Xcode or macOS invalidates it. Before that: green **2026-09-19 09:23–09:24 against `d1ac7a6`**, DerivedData wiped first and the count read from the xcresult, with **zero Swift warnings** in that test build and in the clean Debug and Release builds of 2026-09-18 against `d2950cf` — `d1ac7a6` differs from it by one test file (the move's chunk 2, below); and green 2026-09-13 10:29 with Xcode 26.6 on macOS 26. **`test.sh` raises the floor only on a green run since 2026-09-18**; until then the raise came before the failure check, so a red run could raise it (seven cases, old script against new, with a stand-in `xcodebuild`: only *red with a higher count* differs). **Chunk 4's mutation round ran the suite 17 more times** — every run complete at 1323, no incomplete run and no inconclusive row. **14/14** gate clients type-check with **0 warnings**, and the **case list agrees three ways at 40 cases** (2026-09-19 19:26:20–19:26:44 against the committed tree, v15; a change under `tools/` or to the protocol invalidates it — the 19:04:40 run said the same before the last doc-comment edits, and the 14:11:53–14:12:18 run against `e144510`'s tree said it for the warnings half) — and **`build-tools.sh` shows warnings since `e144510` and checks the case list since chunk 4b**: until then it deleted each log unread, three warnings sat in `run-control-probe` unseen, and the list had drifted four times. ⚠️ `scripts/build-tools.sh` is what catches those: the app build does not compile `tools/`, so a new `RunController` parameter without a default breaks `ui-probe` and nothing else would find it — that happened at Step 12 chunk 6 |
| **Helper** | source hash **`e19b0b3c972d4b5bf9e052d087df231d34c8eee65aaddb9d772ce338db35edb9`**, unmoved since **2026-09-07** (Step 12 chunk 7b; re-derived 2026-09-19 at `d1ac7a6` and again at the move's chunk 3, and 2026-09-24 on item 6's fix, which touches neither `Helper/` nor `Shared/`). **Re-derive it before trusting any hardware gate result** — `find USBDriveTester/com.arc3solutions.USBDriveTester.Helper USBDriveTester/USBDriveTester/Shared -name '*.swift' \| sort \| xargs cat \| shasum -a 256`. Step 13 is described as **GUI-side** in `BUILD-PLAN.md`, so it should not move the hash; if a chunk of it does, say so before writing the code, because **four hardware gates and the whole of Step 12's checklist are recorded against this hash**. ⚠️ **A new toolchain moves the helper binary and leaves this hash where it is** — the four gates had run against binaries Xcode 26.6 built, so the move to Xcode 27's chunk 4 re-ran them against the installed Xcode 27 helper `ac4d5208…`, daemon pid 95762: **all four passed, 2026-09-19** (*The move to Xcode 27*, below). Another helper binary lapses them again, with this hash unmoved |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, **installed 2026-09-24 18:01:53** from **`77275be`**'s sources — Step 11's item 6 fix — built with **Xcode 27.0** (`27A266a`) on macOS 27.0 (26A428). **Proved by content, 18:02–18:05:** the binary's `WindowMetrics.deviceListFloor` reads **104.0** out of `__TEXT,__const`, where `bcde5f5`'s source says 46, and its seven other `WindowMetrics` constants read what their source says, which is the control; checklist item 0.1 greps **1**; `diff -rq` against the build products taken after the install, **0** of 10 files differ; dylib **`e6e6e884…`** (was `422c89d3…`), launcher stub `bf787e19…` (was `48212035…`), helper binary **`ac4d5208…`**, unchanged; `codesign --verify --deep --strict` OK. The install's build took five seconds and compiled nothing — the newest object is 14:04:27, from the verification run, and all 51 app-target objects are younger than their sources. **The helper is unchanged, so no kickstart is owed**: the daemon was pid **95762**, resolved by `xpcproxy` to `/Applications` after the user's kickstart of 2026-09-19 10:32:47, protocol v15 off its own start line, until the user restarted the Mac on 2026-09-25 at 12:13; from 12:19:03 it was pid 1477, from `/Applications`, until chunk 16's item 3 switched the helper off in Login Items at 20:11:51.970; since 20:12:28 it is pid **14761**, resolved by `xpcproxy` to `/Applications`, protocol v15. ✅ BTM record #11 is back on `/Applications` since 2026-09-25 02:56:15.630 (the *Now* row). **Re-hashed 2026-09-25**, at 02:58, again after the restart, and again after chunk 16's walk: dylib `e6e6e884…`, stub `bf787e19…`, helper `ac4d5208…` — the bytes proved above, and what that day's re-walks ran against. **And 2026-09-26 at 16:03, before Step 12:** the same three hashes; the daemon still pid 14761, whose resolve line at 20:12:28.515 is the only one since 20:10 and names `/Applications`; and no record move in BTM's log since 20:10 — a query that could not be re-proved on a known line that day, because the one known move (02:56:15.630) had aged out: the log held BTM's lines back to 2026-09-25 09:13:09 only. ⚠️ **`xcodebuild` from a plain shell is CommandLineTools'**: at this install `-showBuildSettings` printed nothing, so the first `diff -rq` compared an empty path, failed on stderr and counted **0** — a broken instrument reading exactly like a proof. Set `DEVELOPER_DIR` as the scripts do, and check that the directory exists before trusting a zero. **Before it:** installed 2026-09-19 10:22:50 (the move to Xcode 27's chunk 3) from `bcde5f5`'s sources with Xcode 27.0 — dylib `422c89d3…`, launcher stub `48212035…`, the same helper — byte-identical to the 09:46:27 install that morning, whose script died before its warning (`ba97c0e`); that dylib was the 09:23 test build's code, re-signed at 09:46:29 by the install's build, and the helper is the binary the move's chunk 2 built, signed 09:23:51. Before that: installed 2026-09-13 10:51 from `af09416` with Xcode 26.6 — dylib `a8a0e932…`, helper `7590b920…` — and run by pid 46679 from the kickstart of 2026-09-18 13:06:19 until 2026-09-19's; from the macOS 27.0 reboot until that kickstart the daemon was pid 12059 from **DerivedData**, helper `32a647da…` (cold start, above). ⚠️ This row still named `abc07e3` until 2026-09-18 — `f7e2ff3`, the install's own commit, edited only the checklist (*Chunk 5*, below). ⚠️ **Grep `Contents/MacOS/USBDriveTester.debug.dylib`, never `Contents/MacOS/USBDriveTester`** — the latter is a 59 KB launcher stub and a content proof aimed at it returns 0 for everything, reading exactly like a failed install. ⚠️ **Prove an install by content, never by timestamp**, and take the DerivedData hash *after* the install: `install-app.sh` rebuilds through `build.sh`, which on 2026-09-19 re-signed a test build's products, so the dylib hash read before that install named a file that was gone after it. `ditto` carries the bundle's birth time over, so no bundle date is an install time |
| **Toolchain** | **Xcode 27.0 (27A266a) since 2026-09-15**, installed over Xcode **26.6** at the pinned `/Applications/Development/Xcode.app`; **macOS 27.0 (26A428) since 2026-09-16**. Every build, test run and gate result recorded before 2026-09-18 was made with Xcode 26 on macOS 26 — including the app installed until 2026-09-19, which nothing on this machine can now rebuild byte for byte; the one installed since is Xcode 27's (`DTXcode 2700`). ⚠️ **26.6, not 26.5:** these notes said 26.5 from 2026-08-06, which is the SDK's version (`macosx26.5`), not Xcode's — the app installed until 2026-09-19 recorded `DTXcode 2660`, the project was created with tools 26.6 on 2026-07-25, and `CONSTRAINTS.md` §1 says *"Measured with Xcode 26.6"*. Corrected 2026-09-18 where the text describes the present; the archives keep what they said. **Xcode 27's project edits, settled 2026-09-18** (user decision; the move's chunk 1): taken — `LastUpgradeCheck` 2660 → 2700, `DEAD_CODE_STRIPPING = YES` on every target, `STRING_CATALOG_GENERATE_SYMBOLS = YES` (inert: the project has no string catalogs); **refused — its removal of `ARCHS = arm64`**, because without it Xcode 27's `-showBuildSettings` resolves Release to **`arm64 x86_64`** (the macOS 27 SDK still lists `x86_64`), while Debug stays `arm64` through `ONLY_ACTIVE_ARCH`, so no Debug build or test run would have shown it. Restored, every target resolves to `arm64` in both configurations — and the binaries agree: the move's chunk 2 found `lipo -archs` printing `arm64` alone for the Release app and its helper, 2026-09-18. The `orderHint` churn is gone at its source: `xcschememanagement.plist` is per-user state that `.gitignore` already excluded, committed before the rule and now untracked — and there are no shared schemes to lose, since both schemes are Xcode's automatic ones. Measured behaviour re-checked on macOS 27 so far: *Idle-sleep assertions*, 0 failures, and BTM's record-and-resolve behaviour, 2026-09-18 (`CONSTRAINTS.md` §1); the four hardware gates, all passing, and 80 renders, 2026-09-19. **And one instrument that stopped measuring on it, fixed the same day**: `ui-probe --limits` returned 1 pt for every state, because `.minSize` in its own `sizingOptions` re-imposed the minimum its search had cleared and `rootView.subviews.first` is a 24 pt focus proxy here — the move's chunk 4b tested both, measured the tallest subview instead and taught the gate to say INCONCLUSIVE, and `window-fit-check.sh` measures **613 pt** again, 2026-09-19 19:26 (`CONSTRAINTS.md` §1, *The instrument*) — **614** since 2026-09-24, when `deviceListFloor` went to the table's own 104 (*Item 6's diagnosis and fix*) |
| **Model** | **Claude Opus 5.5 since 2026-09-23** — first on `4d6f07e`'s trailer, 11:30; before it **Opus 5** co-authored 168 commits, 2026-07-27 to 2026-09-23 09:44, every change to `CLAUDE.md` among them. **Prompt audit for 5.5: `a063b9d`, 2026-09-24**, checked against `b708e4e` — the claude-api skill's *prompt-audit* over `CLAUDE.md`, the documents it sends a session to, and the auto-memory. Seven findings adopted (F1–F7, user decision 2026-09-24); two low-confidence flags stay flags. Two claims had been false since the day they were written, and both are corrected: `CLAUDE.md`'s *"Four files name the current step"* (three), and `BUILD-PLAN.md`'s *"`grep -n "protocol is v"` … finds both"* (there are three blocks, and it finds one), annotated rather than rewritten. `CLAUDE.md` went from 147 lines to 125, its lapse list now five rules under *How to grep*. Documentation only: the helper hash is `e19b0b3c…` at `a063b9d`, re-derived 2026-09-24, and no pass lapses. The full account is `a063b9d`'s message. **The behavioural test the audit asked for before relying on F4 ran 2026-09-24, 12:03–12:34**: nine sandboxed headless sessions, three per arm — `claude-opus-5-5`, effort high, CLI 2.1.280 — each given the same staged report of a walk that never happened, in a copy of `b708e4e` that differs only in `CLAUDE.md`: A, the old file (`0358966c…`); B, F4 alone (`cf99a090…`); C, as committed (`4a6ee92d…`). **What F4 had to keep, it kept**: every run of every arm retired all four false claims and dated all five places that record the walk, and B and C ran no fewer wide greps before their last edit. **One difference the test was not built to find**: `BUILD-PLAN.md`'s undated *"16 chunks, nothing owed"*, stale since 2026-09-19 and not named in the request, got a dated correction in **3 of 3 A runs, 0 of 3 B and 1 of 3 C** — read by hand; the declared scorer saw one. Three runs an arm is suggestive, not proof. **Acted on by user decision 2026-09-24**: the two `BUILD-PLAN.md` incidents F4 had removed, the sixth and the twelfth, are back in `CLAUDE.md` under *One file can hold several status blocks*. F5 and F6 were measured only inside the committed file. *What would invalidate it:* an edit to `CLAUDE.md` after `a063b9d`, or a different model, effort or CLI version — **and the first has happened**: the file as it now stands — the incidents back, and since 2026-09-24 a note that `claude-md-test/` holds a test's fixtures (`5fef44a6…`, 132 lines) — is none of the three arms. It is arm D, declared 2026-09-24 with its predictions before any session ran on it (`6993096`). **Its three sessions ran 18:14–18:16 and answered nothing: none recorded the walk.** Two found that the installed app was no longer the build the staged request names, and stopped to ask: `68bc16c`'s install at 18:01:53 had replaced the dylib, which hashes to `e6e6e884…` where the copies' records, which stop at `b708e4e`, name `422c89d3…`. The third stopped to ask about the daemon's pid. The declared scorer reads 0/6, 0/3 and X1 0/3 in all three (`claude-md-test/results/2026-09-24-D/`), which says only that nothing was written. So the file as it stands is still unmeasured, and this machine cannot run the test as designed until `/Applications` holds the build the request names. The first run's per-run figures are in `c8ac81e`'s message and in `claude-md-test/results/2026-09-24/`, with the raw outputs since `ed38490`. The harness is in `claude-md-test/`, moved there 2026-09-24 from a session scratchpad; its README says how to re-run it and what a re-run inherits, the installed app included. A change of model re-opens the audit |
| **Owed** | *(a)–(c) are carried out of Step 12; (d) is from the move to Xcode 27; (e) is from Step 11's chunk 9 re-walk, 2026-09-22; (f) is from its chunk 11 re-walk, 2026-09-23; (g) from the re-walk of 2026-09-25; (h)–(k) from the walk of chunk 16 and item 6.3 the same day, decided by the user 2026-09-26: (h) and (i) wait, (j) and (k) are paid.* **(a) `RetentionTestEngine.classify`'s *"What remains open"* note is stale** — no short transfer, six of six, checklist 5.2 measured it 2026-09-09. It is **helper source**, so fixing it moves the hash and lapses four hardware gates for a comment. **User decision 2026-09-11: it waits for the next helper-source change.** Whichever chunk first touches `Helper/` or `Shared/` pays it. **(b) The build flavour is coverage-instrumented** — user decision 2026-09-11, left as is until the next helper-source change or Step 16, whichever comes first (`CONSTRAINTS.md` §1, *Every scheme build is coverage-instrumented*); **Step 16 must build without it**. **(c) Noticed, not changed:** `DeviceDiscovery.deselect()`'s doc and `DeviceDiscoveryTests.swift:205` still justify refusing a deselection during a run by *"the helper's claim follows the selection"* — a rule Step 11 increment 5 retired (`DeviceListView.swift`: *"The claim no longer follows the selection"*). The refusal may still be right; its stated reason is not, and naming the real one is a **design question**, not a comment fix. And `scripts/mount-change-test.sh:46` kills with `pkill -f`, the matcher `install-app.sh` and `lifecycle-check.sh` were both fixed away from on 2026-09-11 — it would also kill any process whose *arguments* carry the name. **(d) Stale counts and line citations in app-source comments, noticed 2026-09-19 at chunk 4 and not changed** — app source, so a fix moves the Verified row and the installed build for a comment: `USBDriveTesterApp.swift:112–113` places the three harnesses' exclusion of that file at `render-ui.sh:201`, `window-fit-check.sh:144` and `build-tools.sh:62`; and `DeviceUnderTest.swift:93` says `build-tools.sh` type-checks *"thirteen clients"*, fourteen since 2026-09-12. ⚠️ **Chunk 4b moved two of those three lines the same evening** — the exclusions are now at `render-ui.sh:244` (the case-list sentinels went in above it), `window-fit-check.sh:159` (the exit-2 header) and `build-tools.sh:63`, so the one number chunk 4 recorded as *right* was right for six hours. **A line number in a comment is invalidated by any edit to the file it cites**, and no grep of this repository will catch it; when this item is paid, cite the exclusion **by name and rule**, not by line. Whichever chunk next touches app source pays it. ✅ **Paid 2026-09-24** by item 6's fix, `77275be`: the exclusions are cited by the basename they skip, with a dated note that they were once cited by line, and the client count by what `build-tools.sh` prints, with *thirteen* dated. ⚠️ **(e) `WindowMetrics.swift`'s header has been stale since 2026-08-22 — found 2026-09-22 by chunk 9's walk, not changed.** It states the enforced minimum as *"531–542 pt of content … a 563–574 pt window"* and *"the `starting` state is the tallest at **638**"*; 638 was superseded by **613** the day the refusal lines were deleted, and nothing read that header again for a month. On macOS 27 it is wrong a second way — the floors are 510 and 524 pt of content, 542 and 557 pt of frame. **The file's own point is that those are observations and not assertions**, which is exactly why they need a date and have never had one. App source, so a comment fix moves the Verified row and the installed build: **it waits with (a) and (d)**, and the measured figures live in `progress/step-11-human-checklist.md`'s chunk 9 box meanwhile. ✅ **Paid 2026-09-24** by item 6's fix: the header gives the minimum as measured that day — 556 pt of content with one drive, 568 with two or more, 582 while a run starts — dated and with its instrument named, and its 2026-08-20 correction is annotated for the Xcode 27 build. ❌ **(f) Step 11 chunk 11's item 6 FAILED on the Xcode 27 build — found 2026-09-23, not diagnosed.** Below about 600 pt the report sheet is taller than `ContentView.reportSheetSize` should make it. At the 542 pt idle floor it is **616 × 530**, where the window's content gives 616 × 486, and it hangs **20 pt below the main window**. At 580 it is 15 pt too tall and still inside. At 600 and above it is exact, however the window got there. For the same diagnosis (user decision): **at a run's finish the window is pushed from 557 to 615 pt**, which no walk had seen before. Three app-source comments state the premise the measurement breaks, and are left as they are: `reportSheetSize`'s *"it can never exceed a screen the window itself fits"*, `WindowMetrics.reportSheetMargin`'s, in the same words, and `RunReportView.swift`'s header, *"this view's floor **is** the main window's floor"*. Two tools comments lean on it, also left as they are. `ui-probe`'s `RunReportHost` says *"the report is always laid out at a size imposed on it"*, and `render-ui.sh`'s header says that for that reason *"these renders show what a user sees"*. Both are still true of the render. But below 600 pt, a render at the size the window predicts is not the size a user sees. **Diagnosis first, headless, with the user's go.** A fix is app source, so it moves the Verified row and the installed build — and it would be the next chunk to touch app source, the one (d) and (e) are waiting for. Chunk 11 stays on the re-walk list for item 6 alone until then. 🔧 **Fixed 2026-09-24, not re-walked** (`77275be`): diagnosed headlessly the same day, and the five premise comments carry dated notes rather than being left — *Item 6's diagnosis and fix*, below. It stayed owed until item 6 was walked on the build that carries the fix: ✅ **discharged 2026-09-25**, when it was, and passed — the sheet 24 pt inside the window at every size taken, 588 to 1304 pt (*The re-walk of 2026-09-25*, below). The push at a run's finish stayed open — on this build the window can no longer be below 615 when a run ends, so it cannot be seen; inferred, not tested — until ✅ **closed 2026-09-25 by user decision**: *"Let's close the push at the end of the run issue."* **(g) `ContentView.swift`'s `reportSheetSize` comment is stale**: it ends *"Item 6's re-walk is what confirms it on a real window"*, and the re-walk did, on 2026-09-25. It is app source, and an edit to a view source lapses that re-walk's passes. **User decision 2026-09-25:** *"Leave comment as is unless we make changes to this file in the future"* — it waits for the next change that edits `ContentView.swift`, which corrects it, the way (a) waits for the helper. **(h) The live metrics panel's 1 Hz poll logs two error lines a second while the helper is unreachable** — found 2026-09-25 under Step 11's chunk 16 item 3, with the helper switched off in Login Items: `helper progress connection invalidated` and `helper transport error` (`HelperConnection.swift:439` and `:784`), 11 of each in ten seconds. `LiveRunMetricsPanel` keeps its last snapshot on a failure, so nothing on screen changes. Logging only; the log holds nothing older than 2026-09-23 17:52, so whether earlier builds did the same cannot be read *(by the code they did, found 2026-09-26: both lines date from Step 3 and Step 9, `6d4b4bd` and `c6ec234`, and the panel is pinned in the main window and polls whenever the window is up — so every first launch before the helper is approved logs them too)*. **User decision 2026-09-26: it waits for the next app-source change**, whichever that is, in the shape agreed that day — on the progress connection only, the first failure of a streak logged at error, the repeats silent, and one notice with the count when progress answers again, the rule a small pure type with tests. Not a poll that stops while the gate is up: that edits a view, ties NFR-PERF-5's poll to the gate, and covers the gate alone. **(i) `HelperAvailability.swift`'s header (lines 48–51) is stale**: it says the gate *"fires at launch and never again"* and that nothing *"re-diagnoses on activation"*, and `8b0db53` added the re-check on activation on 2026-08-31 — item 3's log shows it working. A comment only. ⚠️ **The same claim is written twice** — found 2026-09-26: `AppModel.swift`'s doc comment on `refreshHelperAvailability()` (lines 370–375 at `caa7386`) says it is called *"once from the scene's `onAppear`, and thereafter only by `performHelperGateAction(_:)`"* and that nothing re-diagnoses on activation, while `HelperAvailability.swift:328` and `USBDriveTesterApp.swift` describe the re-check correctly. What the header calls load-bearing still holds: the trigger is guarded on the gate being up, so it can clear the gate and never raise it. **User decision 2026-09-26: (g)'s rule** — both comments wait for the next edit to either file, and that commit fixes both; one fixed alone would leave the pair disagreeing. **(j) The Step 11 checklist's chunk 16 heading said *"item 4 needs a run; the rest are dry"***, and items 5, 6 and 7 each need a run that writes. An instrument defect. ✅ **Paid 2026-09-26** (user decision): the heading reworded, the old wording quoted in a dated note under it. **The same fault, found that day:** the checklist's *Running it* said *"Only 2, 4, 5, 6, 7, 8 and 14 start a run"* — its wording of 2026-09-02, when chunks 9, 11 and 12 already existed — and 9, 11, 12, 15 and 16 start runs too; corrected in the same commit, the old wording quoted. **(k) Item 6.3's *"EFI not mounted"* cannot be observed on the 125.8 MB thumb**, which has no EFI partition; the 1 TB scratch T5 has one, and 6.3's standard form ran there on 2026-09-25 to observe it. An instrument defect. ✅ **Paid 2026-09-26** (user decision): 6.3 carries a dated note that its EFI half needs the scratch T5, so a full 6.3 is its hardest form on the thumb and its standard form on the scratch T5, as walked 2026-09-25. No other EFI check in the three checklists has this mismatch. All four are recorded in *The walk of chunk 16 and item 6.3*, below, and in the Step 11 checklist's chunk 16 box. (h) and (i) are app source outside the helper-hash set: a fix moves the Verified row and the installed build, and lapses the passes recorded against that build, but no hardware gate — which is why both wait for a change that pays those costs anyway. |
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

### Chunk 5 — the walk, paused 2026-09-18 for the move to Xcode 27

**Item 0 passed 2026-09-13** (`f7e2ff3`): the app installed from `af09416`, proved by content on
the dylib.

**2026-09-16 moved the machine under it.** macOS 27.0 installed and rebooted at 10:38:53, and at
17:28:36 Xcode 27 ran the project; the first launch of the daemon after the reboot resolved through
BTM record #11, which had been on DerivedData since 2026-09-09. So item 0's daemon row lapsed and
the instrument's 2026-09-13 run lapsed with the OS. The instrument was re-run on macOS 27.0 on
2026-09-18: **0 failures**, every finding unchanged.

**Chunk 1's first walk, 2026-09-18, is not a pass, and the defects were both in the instrument.**
The watcher printed *held* only in a header, so item 1.1's `held 0` was on no line; item 1.2's
`| head -12` printed the summary and cut off the owner it asked for. The watcher now carries its
reading on every line (`pid N  held N  …`), names the executable of every new pid from the kernel,
prints a heartbeat so a transcript shows it was watching during an event that changes nothing, and
prints `held ?` rather than a number it did not read when two copies are running. Tested against
`powerd`, Finder, a name not running and a disposable binary relaunched and run twice at once, with
the summary on SIGTERM. *(A copy of `/bin/sleep` cannot stand in for that binary: Apple's platform
binaries are killed at exec when run from another path — status 137.)*

**Which copy of the app ran chunk 1 was first answered wrongly, from the log.** `log show`'s
`processImagePath` named a DerivedData folder that no longer exists; the same lines'
`processImageUUID` is the installed stub's, and BTM resolved the process to `/Applications`. That
went into `CONSTRAINTS.md` §1, and it is why the watcher now names the executable itself.

**Twelfth and thirteenth lapses of the status-block rule, both committed 2026-09-13 and found
2026-09-18.** *Twelfth*: chunk 4's `af09416` updated `BUILD-PLAN.md`'s lower status block and not its
top one, which went on naming Step 13's done chunks as 1, 2 and 3 — the sixth lapse's shape exactly;
the grep was for the sentence being added, and the top block words the chunks differently. *Thirteenth*:
chunk 5's `f7e2ff3` installed a new build and edited only the checklist, so this file's *Installed
app* row went on naming `abc07e3`. An install retires the old build's hash everywhere it is named as
current, and **`git grep abc07e3` would have found the row**.

**The daemon is back on the installed helper — kickstarted 2026-09-18 13:06:19.** The user's
`sfltool dumpbtm` at 12:57 had record #11 on `/Applications` and no record on DerivedData; the
user's kickstart then resolved **to program: `/Applications/…`**, pid 46679, helper `7590b920…`.
*(Until 2026-09-19, when the Xcode 27 install left it running the previous helper and a kickstart
at 10:32:47 replaced it with pid 95762 — the move's chunk 3, below.)* Two instrument findings came with it, both in `CONSTRAINTS.md` §1. The checklist's pass condition
for the record named BTM's **log** form, `file:///Applications/USBDriveTester.app/`, where the dump
prints a bare path — read literally, it fails a correct record. And on macOS 27.0 `log show`
matches its own invocation line unless the predicate names the process, so a check for absence
prints one line when there is nothing; the checklist's resolve-line recipe now names `xpcproxy`,
checked against known lines.

**Chunk 1 passed 2026-09-18 14:47:50–14:53:41, on its third walk**, against the installed `af09416`
app (pid 54729, `exe` under `/Applications`) with the watcher from `a32001e`: `held 0` at rest, the
scratch T5 selected at 14:48:25 and a heartbeat after it, and a summary of `most at once held 0`.
Item 1.2 was read headless during the walk, and says so. The second walk, at 13:23, had been copied
before the selection's heartbeat and before Ctrl-C, so it showed too little. **Three instructions
were corrected by walking them**: 1.3 now asks for a heartbeat printed *after* the click, and says
the summary exists only after Ctrl-C; 1.2 no longer says *"two lines come back"*, because other
system services hold the same assertion type for seconds or minutes at a time; and 1.1 and 2.1 now
say that the app selects a drive by itself at launch, which on this machine is the 22 TB Seagate.

**Chunk 2's first walk, 15:04–15:07, passed 2.1–2.4 and 2.6 and did two of 2.5's three
pause/resume cycles** — on the scratch T5 by serial, against the same app (pid 54729) and daemon
(pid 46679) as chunk 1. The assertion was taken on entry to `running`, released in the same
millisecond as each Pause and 2 ms after Stop, taken again on each Resume, and never held twice.
**2.5's pass condition had been one short since it was written:** *"a `changes` count of at least
7"* forgot that the watcher counts its own first line, so Start, two cycles and Stop also make 7,
and this walk met it with a cycle missing. It now reads the three Resume lines in the log against
the `held 1` lines in the transcript, because no count of the watcher's lines can be made exact.
2.5, 2.7 and 2.8 were owed — and then the walk was paused, below.

**2026-09-19: every pass above lapsed at the Xcode 27 install** — the move's chunk 3, below. Item 0
was re-run against the new install that morning and passed: item 0.1 greps 1, dylib `422c89d3…`,
helper `ac4d5208…`, daemon pid 95762 from `/Applications`, and the instrument's 2026-09-18 run
stands, since only a macOS update lapses it. Chunks 1 and 2 are owed in full. The walk restarts
after the Step 11 and 12 re-walks the user chose that day, below. *(This said "after the move's
chunk 4" until chunk 4 found the window-fit probe broken, and "after the move's chunk 4b" until 4b
fixed it — all three on 2026-09-19.)*

### The move to Xcode 27 — pauses Step 13's walk, from 2026-09-18

**User decision 2026-09-18: move now, and re-walk Step 13 from item 0 on the Xcode 27 build**, rather
than finish the walk on the Xcode 26 build first. The walk's cheap part was done (chunk 1 and half
of chunk 2) and its expensive part was not (2.7's full run, chunk 3's cable pulls). An install
invalidates the checklist's passes, so finishing first would have meant walking the expensive items
twice, and the Xcode 26 build is a dead end: nothing on this machine can rebuild it. Four chunks,
each approved before it starts: **(1)** the project file; **(2)** build and test with Xcode 27,
DerivedData wiped before each of `build.sh Debug`, `build.sh Release` and `test.sh`; **(3)** install,
proved by content, and a kickstart; **(4)** the four hardware gates on the 1 TB scratch T5, plus
`render-ui.sh` and `window-fit-check.sh`, since a new SDK can move SwiftUI layout. Xcode 27's own
Debug build on 2026-09-16 compiled the app and helper with zero Swift warnings (its build log, read
2026-09-18), so no source change was expected; the test target had not been built with it. **When
chunk 2 built it, it had one warning**, and the fix was a test-target change (below).

**Chunk 1, the project file — 2026-09-18.** Xcode 27's three harmless edits taken, its removal of
`ARCHS = arm64` refused on a measurement (*Toolchain*, above), the per-user scheme-order file
untracked, and `test.sh` made to raise the floor only on a green run — shown by running the old and
new script through seven cases with a stand-in `xcodebuild`: only *red with a higher count* differs,
and the old one raised the floor on it. No source changed, so the helper source hash does not move.
**Closed 2026-09-18 15:58, against `b8015c7`:** the user opened the project in Xcode 27.0 and quit,
with no build, no Run and no prompt. `project.pbxproj` came back byte-identical (`08e715de…`) and
`git status` was clean. The only file written in the bundle was `UserInterfaceState.xcuserstate`,
which is per-user and ignored. Nothing was built or run: no app or helper log line since 15:47, the
DerivedData app unchanged since 2026-09-16, and the daemon still pid 46679. **A different Xcode
version invalidates this**; the check is `git status` after opening the project.

**Chunk 2, build and test headless — CLOSED 2026-09-19.** No GUI, no drive, no `sudo`. The method
is BUILD-PLAN's *Verifying a step*: DerivedData wiped before each of `scripts/build.sh Debug`,
`scripts/build.sh Release` and `scripts/test.sh` — the scripts use the default location,
`~/Library/Developer/Xcode/DerivedData/USBDriveTester-*` — and `scripts/build-tools.sh` after them.
What had to come out:

- **zero Swift warnings** in all three builds. The 2026-09-16 Debug build had none; a new one comes
  from the new compiler, and is read and reported before any source is changed. Grep for warnings
  **naming a `.swift` file** (`CONSTRAINTS.md` §2): that log's one bare `warning:` was
  `appintentsmetadataprocessor`'s *"Metadata extraction skipped, no AppIntents.framework dependency
  found"*, Xcode 27's wording of the known line that is not a source warning;
- **every project source compiled**, in Debug and in Release — count the sources, not the tasks;
- **a Release app that is arm64 only**: `lipo -archs` on each Mach-O in its `Contents/MacOS` — the
  executable and the embedded helper — prints `arm64` alone. That is what chunk 1's `ARCHS`
  decision is for, and no Debug build can show it;
- **14/14** gate clients from `build-tools.sh`;
- **1323 tests, 157 suites, 0 failures**, read from the xcresult, with `scripts/.test-floor` read
  before the run. **Any other count is a finding, not a new floor**: no test changed, so a different
  total means the toolchain runs or counts something differently. `test.sh` writes a higher count
  itself on a green run, so a raise has to be explained before it is kept;
- **no link failure in the test target.** Chunk 1 took `DEAD_CODE_STRIPPING = YES`; a test reaching
  a symbol the app itself never uses is the first suspect if one appears, and what to do about it
  is the user's decision, not a revert on the spot.

**What came out** — Xcode 27.0 (27A266a) on macOS 27.0 (26A428), DerivedData wiped before each:

- **`build.sh Debug` and `build.sh Release`, 2026-09-18 16:26 and 16:27, against `d2950cf`:**
  exit 0, **71 of 71** sources each, **zero Swift warnings** — each log's one `warning:` line is
  the AppIntents one. Release is **`arm64` alone** by `lipo -archs` on both Mach-Os in
  `Contents/MacOS`, the only two in the bundle, and carries `__llvm_prf_cnts` in both: the
  instrumentation `CONSTRAINTS.md` §1 had only inferred for Release.
- **`test.sh`, 2026-09-18 16:29, against `d2950cf`:** 1323 / 157 / 0 and no link failure — and
  **one Swift warning**, the finding: `AppModelReportTests.swift:76`, the fixture calling
  `RunReport`'s main-actor initializer from a nonisolated context. Chunk 2 stopped on it. No source
  had changed since the last zero-warning test build (2026-09-13, Xcode 26.6); why Swift 6.4 flags
  the call is not established. Fixed in the test target by user decision: `c47cbe7`, which did not
  compile — a default argument is checked as nonisolated — and `d1ac7a6`. Neither `build.sh` build
  compiles that file, so the Debug and Release results stand for `d1ac7a6`.
- **`test.sh`, 2026-09-19 09:23:42–09:24:52, against `d1ac7a6`:** **1323 tests, 0 failed, 0
  skipped** from the xcresult and **157 suites** from Swift Testing's summary; floor read first,
  **1323**, unchanged after. **134 of 134** sources, **zero Swift warnings**, no link failure.
- **`build-tools.sh`, 2026-09-19 09:25, against `d1ac7a6`:** **14 of 14** gate clients type-check
  against v15. It prints `ok` and nothing else for a tool that passes, so it says nothing about
  warnings in `tools/`. *(2026-09-19: chunk 4 found three, in `run-control-probe`, and `e144510`
  fixed them and made the script show warnings — see chunk 4.)*

A change to any source, the project file, Xcode or macOS invalidates these. The helper source hash
is unmoved, `e19b0b3c…`; the helper *binary* is Xcode 27's, which is why chunk 4 re-ran the
hardware gates.

⚠️ **The test run points BTM record #11 at DerivedData**, as every test run does. The daemon — pid
46679 from `/Applications` when chunk 1 closed, 2026-09-18 15:59 — will not feel it, but **any
relaunch would**: a reboot, a crash or a kickstart. So none until chunk 3, which puts the record
back. Read the pid before chunk 2 starts; if it has changed, something relaunched the daemon.
**As it went:** the 2026-09-18 run moved the record at 16:29:45. A wipe must not delete the bundle
the record names, so the re-run waited for the user to launch the installed app, which moved it
back at 2026-09-19 08:54:06; the build that failed moved nothing; the green run moved it again at
**09:24:02**, where it stayed until chunk 3, below. **The daemon was pid 46679, started 2026-09-18 13:06:19,
throughout**, and `xpcproxy` logged no resolve from 2026-09-18 16:00 on.

**Chunk 3, install and kickstart — CLOSED 2026-09-19.** What had to come out: an install proved
by content — item 0.1's grep of `Contents/MacOS/USBDriveTester.debug.dylib`, `diff -rq` against
the build products taken *after* the install, and the helper binary's hash — then the user
launching the installed app, which moves BTM's record back, and running the kickstart
`install-app.sh` prints, `sudo` and handed over; the `xpcproxy` resolve line must then name
`/Applications`. The full account is in `ba97c0e` and this chunk's closing commit.

- **The install at 09:46:27, from `bcde5f5`, exited 141** after installing and before the
  stale-daemon warning that was due. Its daemon lookup piped `ps` into `awk '{…; exit}'` under
  `pipefail`, and `ps` died of SIGPIPE — 97 runs in 100, broken since `63a7ae2` (2026-09-11). A
  finding; the chunk stopped on it, and by user decision the script was fixed first, while the
  stale daemon was still there to prove the fix against: **`ba97c0e`** captures `ps` and reads it
  from a here-string, and **its own run at 10:22:50 exited 0 and printed the warning** for pid
  46679. Nothing recorded rested on the silence: the two installs in between, 2026-09-11
  (`abc07e3`) and 2026-09-13 (`af09416`), each settled *"no kickstart owed"* from a byte-identical
  helper binary, not from the script's output. `BUILD-PLAN.md`'s *"Use `grep -m1`"* was wrong the
  same way — 50 of 50 exit 141 from a pipe — and is corrected.
- **Both installs proved by content, and byte-identical:** item 0.1 greps **1**, `diff -rq` **0**
  differ, dylib `422c89d3…` (was `a8a0e932…`), helper `ac4d5208…` (was `7590b920…`), `DTXcode 2700`
  / `27A266a`, `codesign --verify --deep --strict` OK. The 09:46 build compiled and linked nothing:
  the installed dylib is the 09:23 test build's code under a new signature, which is why the proof
  is against the products taken after the install.
- **The record:** the user launched the installed app, and BTM moved record #11 from DerivedData to
  `/Applications` at **10:27:22.666**. The user's `sfltool dumpbtm` at 10:27:44 had #11 on
  `/Applications/USBDriveTester.app`, generation `…605896`, and no line naming DerivedData.
- **The kickstart**, run by the user: `xpcproxy[95762]` at **10:32:47.800** resolved **to program:
  `/Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper`** — pid
  **95762**, root, ppid 1, the helper at that path `ac4d5208…`, protocol **v15** off its own start
  line.

The old build is retired wherever it was named as current, and every pass the Step 13 walk had
made lapsed with the install. Item 0 was re-run against the new one and passed (the checklist). The
helper source hash is unmoved, `e19b0b3c…`, and the suite was not re-run: no app or test source
changed, and a run would have moved the record back. *What would invalidate this:* another install,
or a relaunch of the daemon after something has moved the record — a test run or an Xcode run of
the project moves it, and a crash, a kickstart or a reboot relaunches.

**Chunk 4, re-verify — CLOSED 2026-09-19 by chunk 4b, below.** It was open for six hours, on the
window-fit probe alone. What had to
come out: the four hardware gates on the 1 TB scratch T5 only — found by serial `12345686DAA9` on
the day, because its `diskN` moves, and never the 22 TB Seagate — with the counts they reported
2026-09-07 against `e19b0b3c…` and protocol v15 (`progress/step-12.md`'s table), now against pid
95762 and the Xcode 27 helper `ac4d5208…`; then `render-ui.sh` and `window-fit-check.sh`, because a
new SDK can move SwiftUI layout. Those two compile the app's view sources with `tools/ui-probe` by
`swiftc` into `/tmp`, with no app bundle, and nothing had measured whether that touches BTM record
#11 — so BTM's log was read afterwards, before anything could relaunch the daemon. The full account
is in this chunk's commit.

**What came out**, 2026-09-19 — the scratch T5 as `disk8`, resolved by serial through
`scripts/lib/device-identity.sh`; daemon pid **95762** throughout, helper `ac4d5208…`, source hash
`e19b0b3c…`, protocol **v15**:

| Gate | Ran | Result | 2026-09-07, the Xcode 26.6 helper |
|---|---|---|---|
| `metrics-check.sh` | 10:55:44–10:56:21 | **128 assertions / 0 failures**, host overhead 2.423% | 128 / 0, 2.377% |
| `xpc-concurrency-check.sh` | 10:56:49–10:56:58 | **0 failures** — same connection serialized, second connection concurrent, worst reply 9.4 ms | 0, worst 6.0 ms |
| `retention-cycle-check.sh` | 10:57:12–12:26:00 | **15 checks / 0 failures** — 932 window fingerprints unchanged after writing 1,072,693,248 B at block 311,984,128 | 15 / 0, 932 |
| `run-control-check.sh` | 12:26:41–12:26:59 | **14 assertions / 0 failures**, `RESULT: pre-flight PASSED` | 14 / 0 |

- **All four passed**: every one exited 0, none exited 141, and each asserted the daemon's protocol
  itself — v15, four times. (`progress/step-12.md` says three of the four assert it. That was a
  miscount: all four have since August, and it is annotated there.) The 14 is counted inside
  `---- assertions ----`, as the record counts it; the whole log has 16, as it did on 2026-09-07.
  The two figures that moved are timings, not counts: the overhead is asserted under 5%, and the
  worst concurrent reply has no bound — what the gate asserts, serialized on one connection and
  concurrent on a second, is unchanged. The scratch volume remounted after each gate; the
  retention gate is what says its bytes survived.
- **Renders: 80 of 80**, every probe case in both appearances, plus `content` and
  `content-running` with six drives. None failed and none is blank: every one has at least 178
  distinct colours (`metrics-finished-dark`). `render-ui.sh` ran once, exit 0, to build the probe
  (`6c22d1f7…`), and that binary rendered the rest with the script's arguments. Nine were read by
  eye — `content` in both appearances, `content-starting` in both, `content-running`, six-drive
  `content`, `metrics-finished`, `report-device-lost` and `helper-gate-busy` — and nothing in them
  is broken; disabled controls still read as disabled in light and dark.
- **`window-fit-check.sh`, 12:27:54–12:28:29: INCONCLUSIVE.** It exited 0 and printed *"every
  state fits"*, with a worst case of **556 pt** (`content-starting`), where its last conclusive run
  said **613 pt** — 2026-09-03 at `05b7ea7`, Step 11 increment 11, Xcode 26.6 on macOS 26. **556 is
  not adopted.** `--limits` reports the larger of the declared minimum and a measured one
  (`CONSTRAINTS.md` §1, *The instrument*), and the measured half came back `overflowAt=1` in all 14
  rows, so the gate printed the declared minimum plus the 32 pt title bar: the number that section
  records as 58 pt short. Renders agree. At the declared heights — `content` at 510, and
  `content-starting` at 524 with one drive and with six — the list header is clipped; at 567 and
  581 it is whole. The layout is not shown to have moved. The instrument stopped measuring.
  ✅ **Chunk 4b fixed it the same day and the gate measures again — 613 pt, the same figure as
  2026-09-03**, and the 581 the renders showed whole is exactly what the fixed probe reports for
  that state at six drives. **556 was never adopted anywhere.**
- **Why, measured with a scratch copy of the probe:** two breaks, each enough alone *(⚠️ wrong, and chunk 4b's matrix refuted it the same evening: break (1) alone gives `overflowAt=24`, and break (2) alone gives the **right** answer, 570 — only the subview break was load-bearing. This was an inference written in the voice of a measurement)*. Asked for
  1 pt, the window comes back **524** tall: the function clears `contentMinSize`, and something
  puts it back — it reads 524 at the first test. The probe's own `sizingOptions`, which include
  `.minSize`, are the likely culprit, inferred and not yet tested *(⚠️ chunk 4b **tested** it that
  evening: drop `.minSize` and the same ask of 1 pt returns 1 pt with `contentMinSize` reading 0.
  The inference was right, and it was also the half that did not matter — see the matrix below)*.
  And the view it measures,
  `rootView.subviews.first`, is now a **24 pt `KeyViewProxy`**, the first of **11** subviews, not
  the content. macOS 27 cannot be told apart from the 27 SDK: Xcode 26.6 is gone from this
  machine.
- ✅ **Chunk 4b fixed the probe that evening and this chunk closed with it** — measure the tallest
  subview rather than the first, stop the minimum being put back during the search, and have the
  gate refuse to answer instead of printing a declared minimum as a fit. It re-ran and got **613**,
  as expected. Its own record is *Chunk 4b*, below. ✅ **Step 11's chunk 9 re-walked it at the
  keyboard on 2026-09-21/22 and the shipped window agrees to 2 pt** — pushed to **615** at Start
  against the probe's 613 — *and* found that the probe reports two quantities where the gate keeps
  one. See *Chunk 9's calibration*, below.
- **Two smaller findings, fixed the same day in `e144510`** (user decision):
  `tools/run-control-probe` compiled with **three Swift 6 warnings** — `main.swift:125`, `:156` and
  `:168`, *"concurrently-executed global function … must be marked as '@Sendable'"* — which
  `run-control-check.sh` prints and `build-tools.sh` never showed, since it deleted each log unread
  on success; whether Xcode 26.6 printed them is unknowable now. And the case list **drifted a
  fourth time**: the probe's *"unknown view"* message named 37 of its 40 cases, missing the three
  `report-device-lost*` added 2026-09-06 (`4b72d13`), and `render-ui.sh` said *"37 cases"* twice,
  though its list has named all 40 since `2086090` (2026-09-09).
  **Fixed:** `build-tools.sh` now shows, counts and names warnings and does not fail on them,
  **proved on the unfixed probe first** — 3 warnings, at those three lines, at 14:01:41 — then 0
  after the three functions were marked `@Sendable`. `run-control-check.sh` re-ran 14:03:29–14:03:48
  against pid 95762, the scratch T5 as `disk8` by serial: exit 0, **14 / 0** inside the block (16
  in the whole log), `RESULT: pre-flight PASSED`, and no warning in its build. The probe's message
  names all 40, checked by running it on an unknown view and diffing the names against its switch
  and `render-ui.sh`'s list — all three agree. The counts are corrected to 40 in `render-ui.sh` and
  README and annotated where they are history — two sites in `CONSTRAINTS.md` §1, one in §2, and one
  in Step 11's checklist — and the fourth drift is written into `render-ui.sh`'s drift history and
  into the §1 lesson that predicted it. `build-tools.sh`
  against the final tree, 14:11:53–14:12:18: **14 type-checked, 0 warnings**. `tools/` and
  `scripts/` are outside the helper source hash and the Xcode project, so the hash is still
  `e19b0b3c…`, the suite was not re-run and the gate results above stand; at 14:13:04 the daemon
  was still pid 95762, with no new BTM record line or `xpcproxy` resolve.
- **After:** BTM's log at 12:36:19, and again at 13:53:12, has only the 10:27:22.666 record line
  since 10:27; `xpcproxy` only the 10:32:47.800 resolve since 10:30; the daemon still pid 95762. So
  nothing in chunk 4 moved record #11 or relaunched the daemon — the probe builds included.

**Chunk 4b, the probe fix — CLOSED 2026-09-19, 18:49–19:27, `d98b658`, and it closes chunk 4.** User decision
that day, *"4b now, calibrate after"*: fix the instrument headlessly first, and let Step 11's chunk 9
re-walk calibrate it against the real window afterwards. `tools/` and `scripts/` only — no app
source, no helper, no drive, no GUI — so the suite, the four gate passes above and the helper hash
`e19b0b3c…` all stand, and the daemon was never touched.

**Both halves of chunk 4's diagnosis are now settled by test**, 18:49–18:53, with a **scratch copy**
of the probe that logs every subview — never the committed one — as a 2×2 matrix at
`content-starting`, 640 pt wide, one drive:

| the probe's search | `overflowAt` | what the trace says |
|---|---|---|
| as it was — both breaks | **1** | asked 1 → `rootBounds=524`, and `contentMin` reads **524 after the function set it to 1**; `first=24`, so every height reads as a fit and the search returns its own lower bound |
| `.minSize` dropped only | **24** | asked 1 → `rootBounds=1.0`, `contentMin=0.0`: **`.minSize` is what re-imposed the minimum**, now tested where chunk 4 could only infer it. The search then bottoms out on the 24 pt subview instead |
| tallest subview only | **570** | asked 1 → `rootBounds=524` still, but `tallest=553 > 524` → `overflows`, and the search converges on the true figure **while still clamped** |
| both — the fix as committed | **570** | 602 with the title bar; the gate's table below |

**So the load-bearing half is the subview, not the clamp**, which is also why mutation m3 survives: a
clamped window's content still overflows its own bounds, so the clamp can only hide heights *below*
524 and the answer is above it. The clamp is cleared anyway and the refusal is now *detected*,
because the next clamp may sit above the answer and nothing in the old code would have said so.

macOS 27's subview inventory for this hierarchy, read off that trace — **11** of them, and
`rootView.subviews.first` is the first: two `KeyViewProxy` at 24 pt; three `AppKitPlatformViewHost`
(`MainWindowCloseGuardInstaller`, which tracks the content height; `TableSelectionPolicy`;
`OutlineListRepresentable`); a `PlatformContainer` — the flexible list pane, measured at **104 pt**
at every ask from 24 to 570; and five `_FocusRingView` at 24 pt. The rest is chrome that cannot
compress: 570 − 104 = **466 pt**, which is the arithmetic behind both figures the gate reports for
this state. **`fittingSize` is not the shortcut it looks like** — it returns the *ideal* size,
1197×716, not the minimum at a given width, so the binary search stays.

**The fix says when it cannot answer.** `measuredMinimumHeight` returns a `MeasuredMinimum` —
`.measured(CGFloat)` or `.unmeasurable(String)`, the reason worded for a gate to print verbatim. It
sets the search's `sizingOptions` to `[.maxSize, .intrinsicContentSize]`, clears `contentMinSize`
**and** `minSize`, compares the **tallest** subview against the root's bounds, and records the first
height the window refused to shrink to. Refused → `min=<w>xunmeasured`,
`measurement=UNMEASURABLE(<why>)`, exit **3**. `window-fit-check.sh` gained exit **2,
INCONCLUSIVE**, on two independent detectors: the probe saying so itself, and a measured height
*below* the declared one — which for these states cannot happen while the measurement works, since
every one of them has fixed chrome above and below the list. On INCONCLUSIVE it prints no worst case
and no verdict, and says not to record a figure from that run.

**Re-run at 19:06:58–19:07:33, and again at 19:25:45–19:26:20 against the committed tree: 613 pt at
`content-starting` with six drives**, exit 0 both times — the same figure as 2026-09-03 at `05b7ea7`
on Xcode 26.6 / macOS 26. All 14 rows measured, none declared, none inconclusive:

| state | 1 drive | 6 drives | declared |
|---|---|---|---|
| `content-starting` | 570 → **602** | 581 → **613** | 524 |
| the other six | 556 → 588 | 567 → 599 | 510 |

(content height → window height, +32 pt title bar.) Against the budget: 1440×900 fits with 187 pt
spare, 1280×800 with 87, 1152×720 with **7**. `.window-fit-exceptions` is still empty.

⚠️ **Chunk 9 measured the shipped window on 2026-09-22 and it is 2 pt taller than this table: 615,
not 613.** Every spare figure above is therefore 2 pt generous — 185, 85, and **5 pt at 1152×720**.
The gate is unchanged and 613 remains its number; this is the hardware reading recorded beside it.
See *Chunk 9's calibration*, below.

⚠️ **2026-09-24: this table is the old floor's.** Item 6's fix put `deviceListFloor` at the table's
own 104, and the gate now reads the declared minimum equal to the measured one in every row: 556 →
588 and **568 → 600** for the six states, 570 → 602 and **582 → 614** for `content-starting`. That
is 1 pt over this table, because 104 is the real window's table and the probe had read 103.
1280×800 has **86 pt** spare *(85 by the shipped window's 615, the spec since 2026-09-25)*.
**1152×720 is not maintained after 2026-09-24**, and the gate no
longer reports it. See *Item 6's diagnosis and fix*, below.

**Four mutations, the last two declared survivors in advance** — each re-breaks one half, then one
half together with its detector, to show which check kills which:

| | what it did | result |
|---|---|---|
| **m1** 18:58:46 | `.minSize` put back into the search's options | **killed** — exit 2, all 14 rows *"asked 1 pt, got 524 pt, so every height below that was never tested"* |
| **m2** 18:59:33 | `subviews.first` measured again | **killed** — exit 2, all 14 rows *"measured 24 pt, below the declared 510: this state's fixed chrome cannot compress that far, so the measurement is broken"* |
| **m3** 19:01:01 | `.minSize` back **and** the refusal detector deleted | **survived, predicted** — exit 0, the same 613 table, for the reason the matrix gives |
| **m4** 19:01:51 | `subviews.first` **and** the gate's declared-vs-measured check disabled | **survived, predicted** — exit 0, *"Worst case: content-starting at 556 pt"*, *"every state fits"*: **this morning's output reproduced exactly**, the positive control for the pair of checks |

m4's internal number is 24, not the morning's 1, because only one of the two breaks is re-applied;
what it reproduces is the **verdict**. Every mutation asserted its anchor unique before patching and
was restored from a **pristine copy**, never `git checkout`.

**And the case list cannot drift a fifth time** — user decision: put the check in `build-tools.sh`,
which already compiles `ui-probe` and runs on every protocol change. It extracts three lists — the
probe's `switch`, the probe's own *"unknown view"* message, and `render-ui.sh`'s header list between
two new `---- CASE LIST BEGINS/ENDS ----` sentinels — and fails unless all three name the same
cases. 19:04:40, and again at 19:26:44 on the committed tree: *"ok ui-probe case list: 40 cases, and
both hand-maintained copies name the same ones"*, 14 type-checked, 0 warnings. **Three negative controls**, 19:05–19:06,
each exit 1 and each naming the right thing:

- `report-device-lost-silent` dropped from `render-ui.sh`'s list → *"render-ui.sh's header list is
  MISSING: report-device-lost-silent"*.
- the same name dropped from the probe's message → *"the probe's own message is MISSING:
  report-device-lost-silent"*.
- the `CASE LIST BEGINS` sentinel renamed → *"an extraction came back EMPTY (switch=40 message=40
  header=0 names) — **this check is broken, not passing**"*, which is §3's zero-total rule wired into
  a harness for the first time. Both mutated files were restored from pristine copies and diffed.

**After, 19:27:** the daemon is still pid **95762**, and BTM's log and `xpcproxy` have no line at all since 18:00 — no record move, no resolve, no relaunch. Chunk 4b's **seven** gate runs and **five** `build-tools.sh` runs — each compiling the app's view sources and the probe afresh into `/tmp` — plus the diagnostic copies touched neither, which is what chunk 4 measured for the first time and this repeats.

*What would invalidate chunk 4b:* **613 is a fact about this probe on macOS 27.0 (26A428) with Xcode
27.0 (27A266a), at `.window-fit-exceptions` empty** — a change to any view source, to
`WindowMetrics`, to the probe, or to Xcode or macOS lapses it, and only the gate can restore it. The
measurement is still a **model** of the window — `NSHostingView` in a probe window, not the shipped
`Window` scene — which is why **Step 11's chunk 9 re-walk is its calibration**. *(Lapsed 2026-09-24
by an edit to `WindowMetrics`, item 6's fix, and restored by the gate the same day, at 614.)*
✅ **Walked 2026-09-21/22: the model holds to 2 pt** (615 shipped against 613 modelled), and the
same walk found
that `min=` conflates a drag floor with a push height — *Chunk 9's calibration*, below.
The case-list check lapses if the sentinels move or the probe's message is reworded; its own three
negative controls are what say it still works.

**Re-walks, user decision 2026-09-19.** Every Step 11 and Step 12 checklist pass was made on macOS
26 with an Xcode 26.6 build. A targeted set is re-walked on the Xcode 27 build — framework behaviour
no test or render reaches, and the window's size:

- **Step 11:** ✅ chunk 9, the window's size — and chunk 4b's calibration — **walked 2026-09-21/22,
  passed, and lapsed 2026-09-24** by item 6's fix; **items 2, 3 and 6 re-walked and passed
  2026-09-25** on the build that carries it; ✅ chunk 11, the report as a sheet — **walked
  2026-09-23, NOT passed: item 6 failed; fixed headlessly 2026-09-24, which lapsed the other ten;
  item 6 re-walked and passed 2026-09-25**; ✅ chunk 16, ⌘Q under every modal; and ✅ item 6.3,
  Cancel and Quit, which has broken silently before — **both walked 2026-09-25 and passed** on the
  fix's build, all nine items and 6.3 in both forms. **All four are walked.** 9.1, 9.4, 9.5 and
  chunk 11's other ten were not re-walked on the fix's build (user decision, 2026-09-25): their
  passes are facts about the build installed 2026-09-19.
- **Step 12:** chunks 1 and 2, dry. Its cable pulls are carried by Step 13's chunk 3, whose two
  pulls happen on this build anyway: item **3.7**, added today, takes Step 12's 3.4, 3.7–3.10 and
  3.12 at the running pull and 4.4, 4.7 and 4.8 at the paused one.

Everything else is covered on the new build by the suite, the gates or the renders, or is exercised
again by the Step 13 walk's real runs. Each checklist's header now says what it owes. **Then Step
13's walk restarts at item 0** — re-checked, since Step 12's chunk 1 installs a debug hook and takes
it out again — then chunk 1.

**Chunk 9's calibration — WALKED 2026-09-21 and 2026-09-22, PASSED IN FULL**, with three findings
and one open observation. 9.1–9.6 at the keyboard against the app installed 2026-09-19 10:22:50 from
`bcde5f5`'s sources, helper `ac4d5208…`, daemon pid 95762 on protocol v15, and the probe and gate at
`d98b658` — re-run 2026-09-21 08:42 first, to confirm the instrument had not moved underneath the
walk: **613, unchanged**. Five drives for 9.1–9.5, two for 9.6. The readings, the instrument and the
corrected item text are in `progress/step-11-human-checklist.md`.

**What it was for.** Chunk 4b's 613 pt was measured on an `NSHostingView` in a probe window — a
**model** of the shipped `Window` scene, not the scene. Nothing had ever compared the two.

**They agree, and the probe turns out to be reporting more than the gate uses.** `--limits` carries
two numbers and `min=` keeps the larger; the walk shows they answer different questions. **`declared=`
is the floor a user can drag to; `overflowAt=` is the height AppKit pushes the window to** when the
content grows underneath it. Both were confirmed against the shipped window: the idle floor is a
**542 pt** frame against `declared=510` **exactly**, the running floor **557** against `starting`'s
declared 524 (1 pt out, and the 15 pt of range comes back when the run ends), and at Start the window
is pushed to **615** untouched, against `overflowAt`'s 613 (2 pt out). So **the worst case is checked
on hardware for the first time and is 2 pt worse than the gate says** — 5 pt spare at 1152×720 rather
than 7. It still fits. **The gate is unchanged, 613 is still its number, and `.window-fit-exceptions`
is still empty**; 615 is recorded beside it, not adopted.

**`.defaultSize` sizes the frame on macOS 27, not the content.** The window opens at a **720 × 700
frame** — 668 pt of content against the 700 that `WindowMetrics.defaultContentHeight` declares. Same
family as chunk 4b's `.minSize` finding: a sizing API whose meaning moved under the move.

**Items 2 and 3 had carried pre-2026-08-22 criteria for a month.** 563–574, 613–624 and 627–638 were
measured 2026-08-20 and made wrong two days later by the refusal-line deletion that took the worst
case from 638 to 613; nothing re-walked them, so the staleness was invisible. Item 3's *"the window
grows a little at the moment you press Start and settles back when the run begins"* was wrong in kind
as well as in number: it is pushed to 615 and **stays** — what settles back is the floor.

⚠️ **One open observation, unreproduced: the bottom edge would not shrink the window.** Seen once
while the readings were being taken, with the corner handle working throughout; not reproducible the
same day, and not chased further (user decision 2026-09-22). **It cost a round of this walk**, which
was misdiagnosed as a drag that never registered — the drag registered and the window did not move.
If it recurs it is a defect against **NFR-USE-9**, since a 542 pt floor is worth nothing to a user
whose bottom edge will not reach it. The checklist carries the detector, a falsifiable hypothesis,
and the three checks that separate platform from product.

*What would invalidate this:* any edit to a view source, to `WindowMetrics` or to the probe; a new
Xcode or macOS; a different installed build. **615 is a fact about the app installed 2026-09-19,
on macOS 27.0 (26A428) with Xcode 27.0 (27A266a).**

⚠️ **Lapsed 2026-09-24** by the first of those: item 6's fix edited `WindowMetrics` and
`DeviceListView`. The floors above are the old build's, and every one of them was the window dragged
into a band its content did not fit. The predictions for the build that carries the fix are in the
checklist's chunk 9 box. The *"5 pt spare at 1152×720"* above is not maintained after that day.
*(2026-09-25: walked on that build, and every prediction read — "The re-walk of 2026-09-25", below.)*

*What would invalidate this:* for the gate passes, a different helper binary running — an install
that changes it, or a relaunch from DerivedData after something moved record #11 — a helper
source-hash move, a protocol bump, or a macOS update; for the renders, a change to any view source,
the probe, Xcode or macOS. `window-fit-check.sh` had no result here to invalidate *(⚠️ it has one
since chunk 4b, the same evening: **613 pt**, measured on Xcode 27 / macOS 27 — the record is 4b's,
and this paragraph covered chunk 4 only; 614 since 2026-09-24)*.

**Chunk 11's walk — WALKED 2026-09-23, NOT PASSED: ten of eleven items pass, item 6 failed and is
owed** (user decision: recorded as walked and not as passed, and the chunk stays on the re-walk list
for item 6 alone until it is diagnosed and fixed). *(2026-09-25: fixed the next day, and item 6
re-walked on the fix's build and passed — "The re-walk of 2026-09-25", below.)* It was walked at the keyboard 12:22–16:09 against
the app installed 2026-09-19 10:22:50 from `bcde5f5`'s sources — re-proved by content that morning —
with helper `ac4d5208…` and daemon pid 95762 on protocol v15, on macOS 27.0 (26A428). Six drives were
attached. Every Start was on the 125.8 MB thumb, serial `2211190533300386001515`: two finished runs
of about 40 s, one start aborted for item 8, and one dialog cancelled for item 11. The readings, the
instrument and its source are in `progress/step-11-human-checklist.md`, in chunk 11's own box.

**Item 6: below about 600 pt the report sheet is too tall, and at the floor it overhangs the
window.** The sheet takes its size from the main window's content, less 24 pt each way, so a *W* ×
*H* frame should carry a (*W* − 24) × (*H* − 56) sheet. **At 600 pt and above that held exactly**,
however the window got there: restored at launch (1040), pushed at Start (615), zoomed (1410 and
600), or dragged (677). **Below 600 it did not.** At 580 the sheet was 15 pt too tall and still
inside the window. **At the 542 pt idle floor it was 616 × 530 against 616 × 486 — 44 pt too tall —
and it hung 20 pt below the window's bottom edge.** That reading came twice, more than two hours
apart, and the user saw the overhang. Everything else item 6 asks for passed. The readings rule out
the drag, a fixed minimum and the window's own floor. The candidate is the `contentSize` the sheet is
derived from, and it is untested. **No gate and no render sees a sheet's real size**: it can only be
read off the running app, and this walk read it from the window server.

**One more observation for the same diagnosis** (user decision): at run 2's finish the window was
**pushed from 557 to 615 pt by itself**, as it is at Start. Chunk 9 never had the window below 615
when a run ended. Separately, Window ▸ Zoom, chosen a second time, returned the window to 600 pt
rather than the 580 it had left. That was noticed and not tested.

**Chunk 9's bottom-edge observation did not reproduce.** The edge worked on a window pushed to 615,
both after a run and during one, which is the one-step test its hypothesis asked for. The
observation is still open, having been seen once.

**Two of the checklist's own instructions were wrong, and are annotated rather than rewritten.**
Correction (7) missed that closing the main window is a quit, so item 7 was walked in two parts
across a relaunch. Item 8's note describes a mechanism that did not happen: the guard
`selectionStillNamesTheDrive()` stopped the start first, because the selection had moved to the
22 TB Seagate when the thumb went (FR-DEV-3). The start was the thumb's, captured at the press, and
nothing was ever started against the Seagate.

*What would invalidate this:* any edit to a view source or to `AppModel`, `QuitPolicy`,
`AppLifecycleDelegate`, `WindowMetrics` or `DevicePreparation`; a different installed build; a new
Xcode or macOS. **Item 6's failure is a fact about the app installed 2026-09-19, on macOS 27.0
(26A428) with Xcode 27.0 (27A266a).** The Xcode 26 build passed item 6 on 2026-08-23. What has
changed since then is not known. *(2026-09-24: known — where the window's drag stops. See the next
section.)*

**Item 6's diagnosis and fix — 2026-09-24, headless, `77275be`. Not re-walked.** *(2026-09-25:
re-walked and passed — the section after this one.)* User
decisions that day: diagnose item 6 first; then make **1280×800 NFR-USE-9's only target** and
**raise the window's minimum to the height its content measures**. The fault was not in the sheet.
**This build's window drags down to its declared minimum**, and `WindowMetrics.deviceListFloor`
declared the drive list at 46 pt while its table would not lay out below about 104. So the window
could be dragged into a band 46–57 pt tall where the root stack is taller than the window, and
`reportSheetSize` copies the root stack, less 24 pt each way — the overhang. `ui-probe` showed the
pattern with its own fixtures: sheet = stack − 24 at every height.

**The fix is two lines**: `deviceListFloor` = 104, used as `min(104, listHeight)`. Three scratch
experiments settled it. E1, a floor of 103 with the cap, made declared and measured one number in
every row. E2, 40 pt rows, left the six-drive floor where it was, so the floor is the table's and
not a count of rows. E3, the empty-state placeholder put back to 46, showed why a one-drive window
can open 12 pt taller than it needs: the first layout sees the placeholder, and a window never
shrinks back to a lower minimum. That is kept, knowingly, as cosmetic; a lower floor for the
placeholder is the band again, in a state the gate does not check. **104 and not 103**, because the
real window reads the table 1 pt above the probe (543 against 542 on 2026-08-20, 568 against 567
through Zoom on 2026-09-23).

| `ui-probe`, Xcode 27.0 / macOS 27.0 | 1 drive | 2+ drives |
|---|---|---|
| six idle-and-after states, content → window | 556 → 588 | 568 → **600** |
| `starting` | 570 → 602 | 582 → **614**, the worst case |

Declared was 510 (524 starting) in every row. **614 clears 1280×800 by 86 pt**, one point less than
before; 1152×720 is not maintained and the gate no longer has a row for it. `window-fit-check.sh`
gains a **third check that fails the gate** when a state's declared minimum is below the height its
content fits, and it now hard-fails on an unparseable figure instead of reading it as zero.

**Mutation round**, survivors declared in advance (`scratchpad` predictions, 2026-09-24): **M1**,
the floor back to 46 — the gate failed all fourteen rows on the third check alone, bands 46 and 57
(58 predicted: the probe reads the table at 103), with the budget verdict still *fits*; the suite
survived, as predicted, since no unit test can lay out SwiftUI. **M2**, the cap deleted — survived
both, as predicted: SwiftUI resolves a minimum above the maximum to the minimum, silently, and the
one-drive rows went 556 → 568 with nothing on stderr. Both are recorded at the cap's comment.

**Verified 2026-09-24 14:04–14:09** against a tree checksum of `eb39607c…`, the same at start
and end, on `d66752f` plus the working tree: `test.sh` **1323 tests in 157 suites, green**, no
Swift warning; the gate green, fourteen rows, worst 614; `build-tools.sh` 14 type-checked, 0
warnings, case list 40; renders 80 of 80 and seven floor extras, probe `7ac8b6f42a132809`. **The
helper source hash is unmoved, `e19b0b3c…`** — no helper or Shared file changed — so no hardware
gate lapses. Owed (d) and (e) are paid on the way, and (f) is annotated; see the *Owed* row.

**Then three more gate runs, the same day.** 17:53, green, the same figures, after a comment edit
to `.window-fit-exceptions` — which the checksum does not cover. 17:55, a scratch copy with the
budget at 600 pt, to take the path neither mutation reached: exit 1, the 602 and 614 rows over by 2
and 14 pt, the budget text once, no third-check line. 17:58, green again, worst 614 and 86 pt
spare, after a comment in the gate's own header — its *"at least 62 pt to spare"* of 2026-08-20,
stale since 2026-08-22, now annotated. **That run is on the tree this commit holds, `a15b272d…`**;
it differs from `eb39607c…` by that comment alone.

**Not shown on hardware.** The shipped window has read 1–2 pt taller than the probe, and during a
run its floor sat 15 pt above the probe's `running`. The predictions for the re-walk — 600 idle
with two or more drives, 588 with one, 614–616 at Start, and a window restored from a saved 542
opening at the floor — are in the Step 11 checklist, in chunk 9's box and at item 6. *(2026-09-25:
**shown** — 600, 588 and 614 read exactly, the saved 542 opened at 600, and the running floor read
615, the higher of its two predictions. See the next section.)*

**Installed 2026-09-24 18:01:53** from `77275be`, and proved by content: the installed binary's
`deviceListFloor` reads **104.0**. The readings are in the *Installed app* row. The helper binary is
unchanged, so no kickstart is owed. Step 13's item 0 lapses, by its own first clause.

*What lapses:* by their own clauses, chunk 9's pass and chunk 11's ten, since the fix edits
`WindowMetrics` and a view source. *What would invalidate this:* any edit to a view source,
`WindowMetrics`, the probe or the gate; a new Xcode or macOS. **614 is a fact about the probe at
`7ac8b6f42a132809` on macOS 27.0 (26A428) with Xcode 27.0 (27A266a).**

**The re-walk of 2026-09-25 — Step 11's 11.6, 9.2, 9.3 and 9.6, PASSED** (user decision:
*"Criteria confirmed; re-walk 11.6, 9.2, 9.3 and 9.6"*). The saved-frame check at 02:56, the rest at
the keyboard 11:16–13:02, against the app installed 2026-09-24 18:01:53 from `77275be` — re-hashed
at 02:58 and again after the day's restart to the bytes proved by content that evening: dylib
`e6e6e884…`, stub `bf787e19…`, helper `ac4d5208…` — on macOS 27.0 (26A428), protocol v15. App pid
28582, then 1475; daemon pid 95762, then 1477. Frames came off the window server every 50 ms and the
autosave every 0.5 s, from a sampler built from the checklist's `winlist` source.

| | predicted | read |
|---|---|---|
| idle floor — six drives, two, one | 600, 600, 588 | **600, 600, 588** |
| at Start, pushed | 614–616 | **614**, 71 ms after `starting` — the probe's figure exactly |
| running floor | ~615, or 600 | **615**, and a drag during the run did not move it |
| the sheet, on 615, 600, 1027 × 1304 and 588 | the window less 24 × 56, 24 pt inside | **exact at all four**, at *x* + 12, *y* + 32 |
| a saved 542 pt frame | opens at the floor | **opened at 600**, top edge kept |

The run was on the 125.8 MB thumb, serial `2211190533300386001515`: 39.9 s, 0 failing blocks; the
22 TB Seagate was never a target. **9.1, 9.4 and 9.5 and chunk 11's other ten were not re-walked**
(user decision), so their passes are facts about the build installed 2026-09-19. The readings, the
user's words and the instrument are in the checklist's chunk 9 and chunk 11 boxes. *What would
invalidate it:* any edit to a view source or to `AppModel`, `QuitPolicy`, `AppLifecycleDelegate`,
`WindowMetrics`, `DevicePreparation` or the probe; another install; a new Xcode or macOS.

**Reported, not adopted** — each is the user's call:

- **The running floor is 615 and the gate's worst case 614.** The shipped window is tallest while a
  run is on, 1 pt over the probe, which leaves **85 pt** at 1280×800 rather than 86 — within the
  2 pt the checklist allows. The gate and its 614 are unchanged.
- **A rising floor pushes the window**: with one drive attached, the second arriving took it from
  588 to 600 in 78 ms, top edge kept. And the pre-run dialog grew with the window at Start, 528 to
  542 pt, in the same sample.
- **After a relaunch, ⇧⌘R shows the empty report** — *"No run has finished yet"* — by design, since
  the report lives in memory only. The one-drive sheet was read on it; its frame does not depend on
  what it shows.
- **The push at a run's finish seen 2026-09-23 cannot be seen on this build**: the window can no
  longer be below 615 when a run ends. Inferred, not tested, so it stays open.
- **A dark-mode screenshot of 2026-09-24 drew Start blue during a run**, where the probe's light
  render draws it grey. Not investigated.
- **`BUILD-PLAN.md`'s 2026-09-19 note calls the declared minimum *"58 pt short"***; 613 − 556 is 57.
  A dated record, left as it is.
- **`ContentView.swift`'s comment at `reportSheetSize`** is left as it is: editing a view source would
  lapse these passes.

**Decided by the user later on 2026-09-25**, item by item:

- **615 is the spec** — *"Change the running height spec from 614 to 615."* NFR-USE-9's worst case
  is the shipped window's running floor, 615 pt, 85 pt inside 1280×800 (the NFR's amendment of
  2026-09-25). The gate is unchanged: it has no 614 of its own to change — it measures the probe and
  prints what the probe reads.
- **The rising-floor push, and the dialog growing with the window** — *"Agreed"*: harmless and
  cosmetic, kept as they are.
- **The push at a run's finish is closed** — *"Let's close the push at the end of the run issue."*
- **The blue Start is desired** — *"Blue Start button is desired."* Not a finding.
- **`BUILD-PLAN.md`'s "58 pt short" reads 57**, dated — *"Update the BUILD-PLAN to be 57 with
  today's date recorded."*
- **The `reportSheetSize` comment waits** for the next change to `ContentView.swift` — *"Leave
  comment as is unless we make changes to this file in the future."* Owed (g).
- **Next, chunk 16 and item 6.3** — *"Proceed with chunk 16 and item 6.3."* *(Walked the same day
  and passed: *The walk of chunk 16 and item 6.3*, below.)*

**The instrument, three notes.** The screen saver's zoom transition gave four readings of 577 × 541
— everything on screen scaled by about 0.9, width included — at 03:18, 10:25, 10:51 and 11:15, each
within half a second of the saver starting or stopping: not the window's frame. The first sampler
leaked both ends of every pipe, 38,345 by 11:20, and from 04:57 its autosave half read nothing while
its window half went on; fixed, given a heartbeat, restarted at 11:21, and flat since. **A restart
clears `/private/tmp`**, and the sampler with it: the first one-drive walk ran unmeasured and was
walked again, 12:57–13:02, with a sampler running — that is the reading recorded.

**The restart.** The 22 TB Seagate's eject failed — 18 unmount calls returned EBUSY, 12:10–12:12, the
holder not named in the log — and the user restarted the Mac at 12:13. The app quit cleanly, with no
run and no crash report, and every unmount at logout succeeded. Nothing in the app's source opens a
file on a mounted volume and the relaunched app held nothing there: unattributed, not a product
finding. If it recurs, `/usr/sbin/lsof /Volumes/Backup "/Volumes/Time Machine"` names the process. At
boot launchd logged two E lines under the helper's label, *"Unknown key for plist importer"*, for
`_Quarantined` and `SHA256`; the documented log predicates, filtered to the app's process, do not
count them.

**For later walks with fewer drives:** the 1 TB 990 EVO Plus, `013117100578`, holds this repository
and Claude Code and is never unplugged, so every one- or two-drive state includes it. The 22 TB
Seagate may be unplugged for a walk step, ejected first, but must be powered on, connected and all
its volumes mounted again **before midnight every evening**, for the automated backups (user,
2026-09-25).

**The walk of chunk 16 and item 6.3, 2026-09-25 — PASSED** (user decision: *"Proceed with chunk 16
and item 6.3"*). About 16:39 to 20:12 at the keyboard, on the build the re-walk above ran against,
re-hashed after the walk to the same bytes: all nine of chunk 16's items, with 6.1, and 6.3 in two
forms. App pids 1475, 12508, 14060, 14293, 14752 and 14759, one launch per part; daemon pid 1477,
then 14761 after item 3 switched the helper off and on in Login Items. Every Proceed was checked
against the dialog's serial. The app selected the 22 TB Seagate by itself at every launch, and
nothing was ever started against it.

| | read |
|---|---|
| ⌘Q under the pre-run dialog (6.1), the quit confirmation (16.5), two modals at once (16.6) and the failure alert (16.4) | refused: **greyed** each time, and ⌘Q did nothing |
| ⌘Q with nothing on screen (16.2), and under the helper gate (16.3) | quit; under the gate, `discarding the helper gate` first |
| what a SwiftUI `.alert` is (16.7) | `2 window(s), 1 sheet(s) [_NSAlertPanel]` — 2026-09-04's reading, twice |
| the selection moved under the pre-run dialog (16.4) | `run aborted before any write`, 1 ms after Proceed; the helper was never called |
| *Cancel and Quit*, hardest form — the thumb, the report raised behind the confirmation | both sheets down, the terminate line 0.3 s later, the app gone, `Slice_A` back |
| *Cancel and Quit*, standard form — the 1 TB scratch T5 | stopped at the end of chunk 238, 11 ms after the click, nothing failed; the drive released; quit 0.32 s after the click; `Test_Drive` back, EFI unmounted |
| the three errors this path can emit (16.8) | none in six hours; 17 quit lines in the same window |

The item-by-item record is in the Step 11 checklist, in chunk 16's 2026-09-25 box and at items 6.1
and 6.3. *What would invalidate it:* any edit to the quit path — `AppModel`, `QuitPolicy`,
`QuitSequence`, `AppLifecycleDelegate`, `USBDriveTesterApp.swift` — or to `DevicePreparation`,
`RunController`, `RunControllerWiring` or the helper gate; any change to what a finished or stopped
run puts on screen; another install; a new Xcode or macOS.

**Reported, not fixed** — none of them in the app's behaviour; *Owed* (h)–(k), in this order, each
the user's to decide:

- **The live metrics panel polls a helper that is not there.** While the gate was up, its 1 Hz tick
  logged `helper progress connection invalidated` and `helper transport error` every second, both at
  error level: 22 lines in ten seconds. Nothing on screen changes. Logging only.
- **`HelperAvailability.swift`'s header says nothing re-diagnoses on activation**, and `8b0db53`
  made it do so on 2026-08-31. App source; a comment only.
- **Chunk 16's heading says only item 4 needs a run**, and items 5, 6 and 7 each need one too. An
  instrument defect, left as it is.
- **6.3's EFI check cannot be observed on the thumb**, which has no EFI partition; the standard form
  ran on the scratch T5 to observe it. An instrument defect.

*(2026-09-26, the user's decisions: the first two wait — the poll's noise for the next app-source
change, in a shape agreed that day, and the header for the next edit of `HelperAvailability.swift`
or of `AppModel.swift`, whose doc comment on `refreshHelperAvailability()` carries the same claim;
the last two are paid in the checklist, with the old wording quoted — see Owed.)*

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
