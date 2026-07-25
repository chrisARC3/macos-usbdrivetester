# Build Progress Log

Tracks what each build step delivered and how its Verification Gate was confirmed.
See [BUILD-PLAN.md](BUILD-PLAN.md) for the full plan.

---

## Step 1 — Xcode workspace (two targets) — COMPLETE

**Sub-stage 1A (Xcode GUI scaffold) — DONE**
- App target `USBDriveTester` (SwiftUI), helper Command Line Tool target
  `com.arc3solutions.USBDriveTester.Helper`, unit-test target `USBDriveTesterTests`
  (Swift Testing), and an extra `USBDriveTesterUITests` (unused).
- App + helper Minimum Deployment = macOS 26.0; arm64 (Standard Architectures).
- Bundle ids under `com.arc3solutions`. Project uses file-system-synchronized groups.

**Sub-stage 1B (authored files) — DONE**
- `USBDriveTester/Shared/TesterControl.swift` — `@objc` XPC protocol with placeholder
  `ping`, plus `HelperIdentity.machServiceName` single-source-of-truth string.
  (Must be added to the **helper** target membership too — GUI step.)
- `com.arc3solutions.USBDriveTester.Helper/main.swift` — NSXPCListener on the Mach
  service, accepts connections, replies `pong`. (Step 3 adds Team-ID code-sig check.)
- `USBDriveTester/HelperConnection.swift` — app-side NSXPCConnection wrapper.
- `USBDriveTester/ContentView.swift` — "Ping helper" button + status UI.
- `Daemon/com.arc3solutions.USBDriveTester.Helper.plist` — LaunchDaemon plist
  (Label / BundleProgram / MachServices / AssociatedBundleIdentifiers) for embedding
  and for SMAppService in Step 3.
- `scripts/build.sh`, `scripts/dev-install-helper.sh`, `scripts/dev-uninstall-helper.sh`.

**Sub-stage 1B (GUI wiring) — DONE & VERIFIED**
- `TesterControl.swift` added to helper target via membership exception set (in both targets).
- App Copy Files phase → `Contents/MacOS` → embeds helper, Code Sign On Copy ✅.
- App Copy Files phase → `Contents/Library/LaunchDaemons` → embeds the daemon plist ✅.
- App → helper target dependency in place.

**Sub-stage 1C (verification) — COMPLETE (live ping deferred to Step 3)**
- [x] Both targets build (arm64 / macOS 26) via `scripts/build.sh` — `** BUILD SUCCEEDED **`.
- [x] `.app` contains helper executable (`Mach-O arm64`, adhoc-signed) AND
      `Contents/Library/LaunchDaemons/com.arc3solutions.USBDriveTester.Helper.plist`.
- [x] GUI launches and shows its window.
- [~] "Ping helper" pong — **DEFERRED to Step 3**. Diagnosed thoroughly:
      * Helper installed via `dev-install-helper.sh`; `launchctl print` shows the
        service registered in the `system` domain with the correct program path and
        Mach endpoint (watching).
      * On-demand launch did not fire on the app's connection (`runs = 0`);
        `launchctl kickstart -kp` force-started it fine (pid 28008, listener up) —
        so the helper binary is healthy and self-contained (only `/usr/lib/swift/*`
        + Foundation deps).
      * Even with the daemon provably running, the app still gets "Couldn't
        communicate with a helper application." → failure is the app↔daemon XPC
        transport trust over the **adhoc-signed, manually-bootstrapped** setup,
        NOT our code. App-side connection code attempts, catches, and reports the
        error correctly.
      * Decision (2026-07-07): defer the live cross-process ping to Step 3, where
        SMAppService establishes the app↔daemon trust the supported way (Team-ID
        signing + AssociatedBundleIdentifiers). Step 3's gate already requires a
        real XPC round-trip through the registered daemon.

**Step 1 status: COMPLETE** (build + embed + GUI launch verified; live ping carried
into Step 3 as its first acceptance item).

**Notes for later steps**
- Helper currently signs with Identifier `com.arc3solutions.USBDriveTester` (no own
  Info.plist yet) and `TeamIdentifier=not set` (adhoc). Step 3 adds the helper's
  embedded Info.plist + CFBundleIdentifier `…​.Helper`; Step 16 adds Developer ID +
  Team ID, which Step 3's code-sig requirement will validate against.

---

## Step 2 — Raw-device abstraction, simulated device, test harness — COMPLETE

**AI-16 / satisfies NFR-MAINT-2 (de-risks FR-TEST-*, FR-FAIL-*, FR-METR-*).**

**Authored files.** Core lives under `com.arc3solutions.USBDriveTester.Helper/Core/`,
compiled into the **helper** target (auto, synchronized folder) and the **test**
target (membership exception), but deliberately **not** the app module — that keeps
it free of the app target's default `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
the core stays pure. Foundation-only; no IOKit/UIKit/Dispatch/privilege.
- `Core/RawBlockDevice.swift` — protocol (`logicalBlockSize`, `blockCount`,
  `read`/`write` at 64-bit byte offsets; `byteCount` extension) + `DeviceIOError`
  (`readError`, `writeError`, `shortTransfer`, `misaligned`, `outOfRange`). Documents
  the alignment / range / full-transfer contract (NFR-COMPAT-5/6).
- `Core/InMemoryBlockDevice.swift` — `[UInt8]`-backed device; validates alignment +
  range on every call; fault injection (`injectReadFault` / `injectWriteFault` /
  `injectSilentCorruption`, block-range granularity — corruption flips one bit per
  block on write so a later verify mismatches, NFR-REL-8); `snapshot()` for
  before/after comparisons.
- `Core/RetentionTestEngine.swift` — stub computing only the chunk plan:
  `chunkPlan() -> [Chunk]` with the exact-remainder final chunk (FR-TEST-5);
  `ChunkPlanError` for non-positive / non-block-aligned I/O size. The {1,2,4,8} MiB
  dropdown that maps onto `ioSizeBytes` is deferred to Steps 7/11.
- `USBDriveTesterTests/InMemoryBlockDeviceTests.swift`,
  `USBDriveTesterTests/RetentionTestEngineTests.swift` — Swift Testing suites.
- `scripts/test.sh` — `DEVELOPER_DIR`-pinned `xcodebuild test`, scoped with
  `-only-testing:USBDriveTesterTests` (the unused template UITests are excluded to
  keep the TDD loop fast; drop the flag to run everything).

**GUI wiring (verified in project.pbxproj).**
- All three `Core/*.swift` added to `USBDriveTesterTests` membership — exception set
  on the helper's synchronized root group with `target = USBDriveTesterTests`.
- Deferred tidy-ups folded in: `ARCHS = arm64` at project level (Debug + Release);
  `MACOSX_DEPLOYMENT_TARGET` normalized to `26.0` (project floor **and**
  `USBDriveTesterTests`; `USBDriveTesterUITests` now inherits 26.0; app + helper
  already 26.0). Fixes a latent 26.5 project floor (NFR-COMPAT-2).

**Verification Gate — COMPLETE.**
- [x] `RawBlockDevice` + `InMemoryBlockDevice` compile into the helper target
      (`./scripts/build.sh` → `** BUILD SUCCEEDED **`) **and** the test target; no
      UIKit/IOKit/privileged deps (Foundation-only, outside the app module).
- [x] Swift Testing green on 512-byte **and** 4096-byte round-trips (`roundTrip512`,
      `roundTrip4096`).
- [x] Fault injection forces a read error, a write error, and a silent corruption /
      verify-mismatch (`readFaultThrowsExactError`,
      `writeFaultThrowsAndLeavesStoreUnchanged`,
      `silentCorruptionCausesReadBackMismatch`).
- [x] Engine chunk-plan stub callable from tests; final chunk = exact remaining
      blocks for both geometries (`finalChunkIsExactRemainder512/4096`, plus
      exact-multiple / smaller-than-ioSize / empty / invalid-size cases).
- [x] Global DoD: builds arm64 / macOS 26.0 with **no new warnings**;
      `./scripts/test.sh` → `** TEST SUCCEEDED **`, 15 tests, 0 warnings (only the
      benign `appintentsmetadataprocessor` "No AppIntents.framework" note remains).

**Notes.**
- Placeholder `USBDriveTesterTests/USBDriveTesterTests.swift` (`example()`) left in
  place — harmless, still passes.
- No `os_log` this step: Core is a pure algorithm stub with no significant runtime
  events yet. Logging grows per-step and is consolidated in Step 15.
- **Next: Step 3** (SMAppService registration + XPC protocol + Team-ID code-signature
  validation), which also carries the **deferred live XPC ping** from Step 1 as its
  first acceptance item.

---

## Step 3 — SMAppService + XPC protocol + code-sig validation — NOT STARTED

**AI-2 / satisfies FR-ARCH-3/4/5/6; NFR-SEC-1/2/3/5, NFR-INST-1, NFR-MAINT-1.**

Scoped and analysed on 2026-07-25; **no files authored yet, no Xcode changes made
yet.** Four decisions are outstanding (below). Recorded here so the analysis is not
re-derived from scratch.

### Why this step is different from Steps 1–2
Most of the gate is **verified interactively on the machine**, not by unit tests or a
CLI build: SMAppService registration, the System Settings approval click, the live
round-trip through the *registered* daemon, and the foreign-client rejection. The CLI
can prove compilation and inspect `project.pbxproj` / the plist, but the run-and-approve
sequence has to be driven from Xcode (⌘R).

### Key finding — real signing is the enabler (unblocks the Step 1 deferral)
The build is currently **adhoc**-signed (`"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-"` on
the app target; helper shows `TeamIdentifier=not set`). That is precisely why the Step 1
live ping failed and was deferred here. Step 3 requires:
- **App + helper signed as Apple Development under team `5JC55GTLZA`** (automatic
  signing; `DEVELOPMENT_TEAM` is already set project-wide). An Apple Development cert
  satisfies `anchor apple generic and certificate leaf[subject.OU] = "5JC55GTLZA"`, so
  our own client passes the requirement and an adhoc/foreign client fails it.
- **Helper needs its own embedded `Info.plist`** (`CFBundleIdentifier` =
  `com.arc3solutions.USBDriveTester.Helper`) so it stops signing under the app's
  identifier. Noted as a Step 1 follow-up; due now.
- **App Sandbox is currently ON** (`ENABLE_APP_SANDBOX = YES`, template default) and
  very likely must be **OFF** — a sandboxed app cannot freely look up a privileged
  system-domain Mach service, which would block gate item 2. **Unverified assumption —
  confirm empirically before treating as fact.** Hardened Runtime stays ON. Turning the
  sandbox off does not elevate the GUI; it still runs unprivileged (NFR-SEC-1 intact).

### Proposed file plan (not yet written)
- `Shared/TesterControl.swift` *(expand)* — versioned protocol: keep `ping`, add
  `protocolVersion(reply:)` and `validateRunParameters(...)` over primitives; add
  `TesterProtocol.version = 1` and `HelperIdentity.expectedTeamID`.
- `Core/RunParameterValidator.swift` *(new)* — pure alignment/range validator
  (NFR-REL-7), unit-tested; reused by Steps 6/7. Needs the same test-target membership
  tick as the Step 2 Core files.
- `…Helper/main.swift` *(rewrite delegate)* — `setCodeSigningRequirement(...)` in
  `shouldAcceptNewConnection`; implement the new methods; `os_log` accept/reject.
- `…Helper/Helper-Info.plist` *(new)* — embedded via `INFOPLIST_FILE` +
  `CREATE_INFOPLIST_SECTION_IN_BINARY`. Must live **outside** a synchronized source
  folder or it will be treated as a source input.
- App: `HelperRegistration.swift` *(new,* `@MainActor` *SMAppService manager)*,
  `HelperConnection.swift` *(expand)*, `ContentView.swift` *(interim Step-3 panel:
  status, Register, approval guidance, version round-trip, bad-parameter demo)*.
- `tools/negative-client/main.swift` + `scripts/negative-test.sh` — standalone
  `swiftc`-built, **adhoc-signed** client to prove rejection (gate item 3)
  reproducibly, without a throwaway Xcode target.
- `USBDriveTesterTests/RunParameterValidatorTests.swift`.

### Open decisions — ANSWER THESE FIRST
1. **App Sandbox → Off?** (recommended; else the privileged Mach lookup is blocked and
   gate item 2 cannot pass — alternative is a fragile mach-lookup temporary exception).
2. **Code-sig mechanism:** `setCodeSigningRequirement` only (recommended, supported on
   macOS 13+), or additionally a manual audit-token `SecCodeCheckValidity` check?
3. **Protocol scope:** minimal now (`ping` + `protocolVersion` + `validateRunParameters`),
   deferring `startRun`/pause/resume/stop and the `*Client` progress-callback protocol to
   the steps that implement them (recommended, per NFR-SEC-3) — or fuller stubs now?
4. **Negative-test harness:** standalone `swiftc` adhoc client (recommended) or a
   dedicated throwaway Xcode target?

### Verification Gate (unchanged, from BUILD-PLAN.md)
- [ ] `register()` installs the daemon; after approval `.status == .enabled`; GUI shows it.
- [ ] Real XPC round-trip succeeds **through the registered daemon** (carries Step 1's
      deferred live ping).
- [ ] **Negative test:** adhoc/foreign-signed client is **rejected** and the rejection is
      logged. *(the security gate — do not pass the step without demonstrating this)*
- [ ] Out-of-range / misaligned parameter request rejected with a clear error (NFR-REL-7).
