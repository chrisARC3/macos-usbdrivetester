# What binds the work

**Read this file in full at the start of a session. It is short on purpose.**

Everything here is a fact that constrains *future* work: measured behaviour that a design must
accommodate, a decision that is settled, or a lesson that has already been paid for. It exists
because these facts used to live inside step narratives in `PROGRESS.md` — a 7,000-line file a cold
start was explicitly told not to read — so conveying twenty facts meant naming five sections across
1,400 lines and hoping.

There is precedent for the move: BUILD-PLAN's *"Working on this project"* was consolidated the same
way on 2026-08-06, for the same reason, and it worked. That section keeps the **process** gotchas
(how to build, how to count tests, shell and Swift traps). This file keeps the **technical** ones.

| where | what lives there |
|---|---|
| **CONSTRAINTS.md** (this file) | what binds future work — measured behaviour, settled decisions, lessons |
| **BUILD-PLAN.md** | the plan, the per-step gates, the process gotchas, the test hardware |
| **PROGRESS.md** | the step in progress, and only that |
| `progress/step-NN.md` | archived history — *why it was done that way*, when that question comes up |
| the FR / NFR documents | requirements and their amendments; the canonical record of what changed and why |

Each entry below names where its full account lives. **Nothing here restates the hardware roster** —
BUILD-PLAN's "Test hardware" is canonical for that, and two copies of a drive list is exactly the
drift this consolidation exists to remove.

---

## 1. Measured behaviour that constrains design

### XPC: the connection blocks, not the daemon

While the helper is inside a blocking privileged call, **a second message on that same connection is
not delivered until the call returns.** Measured 2026-08-04: 24 pings issued during a 2,827.9 ms
`digestRange` were all answered between 2,828.0 and 2,828.5 ms, draining *after* the call finished.
A **second connection** was answered concurrently throughout, in 0.2–0.3 ms.

Consequences that are load-bearing:

- The GUI polls `runProgress` on a **second, non-owning** connection. It never acquires, and its
  death releases nothing.
- **Pause and stop are subject to the same constraint**, which is why `setRunControl` is a **level
  the run reads** rather than a message the run receives — see "Run control" below.
- `releaseDevice` on the owning connection during a run would queue behind the very call it was
  meant to shorten. This is why quitting waits for the call boundary rather than releasing first.
- `TesterProtocol.maximumBytesPerCall` (1 GiB) bounds the reply, the per-call failure list, and how
  long a wedged call can occupy the daemon. **Its original justification has lapsed** — it used to
  read *"what makes an uncancellable privileged call survivable"*, and Step 11 is the step that made
  the call cancellable. The busy-refusals of `releaseDevice` and `prepareForShutdown` are reachable
  from the second connection regardless of call length, so they no longer depend on it either.
  **It is still not a tuning parameter for pause latency**, which is set by the chunk (below).

*Full account: `progress/step-09.md`, D1.*

### Run control: a level the run reads, and a settle bounded by one chunk

**`setRunControl` is one method carrying a level — `proceed` / `pause` / `stop` — not a
pause/resume/stop triple carrying edges.** Resume is `proceed` sent again. An edge would have to be
delivered to a connection that is blocked for the run's whole duration, which the measurement above
forbids; so the app *leaves* its wish somewhere the run will look, and the engine reads it at each
chunk boundary. It travels on the app's second, non-owning connection.

**The engine consults it at the TOP of each chunk iteration** — before that chunk's read, therefore
after the previous chunk's full read → write-back → verify. There is no other point in that loop
where "no write is in flight" is true without qualification, which is how NFR-REL-10 holds by
construction rather than by care. It is also *before* the processed-chunk counter increments, which
is what makes the chunk's own start block the correct resume point.

**Measured on hardware 2026-08-12** (`scripts/run-control-check.sh`, 1 TB T5 scratch drive, protocol
v10), calibrated against an uninterrupted control run of 1 GiB in 6,868 ms — 469 MB/s of device I/O,
matching this drive's independently measured rate:

| I/O size | 1-chunk bound | settle | fraction of bound |
|---|---|---|---|
| 1 MiB | 6.71 ms | 5.83 ms | 0.87 |
| 2 MiB | 13.41 ms | 10.13 ms | 0.76 |
| 4 MiB | 26.83 ms | 6.19 ms | 0.23 |
| 8 MiB | 53.66 ms | 42.45 ms | 0.79 |

**The settle is bounded by one chunk and is typically about half of one.** The pause lands at a
uniformly random point inside a chunk, so a single sample scatters across the bound — which is why
2 MiB came out *higher* than 4 MiB here. That is two draws from two different distributions, not
noise in the mechanism. **Do not quote the bound as the typical value**; an earlier note in this
project did, and the correction is the reason this table exists rather than a single figure.

The daemon acknowledged each request in 0.46–0.62 ms, and **that acknowledgement is not the settle.**
The helper recording a request and the run having acted on it are different facts; only the second
is NFR-REL-10's guarantee, and nothing may display "Paused" on the strength of the first.

**Latency is therefore set by the CHUNK, not the call** — which is what makes the per-call cap
irrelevant to it. A cap of 8 MiB would produce these same figures, because the settle happens at a
chunk boundary *inside* the call either way.

*Full account: commit `e13d3e8`.*

### I/O placement (FR-TEST-10)

All test I/O begins on a **1 MiB boundary** and covers a **whole number of MiB**, the sole exception
being a range ending at the device's final block. **The helper enforces both and refuses otherwise**
— shown refusing on hardware, not assumed.

So a whole-device sequencer must **slice by whole MiB and let only the final call be short**. A
sequencer advancing by "1 GiB or whatever is left" is refused on its last-but-one call against any
device whose size is not a whole number of MiB — which the scratch device is not.

*Full account: `progress/step-09.md`.*

### Unmounting: five things, and four of them are counter-intuitive

1. **`DADiskUnmount` with `kDADiskUnmountOptionWhole` unmounts a physical disk's DIRECT PARTITIONS
   ONLY.** It does not reach volumes inside an APFS container on that disk, and it **reports success
   with no dissenter** having skipped them. Measured from `diskarbitrationd`'s own log on a GPT drive
   carrying exFAT + APFS + HFS+.
2. **Therefore unmount each mounted volume by its own device node**, from
   `DiscoveredDevice.mountedVolumeBSDNames`. A volume that is mounted is by definition in the mount
   table, so it can always be enumerated and always has a node. An APFS volume's node is **not**
   derivable from the physical disk by prefix — it lives on a synthesized disk.
3. **`mountAll` keeps the whole-disk option, and the asymmetry is deliberate.** The mount table
   cannot list the volumes that are *not* mounted, so "mount every mountable volume" has nothing to
   enumerate. Unmount can always enumerate; Mount All never can.
4. **The mount table lags the callback.** Reading it the instant `DADiskUnmount` returns still lists
   a volume that has in fact gone. Re-read until it settles, with a bounded budget — 12 looks at
   150 ms — before concluding anything.
5. **Restore exactly what went, by node.** Capture the mounted set *before* unmounting; restore
   `before − still mounted`. A whole-disk *mount* brings up every mountable volume, which on a GPT
   drive means an EFI partition that was never mounted.

**Keep the helper's independence.** It evaluates `DeviceAccessPrecondition` on the acquire path
itself and refuses with `volumesMounted`. That is what kept a false "unmounted" in the app a *wrong
message* rather than an incident, through three steps in which the app's belief was wrong.

**Not covered by any test:** `mountOne` and `unmountOne`'s DiskArbitration option constants — they
need a real drive. Covered instead by hardware observation of `options = 0x00000000` in
`diskarbitrationd`'s log, and recorded at both call sites.

*Full account: `progress/step-10.md`, "the unmount rollback, verified".*

### Drive identity

**A BSD name is a LOCATOR, not an IDENTITY.** The test is lifetime:

> Does this statement outlive the enumeration that produced it?

- **Live** — the device list, the selected-device detail, `/dev/rdiskN`, a metrics heading, a log
  line about work in flight: **show it, beside the serial.** Two identifiers a user can cross-check
  beat one.
- **Persisted** — this file, BUILD-PLAN, gate scripts and their command lines, the exported report,
  release notes, anything copied into a shell later: **never as the identity. Use the USB serial.**

This is not style. A reboot on 2026-08-06 renumbered the machine's drives and the documented command
`retention-cycle-check.sh disk4` would have unmounted the backup drive and written a gibibyte to it;
`metrics-check.sh` carried a guard refusing any drive but `disk4`, which the renumbering turned
exactly inside out. The scratch device has since been `disk4`, `disk8`, and `disk10`, and on
2026-08-09 **`disk8` named two different physical drives inside one session.**

*Full account: `progress/drive-identity-serial-numbers.md`.*

### Quitting, and the run boundary

- **`AppModel.mayIssueNewWork` is a precondition, not a hint.** It is false from the moment a quit is
  *pending*, and a run sequencer must consult it **before every call it issues**. The quit
  confirmation is window-modal on the main window, so other windows stay clickable underneath it —
  this is not a guard against an unreachable state.
- **"Cancel and Quit" means stop at the call boundary**: issue no further work, wait for the
  in-flight privileged call to return, release, terminate. It deliberately does **not** claim to stop
  the run — there is no cancellation of a privileged call until FR-CTRL-4's machinery exists.
- **The boundary is `cycleIsRunning` going false.** When the run-control state machine replaces both
  run-state sources, the boundary moves with it, and "the run already finished while the dialog was
  up" must survive the move.
- `.terminateLater` was **measured and rejected**: AppKit runs that wait in its own run-loop mode, so
  a `Timer`-driven metrics panel freezes exactly while the app asks to be trusted.

*Full account: `progress/step-09.md`, increments 3 and 4.*

### Metrics and reporting

- **p99 is octave-bucketed, integer-only, and reported as an UPPER BOUND.** Read-latency statistics
  **keep accumulating** across a mid-run I/O-size change.
- **Progress is byte-denominated, never chunk-denominated** — which is what makes a mid-run size
  change expressible at all. `chunkMeasured` fires **once per chunk on every path**, including the
  three failure branches, so a display keeps advancing on a failing drive instead of freezing.
- **Throughput is reported, never graded.** The manufacturer's sustained figure is not something this
  tool knows, and inventing a verdict would be a judgement dressed as a measurement.
- **"Completed clean" means *no currently-unreadable blocks were found*, never "healthy".**
- **A refused call is not a run**: no report, and the refusal is logged so its absence is explicable.
- `MetricsChannel.begin()` runs *after* every validation refusal, so a **refused run leaves the
  previous run's figures installed**. Protocol v9 carries the final figures back in
  `runRetentionCycle`'s own reply, atomically with the run they describe, which removes the
  wrong-run's-numbers hazard by construction rather than detecting it.
- **NFR-PERF-3 has numbers** (2026-08-05): 2.55% host overhead → the run is **97.4% device-bound** at
  the 4 MiB default and ~470 MB/s; the whole daemon is 4.22% of one core. **Host cost follows bytes
  moved, not chunk count** — a larger I/O size does not reduce it.

*Full accounts: `progress/step-09.md`, `progress/step-10.md`.*

### Device loss (Step 12's territory, and a live defect until then)

- **`ENXIO` on offset 0 of a working descriptor means the descriptor is dead.** `EIO` on a block
  means a bad block. Detect loss from those and from the DiskArbitration/IOKit removal callback.
- **Do not infer device loss from a failure count.** A genuinely dead drive also fails every chunk,
  so the heuristic is wrong exactly when being wrong is most expensive.
- **Until Step 12 builds this, a drive that drops off the bus is reported as a drive with ~2 million
  bad blocks** — a false accusation about somebody's hardware, in a file that outlives the session.
  Observed for real during a hardware gate, not simulated.

*Full account: `progress/step-10.md`, increment 6; BUILD-PLAN Step 12's inherited notes.*

### The instrument: `scripts/render-ui.sh` and `tools/ui-probe`

- **A SwiftUI sheet or alert gets its own window and can never be captured in place.** Those surfaces
  need a person, permanently. The mitigation is to build each dialog as a **standalone `View` with
  its own render case**, put the *decision* in a pure type a mutation can reach, and log the route
  taken — so the only thing left to a human is *"did a dialog appear"*.
- **Appearance is pinned** (`light` default, `dark` selectable as a fifth argument, an unrecognised
  value refused). Renders used to inherit the machine's current setting, which made the instrument
  silently report **fewer elements than exist** depending on the time of day.
- **`cacheDisplay` captures the content view's drawing and never the window's background**, so
  regions where SwiftUI draws no background of its own would land in the PNG transparent. The probe
  now supplies an opaque layer. This was diagnosed wrongly **twice** before anyone read the capture
  code.
- **Render only as tall as you need — but the height argument is a FLOOR, not a ceiling** (measured
  2026-08-11, correcting a header note that had called it "the lever"). `NSHostingView` sizes to its
  content, so a view with no intrinsic cap ignores the number: the `metrics*` family returned
  **2,876 pt** when asked for 460. `sips -c <h> <w>` centre-crops reliably, but **`--cropOffset` is
  measured to be silently unreliable** — ignored when the crop fits, and once returning the source
  image unchanged, with no error either time.
- **24 view cases, and three of them render a state this machine cannot produce** — `empty` (no
  drives), `devices-unmounted`, and `devices-unusable` (a drive with a `geometryProblem`, which no
  drive here has). Each exists because *a state nobody can observe is a state nobody has checked*;
  the last was added in Step 14 for a row that had never been rendered in either appearance.
- **Dynamic Type is NOT checkable here, and the axis that would have checked it was built and then
  deleted.** `.dynamicTypeSize` applied to an offscreen `NSHostingView` changes nothing on macOS —
  measured, and discriminated with two controls before it was believed. Confirmed independently at
  the keyboard: the System Settings text-size slider moves no font in this app either. The axis was
  removed rather than kept, because a lever that looks live and does nothing would let somebody
  render at `accessibility5`, see no clipping, and conclude the layout is safe. Do not rebuild it
  without re-measuring. Full note in `scripts/render-ui.sh`'s header.
- The probe prints `appActive / windowKey / firstResponder / appearance` on every run. That line has
  settled several questions that were otherwise being argued about.

*Full account: `progress/step-14.md`, increments 3 and 6.*

---

## 2. Settled — do not re-open

- **Runs cover the WHOLE DEVICE, always start at block 0.** No user-selectable start, ever. Progress
  is a bar with a live percentage, never a slider.
- **FR-DEV-3 default-selects the first usable device in BSD-name order**, confirmed under challenge
  2026-08-06 with the hazard in front of the user. *"I do not want to go down the road of trying to
  divine user intentions."* Same policy as refusing to grade throughput. **On this machine that
  default is currently the 22 TB Seagate with a live Time Machine on it** — which is why Step 11's
  removal of the explicit unmount was gated on Step 14's warnings existing. **That gate is
  discharged (Step 14 complete 2026-08-11), so Step 11 may proceed.**
- **START OWNS UNMOUNT → ACQUIRE → RUN → RELEASE. Settled 2026-08-12, and it will not be
  re-visited.** Step 11 increment 5 deletes the `Unmount All` / `Acquire` / `Release` controls; the
  question of whether that leaves the product under-guarded is closed.

  **And the count that question kept being argued from was wrong.** This project's documents said in
  six places that the deletion leaves FR-DEV-3's default *"one deliberate click from a write"*.
  **There are two clicks**, and the second is the substantive one:

  1. **Start.**
  2. **Proceed**, on either the full FR-WARN-1/2/3 warnings or — where the text has been suppressed
     — a confirmation naming the drive by **model and USB serial** (NFR-USE-4 as qualified
     2026-08-09). That dialog cannot be switched off to nothing; only its content changes.

  > *"This is perfectly adequate. Besides, we have no evidence that more user button clicks makes it
  > less likely that a drive will be mis-identified."* — user, 2026-08-12

  That reasoning is the same species as FR-DEV-3's own defence and as the refusal to grade
  throughput: **do not add a mechanism whose benefit is assumed rather than demonstrated.** A third
  click would be a guard nobody has evidence for, bought with friction on every run for the
  professional user NFR-USE-4's suppression exists to serve. The thing that actually addresses
  mis-identification is already there and is not a click at all — it is the dialog **naming the
  drive by the identifier that survives a renumbering**.

  The older "one click" phrasing survives in `BUILD-PLAN.md`'s Step 14 notes, the NFR document's
  2026-08-09 amendment and the `progress/` archives. Those are **dated records of what was believed
  then** and are deliberately not rewritten; this entry supersedes them.
- **FR-SAFE-5 withdrawn, FR-SAFE-6 REVERSED, FR-SAFE-7 moot.** Start owns unmount → acquire → run →
  release. FR-SAFE-1/2/3 and NFR-REL-3 are untouched: only *who performs the unmount* changed.
- **A RUN IS A SEQUENCE OF BOUNDED CALLS, AND THE SESSION IS THE CLAIM** (Shape A, chosen
  2026-08-12 over the alternative below). Start takes the claim once, holds it for the whole run,
  releases it once — **never a claim per chunk**, which is unbuildable anyway: macOS remounts the
  volume **~4 ms** after a release (measured Step 6), so a per-chunk release would race its own
  remount tens of thousands of times.

  So the metrics and failure accumulators belong on the **claim**, not on the call. Four things
  follow, and each is a reason the shape was chosen rather than a consequence to be managed:

  - **A true whole-run p99.** Percentiles do not compose, so aggregating per-call p99s app-side
    cannot produce one. FR-METR-3 and FR-RPT-3 would silently degrade.
  - **Whole-device progress and ETA**, rather than the fraction of whichever gibibyte is in flight.
  - **`FailureLog`'s cap applies once per run**, not per call — so its truncation notice means what
    it says on a failing drive.
  - **Cumulative figures arrive in the cycle's own reply**, which preserves protocol v9's hard-won
    property — *the figures belong to this run or they do not exist* — at run scope, **with no new
    lifecycle methods**. `acquireDevice` opens the session and `releaseDevice` closes it.

  **The alternative was one long cancellable call, and it needs no session at all.** It was
  rejected on three counts: it bets a multi-hour run on an NSXPC reply nothing here has measured;
  it makes `prepareForShutdown`'s and `releaseDevice`'s busy refusals hours-long instead of
  seconds; and it turns FR-CTRL-8's *"a run resumed after a size change continues using the newly
  selected size"* into engine surgery, because buffers are allocated per call. Under Shape A that
  requirement falls out for free.

  **What is NOT a reason, and was checked rather than assumed:** preserving the 1 GiB cap. The
  cap's own justification lapsed in this step (see section 1), and pause latency is set by the
  chunk regardless — so Shape A stands on the four properties above, not on the cap.

  *Full account: commit `e13d3e8`; the measurement that backs it, `scripts/run-control-check.sh`.*
- **NFR-USE-4 qualified 2026-08-09.** The pre-run warning **text** is suppressible per logged-in
  user; the **deliberate act is not** — a suppressed run still raises a confirmation naming the drive
  by model and USB serial.
- **Screen-reader (VoiceOver) support is OUT OF SCOPE** — user decision 2026-08-11, NFR-USE-8
  amended. Nothing verifies it and no gate depends on it. **The rest of NFR-USE-8 stands**: never
  convey pass/fail by colour alone (audited and passed in greyscale across every status surface,
  both appearances), Dynamic Type, and contrast. Accessibility code already in the app was kept
  **voluntarily** — it is not requirement-driven, so do not build a gate around it, and do not
  delete it either.
- **Status tint is decoration, never the carrier.** `RunReportPresentation` owns the report's
  symbol-and-tint decision as a pure type precisely so a test can reach it; the words and the symbol
  shape carry the meaning. Measured 2026-08-11: the headline renders at 13.97:1 in light appearance
  against status tints at 2.22–2.31:1 — the tint is the *least* legible part of the verdict, which
  is the right way round.
- **Failures interrupt with a modal; a successful unmount reports nothing.** The rule lives in
  `OutcomePresentation`, not in a view.
- **The main scene is a `Window`, not a `WindowGroup`.** Closing the main window quits the app, and
  cannot bypass the during-a-run confirmation.
- **Nothing untriggerable ships.** An outcome, mode or control with no way to reach it is not built
  in advance — *a sound mechanism behind a trigger that never fires looks exactly like a broken one.*
- **Commit straight to `main`**, never a branch unless said in advance, message `Step N: <title>`,
  and **only when asked**.
- **The ADR's 16 checkboxes are never ticked.** It is a decision record; BUILD-PLAN is the tracker.

---

## 3. The lessons, which keep being paid for

Every defect this project has produced came from trusting a substitute for the real thing.

- **A check must be shown capable of failing.** A comment acknowledging a hole is not a check.
- **Measure, don't estimate.** An estimate stood three steps and was wrong by 11×.
- **A pre-flight before a design is committed to is almost free** — and has killed two designs before
  they were built.
- **Prose is not a precondition.** A control that states its requirement in text and then looks live
  is reported as broken.
- **An empty result is not a finding** — and neither is a number that does not move. A test-count
  that fails to rise is how files written to the wrong directory get caught.
- **SwiftUI modifiers fail silently.** `.defaultFocus`, `.selectionDisabled` on the wrong element,
  `.id()` to force a re-assert: all compiled, rendered, and did nothing.
- **A SwiftUI `View` is a STRUCT, and a stored property on it is a SNAPSHOT.** An escaping closure
  created inside one of its methods captures the value the view was *built* with — not whatever the
  model holds when the closure finally runs. The run report read its drive from a property fed by
  `AppModel.lastRunDevice`, which is not written until the run is already under way, so on the first
  run after every launch the closure captured `nil` and **the exported report named "Unidentified
  drive", 0 bytes, no serial** — the one thing a report about a drive must never fail to say. The
  pre-run dialog, reading a property set *before* the press, named the drive correctly at the same
  moment. **Two properties naming the same drive at two different instants is the defect; one
  source, captured once, at the point of decision is the fix.** Found by a person reading an
  exported file, and settled by two log lines 93 seconds apart rather than by reading the code —
  which had two equally plausible explanations for it. *Full account: `git show` the Step 14
  increment 6 follow-up.*
- **A control below the fold in an unadvertised scroll region has now cost this project three
  times.** Step 10 lost two of five rounds to it; `OutcomePresentation` exists because an error
  message did it; and on 2026-08-11 `Acquire exclusive access` was **entirely off-screen at the
  app's own `minHeight`**, which presented as *"Run one bounded cycle stays disabled no matter what
  I do."* **Raising the constant is not the fix** — the block above these controls grows with the
  selected drive's mounted-volume count, so any fixed height is a threshold some drive crosses.
  Pin the controls outside the `ScrollView`. A measured constant is only true until the content
  above it changes, and nothing announces the expiry.
- **An identifier that is assigned rather than intrinsic will eventually name something else, and
  nothing will announce it.**
- **When reasoning and the logs disagree, the logs are right.**
- **An API accepting a request is not the request having had its intended effect.** `DADiskUnmount`
  reports success while a volume is still mounted; `fcntl(F_NOCACHE)` returns 0 on `/dev/null`.
  **Verify the postcondition, not the return value** — and where the postcondition is observed
  asynchronously, re-read it until it settles.
- **A plausible mechanism that would produce the observed symptom is not the cause of it.** This has
  now cost three separate diagnoses: a missing error message explained by reading and excluded by one
  log line; a dark-mode render blamed on an app defect and refuted by looking at the app; and then
  blamed on colour resolution and refuted by reading the capture code.
- **A correct value that nobody can observe is indistinguishable from a wrong one.** Two of Step 10's
  five rounds went on a mechanism that was right and unobservable. **Build the instrument before the
  mechanism** — a green suite over a false premise is exactly as green as one over a true premise.
- **A test that agrees with any change is not a check.** A key-name test read the key from the
  constant on both sides and would have passed the rename it was written to prevent.
