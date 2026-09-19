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

## Step 13 — System-sleep prevention (NFR-REL-9). **IN PROGRESS — chunks 1–4 of 5 done, chunk 5 paused for the move to Xcode 27**

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
> for the move to Xcode 27** (user decision; four chunks — chunk 1 closed that day, chunks 2 and 3
> on 2026-09-19, **chunk 4 next, when the user approves it** — *The move to Xcode 27*, below).
> Chunk 3 installed the Xcode 27 build, and **every pass the walk had made lapsed with that
> install**. Item 0 was re-run against the new build that morning and passed; the walk restarts
> after chunk 4 with item 0 re-checked, then chunk 1.
> The suite is **1323 / 157 / 0 on Xcode 27.0**, green 2026-09-19 against `d1ac7a6` with zero Swift
> warnings — once chunk 2's one warning was fixed in the test target — floor **1323**. The protocol
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
> treat a reboot as one.
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

### Current state — 2026-09-19, Step 13 chunks 1–4 done, chunk 5 paused for the move to Xcode 27

| | |
|---|---|
| **Now: the move to Xcode 27** | **Four chunks from 2026-09-18, user decision; Step 13's walk is paused for it.** (1) the project file, ✅ **closed 2026-09-18** — `b8015c7`, `14d2f79`; (2) build and test headless, ✅ **closed 2026-09-19** — clean Debug and Release builds 2026-09-18 against `d2950cf`, the clean test run and `build-tools.sh` 2026-09-19 against `d1ac7a6`, everything as expected once the test build's one Swift warning was fixed in the test target (`c47cbe7`, `d1ac7a6`); (3) install and kickstart, ✅ **closed 2026-09-19** — the Xcode 27 build installed 10:22:50 and proved by content, BTM's record back on `/Applications` at 10:27:22, the daemon kickstarted at 10:32:47 and resolved from `/Applications` as pid 95762; `install-app.sh`'s stale-daemon warning had been dying of SIGPIPE since 2026-09-11 and was fixed first (`ba97c0e`); **(4) the hardware gates, `render-ui.sh` and `window-fit-check.sh` — NEXT, when the user approves it**. Each chunk is reported before the next starts, and the next needs the user's go. ⚠️ **BTM record #11 is on `/Applications`** since 10:27:22 and the daemon is pid 95762 from there: a test run or an Xcode run of the project moves the record back, and a relaunch after that — a kickstart, a crash or a reboot — comes up from DerivedData. What each chunk must show is in *The move to Xcode 27*, below |
| **Step 13** | **in progress — five chunks, 1–4 done (1–3 on 2026-09-12, 4 on 2026-09-13).** (1) the instrument, ✅ done — `tools/sleep-assertion-probe` + `scripts/sleep-assertion-check.sh`, findings in `CONSTRAINTS.md` §1 *Idle-sleep assertions*; (2) the rule and the seam, ✅ done — `RunControlPolicy.preventsIdleSleep(in:)`, `IdleSleepPreventing` / `IdleSleepPreventer` in `RunControl/SleepPrevention.swift`, and `CountingIdleSleepPrevention` in the test target for chunk 3 to inject; (3) the one acquire/release path, ✅ done — `report(_:)` and `apply(_:movingTo:)` both go through a private `move(to:)`, the sole assignment to `state`, which asks the rule about the destination; init parameter `sleepPrevention` **with a default** (Step 12 chunk 6: one without a default breaks `ui-probe` and only `build-tools.sh` finds it), and **`RunControllerWiring` is deliberately unchanged** — the composition root has no automated cover (m17), so nothing there is required for the assertion to work; (4) mutation round + `progress/step-13-human-checklist.md`, ✅ done — **17 mutations, 13 killed, 4 survived, all four declared in advance**, no unexpected survivor and no inconclusive row; the checklist was written alongside the round rather than after it, so its items are built around measured holes; **`scripts/sleep-assertion-watch.sh` is new** — the gate asks a person to press Pause and then read `pmset`, which is a race they cannot win, so the walk gets a 4 Hz change-log instead; (5) hardware walk and the gate, **paused 2026-09-18 for the move to Xcode 27** — item 0 passed 2026-09-13, its daemon row lapsed 2026-09-16 and was restored by the kickstart at 2026-09-18 13:06:19; chunk 1 passed 2026-09-18 14:47–14:53 on its third walk (the first could not show its reading and the watcher was rewritten; the second's paste stopped short of the selection); chunk 2 part-walked 15:04–15:07 (2.1–2.4 and 2.6 passed; 2.5 was a cycle short, and its threshold, one short since it was written, is corrected). The walk restarts at item 0 after the move's chunk 4; every pass here was a fact about the Xcode 26 build `af09416` and **lapsed at the Xcode 27 install, 2026-09-19** — item 0 was re-run against the new one that morning and passed. **No chunk touches `Helper/` or `Shared/`**, so the helper hash does not move and the four gates recorded against it do not lapse — owed items (a) and (b) therefore stay owed. ⚠️ **From 2026-09-16 until the kickstart at 2026-09-18 13:06:19 the running daemon was an Xcode 27 build no gate had run against; then the installed Xcode 26 helper, `7590b920…`; and since the kickstart at 2026-09-19 10:32:47 the installed Xcode 27 helper, `ac4d5208…`, which no gate has run against until chunk 4 does** — see *Installed app*. Objective, four detailed steps, three gate items and the one named risk are in `BUILD-PLAN.md` |
| **Step 13's one scoping decision** | **The assertion is held while `state == .running` and in no other state — user decision 2026-09-12.** BUILD-PLAN says `Running`; NFR-REL-9 says *"actively executing"*, and `.pausing`/`.stopping` are states where the helper is still finishing a chunk (bounded by one call of at most `maximumBytesPerCall` = 1 GiB), so the two documents differ on two states. `.running` alone was chosen because pressing Pause or Stop is HID input, which resets the idle timer for the whole settle that press begins; because an item whose reading depends on *when* you look is a bad gate item; and because holding iff `.running` makes the release happen on the transition **out of** running — so `.finished` is never the release site and the leaked-assertion risk `BUILD-PLAN.md` names cannot reach it. The one exit with no HID input in front of it is device loss → `.finishing`, where the drive is already gone. ⚠️ **Corrected 2026-09-12 at chunk 3:** that risk was handed over named as `releaseCannotBeConfirmed`, and measurement says otherwise — *that* path reaches `.finished` synchronously. The state a run can sit in indefinitely is **`.finishing`**, by the opposite path: a release that can be confirmed and is never answered. See the annotation under *What Step 13 inherits* |
| **Verified** | **1323 tests, 0 failures, 157 suites** (floor `scripts/.test-floor` = **1323**, ratcheted at Step 13 chunk 3 — the floor raises itself), run green **2026-09-19 09:23–09:24 against `d1ac7a6` with Xcode 27.0 (27A266a) on macOS 27.0 (26A428)**, DerivedData wiped first and the count read from the xcresult, with **zero Swift warnings** in that test build and in the clean Debug and Release builds of 2026-09-18 against `d2950cf` — `d1ac7a6` differs from it by one test file (the move's chunk 2, below). A change to any source, the project file, Xcode or macOS invalidates it. Before that: green 2026-09-13 10:29 with Xcode 26.6 on macOS 26. **`test.sh` raises the floor only on a green run since 2026-09-18**; until then the raise came before the failure check, so a red run could raise it (seven cases, old script against new, with a stand-in `xcodebuild`: only *red with a higher count* differs). **Chunk 4's mutation round ran the suite 17 more times** — every run complete at 1323, no incomplete run and no inconclusive row. **14/14** gate clients type-check (2026-09-19, `d1ac7a6`, v15). ⚠️ `scripts/build-tools.sh` is what catches those: the app build does not compile `tools/`, so a new `RunController` parameter without a default breaks `ui-probe` and nothing else would find it — that happened at Step 12 chunk 6 |
| **Helper** | source hash **`e19b0b3c972d4b5bf9e052d087df231d34c8eee65aaddb9d772ce338db35edb9`**, unmoved since **2026-09-07** (Step 12 chunk 7b; re-derived 2026-09-19 at `d1ac7a6` and again at the move's chunk 3). **Re-derive it before trusting any hardware gate result** — `find USBDriveTester/com.arc3solutions.USBDriveTester.Helper USBDriveTester/USBDriveTester/Shared -name '*.swift' \| sort \| xargs cat \| shasum -a 256`. Step 13 is described as **GUI-side** in `BUILD-PLAN.md`, so it should not move the hash; if a chunk of it does, say so before writing the code, because **four hardware gates and the whole of Step 12's checklist are recorded against this hash**. ⚠️ **A new toolchain moves the helper binary and leaves this hash where it is** — the four gates ran against binaries Xcode 26.6 built, so the move to Xcode 27 re-runs them (its chunk 4) |
| **Installed app** | `/Applications/USBDriveTester.app`, Debug, **installed 2026-09-19 10:22:50** (the move to Xcode 27's chunk 3) from **`bcde5f5`**'s sources, built with **Xcode 27.0** — `DTXcode 2700`, `27A266a` — and byte-identical to the 09:46:27 install that morning, whose script died before its warning (`ba97c0e`). Proved by content: checklist item 0.1 greps **1**, `diff -rq` against the build products taken after the install **0** differ, dylib **`422c89d3…`**, helper binary **`ac4d5208…`**, launcher stub `48212035…`, `codesign --verify --deep --strict` OK. The dylib is the 09:23 test build's code, re-signed at 09:46:29 by the install's build, which compiled and linked nothing; the helper is the binary the move's chunk 2 built, signed 09:23:51. **The daemon runs it since 2026-09-19 10:32:47**: pid **95762**, resolved by `xpcproxy` to `/Applications` after the user's kickstart, protocol v15 off its own start line. **Before it:** installed 2026-09-13 10:51 from `af09416` with Xcode 26.6 — dylib `a8a0e932…`, helper `7590b920…` — and run by pid 46679 from the kickstart of 2026-09-18 13:06:19 until this one; from the macOS 27.0 reboot until that kickstart the daemon was pid 12059 from **DerivedData**, helper `32a647da…` (cold start, above). ⚠️ This row still named `abc07e3` until 2026-09-18 — `f7e2ff3`, the install's own commit, edited only the checklist (*Chunk 5*, below). ⚠️ **Grep `Contents/MacOS/USBDriveTester.debug.dylib`, never `Contents/MacOS/USBDriveTester`** — the latter is a 59 KB launcher stub and a content proof aimed at it returns 0 for everything, reading exactly like a failed install. ⚠️ **Prove an install by content, never by timestamp**, and take the DerivedData hash *after* the install: `install-app.sh` rebuilds through `build.sh`, which on 2026-09-19 re-signed a test build's products, so the dylib hash read before that install named a file that was gone after it. `ditto` carries the bundle's birth time over, so no bundle date is an install time |
| **Toolchain** | **Xcode 27.0 (27A266a) since 2026-09-15**, installed over Xcode **26.6** at the pinned `/Applications/Development/Xcode.app`; **macOS 27.0 (26A428) since 2026-09-16**. Every build, test run and gate result recorded before 2026-09-18 was made with Xcode 26 on macOS 26 — including the app installed until 2026-09-19, which nothing on this machine can now rebuild byte for byte; the one installed since is Xcode 27's (`DTXcode 2700`). ⚠️ **26.6, not 26.5:** these notes said 26.5 from 2026-08-06, which is the SDK's version (`macosx26.5`), not Xcode's — the app installed until 2026-09-19 recorded `DTXcode 2660`, the project was created with tools 26.6 on 2026-07-25, and `CONSTRAINTS.md` §1 says *"Measured with Xcode 26.6"*. Corrected 2026-09-18 where the text describes the present; the archives keep what they said. **Xcode 27's project edits, settled 2026-09-18** (user decision; the move's chunk 1): taken — `LastUpgradeCheck` 2660 → 2700, `DEAD_CODE_STRIPPING = YES` on every target, `STRING_CATALOG_GENERATE_SYMBOLS = YES` (inert: the project has no string catalogs); **refused — its removal of `ARCHS = arm64`**, because without it Xcode 27's `-showBuildSettings` resolves Release to **`arm64 x86_64`** (the macOS 27 SDK still lists `x86_64`), while Debug stays `arm64` through `ONLY_ACTIVE_ARCH`, so no Debug build or test run would have shown it. Restored, every target resolves to `arm64` in both configurations — and the binaries agree: the move's chunk 2 found `lipo -archs` printing `arm64` alone for the Release app and its helper, 2026-09-18. The `orderHint` churn is gone at its source: `xcschememanagement.plist` is per-user state that `.gitignore` already excluded, committed before the rule and now untracked — and there are no shared schemes to lose, since both schemes are Xcode's automatic ones. Measured behaviour re-checked on macOS 27 so far: *Idle-sleep assertions*, 0 failures, and BTM's record-and-resolve behaviour, 2026-09-18 (`CONSTRAINTS.md` §1) |
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
after the move's chunk 4.

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
  warnings in `tools/`.

A change to any source, the project file, Xcode or macOS invalidates these. The helper source hash
is unmoved, `e19b0b3c…`; the helper *binary* is Xcode 27's, which is why chunk 4 re-runs the
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

**Chunk 4, re-verify — NEXT, when the user approves it.** The four hardware gates, on the 1 TB scratch T5
only — found by serial `12345686DAA9` on the day, because its `diskN` moves, and never the 22 TB
Seagate. Last run 2026-09-07 against `e19b0b3c…` and protocol v15, in `progress/step-12.md`'s
table: `metrics-check.sh` 128 assertions / 0 failures, `xpc-concurrency-check.sh` 0 failures,
`retention-cycle-check.sh` 15 checks / 0 failures, `run-control-check.sh` 14 assertions / 0
failures. The source has not moved since; the binary has — they run against pid 95762 and
`ac4d5208…`. Then `render-ui.sh` and `window-fit-check.sh`, because a new SDK can move SwiftUI
layout. Those two compile the app's view sources with `tools/ui-probe` by `swiftc` into `/tmp` —
no app bundle — and the probe's diagnostics view reads this machine's real `SMAppService.status`,
which its renders show as `notFound`. It is not expected to touch BTM record #11, and nothing has
measured that, so **BTM's log is read after chunk 4** — the recipe, added at chunk 3, is in the
checklist's *The daemon* — before anything could relaunch the daemon. Then decide with the user whether any Step 11
or 12 checklist item needs re-walking on the new build. **Then Step 13's walk restarts at item 0**
— re-checked, since item 0 already passed against this install.

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
