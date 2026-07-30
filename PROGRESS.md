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
