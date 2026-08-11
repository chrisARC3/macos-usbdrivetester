# Step 4 — Helper lifecycle teardown

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

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
