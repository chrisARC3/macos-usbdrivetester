# Step 11 — increment 12, planned and approved

**Written 2026-08-25/26, before any code**, for increments 9–11. **Increments 9, 10 and 11 have
landed and their sections were deleted from here**, as the rule below instructs — 9 on 2026-08-27,
10 on 2026-09-02, 11 on 2026-09-03; **increment 12 was added 2026-09-01**, unplanned, having been
produced by walking increment 9's own checklist chunk. Every decision below was taken by the user
during scoping and is **settled**. This file exists so a cold session can execute them without
re-deriving them, and without re-opening choices that were already argued through.

**This is a plan, not history.** When an increment is built, its full account goes in its commit
message and its summary into `PROGRESS.md`, as always. Delete the section from here when it lands.

> **Read `CONSTRAINTS.md` and `PROGRESS.md` first.** This file assumes both. It carries only what
> is not yet anywhere else.

---

## Where this came from

Increment 8 ended with the negotiated USB link speed moved into the **Selected device** pane and
the standing backup advice deleted from it. Walking the human checklist for that change
(chunk 12, passed in full 2026-08-25, `e0f4415`) put the user in front of the pane and the metrics
panel, and three separate requests came out of it:

1. the **readiness banner** is legacy and should go — mounted volumes are named in three places;
2. the **helper being unreachable** is app-wide and fatal, and does not belong in a per-device pane;
3. **Covering** is mislabelled, the row should go, and the metric the user actually wants does not
   exist.

Those became increments 9, 10 and 11. They were ordered so that **the two app-only increments land
before the one that costs a protocol version**, and both have.

> **Increments 9 and 10 have landed and their sections are deleted from this file**, as the header
> above instructs. Their accounts are in `PROGRESS.md` and in their commit messages.
>
> **What increment 10 left that increment 11 depends on.** The `Covering` row is gone from **all
> three** surfaces — the live panel, the report sheet and the exported Markdown — and
> `ThroughputFraming.definition` now reads *"Both rates…"*. That is wider than this file's plan said
> (it named only `RunMetricsView`), and it is the shape `R-W-R-C speed` has to fit into: a new rate
> means that paragraph is rewritten again, on the surface that states it once for both renderers.
> `coverageBytesPerSecond` is still on the wire and still the ETA's quantity, documented at
> `RunProgressSnapshot` as deliberately undisplayed.

---

## Increment 12 — ⌘Q works under every sheet

**Not planned in advance; produced by walking chunk 13 on 2026-08-27.** Scoped here rather than
folded into increment 9 by explicit user decision the same day: *"fix the gate only and proceed."*

### The defect

`NSApp.terminate(_:)` is a **silent no-op while a sheet is attached** — measured on an AppKit probe,
recorded in CONSTRAINTS §1 with the table. AppKit refuses the termination *before*
`applicationShouldTerminate` is consulted, so `QuitPolicy` is never asked and nothing is logged.

**⌘Q is therefore dead under every sheet in this app**: the pre-run dialog, the report sheet, and
the launch gate. It fails safe — no run is ever abandoned — and it fails **silently**, which is the
part that matters: the app's stated contract is that ⌘Q during a run *asks first*, and what it
actually does is nothing at all.

This is the true cause of **check 6.1** from increment 5, which observed the symptom and had a
guessed cause sitting beside it in `AppModel` for two increments.

### What increment 9 already did, and why it is not enough

The gate's own Quit button calls `dismissAttachedSheets()` before `terminateAction()`, and a test
asserts the **order** because swapping the two lines restores the defect. That is deliberately local:
it is safe there because the gate is window-modal at launch, so no run can exist.

### Why the general fix is not the same edit

**`AttachedSheets.endAll()` cannot simply move into `terminateAction`'s default.** Ending the sheet
under the **pre-run dialog** dismisses a prompt the user never answered, and the prompt is the last
thing standing between a ⌘Q and a drive. The quit path must therefore decide *whether* the sheet may
go before it ends it, and the decision belongs in `QuitPolicy` where the truth table is tested —
not in an AppKit poke.

### Know this before building it

- **`isSheet` is not the test for "may I terminate now".** The probe measured `isSheet` still `true`
  immediately after `endSheet(_:)` returned, and terminating right then worked. The blocker is the
  live sheet *session*, closed synchronously by `endSheet(_:)`.
- **`endSheet(_:)` is not enough for a SwiftUI sheet, and this increment must not be built on it.**
  Measured in the shipped app 2026-08-31: it leaves the sheet attached and the termination still
  refused. Each sheet has to be taken down by **its own presentation state going false** — so this
  increment is not one AppKit call in `terminateAction`, it is a rule per sheet (the pre-run prompt,
  the report, the gate) plus a decision about which of them a quit is allowed to discard. The gate's
  is `AppModel.helperGateIsPresented`; the pre-run prompt is the hard one, because dismissing it
  discards a question the user never answered.
- **No delay is needed and none should be used.** A version that terminates "a run-loop turn later"
  rests on a dismissal animation nobody has measured. Same turn works; it was measured.
- **The quit path emits no log lines at all**, which is why the chunk 13 failure could not be
  diagnosed from the archive and needed a probe. Whatever this increment does, `applicationShouldTerminate`
  and `QuitPolicy.disposition` should say so on the log (NFR-OBS-1).
- The probe that established all of this is in the session scratchpad, not the repo. **Rebuild it
  rather than trusting this paragraph** if the behaviour is ever in doubt; three earlier versions of
  it measured *nothing* (a SwiftUI `Window` scene launched from a CLI binary never materialises a
  window, and every mode reported `sheets = 0`) and were only caught because the probe asserted the
  sheet was attached before trusting its own verdict.

### The human checks it owes

⌘Q under the pre-run dialog during a run, ⌘Q under the report sheet, ⌘Q under the gate, and the
existing chunk 6 quit boundary re-run unchanged.

---

## Settled — do not re-open

| Decision | Date |
|---|---|
| ~~Remedy-first, not Quit-only; `.notFound` alone is Quit-only~~ **built, increment 9** | 2026-08-26 |
| ~~The gate fires at **launch/initialization**~~ **built, increment 9** | 2026-08-26 |
| ~~Diagnosed from `SMAppService.status` + the version handshake~~ **built, increment 9** | 2026-08-26 |
| ~~FDA stays a Start-time check (**option A**, inside preparation)~~ **built, increment 10** | 2026-08-26 |
| ~~The FDA modal has **two** buttons~~ **built, increment 10** — a two-button `.alert`, so it has no render cover | 2026-08-26 |
| ~~Increment 10 keeps the FDA move and the banner deletion **together**~~ **built** | 2026-08-26 |
| ~~The `Covering` row is deleted~~ **built, increment 10 — from all three surfaces**; `R-W-R-C speed` is a separate increment | 2026-08-26 |
| The `Covering` deletion covers the panel, the report sheet **and** the exported Markdown | 2026-09-02 |
| Only a **denied** Full Disk Access probe stops a run — `.unknown` and a transport failure carry on | 2026-09-02 |
| ~~`R-W-R-C` on all three surfaces; on a healthy run it reads exactly as Write, and that is accepted~~ **built, increment 11 — then the equality was withdrawn** | 2026-09-02 |
| ~~Write stays, because Write and Read are what reconcile against Activity Monitor~~ **REVERSED 2026-09-02**: reconciling with Activity Monitor is no longer an objective. FR-METR-1 amended; see that document | 2026-09-02 |
| **FR-METR-1: the displayed rates divide by PHASE time.** Read pools both reads over both their times; `R-W-R-C` divides by all successful phase time; covering stays on running time for the ETA | 2026-09-02 |
| The app-side rate properties were **renamed** to match — `sustained*` describes what Core still computes, not what the wire carries | 2026-09-03 |
| Protocol **v14**, not folded into the uncommitted v13 — v13 stays as written, so the record is chronological | 2026-09-02 |
| The gate re-checks on app activation while gated; **no third button** on `requiresApproval` | 2026-08-27 |
| ⌘Q under a sheet is fixed **app-wide as increment 12**, not folded into increment 9 | 2026-08-27 |
| `versionMismatch` re-registers by **unregister-then-register**; no other state unregisters | 2026-09-01 |
| The gate shows a **busy state** — remedies disabled, spinner + label, **Quit stays live** | 2026-09-01 |
| A spinner, **not a wait cursor**: macOS has no hourglass, and a cursor cannot be rendered | 2026-09-01 |
| Quit landing inside the ~730 ms busy window is **accepted, not defended against** — the user is free to leave and the state is recoverable | 2026-09-01 |

**The user was warned that a launch-time fatal modal costs the helper-free link-speed check** —
enumeration, capacity, serial and link speed are all app-side IOKit reads and work without the
helper — and chose launch anyway. That trade is made; do not re-raise it.
