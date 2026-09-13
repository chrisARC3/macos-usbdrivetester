# Step 13 — the human checklist

> **STATUS, 2026-09-13: IN PROGRESS at chunk 5. Item 0 PASSED; chunks 1, 2 and 3 are UNWALKED.**
> Written at **chunk 4**, alongside the mutation round rather than after it, against commit
> `ad1ee28`, suite **1323 / 157 / 0**, protocol **v15**, helper source hash **`e19b0b3c…`**. The
> app was installed from **`af09416`** on 2026-09-13 at 10:51 and **item 0.1 passed against it** —
> the build it replaced, `abc07e3`, predated every line of Step 13 and read 0. **No kickstart was
> owed and none was run.** Nothing below item 0 has been run by a person.
>
> ⚠️ **This block is a status block about itself.** The tenth stale block in this project was
> `progress/step-12-human-checklist.md`'s own header, which still said *"UNWALKED … Nothing here has
> been run"* through three chunks' walks and thirteen commits to that file, because it names no step
> and the grep for the five blocks that do never reached it. **The commit that fills in a Walked line
> below edits this paragraph too.**

> ⚠️ **Step 11's and Step 12's checklist passes do not transfer to this file, and this file's will
> not transfer either.** A pass is a fact about one build on one day. Every chunk below carries a
> line for the date **and** the build it ran against, and both must be filled in. Step 11's item 6.3
> passed on 2026-08-18, was silently broken four days later by a change in another step, and nobody
> noticed for thirteen days — because *"chunks 1–7 passed in full"* reads like a property when it is
> a date.

> ⚠️ **This repository lives on a removable volume.** The absolute paths below are correct for
> `/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester` as of 2026-09-13. If a pasteable
> command fails with *no such file or directory*, re-derive the root with
> `git rev-parse --show-toplevel` and paste that instead.

---

## Why this exists, in one paragraph

Step 13's **decision** is covered to the point of redundancy — which states hold the assertion, that
the rule is stated in one place, that exactly one object can take it, that every transition goes
through one funnel. That is 1,323 tests and it is all of it worth nothing to a sleeping Mac, because
**no test in this project can see whether an assertion was ever published, whether it was the right
kind, or whether it was ever let go.** `ProcessInfo.beginActivity` returns an opaque token with no
description; `endActivity` returns nothing at all. The only instrument that can answer any of those
three questions is `pmset -g assertions`, and it needs a real process. Chunk 4's mutation round
measured exactly where the hole is rather than arguing about it: **deleting the `endActivity` call
entirely — the leaked assertion NFR-REL-9 exists to prevent — passes all 1,323 tests**, and so does
holding the *display*-sleep assertion instead of the system one. Those two mutations are this
checklist's reason for existing, and everything below is built around them.

There is a second reason, particular to this step. **Two of its three requirements are negatives** —
do not prevent display sleep, do not block deliberate sleep — and a negative is the one thing a
green test suite is worst at. Nothing fails when an app quietly holds one assertion too many. The
machine just stops going to sleep, months later, and nobody connects it to a drive test.

---

## Running it

Chunks are run **one at a time, reporting back between each.** Chunk 1 is dry — no run, no writes,
nothing unplugged. Chunks 2 and 3 **write to the scratch drive**, and chunk 3 pulls a cable out of a
running machine.

**The instrument is `scripts/sleep-assertion-watch.sh`, and you should never be asked to type
`pmset` at a particular moment.** Release happens milliseconds after a button press; a person
opening a terminal is sampling a second or two later and can only report the end state. The watcher
polls at 4 Hz and prints a line on every change, so the transcript holds the transitions themselves
and the timestamps line up with the app's own log. Start it before the chunk, do the GUI walk, press
Ctrl-C, and paste the transcript into the chunk's record.

⚠️ **Never answer a gate item from the system-wide summary at the top of `pmset -g assertions`.**
`PreventUserIdleSystemSleep` reads **1** on this machine with nothing of ours running, because
`powerd` holds one whenever the display is on — and it is a **flag, not a count**: measured
2026-09-12 as 1 at baseline, 1 while holding one, 1 while holding **two**, and 1 after release. An
item answered from that line is answered by `powerd`. The watcher reads only the
`Listed by owning process:` section, matched on the app's pid. Item 1.2 makes you look at the trap
once, deliberately, so it is a thing you have seen rather than a warning you have read.

**Builds are installed automatically, and are never something you are asked about.** Every install
is **proved by content** — a string that exists only in that build — and never by a timestamp,
because two hardware gate runs on 2026-08-18 measured stale code while returning entirely plausible
numbers.

⚠️ **Point the content proof at `USBDriveTester.debug.dylib`, not at `MacOS/USBDriveTester`.** This
is a debug-dylib build: the app binary is a 59 KB launcher stub, and all of the app's own strings
live in the dylib beside it. Grepping the stub returns 0 for every product string, which reads
exactly like a failed install (measured 2026-09-08, after that false negative was taken at face
value for one command).

### ⚠️ No kickstart is owed by this step, and none must be run

**Step 13 is GUI-side only.** It touches `RunControlState.swift`, `SleepPrevention.swift` and
`RunController.swift`, all in the app target; the **helper source hash is `e19b0b3c…`, unmoved since
2026-09-07**, so the running daemon is not stale and every hardware gate result recorded against
that hash still stands.

That matters more than usual here: **BTM record #11 has pointed at DerivedData since a 2026-09-09
test run.** The running daemon (pid 89541, started 2026-09-08 16:22:50) came from `/Applications`
and is unaffected — but the *next* kickstart would bring up the DerivedData copy, with byte-identical
binaries and a matching protocol version saying nothing is wrong. If something later in this walk
appears to need one, **stop and hand the command over; it needs `sudo` and must not be run from an
assistant's shell.** See `CONSTRAINTS.md` §1, *It does not stay fixed*.

### Prerequisites

* **The 1 TB scratch T5, serial `12345686DAA9`.** The only write-gate target in this project.
  ⚠️ **Identify it by serial, in the app's own device pane, every time** — three of the attached
  drives are T5s and BSD names move across a replug. The **22 TB Seagate is never a write target.**

  ```bash
  /usr/sbin/diskutil list
  ```

* **The app installed from a build containing Step 13.** Item 0.1 below.

* **Nothing else holding the machine awake.** A `caffeinate` left running from another session, or
  a video playing, does not break any item here — every reading is matched on the app's pid — but it
  makes item 3.4 (the real idle-sleep timer) untestable. Check with:

  ```bash
  /usr/bin/pmset -g assertions | /usr/bin/grep -A 20 'Listed by owning process'
  ```

---

## Item 0 — which build am I looking at *(dry, run once before chunk 1)*

**0.1 — the installed app contains Step 13.** The assertion's name is a string that exists nowhere
in any earlier build, which makes it both the content proof and the thing the gate greps for:

```bash
/usr/bin/grep -c "USB drive retention test in progress" /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester.debug.dylib
```

**≥ 1** means the installed app holds Step 13's code. **0** means it does not, whatever the
timestamps say — the 2026-09-11 build from `abc07e3` reads 0 here, and that is the expected reading
until chunk 5 installs.

*Pass:* ≥ 1.
*What would invalidate it:* changing `IdleSleepPreventer.reason`. The suite pins that string
(`theAssertionNamesItselfInTheWordsTheGateLooksFor`) precisely so that an edit to it breaks a test
rather than this instruction — mutation **m9** of chunk 4's round confirms the test kills it.

**Record:** ✅ **PASSED 2026-09-13 10:51**, headless, at chunk 5.

| | |
|---|---|
| installed from | `af09416` (chunk 4), Debug, via `scripts/install-app.sh` |
| item 0.1 greps | **1** — the previous install, from `abc07e3`, read **0** |
| installed dylib | `a8a0e932…`, byte-identical to the build products (`diff -rq`: **0** differ) |
| installed helper binary | `7590b920…` — **unchanged from the 2026-09-11 install** |
| daemon | pid **89541**, uid 0, ppid 1, started **2026-09-08 16:22:50** — the same process, running byte-identical code |
| kickstart | **none owed, none run.** Step 13 is GUI-side; helper source hash `e19b0b3c…` unmoved |

**And the instrument was re-run the same morning.** `scripts/sleep-assertion-check.sh`, **0
failures**: the type is `PreventUserIdleSystemSleep`, the `reason` string reaches `named:` verbatim,
two activities from one process show as **two** entries, ending one leaves the other held, and the
system-wide summary did not move when we took one (baseline 1, held 1). Release was visible in
**0.090 s against a 0.086 s read cost** — at the instrument's floor, so the release is already true
on the first read rather than 90 ms late. **Nothing in chunk 2 below should be waited for.**

---

## Chunk 1 — the baseline, and the trap *(dry: no run, no writes, no drive needed)*

Nothing here starts a run. The point is to establish that the instrument reads **zero** when nothing
is held — an instrument that cannot show absence cannot show presence either.

Start the watcher in its own terminal and leave it running for the whole chunk:

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/scripts/sleep-assertion-watch.sh
```

**1.1 — at rest, the app holds nothing.** Launch USBDriveTester from `/Applications`. Do not select
anything, do not start a run.

*Pass:* the watcher prints a line naming the app's pid with **held 0** and `—` for the assertions.
*Fail:* any `PreventUserIdleSystemSleep` line attributed to the app's pid before a run has started.

**1.2 — look at the trap once.** In another terminal:

```bash
/usr/bin/pmset -g assertions | /usr/bin/head -12
```

The summary block near the top reads `PreventUserIdleSystemSleep   1` **right now**, with the app
holding nothing. Find the owner further down — it is `powerd`, named *"Powerd - Prevent sleep while
display is on"*.

*Pass:* you have seen the 1 and identified `powerd` as its owner. There is nothing to fix; this item
exists so that no later item is answered from that line.

**1.3 — selecting a drive holds nothing.** Select the 1 TB scratch T5 **by serial** in the device
pane. Do not press Start.

*Pass:* still **held 0**. Selection is not a run; `preventsIdleSleep(in: .idle)` is false and this is
the observable half of it.

**Walked:** date ________ build ________ watcher transcript pasted below.

---

## Chunk 2 — the lifecycle *(writes to the 1 TB scratch T5)*

This is gate items 1, 2 and 3 for every ending a person can produce with a button. Chunk 3 covers
the one they cannot.

Start a fresh watcher for this chunk so its summary covers only this walk:

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/scripts/sleep-assertion-watch.sh
```

**2.1 — Start takes exactly one, of the right type, with the right name.** Select the 1 TB scratch
T5 by serial, acknowledge the warnings, press Start.

*Pass:* one watcher line, **held 1**, reading
`PreventUserIdleSystemSleep "USB drive retention test in progress"`.
*Fail — and these are different failures:* held 0 (never taken); held 2 (the guard is gone —
mutation **m5**); a `PreventUserIdleDisplaySleep` in the detail column (the wrong assertion —
mutation **m8**, which survives the whole suite); any other `named:` string (someone edited
`reason` without the test noticing, which should be impossible — see 0.1).

**2.2 — it was taken on entry to `running`, not on the press.** The app logs both sides. Read them
back after the run:

```bash
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.arc3solutions.USBDriveTester" AND (eventMessage CONTAINS "run control:" OR eventMessage CONTAINS "sleep prevention:")'
```

*Pass:* the `sleep prevention: holding an idle-system-sleep assertion` line sits immediately after
`run control: starting → running on …`, and **not** after `idle → starting`. The pairing is the
point: the `run control:` line above it is what says *why* the assertion moved, and that adjacency
is what makes a leak diagnosable from the record months later.
⚠️ `log show --start` rejects fractional seconds and prints only that error, which a line count
reads as a one-line log. Whole seconds only (measured Step 12, 2026-09-11).

⚠️ **Match the pid, not the process name — the test host is also called `USBDriveTester`.** The unit
suite drives the real state machine, so `scripts/test.sh` emits hundreds of genuine
`run control: starting → running` / `sleep prevention: holding …` pairs from a process indistinguishable
by name from the app (observed 2026-09-13 at 09:59:42, during chunk 4's mutation round). The pid in
the `USBDriveTester[…]` column must be the one the watcher printed. Simplest: **do not run the test
suite during a walk.**

**2.3 — Pause releases it.** Press Pause and let the settle finish.

*Pass:* the watcher goes to **held 0**. NFR-REL-9 names pause explicitly, and this is the row where
the plausible shortcut is wrong: `isRunActive` is **true** in `paused` — the claim is still held and
the volumes are still unmounted — so a rule built on it would keep the Mac awake indefinitely on a
run that is doing nothing. Mutation **m2** makes exactly that mistake and the suite kills it.
*Note:* the release happens on the transition **out of** `running`, which is the press plus one
bounded helper call (at most 1 GiB). If the watcher shows held 1 for a second or two after the
press, that is the settle, not a leak — what must not happen is held 1 once `paused` is on screen.

**2.4 — Resume takes it again.** Press Resume.

*Pass:* **held 1** again, same type, same name. A guard that refused to re-take it would leave the
second half of every paused run with no assertion at all and nothing would say so
(`itCanBeHeldAgainAfterItHasBeenReleased` is the unit-level half of this).

**2.5 — three pause/resume cycles, and never two at once.** Repeat 2.3/2.4 twice more, then read the
watcher's summary (Ctrl-C, or leave it and read it at the end of the chunk).

*Pass:* `most at once  1  (PreventUserIdleSystemSleep only)` and a `changes` count of at least 7.
**This is gate item 3, and the summary line is the evidence** — a person sampling `pmset` after
three cycles sees one entry whether the count went 1,0,1,0,1 or 1,2,3, because a leak is a property
of a *sequence*. Chunk 1 measured that two activities from one process publish two entries with two
ids and that ending one leaves the other held, so a doubling really is visible here.
⚠️ The watcher counts `PreventUserIdleSystemSleep` **only**, deliberately: `powerd` was observed
holding an `ExternalMedia` assertion at the same time as its sleep one, and this app is in the
business of mounting and unmounting external media. Everything the pid owns is still printed in the
detail column — read it, and report anything unexpected even though it does not move the count.

**2.6 — Stop releases it.** With the run going again, press Stop and let it settle.

*Pass:* **held 0** by the time the run report is on screen.

**2.7 — a complete run releases it.** Let a run finish on its own, on the 1 TB scratch T5.
⚠️ **No other drive may be substituted to make this quicker.** The scratch T5, serial
`12345686DAA9`, is the only write target in this project; the 125.8 MB thumb is reserved for Step
12's item 4.9 and the 22 TB Seagate is never a write target. A full pass takes hours — that is the
cost of this item, and it is the one item here that cannot be shortened.

*Pass:* **held 0** with the report on screen, and a `sleep prevention: released` line in the log
adjacent to `running → finishing`.

**2.8 — quitting with no run holds nothing.** Quit the app.

*Pass:* the watcher's last line reads `(USBDriveTester is not running)`. An assertion outlives the
process that took it only if the process is still alive, so this is really a check that nothing
*else* was left behind.

**Walked:** date ________ build ________ drive `12345686DAA9`, transcript and summary pasted below.

---

## Chunk 3 — the endings a button cannot make, and the two negatives *(writes + one cable pull)*

**3.1 — display sleep is not prevented.** Read the detail column for the app's pid at any point
during a run (2.1's line will do).

*Pass:* **no `PreventUserIdleDisplaySleep`** attributed to the app's pid. This is BUILD-PLAN Step 13
step 3, and mutation **m8** — `beginActivity(options: [.idleDisplaySleepDisabled])` — passes all
1,323 tests, so this reading is the only thing standing behind it.

**3.2 — the display actually sleeps during a run.** Start a run, then leave the machine alone for
longer than the display-sleep timer (read it with `/usr/bin/pmset -g | /usr/bin/grep displaysleep`).
Do not touch the keyboard or trackpad.

*Pass:* the display sleeps, and on waking it the run is still going. **This is the half of gate item
1 that 3.4 depends on** — until the display is allowed to sleep, `powerd`'s own assertion keeps the
machine awake whether or not this app holds anything, so a run that survives an idle timer with the
display on has demonstrated nothing.

**3.3 — deliberate sleep is not blocked.** Read the app's assertions during a run once more.

*Pass:* the only type attributed to the app's pid is `PreventUserIdleSystemSleep`. Specifically
**not** `PreventSystemSleep`, which is the one that refuses a deliberate sleep; `IdleSleepPreventer`
passes `[.idleSystemSleepDisabled]` and nothing else, and this is what makes that visible.
*Optional, destructive, on the scratch drive only:* Apple menu → Sleep during a run. The machine
should sleep — that is the requirement. The run will not survive it, and that is expected, not a
defect; do this only if you want the direct reading rather than the inferred one.

**3.4 — the literal reading of gate item 1** *(optional — the gate says "a short idle-sleep timer
**or** `pmset -g assertions`", and 2.1 already satisfies the second)*. With a run going and the
display allowed to sleep (3.2), set a short system-sleep timer and leave the machine alone.

**First, write down what the timer is now** — this is a system setting, and nothing else in this
walk restores it for you:

```bash
/usr/bin/pmset -g custom
```

Then set it. The command needs `sudo`, so it is handed over rather than run from an assistant's
shell:

```bash
sudo /usr/bin/pmset -a sleep 2
```

*Pass:* the machine is still awake and the run still going after five idle minutes.

**Then put it back**, substituting the value you wrote down:

```bash
sudo /usr/bin/pmset -a sleep <the original number>
```

**3.5 — a cable pull releases it.** With a run executing on the 1 TB scratch T5, pull the cable.

*Pass:* the watcher goes to **held 0**, and the log shows `sleep prevention: released` after
`run control: running → finishing`.
⚠️ **Expect the release to lag the pull by a few milliseconds, and that is correct.** On a *running*
run the removal callback does **not** end the run: it arms a three-second deadline and waits for the
helper's reply, which carries the ending — measured 2.7–6.3 ms over six pulls on 2026-09-09. The Mac
must not idle-sleep in that window, so the assertion is deliberately still held while the run finds
out. What must not happen is held 1 once the device-loss report is on screen.

**3.6 — a cable pull from a *paused* run releases it too, and it was already released.** Pause a
run, confirm **held 0** (2.3), then pull the cable.

*Pass:* held 0 throughout — no blip to 1. The assertion went at the pause; the loss has nothing to
release. This is the one ending where route (b) *does* end the run directly, and it is worth walking
because the two paths differ in the code.

**Walked:** date ________ build ________ drive `12345686DAA9`, transcript pasted below.

---

## What has no automated cover, and will not get any

Each of these was **declared in advance** in chunk 4's mutation round and confirmed by measurement,
not argued for. The suite total was **1,323** for every row.

* **That `endActivity` is ever called (mutation m7).** Deleting
  `ProcessInfo.processInfo.endActivity(token)` from `IdleSleepPreventer.end()` while keeping
  `token = nil` passes the entire suite. `isHeld` reads the field, not the OS; the counting double
  the controller's tests use never touches `ProcessInfo` at all; and there is no API that asks
  "is this token still active". **This is NFR-REL-9's defect exactly** — the leaked assertion on an
  exit path — and the only instruments that can see it are `pmset` and a person who notices their
  Mac has stopped sleeping. **Items 2.3, 2.6, 2.7 and 3.5 are the check.**

* **That it is the *idle system sleep* assertion (mutation m8).** Swapping
  `.idleSystemSleepDisabled` for `.idleDisplaySleepDisabled` compiles, holds a token, sets `isHeld`,
  increments the counter, and passes everything. The app would then keep the *screen* awake for
  hours and let the machine sleep mid-write. **Items 2.1, 3.1 and 3.3 are the check.**

* **The two negatives — display sleep and deliberate sleep.** No test can assert the *absence* of an
  assertion nobody took. **Items 3.1, 3.2 and 3.3 are the check**, and 3.2 is the only one of the
  three that exercises the real system rather than reading a list.

* **The `sleepLog` lines themselves (mutation m11).** The error log inside `begin()`'s guard can be
  deleted and nothing fails — deliberately, because no assertion should pin a log line by its text.
  It gets no checklist item either: it fires only on a wiring defect that the state table says
  cannot happen, so there is no way to provoke it without editing the app. The contrast with
  `IdleSleepPreventer.reason` is the point — **that** string is pinned by a test (m9 is killed),
  because a person is told to grep for it in item 0.1, and an instruction that can go silently wrong
  is worse than no instruction.

---

## Walk record

*(Paste watcher transcripts, log extracts and dates here as chunks are walked. Each chunk's own
**Walked** line above is the record of record; this section is the evidence behind it.)*
