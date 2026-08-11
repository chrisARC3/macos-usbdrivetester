# Step 2 — Raw-device abstraction, simulated device, test harness

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

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
