# Step 13 — the human checklist

> **STATUS, 2026-09-18: IN PROGRESS at chunk 5. Item 0 PASSED 2026-09-13; its daemon row LAPSED on
> 2026-09-16 and was restored by a kickstart at 2026-09-18 13:06:19. Chunk 1 PASSED 2026-09-18
> 14:47–14:53, on its third walk: the first, that morning, could not show its readings and the
> watcher was rewritten; the second's paste ended before the selection. Chunks 2 and 3 are owed.**
> Written at **chunk 4**, alongside the mutation round rather than after
> it, against commit `ad1ee28`, suite **1323 / 157 / 0**, protocol **v15**, helper source hash
> **`e19b0b3c…`** (re-derived 2026-09-18, unmoved). The app was installed from **`af09416`** on
> 2026-09-13 at 10:51 and **item 0.1 passed against it**; the build it replaced, `abc07e3`, predated
> every line of Step 13 and read 0. Re-checked 2026-09-18: the installed app is unchanged.
> ⚠️ **What moved underneath it was the machine, not the code.** macOS **27.0** (26A428) was
> installed and the Mac rebooted on **2026-09-16**, and the daemon that came up afterwards was an
> **Xcode 27 build out of DerivedData** (pid 12059, helper `32a647da…`), not the installed
> `7590b920…`. **Kickstarted 2026-09-18 13:06:19**: the daemon is now pid **46679**, resolved from
> `/Applications`, running `7590b920…`. See *The daemon*, below.
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
Ctrl-C, and paste the transcript **and the summary it prints** into the chunk's record.

**Every line carries its own reading**, so nothing depends on a header that has scrolled away. The
format (the pid is illustrative):

```
10:26:52  pid 12345  exe /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester
10:26:52  pid 12345  held 0  (owns no assertions)
10:27:52  pid 12345  held 0  (unchanged)
```

* **`exe`** is printed once for each new pid, taken from the kernel, before anything about what it
  holds. If it is not the installed app, the next line says `!! NOT THE INSTALLED APP` — quit that
  copy, launch `/Applications/USBDriveTester.app`, and start the item again. Readings from another
  copy are about another build.
* **`held N`** is the number of `PreventUserIdleSystemSleep` assertions that pid owns, and it is what
  every item below reads. Everything else the pid owns follows it on the same line.
* **`(unchanged)`** is a heartbeat, once a minute while nothing moves. It is how a transcript shows it
  was watching while something happened that was supposed to change nothing — item 1.3.
* **`held ?`** means more than one process is called `USBDriveTester` — an Xcode run beside the
  installed app, say — and the watcher refuses to guess which one you are testing. Quit the other.

⚠️ **Rewritten 2026-09-18, after chunk 1's first walk.** The first version printed the word *held*
only in a header row, over bare columns that its own em-dash placeholder pushed out of line, and
item 1.1 asked a person to find `held 0` in it. They could not, and said so. It is the shape of one
of the defects found in the week of 2026-09-04: an item asking for a reading off a line that does
not carry it. **Changed once more the same day, after chunk 1 passed and before chunk 2:** the
`exe` lookup could print `sed: stdout: Broken pipe` into the transcript for a process mapping many
files (5 runs of 5 against Finder, through a terminal; neither chunk 1 walk showed it). It now
stops at the first name by itself — identical output for all 654 of this user's processes, and no
reading changed. Chunk 1 ran on the version before this; each chunk's **Walked** line names its
watcher.

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

### The daemon — kickstarted 2026-09-18 13:06:19, from `/Applications`

**Kickstarted 2026-09-18 by the user, after the record was read, and it came up from
`/Applications`.** Headless readings, except the two commands the user ran:

| | |
|---|---|
| record, 12:57 | `sfltool dumpbtm`, run by the user. Record **#11** (in the UID −2 section; the app record listing the helper under `Embedded Item Identifiers`): `URL: /Applications/USBDriveTester.app`, generation `710330143423605892`. Daemon record #12: `[enabled, allowed, notified]`, uuid `FF3ADEC2-…` — the `BTM uuid` that `launchctl print` names — generation 125, last use 10:26:52. **No record names DerivedData** |
| kickstart | run by the user. pid 12059 ended on `Terminated: 15`; `runs = 2`, `immediate reason = non-ipc demand` |
| resolve line | `13:06:19.646616 xpcproxy[46679]: Resolved (…, FF3ADEC2-…) to program: /Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper` |
| daemon | pid **46679**, root, ppid 1, started **2026-09-18 13:06:19** |
| helper binary | **`7590b920…`** at that path — the installed helper that item 0 names |
| record since | no `_bundleURLForAuditToken` line for this app between 12:50 and 13:07 |

*What would invalidate it:* a relaunch of the daemon — a crash, a kickstart or a reboot — after
something has pulled the record elsewhere, and the test suite or an Xcode run of the project does
exactly that. **Before chunks 2 and 3, check the pid is still 46679:**

```bash
/bin/launchctl print system/com.arc3solutions.USBDriveTester.Helper | /usr/bin/grep -E '^[[:space:]]+pid = '
```

If it is not, read the resolve line again (the recipe below) before walking.

**Written 2026-09-18 before the kickstart — why one was owed, and the recipe, corrected where
marked:**

**2026-09-18.** The daemon the 2026-09-13 text further down describes is gone. The Mac rebooted into
macOS 27.0 at **2026-09-16 10:38:53**, and the daemon was next launched at **17:28:36** that day,
when Xcode 27 ran the project: `xpcproxy[12059]` resolved it **to program:
`…/DerivedData/USBDriveTester-djyud…/Build/Products/Debug/USBDriveTester.app/Contents/MacOS/`**, five
seconds after Xcode 27 had rebuilt that bundle. Since then the daemon under this walk has been:

| | |
|---|---|
| pid | **12059**, root, ppid 1, started **2026-09-16 17:28:36** |
| from | **DerivedData**, per `xpcproxy`'s resolve line — not `/Applications` |
| helper binary | **`32a647da…`**, built by **Xcode 27** at 17:28:31. The installed one is `7590b920…` |
| helper source | `e19b0b3c…`, unmoved. The **toolchain and the build settings** differ, not the code |

No gate in this project has run against that binary. **Chunk 1 does not depend on it**: it reads the
app's assertions, and the app is the installed `af09416` build. **Chunks 2 and 3 do**: they run a
real test through the helper, and a pass recorded against a helper that Xcode rebuilds on every run
is a pass about nothing in particular.

**The record has already moved back.** BTM's own log, at the moment the installed app was launched
for chunk 1's first walk:

```
2026-09-18 10:26:52.825  _bundleURLForAuditToken: updating item …, name=USBDriveTester, type=app, …
  url=file:///…/DerivedData/USBDriveTester-djyud…/Build/Products/Debug/USBDriveTester.app/
  URL to: file:///Applications/USBDriveTester.app/
```

It is the only move of the record since 2026-09-13. So a kickstart now should bring the daemon up
from `/Applications` — but **read the record first and the resolve line after** (`CONSTRAINTS.md`
§1). Both commands need `sudo`, so they are handed over and never run from an assistant's shell.
First the record, written to a file the assistant can read without `sudo`:

```bash
sudo /usr/bin/sfltool dumpbtm > /tmp/usbdrivetester-btm.txt
```

Record #11 — the app record that lists the helper under `Embedded Item Identifiers` — must name
`/Applications/USBDriveTester.app`. ⚠️ *Corrected 2026-09-18, on reading the 12:57 dump: this said
it "must carry `file:///Applications/USBDriveTester.app/`", which is BTM's **log**'s form. The dump
prints a bare path — `URL: /Applications/USBDriveTester.app` on macOS 27.0, no scheme and no
trailing slash, and no `file://` in any of its 1,182 lines — so the old wording, read literally,
fails a correct record.* Only then:

```bash
sudo /bin/launchctl kickstart -k system/com.arc3solutions.USBDriveTester.Helper
```

after which the resolve line is read back headlessly: `to program:` must name `/Applications`.

```bash
/usr/bin/log show --last 10m --predicate 'process == "xpcproxy" AND eventMessage CONTAINS "to program: " AND eventMessage CONTAINS "USBDriveTester"'
```

⚠️ *Added 2026-09-18: keep `process == "xpcproxy"` in it.* On macOS 27.0 `log` logs its own
invocation — `log run noninteractively, parent: … args: '/usr/bin/log' 'show' …` — and a predicate
on `eventMessage` alone matches that line, because the predicate is among the args. Without the
process clause the recipe prints a line about itself, and a check for **absence** prints one when
there is nothing (measured 13:07; `CONSTRAINTS.md` §1).

⚠️ **Do not run the test suite or run the project from Xcode between those two commands, or after
them until chunk 3 is walked.** The test host is the app run from DerivedData, and it pulls the
record to itself (measured 2026-09-09). The running daemon would not feel it; any relaunch would —
a kickstart, a crash, or a reboot, which is how this one happened.

**As written 2026-09-13, true then, and kept as the record of when it stopped being true:**

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

* **For chunks 2 and 3, the daemon running the installed helper** — resolved from `/Applications`.
  From 2026-09-16 it was not; since the kickstart at **2026-09-18 13:06:19** it is, as pid
  **46679**. Check the pid before each of those chunks — the command is in *The daemon*, above.

* **Nothing else holding the machine awake.** A `caffeinate` left running from another session, or
  a video playing, does not break any item here — every reading is matched on the app's pid — but it
  makes item 3.4 (the real idle-sleep timer) untestable. Check with:

  ```bash
  /usr/bin/pmset -g assertions | /usr/bin/grep -A 20 'Listed by owning process'
  ```

  Measured during chunk 1's third walk, 2026-09-18 14:51: besides `powerd`, the idle-sleep type was
  held by `sharingd`, `bluetoothd` and `useractivityd` — the last two on timeouts of seconds — and
  **the Claude desktop app** held a `NoIdleSleepAssertion` named "Electron". Read the list at the
  moment 3.4 starts, not before.

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
| daemon | pid **89541**, uid 0, ppid 1, started **2026-09-08 16:22:50** — the same process, running byte-identical code. ⚠️ **Lapsed 2026-09-16**: that process ended with the reboot into macOS 27.0 — see the re-check below |
| kickstart | **none owed, none run.** Step 13 is GUI-side; helper source hash `e19b0b3c…` unmoved. ⚠️ **One was owed from 2026-09-16, and was run 2026-09-18 13:06:19** — see *The daemon* |

**And the instrument was re-run the same morning.** `scripts/sleep-assertion-check.sh`, **0
failures**: the type is `PreventUserIdleSystemSleep`, the `reason` string reaches `named:` verbatim,
two activities from one process show as **two** entries, ending one leaves the other held, and the
system-wide summary did not move when we took one (baseline 1, held 1). Release was visible in
**0.090 s against a 0.086 s read cost** — at the instrument's floor, so the release is already true
on the first read rather than 90 ms late. **Nothing in chunk 2 below should be waited for.**

**Re-checked 2026-09-18, headless, after the Mac was updated to macOS 27.0 (26A428) on 2026-09-16.**

| | |
|---|---|
| item 0.1 greps | **1** — unchanged |
| installed dylib | `a8a0e932…` — unchanged |
| installed helper binary | `7590b920…` — unchanged |
| daemon | ⚠️ **not the installed helper**: pid 12059, from DerivedData, an Xcode 27 build (`32a647da…`). **Restored 13:06:19 by a kickstart**: pid 46679, resolved from `/Applications`, running `7590b920…`. See *The daemon* |
| instrument | `scripts/sleep-assertion-check.sh` re-run on macOS 27.0: **0 failures**, every finding unchanged, release visible after **0.093 s against a 0.087 s read** — still the instrument's floor. Compiled by Xcode 27's Swift 6.4; the probe measures macOS, not this app |

The 2026-09-13 instrument run lapsed with the update, as that script's own footer says it would; this
is its re-run. **Item 0.1 did not lapse**: the installed app is the same bytes. *What would invalidate
this re-check:* another install, or another macOS update.

---

## Chunk 1 — the baseline, and the trap *(dry: no run, no writes, no drive needed)*

Nothing here starts a run. The point is to establish that the instrument reads **zero** when nothing
is held — an instrument that cannot show absence cannot show presence either.

Start the watcher in its own terminal and leave it running for the whole chunk:

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/scripts/sleep-assertion-watch.sh
```

**1.1 — at rest, the app holds nothing.** Launch USBDriveTester from `/Applications`. Do not select
anything, do not start a run. The app selects a drive by itself at launch — the first usable one
(FR-DEV-3), which on 2026-09-18 was **the 22 TB Seagate**, `disk4` — and 1.1 is read with that
selection in place: a selection is not a run.

*Pass:* the watcher prints the app's pid with
`exe /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester`, and then
`held 0  (owns no assertions)`.
*Fail:* `held 1` or more for the app's pid before a run has started.
*Neither:* `!! NOT THE INSTALLED APP` — see *Running it*; quit that copy and start the item again.

**1.2 — look at the trap once.** In another terminal:

```bash
/usr/bin/pmset -g assertions | /usr/bin/grep -E "^ +PreventUserIdleSystemSleep +[0-9]|PreventUserIdleSystemSleep named"
```

The first line back is the system-wide summary, `PreventUserIdleSystemSleep   1`, reading 1
**right now** with the app holding nothing. Every line after it is one owner, and `powerd`'s is
among them whenever the display is on:
`pid NNN(powerd): … PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"`.
Other owners come and go — on 2026-09-18, `sharingd` ("Handoff") for minutes, `bluetoothd` and
`useractivityd` for seconds at a time — and the summary still reads 1: a flag, not a count.

*Pass:* the summary reads 1, `powerd` is among the owners, and no line names the app's pid. There is
nothing to fix; this item exists so that no later item is answered from that line.
⚠️ **Corrected 2026-09-18.** This item said `| head -12`, which prints the summary and cuts off the
owner list the item asks you to read. The first walk could not find `powerd` from it. It also said
*"Two lines come back"*: during the third walk there were two owners at 14:49:46 and four at
14:51:13, and an item expecting exactly one reads a normal machine as a fault.

**1.3 — selecting a drive holds nothing.** Select the 1 TB scratch T5 **by serial** in the device
pane. Do not press Start.

Then **wait for a new `(unchanged)` line — one printed after you clicked.** One already on screen
does not count; the next comes within a minute. A change-only log cannot show it was watching during
an event that changed nothing; the heartbeat can. Then press Ctrl-C — **the summary exists only
after Ctrl-C**, so copy the transcript after pressing it, not before.

*Pass:* no `held 1` anywhere in the transcript, an `(unchanged)` line after the selection, and the
summary reading `most at once     held 0`. Selection is not a run;
`preventsIdleSleep(in: .idle)` is false and this is the observable half of it.
⚠️ **Corrected 2026-09-18, after the second walk.** This said *"wait for one `(unchanged)` line"*.
The one on screen was 25 seconds older than the selection, and the transcript was copied then, with
the watcher still running — so it had no line after the selection and no summary.

**First walk, 2026-09-18 10:26–10:34 — not recorded as a pass.** It ran against the installed
`af09416` app, pid 24803 (the log's `processImageUUID` for that pid is the installed stub's LC_UUID,
`EE5AD84B…`, and BTM resolved the process's bundle to `/Applications`). **1.1** read 0, on a line that did not
say what the 0 was — the watcher printed *held* only in its header. **1.2**'s `head -12` showed the 1
and cut off its owner; the owner was confirmed headlessly afterwards as `powerd`, pid 595. **1.3**:
the app logged selecting `disk8` — the scratch T5 by serial, `12345686DAA9` — at 10:28:57, and the
transcript has no line after 10:26:52 and no end time, so it cannot show it was watching then. **What
failed was the instrument, and it was fixed rather than argued with.** Re-walk owed, with the
rewritten watcher — *walked twice more that day, and passed on the third (below)*. *Evidence in
the Walk record, below.*

**Second walk, 2026-09-18 13:23–13:27 — incomplete, not recorded as a pass.** Installed app, pid
47700, and 1.1 read as it should. The app logged selecting `disk8` at 13:25:04; the pasted transcript
ends at a 13:24:39 heartbeat, before it, and has no summary, because it was copied with the watcher
still running. Nothing in it failed — it shows too little. The chunk was walked again.

**Walked:** ✅ **PASSED 2026-09-18 14:47:50–14:53:41**, on the third walk. **Build:** the installed
app from `af09416` (dylib `a8a0e932…`), pid **54729**, its `exe` under `/Applications`. **Watcher:**
as committed in `a32001e`. **Drive:** `disk8`, serial `12345686DAA9`, selected at 14:48:25; the
14:49:00 heartbeat follows it. 1.1 and 1.3 are the walker's transcript and summary; **1.2 was read
headless by the assistant** at 14:49:46, during the walk, with the app idle and the T5 selected — the
walker pasted no 1.2 reading. *What would invalidate it:* another install, or another macOS update.
Evidence in the Walk record, below.

---

## Chunk 2 — the lifecycle *(writes to the 1 TB scratch T5)*

This is gate items 1, 2 and 3 for every ending a person can produce with a button. Chunk 3 covers
the one they cannot.

⚠️ **Only against the daemon the kickstart brought up** — pid **46679**, from `/Applications`,
since 2026-09-18 13:06:19. This chunk runs a real test through the helper, and from 2026-09-16 until
that kickstart the helper was a binary no gate had run against. Check the pid first (*The daemon*,
above); if it has changed, read the resolve line before going on.

Start a fresh watcher for this chunk so its summary covers only this walk:

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/scripts/sleep-assertion-watch.sh
```

**2.1 — Start takes exactly one, of the right type, with the right name.** Select the 1 TB scratch
T5 by serial, acknowledge the warnings, press Start.
⚠️ The app selects a drive by itself at launch, the first usable one (FR-DEV-3), and on 2026-09-18
that was **the 22 TB Seagate**, `disk4`. Read the serial in the device pane before pressing Start.

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

*Pass:* `most at once     held 1  (PreventUserIdleSystemSleep only)` and a `changes` count of at
least 7.
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

*Pass:* the watcher prints `pid -  held 0  (USBDriveTester is not running)`, with nothing after it
but `(unchanged)` lines. An assertion outlives the
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

### Chunk 1, first walk — 2026-09-18, not a pass

**Build:** installed app from `af09416` (dylib `a8a0e932…`); daemon pid 12059 from DerivedData, which
chunk 1 does not read. **Watcher:** the 2026-09-13 version, as committed in `af09416`. As pasted:

```
10:26:43  —      0     (USBDriveTester is not running)
10:26:52  24803          ── pid changed (— → 24803): the app was relaunched
10:26:52  24803    0     —
```

No summary: the transcript ends there, with no end time. From the app's own log afterwards,
headless: the app selected `disk8` at **10:28:57** and quit at **10:34:41**; `disk8` resolved by
serial to the 1 TB scratch T5, `12345686DAA9`. Item 1.2 was answered from `head -12`, whose output
ends at the summary block.

**Which copy was running was settled by two instruments, after a third gave the wrong answer.**
`log show` attributed all 167 of pid 24803's lines to a `USBDriveTester-fndvz…` DerivedData folder
that no longer exists. That path is looked up through the binary's LC_UUID, and the log carries the
UUID too: `EE5AD84B…`, the installed stub's. BTM resolved the same process's bundle to
`/Applications` at 10:26:52.825. `CONSTRAINTS.md` §1 now says so.

### Chunk 1, second walk — 2026-09-18 13:23, incomplete

**Build:** installed app from `af09416`, pid 47700; daemon pid 46679 from `/Applications`, which
chunk 1 does not read. **Watcher:** as committed in `a32001e`. As pasted:

```
13:23:24  pid -  held 0  (USBDriveTester is not running)
13:23:39  pid 47700  exe /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester
13:23:39  pid 47700  held 0  (owns no assertions)
13:24:39  pid 47700  held 0  (unchanged)
```

From the app's own log, headless: the default selection `disk4 (22.00 TB)` at 13:23:39 (FR-DEV-3),
`selected disk8 (1.00 TB)` at **13:25:04**, and `terminate requested: runIsActive=false` at
13:26:57. The one heartbeat pasted is 25 seconds older than the selection, and there is no summary:
the watcher was still running at 13:26:48, after the paste. At that moment pid 47700 owned no
assertions — a single headless reading, which is not the transcript the item asks for.

### Chunk 1, third walk — 2026-09-18 14:47, PASSED

**Build:** installed app from `af09416` (dylib `a8a0e932…`), pid 54729, started 14:48:00; daemon pid
46679 from `/Applications`. **Watcher:** as committed in `a32001e`. **Drive:** `disk8` is serial
`12345686DAA9` in the I/O registry, read at 14:51:39; `disk4` is the 22 TB Seagate,
`00000000NT17XBRA`. As pasted — the transcript to 14:49:00, then the summary Ctrl-C printed:

```
14:47:50  pid -  held 0  (USBDriveTester is not running)
14:48:00  pid 54729  exe /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester
14:48:00  pid 54729  held 0  (owns no assertions)
14:49:00  pid 54729  held 0  (unchanged)
```

```
== summary ======================================================================
  watched          USBDriveTester from 2026-09-18 14:47:50 to 2026-09-18 14:53:41
  samples          1084 at 0.25s
  changes          2
  held at all      NO - nothing was ever held
  most at once     held 0  (PreventUserIdleSystemSleep only)
```

`changes 2` is the start and the launch, so nothing moved between 14:48:00 and 14:53:41, and the
lines between the 14:49:00 heartbeat and the summary, which were not pasted, can only be heartbeats.
From the app's own log: the default selection `disk4 (22.00 TB)` at 14:48:00.216, `selected disk8
(1.00 TB)` at **14:48:25.907**, and no further line to 14:54:50 — no run was started. The 14:49:00
heartbeat is 34 seconds after the selection.

**1.2, read headless by the assistant at 14:49:46**, the app idle with the T5 selected:

```
   PreventUserIdleSystemSleep     1
   pid 1029(sharingd): [0x0001ba5d00018910] 00:01:59 PreventUserIdleSystemSleep named: "Handoff"
   pid 595(powerd): [0x0001ba3d00018903] 00:02:31 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
```

At 14:51:13 the owners of that type were `sharingd`, `powerd`, `bluetoothd` (7 s left on a release
timeout) and `useractivityd` (55 s), and the Claude desktop app held a `NoIdleSleepAssertion` named
"Electron", taken at 14:49:16. None of it touches a reading here, since every reading is matched on
the app's pid — but it is exactly what item 3.4's prerequisite is about, and it changes by the
minute.
