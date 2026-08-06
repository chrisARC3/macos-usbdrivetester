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

## Step 3 — SMAppService + XPC protocol + code-sig validation — COMPLETE

**AI-2 / satisfies FR-ARCH-3/4/5/6; NFR-SEC-1/2/3/5, NFR-INST-1, NFR-MAINT-1.**

Scoped 2026-07-25; decisions taken and **all source authored the same day**. Xcode
build-settings changes and the interactive gate are outstanding — see
"Current state" at the end of this section.

### Decisions taken (2026-07-25)

1. **App Sandbox → OFF.** Confirmed as more than the Mach-lookup issue: a sandboxed
   process cannot resolve a privileged *global* Mach name without a
   `temporary-exception.mach-lookup.global-name` entitlement; registering a
   system-wide root daemon is at odds with sandboxing; and Steps 5/6/7 need IOKit
   enumeration and DiskArbitration unmount/claim, which the sandbox also blocks. We
   ship Developer ID + notarization (Step 16), **not** Mac App Store, and
   notarization requires Hardened Runtime, not App Sandbox. Turning it off *reduces*
   the entitlement set (NFR-SEC-7-positive) and leaves NFR-SEC-1 intact — the GUI
   still runs unprivileged. **Hardened Runtime stays ON.**
2. **Code-sig mechanism → `setCodeSigningRequirement` only.** No manual
   `SecCodeCheckValidity`. Reason: `NSXPCConnection` exposes `processIdentifier` but
   **not** `auditToken`, so a hand-rolled check would have to resolve the peer by
   PID — the PID-reuse/TOCTOU pattern Apple warns against. `setCodeSigningRequirement`
   evaluates the peer's audit token and is strictly stronger. A PID-based lookup is
   retained *only* to enrich log messages, explicitly marked as never a security
   decision.
3. **Protocol scope → minimal**: `ping`, `protocolVersion`, `validateRunParameters`.
   `startRun`/pause/resume/stop and the `*Client` progress protocol are deferred to
   the steps that implement them (NFR-SEC-3); stubbing them now would be dead code
   *and* attack surface. The three chosen methods are exactly what the gate needs.
4. **Negative test → standalone `swiftc` adhoc client**, not an Xcode target.
   Decisive reason: an Xcode target under `CODE_SIGN_STYLE = Automatic` would be
   signed with team 5JC55GTLZA, **satisfy** the requirement and prove nothing — one
   mis-set flag would silently turn the security gate into a no-op.

### Deviations from the original file plan (agreed 2026-07-25)

- **(a) No `Helper-Info.plist` file.** Replaced by `GENERATE_INFOPLIST_FILE` +
  `CREATE_INFOPLIST_SECTION_IN_BINARY` on the helper target, so Xcode synthesises and
  embeds it. Removes the risk of a plist landing inside a synchronized source folder
  and being treated as a build input.
- **(b) `scripts/dev-install-helper.sh` / `dev-uninstall-helper.sh` DELETED.** They
  are now an active hazard, not merely obsolete: they install a manual system
  LaunchDaemon under the **same Label** as the SMAppService one, which would collide
  with the registered daemon and reproduce exactly the kind of failure that cost us
  the Step 1 ping.
- **(c) `scripts/install-app.sh` ADDED.** `SMAppService` records the *path* of the
  registering app; a DerivedData path is replaced on every rebuild, stranding the
  registration (status stuck at `.notFound`/`.requiresApproval`, cleanable only with
  the machine-wide `sfltool resetbtm`). Building to a stable `/Applications` path
  makes the register→approve→test loop repeatable.

### Verified findings (CLI, 2026-07-25)

- **Team ID confirmed empirically.** The only codesigning identity is
  `Apple Development: cpkarr@me.com (424WY3TDB4)`, whose certificate subject is
  `UID=N9Y2LXCNFE, CN=…(424WY3TDB4), OU=5JC55GTLZA` (valid to 2027-05-06). The
  Team ID is the **OU**; the identifier in the common name is the *individual* ID and
  pinning it would reject our own client. Requirement string is therefore
  `anchor apple generic and certificate leaf[subject.OU] = "5JC55GTLZA"`.
- **Environment clean.** No leftover Step 1 daemon: `/Library/LaunchDaemons`,
  `/Library/PrivilegedHelperTools` and `launchctl print system/…Helper` all empty.
- **`setCodeSigningRequirement` enforcement timing — RESOLVED.** This was an open
  question when the step was planned. The macOS 26 SDK header
  (`Foundation/NSXPCConnection.h:118`) settles it:
  > *"Sets the code signing requirement for this connection. If the requirement is
  > malformed, an exception is thrown. If new messages do not match the requirement,
  > the connection is invalidated. It is recommended to set this before calling
  > `resume`, as it is an XPC error to call it more than once."*

  Three consequences, all now reflected in the helper:
  1. The method returns **`void` and does not throw a Swift error** — a malformed
     requirement raises an ObjC exception. There is nothing to `try`/`catch`.
  2. Enforcement is **lazy and per-message**. A non-conforming peer is *admitted* by
     `shouldAcceptNewConnection` and torn down when it sends its first message.
     Returning `true` therefore means "requirement armed", not "caller trusted".
  3. It follows that the gate's "rejection is logged" requirement is satisfied in
     `invalidationHandler`, **not** in the delegate.
- **False-pass hazard in the negative test, found and closed.** A client that gets no
  reply looks identical whether it was rejected or no daemon exists at all. The
  harness therefore (i) requires the daemon to be loaded *before* running, and
  (ii) afterwards asserts the helper's own log names the client's pid. Without both,
  an absent daemon would report a passing security gate.

### Authored (all compile clean, zero warnings)

- `Shared/TesterControl.swift` *(rewritten)* — versioned contract; `TesterProtocol.version = 1`;
  `HelperIdentity` gains `appBundleIdentifier`, `loggingSubsystem`, `daemonPlistName`,
  `expectedTeamID`, `codeSigningRequirement`.
- `Core/RunParameterValidator.swift` *(new)* — pure `DeviceGeometry` /
  `ValidatedRunRange` / `RunParameterRejection` / `RunParameterValidator`. Includes
  overflow-checked range arithmetic; a wrapping `offset + length` is the exact input
  that defeats a naive bounds check, and is rejected.
- `…Helper/main.swift` *(rewritten)* — Team-ID requirement armed per connection;
  accept/reject/invalidation logging; the three protocol methods; advisory-only peer
  identification. Log categories `xpc` / `lifecycle` under one shared subsystem, which
  is the scheme Step 15 consolidates.
- `USBDriveTester/HelperRegistration.swift` *(new)* — `@MainActor @Observable`
  SMAppService manager: status + explanation, register, dev-only unregister,
  `openSystemSettingsLoginItems()`, and a warning when running from a non-/Applications
  path.
- `USBDriveTester/HelperConnection.swift` *(rewritten)* — adds `checkProtocolVersion`
  and `validateRunParameters`; shared `withProxy` error plumbing; invalidation handler
  now hops to the main actor before mutating state.
- `USBDriveTester/ContentView.swift` *(rewritten)* — interim Step-3 gate harness
  (registration / round-trip / parameter-validation sections). Explicitly disposable.
- `USBDriveTesterTests/RunParameterValidatorTests.swift` *(new)* — 20 tests including
  both integer-overflow attack cases and message-quality assertions.
- `tools/negative-client/main.swift` + `scripts/negative-test.sh` *(new)*.
- `scripts/install-app.sh` *(new)*; `build.sh`/`test.sh` gain
  `-allowProvisioningUpdates` (automatic signing from the CLI needs it).

### CLI verification done so far

- `./scripts/build.sh` → `** BUILD SUCCEEDED **`, **zero warnings**. Confirms the
  authored sources compile in the real project. Build log still shows
  `Signing Identity: "Sign to Run Locally"` — i.e. the adhoc signing that the pending
  build-settings change must replace.
- Standalone `swiftc -typecheck` clean for: helper target sources; app target sources
  (with `-default-isolation MainActor`, matching `SWIFT_DEFAULT_ACTOR_ISOLATION`);
  and test sources with the Testing macro plugin loaded.
- Validator **logic** proven by a throwaway runtime harness mirroring the test
  assertions — all 22 checks passed, including a demonstration that the wrapping add
  would have passed an unchecked bounds test.
- `tools/negative-client` builds and signs adhoc: `Signature=adhoc`,
  `TeamIdentifier=not set` — confirming it is genuinely a foreign caller.

### Xcode GUI changes — DONE & VERIFIED in project.pbxproj (2026-07-27)

| Change | Debug | Release |
|---|---|---|
| App `ENABLE_APP_SANDBOX` | `NO` | `NO` |
| App `CODE_SIGN_IDENTITY[sdk=macosx*]` | `Apple Development` | `Apple Development` |
| Helper `GENERATE_INFOPLIST_FILE` / `CREATE_INFOPLIST_SECTION_IN_BINARY` | `YES` | `YES` |
| Helper `PRODUCT_BUNDLE_IDENTIFIER` | `com.arc3solutions.USBDriveTester.Helper` | same |
| Helper `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | `1.0` / `1` | same |
| `Core/RunParameterValidator.swift` → `USBDriveTesterTests` membership | exception set, `target = USBDriveTesterTests` |

(The App Sandbox toggle lives in a newer place in the Xcode 26 UI than the
capability-card route originally described; the resulting build setting is identical.)

### Post-GUI verification (CLI, 2026-07-27)

- `./scripts/build.sh` (Debug **and** Release) → `** BUILD SUCCEEDED **`, **zero
  warnings** (only the benign `appintentsmetadataprocessor` note).
- `./scripts/test.sh` → `** TEST SUCCEEDED **`, **36 tests, 0 failures**
  (15 from Step 2 + 21 new `RunParameterValidatorTests`).
- **App signature** — `Identifier=com.arc3solutions.USBDriveTester`,
  `TeamIdentifier=5JC55GTLZA`, `Authority=Apple Development: cpkarr@me.com` →
  `Apple WWDR CA` → `Apple Root CA`. The chain satisfies `anchor apple generic` and
  the OU pin, so our own client passes the helper's requirement. Adhoc signing is gone.
- **App entitlements** — `com.apple.security.app-sandbox` **absent**, confirming the
  sandbox is genuinely off rather than merely unset in the project file.
- **Helper signature** — `Identifier=com.arc3solutions.USBDriveTester.Helper`
  (previously the app's identifier — the Step 1 follow-up is now closed),
  `TeamIdentifier=5JC55GTLZA`, hardened runtime on.
- **Helper embedded Info.plist** — extracted from `__TEXT,__info_plist`:
  `CFBundleIdentifier`/`CFBundleExecutable`/`CFBundleName` =
  `com.arc3solutions.USBDriveTester.Helper`, `CFBundleVersion` 1,
  `CFBundleShortVersionString` 1.0, `LSMinimumSystemVersion` 26.0.
- **Embedded LaunchDaemon plist** still correct and internally consistent: `Label`,
  `MachServices` key and `AssociatedBundleIdentifiers` all agree with
  `HelperIdentity`.
- `scripts/install-app.sh` run: `/Applications/USBDriveTester.app` installed, both
  signatures and the daemon plist verified in place.

### Carried forward to Step 16 — RELEASE NOTE (Step 9, BUILD-PLAN 9.5a, measured 2026-08-05)

**The conditional release-note item is now unconditional: the condition was met.** Measured on
`disk4` across all four I/O sizes (`scripts/metrics-check.sh`, 0 failures):

- At USB 3.1 Gen 2 (~470 MB/s device) the run is **97.4% device-bound** — in-span host overhead
  **2.55%** of device I/O time, daemon CPU **4.22% of one core**. NFR-PERF-3 is satisfied.
- **Host cost follows BYTES MOVED, not chunk count**: across an 8× range of I/O size, µs/MiB varied
  **1.32×** while µs/chunk varied **8.65×**. So **a larger I/O size does not reduce it**, and the
  release note must not imply that it does.
- Because the cost is per-byte, its share rises with transport speed: **10.9%** overhead / 18.0% of
  a core at USB 3.2 Gen 2×2; **20.6%** / 34.1% at USB4. Host work equals device time near
  **18.4 GB/s**; one core saturates near **11.1 GB/s**.

Say in the release notes that on the fastest transports a meaningful fraction of run time is host
processing rather than device I/O — while being clear the run stays device-bound on every
transport this product is likely to meet.

### Carried forward to Step 16 (entitlement minimisation, NFR-SEC-7 / NFR-INST-2)

Not Step 3 gate items, but found during the signature audit and easy to lose:

- **`com.apple.security.get-task-allow` is present on both the app and the helper,
  including in Release.** It is added automatically by *Apple Development* signing and
  permits a debugger to attach — on a **root daemon** that is a real privilege-escalation
  surface, and notarization rejects binaries carrying it. It disappears when Step 16
  re-signs with Developer ID. Verify its absence as part of Step 16's gate.
- **`com.apple.security.files.user-selected.read-only`** persists on the app from
  `ENABLE_USER_SELECTED_FILES = readonly`, a sandbox-only setting that is now inert.
  Step 10's `NSSavePanel` export needs no entitlement without the sandbox, so this can
  simply be set to `No`.
- **The helper carries `com.apple.security.temporary-exception.files.absolute-path.read-only = ["/"]`
  and `…temporary-exception.mach-lookup.global-name` for `testmanagerd` /
  `coresymbolicationd`** — Xcode's test-host entitlements, meaningful only under App
  Sandbox and therefore inert here, but wrong to ship on a privileged daemon.

### Verification Gate — COMPLETE (2026-07-27)

- [x] **`register()` installs the daemon; after approval `.status == .enabled`, shown
      in the GUI.** Observed `notFound -> requiresApproval -> enabled`. Independently
      corroborated by `launchctl print system/com.arc3solutions.USBDriveTester.Helper`:
      `state = running`, `managed_by = com.apple.xpc.ServiceManagement`,
      `path = (submitted by smd.361)`, `parent bundle identifier =
      com.arc3solutions.USBDriveTester` — i.e. genuinely SMAppService-registered, not a
      manual bootstrap.
- [x] **Real XPC round-trip through the registered daemon** — `ping` -> `"pong"` and
      the v1 protocol handshake both succeeded. **This discharges the live ping
      deferred out of Step 1.** Helper log: `helper started as uid 0` (root),
      `ping from pid 6759 (identifier com.arc3solutions.USBDriveTester, team
      5JC55GTLZA); replying pong`.
- [x] **Negative test: foreign client rejected and logged.** `./scripts/negative-test.sh`
      exits 0. Adhoc client (`Signature=adhoc`, `TeamIdentifier=not set`) is admitted,
      then invalidated on its first message, and is never served — there is no
      `ping from pid …` line for it. Helper log:
      `incoming connection from pid 6979 (identifier negative-client-…, team none —
      unsigned or adhoc)` … `invalidated`.
- [x] **Out-of-range / misaligned parameters rejected with a clear error (NFR-REL-7).**
      All four presets behaved exactly as predicted, including the 2⁶⁴-wrapping length.
      Rejection messages name the cause and the corrective value.
- [x] **Global DoD:** builds arm64 / macOS 26.0 Debug **and** Release with **no new
      warnings**; `./scripts/test.sh` → `** TEST SUCCEEDED **`, **36 tests, 0 failures**.

### Late findings during the gate

- **`SMAppService.register()` throws on a first, successful registration.** It raises
  `SMAppServiceErrorDomain` code 1 ("Operation not permitted") while *still* submitting
  the daemon; the status moves `notFound -> requiresApproval` regardless. Reporting the
  error verbatim told the user registration had failed at exactly the moment they
  needed to be sent to System Settings — contradicting the status shown directly above
  it, and inverting the guidance NFR-INST-1 requires. **Fixed:** `register()` now
  treats the *resulting status* as the source of truth and surfaces the thrown error
  only when the status agrees something went wrong. (Re-exercised properly in Step 4,
  whose core deliverable is the register/unregister cycle.)
- **The advisory peer lookup is blocked for binaries on the external volume.** The
  helper's log-only `SecCodeCopyGuestWithAttributes` lookup works for the app in
  `/Applications` (`identifier …, team 5JC55GTLZA`) but returned nothing for a client
  built inside this repo on `/Volumes/1TB_Samsung` — macOS gates daemon access to
  removable volumes. This never affected the security decision, which is made from the
  peer's **audit token**, not from reading the file; it only blanked the log detail.
  `scripts/negative-test.sh` therefore builds its client into `/tmp`, which restores
  `team none — unsigned or adhoc` in the rejection log.

### Notes

- Interim `ContentView.swift` is a **disposable gate harness**, not product UI. Steps 5,
  9, 11 and 14 replace it entirely.
- `HelperRegistration.unregister()` is a development affordance only; Step 4 productises
  teardown with the mid-run guard, connection draining and device release (NFR-INST-3).
- **Next: Step 4** (helper lifecycle teardown), which begins from a registered, enabled
  daemon and an install/uninstall/reinstall cycle that must work repeatedly.

### Original scoping analysis (retained for reference)

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

### Open decisions — ~~ANSWER THESE FIRST~~ ALL RESOLVED 2026-07-25
All four were answered as recommended; see "Decisions taken" at the top of this
section for the reasoning, including the two points that were stronger than the
original framing (sandbox, and why a manual `SecCodeCheckValidity` would be *weaker*).
1. ~~App Sandbox → Off?~~ → **Off.**
2. ~~Code-sig mechanism?~~ → **`setCodeSigningRequirement` only.**
3. ~~Protocol scope?~~ → **Minimal.**
4. ~~Negative-test harness?~~ → **Standalone `swiftc` adhoc client.**

### Verification Gate (unchanged, from BUILD-PLAN.md)
- [ ] `register()` installs the daemon; after approval `.status == .enabled`; GUI shows it.
- [ ] Real XPC round-trip succeeds **through the registered daemon** (carries Step 1's
      deferred live ping).
- [ ] **Negative test:** adhoc/foreign-signed client is **rejected** and the rejection is
      logged. *(the security gate — do not pass the step without demonstrating this)*
- [ ] Out-of-range / misaligned parameter request rejected with a clear error (NFR-REL-7).

---

## Step 4 — Helper lifecycle teardown (unregister / remove) — COMPLETE

**AI-14 / satisfies NFR-INST-3, NFR-SEC-5; touches NFR-REL-5.**

The other half of the lifecycle started in Step 3. All source authored and
CLI-verified 2026-07-27; the interactive gate is outstanding.

### Decisions taken (2026-07-27)

1. **Two-layer run guard, helper authoritative.** The gate sanctions a *simulated*
   run, but where the guard lives still matters. What needs preventing is not
   "uninstall while a UI flag is set" — it is **removing the daemon while it holds a
   device** (NFR-REL-5), which only the helper knows, and which an app-side flag loses
   the moment the app is force-quit and relaunched. So: an app-side simulated toggle
   (Step 11 replaces it with the real state machine) **plus** an authoritative
   helper-side query.
2. **One new XPC method, `prepareForShutdown` → protocol v2.** BUILD-PLAN Step 4.3
   explicitly requires draining the connection and ensuring the helper released the
   device node before unregistering, so a helper interaction is specified. Semantics:
   *"if you are busy, refuse and say why; if you are idle, release everything and
   confirm."* The helper **refuses rather than releases** while busy — safe in both
   directions, since that also means no caller (even a correctly Team-ID-signed one)
   can use this method to abort a run in progress. Step 6/7 give it a body; Step 11
   wires it to the state machine.
3. **Fail-open for uninstall.** Block on a *known* active run; **proceed with a logged
   warning** when the helper is unreachable, wedged, or too old to implement the
   method. A privileged root daemon that cannot be removed because it is broken is a
   worse outcome than the risk being guarded against. Encoded in the type system, not
   left to call sites: `HelperConnection.prepareForShutdown` returns a
   `HelperShutdownReadiness`, never a `Result`, so "could not ask" *cannot* be
   mistaken for "unsafe".
4. **Simulated-run toggle lives in the interim `ContentView`**, which is already
   marked disposable and is replaced wholesale in Step 11.

### Authored

- `Shared/TesterControl.swift` — adds `prepareForShutdown`; `TesterProtocol.version`
  1 → 2 with the history documented.
- `…Helper/main.swift` — `HelperActivity` (serialised resource tracker, structurally
  complete but deliberately always idle until Steps 6/7 acquire a device) and the
  `prepareForShutdown` implementation with `lifecycle` logging.
- `USBDriveTester/UninstallPrecondition.swift` *(new)* — the pure safety policy:
  `HelperShutdownReadiness` × `runIsActive` → `UninstallDecision`.
- `USBDriveTester/HelperRegistration.swift` — `unregister()` (one-shot, dev-only)
  replaced by `uninstall(using:runIsActive:)`: app-side guard → helper query →
  connection drain → unregister → **poll `.status` until settled** (10 s). Polling is
  required because `unregister()` lags (BUILD-PLAN Step 4, risks) *and* because
  `SMAppService` can report an error for an operation that nonetheless takes effect —
  as `register()` demonstrated in Step 3 — so the settled status is more trustworthy
  than the thrown error.
- `USBDriveTester/HelperConnection.swift` — `prepareForShutdown` with a 5 s timeout,
  guarding the case where the connection is accepted but no reply ever arrives (a
  wedged helper would otherwise hang the uninstall forever — exactly what failing open
  exists to survive).
- `USBDriveTester/ContentView.swift` — "Unregister (dev)" promoted to a guarded
  **Uninstall helper**, plus the simulated-run toggle. Sections renamed by function
  rather than gate-item number, which had begun to mislead once they served two steps.
  The uninstall button is deliberately **not** disabled on a version mismatch.
- `USBDriveTesterTests/UninstallPreconditionTests.swift` *(new)* — 14 tests covering
  the full cross-product, including an explicit exhaustive-matrix test. The
  fail-open asymmetry is pinned down on purpose: an untested asymmetry is one a later
  well-meaning edit "tidies" into symmetry, silently making a wedged daemon
  unremovable.
- `scripts/lifecycle-check.sh` *(new)* — mechanises the gate's "verified via
  `launchctl`": asserts registration state, process state, and the absence of
  pre-SMAppService manual-install artefacts. `present`/`absent` assertions confirmed
  to discriminate in both directions. No sudo needed.

### CLI verification (2026-07-27)

- `./scripts/build.sh` → `** BUILD SUCCEEDED **`, zero warnings.
- `./scripts/test.sh` → `** TEST SUCCEEDED **`, **50 tests** (36 + 14 new).
- `./scripts/lifecycle-check.sh present` → PASS; `absent` correctly FAILS while the
  helper is installed (verifier proven to discriminate, not merely to pass).
- No Xcode GUI changes were needed this step: new app-side files auto-join the app
  target via the synchronized folder, and nothing new landed in `Core/`.

### A useful accident of sequencing

The protocol bump to v2 left a **live v1 daemon registered** while the v2 app is
installed (helper pid 6806 predates the new bundle). That is not a problem to work
around — it is a free, real-world test of two things at once: NFR-MAINT-1's version
handshake reporting a genuine mismatch, and the fail-open policy against an actually
out-of-date daemon that cannot answer `prepareForShutdown`. Exercised first in the
interactive gate below.

### Interactive gate — first pass (2026-07-27)

Reported as behaving exactly as predicted:
- Uninstall of the **live v1 daemon** succeeded *with* the "could not confirm" warning
  — the fail-open policy exercised against a genuinely out-of-date helper.
- Reinstall, then uninstall refused while the simulated run was active, then uninstall
  succeeded **without** a warning once the v2 helper confirmed it was idle. That
  warning/no-warning difference is the whole point of the design and it held.

Two items came out of the pass and are carried into a second, short pass:

**1. "Check protocol version" reported as not visible — layout defect, now fixed.**
Could not be reproduced by reasoning about the code, so `tools/ui-probe` was written to
render `ContentView` offscreen and capture it (see below). The render showed the button
*was* present but, once disabled, both round-trip buttons rendered as faint,
low-contrast pills sitting side by side in a single Form row — visually
indistinguishable from absent controls, and easy to scan past. Fixed by giving each
action its own labelled row, matching the parameter section's layout (which had caused
no trouble), replacing the dim-only disabled state with an explicit `info.circle`
explanation (NFR-USE-8: never convey by appearance alone), and raising the default
window height so neither the round-trip nor teardown section starts below the fold.
The protocol-version handshake itself is therefore **still unverified at v2** and is
re-checked in the second pass.

**2. A launchd record survived after uninstall — RESOLVED, benign.**
`launchctl print system/…Helper` still found the service (`state = not running`,
`active count = 0`, `runs = 0`, same **`BTM uuid`** `FF3ADEC2-…` as Step 3). Two
readings were consistent with that and were not distinguishable after the fact: either
the last action had been a re-register (`runs = 0` fits a fresh, never-contacted
registration), or `unregister()` leaves the launchd/BTM record behind — which would
have conflicted with BUILD-PLAN's wording that `launchctl print` "should not find it".

Settled empirically by running `lifecycle-check.sh absent` immediately after a **known**
uninstall on the second pass: **PASS — not present in the system domain, process not
running, no leftovers.** So `SMAppService.unregister()` does remove the launchd record
fully, and the earlier state was simply a re-registration. No defect.

Worth keeping: the `BTM uuid` is **stable across register/unregister cycles**, so
Background Task Management keeps one record per daemon and reuses it. That is
presumably how prior approval is remembered — and it explains why re-registering after
an uninstall does not always re-prompt for approval. Relevant to Step 16, whose gate
requires testing on a machine that has *never* run a dev build, precisely to avoid
false "it works" results from cached approvals.

### Tooling added

- `tools/ui-probe/main.swift` + `scripts/render-ui.sh` — compiles the app target's
  **real** view sources into an offscreen `NSHostingView` and captures a PNG, so GUI
  layout can be inspected headlessly. Written in response to item 1 above: a macOS
  window cannot be screenshotted without an interactive session, which made layout a
  blind spot that could only be probed by asking the user to look. Worth having for
  Steps 5, 9, 10, 11, 13 and 14, all of which are GUI-heavy. `ImageRenderer` is not
  used — macOS's grouped `Form` is AppKit-backed and renders blank through it, so a
  real hosting window is required. It is a *layout* probe only: the rendered view
  cannot reach a daemon and reads `.notFound`.

### Verification Gate — COMPLETE (2026-07-28)

- [x] **"Uninstall helper" transitions `.status` to `.notRegistered`** and the GUI shows
      it.
- [x] **After uninstall the daemon is gone**, mechanically verified:
      `./scripts/lifecycle-check.sh absent` → **PASS** (not present in the launchd
      system domain, process not running, no manual-install leftovers) — run
      immediately after a known uninstall so the result is unambiguous. The verifier
      was itself proven to discriminate: `absent` fails while the helper is installed.
- [x] **A subsequent `register()` cleanly reinstalls; the cycle repeats.** Several
      register → uninstall cycles across the two interactive passes, including one
      that began by removing a live *v1* daemon and ended with a working *v2* one.
- [x] **Uninstall is blocked with a clear message while a (simulated) run is active**,
      and permitted again once the toggle is cleared.
- [x] **Fail-open verified against a real out-of-date daemon** (beyond the gate's
      requirement): removing the v1 helper, which cannot answer `prepareForShutdown`,
      succeeded *with* the "could not confirm" warning; the later v2 uninstall
      succeeded *without* one. The warning/no-warning difference is the design's whole
      point and it held in practice.
- [x] **Protocol v2 handshake confirmed in the GUI** — `Protocol v2 — app and helper
      agree.` — after the layout fix, plus a live `ping` → `pong`.
- [x] **Global DoD:** builds arm64 / macOS 26.0 with **no new warnings**;
      `./scripts/test.sh` → `** TEST SUCCEEDED **`, **50 tests**, 0 failures.

### Notes

- No Xcode GUI work was required for this step.
- `HelperActivity` in the helper is structurally complete but **always idle** — nothing
  acquires a device until Step 6/7, which give `releaseAll()` a body, and Step 11,
  which wires the busy check to the run-control state machine. The simulated-run toggle
  in `ContentView` disappears with that same file in Step 11.
- **Next: Step 5** (device discovery & selection) — the first step whose gate needs real
  USB hardware, and the first substantial GUI build, where `scripts/render-ui.sh` should
  earn its keep.

---

## Step 5 — Device discovery & selection — COMPLETE

**AI-3 / satisfies FR-DEV-1…7; NFR-USE-3, NFR-COMPAT-4/6.**

Scoped, decided and authored 2026-07-29; all CLI-verifiable gate items closed the same
day against **real hardware**, headlessly. The interactive pass on 2026-07-30 found one
genuine defect (stale mounted-volume state), which was fixed, given a discriminating
regression test, and re-confirmed on hardware. Gate closed 2026-07-30.

### Hardware on the development machine (2026-07-29)

Three USB whole disks are attached, which is the two-or-more the gate requires:

| BSD | Model | Capacity | Block size | Role |
|---|---|---|---|---|
| `disk4` | Samsung Portable SSD T5 | 1.00 TB | 512 | **the scratch/test drive** (user's choice) |
| `disk6` | Samsung SSD 990 EVO Plus | 1.00 TB | 512 | holds this source tree — must never be tested |
| `disk8` | Seagate Expansion HDD | 22.00 TB | 512 | rotational; 42,970,644,479 blocks exercises 64-bit (NFR-COMPAT-6) |

`disk0` (internal, Apple Fabric, 4096-byte blocks) is the exclusion case. Usefully,
`disk4` sorts first, so FR-DEV-3's default selection lands on the scratch drive rather
than on the working volume.

### Decisions taken (2026-07-29) — all nine as recommended

1. **USB detection → IOKit `Protocol Characteristics` → `Physical Interconnect == "USB"`**,
   found by searching *up* the parent chain with
   `IORegistryEntrySearchCFProperty(… kIORegistryIterateParents)`. Same framework as the
   enumeration and the notifications; DiskArbitration arrives in Step 6 for unmount/claim.
2. **Synthesized APFS containers excluded** by requiring the media's provider to conform
   to `IOBlockStorageDriver` — see "The finding" below.
3. **Capacity → base-10** ("1.00 TB"), matching the drive label, `diskutil` and Disk
   Utility, plus the **exact byte count** for the selected device so the rounding hides
   nothing. Base-2 would render a drive labelled 1 TB as "931.51 GiB" — correct and
   useless when the task is confirming you picked the right physical device.
4. **Live refresh → `IOServiceAddMatchingNotification`** (`kIOMatchedNotification` +
   `kIOTerminatedNotification`), re-enumerating **wholesale** rather than patching. No
   poll interval to tune against the gate's "within a second or two", and sort/selection
   stay single-path.
5. **No helper involvement.** IOKit's geometry is recorded and labelled as provisional;
   Step 7's ioctls remain the final authority. Adding a geometry XPC method now would
   widen the protocol before it is needed (NFR-SEC-3) and leave Step 7 reconciling two
   sources. Consequence worth having: **this entire gate passes with the helper
   uninstalled**, which is the state Step 4 left the machine in.
6. **Freeze source → the existing simulated-run toggle** from Step 4, now with two
   consumers (uninstall guard + discovery freeze). One simulation, not two.
7. **Odd geometry → listed but not selectable**, with the reason shown. FR-DEV-1 says
   enumerate all; silently hiding a drive the user can see in Disk Utility looks like a
   bug in discovery, whereas an explanation does not.
8. **Mounted volume names shown per row.** Not a gate item and **not** the mount guard
   (Step 6 owns that, helper-side). It earns its place because `disk6` — the drive
   holding this source tree — is in the list, and a list that shows it without saying so
   invites exactly one mistake.
9. **`ContentView` becomes a composition root**; the Step 3/4 harness is **moved, not
   deleted**, into `HelperDiagnosticsView` behind a collapsed disclosure. Step 6 needs a
   registered helper again and Step 11 needs the mid-run guard; deleting those controls
   now would mean rebuilding them to pass the next gate.

### The finding: `Whole = true` is not enough (and BUILD-PLAN Step 5 says it is)

BUILD-PLAN Step 5.1 says to match `kIOMediaClass` with `kIOMediaWholeKey = true` and
walk the parent chain to confirm a USB transport. Measured on this machine, that filter
is **not sufficient**: synthesized APFS containers also report `Whole = true`, and they
inherit the USB interconnect from the physical disk beneath them.

```
disk6  IOMedia         parent=IOBlockStorageDriver      link=USB  bs=512   1000204886016
disk7  AppleAPFSMedia  parent=AppleAPFSContainerScheme  link=USB  bs=4096   999995129856
disk8  IOMedia         parent=IOBlockStorageDriver      link=USB  bs=512  22000969973248
disk9  AppleAPFSMedia  parent=AppleAPFSContainerScheme  link=USB  bs=4096  2000624971776
```

So the plan's filter lists **every APFS-formatted USB drive twice** — once real, once
virtual — with different block sizes *and* different capacities, and the virtual entry
is the more plausible-looking of the two. Handing that to a raw block writer is not a
cosmetic defect. Fixed by requiring the media's **immediate provider** to conform to
`IOBlockStorageDriver`: a whitelist, so other virtual schemes are excluded too, and
specifically the *immediate* parent, because a synthesized container has an
`IOBlockStorageDriver` further up as well.

Corollary for Step 7: **disk images are excluded**, by the USB filter rather than this
one (they report `Physical Interconnect == "Virtual Interface"`). Step 7's gate suggests
attaching a disk image as a safe stand-in for a real device — such an image will not
appear in this list. Correct per FR-DEV-1, but plan for it.

> **Resolved 2026-08-01.** It was planned for. BUILD-PLAN has been amended to drop disk
> images as a test target entirely and fix all real-hardware I/O on `disk4`. This
> observation, made during Step 5, is what made the conflict visible two steps before it
> would have bitten.

### Two smaller findings

- **The IOMedia property constants are not bridged into Swift.** `kIOMediaClass`,
  `kIOMediaWholeKey`, `kIOMediaSizeKey`, `kIOMediaPreferredBlockSizeKey`, `kIOBSDNameKey`
  and the `kIOPropertyProtocolCharacteristicsKey` family are C `#define`s and do not
  compile. String literals are required; they are collected in one `RegistryKey` enum
  citing the headers. (`kIOServicePlane` and `kIOMainPortDefault` *are* bridged.)
- **The mount table does not name the physical disk.** `1TB_Samsung` is mounted from
  `/dev/disk7s1`, and only the IOKit registry connects `disk7` back to the physical
  `disk6`. Parsing `disk7s1` down to `disk7` — the obvious implementation — would make
  every APFS-formatted drive show no volumes at all. Resolved by walking the registry
  subtree *downward* from the whole disk and matching that set against the mount table.

### Authored

App target, `USBDriveTester/Discovery/` (all pure unless noted):
- `BSDDeviceName.swift` — numeric-aware **total** order (FR-DEV-2). Total, not merely
  numeric: `sorted()` is only deterministic when no two elements compare equal, and the
  list is rebuilt from scratch on every hot-plug.
- `CapacityFormatting.swift` — base-10 formatting and digit grouping. Not
  `ByteCountFormatter`: it is locale-dependent in separators *and* unit names, which
  would make capacities move with the user's region and make the tests assert whatever
  region the test machine is set to.
- `DiscoveredDevice.swift` — the value type, geometry sanity (`DeviceGeometryProblem`),
  presentation strings, ordering, and `DeviceSetChange` for connect/disconnect logging.
- `DeviceSelectionPolicy.swift` — selection across refreshes (FR-DEV-3/4/7).
- `MountedVolumes.swift` — `getfsstat` snapshot (not `getmntinfo`, whose static buffer is
  a poor fit for a hot-plug callback) plus pure parsing/attribution.
- `IOKitDeviceEnumerator.swift` *(impure)* — the two filters, geometry, registry-subtree
  walk, and the notification port. The only file in Step 5 that needs hardware.
- `DeviceDiscovery.swift` — `@MainActor @Observable` store: list, selection, freeze.

App target, top level:
- `DeviceListView.swift` *(new)* — `List` with a selection binding, plus the
  selected-device detail panel.
- `HelperDiagnosticsView.swift` *(new)* — the Step 3/4 harness, moved verbatim apart
  from the toggle's new second consumer.
- `ContentView.swift` *(rewritten)* — composition root; owns `simulatedRunActive`
  because both children need it.

Tests (`USBDriveTesterTests/`, via `@testable import USBDriveTester`) — **121 new**:
- `DeviceFixtures.swift` — fixtures taken from the real machine, not invented. The
  awkward cases (an **empty** vendor string on the internal SSD; a capacity that rounds
  up across a unit boundary) were found by probing hardware rather than imagined.
- `BSDDeviceNameTests` (18), `CapacityFormattingTests` (15), `DiscoveredDeviceTests` (26),
  `DeviceSelectionPolicyTests` (15), `MountedVolumesTests` (21), `DeviceSetChangeTests` (7),
  `DeviceDiscoveryTests` (19, driven through a `StubDeviceSource`).

Tooling:
- `tools/device-probe/` + `scripts/device-probe.sh` *(new)* — compiles the app's **real**
  Discovery sources and prints what they return. This is what moved four of the five gate
  items off "needs a person at the machine". `--watch` reprints on hot-plug; `--all`
  cross-checks against every whole media object in the registry.
- `tools/device-probe/AllWholeMediaProbe.swift` — deliberately **shares no code** with
  the enumerator. A filter bug that excluded everything would look identical to a correct
  exclusion if both views came from the same query, so the cross-check asks IOKit the
  broadest question independently.
- `tools/ui-probe` + `scripts/render-ui.sh` — gained a 4th argument selecting the view
  (`content` / `devices` / `diagnostics`). Once a view sits behind a disclosure, the
  composition root cannot show it, and "it compiled" is no evidence that a `Form` inside
  a `DisclosureGroup` inside a `VStack` lays out sanely. It did.

### On isolation, and a correction

The app target compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which makes
*every* unannotated declaration — including plain value types — main-actor-isolated. An
early spot-check suggested no annotation was needed; that check was too weak (it did not
exercise a protocol conformance across the module boundary) and an **incremental** test
run then hid the resulting warnings, because warnings are not re-emitted for files that
were not recompiled.

A clean rebuild showed the truth: `Equatable` conformances and initialisers were
unusable from the non-isolated test target. Fixed by marking the pure discovery types,
`DeviceSource`, `IOKitDeviceEnumerator` and its file-scope `Logger` **`nonisolated`**.
Two consequences worth keeping:

- `IOKitDeviceEnumerator` **cannot** be `MainActor`-isolated: IOKit reaches it through a
  C function pointer, and a global-actor-isolated function cannot be converted to
  `@convention(c)`. The test stub is non-isolated for the same reason — otherwise it
  would not be testing the same contract.
- The same latent warnings existed in Step 4's `UninstallPrecondition` and were fixed in
  passing. **Always verify "zero warnings" from a clean build**, not an incremental one.

### Verification done (CLI + real hardware, 2026-07-29)

- `./scripts/test.sh` → `** TEST SUCCEEDED **`, **171 test cases**, 0 failures,
  **zero warnings from a clean build**.
- `./scripts/build.sh` Debug **and** Release → `** BUILD SUCCEEDED **`, zero warnings
  (only the benign `appintentsmetadataprocessor` note).
- **Gate item 1 — all USB drives listed, internal/non-USB excluded.** `device-probe --all`
  lists `disk4`, `disk6`, `disk8` and reports every rejection with its cause: `disk0`
  "not USB (Apple Fabric)", and all five synthesized containers "not a physical disk
  (provider AppleAPFSContainerScheme)". Exclusion is a positive observation, not an
  absence of evidence — a filter that excluded everything would look identical in the
  device list alone.
- **Gate item 2 (partly) — order and default selection.** `disk4, disk6, disk8`, numeric
  and stable; `disk4` default-selected. Order proven independent of IOKit's iteration
  order (which is *not* sorted: it returns disk0, disk1, disk3, disk2, disk7, disk9,
  disk6, disk8 here).
- **Gate item 3 (content) — identity.** Every row carries BSD name, model and
  human-readable capacity; the detail panel repeats the identity and adds the exact byte
  count, geometry, raw device node, medium and mounted volumes. Confirmed by render.
- **Gate item 4 (mechanism) — live refresh.** Verified without hands by attaching and
  detaching a disk image, which publishes a whole-disk `IOMedia` and so fires the same
  notifications a USB drive does: rebuild **~50 ms** after attach, **~700 ms** after
  detach (200 ms of which is deliberate coalescing). The image was correctly **excluded**
  from the list while still triggering the refresh — both halves of the intended
  behaviour in one observation.
- **Gate item 5 — geometry.** `1,953,525,168 blocks × 512 bytes` for `disk4` and
  `42,970,644,479` for `disk8`, both matching `diskutil info`'s independently-reported
  512-byte-unit counts exactly. Displayed in the detail panel.
- **Layout** checked headlessly at 700×700 (`content`) and 700×900 (`diagnostics`).
  Fixed one real defect found this way: an uncapped `List` inside a `VStack` absorbed all
  spare height, leaving three drives above a large gap and pushing the selected-device
  detail — the thing that stops the wrong drive being tested — to the window edge. Now
  content-sized via `@ScaledMetric` so it tracks Dynamic Type rather than a hard-coded
  row height.
- **No Xcode GUI work was required.** Everything landed in the app folder or the test
  folder, both synchronized groups. Nothing new in `Core/`.

### Defect found by the interactive gate, and fixed (2026-07-30)

**Symptom (reported from item 1).** On replugging `disk4`, macOS auto-mounted its
volumes but the device list went on showing it as unmounted.

**Cause.** Mount state is not part of the IOKit *media* set, which is all the enumerator
was watching. Two failures in one:

1. On arrival the list rebuilds ~50 ms after the media appears, and
   `diskarbitrationd` mounts the volumes some time *after* that — the snapshot is taken
   before there is anything to see.
2. Nothing ever asks again, because a mount produces no whole-media notification.

Reproduced without touching the device set, which isolates cause from timing:

```
$ diskutil unmount /Volumes/Test_Drive
Volume Test_Drive on disk4s2 unmounted
   ... no refresh fired; the list still read "mounted  Test_Drive"
```

**Why the earlier verification missed it.** APFS hides the bug. Mounting an APFS volume
publishes a new `AppleAPFSMedia` object, which *is* a whole-media change and does fire
the IOKit notification — so `disk6` and `disk8` behaved correctly. The exFAT scratch
drive has no such side effect. Every check run on 2026-07-29 used either an APFS drive
or a disk image, and all of them passed. **A drive-image test is not a substitute for
the filesystem the user actually has.**

**Fix.** `Discovery/VolumeChangeWatcher.swift` *(new)* — a DiskArbitration session
watching `kDADiskDescriptionVolumePathKey` (plus disk appeared/disappeared), owned by
`IOKitDeviceEnumerator` and funnelled into the same 200 ms coalescing window. Both
sources now mean the same thing: the list needs rebuilding.

DiskArbitration rather than `NSWorkspace.didMountNotification`: NSWorkspace is fewer
lines but is AppKit-level and does not reliably deliver in a plain command-line process,
which would have left `device-probe` unable to reproduce or verify this exact defect. A
fix whose regression test cannot run headlessly is one that quietly rots. It also
matches Step 6, which uses DiskArbitration helper-side for the unmount and claim.

**Verified.** Mount → refresh in ~1.1 s; unmount → ~0.5 s; both directions show the
correct state. `scripts/mount-change-test.sh <disk>` *(new)* mechanises it, asserting
both that a refresh fires **and** that the live view's state changes — an event without a
state change would mean the mount table is misread, and a state change without an event
would mean something else happened to trigger the rebuild.

**The verifier was proven to discriminate**: with the watcher disabled, 3 of its 4 checks
fail. The 4th ("reports its mounted volume again") passes either way and inherently so —
a view that never updates is accidentally correct once the state returns to where it
started — so it is documented as catching the opposite regression rather than this one.
Writing the test also exposed two flaws in the test itself: a `grep -c` idiom emitting
`0\n0`, and state assertions that spawned a *fresh* probe process and so re-enumerated
correctly whether or not live updating worked. Both fixed; the assertions now read the
running watcher's latest output.

### Interactive gate — COMPLETE (2026-07-30)

Run on the installed `/Applications` build, all four confirmed by the user:

- [x] **Physically unplug and replug `disk4`** with no run active — confirmed
      2026-07-30. It leaves the list and rejoins within a second or two, and its
      auto-mounted volume now appears. This is the case that failed on the first
      attempt; the physical replug is the only thing that reproduces the
      arrival-then-mount ordering end to end, so it also closes out the
      `VolumeChangeWatcher` fix on real hardware rather than only under
      `mount-change-test.sh`.
- [x] **Click a different row** — selection moves and the detail panel follows
      (FR-DEV-4). The store's policy was unit-tested; this closes the `List` selection
      binding, which was the untested half.
- [x] **Toggle "Simulate an active run"**, then unplug a drive — the list does not
      change and says why; clearing the toggle catches it up (FR-DEV-7).
- [x] **The selected device reads unambiguously** (NFR-USE-3), including `disk6`
      showing that it holds the source tree.

### Verification Gate — COMPLETE (2026-07-30)

- [x] **Connecting two or more USB drives lists all of them; non-USB/internal disks are
      excluded.** Three USB whole disks listed (`disk4`, `disk6`, `disk8`); `disk0`
      excluded as "not USB (Apple Fabric)" and all five synthesized APFS containers as
      "not a physical disk". Exclusion verified as a *positive* observation by
      `device-probe --all`, whose cross-check shares no code with the enumerator — a
      filter that wrongly excluded everything would look identical in the device list
      alone.
- [x] **List order is stable and numeric-correct across refreshes; the first device is
      default-selected; selection can be changed.** Order proven independent of IOKit's
      iteration order, which is genuinely unsorted here. Default selection lands on
      `disk4`, the scratch drive. Re-selection confirmed in the GUI.
- [x] **Each row shows BSD name, model and human-readable capacity; the selected device
      is unambiguously identified.** Detail panel adds the exact byte count, geometry,
      raw device node, medium and mounted volumes.
- [x] **Plugging/unplugging a drive with no run active updates the list within a second
      or two.** Confirmed by physical replug, and mechanically by
      `mount-change-test.sh` and a disk-image attach/detach (~50 ms attach, ~700 ms
      detach). **Mounted-volume state updates too** — see the defect section above.
- [x] **The selected device's logical block size and block count are captured and
      displayed.** `1,953,525,168 × 512` (`disk4`) and `42,970,644,479 × 512`
      (`disk8`), both matching `diskutil info`'s independently-reported 512-byte-unit
      counts exactly.
- [x] **Global DoD:** builds arm64 / macOS 26.0 Debug **and** Release with no new
      warnings (verified from a *clean* build); `./scripts/test.sh` →
      `** TEST SUCCEEDED **`, **171 test cases**, 0 failures.

### Notes

- `HelperActivity` in the helper is still always idle; nothing acquires a device until
  Steps 6/7. Step 5 does not touch the helper at all.
- The mounted-volume warning on the selected device is **advisory**. Step 6 builds the
  real guard (FR-SAFE-1/2, NFR-REL-3) helper-side, and it is the only thing that may
  permit a run.
- `disk4` currently has a mounted `Test_Drive` volume (exFAT). Step 6's gate needs
  exactly this: a mounted volume present, so starting is refused by name.
- **Lesson carried forward:** the one defect this step produced was invisible to every
  substitute for the real thing — a disk image exercised the notification path without
  a filesystem, and APFS drives masked it by publishing media on mount. Steps 6, 7 and 8
  all have gates that are tempting to close against a disk image or a simulated device;
  do that first, but do not treat it as the hardware check it stands in for.

**Next: Step 6** (mount-guard: unmount verification + exclusive whole-disk claim) — the
first step where the helper does something privileged, and where DiskArbitration moves
from the app's read-only observation here to the helper's authoritative claim.

---

## Step 6 — Mount-guard: unmount verification + exclusive claim — AUTHORED, GATE OUTSTANDING

**AI-4 / satisfies FR-SAFE-1…7; NFR-REL-3, NFR-USE-5.**

Scoped 2026-07-30: requirements amended, decisions taken, exclusivity semantics measured
on real hardware, and the file plan approved by the user. **All source authored 2026-07-31**
(see "Authored" below). Unit tests and the headless checks are green; the hardware and
interactive gate items have **not** been run yet, and one pre-existing build defect must
be fixed before the Global DoD can pass — both tracked at the end of this section.

### Requirements amended this step (2026-07-30)

The mount/unmount control was specified by the user during scoping and changed the
baselined functional spec. Recorded in
[functional-requirements](functional-requirements-usb-drive-tester.md#amendments-to-the-baseline):

- **FR-SAFE-5 revised, C → M.** One control acting on *all* volumes of the selected
  device, label and action always in agreement: `Unmount All` when any volume is
  mounted, `Mount All` when none is, disabled with no selection. **Mounting was not
  previously a requirement at all** — the baseline covered unmounting only.
- **FR-SAFE-6 added.** Nothing mounts or unmounts implicitly; starting a test never
  changes mount state. This closes a real conflict between FR-SAFE-4(a) (refuse and
  instruct) and BUILD-PLAN Step 6.2 as written (unmount as part of acquiring). BUILD-PLAN
  Step 6.2 was amended to match.
- **FR-SAFE-7 added, derived not requested.** The control is also disabled during a run
  or while the helper holds the claim, because mounting the device under test would
  violate NFR-REL-3. Marked as derived so it is easy to identify and reverse.

A useful consequence: the control's state comes from `DiscoveredDevice.mountedVolumeNames`,
which live-updates through the `VolumeChangeWatcher` added to fix the Step 5 defect. The
label re-evaluates itself when the action completes, with no extra plumbing — yesterday's
bug fix is now load-bearing for this feature.

### Decisions taken (2026-07-30)

1. **Never unmount implicitly** — now FR-SAFE-6 rather than a design preference.
2. **The mount/unmount control is app-side**, using unprivileged DiskArbitration, keeping
   the privileged XPC surface to check/acquire/release (NFR-SEC-3). Evidence:
   `diskutil unmountDisk` succeeds without `sudo` on an external drive, so an
   unprivileged process can do it.
3. **Protocol → v3, three methods:** `checkDeviceReadiness` (read-only, safe to poll for
   display), `acquireDevice`, `releaseDevice`. The check must be side-effect-free because
   the GUI has to show "2 volumes mounted" *before* Start, and a check with side effects
   cannot drive a display.
4. **The write-path guard is a type, not a flag (NFR-REL-3).** The helper holds an
   `AcquiredDevice` value constructible only by a successful acquire; Steps 7/8's write
   path takes it as a parameter. No value, no write path — the guard cannot be forgotten
   at a call site. Classification logic goes in `Core/` as a pure
   `DeviceAccessPrecondition`, unit-tested exhaustively like `UninstallPrecondition`.
5. **`HelperActivity` finally gets a body.** Acquiring marks the helper busy, so
   `prepareForShutdown` genuinely refuses and `releaseAll()` releases the claim — closing
   the loop deliberately left open in Step 4.
6. **A partially-mounted device reads `Unmount All`.** Any mounted volume selects the
   unmount direction; confirmed with the user.
7. **A device with nothing mountable keeps the control enabled** and reports honestly
   afterwards, rather than being disabled via DiskArbitration's `VolumeMountable` flag.
   Faithful to the stated rule (only "no selection" disables), and avoids relying on a
   flag that can be conservative for third-party filesystems.

### Exclusivity semantics — MEASURED (2026-07-30)

Took three runs; the first two produced answers that did not follow from their evidence,
which is recorded below because the failures were more instructive than the successes.

**Findings, all from `scripts/exclusivity-probe.sh disk4` on the real device:**

| Question | Answer |
|---|---|
| `open(rdiskN, O_RDWR)` while a volume is mounted | fails `EBUSY` — **the mount guard is kernel-enforced** |
| `open(rdiskN, O_RDWR)` unmounted | succeeds |
| Two independent `O_RDWR` opens, unmounted | **both succeed — a plain open is not exclusive** |
| `O_EXLOCK` | first succeeds, second fails `EBUSY` — **this is the exclusivity mechanism** |
| Another **process** holding claim + `O_EXLOCK` | second process gets `EBUSY`, nothing mounted — **FR-SAFE-4(b) is detectable** |
| Contended `DADiskClaim` | **PENDING forever** — never granted, never dissented |
| Volume left unmounted with no claim | **macOS silently remounted it** |

**Consequences, all now reflected in BUILD-PLAN:**

1. **Step 7 amended: the raw open must be `O_RDWR | O_EXLOCK | O_NONBLOCK`.** It
   specified a plain `O_RDWR`, which would have let two processes write the same device
   simultaneously — the failure would have been silent and intermittent.
2. **The claim needs a timeout**, and a timeout *means* FR-SAFE-4(b). A blocking claim
   would wedge the helper, and no dissenter ever arrives to tell it otherwise.
3. **Both FR-SAFE-4 causes present as the same `EBUSY`.** Only the mount check separates
   them — which the app can do unprivileged, and which is why `checkDeviceReadiness`
   must return mount state rather than an error code.
4. **The claim is mandatory, not defensive.** Auto-remount was observed, not theorised.
5. **Release is asynchronous** — an open straight after `DADiskUnclaim` can still see
   `EBUSY`, so the release path must not assume instant reusability (NFR-REL-5).

**Probe defects found and fixed along the way** — worth keeping, because each one
produced a *plausible but wrong* answer rather than an obvious failure:

- Printed "open IS exclusive" when a second open failed, in a phase where both opens
  failed because a volume was mounted. A verdict is now printed only when the first open
  succeeded.
- Passed the DiskArbitration claim context `passUnretained`, so a callback arriving after
  the timeout dereferenced a deallocated object — a segfault mid-measurement. Retained
  now, released in the callback.
- Had the holder process open with a plain `O_RDWR`, so it held nothing and the
  contention phase measured an uncontended disk.
- Ran its FR-SAFE-4 classification at the *end* of the battery, where it reported "held
  by another process" in a phase in which nothing else held the disk. It was measuring
  the probe's own leftover pending claim. **Now measured first, before the probe touches
  anything.**
- `$DISK` followed by a UTF-8 ellipsis made bash absorb those bytes into the variable
  name under `set -u`, aborting before the most important phase. Locale-dependent, so it
  ran here and failed on the user's terminal. The same latent bug was fixed in
  `install-app.sh` and `mount-change-test.sh`.

**Still unresolved, and not blocking.** Whether phase 3's exclusion came from the
holder's `DADiskClaim` or its `O_EXLOCK` cannot be told apart from this data. It does not
change the design, because the helper holds both regardless — the claim for anti-remount
(mandatory per finding 4) and `O_EXLOCK` for write exclusion.


### Approved file plan (2026-07-30) — NOT YET AUTHORED

Confirmed by the user. Author in this order: pure logic + its tests first, then the
privileged side, then the UI — the Step 5 order, which kept the hardware-dependent
surface small.

**Core** — `com.arc3solutions.USBDriveTester.Helper/Core/`
- `DeviceAccessPrecondition.swift` — pure classification of (mount state, claim outcome,
  open `errno`) → decision + message, distinguishing FR-SAFE-4(a) from (b). Mirrors
  `UninstallPrecondition`. **This is what gate item 4 verifies.**
  ⚠️ **Needs an Xcode target-membership tick** for `USBDriveTesterTests`, exactly as the
  Step 2/3 Core files did. It is the only GUI action Step 6 requires.

**Helper** — `com.arc3solutions.USBDriveTester.Helper/`
- `DeviceClaim.swift` *(new)* — DA session, mount check, claim-with-timeout, exclusive
  open, and the `AcquiredDevice` value.
- `main.swift` *(edit)* — the v3 methods; `HelperActivity` finally gets a body.

**Shared** — `USBDriveTester/Shared/`
- `TesterControl.swift` *(edit)* — protocol **v2 → v3**: `checkDeviceReadiness`
  (read-only, safe to poll), `acquireDevice`, `releaseDevice`.

**App** — `USBDriveTester/`
- `Discovery/VolumeMounter.swift` *(new)* — unprivileged mount/unmount-all via
  DiskArbitration.
- `MountControlState.swift` *(new)* — **pure** mapping of (selection, mounted count, run
  active) → button label + enabled state. FR-SAFE-5/7 encoded as testable logic rather
  than inline view conditionals.
- `HelperConnection.swift` *(edit)* — typed v3 calls.
- `DeviceListView.swift` *(edit)* — the Mount All / Unmount All button and the readiness
  banner.

**Tests** — `USBDriveTesterTests/`
- `DeviceAccessPreconditionTests.swift`, `MountControlStateTests.swift`.

**Tooling** — `scripts/claim-contention-test.sh`, reusing `exclusivity-probe --hold` to
assert the helper reports cause (b) rather than cause (a).

### The acquire sequence, as designed

1. Check mounted volumes → any ⇒ refuse, **cause (a)**, naming them (FR-SAFE-4(a)).
2. `DADiskClaim` **with a 5 s timeout** → pending ⇒ refuse, **cause (b)**.
3. `open(rdiskN, O_RDWR | O_EXLOCK | O_NONBLOCK)` → `EBUSY` ⇒ refuse, **cause (b)**;
   another `errno` ⇒ a specific error naming it.
4. Success ⇒ construct `AcquiredDevice` — the only value that unlocks the Steps 7/8 write
   path (NFR-REL-3).

**Release:** close fd → `DADiskUnclaim` → mark `HelperActivity` idle, without assuming the
device is instantly reusable (release is asynchronous — see the measurements above).

### Verification split for the gate

| Unit-testable | CLI + root | Needs a person |
|---|---|---|
| Classification of both causes; the guard tripping when access is absent; the button label/state matrix | `claim-contention-test.sh`; `exclusivity-probe.sh` | Both refusal messages in the GUI; the button toggling; release restoring normal use |

### State this step begins from

- Helper **uninstalled** (Step 4 left it that way; Step 5 never needed it).
  `/Applications/USBDriveTester.app` holds the **Step 5** build.
- Protocol at **v2**; Step 6 takes it to v3.
- `git` clean on `main`; Step 5 committed at `cbd3a39`, scoping commits after it.
- Hardware attached: `disk4` (Samsung Portable SSD T5, 1 TB, 512 B, one exFAT volume
  `Test_Drive` — **the designated scratch device**), `disk6` (holds this source tree —
  never test it), `disk8` (Seagate 22 TB).
- 171 tests passing, zero warnings from a clean build, Debug and Release.

---

### Authored (2026-07-31)

Written in the Step 5 order — pure logic and its tests first, verified green, then the
privileged side, then the UI.

**Core** — `com.arc3solutions.USBDriveTester.Helper/Core/`
- `DeviceAccessPrecondition.swift` *(new)* — the whole decision, pure and Foundation-only:
  - `WholeDiskName` — boundary validation of the caller-supplied BSD name (NFR-REL-7).
    Accepts only a canonical `disk<N>`; the canonicity check is one comparison against the
    round-trip of the parsed number, which rejects `disk04`, `disk4s2`, `rdisk4`, paths and
    oversized unit numbers in a single rule rather than one per attack shape. This is the
    string that becomes `/dev/rdiskN` in a root process.
  - `MountState` / `DiskClaimOutcome` / `ExclusiveOpenOutcome` — the three measured facts,
    as types. `MountState(mountedVolumeNames:)` maps an empty list to `.unmounted`, so
    "mounted, with nothing mounted" is unrepresentable.
  - `DeviceAccessRefusal` (+ `causeCode`) and `DeviceAccessPrecondition.evaluate(…)` — the
    classification, and the FR-SAFE-4 messages.
  - `DeviceAccessGrant` / `WritePrecondition` — the runtime half of NFR-REL-3.
  - *This was the one file needing a target-membership tick; done and verified in
    `project.pbxproj` (it now sits alongside the four Step 2/3 Core files in the
    `USBDriveTesterTests` exception set, and in no app-target set).*

**Helper** — `com.arc3solutions.USBDriveTester.Helper/`
- `DeviceClaim.swift` *(new)* — `HelperDeviceRegistry` (the helper's own IOKit identity
  re-check), `HelperMountTable` (its own `getfsstat` read), the claim-with-timeout, the
  `O_EXLOCK` open, and `AcquiredDevice`.
- `main.swift` *(edit)* — the three v3 methods; `HelperActivity` given a body; release on
  connection loss.

**Shared** — `Shared/TesterControl.swift` *(edit)* — protocol **v2 → v3**
(`checkDeviceReadiness`, `acquireDevice`, `releaseDevice`), plus `DeviceAccessRefusalCause`.

**App** — `USBDriveTester/`
- `MountControlState.swift` *(new)* — the pure FR-SAFE-5/7 truth table.
- `Discovery/VolumeMounter.swift` *(new)* — unprivileged mount/unmount-all.
- `HelperConnection.swift` *(edit)* — typed v3 calls, `DeviceReadiness`, `DeviceAcquisition`.
- `DeviceListView.swift` *(edit)* — the mount control, readiness banner, acquire/release.
- `ContentView.swift` *(edit)* — owns the single `HelperConnection`; window min height
  620 → 720.
- `HelperDiagnosticsView.swift` *(edit)* — takes the shared connection.

**Tests** — `DeviceAccessPreconditionTests.swift` (49), `MountControlStateTests.swift` (15).

**Tooling** — `tools/mount-guard-client/main.swift` *(new)*,
`scripts/claim-contention-test.sh` *(new)*, `tools/ui-probe` updated for the new view
signatures.

### Design decisions taken while authoring

Beyond the nine taken during scoping:

10. **The helper re-checks device *identity*, not just mount state.** BUILD-PLAN Step 3.5
    asks for it and it turns out to matter a great deal here: without it, any client that
    satisfies the Team-ID requirement could hand the root daemon `disk0`. `HelperDeviceRegistry`
    re-applies both Step 5 filters (immediate provider is an `IOBlockStorageDriver`,
    ancestor `Physical Interconnect == "USB"`) from the helper's own view of the registry.
    The registry-key literals are deliberately duplicated rather than shared: a shared
    filter would let one bug excuse itself on both sides of the trust boundary.
11. **A sixth refusal cause, `alreadyHeld`.** "The helper already holds a device" is not
    cause (b): the holder is us, so the corrective step is inside the app. Folding it into
    `claimedByAnotherProcess` would send the user hunting for a process that does not exist.
12. **A claim must not outlive the connection that took it (NFR-REL-5).** Each acquisition
    records an owner `UUID`; the connection's `invalidationHandler` releases only what that
    connection acquired. Without this, a force-quit GUI would strand the claim — and because
    macOS only remounts once a claim is dropped, the symptom would be a drive that has
    silently stopped mounting with no process visibly responsible. A `UUID` rather than the
    peer's pid, because pids are reused.
13. **One `HelperConnection` for the app, owned by `ContentView`.** Not merely tidier than
    one per view: with decision 12, two connections would mean two owners, and tearing down
    a view could release a claim another part of the app believed it held.
14. **The mount/unmount control renders even with no selection.** FR-SAFE-5 specifies the
    no-selection state — *disabled*, labelled "Unmount All" — and a control that is absent
    is not a control that is disabled. This was caught by re-reading the requirement against
    the first draft, which only rendered the control inside the selected-device panel.
15. **`checkDeviceReadiness` cannot detect cause (b), and says so.** Establishing that
    another process holds the node requires actually claiming and opening the device, which
    are side effects — and the claim in particular would stop the disk remounting. So
    `ready == true` means "nothing known would refuse an acquire", never "an acquire will
    succeed". Documented on the protocol method, because a future caller treating it as a
    promise would move the safety decision app-side.

### Verified (headless, 2026-07-31)

- **`./scripts/test.sh` from a CLEAN build → `** TEST SUCCEEDED **`, 235 test cases
  (226 `@Test` declarations), 0 failures, zero warnings.** Up from 171/162 at Step 5.
  Counted from the result bundle rather than the log: parallel test output tore a line and
  made a naive `grep -c` read 231. Step 5's "171" is the same executed-case measure, so the
  comparison is like-for-like.
- **`./scripts/build.sh` (Debug) → `** BUILD SUCCEEDED **`, zero warnings from a clean
  build.** Three warnings appeared first time round in `VolumeMounter` (two non-Sendable
  captures and an unused result) and were fixed rather than suppressed.
- **Core logic proven before the target-membership tick** by a throwaway `swiftc` harness
  over the real Core source — 64/64 checks. Two properties worth keeping: of the 40 input
  combinations to `evaluate`, **exactly one** grants access; of the 8 grant/target
  combinations, **exactly one** permits a write.
- **Layout rendered headlessly** at 640×720 (`content`). The first render at the old
  620-point minimum put the refusal message — the thing FR-SAFE-4 exists to communicate —
  below the fold, which is the same class of defect Step 4 hit. Window minimum raised.
- **`scripts/claim-contention-test.sh`** passes `bash -n`, and its client compiles and
  signs. Every `$VAR` before a non-ASCII character is brace-delimited; confirmed
  empirically that braces are sufficient (the unbraced form is locale-dependent, which is
  why it ran here and failed on the user's terminal last time).

### A pre-existing defect found by the clean Release build — NEEDS A GUI FIX

**Symptom.** `./scripts/build.sh Release` fails after a DerivedData wipe:
`error: The file "com.arc3solutions.USBDriveTester.Helper" couldn't be opened because
there is no such file.`

**Cause.** The app target's **Embed Helper** copy-files phase references the wrong file
object. `project.pbxproj` contains *two* references to the helper executable:

- `FE6097482FEECD1D0091C1E0` — correct: `path = com.arc3solutions.USBDriveTester.Helper;
  sourceTree = BUILT_PRODUCTS_DIR;`
- `FE6097752FEF20FC0091C1E0` — wrong, and the one the phase actually uses:
  `sourceTree = "<group>"` with the path hard-coded to
  `…/DerivedData/USBDriveTester-fndvzobcvvrsxwfjhtiawbpirxmt/Build/Products/**Debug**/…`

It is the shape you get from dragging the built binary in from Finder rather than picking
the helper's product from the target's Products group — so it dates from Step 1.

**Why it went unnoticed until now, and why it matters more than the error message
suggests.** Debug builds copy `Products/Debug → Products/Debug/…app`, so Debug is
*accidentally* correct. Release builds copy `Products/Debug → Products/Release/…app`, which
succeeds whenever stale Debug products happen to exist — and silently embeds the **Debug**
helper in the Release app. Measured: the Release `.app` contains a **958,720**-byte helper,
byte-for-byte the size of the Debug build, against **584,128** for the Release build.
So every "Release builds clean" recorded in Steps 3–5 was true of the app and produced a
Release bundle wrapping an unoptimised helper.

Three consequences:
1. **Release ships a Debug helper.** Relevant now, and load-bearing for Step 16 — the
   embedded binary is the one that gets signed, sealed and notarized.
2. **The build is not reproducible (NFR-MAINT-3).** The path embeds this machine's
   DerivedData hash; the project would not build on another Mac, or after a DerivedData
   reset, which is exactly what exposed it.
3. **It masks itself.** The failure only appears from a genuinely clean state. Another
   entry in this project's running theme: every defect so far came from trusting a
   substitute — here, an incremental build standing in for a clean one.

**Not caused by Step 6**, but it blocks Step 6's Global DoD ("builds Debug **and**
Release").

**FIXED 2026-08-01.** The Embed Helper phase now references
`FE6097482FEECD1D0091C1E0` (`sourceTree = BUILT_PRODUCTS_DIR`) with Code Sign On Copy, and
the stray hard-coded reference is gone — `project.pbxproj` no longer contains the string
`DerivedData` anywhere. Verified from a wiped DerivedData:

| Check | Result |
|---|---|
| Clean Debug build | `** BUILD SUCCEEDED **`, 0 warnings |
| Clean **Release** build | `** BUILD SUCCEEDED **`, 0 warnings |
| What Release copies | `Products/**Release**/com.arc3solutions.USBDriveTester.Helper` |
| Embedded helper size | **584,128** = the Release build (was 958,720, the Debug one) |
| Embedded helper signature | `Identifier=…Helper`, `TeamIdentifier=5JC55GTLZA` |
| Embedded helper contents | contains `acquireDevice` — genuinely the v3 build |

This is the first Release build in the project's history that embeds the binary it was
supposed to. Steps 3–5's recorded "Release builds clean" were true of the app and wrapped
an unoptimised helper.

**An incident during the fix, worth recording.** The GUI instructions issued for it had a
sixth step — "delete any leftover stray reference in the Project navigator" — which did not
distinguish between two objects **with identical names**: the stray `PBXFileReference` (a
built binary) and `FE6097492FEECD1D0091C1E0`, the helper's *synchronized source folder
group*. The folder group was deleted instead. Symptom: `Undefined symbols: _main` — the
helper target had no sources at all, because the group is what feeds `main.swift`,
`DeviceClaim.swift` and `Core/*.swift` into it. It also silently removed the Core files'
`USBDriveTesterTests` membership, since the group carried that exception set.

No source was lost — only project references. Repaired by restoring the four deleted
objects directly in `project.pbxproj` (the exception set, now listing **five** Core files
including `DeviceAccessPrecondition.swift`; the synchronized root group; its entry in the
main group; and the helper target's `fileSystemSynchronizedGroups`), rather than by more
GUI steps that could go the same way. `plutil -lint` passes and the clean builds and tests
above confirm it.

Two lessons: **never issue a delete instruction for an object identified only by a name
that another object also has** — say what kind of object it is and what it looks like. And
a deletion in the Project navigator can remove a *synchronized group*, which is not
recoverable by re-ticking a checkbox the way a membership change is.

### A `pipefail` defect that made a guard fire only when it succeeded (2026-08-01)

**Symptom.** The first real run of `claim-contention-test.sh` aborted at its own preflight:
*"error: the client is not signed under team 5JC55GTLZA"* — while the client sitting on
disk was, verifiably, signed under exactly that team.

**Cause.** `codesign -dvvv "$CLIENT" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID"` under
`set -o pipefail`. `grep -q` exits on the **first match** and closes the pipe; `codesign`
then dies of `SIGPIPE` writing the rest of its (long) output; `pipefail` promotes that
non-zero status to the whole pipeline. **The check therefore failed precisely when the
match succeeded** — an inverted guard, not a flaky one.

**Why the pre-flighting missed it.** The signing path *was* exercised before handing the
script over, and it passed — but as loose commands in a shell **without** `set -o
pipefail`, not inside the script. So what was verified was the commands, not the script.
The same substitution error this project keeps producing, in a new costume.

**The same pattern audited across every script.** Only the `codesign -dvvv` sites are
actually broken; the others (`launchctl print`, `mount`, `printf`, `grep -A6`) return 0
today because their output fits the pipe buffer and the producer finishes before `grep`
exits. Tested rather than reasoned about, since it depends on output size:

| Site | Under pipefail |
|---|---|
| `codesign -dvvv \| grep -q` — claim-contention:139, negative-test:88 | **BROKEN** |
| `launchctl print \| grep -q` — negative-test:59 | OK today |
| `mount \| grep -q` — exclusivity-probe:77 | OK today |
| `printf \| grep -qF` — claim-contention:193, 240 | OK today |
| `… \| grep -A6 \| grep -q` — mount-change-test:83 | OK today |

**Fixed** by capturing first and matching against a here-string, which has no upstream
producer and so cannot `SIGPIPE`. Applied to both `codesign` sites and to
`claim-contention-test.sh`'s two `printf` sites. The three remaining latent uses are left
alone and recorded here: all three fail **closed** (a false non-match reads as a FAIL, not
a PASS), and rewriting working verification code that cannot be fully re-exercised right
now carries its own risk.

**The second site was worse than the first.** `negative-test.sh:88` is the Step 3 security
gate's own anti-vacuousness guard — *"refuse to run this test if the client is signed with
our own Team ID"*. Being inverted, it could **never fire**, which is the single condition
it exists to catch.

**Both fixes proven to discriminate**, in both directions, against a properly-signed and an
adhoc-signed client:

| Client | `claim-contention` guard | `negative-test` guard |
|---|---|---|
| Apple Development, team 5JC55GTLZA | proceeds | **aborts** (correctly: test would be vacuous) |
| adhoc | **aborts** (correctly: results would be transport failures) | proceeds |

**`negative-test.sh` re-run against the live v3 daemon → GATE PASSED.** The helper's log
also settles independently that the installed daemon is the new one:
`exporting TesterControl v3`.

### First real-hardware evidence (2026-08-01, live v3 daemon, `disk4`)

Obtained directly, without the script, using the signed `mount-guard-client`. Both calls
are safe to make with a volume mounted: the readiness check is side-effect-free by
construction, and an acquire with anything mounted is guaranteed to refuse (FR-SAFE-4(a)),
kernel-enforced as well as by policy.

**`checkDeviceReadiness disk4`** — `READY=0`, `MOUNTED_COUNT=1`, `MOUNTED=Test_Drive`,
`HELD=0`, message *"disk4 has 1 mounted volume (Test_Drive). It must be unmounted before a
test can start."* The helper's **independent** mount detection (its own `getfsstat` plus
the IOKit subtree walk) agrees exactly with `mount`, which reports
`/dev/disk4s2 on /Volumes/Test_Drive (exfat …)`. Singular agreement is right too — "1
mounted volume … It must be unmounted".

**`acquireDevice disk4`, with `Test_Drive` mounted** — the FR-SAFE-4(a) path, on hardware:

| Assertion | Result |
|---|---|
| refused | `ACQUIRED=0` |
| cause is **2** (volumes mounted), not 3 | `CAUSE=2` |
| names the volume and the corrective step | *"…the volume Test_Drive is still mounted. Unmount it first — use Unmount All, or unmount in Disk Utility…"* |
| **FR-SAFE-6: nothing was unmounted** | mount count `1 -> 1`, `disk4s2` still on `/Volumes/Test_Drive` |

The message also states FR-SAFE-6 to the user outright — *"Nothing was unmounted for you;
starting a test never changes what is mounted."*

`claim-contention-test.sh`'s output parser was checked against this real output rather than
against assumed output, including the trap where `MOUNTED` could swallow `MOUNTED_COUNT`.
`mounted_volume_count()` and the helper's own count agree (1 and 1).

Still unexercised on hardware: **cause (b)** (needs the `--hold` process under `sudo`, so a
Terminal), a **successful acquire**, **release**, and **release-on-connection-loss** — all
of which require unmounting the scratch drive, which is the script's job under supervision
rather than something to do unasked.

### THE MAJOR FINDING: the helper needs Full Disk Access (2026-08-01)

**Running as root is not sufficient to open `/dev/rdiskN` on an external drive.** This is
not in BUILD-PLAN, the FRs or the NFRs anywhere, and nothing in Steps 1–5 could have
surfaced it — Step 6 is the first time the helper tries to open a device.

**How it presented.** `claim-contention-test.sh` phases C and E failed with
`errno 1 (Operation not permitted)` — with nothing mounted and nothing contending. Both
FR-SAFE-4 causes were correctly excluded, so the refusal fell through to the generic
device-error case.

**The evidence.** `tccd`, at the exact instant of a clean, isolated acquire attempt:

```
08:51:32.318  Handling access request to kTCCServiceSystemPolicyAllFiles,
              from Sub:{com.arc3solutions.USBDriveTester}
              Resp:{…USBDriveTester.Helper, pid=72951, auid=0, euid=0}
              ReqResult(Auth Right: Denied (Service Policy))
08:51:32.320  kTCCServiceSystemPolicyRemovableVolumes denied by TCC
              for com.arc3solutions.USBDriveTester
```

So the raw open is gated by **TCC**, not by uid. Two details matter:

1. **`exclusivity-probe` succeeds at the identical sequence** — claim, then
   `O_RDWR|O_EXLOCK|O_NONBLOCK` — only because `sudo` from Terminal inherits **Terminal's**
   TCC grant. Every exclusivity measurement on 2026-07-30 was made through that borrowed
   permission. The measurements themselves stand (they were about exclusivity semantics,
   which are unaffected); but "a root process can open the raw device" was never true of a
   *daemon*, and was never tested as one.
2. **TCC attributes the request to the app bundle** (`Sub:{com.arc3solutions.USBDriveTester}`),
   not to the helper. So the grant belongs to the containing app and travels with it.

**Ruled out before concluding.** The obvious rival explanation was a claim leaked by the
timeout in phase B poisoning later attempts. Tested directly: with `disk4` remounted
beforehand (which proves no claim was held, since a claim is what prevents mounting), a
single clean acquire on an unmounted, uncontended disk still returned `EPERM`. The helper
has, in fact, **never once successfully opened a raw device**.

**Product change made in response.** `EPERM` now has its own refusal case,
`DeviceAccessRefusal.accessNotPermitted` (cause 7), instead of falling into the generic
device error. The old message read *"the device itself refused the open"* — which sends
someone to check the cable or suspect a failing drive when the fix is a checkbox. It now
names Full Disk Access, the exact System Settings path, and states that administrator
rights are not sufficient (NFR-USE-5). Four tests cover it, including that `EPERM` and
`EACCES` do not collapse into one classification.

**Consequences beyond Step 6 — these need a decision:**

- **Step 7 cannot work without this.** Raw I/O is the entire step.
- **This is a new install-time requirement.** NFR-INST-1 covers guiding the user through
  helper approval; it says nothing about Full Disk Access. Probably wants a requirements
  amendment, like FR-SAFE-5 got.
- **Step 16** must cover it in the clean-machine test: a fresh Mac will deny this by
  default, so "it works here" would be a false pass.
- **The app should detect and guide, not just report.** The refusal message is a stopgap;
  a first-run check that surfaces the requirement before the user reaches a failure would
  be better. Deferred pending the decision above.

### A second defect the same logs exposed: a stranded claim on timeout

Independent of the TCC finding, and real. From `diskarbitrationd`:

```
08:43:56.862  exclusivity-probe  claimed disk /dev/disk4, success
08:43:56.984  …Helper            queued solicitation, disk claim /dev/disk4   (pending)
08:44:02.059  unable to unclaim disk /dev/disk4 (status code 0xF8DA0003)
08:44:02.102  claimed disk /dev/disk4, success                                (43 ms later)
```

The timeout path called `DADiskUnclaim` immediately, on the assumption — written into a
code comment as though established — that this cancels a pending claim so a late grant
cannot strand the disk. It does not. The claim was still *pending*, the unclaim failed
with `kDAReturnBadArgument`, and the grant then landed into a session nobody was watching.

**Fixed.** On timeout the claim box is now *abandoned* rather than discarded: it keeps the
session and disk alive so DiskArbitration can still deliver the grant, and releases it the
moment it arrives (`ClaimOutcomeBox.claimArrived(granted:)`). The session is deliberately
**not** torn down on the timeout path, since tearing it down is what stranded the claim.
Logged when it happens, so the case is observable rather than inferred.

Not yet re-exercised on hardware — it needs a contended claim that later becomes
available, which is exactly what phase B of `claim-contention-test.sh` produces.

### NFR-INST-4 added, and detection built (2026-08-01)

Both approved by the user in response to the finding above.

**Requirement.** `NFR-INST-4` added to the non-functional set, priority **M**, with the
measured `tccd` evidence recorded in that document's new *Amendments to the Baseline*
section. It requires the permission, **and** requires the app to detect its absence and
report it *before* a run is attempted rather than as a run failure. Priority M rather than
S because without it the tool cannot perform its primary function at all — no raw open
means no read, no write-back, no verify. It is a prerequisite, not a degradation.

**Protocol v3 → v4.** `checkDeviceReadiness` gains a `blockingCause`
(a `DeviceAccessRefusalCause` raw value, `0` when nothing blocks). A signature change, so
the bump is mandatory rather than merely cheap — a v3 daemon would decode the reply block
differently. Folded into the existing read-only query rather than given its own method:
it answers the same question that method already asks, and a second privileged entry point
would be the wrong trade (NFR-SEC-3).

**Detection.** `DeviceClaim.fullDiskAccessState(for:)` opens the raw node **read-only** and
closes it immediately — no claim, no `O_EXLOCK`, nothing written, no mount state touched —
so it is safe to run on every selection change. Probing the real device rather than the
usual `TCC.db` proxy is deliberate: it tests exactly the capability needed on exactly the
device needed, and the measured denial named **two** TCC services
(`…AllFiles` *and* `…RemovableVolumes`), only one of which a `TCC.db` probe exercises.

**Classification** is pure and in Core: `FullDiskAccessState` is a three-state enum, not a
`Bool`. The probe is conclusive in only two directions, and `EACCES` in particular must not
read as "denied" — Full Disk Access is not the fix for ordinary filesystem permissions, and
saying so would send the user to grant something that changes nothing. Nine tests.

**Guidance.** The readiness banner shows the explanation and, when the grant is missing,
an **Open Full Disk Access settings…** button. Deliberately separate from the existing
Login Items button: those are different panes and different permissions, neither implies
the other, and being sent to the wrong one is a dead end. Ordering matters too — Full Disk
Access is reported ahead of a mounted volume, since telling someone to unmount when the
permission is *also* missing sends them round twice.

**Verified:** clean Debug tests `** TEST SUCCEEDED **`, **247 test cases** (238 `@Test`
declarations), 0 failures, 0 warnings; clean **Release** build succeeds, 0 warnings; the
CLI client, `negative-client` and `ui-probe` all recompile against v4.

**The first probe was wrong, and hardware caught it (2026-08-01).** With Full Disk Access
*not* granted, the banner showed the mounted-volume message instead of the permission
message. The helper's own log gave the reason immediately —
`readiness check for disk4: ready=false, 1 mounted volume(s), full-disk-access=granted`.

The probe opened `O_RDONLY`, chosen to be maximally side-effect-free. **Reading a raw
device is permitted; only writing is gated.** So it reported `granted` on a machine that
had been granted nothing — a probe that cannot fail on the condition it exists to detect,
which is worse than no probe at all: the banner stays silent and the user still learns the
truth from a failed acquire, which is precisely what NFR-INST-4 forbids.

The same substitution error as the rest of this session, one layer down: a safer stand-in
was chosen for the real operation, and it answered a different question. Note also what
did *not* fail — the app, the wire format, the ordering and the UI were all correct, and
faithfully reported a wrong input.

**Fixed:** the probe now opens `O_RDWR`, matching the acquire's access mode. It still omits
`O_EXLOCK` — the exclusive lock is what makes the acquire *exclusive*, not what makes it
authorised, and taking one here could make a concurrent acquire fail spuriously. It is also
skipped in two cases where it could not answer anyway: while a volume is mounted (the
kernel fails `O_RDWR` with `EBUSY` before TCC is consulted) and while the helper already
holds the device (it demonstrably opened it, and probing would collide with its own lock).

**The probe is advisory; `acquireDevice` remains the authority.** If the inference behind
it — that TCC gates on write access — is wrong in some case, the cost is a silent banner,
not a wrong answer.

**Consequence for the UI flow, worth knowing before testing:** with a volume mounted the
banner reports the *mount* (the actual blocker); the permission message appears once the
device is unmounted. Two steps, but each names the thing that is genuinely in the way at
that moment, and both still come before any run is attempted.

**Wrong a second time, and the flag that actually matters (2026-08-01).** The `O_RDWR`
probe *also* reported `granted`:

```
14:01:54.550  readiness check for disk4: ready=true, 0 mounted volume(s), full-disk-access=granted
```

Three measurements on the same machine, Full Disk Access **not** granted throughout:

| Flags | Result |
|---|---|
| `O_RDONLY` | succeeds |
| `O_RDWR \| O_NONBLOCK` | succeeds |
| `O_RDWR \| O_EXLOCK \| O_NONBLOCK` | **`EPERM`**, with `tccd` denying `…AllFiles` and `…RemovableVolumes` |

**TCC gates `O_EXLOCK`, not the access mode.** Neither reading nor writing is refused —
what is refused is *taking the exclusive lock*, which is the operation that amounts to
claiming ownership of the whole device. Sensible in hindsight, and not what either guess
predicted.

**The probe now uses exactly the flags `acquire` uses.** The cost is a lock held for the
microseconds between `open` and `close`; a concurrent acquire in that window would see
`EBUSY` and report cause (b). Accepted, and bounded by the two existing skips (mounted, or
already held by us).

**The lesson, stated plainly because it has now cost two rounds:** every approximation of
the real operation reported success on a machine where the real operation fails. First
`O_RDONLY` because it was maximally side-effect-free, then `O_RDWR` because "write access
must be the trigger" — reasoning, not measurement. This is the project's recurring theme
appearing at the level of a single `open(2)` flag. **Probe with the exact call.**

### The faithful probe had to be abandoned — it remounted the drive (2026-08-01)

Fixing the probe to use `O_EXLOCK` made it correct and simultaneously made it harmful.
Measured immediately after an Unmount All:

```
14:47:00.184  unmounted disk /dev/disk4s2, success
14:47:00.185  app: "Unmounted every volume on disk4: Test_Drive."
14:47:00.198  readiness check … full-disk-access=granted   <- the probe opened and closed
14:47:00.202  probed disk /dev/disk4s1 …                   <- 4 ms later
14:47:00.425  mounted disk /dev/disk4s2, success           <- the user's unmount undone
```

**Releasing an exclusive lock makes DiskArbitration re-probe and remount** — the same
behaviour measured on 2026-07-30 for a released `DADiskClaim`, reproduced with `O_EXLOCK`
instead. A readiness check that is documented as safe to poll was quietly defeating
FR-SAFE-5: press Unmount All, and the volume returns a heartbeat later. Strictly worse
than the bug it fixed, because it broke a working feature.

**The genuine conflict.** `O_EXLOCK` is the only device open that reaches the TCC gate, and
touching `O_EXLOCK` remounts the drive. The faithful test cannot live in a polled check.

**Resolution.** The probe no longer touches the device at all: it opens the protected TCC
database read-only and closes it, never reading a byte. That is gated by exactly the grant
the user makes (`kTCCServiceSystemPolicyAllFiles`), and nothing about it can cause a mount.

**This is a proxy, and the file says so.** Three device probes were wrong before it, so the
limits are stated rather than glossed: it establishes whether the *app holds Full Disk
Access*, not whether *this device* can be opened. `acquire` remains the only authority and
still reports the condition precisely from the real open. The probe is permitted to be
silent when it should not be; it is not permitted to remount a drive.

**The pattern, four probes in.** `O_RDONLY` (too weak), `O_RDWR` (still too weak),
`O_RDWR|O_EXLOCK` (faithful, unusable), and finally a non-device check with its limits
declared. Each earlier version was chosen by reasoning about what *ought* to trigger TCC;
each was settled by reading `diskarbitrationd` and `tccd` logs. **The logs answered every
question that reasoning got wrong.**

### An earlier remount, which was Finder rather than the app

Reported as "the volume remounts very quickly after unmounting", which looked like the
measured auto-remount-on-claim-release. It is not. `diskarbitrationd`:

```
14:01:54.148  USBDriveTester  disk unmount, /dev/disk4, options = 0x1 (Whole)   <- our button
14:01:54.420  app log: "Unmounted every volume on disk4: Test_Drive."
14:01:54.550  readiness: ready=true, 0 mounted volume(s)                        <- banner updated
   … 30 seconds pass, disk stays unmounted …
14:02:23.975  Finder [694]   disk eject, /dev/disk4
14:02:25.253  mounted disk /dev/disk4s2, success                                <- re-probe + auto-mount
```

**FR-SAFE-5's control works**, and the banner refreshed correctly within 130 ms. What
remounts the drive is a Finder **eject** on a device that cannot actually be detached:
DiskArbitration re-probes the media and auto-mounts it ~1.3 s later. The same pattern
appears twice in the log, each time following a Finder eject and never following our
unmount.

Worth keeping for Step 12 (device loss) and for the user-facing guidance: *unmount* and
*eject* are different operations here, and eject is counter-productive — it puts the volume
straight back.

### THE GUARD WORKS END TO END ON HARDWARE (2026-08-01)

With Full Disk Access granted to `USBDriveTester` and `disk4` unmounted, against the live
v4 daemon:

```
[check]   READY=1  MOUNTED_COUNT=0  HELD=0  BLOCKING_CAUSE=0
[acquire] ACQUIRED=1  CAUSE=0
          "Exclusive whole-disk access to disk4 is held: no volumes are mounted, the
           DiskArbitration claim is in place so the system cannot remount them, and
           /dev/rdisk4 is open exclusively."
[check]   HELD=1  BLOCKING_CAUSE=6
          "This app holds exclusive access to disk4. Release it before starting another run."
[release] RELEASED=1
          "Released exclusive access to disk4: the raw device was closed and the
           DiskArbitration claim dropped."
```

`disk4` then remounted normally. That discharges, on real hardware: the **successful
acquire** (FR-SAFE-3), **release restoring normal use**, the `alreadyHeld` cause
(FR-CTRL-9) with its own message, and the readiness check reporting held state correctly.

**Full Disk Access was the whole of it.** Once granted, the helper opens
`O_RDWR | O_EXLOCK | O_NONBLOCK` without complaint. NFR-INST-4 is confirmed as a genuine
hard prerequisite rather than an artefact of some other misconfiguration.

**Two false alarms in the same round, both mine, both worth recording:**

1. *"Unmount All fails"* — it did not. With the grant already in place there was no
   permission warning left to show, so the banner correctly read "disk4 has no mounted
   volumes…". The instruction to expect a permission message was written against a stale
   assumption about the machine's state, not against what was actually configured.
2. A `TRANSPORT_ERROR` on the first attempt to test this: the CLI client had been
   recompiled for v4 and not re-signed, so it was adhoc and the helper refused it —
   the Step 3 security gate working exactly as designed, mistaken for a fault.

**Still to verify:** the corrected `O_EXLOCK` probe (the installed build predates it, and
with the grant in place every probe variant agrees, so it can only be distinguished by
temporarily revoking Full Disk Access), phase B's cause 3 under the fixed harness, and the
stranded-claim fix.

**Note for Step 16:** re-registering the helper no longer prompts for approval on this
machine. That is the stable `BTM uuid` remembering prior consent, recorded in Step 4. A
clean Mac **will** prompt, so approval cannot be regarded as tested here — exactly the
false-pass hazard NFR-INST-2's clean-system clause exists to catch.

### `claim-contention-test.sh disk4` — FULL PASS (2026-08-01)

All four phases, 12/12 checks, against the live v4 daemon on the real exFAT scratch drive.

| Phase | Result |
|---|---|
| **A** — volumes mounted | refused, `CAUSE=2`, names `Test_Drive`, **mount state unchanged** (FR-SAFE-6) |
| **B** — unmounted, another process holding | `MOUNTED_COUNT=0` with `CAUSE=3`, message names another process |
| **C** — unmounted and free | `ACQUIRED=1`, then `HELD=1`/`CAUSE=6`, then `RELEASED=1` |
| **E** — connection loss | acquired, client exited without releasing, helper then holds nothing |

**Phase B is the one that matters most.** `MOUNTED_COUNT=0` paired with `CAUSE=3` is the
whole point of the step: both underlying failures are the same `EBUSY`, and only the mount
check separates them. Cause 2 and cause 3 have now each been produced on hardware, from the
same device, minutes apart.

**The three fixes made during this session were all exercised**, confirmed from the helper's
own log rather than inferred from the script's verdict:

- **Stranded claim on timeout** —
  `late DiskArbitration grant for disk4 arrived after the claim had timed out; released it
  immediately so it cannot strand the disk`. Phase B produces exactly the contended-then-
  released claim that caused the original defect, and the fix fired on it.
- **Full Disk Access probe** — `full-disk-access=granted` on every check, with the grant in
  place. No false warning, and the TCC-database proxy does inherit the app's grant when
  called from the helper, which had been an open question.
- **The remount regression** — a readiness check on an unmounted disk is now followed by
  the acquire, not by a re-probe. The drive stays unmounted.

**Release-on-connection-loss corroborated twice over.** The helper logged
`released on connection loss from pid 81836`, and phase E's follow-up check reported
`MOUNTED_COUNT=1` — the volume came back, which can only happen once the claim is genuinely
gone. State evidence and log evidence agreeing is stronger than either alone.

**Geometry sanity, incidentally confirmed:** the acquire logged
`IOKit reports 1000204886016 bytes in 512-byte blocks` for `disk4`, matching Step 5's
recorded figures exactly.

### Verification Gate — status

- [x] **Mounted volume ⇒ refusal naming the volume** (FR-SAFE-4(a)) — phase A, on hardware.
- [x] **Unmounted but held ⇒ "device node is claimed", distinct from the above**
      (FR-SAFE-4(b)) — phase B, on hardware.
- [x] **On success the helper holds claim + exclusive `rdiskN` open; releasing makes the
      disk normally usable again** — phase C, and the volume remounted afterwards.
- [x] **The write path has an enforced guard, verified by a check that trips when access is
      absent** (NFR-REL-3) — `WritePrecondition`, exhaustive over all 8 grant/target
      combinations; exactly one permits a write.
- [x] **Nothing mounts or unmounts implicitly** (FR-SAFE-6) — phase A asserts the mount
      count is identical before and after a refusal.
- [x] **Mount/unmount control (FR-SAFE-5/6/7)** — closed 2026-08-01. The label/enabled
      matrix is exhaustively unit-tested (15 tests over the full cross-product), and all
      three interactive parts are now confirmed: **Unmount All** unmounts and the label
      flips to **Mount All**; **Mount All** remounts `Test_Drive` and the label flips back
      — the genuinely new half of the FR-SAFE-5 amendment, exercised for the first time; a
      **failed unmount** (forced by holding a file open on the volume) names the volume
      *and* the reason (NFR-USE-5); and the **no-selection** state renders disabled with
      the default label "Unmount All" plus a stated reason.

      The no-selection state was verified by **render**, not by clicking. It is reachable
      only with no USB drive present at all — clicking blank space in the list is a
      deliberate no-op, because the selection binding discards `nil` so that a stale tap
      arriving as a device disappears cannot silently deselect (Step 5). Confirming it on
      this machine would have meant unplugging every USB device, one of which holds the
      source tree, so `scripts/render-ui.sh … empty` was added: it drives `DeviceListView`
      through an empty `DeviceSource`, which is the one state hardware here cannot
      produce.
- [x] **Global DoD** — clean Debug **and** Release builds, zero warnings; 247 test cases,
      0 failures.

### Outstanding before the gate can close

- [x] **Fix the Embed Helper phase** (above) — done 2026-08-01; clean Debug **and**
      Release both build with zero warnings, and Release now embeds the Release helper.
- [x] **Install and register the helper** — done 2026-08-01. `install-app.sh` installed the
      Debug build; both signatures carry `TeamIdentifier=5JC55GTLZA`. Verified from the
      binaries themselves that the helper contains `checkDeviceReadiness`/`acquireDevice`/
      `releaseDevice`, `DeviceClaim` and `WholeDiskName`, and that the app's code (which
      lives in `USBDriveTester.debug.dylib`, not the 59 KB launcher stub) contains the
      Step 6 UI. The daemon is registered and its own log reports
      `exporting TesterControl v3`.
- [x] **`./scripts/claim-contention-test.sh disk4` — run on hardware 2026-08-01.**
      Phase A **4/4 PASS** (cause 2, names the volume, FR-SAFE-6 holds). Phase B **3/4** —
      including the assertion the whole step exists for: `MOUNTED_COUNT=0` with `CAUSE=3`,
      cause (b) correctly told apart from cause (a) when both are the same `EBUSY`
      underneath. Its 4th check failed on a **harness** bug, not the product (below).
      Phases C and E failed on the Full Disk Access finding above.
- [x] **Harness bug in phase B fixed** — `value_of()` is now scoped by command. It had
      taken the *first* matching line, so `MESSAGE` resolved to the **check** message
      ("…confirm no **other** process holds the device") rather than the acquire refusal
      ("…held by **another** process"). The product was right; the assertion read the wrong
      line. Phase A's equivalent check had passed only because both messages happen to
      contain the volume name — luck, not correctness. Re-run: PASS.
- [x] **Full Disk Access granted; helper re-registered from `/Applications`.**
- [x] **Stranded-claim fix re-verified** on the hardware path that produced it (phase B).
- [x] **Interactive GUI items — all confirmed 2026-08-01.** Mount All, the failed-unmount
      message, the label toggling in both directions, both refusal messages, release
      restoring normal use, and the no-selection state (by render).

---

## Step 6 — COMPLETE (2026-08-01)

Every gate item is discharged. Summary of what the step delivered and what it cost.

**Delivered.** A helper-side mount guard that refuses a run unless every volume is
unmounted *and* it holds both a DiskArbitration claim and an `O_EXLOCK` open, telling the
two FR-SAFE-4 causes apart when the kernel reports both as the same `EBUSY`; a write-path
guard that is a type rather than a flag (`AcquiredDevice` is constructible only by a
successful acquire, and `WritePrecondition` re-checks at runtime what the type system
cannot see); a bidirectional Mount All / Unmount All control whose label and action are one
decision; and protocol v4.

**Requirements changed by this step.** FR-SAFE-5 revised and elevated C→M, FR-SAFE-6 and
FR-SAFE-7 added (all 2026-07-30, during scoping); **NFR-INST-4 added 2026-08-01**, the
Full Disk Access requirement, discovered only because Step 6 is the first step in which the
helper opens a device.

**Defects found in code that pre-dated this step:**

1. **The Embed Helper build phase** referenced a hard-coded DerivedData path, so every
   Release build since Step 1 embedded the *Debug* helper, and the project would not build
   on another machine (NFR-MAINT-3). Found only by building Release from a wiped
   DerivedData.
2. **`negative-test.sh`'s anti-vacuousness guard was inverted** by a `pipefail` +
   `grep -q` interaction, so the one condition it exists to catch could never fire. Present
   since Step 3.

**Defects found in this step's own code, all on hardware:** a stranded DiskArbitration
claim on the timeout path; a readiness probe that remounted the drive 4 ms after the user
unmounted it; and three successive versions of the Full Disk Access probe that reported
`granted` on a machine that had been granted nothing.

**The thread running through all of it.** Every one of those was found by reading
`diskarbitrationd`, `tccd` or the helper's own log, and every one had first been reasoned
about incorrectly. The project's standing lesson — never report a substitute's result as
the real thing — held at every scale this step, from a whole build configuration
(Debug helper standing in for Release) down to a single `open(2)` flag (`O_RDONLY`, then
`O_RDWR`, standing in for `O_RDWR|O_EXLOCK`). Logging that names the actual cause was what
made each one findable; NFR-OBS-1 paid for itself several times over.

**Carried into Step 7.**

- The helper must hold Full Disk Access or nothing works. Step 7's raw I/O is the whole
  point of the step, so this is a prerequisite, not a footnote.
- `AcquiredDevice.fileDescriptor` is the already-open, already-exclusive descriptor Step 7
  adds `F_NOCACHE`, `F_GLOBAL_NOCACHE` and the geometry ioctls to. It is opened
  `O_RDWR | O_EXLOCK | O_NONBLOCK`, as BUILD-PLAN Step 7 was amended to require.
- IOKit's geometry is recorded on `AcquiredDevice.geometry` and labelled provisional;
  Step 7's ioctls are the authority and BUILD-PLAN says to prefer them. The acquire log
  already prints it (`1000204886016 bytes in 512-byte blocks` for `disk4`) so the two can
  be compared directly.
- Releasing an exclusive lock or a claim makes macOS remount within milliseconds. Any Step 7
  code that opens and closes the raw device outside a held acquire will undo the user's
  unmount.
- **The test target is `disk4`, and disk images are no longer offered as an option.**
  BUILD-PLAN suggested attaching a disk image as a safer stand-in in Steps 7, 8 and
  Appendix B; that could never have been followed, because discovery lists USB
  mass-storage whole disks only and an image reports
  `Physical Interconnect == "Virtual Interface"` (measured, Step 5). The helper's own
  identity re-check would refuse it too. Amended 2026-08-01 by user decision: all
  real-hardware I/O uses `disk4`, whose contents are expendable, and a new "Test hardware"
  section near the top of BUILD-PLAN states this once for every step rather than per-gate.

  Recorded alongside it, because it is the part that is easy to misread: the drive being
  expendable relaxes the *consequence* of a bug, not the discipline. NFR-REL-1 still
  requires non-destructiveness to be proven in simulation before hardware (Step 8's gate),
  and FR-TEST-7 still requires the engine to write back the bytes it read rather than any
  pattern.

**State at completion.** Protocol v4. 247 test cases, 0 failures, zero warnings from clean
Debug **and** Release builds. Helper installed from `/Applications` and registered.
`claim-contention-test.sh disk4` passes 12/12.

### Also found: the registered daemon was running from DerivedData, not `/Applications`

`tccd` logged the helper's `binary_path` as
`…/DerivedData/USBDriveTester-…/Build/Products/Debug/USBDriveTester.app/Contents/MacOS/…`
— so the `SMAppService` registration in force was a stale one from an Xcode run, not from
the `/Applications` install. Step 3 recorded this exact hazard and added
`scripts/install-app.sh` because of it; it recurred anyway.

It did not invalidate the results above — that binary was rebuilt during this session and
was genuinely v3 (its log says `exporting TesterControl v3`) — but it must be corrected
before anything else, for two reasons: DerivedData is wiped routinely during clean-build
verification, which would delete the running daemon's binary out from under it; and a TCC
grant attaches to a bundle, so granting Full Disk Access to `/Applications/USBDriveTester.app`
while the daemon runs from DerivedData is at best confusing.

---

## Step 7 — COMPLETE (2026-08-02)

Every gate item discharged, 0 failures on hardware. Summary of what the step delivered and
what it cost.

**Delivered.** The real `RawBlockDevice` over the descriptor Step 6 already holds — uncached,
block-aligned `pread`/`pwrite` with short-transfer resumption and `errno` diagnosis; geometry
from the `DKIOC*` ioctls, reconciled against the helper's own IOKit reading and preferred over
it; a chunk plan that no longer scales with capacity; a buffer pair that *cannot* scale
because capacity is not one of its inputs; a run-start cache-bypass check that verifies
structurally and falsifies against a ceiling derived from the negotiated USB link speed; and
protocol v5.

**Requirements changed by this step.** **FR-TEST-9 added (M, 2026-08-02)** — run-start
verification that reads are not served from the host buffer cache, reported to the user and in
the run report, qualifying the verify result rather than preventing the run. Proposed by the
user in response to the finding that `fcntl(F_NOCACHE)`'s return value proves nothing.

**BUILD-PLAN amended in five places**, all 2026-08-02: 7.1 (Step 7 opens nothing — Step 6
already did, and a second descriptor would remount the volume on close); 7.3 (reconcile against
the *helper's* IOKit reading, not the app's Step 5 discovery, which would re-cross the trust
boundary Step 6 closed); 7.6 and gate item 3 (bounded memory binds every run-state structure,
not only the buffers); gate item 4 (a checked `fcntl` is not sufficient evidence); "Test
hardware" (`disk4` only, `disk8` by prior agreement per step).

**The measurement that changed the design.** `scripts/nocache-calibration.sh` was built as a
prerequisite rather than as polish, and it killed the mechanism FR-TEST-9 was going to use.
Re-read timing **cannot discriminate** on a raw device: with `F_NOCACHE` unset, repeated reads
of one region took 12,295 then ~8,800 µs; with it set, ~8,900 µs throughout — while a 4 MiB
copy from RAM takes **58 µs**, so a real cache hit would be ~150× faster than either. The cause
is that `/dev/rdisk4` is the **character** device and the buffer cache belongs to the block
node, so there was never anything to suppress. Shipping the timing check would have produced a
test that cannot fail — the precise defect FR-TEST-9 exists to prevent, reproduced inside
FR-TEST-9.

**The trap that nearly shipped.** Deriving the falsifier's ceiling from the USB link speed
required reading the IORegistry's `Device Speed`, whose enum **is not the one the SDK
documents**: `IOUSBHostFamilyDefinitions.h` describes a different property. Ten attached
devices resolved the question — a connected keyboard reports 0, which under the SDK enum means
"no device connected". Being wrong in the slow direction would have set the ceiling at
~0.2 MB/s and flagged every read of every run as cached.

**Defects found in this step's own work, all before they reached hardware:** a probe that would
have raced DiskArbitration's remount by opening and closing three times; a write-path guard
that fired on its own documentation and would have had to be silenced to run; a guard that
reported "assertion deleted" when it simply could not find the file; and a `#expect` comparison
whose compound integer literal was silently not promoted to `Double`.

**The thread running through all of it.** Every one was caught by insisting a check be shown to
*fail* before its passing was believed — the calibration probe written before the classifier,
the canary in the constants guard, the corrupted-copy run, the assertion that a temp file
accepts the misaligned read the device refuses. The project's standing lesson held again, in a
new form: it is not enough to avoid substituting for the real thing; a check must also be
capable of failing, or it is a substitute for a test.

**Carried into Step 8.**

- `AcquiredDevice.blockDevice()` vends a `FileDescriptorBlockDevice` on the held descriptor,
  using the authoritative geometry. The write path takes the `AcquiredDevice`, so NFR-REL-3's
  compile-time half still holds, and `WritePrecondition.check(_:writingTo:)` is the runtime half.
- `RetentionTestEngine.chunks()` is the lazy plan a run iterates. `chunkPlan()` remains for
  tests and diagnostics only — it is the 200 MiB path for a 22 TB device.
- `ChunkBuffers` is the two-buffer pair; `original` is the only copy of the user's data during
  the write, which is what bounds NFR-REL-4's in-flight window to one chunk.
- FR-TEST-9's verdict is on `AcquiredDevice.cacheBypass`; Step 8 seeds a
  `CacheBypassAssessment` from it plus the link speed and feeds per-chunk throughput in.
- **Step 8 writes the first byte to real media.** NFR-REL-1 requires non-destructiveness proven
  in simulation *before* that, and Step 8's own gate is where that proof lives. Nothing in
  Step 7 wrote to `disk4`.

**NFR-COMPAT-6 — DISCHARGED ON HARDWARE (2026-08-02), on user instruction, before Step 8.**
Carried out of the main gate because `disk4` is 1,953,525,168 blocks — below 2³² — where a
bridge truncating its block count to 32 bits would be invisible, and the failure is silent: the
tool would test the first portion of a larger drive and report a clean pass.

`./scripts/large-address-check.sh disk8` closes it, **10 PASS / 0 failures**:

| Check | Result |
|---|---|
| `DKIOCGETBLOCKCOUNT` | **42,970,644,479** — matches `diskutil`, and is *not* the 20,971,519 (10.7 GB) a 32-bit truncation would report |
| read at block 0 | ok |
| read at block 4,294,967,295 (last 32-bit-addressable) | ok |
| read at block **4,294,967,296** (first needing >32 bits) | ok |
| read at block 4,295,967,296 | ok |
| read at block 42,970,644,478 (the last block) | ok |
| read one block **past** the end | **correctly refused** (0 bytes) |
| last block vs its 32-bit-wrapped twin (20,971,518) | **distinct**, and neither all-zero |

The decisive pair is the last two rows but one: succeeding at the final block *and* being
refused one block past it brackets the device exactly, which is only possible if 64-bit
addressing holds end to end — a truncated size or wrapped addressing would have made the
past-the-end read land on a valid low block and succeed. The aliasing check then confirmed it
directly, and did **not** hit the all-zeroes ambiguity it was written to tolerate: both blocks
held real, different data.

**How it was done safely, since `disk8` is not the expendable scratch device.** It carries a
live HFS volume, `/Volumes/Backup`. So `tools/large-address-probe` departs from
`DeviceClaim`'s flags deliberately and opens **`O_RDONLY`** with no `O_EXLOCK`: the descriptor
physically cannot write, nothing had to be unmounted, and with no exclusive lock there was no
release to trigger DiskArbitration's remount. The volume stayed mounted throughout and was
verified still mounted afterwards. The fidelity cost is acceptable because of what was asked —
whether the ioctls report a 64-bit count and whether `pread` reaches a block above 2³² are
properties of the device, bridge and kernel, not of the open mode.

`scripts/large-address-check.sh` **refuses `disk4`** for being at or below 2³², so it cannot be
run against hardware that would pass it vacuously.

**State at completion.** Protocol v5. **323 tests, 0 failures. Zero warnings from clean Debug
and clean Release builds**, DerivedData wiped before each. Release bundle re-audited and
confirmed to embed the *Release* helper (identical byte-for-byte with signatures stripped).
`./scripts/geometry-check.sh disk4` passes 9/9. `./scripts/ioctl-constants-check.sh` passes
9/9. `./scripts/usb-speed-check.sh` passes 3/3.

---

## Step 7 — Raw I/O core — scoping and authoring log

**AI-5 / satisfies FR-TEST-2/5/6; FR-DEV-5; NFR-PERF-1/2, NFR-COMPAT-5/6.**
**Helper-side only** (FR-ARCH-6).

Recorded here so a cold start has the state without re-deriving it.

### State this step begins from

- **Steps 1–6 complete.** Step 6 committed at `81e7485`; `git` clean on `main`.
- **Protocol v4.** `ping`, `protocolVersion`, `validateRunParameters`,
  `prepareForShutdown`, `checkDeviceReadiness`, `acquireDevice`, `releaseDevice`.
- **247 test cases** (238 `@Test` declarations), 0 failures, zero warnings from clean
  Debug **and** Release builds.
- **Helper installed from `/Applications` and registered**, with **Full Disk Access
  granted** to `USBDriveTester`. Re-registering no longer prompts for approval on this
  machine (stable `BTM uuid`) — a clean Mac still will.
- `./scripts/claim-contention-test.sh disk4` passes 12/12.

### What Step 6 hands over

- **`AcquiredDevice`** (`…Helper/DeviceClaim.swift`) — constructible only by a successful
  `DeviceClaim.acquire(_:)`. Carries:
  - `fileDescriptor` — the raw node **already open** `O_RDWR | O_EXLOCK | O_NONBLOCK`.
    Step 7 adds `F_NOCACHE`, `F_GLOBAL_NOCACHE` and the geometry ioctls to *this* fd; it
    must not open its own.
  - `geometry: EligibleDevice` — IOKit's `sizeBytes` and `logicalBlockSize`, explicitly
    **provisional**. BUILD-PLAN Step 7.3 says to reconcile and prefer the ioctl values.
    Already logged at acquire time (`1000204886016 bytes in 512-byte blocks` for `disk4`),
    so the two can be compared directly in the log.
  - `grant: DeviceAccessGrant` — recomputed, not stored, so it reads incomplete after
    `release()`.
- **`WritePrecondition.check(_:writingTo:)`** (Core) — the NFR-REL-3 runtime guard. Step 8's
  write path calls it; Step 7 need only keep the descriptor honest.
- **`RunParameterValidator`** (Core, Step 3) — alignment and range, overflow-checked. From
  Step 7 it is fed ioctl-derived geometry instead of caller-supplied.
- **`RetentionTestEngine.chunkPlan()`** (Core, Step 2) — the exact-remainder final chunk,
  already tested for 512 B and 4096 B.

### Hazards that will bite Step 7 specifically

1. **The helper needs Full Disk Access** (NFR-INST-4) or the raw open fails `EPERM`. Root
   is not sufficient. Granted on this machine; a clean Mac is not.
2. **Opening and closing the raw device outside a held acquire remounts the volume within
   milliseconds.** Measured: releasing an `O_EXLOCK` open makes DiskArbitration re-probe and
   auto-mount ~4 ms later. Any Step 7 probe, geometry check or experiment that opens the
   node on its own will undo the user's unmount. Use the descriptor `AcquiredDevice`
   already holds.
3. **Disk images are not a test target** — discovery excludes them by design. All
   real-hardware I/O is `disk4`, whose contents are expendable. `disk6` holds the source
   tree and must never be tested.
4. **Raw devices reject misaligned offsets/lengths with `EINVAL`.** Alignment is the
   device's contract, not a style preference.
5. **`F_NOCACHE` is what makes Step 8's verify read meaningful.** Reading through a cached
   path would let the buffer cache satisfy the verify and make the whole test vacuous.

### The gate (from BUILD-PLAN, amended 2026-08-01)

- [x] Against `disk4`, geometry reads correctly and matches `diskutil info`.
      **`./scripts/geometry-check.sh disk4`, 0 failures (2026-08-02):** 512 / 1,953,525,168 /
      1,000,204,886,016 from the ioctls on the held descriptor, matching `diskutil` on all
      three, and matching the helper's own IOKit reading.
- [x] Chunk plan correct for awkward sizes, both 512 B and 4096 B, via unit tests — including
      a block count that is **not** a multiple of `blocksPerChunk`. `RetentionTestEngineTests`
      (7 cases, unchanged from Step 2) plus `ChunkPlanTests` (12), which adds `disk4`'s and
      `disk8`'s **real** geometries and full-traversal tiling over 5,245,440 chunks.
- [x] Peak buffer memory ≈ 2×`ioSize` regardless of device size (NFR-PERF-1) — **and no
      other run-state structure scales with capacity either** (NFR-PERF-2; amended
      2026-08-02, see decision 4 below). `ChunkBuffers` cannot scale because capacity is not
      one of its inputs; the chunk plan is now a lazily-computed `Sequence`.
- [x] `F_NOCACHE` / `F_GLOBAL_NOCACHE` set — both `fcntl` results checked, acquire fails if
      either is non-zero — **and** the FR-TEST-9 mechanism built on the calibrated finding
      that re-read timing cannot discriminate. Hardware: `CACHE_BYPASS=1` (bypassed).

- [x] **NFR-COMPAT-6, added to this gate 2026-08-02 by user instruction** — not discharged by
      anything run on `disk4`, which is below 2³². `./scripts/large-address-check.sh disk8`
      passes 10/10: 42,970,644,479 blocks reported, reads succeed at and beyond the boundary
      and at the last block, a read one block past the end is refused, and the last block is
      not an alias of its 32-bit-wrapped twin. Read-only; `/Volumes/Backup` never unmounted.

### Facts established headlessly during scoping (2026-08-02)

Measured before any code was written, with no drive touched and nothing added to the
project. They change the file plan, so they are recorded rather than left in a transcript.

1. **`DKIOCGETBLOCKSIZE` / `DKIOCGETBLOCKCOUNT` cannot be imported into Swift.** The SDK
   is explicit: `macro 'DKIOCGETBLOCKSIZE' unavailable: structure not supported`. They are
   `_IOR(…)` macros, not plain integer `#define`s — the same class of problem as the IOKit
   registry-key `#define`s that `DeviceClaim.swift` spells out by hand.
2. **The Swift re-derivation is correct, checked against C rather than reasoned about.**
   A `_IOR` written in Swift produces `0x40046418` and `0x40086419`; compiling
   `<sys/disk.h>` in C and printing the macros produces the same two values.
3. **No C shim and no bridging header are needed.** `ioctl(fd, UInt, &value)` and
   `fcntl(fd, F_NOCACHE, 1)` both compile and link from Swift; `F_NOCACHE` (48) and
   `F_GLOBAL_NOCACHE` (55) import normally. This removes what would have been the largest
   Xcode GUI task of the step.
4. **`fcntl(fd, F_NOCACHE, 1)` returns 0 on `/dev/null`.** A zero return therefore proves
   almost nothing on its own — it is not evidence that caching was suppressed on a device.
   This is what makes the `F_NOCACHE` gate item's "verified by code path" wording weak.
5. **Geometry and chunk arithmetic for the real hardware** (`diskutil`, read-only):

   | Device | Bytes | Blocks (512 B) | Chunks @ 4 MiB | Final chunk |
   |---|---|---|---|---|
   | `disk4` — 1.0 TB | 1,000,204,886,016 | 1,953,525,168 | 238,468 | 3,504 blocks (1,794,048 B) |
   | `disk8` — 22 TB | 22,000,969,973,248 | 42,970,644,479 | 5,245,440 | 8,191 blocks (4,193,792 B) |

   Both are genuine FR-TEST-5 remainder cases, so `disk4` alone does exercise the
   exact-remainder final chunk on hardware. `MemoryLayout<Chunk>.stride` is 40 bytes and
   the page size is 16,384.

### Authoring log — the calibration probe (2026-08-02)

`tools/nocache-probe/main.swift` + `scripts/nocache-calibration.sh`. Neither is in the Xcode
project (standalone `swiftc` + shell), so no GUI work was needed. Two defects found and
fixed before either touched hardware.

**1. Open/close/open would have raced DiskArbitration.** The first draft ran each phase in
its own `open` … `close`. Measured 2026-08-01: releasing an exclusive open makes
DiskArbitration re-probe (~4 ms) and remount (~230 ms). A second open racing that can fail
`EBUSY` for reasons unrelated to caching — and the failure would have read as a caching
result. Restructured to **one descriptor for the whole probe**, which also matches what
`DeviceClaim.acquire(_:)` does and removes the race entirely.

**2. The script's write-path guard fired on its own documentation.** The guard greps the
probe's source to prove it contains no device write before handing it a raw exclusive
descriptor. It matched line 31 of the probe — the header sentence *"no `pwrite`, no `write`,
no `O_TRUNC`"* — and refused to run.

It **failed closed**, which was the right direction, and it was caught on the first real
invocation. But the guard was wrong: it could not tell code from prose, so the only way to
run at all would have been to silence it, and silencing a guard is how a guard stops
guarding. Fixed by stripping comments before matching, and by allowing `.write(`
(`FileHandle.standardError.write` is how the tool reports errors) while still rejecting a
bare `write(` or any `pwrite(`.

**A canary was added with the fix.** The guard now also asserts it still fires against a
deliberate `pwrite(fd, …)` string. Without that, a pattern matching *nothing* would report
the same `PASS` as a genuinely clean file — which is exactly the shape of the inverted
`pipefail` guard in `negative-test.sh` that could not fire for three steps.

### Authored 7/7 — the helper wiring, protocol v5 (2026-08-02)

All Step 7 code is now written. **No GUI work** — every new file is helper-only or a script,
and both auto-join.

**Tests: 321 → 323, 0 failures.** **Zero warnings from clean Debug *and* clean Release
builds**, DerivedData wiped before each (the incremental-build warnings gotcha).

| File | Change |
|---|---|
| `Helper/RawDeviceGeometry.swift` | **NEW.** The syscalls: `F_NOCACHE`/`F_GLOBAL_NOCACHE`, `fstat` for the node kind, the four `DKIOC*` ioctls, and reconciliation against the helper's own IOKit reading. |
| `Helper/DeviceClaim.swift` | `EligibleDevice` gains `usbLinkSpeed`; `eligibility(of:)` reads `Device Speed` via a new **ancestor-searching** numeric lookup; `acquire` runs step 5 (configure + geometry) and **fails closed**, releasing fd, claim and session, if geometry cannot be established; `AcquiredDevice` carries the authoritative geometry, reconciliation, uncached-I/O configuration and cache-bypass verdict, and vends a `FileDescriptorBlockDevice` on demand. |
| `Shared/TesterControl.swift` | `deviceProfile` added, `CacheBypassOutcome` wire enum added, **v4 → v5**. |
| `Helper/main.swift` | Implements `deviceProfile`; new `io` log category. |
| `tools/mount-guard-client` | `profile` command. |
| `scripts/geometry-check.sh` | **NEW.** The hardware gate. |

**Geometry is established at acquire, not on first use**, so `AcquiredDevice` carries
authoritative numbers from birth and there is no window in which a caller could address the
device using IOKit's provisional ones.

**`Device Speed` needed a new registry helper.** The existing `number(_:_:)` reads the entry
itself, but the USB properties sit several levels up past the block-storage driver and the SCSI
peripheral — the same reason `ioreg -n disk4` cannot answer this. Added `ancestorNumber`,
alongside the existing `ancestorDictionary`.

**One method, not two (user decision).** `deviceProfile` returns both geometries, the
cache-bypass verdict, the raw link-speed code and the advertised maximum read. They were
originally to be split because the cache-bypass check would perform timed reads; the
calibration made it structural and passive, so a second privileged method would have bought
nothing (NFR-SEC-3). The **raw** `Device Speed` code crosses the wire rather than an
interpreted speed, so the app is not forced to trust this build's reading of an enum no SDK
header declares.

**v5 is purely additive** — a v4 client's existing calls decode identically — but bumped
anyway, because an app needing the profile must be able to tell a helper that cannot provide it
from one that can, and a missing method surfaces as a transport failure rather than as "too
old". `cacheBypassCodesMatchTheWireEnum` pins `CacheBypassOutcome` against
`CacheBypassState.wireCode`, and asserts an unrecognised code still **qualifies** the verify
result rather than clearing it.

#### Release-bundle audit (the defect that hid for five steps)

The Step 6 finding was that Release embedded the *Debug* helper. Re-checked here rather than
assumed: the standalone Release helper and the one inside the Release app bundle have different
SHA-256 hashes but identical sizes. Stripping both signatures makes them **byte-identical**, so
the difference is re-signing at embed time and the Release bundle does embed the Release helper.
(Debug's helper is 998,064 bytes; Release's is 866,976 — they are not interchangeable by size
either.)

### Authored 6/7 — the lazy chunk plan, in `Core/RetentionTestEngine.swift` (2026-08-02)

Discharges **decision 4**. No GUI work — an existing Core file.

**Tests: 309 → 321, 0 failures.** The seven existing `RetentionTestEngineTests` cases pass
**verbatim, unmodified**, which was the constraint on this change.

`ChunkPlan` is now a `Sequence` computed on demand, storing four integers. `chunks()` is what a
run iterates; `chunkPlan()` survives unchanged, returning `Array(chunks())`, and is documented
as **for tests and diagnostics only** — it is the 9.1 MiB / 200.1 MiB path.

Built from geometry rather than from a device, which is what makes the scale cases testable at
all: `InMemoryBlockDevice` allocates its whole backing store, so it cannot represent `disk8` at
any price, while a plan over that geometry costs four integers.

**The laziness proof is a plan that could not be materialised.** `aPlanTooLargeToMaterialiseIsStillFullyUsable`
builds an 18-exabyte plan — 4,398,046,511,104 chunks, ~176 TB as an array — then reads its
first chunk, its last chunk and its size, instantly. If `ChunkPlan` ever goes back to storing
its chunks, that test fails by exhausting memory rather than by reporting a wrong value.

Both real geometries are now asserted against their measured numbers rather than invented
awkward sizes:

| Device | blocks | chunks @ 4 MiB | final chunk |
|---|---|---|---|
| `disk4` | 1,953,525,168 | 238,468 | 3,504 blocks (1,794,048 B) |
| `disk8` | 42,970,644,479 | 5,245,440 | **8,191 blocks** — one short of full |

`disk8PlanTilesTheWholeDeviceWithoutGapsOrOverlaps` walks all 5,245,440 chunks accumulating
counters only, asserting exact coverage first block to last and that **exactly one** chunk is
short. It is the slowest case in the suite at ~1 s, which is the cost of proving tiling at
22 TB scale and is worth it.

Two small things found while doing it:

- `min` inside a `Sequence` conformance resolves to `Sequence.min()` rather than the global
  function — including inside the nested `Iterator`, by enclosing-scope lookup. Qualified to
  `Swift.min`.
- `chunkCount` is `UInt64` and is computed as `full + (remainder == 0 ? 0 : 1)` rather than
  `(blockCount + blocksPerChunk - 1) / blocksPerChunk`, which overflows near `UInt64.max` —
  reachable by the 18-exabyte test above.

### Authored 5/7 — `Core/FileDescriptorBlockDevice.swift` (2026-08-02)

The real `RawBlockDevice`: block-aligned `pread`/`pwrite` over a borrowed descriptor, with
short-transfer resumption, `EINTR` retry, and `errno` mapped onto `DeviceIOError`. Alignment
and range are delegated to `RunParameterValidator` rather than restated next to the syscalls.
Ticked into `USBDriveTesterTests` and verified in `project.pbxproj` (ten Core files; app target
still has no exception set).

**Tests: 294 → 309, 0 failures** — 15 new cases.

**It borrows the descriptor and has no `deinit`, deliberately.** `AcquiredDevice` owns the fd.
Closing it here would be worse than a leak: measured 2026-08-01, releasing an exclusive open
makes DiskArbitration remount the volume ~4 ms later — silently undoing the user's unmount
*while a run is writing*. `theDescriptorSurvivesTheDeviceBeingDeallocated` is what fails if a
`deinit` is ever added as tidiness.

**`errno` is kept apart from the thrown error.** `DeviceIOError` carries what Step 8 needs to
classify a chunk failure (FR-FAIL-6) and not the `errno`, which the engine has no use for. But
"the read failed" and nothing else is the message that sent us hunting for a cable when the
answer was a checkbox (NFR-INST-4). So `lastFailure` records operation, offset, length,
bytes-transferred and `errno` for the helper to log — addressing only, never data (NFR-SEC-6).
It also distinguishes the two failures that look alike: a partial transfer with `errno == 0` is
not the same event as an outright refusal.

#### A claim I had to make more precise

The file header first said that no file-backed test can distinguish a working alignment guard
from a missing one. **That was overstated**, and the tests forced the correction. A regular
file *would* accept a misaligned read — so a test showing the request throws does prove this
guard fired, precisely because the backing store would not have objected. What no file-backed
test can show is that the guard is **necessary**: that `/dev/rdiskN` would have refused with
`EINVAL`. Correctness is testable here; necessity is a fact about hardware and is on the gate.
`aMisalignedOffsetIsRefusedEvenThoughAFileWouldAllowIt` asserts both halves — the device
refuses, and the same `pread` straight to the file succeeds.

#### NFR-COMPAT-6 gets real evidence after all

`offsetsBeyondThirtyTwoBitsAddressCorrectly` writes and reads at a **5 GiB** offset through an
actual `pread`/`pwrite` on a *sparse* temp file — past the 4.295 GB where a 32-bit byte offset
wraps, at no disk cost. It then asserts nothing landed at the wrapped offset, which is where a
truncated offset would have written.

This does not discharge the NFR-COMPAT-6 limit recorded against the gate — that limit is about
a *USB bridge* reporting a >2³² block count, which only `disk8` can show. But the 64-bit
arithmetic and syscall path through this project's own code are now exercised against real
syscalls rather than only in-memory, which is more than was previously true.

Also covered: agreement with `InMemoryBlockDevice` over a sequence of operations (the engine is
written once and runs against both, so a divergence would mean Step 8's simulation proof does
not describe the hardware path); zero-length requests matching the in-memory device exactly;
geometry validated once at construction rather than per transfer; and short-transfer detection
via a file deliberately shorter than its declared geometry.

### Authored 4/7 — `Core/ChunkBuffers.swift` (2026-08-02)

The original-read and verify-read buffer pair (BUILD-PLAN 7.6, NFR-PERF-1 and the buffer half
of NFR-PERF-2). Named for the type rather than the `IOBuffer.swift` of the scoping plan,
because it owns a *pair* and every other Core file is named for its primary type. Ticked into
`USBDriveTesterTests` and verified in `project.pbxproj` (nine Core files; app target still has
no exception set).

**Tests: 282 → 294, 0 failures** — 10 cases plus a 2-case serialised instrumentation suite.

**The guarantee is structural, not measured.** `ChunkBuffers` has **no parameter through which
a device's size could reach it** — the initialiser takes an I/O size and nothing else. So
"memory must not scale with capacity" is not a property to be checked and hoped for; it is
unrepresentable. A test states the contrast: at 4 MiB, `disk4` is 238,468 chunks and `disk8` is
5,245,440 — 22× the work — and the memory held while doing it is byte-for-byte identical.

That framing is deliberate, because the *other* half of NFR-PERF-2 was not written this way
and quietly failed: Step 2's materialised `[Chunk]` is 200.1 MiB for `disk8`. Bounded buffers
beside an unbounded plan satisfied the gate's wording and missed its intent. Item 6 fixes it.

**The case that matters most is `theTwoBuffersAreDistinctMemory`.** If `original` and `verify`
ever aliased, FR-TEST-3's cycle would compare a buffer against itself and pass for every chunk
of every drive, including a failing one — the same vacuous-pass shape FR-TEST-9 guards against
at the caching layer, arriving instead through a pointer, and nothing else in the system would
notice. Asserted both by base address and behaviourally (fill one 0xAA, the other 0x55, check
the far end of each), because an address comparison alone would still pass for views that
overlapped without sharing a base.

Also covered: page alignment (16,384 on Apple Silicon, asserted rather than assumed — a
silently unhelpful alignment produces correct results and slower I/O, which is the kind of
thing that never gets noticed); prefix views for the short final chunk, using `disk4`'s real
3,504-block and `disk8`'s 8,191-block remainders; and BUILD-PLAN 7.6's "instrument and
confirm" via process-wide `peakAllocatedBytes`, with a 1,000-chunk loop asserting the peak
never rises above one chunk's worth.

Two hygiene decisions recorded in the file: the buffers are wiped with `memset_s` before
`free` (they hold the contents of somebody's drive and this runs as root — hygiene rather
than a boundary, but cheap and once), and the type is deliberately not thread-safe, matching
`InMemoryBlockDevice` and the one-chunk-in-flight model (NFR-REL-4).

### Authored 2–3/7 — `Core/CacheBypassCheck.swift`, `Core/USBLinkSpeed.swift` (2026-08-02)

FR-TEST-9's classifier and the link-speed mapping its falsifier derives its ceiling from. Both
pure; both ticked into `USBDriveTesterTests` and verified in `project.pbxproj` (all eight Core
files present, app target still has no exception set).

**Tests: 253 → 282, 0 failures.** 29 new cases in four suites — `USBLinkSpeedTests` (7),
`DeviceNodeKindTests` (2), `CacheBypassCheckTests` (9), `CacheBypassAssessmentTests` (11).

The cases worth naming, because they are the ones that would have to fail for the check to be
worthless: a block device is reported as `likelyCached` (the one-character bug that would make
every verify vacuous); a *bad speed code abandons its own ceiling instead of flagging a healthy
drive*; after abandoning it, the fixed fallback still catches a RAM-speed read; a confirmed
ceiling catches a 2 GB/s read that the fallback alone would have missed; the verdict never
improves, including after a structural failure; and `code 0` is asserted to be Low Speed
rather than the SDK enum's "no device connected", so the mapping cannot be quietly "corrected"
into the wrong enum.

The authoring list grew from 6 to 7 items: the derived-ceiling design added one Core file.

#### GOTCHA: a compound integer literal inside `#expect` is not promoted to `Double`

New, and in the same family as the `pipefail` inversion — a test mechanism that silently
changes meaning.

```swift
#expect(USBLinkSpeed.high.maximumPayloadBytesPerSecond == 480_000_000 / 8)   // FAILS
```

It failed reporting `60000000.0 == 60000000` — two renderings of the same number. The same
comparison is `true` when evaluated normally. `#expect` captures each operand separately for
reporting, and a **compound** integer-literal expression (`480_000_000 / 8`) takes its default
type, `Int`, instead of being promoted to `Double`. A **bare** literal (`500_000_000`) infers
correctly from context — which is why the very next line in the same test passed, for no
visible reason.

This instance produced a false *fail*, which is harmless. The identical mechanism can produce
a false *pass*, which is not. **Write every expected `Double` as an explicit `Double`
literal** (`60_000_000.0`, `< 1.0`, `> 2.0`) in `#expect`, and prefer
`try #require(...)` into a local over inlining an optional.

### Design change during authoring: the falsifier's ceiling is derived, not chosen (2026-08-02)

**User proposal**, during file 2's GUI tick: *"If you are able to query what the highest USB
standard of both the USB host device and the USB Unit Under Test, then you can actually derive
the theoretical max i/o rate for the currently selected drive and use that as the threshold."*

Adopted. It replaces a number chosen by judgement (8 GB/s) with one the hardware states, and
it does not age as USB gets faster. **The host half turns out to be unnecessary**, which is a
simplification rather than a limitation: the registry reports the *negotiated* connection
speed, already the minimum of device, every intervening hub, and host port. Querying the host
separately would re-derive a minimum negotiation has already taken.

**Margin: ×1.1, corrected by the user from the ×2 first proposed.** *"I spent decades of my
career measuring block storage speeds, and I don't recall ever getting a measured result above
the negotiated theoretical max."* Correct — the payload rate after encoding is a hard physical
limit, not an estimate to pad, and a doubled ceiling concedes far more than measurement error
needs. 10% covers timer granularity and scheduling jitter.

Result, all confirmed on hardware 2026-08-02:

| Disk | code | link | payload max | ceiling ×1.1 | measured | headroom |
|---|---|---|---|---|---|---|
| `disk4` | 4 | 10 Gb/s | 1.212 GB/s | **1.333 GB/s** | 0.475 GB/s | 2.8× below |
| `disk8` | 3 | 5 Gb/s | 0.500 GB/s | **0.550 GB/s** | — | — |
| `disk0` | — | not USB | — | fallback 8 GB/s | — | — |

**6× tighter than the fixed threshold for `disk4`, 14.5× for `disk8`**, and a RAM-served cache
hit (71.3 GB/s measured) now sits 53× above `disk4`'s ceiling rather than 9×.

#### THE TRAP: two USB speed enums, and the SDK documents the wrong one

Nearly shipped a serious bug. `IOUSBHostFamilyDefinitions.h` defines
`tIOUSBHostConnectionSpeed` as `None=0, Full=1, Low=2, High=3, Super=4, SuperPlus=5,
SuperPlusBy2=6` — but that documents **`kUSBHostMatchingPropertySpeed`, a different
property**. The registry key actually present is `"Device Speed"`, a legacy `IOUSBFamily`
name whose enum is `Low=0, Full=1, High=2, Super=3, SuperPlus=4, SuperPlusBy2=5`, and which
the SDK does not declare at all — the same class of problem as the registry `#define`s
`DeviceClaim.swift` spells out by hand, and as the `_IOR` macros earlier this step.

Resolved by evidence, not by picking one. `scripts/usb-speed-check.sh` dumped every attached
USB device — **ten devices, zero anomalies** under the legacy mapping, four absurdities under
the SDK one:

| Device | code | legacy | SDK enum would say |
|---|---|---|---|
| USB keyboard, optical mouse | 0 | Low 1.5 Mb/s ✓ | **"no device connected"** ✗ |
| USB2 / USB2.1 Hub | 2 | High 480 Mb/s ✓ | **Low 1.5 Mb/s** ✗ |
| Expansion HDD (USB 3.0), USB3.1 Hub | 3 | Super 5 Gb/s ✓ | **High 480 Mb/s** ✗ |
| Portable SSD T5 (USB 3.1 Gen 2), USB3/3.2 Hubs, Ugreen | 4 | SuperPlus 10 Gb/s ✓ | Super 5 Gb/s |

The single decisive observation: **a connected keyboard reports 0**, which under the SDK enum
means "no device is connected". Independently, `disk4`'s measured 475 MB/s is 3.8 Gb/s of
payload and therefore impossible on a 480 Mb/s link, so code 3 cannot be High Speed.

**The consequence of being wrong is not symmetric**, which is what makes this dangerous rather
than merely untidy. Reading a 10 Gb/s link as 5 Gb/s only loosens the ceiling. Reading it as
Low Speed would set the ceiling at ~0.2 MB/s and flag **every read of every run** as cached.

#### Two guards, because the mapping is evidence-derived and can drift

1. **An unrecognised or absent code yields no ceiling** — the check falls back to the fixed
   8 GB/s and says so in the report. No code is ever guessed at.
2. **The derived ceiling must be confirmed before it is trusted.** It becomes credible only
   once a read arrives at or below it. Until then, exceeding it is evidence against *the
   ceiling*, not against the drive — a bad speed code makes every read exceed from the very
   first, whereas caching appears against a background of normal reads. The ceiling is then
   abandoned, with the reason recorded, and the fallback applies. Exceeding the *fallback*
   always counts, since no USB link of any generation reaches 8 GB/s.

Also added: reads below 64 KiB are not judged at all — at small sizes the measured rate is
dominated by fixed per-operation latency and timer granularity. Step 8 reads whole chunks of
1–8 MiB, so this excludes nothing real.

#### Added with it

- `tools/usb-speed-probe/main.swift` — resolves a whole disk to its link speed using the same
  upward recursive registry search `HelperDeviceRegistry` performs. Needed because `ioreg -n`
  **cannot** answer this: a disk's IOMedia entry does not carry the USB device's properties,
  which sit several levels up past the block-storage driver and SCSI peripheral. Verifying
  the real mechanism standalone before wiring it into a root daemon, exactly as `nocache-probe`
  did for the geometry ioctls.
- `scripts/usb-speed-check.sh` — dumps every attached device's code and checks the mapping
  still holds, including the keyboard-reports-0 test that discriminates the two enums. Run it
  after a macOS update, or whenever the cache-bypass check reports something surprising. 3
  PASS / 0 failures on macOS 26.5.2 (25F84).

### Authored 1/6 — `Core/DiskIOControl.swift` (2026-08-02)

The `ioctl` request numbers and the geometry-reconciliation policy. Pure Foundation; the
syscalls that use these constants land later, in the helper's `RawDeviceGeometry.swift`.
Same split as `DeviceAccessPrecondition` (pure decision) against `DeviceClaim` (impure
doing).

**Also edited, no GUI work needed:** `Core/RunParameterValidator.swift` gained
`validateGeometry(_:)`, factored out of `validate(byteOffset:byteLength:geometry:)`. From
Step 7 geometry arrives from two provenances — caller-supplied over XPC, and the helper's own
ioctls — and both must reject the same impossible values. Two copies of that rule would
eventually disagree, and the copy that mattered would be the looser one. Behaviour is
unchanged; the existing suite confirmed it.

**GUI operation done and verified (2026-08-02).** `Core/DiskIOControl.swift` added to
`USBDriveTesterTests` membership. Confirmed by reading `project.pbxproj`: it appears in the
test target's `membershipExceptions` set, the app target gained no exception set, and
`USBDriveTesterUITests` is untouched — exactly the two intended ticks.

**Tests: 238 → 253, 0 failures.** All 15 new `DiskIOControlTests` cases pass. Notable ones:
the four request numbers pinned against the C-measured literals; the `_IOR` encoding asserted
field by field so a failure says *which* part drifted; a test that a `UInt32` out-parameter
produces a *different, unrecognised* request rather than a truncated block count; decision
3a's power-of-two invariant made executable; and `disk8`'s real 42,970,644,479-block geometry
as the NFR-COMPAT-6 fixture, asserting the value a 32-bit truncation would have produced is
**not** the answer.

**`scripts/ioctl-constants-check.sh` added.** The tests guard the *code* against drifting
from the literals; they cannot guard the *literals* against drifting from the SDK, because a
Swift test cannot see a C macro — which is the whole reason this problem exists. This script
compiles `<sys/disk.h>` against the selected SDK and diffs. 9/9 pass on SDK 26.5.

Its own guards were then verified rather than assumed, in all three classes: the SDK
comparison fires when an expected value is corrupted; the assertion check fires when a
literal is deleted from the test file; and a missing source file now reports *"source not
found"* and refuses to report at all. That last one was a real defect found while testing the
guard — grepping a path that does not exist returns no hits, which was being reported as "the
assertion was deleted", sending a reader to the wrong file (NFR-USE-5).

### THE CALIBRATION RESULT: re-read timing cannot discriminate (2026-08-02, `disk4`)

`./scripts/nocache-calibration.sh disk4`, 4 MiB I/O, 4 reads per phase, 0 failures.
**The mechanism FR-TEST-9 was going to use does not work.** Measured, not predicted.

| phase | read 0 | read 1 | read 2 | read 3 |
|---|---|---|---|---|
| unflagged (`F_NOCACHE` not set) | 12,295 µs | 8,829 | 8,786 | 8,737 |
| flagged (`F_NOCACHE` + `F_GLOBAL_NOCACHE`, both `rc=0`) | 8,903 µs | 8,872 | 8,846 | 8,887 |

Reported speed-ups: unflagged **1.41**, flagged **1.01**.

**Why 1.41 is not a cache hit.** A 4 MiB copy from RAM on this machine takes **58 µs**
(71.3 GB/s, measured the same day). A genuine cache hit would therefore have been **~150×**
faster than an 8,800 µs read, not 1.4×. All eight reads sit at ~475 MB/s, which is real
USB 3.1 Gen 2 throughput for a T5 — every one of them went to the device.

**What 1.41 actually is: one-time warm-up.** It is read 0 of the whole process — USB
pipeline spin-up plus first-touch faults on 256 freshly `posix_memalign`'d 16 KiB pages. The
proof is in the second phase: its read 0 targets a **different, never-touched region** and
returns in 8,903 µs with no penalty, because the process was already warm. Had read 0 been a
cold miss followed by cache hits, the flagged phase's first read would have been ~12,300 µs
too. It was not.

**Root cause, now confirmed rather than suspected.** `/dev/rdisk4` is `crw-` — a
**character** device; `/dev/disk4` is `brw-`. The unified buffer cache is a property of the
*block* node. Reads through the raw node were never cached, so `F_NOCACHE` had nothing to
suppress, and its `rc=0` meant exactly as little as the `/dev/null` measurement suggested.

**This is the outcome the probe was written to be able to report.** Shipping a check that
returned `bypassed` on this evidence would have been a check that cannot fail — the precise
defect FR-TEST-9 exists to prevent, reproduced inside FR-TEST-9. Found before a line of the
classifier was written, which is the whole reason the calibration was made a prerequisite.

**The 8 MiB run corroborates the warm-up reading independently, and this is the part that
makes it conclusive rather than merely consistent.** A second run at 8 MiB gave read 0 =
21,686 µs against a steady 17,566–17,765 µs, i.e. a speed-up of **1.23** where 4 MiB gave
**1.41**. The *absolute* first-read overhead barely moved (≈3,560 µs at 4 MiB, ≈4,120 µs at
8 MiB) while the transfer doubled — which is the signature of a roughly fixed start-up cost,
and is why the ratio *fell* as the I/O grew. Caching cannot produce that: a cache hit is
~150× faster irrespective of size (8 MiB from RAM is 117 µs against the 17,566 µs measured).
Two different I/O sizes, the same conclusion, reached from the direction of the ratio moving
the *wrong way* for the caching hypothesis.

#### Two further findings from the same run

1. **`DKIOCGETMAXBYTECOUNTREAD` = 1,048,576 (1 MiB) — smaller than the I/O size, and it does
   not matter.** `extraIterations=0` in every phase of both runs: `pread` returned all
   4 MiB, and then all **8 MiB**, in a single call. The kernel splits the transfer
   internally at up to 8× the device's reported maximum. So `DeviceIOError.shortTransfer` is
   **not a live path on this bridge at either the default or the largest FR-CTRL-8 option**
   (a second run, 2026-08-02, at 8 MiB, confirmed it at the largest). Smaller sizes are
   strictly less demanding. The read loop and its iteration counter stay regardless — this
   is one bridge, and a short transfer remains legal.
2. **Throughput saturates at or before 4 MiB — 8 MiB buys nothing on this device.**
   ~477 MB/s at 4 MiB against ~474 MB/s at 8 MiB, i.e. identical within noise, and both are
   normal USB 3.1 Gen 2 figures for a T5. Relevant to Steps 9 and 11: FR-CTRL-8's 4 MiB
   default is well chosen, and a user selecting 8 MiB should not expect it to be faster —
   it only doubles the buffer pair (NFR-PERF-1) and the in-flight window (NFR-REL-4). Worth
   remembering when Step 9's metrics invite the conclusion that a bigger I/O size is better.
3. **Geometry confirmed on real hardware, pre-validating Step 7's first gate item.** The
   re-derived ioctls returned `logicalBlockSize=512`, `blockCount=1953525168`,
   `byteCount=1000204886016` — matching `diskutil` exactly, and matching the IOKit values
   Step 6 already logged. The `_IOR` derivation is correct through a real USB bridge, not
   merely correct as arithmetic. `DKIOCGETPHYSICALBLOCKSIZE` also returned 512, so this
   drive is not 512e.

#### The replacement mechanism for FR-TEST-9

The **requirement stands unchanged** — its text specifies *what* to verify, never *how*, and
protecting the verify from a vacuous pass is still right. Only the mechanism changes, and the
change is forced by an asymmetry the calibration exposed:

> **Timing can falsify, but it cannot verify.** A read returning 150× faster than the
> transport allows *proves* a cache hit. Two similar timings prove nothing at all, because
> they are identical whether caching was suppressed or was never possible.

So `bypassed` may never rest on timing. It rests on structure:

- **Primary — structural, and checkable.** `fstat(fd)` and assert `S_ISCHR`: the descriptor
  is the **character** device, not the block device. This catches the failure mode that can
  actually occur — opening `/dev/disk4` instead of `/dev/rdisk4`, a one-character bug that
  would silently make every verify vacuous — and it is a fact about the file, not a
  heuristic. Plus: the path opened is the raw node, and both `fcntl` calls returned 0.
- **Secondary — behavioural, falsification only.** During the run, flag `likelyCached` if any
  chunk read returns at a rate the transport cannot produce. Calibrated by this run: RAM is
  71.3 GB/s, the device is 0.475 GB/s — a 150× gap, so a threshold near **2 GB/s** sits ~4×
  above the fastest plausible USB device and ~35× below RAM. Wide and unambiguous.
- Three states as already decided: `bypassed` (structural checks pass, no implausible read
  seen), `likelyCached` (a structural check fails, or an implausible read is seen),
  `inconclusive` (the checks could not be performed).

#### A limit this exposed that belongs to Step 14, not Step 7

None of the above — and nothing available on the host — can establish that the verify read
came from **NAND**. The drive's own DRAM/SLC cache sits below every host mechanism, and a
read-back moments after a write may legitimately be served from it. The verify therefore
proves the data round-tripped through the device's I/O path; it does not prove the medium
retained it. That is a real limit on what a clean pass means, it is not fixable from here,
and it belongs with Step 14's honest framing (FR-WARN-3, "a clean pass is not a healthy
drive") rather than being quietly carried as if the tool proved more than it does.

### Decisions taken (2026-08-02) — all six

Numbered as in the scoping conflict list.

**1. BUILD-PLAN 7.1 reworded: Step 7 opens nothing.** The step instructed Step 7 to open
the raw device; Step 6 already does, in `DeviceClaim.acquire(_:)`, because the open is half
of the mount guard. Followed literally Step 7 would open a *second* descriptor, and closing
it is the hazard — measured 2026-08-01, releasing an exclusive open makes DiskArbitration
re-probe and remount ~4 ms later. "Fail with a precise error if it can't be opened
exclusively" was already discharged by `DeviceAccessPrecondition`.

**2. BUILD-PLAN 7.3 reworded: reconcile against the helper's own IOKit reading**
(`AcquiredDevice.geometry`), not "the values discovered in Step 5". Step 5's discovery runs
in the **app**. Step 6 gave the helper an independent registry read specifically so a root
daemon need not take the app's word about the device it is about to write to (NFR-REL-7);
reconciling against a Step 5 value would re-cross that boundary and let a GUI bug influence
what the helper believes. The comparison is ioctl vs. helper-IOKit, and both are logged.

**3. `validateRunParameters` keeps its caller-supplied geometry; the comments change
instead.** Option A of the two offered. The method's own documentation in
`Shared/TesterControl.swift` and `main.swift` promised that *"from Step 7 the caller-supplied
values are dropped entirely"*. That promise is retired, not kept.

The reason it is safe to retire: **this method authorises nothing.** No I/O passes through
it, no device is touched, nothing is acquired — it answers "would these numbers be
accepted?". It is a calculator, not a gate. The validation NFR-REL-7 is actually about is
the one on the write path, and that uses ioctl-derived geometry under either option, because
the helper's run path never receives geometry over XPC at all: it reads it off
`AcquiredDevice`.

What keeping it buys, and what changing it would have cost:

- The Diagnostics panel keeps demonstrating the validator **with no drive attached** —
  four presets driving the misaligned-offset, out-of-range and overflow rejections against
  a synthetic 2,048-block × 512-byte device (`HelperDiagnosticsView.demoBlockSize` /
  `demoBlockCount`). Making the method device-dependent would have required a drive
  attached *and* claimed before any of that could be shown.
- Step 7's protocol change stays **purely additive**, and Step 7 stays **helper-side only**
  as FR-ARCH-6 requires — no app-target source changes. Option B would have pulled
  `HelperConnection.swift` and `HelperDiagnosticsView.swift` into the step.

**Action:** rewrite both doc comments to state what the method actually is — a diagnostic
that validates against *caller-supplied* geometry — with a pointer to where the real
write-path validation happens. A stale comment claiming otherwise is worse than none.

**3a. Supported logical block sizes stay the explicit allowlist `{512, 4096}`.** Raised
during this decision: should the rule instead be "any even multiple of 512"? No — that rule
is **not sufficient**, which is the point that settles it. The design needs
`ioSize % blockSize == 0` for every offered I/O size, and those are 1/2/4/8 MiB, all powers
of two. A 1536-byte block size is an even multiple of 512 and divides none of them: every
run would fail deep inside `ChunkPlanError.ioSizeNotBlockAligned` instead of being refused
cleanly at the geometry check. The true structural invariant is **a power of two between
512 B and 1 MiB**.

The allowlist is kept even so, in preference to that broader invariant, because it is
exactly NFR-COMPAT-5's floor and the only two values that can be tested. BUILD-PLAN Step 7's
risks say to *"trust the ioctl and reject impossible values"*; a bridge reporting 1024 is far
likelier to be broken than to be a genuine 1024-byte-sector device, and accepting a geometry
never validated against is the substitute-for-the-real-thing pattern in requirement form.

Two consequences to implement:

- The power-of-two invariant becomes an **executable test**, not a comment: every member of
  `DeviceGeometry.supportedBlockSizes` must be a power of two dividing all four offered I/O
  sizes. A careless future `1536` then fails a test rather than shipping.
- **Physical** block size (`DKIOCGETPHYSICALBLOCKSIZE`, `0x4004644d`) is read and **logged
  only — never branched on.** Correctness depends solely on the *logical* size, which is
  what the kernel enforces alignment against; physical size affects performance only (on a
  512e drive, logical 512 / physical 4096, a write unaligned to 4096 forces a
  read-modify-write inside the drive). It costs one ioctl and would explain an otherwise
  baffling Step 9 throughput result.

**No FR/NFR amendment is required for 3a** — NFR-COMPAT-5 already says "at least 512-byte
and 4096-byte", and this is an implementation invariant beneath it.

**4. Bounded memory is the final design, and it binds more than the buffers.** User
decision, verbatim: *"peak buffer memory ≈ 2×ioSize is the correct and final design. I do
not want memory to scale with capacity."*

The buffers were never the problem. `RetentionTestEngine.chunkPlan()` returns a
materialised `[Chunk]`, which is **9.1 MiB for `disk4` and 200.1 MiB for `disk8`** — memory
scaling linearly with capacity, straight past NFR-PERF-2, and it survived because the gate
item says "peak *buffer* memory" and the buffers genuinely were bounded. The gate wording
in BUILD-PLAN and above is now widened to *no run-state structure scales with capacity*,
which also constrains Step 9's metrics and Step 10's bad-block report to bounded summaries
rather than per-chunk records. The plan becomes a lazily-computed `Sequence`; the array
survives as a test convenience. **This also settles the "lazy plan now?" question — yes.**

*Also confirmed, because it was queried:* the I/O-size control is **unchanged and not
lost**. FR-CTRL-8 specifies a dropdown of 1 / 2 / 4 / 8 MiB, default 4 MiB, set before a run
and fixed for its duration; BUILD-PLAN Step 11.2 builds that control. Step 7 only *consumes*
`ioSizeBytes` as a parameter, exactly as BUILD-PLAN 7.5 says ("passed in"), which is what
lets the unit tests drive deliberately awkward sizes the dropdown will never offer.

**5. The `F_NOCACHE` check becomes a run-start self-check that qualifies the result, not a
gate artefact — and it becomes a requirement (FR-TEST-9, M, added 2026-08-02).**

Offered as three options (checked `fcntl` only / timed double-read / double-read plus a
calibration control). The user chose the double-read and then **improved it**: rather than
proving the mechanism once at gate time, run the check *at the start of every run*, and if
it fails, have the app report and warn that the compare function may be compromised —
letting the run proceed, because the read → write-back still refreshes the medium, which is
a key project goal.

That is strictly better than what was proposed, for two reasons worth recording. It proves
the property on **every run, on the actual device, at the actual I/O size**, rather than once
on one drive. And it converts a binary pass/fail into a *qualification of the result*, which
is more honest than either blocking the run or proceeding silently — the two halves of the
product fail independently, and a cached read does not stop the write-back reaching the
device. Requirement text, rationale and consequences: FR doc, Amendments, 2026-08-02.

**Two corrections applied to the proposal as stated.**

1. **The polarity was inverted.** `F_NOCACHE` *working* means both reads reach the device and
   take **similar** times; `F_NOCACHE` *not* working means the second read is served from RAM
   and is much **faster**. So a large speed-up on the re-read is the warning condition, and
   similar durations are the healthy result. As originally worded the warning would have
   fired exactly backwards.
2. **The check's discriminating power is unproven, and may be nil.** `/dev/rdiskN` is the
   **character** device and is inherently unbuffered — which is precisely why FR-TEST-6
   specifies it over `/dev/diskN`. `F_NOCACHE` / `F_GLOBAL_NOCACHE` are belt-and-braces on a
   path that is probably already uncached, so the two timings may match *whether or not the
   fcntls did anything*, and the check would pass vacuously. That is the same defect shape it
   exists to catch. Stated as a prediction, not a measurement.

**Consequence: the calibration probe is a prerequisite, not optional polish.** It was offered
as optional (option C) and is now required, because it is the only thing that answers both
open questions at once — whether the timing test can discriminate at all, and what the
numeric thresholds for "similar" versus "much faster" actually are on this hardware.
Approved by the user 2026-08-02: *"I am willing to run a calibration probe on `disk4` as
needed to establish thresholds based on real world testing."* Thresholds will be recorded
with their provenance; none are to be invented.

**Build order this forces.** `tools/nocache-probe` + `scripts/nocache-calibration.sh` are
authored **first**, before `Core/CacheBypassCheck.swift`, so the classifier is written
against measured numbers rather than adjusted to them afterwards.

**Design notes settled with it.**

- The classifier has **three** states — `bypassed` / `likelyCached` / `inconclusive` —
  matching `FullDiskAccessState` and `HelperShutdownReadiness`. "Could not tell" must never
  collapse into either answer, and a device fast enough that timing noise dominates must
  report `inconclusive` rather than a verdict.
- The self-check reads a chunk from the **middle of the device, not chunk 0**. Block 0 is
  the GPT and partition table — the region the OS has most recently touched, so its "first"
  read is the least likely to be genuinely cold.
- Step split: **Step 7** builds the pure classifier and the helper-side timing harness;
  **Step 8** calls it at run start and gates the verify result on it; **Step 10** carries the
  qualification into the exported Markdown report; **Step 11** surfaces it in the UI.

**5a. The XPC surface does grow — protocol v4 → v5, purely additive.** This was left open
during scoping. The hesitation was NFR-SEC-3: a privileged method whose only caller is the
gate harness is not "necessary to perform its function". FR-TEST-9 dissolves that — the
result is now a product signal the app is *required* to display. Two methods, both requiring
a held device and refusing cleanly otherwise:

- `deviceGeometry(reply:)` — **passive.** Reports what acquire already established: the
  ioctl geometry and the helper's IOKit geometry, so the gate compares each against
  `diskutil info` and the reconciliation of decision 2 is directly observable.
- `checkCacheBypass(reply:)` — **active.** Performs the two timed reads on the held
  descriptor and returns the classifier's state plus both durations.

Two methods rather than one because mixing a passive accessor with an operation that
performs I/O reads fine now and confuses badly by Step 11.

**6. `disk4` only.** User decision: *"I only want to use `disk4` for testing for now, unless
there is an important test case that cannot be satisfied with `disk4`."* `disk8` is not part
of this gate.

One case that genuinely cannot be satisfied by `disk4` was identified and carried: NFR-COMPAT-6.
`disk4` is below 2³² blocks, so a bridge truncating its block count to 32 bits would be
invisible there, and the failure mode is silent — the tool would test the first portion of a
larger drive and report a clean pass. Unit tests cover the 64-bit arithmetic at full scale
using `disk8`'s real geometry as a fixture; what had no evidence was a real bridge reporting a
>2³² count.

> **CLOSED later the same day (2026-08-02), on user instruction: "verify on disk8 that we can
> address above the 32-bit boundary… before we begin Step 8."** `scripts/large-address-check.sh
> disk8` passed 10/10 — read-only, nothing unmounted. See the Step 7 COMPLETE summary. `disk8`
> remains outside every other gate; a specific case still has to be named and agreed before it
> is used again.

---

## Step 8 — COMPLETE (2026-08-03)

Every gate item discharged. **The first bytes this project has ever written to real media were
written during this step, and the drive is byte-identical afterwards.**

**Delivered.** The cycle at the heart of the tool — read a chunk, write the *same* bytes back,
read them again, compare — over any `RawBlockDevice`, so the identical code path runs against the
simulated device and against `/dev/rdisk4`. With it: block-narrowed verify failures; a bounded,
coalescing failure log; a `LoadedChunk` token that makes "write after a failed read" unexpressible;
a per-chunk NFR-REL-3 guard that stops the *next* write when access goes away; FR-TEST-9's verdict
seeded at acquire and fed the run's own throughput; protocol **v7**; and a hardware gate that
fingerprints a terabyte either side of the write.

**Final state.** **403 tests, 0 failures.** Zero warnings from clean **Debug**, clean **Release**
*and* a clean **test-target** compile, DerivedData wiped before each.
`./scripts/ioctl-constants-check.sh` **11/11** (was 9/9).
`./scripts/retention-cycle-check.sh disk4` **15/15**.

**Requirements affected.** None added. Five BUILD-PLAN amendments (8.8's wording, the `F_NOCACHE`
risk line, gate items 4 and 5, plus new detailed steps 9–11), and a new Step 9 obligation to
measure helper CPU against throughput (NFR-PERF-3, which had never had a number attached).

### The hardware result

`retention-cycle-check.sh disk4`, placement block **277,372,928** — drawn at random from 238,212
chunk-aligned positions:

| | |
|---|---|
| chunks | **256** — 255 full + one short (FR-TEST-5 on real media) |
| failed ranges | **0** |
| cache bypass at end | **1 = `bypassed`** (FR-TEST-9 survived real I/O) |
| fastest read | **492,870,060 B/s** — transport-plausible, not RAM-plausible |
| buffers held | **8,388,608 B** = 2 × I/O size (NFR-PERF-1) |
| fingerprint coverage | **932 windows, 1,000,204,886,016 bytes — exactly the device's size** |
| before vs after | **byte-identical** |

Verified independently of the script: **0 of 932 windows are all-zero** and **932 of 932
fingerprints are distinct**, so a stray write anywhere on the drive would have moved a window.

### What this step cost, and what it bought

**Seven defects, all found before they could mislead.** Four in the code, three in the gate — and
the gate ones were the dangerous kind, because a gate that passes wrongly is worse than no gate.

1. The engine reset a **process-global** counter (`ChunkBuffers.peakAllocatedBytes`), clobbering a
   Step 7 suite running concurrently. Production code must not mutate shared instrumentation.
2. **Parallel testing made global-counter assertions unsound.** Three green runs after fixing (1)
   were not evidence. Loosening was rejected — *no* assertion on a global counter is immune to
   concurrent mutation — and the suite was serialised instead: 9.7 s → 18.8 s, measured.
3. The gate script planned a run at block **−893,534,208**: `od -N8 -tu8` yields 64 unsigned bits
   and **bash arithmetic is signed**. Caught by a dry run that aborts before unmounting.
4. The first hardware run failed on `EACCES`, and the check **reported it as `EBUSY`'s meaning** —
   asserting a conclusion its evidence did not support, the same conflation Step 6 untangled.
5. The content check parsed **`awk '{print $4}'` — the block count, not the fingerprint.** It
   would have reported "2 distinct values" on any drive, empty or full, forever.
6. `disk4` was **1% used**, so a random placement tested a region of pure zeros. Writing zeros
   over zeros is non-destructive however wrongly it is addressed.
7. The client's stdout was **block-buffered through `tee`**, so an hour-long run reported no
   progress at all. Invisible until a run lasted longer than ten seconds.

**One measurement changed the design.** `O_EXLOCK` held by the helper refuses a second
`O_RDONLY` open — `EBUSY`, even for root with Full Disk Access requesting no lock. Not in the
2026-07-30 matrix, which only tested `O_EXLOCK` against `O_EXLOCK`. It made the planned
"fingerprint from a separate process" impossible and moved the digest into the helper as protocol
v7. The pre-flight that caught it was written **before** the gate design was committed to;
assuming it would have produced a gate failing ~40 minutes in, immediately after the first write
to real media, with no way to tell "the digest could not be taken" from "the device changed".

**The lesson, in this step's own words.** Defects 5 and 6 are one failure wearing two faces: a
gate reported **15 checks, 0 failures** over a region of zeros, with a check that had never once
looked at a fingerprint. Both had been *anticipated* — the source comment said "an all-zero region
legitimately repeats" — and shipped anyway. **A comment acknowledging a hole is not a check; it
is a note explaining why the check does not work.** The replacement samples three chunks from
inside the tested range before anything is written and requires their fingerprints to differ, and
it reads its input from an unambiguous source rather than positionally from a file whose columns
must be remembered correctly.

**And the fix for the vacuity risk cost nothing on hardware.** With both fingerprints taken by one
process, a digest returning a constant would make "before == after" pass unconditionally. That was
closed entirely in simulation: `Core/DeviceDigest` is pinned against **externally computed**
SHA-256 vectors — every constant from Python's `hashlib` over the same bytes, never from running
the Swift code and recording its output.

**Carried into Step 9.**

- `RunObserver` already carries per-chunk `ChunkTiming`; Step 9 builds throughput and latency from
  it. Step 8 computes **no** statistics — it times reads only to feed FR-TEST-9's falsifier.
- `FailureDisposition` is the seam Step 10 fills with FR-FAIL-1/2/3's user-selectable modes.
  Step 8 ships one caller, which always continues.
- **Measure helper CPU against throughput (NFR-PERF-3).** Never numbered. The 36–39% of one core
  observed at ~500 MB/s during this gate is the *fingerprint*, which is not in the product; the
  cycle's per-chunk `memcmp` is expected to be far cheaper and is **unmeasured**.
- `runRetentionCycle` and `digestRange` are both capped at 1 GiB per call because there is no
  cancellation until Step 11. Step 11 replaces the first with real run control.

**Not discharged by this step, and not to be mistaken for covered:** the final chunk at the
**physical end** of the device, and a whole-device traversal. Neither is reachable under the
"1 GiB clear of the end" rule. Both belong to a later, separately agreed run — the `disk8`
precedent.

---

## Step 8 — scoping, decisions and authoring log

**AI-6 / satisfies FR-TEST-1/3/4/7/8; FR-FAIL-6/7; NFR-REL-1/2/4/8; and FR-TEST-9's caller.**
**Helper-side core** — runs identically against the simulated device.

Recorded here so a cold start has the state without re-deriving it from the log above.

### State this step begins from

- **Steps 1–7 complete.** Step 7 committed at `e0fdea2`, docs convention at `d1259d9`;
  `git` clean on `main`.
- **Protocol v5.** `ping`, `protocolVersion`, `validateRunParameters`, `prepareForShutdown`,
  `checkDeviceReadiness`, `acquireDevice`, `releaseDevice`, `deviceProfile`.
- **323 tests, 0 failures.** Zero warnings from clean Debug **and** clean Release builds.
- **The installed helper is v5**, registered from `/Applications`, with Full Disk Access
  granted. Re-registering does not prompt on this machine; a clean Mac will.
- Hardware gates passing: `geometry-check.sh disk4` 9/9, `large-address-check.sh disk8` 10/10,
  `claim-contention-test.sh disk4` 12/12. Guard scripts: `ioctl-constants-check.sh` 9/9,
  `usb-speed-check.sh` 3/3.

### What Step 7 hands over

- **`AcquiredDevice.blockDevice()`** — vends a `FileDescriptorBlockDevice` over the held
  descriptor using the **authoritative** (ioctl-derived, reconciled) geometry. Returns `nil`
  once released. Built on demand rather than stored, so it cannot outlive the descriptor.
- **`AcquiredDevice.deviceGeometry`** — the authority. `AcquiredDevice.geometry` is IOKit's
  and is **provisional**; it is kept only for comparison and the log.
- **`AcquiredDevice.cacheBypass`** — the FR-TEST-9 verdict established at acquire. Step 8
  seeds a `CacheBypassAssessment` from it *plus* `AcquiredDevice.usbLinkSpeed`, then feeds each
  chunk's throughput in via `observe(bytes:nanoseconds:)`. That can only ever downgrade.
- **`RetentionTestEngine.chunks()`** — the **lazy** plan, and what a run must iterate.
  `chunkPlan()` still exists but materialises: 9.1 MiB for `disk4`, 200.1 MiB for `disk8`. It
  is for tests and diagnostics only.
- **`ChunkBuffers`** — the two page-aligned buffers, allocated once and reused. `original` is
  buffer A and is the **only copy of the user's data** during the write, which is exactly what
  bounds NFR-REL-4's in-flight window to one chunk. `original(byteCount:)` / `verify(byteCount:)`
  give the short prefix the final chunk needs.
- **`WritePrecondition.check(_:writingTo:)`** — the NFR-REL-3 runtime guard. The compile-time
  half is that the write path takes an `AcquiredDevice`, which only a successful acquire can
  produce.
- **`InMemoryBlockDevice`** — fault injection (`injectReadFault`, `injectWriteFault`,
  `injectSilentCorruption`) and `snapshot()`, all from Step 2 and all still unused. Step 8's
  gate is what finally exercises them.

### Hazards that will bite Step 8 specifically

1. **This step writes the first byte to real media.** Everything before it was read-only.
   NFR-REL-1 requires non-destructiveness proven **in simulation first**, and the gate is
   ordered that way deliberately — the `disk4` run is the *last* item, not the first.
2. **A torn write to the GPT or a superblock can brick an otherwise-good drive.** `disk4`'s
   contents are expendable; the *time* spent re-creating a test volume is not, and the point
   generalises to a user's drive.
3. **The verify must not be vacuous.** If buffer A and buffer B ever alias, or the write does
   not truly precede the verify read, the comparison passes for every chunk of every drive.
   `ChunkBuffersTests.theTwoBuffersAreDistinctMemory` guards the first; ordering guards the
   second; FR-TEST-9 guards the third (host caching).
4. **FR-TEST-7 is absolute: write back the bytes that were read, never a pattern.** A
   known-value write would be a faster, easier test and would destroy user data.
5. **One chunk in flight (NFR-REL-4).** Never hold more than the current chunk's original.
   Anything that accumulates — a list of chunks processed, per-chunk timings kept for later —
   reintroduces the capacity-scaling NFR-PERF-2 forbids and Step 7 removed.

### The gate (from BUILD-PLAN)

- [ ] Non-destructiveness proven in simulation (NFR-REL-1): known random data, full cycle,
      backing store bit-for-bit identical afterwards.
- [ ] Verify-mismatch detection (NFR-REL-8): corruption injected on a range flags exactly
      that range and no other.
- [ ] Hard-error classification (FR-FAIL-6): read-error and write-error injection produce
      correctly-typed `BlockRangeFailure`s.
- [ ] One-chunk-in-flight (NFR-REL-4) confirmed by instrumentation.
- [ ] The cycle runs end-to-end against `disk4` and leaves its contents unchanged
      (checksum before == after). **Only after the simulation proof passes.**

### Scoping decisions (2026-08-02, user decisions) — APPROVED

Seven decisions were put to the user with recommendations; all seven were taken as
recommended, two with constraints the user supplied that changed the design.

**D1 — how the hardware gate drives the cycle: a bounded XPC method on the real helper**
(protocol **v5 → v6**), not a standalone `sudo` probe. A probe would compile the identical
engine but bring its own descriptor, its own acquire and its own geometry — a substitute for
the helper on the one run where the first byte is written to real media, which is the exact
mistake this project's standing lesson describes. The method is **capped by construction**
because there is no cancellation until Step 11 and no progress channel until Step 9: an
uncancellable privileged operation that a caller can start must be bounded, or a root daemon
can be wedged for hours with `prepareForShutdown` correctly refusing throughout.

**D2 — how much of `disk4` to write, and where. User constraints, which supersede the
three-segment proposal that was offered:**

> *"I really don't care about any data on disk4. If data corruption occurs, I'll reformat the
> drive. Since we are unable to cancel a test run until Step 11, for now I want the test to
> limit itself to 1 GiB worth of LBA's and then stop the test as if the test were completed.
> That's 3 GiB total of i/o's (R+W+R) with at least an average speed of 200 MiB/sec so the
> test run should complete in less than 15 seconds. Start at a random LBA (to minimize NAND
> wear) that is a multiple of 1024 and at least 1 GiB before the logical end of the drive so
> we don't hit the end of the drive during the test."* — user, 2026-08-02

Three consequences, none of them cosmetic:

1. **The bound is expressed as the plan, not as an early stop.** "Stop as if the test were
   completed" is exactly what happens when the engine is handed a plan covering only that
   range and runs it to the end. So `ChunkPlan` gains a `startBlock` and the engine keeps its
   single behaviour — *complete the plan you were given*. No stopped-early state is needed for
   the gate, and FR-TEST-1/4's whole-device traversal remains the default (`startBlock = 0`,
   the whole device) rather than becoming one option among several.
2. **A chunk-index range cannot express the requirement.** An arbitrary start LBA is not in
   general a multiple of 8,192 (one 4 MiB chunk at 512-byte blocks), so the earlier proposal —
   a range of chunk indices over the whole-device plan — was discarded before it was written.
   `ChunkPlan.startBlock` accepts **any** block-aligned start, so this constrains the design
   rather than the parameters.

**Start alignment revised to 8,192 blocks (user decision, same day).** The original instruction
said a multiple of 1,024. `ChunkPlan.startBlock` handles either, so this is not forced by the
code — it is chosen, for one reason: **8,192 blocks is where a real whole-device run's chunks
actually land.** A gate that writes at offsets production will never use is testing something
production does not do, and this project has already paid for substituting a nearly-right thing
for the real one. What it costs: a start that is *not* on a whole-device chunk boundary is no
longer exercised on hardware. That path is `ChunkPlan.startBlock`'s arithmetic, it is covered
exhaustively in simulation where it can be checked at every offset rather than one random one,
and it is not a property of the drive.

**The gate's numbers on `disk4`, computed rather than assumed:**

| | |
|---|---|
| Device | 1,953,525,168 blocks |
| Run length | **2,096,128 blocks** (1,023.5 MiB) — 255 full 4 MiB chunks + a final chunk of **7,168 blocks (3.5 MiB)** |
| Start | a multiple of **8,192**, chosen at random from **238,212** positions: 0 … **1,951,424,512** (238,211 × 8,192) |
| Ceiling | the user's rule — start no later than 1 GiB before the logical end (1,953,525,168 − 2,097,152 = 1,951,428,016), floored to the alignment |
| Margin at the latest start | run ends at 1,953,520,640, leaving **4,528 blocks** |

Note that block 0 is a legal draw, so a run may land on the GPT and the exFAT boot sector.
That is deliberate and is covered by the user's position that `disk4`'s contents are
expendable — it is also the one region where hazard 2 ("a torn write to the GPT can brick an
otherwise-good drive") is a live case rather than a hypothetical. The script prints the drawn
start before it writes anything, and says whether the run overlaps the first 34 blocks.
3. **The cap is 1 GiB**, and the `mount-guard-client` reply timeout goes from 30 s to 300 s.
   At the user's 200 MiB/s floor the call takes 3,072 MiB ÷ 200 MiB/s ≈ **15.4 s**, which is
   under the existing 30 s but not by enough to survive a struggling drive; at the measured
   475 MB/s it is ≈6.8 s.

**The range is 1 GiB − 512 KiB, not 1 GiB — a judgment call taken, and reversible.**
2,096,128 blocks: 255 full 4 MiB chunks **plus a final chunk of 7,168 blocks**. 1 GiB divides
by 4 MiB exactly, so a full 1 GiB range would contain no short final chunk, and the
"at least 1 GiB before the logical end" rule means the gate never reaches the end of the
device either. FR-TEST-5's short-chunk path — `original(byteCount:)` / `verify(byteCount:)`,
and whether the bridge accepts a **write** that is not a full I/O size — would then run only
in simulation. Shortening the range by 512 KiB exercises it on real media, stays inside the
user's 1 GiB ceiling, and stays 1,024-block aligned. Cost: nothing.

**What this gate deliberately does NOT discharge**, recorded so it is not mistaken for
covered: the final chunk **at the physical end of the device**, and the whole-device
traversal. Neither is reachable under the 1-GiB-clear-of-the-end rule. Both belong to a
later, separately agreed run — the `disk8` precedent from Step 7.

The start LBA is chosen by the **script**, not the helper — a root daemon has no business
owning a "pick somewhere to write" behaviour — and is printed and recorded, so a failure can
be re-run at the same place. Bounds on `disk4`: `blockCount` is 1,953,525,168, so the start
must be a multiple of 1,024 no greater than 1,951,427,584 (1,953,525,168 − 2,097,152, floored
to a multiple of 1,024), which leaves 432 blocks of margin beyond the user's rule.

**D3 — evidence that nothing changed: a per-1-GiB SHA-256 vector plus a whole-device digest,
taken twice, both inside the claim window.** The vector costs the same I/O as a single scalar
digest and localises any difference to a 1 GiB window instead of merely asserting one exists.
~35 min per pass on `disk4`, so ~70 min for the pair. Both digests must be taken while the
helper still holds the claim: release makes DiskArbitration remount ~4 ms later, and a mounted
exFAT volume writes to itself, so an "after" digest taken post-release would differ for
reasons that have nothing to do with this tool.

> *"if it is better to develop and run a test tool before deciding, let's do that"* — user

**So `tools/media-digest` is built and run BEFORE the gate design commits to it**, and its
first job is a fact this log does not contain: **can a second process
`open("/dev/rdisk4", O_RDONLY)` while the helper holds `O_EXLOCK`?** The 2026-07-30 matrix
records that two plain `O_RDWR` opens both succeed and that a second `O_EXLOCK` is refused —
but not that combination, and the whole digest ordering above rests on it. Read-only, nothing
unmounted, nothing written. If it fails, the fallback is for the helper to compute the digest
through its own descriptor, which is more work and is worth discovering now rather than at the
gate.

**D4 — verify mismatches narrow to contiguous failing block sub-ranges** within the chunk,
paid only on mismatch. Gate item 2 requires the injected range to be flagged "and no other";
at chunk granularity a 4-block injected corruption inside an 8,192-block chunk flags 8,192
blocks, which does not satisfy that wording and would make Step 10's report far less useful.
Hard read/write errors stay **chunk-granular**: the syscall failed for the whole request, and
narrowing there would invent precision the device never gave us.

**D5 — a minimal `.continueRun` / `.stopRun` disposition now.** Without a stop path, detailed
step 6 (NFR-REL-5, "on stop, issue no further writes") has nothing to test. Step 8 ships one
caller, which always continues. The user-selectable **modes** — FR-FAIL-1/2/3/4 and their
default — remain Step 10's.

**D6 — Step 8 times both reads and feeds both into `CacheBypassAssessment.observe()`.** The
**verify** read is the load-bearing one: it is the read a host cache would answer, so feeding
only the original read would systematically miss the very signal FR-TEST-9 exists to catch. No
min/max/p99 and no throughput averages — that is Step 9. The clock is injected
(`clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` by default), which is what makes the falsifier
testable: a fake clock returning 0 ns must drive the run's verdict to `likelyCached`.

**D7 — `DKIOCGETMAXBYTECOUNTWRITE` (request 71) is added** alongside the existing read
constant, diagnostic only, with a line in `ioctl-constants-check.sh`. Step 7 established that
`disk4` advertises a 1 MiB maximum **read** and still answers a 4 MiB and an 8 MiB `pread`
whole. The write side is unmeasured and `shortTransfer` on the write path has never executed
anywhere, on any device, in any test. If a real write ever comes back short, this is the first
number anyone will want.

### Tooling note (2026-08-02) — `xcresulttool` reports TWO test counts

Found while taking a baseline before Step 8's tests were written, and recorded because it
produced a phantom regression: a run that had changed nothing appeared to gain 17 tests.

`xcrun xcresulttool get test-results summary` emits **two different counts**, and the
misleading one comes first:

| Where in the JSON | `disk4` baseline, 2026-08-02 | What it counts |
|---|---|---|
| `passedTests` **inside** `devicesAndConfigurations` | **340** | executed test *cases* |
| top-level `totalTestCount` / `passedTests` | **323** | `@Test` *declarations* |

Confirmed against the source: `grep -rh '@Test' USBDriveTesterTests/*.swift` counts exactly
**323**, of which **6** are parameterised — and those 6 expand to 23 executed cases, which is
the whole of the 17-case difference. The Step 7 run's bundle reports the identical 340/323
pair, so nothing had changed.

**Use the top-level `totalTestCount`.** That is the measure Step 7's "323" refers to and the
one to keep quoting.

⚠️ **Step 6's "235 test cases (226 `@Test` declarations)" is the *other* measure** — it
headlined executed cases. So 235 → 323 is not a like-for-like comparison, despite Step 6's note
claiming its figure was chosen to make exactly that comparison safe. Step 6's declaration count
(226) is what lines up with 323.

### A sixth hazard, added 2026-08-02 — stale buffer contents

The five hazards recorded above do not cover this one, and it is the worst thing this step can
do.

**The buffers are reused, so a failed original read must never be followed by a write.** If
chunk *n*'s read fails and control falls through to the write, `ChunkBuffers.original` still
holds **chunk *n−1*'s data**, and the engine writes the previous chunk's bytes to this chunk's
offset. That is silent, permanent corruption of a region the tool was asked to preserve, on a
drive whose every other block verifies clean — and it is one missing `continue` away. Hazard 3
does not cover it: that one is about aliasing and ordering, this one is about **staleness**.

Made structurally impossible rather than guarded by control flow: the read step returns a
`LoadedChunk` token, produced **only** on a successful read and carrying the chunk and its byte
count, and the write step takes that token. There is then no expressible path from a failed
read to a write. The test injects a read fault on chunk *n* and asserts the backing store at
chunk *n*'s offset is **untouched** — not merely that a failure was recorded.

The same shape one step later: **a failed write must not be followed by a verify read.**
Reading back after a failed write compares buffer A against the *old* data and reports a
spurious verify mismatch on a chunk whose actual fault was the write. A write failure ends the
chunk.

### Bounded failure accumulation (NFR-PERF-2, decided during scoping)

`RunSummary` cannot hold an unbounded `[BlockRangeFailure]`: a device with millions of bad
blocks would reintroduce exactly the capacity-scaling growth Step 7 removed from the chunk
plan. So failures are **coalesced on append** (same kind, contiguous blocks) and the retained
list is **capped**, with the total count and a `truncated` flag carried separately. The cap is
reported rather than silent — a truncated list that does not say so reads as a complete one,
which is the same class of defect as a report line that appears only on failure. Coalescing
also discharges part of Step 10's "coalesce contiguous failing chunks into ranges, but don't
lose a non-contiguous failure" risk note.

### Conflicts with Step 7's findings — RESOLVED (2026-08-02, user instruction)

> *"resolve Step 8 conflicts based upon Step 7 learnings"* — user

BUILD-PLAN Step 8 is amended in five places, all 2026-08-02:

1. **8.8 said "call the Step 7 mechanism" before the first chunk. There is nothing to call.**
   FR-TEST-9's check runs at **acquire**, inside `DeviceClaim`, and its verdict is already on
   `AcquiredDevice.cacheBypass`. Step 8 *seeds* from it; it does not invoke it. That is not a
   shortcut — the check is `fstat` plus the two `fcntl` results on the descriptor, and Step 7
   measured that opening the raw node speculatively to answer a query makes DiskArbitration
   remount the volume ~4 ms later. Amended to *performed at acquire, consumed at run start*,
   which is sound because the acquire holds the descriptor continuously between the two.
2. **The risks section said "Step 7's `F_NOCACHE` is what makes the verify meaningful".
   Step 7 measured that this is false.** `/dev/rdiskN` is the character device, the buffer
   cache belongs to the block node, and `F_NOCACHE` had nothing to suppress. What makes the
   verify meaningful is that the descriptor **is** the character device. Left as written, that
   line points the next reader at the wrong mechanism and would justify re-proposing the timing
   check the calibration probe already killed.
3. **Gate item 5 was under-specified for a 1 TB device** — replaced with the bounded
   random-placement run and the digest vector of D2/D3.
4. **Gate item 4's instrumentation half-exists.** `ChunkBuffers.peakAllocatedBytes` (Step 7)
   covers the *buffer* half. What it cannot see is the hazard NFR-REL-4 actually names — a
   second chunk's original being held, or per-chunk state accumulating beside bounded buffers.
   That needs an **ordering** proof, and by this project's rule the checker must be shown
   capable of failing before its passing is believed.
5. **`chunkPlan()` must not appear in the run path or in any many-chunk test** — it is the
   9.1 MiB / 200.1 MiB materialised path. Stated because it is still the more convenient API
   and the Step 2 tests use it.

### Approved file plan (2026-08-02) — NOT YET AUTHORED

Author in this order: pure logic and its tests first, then the privileged side, then the
tooling, then hardware. The Step 5/6/7 order, and also the gate's order — the simulation proof
comes before the first byte reaches real media.

**Core** — `com.arc3solutions.USBDriveTester.Helper/Core/`
- `RetentionRun.swift` *(new)* — the run's vocabulary: `BlockRangeFailure` +
  `FailureKind { readError, writeError, verifyMismatch }` (FR-FAIL-6); `RunSummary` with the
  bounded, coalesced failure list; `RunObserver` (so Core emits events and the **helper** does
  the `os_log`, keeping Core pure); `FailureDisposition`; `RunAbort` for engine faults that are
  **not** device failures; the injected monotonic clock.
  ⚠️ **Needs an Xcode target-membership tick** for `USBDriveTesterTests`, exactly as the
  Step 2/3/6/7 Core files did. It is the only GUI action Step 8 requires.
- `RetentionTestEngine.swift` *(edit)* — `ChunkPlan.startBlock`; `run(...)`: the per-chunk
  cycle over `chunks()`, the `LoadedChunk` token, per-chunk `WritePrecondition.check`,
  block-narrowed mismatch scanning, `CacheBypassAssessment` seeding and `observe()`.
- `DiskIOControl.swift` *(edit)* — `DKIOCGETMAXBYTECOUNTWRITE` (request 71), diagnostic.

**Helper** — `com.arc3solutions.USBDriveTester.Helper/`
- `RunCoordinator.swift` *(new)* — bridges `AcquiredDevice` → engine: allocates
  `ChunkBuffers`, seeds the assessment from `cacheBypass` + `usbLinkSpeed`, supplies the grant
  provider, enforces the 1 GiB cap, `os_log`s run start and each failed range — never contents
  (NFR-SEC-6) — and returns the summary.
- `main.swift` *(edit)* — the v6 method.

**Shared** — `USBDriveTester/Shared/`
- `TesterControl.swift` *(edit)* — protocol **v5 → v6**:
  `runRetentionCycle(startBlock:blockCount:ioSizeBytes:)`, replying with
  `(ok, chunksProcessed, failureCount, firstFailureSummary, cacheBypassCode,
  fastestBytesPerSecond, peakBufferBytes, message)` — every parameter ObjC-representable, as
  the rest of the protocol is.

**Tests** — `USBDriveTesterTests/` (auto-join; no ticks)
- `RetentionCycleTests.swift` — the four simulation gate items plus the stale-buffer, write-
  failure, grant-revocation, stop-path and falsifier cases.
- `ChunkCycleAudit.swift` — test support: a `RecordingBlockDevice` decorator and the **pure**
  checker over the recorded operation sequence.
- `ChunkCycleAuditTests.swift` — feeds the checker hand-built **bad** sequences (write before
  read, verify read before write, two chunks open at once, missing write) and asserts it
  rejects each. Without this file the audit is a check that cannot fail.

**Tooling** — `tools/`, `scripts/`
- `tools/media-digest/main.swift` *(new)* — one pass over an `O_RDONLY` descriptor emitting a
  SHA-256 per 1 GiB window plus a whole-device digest. It takes a path, so pointing it at a
  temporary file and flipping one byte is its canary — the same shape as Step 7's assertion
  that a temp file *accepts* the misaligned read the device refuses. **Built and run first**,
  for the `O_RDONLY`-under-`O_EXLOCK` measurement.
- `tools/mount-guard-client/main.swift` *(edit)* — a `cycle:<startBlock>:<blockCount>` command
  and a 300 s reply timeout for it.
- `scripts/retention-cycle-check.sh <disk>` *(new)* — the hardware gate.
- `scripts/ioctl-constants-check.sh` *(edit)* — the request-71 line.

### Authored so far (2026-08-02) — the simulation half is DONE

**Core, and its tests, complete and green. Nothing has touched real media.**

| Authored | State |
|---|---|
| `Core/RetentionRun.swift` | new; target-membership tick applied and verified in `project.pbxproj` |
| `Core/RetentionTestEngine.swift` | `ChunkPlan.startBlock` + `run(...)` |
| `Core/DiskIOControl.swift` | `getMaxByteCountWrite` (request 71) |
| `USBDriveTesterTests/ChunkCycleAudit.swift` | recorder, pure checker, `SplitMix64`, `TestPattern`, `firstDifference` |
| `USBDriveTesterTests/ChunkCycleAuditTests.swift` | 21 tests — every violation produced deliberately |
| `USBDriveTesterTests/RetentionCycleTests.swift` | the four gate items and the cases that make them mean something |

**386 tests, 0 failures** (up from 323; the number is the top-level `totalTestCount`, and
`grep -rh '@Test'` over the test sources agrees at 386). Debug builds with no warnings and no
errors from a forced recompile of every changed file. **The clean Debug + Release
zero-warning check of the Global DoD is still outstanding** and belongs at the end of the step.

**Gate items 1–4, plus the added read-fault item, are discharged in simulation:**

- **1 — non-destructive, bit-for-bit.** Whole-device runs at 512 B *and* 4,096 B geometry leave
  the backing store byte-identical, checked by first-differing-index rather than by comparing
  4 MB arrays inside `#expect`.
- **2 — verify mismatch flags exactly that range.** A 4-block fault inside a 128-block chunk
  reports 4 blocks, not 128; a single flipped bit in one block reports one block; a fault
  straddling a chunk boundary arrives as one coalesced range; separate faults stay separate.
- **3 — hard errors classified.** Read faults, write faults and corruption in one run produce
  three correctly-typed ranges, and adjacent ranges of *different* kinds are not merged.
- **4 — one chunk in flight.** The ordering audit is clean across every run, the cycles tile
  the device exactly once in order, and peak buffer memory is identical for a 65-chunk run and
  a 1-chunk run (2 × I/O size in both).
- **added — a failed read leaves the device untouched.** Asserted four ways, because "the
  device is unchanged" is also true of a clean run and would pass whether or not the guard
  exists: no write was attempted at that offset, the audit sees no write-after-failed-read, the
  range still holds its own pattern, and the bytes are missing from the accounting.

**Four checks were shown capable of failing before their passing was believed**, per the
project's standing rule:

1. `ChunkCycleAuditTests` produces **every** violation the audit can report from hand-built
   sequences — including `writeAfterFailedRead` (the sixth hazard) and
   `chunkOpenedWhilePreviousInFlight` (NFR-REL-4 itself) — with no device and no engine
   involved, which is only possible because the checker is a pure function of
   `[DeviceOperation]`. Four further tests assert it does **not** flag legitimate irregularity
   (a failed read, a failed write, a failed verify), because a checker that did would make
   every fault-injection test fail for the wrong reason and be trusted anyway for being strict.
2. `aMisdirectedWriteIsDetectedByTheSameAssertion` runs the cycle through a device that writes
   one block late; the bit-for-bit comparison must and does fail. Without it, a green
   non-destructiveness result is indistinguishable from a comparison that cannot fail.
3. `everyBlockHoldsItsOwnPatternAndNoTwoBlocksAreAlike` checks the *test data* can reveal a
   wrong-place write, rather than trusting that a PRNG produced distinct blocks.
4. **`theInMemoryDeviceIsItselfFlaggedAsCached` — the one with nothing rigged at all.** An
   `InMemoryBlockDevice` read is a `memcpy`, so a run against it genuinely *is* answered from
   RAM, and FR-TEST-9's falsifier says so under the **real** monotonic clock with no fake
   timings and no constructed rate. That is the strongest available evidence that the falsifier
   works, and it arrived as a consequence of the design rather than being contrived: tests that
   need the verdict to stay `bypassed` have to supply a slow clock, which is what the injected
   `MonotonicClock` is for.

**A finding worth carrying to Step 10.** The misdirected-write canary also demonstrates that a
wrong-place write is *not* reliably caught by the verify — the verify compares what was read at
the intended offset, so damage done elsewhere is only visible to a whole-device comparison.
That is precisely why gate item 5's evidence is a per-1-GiB digest vector over the whole device
and not the run's own "0 bad blocks" result. A run can report clean and still have moved data.

### Helper side and tooling authored (2026-08-02) — still nothing written to any drive

| Authored | State |
|---|---|
| `Shared/TesterControl.swift` | protocol **v6**: `runRetentionCycle`, plus `maximumCycleBytesPerCall` (1 GiB), `permittedIOSizes`, `defaultIOSizeBytes` |
| `Helper/RunCoordinator.swift` | new; validates, allocates, seeds FR-TEST-9, runs, logs. Auto-joined the helper target — no GUI action needed |
| `Helper/main.swift` | the v6 method; `HelperActivity.beginRun/endRun`; `releaseDevice` now refuses mid-cycle |
| `tools/media-digest/main.swift` | new; SHA-256 per window + whole-device, `O_RDONLY`, nothing unmounted |
| `tools/mount-guard-client/main.swift` | `version`, `wait:<path>`, `cycle:<start>:<count>[:<ioSize>]`; 300 s timeout for the cycle |
| `scripts/retention-cycle-check.sh` | new — the hardware gate |
| `scripts/ioctl-constants-check.sh` | request 71; **11/11**, and the SDK confirms `DKIOCGETMAXBYTECOUNTWRITE = 0x40086447` |
| `scripts/test.sh` | parallel testing disabled — see below |

**389 tests, 0 failures.** The count fell from 390 because `RunMemoryTests` was deleted, not because
anything regressed — see defect 1.

#### Three defects found in this step's own work, all before hardware

**1. The engine mutated process-global test instrumentation.** `run()` called
`ChunkBuffers.resetPeakAllocatedBytes()` so it could report a per-run high-water mark. That is a
process-global counter, and resetting it clobbered the baseline of
`ChunkBuffersInstrumentationTests` — a *Step 7* suite, running concurrently, which failed.
Production code has no business resetting instrumentation other code is using, and the figure it
bought was the weaker half of NFR-PERF-1 anyway. `RunSummary.peakBufferBytes` became
`bufferBytesHeld` (`buffers.totalAllocatedBytes`): exact, uncontaminated, and unable to vary with
capacity because capacity is not one of `ChunkBuffers`' inputs. `RunMemoryTests` was deleted with
it — its claim is Step 7's `reusingOnePairAcrossManyChunksDoesNotAccumulate`, which is the right
home for it.

**2. Parallel testing made global-counter assertions unsound — `scripts/test.sh` now disables it.**
Fixing defect 1 stopped the *reliable* clobber, and three consecutive full runs then passed. Three
greens are not evidence: Step 8's cycle tests allocate `ChunkBuffers` in forty-odd tests, and no
assertion on a global counter can be sound while another test may be mutating it. Step 7 saw this
exact case coming and wrote the instruction into the suite — *"if a future test does [allocate
`ChunkBuffers`], it must either live here or the assertions below must be loosened"* — and Step 8
is when the condition arrived.

Loosening was rejected: **there is no assertion on a global counter that is immune to concurrent
mutation**, so every loosening on offer traded away the thing being checked. Serialising was
measured instead — **9.7 s parallel, 18.8 s serialised** — and taken. Nine seconds removes a whole
class of results that depend on scheduling, and a green that depends on scheduling is not evidence.
Verified rather than assumed: the suite runs in a **single** process either way (so this is Swift
Testing's in-process parallelism, not xcodebuild workers), and disabling it doubles the wall clock.

**3. The gate script planned a run at block −893,534,208.** Caught by a dry run that aborts at the
confirmation prompt, before anything was unmounted or written. `od -An -N8 -tu8 < /dev/urandom`
yields a 64-bit unsigned value, and **bash arithmetic is signed 64-bit** — so any draw above 2⁶³
became negative, and `RAW % POSITIONS` then produced a negative start block. Fixed to 32 bits
(`-N4 -tu4`), whose modulo bias over ~238,000 positions is ~5×10⁻⁵ and irrelevant to spreading NAND
wear. `$RANDOM` was not an option either: 15 bits would confine every run to the first 32,768 chunk
positions.

Three explicit placement assertions were added with the fix and were then **shown to fire**: a
start past the legal maximum is refused, a misaligned start is refused, and the latest legal start
(1,951,424,512) is accepted and ends at block 1,953,520,639 — 4,528 blocks of margin, matching the
computation exactly. The arithmetic that produced a negative block number looked perfectly
reasonable in the source; only running it revealed it.

#### A gap in the project's "zero warnings" claim, found and closed

The clean-build discipline this project has followed since Step 4 runs `./scripts/build.sh` after
wiping DerivedData. **`build.sh` does not compile the test target** — only `test.sh` does — so
"zero warnings from clean Debug *and* Release builds" has never covered test sources. A clean
`test.sh` run on 2026-08-02 surfaced three warnings that had been present since Step 7, all in
`FileDescriptorBlockDeviceTests.swift` (lines 71, 295, 358): `variable 'source' was never mutated;
consider changing to 'let' constant`. Fixed.

They were invisible for the usual reason — incremental builds do not re-emit warnings — but the
deeper cause is that the *scope* of the check was narrower than the claim made of it. The
zero-warning check now means: **wipe DerivedData, then `build.sh Debug`, `build.sh Release`, and
`test.sh`.** Two of those three were already being done.

#### First hardware run of the gate — 2026-08-02, aborted at the pre-flight. **Nothing was written.**

The gate stopped exactly where it was designed to stop: at the measurement its own design rests
on, before either fingerprint and long before the cycle. Four checks passed on real hardware
first, which is worth recording because they were not certain either:

| Check | Result |
|---|---|
| the live daemon speaks protocol v6 | PASS |
| `disk4` unmounted | PASS |
| helper acquired `disk4` (claim + `O_EXLOCK`) | PASS |
| pre-flight: second process reads `/dev/rdisk4` while the helper holds `O_EXLOCK` | **FAIL — `errno 13`** |
| mount state restored on exit | PASS (`Test_Drive` remounted) |

Placement drawn: block 1,845,444,608 — chunk-aligned, well clear of both ends.

**`errno 13` is `EACCES`, not `EBUSY`, and the difference is the whole finding.** `/dev/rdisk4`
is `crw-r----- root:operator` (mode `0o20640`, measured in Step 7 and recorded in
`CacheBypassCheck`), and `media-digest` was being run as the ordinary user — who is neither root
nor in `operator`. The open was refused by plain Unix permissions and **never reached the
exclusive lock at all**. So the question the pre-flight exists to answer is still open, and the
run proved nothing about exclusivity in either direction.

**Two defects, and the second is the instructive one.**

1. The script ran the fingerprint unprivileged. Fixed: it now primes `sudo` **once, up front**,
   before anything is unmounted, and keeps the credential alive with a background refresher —
   the two fingerprint passes are ~35 minutes apart on a 1 TB drive, far beyond sudo's ~5-minute
   cache, and a password prompt appearing silently mid-run while the helper holds an exclusive
   claim is a trap rather than a safeguard. `sudo` from Terminal also supplies the Full Disk
   Access grant the raw open needs (NFR-INST-4) by inheriting Terminal's.

2. **The check reported a conclusion its evidence did not support.** It said *"a second process
   cannot read `/dev/rdisk4` while the helper holds `O_EXLOCK`"* — a statement about
   exclusivity — when all it had observed was that *an* open failed. That is the same conflation
   Step 6 spent a measurement session untangling: there, **both** of FR-SAFE-4's causes surfaced
   as an identical `EBUSY`, and only an independent fact could separate them. A check that
   converts any failure into its favourite explanation is worse than no check, because it is
   believed.

   The pre-flight now classifies the `errno` and says what was actually learned:

   | errno | what it means | what to do |
   |---|---|---|
   | success | the digest ordering this gate uses is sound | proceed |
   | 16 `EBUSY` | the `O_EXLOCK` genuinely does block a second reader | the fingerprints would have to be taken by the **helper**, through its own descriptor |
   | 13 `EACCES` | not root, not in `operator` — never reached the lock | a fault in the script, not a finding |
   | 1 `EPERM` | TCC refused; Terminal needs Full Disk Access | grant it; root alone is not sufficient |

**Still true after this run: nothing has ever been written to any drive.** The gate's
simulation-first ordering did its job — it refused to proceed on a check it could not honestly
pass, at the cost of one unmount and a remount.

#### Second run — MEASURED: `O_EXLOCK` blocks a plain `O_RDONLY` open (2026-08-02)

Re-run with the fingerprint under `sudo`, so the process was root **and** carried Terminal's Full
Disk Access grant. The only thing left in the way was the lock, and it refused:

```
open=failed
open.errno=16
open.errnoText=Resource busy
```

**This is a new measured fact, and it is not in the 2026-07-30 exclusivity matrix.** That session
established `O_EXLOCK` vs `O_EXLOCK` (second one fails `EBUSY`) and plain `O_RDWR` vs plain
`O_RDWR` (both succeed). It never tested a **held `O_EXLOCK` against an opener requesting no lock
at all** — and the answer turns out to be that the lock excludes it too. Added to the matrix:

| Question | Answer |
|---|---|
| `open(rdiskN, O_RDONLY)`, **no lock requested**, while another process holds `O_EXLOCK` | **fails `EBUSY`** — measured 2026-08-02 |

`disk4` was unmounted, acquired, and remounted cleanly around the failure. Placement drawn:
block 1,340,219,392. **Nothing was written.**

**Consequence: D3's digest ordering is impossible as designed, and BUILD-PLAN gate item 5 is
wrong as written.** It says both fingerprints are taken "by a separate process while the helper
still holds the claim". No separate process can read the device at all while the claim is held,
because the claim is accompanied by the exclusive open. Both digests must therefore come from
**the helper, through its own descriptor** — which is the branch the pre-flight's `EBUSY` case was
written to name, and the reason the pre-flight was built before the gate design was committed to.

That the pre-flight existed at all is the Step 7 lesson holding: `tools/media-digest` was written
and its canary proven *before* it was relied upon, and the one fact the design rested on was
measured rather than assumed. Assuming it would have produced a gate that failed at the "after"
fingerprint, ~40 minutes into a run, immediately after the first write this project has ever made
to real media — with no way to tell a digest that could not be taken from a device that had been
changed.

#### The redesign the `EBUSY` finding forced — protocol **v7** (2026-08-02, user decisions)

Two decisions taken:

- **The fingerprints move into the helper**, as a *bounded* `digestRange(startBlock:blockCount:)`
  capped by the same `TesterProtocol.maximumBytesPerCall` the cycle uses. A whole device is one
  call per gibibyte — ~932 of them for `disk4`, ~2.2 s each. Rejected: a single
  `digestWholeDevice()` call, because it would be a ~35-minute uncancellable privileged
  operation, exactly what the cap on `runRetentionCycle` exists to prevent. Rejected: taking the
  fingerprints outside the claim, because DiskArbitration remounts within ~4 ms of release and
  mounting an exFAT volume can dirty it — that would need its own measurement first.
- **No independence cross-check** against a separate reader. Recorded as a known residual: both
  fingerprints now come from the helper's own descriptor, so a fault in *that descriptor's*
  addressing would be invisible to them. What stands against it is indirect — geometry
  cross-checked against `diskutil` (`geometry-check.sh` 9/9) and addressing verified past 2³² on
  `disk8` (`large-address-check.sh` 10/10).

**A vacuity risk the second decision did not cover, and how it was closed.** With both
fingerprints taken by one process and nothing checking the digest against a known value, a digest
function that returned a **constant** would make `before == after` pass unconditionally — a check
that cannot fail, which is the defect this project has now caught four times in other guises. It
is a different question from the addressing one, and it is closed **in simulation, at no hardware
cost**: `Core/DeviceDigest.swift` is a pure function over `RawBlockDevice`, unit-tested against
known SHA-256 vectors and against a single flipped bit. The gate adds a cheap corroboration on
hardware too — a real device must not fingerprint to one repeated value across its windows.

`DeviceDigestTests` pins the digest against **externally computed** values — every constant came
from Python's `hashlib` over the identical byte sequence, never from running the Swift code and
recording what it said, which would pin the implementation to itself and prove nothing. Four
sequences at both supported geometries agree, and the flipped-bit case asserts not merely that
the digest *changed* but that it changed to the value an outside tool computes for the corrupted
bytes. Also pinned: the digest is independent of read size (a digest that varied with it would
produce spurious before/after differences, which is the only comparison it is used for), the
exact final block is legal, and a read failure is reported with its offset.

`Core/DeviceDigest.swift` adds **`CryptoKit`** to Core's import list, which was Foundation-only.
Deliberate: CryptoKit is unprivileged, hardware-free, deterministic and testable off-device, so it
weakens none of the reasons that rule exists. The rule is about keeping the algorithm pure and
provable, and hand-rolling SHA-256 to honour its letter would have been a far worse trade.

**The redesign made the gate script simpler, not more complex.** The helper doing the work on one
connection removed the sentinel files, the background client process, *and* `sudo` entirely — the
only reason `sudo` was ever needed was an external reader that turns out to be impossible.
`tools/media-digest` is no longer in the gate's path; it is kept because it is the tool that made
the `EBUSY` measurement (`--probe`) and because its file-based canary is what proved a per-window
digest detects and localises a one-byte change.

#### Third run — THE FIRST WRITE TO REAL MEDIA. 15/15, and it proved almost nothing (2026-08-02)

`./scripts/retention-cycle-check.sh disk4 --quick`, protocol v7, placement block 86,319,104.
Every check passed. **Gate item 5 is not discharged, and the 15/15 is misleading.**

**What the run genuinely established** — real, and not nothing:

| | |
|---|---|
| the live daemon speaks **v7**; acquire and release on real hardware | PASS |
| **256 chunks — 255 full + 1 short** — executed on real media | PASS |
| 4 MiB `pwrite`s completed with **no short transfers**; 0 failed ranges | PASS |
| FR-TEST-9's verdict **survived real I/O**: `bypassed` | PASS |
| fastest read **500,242,470 B/s** — transport-plausible, not RAM-plausible | PASS |
| buffers **8,388,608 B = 2 × I/O size** in the daemon | PASS |
| mount state restored | PASS |

The **mechanism** ran end to end on hardware. That is the first time the write path, the short
final chunk and the per-chunk guard have executed against a real device.

**What it did not establish, and why.** The three window fingerprints were:

```
window 0  84221952  2097152  49bc20df…
window 1  86319104  2097152  49bc20df…     <- the window containing the run
window 2  88416256  2096128  a2986c1d…
```

Computed independently afterwards: `sha256(bytes(1073741824))` **is** `49bc20df…`, and
`sha256(bytes(1073217536))` **is** `a2986c1d…`. **All three windows are entirely zeros.** The
cycle read 1 GiB of zeros, wrote zeros back, and verified zeros against zeros. Writing zeros over
zeros is non-destructive however wrongly the code addresses the device — a write landing at the
wrong offset anywhere inside that region would be invisible to the verify *and* to the
fingerprints. `disk4` is **1% used**, so a randomly placed run lands on unwritten space almost
every time.

**The defect is in the gate, not the engine — and it is the project's signature failure again.**
The check that was supposed to catch this read:

> `PASS  the fingerprints are content-dependent (2 distinct values across 3 windows)`

**It was parsing the wrong field.** The digest file's format is
`window <index> <startBlock> <blocks> <sha256>`, and the check ran `awk '{print $4}'` — which is
the **block count**, not the fingerprint. A 3-window `--quick` run always has exactly two distinct
block counts (2,097,152 for the full windows, 2,096,128 for the short one), so it reported "2
distinct values" **on any drive, empty or full, whatever the content**. It never examined a
fingerprint at all.

*(Corrected 2026-08-02. This was first recorded as "the all-zero digests differed by length",
which was wrong — that explanation was inferred from the output rather than from the code, and
the code was not doing what it appeared to be doing. The conclusion was unaffected: the check was
vacuous either way. The mechanism was not, and a wrong mechanism in the log is how the next
person mis-fixes it.)*

The weakness was also anticipated and then not acted on: the source comment said "an all-zero
region legitimately repeats", and the check was shipped anyway rather than being made to test the
property that mattered. A comment acknowledging a hole is not a check; it is a note explaining
why the check does not work.

The replacement reads its input from a different, unambiguous source — the `[digest] SHA256=`
lines the helper emits per probed chunk — rather than positionally from a file whose column
layout has to be remembered correctly.

**Replaced with the property that actually matters.** Before the cycle writes a byte, three whole
chunks from *inside* the tested range are fingerprinted and must be pairwise **distinct**. If they
are not, the region is uniform, no misdirected write within it could ever be detected, and the
gate **fails** rather than reporting a pass. Cost: 12 MiB of reads.

Plus an early warning before anything is unmounted, so a doomed run can be avoided rather than
merely failed afterwards: the script reads the volume's usage and says so when it is under 25%
full. Verified firing — `disk4 is only 1% used`.

**The precondition this exposed, which belongs with the test hardware.** `disk4` must hold **real
data**, not empty space, for any placement-random gate to mean anything. One-time fix: fill the
volume with high-entropy data and keep the file, because deleting it may let the drive discard
the blocks.

#### Fourth run — the mechanism proven over REAL DATA (2026-08-02)

`Test_Drive` filled with ~1 TB of `/dev/urandom` (file kept, so the blocks stay written), then
`./scripts/retention-cycle-check.sh disk4 --quick`, placement block 210,157,568. **15 checks,
0 failures — and this time the content is real.**

The check that decides whether the run means anything now has something to say:

```
PASS  the tested region holds distinguishable data (3 sampled chunks, 3 distinct fingerprints)
   block 210,157,568  8a624eb4…
   block 211,197,952  43852cb9…
   block 212,238,336  4393acef…
```

All three probes lie inside the run, and all three differ. Verified independently afterwards:
none of the three window fingerprints is the all-zero digest for its length, and all three
windows differ from one another.

| | before | after |
|---|---|---|
| window @208,060,416 (2,097,152 blocks) | `18531d1f…` | `18531d1f…` |
| window @210,157,568 (2,097,152 blocks) — **contains the run** | `52ea3b71…` | `52ea3b71…` |
| window @212,254,720 (2,096,128 blocks) | `3ecb14b4…` | `3ecb14b4…` |

Byte-identical. The cycle read 1,073,217,536 bytes of high-entropy data, wrote the same bytes
back, verified each chunk against its re-read, and left the region unchanged — with
`FASTEST_BYTES_PER_SECOND=504,229,135`, `CACHE_BYPASS=1`, `BUFFER_BYTES=8,388,608` and 256 chunks
of which the last is short.

**What is now discharged, and what is not.** The read → write-back → read-verify cycle is proven
non-destructive over real data on real hardware, at the offsets a real run would use, including
the short-final-chunk path. **Gate item 5 is still not fully discharged**: `--quick` fingerprinted
only 6,290,432 blocks (3 GiB) around the run, so a write that landed outside that window would not
have been seen — and detecting exactly that is the reason the fingerprint exists. The full run,
fingerprinting all 1,953,525,168 blocks either side of the cycle, is what closes it.

#### A tooling defect the first long run exposed — progress that never arrived

`mount-guard-client` set `setvbuf(stdout, nil, _IOLBF, 0)`, which does not reliably flush per
line when stdout is a **pipe** — and the gate script always pipes it through `tee`. During the
first full-device fingerprint pass, none of the per-50-window progress lines reached the
terminal: ~18 lines of ~40 bytes never fill a 4 KB buffer. Changed to `_IONBF`.

Invisible until now because every previous run finished in about ten seconds, so all output
arrived at once. The same shape as the warnings gotcha — a defect that only appears at a scale
nothing had yet reached.

The unified log was unaffected and turned out to be the better progress indicator anyway: the
helper emits one `digest for … blocks X–Y … = <hash>` line per window, so
`log show … | grep -c "digest for"` gives an exact window count against the 932 per pass, with no
buffering in the way.

#### Helper CPU — an observation from the full run, and what it does and does not mean

**Observed by the user during the full-device gate: the helper at 36–39% of one core on an M4
Mac Mini, at ~500 MB/s.**

**That figure is the gate's fingerprint, not the product.** `Core/DeviceDigest.sha256` exists so
the hardware gate can prove the cycle moved nothing; it is instrumentation, and nothing in the
FR/NFR set makes the shipping tool hash anything. The observation is of code that will never run
during a user's test.

**But the extrapolation is sound and worth having.** Linear in data rate, SHA-256 reaches one
full core at roughly **1.3 GB/s** on this machine — within reach of a USB4 enclosure. So the
*gate* stops being I/O-bound on faster hardware, which matters for how long a full fingerprint
pass takes on someone else's setup.

**What the product actually costs per chunk is a `memcmp`** — the block-by-block walk is paid only
on a mismatch — expected to be order 40–80 µs against ~25 ms of I/O per chunk at 500 MB/s, so a
fraction of a percent. **Expected, not measured**, and recorded as such: an unmeasured performance
claim is exactly the sort of thing this project has been caught by, and NFR-PERF-3
("device-bound, not host-bound … overhead shall remain negligible") is the requirement that says
it must not be assumed.

**Consequences recorded rather than acted on now**, because Step 9 owns metrics and NFR-PERF-3:

- **BUILD-PLAN Step 9 gains detailed step 5a and a gate item**: measure helper CPU as a
  percentage of one core against measured MB/s, and show the run is device-bound.
- **Carried to Step 16**: *if* that measurement shows the host becoming the limit at a transport
  speed the product plausibly meets, it belongs in the release notes. Conditional on the number,
  not assumed from this one — per the user's own framing, *"if the final product shows similar
  CPU consumption at a given data rate"*.

#### `tools/media-digest` was proven capable of failing before hardware use

Digest a 5 MB file, flip **one byte** at offset 3,000,000, digest again:

| | before | after |
|---|---|---|
| window 0, 1, 3, 4 | unchanged | unchanged |
| **window 2** (2,097,152–3,145,727) | `3061f141…` | **`15dc9412…`** |
| whole | `b78ca110…` | **`dfec406c…`** |

The single flipped byte changed exactly the window containing it, and nothing else. So the tool
detects a change *and* localises it — the reason the gate uses a per-window vector rather than one
scalar, at identical I/O cost.

**Simulation-proof details that are easy to get wrong, and are decided:**
- The in-memory device is filled from a **seeded** PRNG stream keyed by **block index**, so
  "block *k* contains block *k*'s pattern" is checkable and a mis-addressed write is detectable
  by content. Uniform random is not enough; an all-zero or repeating fill would let a
  wrong-offset write pass, which is the same family of vacuity as hazard 3.
- The non-destructiveness assertion finds the **first differing index** and asserts on that,
  never `#expect(before == after)` on a multi-MiB array — Swift Testing renders both operands.
  Same family as Step 7's `#expect` literal-promotion trap.

---

## Step 9 — GATE DISCHARGED (2026-08-05) — step still open, nothing committed

> **Read this together with "Step 9 — UI work folded in after the gate", below.** Everything in
> *this* section is the metrics work and its Verification Gate, which is fully discharged. After it
> passed, the user reviewed the shipped window and a body of **UI work was folded into Step 9 by
> decision** rather than deferred — so the step is **not closed and nothing is committed**. The
> figures below (497 tests) are the gate's; the current count is **516**.

Every gate item discharged. **The step's own pre-flight overturned the design the plan assumed,
and the number this project had carried as an estimate for three steps turned out to be wrong by
11×.**

**Delivered.** Live metrics, measured helper-side and displayed GUI-side. `Core/LatencyHistogram`
— a constant-memory percentile in **17,920 fixed bytes**, selected with integer arithmetic alone
and reported as an *upper bound* rather than a point. `Core/RunMetrics` — the accumulator, keeping
three distinct rates apart and denominating progress in **bytes, never chunks**. A rewritten engine
inner loop where `chunkMeasured` fires **once per chunk on every path**, the three failure branches
included, and where host overhead is the chunk's whole span minus its device phases. `RunPlacement`
— FR-TEST-10's 1 MiB rule, enforced at the trust boundary. Protocol **v8**. And on the app side:
one hoisted `AppModel`, the `Metrics/` panel that is a pure function of a snapshot, a diagnostics
**window** rather than a disclosure, and a GUI that polls progress on a **second, non-owning XPC
connection** — because the run's own connection provably cannot answer while the run holds it.

**Final state.** **497 tests, 0 failures.** Zero source warnings from clean **Debug**, clean
**Release** *and* a clean **test-target** compile, DerivedData wiped before each.
`./scripts/xpc-concurrency-check.sh` **0 failures** on the scratch device (read-only).
`./scripts/metrics-check.sh` **0 failures** on the scratch device, all four I/O sizes.
`./scripts/retention-cycle-check.sh` **15/15** on the scratch device, all **932** whole-device fingerprints
unchanged. NFR-PERF-4 observed by the user on hardware.

**Requirements affected.** **FR-TEST-10 added** (1 MiB alignment, helper-enforced) and
**FR-CTRL-8 revised** (I/O size configurable while paused or stopped), both with full amendment
entries dated 2026-08-04. **NFR-PERF-3 measured**, wording unchanged, recorded in the NFR
document's amendments. The ADR's sixteen checkboxes remain untouched, as they have been for every
step — it is a decision record, and BUILD-PLAN is the tracker.

### The hardware result

`metrics-check.sh disk4` — the same gibibyte from block 0, four times, which is an **8× lever on
chunk count at constant bytes**:

| | 1 MiB | 2 MiB | 4 MiB | 8 MiB |
|---|---|---|---|---|
| chunks | 1024 | 512 | 256 | 128 |
| progress reached | 100.00% | 100.00% | 100.00% | 100.00% |
| mid-run snapshots | 14 | 13 | 14 | 13 |
| widest gap | 505.4 ms | 505.3 ms | 505.3 ms | 505.4 ms |
| read / write | 517 / 491 | 516 / 491 | 488 / 492 | 501 / 492 MB/s |
| p99 (min ≤ p99 ≤ max) | 2.195 ms | 4.162 ms | 9.175 ms | 17.302 ms |

**NFR-PERF-5 is discharged with a factor of two in hand**, and 13–14 of those snapshots arrived
*while the privileged call was blocking* — the property the whole second-connection design exists
to provide, which no amount of simulation could have shown. **FR-TEST-10 was shown refusing**, not
merely shown not-refusing: a start at block 1 and a length one block short of a whole MiB were both
refused with **zero chunks processed**.

**NFR-PERF-3, final:** at the 4 MiB default with the device moving ~470 MB/s, in-span host overhead
is **2.55%** of device I/O time and daemon CPU **4.22% of one core** — the run is **97.4%
device-bound**, cross-checked by an independent `ps` sampler peaking at 8.5%. **Host cost follows
bytes moved, not chunk count**: µs/MiB varied **1.32×** across the 8× range while µs/chunk varied
**8.65×**, so a larger I/O size does not reduce it. Because the cost is per-byte its share rises
with transport speed — ~10.9% at USB 3.2 Gen 2×2, ~20.6% at USB4 — which makes Step 16's
release-note item **unconditional** rather than contingent.

### What this step cost, and what it bought

**A pre-flight reversed the design before a line of it was written.** BUILD-PLAN 9.4 assumed the
helper would *push* snapshots; scoping recommended a *poll*. Both were guesses about whether a
daemon inside a blocking call answers a second message. Twenty minutes of `xpc-concurrency-probe`
settled it: on the run's own connection **0 of 24** pings were answered during a 2,827.9 ms call —
the whole queue draining in ~0.6 ms *afterwards* — while a **second connection** answered **24 of
24** in 0.2–0.3 ms. So the daemon is not blocked; the connection is. That ruled out the recommended
option *and* priced a third one the probe's pre-written verdict branches had not contained, because
the second-connection number did not exist until it was measured.

**Twelve defects, none of which reached a gate as a false pass.** Four are worth naming:

1. **`chunkCompleted` fired only for chunks that got through every phase** — all three `catch`
   blocks `continue` past it. Harmless while nothing computed statistics from it; a defect the
   instant something did, and it would have frozen percent-complete and run the ETA away **on
   exactly the drive this tool exists to find**. Replaced wholesale rather than patched.
2. **Step 8's gate would have been refused by FR-TEST-10, ~35 minutes in.** Its `1 GiB − 512 KiB`
   constant is 1023.5 MiB. Found by *reading the new rule against the existing script*, not by
   losing an hour to it. Both constants are now pinned by `StepEightGateCompatibilityTests`, so the
   compatibility is a test rather than a memory.
3. **The probe reported `samples ÷ chunks` as every run's final figure** — 987/1024, 488/512,
   240/256, 123/128. The polling loop exited the instant the cycle replied, so **nobody ever asked
   the helper what the completed state was**. The runs had all completed. A failure off by an
   arbitrary amount is a mystery; one off by exactly the polling granularity at four different
   chunk counts is a measurement artefact, and the arithmetic is what identified it.
4. **The bounded-cycle button was pressable with no device held.** Reported as "appears to do
   nothing"; it was working perfectly and failing in **25 ms**, which the unified log settled in one
   query after several paragraphs of my speculation had settled nothing.

The other eight, in the order they were found. **Two of them are the same failure mode as each
other and as this project's most expensive recurring bug — a value that reads as a pass when it
means "no data":** the D1 probe printed **"0.0 ms"** under *worst reply during the call* when no
reply had arrived during the call at all, and the first row of every sweep table read **100% then
dropped to 3%**, because `MetricsChannel.begin()` runs *after* validation — correctly, so a refused
run does not wipe the previous run's figures — leaving a few milliseconds in which a poll still saw
the **previous** size's completed snapshot. Fixed by spelling out the no-data case, and by settling
250 ms before the first poll.

The remaining six were mine and caught early: a `%s` format specifier given a Swift `String`
segfaulting a scratch harness (the same bug I had removed an hour earlier), `#expect`'s comment
argument being a `Comment` rather than a `String` expression, a `Duration` extension needing
`nonisolated`, `Timer.publish(…).autoconnect()` needing an explicit `import Combine` under
`MemberImportVisibility`, an idle placeholder implemented as an **overlay** — which left a row of
em-dashes visible behind it, so the panel showed empty measurements *and* a note saying there were
none, one of which looked like data — and **two stale spatial references** ("install the helper
below", "the metrics panel above") left pointing at a panel that had become a window, both found by
rendering rather than by reading. A corrective instruction pointing where the control is not is
worse than none.

**Three lessons this step earned, all paid for.**

**Measure, don't estimate.** "Order 40–80 µs of host work per chunk" stood for three steps and
appears in BUILD-PLAN as a parenthetical. The measurement is **683 µs** against 25.44 ms of I/O —
wrong by 11×, and it survived only because nobody measured it. The replacement figure is not
re-estimated: what the residual ~209 µs-per-chunk term in daemon CPU actually *is* has been
measured and is deliberately **not guessed at**.

**A pre-flight before a design is committed to is almost free; the same discovery afterwards is
not.** True twice here — the D1 probe, and reading FR-TEST-10 against Step 8's gate script.

**Prose is not a precondition.** A control that states its requirement in body text and then looks
live is a control that fails on press. Every other control in this app disables itself and names
the corrective step.

**And a correction to my own arithmetic, recorded rather than edited away.** I reported the daemon
saturating one core near **4.7 GB/s**. That was a stray factor of 0.5; the figure is **11.1 GB/s**,
more than double the headroom. It also rested on a single 4 MiB point and used the *fastest observed
read* rather than the run's actual rate. The percentage columns survived the correction; the
saturation point did not.

### Carried into Step 10 (the report this step feeds)

- **Final throughput and latency are on the wire already** — `runRetentionCycle`'s reply carries
  them, so the report assembles from measured values rather than re-deriving any.
- **p99 must reach the report as an upper bound.** "p99 ≤ x" is what the histogram knows; a report
  printing "p99 = x" would dress a bracketing interval as a measurement, which is the same class of
  error as a verdict the tool is not entitled to.
- **The report records which I/O sizes were used**, because FR-CTRL-8's mid-run change makes the
  latency distribution bimodal and the statistics deliberately **keep accumulating** across it.

### Not discharged by this step, and not to be mistaken for covered

- **Whole-device progress and ETA.** This step's are **per-call**, honestly labelled, because a run
  is one bounded call until Step 11 sequences them. The multi-hour convergence observation the
  gate's original wording implies is unreachable under the 1 GiB cap and belongs to Step 11.
- **The final chunk at the physical end of the scratch device, and a whole-device traversal.** Unchanged from
  Step 8: neither is reachable under the placement rules used so far, and both belong to a later,
  separately agreed run.
- **What the ~209 µs per-chunk term in the daemon's CPU is.** Measured, not explained.
- **The `File ▸ New Window` defect, found 2026-08-05 and not fixed here.** The main scene is a
  `WindowGroup`, so macOS offers ⌘N — and a second main window would build a second
  `DeviceDiscovery` with its own selection while sharing one claim, so the two windows could
  disagree about *which drive is selected* while only one is actually held. That is NFR-USE-3's
  hazard, and it is the same one-truth-two-views problem the diagnostics scene already solved by
  being a `Window`. Recorded here as found-and-open rather than folded into this step.

**One measured behaviour confirmed from the product's own surface.** Releasing the device
auto-remounts `Test_Drive` with no user action — `Mount All` is not needed after a release. This
was already measured in Steps 6 and 7 (releasing an `O_EXLOCK` open or a `DADiskClaim` makes
DiskArbitration remount within milliseconds) but had only ever been seen from probes and scripts;
2026-08-05 is the first time it was observed through the shipped Release button, with FR-SAFE-5's
control correctly re-evaluating its label afterwards.

---

## Drive identity moved to serial numbers (2026-08-06) — READ THIS BEFORE ANY BSD NAME BELOW

**A reboot renumbered this machine's drives, and every `disk4` written anywhere in this project
became wrong on the same morning.** The designated scratch device — Samsung Portable SSD T5,
serial **`12345686DAA9`** — is now **`disk8`**. And `disk4` is now the **Seagate 22 TB holding
Backup and Time Machine**. The two swapped.

| role | drive | **serial** | was | is now |
|---|---|---|---|---|
| scratch (every write gate) | Samsung Portable SSD T5, 1 TB | **`12345686DAA9`** | `disk4` | **`disk8`** |
| bulk (read-only, by agreement) | Seagate Expansion HDD, 22 TB | **`00000000NT17XBRA`** | `disk8` | **`disk4`** |
| source tree (never tested) | Samsung 990 EVO Plus, Ugreen enclosure | **`013117100578`** | `disk6` | `disk6` |

### What that would have cost, stated plainly

`./scripts/retention-cycle-check.sh disk4` — the command written in this file, in BUILD-PLAN, and
in a dozen shell histories — would have unmounted the backup drive and written a gibibyte to it.
And `metrics-check.sh` carried a guard that **refused any drive but `disk4`**: a safety check that
the renumbering turned exactly inside out, so it would have refused the correct drive and admitted
the backup one. A guard whose premise has silently expired is worse than no guard, because it is
still trusted.

The product has identified drives by USB serial number since 2026-08-05, for precisely this
reason. The decision had been implemented in the app and **not** in the apparatus around it.

### What changed (user decision 2026-08-06)

- **`tools/device-id`** — resolves serial ↔ BSD name by compiling the **app's own** enumerator, so
  "this drive's serial" has one definition in the project rather than two. It inherits the IOKit
  ancestor search and `USBSerialNumber.sanitised`'s placeholder rejection for free.
- **`scripts/lib/device-identity.sh`** — every hardware script now resolves its target by serial,
  cross-checks the block count, and **refuses** anything else. A stale `diskN` on the command line
  is not ignored: it is checked and refused, naming both serials and what the other drive is.
- **The scripts' own name-based guards are gone**, replaced rather than weakened — `resolve_target`
  establishes identity before any of that code runs, and by 2026-08-06 those guards were inverted.
- **Shown refusing, on the real machine**, which is the only evidence that counts here:
  `metrics-check.sh disk4` and `retention-cycle-check.sh disk4` both refuse, before touching
  anything, and say why.

### One consequence inside the product, found by rendering

**The app now default-selects the backup drive.** FR-DEV-2 sorts the list by BSD name and FR-DEV-3
selects the first usable device; after the renumbering the first in that order is `disk4` — the
Seagate, with Backup and Time Machine mounted. `scripts/render-ui.sh devices` shows it selected,
with its 22 TB detail filled in. Both requirements are satisfied exactly as written; what changed
is which physical drive "first" names.

Nothing is done about it here, and nothing needs to be *today*: no run can start without an
explicit unmount and acquire, and the panel already says "Testing a drive you are using is not
advisable." It matters at **Step 11**, where Start owns unmount → acquire → run and the default
selection is one deliberate click from a write — which is precisely why that step's removal of the
explicit unmount is gated on Step 14's warnings existing. Recorded as an inherited note on both.

**FR-DEV-3 stands as written — settled 2026-08-06, user decision**, put to the user with the
render above and kept unchanged.

> *"FR-DEV-3 is perfect as written. I do not want to go down the road of trying to divine user
> intentions."* — user, 2026-08-06

It is the same policy as D9's refusal to grade throughput, and worth seeing as one rule rather
than two: the tool reports what it measured and declines the judgements it is not entitled to
make. A default that guessed which drive its owner considers expendable would be exactly such a
judgement, and a worse one than a graded throughput figure — it would look like the app knowing
something about the user's hardware, at the moment that belief is most expensive. "The first
device in a stated order" says only what is true.

The consequence is that **the entire mitigation sits in Step 14's warnings**, which must name the
drive by model and USB serial rather than by BSD name. Recorded on Step 14, and it is why Step 11's
removal of the explicit unmount is gated on that step existing rather than merely sequenced after
it.

### The rule is two-sided, and the test is lifetime (clarified by the user, 2026-08-06)

Everything above states one half, and read alone it would justify stripping the BSD name out of
the UI. That would be a regression, and it is not what was decided.

> *"I like the idea of showing the BSD name anywhere live drive data is being displayed because it
> offers one more piece of identity disambiguation information. I just don't ever want to refer to
> drives by their BSD name for any purpose that might become stale upon unplug/re-plugs or reboots
> (like build plans, scripts, previous test results, etc.)."* — user, 2026-08-06

So the question is never "is a BSD name allowed here?" but **does this statement outlive the
enumeration that produced it?**

- **Live** — the device list, the selected-device detail, `/dev/rdiskN`, a metrics heading, a log
  line about work in flight: **show it**, beside the serial. It answers *which of the things in
  front of me right now?*, and two identifiers a user can cross-check beat one.
- **Persisted** — this file, BUILD-PLAN, gate scripts and their command lines, the exported report,
  release notes: **never as the identity**; use the serial. If a BSD name appears at all it is
  labelled as the locator it was at the time.

Recorded canonically in the FR document's 2026-08-06 entry, with the rule stated at
`BSDDeviceName` where a developer meets it, and applied to Step 10's report (identity = serial)
and Step 14's warnings (identify by model + serial, locator beside it).

### About the BSD names still in this file

**They stay.** Everything below this entry is a historical record — what a drive was called on the
day a thing was measured — and rewriting it would falsify the audit trail this file exists to be.
`disk4` in an entry dated 2026-08-03 correctly names the drive that was `disk4` on 2026-08-03.
Forward-looking text has been corrected; BUILD-PLAN, the FR and NFR documents and every script
name drives by serial now, because those are read as instructions.

**The lesson, which this project has now learned in four different costumes:** an identifier that
is assigned rather than intrinsic will eventually name something else, and nothing will announce
it. It was the same shape as the BSD name in a device list, the same shape as a placeholder serial
of sixteen zeros, and the same shape as a probe reporting `0.0 ms` for a reply that never came.
Here it had teeth, because the identifier was being handed to something that writes.

---

## Step 9 — UI work folded in after the gate (2026-08-05) — CURRENT STATE

Written for a cold start. The gate above is discharged; this is what happened next and what is
left. **Nothing is committed.**

### Why this work is in Step 9 at all

With the gate passed, the user reviewed the running app and raised a series of UI defects and one
product-design change. Asked whether to commit Step 9 first or fold the work in, the user chose
**fold in** (2026-08-05). So Step 9's commit will cover the metrics work *and* this.

### Verified state right now

**551 tests, 0 failures, 65 suites** (was 516/62 before increment 4; +35 tests, +3 suites).
**Zero source warnings from all three clean builds** — `build.sh Debug`, `build.sh Release` and
`test.sh`, DerivedData wiped before each, run 2026-08-05 after increments 3 and 4.

`metrics-check.sh`, `retention-cycle-check.sh` and `xpc-concurrency-check.sh` results are unchanged
from the gate — **no helper, `Core/` or `Shared/` file has been touched by any of this work**; it is
app target, `tools/ui-probe` and documents only.

> **What is still owed, and it needs the machine's owner.** The Release build has not been
> **installed** (the app was running, and `install-app.sh` refuses to replace a live bundle), the
> helper has not been re-registered from it, and **NFR-PERF-4 has not been re-checked against the
> new binary**. Increments 3 and 4 touch the window layer, which is what that requirement is about,
> so the re-check is earned rather than pedantic. See "What is left".

### Increments done

| | |
|---|---|
| **1** | `tools/ui-probe`'s `devices` view never called `discovery.start()`, so it had **always** rendered the no-devices state — identical to the `empty` view it sits beside. Two named views collapsed into one, and nothing failed. Also added a `appActive / windowKey / firstResponder` diagnostic line, which went on to settle three later questions. |
| **2** | The device list is **focused on launch**, so FR-DEV-3's default selection draws blue rather than grey. The **Refresh button is removed**. |
| **2.5** | Panes merged; deselection implemented and auto-releasing; selection frozen during a run; run timestamp; **drives identified by USB serial number**. |
| **3** | The main scene is a **`Window`, not a `WindowGroup`** — `File ▸ New Window` is gone, and with it the possibility of two `DeviceDiscovery` instances with independent selections sharing one claim (NFR-USE-3's hazard). |
| **4** | **Quit/close confirmation during a run**, with the wind-down that keeps its promise: `Quit/QuitPolicy`, `Quit/QuitSequence`, `Quit/MainWindowCloseGuard`, `Quit/AppLifecycleDelegate`, plus the state and the sequencing in `AppModel`. **+35 tests, five mutations, all caught.** |
| **5** | The three clean builds above. Install, re-register and the NFR-PERF-4 re-check are outstanding — they need the app quit and a person at the keyboard. |

### Decisions taken (all user decisions, 2026-08-05)

1. **FR-SAFE-5 withdrawn, FR-SAFE-6 reversed, FR-SAFE-7 moot, FR-SAFE-4(a)'s remedy revised.** The
   `Unmount All` / `Acquire exclusive access` / `Release` buttons go, and **Start owns**
   unmount → acquire → run → release. Full amendment in the FR document; Step 11 inherits the work
   and Step 12 inherits FR-DEV-8 details. **Gated on Step 14's warnings existing first** — removing
   the explicit unmount before any confirmation exists would leave the product briefly less guarded
   than either the current design or the intended one.
2. **The claim follows the selection.** Deselecting, or selecting another drive, releases the
   device. Interim; Step 11 subsumes it.
3. **The selection is frozen while a run is active** — otherwise rule 2 would release a device
   under an active write.
4. **Drives are identified by USB serial number**, never by BSD name. Selection identity stays
   `registryEntryID` (its instability across replug is deliberate).
5. **Deselection is allowed** and is *not* durable across a device-set change — any hot-plug
   re-applies FR-DEV-3's default. Pinned by test, because it is surprising in use.
6. **Quitting mid-run: stop at the call boundary, then quit** — issue no further work, wait for the
   in-flight call to return, release cleanly, terminate. Same confirmation for window-close and
   ⌘Q. **Built in increment 4; see below.**

### Increments 3 and 4 — the window layer (2026-08-05)

#### The pre-flight, which settled five questions and killed one design

A scratch SwiftUI scene probe (two `Window` scenes, the app's own `.commands` shape, run
`.accessory` so it never took focus), because every question below had a plausible answer that
would have been wrong to build on. macOS 26, this machine:

| question | measured |
|---|---|
| what `WindowGroup` gives us today | File menu: **New Window ⌘N**, Close ⌘W, Close All ⇧⌘W |
| what `Window` gives us | **no File menu at all** — ⌘N, ⌘W and ⇧⌘W all disappear |
| is a closed `Window` recoverable | **yes** — SwiftUI adds a permanent Window-menu item per `Window` scene that brings it back |
| SwiftUI's own window delegate | `AppKitWindowController`, on an `AppKitWindow` |
| a forwarding proxy over it | intercepts `windowShouldClose:`; refuse keeps the window, allow closes it — **and the window still reopens from the menu afterwards**, so SwiftUI's own bookkeeping survived being proxied |
| `applicationShouldTerminate` via `@NSApplicationDelegateAdaptor` | fires; `.terminateCancel` keeps the app alive |
| main-queue delivery during `.terminateLater` | **delivered**, on time |
| run-loop `Timer` during `.terminateLater` | **never fired** — AppKit runs that wait in its own run-loop mode |

Two of those rows changed the design. The last one **rejected `.terminateLater`**, which was the
obvious API for "wait, then quit": the live metrics panel is `Timer`-driven, so the seconds spent
waiting for the boundary would have been exactly the seconds where the display of the operation
being waited on stops moving — a window that looks wedged at the moment the app is asking to be
trusted. `.terminateCancel` plus a wind-down in the app's ordinary run loop has no such mode.

**And the probe's own first answer was wrong, which is the more useful half of this.** Round 1
reported that main-queue blocks are *not* delivered during `.terminateLater` — a negative that
would have disqualified the mechanism for a completely fictitious reason. It called
`NSApp.terminate(nil)` from inside a GCD main-queue block, so the main queue was still occupied
when AppKit spun its nested wait: no other main-queue block could start, whatever the run-loop mode.
A real ⌘Q arrives from the run loop with the queue free. Round 2 drove every terminate from a
`Timer` and got the opposite result. **The probe was measuring itself.**

#### What increment 4 actually promises, and why it is worded that way

There is no cancellation of a privileged call once issued — that is Step 11's work, and it is why
the 1 GiB cap exists. So "Cancel and Quit" promises the two things the trust boundary can deliver:
**issue nothing further**, and **wait rather than walk away**. It does not claim to stop the run.

Quitting *without* waiting was never unsafe: the helper releases a claim when the connection that
took it goes away (NFR-REL-5), so an abrupt exit still ends with the device released and the volumes
remounted. What the wait buys is a release that is **issued and acknowledged** rather than inferred
from a socket closing — and, from Step 11 onward, a whole-device run that cannot be abandoned half
way by a keystroke that looks like housekeeping.

**The order is forced by measurement, not by taste.** `releaseDevice` goes out on the owning
connection, and D1 established that a second message on a connection with a blocking call in flight
is not delivered until that call returns. Releasing mid-run would queue the release behind the very
call it was meant to shorten. Waiting for the boundary is the only order in which these two
messages can happen at all.

**Two questions, deliberately answered by different state.** *Whether to ask* uses `runIsActive` —
the real cycle **or** the Step 4/5 stand-in toggle, because that toggle already means "a run is
active" everywhere else in the app, and a stand-in honoured in two places out of three teaches the
wrong lesson. It also makes the dialog exercisable without writing a gibibyte to a drive. *When to
quit* uses `cycleIsRunning` alone: there is nothing to wait for when the only run is a toggle.

#### The state machine, and the row that stops it deadlocking against itself

`QuitState` is `.idle → .confirming → .windingDown → .terminating`, and the last state exists for
exactly one reason: **the wind-down's own `NSApp.terminate(_:)` comes back through the same guard
that refused the user's.** Without a state that says "this one is mine", an app that reached the
boundary with the run-state stand-in still on would answer every termination — including its own —
with "wait for the boundary", forever. `theAppsOwnTerminationIsNotRefusedByItsOwnGuard` is that row.

#### Five mutations, five catches

The suite is green, which is not evidence. Each of these defects was introduced deliberately and
the suite re-run:

| defect introduced | caught by |
|---|---|
| policy loses its `.terminating` row | 3 tests, including the deadlock one |
| "Cancel and Quit" ignores an already-finished run | 2 tests |
| the call boundary never triggers the release | 2 tests |
| the sequence can terminate twice | 3 tests |
| the deadline is armed *after* the release is issued | 1 test — the ordering assertion exists precisely because it is invisible |

The last two are the ones no amount of clicking could produce: they need a daemon that accepts a
message and never replies. Both closures are injected, so neither test sleeps.

#### A defect found by rendering, in a path increment 3 changes

`ContentView` told the device-list store about run state through `onChange(of:)` only — and
`onChange` fires on a **transition**, while the store is built fresh with the view. A main window
appearing *while a run is already under way* was therefore never told: the list stayed live during
a run (FR-DEV-7), and `select`/`deselect` stayed willing to change the selection — which releases
the claim, **under an active write**.

Not hypothetical, and not only in the probe: the bounded cycle is started from the *diagnostics*
window, so the main window can be closed, a run started, and the main window reopened from the
Window menu. Fixed by seeding the state in `onAppear` as well; `setRunActive` ignores a value it
already holds, so it costs nothing when nothing is running. Found because the `content-quitting`
render showed a device list cheerfully advertising that it updates as drives come and go, while
the model said a run was in flight.

#### What was left alone, with the measurement that says why

`.commandsRemoved()` looked like the fix for a cosmetic duplicate: SwiftUI generates a Window-menu
item per `Window` scene, so the app's own **⇧⌘D "Privileged Helper & Diagnostics"** command sits
next to an automatic entry with the same title. Applying it to the diagnostics scene removed the
automatic items for **both** windows — including the main window's, which is the only way back to a
closed main window. Rejected: the duplicate is cosmetic, and the thing it would have cost is not.

### Increment 5 — closed (2026-08-06)

| | |
|---|---|
| **three clean builds** | `build.sh Debug`, `build.sh Release`, `test.sh`, DerivedData wiped before each. **Zero source warnings. 551 tests, 0 failures, 65 suites.** |
| **install** | `install-app.sh Release`, run by the user once the app was quit. Verified afterwards that the installed binary is **newer than every app-target source**, so what is installed is what was tested. |
| **re-register** | Unregistered and re-registered from `/Applications`, confirmed with **Check version** — `install-app.sh` only copies files, so this is what makes the running daemon the new one. |
| **NFR-PERF-4** | **Re-checked and passed**, user-observed against the new binary: a live bounded cycle over the scratch device while scrolling, drag-selecting, resizing, holding a menu open and switching windows, with the metrics still **advancing during** the gestures. |
| **the confirmation** | **Observed in the product**, both entry points. Not renderable — a SwiftUI `alert` gets its own window — so this one always needed a person. |

**No figures are claimed for the last two.** They are observations of behaviour, reported by the
user; nothing was re-measured, and inventing a number for them would be exactly the kind of
authoritative-looking value this project keeps catching itself producing.

### Learnings this work paid for, all of them the same shape

**An empty result is not a finding.** `ioreg -rn "SSD 990 EVO Plus"` returned *nothing*, and it was
read as "this drive has no serial number" — then a comparison table and a design argument were
built on top of it. `-n` matches a registry entry *name*; that string is a property *value*. The
drive has a serial (`013117100578`, on its Ugreen enclosure). A query that matched nothing looks
exactly like a fact about the world.

**Three SwiftUI modifiers compiled, rendered, and did nothing.** `.defaultFocus(…)` on a `List`
left `firstResponder` as the `NSWindow`. `.selectionDisabled(…)` on the `List` *container* instead
of on its rows had no effect at all. `.id(…)` driven by a change token did not make a `List`
re-assert its selection. None produced a warning; each was found only by a person using the app, or
by the probe's `firstResponder` line.

**A sound mechanism behind a trigger that never fires looks exactly like a broken mechanism.** Two
fixes for the selection desync were wired to `selectedDeviceID != requested` — and a ⌘-click on the
already-selected row arrives as `select(thatSameID)`, not as `nil`. The condition was false every
time, so the resync never ran once. Measured from the unified log, after three rounds of reasoning
had produced three wrong answers.

**Prevent, don't undo.** What finally worked was `NSTableView.allowsEmptySelection = false` while a
run is active — stopping the deselection rather than restoring the highlight afterwards.

**A claim about an instrument's limits is itself a claim, and needs measuring.** `ui-probe` was
documented as unable to decide the highlight question because it runs as a parked `.accessory` app.
The diagnostic added alongside that note refuted it in one run — `appActive=true windowKey=true`.
Had the claim stood, every check of that behaviour would have gone to a human forever.

**A placeholder that looks like data.** The Ugreen bridge reports a SCSI INQUIRY serial of
`0000000000000000`. Accepted, it would have become an identifier every drive behind that bridge
model shares — a *wrong* identity that reads as authoritative, which is worse than the transient
BSD name it replaces. Rejected by rule ("a single repeated character"), and `INQUIRY` is
deliberately not used as a fallback: a second source that can return sixteen zeros is not a
fallback.

**And once more: the unified log settles in one query what reasoning does not.** It identified the
⌘-click's true shape, and confirmed that the store refused every mid-run change while the picture
was wrong — which is what established that the *safety* property held throughout, and only the
picture was broken.

**An instrument can measure itself and report the result as a fact about the world.** The
`.terminateLater` probe returned a clean, plausible negative that was entirely an artefact of how
the probe invoked it — and that negative would have disqualified a mechanism for a fictitious
reason, with a comment recording the false finding for whoever came next. What caught it was
asking *why* the mechanism would behave that way and finding an answer that implicated the probe
rather than the framework. This is the same shape as "an empty result is not a finding", one level
up: **a measurement is a claim about the apparatus as much as about the thing measured.**

**A promise the trust boundary cannot keep must not be made, even when the honest one is weaker.**
"Cancel and Quit" cannot stop a run — the helper is inside `pread`/`pwrite` on a raw device and
will finish the chunk plan it was given. So the dialog promises what is deliverable (issue nothing
further, wait rather than walk away) and the code is named for it (`waitForBoundary`, not
`cancelRun`). A "Stop" that does not stop is the throughput-verdict problem in another costume: a
judgement the tool is not entitled to make, dressed as a capability.

### Known-not-discharged, carried forward from this work

- **The NFR-PERF-4 re-check** against the post-increment-3/4 binary, and the **confirmation dialog
  itself** — both need the installed Release build and a person. See "What is left".
- **The `Window` menu behaviour is measured in isolation, not yet observed in the product.** The
  scene probe establishes what `Window` does on this OS; that the app's own File and Window menus
  now read that way is a code-level inference until someone looks at the running app.
- **A main window reopened *during* a run comes back frozen but with no highlighted row.** The
  rows are `selectionDisabled` from the first frame, so the `List` never applies the initial
  selection to its table. The selected-device detail — the surface NFR-USE-3 is actually about —
  is correct throughout, and the model's selection is untouched. Not chased: three earlier attempts
  to make a `List` re-assert a selection all failed and are recorded above.
- **`tools/ui-probe`'s `devices` render cannot show a focus fix in the real app**, because it hosts
  views in a raw `NSWindow` with no SwiftUI `Scene`. First responder is the common ground.
- **`TableSelectionPolicy` depends on `List` being backed by an `NSTableView`.** True on macOS 26,
  not contractual. It **fails safe**: finding no table sets nothing and degrades to a list that can
  look deselected during a run while the model holds. It cannot fail into releasing a device — the
  store's refusals do that, and they are tested and mutation-verified.
- **`MainWindowCloseGuard` depends on SwiftUI routing closes through the window's delegate.**
  Measured on macOS 26, not contractual. It **fails open**: if the guard cannot install, the window
  closes without asking — which is what the app did before it existed, and closing the main window
  does not end a run. The path that *can* abandon a run is termination, and that is guarded
  separately in `applicationShouldTerminate` with no AppKit archaeology in it.
- **The duplicate Window-menu item** for the diagnostics window (SwiftUI's automatic entry plus the
  app's own ⇧⌘D command). Cosmetic, pre-existing, and left alone deliberately — see above for the
  measurement that rejected the obvious fix.

---

## Step 9 — pre-work planning snapshot — SUPERSEDED (kept for audit)

> **Do not read this as current.** It is the state as it stood *before* Step 9 began, and several
> of its assumptions were **falsified by measurement** — most importantly the progress-channel
> mechanism (see D1) and the estimated per-chunk host cost. The step's outcome is the COMPLETE
> summary above; the reasoning is the authoring log below.

**AI-8 / satisfies FR-METR-1..6; NFR-PERF-3/4/5/6/7, NFR-USE-1/2.**
**Measured helper-side, displayed GUI-side.**

Recorded here so a cold start has the state without re-deriving it from the log above.

### State this step begins from

- **Steps 1–8 complete.** `git` clean on `main`.
- **Protocol v7.** `ping`, `protocolVersion`, `validateRunParameters`, `prepareForShutdown`,
  `checkDeviceReadiness`, `acquireDevice`, `releaseDevice`, `deviceProfile`,
  `runRetentionCycle`, `digestRange`.
- **403 tests, 0 failures.** Zero warnings from clean Debug, clean Release **and** a clean
  test-target compile — all three, DerivedData wiped before each.
- Hardware gates passing: `retention-cycle-check.sh disk4` 15/15,
  `geometry-check.sh disk4` 9/9, `large-address-check.sh disk8` 10/10,
  `claim-contention-test.sh disk4` 12/12, `ioctl-constants-check.sh` 11/11,
  `usb-speed-check.sh` 3/3.
- **`Test_Drive` is now full of `/dev/urandom` data and the fill file must stay.** A gate that
  places work at a random offset needs the media to hold real data; see BUILD-PLAN "Test hardware".

### What Step 8 hands over

- **`RetentionTestEngine.run(...)`** — the cycle. Takes a `RawBlockDevice`, so it runs
  identically against `InMemoryBlockDevice` and `FileDescriptorBlockDevice`. Throws **only**
  `RunAbort`; a device failure is never thrown, it is classified and reported.
- **`RunObserver`** — the seam Step 9 builds on. It already receives
  `chunkCompleted(_:timing:)` with `ChunkTiming { readNanoseconds, writeNanoseconds,
  verifyNanoseconds }` per chunk. **Step 8 computes no statistics from these** — it times reads
  solely to feed FR-TEST-9's falsifier. Averages, min/max and p99 are Step 9's, and NFR-PERF-7
  requires the percentile to be **constant-memory**.

  > **Superseded 2026-08-04 (Step 9, increment 3).** `chunkCompleted(_:timing:)` and
  > `ChunkTiming` no longer exist. They fired only for chunks that got through every phase, which
  > stalls a metrics accumulator on a failing drive; `chunkMeasured(_:measurement:)` with
  > `ChunkMeasurement` replaces them and fires **once per chunk, whatever happened**. `RunStart`
  > also gained `logicalBlockSize`. See increment 3 below.
- **`RunClock` / the injected `MonotonicClock`.** `CLOCK_MONOTONIC_RAW`, chosen because it
  *includes* sleep: excluding it would make a read that spanned a sleep look faster, which is the
  direction that falsely accuses the verify of being cached. Injected so timing-dependent
  behaviour is testable without hardware — `SteppingClock` in the tests drives it.
- **`RunSummary`** — outcome, chunk counts, `bytesRead`/`bytesWritten`/`bytesVerified` as three
  separate counters, the bounded `FailureLog`, the final `CacheBypassAssessment`, and
  `bufferBytesHeld`. Step 10's report is assembled from this.
- **`FailureDisposition { continueRun, stopRun }`** — the seam Step 10 fills with FR-FAIL-1/2/3.
  Step 8 ships one caller, which always continues (FR-FAIL-4's default).
- **`RunCoordinator`** — the helper-side bridge, and where the chosen failure mode will be wired.
  `HelperActivity.beginDeviceOperation(_:)` is the one-at-a-time slot for the descriptor.

### Hazards that will bite Step 9 specifically

1. **Do not accumulate per-chunk samples.** NFR-PERF-7 requires constant memory for p99. A 22 TB
   device at 4 MiB is 5,245,440 chunks; an array of samples is the same capacity-scaling defect
   Step 7 removed from the chunk plan and Step 8 removed from the failure list.
2. **Do not push per-chunk over XPC.** NFR-PERF-5 asks for at least one update per second, not one
   per chunk — a chunk is ~25 ms at 500 MB/s, so per-chunk IPC is 40×/s of pure overhead against
   NFR-PERF-3.
3. **Global counters cannot be asserted under parallel tests.** `scripts/test.sh` disables
   parallelism for exactly this reason; anything Step 9 adds that is process-global inherits it.
4. **NFR-PERF-3 has never had a number.** Detailed step 5a and its gate item now require helper
   CPU to be measured against measured MB/s. The 36–39% of one core seen during Step 8's gate was
   the **fingerprint**, which is not in the product; the cycle's per-chunk `memcmp` is expected to
   be far cheaper and is **unmeasured**.
5. **A run is still uncancellable.** Both privileged I/O methods are capped at 1 GiB per call
   because of it. Step 9 adds no cancellation — that is Step 11 — so anything Step 9 introduces
   must not lengthen a single call.

---

## Step 9 — scoping, decisions and authoring log

### Scoping, 2026-08-04

Eight decisions taken before any code. Seven were agreed from the analysis; the eighth (D1) was
deliberately deferred to a measurement, and **the measurement reversed the recommendation**.

| | Decision | Outcome |
|---|---|---|
| **D1** | Progress channel mechanism | **Measured, not chosen.** See below. |
| **D2** | Where the GUI's run trigger lives | Split: the **metrics panel** goes in the main window (real product surface, FR-METR-2/4/5/6, NFR-USE-1/2); the **trigger** goes inside the "Privileged helper & diagnostics" disclosure, bounded to 1 GiB, no pause/resume/stop. Step 11 *deletes* it rather than inheriting it. |
| **D3** | p99 method (NFR-PERF-7) | **Octave-bucketed histogram, 64 sub-buckets per octave**, over 0 … 2⁴⁰ ns (≈18.3 min) = **2,240 buckets × 8 B = 17.5 KiB**, fixed at compile time. Bucket selection is integer-only (`leadingZeroBitCount` + shift + mask) — no floating point, no division, no lookup table. p99 is reported as a *bracketing interval*, not a point estimate. min/max/count kept **exact**. Explicit **overflow counter**, surfaced. |

> **Correction to the D3 figures as first stated (2026-08-04).** Scoping quoted "2,560 buckets,
> 20 KiB, 1.09% max relative width". Those numbers describe *geometric* spacing — 2^(1/64) per
> bucket — which needs floating point or a lookup table to select a bucket. The scheme actually
> built is **linear within each octave** (HdrHistogram's), which keeps bucket selection to a
> handful of integer instructions. Its buckets are therefore 1/64 of the octave's base wide, so
> the relative width runs from **1.5625%** at the start of an octave down to **0.78%** at the
> end — worse than the figure first quoted, and worth the trade: the integer-only hot path is
> worth far more than half a percent of an interval that is already reported as an interval.
> Bucket count and footprint change with it: 2,240 and 17.5 KiB, because the bottom 64 buckets
> hold the values 0–63 exactly rather than being spent on sub-nanosecond octaves that no clock
> can resolve.
| **D4** | Which read is "read latency" | **Both.** The original read is FR-METR-3's (BUILD-PLAN 9.2 says "each original read", and for a *retention* tester it is the meaningful one — it measures the device reading data it has been holding, where the verify read measures data written milliseconds ago and plausibly served from the drive's own DRAM/SLC cache). A **second histogram for the verify read** is carried as well, at 20 KiB, because a cached verify would show as a visibly different distribution — a useful complement to FR-TEST-9. |
| **D5** | The failing-chunk progress gap | Additive `RunObserver` method reporting **every** chunk's outcome with whatever phases were timed. |
| **D6** | ETA scope | **Per-call**, honestly labelled. Whole-device progress and ETA recorded as **not discharged**, carried to Step 11. |
| **D7** | Hardware regression | Step 9 modifies the engine's inner loop, which re-opens NFR-REL-1 — so `retention-cycle-check.sh disk4` is re-run as part of the gate. |
| **D8** | Protocol version | **v8.** |
| **D9** | What throughput reporting is *for*, and how narrow the live reply should be | **A heuristic for the user, not a verdict from the tool** — see below. |

### D9 — throughput is a heuristic the user judges (user decision, 2026-08-04)

Recorded because it constrains this step's protocol surface, Step 10's report wording and Step 14's
honest framing, and because the opposite reading — that a drive tester measuring MB/s is a
benchmark — is the natural assumption for anyone joining cold.

> *"I don't intend this tool to be a performance benchmarking program. The main purpose behind
> i/o rate reporting is more of a heuristic one: the device should have an advertised sustained
> read and write speed from the manufacturer. If we measure something significantly below the
> advertised rate, and after accounting for negotiated speed limits the device is significantly
> underperforming, this can be an indication of excessive wear or impending failure. But this
> judgement will be up to the user to make, not the tool."* — user, 2026-08-04

**Four consequences.**

1. **The tool never grades throughput.** No "healthy"/"slow"/"degraded" verdict, no comparison
   against a built-in expectation, no threshold. It reports what it measured. The manufacturer's
   advertised figure is not something this tool knows, and inventing one would be a judgement
   dressed as a measurement — the same failure mode FR-WARN-3 exists to prevent for a clean pass.
2. **The negotiated link speed must be presented beside the measured rate.** "After accounting for
   negotiated speed limits" is the user's stated method, and they cannot apply it without both
   numbers.

   > **Corrected while building increment 4.** This was first written as "the app *already has*
   > the link speed from `deviceProfile`". It does not: `deviceProfile` has existed on the
   > protocol since Step 7, but `HelperConnection` never calls it — the only callers are
   > `tools/mount-guard-client` and the gate scripts. The claim that this costs **no new
   > privileged surface** still holds, because the method is already there and is passive and
   > side-effect-free; what was wrong is that the app needs to start calling it, which is work
   > rather than a presentation detail.
3. **The live reply stays narrow.** A proposed run sequence number and `isActive` flag were
   dropped: the app issues the run on its own connection and receives its completion there, so it
   already knows the run's lifecycle and does not need the helper to restate it. The reply carries
   what FR-METR-2/4/5/6 require and nothing else.
4. **NFR-PERF-3's diagnostic figures do not belong in a once-a-second reply.** The host-overhead
   ratio and the helper's CPU share are read once, by a gate and by Step 16's release note — not
   watched. They ride on `runRetentionCycle`'s end-of-run reply, where the run's other results
   already are.

**Why D3 rejected the alternatives.** `t-digest` needs floating-point merge invariants and is hard
to pin against an exact answer. `P²` (Jain & Chlamtac) is O(1) memory but is a heuristic with no
statable error bound and known bad behaviour on multimodal distributions — and a drive with a slow
tail *is* multimodal. The deciding property is that a histogram can be validated against an
exactly-computed answer, so **the check can fail**.

**Why D5 exists — a hazard not in the plan.** A chunk whose read, write, or verify-read
*hard-errors* never reaches `observer?.chunkCompleted(...)`: all three `catch` blocks `continue`
past it. (A verify *mismatch* does still emit, having completed all three phases.) So an
observer-based accumulator would see the chunk counter stall while the engine walks on — percent
complete frozen, ETA running away, throughput reading low — **on exactly the drive this tool
exists to find**, and precisely when a user is watching hardest. `failureDetected` cannot fill the
gap: it carries no timing and can fire many times per chunk. On a hard read error there is no
timing at all, because `readNanoseconds` is computed *after* the read, on the success path only.

### D1 — measured, and it reversed the recommendation

**The question.** Step 9 must refresh live metrics at least once per second (NFR-PERF-5). BUILD-PLAN
9.4 assumes a **push** ("the helper sends a metrics snapshot to the GUI over the XPC progress
callback"). A **poll** — one additive query method the GUI calls on a 1 Hz timer — is a far smaller
change, but only works if the daemon will service that second message while it is inside a blocking
privileged call. **Nothing in this project had ever established that.** The only statement about
concurrent delivery is a comment in `HelperActivity`, and it is about two *connections*, not two
messages on one.

Scoping recommended the poll. That was a guess, and it was wrong.

**How it was measured.** `tools/xpc-concurrency-probe` + `scripts/xpc-concurrency-check.sh disk4`,
run 2026-08-04. **Read-only** — the long call underneath the pings is `digestRange`, one SHA-256
read pass, deliberately *not* `runRetentionCycle`: the XPC delivery question is identical for both
(a blocking privileged call holding the device-operation slot) and answering it does not require
putting a byte on the drive. Pings every 100 ms on two connections, each timestamped twice — when
sent and when its reply arrived — both relative to the digest being issued. **0 failures.**

| | same connection (A) | second connection (B) |
|---|---|---|
| pings sent during the call | 24 | 24 |
| answered **during** | **0** | **24** |
| answered **after** | 24 | 0 |
| worst reply during the call | n/a | **7.5 ms** (first), then 0.2–0.3 ms |
| verdict | **serialized** | **concurrent** |

The digest replied at **2,827.9 ms**. Connection A's twenty-four replies landed between **2,828.0
and 2,828.5 ms** — the whole queue draining in ~0.6 ms *after* the call returned. They were queued
and waiting, not lost. Connection B was answered throughout the same window in a fifth of a
millisecond.

**So the daemon is not blocked — the connection is.** That is the finding, and it is more useful
than the yes/no the probe was written to get: it ruled out the recommended option *and* priced a
third one the pre-written verdict branches had not, because the second-connection number did not
exist until the probe produced it.

| Mechanism | Status |
|---|---|
| poll on the run's own connection | **Ruled out.** Measured impossible. |
| push on the run's own connection (BUILD-PLAN 9.4's assumption) | Still rests on a **further unmeasured assumption** — that an outbound send succeeds on a connection whose inbound queue is blocked. |
| **poll on a second connection** | **Measured working.** 24/24 at 0.2–0.3 ms during a live in-flight privileged call. |

**Decided: poll on a second connection (user decision, 2026-08-04).** It is the only one of the
three resting on no unmeasured assumption, and it is also the smaller change: one additive query
method rather than a reverse `@objc` protocol plus an exported object on the app side. The root
daemon keeps the property that it **never initiates traffic to a client**, and the ≥1/s cadence of
NFR-PERF-5 is owned by the GUI's own timer rather than by the daemon. The second connection is
**non-owning** — it never acquires, so `releaseIfOwned(by:)` means its death releases nothing —
and both connections live inside the app's single `HelperConnection`, hoisted to one shared
instance in Step 6 exactly so the device has one owner.

**Two things this establishes beyond D1, which matter to Steps 4, 11 and 12.**

1. **During a run, the run's own connection is unusable for anything else.** `releaseDevice`'s
   carefully worded "the device is in use — try again shortly" refusal, and `prepareForShutdown`'s
   busy refusal, **cannot be delivered** on the connection that started the run. They queue. Those
   messages are only reachable from a *different* connection. This is not a defect — the behaviour
   is correct and Step 8's gate drives one command at a time — but it was an undocumented property
   of the trust boundary, and Step 11's pause/stop and Step 12's device-loss handling both have to
   be designed knowing it.
2. **A second justification for the 1 GiB cap, which nobody had written down.** The cap was
   understood as "do not wedge a root daemon for hours". It is also "do not make the run's own
   connection unanswerable for hours". At ~7 s per call the queueing above is survivable; at
   whole-device scale it would not be.

**One incidental number, recorded so it is not later mistaken for jitter.** Connection B's *first*
ping took 7.5 ms against 0.2–0.3 ms for every subsequent one — the cold start of a fresh connection
(accept, code-signing requirement evaluation, exported object vend). A progress channel's first
sample is ~25× slower than the rest, and that is the reason.

**A defect found in the probe's own reporting, and fixed.** The "worst reply during the call"
figure is a maximum over replies that arrived *during* the window. When none did, that maximum is
`0.0` — and "0.0 ms" printed under that heading reads as *excellent* when it means *never
happened*. A number that reads as a pass when it means "no data" is this project's most expensive
recurring defect, so the no-data case is now spelled out instead of printed as a zero.

### Increment 1 — `Core/LatencyHistogram.swift` (2026-08-04)

D3's constant-memory percentile, plus `LatencyHistogramTests`. **425 tests, 0 failures**
(was 403; +22 test functions, 26 executed cases — one is parameterised over five fractions).
Suite **18.8 s → 20.7 s**, the extra being the constant-memory test.

**Shape, as built and verified.** 2,240 buckets × 8 B = **17,920 bytes**, fixed at compile time.
Values **0–63 ns are exact**, one bucket each; from 64 ns up, each octave is split into 64 equal
sub-buckets selected by `clz` + shift + mask — no floating point, no division, no lookup table.

**Measured on this machine** (`-O`, host-side only, no device involved):

| | |
|---|---|
| `record()` | **2.9 ns** — and flat: 2.96 ns on realistic 4 MiB latencies vs 2.80 ns across every octave |
| `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` | **8.32 ns** |
| worst-case bucket width | **1.5625%** (1/64 at an octave's start, 1/128 at its end) |

That clock figure is the calibration NFR-PERF-3's overhead measurement needs: timing a ~40–80 µs
compare with an 8.3 ns clock costs ~0.02% of the thing being measured, so the measurement does not
distort what it measures. Both numbers are host-side; the **ratio** NFR-PERF-3 actually states
still requires hardware.

**How the tests avoid being vacuous.** Every percentile assertion is against a value computed by
**sorting the samples in the test**, independently of the code under test — and the interval is
additionally required to be tight enough to *exclude the wrong answer*
(`p99ExcludesTheFastPopulationEntirely`, `p50ExcludesTheSlowTailEntirely`). An interval wide
enough to contain both the fast and the slow population would bracket the truth while
distinguishing nothing, which is a green result indistinguishable from a histogram that returns a
constant. The bucket arithmetic is walked **exhaustively** over all 2,240 buckets rather than
sampled, because an off-by-one in bucket selection produces no crash and no error — just a
percentile that is quietly one bucket wrong forever.

**Better than designed, incidentally.** Intersecting a bucket's range with the exact minimum and
maximum is sound (the true value is in both) and tightens the answer for free: p99 of the slow-tail
fixture comes back as **99,614,720–100,000,000 ns**, where the upper bound is the *exact* maximum
rather than the bucket edge, and p100 collapses onto the exact maximum entirely.

**Two errors of my own, both caught before they reached a gate.** A `%s` format specifier given a
Swift `String` segfaulted a scratch harness — the identical bug I had removed from the probe an
hour earlier, reintroduced from muscle memory. And `#expect`'s comment argument is a `Comment`,
expressible by a string *literal*: `"a" + "b"` is a `String` expression and will not convert. Both
were in scratch/test code, neither reached the repo's product path.

### Increment 2 — `Core/RunMetrics.swift` (2026-08-04)

The accumulator: `RunMetrics`, `MetricsSnapshot`, `LatencySummary`, `ChunkMeasurement`,
`ChunkOutcome`. Plus `RunMetricsTests`. **443 tests, 0 failures** (was 425; +18 test functions).
Zero warnings. No engine or observer changes yet — those are increment 3.

**Three rates, and collapsing them is the easy mistake.** A cycle moves **3×** the range it
covers, so there are three different rates and only one of them can drive an ETA:

| Rate | Definition | For |
|---|---|---|
| `readBytesPerSecond` | bytes read ÷ **time spent reading** | FR-METR-1, the device's read speed |
| `writeBytesPerSecond` | bytes written ÷ **time spent writing** | FR-METR-1 |
| `coverageBytesPerSecond` | range bytes ÷ **wall-clock elapsed** | FR-METR-5, and the *only* correct ETA denominator |

Using the read rate for the ETA would make every estimate ~3× too optimistic and would look
entirely plausible. `coverageIsAboutOneThirdOfTheReadRateAndTheyAreNotInterchangeable` is the
assertion that catches it.

**Progress advances on failure**, by counting *attempted* work — the A7 hazard as an assertion
(`progressAdvancesThroughAChunkThatFailed`).

**The histograms hold only reads that returned data.** A failed read's duration is a failure
duration, possibly a long controller retry; folding it into "read latency" would make p99 report
a broken drive as a slow one. That time is reported as `failedPhaseNanoseconds`, not dropped
(`aFailedReadsDurationIsNotReadLatency`, using a 30-second injected failure against 8 ms reads).

**NFR-PERF-3 finally has a shape.** `hostOverheadFraction` = host work ÷ device I/O time, measured
in the product's own run path rather than inferred from a CPU percentage — and
`unaccountedNanoseconds` sits beside it as the completeness check, because an overhead fraction
computed from a small accounted slice would be measuring a fraction of the story.

**ETA convergence, which the 1 GiB cap makes unobservable on hardware.** `RunMetrics` calls no
clock — every entry point is handed the reading — so a run of any shape is synthesisable exactly.
A 100-chunk run whose rate changes partway (20 chunks at 20 ms, then 80 at 5 ms; true total
800 ms):

| chunk | elapsed | ETA | true remaining | error |
|---|---|---|---|---|
| 1 | 20 ms | 1980 ms | 780 ms | 1200.00 ms |
| 20 | 400 ms | 1600 ms | 400 ms | 1200.00 ms |
| 40 | 500 ms | 750 ms | 300 ms | 450.00 ms |
| 60 | 600 ms | 400 ms | 200 ms | 200.00 ms |
| 80 | 700 ms | 175 ms | 100 ms | 75.00 ms |
| 99 | 795 ms | 8 ms | 5 ms | **3.03 ms** |
| 100 | 800 ms | 0 ms | 0 ms | 0.00 ms |

The error is **flat at 1200 ms through the constant-rate opening**, and that is correct rather
than a defect: while the rate is steady the cumulative average equals the current rate, so the
estimate is exactly right *for a run that continues as it has been*, and the whole error is the
future rate change that no measured-throughput ETA can predict (NFR-COMPAT-7 forbids assuming
one). Convergence starts when the rate actually changes. The test's first sample point sits at
chunk 20 deliberately; a sample point inside the flat opening would compare 1200 against 1200 and
fail the strictly-decreasing check for a reason unrelated to convergence.

This discharges the *arithmetic* half of BUILD-PLAN gate item 3. The observed-on-real-media half
is still owed, and the multi-hour observation the gate's wording implies remains **not
dischargeable** under the 1 GiB cap — see conflict 2.

### Increment 3 — the engine and observer wiring (2026-08-04)

No new files, so no GUI ticks — but this is the increment that **changes the write loop**, which
re-opens NFR-REL-1. **460 tests, 0 failures** (was 443; +17), zero warnings.

**`ChunkTiming` is gone; `ChunkMeasurement` replaces it.** Step 8's `chunkCompleted(_:timing:)`
fired **only for chunks that got through every phase** — all three `catch` blocks `continue` past
the emission. Harmless while nothing computed statistics from it; a defect the moment something
did. `chunkMeasured(_:measurement:)` fires **once per chunk, whatever happened**, and says which
phase was reached. It carries a strict superset of what `ChunkTiming` did, which is why that type
was removed rather than kept alongside — two representations of one fact are two things that can
drift. Blast radius was one test recorder: `timings` and `completedChunks` both had **zero**
consumers outside it.

**`RunStart` gained `logicalBlockSize`.** Without it an observer cannot turn `blockCount` into
bytes, and every FR-METR metric is denominated in bytes — so a run's size was not derivable from
what Step 8 handed over. `rangeByteCount` comes with it.

**`ObserverFanOut`.** The engine takes one observer and the helper now needs two — the one that
logs (NFR-OBS-1) and the one that accumulates (FR-METR-*). Composing them beats having the logger
forward, which is the same forget-a-method hazard in miniature. **Stop wins**, and every observer
is asked with no short-circuiting: a passive observer answering the default `.continueRun` must
never be able to override a decision to stop.

**Host overhead is the chunk's whole span minus its device phases.** That captures *everything* in
the iteration that is not a device call — the write-guard re-check, the compare, the loop's own
bookkeeping — rather than only the parts somebody remembered to time. It costs **one extra clock
read per chunk** (~8.3 ns, measured in increment 1). The span is captured *before* the observer is
called, so the figure does not vary with what the observer costs; nothing is hidden by that,
because `unaccountedNanoseconds` measures the wall clock independently and would show an expensive
observer as unaccounted time. One documented exception: for a *mismatching* chunk the scan has
already called the observer once per differing range, so those chunks' overhead includes it. On a
healthy drive the scan is a single `memcmp` that calls nobody, which is the case NFR-PERF-3 is
about.

**The mutation test — this is the evidence, not the green suite.** BUILD-PLAN's Step 7 lesson is
that a check never shown capable of failing is a substitute for a test. So the `measure(...)` call
was deliberately deleted from the failed-read path and the suite re-run. **Six tests across four
suites caught it:**

- `aReadFaultStillProducesAMeasurementForThatChunk`
- `everyMixOfOutcomesStillMeasuresEveryChunkExactlyOnce`
- `theChunkAStopHappenedOnIsStillMeasured`
- `aFailedReadsOverheadIsMeasuredFromItsShorterSpan`
- `everyEventReachesEveryObserver`
- `progressReachesTheEndEvenWhenChunksFail`

The last one matters most: it is the **actual hazard** — a run with two failing chunks must still
reach 100% and still finish at the last block — rather than a proxy for it. The engine was
restored and the suite is green at 460.

**The overhead subtraction is asserted exactly, without any real timing.** The engine reads its
clock a fixed number of times per chunk — 8 for one that completes, 3 for one whose read failed —
so under a constant-step clock the overhead is exactly 4 steps and 1 step respectively. The 4:3
host-to-device ratio that implies is nonsense as a performance figure, because a stepping clock
gives a `memcmp` the same duration as a device read; what is asserted is that the *subtraction* is
right. NFR-PERF-3's real number still comes from hardware.

**All of Step 8's simulation proof passes unchanged** — non-destructiveness, verify mismatch, hard
errors, one-chunk-in-flight, bounded range, write guard, stop path, cache bypass. D7's hardware
regression (`retention-cycle-check.sh disk4`) is still owed, because simulation passing is not
evidence about real media.

### Increment 4a — protocol v8 and the helper side (2026-08-04)

No new Core files, so no GUI ticks. Debug builds, **460 tests still green**, zero warnings, and
all three protocol-dependent tools typecheck against v8.

**Protocol v8.** Adds `runProgress` (11 primitives) and widens `runRetentionCycle`'s reply from 8
to 10 with NFR-PERF-3's two figures. A signature change, so the bump is mandatory rather than
merely cheap — a v7 daemon would decode the cycle's reply block differently.

**No sentinel means two things.** Every "not yet known" is `-1` for a rate and a sample count of
`0` for the latency figures — never a `0` rate. Zero MB/s means *stalled*, which is real and
alarming; using it for "nothing has happened yet" would print an alarm to report an absence. This
is the same defect found in the D1 probe's own reporting a few hours earlier, avoided by having
just been bitten by it.

**Two simplifications fell out of D9.** An earlier sketch had a `MetricsPublisher` copying a
computed `MetricsSnapshot` into a box after every chunk, with a 100 ms throttle so it would not
recompute a percentile forty times a second. Both were solving a problem the design created: hold
the **accumulator** behind the lock instead, and the snapshot — percentile included — is computed
once per *poll*, on the poller's thread, about once a second. The run's per-chunk cost is one
uncontended lock acquisition around ~3 ns of histogram work; nothing is computed for a reader that
has not asked. No throttle, no copying, no publisher.

**And the lock has no logic to test.** `SynchronizedMetricsObserver` is a lock around Core's
already-tested `RunMetricsObserver`, so the helper file needs no test-target membership and no GUI
tick. Anything with a decision in it that ends up in `MetricsChannel.swift` is in the wrong file.

**NFR-PERF-3's CPU figure** is `getrusage(RUSAGE_SELF)` bracketing the cycle — two syscalls per
run, not per chunk — reported as a fraction of one core, `nil`/`-1` when it cannot be established.
Process-wide, which is the honest scope: during a cycle the daemon does nothing else except answer
progress polls, and those polls are part of what the product costs. It replaces the figure that
came from watching Activity Monitor, which was measuring the gate's SHA-256 rather than the
product.

**`metrics` is now a live `os_log` category** — the last of the six named in `HelperIdentity`.
One line per run, never per chunk, and carrying **no verdict** (D9).

### D10 — whole device, block 0, and 1 MiB placement (user decisions, 2026-08-04)

Four decisions taken after a proposal to let the user type a starting block was rejected. Two of
them are **requirements amendments**, recorded in the FR document (2026-08-04 entry): **FR-TEST-10
added**, **FR-CTRL-8 revised**.

| | Decision |
|---|---|
| Placement | **Whole device only, always start at block 0.** Random placement was a *gate* technique for testing a bounded region without writing a terabyte; it was never a product policy, and I had wrongly carried it across. |
| Alignment | All I/O begins on a **1 MiB boundary**; a bounded call covers whole MiB units unless it ends at the device's last block. **The helper enforces both.** |
| Progress control | A **progress bar with a live percentage**, not a slider — a slider implies a draggable thumb, and the starting block is never user-selectable. |
| I/O size | Changeable while **paused or stopped**, fixed while running; a resumed run continues from its pause point at the newly selected size (FR-CTRL-8, revised). |
| Latency across a size change | **Keep accumulating**, do not reset. |

**Why 1 MiB is a correctness rule and not a tidiness one.** A misaligned start makes the device
read-modify-write internally, which depresses measured throughput and adds wear. Throughput here
is a **wear heuristic the user judges** (D9), so accepting a misaligned start would manufacture the
exact signal the measurement exists to detect — a systematic bias toward "this drive looks worn",
on a tool whose output is a judgement about somebody's hardware.

**Why the length rule, not just the start.** A whole-device run is a *sequence* of ≤1 GiB calls.
A call covering a partial MiB leaves the next one misaligned, so enforcing only the start would let
a caller walk itself out of alignment one call at a time.

**It is self-maintaining, which is the point.** Runs begin at block 0 and every permitted transfer
size is a whole number of MiB, so every position reachable — under any mix of sizes, including a
change on resume — is an integer number of MiB. The helper's check is a guard against a **caller**,
never against the engine's own arithmetic. `SelfMaintainingAlignmentTests` asserts this over 500
steps with a size change at every one, rather than arguing it.

**Why latency keeps accumulating across a size change.** An 8 MiB read takes roughly twice as long
as a 4 MiB one, so a run whose size changed has a bimodal distribution and p99 can be dominated by
whichever size ran longer. Resetting would make each statistic describe the size currently in use —
but it would also **delete the evidence** of a 30-second read that happened before the change, which
is precisely the retry behaviour this tool exists to surface. Losing evidence is the worse failure.

**The rule broke an existing gate, and reading caught it rather than hardware.** Step 8's
`retention-cycle-check.sh` requested `1 GiB − 512 KiB` — deliberately, to force a short final chunk
on real media — which is **1023.5 MiB**, in the middle of the device, and would have been refused.
It would have been refused roughly **35 minutes in**, immediately after the before-fingerprint pass:
the same failure shape the D1 pre-flight was written to avoid. Changed to `1 GiB − 1 MiB`, which
still yields 255 full 4 MiB chunks plus a short 3 MiB one, so FR-TEST-5 is still exercised and the
expected chunk count is unchanged at 256. Both constants are now pinned by
`StepEightGateCompatibilityTests`, so the compatibility is a test rather than a memory.

### Increment 4b — the app side, and the GUI (2026-08-04)

**497 tests, 0 failures** (was 460), zero source warnings, Debug builds.

**Presentation is a pure function of a snapshot.** `RunMetricsView` owns no timer, no connection
and no state, which is what lets `scripts/render-ui.sh metrics` render it from a fixture and check
the layout headlessly; `LiveRunMetricsPanel` is the thin shell that owns the 1 Hz timer. A view
that fetched its own data could only ever be seen by running the signed app against a live daemon.

**The wire's sentinels stop at one place.** `RunProgressSnapshot`'s decoding init is the only code
that interprets `-1` and a zero sample count; every consumer above it sees `nil`. Verified visually
as well as by test — the `metrics-idle` render shows **every unmeasured value as an em-dash**, and
`MetricsFormatting` has no path from `nil` to a digit.

**Throughput is decimal MB, not MiB**, because the point of showing it is comparison against a
figure quoted in decimal megabytes on the box (D9). Using 2²⁰ would make every reading ~4.8% lower
than the advertised number for no reason the user could see — a bias in the "looks worn" direction.

**The GUI trigger is deliberately unconfigurable**: block 0, 4 MiB, 1 GiB, no controls. The
dropdown is Step 11's, because its whole behaviour is defined in terms of pause and resume. It
fetches `deviceProfile` first — not politeness, but because 1 GiB is a byte figure and the request
is in blocks, and assuming 512 would ask for eight times the intended range on 4,096-byte geometry.

**Three defects found and fixed in this increment.** The `Duration` extension needed `nonisolated`
(the app's MainActor default reaching an extension on a standard-library type — the Steps 5/6
gotcha in a new place). `Timer.publish(…).autoconnect()` needed an explicit `import Combine`, because
the project builds with `MemberImportVisibility` enabled and SwiftUI re-exporting it is not enough.
And the idle placeholder was an **overlay**, leaving a row of em-dashes visible behind it — the
panel showed empty measurements *and* a note saying there were none, one of which looked like data.
Replaced rather than overlaid.

### Increment 5 — the hardware gate, authored (2026-08-04)

`tools/metrics-probe` and `scripts/metrics-check.sh <disk>`. **Not yet run** — it needs a v8
daemon, which needs an install.

Structured the way the app is, because that is the only way to test what the app does: connection
A issues `runRetentionCycle` and blocks; connection B polls `runProgress` twice a second and
timestamps every reply. **It writes** — the first 1 GiB from block 0 — and it deliberately does
**not** re-prove non-destructiveness; `retention-cycle-check.sh` is what fingerprints the device
either side of a run, and that is the Step 9 regression D7 asks for.

Two anti-vacuity guards, both learned from earlier steps:

- **Mid-run snapshots are counted separately.** Snapshots arriving only before or after the run
  would prove nothing about delivery *during* a blocking privileged call, which is the entire
  question. The gate requires at least five with `0 < fraction < 1`.
- **The latency distribution must have spread.** `min <= p99 <= max` is satisfied trivially by a
  degenerate distribution where every read is identical, so `max > min` is asserted separately.

And the CPU figure is **cross-checked from outside**: a `ps` sampler runs alongside the cycle,
because a self-reported number that nothing can contradict is a number rather than evidence.

### Verification status — 2026-08-04, before the hardware session

**497 tests, 0 failures.** Zero source warnings from **all three** clean builds with DerivedData
wiped before each: `build.sh Debug`, `build.sh Release`, `test.sh`. (The three-command form is
Step 8's lesson — `build.sh` does not compile the test target, and two of the three had been the
whole check for seven steps.)

Everything that can be verified without hardware is verified. What remains needs a v8 daemon and
the drive:

| | |
|---|---|
| Install + register v8 | `scripts/install-app.sh Release`, then unregister/re-register in the app and confirm with **Check version** |
| Step 9's gate | `scripts/metrics-check.sh disk4` — **writes** the first 1 GiB, ~15 s |
| D7's regression | `scripts/retention-cycle-check.sh disk4` — **writes**, ~70 min with the fingerprint passes |
| GUI items | Live metrics refreshing ≥ 1/s and the window staying responsive during a real run — observed, not rendered |

### D7's regression — PASSED on hardware (2026-08-04)

`./scripts/retention-cycle-check.sh disk4` — **15 checks, 0 failures**, against the live **v8**
daemon. Placement block **309,460,992**, drawn at random from 238,212 chunk-aligned positions.

**The check that mattered: `every one of the 932 window fingerprints is unchanged (NFR-REL-1)`.**
Step 9 rewrote the engine's inner loop — a span timer, an outcome-carrying measurement emitted on
every path including the three failure branches — and the whole terabyte is byte-identical after
writing 1,072,693,248 bytes. Also confirmed: 256 chunks (255 full + 1 short, FR-TEST-5), cache
bypass still `bypassed`, buffers still 2 × I/O size, fastest read 494,579,710 B/s.

**FR-TEST-10 was live and this run satisfied it.** Start offset 158,444,027,904 bytes is exactly
151,104 MiB; length 1,072,693,248 bytes is exactly 1023 MiB. The run does **not** end at the
device's last block, so it passed on the length rule alone — the old `1 GiB − 512 KiB` constant
would have been refused, as predicted.

> **But a passing run is not evidence a guard is enforced.** It shows the rule did not get in the
> way. An unenforced guard looks exactly like an enforced one until something misaligned arrives.
> So `metrics-probe` now asks for **both** forbidden placements explicitly — a start one block past
> zero, and a length one block short of a whole MiB in the middle of the device — and
> `metrics-check.sh` requires both to be refused **with zero chunks processed**. Neither performs
> any I/O: placement is validated before a block device is vended.

### NFR-PERF-3 — the number it has never had (measured 2026-08-04)

Measured **in the product's own run path**, not inferred from a CPU percentage and not from the
gate's SHA-256:

| | |
|---|---|
| host overhead ÷ device I/O time | **2.686%** — the run is **97.3% device-bound** |
| daemon CPU | **5.269% of one core** at ~495 MB/s |

For comparison, the figure this replaces: 36–39% of one core, observed in Activity Monitor during
Step 8's gate, which was the *fingerprint's* SHA-256 and is not in the product at all. The product's
run path is roughly seven times cheaper.

**My estimate was wrong by 11×, and recording that is the point of having measured it.** Step 8's
note predicted "order 40–80 µs [of host work] against ~25 ms of I/O"; the measurement is
**683 µs per chunk** against 25.44 ms. A `memcmp` over two 4 MiB buffers touches 8 MiB and is
memory-bandwidth bound, which plausibly accounts for much of it — but that is a hypothesis, and the
only reason the 40–80 µs figure survived this long is that nobody had measured it. It is not
re-estimated here.

**This triggers BUILD-PLAN 9.5a's release-note item.** The gate item says: *if the ratio implies
the host becomes the limit at a transport speed the product plausibly meets, that is a release-note
item, carried to Step 16.* Holding host work per chunk constant:

| transport | device time / chunk | host overhead as % of it |
|---|---|---|
| USB 3.1 Gen 2 (measured) | 25.44 ms | **2.7%** |
| USB 3.2 Gen 2×2 | 6.29 ms | **10.9%** |
| USB4 / Thunderbolt | 3.31 ms | **20.6%** |

The daemon saturates one core at roughly **4.7 GB/s**, and host work equals device time at roughly
**18.4 GB/s**. USB4 enclosures exist and this product plausibly meets them, and 20.6% is not
"negligible" in NFR-PERF-3's sense. **Carried to Step 16 as a release-note item.**

> **Superseded and partly WRONG — corrected 2026-08-05 by the four-size sweep.** Left in place
> rather than edited, because the error is the point: **"4.7 GB/s" was an arithmetic mistake**, a
> stray factor of 0.5. The correct figure is **11.1 GB/s** — more than double the headroom. The
> figure also rested on a single 4 MiB point and used the *fastest observed read* as the
> throughput rather than the run's actual rate. See "The sweep, and NFR-PERF-3 finalised" below.
> The percentage columns above survived the correction; the saturation point did not.

### Increment 6 — the I/O-size sweep, and the diagnostics window (2026-08-04)

**The gate now sweeps all four I/O sizes** (user decision). It runs the same gibibyte at 1, 2, 4
and 8 MiB, which gives an **8× lever on chunk count at constant bytes** — enough to settle the
question the 4 MiB-only measurement left open: does host cost follow **bytes moved** or **chunk
count**? The two imply opposite advice about I/O size, so the Step 16 release note could not say
anything until this was measured. It also exercises the chunk plan at every size the UI offers, on
real media, which nothing had done.

The analysis reports µs/chunk and µs/MiB per size and states which normalisation is flat.
**Verified against synthetic data before the hardware run** — fed a pure-bytes profile, a
pure-chunks profile and a mixed one, it returns all three verdicts correctly. A verdict that can
only reach one conclusion is not a verdict.

**The diagnostics panel is now its own window** (user decision: the main window's vertical space
had become excessive).

> **Not a sheet, and the reason is functional.** The control that *starts* a run lives in
> diagnostics; the metrics panel that *displays* it lives in the main window. A modal would cover
> the one thing worth watching, for the whole of the run it had just started. A separate
> non-modal window sits beside it.

**One connection, hoisted into `AppModel`.** This is a correctness requirement, not tidiness: the
helper releases a device claim when the connection that acquired it goes away (NFR-REL-5), so two
scenes each building their own `HelperConnection` would be two owners — and closing the diagnostics
window could drop a claim out from under a run in the main window. It is the same hazard Step 6
hit when the device list gained its own reason to talk to the helper, solved the same way, one
level up. Step 11's state machine replaces the run-state fields this class currently stands in for.

`Window` rather than `WindowGroup`: there is one helper and one registration state, so a second
copy of the panel would be two views of one truth that could disagree. Opened from the Window menu
or **⇧⌘D**.

**A stale instruction found by rendering.** The device panel's readiness banner told the user to
install the helper *"under 'Privileged helper & diagnostics' **below**"* — which stopped being
true the moment the panel became a window. NFR-USE-5 asks for the corrective step, and a
corrective step pointing somewhere the control is not is worse than none. Now points at the window
and names the shortcut.

**And the height was measured rather than guessed.** At 620 pt the mount controls fall below the
fold; 700 pt is where the idle window stops clipping. That is only 20 less than Step 6's 720 —
moving the diagnostics form out bought back roughly what the metrics panel spends. The panel is
~55 pt idle and ~300 pt with a run in progress, so the *running* window wants nearer 900. If that
proves excessive the next lever is making the selected-device detail collapsible, rather than
shrinking anything that carries a warning.

### First hardware run of `metrics-check.sh` — 8 failures, all mine, none in the product

**What passed, and it is the substance of the step.** At every one of the four I/O sizes: the
cycle completed every planned chunk (1024 / 512 / 256 / 128), no failed ranges, FR-TEST-9 still
`bypassed`, buffers exactly 2 × the I/O size, **13–16 snapshots delivered mid-run while the
privileged call was blocking**, widest gap **505 ms** against NFR-PERF-5's 1000, progress
monotonic, `min ≤ p99 ≤ max` with real spread, and transport-plausible throughput.

**And FR-TEST-10 was shown refusing**, which a passing run cannot show: a start at block 1 and a
length one block short of a whole MiB were both refused, **with zero chunks processed**, each with
a message naming the rule and the reason.

**The 8 failures were one probe bug.** Every "final" figure was exactly `samples ÷ chunks` —
96.39% = 987/1024, 95.31% = 488/512, 93.75% = 240/256, 96.09% = 123/128. The polling loop exits
the instant the cycle replies, so its newest snapshot was the one caught up to a poll interval
*before* the end; **nobody ever asked the helper what the completed state was.** The runs had all
completed. Fixed by issuing one more `runProgress` after the reply — `MetricsChannel` keeps the
finished run's accumulator until the next run replaces it, so that final ask is the run's real
end state.

The arithmetic is what identified it. A failure that is off by an arbitrary amount is a mystery;
one that is off by exactly the polling granularity, at four different chunk counts, is a
measurement artefact.

**A second probe artefact, fixed in the same place.** Each table's first row read 100% and then
dropped to 3%, because `MetricsChannel.begin()` runs inside `runCycle` *after* validation —
correctly, so a refused run does not wipe the previous run's figures — leaving a few milliseconds
in which a poll still sees the **previous** size's completed snapshot. The probe now settles 250 ms
before its first poll, the same fix and the same reasoning as the D1 pre-flight.

### "The Run one bounded cycle button appears to do nothing" — it worked; the button was wrong

The unified log settled it in one query:

```
07:28:51.596  deviceProfile from pid 49059: no device is held
07:28:51.625  discovery frozen (run active)      <- cycleIsRunning went true
07:28:51.650  discovery resumed                  <- and false again, 25 ms later
```

Three presses, three identical sequences. The binding propagated, the call went out, the helper
answered truthfully, and the whole thing was over in **25 ms** — a spinner for one frame and a
failure message.

**The defect is that the button was pressable at all.** Every other control in this app disables
itself and names the corrective step (FR-SAFE-4, NFR-USE-5); the connection section literally says
"These are disabled until the helper is enabled above". This one stated its precondition **in
prose** and then looked live. *Prose is not a precondition.*

Fixed: the button is disabled unless a device is held, with the corrective step spelled out
underneath. That required `helperHoldsDevice` to move into `AppModel` — the device is acquired in
the **main** window and the cycle is started in the **diagnostics** window, so neither view can own
it. `DeviceListView` now reads it through the model rather than keeping a `@State` mirror, because
a second copy of that answer would eventually disagree with the first about whether a run may be
offered.

**Two stale spatial references, both found by rendering rather than by reading.** The device
panel's readiness banner said to install the helper *"under 'Privileged helper & diagnostics'
**below**"*, and the bounded-cycle section said it would give *"the metrics panel **above**"* a run
to display. Neither was true once the panel became a window. A corrective instruction pointing
where the control is not is worse than none — the first told the user to look somewhere the thing
had never been.

`ui-probe` gained a `diagnostics-held` view so both states of the button are renderable, since the
disabled one is what a user meets first and is the one that was reported as broken.

**497 tests, 0 failures; zero source warnings from all three clean builds** after these fixes.

### The sweep, and NFR-PERF-3 finalised — `metrics-check.sh disk4`, **0 failures** (2026-08-05)

Every hardware-only gate item discharged, at **all four** I/O sizes.

| | 1 MiB | 2 MiB | 4 MiB | 8 MiB |
|---|---|---|---|---|
| chunks | 1024 | 512 | 256 | 128 |
| progress reached | 100.00% | 100.00% | 100.00% | 100.00% |
| latency samples | 1024 | 512 | 256 | 128 |
| mid-run snapshots | 14 | 13 | 14 | 13 |
| widest gap | 505.4 ms | 505.3 ms | 505.3 ms | 505.4 ms |
| read / write | 517 / 491 | 516 / 491 | 488 / 492 | 501 / 492 MB/s |
| p99 (min ≤ p99 ≤ max) | 2.195 ms | 4.162 ms | 9.175 ms | 17.302 ms |

**NFR-PERF-5 is discharged with a factor of two in hand**: the widest gap between live snapshots
was **505 ms** against a 1000 ms requirement, and 13–14 of them arrived *while the privileged call
was blocking* — which is the property the whole second-connection design exists to provide, and
which no amount of simulation could have shown.

**FR-TEST-10 was shown refusing**, not merely shown not-refusing: a start at block 1 and a length
one block short of a whole MiB were both refused with **zero chunks processed**, each naming the
rule and the reason.

**The open question is answered: host cost follows BYTES MOVED.** µs/MiB varied **1.32×** across an
8× range of I/O size while µs/chunk varied **8.65×**. A larger I/O size does **not** reduce host
overhead. Step 16's release note can now say something true instead of nothing.

**NFR-PERF-3, final:** at the 4 MiB default with the device moving ~470 MB/s, in-span overhead is
**2.55%** and daemon CPU **4.22% of one core** — the run is **97.4% device-bound**. The independent
`ps` sample peaked at **8.5%**, the same order as the self-reported figure, which is what that
cross-check exists to establish.

**A correction to what I reported yesterday.** I said the daemon saturates one core near
**4.7 GB/s**. That was an arithmetic error — a stray factor of 0.5 — and it understated the
headroom by more than half; the figure is **11.1 GB/s**. It also rested on a single 4 MiB point and
used the *fastest observed read* rather than the run's actual throughput. Both are fixed above and
in BUILD-PLAN Step 16.

**And one thing measured but not explained.** Total daemon CPU fits roughly **209 µs fixed per
chunk + 207 µs per MiB**, while the *in-span* overhead follows bytes alone. The difference is work
outside the timed span — which the span is documented to exclude, since it stops before the
observer is called. What that per-chunk term is has not been measured and is **not guessed at
here**: the 40–80 µs estimate that stood for three steps was wrong by 11× for exactly the want of
measuring rather than reasoning.

**D7's regression still stands.** Verified rather than assumed: **no file in the helper, `Core/` or
`Shared/` has changed** since `retention-cycle-check.sh disk4` passed 15/15 with all 932 window
fingerprints unchanged. Everything modified since is app-target UI, a tool, or a script.

---

## Step 9 — state as it stood before the step closed (2026-08-05) — SUPERSEDED

> **Superseded by the COMPLETE summary at the top of this step.** Kept because its "what the next
> step inherits" list is more detailed than the summary's, and that list is still current. What is
> **no longer true** is the framing: NFR-PERF-4 was discharged later the same day, so nothing in
> this step is outstanding.

Everything above is the working log; this was the state.

### Done and verified

**497 tests, 0 failures. Zero source warnings from all three clean builds** — `build.sh Debug`,
`build.sh Release`, `test.sh`, with DerivedData wiped before each. (Three commands, not two: Step 8
found that `build.sh` does not compile the test target.)

| Hardware gate | Result |
|---|---|
| `xpc-concurrency-check.sh disk4` (D1 pre-flight, read-only) | 0 failures — decided the whole design |
| `metrics-check.sh disk4` (Step 9's gate, writes) | **0 failures**, all four I/O sizes |
| `retention-cycle-check.sh disk4` (D7 regression, writes) | **15/15**, 932 fingerprints unchanged |

Protocol **v8**. Helper installed from `/Applications`, registered, running v8, Full Disk Access
granted. `disk4` byte-identical after every run.

### The one thing that was still outstanding — since discharged

**NFR-PERF-4 — "GUI stays responsive (scroll/interact) throughout".** It could not be rendered and
could not be asserted from a script; it needed a person to interact with both windows during a live
run.

Recorded here because of the trap it set. The user had confirmed earlier the same day that the
**Run one bounded cycle** button worked and the live progress display "looks good" — which covers
the ≥1/s refresh and the panel itself, and covers **nothing** about responsiveness. Reading it as
covering both would have ticked a box on evidence for a different question.

**Discharged 2026-08-05**, later the same day: two live bounded cycles with the main window
scrolled, drag-selected, dragged and resized, a menu held open, and focus switched between both
windows. No stalls, clean redraws, and the metrics kept advancing *during* the gestures — the part
only interaction can settle, and the one a `.default`-mode timer would have failed while the run
underneath carried on perfectly.

### Requirements changed during this step

- **FR-TEST-10 — added.** All I/O begins on a **1 MiB boundary**; a bounded call covers whole MiB
  units unless it ends at the device's last block. Helper-enforced.
- **FR-CTRL-8 — revised.** I/O size is now configurable while **paused or stopped** as well as
  before a run, fixed only while actively running; a resumed run continues at the newly selected
  size.
- **NFR-PERF-3 — measured, wording unchanged.** Recorded in the NFR document's amendments.

Both FR changes have full amendment entries in `functional-requirements-usb-drive-tester.md`
(2026-08-04). The ADR's checkboxes remain untouched, as they have been for every step.

### What the next step inherits that it must not re-derive

- **A second XPC connection is mandatory for anything asked of the helper during a run.** Measured:
  a second message on a connection with a blocking call in flight is **not delivered until that
  call returns**; a second connection is answered in 0.2–0.3 ms. Step 11's pause/stop has exactly
  this shape and cannot use the run's own connection unless it first makes the run call
  non-blocking.
- **`releaseDevice`'s and `prepareForShutdown`'s busy refusals are only reachable from another
  connection**, for the same reason. Both are correct; neither had been shown to be deliverable.
- **The 1 GiB per-call cap is still load-bearing** and now has a second justification: it bounds
  how long the run's own connection is unanswerable.
- **`ChunkTiming` and `chunkCompleted` are gone**, replaced by `ChunkMeasurement` and
  `chunkMeasured`, which fire **once per chunk whatever happened** — the failure paths included.
- **Progress is byte-denominated, never chunk-denominated**, which is what lets FR-CTRL-8's
  mid-run size change work at all.
- **Whole-device runs start at block 0 and there is no user-selectable start**, by decision. The
  GUI's bounded-cycle button is scaffolding Step 11 deletes.

### Known-not-discharged, carried forward

- ~~**NFR-PERF-4**, above.~~ **Discharged 2026-08-05** — see above and BUILD-PLAN Step 9's gate.
- **`File ▸ New Window` opens a second main window** (found 2026-08-05, open). The main scene is a
  `WindowGroup`; two main windows would be two `DeviceDiscovery` instances with independent
  selections sharing one claim, so they could disagree about which drive is selected while only one
  is held (NFR-USE-3). The diagnostics scene already avoids this by being a `Window`.
- **The final chunk at the physical end of the scratch device, and a whole-device traversal.** Unchanged from
  Step 8: neither is reachable under the placement rules used so far, and both belong to a later,
  separately agreed run.
- **Whole-device progress and ETA.** Step 9's are per-call, because a run is one bounded call until
  Step 11 sequences them.
- **What the ~209 µs per-chunk term in the daemon's CPU actually is.** Measured, not explained, and
  deliberately not guessed at.
