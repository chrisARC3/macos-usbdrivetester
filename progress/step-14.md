# Step 14 — Mandatory pre-run warnings & honest framing

*Archived from `PROGRESS.md` on 2026-08-11, when the step completed. Statements carry the dates on
which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

---

## Step 14 — COMPLETE AND COMMITTED (2026-08-11)

FR-WARN-1/2/3/4, NFR-USE-4/6/8. Started 2026-08-09 from a clean tree at `c1be1ed` (744 tests,
88 suites); finished 2026-08-11.

| commit | |
|---|---|
| `98570d9` | Step 14: scope, the NFR-USE-4 qualification, and the warning decision |
| `6c686f6` | Step 14: one wording for the honest framing (increment 2) |
| `b7b67ef` | Step 14: the pre-run dialog (increment 3), and two instrument fixes |
| `2403c80` | Step 14: warning suppression persisted, and the probe's dark mode fixed |
| `0f5abb2` | Step 14: the pre-run gate is wired (increment 5) |
| `9ccbf8d` | Step 14: the accessibility audit (increment 6), and VoiceOver out of scope |
| `a6f2e44` | Docs: record increment 6's commit hash |
| `e61c4f0` | Step 14: the report could not name its drive, and Acquire was off-screen |

**801 tests, 0 failures, 93 suites.** Zero source warnings from three clean builds. Helper source
hash `737e6972bfdec1c5c1901a27bd5a00da2fed413166c909fc6639666c38e8907e` — **untouched all step**, so
Step 10's three hardware gates continue to apply. No hardware gate and no Xcode GUI work were needed:
app target and test target only, both file-system synchronized.

**Step 11 is next.** What it inherits from this step is in [PROGRESS.md](../PROGRESS.md).

---

## Why this step was built before Step 11

Step 11 deletes the `Unmount All` / `Acquire` / `Release` controls and gives Start ownership of
unmount → acquire → run → release. That deletion has been **gated on Step 14's warnings existing**
since 2026-08-05, because FR-DEV-3 default-selects the first device in BSD-name order and after
Step 11 that selection is one deliberate click from a write. **Re-measured 2026-08-09** by rendering
the real device list: the default is the 22 TB Seagate with Backup and Time Machine mounted.

Three options were put to the user — Step 14 first, both together, or split Step 11 so the deletion
is last. **Step 14 first** was chosen.

That created a wrinkle worth remembering: this step's gate said *"Start is disabled until the
warnings are acknowledged"*, and **there is no Start control until Step 11 builds it**. Resolved by
decision 2 below.

## The seven scoping decisions (all user decisions, 2026-08-09, taken before a line was written)

1. **Step 14 lands before Step 11.**
2. **The gate sits on `Run one bounded cycle`** until Start exists — the only control that currently
   writes. Considered against gating `Acquire`, which would spend the warnings when no write is
   imminent, and against gating both.
3. **A modal sheet raised by pressing Start**, Proceed / Cancel — not an inline panel. *"No real
   reason to take up precious pixels in the main window for a message that only needs to be shown at
   the beginning of every run."* It must be a **sheet, not an `alert`**: an alert cannot hold a
   `Toggle`.
4. **One acknowledgement, and Proceed is it.** No per-warning checkboxes. This replaced the gate's
   original wording, which was BUILD-PLAN's phrasing and not requirement text.
5. **A "Don't show this warning again" checkbox, recorded per logged-in user** — the app's
   `UserDefaults`, **never the helper's**, which runs as root and would make it system-wide.
6. **Suppressing the text does not suppress the deliberate act.** Start then raises a one-line
   confirmation naming the drive by model and USB serial. This is what keeps NFR-USE-4 *qualified*
   rather than weakened.
7. **A "Show pre-run warnings again" control in the diagnostics window** — a setting with no way back
   is one the user cannot undo without editing a plist.

Requirement changes landed before the code: **NFR-USE-4 qualified**, **FR-WARN-1 qualified**,
FR-WARN-2/3/4 examined and unaffected (3 and 4 are discharged by the exported report, which is not
suppressible). BUILD-PLAN Step 14's gate and its risks note were both rewritten rather than left
contradicting the code.

**An eighth decision arrived on 2026-08-11, during increment 6: VoiceOver was removed from scope.**
NFR-USE-8 no longer asks for screen-reader support and the product makes no claim to it. The
instruction was to remove the requirement; no rationale was given and none was invented. The full
entry is in the NFR document's Amendments for that date, including what it costs. The colour-alone
absolute, Dynamic Type and contrast were untouched, and the accessibility code already in the app
was kept — voluntarily, and no longer requirement-driven.

## Increments

| # | what it did | commit |
|---|---|---|
| **1** | `PreRunPrompt` / `PreRunWarningPolicy` — the pure decision, with nothing calling it. Two cases and **no third**: "no dialog at all" is not expressible. The preference is recorded only by a run that actually starts, so tick-then-Cancel records nothing. 9 mutations, 9 catches. | `98570d9` |
| **2** | `HonestFraming` — **one** wording for the honest framing, and both existing renderers moved onto it. Found the two existing copies **had already drifted**: the result screen had lost the clause explaining why a matching verify does not prove retention. Exported report wording verified byte-identical. 12 mutations, 12 catches. | `6c686f6` |
| **3** | `PreRunPromptSheet` + four render cases, built and inspected **before anything could present it**. Renders caught two defects the source could not (a heading that repeated the question verbatim; a confirmation sized for the full dialog). Footer pinned outside the `ScrollView`. Also: the standing device-pane advice reworded and made unconditional, and the probe's appearance pinned. 6 text mutations + 1 layout mutation the suite could not see. | `b7b67ef` |
| **4** | `UserDefaults` persistence, per logged-in user, plus the diagnostics "Show pre-run warnings again" control. A key-name test was **agreeing with the rename it was written to prevent** and was fixed. Also fixed the probe's dark mode. 6 mutations, 6 catches — one only by a render. | `2403c80` |
| **5** | The gate wired: Start raises the dialog, `runBoundedCycle(authorisedBy:)` requires proof it ran. `PreRunWarningLog` — the only durable record that the gate ran, since the sheet cannot be rendered. **Three mutations survive**, all SwiftUI wiring. | `0f5abb2` |
| **6** | The accessibility audit (NFR-USE-8), never run before on any surface. **Greyscale passes on every status-bearing case in both appearances.** Contrast **measured** off rendered pixels with a calibrated sampler. `RunReportPresentation` hoisted out of the view. 6 mutations, 6 caught. New `devices-unusable` render case. Two user decisions taken during it. | `9ccbf8d` |
| **7** | Three clean builds, the docs pass, and the human checklist — all seven items plus two more the session added. | *this archive's commit* |

## Increment 6's three findings, kept because they outlive the step

1. **Dynamic Type is inert on macOS.** A `dynamicTypeSize` axis was built for the probe and
   **removed after measuring**: `warnings` at `large` and at `accessibility5` produced byte-identical
   PNGs. Discriminated before it was believed — a bogus value made the probe refuse (so the argument
   reached the parse) and a temporary `.opacity()` keyed on the parsed value made the renders diverge
   (so the modifier reached the hierarchy). The axis was deleted rather than kept, because a lever
   that looks live and does nothing would let somebody render at `accessibility5`, see no clipping,
   and conclude the layout is safe. Recorded in `scripts/render-ui.sh`'s header. **Confirmed
   independently at the keyboard**: changing System Settings ▸ Accessibility ▸ Display ▸ Text size
   changed no font in any window.
2. **`render-ui.sh`'s height argument is a floor, not a ceiling** — the header had claimed it was
   simply "the lever". The `metrics*` family returned **2,876 pt** when asked for 460. Centre-crop
   with `sips -c` instead.
3. **Light appearance is where contrast is marginal, and it is all system semantic colour.** Faint
   body text 3.41:1 and status tints 2.22–2.31:1, both under WCAG AA; dark measures 6.61:1 and
   7.47–8.25:1. **Recorded, not changed** (user decision): the app leverages SwiftUI's built-in
   styles, which is exactly why it inherits macOS's own "Increase contrast" setting for free, and
   overriding Apple's palette would break that adaptation to chase a threshold on decoration that
   carries no meaning.

## The two defects the keyboard session found, and what they cost

Neither was introduced by this step; both are Step 9/10 wiring the session walked into. **Both are
SwiftUI wiring that no test here reads**, and the meaningful mutation for the first — restoring the
stale capture — is not catchable by the suite. Their only cover is a person re-testing them, which
was done on 2026-08-11. Fixed in `e61c4f0`.

1. **The exported report could not identify its drive.** Model, serial and capacity were all missing
   on the first run after every launch. `makeReport` read `reportedDevice`, fed from
   `AppModel.lastRunDevice`, which is not written until `cycleIsRunning` flips *during* the run — so
   the escaping completion handler captured the `nil` the view struct was built with. The pre-run
   dialog was correct throughout, because it reads `heldDevice`, set by `acquire` before the button
   is even enabled. **Fixed by deleting the second property.** A `reportBuiltWithNoHeldDevice()`
   error log makes the impossible case loud instead of silent.

   **Settled by the log, not by reading the code.** Two mechanisms fitted the symptom equally well —
   this one, and `helperHoldsDevice` true while `heldDevice` was never set. Two lines, same process,
   93 seconds apart, decided it:

       11:27:59  pre-run prompt raised: full warnings; drive serial 12345686DAA9
       11:29:32  run report: ... drive serial none

   No `promptRaisedForAnUnnamedDrive` line appears anywhere in the log, which excluded the other
   candidate outright.

   **Consequence worth stating: every first-run report between Step 10 and this fix was
   unattributable.** The run data in those files is sound; the identity is not.

2. **`Acquire exclusive access` was off-screen at the app's own minimum height**, which presented as
   *"Run one bounded cycle stays disabled no matter what I do"* — the button's precondition is a
   held device, and the control that holds one could not be reached. Measured: the whole
   `Mounting & exclusive access` section is absent at 640×700, present at 760. **Fixed structurally,
   not by raising `minHeight`** — the identity block above it grows with the drive's mounted-volume
   count, so any constant is a threshold some drive crosses. The controls are now pinned outside the
   `ScrollView`, as increment 3 did for the pre-run dialog's footer. `minHeight: 700` stands
   unchanged because nothing depends on it for reachability.

**The pattern across both, and it is the argument for keeping the human checklist.** Increment 6's
headless half — 36 renders, a calibrated contrast sampler, six mutations — found **no defects in the
app at all**. The keyboard half found two, one of them the most serious kind this tool can have. A
person using the product remains the only instrument that has found this class of defect here.

## The human checklist — ALL NINE PASSED 2026-08-11

Kept rather than deleted: it is what any rebuild of this area has to pass again, and the three
increment-5 mutations it covers are still uncatchable by the suite. Needs the app installed and the
helper re-registered, since any rebuild replaces the embedded helper binary.

1. ✅ **Run one bounded cycle** raises the dialog, and the log shows `pre-run prompt raised`.
2. ✅ **Cancel** issues no run (`run issued: false`).
3. ✅ **Proceed** issues one.
4. ✅ **Tick + Cancel**, then reopen: still the **full warnings**.
5. ✅ **Tick + Proceed**: the run starts, and the *next* one shows the brief confirmation naming the
   drive by model and serial.
6. ✅ Diagnostics ▸ **Show pre-run warnings again**: the next run shows the full warnings, and the
   setting survives a relaunch.
7. ✅ A **quit pending** while the dialog is open: Proceed issues nothing.
8. ✅ The **first** run after a fresh launch produces a report naming model, serial and capacity.
   First run specifically — later ones looked correct even with the defect present.
9. ✅ The `Mounting & exclusive access` controls are reachable without resizing the window.

Items 1–3 and 7 are the ones that matter most: they are the three increment-5 mutations the suite
cannot reach, so a wrong answer there would mean the gate was not actually wired.

## What increment 5 predicted and increment 7 confirmed

Three mutations from increment 5 are **not caught by the suite** — the authorisation guard, Start
wired straight to a run, and the checkbox bound to the persisted value. All three are SwiftUI
wiring. This was predicted when the modal was chosen, and predicted is not covered.

Partial cover, stated honestly: **Start skipping the gate is visible in the log by its absence** (no
`pre-run prompt raised` line). The checkbox binding is visible behaviourally. **The guard alone
changes nothing observable** — with correct wiring nothing reaches it — so it is defence against a
*second* defect and is not independently caught.
