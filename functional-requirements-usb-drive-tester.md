# Functional Requirements: USB Drive Retention & Hard-Fault Tester

**Status:** Baselined (amended — see [Amendments](#amendments-to-the-baseline))
**Date:** 2026-06-25
**Baselined:** 2026-06-25
**Last amended:** 2026-08-05 (FR-SAFE-5 withdrawn, FR-SAFE-6 reversed, FR-SAFE-7 moot — the run owns unmount and acquire)
**Last recorded (no change):** 2026-08-06 (when a BSD name may be used; FR-DEV-3 confirmed under challenge)
**Source documents:** [USBDriveTester.md](USBDriveTester.md), [ADR-001-usb-drive-tester.md](ADR-001-usb-drive-tester.md)
**Companion document:** [Non-Functional Requirements](nonfunctional-requirements-usb-drive-tester.md) (Baselined 2026-06-25)

## Purpose & Scope

This document specifies the **functional requirements** — the observable behaviors and capabilities the system must provide. Quality attributes (performance targets, security hardening, reliability, usability standards, platform/compatibility constraints, maintainability) are deliberately excluded and will be captured in the companion non-functional requirements document.

## Conventions

- Each requirement has a unique ID of the form `FR-<AREA>-<n>`.
- "**shall**" denotes a mandatory requirement; "**should**" a recommended one.
- **Priority** uses MoSCoW: **M** (Must have for first release), **S** (Should have), **C** (Could have / later).
- **Source** cites the originating statement in the product brief (PB) or ADR.

## Functional Areas

| Area code | Description |
|-----------|-------------|
| ARCH | Application architecture & privilege model |
| DEV  | Device discovery & selection |
| SAFE | Pre-test safety guards |
| TEST | Test execution core (read → write-back → verify) |
| FAIL | I/O failure handling |
| CTRL | Run control state machine |
| METR | Metrics capture & live monitoring |
| RPT  | End-of-run reporting |
| WARN | User warnings & honest framing |

---

## FR-ARCH — Application Architecture & Privilege Model

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-ARCH-1 | The system shall be delivered as two executables: an unprivileged GUI application and a privileged helper that performs raw block-level I/O. | M | PB Software Architecture; ADR Decision |
| FR-ARCH-2 | The GUI application shall provide all device-control and monitoring functions and shall never itself run with elevated privileges. | M | ADR Decision; ADR Pros |
| FR-ARCH-3 | The privileged helper shall be registered/installed as a LaunchDaemon via `SMAppService`. | M | ADR Decision; Action Item 2 |
| FR-ARCH-4 | The GUI and helper shall communicate over an authenticated XPC connection. | M | ADR Decision |
| FR-ARCH-5 | The helper shall validate the calling client's code signature before accepting privileged commands. | M | ADR Cons; Action Item 2 |
| FR-ARCH-6 | The system shall perform all raw, uncached, block-level read and write operations exclusively within the privileged helper. | M | ADR Decision |

## FR-DEV — Device Discovery & Selection

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-DEV-1 | On launch, the system shall enumerate all connected USB mass-storage devices and display them in a list view. | M | PB Upon launch; Action Item 3 |
| FR-DEV-2 | The device list shall be presented in a stable order (sorted by BSD device name). | M | ADR Action Item 3 |
| FR-DEV-3 | The system shall select the first discovered device as the default selection in the list. | M | PB Upon launch; **confirmed under challenge 2026-08-06** — see Amendments before proposing a "smarter" default |
| FR-DEV-4 | The user shall be able to change the selected device from the list before starting a test. | M | PB Upon launch (implied) |
| FR-DEV-5 | For the selected device, the system shall determine and use the device's logical block size and total block count. | M | ADR Action Item 5 |
| FR-DEV-6 | The system should display identifying information for each listed device sufficient for the user to distinguish devices (e.g., BSD name, capacity, model/identifier). | S | PB Upon launch (implied) |
| FR-DEV-7 | The system should reflect device connect/disconnect changes in the list while no test is running. | S | PB Upon launch (implied) |
| FR-DEV-8 | If the device under test is hot-unplugged or de-enumerates from the USB bus during a run, the system shall immediately terminate the test, present a suitable error message, and re-run the initial device discovery routine (FR-DEV-1). | M | user decision 2026-06-25 |

## FR-SAFE — Pre-Test Safety Guards

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-SAFE-1 | The system shall not begin a read/write test while any volume belonging to the selected device is mounted by the macOS file system. | M | PB Managing Mounted Volumes |
| FR-SAFE-2 | The system shall verify that all volumes belonging to the selected device are unmounted before starting a test. | M | PB Managing Mounted Volumes |
| FR-SAFE-3 | The system shall acquire exclusive whole-disk access to the device node (e.g., via DiskArbitration claim / `diskutil unmountDisk`) and shall not start a test unless exclusive access is held. | M | ADR Consequences; Action Item 4 |
| FR-SAFE-4 | When a test cannot start, the system shall display a clear error message identifying the actual cause: (a) one or more of the device's volumes are still mounted (instruct the user to unmount them), or (b) the volumes are unmounted but exclusive whole-disk access cannot be acquired because the device node is claimed by another process. | M | PB Managing Mounted Volumes; ADR Consequences; Action Item 4 |
| FR-SAFE-5 | ~~Withdrawn 2026-08-05~~ — see Amendments. Was: a single Mount All / Unmount All control. Superseded by the run owning unmount and acquire. | — | **withdrawn 2026-08-05** |
| FR-SAFE-6 | ~~Reversed 2026-08-05~~ — see Amendments. Was: no implicit mount/unmount as a side effect of starting a test. Starting a test now **does** unmount the selected device's volumes and acquire exclusive access, and releases on completion. FR-SAFE-1/2/3 and NFR-REL-3 are unaffected — what changed is who performs the unmount, not whether it must have happened. | — | **reversed 2026-08-05** |
| FR-SAFE-7 | ~~Moot 2026-08-05~~ — see Amendments. Constrained the state of FR-SAFE-5's control, which no longer exists. The hazard it guarded against (mounting the device under test mid-run, violating NFR-REL-3) is now unreachable: no control can mount a device, and the run holds the claim for its own duration. | — | **moot 2026-08-05** |

## FR-TEST — Test Execution Core

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-TEST-1 | The system shall perform the test as a sequential, in-place **read → write-back → read-verify** cycle over the device's entire addressable range. | M | PB Test Algorithm; ADR Decision |
| FR-TEST-2 | The system shall process the device in block-aligned chunks whose size equals the user-selected I/O size (see FR-CTRL-8), defaulting to 4 MiB. | M | PB Test Algorithm; user decision 2026-06-25 |
| FR-TEST-3 | For each chunk, the system shall read the original data, write the same data back to the same location, then read the freshly written data into a second buffer and compare the two read buffers for differences. | M | PB Test Algorithm |
| FR-TEST-4 | The test shall begin at the first addressable block and proceed sequentially to the last addressable block. | M | PB Test Algorithm |
| FR-TEST-5 | The final chunk shall be sized to match exactly the remaining blocks, rounded up to the device's logical block size, never to an arbitrary byte remainder. | M | PB Test Algorithm |
| FR-TEST-6 | All test I/O shall be performed as raw, uncached, block-level access (e.g., `/dev/rdiskN` with `F_NOCACHE`/`F_GLOBAL_NOCACHE`). | M | PB Test Algorithm; ADR Action Item 5 |
| FR-TEST-7 | The test shall be non-destructive by design: data read from a location shall be the only data written back to that location (no patterns or known-value overwrites). | M | PB Test Algorithm; ADR Trade-off Analysis |
| FR-TEST-8 | When a verify comparison detects a mismatch, the system shall treat that chunk's block range as a failure and handle it per the selected failure-handling mode (see FR-FAIL). | M | PB Test Algorithm; PB Handling I/O Failures |
| FR-TEST-9 | At the start of every run the system shall verify that its reads are not being served from the host buffer cache, and shall report that verification's outcome to the user and in the run report. A failed or inconclusive verification shall **qualify the verify result rather than prevent the run** — the read → write-back refresh remains valid, but fault detection may be unreliable. | M | user decision 2026-08-02 |
| FR-TEST-10 | All test I/O shall begin at an offset that is a whole multiple of **1 MiB** from the start of the device, and any bounded portion of a run shall cover a whole multiple of 1 MiB **unless** it ends at the device's final addressable block. The privileged helper shall enforce both rather than trusting the caller. | M | user decision 2026-08-04 |

## FR-FAIL — I/O Failure Handling

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-FAIL-1 | The system shall provide two user-selectable failure-handling modes, chosen before a run starts: **Stop on first error** and **Log and continue**. | M | PB Handling I/O Failures |
| FR-FAIL-2 | In **Stop on first error** mode, the system shall halt immediately on any I/O failure and report the offending block range. | M | PB Handling I/O Failures |
| FR-FAIL-3 | In **Log and continue** mode, the system shall record each offending block range to a bad-block list and continue refreshing the remainder of the device. | M | PB Handling I/O Failures |
| FR-FAIL-4 | **Log and continue** shall be the default failure-handling mode. | M | PB Handling I/O Failures; ADR sub-decision |
| FR-FAIL-5 | In both modes, the run shall conclude with a report listing every failed block range (see FR-RPT). | M | PB Handling I/O Failures |
| FR-FAIL-6 | The system shall classify and record both hard I/O failures (read or write errors) and verify mismatches as block-range failures. | M | PB Handling I/O Failures; PB Test Algorithm |
| FR-FAIL-7 | The system shall not journal in-flight chunks and shall not support resuming a partially completed run. If a run is halted by a data transfer error (in Stop-on-first-error mode), terminated by device loss (FR-DEV-8), or otherwise interrupted, the system shall report the error and the run must be restarted from the beginning. | M | user decision 2026-06-25 |

## FR-CTRL — Run Control State Machine

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-CTRL-1 | The user shall be able to start a test on the selected device. | M | PB Features; Action Item 10 |
| FR-CTRL-2 | The user shall be able to pause a running test. | M | PB Features |
| FR-CTRL-3 | The user shall be able to resume a paused test from the point of pause. | M | PB Features |
| FR-CTRL-4 | The user shall be able to stop a running or paused test. | M | PB Features |
| FR-CTRL-5 | The user shall be able to restart a test from the beginning. | M | PB Features |
| FR-CTRL-6 | The system shall enforce valid control transitions via a defined run-control state machine (e.g., resume only from paused, pause only while running). | M | ADR Action Item 10 |
| FR-CTRL-7 | The system shall require the user to select the failure-handling mode (FR-FAIL-1) before a run can be started. | M | PB Handling I/O Failures |
| FR-CTRL-8 | The system shall provide an **"I/O size"** dropdown control offering the values 1 MiB, 2 MiB, 4 MiB, and 8 MiB, defaulting to 4 MiB, configurable before a run starts and while a run is paused or stopped, and fixed while a run is actively running. A run resumed after a size change continues from its point of pause using the newly selected size. | M | user decision 2026-06-25; **revised 2026-08-04** |
| FR-CTRL-9 | The system shall test only one device at a time; a new run shall not be startable while another run is in progress. | M | user decision 2026-06-25 |

## FR-METR — Metrics Capture & Live Monitoring

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-METR-1 | The system shall measure and maintain the average read throughput and average write throughput during a run. | M | PB Features |
| FR-METR-2 | The system shall display read and write throughput in the GUI. | M | PB Features |
| FR-METR-3 | The system shall capture per-chunk read latency statistics, including at minimum the minimum, maximum, and a high percentile (e.g., p99). | M | PB Features |
| FR-METR-4 | The system shall display the read-latency statistics in the GUI. | M | PB Features; Action Item 8 |
| FR-METR-5 | The system shall display test progress and a real-time ETA derived from measured throughput. | M | ADR Trade-off Analysis; Consequences |
| FR-METR-6 | The system should indicate the current chunk/position (e.g., current block offset) during a run. | S | Derived from progress/ETA needs |

## FR-RPT — End-of-Run Reporting

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-RPT-1 | At the end of a run, the system shall produce a report listing every block range that failed (hard I/O error or verify mismatch). | M | PB Handling I/O Failures |
| FR-RPT-2 | The end-of-run report shall include the throughput statistics (average read/write). | M | PB Handling I/O Failures; PB Features |
| FR-RPT-3 | The end-of-run report shall include the read-latency statistics (min, max, p99). | M | PB Handling I/O Failures; PB Features |
| FR-RPT-4 | The report shall convey the run outcome (e.g., completed clean, completed with failures, stopped on error, stopped by user). | M | Derived from FR-FAIL / FR-CTRL |
| FR-RPT-5 | The system shall allow the report (including the bad-block list, throughput, and latency statistics) to be exported to a file in Markdown format for the user's records. | M | user decision 2026-06-25; ADR "auditable" |

## FR-WARN — User Warnings & Honest Framing

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-WARN-1 | Before a run, the system shall warn the user that although the test is intended to be non-destructive, data loss or corruption remains possible, and the device should be backed up before testing. | M | PB Features; Action Item 10 |
| FR-WARN-2 | The system shall warn the user that this type of testing should be performed only infrequently on NAND devices. | M | PB Features; Action Item 10 |
| FR-WARN-3 | The system shall clearly communicate that a clean pass means "no currently-unreadable blocks were found," not that the drive is healthy. | M | PB What the Test Does and Does Not Prove; Action Item 10 |
| FR-WARN-4 | The system should communicate that the tool acts as both a retention refresher and a hard-fault detector, and that degrading-but-still-correctable blocks cannot be detected at the USB block level. | S | PB What the Test Does and Does Not Prove |

---

## Out of Scope (Functional)

- **SMART / NVMe health polling.** Excluded due to unreliable SAT pass-through on USB-to-SATA bridges. (Possible future fast-follow for USB-NVMe enclosures.) — *ADR Telemetry sub-decision; PB What's Not Included*
- **Pipelined / overlapped I/O.** First release ships the simple one-chunk-in-flight model; pipelining is a later optimization. — *ADR Trade-off Analysis; To revisit*
- **Run history.** Each run is standalone; the system shall not retain a history of previous test runs. (Reports may still be exported per FR-RPT-5.) — *user decision 2026-06-25*
- **Multi-device / queued testing.** Only one device is tested at a time (see FR-CTRL-9); batch or queued testing of multiple devices is not in scope. — *user decision 2026-06-25*
- **Crash-safe journaling & resume.** Removed. The system does not journal in-flight chunks and does not support resuming an interrupted run; any interrupted or aborted run is restarted from the beginning (see FR-FAIL-7). The residual in-flight data-loss window is accepted and covered by the mandatory back-up warning (FR-WARN-1). — *user decision 2026-06-25*
- **Verify-only mode.** Removed. The system performs only the full read → write-back → read-verify cycle. — *user decision 2026-06-25*

## Deferred to Non-Functional Spec

- **Readability / presentation of throughput and latency.** The product brief's "easily readable from the user interface" intent is a usability quality and will be specified in the companion non-functional requirements document. The functional spec only requires that throughput (FR-METR-2) and latency (FR-METR-4) are displayed.

## Amendments to the Baseline

Changes made after the 2026-06-25 baseline. Recorded here so the delta from the
baselined set is auditable rather than silently absorbed into the tables above.

> **Latest: 2026-08-06/07 — four GUI decisions from Step 10**, at the end of this section. No
> requirement text changes, but one of them records a **measured** constraint on any code that
> unmounts, and another explains why the live metrics panel no longer retains a finished run
> without FR-METR being affected.

### 2026-07-30 — FR-SAFE-5 revised; FR-SAFE-6 and FR-SAFE-7 added

**Trigger.** User decision during Step 6 scoping.

**FR-SAFE-5 — revised, and elevated from priority C to M.** Previously: *"The system
should offer the user the option to unmount the device's volumes from within the
application."* Now specifies a **single bidirectional control** whose label and action
track the selected device's mount state ("Unmount All" / "Mount All"), disabled when no
device is selected.

Three substantive changes:
1. **Mounting is now in scope.** The baselined requirement covered unmounting only.
   Mounting was not a requirement at all, and is a genuine addition rather than a
   clarification — a drive left unmounted after a test previously had to be remounted
   through Disk Utility or the Finder.
2. **Priority C → M.** It is now a specified part of the safety UI, not a convenience.
3. **The control's state is specified**, not just its existence, because the label is
   what tells the user which way the action will go. A control whose text and behaviour
   could disagree would be worse than no control on a screen whose job is preventing the
   wrong drive being touched.

**FR-SAFE-6 — added.** Makes explicit what FR-SAFE-4(a) implies: a mounted volume causes
a *refusal with instructions*, never an implicit unmount. Starting a test must never
change the mount state as a side effect. This closes an ambiguity between FR-SAFE-4(a)
and BUILD-PLAN Step 6.2, which described unmounting the whole disk as part of acquiring
access.

**FR-SAFE-7 — added, derived rather than requested.** The control must also be disabled
during a run or while the helper holds exclusive access. Not part of the user's stated
rule, which addressed only the no-selection case, but mounting a device mid-run would
violate NFR-REL-3 directly. Flagged as derived so it is easy to identify and reverse.

### 2026-08-02 — FR-TEST-9 added (run-start cache-bypass verification)

**Trigger.** User decision during Step 7 scoping, proposed by the user in response to the
finding below.

**What was found.** FR-TEST-6 requires uncached I/O and names the mechanism
(`/dev/rdiskN` with `F_NOCACHE` / `F_GLOBAL_NOCACHE`). Step 7 scoping established that
**setting that mechanism cannot be verified by its own return value**: measured 2026-08-02,
`fcntl(fd, F_NOCACHE, 1)` returns `0` on `/dev/null`, a target that plainly does no
raw-disk caching. There is also no `F_GETNOCACHE` — the flag cannot be read back. A zero
return proves the syscall was accepted, not that caching was suppressed.

**Why that gap is serious enough to be its own requirement.** If the buffer cache can
satisfy the verify read of FR-TEST-3, the engine compares buffer A against a cached copy of
buffer A and the comparison succeeds unconditionally. The tool would then report **every**
drive as clean, including a failing one, with no error raised anywhere — FR-TEST-8 and
NFR-REL-8 would both be silently inert. That is the single worst outcome available to a
tool whose purpose is detecting failing NAND, and nothing in the baselined set would have
caught it.

**Why it qualifies the result instead of blocking the run.** The two halves of the product
fail independently. A cached *read* does not prevent the write-back from reaching the
device, so the charge-retention refresh — the other reason this tool exists — still happens
and is still valid. Blocking the run would therefore withhold a working feature to protect
a broken one. Reporting instead preserves the refresh and tells the user exactly which
half of the result they may not rely on.

**Why the report, and not just the UI.** The Markdown export of FR-FAIL / ADR Action
Item 7 outlives the session. A report stating "0 bad blocks" that has outlived the banner
qualifying it reproduces the original silent failure with extra steps, so the qualification
travels with the report.

**Priority M, not S.** Without it the product's primary claim — that it detects hard faults
— can be false with no indication. It is a correctness-of-reporting prerequisite, not a
degradation.

**Consequences elsewhere.** Step 7 builds the mechanism (a pure classifier plus the
helper-side timing harness); Step 8 consumes it at run start and gates the verify result on it;
Step 10 carries the qualification into the exported report; Step 11 surfaces it in the UI;
Step 14's honest-framing warnings are its natural neighbour.

> **Clarified 2026-08-02 (Step 8), because "at the start of every run" was being read as "run
> the check at run start".** The verification is performed **when the device is acquired** — it
> is `fstat` plus the two `fcntl` results on the descriptor — and its verdict is **consumed** by
> the run. There is nothing to re-run: opening the raw node speculatively to ask again is what
> makes DiskArbitration remount the volume ~4 ms later (measured 2026-08-01). It satisfies the
> requirement because the acquire holds that same descriptor continuously from the check to the
> run, and the helper holds at most one device at a time (FR-CTRL-9).
>
> **What Step 8 added is the falsifier's live half.** Each read's throughput is fed into the
> assessment as the run proceeds, and can only ever **downgrade** the verdict — a plausible rate
> is what an uncached read and a slow cache hit look like alike, so it never promotes. Measured
> on the scratch device 2026-08-03: a full run's fastest read was 492,870,060 B/s and the verdict stayed
> `bypassed`. The falsifier was independently shown to fire — a run against an in-memory device,
> under the real clock, is correctly flagged `likelyCached`, because it genuinely *is* answered
> from RAM.

**The open risk was measured the same day, and it was real.** Recorded here because it
changes how the requirement is met, though not what it requires. `scripts/nocache-calibration.sh`
on the scratch device established that a re-read timing comparison **cannot discriminate**: with
`F_NOCACHE` unset, repeated reads of one region took 12.3 ms then ~8.8 ms; with it set,
~8.9 ms throughout. A 4 MiB copy from RAM on the same machine takes 58 µs, so a genuine cache
hit would be ~150× faster than either — the small first-read difference is warm-up, not
caching. The cause is that `/dev/rdiskN` is the **character** device (`crw-`) while
`/dev/diskN` is the block device (`brw-`), and the buffer cache belongs to the block node;
the raw path was never cached, so there was nothing for the flags to suppress.

**The requirement's wording is unaffected** — it specifies what must be verified, never how.
The mechanism becomes structural rather than statistical, because timing turns out to be able
to *falsify* (a read 150× faster than the transport allows proves a cache hit) but not to
*verify* (similar timings are identical whether caching was suppressed or was never
possible). Verification therefore rests on asserting the descriptor is the character device
(`fstat` → `S_ISCHR`), which also catches the one failure that can realistically occur:
opening `/dev/diskN` instead of `/dev/rdiskN`. Timing is retained only as a falsifier.

**A limit this exposed, which no mechanism can close.** Neither the structural check nor any
other host-side test can establish that a verify read came from **NAND**. The drive's own
DRAM/SLC cache sits below every host mechanism, and a read-back moments after a write may
legitimately be served from it. The verify proves the data round-tripped through the device's
I/O path; it does not prove the medium retained it. This is a genuine constraint on what a
clean pass means and belongs with FR-WARN-3's honest framing rather than being carried
silently.

### 2026-08-04 — FR-TEST-10 added; FR-CTRL-8 revised

**Trigger.** User decisions during Step 9 scoping, after a proposal to let the user type a
starting block was rejected.

**FR-TEST-10 — added.** Every I/O begins on a **1 MiB boundary**, and a bounded portion of a run
covers a whole multiple of 1 MiB unless it ends at the device's last block.

**Why 1 MiB, and why this is not a tidiness rule.** It keeps starting LBAs in sync with all four
UI-selectable transfer sizes, and it makes it far more likely that an I/O begins on one of the
device's *physical* block boundaries — 1 MiB alignment implies 4 KiB page alignment and covers
most erase-block sizes. Physical geometry cannot be queried, so this improves the odds rather than
guaranteeing anything, which is exactly how the user framed it.

The consequence that makes it a correctness rule rather than a performance one: a misaligned start
makes the device perform read-modify-write internally, which **depresses measured throughput and
adds wear**. FR-METR-1's throughput figure exists so the user can compare it against the
manufacturer's advertised sustained rate as a wear heuristic (see below). Misaligned I/O would
therefore manufacture the exact signal the measurement exists to detect — a systematic bias toward
"this drive looks worn", on a tool whose output is a judgement about somebody's hardware.

**Why the length rule, and not just the start.** A whole-device run is covered as a sequence of
bounded calls (`TesterProtocol.maximumBytesPerCall`, 1 GiB). If any call covers a length that is
not a whole number of MiB, the *next* call starts misaligned — so enforcing only the start would
let a caller walk itself out of alignment one call at a time. The exemption for a range ending at
the device's final block is FR-TEST-5's short final chunk, which is legitimate and unavoidable:
the scratch device is 1,953,525,168 blocks, which is 953,869 whole MiB plus 1,456 blocks.

**Why the helper enforces it.** NFR-REL-7 — the helper re-checks rather than trusting the caller.
Making a misaligned start unexpressible in the GUI is right, but the GUI is not the only caller:
the CLI gate clients are, and so is anything signed under the Team ID.

**It is self-maintaining for a real run, and that is the point.** Runs always begin at block 0
(FR-TEST-4), and a position reached after any mix of {1,2,4,8} MiB chunks is always an integer
number of MiB. So no transfer-size change can produce a misaligned resume, and the helper's check
is a guard against a *caller*, never against the run's own arithmetic.

**Found immediately, and worth recording.** Step 8's hardware gate requested `1 GiB − 512 KiB` —
deliberately, to force a short final chunk on real media — which is 1023.5 MiB and would have been
**refused** by this rule, roughly 35 minutes into the gate's before-fingerprint pass. Changed to
`1 GiB − 1 MiB`, which still yields 255 full 4 MiB chunks plus a short 3 MiB one, so FR-TEST-5 is
still exercised and the expected chunk count is unchanged at 256.

**FR-CTRL-8 — revised.** Previously the I/O size was "configurable before a run starts and **fixed
for the duration of that run**". It is now also configurable **while a run is paused or stopped**,
and a resumed run continues from its point of pause using the newly selected size. Fixed only
while actively running.

Two consequences follow, both of which the metrics design already had to satisfy for other
reasons:

1. **Progress must be measured in bytes, not chunks.** A size change alters how many chunks remain,
   so a chunk-denominated percentage would jump at the moment of the change.
2. **Read-latency statistics span the sizes used.** An 8 MiB read takes roughly twice as long as a
   4 MiB one, so a run whose size changed has a bimodal latency distribution. The statistics
   **keep accumulating** rather than resetting (user decision 2026-08-04): a drive that produced
   one 30-second read at 4 MiB is showing retry behaviour that matters regardless of what was
   selected afterwards, and resetting would delete that evidence. The run report records which
   sizes were used.

**A slider was considered and rejected** for the progress display: a slider implies the thumb can
be dragged, and the starting block is never user-selectable. A progress bar with a live percentage
says only what is true.

### 2026-08-05 — FR-SAFE-5 withdrawn; FR-SAFE-6 reversed; FR-SAFE-7 moot; FR-SAFE-4(a) remedy revised

**Trigger.** User decision during Step 9's UI work, on reviewing the shipped main window.

> *"For the production version of this tool, I can see no reason for the 'Unmount All' button, the
> 'Acquire exclusive access' button and the 'Release' buttons… What I expected was to be able to
> select a drive and immediately start a test run. The software should automatically unmount and
> acquire exclusive access to the drive as part of the test run itself."* — user, 2026-08-05

**FR-SAFE-6 — reversed.** It read: *"The system shall not mount or unmount any volume implicitly as
a side effect of starting a test. Mounting and unmounting shall occur only in response to explicit
user action through the control of FR-SAFE-5."* Starting a test now **does** unmount the selected
device's volumes and acquire exclusive access as part of the start transition, and releases on
completion, cancellation or failure — after which macOS remounts the volumes on its own.

**FR-SAFE-5 — withdrawn.** The single Mount All / Unmount All control is removed along with the
acquire and release controls. Its no-selection and during-run states (FR-SAFE-7) go with it.

**FR-SAFE-4(a) — remedy revised, not the requirement.** The system must still identify the actual
cause when a test cannot start. What changes is the instruction: where (a) previously told the user
to unmount the volumes themselves, the system now attempts the unmount, and reports and aborts if
it cannot — for example a volume held busy by another process. The distinction FR-SAFE-4 exists to
preserve, between "still mounted" and "unmounted but the node is claimed elsewhere", is unaffected.

**What does not change, and this is the point.** FR-SAFE-1, FR-SAFE-2, FR-SAFE-3 and **NFR-REL-3**
are untouched: no block write may occur unless every volume is unmounted **and** exclusive
whole-disk access is held. Unmount-then-acquire as part of starting satisfies that exactly. The
reversal is about *who performs the unmount*, never about whether it must have happened.

**Why the reversal is sound, given FR-SAFE-6 was itself a deliberate addition (2026-07-30).**

1. **The premise for elevating FR-SAFE-5 to M has lapsed.** The stated rationale was that *"a drive
   left unmounted after a test previously had to be remounted through Disk Utility or the Finder"*.
   Steps 6 and 7 then measured the opposite: releasing an `O_EXLOCK` open or a `DADiskClaim` makes
   DiskArbitration remount the volume within milliseconds. Confirmed from the shipped Release button
   on 2026-08-05. There is nothing for a Mount All control to do.
2. **The deliberate-confirmation role passes to FR-WARN-1/2/3**, which are M and must be
   acknowledged *before a run*. An explicit unmount click is a confirmation step in disguise; the
   warnings are one on purpose.
3. **It removes a class of defect rather than relocating it.** Tying the claim's lifetime to a UI
   selection produced a state where the app believed no device was held while the helper held one,
   greying out the only control that could give it back. A claim owned by the run cannot drift from
   the run.

**Sequencing, and a constraint on it.** The controls stay until **Step 11**, which owns the start
and terminal transitions, and their removal is gated on **Step 14**'s warnings existing — removing
the explicit unmount before there is any confirmation step would leave the product briefly *less*
guarded than either the current design or the intended one.

**Four GUI decisions recorded with it, none of them a requirement change.**

- **The device list's Refresh button is removed.** No requirement ever specified it; FR-DEV-7's
  live refresh is driven by IOKit arrival/departure and already keeps the list current. It was also
  the one control that let a user rebuild the list *during* a run, which is precisely what
  FR-DEV-7's freeze exists to prevent.
- **The helper's claim follows the selection.** Deselecting a drive, or selecting a different one,
  releases it — holding exclusive access to a device the UI does not name as selected is a mismatch
  between what the product shows and what it controls. Correspondingly, **the selection is frozen
  while a run is active**, since changing it would otherwise release the device under an active
  write. Both are interim behaviours that Step 11 subsumes when Start takes ownership of the claim.
- **The app has exactly one main window.** The main scene became a `Window` rather than a
  `WindowGroup`, which removes `File ▸ New Window`. A second main window would have carried its own
  device list and its own selection while sharing one exclusive claim, so the two could have named
  different drives while only one was held — **NFR-USE-3's hazard**, on the screen whose whole job
  is stopping the wrong drive from being written to. No requirement asked for a second window; this
  removes the means to create one rather than adding a rule against it.
- **Quitting or closing the main window during a run asks first, and quitting stops at the call
  boundary.** The dialog offers *Cancel and Quit* / *Continue Testing*; *Cancel and Quit* issues no
  further work, waits for the privileged call already in flight to return, releases the device, and
  then terminates. It deliberately does **not** claim to stop the run: there is no cancellation of
  a privileged call until FR-CTRL-4's machinery exists (Step 11), and a control that says "stop"
  without stopping is a capability claimed rather than held.

  Recorded as a decision rather than as a new requirement, because the territory belongs to
  **FR-CTRL** from Step 11 — at which point stopping *is* a capability and this behaviour becomes
  one branch of the run-control state machine rather than a rule of its own. What it rests on today
  is already required: **FR-FAIL-7** (an interrupted run cannot be resumed, so ending one by
  accident costs the whole run) and **NFR-REL-5** (terminate cleanly, issue no further writes,
  release the node). Quitting without asking was never *unsafe* — the helper releases a claim when
  the connection that took it goes away — so what this adds is deliberateness and an acknowledged
  release, not a safety property the product previously lacked.

### 2026-08-06 — when a BSD name may be used, and when it may not (no requirement change)

**Not an amendment**, and it changes no requirement text. Recorded because the surrounding work
that day — moving the test hardware and every gate script onto serial numbers — states the rule in
one direction only, and read alone it would justify stripping the BSD name out of the UI. That
would be a regression: FR-DEV-6 names it as identifying information and it earns its place.

> *"I like the idea of showing the BSD name anywhere live drive data is being displayed because it
> offers one more piece of identity disambiguation information. I just don't ever want to refer to
> drives by their BSD name for any purpose that might become stale upon unplug/re-plugs or reboots
> (like build plans, scripts, previous test results, etc.)."* — user, 2026-08-06

**The rule, and the test that generates it.** A BSD name is a **locator**, not an **identity**: it
is assigned at enumeration and names a different drive after a replug or a reboot. So the question
is never "is a BSD name allowed here?" but:

> **Does this statement outlive the enumeration that produced it?**

| lifetime | rule | examples |
|---|---|---|
| **Live** — read while the enumeration is still current | **Show it.** It is a real extra axis of disambiguation, it is what ties this window to `diskutil` and `/dev/rdiskN`, and it is checkable against the physical machine in the moment. | The device list row, the selected-device detail, the raw-device path, a live metrics heading, an `os_log` line about work in flight. |
| **Persisted** — read after that enumeration may have gone | **Never as the identity. Use the USB serial.** | BUILD-PLAN and PROGRESS, gate scripts and their command lines, the exported run report (FR-RPT), release notes, anything a person may copy into a shell later. |

Both halves matter. **Showing both is better than showing either**: the serial answers *which
drive is this?* across time, the BSD name answers *which of the things in front of me right now?*
— and a live surface that shows both lets a user cross-check one against the other. Where a
persisted artefact records a BSD name at all, it must be **labelled as the locator it was at the
time**, never presented as the answer to "which drive was tested?".

**What this constrains.** FR-DEV-6 and NFR-USE-3 are satisfied by showing BSD name, model, serial
and capacity together — that is the current UI and it should stay. **FR-RPT** is on the other side
of the line: the exported report outlives the session, so the drive it names must be identified by
serial (Step 10, and see BUILD-PLAN Step 16's release-note item for what a USB serial actually
names). Step 14's warnings are likewise persisted in the user's memory of what they agreed to, so
they identify by model and serial — with the BSD name available beside it as the locator, which is
useful precisely because the user is looking at the machine while they read it.

### 2026-08-06 — FR-DEV-3 confirmed under challenge (no change)

**Not an amendment.** FR-DEV-3's text is unchanged and its priority is unchanged. Recorded here
because the requirement was put to the user with a specific hazard in front of it, and a reader
who meets that hazard in BUILD-PLAN should know the question was asked and answered rather than
overlooked.

**The trigger.** A reboot renumbered this machine's drives (see BUILD-PLAN, "Test hardware"), and
the default selection — FR-DEV-3's first usable device, in FR-DEV-2's BSD-name order — landed on a
22 TB drive with Backup and Time Machine mounted. Both requirements were satisfied exactly as
written; what changed was which physical drive "first" names.

> *"FR-DEV-3 is perfect as written. I do not want to go down the road of trying to divine user
> intentions."* — user, 2026-08-06

**Why this is the same rule the tool already follows.** The alternatives all require the app to
prefer one drive over another — removable over fixed, unmounted over mounted, smaller over larger
— and every one of them is a guess about which drive its owner considers expendable. That is the
error FR-WARN-3 and the throughput-reporting decision (2026-08-04) exist to prevent, in a new
place: a judgement the tool is not entitled to make, presented as something it knows. A default
that guessed would be *more* dangerous than a graded throughput figure, because it would look
authoritative at the moment a user is choosing what to write to.

**What follows from it.** With FR-DEV-3 fixed, nothing upstream narrows the selection, so
**FR-WARN-1/2/3's acknowledgement carries the whole weight** — and the warnings must identify the
drive by model and **USB serial number**, never by BSD name, since a name can have moved since the
list was drawn. Recorded against Step 14, and it is why Step 11's removal of the explicit unmount
control is gated on Step 14 existing rather than merely sequenced after it.

### 2026-08-06/07 — four GUI decisions from Step 10 (no requirement change)

**Not amendments.** No requirement text changes. Recorded because each was taken from the user
exercising the shipped app, and three of them touch a requirement closely enough that a reader
would otherwise wonder whether it had been broken.

**1. The live metrics panel no longer retains a finished run — and FR-METR is still satisfied.**
Step 10 gave the finished run its own window with the full bad-block list and a Markdown export
(FR-RPT-1/5). The panel under the device list kept displaying the last run's figures indefinitely,
because `runProgress` returns them until a new run replaces them.

> *"I see no reason to retain the Last Run pane since all the information is redundant and the
> separate window & file exporting is far more valuable."* — user, 2026-08-06

**FR-METR-2/4/5/6 are M and are unaffected**: they require throughput, latency, progress and ETA to
be displayed **during** a run, and that display is untouched. What was removed is the *post-run*
retention, which no requirement asks for — and no report exists while a run is under way, so there
is nothing redundant about the live half. The idle panel now points at the report window, because a
placeholder that only said "nothing is running" would read as the result having been lost.

**2. Closing the main window quits the app.** Step 9 made the main scene a `Window` and left the
app running when it closed, reasoning that the Window menu brings it back. Observed in the product,
that leaves the app alive and invisible while the helper may still hold a claim — a drive
unmounted, with no UI to release it. An interim fix used
`applicationShouldTerminateAfterLastWindowClosed`, which fires only when *no* window remains, so
the behaviour depended on whether a panel opened earlier was still up:

> *"I don't think that this is an intuitive user experience. I think closing the main window should
> always try to terminate the app."* — user, 2026-08-06

The main window's close is now the quit request itself. It **cannot bypass the during-a-run
confirmation** — that refuses the close before AppKit can terminate — so FR-FAIL-7's protection of
an un-resumable run is unaffected.

**3. A failed unmount is undone.** `DADiskUnmount` leaves already-unmounted volumes unmounted when
one volume refuses, stranding a multi-volume drive half-dismounted:

> *"if any volume unmount operation fails for any reason, just post an error message with the error
> code (stated in english if available) and remount any volumes that did unmount successfully."*
> — user, 2026-08-06

FR-SAFE-5's control is withdrawn and Step 11 deletes it, so this is recorded as a decision rather
than a requirement — but **the behaviour outlives the control**: Step 11's Start owns
unmount → acquire → run, and its abort path reaches the same state with no manual control at all.
Carried as an inherited note on Step 11.

**4. And a measured fact that constrains anything which unmounts.** `DADiskUnmount` can report
**success while a volume is still mounted**, and the mount table lags its callback. Neither is
inferable from the API's own signal; both were found only by running the app and reading the
unified log. Any code that unmounts must verify the mount table, and must re-read it until it
settles rather than trusting the first look. This is the same shape as FR-TEST-9's origin —
`fcntl(F_NOCACHE)` returning 0 on `/dev/null` — and for the same reason: **an API accepting a
request is not the request having had its intended effect.**

## Open Questions

None outstanding — all questions from iterations 1–2 have been resolved (see *user
decision 2026-06-25* annotations throughout), and the 2026-07-30, 2026-08-02, 2026-08-04,
2026-08-05 and 2026-08-06 amendments above are recorded rather than open.
