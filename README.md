# USBDriveTester

A macOS tool that **refreshes and fault-tests USB storage** by walking a drive's entire
addressable range with a sequential, in-place **read → write-back → read-verify** cycle.

Data written to NAND flash decays — slowly while powered, faster when a drive sits
unplugged or gets thermally cycled. Rotational drives have their own decay paths: adjacent
track interference, thermal cycling, the superparamagnetic effect. Both eventually produce
the same result, which is a block that will not read back. Rewriting a block with its own
contents restores the charge (or the magnetic domain) that holds it, and reading it back
immediately afterwards is what catches the blocks that are already gone.

So the tool does two jobs with one pass: it is a **retention refresher** and a **hard-fault
detector**.

It is **non-destructive by design** — the only data ever written to a location is the data
just read from it. No test patterns, no known-value overwrites, no scratch areas.

> ### Status: in development — Step 12 of 16 is complete; Step 13 is in progress (all five chunks done: chunk 5's walk has passed — item 0 and chunks 1–3 — and so has the verification gate, on 2026-09-29; closing the step is next)
>
> Steps 1–12 and Step 14 are complete and committed. **Step 11 (run control: start / pause /
> resume / stop) closed on 2026-09-05** — all twelve increments landed and gated, its 16-chunk
> human checklist walked in full, and its verification gate re-run against the current XPC
> protocol. **Step 12 — device-loss handling — CLOSED on 2026-09-11**, all nine chunks done and
> all four verification-gate items ticked against real hardware: **eight cable pulls on two
> drives**, a run ending 2.7–6.3 ms after the drive left, naming the model, the serial and the
> block it stopped at. Chunk 7 was the mutation round, the human checklist, the physical-unplug
> hardware gate and all four hardware gates re-run; **7a (the increment gate), 7b (the mutation
> round), 7c (the human checklist) and 7d (reinstall, kickstart, and all four hardware gates re-run
> and passed on 2026-09-07) are done, 7e — walking that checklist — closed on 2026-09-11 (chunks 1
> and 2 passed 2026-09-08, chunk 3 on 2026-09-09, chunk 4 on 2026-09-11, and chunk 5 discharged from
> chunk 3's log), and 7f fixed a false-positive device loss that walk uncovered.** Chunk 3 of the walk first aborted on 2026-09-08 when the app ended its own run ten
> milliseconds in: route (b) treated a slice disappearance as the drive leaving, and taking
> exclusive whole-disk access is what makes the slices disappear. Fixed, covered by six tests, and
> **chunk 3 re-walked from the top and CLOSED 2026-09-09** — every item passed, item 9 on the sixth
> cable pull, which landed mid-write-back: the hazard case. **Chunk 4 — a paused run unplugged —
> passed on 2026-09-11** on two drives: the run ended a millisecond after the drive left, and the
> report said it had been paused and nothing was half-written. Chunk 5's two measurements were
> already in the persisted log, six trials each from chunk 3's pulls, and were accepted as they
> stand. **Chunk 7g closed the walk's two logging gaps in code on 2026-09-11** — every run command
> and every automatic re-selection now leaves a line — and retired the two stale app-target
> comments with them; the third is helper source and waits for the next helper change. **A person
> ran that build on the 1 TB scratch T5 the same evening** and both kinds of line came out as
> specified. **Chunk 7h then closed the test gap 7g predicted**: the *build one wind-down per
> callback* mutation was measured surviving all 1301 tests, and one new test kills it. The last
> unseen line, `paused → running on the Resume command`, was watched on hardware at 18:02 the same
> evening, and **Step 12 closed** — its full account is in
> [`progress/step-12.md`](progress/step-12.md). **Step 13 — system-sleep prevention — is in
> progress**, all five of its chunks done and only its close left: the gate's instrument measured,
> the rule and its seam built, and the assertion wired to the one place the run state is assigned
> (2026-09-12), then **its mutation round run on 2026-09-13 — 17 mutations, 13 killed, four
> survivors, all four declared in advance.** Two of those survivors are the point: deleting the
> release call outright, and holding the display-sleep assertion instead of the system one, each
> pass all 1,323 tests. That is what
> [`progress/step-13-human-checklist.md`](progress/step-13-human-checklist.md) is for, and walking
> it was the last chunk. **The walk was paused on 2026-09-18 for the move to
> Xcode 27**, which had replaced Xcode 26.6 under the project three days before, **and restarted on
> 2026-09-27**. Three of the
> move's four chunks are done: the project file, a clean build and test run, and — on 2026-09-19 —
> the Xcode 27 build installed, with its daemon running from `/Applications`. The fourth ran the same
> day: the four hardware gates passed on the Xcode 27 build and the UI renders are whole, but the
> window-size check's probe had stopped measuring on Xcode 27 and proved nothing. **That probe was
> fixed the same evening** — it was measuring the wrong subview, and it now says so instead of
> guessing when it cannot measure at all — and the check is back to the figure it gave on Xcode 26.
> **The move is complete.** After it, a chosen set of Step 11 and 12 checklist items is re-walked on the
> new build, and then the walk restarts at item 0. **The first of those re-walks — the window's size
> — passed on 2026-09-22**, and it confirmed the fixed probe against the real window for the first
> time: they agree to two points. **The second — the run report, shown as a sheet on the main
> window — was walked on 2026-09-23 and did not pass.** Ten of its eleven checks passed. The one
> that failed: when the window is short, the report is taller than the window and hangs below its
> bottom edge, by 20 points at the smallest size. **Found and fixed on 2026-09-24:** the window
> could be dragged shorter than its own content, and now it cannot. The fix lapsed both re-walks'
> passes. The same day the smallest screen this app is held to became 1280x800 alone. **Walked
> again on 2026-09-25, on the build that carries the fix, and passed:** the report sits 24 points
> inside the window at every size tried, and the window stops at its floor with six drives, with two
> and with one. Only the failed check and the three window-size checks the fix touches were walked
> again; the rest remain passes of the earlier build. **The last two Step 11 re-walks passed the same
> day, on the same build:** ⌘Q under the app's dialogs — refused under the pre-run warning, the quit
> confirmation and the failure alert, and quitting with nothing on screen and with the helper switched
> off — and *Cancel and Quit* during a run, which stopped between two chunks, let go of the drive and
> quit. **Step 12's first two chunks passed again on 2026-09-26**: the report left on screen when a
> drive disappears mid-test, read off the app's own renderings of it, and the alert shown when there
> is no report to show, raised through a temporary debug menu and then taken out again, the install
> put back byte for byte. **The walk restarted on 2026-09-27: item 0 — which build is installed, and
> which helper is running — was re-checked and passed**, and the three flash drives it may write to
> were named that day. **Chunk 1, the baseline, passed the same morning:** with the app open, and
> then with a drive selected but no test started, it keeps nothing awake. **Chunk 2, the lifecycle,
> passed that afternoon**, on the drives agreed that morning: a test on the 4 TB T5 EVO asked the
> Mac to stay awake only while it was running — not while paused, and never twice over — and
> stopped asking at the stop; a test on the 125.8 MB thumb stopped asking the moment it finished;
> and quitting left nothing behind. **Chunk 3, the endings a button cannot make, passed on
> 2026-09-28**, on the 4 TB T5 EVO: a test asked the Mac to stay awake but never to keep the display
> on, and the display slept for nearly three minutes with the test running on; pulling the drive's
> cable mid-test stopped the asking as the report appeared; and pulling it from a paused test found
> nothing to stop. Step 12's cable-pull checks passed again on this build along the way. **Step 13's
> verification gate passed on 2026-09-29** on those readings — a test that stops on a failed block
> was argued from the code rather than seen, since none of the drives it may write to has one — and
> closing the step is next.
> Before the pause, item 0 passed on 2026-09-13 and
> chunk 1 on 2026-09-18, on its third walk — the first could not show the reading it was asked for,
> and the instrument was rewritten — and chunk 2 was part-walked. Those passes were facts about the
> Xcode 26 build and lapsed when the Xcode 27 one was installed. The engine, the privilege
> plumbing, the safety guards, metrics, reporting, run control, device-loss handling, the pre-run
> warnings and sleep prevention all exist and are exercised on real hardware; sleep prevention's
> verification gate passed on 2026-09-29. Logging consolidation (Step 15) and notarization (Step 16)
> do not exist yet. *(Until 2026-09-29 this paragraph ended "Sleep prevention, logging consolidation
> and notarization do not yet." — wrong from 2026-09-12, when the assertion was wired. Finding F4 of
> Step 13's walk, found 2026-09-28 and fixed by the user's decision.)* *(And until the same day the
> heading above ended "the move to Xcode 27 is complete and the walk resumes with a set of re-walks"
> — stale from 2026-09-27, when the walk restarted. Finding F5, found and fixed 2026-09-29 by the
> user's decision.)*
>
> ⚠️ **This block said *"Step 12 … is next and is not yet started"* until 2026-09-07** — wrong
> since chunk 1 landed on 2026-09-05, through seven chunks and a protocol bump. That is the
> **eighth** status block this repository has shipped disagreeing with the body under it, and the
> second one outside `BUILD-PLAN.md`. It was missed because the check greps for the *claim* and
> nobody thought of the README as a place where the current step is named. **It is. Add it to the
> grep.**
>
> ⚠️ **And it said *"chunk 3 must now be re-walked from the top"* until 2026-09-10** — through all
> six of chunk 3's commits, `bed54e9` to `2086090`, while `BUILD-PLAN.md` was kept current. The
> **ninth**, and the first in a place already on the list; see `CLAUDE.md` for what that changes.
>
> **Nothing is distributed until the whole plan is complete** (Step 16). There is no preview
> build and no notarized release; every build so far runs on the author's machine.
>
> Current verified state, on Xcode 27.0 since 2026-09-19: **1323 tests / 157 suites / 0 failures**
> (floor 1323), zero source warnings from three clean builds, **14/14** gate clients type-checking
> and warning-free, all four hardware gates passing against the Xcode 27 helper, XPC protocol v15,
> and the main window measured at **613 pt** against its committed 700 pt budget — **615 pt when
> measured on the shipped window itself, 2026-09-22**, which is the first time the two have been
> compared. *(2026-09-24: **614 pt**, re-measured on the report fix, and the suite green again at
> 1323 / 157 / 0 on its tree; the shipped window is not yet re-measured.)* *(2026-09-25: the
> shipped window re-measured on the build that carries the fix — **614 pt** as a run starts and
> **615 pt** while it runs, 85 pt inside the budget. The 615 was recorded, not adopted, and became
> the spec later that day, by user decision.)* See
> [`PROGRESS.md`](PROGRESS.md) for the step in flight and [`BUILD-PLAN.md`](BUILD-PLAN.md) for the
> sequence and its gates.

## How the test works

For each block-aligned chunk, in order, from the first addressable block to the last:

1. **Read** the original data into a buffer.
2. **Write** that same data back to the same location.
3. **Read** the freshly written data into a second buffer.
4. **Compare** the two reads. A mismatch is a failed block range.

All of it is raw, uncached, block-level I/O through `/dev/rdiskN` with `F_NOCACHE` — the
page cache would otherwise serve step 3 from memory and turn the verify into a test of RAM.
At the start of every run the tool **verifies that its reads really are bypassing the cache**
and reports the outcome; a failed or inconclusive check qualifies the verify result rather
than blocking the run, because the refresh half stays valid either way.

Chunk size is the user-selected **I/O size** — 1, 2, 4 or 8 MiB, defaulting to 4 MiB — fixed
for the whole of a run, including across a pause. The final chunk is sized to exactly the
remaining blocks. All I/O begins at a whole multiple of 1 MiB from the start of the device,
and the privileged helper **enforces that itself** rather than trusting the caller.

## What a clean pass proves — and what it does not

A clean pass means **no currently-unreadable blocks were found**. It does not mean the drive
is healthy.

The USB block layer hands back corrected data without saying it had to correct it, so a
block that is degrading but still recoverable reads back perfectly and is invisible to this
tool — or to any tool working at this level. What you get is a floor, not a bill of health.
The app says so on screen and in the exported report rather than only here.

Testing writes the whole drive, so on NAND it spends endurance. It is meant to be run
**infrequently**.

## Safety

The tool writes to a real drive with elevated privileges, so the guards are the design:

- **It refuses to start unless every volume on the device is unmounted**, and unless it holds
  an **exclusive whole-disk claim** on the device node. Not held means not started, and the
  error names which of the two failed.
- **Start owns the whole sequence** — check permission, unmount, claim, run, release — so
  there is no window in which a run is underway without the claim that protects it.
- **Two clicks stand between the default selection and a write**: Start, then Proceed on a
  dialog that names the drive by **model and USB serial number** and cannot be dismissed to
  nothing.
- **Drives are identified by serial, never by BSD name, anywhere that outlives the
  enumeration.** This was learned, not assumed: a reboot renumbered the author's machine so
  that the designated scratch drive stopped being `disk4` and the **22 TB backup drive became
  `disk4`**. Every gate script now resolves its target through
  [`scripts/lib/device-identity.sh`](scripts/lib/device-identity.sh), which asks the app's own
  enumerator for the drive with the expected serial, cross-checks its block count, and refuses
  otherwise. Live UI still shows the BSD name beside the serial, because it is the locator
  that ties the window to `diskutil`.
- **Back up first.** The cycle is non-destructive by design, but a power loss or an unplug
  mid-chunk can still lose the chunk in flight, and there is no journal and no resume — an
  interrupted run restarts from block 0.

## Features

- **Device discovery** — enumerates connected USB mass-storage devices in a stable order,
  live-refreshing while no run is in progress. The internal disk is excluded by discovery,
  not by name.
- **Two failure modes** — *Stop on first error*, or *Log and continue* (the default), which
  records each failed block range and refreshes the rest of the drive.
- **Live metrics** — average read and write throughput, per-chunk read latency (min, max,
  p99, computed in constant memory), progress and a real-time ETA.
- **Run control** — start, pause, resume, stop. A pause settles at a **chunk boundary**, with
  the previous read → write → verify complete and nothing in flight, so pausing can never
  leave a chunk half-written.
- **End-of-run report** — the outcome, the throughput and latency statistics, and every
  failed block range, **exportable as Markdown** for the drive's records. Runs are standalone;
  the app keeps no history.

## Architecture

Two executables, because raw block access needs privilege and a GUI should never hold it:

| | |
|---|---|
| **`USBDriveTester.app`** | Unprivileged SwiftUI app. All control and monitoring. Never elevated. |
| **`com.arc3solutions.USBDriveTester.Helper`** | Privileged LaunchDaemon, registered via `SMAppService`. Performs *all* raw block I/O. |

They talk over NSXPC. The helper **validates the calling client's code signature** before
accepting any privileged command, and enforces the alignment and placement rules itself
rather than trusting what it is told.

The app is **not sandboxed** — raw device access and daemon registration are incompatible
with it — and the hardened runtime is on for both targets.

## Requirements

- **macOS 26 (Tahoe)** or later
- **Apple Silicon** — the project builds `arm64` only
- **Xcode 26** or later to build
- **Full Disk Access** for the app, so its helper can open a USB device's raw node. The app
  detects whether it has been granted and asks for it at the start of a run, with a button
  that opens the right System Settings pane.

## Build & run

Clone the repo and open **`USBDriveTester/USBDriveTester.xcodeproj`** in Xcode. In **Signing
& Capabilities**, select your own **Team** for both targets — the checked-in team id is the
author's. Then **⌘R**.

From the command line, from the repository root:

```bash
scripts/build.sh Debug
```

`build.sh` points `xcodebuild` at a full Xcode via `DEVELOPER_DIR`, because the active
developer directory on the author's machine is Command Line Tools. It defaults to
`/Applications/Development/Xcode.app`; export `DEVELOPER_DIR` yourself if your Xcode lives
somewhere else — which, for most people, it does:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/build.sh Debug
```

## Installing the helper

Install the app to `/Applications` before registering the daemon:

```bash
scripts/install-app.sh Debug
```

**This is not optional tidiness.** `SMAppService` records the *path* of the app that
registered a daemon. Registering from a DerivedData build directory works exactly once —
that path is then rebuilt and replaced, stranding the registration on a binary that no
longer exists. The symptom is a status stuck on `.notFound` or `.requiresApproval` no matter
how often you re-register, and the only sanctioned cleanup for a wedged Background Task
Management record is `sfltool resetbtm`, which resets it for **every app on the machine**.

Launch the app, register the helper when prompted, and approve it in **System Settings →
General → Login Items**. Grant **Full Disk Access** in **System Settings → Privacy &
Security**. The app can also cleanly unregister and remove the helper.

## Verification

The core algorithm is built against an in-memory simulated device, so the whole
read → write → verify engine, its metrics and its failure handling are testable without
touching hardware.

```bash
scripts/test.sh
```

**The test count is part of the result.** The script keeps a floor in
[`scripts/.test-floor`](scripts/.test-floor) and fails the run if fewer tests execute than
the most this repo has ever seen. That exists because on 2026-08-18 a build race produced
`✔ Test run with 624 tests in 98 suites passed` on a suite of 964 — **340 tests did not run
and the output said "passed"**. A green tick alone means "everything that ran, passed",
which is a different claim. The floor ratchets upward by itself and only ever refuses to go
down.

Alongside it:

| | |
|---|---|
| [`scripts/build-tools.sh`](scripts/build-tools.sh) | Type-checks all 14 command-line gate clients in [`tools/`](tools/), so an XPC protocol bump cannot leave one silently uncompilable, and shows their compiler warnings |
| [`scripts/render-ui.sh`](scripts/render-ui.sh) | Renders 40 UI states headlessly through [`tools/ui-probe`](tools/ui-probe) |
| [`scripts/window-fit-check.sh`](scripts/window-fit-check.sh) | Holds the window to a committed 700 pt budget across a range of display sizes |
| The hardware gates | Run against real drives, resolving their target by serial — see the *Test hardware* section of [`BUILD-PLAN.md`](BUILD-PLAN.md) |

Some things no test reaches — a SwiftUI `alert` gets its own window and cannot be captured,
and permission prompts need a human. Those live in
[`progress/step-11-human-checklist.md`](progress/step-11-human-checklist.md) and are walked
by hand, rather than being quietly assumed.

## Repository layout

| Path | What it is |
|---|---|
| [`CONSTRAINTS.md`](CONSTRAINTS.md) | **The highest-value file here.** Measured behaviour that binds design, settled decisions not to re-open, and the lessons already paid for |
| [`BUILD-PLAN.md`](BUILD-PLAN.md) | The 16-step plan, each step's verification gate, the process gotchas, the test hardware |
| [`PROGRESS.md`](PROGRESS.md) | The step in progress, and only that |
| [`ADR-001-usb-drive-tester.md`](ADR-001-usb-drive-tester.md) | The architecture decision record |
| [`functional-requirements-usb-drive-tester.md`](functional-requirements-usb-drive-tester.md) · [`nonfunctional-requirements-usb-drive-tester.md`](nonfunctional-requirements-usb-drive-tester.md) | The requirements, with dated amendment entries where a decision changed one |
| [`USBDriveTester/`](USBDriveTester/) | The Xcode project: app target, helper target, test target |
| [`scripts/`](scripts/) · [`tools/`](tools/) | The verification harness |
| [`progress/`](progress/) | Archived per-step history — for *"why was it done that way?"* |

The full account of each increment lives in its **commit message**; `PROGRESS.md` carries a
summary and the hash.

## Not included (by design)

No SMART or NVMe health polling — SAT pass-through over USB-to-SATA bridges is too
unreliable to build on. No pipelined I/O; the first release ships one chunk in flight. No run
history, no multi-device or queued testing, no crash-safe journaling or resume, and no
verify-only mode. See the *Out of Scope* section of the functional requirements for why each
one was cut.

## License

[MIT](LICENSE) © 2026 ARC3 Solutions

USBDriveTester is a sibling to **NetSpeed** and **DriveSpeed**, which monitor network and
local disk throughput respectively.
