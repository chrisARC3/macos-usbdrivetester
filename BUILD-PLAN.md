# Build Plan: USB Drive Retention & Hard-Fault Tester

**Status:** Draft for execution
**Date:** 2026-06-25
**Last amended:** 2026-08-01 — Steps 6 and 7 (measured exclusivity semantics, Full Disk
Access), and the test target fixed to `disk4` with disk images removed as an option
(see "Test hardware")
**Source documents:**
- [Product Brief](USBDriveTester.md)
- [ADR-001](ADR-001-usb-drive-tester.md) — the 16 Action Items this plan sequences
- [Functional Requirements](functional-requirements-usb-drive-tester.md) (Baselined 2026-06-25)
- [Non-Functional Requirements](nonfunctional-requirements-usb-drive-tester.md) (Baselined 2026-06-25)

---

## How to use this plan

This plan turns the ADR's 16 Action Items (AI-1 … AI-16) into an ordered sequence of **build steps**. The work is intended to be done **slowly and deliberately, one step at a time**, with each step fully verified before the next begins.

- **Steps are renumbered (Step 1 … Step 16)** to reflect true build order. Each step is annotated with its original **`AI-n`** so traceability back to the ADR is preserved.
- Every step lists the **requirements it satisfies** (FR-/NFR- IDs) so you can confirm coverage.
- Every step ends with a **Verification Gate** — an explicit, testable definition of "done." **Do not start the next step until the current gate passes.** This is the core discipline of the plan.
- Where a step builds code that touches the privileged trust boundary, the step calls out which side of the boundary (GUI vs. helper) the code lives on.

### Why the order differs from the ADR's 1–16 list

The ADR lists action items by topic, not by dependency. Three deliberate re-orderings:

1. **AI-16 (test abstraction) moves to Step 2 — the foundation.** The ADR explicitly wants the core algorithm "unit-testable against a simulated/in-memory device independent of privileged hardware" (NFR-MAINT-2). Building that abstraction *first* lets us develop and verify the entire read→write→verify→metrics→failure engine (Steps 7–10) with fast, deterministic unit tests, before any privileged hardware is involved. This is the single biggest risk-reducer in the plan.
2. **AI-14 (helper teardown) pairs with AI-2 (helper registration)** as Step 4, immediately after registration. Registration and unregistration are two ends of the same lifecycle; building them together means you can install/remove cleanly throughout the rest of development.
3. **AI-15 (logging) is cross-cutting.** It gets a dedicated consolidation step (Step 15) near the end, but each earlier step instructs you to add its `os_log` points as you go, so logging grows with the code rather than being bolted on.

### Global "Definition of Done" applied to every step

Before a step's gate is considered passed:
- The code compiles for **arm64 / macOS 26 (Tahoe)** with no new warnings (NFR-COMPAT-1/2/3).
- Any logic added in this step that *can* be unit-tested **is** unit-tested (NFR-MAINT-2).
- The privileged/unprivileged trust boundary is respected: no raw I/O outside the helper (FR-ARCH-6, NFR-SEC-1).
- New significant events are emitted via `os_log` (NFR-OBS-1) — see Step 15.
- A one-paragraph note is recorded (commit message or a `PROGRESS.md`) describing what was verified and how.

### Test hardware (amended 2026-08-01, user decision)

Every step with a real-hardware gate uses **`disk4`** — Samsung Portable SSD T5, 1 TB,
512-byte blocks, one exFAT volume `Test_Drive`. It holds only expendable test files.

- **`disk6` must never be tested** — it holds this source tree.
- **`disk8`** (Seagate 22 TB) is for read-only checks such as 64-bit block-count handling.
- **Disk images are not a test target.** Discovery excludes them (they report
  `Physical Interconnect == "Virtual Interface"`), and they lack the USB bridge, real
  block device and NAND this tool exists to exercise. Earlier wording in Steps 7, 8 and
  Appendix B offering a disk image as a safer stand-in has been removed — see Step 7,
  "The test target".
- **The helper requires Full Disk Access** (NFR-INST-4) before any raw I/O works at all.

The drive's data being expendable relaxes the *consequence* of a bug, never the discipline:
simulation-first still applies wherever the plan calls for it.

---

## Sequence overview

| Step | AI | Title | Primarily on | Gate in one line |
|------|----|-------|--------------|------------------|
| 1 | AI-1 | Xcode workspace: app + helper targets | Both | Both targets build and launch; empty XPC round-trip works |
| 2 | AI-16 | Raw-device abstraction + simulated device + test harness | Helper/core | Core algorithm scaffold runs against an in-memory device under Swift Testing |
| 3 | AI-2 | `SMAppService` registration + XPC protocol + code-signature validation | Both | GUI registers helper; helper rejects an unsigned/foreign caller |
| 4 | AI-14 | Helper lifecycle teardown (unregister/remove) | Both | GUI can fully remove the helper; status reflects it |
| 5 | AI-3 | Device discovery & selection | GUI | USB devices enumerate, sort stably, default-select, live-refresh |
| 6 | AI-4 | Mount-guard: unmount + exclusive whole-disk claim | Helper | Test refuses to start unless unmounted **and** claimed; precise errors |
| 7 | AI-5 | Raw I/O core: open `rdiskN`, no-cache, block geometry, chunking | Helper | Geometry read correctly; chunk plan correct incl. final chunk |
| 8 | AI-6 | read → write-back → read-verify cycle | Helper/core | Full-device cycle is bit-for-bit non-destructive in simulation |
| 9 | AI-8 | Metrics: throughput + read-latency min/max/p99 | Both | Live metrics refresh ≥1/s; ETA converges; constant-memory p99 |
| 10 | AI-7 | Failure modes + bad-block report + Markdown export | Both | Stop-on-error and log-and-continue both correct; report exports |
| 11 | AI-10 | Run-control state machine: start/pause/resume/stop/restart | Both | Illegal transitions blocked; pause settles at chunk boundary |
| 12 | AI-9 | Device-loss handling (hot-unplug mid-run) | Both | Unplug terminates cleanly, errors, re-runs discovery |
| 13 | AI-12 | System-sleep prevention | GUI | Assertion held only while actively running; released on all exits |
| 14 | AI-11 | Mandatory pre-run warnings & honest framing | GUI | Three warnings shown & acknowledged before any run |
| 15 | AI-15 | Logging / observability consolidation | Both | All significant events logged; never logs device contents |
| 16 | AI-13 | Signing, hardened runtime, notarization | Both | Notarized build launches Gatekeeper-clean on a clean Mac |

---

# Phase 0 — Foundations & Test Harness

## Step 1 — Stand up the Xcode workspace (two targets)

**Original action item:** AI-1
**Satisfies:** FR-ARCH-1, FR-ARCH-2; NFR-COMPAT-1/2/3, NFR-MAINT-3, NFR-MAINT-4
**Trust boundary:** establishes both sides.

### Objective
Create the Xcode project containing two products — an unprivileged SwiftUI app and a privileged LaunchDaemon helper — that build reproducibly and can exchange a trivial XPC message. No real functionality yet; this is the skeleton everything else hangs on.

### Detailed steps
1. **Create the app target.** New Xcode project → macOS → App → SwiftUI lifecycle, Swift. Name e.g. `USBDriveTester`. Set **Deployment Target = macOS 26.0**, **Architectures = arm64** (NFR-COMPAT-1/2). Set the **Team** to your Apple Developer team in Signing & Capabilities (you will need a real Team ID later for code-sig validation; set it now).
2. **Add the helper target.** Add a new target of type **Command Line Tool** (Swift), e.g. `com.<you>.USBDriveTester.helper`. This becomes the LaunchDaemon. Its bundle/executable name must be a reverse-DNS identifier — it will double as the **Mach service name** and the **`SMAppService` plist name** (keep these three consistent from the start; mismatches are the #1 cause of `SMAppService` failures).
3. **Lay out the source tree so the trust boundary is obvious** (NFR-MAINT-4). Suggested top-level groups:
   - `App/` — SwiftUI views, view models, app-side controllers (unprivileged).
   - `Helper/` — daemon `main`, XPC listener, privileged I/O (privileged).
   - `Shared/` — the XPC protocol definition, shared model types (DTOs), error enums. Compiled into **both** targets.
   - `USBDriveTesterTests/` — Swift Testing target (the unit-test target; our "CoreTests").
4. **Embed the helper in the app bundle the way `SMAppService` expects:**
   - Helper executable goes in `Contents/MacOS/` of the app, *or* is referenced from the LaunchDaemon plist.
   - Create the LaunchDaemon **launchd property list** at `Contents/Library/LaunchDaemons/<helper-id>.plist`. Minimum keys: `Label` (= helper id), `BundleProgram` (path to the helper executable inside the app bundle), and `MachServices` = `{ <helper-id> = true }`. Add a **Copy Files build phase** on the app target that copies this plist into `Contents/Library/LaunchDaemons/`.
   - Add a build phase to embed the built helper executable into the app bundle.
5. **Add a placeholder XPC protocol** in `Shared/` (e.g. `protocol TesterControl { func ping(reply: @escaping (String) -> Void) }`) and a no-op helper implementation that returns `"pong"`. Wire the GUI to a temporary "Ping helper" button. (Real registration is Step 3; for Step 1 you may run the helper manually via `launchctl bootstrap` to prove the plumbing.)
6. **Confirm reproducible build** (NFR-MAINT-3): a clean build (`⇧⌘K` then build, or `xcodebuild`) produces the `.app` with the helper and plist embedded.

### Verification Gate (must pass before Step 2)
- [ ] Both targets build for arm64 / macOS 26 with zero errors and no new warnings.
- [ ] The built `.app` bundle contains the helper executable **and** `Contents/Library/LaunchDaemons/<helper-id>.plist`, and the plist's `Label`, `BundleProgram`, and `MachServices` are internally consistent and match the helper id.
- [ ] The GUI launches and shows its window.
- [ ] The "Ping helper" round-trip returns `"pong"` (helper may be launched manually for this step).
- [ ] `git` repo initialized/committed; a `PROGRESS.md` note records the verification.

### Risks / gotchas
- The Mach service name, plist `Label`, and `SMAppService.daemon(plistName:)` argument must be **identical**. Decide the string now and never change it casually.
- Command-line-tool helpers still need an `Info.plist` (embedded via linker flags) for code signing later (Step 16) — note this for now.

---

## Step 2 — Raw-device abstraction, simulated device, and test harness

**Original action item:** AI-16 *(pulled forward — see "Why the order differs")*
**Satisfies:** NFR-MAINT-2 (and de-risks FR-TEST-*, FR-FAIL-*, FR-METR-*)
**Trust boundary:** core/helper-side code, but designed to run with **no privileges** under Swift Testing.

### Objective
Define the abstraction that separates the **core test algorithm** (chunking, final-chunk sizing, verify, metrics, failure classification) from the **physical device**. Provide an in-memory implementation so the entire engine can be developed and unit-tested deterministically, before any hardware or privilege is involved.

### Detailed steps
1. **Define a `RawBlockDevice` protocol** in `Shared/` (or a `Core/` group compiled into the helper and the test target). Minimal surface, mirroring the real raw-device operations:
   ```
   protocol RawBlockDevice {
       var logicalBlockSize: Int { get }      // bytes, e.g. 512 or 4096
       var blockCount: UInt64 { get }          // total addressable blocks
       func read(into buffer: UnsafeMutableRawBufferPointer,
                 atByteOffset: UInt64) throws -> Int
       func write(_ buffer: UnsafeRawBufferPointer,
                  atByteOffset: UInt64) throws -> Int
   }
   ```
   Use **64-bit** offsets/counts throughout (NFR-COMPAT-6). Define a `DeviceIOError` enum with cases for read error, write error, short transfer, and misalignment.
2. **Implement `InMemoryBlockDevice`** conforming to `RawBlockDevice`, backed by a `Data`/byte array sized `blockSize * blockCount`. Parameterize block size so you can test **both 512-byte and 4096-byte** geometries (NFR-COMPAT-5). Add **fault-injection hooks**: ability to make specific block ranges throw on read or write, or to silently corrupt bytes on write (so a later verify mismatch is triggered) — these power the failure-mode tests in Step 10.
3. **Use the `USBDriveTesterTests` (Swift Testing) target.** Add a first test that constructs an `InMemoryBlockDevice`, fills it with known pseudo-random data, and asserts read-back equality (`#expect`). This proves the harness itself is sound.
4. **Stub the core engine type** (e.g. `RetentionTestEngine`) that takes a `RawBlockDevice` plus an `ioSize` and will host the algorithm built in Steps 7–10. For now it only computes the **chunk plan** (see Step 7 detail) so you have something to test immediately.
5. **Document the contract:** alignment requirements (offset and length multiples of `logicalBlockSize`), and that the engine must never assume `ioSize` divides the device evenly (final-chunk handling, FR-TEST-5).

### Verification Gate (must pass before Step 3)
- [ ] `RawBlockDevice` protocol and `InMemoryBlockDevice` exist and compile into both the helper target and the test target — with **no UIKit/IOKit/privileged dependencies** in the core (proves true independence per NFR-MAINT-2).
- [ ] Swift Testing suite runs green: read/write round-trip on a 512-byte-block device **and** on a 4096-byte-block device.
- [ ] Fault-injection demonstrably forces a read error, a write error, and a silent corruption (verify-mismatch) in a test.
- [ ] The engine's chunk-plan stub is callable from a test (even if it only returns a list of `(offset, length)`).

### Risks / gotchas
- Resist putting any `Dispatch`/UI/IOKit code in the core. The whole value of this step is that the engine is pure and host-only-testable.
- Keep buffers as raw byte buffers, not typed arrays, so the same code path drives both the simulated and the real (Step 7) device.

---

# Phase 1 — Privilege Plumbing

## Step 3 — `SMAppService` registration + XPC protocol + client code-signature validation

**Original action item:** AI-2
**Satisfies:** FR-ARCH-3/4/5/6; NFR-SEC-1/2/3/5, NFR-INST-1, NFR-MAINT-1
**Trust boundary:** spans both; this step *builds* the boundary.

### Objective
Make the helper a real, `SMAppService`-registered LaunchDaemon, define the versioned XPC protocol the GUI uses to drive it, and have the helper **refuse commands from any client not signed by your Team ID**.

### Detailed steps
1. **Register the daemon.** In the GUI, use `SMAppService.daemon(plistName: "<helper-id>.plist")`. Call `.register()` to install; read `.status` (`.enabled`, `.requiresApproval`, `.notRegistered`, `.notFound`). When `.requiresApproval`, guide the user to **System Settings → General → Login Items & Extensions** (NFR-INST-1). Surface status clearly in the GUI.
2. **Stand up the XPC listener in the helper.** The daemon's `main` creates an `NSXPCListener` for the Mach service name from the plist, sets a delegate implementing `listener(_:shouldAcceptNewConnection:)`, and `resume()`s. Keep the daemon alive (run loop).
3. **Define the real XPC protocol** in `Shared/` and **version it** (NFR-MAINT-1) — e.g. include a `protocolVersion` query the GUI checks on connect. Keep the interface **minimal** (NFR-SEC-3): device geometry query, start run (with parameters), pause, resume, stop, and a callback/progress channel back to the GUI. Use a second `*Client` protocol for helper→GUI progress callbacks via `NSXPCConnection.exportedObject`.
4. **Validate the caller's code signature (the security crux, FR-ARCH-5 / NFR-SEC-2).** In `shouldAcceptNewConnection`, before configuring the exported object, require the connection's peer to satisfy a code-signing requirement pinned to your **Team ID**:
   - Preferred modern API: `connection.setCodeSigningRequirement("anchor apple generic and certificate leaf[subject.OU] = \"<YOUR_TEAM_ID>\"")` (macOS 13+). Per NFR-SEC-2, Team-ID match is the accepted bar — do **not** additionally pin bundle id or Apple anchor beyond this requirement string.
   - Reject (return `false`) if the requirement is not met.
5. **Validate every request's parameters at the boundary** (NFR-REL-7, NFR-SEC-3): even after a trusted connection, the helper independently re-checks device identity, offset/length range, and block alignment, rejecting anything out of range or misaligned **before** any privileged I/O.
6. **Connect from the GUI** via `NSXPCConnection(machServiceName:options:.privileged)`, set `remoteObjectInterface`, set the interrupt/invalidation handlers, and `resume()`.
7. **Add `os_log` points** (NFR-OBS-1): helper registration, connection accepted/rejected (with reason), protocol-version handshake.

### Verification Gate (must pass before Step 4)
- [ ] From the GUI, `register()` installs the daemon; after user approval, `.status == .enabled`, and the GUI shows that status.
- [ ] A real XPC round-trip (e.g. protocol-version query) succeeds **through the registered daemon** (not a manually-bootstrapped one).
- [ ] **Negative test:** a build signed with a *different* Team ID (or an ad-hoc/unsigned dummy client) is **rejected** by `shouldAcceptNewConnection`, and the rejection is logged. This is the security gate — do not pass the step without demonstrating rejection.
- [ ] The helper rejects an out-of-range / misaligned parameter request with a clear error (NFR-REL-7), exercised by a deliberately bad call.

### Risks / gotchas
- `SMAppService` requires the app to be **code-signed** (even locally) and the plist embedded correctly. If `.status == .notFound`, the plist path/Label/Mach-service name are inconsistent — recheck Step 1.
- The helper runs as **root**; treat every byte from the GUI as untrusted input (this is why Step 5/NFR-REL-7 validation is mandatory).
- Keep the protocol minimal now; widening it later is cheap, but a wide attack surface is hard to walk back.

---

## Step 4 — Helper lifecycle teardown (unregister / remove)

**Original action item:** AI-14
**Satisfies:** NFR-INST-3, NFR-SEC-5
**Trust boundary:** GUI initiates; helper is removed.

### Objective
Provide a clean, user-invokable path to fully unregister and remove the privileged helper — the other half of the lifecycle started in Step 3.

### Detailed steps
1. **Add an "Uninstall helper" action** in the GUI that calls `SMAppService.daemon(...).unregister()` (async; handle the completion/error).
2. **Refuse teardown mid-run.** Guard: if a run is active, block uninstall and tell the user to stop the run first (interacts with Step 11's state machine).
3. **Drain the XPC connection** before/while unregistering: invalidate the `NSXPCConnection`, ensure the helper has released the device node (ties to NFR-REL-5), then unregister.
4. **Reflect the new status** in the GUI (`.notRegistered`). Confirm no leftover Mach service or daemon process remains (`launchctl print system/<helper-id>` should not find it).
5. **`os_log`** the unregister event.

### Verification Gate (must pass before Step 5)
- [ ] "Uninstall helper" transitions `.status` to `.notRegistered` and the GUI shows it.
- [ ] After uninstall, the daemon process is gone (verified via `launchctl`), and a subsequent `register()` cleanly reinstalls (install→uninstall→reinstall cycle works repeatedly).
- [ ] Uninstall is blocked with a clear message while a (simulated) run is active.

### Risks / gotchas
- `unregister()` is asynchronous and can lag; poll `.status` rather than assuming immediate removal.
- Ensure the device node is released first, or removal can leave a claimed disk (revisited in Step 6).

---

# Phase 2 — Device Discovery & Safety

## Step 5 — Device discovery & selection

**Original action item:** AI-3
**Satisfies:** FR-DEV-1/2/3/4/5/6/7; NFR-USE-3, NFR-COMPAT-4/6
**Trust boundary:** primarily GUI (discovery does not require root); geometry for the *selected* device may be confirmed via the helper.

### Objective
Enumerate connected USB mass-storage devices, present them in a stable, identifiable list, default-select the first, allow the user to change selection, and live-refresh as devices come and go **while no test is running**.

### Detailed steps
1. **Enumerate USB mass-storage whole disks.** Use IOKit: match `kIOMediaClass` with `kIOMediaWholeKey = true`, then walk each media object's parent chain to confirm it sits behind a **USB** transport (USB mass-storage). For each match collect:
   - **BSD name** (`kIOBSDNameKey`) → e.g. `disk6` (FR-DEV-6).
   - **Capacity** = `kIOMediaSizeKey` (bytes) (FR-DEV-6, NFR-USE-3).
   - **Logical block size** = `kIOMediaPreferredBlockSizeKey` and/or confirm later via ioctl (FR-DEV-5; reconciled in Step 7).
   - **Model / vendor / product** from the USB device properties up the chain.
2. **Sort stably by BSD name** (FR-DEV-2) — a numeric-aware sort so `disk2` < `disk10`. Stability matters so the list does not jump around between refreshes.
3. **Default-select the first device** (FR-DEV-3); allow re-selection (FR-DEV-4). Surface the selected device **unambiguously** — BSD name + model + human-readable capacity (NFR-USE-3) so the wrong drive can't be picked by accident.
4. **Live refresh (FR-DEV-7).** Register IOKit/DiskArbitration appearance & disappearance callbacks and update the list **only while no run is active**. (During a run, discovery is frozen; hot-unplug of the *device under test* is handled separately in Step 12.)
5. **Determine geometry for the selected device (FR-DEV-5):** record logical block size and block count; this feeds the chunk plan. Final authority on geometry is the helper's ioctl in Step 7 — reconcile and prefer the device-reported values.
6. **`os_log`** device connect/disconnect events (NFR-OBS-1).

### Verification Gate (must pass before Step 6)
- [ ] Connecting two or more USB drives lists all of them; non-USB/internal disks are excluded.
- [ ] List order is stable and numeric-correct across refreshes; first device is default-selected; selection can be changed.
- [ ] Each row shows BSD name, model, and human-readable capacity; the selected device is unambiguously identified.
- [ ] Plugging/unplugging a drive **with no run active** updates the list within a second or two.
- [ ] Selected device's logical block size and block count are captured and displayed/recorded.

### Risks / gotchas
- A single physical device can expose multiple `IOMedia` nodes (whole disk + partitions). List **whole disks only** (`kIOMediaWholeKey`).
- Capacity formatting: use base-10 vs base-2 consistently and label units (ties to NFR-USE-1).

---

## Step 6 — Mount-guard: unmount verification + exclusive whole-disk claim

**Original action item:** AI-4
**Satisfies:** FR-SAFE-1/2/3/4/5/6/7; NFR-REL-3, NFR-USE-5
**Trust boundary:** the **claim/exclusive-open is helper-side** (privileged); the GUI orchestrates and shows errors.

### Objective
Guarantee that no test ever starts unless **(a) every volume on the device is unmounted** and **(b) the helper holds exclusive whole-disk access** to the device node — with precise, actionable errors distinguishing the two failure causes.

### Detailed steps
1. **Check for mounted volumes (FR-SAFE-1/2).** Via DiskArbitration, enumerate the selected whole disk's child media; for each, get its `DADiskCopyDescription` and check `kDADiskDescriptionVolumePathKey` (non-nil ⇒ mounted). If any are mounted, **do not proceed**.
2. **Acquire exclusive whole-disk access (FR-SAFE-3).** Helper-side, and **without
   unmounting anything** — see the amendment note below.
   - **Claim the disk** — `DADiskClaim(wholeDisk, …)` so the OS won't auto-remount mid-run, **and** open `/dev/rdiskN` with `O_EXLOCK` (Step 7's `open` must succeed). Hold both for the run's duration.
   - **Claim with a timeout.** Measured 2026-07-30: a contended `DADiskClaim` is neither
     granted nor dissented — it stays **pending indefinitely**. A blocking claim would
     wedge the helper, so the claim must time out, and a timeout means *another process
     holds the disk* (FR-SAFE-4(b)), not that the call failed.
   - If any volume is still mounted, **refuse** (FR-SAFE-4(a), FR-SAFE-6). Acquiring must
     never change the mount state as a side effect.

   > **Measured, 2026-07-30** (`scripts/exclusivity-probe.sh`), and load-bearing for this
   > step:
   > - **The mount guard is kernel-enforced.** `open(rdiskN, O_RDWR)` fails `EBUSY` while
   >   any volume is mounted. FR-SAFE-1/2 is backed by the OS, not only by our policy.
   > - **Auto-remount is real.** The moment a probe released its claim, macOS silently
   >   remounted the volume. Unmounting alone is *not* sufficient — the claim is what
   >   keeps it unmounted, exactly as this step's "risks" note warns.
   > - **The two FR-SAFE-4 causes are the same errno.** Both (a) and (b) surface as
   >   `EBUSY`. The mount check is the only thing that separates them, which is why the
   >   read-only readiness check must report mount state rather than just an error code.
   > - **Release is asynchronous.** An open immediately after `DADiskUnclaim` can still
   >   see `EBUSY`. The release path must not assume the device is instantly reusable.

   > **Amended 2026-07-30.** This step originally read "unmount the whole disk (all
   > volumes)" as part of acquiring, with an in-app unmount as an optional extra. That
   > conflicted with FR-SAFE-4(a), which requires a mounted volume to produce a refusal
   > naming the volume and instructing the user. Unmounting is now **only** ever the
   > result of the user pressing the control in 2a, never a side effect of starting a
   > test (FR-SAFE-6).

2a. **Mount/unmount control (FR-SAFE-5/6/7).** One button in the app, acting on **all**
   volumes of the selected device, whose label and action always agree:

   | Selected device | Label | State |
   |---|---|---|
   | none | `Unmount All` (default) | disabled |
   | one or more volumes mounted | `Unmount All` | enabled → unmount all |
   | no volumes mounted | `Mount All` | enabled → mount all |

   A partially-mounted device reads `Unmount All` — any mounted volume selects the
   unmount direction. Also disabled during a run or while the helper holds the claim
   (FR-SAFE-7). Unmount is a common failure case (open files), so a failure must name the
   volume and the reason (NFR-USE-5), not merely report that it failed. The control lives
   app-side and uses unprivileged DiskArbitration, keeping the privileged XPC surface to
   check/acquire/release (NFR-SEC-3). Its state derives from the Step 5 device model,
   which live-updates through the volume watcher, so the label re-evaluates itself when
   the action completes.
3. **Distinguish the two failure causes precisely (FR-SAFE-4, NFR-USE-5):**
   - (a) Volume(s) still mounted → name the specific volume(s) and instruct the user to unmount them.
   - (b) Volumes unmounted but exclusive access fails because the device node is **claimed by another process** → say exactly that (and, if discoverable, which process / that the node is busy).
   - Never show a generic "couldn't start" — the message must name the actual cause and the corrective step.
4. **Hard precondition on writes (NFR-REL-3):** the helper must **never** issue a block write unless both conditions hold. Encode this as an assertion at the top of the write path, not just a UI check.
5. **`os_log`** the unmount, the claim acquire/release, and any block reason (NFR-OBS-1).

### Verification Gate (must pass before Step 7)
- [ ] With a mounted volume present, starting a test is refused with a message naming the **mounted volume** and telling the user to unmount it.
- [ ] With volumes unmounted but the node held busy by another process, starting is refused with the **"device node is claimed"** message — distinct from the mounted-volume message.
- [ ] On success, the helper holds an exclusive claim and an exclusive `rdiskN` open; releasing it (stop/teardown) makes the disk normally usable again.
- [ ] The write path has an enforced guard that exclusive access is held (verified by a unit/integration check that the guard trips when access is absent).
- [ ] **Mount/unmount control (FR-SAFE-5/6/7):** disabled with no device selected; reads `Unmount All` and unmounts every volume when any is mounted; reads `Mount All` and mounts them when none is; a partially-mounted device reads `Unmount All`; the label re-evaluates after each action; a failed unmount names the volume and the reason.
- [ ] **Nothing mounts or unmounts implicitly (FR-SAFE-6):** attempting to start with a volume mounted refuses and leaves the mount state unchanged.

### Risks / gotchas
- Unmounting volumes is **not** sufficient — without `DADiskClaim`, `diskarbitrationd` or Spotlight can re-probe/remount and corrupt an in-flight run. The claim is mandatory.
- Releasing the claim cleanly on **every** exit path (stop, error, device loss, crash-as-much-as-possible) ties to NFR-REL-5 and is re-checked in Steps 11/12.

---

# Phase 3 — I/O Core (built test-first against the simulated device from Step 2)

## Step 7 — Raw I/O core: open `rdiskN`, no-cache, block geometry, chunk plan

**Original action item:** AI-5
**Satisfies:** FR-TEST-2/5/6; FR-DEV-5; NFR-PERF-1/2, NFR-COMPAT-5/6
**Trust boundary:** **helper-side only** (FR-ARCH-6).

### Objective
Implement the real `RawBlockDevice` for hardware: open the raw device uncached, read true block geometry, and produce the block-aligned chunk plan (including the correctly-sized final chunk). The same engine from Step 2 will now run against either the in-memory device or this real one.

### Detailed steps
1. **Open the raw device** in the helper: `open("/dev/rdiskN", O_RDWR | O_EXLOCK | O_NONBLOCK)` (raw, not buffered `diskN`). Fail with a precise error if it can't be opened exclusively (ties to Step 6).

   > **Amended 2026-07-30, measured.** This originally specified a plain `O_RDWR` open.
   > `scripts/exclusivity-probe.sh` established that **a plain `O_RDWR` open on an
   > unmounted raw disk is not exclusive at all** — two independent opens both succeed,
   > so two processes could write the same device simultaneously. `O_EXLOCK` does
   > exclude: the second attempt fails `EBUSY`. `O_NONBLOCK` matters too, or a contended
   > open blocks instead of returning the error the guard needs.
2. **Disable caching (FR-TEST-6):** `fcntl(fd, F_NOCACHE, 1)` and `fcntl(fd, F_GLOBAL_NOCACHE, 1)` so reads/writes hit the device, not the unified buffer cache.
3. **Query geometry:**
   - `ioctl(fd, DKIOCGETBLOCKSIZE, &blockSize)` → `UInt32` logical block size (expect 512 or 4096; NFR-COMPAT-5).
   - `ioctl(fd, DKIOCGETBLOCKCOUNT, &blockCount)` → `UInt64` (NFR-COMPAT-6).
   - Reconcile with the values discovered in Step 5; prefer the ioctl values.
4. **Implement read/write** using `pread`/`pwrite` at explicit byte offsets (block-aligned). Treat short transfers and `errno` as `DeviceIOError`. **All offsets/lengths are 64-bit and block-aligned** (NFR-COMPAT-6, NFR-REL-7).
5. **Build the chunk plan (FR-TEST-2/5):**
   - `ioSize` ∈ {1,2,4,8} MiB (default 4) — passed in; fixed for the run (FR-CTRL-8).
   - `blocksPerChunk = ioSize / blockSize`; iterate from block 0 to `blockCount-1`.
   - **Final chunk:** size to **exactly the remaining blocks**, i.e. `remaining = blockCount - offsetBlocks`, length `= remaining * blockSize` — **rounded to the logical block size, never to an arbitrary byte remainder** (FR-TEST-5). (Because the device is an integer number of logical blocks, the final chunk is already a whole number of blocks; the requirement is to never truncate to a sub-block byte count.)
6. **Bounded memory (NFR-PERF-1/2):** allocate exactly **two** buffers of `ioSize` (original-read + verify-read) and reuse them for every chunk — memory must **not** scale with device capacity. Use page-aligned buffers (`valloc`/`posix_memalign`) for raw I/O.
7. **`os_log`** device open and geometry (NFR-OBS-1) — never log contents (NFR-SEC-6).

### Verification Gate (must pass before Step 8)
- [ ] Against the **designated scratch device** (`disk4`), geometry (block size, block count, capacity) reads correctly and matches `diskutil info`. *(Amended 2026-08-01: disk images are not an option — see "The test target" below.)*
- [ ] The chunk plan computed for several sizes (e.g. a device whose block count is **not** a multiple of `blocksPerChunk`) yields a correct final chunk equal to the exact remaining blocks — verified by **unit tests using `InMemoryBlockDevice`** with deliberately awkward sizes, for both 512B and 4096B blocks.
- [ ] Peak buffer memory == ~2×`ioSize` regardless of device size (instrument and confirm; NFR-PERF-1).
- [ ] `F_NOCACHE`/`F_GLOBAL_NOCACHE` are set (verified by code path / no cache-hit behavior on re-read timing).

### The test target (amended 2026-08-01, user decision)

**All real-hardware I/O testing uses `disk4`** — the Samsung Portable SSD T5, 1 TB, 512-byte
blocks, one exFAT volume `Test_Drive`. It holds only expendable test files. **Disk images
are not used and are not supported as a test target.**

Two reasons, one practical and one deliberate:

1. **They do not work.** Discovery lists USB mass-storage whole disks only, and an attached
   disk image reports `Physical Interconnect == "Virtual Interface"` (measured, Step 5). It
   never appears in the device list, so it cannot be selected, and the helper's own
   independent identity re-check (Step 6) would refuse it as ineligible even if it were.
   The original wording here — "or a disk image attached as a raw device for safety" —
   could not have been followed.
2. **They would be the wrong kind of safe.** This project's recurring defect is a
   substitute standing in for the real thing: a disk image that exercised a notification
   path but had no filesystem, an APFS drive that masked a bug the exFAT drive exposed, an
   incremental build that hid warnings, three `open(2)` flag combinations that reported a
   permission as granted when it was not. A disk image has no USB bridge, no real block
   device, and no NAND — exactly the layers this tool exists to exercise.

**What does *not* change:** the drive being expendable relaxes the *consequence* of a bug,
not the discipline. NFR-REL-1 still requires non-destructiveness to be **proven in
simulation first** (Step 8's gate), and the engine must still write back the bytes it read
rather than any pattern (FR-TEST-7). "We can afford to lose this data" is not a licence to
skip the in-memory proof; it is what makes the hardware run survivable when the proof
misses something.

### Risks / gotchas
- **All destructive testing goes on `disk4`, the designated scratch device.** Even though the algorithm is non-destructive, bugs in this step write to raw blocks. Never `disk6` (holds the source tree) or `disk8`.
- Raw devices reject misaligned offsets/lengths with `EINVAL` — alignment is not optional.
- Some USB bridges report odd geometry; trust the ioctl and reject impossible values.
- **The helper needs Full Disk Access** (NFR-INST-4, added 2026-08-01) or the raw open fails `EPERM`. Running as root is not sufficient.
- **Releasing an `O_EXLOCK` open or a `DADiskClaim` makes macOS remount the volume within milliseconds** (measured). Any code that opens and closes the raw device outside a held acquire will undo the user's unmount.

---

## Step 8 — read → write-back → read-verify cycle

**Original action item:** AI-6
**Satisfies:** FR-TEST-1/3/4/7/8; FR-FAIL-6/7; NFR-REL-1/2/4/8
**Trust boundary:** **helper-side core** (runs identically against the simulated device).

### Objective
Implement the heart of the tool: for each chunk, read original → write the *same* bytes back → read again into a second buffer → compare. Bit-for-bit non-destructive, one chunk in flight, no journaling, no resume.

### Detailed steps
1. **Per-chunk cycle (FR-TEST-3):**
   - `read` original chunk into buffer A at the chunk's offset.
   - `write` **buffer A unchanged** back to the same offset (FR-TEST-7 — never patterns/known values).
   - `read` the just-written data into buffer B.
   - **compare A vs B** byte-for-byte; any single-bit difference is a verify failure (NFR-REL-8, FR-TEST-8).
2. **Sequential whole-device traversal (FR-TEST-1/4):** first addressable block → last, in order, using the Step 7 chunk plan.
3. **Failure classification (FR-FAIL-6):** a chunk fails if the read errors, the write errors, **or** the verify mismatches. Produce a `BlockRangeFailure { startBlock, blockCount, kind }`. (How the run *reacts* to a failure — halt vs. continue — is Step 10; this step only **detects and classifies**.)
4. **No journaling / one-chunk-in-flight (FR-FAIL-7, NFR-REL-4):** never hold more than the current chunk's original data (in buffer A). The in-flight data-loss window is bounded to exactly the chunk being written.
5. **No resume (FR-FAIL-7):** if interrupted, the engine reports and the run is over — there is no checkpoint to resume from. (Restart-from-beginning is wired in Step 11.)
6. **Clean termination contract (NFR-REL-5):** on stop/error, issue no further writes and leave buffers/state consistent for the caller to release the device.
7. **`os_log`** run start, and each failed block range (NFR-OBS-1) — never the data itself (NFR-SEC-6).

### Verification Gate (must pass before Step 9)
- [ ] **Non-destructiveness proven in simulation (NFR-REL-1):** fill an `InMemoryBlockDevice` with known random data, run the full cycle over the whole device, assert the backing store is **bit-for-bit identical** afterward.
- [ ] **Verify-mismatch detection (NFR-REL-8):** with write-corruption fault injection on a specific block range, the engine flags exactly that range as a verify failure and no other.
- [ ] **Hard-error classification (FR-FAIL-6):** with read-error and write-error fault injection, the engine produces correctly-typed `BlockRangeFailure`s for the injected ranges.
- [ ] **One-chunk-in-flight (NFR-REL-4):** instrumentation confirms only one chunk's worth of original data is ever held.
- [ ] The cycle also runs end-to-end against the **designated scratch device** (`disk4`) and leaves its contents unchanged (checksum before == after). *(Amended 2026-08-01: disk images are not a test target — see Step 7, "The test target". The drive's data is expendable, which is what makes this survivable if the simulation proof missed something — it is not a reason to run it before that proof passes.)*

### Risks / gotchas
- A torn write to GPT/superblocks can brick an otherwise-good drive (per the brief) — this is exactly why the simulation-first verification above is mandatory before trusting hardware.
- Ensure the write of buffer A truly precedes the verify read and that no caching makes the verify read a no-op (Step 7's `F_NOCACHE` is what makes the verify meaningful).

---

## Step 9 — Metrics: throughput + read-latency (min/max/p99) with live monitoring

**Original action item:** AI-8
**Satisfies:** FR-METR-1/2/3/4/5/6; NFR-PERF-3/4/5/6/7, NFR-USE-1/2
**Trust boundary:** measured **helper-side**, displayed **GUI-side** via XPC progress callbacks.

### Objective
Measure average read and write throughput and per-chunk read latency (min/max/p99), and surface progress + a measured-throughput ETA live in the GUI, refreshing at least once per second, all with negligible overhead and constant memory.

### Detailed steps
1. **Throughput (FR-METR-1):** accumulate bytes read and bytes written and elapsed time; report running averages (MB/s). Use a monotonic clock.
2. **Read latency per chunk (FR-METR-3):** time each original read. Maintain **min**, **max**, and a **p99** using a **constant-memory** method (fixed-bucket histogram or a streaming/approximate percentile such as t-digest) — must **not** store per-chunk samples (NFR-PERF-7).
3. **Progress + ETA (FR-METR-5/6):** percent complete and current block offset; ETA = remaining bytes ÷ measured average throughput, **updated continuously** and converging over time (NFR-PERF-6). Never assume a fixed link speed (NFR-COMPAT-7).
4. **Live push to GUI (FR-METR-2/4, NFR-PERF-5):** helper sends a metrics snapshot to the GUI over the XPC progress callback **at least once per second**. Keep the per-chunk measurement overhead negligible relative to device I/O (NFR-PERF-3).
5. **UI responsiveness (NFR-PERF-4):** all heavy work is in the helper / off the main thread; the GUI only renders snapshots. Format values human-readably with clear units — MB/s, ms (NFR-USE-1) — and show percent/position/ETA clearly (NFR-USE-2).
6. **Carry metrics into the report:** expose the final throughput and latency stats so Step 10's report can include them.

### Verification Gate (must pass before Step 10)
- [ ] During a (simulated or real) run, the GUI shows read & write throughput, read-latency min/max/p99, percent complete, current position, and ETA, all **refreshing ≥ once per second**.
- [ ] p99/min/max computed with **constant memory** — verified by running a very large simulated device and confirming no per-chunk sample growth.
- [ ] ETA converges toward actual remaining time as the run progresses (observed on a long-enough run).
- [ ] GUI stays responsive (scroll/interact) throughout (NFR-PERF-4).
- [ ] Latency p99 from a controlled fault-injection (artificially slow reads on some chunks) reflects the injected slow tail.

### Risks / gotchas
- Don't let metrics formatting/IPC dominate per-chunk time — batch/throttle the once-per-second push rather than sending per chunk.
- Approximate-percentile error is acceptable (the spec says "e.g., p99"); document the method chosen.

---

## Step 10 — Failure modes + end-of-run bad-block report + Markdown export

**Original action item:** AI-7
**Satisfies:** FR-FAIL-1/2/3/4/5; FR-RPT-1/2/3/4/5; NFR-USE-7
**Trust boundary:** mode logic **helper-side**; report assembly/export **GUI-side**.

### Objective
React to classified failures per the user-selected mode, and conclude every run with a structured report — bad-block ranges + throughput + latency + outcome — exportable to Markdown.

### Detailed steps
1. **Two modes, chosen before the run (FR-FAIL-1, default = log-and-continue FR-FAIL-4):**
   - **Stop on first error (FR-FAIL-2):** on the first hard I/O failure (or verify mismatch), halt immediately and report the offending range. (No resume — restart from the beginning, FR-FAIL-7.)
   - **Log and continue (FR-FAIL-3):** append the offending range to a bad-block list and keep refreshing the rest of the device.
2. **Both modes end with a report (FR-FAIL-5, FR-RPT-1):** list **every** failed block range (hard error or verify mismatch).
3. **Report contents:**
   - Bad-block ranges (start block, length, kind) (FR-RPT-1).
   - Average read/write throughput (FR-RPT-2) and read-latency min/max/p99 (FR-RPT-3) — from Step 9.
   - **Run outcome (FR-RPT-4):** completed clean / completed with failures / stopped on error / stopped by user / terminated by device loss.
   - Device identity, I/O size, failure mode, start/end time.
4. **Markdown export (FR-RPT-5, NFR-USE-7):** an "Export report…" action writing a well-structured `.md` (via `NSSavePanel`): headings, a clear pass/fail outcome line, and **tabulated** bad-block ranges and statistics. No run history is retained (each run standalone) — export is the only persistence.
5. **Honest outcome wording:** "completed clean" must read as "no currently-unreadable blocks found," not "healthy" (ties to Step 14 / FR-WARN-3).
6. **`os_log`** the failure-mode selection and final outcome (NFR-OBS-1).

### Verification Gate (must pass before Step 11)
- [ ] **Stop-on-error:** with an injected fault, the run halts immediately at the offending range and reports it; nothing past it is processed.
- [ ] **Log-and-continue (default):** with multiple injected faults, all bad ranges are recorded and the rest of the device is still refreshed to completion.
- [ ] A clean run reports "completed clean / no currently-unreadable blocks," with throughput + latency stats present.
- [ ] Exported Markdown is well-structured (headings, outcome line, tabulated ranges + stats) and opens cleanly in a Markdown viewer.
- [ ] Outcome field correctly distinguishes clean / with-failures / stopped-on-error / stopped-by-user.

### Risks / gotchas
- Coalesce contiguous failing chunks into ranges for a readable report, but don't lose a non-contiguous failure.
- The report must include stats even when the run stopped early.

---

# Phase 4 — Control, Resilience, and Power

## Step 11 — Run-control state machine: start / pause / resume / stop / restart

**Original action item:** AI-10
**Satisfies:** FR-CTRL-1/2/3/4/5/6/7/8/9; NFR-REL-10
**Trust boundary:** state owned **GUI-side**, enforced **helper-side** (pause must settle in the helper).

### Objective
Implement the explicit run-control state machine with legal-transition enforcement, the pre-run controls (I/O size, failure mode), single-device-at-a-time enforcement, and a pause that settles at a chunk boundary with no write in flight.

### Detailed steps
1. **Define states:** `Idle → Configured → Running ⇄ Paused → (Stopped | Completed | Failed)`; `Restart` returns to the start of `Running` from beginning. Enumerate **legal transitions only** (FR-CTRL-6): pause only while running; resume only from paused; stop from running/paused; start only from configured/idle.
2. **Pre-run controls (FR-CTRL-7/8):** require failure-mode selection before start; provide the **I/O-size dropdown {1,2,4,8 MiB, default 4}**, configurable before start and **fixed for the run's duration**.
3. **Pause settles at a chunk boundary (NFR-REL-10, key safety property):** the helper finishes the current chunk's full read→write→verify (or the read-before-write point with **no write in flight**), then acknowledges the pause, leaving the device consistent. The GUI shows "Paused" only **after** the helper acknowledges (not optimistically).
4. **Resume from point of pause (FR-CTRL-3):** continue at the next chunk (this in-session resume is allowed; it is **not** the prohibited cross-interruption resume of FR-FAIL-7).
5. **Stop (FR-CTRL-4):** halt, release the device (Step 6), produce the report (Step 10) with outcome "stopped by user."
6. **Restart (FR-CTRL-5):** discard state and begin again from block 0.
7. **One device at a time (FR-CTRL-9):** disallow starting a new run while any run is active; the start control is disabled and explained.
8. **`os_log`** start/stop and mode at run start (NFR-OBS-1).

### Verification Gate (must pass before Step 12)
- [ ] Illegal transitions are impossible (e.g., resume while running, start while running) — verified by unit tests over the state machine.
- [ ] Pause acknowledgment arrives **only after** the helper confirms no write is in flight and it is at a chunk boundary (NFR-REL-10) — verified with instrumentation/log timestamps.
- [ ] Resume continues from the correct next chunk; metrics/ETA continue sensibly.
- [ ] Stop releases the device and yields a "stopped by user" report; Restart begins from block 0.
- [ ] I/O size is selectable before start, fixed during the run; failure mode required before start; second concurrent run is refused.

### Risks / gotchas
- Pause acknowledgment is a **two-party handshake** across XPC — never show "Paused" before the helper confirms, or you imply a safety guarantee you don't have.
- State must be the single source of truth gating Step 4 (no uninstall mid-run) and Step 13 (sleep assertion lifecycle).

---

## Step 12 — Device-loss handling (hot-unplug / de-enumeration mid-run)

**Original action item:** AI-9
**Satisfies:** FR-DEV-8; FR-FAIL-7; NFR-REL-5/6
**Trust boundary:** detected **helper-side** (I/O errors) and via **DiskArbitration/IOKit** removal callbacks; surfaced **GUI-side**.

### Objective
If the device under test disappears mid-run, immediately terminate the test cleanly, surface a clear error, and re-run device discovery — with no resume.

### Detailed steps
1. **Detect loss two ways:** (a) raw I/O suddenly returns `ENXIO`/`EIO` from `pread`/`pwrite`; (b) DiskArbitration "disk disappeared" / IOKit termination callback for the device under test. Treat either as device loss.
2. **Terminate immediately and cleanly (NFR-REL-5):** stop issuing I/O, release the claim and close the fd, leave the helper in a consistent state (no further writes).
3. **Surface a specific error (NFR-REL-6, NFR-USE-5):** GUI shows "The device under test was removed; the run was terminated and cannot be resumed — restart from the beginning if you reconnect it." The GUI must **not crash** and must return to a usable state.
4. **No resume (FR-FAIL-7):** the partially-completed run is over; only restart-from-beginning is offered.
5. **Re-run discovery (FR-DEV-8):** automatically re-execute Step 5's discovery routine so the (possibly reconnected) device list is fresh.
6. **`os_log`** device loss and clean termination (NFR-OBS-1/2 — logs must be enough to diagnose the interrupted run after the fact).

### Verification Gate (must pass before Step 13)
- [ ] Physically unplugging the device mid-run (`disk4`, the designated scratch device) **immediately** terminates the run, releases the node, and shows the specific device-loss error — the GUI stays alive and usable.
- [ ] Discovery re-runs automatically; reconnecting the device repopulates the list.
- [ ] No resume is offered; only restart-from-beginning.
- [ ] Logs after the event are sufficient to reconstruct what happened (which device, at what offset) without recording contents.

### Risks / gotchas
- Simulate this safely first by injecting `ENXIO` via the `InMemoryBlockDevice` fault hook, then confirm on real hardware with `disk4`.
- Ensure the claim is released even though the device is already gone (avoid a stuck DiskArbitration state).

---

## Step 13 — System-sleep prevention

**Original action item:** AI-12
**Satisfies:** NFR-REL-9 (and FR-FAIL-7 rationale)
**Trust boundary:** **GUI-side** power assertion tied to run state.

### Objective
Prevent idle system sleep while a run is **actively executing** (because runs can take many hours and cannot be resumed), and release the assertion the moment the run pauses, stops, completes, or fails.

### Detailed steps
1. **Hold an idle-system-sleep assertion** while `state == Running`: `ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "USB drive retention test in progress")`, retaining the returned token. (Equivalently `IOPMAssertionCreateWithName` with `kIOPMAssertPreventUserIdleSystemSleep` — the ADR specifies the `NSProcessInfo` route.)
2. **Release on every exit from Running (NFR-REL-9):** `endActivity(token)` on pause, stop, completion, and failure (including device loss, Step 12). Driven by the Step 11 state machine so there is exactly one acquire/release path.
3. **Do not prevent display sleep or block manual sleep** — only *idle system* sleep. The user can still deliberately sleep/quit.
4. **`os_log`** assertion acquire/release alongside run start/stop.

### Verification Gate (must pass before Step 14)
- [ ] During an active run, the Mac does not idle-sleep (verify with a short idle-sleep timer or `pmset -g assertions` showing `PreventUserIdleSystemSleep` while running).
- [ ] On pause/stop/complete/fail/device-loss, the assertion is released (`pmset -g assertions` no longer lists it).
- [ ] Exactly one assertion is held at a time (no leaks across pause/resume cycles) — verified across several transitions.

### Risks / gotchas
- The most common bug is a **leaked assertion** on an error path — route acquire/release exclusively through the state machine so every exit releases it.

---

# Phase 5 — Honesty & Observability

## Step 14 — Mandatory pre-run warnings & honest framing

**Original action item:** AI-11
**Satisfies:** FR-WARN-1/2/3/4; NFR-USE-4/6/8
**Trust boundary:** **GUI-side**.

### Objective
Before any run, prominently present the three mandatory warnings and the honest-framing message, requiring acknowledgment so a clean pass is never mistaken for a clean bill of health.

### Detailed steps
1. **Three mandatory warnings, shown prominently before a run starts (NFR-USE-4), and acknowledged before Start is enabled:**
   - **Back up first (FR-WARN-1):** non-destructive *by design*, but data loss/corruption remains possible; back up the device first.
   - **Infrequent on NAND (FR-WARN-2):** this testing should be run only infrequently on NAND devices.
   - **Clean pass ≠ healthy (FR-WARN-3):** a clean pass means "no currently-unreadable blocks were found," **not** that the drive is healthy.
2. **Honest dual-role framing (FR-WARN-4, priority S):** explain that the tool is both a retention refresher and a hard-fault detector, and that degrading-but-still-correctable blocks cannot be detected at the USB block level.
3. **Presentation (NFR-USE-6):** the honest-framing must be positioned so a clean pass cannot reasonably be read as a health certificate — echo it on the result screen and in the report's outcome wording (Step 10).
4. **Accessibility, best-effort (NFR-USE-8):** use SwiftUI's built-in accessibility (VoiceOver labels, Dynamic Type, contrast); **never convey pass/fail by color alone** — pair color with text/icon. Full audit is not a v1 gate.

### Verification Gate (must pass before Step 15)
- [ ] Start is **disabled** until all three mandatory warnings are acknowledged; they appear prominently every run.
- [ ] The honest-framing message appears pre-run and on the result/report so a clean pass can't be mistaken for "healthy."
- [ ] Pass/fail is conveyed by text/icon, not color alone (toggle to grayscale and confirm meaning survives).
- [ ] VoiceOver reads the warnings and result; Dynamic Type scales them.

### Risks / gotchas
- Don't bury the warnings in a settings pane; they must gate the Start action each run (the spec says "before a run starts," not "once").

---

## Step 15 — Logging / observability consolidation

**Original action item:** AI-15
**Satisfies:** NFR-OBS-1/2; NFR-SEC-6
**Trust boundary:** **both** (app and helper each log to unified logging).

### Objective
Ensure all significant events from both executables are emitted to the macOS unified logging system, sufficient to diagnose an interrupted/failed run after the fact, and **never** recording device contents.

### Detailed steps
1. **Audit the event set (NFR-OBS-1):** confirm `os_log`/`Logger` points exist for: run start/stop, failure-mode selection, failed block ranges, device connect/loss, helper registration/unregistration, exclusive-claim acquire/release, pause/resume, sleep-assertion acquire/release. (Most were added per-step; this step fills gaps and standardizes.)
2. **Subsystem/category scheme:** one subsystem (your bundle id) with categories like `discovery`, `safety`, `io`, `metrics`, `lifecycle`, `xpc` — for both targets — so logs filter cleanly in Console/`log show`.
3. **Diagnosability of interrupted runs (NFR-OBS-2):** ensure a failed/interrupted run leaves enough breadcrumbs (which device, offset/block at failure, outcome) to reconstruct what happened.
4. **Privacy (NFR-SEC-6, NFR-OBS-2):** **never** log device contents. Mark any potentially-identifying interpolations as `private` in `os_log` format strings; offsets/sizes/BSD names are fine, data bytes are not.
5. **No user-visible activity log required for v1** (resolved open question) — unified logging is sufficient.

### Verification Gate (must pass before Step 16)
- [ ] `log show --predicate 'subsystem == "<bundle-id>"'` (and Console) shows a coherent trace across a full run lifecycle from both app and helper.
- [ ] An induced interrupted run (device loss / stop-on-error) is fully reconstructable from logs (device, offset, outcome).
- [ ] No log entry anywhere contains device data bytes (inspect read/write/verify paths specifically).

### Risks / gotchas
- The privileged helper logs as root; double-check no buffer contents are interpolated into format strings even at debug level.

---

# Phase 6 — Ship

## Step 16 — Code-signing, hardened runtime, notarization

**Original action item:** AI-13
**Satisfies:** NFR-SEC-4, NFR-INST-2; supports NFR-SEC-2 (Team-ID stability)
**Trust boundary:** **both** targets.

### Objective
Code-sign both the app and the helper, enable the hardened runtime, and notarize so the app launches Gatekeeper-clean on a clean supported Mac.

### Detailed steps
1. **Sign both targets** with a Developer ID (or Apple Distribution) identity under the **same Team ID** the helper pins in Step 3 (NFR-SEC-2 depends on this stability). The embedded helper must be signed and sealed inside the app bundle.
2. **Enable the hardened runtime** (NFR-SEC-4) on both targets. Request **only the entitlements actually required** (NFR-SEC-7) — keep the set minimal.
3. **Notarize:** archive, submit via `notarytool`, and **staple** the ticket to the app (NFR-INST-2).
4. **Verify Gatekeeper-clean launch (NFR-INST-2):** on a **clean** macOS 26 machine (or a fresh user), download/copy the app, confirm it launches without Gatekeeper warnings, registers the helper via `SMAppService` (Step 3), and the helper accepts the now-properly-signed client (Step 3's Team-ID requirement is satisfied by the real signature).
5. **Confirm the install/uninstall lifecycle** end-to-end on the clean machine (Steps 3 & 4) with the signed build.
6. **`os_log`** nothing new required; ensure release logging level is sane.

### Verification Gate (release gate)
- [ ] `codesign --verify --deep --strict` and `spctl -a -vv` pass on the app; the embedded helper is validly signed under the expected Team ID.
- [ ] Hardened runtime is on; entitlement set is minimal and justified.
- [ ] Notarization succeeds and the ticket is stapled (`stapler validate` passes).
- [ ] On a clean macOS 26 Mac: the app launches with **no Gatekeeper warning**, registers and (after approval) enables the helper, runs a full test on `disk4`, and uninstalls the helper cleanly.
- [ ] The helper's Team-ID code-signing requirement (Step 3) now matches the real signing identity end-to-end.

### Risks / gotchas
- `SMAppService` is unforgiving about signing/notarization: an unsigned or mismatched helper fails to register on a clean system. This step is what makes Step 3 work for real users.
- Test on a machine that has **never** run a dev build of this app, or you'll get false "it works" results from cached approvals.

---

## Appendix A — Action-item → build-step cross-reference

| ADR AI | Build Step |
|--------|-----------|
| AI-1 Xcode workspace | Step 1 |
| AI-2 SMAppService + XPC + code-sig validation | Step 3 |
| AI-3 Device discovery | Step 5 |
| AI-4 Mount-guard / exclusive access | Step 6 |
| AI-5 Raw I/O core | Step 7 |
| AI-6 read→write→verify cycle | Step 8 |
| AI-7 Failure modes + report + Markdown export | Step 10 |
| AI-8 Metrics (throughput + latency) | Step 9 |
| AI-9 Device-loss handling | Step 12 |
| AI-10 Run-control state machine | Step 11 |
| AI-11 Pre-run warnings | Step 14 |
| AI-12 System-sleep prevention | Step 13 |
| AI-13 Signing & distribution | Step 16 |
| AI-14 Helper teardown | Step 4 |
| AI-15 Logging/observability | Step 15 (woven throughout) |
| AI-16 Test abstraction | Step 2 |

## Appendix B — The discipline of this plan

1. **One step at a time.** Do not begin a step until the previous step's Verification Gate is fully checked off.
2. **Simulate before you touch hardware.** Steps 2, 7, 8, 9, 10, 12 all have an in-memory verification *before* the real-device verification. Never debug the algorithm on a drive you can't afford to lose.
3. **Always test on the designated scratch device** (`disk4`) for any real-hardware step. The tool writes raw blocks; treat every hardware run as potentially destructive until proven otherwise. Disk images are **not** an alternative — discovery excludes them by design, and they lack the USB bridge, block device and NAND this tool exists to exercise (amended 2026-08-01).
4. **The trust boundary is sacred.** Raw I/O only ever happens in the helper; the GUI never elevates. Re-confirm this at every step that adds helper code.
5. **Record what you verified.** A one-paragraph note per step (in `PROGRESS.md` or the commit) keeps the deliberate pace auditable.
