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

### Run control: a level the run reads, and a settle at a chunk boundary

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

**Measured on hardware three times** — `scripts/run-control-check.sh` on the 1 TB T5 scratch drive
(`12345686DAA9`), at protocol **v10 (2026-08-12)**, **v12 (2026-08-24)** and **v14 (2026-09-05)**.
The v10 run, calibrated against an uninterrupted control run of 1 GiB in 6,868 ms — 469 MB/s of
device I/O, matching this drive's independently measured rate:

| I/O size | 1-chunk bound | settle | fraction of bound |
|---|---|---|---|
| 1 MiB | 6.71 ms | 5.83 ms | 0.87 |
| 2 MiB | 13.41 ms | 10.13 ms | 0.76 |
| 4 MiB | 26.83 ms | 6.19 ms | 0.23 |
| 8 MiB | 53.66 ms | 42.45 ms | 0.79 |

**The settle lands at a chunk boundary, and takes the rest of the current chunk plus about 3.5 ms.**
The pause lands at a uniformly random point inside a chunk, so a single sample scatters across the
bound, which is why 2 MiB came out *higher* than 4 MiB here. That is two draws from two different
distributions, not noise in the mechanism. **Do not quote the bound as the typical value**; an
earlier note in this project did, and the correction is the reason this table exists rather than a
single figure. The fixed term is measured below and is what puts the 1 MiB column above its bound.

⚠️ **This section said "bounded by one chunk" until 2026-09-05. It is not bounded by one chunk, and
as of 2026-09-05 that is measured rather than suspected.** The four-size samples, each as a fraction
of its own bound — calibrated uniformly as `2000 ms ÷ chunks done in the 2 s pre-pause window`,
which is what makes the runs comparable:

| run | 1 MiB | 2 MiB | 4 MiB | 8 MiB |
|---|---|---|---|---|
| v10, 2026-08-12 | 0.87 | 0.75 | 0.23 | 0.81 |
| v12, 2026-08-24 | 0.96 | 0.23 | 0.36 | 0.38 |
| v14, 2026-09-05 | **1.43** | 0.58 | 0.23 | 0.13 |
| **v14, 2026-09-05 (second run, same hash)** | **1.52** | 0.78 | 0.48 | 0.13 |

*(The v10 row differs by a point or two from that run's own column above, which calibrated off the
control run instead. Either calibration puts the same samples in the same places.)*

**THE MODEL IS `settle = the remainder of the current chunk + a FIXED COST OF ABOUT 3.5 ms`, and
the experiment that settles it has been run.** `run-control-check.sh --repeat-1mib 8`, 2026-09-05,
v14 daemon at helper hash `e6888aa5…`, the 1 TB T5 scratch drive — the 1 MiB case alone, eight
times, each self-calibrated from its own pre-pause window:

| sample | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| settle (ms) | 8.92 | 6.20 | 9.45 | 4.67 | 4.39 | 5.56 | 6.15 | 8.10 |
| fraction of bound | 1.32 | 0.93 | 1.39 | 0.69 | 0.65 | 0.83 | 0.92 | 1.21 |

**Nothing came near zero. The minimum was 0.65 of its own bound**, and under a uniform draw over
`[0, bound]` eight samples all above 0.65 is `0.35⁸` — about **one chance in 4,400**. Three of the
eight also exceed 1.0, which a uniform draw cannot produce at all. **A fixed cost has a floor; a
uniform draw does not**, and this is a floor.

**The size of the cost, from three estimators that agree.** With `B ≈ 6.73 ms`, a shifted uniform
`U(c, c+B)` predicts a mean of `c + B/2`, a minimum of `c + B/9` and a maximum of `c + 8B/9`. The
observed mean 6.68, minimum 4.39 and maximum 9.45 give **c ≈ 3.3, 3.6 and 3.5 ms** respectively, and
the observed range 5.06 ms sits against a predicted `7B/9 = 5.23`. **c ≈ 3.5 ms.**

**It also fits every earlier sample, which is the check that matters.** A fixed 3.5 ms puts each
size's fractions in `[c/B, c/B + 1]`: 1 MiB `[0.52, 1.52]`, 2 MiB `[0.26, 1.26]`, 4 MiB
`[0.13, 1.13]`, 8 MiB `[0.065, 1.065]`. **All twenty samples in the two tables above fall inside
their band**, the single marginal case being v12's 2 MiB at 0.23 against a 0.26 floor — three
hundredths, inside the calibration's own precision. That is why the 1 MiB column rides high in
every run while the 8 MiB column scatters freely: the same 3.5 ms is half of one chunk at 1 MiB and
a fifteenth of one at 8 MiB.

⚠️ **What the cost IS has been measured, not explained** — the same standing as the ~209 µs
per-chunk term in the daemon's CPU. It is **not** simply transport latency: the daemon's
acknowledgement of the pause request travels the same XPC in **0.36–0.53 ms**, an order of magnitude
less. The reply that carries the settle is a 22-argument cumulative payload off a connection that
has been blocked for the whole call, which is a plausible difference and **is not evidence.** Do not
write down a cause for this figure without measuring one.

**None of this touches NFR-REL-10**, which requires the settle to happen *at a chunk boundary with
no write in flight* and says nothing about how long it may take. Its evidence is the resume
arithmetic — `resumeBlock == startBlock + chunksProcessed × blocksPerChunk`, exact and 1 MiB-aligned
in every case of all four runs, the eight repeat samples included — and the millisecond figures are
characterisation beside it. `run-control-check.sh` **reports** the settle rather than asserting it
against a threshold, on the stated ground that throughput is measured here and not graded; that is
why nothing flagged the 1.43. **There was no assertion to fail, by design rather than by omission**,
and now that the floor is measured there is still nothing to assert: a settle of one chunk plus
3.5 ms is the mechanism working.

⚠️ **A withdrawn claim, recorded because the mistake is repeatable.** Step 11's gate item 2 said
*"settle tracks the I/O size rather than the 1 GiB call cap"* on the strength of the v12 run's four
samples. **No other run shows that ordering** — 2026-09-05's first v14 run is inverted
(9.33 / 7.59 / 5.93 / 6.59), its second is unordered (10.14 / 10.26 / 12.88 / 6.62), and v10 is
unordered. **Four samples fitted a trend that twelve more contradicted**, in a quantity this section
already says scatters. The claim two paragraphs below is the one that has survived every run, and it
is the one to quote.

The daemon acknowledged each request in **0.34–0.62 ms** across all four runs, and **that
acknowledgement is not the settle.** The helper recording a request and the run having acted on it
are different facts; only the second is NFR-REL-10's guarantee, and nothing may display "Paused" on
the strength of the first. **The gap between the two is where the 3.5 ms lives**, and it is the
reason the ack cannot stand in for the settle even as an approximation.

**Latency is set by the CHUNK, not the call** — which is what makes the per-call cap irrelevant to
it. A cap of 8 MiB would produce these same figures, because the settle happens at a chunk boundary
*inside* the call either way. This is the claim that has held across v10, v12 and both v14 runs.

*Full account: commits `e13d3e8` (the measurement), `c8ca155` (the v14 re-run) and `a6e3bb0` (the
fixed-cost finding). The experiment is reproducible as
`scripts/run-control-check.sh --repeat-1mib 8`, which re-runs the whole gate and then takes the
samples.*

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

**A USB bridge answers for the drive, and often declines.** `Medium Type` — the IOKit key behind the
`Medium` row — is published by the enclosure, not the medium. Measured 2026-09-02 across six
attached drives: the Portable SSD T5 and the 990 EVO Plus enclosure report `Solid State`; the
125.8 MB and 256.6 GB thumb drives and both Seagate Expansions publish nothing at all. **Two of the
three drives with no value are NAND**, so absence is not evidence of rotational media, and nothing
may gate a warning on it — FR-WARN-2's "run this infrequently on NAND" is unconditional in
`HonestFraming.mandatory` and must stay that way. Same shape as the SMART exclusion: what a bridge
declines to report is not information about the drive.

**Two drives on this machine share a block count.** The scratch Portable SSD T5 (`12345686DAA9`) and
the 990 EVO Plus holding this repository (`013117100578`) are both 1,953,525,168 blocks.
`device-identity.sh` selects on **serial** and uses the block count only to confirm, which is the
right way round and must stay that way — a block count cannot discriminate these two, and the drive
it would confuse the scratch device with is the one carrying the source tree.

**⚠️ Do not pair a serial to a drive by ADJACENCY in a text dump — measured 2026-09-08, a near
miss.** Establishing which BSD name held `12345686DAA9` before a write walk, an `awk` over
`ioreg -rd1 -c IOUSBHostDevice` that paired each `"USB Product Name"` with the next
`"USB Serial Number"` reported **`Portable SSD T5 → 00000S7CLNJ0WC02266P`**. That is the wrong
serial: the T5 is `12345686DAA9`. Within one IORegistry entry the two keys appear in **either
order**, and devices publishing one key but not the other slide the pairing along — the same run
silently dropped two of the six drives, including the 990 EVO Plus that holds this repository.
`system_profiler SPUSBDataType -json` was no better: its schema does not carry `serial_num` where
the flat listing implies, and a walk for it returned **nothing at all**, which is at least a *loud*
failure.

What works is a **structured walk that attaches each `"BSD Name"` to the USB device entry it is
nested under**, and it must allow product names containing spaces — a `\S+` in the entry-header
pattern silently matches no storage device on this machine, since every one of them is called
something like `Portable SSD T5`. The verified map is in
`progress/step-12-human-checklist.md` under *Which drive is which*.

⚠️ **2026-09-10: *nested under* has to mean the NEAREST enclosing `IOUSBHostDevice`.** A hub is a
USB device entry too, and can carry a serial — this machine's Apple *USB3 Gen2 Hub* reports
`7423J07` — and the 2026-09-08 map gave exactly that serial to the 4 TB T5 EVO behind it: the walk
attached the disk to an enclosing entry that was not the drive's own. The scratch T5's row was
right, so it was not a write hazard this time. Re-verified with a nearest-ancestor walk and
cross-checked against the app's own enumerator (`tools/device-id serial-of <bsd>`, built by
`scripts/lib/device-identity.sh`), which agreed on all six drives. **Prefer that second source**:
it is the code the product runs, and it is what `resolve_target` already trusts.

⚠️ **And because it is the code the product runs, it logs like the product — measured 2026-09-11.**
Every `resolve_target` writes `discovery found N USB whole disk(s)` into the app's own subsystem and
`discovery` category, from a process named `device-id`. On a walk that reads `discovery` lines as
evidence of what the *app* saw, two of them turned up between a pause and a pull, from the
resolver. **Read the process column on any `discovery` line**, and do not resolve a drive between a
cable pull and the readback of its log.

The rule underneath: **an instrument that returns a plausible wrong answer is worse than one that
returns none**, and both failed here on the way to naming a drive that was about to be written to
end to end. Cross-check any BSD↔serial mapping against a second source — `scripts/device-probe.sh`
prints BSD and model together — before it is used to pick a write target.

### Registering and replacing the helper (`SMAppService`)

Both measured at the keyboard on 2026-08-31/09-01, walking chunk 13 item 7. Neither is documented by
Apple and both were found only because someone pressed the button.

- **`register()` on a service that is already `enabled` is a no-op.** It reports success and reloads
  nothing, so a daemon already running keeps running the code it started with. The gate's
  `versionMismatch` remedy — whose own message reads *"Re-register the helper so the installed
  daemon matches this app"* — was therefore **inert in the only state where it mattered**, and the
  log showed `register() succeeded` with the same pid answering the same old protocol version
  immediately afterwards.

  **To replace a running daemon you must unregister first.** `install-app.sh` had been printing
  exactly that — *"(or unregister and re-register in the app's Step 3 panel)"* — since Step 4, and
  the app had never done it. `HelperRegistrationRemedy.forGate(_:)` now decides which of the two a
  state needs, and `HelperRegistration.replaceRunningDaemon(using:runIsActive:)` performs it.

- **A `register()` issued the instant a removal settles is refused** with
  `SMAppServiceErrorDomain 1 — Operation not permitted`. The status reaching `notRegistered` is not
  the same as the system being ready to accept a new registration. Measured: **the first attempt is
  refused and the next one, 500 ms later, is accepted** — every time, twice. So the register polls,
  the same way `performUnregister` already polled for the same class of behaviour.

  Left unhandled this cost a press: the gate dropped to `notRegistered` and the user had to press
  Register Helper again. **The whole replacement takes ~730 ms**, measured end to end.

- **A removal survives its own approval.** Unregistering and re-registering the same bundle path
  keeps the Background Task Management record — same `BTM uuid` either side — so the daemon comes
  back `enabled` without a fresh trip to Login Items. This is also why chunk 13's item 3 does not
  chain into item 4 on a Mac that has approved the app before.

- **⚠️ The BTM record is keyed by bundle IDENTIFIER, and several records can claim the same one —
  measured 2026-09-08.** `sfltool dumpbtm` after chunk 7f's install held **four** records for this
  app:

  | # | Type | URL | Generation | Embedded |
  |---|---|---|---|---|
  | 11 | app | `…/DerivedData/…/Debug/USBDriveTester.app/` | 355165071711802941 | **the helper** |
  | 12 | daemon | `Contents/Library/LaunchDaemons/…Helper.plist` | 115 | parent `2.com.arc3solutions.USBDriveTester` |
  | 6 | app | `/Applications/USBDriveTester.app/` | 6 | none |
  | 50 | app | `/Applications/USBDriveTester.app/` | 12 | none |

  All three app records carry the **same** `Identifier: 2.com.arc3solutions.USBDriveTester`, and the
  daemon's `Parent Identifier` names that identifier — so the parent pointer **does not identify a
  record**. What actually decides the resolution is which app record lists the helper under
  `Embedded Item Identifiers`, and that was the DerivedData one. `launchctl kickstart` therefore
  relaunched the daemon out of DerivedData while `/Applications` held a byte-identical copy, and
  the only thing that said so was `xpcproxy`'s `to program:` line.

  **Two `/Applications` records at the same URL, differing only in generation**, are the fingerprint
  of the bundle having been replaced at that path. `install-app.sh` does `rm -rf "$DEST"` before
  `ditto`, which deletes the bundle a live registration points at — the same hazard that script's
  own header describes for DerivedData paths, arriving at the stable path it recommends. **Whether
  the `rm -rf` is what re-parented the helper is NOT established**: what is measured is the state
  after, plus a `/Applications` resolve at 12:14:01 and a DerivedData resolve at 16:01:04 with one
  install in between. Recorded as a suspect, not a cause.

  The practical rule this leaves: **the version handshake, the protocol number and the binary hashes
  can all agree while the daemon is running out of a directory that gets rebuilt every chunk.**
  Provenance comes from the resolve line or from BTM parentage; it never comes from the bytes,
  because after an install the two bundles are byte-identical by construction. Do **not** try to
  force the issue by deleting the DerivedData bundle — with BTM still pointing at it that strands
  the record, and the only sanctioned cleanup is `sfltool resetbtm`, which resets Background Task
  Management for **every app on the machine**.

  **RESOLVED the same day, and the fix is the cheap one — measured 2026-09-08 16:22.** Unregister
  then Register from the `/Applications` app **re-parents the record in place**: #11 kept its record
  number, changed its URL from the DerivedData path to `file:///Applications/USBDriveTester.app/`,
  and bumped its generation `355165071711802941` → `710330143423605884`; the daemon record went
  `115` → `117`. **No record pointed at DerivedData afterwards.** So the neighbouring bullet's
  finding — *a removal survives its own approval, for the **same** bundle path* — extends to a
  **different** path as well: the registration follows the app that registers it, and
  `sfltool resetbtm` is **not** needed for this. Two childless `/Applications` records (generations
  6 and 12) were left behind and are harmless; duplicates accumulate and nothing prunes them.

  Order matters, and `register()` alone is not enough: the same section's first bullet records that
  **`register()` on an already-`enabled` service is a no-op**. The service was enabled the whole
  time — wrongly parented, but enabled — so a bare Register would have reported success and changed
  nothing. **Unregister first.**

  **⚠️ It does not stay fixed: a test run re-points the record at DerivedData — measured
  2026-09-09 15:34:09.672, found 2026-09-10.** Record #11 was back on the DerivedData URL, its
  generation bumped `…605884` → `…605885`, and **no install had run in between**. The BTM daemon's
  own log names the moment:

  ```
  _bundleURLForAuditToken: updating item uuid=226468B0-…, name=USBDriveTester, type=app, …
    url=file:///Applications/USBDriveTester.app/ URL to: file:///Users/…/DerivedData/…/Debug/USBDriveTester.app/
  ```

  That is six seconds into `Test-USBDriveTester-2026.09.09_15-34-03`. The suite's host **is** the
  app, run from DerivedData; it asked BTM about the daemon, and BTM moved the record to the asking
  process's bundle. It is the only such line in the retained log, which for this daemon reaches
  back only to 2026-09-09 13:14 — nothing from 2026-09-08 survives to compare.

  - **`rm -rf "$DEST"` is cleared on both counts measured.** The 2026-09-09 re-parent had no
    install to blame, and the 2026-09-10 09:26 install — `rm -rf` and `ditto` both — changed **no**
    USBDriveTester record, dumps before and after identical. What moved it on 2026-09-08 is still
    not established: a test run at 15:03:31 preceded it, which fits this mechanism and proves
    nothing.
  - **After any test run, a kickstart relaunches the DerivedData copy.** A running daemon does not
    feel it — its provenance was fixed when it launched — so the hazard is the *next* launch, and
    byte-identical helpers mean nothing else will say so. The reverse direction is recorded but not
    measured with a dump: on 2026-09-07 a kickstart came up from `/Applications` *"after the
    installed app had run and re-pointed the record"* (Step 12 checklist, Prerequisites).
  - **So read the record before a kickstart, and the resolve line after.** Record #11 — the app
    record listing the helper under `Embedded Item Identifiers` — must carry
    `file:///Applications/USBDriveTester.app/`. ⚠️ **`sfltool dumpbtm` needs admin**: run without
    `sudo` it raises a password dialog on the logged-in user's screen, every time — measured
    2026-09-10, `authd` logging a `system.privilege.admin` authorization for each of two runs made
    from an agent's shell, and a third left waiting on its dialog. It is a hand-over command, like
    the kickstart.

### Every scheme build is coverage-instrumented — measured 2026-09-10

**`build.sh`, `install-app.sh` and `test.sh` all produce binaries carrying LLVM coverage counters —
the installed app and daemon included, Release as well as Debug.** No `.xcscheme` has ever been
committed, so `-scheme USBDriveTester` runs a scheme `xcodebuild` **autocreates**, and that
scheme's test action gathers coverage. Xcode then synthesizes `CLANG_COVERAGE_MAPPING = YES` (with a
`CLANG_PROFILE_DATA_DIRECTORY`) into every action run through it — a plain `build` included.
Measured with Xcode 26.6, unchanged since 2026-06-26:

- `xcodebuild -showBuildSettings -scheme USBDriveTester` resolves `CLANG_COVERAGE_MAPPING = YES` for
  **Debug and Release**. The same query by `-target` resolves nothing.
- DerivedData's cached build requests (`XCBuildData/*/build-request.json`) carry it among their
  **synthesized** overrides for build-only runs, not only for test runs.
- All 21 helper object files carry `__llvm_prf_cnts`, and both helpers installed since chunk 7b
  carry the counters: `7590b920…` today, and `ab4b6957…` in its own `nm` output of 2026-09-07.

What it changes, and what it does not:

- **`nm -U` counts are not source counts.** Each function and each of its closures gains a local
  `___profc_` and `___profd_` symbol carrying the function's name, so `nm -U … | grep -c
  injectShort` is **14** for two functions. **A presence test uses `nm -gU`** — external symbols
  only, **2**. The Step 12 checklist expected 2 from plain `nm -U` from 2026-09-07 until this was
  found; how that "2" came to be recorded is in `PROGRESS.md`, chunk 7d.
- **No behavioural effect is known.** The counters change no result. An instrumented process that
  exits normally writes `default.profraw` into its working directory; the daemon's is `/` (its
  plist sets no `WorkingDirectory`), which is read-only, and no `/default.profraw` exists.
- **Every figure taken from the app or the daemon was taken on an instrumented binary** — seen
  directly from 2026-09-07, implied by the settings for as long as this Xcode has been installed.
  The figures compare like with like; none of them says what an uninstrumented build costs. That
  includes the unexplained ~209 µs per-chunk term in the daemon's CPU (`progress/step-09.md`), for
  which instrumentation is an **untested** candidate.
- **Not fit to distribute.** The counters' names embed absolute source paths —
  `___profc_/Volumes/1TB_UGreen/…/InMemoryBlockDevice.swift:…` — and a `build.sh Release` build is
  instrumented too (from the settings; no Release binary was on disk to inspect). Step 16 must
  build without it.

**Left as it is — user decision 2026-09-11.** Changing it then would have put a different binary
under Step 12's checklist chunks 4 and 5 than chunks 1–3 ran on — chunk 4 was walked on the
instrumented build later that day, and chunk 5 discharged from chunk 3's log — and it still needs a
kickstart while BTM points at DerivedData. **Revisit at the next helper-source change** — which
owes a rebuild, a kickstart and a gate re-run anyway — **or at Step 16, whichever is first.** Two
ways then: commit a shared scheme with coverage off, which keeps `build.sh` and `test.sh` on one
flavour; or pass `CLANG_COVERAGE_MAPPING=NO` from `build.sh`, which makes the two compile
differently into one DerivedData, so every switch between them rebuilds everything.

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
- **`NSApp.terminate(_:)` is a silent no-op while a sheet is attached** (measured 2026-08-27, AppKit
  probe). It is refused **before** `applicationShouldTerminate` is consulted, so `QuitPolicy` is not
  asked and nothing is logged. Ending the sheet first — in the *same* run-loop turn — is sufficient
  **for a sheet AppKit owns**, and needs no delay. It is not sufficient for one SwiftUI owns; see the
  bullet below, which is the case this app is actually in:

  | sheet attached | `applicationShouldTerminate` | outcome |
  |---|---|---|
  | no | reached → `.terminateNow` | the app exits |
  | yes | **never reached** | the app survives |
  | `endSheet` then terminate, same turn | reached → `.terminateNow` | the app exits |

  **`isSheet` is not the test for "may I terminate now".** The probe measured `isSheet` still
  reporting `true` immediately after `endSheet(_:)` returned, and terminating right then worked
  anyway: what blocks the termination is the live sheet *session* on the parent window, which
  `endSheet(_:)` closes synchronously. Anything gating on `isSheet` will gate on the wrong thing.
- **`endSheet(_:)` does NOT take down a sheet that SwiftUI presented** — measured in the shipped app
  on 2026-08-31, after two fixes built on the probe above failed in the product. The log read
  `ending sheets: 2 window(s), 1 sheet(s), 0 with no parent; 1 still flagged afterwards` and **no**
  `terminate requested` line ever followed it: AppKit was still refusing. SwiftUI keeps the sheet
  while its `isPresented` getter reads `true`, and a binding written with a **no-op setter** — which
  is how a non-dismissable modal is spelled — cannot be taken down any other way.

  So a SwiftUI sheet is dismissed by **making the model say it is not presented**, and only then can
  the app terminate. `AppModel.helperGateIsPresented` is that rule for the launch gate. **The probe
  was not wrong; it was not the app**: a plain AppKit sheet, and a SwiftUI sheet inside an
  `NSHostingView`, both quit on the first attempt. Three probe versions before that measured nothing
  at all — a SwiftUI `Window` scene launched outside Xcode never materialises its window, whether the
  binary is run directly or through `open`, so `onAppear` never fires. **What diagnosed this was
  logging in the shipped app, not a probe**, which is why the quit path is now instrumented.
- **This is what check 6.1 saw in increment 5** — "⌘Q during the pre-run dialog never reached
  `QuitPolicy`" — and `AppModel` carried a *guessed* cause beside it ("⌘Q reaches a different path")
  for two increments before it was measured. **⌘Q was therefore dead under every window-modal
  surface in this app.** There are **five**, not the three the increment plan named: a SwiftUI
  `.alert` on macOS is presented as a window-modal sheet like any other, so the quit confirmation and
  the run-failure/Full-Disk-Access alert blocked it exactly as the pre-run dialog, the report sheet
  and the launch gate did. It failed safe and it failed silently.
- **A SwiftUI `.alert` on macOS really is a window-modal sheet — measured 2026-09-04**, at the
  keyboard, with the quit confirmation on screen: `2 window(s), 1 sheet(s) [_NSAlertPanel];
  key=_NSAlertPanel`. It was believed rather than measured for three increments. **The class name
  differs from a `.sheet`'s** — a `.sheet` reports `SheetPresentationWindow`, an `.alert` reports
  `_NSAlertPanel` — but both set `isSheet`, both block `NSApp.terminate(_:)`, and both are counted
  by `AttachedSheets`. That is why the inventory prints class names rather than only a count.
- **An app-declared menu command DOES run while a sheet is attached** (measured 2026-08-21 for ⇧⌘R,
  chunk 11.11; and 2026-09-04 for a declared ⌘Q, increment 12 chunk 0). This is the fact the fix
  rests on, and it is not the same as AppKit's terminate: SwiftUI cannot present a second sheet on
  one window, so it **queues** the command's effect rather than swallowing the command. Without it
  there would be no path in which a quit rule could be consulted at all.
- **Fixed app-wide in increment 12 (2026-09-04).** Increment 9 fixed only the launch gate's own Quit
  button, locally. The app now replaces AppKit's Quit item with one of its own — the only route that
  is entered under a sheet — and that command asks `QuitPolicy.disposition(underModals:)`, a truth
  table with one answer per surface (user decision, 2026-09-04):

  | surface | ⌘Q does |
  |---|---|
  | nothing on screen | request the termination, unchanged |
  | run report | discard it, then quit |
  | launch gate | discard it, then quit |
  | pre-run prompt | **refuse**, and grey the menu item |
  | failure alert | **refuse**, and grey the menu item |
  | quit confirmation | **refuse**, and grey the menu item |
  | more than one flagged | **refuse** — the model cannot see SwiftUI's queue, so it does not know which is visible |

  Blunt "end every sheet then quit" stayed rejected for the reason 2026-08-27 gave: under the pre-run
  dialog it dismisses a prompt nobody answered. **The refusals are now visible rather than silent**,
  which was the half of the defect that mattered — the menu item greys instead of staying black and
  doing nothing. The modal table does **not** replace the run-boundary vote; they compose.

*Full account: `progress/step-09.md`, increments 3 and 4; the sheet measurement is increment 9's, and
the app-wide fix is Step 11 increment 12.*

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

### DiskArbitration at disappearance — measured 2026-09-05 (Step 12 route (b))

Driven headlessly against a real `DASession` with `hdiutil` ram disks, and then re-checked through
the app's **own** `VolumeChangeWatcher` compiled by `scripts/device-probe.sh --watch`. Route (b)
rests on all four of these, and every one of them was an assumption first.

- **An unmounted whole disk DOES fire `DADiskDisappeared`.** This is the one that mattered: a
  claimed device is unmounted by Step 6 before the run, and the obvious worry — that a disk with
  no volume left has nothing to report — is not the case.
- **`DADiskGetBSDName` and `DADiskCopyDescription` both still work inside the callback**, and the
  description carries `DAMediaWhole`. Neither is obvious for an object describing something that no
  longer exists. `DAMediaWhole` bridges through `[String: Any]` as an **`NSNumber`**, not a `Bool`;
  reading it as `Bool` alone silently reports every whole disk as a slice.
- **A partitioned drive fires once for the whole disk and once per slice** — observed as
  `disk13` then `disk13s1`, whole first. **Anything acting on this must be idempotent**, because a
  two-partition drive produces three events for one unplug. *(⚠️ 2026-09-10: that is with **nothing
  claimed**. Under a run's exclusive claim an unplug is **one** event — see *Under a claim, an
  unplug fires the WHOLE DISK only* below.)*
- **`DAVolumePath` is already absent by then**, even for a volume that was mounted a moment
  earlier. A disappearance cannot be matched by its mount point, and the description-changed
  callback on `kDADiskDescriptionVolumePathKey` has nothing to report for an already-unmounted
  claimed device — which is what leaves `DADiskDisappeared` as the only route.

⚠️ **The boundary: this was measured on a ram disk detaching cleanly, which is not the same event
as a USB drive being pulled.** It is strong evidence about the API's behaviour and it is not the
hardware claim. Step 12's gate is what unplugs a drive on purpose.

**That boundary was the right warning and it was still not wide enough.** There is a third event,
and it is the one that bit — measured on hardware 2026-09-08, Step 12 chunk 7f:

### ⚠️ Claiming a whole disk makes its own slices disappear — measured 2026-09-08

**Opening `/dev/rdiskN` with `O_EXLOCK` tears the partition scheme down.** The slices' `IOMedia`
nodes terminate and DiskArbitration reports each one through `DADiskDisappeared`, **while the
claim is held and the drive is physically present and enumerated the whole time.**

On the 1 TB scratch T5 (serial `12345686DAA9`, GPT: EFI + a 1 TB exFAT volume), from the app's own
log:

```
14:28:23.876  APP     unmount succeeded on disk7s2: unmounted
14:28:23.885  HELPER  acquired disk7: claim held, /dev/rdisk7 open exclusively (fd 4)
14:28:23.886  HELPER  acquire GRANTED
14:28:23.896  APP     a disk disappeared: disk7s1 (slice)      <- 10 ms after the claim
14:28:23.896  APP     a disk disappeared: disk7s2 (slice)
```

**The whole disk did not fire** — zero `disk7` disappearances in the entire capture. So the shape
of a self-inflicted teardown is *slices only*, and the shape of a real unplug is *whole disk plus
slices*. `DAMediaWhole` is the discriminator, and it is the only one available inside the callback.

**The consequence for anything built on route (b):** a rule of the form "a slice of my drive
vanished, therefore my drive vanished" is false, and it is false *because of the run's own
preconditions* rather than in spite of them. `DeviceUnderTest` shipped exactly that rule from
2026-09-05 to 2026-09-08 with a comment arguing the opposite, and it ended a healthy run ten
milliseconds after the claim was granted, on every drive with a partition table. The run it
discarded went on to complete 128/128 chunks with no failed block ranges.

✅ **RESOLVED 2026-09-09 — the whole-disk event DOES fire while the claim is held.** This section
stood for a day saying it was assumed; chunk 3's walk pulled the cable mid-run and logged
`a disk disappeared: disk7 (whole disk)` at 13:15:15.920 with the claim active. Route (b) is sound.
See the next section for the timeline and for the third finding, which was not anticipated: at the
unplug **only** the whole disk fires, because the slices went at the claim and cannot go twice — so
the *"whole disk plus slices"* shape described above is what a real unplug looks like **only when
nothing has claimed the drive**. Under a claim it is whole-disk-alone. Both shapes are
distinguished from a self-inflicted teardown by the same discriminator, `DAMediaWhole`.

### ⚠️ Under a claim, an unplug fires the WHOLE DISK only — measured 2026-09-09

The open question route (b) rested on, answered by chunk 3's walk. Timeline, one run, `disk7`
(Portable SSD T5, `12345686DAA9`):

```
13:14:58.519  unmount succeeded on disk7s2: unmounted
13:14:58.535  a disk disappeared: disk7s1 (slice)          ← the claim tearing the
13:14:58.535  a disk disappeared: disk7s2 (slice)             partition scheme down
13:14:58.536  acquired disk7: claim held, /dev/rdisk7 open exclusively (fd 4)
13:14:58.540  run control: starting → running on claimEstablished
   … 17 s of I/O, cable pulled …
13:15:15.919  retention cycle END: … the device was lost while verifying the write-back
13:15:15.919  E  read … failed after 0 bytes: errno 6 (Device not configured)   ← route (a)
13:15:15.920  a disk disappeared: disk7 (whole disk)                            ← route (b)
13:15:15.920  E  the drive under test left the machine while running
```

**Six of six**, read back from the persisted unified log on 2026-09-10: every one of chunk 3's
pulls that day logged `disk7s1 (slice)` and `disk7s2 (slice)` in the same millisecond as
`acquired disk7`, and exactly **one** `disk7 (whole disk)` at the pull.

**Eight of eight, and on a second drive — 2026-09-11**, checklist chunk 4, both runs **paused** at
the pull: the 1 TB scratch T5 again, and the 125.8 MB thumb (`2211190533300386001515`, two slices,
over USB High Speed where the T5 runs at 10 Gb/s). Each logged both of its slices at the claim and exactly
**one** whole-disk event at the pull. ⚠️ **"In the same millisecond as `acquired`" is too tight**:
the T5's slice lines came **2 ms after** `acquired disk7`, the thumb's **3 ms before** `acquired
disk4` — the helper logs `acquired` once the claim is already held, and two processes' lines are not
ordered at this resolution. What held both times is **4–5 ms before `claimEstablished`**, which is
the ordering the next paragraph's guard depends on. Read *"at the claim"* as within a few
milliseconds of it.

Three findings, and the third was not anticipated:

1. **The whole-disk `DADiskDisappeared` DOES fire while an exclusive claim is held.** Route (b) is
   sound. This had been assumed since 2026-09-05 and measured only with nothing claimed.
2. **Both routes fire, ~1 ms apart** — route (a)'s `ENXIO` at `.919`, route (b)'s whole-disk event
   at `.920`. On a *running* run they race; on a **paused** one only route (b) can see it, which is
   why route (b) had to be right.
3. **At the unplug there are NO slice events — only the whole disk.** The slices went at the claim,
   17 seconds earlier, and cannot disappear twice. So while a claim is held route (b) receives
   **exactly one** event per unplug. The idempotency in `deviceDisappeared` is therefore not
   exercised by this path at all; it is kept because it is cheap and because `paused`-with-volumes-
   remounted is not this path. **Do not read "one event" as "idempotency is unnecessary"** — read it
   as "the walk cannot test it", which is what puts multi-slice idempotency in chunk 4.9 on the
   125.8 MB thumb instead.

   ⚠️ **Corrected 2026-09-10: chunk 4.9 cannot test it either.** A paused run keeps its claim
   (`RunController.pause()` only sends `setRunControl(.pause)`), and the thumb is claimed like any
   other drive — so its slices go at the claim and its unplug fires one whole-disk event, the same
   as here. **Multi-slice idempotency has no hardware path in this design.** It is pinned on the
   bench by `threeCallbacksFromOneUnplugArmOneDeadline` and by nothing else. The checklist's item
   4.9 now carries this as a prediction declared before the walk, and leaves whether to walk it to
   the user. *(✅ Walked 2026-09-11 by user decision, and the prediction held in both halves: the
   thumb's slices went at the claim and its paused unplug fired one `disk4 (whole disk)` — one loss
   line, one `run ended`, one report. 4.9 passed without exercising idempotency, as declared.)*

**The consequence for instrumentation, which cost a checklist item:** any log line that fires only
on *a slice of the drive under test disappearing* is unreachable on a normal run. `deviceUnderTest`
is set when the claim returns `.ready` (`RunController.swift:530`), five milliseconds *after* the
slices have gone, so `deviceDisappeared`'s `guard let deviceUnderTest` swallows them; and at unplug
there are no slices left. To prove the DA subscription is alive, read the **`discovery`** category's
`a disk disappeared: disk7sN (slice)` lines at claim time — those come from the app's own
subscription and do fire.

### Device loss (Step 12's territory — the engine's half built 2026-09-05)

- **`ENXIO` on offset 0 of a working descriptor means the descriptor is dead.** `EIO` on a block
  means a bad block. Detect loss from `ENXIO` and from the DiskArbitration/IOKit removal callback.
- **`ENXIO` ALONE is the errno discriminator** (user decision 2026-09-05, built in Step 12 chunk 1).
  `EIO` is emphatically **not** included, and the direction of that mistake is why it is stated
  rather than left implied: `EIO` is the ordinary answer from a single unreadable block, so treating
  it as loss would end a run at the first genuine bad block — turning the one thing this tool exists
  to find into a reason to stop looking, and breaking FR-FAIL-3 outright. Every other `errno` keeps
  its meaning, `EBADF` included: a closed or invalid descriptor is *our* mistake, not the device's
  absence. **BUILD-PLAN said `ENXIO`/`EIO` in three places until 2026-09-05** while its own incident
  note said the opposite; corrected there, pinned by `DeviceLossErrnoTests`.
- **Do not infer device loss from a failure count.** A genuinely dead drive also fails every chunk,
  so the heuristic is wrong exactly when being wrong is most expensive.
- **`ENXIO` from real hardware has ONE observation behind it**, the 2026-08-06 incident. That is
  evidence, not a gate. Whether a de-enumerating drive *always* answers `ENXIO` — and whether it
  first answers with a short transfer and `errno 0`, which still classifies as a bad block — is
  **open, and only a hardware gate can close it**. Step 12's gate unplugs a drive on purpose.
  *(2026-09-10: **seven** observations now, all on the same 1 TB T5 — chunk 3's six pulls on
  2026-09-09 each failed their in-flight I/O after **0 bytes** with `ENXIO`, five reads and one
  write, read back from the persisted log. No short transfer in either direction. That answers both
  questions for this drive and says nothing yet about a different one.)*
- **A run that is PAUSED cannot see the device leave through the errno route**, because it has
  returned from its call and issues no syscalls: the helper sits holding the claim and the fd with
  nothing to classify. The removal callback is the only route that can see it, which makes that
  route load-bearing rather than a second opinion.
- **A drive that dropped off the bus used to be reported as a drive with ~2 million bad blocks** —
  a false accusation about a drive, in a file that outlives the session. Observed for real during a
  hardware gate, not simulated. **The engine stopped doing this on 2026-09-05** (chunk 1): a lost
  device now ends the run and records nothing against the drive, while failures found *before* the
  loss are kept. Chunk 2 built the detection route that covers a paused run, and **chunk 3 put the
  ending on the wire as protocol v15**, so the app can tell device loss from a refusal. **Chunk 4
  (2026-09-06) made the app act on route (b)**: `DeviceLossWindDown` ends the run once, from either
  route, and a paused run — the case route (a) cannot see at all — ends immediately rather than
  sitting on a claim for a drive that has gone.
  ⚠️ **The defect is not fully closed:** the report still answers
  `incomplete` rather than naming the removal, and nothing has told the *person* yet — chunks 5
  and 6. Nothing is distributed before Step
  16 (section 2), so the person misled is the one who can recognise it, which lowers the stakes and
  changes nothing about the remaining gap. *(✅ 2026-09-10: **closed in code since 2026-09-07** —
  chunk 5 made the report name the removal on 2026-09-06, and chunk 6 raised the alert on
  2026-09-07. A person has since seen both: the alert by eye through a debug hook and the report's
  face on 2026-09-08 (checklist chunks 1 and 2), and a real report after a real unplug of a
  *running* run on 2026-09-09 (chunk 3). **The paused run was walked with a cable on 2026-09-11**
  (chunk 4), on the 1 TB scratch T5 and the 125.8 MB thumb: route (b) alone ended it **1 ms** after
  the removal callback, and the report said *paused* and that nothing was left half-written.)*
- **`interruptedAtBlock` carries two different things from v15, and the outcome code is the only
  thing that says which.** Under `pausedByUser` it is a **resume point** — the run settled at a
  chunk boundary with nothing in flight. Under `deviceLost` it is where the run died *inside* a
  chunk, and FR-FAIL-7 forbids continuing across it. Sharing the slot is right, because it is the
  same quantity; exposing it as one app-side optional would not be. `RunCycleOutcome` splits it
  into `resumeBlock` and `deviceLostAtBlock`, **never both non-nil**. Block 0 is a legitimate value
  for either, which is why no sentinel could do this job.

*Full account: `progress/step-10.md`, increment 6; BUILD-PLAN Step 12's inherited notes.*

### Idle-sleep assertions — measured 2026-09-12 (Step 13 chunk 1)

Measured by `scripts/sleep-assertion-check.sh` and `tools/sleep-assertion-probe`, on macOS 26.0
(Darwin 25.6.0), before a line of Step 13 was written. Nothing here is about this app, so **it does
not lapse when a commit moves — it lapses on a macOS update.** Re-run it then, and before walking
Step 13's gate on a machine that has been updated since.

- **`ProcessInfo.beginActivity(options: [.idleSystemSleepDisabled], reason:)` publishes exactly one
  `PreventUserIdleSystemSleep`**, attributed to the process's pid, and **the `reason:` string is
  what `pmset` shows as `named:`**, verbatim. BUILD-PLAN Step 13's gate greps for that type string
  and it is correct as written — which was not a given: the API is documented in terms of behaviour
  and never in terms of the assertion it creates, and another process on this machine publishes
  `NoIdleSleepAssertion` for the same intent by the `IOPMAssertionCreateWithName` route BUILD-PLAN
  names as the equivalent.
- **It touches nothing else.** The pid publishes no `PreventUserIdleDisplaySleep` and no
  `PreventSystemSleep`, which is BUILD-PLAN step 3's requirement — idle *system* sleep only, and
  deliberate sleep still works — confirmed by reading what our own pid owns rather than a
  system-wide count another app can move.
- **One activity per token, and they are visible individually.** Two `beginActivity` calls from one
  process show as **two** entries with two assertion ids; ending one leaves the other held. So a
  leaked assertion is *visible* in `pmset`, and Step 13's third gate item — "exactly one at a time"
  — can be read there rather than only in the suite.
- **Acquire and release are visible on the first read**: 0.086–0.089 s in every phase, against
  0.091 s for one `pmset -g assertions` invocation. ⚠️ **Those are upper bounds set by the
  instrument, not latencies the mechanism produced** — every change was already true before the
  first read completed. Do not quote 88 ms as a latency.

⚠️ **The summary count cannot answer any of this, and a gate item read off it passes with the app
not running.** `pmset -g assertions`'s system-wide block reads

```
   PreventUserIdleSystemSleep     1
```

**before anything of ours exists**, because `powerd` holds one the whole time the display is on
(*"Powerd - Prevent sleep while display is on"*). Measured: baseline 1, held 1, held twice 1,
released 1 — **the line never moves.** It is a system-wide flag, not a count of holders. So every
reading of this gate is taken from the **`Listed by owning process:`** section, matched on our pid,
and `powerd`'s own assertion is also why a person checking that the Mac *actually stays awake* has
to let the **display** sleep first: until it does, the machine will not idle-sleep whether or not
this app holds anything.

*This is the same shape as the error channel firing 17 false positives per test run: the instrument
was the defect. Here it was found before the gate was walked rather than after.*

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
- **36 view cases, and FOUR of them render a state this machine cannot produce** — `empty` (no
  drives), `devices-unmounted`, and `devices-unusable` (a drive with a `geometryProblem`, which no
  drive here has). Each exists because *a state nobody can observe is a state nobody has checked*;
  the third was added in Step 14 for a row that had never been rendered in either appearance.
  `devices-unmounted` has since taken a **second** job it was not built for: since 2026-08-23 its
  fixture drive is the only one in the harness reporting `usbLinkSpeedCode == -1`, so it is the one
  render where the link-speed row's unknown sentinel appears at all.
  **`helper-gate-not-found` is the fourth**, added by increment 9: it needs an installed app bundle
  edited, which is a broken install rather than a test. The other four of that family sort
  differently and the distinction is worth keeping straight — `helper-gate-not-registered`,
  `-requires-approval` and `-version-mismatch` **are** producible by deliberately breaking the
  helper, and chunk 13 of the human checklist walks all three; `helper-gate-unreachable` needs a
  daemon that is enabled and silent, which nothing here stages reliably, so it is rendered and not
  walked.
  They are one render per state rather than one for the family because the states differ in message
  length, in **button count** (`not-found` is the only one-button footer) and in which remedy is
  emphasised — and `helper-gate-unreachable` is the only surface in this app rendering a string
  whose length the app does not choose, being a transport error's own words.
  **The probe is authoritative and `render-ui.sh`'s header list has drifted from it three times, and
  the header's own COUNT of those drifts was itself stale until 2026-08-27** — it said "twice" while
  CONSTRAINTS recorded three, which is the same failure one level up. Corrected in increment 9,
  which added five cases by re-deriving the list rather than hand-editing it. The drifts:
  caught 2026-08-11; again by Step 11 increment 6, which found the script listing 24 cases against
  the probe's 28, naming two (`diagnostics-held`, `diagnostics-quitting`) the probe would refuse
  with exit 2 and omitting all six `content-*` run states; and again on 2026-08-23, when the script
  still said 34 against the probe's 31 after the Restart removal deleted three. Re-derive the list,
  never hand-edit it; the one-line `grep` is in the script's header. **Three drifts is the number
  that says this will drift again.**
- **A render cannot see the live metrics panel or sheet modality — and the report body turns out to
  be a smaller blind spot than this entry claimed.** The panel polls a real helper, so offscreen it
  always shows the unavailable state whatever the run state is; and a window-modal sheet answers ⌘Q
  before `QuitPolicy` is consulted, so the policy's truth table is not what decides.

  **The report body is reachable after all, and it is only the height that hid it** (measured
  2026-09-02). This entry said a render "stops at `## Measurements`" because the body sits in a
  scroll region. It stops there at a normal window height; give it
  `render-ui.sh out.png 720 1500 report` and the region has nothing left to hide, so the **whole**
  body renders — the claim sentences, both `ThroughputFraming` paragraphs and the closing section.
  Increment 10's rewrite of that framing was checked that way, which is the first time the wording
  has been read in the artefact rather than in the source — the distinction a `/verify` pass already
  proved matters, when the exported report contradicted itself about its own denominator and the
  source read fine either side. **Render the report tall before concluding its prose is unseeable.** **An acceptance criterion derived from model
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
- **THE HARNESS PINS APPEARANCE BUT NOT ACCENT, AND THAT NOW HAS A SECOND REPRODUCTION AND A
  METHOD.** Recorded from one incident until 2026-08-27 — a progress-bar fill measuring `#3e99fd`
  and then `#bdbdbd` on one day with nothing in the diff touching it. Increment 9 reproduced it
  independently: `helper-gate-not-registered` and `helper-gate-version-mismatch` rendered their
  `.borderedProminent` button at **`#0079FF`** in one batch and **grey** in another, same commit,
  same `light` appearance, minutes apart — and *within* a batch three consecutive renders of one
  view were **byte-identical**. So the leak varies between invocations, not between views or runs,
  which is what makes it look like a per-view defect when it is not.
  **The method is worth keeping**: sample the most saturated pixel in the region of interest rather
  than eyeballing the PNG. Twenty lines of `CGContext`, and it turns "that button looks grey" into a
  number. Render-to-render **colour** comparisons remain untrustworthy; layout, text and element
  presence are not affected.
- **A `contains` assertion cannot see punctuation, and a render can.** Increment 9's gate messages
  passed a full table walk — every message a sentence, ending in a full stop, naming its own remedy —
  and the first renders showed *"Sandbox restriction.. Choose Retry"* and *"Choose Open Login
  Items…, enable…"*. Both came from composing prose with a **fragment that punctuates itself**: a
  transport error's `localizedDescription`, and a button label carrying a platform ellipsis. Every
  assertion about those strings was a `contains`, and `contains` is blind to what sits either side.
  Both are now pinned by tests written *after* the render found them.
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
- **`USBDriveTesterApp.swift` IS THE ONE FILE NO HARNESS COMPILES, AND THAT MAKES IT THE RIGHT HOME
  FOR AN APP-WIDE TRIGGER** (Step 11 increment 9). `render-ui.sh`, `window-fit-check.sh` and
  `build-tools.sh` each exclude it **by name** — its `@main` clashes with a tool's top-level code —
  and `tools/ui-probe` renders a bare `ContentView()`, so a modifier applied at that view's *call
  site* is not carried into any render.
  The launch-time helper gate uses this deliberately: the **trigger** is there, the `.sheet`
  **modifier** is on `ContentView`. The presentation therefore type-checks in all three harnesses
  while every one of the 36 renders is provably free of it, because nothing in a render writes
  `helperAvailability`. Had the trigger gone in `ContentView.onAppear`, every `content-*` render
  would read this machine's live `SMAppService.status` and issue a real XPC call — the ambient-state
  leak recorded twice in section 1. The alternative was a fourth injected dependency on
  `AppModel.init`.
  **What it costs is stated rather than discovered: logic in that file has no automated cover at
  all.** `build.sh` and `test.sh` compile it, so a compile error is caught; a wiring defect is not.
  Two of increment 9's mutations survive there by construction and were declared in advance. Put a
  *trigger* there; never a *decision*.
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
- **When a comment argues that a precondition makes something safe, check whether the precondition
  is what CAUSES the thing.** `DeviceUnderTest` accepted a slice disappearance as proof the drive
  had gone, reasoning that *"the device under test is unmounted and exclusively claimed, so nothing
  can be repartitioning it"*. Taking the exclusive whole-disk open is precisely what makes the
  slices vanish. The argument was not weak — it was inverted, and it read as careful because it
  named a real precondition and reasoned from it. **Three days, 1,297 green tests, four passing
  hardware gates and a mutation round did not touch it.** What found it was a person pressing Start
  once, on a drive with a partition table. See §1, 2026-09-08.
- **Ask what a bench cannot synthesise.** Every test of route (b) built its own `DisappearedDisk`,
  so the suite could only ever check the rule it had been told; it could not observe which events
  a real claim produces. And the four hardware gates drive the *helper*, while route (b) lives in
  the *app* — so the gate that looked most like coverage could not reach the code at all. **When a
  seam is only ever fed synthetic input, the test suite's agreement with it is not evidence.**
- **Measure, don't estimate.** An estimate stood three steps and was wrong by 11×.
- **A pre-flight before a design is committed to is almost free** — and has killed two designs before
  they were built.
- **Prose is not a precondition.** A control that states its requirement in text and then looks live
  is reported as broken.
- **An empty result is not a finding** — and neither is a number that does not move. A test-count
  that fails to rise is how files written to the wrong directory get caught.
  **The sharpest form of this is an empty result you silenced yourself.** On 2026-09-05, checking
  whether route (b)'s log line had fired, `log show ... 2>/dev/null` returned nothing and was read
  as "the code did not log". It had logged. `log` is a **zsh builtin**, the real command is
  `/usr/bin/log`, and the shell had been saying `too many arguments` into the `/dev/null` the
  command itself sent it to. Redirecting stderr on a diagnostic command converts "this did not run"
  into "this found nothing", which are opposite results wearing the same face.
  **The same day, in the other direction: `build.sh | grep error:` came back empty and was read as
  "it builds".** It did not — exit code 65, `** BUILD FAILED **`, two errors the grep's own pipeline
  had scrolled past. A pipeline reports the *last* command's status, so grepping a build log throws
  the build's exit code away. **Check the exit code, or grep for the success line; never infer a
  pass from the absence of a word.**
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
- **A definition that uses its own term hides whatever the term actually means.** `Covering` was
  documented as *"how fast the run is covering the drive"* and had been read that way by everyone,
  the author of that sentence included. It survived a review in this project on 2026-08-25 in which
  the arithmetic was checked against the source, the identity `Covering ≡ Write` was derived
  correctly, and the conclusion "not a defect" was reached — **all of it true, and all of it beside
  the point**, because the word "covered" carried the ambiguity through the argument untouched. The
  user then asked for a definition that did not reuse the term. One sentence later the discrepancy
  was plain: `rangeBytesCovered` counts **attempted** work, and says so in its own comment, while
  the label promises successful work. The gap only shows on a failing drive — the one occasion
  anyone reads the number closely.
  **When a name is in question, define it in words that do not contain it.** The restatement is
  cheap, it takes one sentence, and it is the only step in that review that found anything.

  **The row was deleted in Step 11 increment 10, and it was on three surfaces rather than the one
  the plan named** — the live panel, the report sheet and the exported Markdown, with the prose
  explaining it written twice. All three went together: deleting two of three would have left the
  report naming a figure the panel refuses to, and the report is the artefact a drive's history is
  kept in. **A mislabel is as wide as the surfaces that render it, and a plan naming one of them is
  not evidence there is only one — grep before scoping.** The quantity is untouched and still on the
  wire, since `rangeBytesCovered` is the only correct ETA denominator; what no longer exists is a
  label promising successful work over a number counting attempted work.
- **"Report it before a run" and "report it at selection" are not the same requirement, and the
  weaker one can masquerade as the stronger.** NFR-INST-4's Full Disk Access check sat in the device
  pane, refreshed on selection change and on mount change only — so granting the permission with the
  app open left the pane asserting the opposite indefinitely. It looked like the earliest possible
  report and was in fact a snapshot with no expiry. A check placed where the condition *matters*
  is fresh by construction; a check placed early is only fresh if something invalidates it, and
  nothing was.

  **Fixed in Step 11 increment 10**: the check is a step of `DevicePreparation`, before the unmount,
  and the pane it lived in is deleted. Two things the move settled that are worth carrying. **The
  ordering is part of the requirement, not an implementation detail** — after the unmount, a denied
  grant takes a multi-volume drive down and remounts it for a run that never started. And **only a
  `denied` probe stops a run**: `FullDiskAccessState` is three-state because the probe is conclusive
  in two directions only, so `.unknown` and an unreachable helper both carry on and let the acquire's
  helper-side precondition decide. Refusing to start on "could not ask" would make a dead helper
  indistinguishable from a missing permission. The full account is NFR-INST-4's 2026-09-02
  amendment.
- **A protocol bump that keeps its arity is the dangerous kind, and the handshake is the only thing
  that can see it.** Every version through v13 changed a reply's shape, so a mismatched app and
  daemon failed to decode and something said so loudly. v14 moved three rates onto a different
  denominator with both replies at 22 and 13 arguments unchanged: a v13 app against a v14 daemon
  decodes perfectly and displays figures low by the ratio of running time to phase time, and nothing
  downstream is wrong enough to notice. **When the constant moved, exactly one test in 1092 failed.**
  Reinstall and kickstart before any hardware gate or checklist walk is a correctness requirement
  after a bump like this, not hygiene — and a gate whose prerequisites are stale will print numbers
  that look almost right.
- **A number in prose that nothing asserts will drift, and "increment it" is the wrong repair.**
  `RunMetrics.swift`'s rate table read "Five rates" over a six-row table for weeks, and the increment
  that added a seventh row made it "Six". Both counts survived reviews in which the arithmetic below
  them was checked line by line. The count came out rather than being corrected; where a count is
  genuinely load-bearing, derive it from the thing it counts, as
  `theDefinitionNamesEveryRateTheReportTabulatesAndNoOther` parses the rendered table.
- **Search-and-replace across a codebase rewrites the prose that records what a name used to be, and
  prose does not fail to compile.** Renaming the app-side `sustained*` rate properties to match what
  v14 made them carry also silently rewrote a protocol-history sentence describing what those names
  *became* in v12 — into a sentence saying two things had become themselves. The compiler is no help
  here and neither is the test suite. After a bulk rename, grep the renamed identifiers for words
  like "became", "until", "previously" and version numbers, and read what comes back.
- **A prose claim can be the safety mechanism of a change, and then it needs its own assertion.**
  FR-METR-1's 2026-09-02 amendment is defensible only because the report tells the reader these
  figures will not match Activity Monitor. That sentence could be deleted outright with the whole
  suite green: the tests around it checked *which rates* it named and that the document contained the
  constant, and the second kind moves with the constant when it is edited. "The document contains
  what the code says" is not cover for what the code says.
- **A gate assertion can look like a check while asserting nothing, and the way to find out is to
  run it against the mutation it exists to catch.** `metrics-check.sh`'s replacement for the covering
  identity first compared covering against the read rate, where a running-time denominator gives
  0.33× and a phase-time one gives 0.35× — no band tolerant of a real drive could separate them.
  Re-anchored against a quantity counting the *same bytes*, so only the denominator differs and the
  defect lands on exactly 1.0. **Exercise a new assertion against representative numbers before
  trusting it**, including the values it is supposed to reject.
- **A fixture must agree with its own headline.** A render whose report said "every comparison
  matched" above a rate that can only fall when comparisons did not would have been read as the
  product contradicting itself, and it was caught by looking at the rendered sheet rather than the
  source — the same way the `Covering` mislabel was. Where one fixture serves several variants,
  parameterise the figure that has to move with them rather than picking a value that suits one.
- **A new human-checklist item must be checked against the items already in the file, not only
  against the source.** Chunk 15's item 4 asked a walker to confirm three em-dashed rate rows on the
  idle metrics panel. There are no rows there — `RunMetricsView` shows a placeholder — and the
  rows-behind-the-placeholder state it described is **a defect that had been found and fixed**, the
  placeholder being *"replaced rather than overlaid"* for exactly that reason. **The item would have
  passed on the broken build and invited a false failure report on the correct one.** Check 11.4,
  walked and passed a fortnight earlier, described the same panel correctly 600 lines away in the
  same document. `grep` the checklist for the screen a new item names before writing it; a checklist
  that instructs someone to verify something false is worse than having no item at all.
- **A deletion is not finished when the item is gone — every cross-reference to a number above it is
  now wrong, and prose references do not fail to compile.** Deleting chunk 15's original item 1 left
  the chunk's own preamble pointing at "item 3" for a check that had become item 2, and it went
  unnoticed until the walk. De-numbering item 4 during that same walk then left two entries numbered
  `4.`. Three numbering defects in one chunk of five items. **After removing a numbered item,
  re-read the whole section for references to positions, not just for references to the item.**
- **Verify the installed build by symbol, not by timestamp, before any checklist walk.** Chunk 14's
  walk was blocked by a stale `/Applications` build and had to be restarted; chunk 15's pre-flight
  instead checked the installed binary for the identifiers the change introduced and for the ones it
  removed — `deviceReadBytesPerSecond` present 30 times, `sustainedReadBytesPerSecond` zero times,
  the new disclaimer string present and the superseded one absent. A timestamp suggests; a symbol
  settles. It costs seconds and it protects a walk that costs a person an hour.
- **An external instrument is worth more than the item that summons it.** Chunk 15 asked only that
  Activity Monitor *disagree* with the app by roughly the claimed factors. Reading the two figures
  side by side also confirmed the cycle's shape from outside the app (its read ÷ its write = 1.966
  against the 2:1 the cycle implies), recovered `coverageBytesPerSecond` — the row increment 10
  deleted — from a tool sharing no code with the app, landing it inside `metrics-check.sh`'s own
  band, and put a number on host overhead (**3.28% of running time**) where the amendment had only
  had an argument. **When a check reaches outside the system, record everything it saw, not only the
  answer to the question asked.**
- **Point-valued expectations in a checklist generate defect reports against healthy hardware.**
  Chunk 15's item 1 carried `ui-probe`'s fixture figures — 376 / 419 / 130 MB/s — and the walk read
  344 / 419 / 122, which was reported as Read being "about 10% too high". Nothing was wrong: one
  rate drifted between sessions and the other two followed it correctly through the identity.
  **Give a human a band and a relationship to check, never a number to match**; the relationship is
  the test, and on this project the absolute figures are explicitly not.
- **A long gate that dies at its first assertion has spent its whole cost and produced nothing —
  exercise the reporting path cheaply before spending the run.** `retention-cycle-check.sh`'s full
  pass did all 88 minutes of work on 2026-09-03 and then exited 1 at line 366, because the file
  `tee` had been writing the client's output to was gone by the time `sed` read it. The evidence
  survived in the artefacts and every assertion could be checked by hand from them — and that was
  **not** recorded as the gate passing, for the same reason a mutation that does not compile is not
  a result. `--quick` at the same start block runs the identical acquire → digest → cycle → digest →
  release → assert path in about a minute; it is not evidence, but it establishes that the gate can
  report before the long run is committed to.
- **A `df` reading is not evidence about what is on the media, and this project has now been fooled
  by the same one twice.** `retention-cycle-check.sh` warns when the scratch volume is under 25%
  used, because a cycle over unwritten space reads zeros, writes zeros and verifies zeros while
  reporting a clean pass. Both times the volume read 1% used and both times the residual
  `/dev/urandom` pattern was intact, because **an unlink clears the allocation table, not the
  media**. The CONTENT check — three chunks from inside the tested range, required to be mutually
  distinct — is the authority, and it is the only reason either run proved anything.
- **ONE FILE CAN HOLD TWO STATUS BLOCKS, AND YOU WILL EDIT THE ONE YOU ARE LOOKING AT.**
  `BUILD-PLAN.md` has a status block at the top and another 400 lines down in "Sequence overview".
  Step 12's chunks 1 and 2 updated the second and left the first saying *"Step 12 is next and is
  UNSTARTED. The protocol is v14"* — for two commits, while the file's own closing paragraph warned
  that a status block is *"the first thing a cold session believes and the last thing anyone thinks
  to check"*. The `grep -rn` rule in `CLAUDE.md` is written per **repository**, and the habit it
  builds is per **file**: open the file, edit the block, move on. **Grep for the claim, not for the
  filename** — `grep -n "protocol is v" BUILD-PLAN.md` finds both in one line of effort.
- **THE NARROW BUILD IS THE ONE THAT CAN FAIL, WHICH IS THE WHOLE REASON TO KEEP IT.**
  `scripts/device-probe.sh` runs the app's real discovery headlessly by compiling
  `Discovery/*.swift` plus one `Shared` file and **nothing else**. On 2026-09-05 a new type was put
  in `Discovery` that read `ReportedDevice` from `Report` — the full app target compiled it without
  complaint, the whole suite passed, and the probe failed instantly with *"cannot find type
  'ReportedDevice' in scope"*. The app target cannot produce that error, because it contains every
  file; only a build with a genuine boundary in it can. **A layering rule nothing compiles against
  is a comment.** The fix was to put the *event* type next to the watcher that produces it and the
  *question asked of a run* in `RunControl` — and the layering fell out of the instrument rather
  than out of an opinion, which is the stronger way round.
- **A DECISION STATED IN FOUR PLACES DRIFTS IN THE THREE THAT ARE POINTERS, AND THE MAJORITY IS NOT
  THE AUTHORITY.** BUILD-PLAN's Step 12 said to detect device loss from `ENXIO`/`EIO` in its
  *detailed step*, and two further lines deferred to it — *"detect `ENXIO`/`EIO` per detailed step
  1"*, *"device loss is detected, per detailed step 1, from `ENXIO`/`EIO`"*. The **incident note in
  the same section**, written the day a drive actually de-enumerated, said the opposite and said it
  once: `EIO` on a block is a bad block; `ENXIO` on offset 0 means the descriptor is dead. Three
  statements of the wrong thing, one of the right, and the three were **not independent** — they
  were one mistake quoted twice, which is exactly how a wrong reading acquires the texture of a
  settled one. Building it as written would have ended a run at the first genuine bad block: the
  one thing the tool exists to find, turned into a reason to stop looking.
  **Check a decision against the observation that motivated it, not against the count of places
  that repeat it** — and when a section contains both a rule and the incident the rule came from,
  the incident is the authority. Corrected 2026-09-05, in the commit that built the discriminator.

- **A BENCH THAT KEEPS ONLY THE LATEST OF A THING CANNOT SEE ONE BEING BUILT TOO OFTEN.** Chunk 4's
  test bench stored `windDown` — *the* wind-down. A mutation removing the "build one per run" guard
  therefore built three (one unplug delivers a whole-disk callback and one per slice, measured
  2026-09-05), armed three deadlines, left two of them running untracked, **and passed all 1219
  tests**. Every assertion the bench could express was about the last one, which was fine. The fix
  was the bench, not the test: keep **every** instance, and assert over the collection. The general
  form — *a test double that collapses a sequence into its most recent value silently converts "how
  many" into "what was the last", and how-many is exactly what an idempotence bug is about.* And
  the second-order lesson: this survivor was invisible in the *paused* walk, because there the
  first callback ends the run and the state guard swallows the rest. **Drive an idempotence test
  from the state where nothing else is filtering.** *(⚠️ 2026-09-11, Step 12 chunk 7g: "one unplug
  delivers a whole-disk callback and one per slice" is an **unclaimed** drive — under a run's claim
  it is the whole disk alone, §1 *Under a claim*. And the lesson recurred without anyone noticing:
  7f added a filter — only a whole-disk call gets past `deviceDisappeared`'s guard (3) — upstream of
  the idempotence this test pins, so its two slice calls are now filtered before any wind-down is
  built. **A new filter upstream of an idempotence test can silently empty it; re-check the test's
  inputs, not just its result, when one is added.** Whether the mutation survives again is
  predicted, not yet measured — `PROGRESS.md`'s Owed row.)* *(✅ 2026-09-11, chunk 7h: **measured —
  it survived all 1301 tests**, so the sub-lesson above has its instance and is no longer a
  worry about a mechanism but a record of one. Killed by
  `aSecondWholeDiskCallbackBuildsNoSecondWindDown`, which delivers the whole-disk callback **twice**
  to a running run — the state where nothing upstream is filtering, exactly as the bolded lesson
  four sentences up says to. **Note what the two lessons cost together: the bench fix was right and
  was kept, and the test still stopped covering the thing — because the defect moved from what the
  bench could see to what the test was allowed to deliver.** The cheap check, whenever a guard is
  added: list the tests that reach the guarded code and ask how many calls each still gets through,
  not whether they are green.)*
- **A DOC COMMENT THAT OVERCLAIMS IS A DEFECT, AND THE MUTATION ROUND IS WHAT FINDS IT.** Deleting
  `windDown?.standDown()` survived the suite. The investigation found the comment was wrong, not the
  code: it said the call prevented a double-ending, but the sequencer's `.ended` phase already
  refuses one and `RunController` drops its references regardless. What the call actually prevents
  is an **error-level log line three seconds later saying the helper never answered, on a run where
  it answered fine** — false evidence on the one path where somebody is reading the log to find out
  what happened to their drive. Two corrections came out of one mutation: the comments in both files
  were rewritten to claim only what is true, and two tests were added to pin the property that is.
  **When a mutation survives, suspect the comment before you suspect the test** — an unkillable line
  is often a line doing a smaller and more specific job than its documentation admits.
- **TWO MUTATION RUNNERS ON ONE WORKING TREE PRODUCE PLAUSIBLE NONSENSE, AND NOTHING SAYS SO.**
  Chunk 5's round was launched as a background job; a context break later, a foreground runner was
  started from the same script on the belief that the job had died. It had not. **For four
  mutations, two runners mutated, built, tested and restored the same seven files against each
  other.** The output never looked broken — it looked like results: m5 (reverting the device-loss
  report outcome) reported *three* failing assertions in two tests, which is a small, specific,
  believable number. Re-run alone it fails **29**, and the three it had reported were another
  mutation's. The tell was a *missing* one — the background job's own m5 line printed
  `killed_by=` with **no test total at all**, which the zero-total rule already classifies as
  INCONCLUSIVE. Two rules follow, and only the second is new:
  **a mutation round owns the working tree, so run exactly one at a time and confirm the previous
  runner is dead before starting another** — `ps` for the build, not the absence of new output; and
  **a result is only a result if the run that produced it was the only writer**, which is a
  property of the environment that no assertion inside the suite can see. Everything from the first
  overlapping mutation onward was discarded and re-run.
- **A TEST CAN BE NAMED FOR A LINE IT CANNOT REACH, AND THEN THE GREEN TICK IS ABOUT NOTHING.**
  Chunk 5's `theEndingDoesNotSurviveIntoTheNextRun` was written to pin `deviceLossEnding = nil` in
  `driveIsBack()`. Deleting that line survived all 1261 tests. The test drove the second run to a
  **clean** finish — and the consumer reads the field only when a run ended `deviceLost`, so on any
  other ending a stale value is never consulted. The name asserted the coverage; the body could not
  deliver it, and for as long as it was green nobody had reason to look. This is the neighbour of
  the overclaiming-doc-comment lesson above and the more dangerous one: a comment that overclaims is
  read by a person, but **a test name that overclaims is read by a person as a passing test**.
  The fix was both halves — rename to what it does pin (`aCleanRunAfterALostOneGetsNoAccount`), and
  write the one that reaches the line. **When a mutation survives, check whether the test named for
  it ever executes the branch it names** — and if the branch is defensive, say so in the test rather
  than deleting either.

- **`try!` IN A TEST DOES NOT FAIL THE TEST — IT KILLS THE PROCESS, AND TAKES THE ROUND'S EVIDENCE
  WITH IT.** Chunk 6's round ran three mutations that stopped the device-loss alert being raised.
  All three landed on `theAlertNamesTheEndingThatProducedIt`, which read
  `try! #require(bench.failures.first?.text)`. A failed `#require` under `try!` **traps**: the test
  bundle died, xcodebuild printed *"Restarting after unexpected exit, crash, or test timeout"*, and
  the run ended having executed **321 of 1288 tests — with a green tick on the 321**. The other 967
  reported nothing, so *which* tests catch that mutation — the entire question a mutation round
  asks — was unanswerable for three of seventeen rows.
  **`scripts/test.sh`'s floor check is what caught it**, refusing the partial run with *"INCOMPLETE
  RUN: 321 tests in 54 suites, but this repo has run 1288"*. Without that floor the round would have
  recorded three plausible kills and nobody would have known the readings were a quarter of a suite.
  Note what the raw log said on its own: `✔ Test run with 321 tests in 54 suites passed`, a tick,
  four lines above `** TEST FAILED **`. A `tail -1` on the summary line reads the **retry**, not the
  run. Three rules follow:
  **use `try #require` in a `throws` test, never `try!`** — a failed requirement then fails that one
  test and unwinds normally; **read a mutation log by its named failing tests and its exit code,
  never by the last summary line**; and **a test total below the floor is INCONCLUSIVE for every
  test in the suite, not only the ones that failed** — the same rule as a zero total, for the same
  reason. All nine `try!` sites in the test target were converted in chunk 6's commit, and the three
  contaminated rows were re-run.

- **A SURVIVING MUTATION CAN MEAN THE TEST DOUBLE CANNOT REACH THE LINE — NOT THAT THE TESTS FORGOT
  IT.** Chunk 7b moved `.shortTransfer` from the block-failure arm of `RetentionTestEngine.classify`
  into `.deviceLost`. All 1,288 tests passed. So did the reverse reading: the engine's treatment of
  a short transfer was unpinned in **both** directions, in the one function Step 12 exists to get
  right.
  The reason was not an oversight in the tests. `InMemoryBlockDevice` is the only device the engine
  tests run against, and it had four fault hooks — read error, write error, silent corruption,
  device loss — and **none that could produce a short transfer**. Step 2 reserved that case for the
  real device and nothing revisited it, so no test *could* have been written to cover the line
  without first extending the fake. Meanwhile `FileDescriptorBlockDeviceTests` did pin short
  transfers, which is what made the gap invisible: grep finds the case name in a test file and the
  coverage looks present. **What that test pins is what *produces* a short transfer. What was
  missing is what is *done* with one.** Two different questions about the same enum case, and only
  a mutation round distinguishes them.
  So when a mutation survives, the question is not only *"which test should have caught this?"* but
  **"could any test have reached this line at all, with the fakes that exist?"** If the answer is
  no, the fix is in the harness before it is in the tests. The tell to look for: a case the fake's
  own header says is *"reserved for the real device"*, still reserved several steps later.
  Two smaller things followed from writing the hook. A short transfer **delivers or persists its
  prefix and then throws** — `FileDescriptorBlockDevice` has `transferred` bytes in the caller's
  buffer when its guard fires — so a fake that threw with the buffer untouched would let a bug that
  reads the untouched tail pass on the bench and fail on hardware; the fake copies the prefix for
  that reason. And extending the fake **moved the helper source hash**, because
  `Core/InMemoryBlockDevice.swift` is a `project.pbxproj` membership exception built into the test
  target *as well as* the helper: `nm` finds the new hooks in the daemon binary. A hash can move for
  a change that cannot alter a single thing the daemon does. Record it anyway — the recipe is
  defined by path and the binary really is different — but know which kind of move it was before
  concluding a gate result lapsed for a substantive reason.
