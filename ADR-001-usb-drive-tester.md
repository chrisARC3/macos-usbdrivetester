# ADR-001: USB Drive Retention & Hard-Fault Tester — Architecture and Test Strategy

**Status:** Proposed
**Date:** 2026-06-22
**Deciders:** Project owner (former macOS storage developer)

## Context

All external direct-attach storage is USB-connected (both NAND flash and rotational HDD). Two failure modes need to be addressed with a single tool:

- **NAND retention loss** — charge in flash cells leaks over time, accelerated by long unpowered storage and thermal cycling, eventually rendering data uncorrectable.
- **HDD retention loss** — adjacent-track interference, thermal cycling, and the superparamagnetic effect degrade a sector's readability over time.

The deliverables are Apple-Silicon-native executables for macOS Tahoe (macOS 26) and later, built in Xcode/Swift, with at least one GUI executable for control and monitoring.

Forces at play:

- macOS blocks direct block-device access without privilege escalation; Apple's guidance is to split privileged work into a separate helper.
- The tool aims to be **non-destructive**: it refreshes data in place rather than overwriting with patterns. This makes the only copy of in-flight data volatile (RAM), which creates a data-loss window the design must weigh.
- Block-level access sits *above* the device FTL and *above* SMART/NVMe telemetry, which fundamentally bounds what the tool can observe.

## Decision

Build a two-executable macOS application:

1. A **GUI app** (SwiftUI) for device discovery, run control (start/pause/resume/stop/restart), and live throughput/latency display.
2. A **privileged LaunchDaemon helper** that performs raw, uncached, block-level I/O, installed via `SMAppService` and driven over an authenticated **XPC** connection.

The core test is a sequential, in-place **read → write-back → read-verify** cycle over the entire addressable device in block-aligned chunks sized by a user-selectable **I/O size** (1/2/4/8 MiB dropdown, default 4 MiB). The decision incorporates these changes over the original concept:

- **Log-and-continue** failure mode (in addition to stop-on-first-error), as the safer default for marginal drives.
- **No in-flight journaling and no resume.** An interrupted run — a halting data transfer error, a crash, power loss, or device removal — is reported and must be restarted from the beginning. The residual in-flight data-loss window is accepted and covered by the mandatory back-up warning; journaling was judged not worth its added complexity.
- **Honest framing**: the tool is a *retention refresher* + *hard-fault detector*, not a health certificate; latency percentiles are captured as the only block-level early-warning proxy.

## Options Considered

### Option A: Two executables — GUI app + `SMAppService` privileged daemon over XPC (chosen)

| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium — XPC protocol + daemon lifecycle + client validation |
| Cost | Low (no third-party deps) |
| Scalability | N/A (single-host tool); handles arbitrarily large devices via chunked streaming |
| Team familiarity | High — owner is an experienced macOS storage developer |

**Pros:** Apple-sanctioned privilege model on Tahoe; clean separation of trust boundary; GUI never runs as root; survives App Sandbox/notarization requirements.
**Cons:** XPC + daemon registration boilerplate; must validate the calling client's code signature in the helper.

### Option B: Single privileged GUI app (run whole app elevated)

| Dimension | Assessment |
|-----------|------------|
| Complexity | Low to build, high to secure |
| Cost | Low |
| Scalability | N/A |
| Team familiarity | High |

**Pros:** No IPC layer; simplest to write.
**Cons:** Runs an entire UI as root (large attack surface); fights macOS security model; poor notarization/distribution story. Rejected.

### Option C: `SMJobBless` privileged helper (the older pattern)

| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium |
| Cost | Low |
| Scalability | N/A |
| Team familiarity | High |

**Pros:** Well-documented historically; same trust-boundary benefits as Option A.
**Cons:** **Deprecated**; `SMAppService` is the supported path on macOS 13+. Building new on a deprecated API is wrong for a Tahoe-and-later target. Rejected.

### Test-strategy sub-decision: stop-on-first-error vs. log-and-continue

**Stop-on-first-error only** (original concept) halts on the first bad block. On a marginal drive this leaves the vast majority of the device un-refreshed — arguably worsening retention for the drive that most needs the refresh. **Decision: support both**, with log-and-continue as the safer default and stop-on-error available for a quick pass/fail check.

### Telemetry sub-decision: SMART/NVMe health polling

Excluded. USB-to-SATA bridges rarely pass through SCSI/ATA (SAT) commands reliably, so SMART polling would add complexity for little value on the dominant hardware. (Noted fast-follow: USB **NVMe** enclosures increasingly *do* expose NVMe health, so this subset could be revisited later.)

## Trade-off Analysis

- **Non-destructive refresh vs. data-loss window.** Refreshing in place (rather than writing known patterns) preserves user data but means the only copy of an in-flight chunk is in RAM. There is **no journaling and no resume**: an interrupted run is reported and must be restarted from the beginning, and the user is required to back up first. We accept this residual risk because a destructive pattern test would defeat the tool's primary purpose, and journaling/resume was judged not worth its added implementation and test complexity for a single-user tool.

- **Serialized safety vs. throughput.** Per-chunk read→write→verify is ~3× the device's data volume in fully serialized I/O — on a large HDD this can run the better part of a day. Pipelining (read N+1 while writing/verifying N) would recover throughput but widens the in-flight/crash surface. **Decision: ship the simple one-chunk-in-flight model first**; optimize only if runtimes prove unacceptable. The UI shows a real ETA derived from measured throughput.

- **What the tool can prove.** Block-level reads only fail when a sector is *beyond ECC*. Degrading-but-correctable blocks read clean, so a passing run is "no currently-unreadable blocks," not "healthy." Capturing read-latency percentiles is cheap and gives the only available early-warning proxy; the richer signal lives in the deliberately-excluded SMART telemetry. We accept this limitation and make it explicit in the UI rather than imply a false guarantee.

- **NAND refresh semantics.** Rewriting LBA *N* does not reprogram the same physical page (the FTL writes a fresh page and GCs the old one). This still achieves the goal — cold data gets re-programmed into full-charge cells — but we document it accurately rather than claim same-cell rewrite.

## Consequences

**Easier:**
- Clean trust boundary; GUI stays unprivileged and notarizable.
- No journaling/resume state machine to build or test — simpler, with a smaller in-flight surface to reason about.
- Marginal drives still get fully refreshed (log-and-continue) and produce a complete bad-block report.
- Users get an honest picture of drive state plus a latency-based early-warning signal.

**Harder:**
- Must implement and test XPC, daemon registration, and helper-side client code-signature validation.
- Must correctly acquire exclusive whole-disk access (unmounting volumes alone is insufficient — the device node must not be claimed).
- Must detect device hot-unplug / de-enumeration mid-run, terminate the test cleanly, surface an error, and re-run discovery.
- Long runtimes on large HDDs require good progress/ETA UX and robust pause/resume (in-session) state management; an interrupted run cannot be resumed and must be restarted from the beginning.

**To revisit:**
- Pipelined I/O for throughput, if serialized runtimes are unacceptable.
- NVMe health polling for USB-NVMe enclosures as a fast-follow.

## Action Items

1. [ ] Stand up the Xcode workspace: unprivileged SwiftUI app target + privileged LaunchDaemon helper target.
2. [ ] Register the helper via `SMAppService`; define the XPC protocol; implement helper-side validation of the client's code signature.
3. [ ] Implement device discovery (USB mass-storage enumeration), stable sort by BSD name, default-select first device, display identifying details (BSD name, model, capacity), and refresh the list on connect/disconnect while no test is running.
4. [ ] Implement the mount-guard: verify no volumes are mounted **and** acquire exclusive whole-disk access (`diskutil unmountDisk` / DiskArbitration claim); clear error messaging when blocked.
5. [ ] Implement raw I/O core: open `/dev/rdiskN`, set `F_NOCACHE`/`F_GLOBAL_NOCACHE`, query logical block size (`DKIOCGETBLOCKSIZE`) and count (`DKIOCGETBLOCKCOUNT`), block-aligned chunking at the user-selected I/O size (1/2/4/8 MiB, default 4 MiB) with a block-size-rounded final chunk.
6. [ ] Implement the read → write-back → read-verify cycle (no journaling, no resume): on a data transfer error or any interruption, report and require a restart from the beginning.
7. [ ] Implement both failure modes (stop-on-error, log-and-continue) and the end-of-run bad-block report, with **Markdown export** of the report (bad-block list + throughput + latency stats). No history of previous runs is retained.
8. [ ] Implement metrics: average read/write throughput + read-latency min/max/p99; surface live in the UI.
9. [ ] Implement device-loss handling: if the device under test hot-unplugs or de-enumerates mid-run, immediately terminate the test, present an error, and re-run device discovery.
10. [ ] Implement run control state machine: start / pause / resume / stop / restart, plus the pre-run controls (I/O size, failure mode). Pause must settle at a chunk boundary with no write in flight before it is acknowledged. Only one device is tested at a time — no concurrent runs.
11. [ ] Implement mandatory pre-run warnings (back up first; run infrequently on NAND; clean pass ≠ healthy drive).
12. [ ] Implement system-sleep prevention: hold an idle-system-sleep power assertion (`NSProcessInfo`) while a run is actively executing, and release it on pause / stop / completion / failure (runs cannot be resumed, so an idle-sleep interruption would force a full restart).
13. [ ] Implement signing & distribution: code-sign both targets, enable the hardened runtime, and notarize so the app launches Gatekeeper-clean on a supported system.
14. [ ] Implement helper lifecycle teardown: provide a clean path to unregister/remove the privileged `SMAppService` helper.
15. [ ] Implement logging/observability: emit significant events (run start/stop, failure-mode selection, failed block ranges, device connect/loss, helper registration) via `os_log`, never recording device contents.
16. [ ] Establish the test strategy: abstract raw-device access so the core algorithm (chunking, final-chunk sizing, verify, metrics, failure classification) is unit-testable against a simulated/in-memory device independent of privileged hardware.
