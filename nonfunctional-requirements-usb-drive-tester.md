# Non-Functional Requirements: USB Drive Retention & Hard-Fault Tester

**Status:** Baselined
**Date:** 2026-06-25
**Baselined:** 2026-06-25
**Source documents:** [USBDriveTester.md](USBDriveTester.md), [ADR-001-usb-drive-tester.md](ADR-001-usb-drive-tester.md)
**Companion document:** [Functional Requirements](functional-requirements-usb-drive-tester.md) (Baselined 2026-06-25)

## Purpose & Scope

This document specifies the **non-functional requirements** — the quality attributes and constraints the system must satisfy (how well it does what the functional spec defines). It deliberately does **not** restate behaviors; those live in the functional spec, which is referenced here by ID (e.g., `FR-ARCH-5`).

## Conventions

- Each requirement has a unique ID of the form `NFR-<AREA>-<n>`.
- "**shall**" denotes a mandatory requirement; "**should**" a recommended one.
- **Priority** uses MoSCoW: **M** (Must have for first release), **S** (Should have), **C** (Could have / later).
- **Source** cites the originating statement in the product brief (PB), the ADR, the functional spec (FR), or a noted decision.

## Quality Attribute Areas

| Area code | Description |
|-----------|-------------|
| PERF   | Performance & efficiency |
| REL    | Reliability & data integrity |
| SEC    | Security & privilege model |
| USE    | Usability & honest presentation |
| COMPAT | Platform & device compatibility |
| MAINT  | Maintainability & testability |
| OBS    | Observability & logging |
| INST   | Installation & distribution |

---

## NFR-PERF — Performance & Efficiency

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-PERF-1 | Peak buffer memory for a run shall be bounded to approximately 2× the selected I/O size (one original-read buffer + one verify-read buffer) and shall **not** scale with device capacity. | M | PB Test Algorithm; ADR Scalability |
| NFR-PERF-2 | The helper shall process the device as a bounded-memory stream of chunks so that arbitrarily large (multi-terabyte) devices can be tested without proportional memory growth. | M | ADR Option A Scalability |
| NFR-PERF-3 | Throughput shall be **device-bound, not host-bound**: the per-chunk compare, metrics, and bookkeeping overhead shall remain negligible relative to the wall-clock time of the underlying raw read → write → read I/O, such that overall run time is dominated by device I/O rather than host processing. | S | ADR Trade-off Analysis (serialized I/O) |
| NFR-PERF-4 | The GUI shall remain responsive (no UI thread blocking) throughout a run; all privileged I/O and heavy work shall run off the main thread / in the helper. | M | PB Project Objective (monitor progress); ADR Decision |
| NFR-PERF-5 | Live metrics (throughput, latency, progress, ETA) shall refresh at least once per second during an active run. | S | FR-METR-2/4/5 (presentation cadence) |
| NFR-PERF-6 | The displayed ETA shall be derived from measured throughput and shall update continuously, converging toward the actual remaining time as the run progresses. | S | ADR Trade-off Analysis (real ETA); FR-METR-5 |
| NFR-PERF-7 | Capturing per-chunk read-latency statistics (min/max/p99) shall be performed with constant memory (e.g., streaming/approximate percentile) and shall not materially reduce throughput. | S | FR-METR-3 |

## NFR-REL — Reliability & Data Integrity

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-REL-1 | Under uninterrupted operation, the tool shall be **logically non-destructive**: every successfully processed block shall contain, after the run, exactly the bytes it contained before the run (bit-for-bit). | M | PB Test Algorithm; FR-TEST-7; ADR Trade-off Analysis |
| NFR-REL-2 | The write-back for each chunk shall write exactly the bytes read from that chunk; correctness of the write shall be confirmed by the read-verify comparison before the chunk is considered complete. | M | PB Test Algorithm; FR-TEST-3 |
| NFR-REL-3 | The tool shall never issue block writes unless all of the device's volumes are unmounted **and** exclusive whole-disk access is held. | M | PB Managing Mounted Volumes; FR-SAFE-1/2/3 |
| NFR-REL-4 | The in-flight data-loss window shall be bounded to at most one chunk — the chunk currently being written — consistent with the no-journaling decision. | M | ADR Decision; FR-FAIL-7 |
| NFR-REL-5 | On stop, halting error, or device loss, the helper shall terminate cleanly, issue no further writes, and release the device node without leaving the helper in an inconsistent state. | M | FR-DEV-8; FR-FAIL-7 |
| NFR-REL-6 | A device-side error, device removal, or malformed condition shall not crash the GUI; the GUI shall surface the error and return to a usable state (re-running discovery where applicable). | M | FR-DEV-8 |
| NFR-REL-7 | The helper shall validate all parameters received from the GUI (device identity, offset, length, alignment) and reject any request that is out of range or misaligned before performing privileged I/O. | M | ADR Cons (client validation) |
| NFR-REL-8 | The verify comparison shall detect any single-bit difference between the written and re-read buffers. | M | PB Test Algorithm |
| NFR-REL-9 | While a run is actively executing, the app shall prevent idle system sleep (e.g., via an `NSProcessInfo` idle-system-sleep power assertion) so that long-running runs — which cannot be resumed (FR-FAIL-7) and may take many hours — are not interrupted by the Mac sleeping. The assertion shall be released when the run pauses, stops, completes, or fails. | M | ADR Trade-off Analysis (multi-hour runs); FR-FAIL-7; user decision 2026-06-25 |
| NFR-REL-10 | When the user pauses a run (FR-CTRL-2/3), the helper shall settle at a chunk boundary with no write in flight, leaving the device in a consistent state before the pause is acknowledged. | M | FR-CTRL-2/3; NFR-REL-4; user decision 2026-06-25 |

## NFR-SEC — Security & Privilege Model

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-SEC-1 | Elevated privileges shall be confined to the helper; the GUI shall run wholly unprivileged (principle of least privilege). | M | ADR Decision; FR-ARCH-2 |
| NFR-SEC-2 | The helper shall accept privileged commands only over the authenticated XPC connection and only after validating that the calling client's code signature was issued under the expected **Team ID**. (Bundle identifier and Apple anchor are not separately pinned; Team-ID match is the accepted bar.) | M | ADR Cons; FR-ARCH-4/5; user decision 2026-06-25 |
| NFR-SEC-3 | The helper shall expose the minimum XPC interface necessary to perform its function and shall reject unrecognized or malformed messages. | M | ADR Cons; NFR-REL-7 |
| NFR-SEC-4 | The application and helper shall be code-signed, notarized, and run under the macOS hardened runtime. | M | ADR Pros (notarizable) |
| NFR-SEC-5 | The helper shall be installed, updated, and removed solely via `SMAppService`; the design shall not rely on setuid binaries or deprecated privileged-helper mechanisms. | M | ADR Decision; Option C rejection |
| NFR-SEC-6 | The tool shall operate entirely locally; device contents shall never be transmitted off the host nor written to logs or reports. | M | Derived (privacy of user data) |
| NFR-SEC-7 | The application and helper shall request only the entitlements required for their function. | S | ADR Pros (least privilege) |

## NFR-USE — Usability & Honest Presentation

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-USE-1 | Throughput and latency shall be presented in an easily readable form, with clear units (e.g., MB/s, ms) and human-friendly formatting. | M | PB Features ("easily readable"); deferred from FR-METR (user decision 2026-06-25) |
| NFR-USE-2 | Progress shall be conveyed clearly during a run, including percent complete, current position, and the live ETA. | M | FR-METR-5/6 |
| NFR-USE-3 | The currently selected device shall be unambiguously identified (e.g., BSD name, model, capacity) so the user cannot accidentally test the wrong device. | M | PB Upon launch; FR-DEV-6 |
| NFR-USE-4 | Pre-run warnings (back up first; infrequent on NAND; clean pass ≠ healthy drive) shall be presented prominently before a run starts. | M | PB Features; FR-WARN-1/2/3 |
| NFR-USE-5 | Error messages shall be specific and actionable, naming the actual cause and the corrective step (e.g., which volume to unmount, or that the device node is claimed). | M | FR-SAFE-4; FR-DEV-8 |
| NFR-USE-6 | The honest-framing messaging shall be presented such that a clean pass cannot reasonably be mistaken for a health certificate. | M | PB What the Test Does and Does Not Prove; FR-WARN-3/4 |
| NFR-USE-7 | The exported Markdown report shall be well-structured and human-readable (headings, a clear pass/fail outcome, and tabulated bad-block ranges and statistics). | S | FR-RPT-5 |
| NFR-USE-8 | The GUI should follow macOS accessibility expectations on a best-effort basis — leveraging SwiftUI's built-in accessibility (VoiceOver labels, Dynamic Type, sufficient color contrast) and, in particular, never conveying pass/fail status by color alone. A full accessibility audit is not a v1 release gate. | S | Derived (macOS HIG); user decision 2026-06-25 |

## NFR-COMPAT — Platform & Device Compatibility

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-COMPAT-1 | The executables shall be Apple-Silicon-native (arm64). | M | PB Project Objective; ADR Context |
| NFR-COMPAT-2 | The application shall target macOS Tahoe (macOS 26) and later as its minimum supported OS. | M | PB Project Objective; ADR Context |
| NFR-COMPAT-3 | The application shall be built with Xcode and Swift, with the GUI implemented in SwiftUI. | M | PB Project Objective; ADR Decision |
| NFR-COMPAT-4 | The tool shall support USB mass-storage-class devices, covering both NAND-flash media and rotational HDDs (including SATA-to-USB bridged drives). | M | PB Goal; ADR Context |
| NFR-COMPAT-5 | The tool shall use the device-reported logical block size and shall correctly support at least 512-byte and 4096-byte logical blocks. | M | PB Test Algorithm; FR-DEV-5; FR-TEST-5 |
| NFR-COMPAT-6 | The tool shall support large-capacity devices (multi-terabyte) using 64-bit block offsets and counts, with no capacity-related limits short of the device's own. | M | ADR Scalability |
| NFR-COMPAT-7 | The tool should operate correctly across USB link speeds (e.g., USB 2.0 and USB 3.x), deriving timing and ETA from measured throughput rather than assumed speed. | S | ADR Trade-off Analysis (measured ETA) |

## NFR-MAINT — Maintainability & Testability

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-MAINT-1 | The GUI and helper shall be cleanly separated by a well-defined, versioned XPC protocol so each can evolve independently. | M | ADR Decision |
| NFR-MAINT-2 | Core test-algorithm logic (chunking, final-chunk sizing, verify, metrics, failure classification) should be unit-testable independently of privileged hardware access, via an abstraction over the raw device (e.g., a simulated/in-memory device). | S | Derived (testability of FR-TEST/FR-FAIL) |
| NFR-MAINT-3 | The project shall build reproducibly from the Xcode workspace, producing both the unprivileged app and the privileged helper targets. | M | ADR Action Item 1 |
| NFR-MAINT-4 | The codebase should follow idiomatic Swift conventions and be organized so the trust boundary (privileged vs. unprivileged code) is obvious in the source layout. | S | Derived (ADR trust boundary) |

## NFR-OBS — Observability & Logging

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-OBS-1 | The application and helper shall log significant events (run start/stop, failure-mode selection, failed block ranges, device connect/loss, helper registration) to the macOS unified logging system (`os_log`). | S | Derived (diagnosability) |
| NFR-OBS-2 | Logs shall be sufficient to diagnose an interrupted or failed run after the fact, while never recording device contents. | S | NFR-SEC-6; FR-FAIL-7 |

## NFR-INST — Installation & Distribution

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-INST-1 | The helper shall register via `SMAppService`, and the GUI shall report registration status clearly, including guiding the user when approval is required (e.g., Login Items in System Settings). | M | ADR Decision; Action Item 2 |
| NFR-INST-2 | The application shall be distributable as a notarized, hardened-runtime build that launches without Gatekeeper warnings on a clean supported system. | M | ADR Pros (distribution) |
| NFR-INST-3 | The tool shall provide a clean way to unregister/remove the privileged helper. | S | Derived (lifecycle of SMAppService daemon) |

---

## Assumptions

- This is a **single-user, single-host desktop tool**; multi-user concurrency, networked operation, and high-availability/service-uptime requirements are not applicable.
- The product is **English-only**; no localization infrastructure (string catalogs, translation) is built for the first release (decision 2026-06-25).
- "Performance" targets are about overhead and responsiveness, not absolute throughput — absolute speed is bounded by the device and USB link, which the tool measures rather than controls.

## Out of Scope (Non-Functional)

- **SMART/NVMe-derived health metrics** as a quality signal — excluded with the functional feature (USB-to-SATA SAT pass-through unreliability). — *ADR Telemetry sub-decision*
- **Throughput-optimizing pipelined I/O** — the first release accepts serialized-I/O runtimes; pipelining is a later optimization. — *ADR Trade-off Analysis*
- **Localization / internationalization** — English-only for v1; no translation infrastructure. — *user decision 2026-06-25*

## Open Questions (to resolve during iteration)

1. ~~**Performance overhead target (NFR-PERF-3):**~~ **Resolved 2026-06-25** — qualitative "device-bound, not host-bound"; no fixed percentage.
2. ~~**Metrics refresh cadence (NFR-PERF-5)** and **ETA accuracy tolerance (NFR-PERF-6):**~~ **Resolved 2026-06-25** — refresh at least once per second; ETA qualitative (measured-throughput-derived, converges over time).
3. ~~**Code-signature validation strictness (NFR-SEC-2):**~~ **Resolved 2026-06-25** — Team-ID match only (bundle identifier / Apple anchor not separately pinned).
4. ~~**Accessibility commitment (NFR-USE-8):**~~ **Resolved 2026-06-25** — Should / best-effort; not a v1 release gate.
5. ~~**Localization:**~~ **Resolved 2026-06-25** — English-only for v1; no localization infrastructure (now in Out of Scope).
6. ~~**Logging verbosity/retention (NFR-OBS):**~~ **Resolved 2026-06-25** — `os_log` events as specified in NFR-OBS-1/2 are sufficient; no user-visible activity log or formal level/retention rules for v1.
7. ~~**Minimum deployment target:**~~ **Resolved 2026-06-25** — minimum deployment target is macOS 26 (Tahoe); Xcode/Swift versions are not pinned in the spec (left to build config).
