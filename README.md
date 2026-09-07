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

> ### Status: in development — Step 12 of 16 is in progress
>
> Steps 1–11 and Step 14 are complete and committed. **Step 11 (run control: start / pause /
> resume / stop) closed on 2026-09-05** — all twelve increments landed and gated, its 16-chunk
> human checklist walked in full, and its verification gate re-run against the current XPC
> protocol. **Step 12 — device-loss handling — is IN PROGRESS: chunks 0–6 of 8 are done**, and
> chunk 7 (the mutation-round checklist, the physical-unplug hardware gate, and all four hardware
> gates re-run) is not. The engine, the privilege plumbing, the safety guards, metrics, reporting,
> run control and the pre-run warnings all exist and are exercised on real hardware. Sleep
> prevention, logging consolidation and notarization do not yet.
>
> ⚠️ **This block said *"Step 12 … is next and is not yet started"* until 2026-09-07** — wrong
> since chunk 1 landed on 2026-09-05, through seven chunks and a protocol bump. That is the
> **eighth** status block this repository has shipped disagreeing with the body under it, and the
> second one outside `BUILD-PLAN.md`. It was missed because the check greps for the *claim* and
> nobody thought of the README as a place where the current step is named. **It is. Add it to the
> grep.**
>
> **Nothing is distributed until the whole plan is complete** (Step 16). There is no preview
> build and no notarized release; every build so far runs on the author's machine.
>
> Current verified state: **1288 tests / 152 suites / 0 failures**, zero source warnings from
> three clean builds, **13/13** gate clients type-checking, XPC protocol v15. See
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
| [`scripts/build-tools.sh`](scripts/build-tools.sh) | Type-checks all 13 command-line gate clients in [`tools/`](tools/), so an XPC protocol bump cannot leave one silently uncompilable |
| [`scripts/render-ui.sh`](scripts/render-ui.sh) | Renders 37 UI states headlessly through [`tools/ui-probe`](tools/ui-probe) |
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
