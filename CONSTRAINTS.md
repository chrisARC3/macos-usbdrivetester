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

So a whole-device sequencer must **slice by whole MiB and let only the final call be short**. That
conclusion is right. **The justification this entry gave for it was measured on 2026-08-14 and is
wrong**, and the correction matters because it moves where the fragility actually is.

This entry used to say a sequencer advancing by *"1 GiB or whatever is left"* is **"refused on its
last-but-one call"** against a device whose size is not a whole number of MiB. Checked rather than
believed — `Core/RunParameterValidator.swift` compiled standalone, four geometries walked through
`RunPlacement.validate`:

| geometry | naive `min(cap, remaining)` |
|---|---|
| 1 TB T5, 1,953,525,168 blocks | 932 calls, **0 refusals** |
| 4 TB T5 EVO, 7,814,037,168 | 3,727 calls, **0 refusals** |
| 22 TB Seagate, 42,970,644,479 | 20,490 calls, **0 refusals** |
| 4,096-byte, 244,190,646 | 932 calls, **0 refusals** |

It produces slices **identical** to whole-MiB slicing on all four, and is safe for one unstated
reason: **`maximumBytesPerCall` is itself a whole multiple of 1 MiB**, so `min(cap, remaining)` is
always either a whole 1 GiB or the final remainder, which is exempt. Give it a cap that is *not* a
whole number of MiB and it is refused on **call 2**, not last-but-one.

What **is** refused on its last-but-one call is a different sequencer — one that backs the final
call up so it is a full 1 GiB — failing at #931/#932 on the 1 TB T5 and #3726/#3727 on the 4 TB EVO.
The recorded symptom belongs to that algorithm and was written down against this one.

**Two things follow, and the second is the one that costs something.** Whole-MiB rounding is correct
for *any* cap where the naive form is correct only for today's — so keep it. And because the two
agree on every real geometry, **a test that only slices real devices at the real cap cannot tell
them apart**: `RunSlicing`'s cap is therefore an injected parameter and the suite slices with
deliberately ragged ones. Confirmed by mutation — deleting the rounding is killed by the ragged-cap
cases and **not** by the walk over the real drives.

*Full accounts: `progress/step-09.md` for the rule; commit `c8bcc2a` for the measurement.*

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

**Every figure here is now the RUN's, not the call's** — see "the session is the claim" in section 2,
built in Step 11 increment 3. The two exceptions are `bufferBytesHeld` (2 × *this call's* I/O size,
because FR-CTRL-8 lets the size change mid-run) and `runOutcomeCode` / `interruptedAtBlock` (how
*this call* ended is what a sequencer branches on).

- **p99 is octave-bucketed, integer-only, and reported as an UPPER BOUND.** Read-latency statistics
  accumulate across **every call of the run** (increment 3). **Percentiles do not compose**, so an
  app aggregating per-call p99s cannot produce a whole-run one; that is why the accumulator had to
  move rather than the app doing arithmetic — and it is also why *"reset the figures on a size
  change"* could never have been an app-side subtraction.
  **A run no longer spans two I/O sizes at all** (FR-CTRL-8 revised 2026-08-14, and enforced more
  simply since 2026-08-19 — the size is fixed for the whole run, so there is no mid-run change left
  to handle). The bimodal-distribution caveat this entry used to carry is retired, and
  `RunReport.latencySpansMultipleIOSizes` is permanently `false` — correctly, because the product
  cannot produce a run that would make it true.
- **Progress is byte-denominated, never chunk-denominated.** The justification this entry used to
  give — *"which is what makes a mid-run size change expressible at all"* — **has lapsed**: there is
  no mid-run size change as of 2026-08-19. The requirement stands on its other reason, which was
  always the load-bearing one and is stated two sentences below: a bounded run must report the
  fraction of the **drive** it covered. `chunkMeasured` fires **once per chunk on every path**,
  including the three failure branches, so a display keeps advancing on a failing drive instead of
  freezing.
  The denominator is the **whole device**, from the claim's authoritative ioctl geometry, stated
  once when the session opens. A bounded diagnostic run therefore reports the fraction of the
  *drive* it covered, not 100% of the piece it asked for — which is the true statement.
- **`isComplete` and `fractionComplete` answer different questions and are not derived from each
  other.** The first is "every chunk the calls asked for was attempted"; the second is "this much of
  the device". Both are true at once after a call that completed. Collapsing them makes one lie, and
  it is the whole-device figure the user reads.
- **Throughput is reported, never graded.** The manufacturer's sustained figure is not something this
  tool knows, and inventing a verdict would be a judgement dressed as a measurement.
- **"Completed clean" means *no currently-unreadable blocks were found*, never "healthy".**
- **A refused call is not a run**: no report, and the refusal is logged so its absence is explicable.
- **The figures belong to this run or they do not exist — and from increment 3 that is a WEAKER
  guard than it was.** Protocol v9 read them from an observer installed *after* validation, so a
  refused call had nothing to misattribute; `MetricsChannel.begin()` and its process-wide slot are
  **gone**. The accumulators now live on the claim and predate the call, so what keeps the property
  is only that the helper assembles the reply from a `CycleResult`, which exists on the success path
  alone. They sit one line from the refusal path, and `main.swift` is not in the test target.
  **`metrics-check.sh`'s three "reported no figures" assertions are the only cover anywhere** —
  verified, not assumed: mutation H1 (2026-08-12) wrote that exact defect and the gate killed it.
  Do not weaken those assertions.
  What *did* improve: a poll can no longer return a **previous** run's figures at all, because the
  session dies with the claim.
- **NFR-PERF-3 has numbers, and there are now TWO of them that must not be confused.** The
  host-overhead ratio is 2.55% at 4 MiB (2026-08-05) and **2.620% over a whole run** (2026-08-14) —
  both mean the run is device-bound, and both are host ns ÷ device ns, undiluted. The **daemon CPU**
  figure is the one that changed meaning: Step 9's **4.22% of one core** was per call, whereas from
  increment 3 it is bracketed from `acquireDevice` and is a **run average diluted by the idle
  between calls** — measured 7.73% → 6.50% → 5.44% → 4.85% across four calls, falling as idle
  accumulates. Step 16's release note wants the during-I/O figure. Quote which one you mean.
  **Host cost follows bytes moved, not chunk count** — a larger I/O size does not reduce it.

*Full accounts: `progress/step-09.md`, `progress/step-10.md`; increment 3, commit `4c84329`.*

### Device loss (Step 12's territory, and a live defect until then)

- **`ENXIO` on offset 0 of a working descriptor means the descriptor is dead.** `EIO` on a block
  means a bad block. Detect loss from those and from the DiskArbitration/IOKit removal callback.
- **Do not infer device loss from a failure count.** A genuinely dead drive also fails every chunk,
  so the heuristic is wrong exactly when being wrong is most expensive.
- **Until Step 12 builds this, a drive that drops off the bus is reported as a drive with ~2 million
  bad blocks** — a false accusation about a drive, in a file that outlives the session. Nothing is
  distributed before Step 16 (section 2), so the person misled is the one who can recognise it —
  which lowers the stakes and changes nothing about the defect. The exported report is still the
  artefact a drive's history is kept in, and this project has already had one report that could not
  say which drive it was about. Observed for real during a hardware gate, not simulated.

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
- **A render cannot answer "what sizes will this window be".** It shows a view at a size *you*
  chose; the window's own limits are a different question, and it is the one behind whether the app
  fits a small Mac. `ui-probe --limits <view> <width> <drives>` asks the real view hierarchy — it
  sets `NSHostingView.sizingOptions` so SwiftUI's minimum and maximum propagate to the window,
  exactly as a `Window` scene arranges — and `scripts/window-fit-check.sh` is that with a screen
  budget beside it. **Added Step 11 increment 7, because four defects had been sitting in plain
  sight of 29 render cases**: the window opened at screen height, `starting` clipped at the window's
  own minimum, the minimum swung 168 pt with the number of attached drives, and the live metrics
  panel clipped instead of scrolling.
- **`--limits` reports the larger of two numbers, and reading only the first was wrong by 58 pt.**
  What SwiftUI *declares* (`NSWindow.contentMinSize`) is built from the `.frame(minHeight:)` each
  pane asks for, and **a control can ignore the floor it is given** — see the lesson below. What
  the *layout* does is the smallest height at which the content stops overflowing the space it is
  handed, found by driving the window down. Each can be too small: the declared one when a floor is
  fiction, the measured one for a view whose whole body is a scroll region and so never overflows
  (`report` bottoms out at 24 pt against a declared 560). Neither can be too large, so the answer is
  the max. Until this was fixed the **width argument was inert** — `content-starting` reported the
  same height at 640, 700 and 900 — and the figures the gate's own header quoted for it had never
  been produced by the gate.
- **Drive count is a render axis** (sixth argument, default 1). Until it existed, **every render
  this project had ever taken showed exactly one drive**, so `DeviceListView`'s list — which grows
  to a 260 pt cap with the number attached — had never been looked at near that cap. The first
  six-drive render found a live defect immediately: two greedy `ScrollView`s, the metrics panel and
  the device detail, splitting spare height evenly, so a 700 pt window showed two drives of six
  beside a metrics panel spending 265 pt on one sentence. 6 saturates the cap.
- **The fixture's selection was on row 1 in every render ever taken, until 2026-08-20.**
  `DeviceFixture.fleet(of:)` puts `evo` first and the store selects the first usable drive, so the
  selected row was always at the top of the list and always visible — which made the whole harness
  structurally blind to *"is the chosen drive on screen at all?"*. `content-selection-below-fold`
  selects the **last** drive instead, and it is the only case that can see it. Render it near the
  window's minimum with **two** drives, not six: at six the required scroll saturates at the end of
  the content and succeeds regardless of whether the mechanism is right. An axis is only as good as
  the value you vary it to.
- **Render only as tall as you need — but the height argument is a FLOOR, not a ceiling** (measured
  2026-08-11, correcting a header note that had called it "the lever"). `NSHostingView` sizes to its
  content, so a view with no intrinsic cap ignores the number: the `metrics*` family returned
  **2,876 pt** when asked for 460. Step 11 increment 7 named the cause — `--limits` reports
  `max=infxinf` for the main window, and an unbounded maximum is also why the window opened at
  screen height while the scene declared no `.defaultSize`. `sips -c <h> <w>` centre-crops reliably, but **`--cropOffset` is
  measured to be silently unreliable** — ignored when the crop fits, and once returning the source
  image unchanged, with no error either time.
- **31 view cases, and three of them render a state this machine cannot produce** — `empty` (no
  drives), `devices-unmounted`, and `devices-unusable` (a drive with a `geometryProblem`, which no
  drive here has). Each exists because *a state nobody can observe is a state nobody has checked*;
  the third was added in Step 14 for a row that had never been rendered in either appearance.
  `devices-unmounted` has since taken a **second** job it was not built for: since 2026-08-23 its
  fixture drive is the only one in the harness reporting `usbLinkSpeedCode == -1`, so it is the one
  render where the link-speed row's unknown sentinel appears at all.
  **The probe is authoritative and `render-ui.sh`'s header list has drifted from it three times** —
  caught 2026-08-11; again by Step 11 increment 6, which found the script listing 24 cases against
  the probe's 28, naming two (`diagnostics-held`, `diagnostics-quitting`) the probe would refuse
  with exit 2 and omitting all six `content-*` run states; and again on 2026-08-23, when the script
  still said 34 against the probe's 31 after the Restart removal deleted three. Re-derive the list,
  never hand-edit it; the one-line `grep` is in the script's header. **Three drifts is the number
  that says this will drift again.**
- **A render cannot see the live metrics panel, the report body, or sheet modality — and all three
  hid a defect on 2026-08-18.** The panel polls a real helper, so offscreen it always shows the
  unavailable state whatever the run state is; the report body sits in a scroll region, so a render
  stops at `## Measurements`; and a window-modal sheet answers ⌘Q before `QuitPolicy` is consulted,
  so the policy's truth table is not what decides. **An acceptance criterion derived from model
  code alone is a guess about the presentation layer** — 6.1 of the human checklist was predicted
  from `QuitPolicy` and was wrong for exactly that reason. These are the checklist's territory, not
  the harness's; see `progress/step-11-human-checklist.md`.
- **`tools/ui-probe` is a gate client and belongs in the list rebuilt after a protocol bump.** It
  went uncompilable for three increments because v10 → v11 rebuilt `metrics-probe` and
  `mount-guard-client` and not it. `scripts/build-tools.sh` now type-checks all 13 in seconds, and
  found `tools/nocache-probe` broken since Step 9 on its first run.
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

- **NOTHING IS DISTRIBUTED UNTIL THE WHOLE BUILD PLAN IS COMPLETE** (user decision 2026-08-14). No
  early access, no preview build, no external tester. Step 16 is where distribution happens; every
  build before it runs on this machine, for the person building it.

  **What it changes is who is exposed to a defect, and therefore how a risk reads.** Several notes
  here and in the requirements were written as though a stranger would be handed a wrong answer
  about their own hardware. Until Step 16 the reader of every report this tool produces is the
  person who wrote it. A wrong report is still wrong; it is merely being shown to the one person
  equipped to recognise it.

  **What it does not change, which is the larger half:**

  - **Every runtime guard stays.** The mount guard, the exclusive claim, `RunPlacement`'s refusal,
    `mayIssueNewWork`, the pre-run dialog and its two clicks — none of these exist to make a
    *release* safe. They exist because FR-DEV-3 default-selects the first usable device in BSD-name
    order, which on this machine is **the 22 TB Seagate carrying Backup and Time Machine**, and
    because every hardware gate writes real bytes to a real drive. The exposure they cover is
    today's, not Step 16's.
  - **The per-step gates stay.** Their purpose is that a step's defects are found in that step
    rather than four steps later. Who eventually receives the result has nothing to do with it.
  - **The verification rules stay**, including the one below whose wording rested on the word
    *ships* and has been corrected.

  **Searched rather than assumed, 2026-08-14.** The source contains no `#if DEBUG`, no production
  flag, no release-gated path, no `TODO`/`FIXME`/`HACK`, and no guard whose stated justification is
  a recipient other than this machine's owner. There was no mechanism of that kind to remove — the
  thing this decision actually retires is a *framing*, not a guard.
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
  2026-08-12 over the alternative below; **built in increment 3, `4c84329`, and measured on
  hardware**). Start takes the claim once, holds it for the whole run, releases it once — **never a
  claim per chunk**, which is unbuildable anyway: macOS remounts the volume **~4 ms** after a
  release (measured Step 6), so a per-chunk release would race its own remount tens of thousands of
  times.

  **The session is *stored on* the claim, not kept in step with it**, and that is the load-bearing
  part of how it was built: `AcquiredDevice` holds a `RunSession`, created by `DeviceClaim.acquire`
  and destroyed by `release()`. So a fresh claim starts empty and a released claim answers nothing
  **by construction** rather than because somebody remembered to clear a slot. `MetricsChannel`
  keeps only its lookup job; `begin()` and its process-wide slot are deleted. The alternative —
  keep the slot, add an `end()` called from release — was rejected as two things that must be kept
  in step to state one fact, which is what `AppModel.helperHoldsDevice` is being deleted for.

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

  **The third of those grounds lapsed on 2026-08-14** — there is no resume across a size change any
  more, so nothing has to survive one. **Shape A is unaffected**: it stands on the four properties
  above, and the amendment that retired this ground is one Shape A is what makes cheap (a size
  change ends the run, the claim goes, the session dies with it). Recorded so nobody re-derives a
  decision from an argument that has expired — the first two grounds are untouched.

  **What is NOT a reason, and was checked rather than assumed:** preserving the 1 GiB cap. The
  cap's own justification lapsed in this step (see section 1), and pause latency is set by the
  chunk regardless — so Shape A stands on the four properties above, not on the cap.

  *Full account: commit `e13d3e8`; the measurement that backs it, `scripts/run-control-check.sh`.*
- **THE MAIN WINDOW'S MINIMUM HEIGHT IS NOT WRITTEN DOWN ANYWHERE, AND THAT IS THE DESIGN**
  (NFR-USE-9, Step 11 increment 7). Each pane that scrolls declares its own floor in
  `WindowMetrics`; SwiftUI sums those with the blocks that cannot scroll; nothing states the total.
  The literal this replaced lived in `ContentView` and **expired three times, silently each time** —
  a measured constant is only true until the content above it changes, and nothing recomputes a
  literal. Do not reintroduce a total, including "as documentation": a number that is right today
  and unwatched is the exact failure being designed out. `scripts/window-fit-check.sh` is what
  checks it, by measurement, against a screen budget — **the laid-out hierarchy, not SwiftUI's
  declared minimum**, which was wrong by 58 pt until 2026-08-20. The budget is **700 pt**: a
  13.3-inch at 1280x800 with the Dock (user decision, 2026-08-20, replacing a one-day commitment to
  every scaling that was chosen from the broken figures).
- **POINTS, NOT PIXELS.** A 13.3-inch Apple Silicon Mac is 2560x1600 **pixels** and **1440x900
  points** at default scaling. Every window measurement in this project is in points. Reasoning from
  the pixel number inflates the budget by a factor of 1.8 and makes a window that does not fit look
  comfortable — which is how this question was first framed, and it would have closed with the
  defect still present. Measured chrome: title bar **32 pt**, menu bar **30 pt**, default bottom
  Dock **~70 pt**.
- **A RUN USES ONE I/O SIZE, AND BOTH PRE-RUN CONTROLS ARE FIXED FOR THE WHOLE OF IT** (FR-CTRL-8
  revised 2026-08-14 and again **2026-08-19**; FR-CTRL-7 amended to match). The I/O-size dropdown
  and the failure-mode picker are live in `idle` and `finished` and **dead in the six states where a
  run is under way, `paused` included**. One rule, one disabled sentence, both controls. Testing at
  a different size is a new run from block 0, reached by **Stop → change → Start**.

  **A run using one size is what gets clean accumulators by construction**, and it cannot be had any
  other way: not app-side, because percentiles do not compose and a minimum cannot be un-seen; not
  by releasing and re-acquiring mid-pause, because macOS remounts ~4 ms after a release. The
  alternative was a protocol method resetting the session's accumulators plus a session split into
  two accumulator lifetimes, which would put two scopes in every report.

  **The paused window is gone, and this is the third revision — do not re-derive it from the second.**
  2026-08-04 made the dropdown live while paused with the statistics accumulating across a change;
  2026-08-14 kept it live and made a change *end* the run; 2026-08-19 made it dead. What settled it
  was **looking at the built control on hardware with a run paused**: the size was live and the
  failure-mode picker beside it was not, and two adjacent controls with different rules read as one
  being broken. *"The user should either be able to change both or neither."*

  **Both went to the dead side because they could not be made to agree on the live side.** The size
  cannot resume across a change (above). The **mode can** — it is per call, a stored property on
  `RunSequencer`, and it contaminates no measurement — but `RunReport.failureMode` is a single field
  taken from the **last call's reply**, and `stopOnFirstError` selected *after* failures already
  exist has no defined meaning. So "both live" bought an ambiguity with no principled answer.

  **It deleted a mechanism built earlier the same increment**: the size-change confirmation, its
  alert, `RunController.endRunForIOSizeChange()` and three test suites, all untriggerable once no
  state can reach them. Full account in the FR document's 2026-08-19 amendment.
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
- **Nothing untriggerable is built in advance.** An outcome, mode or control with no way to reach it
  waits for its trigger — *a sound mechanism behind a trigger that never fires looks exactly like a
  broken one.* **This is a rule about verification, not about what a release contains**, and it is
  worth being precise now that nothing is released until the plan ends: it says you cannot
  distinguish a working unreachable mechanism from a broken one, which is as true on a machine
  nobody else will ever see. It read *"nothing untriggerable **ships**"* until 2026-08-14, resting a
  live rule on a premise that is now explicitly false.
- **`defaults` addressed by domain does not reach this app's preferences — for reads OR writes.** A
  stale sandbox container under `~/Library/Containers/com.arc3solutions.USBDriveTester` (7 July,
  from before App Sandbox was turned off) makes the CLI prefer a container path that the app has
  never written. It reports *"does not exist"* on a read and **succeeds silently on a delete having
  done nothing**. Cost time twice: increment 6 (a read, diagnosed as a missing preference) and
  increment 7 (a delete, diagnosed as `.defaultSize` not working, and a checklist item recorded as
  failed). Address the plist by **path**. The first write-up called it a read problem, which is what
  let it happen again.
- **A requirement you are about to cite may not exist.** Step 11 increment 7 was built, measured and
  gated against "the window must fit a 13.3-inch Mac" — and the docs pass found that **nothing in
  either requirements document said what it had to fit**. Three source citations of `NFR-USE-8` had
  been written by then, pointing at an *accessibility* requirement that says nothing about window
  size. Check the ID resolves to the thing you mean before writing it down; a wrong citation is
  worse than none, because it reads as having been checked. NFR-USE-9 now exists.
- **The daemon holds process-wide state, and a gate script is not the app.** `RunControlChannel`
  is a single slot on the helper shared by every client, and nothing clears it but the caller. The
  app clears it before every run and every resume, awaits the confirmation, and abandons with a
  visible message if it does not come — so the app is immune, and the class's own header argued from
  that immunity that a stale value was *harmless*. It is not. On 2026-08-23 the app left `stop` in
  the slot at 09:11:29; `metrics-check.sh` ran later, inherited it, and its four bounded calls each
  returned `stoppedByUser` after **0.5 ms having processed zero chunks**. Forty assertions failed and
  **not one of them named the cause** — they all reported downstream consequences (no chunks, no
  latency, `-1` throughput) of one stale value. `run-control-probe` had cleared the slot since
  increment 2; `metrics-probe` predated the channel and never did. **Any probe that issues a run
  must clear the level first**, and any argument that reasons about the app has not yet said
  anything about the gates. The comment was corrected 2026-08-24, which moved the helper source
  hash for a comment-only change — see PROGRESS for why the gates still stand.
- **Show a check answering both ways before trusting either — a mutation is one way to do that,
  and often not the cheapest.** The device-operation slot check added 2026-08-24 asserts that a
  second run is refused while one is in flight; on its own that proves only that *something*
  refused. It issues the identical call again with nothing in flight and asserts it is **accepted**.
  Same request, same connection, one variable. That also settled a question reading the source had
  not — whether `runRetentionCycle` gates on connection ownership — and it cost nothing, where a
  mutation would have meant rebuilding and **reinstalling a privileged daemon** to test the guard
  live. Where the product can be made to demonstrate both answers, prefer that to a mutation.
- **A gate that has not been re-run cannot report anything, and its probe rots quietly.** Step 11
  increment 3 moved the run accumulators onto the claim, so `chunksProcessed` became cumulative
  across a session rather than per call. That broke two probes identically. `metrics-probe` was
  updated at the time and says so at length in its header; **`run-control-probe` was missed, and
  nothing noticed for twelve days** — its gate had last run on 2026-08-12 against a v10 daemon.
  When it was finally re-run on 2026-08-24 it reported five failures that all looked like a product
  defect (*resume block X, expected Y*) and were all its own arithmetic multiplying a running total
  by a per-call chunk size. **Both defects found this week were instruments, not product.** When a
  reply's meaning changes, grep every `tools/` client for the field, not just the one you are
  looking at; and re-run a gate when the thing under it moves, not when the calendar suggests it.
- **An incremental build does not re-emit warnings for files it did not recompile.** "Zero warnings"
  from a warm build is a statement about what changed, not about the tree. Only a clean build with
  DerivedData wiped answers the question, which is why the gate asks for three of them. Related:
  grep the build log for warnings **naming a `.swift` file** — a bare `warning:` also matches
  `appintentsmetadataprocessor`'s AppIntents line, which is not a source warning and produced a
  false alarm on 2026-08-24.
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
- **A MUTATION THAT DID NOT COMPILE IS NOT A SURVIVOR, AND A HARNESS THAT SAYS OTHERWISE IS THE
  WORST FAILURE AVAILABLE.** Increment 3's harness reported *"SURVIVED: all 0 tests passed"* for a
  mutation whose textual anchor occurred **twice** in the file: it patched the wrong site, the build
  failed, and zero tests ran. A suite that did not run is the number-that-did-not-move trap wearing
  a green hat — it would have been recorded as evidence that a real hole exists where none does.
  Two fixes, both required: a total of `0` is **inconclusive regardless of the failure count**, and
  every anchor is **asserted unique** before it is applied. Verifying that the pattern *exists* is
  not verifying that it landed where you meant.
- **One flag stating two facts misdiagnoses, and the mutation is how you find out.** The metrics
  probe computed `REFUSED` as `outcome == unrecognised && chunks == 0`. A mutation that leaked
  figures into a correct refusal flipped it, and the gate announced *"the alignment guard is not
  enforced"* — pointing at innocent code while the real defect was three lines below. Under a
  cumulative session the conflation was also measuring the wrong thing outright, because the chunk
  count in a reply is the run's total. Split them.
- **`git checkout <file>` reverts to HEAD, not to the state you were mutating from.** Used to undo a
  deliberate defect, it silently discarded an increment's worth of uncommitted edits to that file as
  well. It was caught by **re-deriving the helper source hash and finding it did not return to the
  known-good value** — a hash against a known-good one is a stronger restore check than reading a
  diff, and it costs one command. Mutate from saved pristine copies with a `cmp` guard.
- **A whole-binary comparison does not answer "did this change behaviour".** Debug builds embed
  line numbers, so a comment-only edit produces a different binary. Comparing `__TEXT,__text` and
  `__TEXT,__cstring` does answer it — byte-identical across 1.63 MB of instruction text is proof
  the compiled behaviour is unchanged, and it is what let a post-gate comment rewrite stand without
  re-running the gate.
- **A FLOOR A CONTROL IGNORES IS INDISTINGUISHABLE FROM A FLOOR THAT WORKS, AND EVERYTHING BUILT
  ON IT INHERITS THE LIE.** `WindowMetrics.deviceListFloor` asks the drive list for 46 pt. The
  AppKit table behind SwiftUI's `List` will not lay out below about **104** whatever it is told, so
  the constant is a request that is accepted and has no effect. Nothing warned; the modifier
  compiled, rendered, and was believed — **including by SwiftUI itself**, which is what made it
  expensive. `contentMinSize` is computed *from* the declared floors, so the window's declared
  minimum came out 58 pt below any height the content can occupy, `window-fit-check.sh` was built
  on that number, and for a day the gate reported the window fitting screens it does not fit while
  a render at the reported minimum visibly clipped its header.
  **The instrument inherited the defect it existed to catch.** Found only by driving the shipped
  window with accessibility scripting and comparing — which is the general lesson: when a gate and
  the app disagree, the app is the fact, and a gate that has never been calibrated against the
  running thing is an assertion wearing a measurement's clothes. Verify a floor by measuring what
  the layout does with it, never by reading it back.
- **The bigger case is often the weaker test, and it is the one you will reach for.** Keeping the
  drive list scrolled to the selected row worked at six drives and failed at two. The reason is
  saturation: at six, the scroll runs into the end of the content and clamps — and a clamp does not
  care that it was computed from a viewport height which had already changed, so the large case
  comes out right whether the mechanism is right or not. At two drives the correct answer is a few
  points wide, and only a correct mechanism finds it. **Choose the input where the right answer is
  narrow**, not the one where the effect is largest; a visible effect is not a discriminating one.
  The defect underneath was a third instance of a shape `DeviceListView` had already recorded twice
  — a handler running before the layout it reasons about has settled — and it was one deferred
  run-loop turn away from correct.
