# Build Progress Log — the step in progress

**This file holds the current step and nothing else.** It was 7,156 lines on 2026-08-11 and was
split, because a log a cold start is told not to read is a log that is not doing its job.

| where | what lives there |
|---|---|
| **PROGRESS.md** (this file) | the step in progress |
| **[CONSTRAINTS.md](CONSTRAINTS.md)** | **read this in full** — what binds future work: measured behaviour, settled decisions, lessons |
| **[BUILD-PLAN.md](BUILD-PLAN.md)** | the plan, the per-step gates, the process gotchas, the test hardware |
| `progress/step-NN.md` | archived history, for *"why was it done that way?"* |

**Each increment below is a summary plus its commit hash. The full account is in the commit
message** — deliberately, since 2026-08-11. Writing the same reasoning twice at length gave two
long prose accounts of one increment that could drift apart, and the commit is the immutable,
greppable one. Use `git show <hash>` for the detail; what is kept here is what a cold start needs
without running git.

---

## Step 14 — Mandatory pre-run warnings & honest framing — IN PROGRESS

FR-WARN-1/2/3/4, NFR-USE-4/6/8. Started 2026-08-09 from a clean tree at `c1be1ed` (744 tests,
88 suites).

### Where it stands

| | |
|---|---|
| **Increments 1–6** | complete and committed |
| **Increment 6** | headless half done; **Dynamic Type is the only keyboard item left**, and it shares increment 7's setup |
| **Increment 7** | not started — three clean builds, docs, human confirmation |
| **Verified** | **801 tests, 0 failures, 93 suites.** Zero source warnings from `build.sh Release` and `test.sh` |
| **Helper** | **untouched all step.** Source hash still `737e6972bfdec1c5c1901a27bd5a00da2fed413166c909fc6639666c38e8907e`, so Step 10's three hardware gates continue to apply |
| **This step needs** | no hardware gate, and **no Xcode GUI work** — app target and test target only, both file-system synchronized |

### Why this step is being built before Step 11

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

### The seven scoping decisions (all user decisions, 2026-08-09, taken before a line was written)

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

### Increments

| # | what it did | commit |
|---|---|---|
| **1** | `PreRunPrompt` / `PreRunWarningPolicy` — the pure decision, with nothing calling it. Two cases and **no third**: "no dialog at all" is not expressible. The preference is recorded only by a run that actually starts, so tick-then-Cancel records nothing. 9 mutations, 9 catches. | `98570d9` |
| **2** | `HonestFraming` — **one** wording for the honest framing, and both existing renderers moved onto it. Found the two existing copies **had already drifted**: the result screen had lost the clause explaining why a matching verify does not prove retention. Exported report wording verified byte-identical. 12 mutations, 12 catches. | `6c686f6` |
| **3** | `PreRunPromptSheet` + four render cases, built and inspected **before anything could present it**. Renders caught two defects the source could not (a heading that repeated the question verbatim; a confirmation sized for the full dialog). Footer pinned outside the `ScrollView`. Also: the standing device-pane advice reworded and made unconditional, and the probe's appearance pinned. 6 text mutations + 1 layout mutation the suite could not see. | `b7b67ef` |
| **4** | `UserDefaults` persistence, per logged-in user, plus the diagnostics "Show pre-run warnings again" control. A key-name test was **agreeing with the rename it was written to prevent** and was fixed. Also fixed the probe's dark mode. 6 mutations, 6 catches — one only by a render. | `2403c80` |
| **5** | The gate wired: Start raises the dialog, `runBoundedCycle(authorisedBy:)` requires proof it ran. `PreRunWarningLog` — the only durable record that the gate ran, since the sheet cannot be rendered. **Three mutations survive**, all SwiftUI wiring; see below. | `0f5abb2` |
| **6** | The accessibility audit (NFR-USE-8), never run before on any surface. **Greyscale passes on every status-bearing case in both appearances** — meaning is carried by symbol shape and words, never by tint. Contrast **measured** off rendered pixels with a calibrated sampler, not estimated: headline 13.97:1 light / 12.63:1 dark against status tints at 2.22–2.31:1 light, so the tint is provably decoration. `RunReportPresentation` hoisted out of the view — the colour-alone rule had been held up by a comment no test could reach. 6 mutations, 6 caught. New `devices-unusable` render case for a row that had never been renderable. **Two user decisions taken during it: the seven decorative glyphs hidden, and VoiceOver removed from scope.** | *pending* |

### Increment 6's three findings, kept because they outlive the increment

1. **Dynamic Type is inert on macOS.** A `dynamicTypeSize` axis was built for the probe and
   **removed after measuring**: `warnings` at `large` and at `accessibility5` produced byte-identical
   PNGs. Discriminated before it was believed — a bogus value made the probe refuse (so the argument
   reached the parse) and a temporary `.opacity()` keyed on the parsed value made the renders diverge
   (so the modifier reached the hierarchy). The axis was deleted rather than kept, because a lever
   that looks live and does nothing would let somebody render at `accessibility5`, see no clipping,
   and conclude the layout is safe. Recorded in `scripts/render-ui.sh`'s header.
2. **`render-ui.sh`'s height argument is a floor, not a ceiling** — the header had claimed it was
   simply "the lever". The `metrics*` family returned **2,876 pt** when asked for 460. Centre-crop
   with `sips -c` instead.
3. **Light appearance is where contrast is marginal, and it is all system semantic colour.** Faint
   body text 3.41:1 and status tints 2.22–2.31:1, both under WCAG AA; dark measures 6.61:1 and
   7.47–8.25:1. **Recorded, not changed** (user decision): the app leverages SwiftUI's built-in
   styles, which is exactly why it inherits macOS's own "Increase contrast" setting for free, and
   overriding Apple's palette would break that adaptation to chase a threshold on decoration that
   carries no meaning.

**Increment 7 — three clean builds, docs, and human confirmation.** Three mutations from increment 5
are **not caught by the suite** — the authorisation guard, Start wired straight to a run, and the
checkbox bound to the persisted value. All three are SwiftUI wiring: no test here reads SwiftUI and a
render is static and cannot press a button. This was predicted when the modal was chosen, but
predicted is not covered.

Partial cover, stated honestly: **Start skipping the gate is visible in the log by its absence** (no
`pre-run prompt raised` line). The checkbox binding is visible behaviourally. **The guard alone
changes nothing observable** — with correct wiring nothing reaches it — so it is defence against a
*second* defect and is not independently caught.

**The human checklist, written now rather than recalled later.** Needs the app installed and the
helper re-registered, since any rebuild replaces the embedded helper binary. **Increment 6's one
remaining keyboard item shares this setup and belongs in the same sitting: Dynamic Type**, checked
against System Settings ▸ Accessibility ▸ Display ▸ Text size — the pre-run dialog is raised by
`Run one bounded cycle`, which is disabled until the device is held, so it cannot be reached
without the helper.

1. **Run one bounded cycle** raises the dialog, and the log shows `pre-run prompt raised`.
2. **Cancel** issues no run (`run issued: false`).
3. **Proceed** issues one.
4. **Tick + Cancel**, then reopen: still the **full warnings**.
5. **Tick + Proceed**: the run starts, and the *next* one shows the brief confirmation naming the
   drive by model and serial.
6. Diagnostics ▸ **Show pre-run warnings again**: the next run shows the full warnings, and the
   setting survives a relaunch.
7. A **quit pending** while the dialog is open: Proceed issues nothing.

### Known loose ends carried into later steps

- **Step 12 inherits the worst one:** a drive that drops off the bus is reported as a drive with
  ~2 million bad blocks. See [CONSTRAINTS.md](CONSTRAINTS.md), "Device loss".
- **`minHeight: 700` no longer holds.** At the app's own minimum the `Mounting & exclusive access`
  controls are **clipped** — content outgrew a constant measured in Step 9, and idle content now
  needs roughly 730 pt. Found while scoping this step; **decoupled from it** by the modal decision,
  so it is unfixed and belongs to whichever step next touches that window.
- `mountOne` / `unmountOne`'s DiskArbitration option constants are covered by no test.
- A cosmetic duplicate Window-menu entry, now three. `.commandsRemoved()` is measured **not** to be
  the fix.
- A main window reopened **during** a run comes back with no highlighted row (model and detail are
  correct).
- What the ~209 µs per-chunk term in the daemon's CPU actually is: measured, not explained.
- The root cause of the scratch drive's mid-gate de-enumeration is **not** established. One clean
  re-run after a cable and port change is the evidence available; it is not proof.
