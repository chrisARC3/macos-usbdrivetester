# Step 1 — Xcode workspace (two targets)

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

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
