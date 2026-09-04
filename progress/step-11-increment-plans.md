# Step 11 — the settled decisions from increments 9–12

**Written 2026-08-25/26, before any code**, for increments 9–11. **All four increments have now
landed and every plan section was deleted from here**, as the rule below instructs — 9 on
2026-08-27, 10 on 2026-09-02, 11 on 2026-09-03, and **12 on 2026-09-04**. Increment 12 was added
2026-09-01, unplanned, having been produced by walking increment 9's own checklist chunk. Every
decision below was taken by the user during scoping and is **settled**. This file exists so a cold
session does not re-open choices that were already argued through.

**No increment is planned here right now.** What remains is the settled-decision table, which
outlives the plans it came from.

**This is a plan, not history.** When an increment is built, its full account goes in its commit
message and its summary into `PROGRESS.md`, as always. Delete the section from here when it lands.

> **Two of increment 12's "know this before building it" bullets were wrong, and that is why the
> section is gone rather than annotated.** It named **three** sheets — the app has **five**
> window-modal surfaces, because a SwiftUI `.alert` on macOS is presented as a sheet — and it said
> *"no delay is needed and none should be used"*, which was the AppKit probe's measurement and does
> not hold for a sheet SwiftUI owns; one run-loop turn is required, and it is not a wait for an
> animation. Both corrections are at their sites in the source, in CONSTRAINTS §1, and in the
> increment's commit messages.

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
| ~~⌘Q under a sheet is fixed **app-wide as increment 12**, not folded into increment 9~~ **built, increment 12** | 2026-08-27 |
| **Which modals a ⌘Q may discard**: the run report and the launch gate, yes; the pre-run prompt, the failure alert and the quit confirmation are **refused visibly** (the menu item greys). More than one flagged is refused | 2026-09-04 |
| The launch gate's own Quit **button** shares the mechanism but never the policy — it must not be able to refuse | 2026-09-04 |
| `versionMismatch` re-registers by **unregister-then-register**; no other state unregisters | 2026-09-01 |
| The gate shows a **busy state** — remedies disabled, spinner + label, **Quit stays live** | 2026-09-01 |
| A spinner, **not a wait cursor**: macOS has no hourglass, and a cursor cannot be rendered | 2026-09-01 |
| Quit landing inside the ~730 ms busy window is **accepted, not defended against** — the user is free to leave and the state is recoverable | 2026-09-01 |

**The user was warned that a launch-time fatal modal costs the helper-free link-speed check** —
enumeration, capacity, serial and link speed are all app-side IOKit reads and work without the
helper — and chose launch anyway. That trade is made; do not re-raise it.
