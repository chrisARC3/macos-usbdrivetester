# Build Progress Log — the step in progress

**This file holds the current step and nothing else.** It was 7,156 lines on 2026-08-11 and was
split, because a log a cold start is told not to read is a log that is not doing its job.

| where | what lives there |
|---|---|
| **PROGRESS.md** (this file) | the step in progress |
| **[CONSTRAINTS.md](CONSTRAINTS.md)** | **read this in full** — what binds future work: measured behaviour, settled decisions, lessons |
| **[BUILD-PLAN.md](BUILD-PLAN.md)** | the plan, the per-step gates, the process gotchas, the test hardware |
| `progress/step-NN.md` | archived history, for *"why was it done that way?"* |

**The full account of an increment goes in its commit message**, with this file carrying a summary
and the hash. Writing it twice at length produced two long prose accounts of one increment that
could drift; the commit is the immutable, greppable one.

---

## Step 14 — COMPLETE (2026-08-11)

Mandatory pre-run warnings & honest framing. FR-WARN-1/2/3/4, NFR-USE-4/6/8. Seven increments,
2026-08-09 to 2026-08-11, eight commits ending at `e61c4f0`. **Gate passed in full.**

**History archived to [`progress/step-14.md`](progress/step-14.md)** — the seven scoping decisions,
the increment table, the accessibility audit's findings, the two defects the keyboard session found,
and the nine-item human checklist that any future change to this area has to pass again.

| | |
|---|---|
| **Verified** | **801 tests, 0 failures, 93 suites.** Zero source warnings from **three clean builds** with DerivedData wiped before each |
| **Helper** | **untouched all step.** Source hash `737e6972bfdec1c5c1901a27bd5a00da2fed413166c909fc6639666c38e8907e`, so Step 10's three hardware gates continue to apply |
| **Requirements changed** | NFR-USE-4 qualified, FR-WARN-1 qualified (2026-08-09); **VoiceOver removed from scope** (2026-08-11) — all three recorded in the requirement documents' Amendments |

---

## Step 11 — NEXT, not started

Run-control state machine: start / pause / resume / stop / restart. FR-CTRL-1…9, NFR-REL-10.

**Its gating precondition is now discharged.** Step 11 deletes the `Unmount All` / `Acquire` /
`Release` controls and gives Start ownership of unmount → acquire → run → release. That deletion was
gated on Step 14's warnings existing since 2026-08-05, because after it FR-DEV-3's default selection
is one deliberate click from a write — and on this machine that default is the 22 TB Seagate with
Backup and Time Machine mounted. **Step 14 is done, so this may now proceed.**

### What to read before scoping it

**BUILD-PLAN Step 11 carries six inherited notes** and they are the substance — the XPC
connection-blocking measurement that constrains pause/stop, FR-TEST-10's slicing rule, the partial
unmount that must not strand the user, the quit machinery, and the two interim behaviours this step
subsumes. Do not scope this step without reading them. [CONSTRAINTS.md](CONSTRAINTS.md) has the same
facts in shorter form and should be read in full anyway.

### Three things this step needs that are not in BUILD-PLAN

- **The 4 TB T5 EVO fixture drive is required**, not optional. `VolumeMounter.restoringUnmount` can
  only be exercised end to end on a drive with two or more mounted volumes, and Start's abort path
  reaches the identical partial-unmount state with no manual control left at all. Rebuild it with
  `scripts/make-unmount-fixture.sh` if its layout has been lost.
- **`AppModel.helperHoldsDevice` is still a per-device answer read as an any-device one.** Step 14
  narrowed the related hazard — `heldDevice` is now the single source for both the pre-run dialog
  and the report — but the boolean beside it was not touched. A run-owned claim removes the
  ambiguity at the source; do not reintroduce a selection-scoped flag.
- **The report's outcome vocabulary gains "stopped by user" here**, when FR-CTRL-4 finally gives it
  a trigger. It was deliberately not built in advance: a sound mechanism behind a trigger that never
  fires looks exactly like a broken one.

### What Step 14 leaves it, concretely

- The pre-run gate currently sits on `Run one bounded cycle` in the diagnostics window (scoping
  decision 2). **Step 11 relocates it to the real Start**, along the same path FR-CTRL-7's failure
  mode picker beside it is already documented to take, and deletes the scaffolding with the button.
- `runBoundedCycle(authorisedBy:)` takes a `PreRunOutcome` as proof the gate ran. **Keep that
  shape** — it is what makes "wire Start straight to a run" a deliberate act visible in a diff
  rather than a one-word edit.
- The nine-item human checklist in `progress/step-14.md` is what the relocated gate must pass again.
  Three of its items cover mutations the suite cannot catch.

---

## Known loose ends carried into later steps

- **Step 12 inherits the worst one:** a drive that drops off the bus is reported as a drive with
  ~2 million bad blocks. See [CONSTRAINTS.md](CONSTRAINTS.md), "Device loss".
- **Every first-run report between Step 10 and 2026-08-11 was unattributable** — model, serial and
  capacity were missing. Fixed in `e61c4f0`. The run data in any such exported file is sound; its
  identity is not.
- `mountOne` / `unmountOne`'s DiskArbitration option constants are covered by no test.
- A cosmetic duplicate Window-menu entry, now three. `.commandsRemoved()` is measured **not** to be
  the fix.
- A main window reopened **during** a run comes back with no highlighted row (model and detail are
  correct).
- What the ~209 µs per-chunk term in the daemon's CPU actually is: measured, not explained.
- The root cause of the scratch drive's mid-gate de-enumeration is **not** established. One clean
  re-run after a cable and port change is the evidence available; it is not proof.
- **Light-appearance contrast is marginal in two places** — faint body text at 3.41:1 and the status
  glyph tints at 2.22–2.31:1, both under WCAG AA. **Recorded, not a defect** (user decision
  2026-08-11): these are macOS's own semantic colours, which is why the app inherits the system-wide
  "Increase contrast" setting for free. Dark appearance measures 6.61:1 and 7.47–8.25:1.
