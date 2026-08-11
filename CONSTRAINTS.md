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
- **Pause and stop are subject to the same constraint** (Step 11).
- `releaseDevice` on the owning connection during a run would queue behind the very call it was
  meant to shorten. This is why quitting waits for the call boundary rather than releasing first.
- `TesterProtocol.maximumBytesPerCall` (1 GiB) is not a tuning parameter: it is what makes an
  uncancellable privileged call survivable at ~7 s, and it is what makes the busy-refusals of
  `releaseDevice` and `prepareForShutdown` reachable at all.

*Full account: `progress/step-09.md`, D1.*

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
- **Render only as tall as you need.** Rendering 1,800 pt to inspect a 200 pt section is pure waste;
  the height argument is the lever. `sips -c <h> <w>` centre-crops reliably, but **`--cropOffset` is
  measured to be silently unreliable** — ignored when the crop fits, and once returning the source
  image unchanged, with no error either time.
- The probe prints `appActive / windowKey / firstResponder / appearance` on every run. That line has
  settled several questions that were otherwise being argued about.

*Full account: `PROGRESS.md`, Step 14 increment 3.*

---

## 2. Settled — do not re-open

- **Runs cover the WHOLE DEVICE, always start at block 0.** No user-selectable start, ever. Progress
  is a bar with a live percentage, never a slider.
- **FR-DEV-3 default-selects the first usable device in BSD-name order**, confirmed under challenge
  2026-08-06 with the hazard in front of the user. *"I do not want to go down the road of trying to
  divine user intentions."* Same policy as refusing to grade throughput. **On this machine that
  default is currently the 22 TB Seagate with a live Time Machine on it** — which is why Step 11's
  removal of the explicit unmount is gated on Step 14's warnings existing.
- **FR-SAFE-5 withdrawn, FR-SAFE-6 REVERSED, FR-SAFE-7 moot.** Start owns unmount → acquire → run →
  release. FR-SAFE-1/2/3 and NFR-REL-3 are untouched: only *who performs the unmount* changed.
- **NFR-USE-4 qualified 2026-08-09.** The pre-run warning **text** is suppressible per logged-in
  user; the **deliberate act is not** — a suppressed run still raises a confirmation naming the drive
  by model and USB serial.
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
