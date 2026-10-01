# Step 15 — the event-set audit (chunk 1)

> **Written 2026-09-30, read-only, against commit `d59042e`**, helper source hash **`e19b0b3c…`**
> (unmoved), protocol **v15**, on macOS 27.0.1 (26A434). No source, test, install or drive was
> touched, and nothing here is a pass. **Findings are reported, not fixed**: each one waits for the
> user's decision, and the chunks that act on them get their own plans.
>
> **What would invalidate it:** any edit to a `.swift` file under `USBDriveTester/` outside the
> test target — the inventory is of the source as it stands at `d59042e` — and, for F1's reading of
> the log store, a macOS major or minor release or a change to the subsystem's logging
> configuration (`CONSTRAINTS.md` §2). Re-derive the inventory with the method below rather than
> editing its counts by hand.
>
> *(2026-09-30, chunk 2: the user's decisions on F1–F6, F1's reading of the store, and a correction
> to F5 are in section 4. Sections 1–3 are left as written.)*

## Method

A scratch script — not committed — found every `Logger(subsystem:category:)` declaration in the
app and helper targets (tests excluded), then every call on each declared name, bracket-balanced
to the closing parenthesis, and recorded its file, line, target, category, level and format
string. Two cross-checks: `grep -c "Logger(subsystem"` per file agrees at **27** declarations
(`RunLogger`, a `RunObserver`, is not one), and there is **no** `os_log`, `OSLog`, `NSLog` or
`print(` outside comments. The helper's `Core/` does not log by design (`RetentionRun.swift`'s
*Why Core does not log*): `RunCoordinator`'s `RunLogger` logs the engine's events for it.

**172 log calls**: app **119**, helper **53**. By level: `notice` **92**, `error` **68**, `info`
**10**, `debug` **2**, and no `fault`. By category: `io` 65, `lifecycle` 28, `discovery` 24,
`safety` 21, `xpc` 17, `quit` 16, `metrics` 1. **Every interpolation is `.public`**: 130 calls
mark each one, and the other two interpolate only integers, which unified logging does not redact
(`AppModel.swift:1197`), or are `.public` past the point where the scratch script's output was cut
off (`RunCoordinator.swift:535`, checked by eye). No call marks anything `.private`.

## 1. Coverage — NFR-OBS-1 and Step 15's step 1

Every event on either list is logged, on both sides where both sides take part, at `notice` or
`error` — the levels the store persists (`info` stays in memory; `debug` is not kept). Line
numbers are at `d59042e`.

| Event | App | Helper |
|---|---|---|
| **Run start** | `RunController.swift:1037` *run authorised* — drive serial, I/O size, failure mode | `main.swift:690` *runRetentionCycle from …* — start block, block count, I/O size, mode code; `RunCoordinator.swift:158` *retention cycle START on diskN* — block range, chunks, mode, cache-bypass verdict |
| **Run stop** | `RunController.swift:978` *run control: A → B on the Stop command*; `:1173` *run ended: \<outcome>* | `RunControlChannel.swift:113` *run control set to stop by \<peer>*; `RunCoordinator.swift:191` *retention cycle END* — outcome, chunks done of planned, bytes read/written/verified, failure summary |
| **Failure-mode selection** | `RunReportView.swift:623` *failure-handling mode selected* (the picker, logged from the report view's file); also in *run authorised* | in START (name) and in `main.swift:690` (code) |
| **Failed block ranges** | the report's count, `RunReportView.swift:631` | `RunCoordinator.swift:173` *retention cycle FAILURE: block N* or *blocks N–M (count): kind*, one line per coalesced range up to **64**, then one truncation line (`:178`); the END line's summary; `:576` the last device-level failure |
| **Device connect / loss** | `DeviceDiscovery.swift:143` *connected / disconnected diskN*; `VolumeChangeWatcher.swift:200` *a disk disappeared*; `RunController.swift:1073` *the drive under test left the machine while \<state>* — model, serial, BSD name; `:1134` the slice lines a run's own claim causes | the FAILURE line with the device's errno (errno 6 at Step 12's pulls); `main.swift:1104` *released on connection loss* |
| **Helper registration / unregistration** | `HelperRegistration.swift`, 20 calls — register requested / submitted / succeeded / failed, status changes, uninstall requested / refused / complete / failed | `main.swift:1131` *helper started as uid 0 … protocol v15* (it does not log its own removal: launchd ends it) |
| **Exclusive claim acquire / release** | `RunController.swift:1100` (release not awaited) | `DeviceClaim.swift:556` *acquired … open exclusively*, `:822` *released*, `:479`/`:653`/`:656` *acquire REFUSED*; `main.swift:530`/`:543`/`:571` |
| **Pause / resume** | `RunController.swift:978` on the Pause and Resume commands; `:1056` *run paused and settled at block N* | `RunControlChannel.swift:113` |
| **Sleep assertion acquire / release** | `SleepPrevention.swift:129` *holding*, `:144` *released*, `:119` the double-hold guard | — (the helper holds none) |

**Gaps: one, minor.** **G1** — while a run is active, discovery is frozen, and a drive connected
in that time is logged only as *"device change ignored while a run is active"*
(`DeviceDiscovery.swift:191`), without naming it. Disappearances are still named
(`VolumeChangeWatcher.swift:200`), so this touches connects only, and the refresh after the run
names whatever is there.

## 2. Findings

**F1 — functional, and the largest: the log store keeps very little of this subsystem.**
`log show --predicate 'subsystem == "com.arc3solutions.USBDriveTester"' --info --debug` over the
last 30 days returns **21 lines in all**: 3 from 2026-09-28, 4 from 2026-09-29 and 14 from
2026-09-30. The 3 from 2026-09-28 are in the window of Step 13's chunk 3, 14:47–15:27. That walk's
record quotes many more of this subsystem's lines — *run ended: deviceLost*, *a disk disappeared*,
the helper's errno 6 — read headless the same afternoon. The 3 that survive are a metrics line and
two release lines, 15:12:07–15:13:05. The instrument reaches that day and that subsystem, because
it returns those 3 lines; and it reaches the store, because every process together has **4825**
lines in the one minute from 15:00 on 2026-09-28. So what has gone is this subsystem's lines,
within about two days. Today's 14 lines include the `info` ones, which are still in memory.

**This is NFR-OBS-2 and gate item 2 directly.** A run *"reconstructable from logs after the
fact"* currently holds for hours, not days. **The cause is not established.** Reading the
subsystem's persistence settings needs root: `log config --status` answers *"Must be root"*. So
this audit does not say whether the cause is a configuration, a quota or macOS behaviour. The
commands to settle it would be handed over (`sudo /usr/bin/log config --status --subsystem
com.arc3solutions.USBDriveTester`, and the store's statistics). The remedies range from a subsystem
persistence setting, to a level change, to NFR-OBS-2 naming a retention window it does not name
today. That is a decision, not something this audit makes.

**F2 — NFR-SEC-6, a decision: the helper logs a SHA-256 of device blocks.** `main.swift:984`, at
`notice`: *digest for \<peer>: blocks N–M (B bytes) = \<hex>*. It is not device contents, but it is
computed from them. Over a single block whose content can be guessed (zeros, a known boot sector) it
confirms the guess. Only the gate tools and scripts call `digestRange` — `retention-cycle-check.sh`,
`run-control-check.sh`, `xpc-concurrency-check.sh` and their `tools/` clients. The app never
does. Changing this line is helper source, so it moves the hash.

**F3 — privacy, a decision: identifying values are logged `.public`.** Step 15's step 4 says
*"mark any potentially-identifying interpolations as `private`"*. What is logged `.public`:
- **Drive serial numbers**, in six app lines: `RunController.swift:1037`, `:1073`, `:1087`,
  `PreRunWarnings.swift:190`, `RunReportView.swift:600`, `:631`.
- **Model names.**
- **Volume names**, in `VolumeMounter.swift`'s success and failure messages (`:487`, `:493`).
  They are user-chosen and can name a person.

Gate item 2, *"reconstructable (device …)"*, is exactly what the serial provides, and `.private`
prints `<private>` in `log show` unless private data is enabled on the machine. So step 4 and gate
item 2 pull against each other. There are three options: keep them public and record why; make
them private and reconstruct by BSD name and time; or log a stable hash of the serial. Serials are
in app source only; volume names come through the app's `VolumeMounter`.

**F4 — diagnosability, a design choice: nothing ties a run's lines together but time and pid.**
The helper's END line names no device — only START does — and a paused and resumed run produces
several START/END pairs, one per `runRetentionCycle` call. The app's lines name the drive by
serial, and the helper's lines name it by BSD name. Step 12's and Step 13's walks reconstructed
their pulls this way, by timestamp, so it works. A run identifier carried on both sides would make
it mechanical, but it would touch the protocol, `Shared/` and the hash.

**F5 — cosmetic: `error` is used for expected refusals.** For example `RunSequencer.swift:228`,
`:255` and `:284` (*start refused, a run is already in progress*), `RunController.swift:421` and
`:446`, and `IOKitDeviceEnumerator.swift:233–244` (*skipping diskN: no Size property*, for any odd
disk). Beside F7's noise this makes `error` a weak filter. Every line is persisted either way, so
none of this is lost. The 10 `info` lines are:
- the XPC handshake, ping and connection-admission lines;
- the readiness checks;
- *parameters ACCEPTED*, which `main.swift:690` repeats at `notice`;
- *discovery found N USB whole disk(s)*, whose names the `notice` enumeration line repeats.

So the `info` level loses no NFR-OBS-1 event.

*(2026-09-30: `RunController.swift:421` and `:446` are wrongly listed above — they log states that
should be unreachable, where `error` is right. Section 4, F5.)*

**F6 — categories.** Seven categories are in use: step 2's six and `quit`, which step 2 does not
name. Two placements are worth a look. `io` in the app carries run control, the report and its
export, sleep prevention and the I/O-size picker. The failure-mode selection is logged from
`RunReportView.swift`, under `io`. The scheme filters as step 2 asks — one subsystem, the same
names on both targets — so any change here is naming, not coverage.

**F7 — Owed (h), re-confirmed in the source.** `HelperConnection.swift:439` (*helper progress
connection invalidated*) and `:784` (*helper transport error*) are both still `error`, still
unconditional, and still what the 1 Hz poll produces while the helper is unreachable. The shape
agreed 2026-09-26 stands: the first failure of a streak logged, the repeats silent, one notice with
the count on recovery.

**No device bytes anywhere.** No log call interpolates a `Data`, a buffer, a pointer or a byte
array. The read, write and verify paths — `RetentionRun` in `Core/` — do not log at all, and
`RunLogger` sees only `RunStart`, `BlockRangeFailure` (block numbers and a kind) and `RunSummary`
(counts). The one value derived from device bytes is F2's digest. This is a reading of the source;
gate item 3 wants it shown on a real run's log too.

## 3. What this means for the rest of the step

- **Coverage is essentially complete.** The step's weight is in F1 (retention), F2 and F3
  (privacy decisions) and F4 (correlation), not in adding events.
- **F1 is the first thing to settle.** Its cause decides whether the fix is a setting, a source
  change or a requirement, and gate item 2 cannot pass while a run's lines vanish within days.
- **By the source they touch:**
  - app source only: G1, F3, F5, F7 (Owed (h));
  - helper source, moving the hash and lapsing the four hardware gates: F2, and F4 if it is taken;
  - naming only: F6.

## 4. 2026-09-30: the readings and decisions after the audit

*Added the same day, in chunk 2, against `d60b9c3`; documentation only, helper hash `e19b0b3c…`
unmoved. Sections 1–3 are left as written; where this section corrects them, it says so.*

**F1 — read.** The user ran the two commands handed over, the same afternoon:
- `sudo /usr/bin/log config --status --subsystem com.arc3solutions.USBDriveTester` →
  `INFO PERSIST_DEFAULT` (signposts: persisted off, enabled on, backtrace off; oversize off). **The
  subsystem is at the defaults**: `notice` and `error` persist, `info` stays in memory. Nothing
  lowers or disables its persistence.
- `sudo /usr/bin/log stats --overview` → the store spans **2026-09-08 06:36:23 to 2026-09-30
  13:42:55**, 1,772,901,384 bytes (6.3 GB uncompressed), 44,636,293 events. Its `ttl` row puts
  **about 20.6 M** of them on a fixed lifetime — 1 day 4,230,727; 3 days 6,013,855; 7 days
  7,274,314; 14 days 2,885,338; 30 days 171,524 — and the rest are kept until space runs out. So
  the store is not evicting everything older than two days.
- `log help config` and `man log` (read headless): `log config` sets `level`, `persist`, `stream`
  and the signpost and oversize keys only. **No setting controls a subsystem's lifetime**; the one
  TTL control is `log erase --ttl`, which deletes.

**The best-fitting cause, not proven:** macOS gives this subsystem's lines a short lifetime, one or
three days. `log stats` does not break lifetimes down by subsystem, and it does not explain why the
three 2026-09-28 lines that survive — all `notice` — outlived the others. Re-running the audit's
query that afternoon returned **19** lines where it returned 21 that morning: two of that day's
`info` lines had left memory, as `info` does.

**F1 — decided (user, 2026-09-30): options 1 and 2, not 3.**
1. NFR-OBS-2 names the window: the unified log keeps a run's lines for about one to three days on
   macOS 27.0.1, and after that a run is reconstructed from its exported report, which carries the
   device (serial, and BSD name at run time), the outcome and the failed block ranges
   (`RunReport.swift`). A dated note in `nonfunctional-requirements-usb-drive-tester.md`.
2. Gate item 2's evidence is exported the same day, with `log show`, to
   `/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester-evidence/step-15/` — beside the
   repository, on no drive under test — and judged on that file, not on the live store. A dated
   note under Step 15's gate in `BUILD-PLAN.md`.

Not option 3, a durable run log written by the app. *What would invalidate the reading:* a macOS
major or minor release, or a change to the subsystem's logging configuration.

**F2 — decided (user, 2026-09-30): keep the line, drop the hash.** `main.swift:984` goes on
recording that a digest was taken, over which blocks and for which peer, without the value. It is
helper source, so it lands in chunk 4 with F4, whose protocol change moves the hash anyway: the
extra cost is none.

**F3 — decided (user, 2026-09-30): serials, model names and volume names stay `.public`.** The
reason, recorded here and under Step 15's step 4: the log never leaves this Mac and holds no device
contents; gate item 2 needs the drive named; and `.private` prints `<private>` in `log show` unless
private data is enabled for the whole system, which is the worse trade. No source changes.

**F4 — decided (user, 2026-09-30): a shared run ID for future runs.** The app makes a UUID when a
run is authorised, and the helper puts it on that run's lines. A protocol change, v15 → v16, in
`Shared/` and the helper, so it moves the hash, lapses the four hardware gates, pays *Owed* (a) and
makes (b) due. Chunk 4, with its design in that chunk's plan.

**F5 — corrected.** Section 2 lists `RunController.swift:421` and `:446` among *"expected
refusals"*. **They are not.** The comment above `:421` says the state is unreachable and is
logged as a wiring defect; `:446` carries no such comment, but an authorisation with nothing
pending is the same kind of fault by reading, not something a user does. So `error` is right for
both. The `RunSequencer` refusals may be the same kind. The fix
(user, 2026-09-30: *"Fix F5"*) starts by classifying all **68** `error` calls as *unexpected* (stays
`error`) or *routine* (to `notice`), a list the user approves before any level changes. App
source, chunk 3.

**F6 — decided (user, 2026-09-30): option (a), documentation only.** `quit` is recorded as the
seventh category in a dated note under Step 15's step 2. Folding it into `lifecycle` was declined:
it would edit `AppLifecycleDelegate.swift` and so lapse the Step 11 passes whose clauses name that
file, for a filter name.

**F7 — not open.** Section 2 and PROGRESS said every finding awaited a decision; this one was
decided 2026-09-26 (*Owed* (h)), shape and timing both — it waits for the next app-source change,
which is chunk 3. It rides in that chunk.

**The chunks, renumbered from the audit's reply:** 1, this audit; **2**, these decisions, in the
documents; **3**, app source — F5's levels from the approved list, and F7 with its tests, which
runs the suite and so pays *Owed* (o); **4**, `Shared/` and the helper — F4 at protocol v16, F2,
and *Owed* (a) and (b); **5**, the gate — install, the four hardware gates, a traced full run and
an induced interrupted run on a write target, the evidence exported the same day. Each is planned
and approved on its own.

## 5. 2026-09-30: chunk 3 done

*Added the same day, with chunk 3's commit; helper hash `e19b0b3c…` unmoved.* **F5**: all 68
`error` calls classified, and the list approved by the user. **2 moved to `notice`**:
`IOKitDeviceEnumerator.swift`'s *no Size property* and *no usable Preferred Block Size* skips.
2 are F7's. **64 kept**, the helper's 21 among them:
- **wiring defects, 20** — the three `RunSequencer` refusals among them;
- **real failures of an action or the run, 19**;
- **system calls failing, 7**;
- **the helper's calls, 21**, all kept at `error`.

`HelperAvailability.swift:477`, the gate line, is kept by the user's decision. So is
`HelperConnection.swift:417`, option (a): the line before it, *invalidating helper connections*,
already shows when a close was the app's own.

**F7 — paid**: `FailureStreak.swift`, applied to the progress poll only. The full account is the
commit's message, and the summary is PROGRESS's Step 15 row.
