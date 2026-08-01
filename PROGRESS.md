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
