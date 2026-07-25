# Functional Requirements: USB Drive Retention & Hard-Fault Tester

**Status:** Baselined
**Date:** 2026-06-25
**Baselined:** 2026-06-25
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
| FR-DEV-3 | The system shall select the first discovered device as the default selection in the list. | M | PB Upon launch |
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
| FR-SAFE-5 | The system should offer the user the option to unmount the device's volumes from within the application. | C | Derived from PB/ADR (convenience) |

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
| FR-CTRL-8 | The system shall provide an **"I/O size"** dropdown control offering the values 1 MiB, 2 MiB, 4 MiB, and 8 MiB, defaulting to 4 MiB, configurable before a run starts and fixed for the duration of that run. | M | user decision 2026-06-25 |
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

## Open Questions

None outstanding — all questions from iterations 1–2 have been resolved (see *user decision 2026-06-25* annotations throughout).
