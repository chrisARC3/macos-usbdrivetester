# Step 3 — SMAppService + XPC protocol + code-signature validation

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

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
