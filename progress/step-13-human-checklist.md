# Step 13 — the human checklist

> **STATUS, 2026-09-28: IN PROGRESS at chunk 5 — the walk RESTARTED 2026-09-27: item 0 PASSED
> 09:44–09:55, chunk 1 PASSED 10:56–11:05 and chunk 2 PASSED 16:18–16:33; chunk 3 PASSED 2026-09-28
> 14:48–15:25, with 3.4 and 3.3's optional deliberate sleep not walked, by the user's decision.
> Every chunk of this checklist is walked; Step 13's verification gate is next, once its plan is
> approved.**
> *(This line read "STATUS, 2026-09-19: IN PROGRESS at chunk
> 5 — and PAUSED since 2026-09-18 for the move to Xcode 27" until 2026-09-27; the rest of this
> block is as it stood, dated where it moved.)* **The walk was PAUSED from 2026-09-18 for the move
> to Xcode 27 (user decision). The move's chunk 3 installed the Xcode 27 build on 2026-09-19, and every
> pass this file had made — item 0, chunk 1, 2.1–2.4 and 2.6, each a fact about the Xcode 26 build
> `af09416` — LAPSED at that install. Item 0 was re-run against the new install that morning and
> PASSED — ⚠️ and LAPSED 2026-09-24 18:01:53, at the install of Step 11's item 6 fix. The move's
> chunk 4 ran 2026-09-19: the four hardware gates PASSED against `ac4d5208…`, and it was OPEN for
> six hours on the window-fit probe — **chunk 4b fixed that probe the same evening,
> the gate measures 613 pt again (614 since 2026-09-24, Step 11's item 6 fix), and chunk 4 CLOSED
> with it, so THE MOVE IS COMPLETE.** The walk
> restarted after the re-walks of Step 11 and 12 items the user decided on 2026-09-19 — Step 12's cable
> pulls are not re-walked on their own, because this file's item 3.7 carries them: item 0
> re-checked, then chunk 1 from the top. Before the pause: item 0 PASSED 2026-09-13; its daemon row
> LAPSED on 2026-09-16 and was restored by a kickstart at 2026-09-18 13:06:19. Chunk 1 PASSED 2026-09-18
> 14:47–14:53, on its third walk: the first, that morning, could not show its readings and the
> watcher was rewritten; the second's paste ended before the selection. Chunk 2 was PART-WALKED: its
> first walk, 15:04–15:07, passed 2.1–2.4 and 2.6 and did two of 2.5's three cycles, which 2.5's
> threshold — one short since it was written, now corrected — let read as enough.**
> Written at **chunk 4**, alongside the mutation round rather than after
> it, against commit `ad1ee28`, suite **1323 / 157 / 0**, protocol **v15**, helper source hash
> **`e19b0b3c…`** (re-derived 2026-09-19, unmoved). The app was installed from **`af09416`** on
> 2026-09-13 at 10:51 and **item 0.1 passed against it**; the build it replaced, `abc07e3`, predated
> every line of Step 13 and read 0. Re-checked 2026-09-18: the installed app is unchanged.
> ⚠️ **What moved underneath it was the machine, not the code.** macOS **27.0** (26A428) was
> installed and the Mac rebooted on **2026-09-16**, and the daemon that came up afterwards was an
> **Xcode 27 build out of DerivedData** (pid 12059, helper `32a647da…`), not the installed
> `7590b920…`. **Kickstarted 2026-09-18 13:06:19**: the daemon became pid **46679**, resolved from
> `/Applications`, running `7590b920…`.
> **From 2026-09-19 the installed app was Xcode 27's build** of `bcde5f5`'s sources, installed
> 10:22:50 — dylib `422c89d3…`, helper `ac4d5208…`. **Since 2026-09-24 18:01:53 it is `77275be`'s**,
> Step 11's item 6 fix — dylib `e6e6e884…`, the same helper — which **lapses item 0's pass of
> 2026-09-19** by its first clause, *another install*; item 0 is re-run when the walk restarts,
> as it was going to be *(and was, 2026-09-27, and passed)*. **The daemon is pid 95762**, kickstarted 2026-09-19 10:32:47, resolved
> from `/Applications`, running `ac4d5208…` — no kickstart owed, the helper being unchanged. See
> *The daemon*, below. *(2026-09-25: **pid 1477 since 12:19:03** — the user's restart of the Mac at
> 12:13 ended 95762 and brought the daemon up again, resolved from `/Applications` at 12:19:03.297,
> the same helper `ac4d5208…`, protocol v15. Still no kickstart owed.)* *(2026-09-25 20:12: **pid
> 14761 since 20:12:28** — Step 11's chunk 16 item 3 switched the helper off and on in Login Items,
> which ended 1477 at 20:11:51.970; resolved from `/Applications`, the same helper `ac4d5208…`,
> protocol v15. Still no kickstart owed.)* *(2026-09-26: **the re-walks are done** — Step 11's by
> 2026-09-25, Step 12's chunks 2 and 1 on 2026-09-26 — **so the walk restarts next, at item 0.**
> Step 12's chunk 1 installed a debug hook over this app at 19:50:50 and took it out by restoring
> the bundle saved before it, at 20:22:31, proved byte-identical to the 2026-09-24 18:01:53 install
> — dylib `e6e6e884…`, the same helper; the daemon stayed pid 14761. Item 0 re-checks all of it.)*
> *(2026-09-27: **the walk restarted, and item 0 PASSED**, 09:44–09:55 — the newest record under
> item 0. The installed app is that 2026-09-24 18:01:53 install, proved byte-identical once more;
> the daemon is still pid 14761, running the installed helper. One instrument finding, F1 — BTM's
> record numbers had moved by one — fixed in the same commit by the user's decision. **The write
> targets widened the same day**, by the user's decision: the 1 TB scratch T5, the 4 TB T5 EVO
> and the 125.8 MB thumb — *Prerequisites*.)* *(2026-09-27, later: **chunk 1 PASSED**,
> 10:56:26–11:05:41, on its fourth walk and the first on the Xcode 27 build — the newest Walked line
> under the chunk. The installed app, pid 42734, held nothing at rest and nothing with the 1 TB
> scratch T5 selected. One instrument finding, F2 — the watcher samples about three times a second,
> not at the 4 Hz this file said — fixed in the same commit by the user's decision, in wording only.
> **Chunk 2 is next**, once the user approves which write target each of its items runs on.)*
> *(2026-09-27, later still: **the user approved chunk 2's drives** — the 4 TB T5 EVO for 2.1–2.6,
> the 125.8 MB thumb for 2.7 — and the standing rules in `BUILD-PLAN.md` widened to match; 2.1 and
> 2.7 say so, dated.)* *(2026-09-27, afternoon: **chunk 2 PASSED**, 16:18:28–16:33:20, on its
> second walk and the first on the Xcode 27 build — the newest Walked line under the chunk. The
> same app process, pid 42734, held one assertion of the right type and name from each entry to
> `running` to the transition out of it — Start, three Pause/Resume cycles and Stop on the 4 TB T5
> EVO, a complete run on the 125.8 MB thumb — never two at once, and nothing after a quit. No
> findings. **Chunk 3 is next**, once the user approves its plan.)* *(2026-09-28: **the user
> approved chunk 3's plan** — both cable pulls on the 4 TB T5 EVO, the display-sleep timer
> shortened for 3.2 and put back after it, and neither 3.3's optional deliberate sleep nor 3.4
> walked; 3.2–3.5 say so, dated.)* *(2026-09-28, afternoon: **chunk 3 PASSED**, 14:48:00–15:25:21,
> on its first walk, both cable pulls on the 4 TB T5 EVO — the Walked line under the chunk. The
> installed app, pid 5999, launched from `/Applications` at 14:45:42, held only
> `PreventUserIdleSystemSleep` while running, and never the display-sleep type; the display slept
> for 2 minutes 49 seconds of a run, and the run went on; a pull mid-run released the assertion 4 ms
> after the app saw the drive go, before the report; a pull from a paused run found nothing held,
> and nothing was taken. All nine of 3.7's Step 12 readings passed, and Step 12's 3.13 and 3.14 at
> the reconnect between the pulls — recorded in that file too. No findings from the walk; **F3**,
> found at its plan — *Prerequisites* named 3.4 alone as the item something else holding the
> machine awake makes untestable — is fixed in the same commit, by the user's decision. This is the
> checklist's last chunk: **Step 13's verification gate is next**, once its plan is approved.)*
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
nothing unplugged. Chunks 2 and 3 **write to a write target** — one of the three flash drives in
*Prerequisites*, checked by serial — and chunk 3 pulls a cable out of a running machine.
⚠️ *Changed 2026-09-27, by the user's decision on the write targets: this said "write to the scratch
drive". The commit that recorded the decision, `c388605`, missed it.*

**The instrument is `scripts/sleep-assertion-watch.sh`, and you should never be asked to type
`pmset` at a particular moment.** Release happens milliseconds after a button press; a person
opening a terminal is sampling a second or two later and can only report the end state. The watcher
sleeps 0.25 s between reads of `pmset` — about three samples a second — and prints a line on every
change, so the transcript holds the transitions themselves and the timestamps line up with the app's
own log. Start it before the chunk, do the GUI walk, press Ctrl-C, and paste the transcript **and the
summary it prints** into the chunk's record.
⚠️ *Corrected 2026-09-27, finding F2 at chunk 1: this said the watcher "polls at 4 Hz". A read of
`pmset` takes time of its own, and the loop sleeps 0.25 s after each one, so a sample comes about
every 0.32 s — 1,710 in 555 s on 2026-09-27, 1,084 in 351 s on 2026-09-18. Its header said
"sampling every 0.25s" and its summary "at 0.25s"; both say "between" since the same commit, and
nothing it reads changed. No item's pass turns on the difference: the states the items ask about
last for seconds, 2.5's "within a second" is three samples wide, and a blip shorter than a sample —
the one thing 3.6's "no blip to 1" could miss — could slip between samples at 4 Hz too.*

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

### The daemon — kickstarted 2026-09-19 10:32:47, from `/Applications`

**Kickstarted 2026-09-19 by the user, at the move to Xcode 27's chunk 3 — after the Xcode 27 build
was installed and the record was read — and it came up from `/Applications`.** Headless readings,
except the two commands the user ran. The daemon's rows were read again at 10:43 and had not moved:

| | |
|---|---|
| install | **10:22:50**, by `scripts/install-app.sh` as committed in `ba97c0e`: exit 0, and its stale-daemon warning printed for pid 46679. The 09:46:27 install, by the script before that fix, installed the same bytes and exited 141 before the warning |
| record moved | the user launched the installed app, and BTM logged `10:27:22.666 _bundleURLForAuditToken: updating item uuid=226468B0-…, name=USBDriveTester, type=app, …` from DerivedData to `/Applications` — the only move since chunk 2 of the move ran the suite, at 09:24:02 |
| record, 10:27:44 | `sfltool dumpbtm`, run by the user. Record **#11** (in the UID −2 section, uuid `226468B0-…`, listing the helper under `Embedded Item Identifiers`): `URL: /Applications/USBDriveTester.app`, generation `710330143423605896`. Daemon record #12: `[enabled, allowed, notified]`, uuid `FF3ADEC2-…`, generation 131. The two other records naming the app, #6 and #50, name `/Applications` too. **None of the dump's 1,183 lines names DerivedData** |
| kickstart | run by the user. pid 46679 ended on `Terminated: 15`; `runs = 3`, `immediate reason = non-ipc demand` |
| resolve line | `10:32:47.800 xpcproxy[95762]: Resolved (…, FF3ADEC2-…) to program: /Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper` |
| daemon | pid **95762**, root, ppid 1, started **2026-09-19 10:32:47**. Its own line at 10:32:47.860: *"helper started as uid 0; listening on com.arc3solutions.USBDriveTester.Helper; protocol v15; …"* |
| helper binary | **`ac4d5208…`** at that path — the installed helper that item 0 names |
| record since | no `_bundleURLForAuditToken` line for this app after 10:27:22.666, read to 10:43 |

*What would invalidate it:* a relaunch of the daemon — a crash, a kickstart or a reboot — after
something has pulled the record elsewhere, and the test suite or an Xcode run of the project does
exactly that; or another install, which leaves this daemon running the previous binary. **Before
chunks 2 and 3, check the pid is still 95762:**

```bash
/bin/launchctl print system/com.arc3solutions.USBDriveTester.Helper | /usr/bin/grep -E '^[[:space:]]+pid = '
```

If it is not, read the resolve line again (the recipe below) before walking.
*(2026-09-25: it is not. **pid 1477**, started 12:19:03 by the user's restart of the Mac at 12:13;
its resolve line, `12:19:03.297 xpcproxy[1477]: Resolved (…, FF3ADEC2-…) to program:
/Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper`, and its
own line at 12:19:03.312, "helper started as uid 0; … protocol v15", both read 2026-09-25. Check
for 1477 from here on.)*
*(2026-09-25 20:12: it changed again — **pid 14761**, started on demand at 20:12:28 after Step 11's
chunk 16 item 3 switched the helper off and on in Login Items; its resolve line, `20:12:28.515
xpcproxy[14761]: Resolved (…, FF3ADEC2-…) to program:
/Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper`, and its
own line at 20:12:28.528, "helper started as uid 0; … protocol v15", both read 2026-09-25. Check
for 14761 from here on.)*
*(2026-09-27, at item 0: still **pid 14761** — `runs = 1`, never exited, and `codesign` against
the pid gives CDHash `e1e7fe63…`, the installed helper's. Its resolve line has aged out of the log,
whose `xpcproxy` lines reach back only to 2026-09-26 02:19:50; none is owed while the pid holds.)*
*(2026-09-27, at chunk 2: still **pid 14761** — `runs = 1` and CDHash `e1e7fe63…` at 14:08:31,
before the walk, and `runs = 1` again at 16:34:26, after it.)*
*(2026-09-28, at chunk 3: still **pid 14761** — `runs = 1` and CDHash `e1e7fe63…` at 14:14:19,
before the walk, and at 14:46:29, with the app open; the same again at 15:26:45 and 15:38:53, after
it.)*

**Whether the record has moved since** needs no `sudo`: BTM logs every move. The start time is just
before the 10:27:22 move, so that line is the first one back, and it is the check that the query
works; **any line after it is a move**:

```bash
/usr/bin/log show --style compact --start '2026-09-19 10:27:00' --predicate 'process == "backgroundtaskmanagementd" AND eventMessage CONTAINS "_bundleURLForAuditToken" AND eventMessage CONTAINS "USBDriveTester"'
```

*Added 2026-09-19, and checked that day: it printed the 10:27:22.666 line and nothing after it.
Nothing but the header means the query is broken, not that the record stayed. The unified log
rotates, so once the 10:27:22 line has aged out, the next record read starts from a `sfltool
dumpbtm` instead.*

*(2026-09-27: it has aged out — BTM's `main` lines reach back only to 2026-09-26 00:03:33 — and item
0 started from the user's dump at 09:36, as this says. The query that works now is anchored on Step
12's chunk 1 launch of the installed app, and it will age out in its turn:*

```bash
/usr/bin/log show --info --debug --style compact --start '2026-09-26 19:45:00' --predicate 'process == "backgroundtaskmanagementd" AND eventMessage CONTAINS "USBDriveTester"'
```

*It printed four lines at 2026-09-26 19:52:59 — .511 and .702, `effectiveItemDispositionWithAuditToken:
pid=31583`, and .514 and .704, `effectiveItemDisposition: appURL=file:///Applications/USBDriveTester.app/`
— and nothing after them, read 2026-09-27. All four are Default-level: without `--info --debug`
it prints the same four, so the flags only widen it. A `_bundleURLForAuditToken` line after them is
a move. Chunk 1 launches the installed app, which leaves fresh lines to anchor on.)* *(2026-09-27,
at chunk 1: it did. The same query with `--start '2026-09-27 10:56:00'` prints four lines at
10:56:41 — .104 and .267, `effectiveItemDispositionWithAuditToken: pid=42734`, and .106 and .268,
`effectiveItemDisposition: appURL=file:///Applications/USBDriveTester.app/` — and nothing after them,
read at 11:21:57.)* *(2026-09-27, at chunk 2: the same four and nothing after them, read at 14:08:41,
before the walk, and at 17:06:33, after it.)* *(2026-09-28, at chunk 3: the same four and nothing
after them at 14:14:19, before the walk. The user's launch of the installed app at 14:45:42 added
four more — .825 and .985, `effectiveItemDispositionWithAuditToken: pid=5999`, and .827 and .987,
`effectiveItemDisposition: appURL=file:///Applications/USBDriveTester.app/` — read at 14:46:29; at
15:38:53, after the walk, nothing after those eight, and no `_bundleURLForAuditToken` line.)*

### The kickstart before it — 2026-09-18 13:06:19, superseded 2026-09-19

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
exactly that. Before chunks 2 and 3 the check was that the pid was still 46679. **Invalidated
2026-09-19** by the Xcode 27 install, which left pid 46679 running the previous helper, and by the
kickstart that ended it — above.

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

The app record — in the dump's `Records for UID -2` section, uuid `226468B0-…`, the one that lists
the helper under `Embedded Item Identifiers` — must name `/Applications/USBDriveTester.app`.
⚠️ *Corrected 2026-09-27, finding F1 at item 0: this named it "Record #11". The number is a
position in its section, not an identifier: #11 through 2026-09-19, #12 on 2026-09-27, when #11 was
Epson's `RemotePrintIODaemon.app`. Nor does the uuid pin it alone — the UID 501 section's record
#51 carries `226468B0-…` too, with no embedded list. The dated readings that say #11 were true on
their day and stay as they are.* ⚠️ *Corrected 2026-09-18, on reading the 12:57 dump: this said
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
*(2026-09-18, later: with the walk paused, the move to Xcode 27 runs the suite on purpose in its
chunk 2. Its chunk 3 reinstalls, relaunches the app from `/Applications` and kickstarts, so the
record is back before the walk restarts at item 0 — where this warning applies again.)*
*(2026-09-19: chunk 2 ran it. The record is on DerivedData since 09:24:02, until chunk 3; the
daemon is still pid 46679 from `/Applications`.)*
*(2026-09-19, later: the move's chunk 3 put the record back on `/Applications` at 10:27:22, and
the daemon has been pid 95762 from there since 10:32:47 — see* The daemon*, above. This warning
applies again, until this walk's chunk 3 is walked.)*
*(2026-09-24: Step 11 item 6's test runs moved the record to DerivedData at 13:44:34.894, by BTM's
own log; the daemon is still pid 95762 from `/Applications`. Launching the installed app moves it
back — read it before item 0.)*
*(2026-09-25: it did — the user's launch of the installed app moved it back at 02:56:15.630, by
BTM's log, and the restart at 12:13 brought the daemon up from there, as pid 1477 at 12:19:03.)*
*(That evening a Login Items toggle relaunched it through the same record, as pid 14761 at
20:12:28.)*

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

* **A write target — one of three flash drives, by the user's decision 2026-09-27**, chosen item
  by item for testing efficiency:

  | drive | serial | |
  |---|---|---|
  | the 1 TB scratch T5 | `12345686DAA9` | holds the byte-pattern fill; a whole run takes hours, and losing the fill costs the time to recreate it |
  | the 4 TB T5 EVO | `00000S7CLNJ0WC02266P` | holds no fill; on a 5 Gb/s link, the slowest whole run of the three |
  | the 125.8 MB thumb | `2211190533300386001515` | a whole run in about 40 s |

  ⚠️ **Identify it by serial, in the app's own device pane and in the pre-run prompt, every
  time** — three of the attached drives are T5s and BSD names move across a replug. The **22 TB
  Seagate is never a write target**, and neither is the 1 TB EVO Plus that holds this repository.
  *(Until 2026-09-27 this bullet named the scratch T5 alone — "The only write-gate target in this
  project". The user widened it that day: "we are free to use the 1 TB scratch T5, the 4 TB Samsung
  and the 126 MB thumb drive. The only consideration is testing efficiency".)*

  ```bash
  /usr/sbin/diskutil list
  ```

* **The app installed from a build containing Step 13.** Item 0.1 below.

* **For chunks 2 and 3, the daemon running the installed helper** — resolved from `/Applications`.
  From 2026-09-16 it was not; from the kickstart at 2026-09-18 13:06:19 it was, as pid 46679,
  until the Xcode 27 install of 2026-09-19 left that one running the previous helper; since the
  kickstart at **2026-09-19 10:32:47** it is, as pid **95762**, running `ac4d5208…`. Check the pid
  before each of those chunks — the command is in *The daemon*, above. *(2026-09-25: pid **1477**
  since the restart at 12:13, resolved from `/Applications` at 12:19:03, the same helper.)*
  *(And pid **14761** since 20:12:28 that day, after a Login Items toggle, resolved from
  `/Applications`, the same helper.)*

* **Nothing else holding the machine awake.** Another process's assertion does not break a reading
  here — every reading is matched on the app's pid — but it can make the two items that test the
  real system untestable. Anything holding `PreventUserIdleDisplaySleep` — a video playing, a
  `caffeinate -d` — keeps the display on, and item 3.2 needs it to sleep. Anything holding the
  idle-system-sleep type — a plain `caffeinate`, which asserts against idle sleep when given no
  flags, among others — keeps the machine awake whatever the app does, and item 3.4 (the real
  idle-sleep timer) needs it not to. Check with:

  ```bash
  /usr/bin/pmset -g assertions | /usr/bin/grep -A 20 'Listed by owning process'
  ```

  Measured during chunk 1's third walk, 2026-09-18 14:51: besides `powerd`, the idle-sleep type was
  held by `sharingd`, `bluetoothd` and `useractivityd` — the last two on timeouts of seconds — and
  **the Claude desktop app** held a `NoIdleSleepAssertion` named "Electron". Read the list at the
  moment 3.2 or 3.4 starts, not before.

  ⚠️ *Corrected 2026-09-28, finding F3 at chunk 3's plan, by the user's decision: this bullet said a
  `caffeinate` or a video playing "does not break any item here … but it makes item 3.4 (the real
  idle-sleep timer) untestable", and ended "Read the list at the moment 3.4 starts". A video holds
  `PreventUserIdleDisplaySleep`, which stops 3.2's display from sleeping, so 3.4 was not the only
  item it touched. It did not touch that day's walk: `PreventUserIdleDisplaySleep` read 0 at each
  of the eight reads that printed it, 14:16:45 to 15:19:26 — at 14:51:09, before 3.2's window, and
  at 14:57:15, after it — and the display slept.*

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

**Record:** ✅ **PASSED 2026-09-27 09:44–09:55**, headless but for the user's `sfltool dumpbtm` at
09:36 — the walk's restart. It ran against the install of 2026-09-24 18:01:53 as Step 12's chunk 1
left it: a debug hook installed over it on 2026-09-26 at 19:50:50, and the bundle saved at 19:50:18,
before the hook, restored at 20:22:31.

| | |
|---|---|
| installed from | `77275be`'s sources — Step 11's item 6 fix — Debug, via `scripts/install-app.sh`, built by **Xcode 27.0** (`27A266a`), installed **2026-09-24 18:01:53**. No file outside `*.md` and `claude-md-test/` has changed since `77275be`, and the helper source hash is `e19b0b3c…` over 21 files, re-derived that morning |
| item 0.1 greps | **1** — and `Device-loss alert` **0**: no debug hook |
| installed binaries | full sha-256, each equal to the manifest taken before the hook: dylib `e6e6e884d77250e0…`, launcher stub `bf787e192c6e7eec…`, helper `ac4d520884f2c3cb…` |
| byte-identical | `diff -rq` against the bundle saved before the hook: **0** differ. The 17-entry manifest — type, mode, flags, owner, size, sha-256, every extended attribute's value, mtime and birth time — identical to the three taken on 2026-09-26: of the installed bundle before the hook, of the copy saved then, and of the bundle after the restore. `codesign -dvvv` identical for the app (CDHash `71b8451c…`, signed 2026-09-24 18:01:53) and the helper (CDHash `e1e7fe63…`, signed 2026-09-19 09:23:51); `codesign --verify --deep --strict` OK |
| daemon | pid **14761**, root, ppid 1, started **2026-09-25 20:12:28**. `launchctl print`: running, `runs = 1`, never exited, `ipc (mach)`, BTM uuid `FF3ADEC2-…`. `codesign` against the pid gives CDHash `e1e7fe63…`, the installed helper's. No app process running |
| record, 09:36 | the user's dump, 1,230 lines. The app record — `Records for UID -2`, uuid `226468B0-…`, listing the helper under `Embedded Item Identifiers` — is **#12** now: `URL: /Applications/USBDriveTester.app`, generation `710330143423605898` (`…896` on 2026-09-19), disposition `[disabled, allowed, notified]`, a first reading with nothing earlier to compare. Daemon record **#13**: `[enabled, allowed, notified]`, uuid `FF3ADEC2-…`, generation 187 (131), last use 2026-09-27 08:46:30. The UID 0 record #7 and the UID 501 record #51 (#6 and #50 on 2026-09-19) name `/Applications` too. **No line names DerivedData** |
| record since | BTM's log: the four lines of Step 12's hooked launch at 2026-09-26 19:52:59, all `/Applications`, and nothing naming the app after them — no move (the query is under *The daemon*). At 08:46:30 that morning BTM re-checked every entry (`userDataDidChange`) and saved its store at 08:46:33, with no line naming the app |
| kickstart | **none owed.** The helper is unchanged, and the daemon has not relaunched since its resolve line was read on 2026-09-25 |
| instrument | the 2026-09-18 re-run of `scripts/sleep-assertion-check.sh`, below, stands: macOS is still 27.0 (26A428), and Xcode 27.0 (27A266a) |

*What would invalidate it:* another install; a relaunch of the daemon after something has moved
BTM's record — the test suite and an Xcode run of the project both move it (*The daemon*); a macOS
update, for the instrument row; a change to `IdleSleepPreventer.reason`, for 0.1.

⚠️ **Finding F1, 2026-09-27 — the instrument's wording, not the app.** The recipe under *The
daemon* and `CONSTRAINTS.md` §1 called the app record "record #11". The dump numbers its records by
position within each UID section, and every number had moved up by one: #11 is now Epson's
`RemotePrintIODaemon.app`, so the recipe read literally checks the wrong record. The uuid does not
pin it alone either: the UID 501 section's #51 carries `226468B0-…` too, with no embedded list.
**Fixed in this record's commit, by the user's decision:** both recipes name the record by its
section, its uuid and the helper in its embedded list, with a dated note; the dated readings that
say #11 stay as they are.

**Record:** ✅ **PASSED 2026-09-19**, headless, at the move to Xcode 27's chunk 3 — the install
proved at 10:23:09, the daemon row after the user's kickstart at 10:32:47, both read again at 10:43.
⚠️ *LAPSED 2026-09-24 18:01:53, by its first clause: `77275be` was installed, Step 11's item 6 fix.
Read headlessly the same evening, not as a record: item 0.1 greps 1, dylib `e6e6e884…`, the same
helper, the daemon still pid 95762 — and BTM's record on DerivedData since 13:44:34.894, which the
next launch of the installed app moves back (`PROGRESS.md`, *Installed app*).*
*(2026-09-25: the user's launch moved it back at 02:56:15.630; the daemon is pid 1477 since the
restart at 12:13, the same helper. Item 0 stays lapsed until it is re-run.)* *(Pid 14761 since
20:12:28 that day, after a Login Items toggle; the same helper.)* *(2026-09-26: Step 12's chunk 1
installed a debug hook over this app at 19:50:50 and put back the bundle saved before it at
20:22:31, proved byte-identical to the 2026-09-24 18:01:53 install; the daemon stayed pid 14761.
Read headlessly at 20:52, not as a record: item 0.1 greps 1, dylib `e6e6e884…`, the same helper,
the daemon still pid 14761. Item 0 stays lapsed until it is re-run.)* *(2026-09-27: re-run and
PASSED — the record above.)*

| | |
|---|---|
| installed from | `bcde5f5`'s sources, Debug, via `scripts/install-app.sh` as committed in `ba97c0e`, built by **Xcode 27.0** (`DTXcode 2700`, `27A266a`), installed **10:22:50** — byte-identical to the 09:46:27 install by the script before that fix |
| item 0.1 greps | **1** |
| installed dylib | `422c89d3…` (was `a8a0e932…`), byte-identical to the build products taken after the install (`diff -rq`: **0** differ); `codesign --verify --deep --strict` OK |
| installed helper binary | `ac4d5208…` (was `7590b920…`) — Xcode 27's build of the unmoved source `e19b0b3c…` |
| daemon | pid **95762**, root, ppid 1, started **2026-09-19 10:32:47**, resolved from `/Applications`, running `ac4d5208…` — see *The daemon* |
| kickstart | **owed, and run.** The helper binary changed and `install-app.sh` printed its warning for pid 46679; the user ran the kickstart at 10:32:47 |
| instrument | the 2026-09-18 re-run of `scripts/sleep-assertion-check.sh`, below, stands: it measures macOS, not this app, and its own footer says it does not lapse when the app's commit moves. macOS is still 27.0 (26A428) |

*What would invalidate it:* another install; a relaunch of the daemon after something has moved
BTM's record (*The daemon*); a macOS update, for the instrument row; a change to
`IdleSleepPreventer.reason`, for 0.1.

**Record:** ✅ **PASSED 2026-09-13 10:51**, headless, at chunk 5. ⚠️ *LAPSED 2026-09-19 at the
Xcode 27 install — the record above.*

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
this re-check:* another install, or another macOS update. *(2026-09-19: lapsed by another install —
except its instrument row, which only a macOS update lapses. See the record at the top of this
item.)*

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

**Walked:** ✅ **PASSED 2026-09-27 10:56:26–11:05:41**, on the fourth walk — the first on the Xcode
27 build. **Build:** the installed app from `77275be` (dylib `e6e6e884…`), as item 0 proved it that
morning; pid **42734**, its `exe` under `/Applications`, and `codesign` against the pid gives the
installed app's CDHash, `71b8451c…`. **Watcher:** as committed in `278ac0b`, sha-256 `6728b7af…`.
**Drive:** `disk9`, serial `12345686DAA9` — the 1 TB scratch T5 — selected at 11:04:33; the 11:04:40
and 11:05:40 heartbeats follow it. All three readings are the walker's: 1.1 and 1.3 the transcript
and its summary, and 1.2 a paste taken at about 11:02:35, read again headless at 11:03:14. *What
would invalidate it:* another install, or another macOS update. The F2 fix below, in this record's
commit, does not: it changes the watcher's wording, not what it reads. Evidence in the Walk record,
below.

⚠️ **Finding F2, 2026-09-27 — the instrument's wording, not the app.** *Running it* said the watcher
"polls at 4 Hz", and its header printed "sampling every 0.25s". It sleeps 0.25 s *after* each read,
and a read takes time of its own: this walk's summary counts 1,710 samples in 555 s, about three a
second, and so do both transcripts of 2026-09-18 — 1,084 in 351 s and 499 in 164 s. **Fixed in this
record's commit, by the user's decision, in wording only:** *Running it*, `PROGRESS.md` (two
places), `BUILD-PLAN.md`'s Step 13 gate, and the script's comment, header and summary line. What the
watcher reads, and when, is unchanged; each later Walked line names the commit its watcher came from.

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
Evidence in the Walk record, below. ⚠️ *LAPSED 2026-09-19 at the Xcode 27 install: chunk 1 is owed
in full, from 1.1, on the new build.* *(2026-09-27: walked in full on the new build and PASSED — the
Walked line above the first walk.)*

---

## Chunk 2 — the lifecycle *(writes to a write target — see* Prerequisites*)*

This is gate items 1, 2 and 3 for every ending a person can produce with a button. Chunk 3 covers
the one they cannot.

⚠️ **Only against the daemon the kickstart brought up** — pid **95762**, from `/Applications`,
since 2026-09-19 10:32:47, running the installed Xcode 27 helper `ac4d5208…`. This chunk runs a real
test through the helper, so its passes are about whichever helper the daemon is running. Check the
pid first (*The daemon*, above); if it has changed, read the resolve line before going on.
*(Until 2026-09-19 this named pid 46679, from the kickstart of 2026-09-18 13:06:19; from 2026-09-16
until that kickstart the helper was a binary no gate had run against. So was `ac4d5208…` until the
move's chunk 4 re-ran the four hardware gates against it on 2026-09-19: all four passed, against
pid 95762.)*
*(2026-09-25: it has changed — pid **1477** since 12:19:03, brought up by the user's restart of the
Mac rather than a kickstart, resolved from `/Applications`, running the same `ac4d5208…`, protocol
v15. The helper the gates ran against has not moved.)* *(And again that evening: pid **14761**
since 20:12:28, after Step 11's chunk 16 item 3 switched the helper off and on in Login Items,
resolved from `/Applications`, the same `ac4d5208…`, protocol v15.)*

Start a fresh watcher for this chunk so its summary covers only this walk:

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/scripts/sleep-assertion-watch.sh
```

**2.1 — Start takes exactly one, of the right type, with the right name.** Select the 4 TB T5 EVO
by serial, `00000S7CLNJ0WC02266P`, acknowledge the warnings, press Start.
⚠️ *Changed 2026-09-27, by the user's decision on chunk 2's drives: this said "Select the 1 TB
scratch T5 by serial". 2.1–2.6 are one run, which has to outlast Start, three Pause/Resume cycles
and Stop, so it goes on the write target that holds no fill to lose; the scratch T5 and its fill
stay out of this chunk. 2.7's complete run goes on the 125.8 MB thumb.*
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

*Pass:* `most at once     held 1  (PreventUserIdleSystemSleep only)`, and **three**
`paused → running on the Resume command` lines for the pid in the log — 2.2's command, its
`--last 10m` widened to cover the walk — each with a transcript line going to `held 1` within a
second of it. A heartbeat's `held 1  (unchanged)` is not one: during a run every heartbeat reads
`held 1`.
⚠️ **Corrected 2026-09-18, after chunk 2's first walk.** This read *"and a `changes` count of at
least 7"*, which was one short from the day it was written (`af09416`): the watcher counts its own
first line as a change — chunk 1's two `held 0` lines summarised as `changes 2`. So Start, **two**
cycles and Stop also make 7, and the 15:04 walk did exactly that. Adding one would not make the count
right, because every change of pid or detail column adds a line, and an app launched mid-watch adds
one. The log says what was pressed and the transcript what was held, and the pass reads both.
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

**2.7 — a complete run releases it.** Let a run finish on its own, on one of the three write
targets in *Prerequisites*, checked by serial in the pre-run prompt. The 125.8 MB thumb finishes a
whole run in about 40 s; the scratch T5 takes hours. The 22 TB Seagate is never a write target.
⚠️ *Changed 2026-09-27, by the user's decision on the write targets. This said "on the 1 TB scratch
T5", and "No other drive may be substituted to make this quicker … the 125.8 MB thumb is reserved
for Step 12's item 4.9" — a reservation spent 2026-09-11 — and so that this was "the one item here
that cannot be shortened". This chunk's heading and the Walked lines of chunks 2 and 3 named the
scratch T5 too, and changed with it.* *(2026-09-27, later, by the user's decision on chunk 2's
drives: the 125.8 MB thumb, `2211190533300386001515`.)*

*Pass:* **held 0** with the report on screen, and a `sleep prevention: released` line in the log
adjacent to `running → finishing`.

**2.8 — quitting with no run holds nothing.** Quit the app.

*Pass:* the watcher prints `pid -  held 0  (USBDriveTester is not running)`, with nothing after it
but `(unchanged)` lines. An assertion outlives the
process that took it only if the process is still alive, so this is really a check that nothing
*else* was left behind.

**Walked:** ✅ **PASSED 2026-09-27 16:18:28–16:33:20**, on the second walk — the first on the Xcode
27 build. **Build:** the installed app from `77275be` (dylib `e6e6e884…`), as item 0 proved it that
morning; pid **42734**, the process chunk 1's fourth walk watched, its `exe` under `/Applications`
and CDHash `71b8451c…`. **Daemon:** pid **14761**, the installed helper `ac4d5208…` (CDHash
`e1e7fe63…`), protocol v15, `runs = 1` before the walk and after it; BTM's record unmoved.
**Watcher:** as committed in `5114006`, sha-256 `2cdc6de9…`. **Drives:** 2.1–2.6 on the 4 TB T5
EVO, serial `00000S7CLNJ0WC02266P`, as `disk10`, selected at 16:18:37; 2.7 on the 125.8 MB thumb,
serial `2211190533300386001515`, as `disk8`, named by the pre-run prompt at 16:29:14; 2.8 needs
none. The transcript and summary are the walker's; 2.2's log extract and the `pmset` cross-checks
were read headless by the assistant during the walk, and the extract once more over the whole of it
at 16:35:31. *What would invalidate it:* another install, another macOS update, or the daemon
running any helper but `ac4d5208…` — this chunk's runs go through it. Evidence in the Walk record,
below.

**First walk, 2026-09-18 15:04:56–15:07:40 — 2.1–2.4 and 2.6 passed; 2.5 one cycle short.** The
installed app, pid 54729, and daemon pid 46679, both as in chunk 1; the scratch T5 by serial,
`12345686DAA9`, named by the pre-run prompt and acquired as `disk8`. Start took one assertion, of the
right type and name, on entry to `running`; each Pause released it in the same second; each Resume
took it again; Stop released it before the run's report was logged; nothing was ever held twice.
But the log has **two** Resumes, not three — Start, two cycles, Stop — and 2.5's threshold as then
written read that as enough (corrected at 2.5). **Owed: 2.5, 2.7 and 2.8**, against the same build
and daemon. *Evidence in the Walk record, below.* *(2026-09-18, later: not against this build after
all — the walk was paused for the move to Xcode 27, and restarts at item 0 on the new install.)*
⚠️ *(2026-09-19: 2.1–2.4 and 2.6 LAPSED at the Xcode 27 install. Chunk 2 is owed in full.)*
*(2026-09-27: walked in full on the new build and PASSED — the Walked line above the first walk.)*

---

## Chunk 3 — the endings a button cannot make, and the two negatives *(writes + two cable pulls)*

*The heading said "one cable pull" until 2026-09-18; 3.5 and 3.6 each pull the cable, and the
run 3.5 ends is not the paused run 3.6 needs.*

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

⚠️ *Added 2026-09-28, by the user's decision on chunk 3's plan:* **shorten the display-sleep timer
for this item, and put it back after.** This Mac's is 60 minutes, which would make 3.2 an hour
hands-off. As in 3.4, write down what the timer is now — `/usr/bin/pmset -g custom` — then, with
the run going:

```bash
sudo /usr/bin/pmset -a displaysleep 2
```

Move the mouse once after it returns, so the last activity the Mac saw comes after the change — the
key press that ran the command may still be timed against the old setting — then leave the machine
alone for about five minutes, and wake it. Put the timer back with the number you wrote down:

```bash
sudo /usr/bin/pmset -a displaysleep <the original number>
```

`-a` sets every power source to one value: on a laptop whose settings differ on battery, restore
`-c` and `-b` separately. The reading is taken afterwards, headless, from the power log — the
display's own lines, and every assertion created or released across the window:

```bash
/usr/bin/pmset -g log | /usr/bin/grep -E 'Display is turned (off|on)'
```

If the display does not sleep, read who held `PreventUserIdleDisplaySleep` before calling it the
app's — a video playing holds it, and so does `caffeinate -d`.

**3.3 — deliberate sleep is not blocked.** Read the app's assertions during a run once more.

*Pass:* the only type attributed to the app's pid is `PreventUserIdleSystemSleep`. Specifically
**not** `PreventSystemSleep`, which is the one that refuses a deliberate sleep; `IdleSleepPreventer`
passes `[.idleSystemSleepDisabled]` and nothing else, and this is what makes that visible.
*Optional, destructive, on a write target, checked by serial:* Apple menu → Sleep during a run. The
machine should sleep — that is the requirement. The run will not survive it, and that is expected,
not a defect; do this only if you want the direct reading rather than the inferred one.
⚠️ *Changed 2026-09-28, by the user's decision on chunk 3's plan: this said "on the scratch drive
only", from before the write targets widened on 2026-09-27. Not part of that day's walk, by the
same decision — it would test macOS, and the app's part is the type it asks for, which the reading
above checks.*

**3.4 — the literal reading of gate item 1** *(optional — the gate says "a short idle-sleep timer
**or** `pmset -g assertions`", and 2.1 already satisfies the second)*. With a run going and the
display allowed to sleep (3.2), set a short system-sleep timer and leave the machine alone.
*(2026-09-28: not part of that day's walk, by the user's decision on chunk 3's plan — the item is
optional, as its heading says.)*

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

**3.5 — a cable pull releases it.** With a run executing on the 4 TB T5 EVO, checked by serial,
pull the cable.
⚠️ *Changed 2026-09-28, by the user's decision on chunk 3's plan: this said "on the 1 TB scratch
T5". A pull during a run can land part-way through a chunk's write-back, so it goes on the drive
whose contents are expendable — the 4 TB T5 EVO is the unmount fixture, which
`scripts/make-unmount-fixture.sh` rebuilds — and the scratch T5 keeps its fill. 3.6 pulls the same
drive. Only that drive's cable is pulled; the 22 TB Seagate stays connected.*

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

**3.7 — Step 12's cable-pull items, carried by 3.5 and 3.6** *(added 2026-09-19, user decision)*.
Every pass in `progress/step-12-human-checklist.md` was made on macOS 26 with an Xcode 26.6 build.
Its dry chunks 1 and 2 are re-walked on their own; its pulls are not, because 3.5 and 3.6 already
pull the cable on this build and can take these readings at no extra cost. Each is named by its
Step 12 number so the pass can be recorded there too.

After **3.5's** pull — a *running* run:

* **(a)** The GUI does not crash or hang, and the window stays usable *(Step 12, 3.4)*.
* **(b)** A **report** appears — **not** the alert *(3.7)*. A reply came back on this path, so there
  is a document, and the report is the message.
* **(c)** The report's outcome is device loss, and its account names **which detector** accounted
  for it *(3.8)*.
* **(d)** Its one device-loss sentence **matches the phase it names**, read against Step 12's
  chunk 3 item 9, whose three rows are verbatim from `HonestFraming.swift` *(3.9)*. **Any phase
  passes here.** Landing in `writingBack` was Step 12's job, and it was observed on 2026-09-09; what
  this build owes is that sentence and phase still agree.
* **(e)** **No Resume** is offered. Check the controls, not the report text *(3.10)*.
* **(f)** Discovery re-runs by itself: the drive leaves the list without a click *(3.12)*. The
  closure in `RunControllerWiring` that fires this has no cover but a person watching.

Reconnecting the drive for 3.6 repeats Step 12's 3.13 and 3.14 on the way: the drive comes back,
confirmed by serial, and the new run is accepted.

After **3.6's** pull — a *paused* run:

* **(g)** The run ends **at once**, not three seconds later *(Step 12, 4.4)*.
* **(h)** The report's device-loss account is this sentence, word for word *(4.7)*:

  > The run was **paused** when the drive left, so no chunk was part-way through anything and
  > nothing was left half-written. Every chunk the run had reached was written back and verified
  > before it stopped.

  The pass is that sentence being on screen. A sentence saying a chunk *may hold partly written
  data* in its place is the defect.
* **(i)** Discovery re-runs, and the drive leaves the list *(4.8)*.

*Pass:* all nine. A miss is a **Step 12 defect found on the Xcode 27 build**, and it is reported as
one. It does not fail 3.5 or 3.6, whose subject is the assertion.

**Walked:** ✅ **PASSED 2026-09-28 14:48:00–15:25:21**, on the first walk — on the Xcode 27 build:
3.1, 3.2, 3.3's reading, 3.5, 3.6 and all nine of 3.7; 3.4 and 3.3's optional deliberate sleep not
walked, by the user's decision on the plan. **Build:** the installed app from `77275be` (dylib
`e6e6e884…`), as item 0 proved it on 2026-09-27; pid **5999**, launched 14:45:42 from
`/Applications`, CDHash `71b8451c…`, signed 2026-09-24 18:01:53. **Daemon:** pid **14761**, the
installed helper `ac4d5208…` (CDHash `e1e7fe63…`), protocol v15, `runs = 1` before the walk and
after it; BTM's record unmoved. **Watcher:** as committed in `5114006`, sha-256 `2cdc6de9…`.
**Drive:** every item on the 4 TB T5 EVO, serial `00000S7CLNJ0WC02266P`, as `disk10`, selected at
14:48:47.789 and at 15:11:01.120, and named by both pre-run prompts, at 14:48:55.326 and
15:11:20.279. **3.2's timer:** `displaysleep` 60, then 2 — read at 14:51:09 — then 60 again, read
at 14:58:15, by the commands the user ran. The transcript and summary are the walker's; the log
extracts, the power log and the `pmset` cross-checks were read headless by the assistant, during
the walk and after it. *What would invalidate it:* another install, another macOS update, or the
daemon running any helper but `ac4d5208…` — both runs go through it. Evidence in the Walk record,
below.

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

### Chunk 1, fourth walk — 2026-09-27 10:56, PASSED

**Build:** installed app from `77275be` (dylib `e6e6e884…`), as item 0 proved it at 09:44–09:55;
pid 42734, ppid 1, started 10:56:40, its mapped images the launcher stub and
`USBDriveTester.debug.dylib`, both under `/Applications`, and `codesign` against the pid gives CDHash
`71b8451c…`, signed 2026-09-24 18:01:53. Daemon pid 14761, which chunk 1 does not read.
**Watcher:** as committed in `278ac0b`, sha-256 `6728b7af…`, unmodified during the walk.
**Drives:** `disk9` resolved by serial to the 1 TB scratch T5, `12345686DAA9`, before the selection
and after the walk; `disk4` is the 22 TB Seagate, `00000000NT17XBRA`; `disk6` is the 1 TB EVO Plus
that holds this repository. As pasted — the whole transcript, then the summary Ctrl-C printed:

```
sleep-assertion-watch: USBDriveTester, sampling every 0.25s, heartbeat every 60s
  Reads only the 'Listed by owning process:' section. The system-wide summary line is a
  flag powerd holds while the display is on, and is never consulted. Ctrl-C to stop.

10:56:26  pid -  held 0  (USBDriveTester is not running)
10:56:40  pid 42734  exe /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester
10:56:40  pid 42734  held 0  (owns no assertions)
10:57:40  pid 42734  held 0  (unchanged)
10:58:40  pid 42734  held 0  (unchanged)
10:59:40  pid 42734  held 0  (unchanged)
11:00:40  pid 42734  held 0  (unchanged)
11:01:40  pid 42734  held 0  (unchanged)
11:02:40  pid 42734  held 0  (unchanged)
11:03:40  pid 42734  held 0  (unchanged)
11:04:40  pid 42734  held 0  (unchanged)
11:05:40  pid 42734  held 0  (unchanged)
^C
== summary ======================================================================
  watched          USBDriveTester from 2026-09-27 10:56:26 to 2026-09-27 11:05:41
  samples          1710 at 0.25s
  changes          2
  held at all      NO - nothing was ever held
  most at once     held 0  (PreventUserIdleSystemSleep only)

  Paste the whole transcript AND this summary into the checklist's walk record.
```

`changes 2` is the start and the launch, as on 2026-09-18, so nothing moved between 10:56:40 and
11:05:41. From the app's own log: `initial enumeration: connected disk4, disk6, disk9` and the
default selection `disk4 (22.00 TB)` at 10:56:41.264 (FR-DEV-3), `helper gate: available — no
modal raised` at 10:56:41.308, `selected disk9 (1.00 TB)` at **11:04:33.750**, and no further line
from the app's subsystem to 11:06:30 — no run was started. The 11:04:40 heartbeat is six seconds
after the selection. BTM's four lines at the launch, 10:56:41, name `/Applications` (*The daemon*).

**1.2, the walker's paste**, taken at about 11:02:35 — dated by `powerd`'s assertion, 02:20:05 old
here and 02:20:44 when the assistant read the same id, `0x0001fc5200018427`, at 11:03:14. The paste
dropped the first line's leading spaces, which the item's pattern requires:

```
PreventUserIdleSystemSleep     1
   pid 419(powerd): [0x0001fc5200018427] 02:20:05 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"  
   pid 779(sharingd): [0x00021d25000187bc] 00:00:02 PreventUserIdleSystemSleep named: "Handoff"  
   pid 758(useractivityd): [0x00021d25000187bb] 00:00:02 PreventUserIdleSystemSleep named: "BTLEAdvertisement.30567278-979A-47C8-80EB-F89C54B9DB79"
```

At 11:03:14 the owners were `powerd` and `sharingd` — `useractivityd`'s had gone — and the summary
still read 1. No line named pid 42734 at either reading.

**For F2, after the walk:** a 20-second run of the same watcher from 11:08:52, read-only, counted
62 samples; pid 42734 still held nothing, with the scratch T5 selected. The reworded watcher, run
for 10 seconds from 11:20:49, counted 30 and printed its new header and summary wording.

### Chunk 2, first walk — 2026-09-18 15:04, 2.5 one cycle short

**Build:** installed app from `af09416` (dylib `a8a0e932…`), pid 54729 — the process chunk 1's third
walk watched; daemon pid 46679 from `/Applications`, `runs = 2` at 15:00:35 and again at 15:09:06, so
it was neither restarted nor replaced across the walk. **Watcher:** as committed in `278ac0b`.
**Drive:** the pre-run prompt at 15:05:18.960 named serial `12345686DAA9`, and the helper acquired
`disk8` at 15:05:31.404 with IOKit reporting 1000204886016 bytes. As pasted — the transcript, then the
summary Ctrl-C printed:

```
15:04:56  pid 54729  exe /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester
15:04:56  pid 54729  held 0  (owns no assertions)
15:05:31  pid 54729  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
15:05:37  pid 54729  held 0  (owns no assertions)
15:06:37  pid 54729  held 0  (unchanged)
15:06:56  pid 54729  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
15:07:01  pid 54729  held 0  (owns no assertions)
15:07:11  pid 54729  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
15:07:23  pid 54729  held 0  (owns no assertions)
```

```
== summary ======================================================================
  watched          USBDriveTester from 2026-09-18 15:04:56 to 2026-09-18 15:07:40
  samples          499 at 0.25s
  changes          7
  held at all      yes
  most at once     held 1  (PreventUserIdleSystemSleep only)
```

2.2's extract, read headless at 15:09:06 with `--start`/`--end` in place of `--last 10m`. Every line
is pid 54729:

```
2026-09-18 15:05:20.400 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: idle → starting on the Start command
2026-09-18 15:05:31.409 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: starting → running on claimEstablished
2026-09-18 15:05:31.411 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-18 15:05:37.418 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: running → pausing on the Pause command
2026-09-18 15:05:37.418 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-18 15:05:37.430 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: pausing → paused on pauseSettled
2026-09-18 15:06:56.537 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: paused → running on the Resume command
2026-09-18 15:06:56.537 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-18 15:07:01.562 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: running → pausing on the Pause command
2026-09-18 15:07:01.562 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-18 15:07:01.582 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: pausing → paused on pauseSettled
2026-09-18 15:07:11.282 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: paused → running on the Resume command
2026-09-18 15:07:11.282 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-18 15:07:22.812 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: running → stopping on the Stop command
2026-09-18 15:07:22.814 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-18 15:07:22.838 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: stopping → finishing on runEnded
2026-09-18 15:07:23.180 Df USBDriveTester[54729:13ffec] [com.arc3solutions.USBDriveTester:io] run control: finishing → finished on deviceReleased
```

- **2.1 ✅** `held 1` at 15:05:31: one entry, `PreventUserIdleSystemSleep "USB drive retention test
  in progress"`, and no display-sleep type — the summary raised no flag. The two spaces after the
  name are the detail column's separator (the watcher's `printf "%s \"%s\"  "`), not a second entry.
- **2.2 ✅** `holding` at 15:05:31.411, 2 ms after `starting → running on claimEstablished`; the 11 s
  from `idle → starting` at 15:05:20.400 — the pre-run unmount and the claim — have no
  sleep-prevention line. Each Resume pairs the same way, `paused → running` then `holding`, in the
  same millisecond.
- **2.3 ✅** each Pause logs `running → pausing`, then `released` in the same millisecond, then
  `paused` 12 ms and 20 ms later: the helper stopped at its next 4 MiB chunk. The watcher read `held 0`
  in the same second both times, 15:05:37 and 15:07:01.
- **2.4 ✅** `held 1` again at 15:06:56 and 15:07:11, the same type and name.
- **2.5 ❌ not passed — two cycles, not three.** `most at once held 1` and no line read `held 2`, so
  neither re-take doubled; but the third cycle was not done. `changes 7` is the watcher's first line,
  Start, two cycles and Stop. It met the bar as then written only because the bar was one short —
  corrected at 2.5.
- **2.6 ✅** Stop at 15:07:22.812 and `released` at .814 — before `run ended: stoppedByUser` (.838),
  the report line (.839) and `finishing → finished` (15:07:23.180). The watcher read `held 0` at
  15:07:23.

The helper's side: four bounded calls on `disk8` — paused at blocks 1818624 and 3342336, one full
1 GiB call completed at 15:07:18.180 in 6.9 s, stopped at block 6856704 — each reading, writing back
and verifying, with no failed range. The report: *"Stopped by the user — the rest of the drive was not
tested"*, 0 failing blocks.

### Chunk 2, second walk — 2026-09-27 16:18, PASSED

**Build:** installed app from `77275be` (dylib `e6e6e884…`), pid 42734 — the process chunk 1's
fourth walk watched, launched 10:56:40 from `/Applications`, CDHash `71b8451c…`. Daemon pid 14761
from `/Applications`: `runs = 1` and CDHash `e1e7fe63…`, the installed helper's, at 14:08:31, and
`runs = 1` again at 16:34:26, so it was neither restarted nor replaced across the walk; BTM's query
(*The daemon*) printed only the four 10:56:41 lines, at 14:08:41 and again at 17:06:33.
**Watcher:** as committed in `5114006`, sha-256 `2cdc6de9…`, the same at 16:30. **Drives,**
resolved by serial at 16:04:29 and again at 16:28:15: `disk10` is the 4 TB T5 EVO,
`00000S7CLNJ0WC02266P`, selected at 16:18:37.044; `disk8` is the 125.8 MB thumb,
`2211190533300386001515`, 245760 × 512 B, selected at 16:29:08.277; `disk9` is the 1 TB scratch T5,
not used; `disk4` is the 22 TB Seagate, never a target. As pasted — the whole transcript, then the
summary Ctrl-C printed:

```
sleep-assertion-watch: USBDriveTester, 0.25s between samples, heartbeat every 60s
  Reads only the 'Listed by owning process:' section. The system-wide summary line is a
  flag powerd holds while the display is on, and is never consulted. Ctrl-C to stop.

16:18:28  pid 42734  exe /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester
16:18:28  pid 42734  held 0  (owns no assertions)
16:19:28  pid 42734  held 0  (unchanged)
16:19:50  pid 42734  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
16:20:50  pid 42734  held 1  (unchanged)
16:21:25  pid 42734  held 0  (owns no assertions)
16:22:25  pid 42734  held 0  (unchanged)
16:22:50  pid 42734  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
16:23:39  pid 42734  held 0  (owns no assertions)
16:23:42  pid 42734  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
16:23:46  pid 42734  held 0  (owns no assertions)
16:23:50  pid 42734  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
16:24:50  pid 42734  held 1  (unchanged)
16:24:50  pid 42734  held 0  (owns no assertions)
16:25:50  pid 42734  held 0  (unchanged)
16:26:50  pid 42734  held 0  (unchanged)
16:27:50  pid 42734  held 0  (unchanged)
16:28:50  pid 42734  held 0  (unchanged)
16:29:21  pid 42734  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
16:30:00  pid 42734  held 0  (owns no assertions)
16:31:00  pid 42734  held 0  (unchanged)
16:32:00  pid 42734  held 0  (unchanged)
16:32:18  pid -  held 0  (USBDriveTester is not running)
16:33:18  pid -  held 0  (unchanged)
^C
== summary ======================================================================
  watched          USBDriveTester from 2026-09-27 16:18:28 to 2026-09-27 16:33:20
  samples          2826, 0.25s between them
  changes          12
  held at all      yes
  most at once     held 1  (PreventUserIdleSystemSleep only)

  Paste the whole transcript AND this summary into the checklist's walk record.
```

2.2's extract, read headless at 16:35:31 with `--start '2026-09-27 16:18:00' --end '2026-09-27
16:33:30'` in place of `--last 10m`. Every line is pid 42734:

```
2026-09-27 16:19:50.165 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: idle → starting on the Start command
2026-09-27 16:19:50.712 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: starting → running on claimEstablished
2026-09-27 16:19:50.713 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-27 16:21:25.013 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: running → pausing on the Pause command
2026-09-27 16:21:25.014 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-27 16:21:25.047 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: pausing → paused on pauseSettled
2026-09-27 16:22:50.365 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: paused → running on the Resume command
2026-09-27 16:22:50.365 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-27 16:23:39.328 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: running → pausing on the Pause command
2026-09-27 16:23:39.328 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-27 16:23:39.357 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: pausing → paused on pauseSettled
2026-09-27 16:23:42.703 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: paused → running on the Resume command
2026-09-27 16:23:42.703 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-27 16:23:46.748 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: running → pausing on the Pause command
2026-09-27 16:23:46.748 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-27 16:23:46.756 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: pausing → paused on pauseSettled
2026-09-27 16:23:49.932 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: paused → running on the Resume command
2026-09-27 16:23:49.933 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-27 16:24:50.562 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: running → stopping on the Stop command
2026-09-27 16:24:50.563 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-27 16:24:50.572 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: stopping → finishing on runEnded
2026-09-27 16:24:50.907 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: finishing → finished on deviceReleased
2026-09-27 16:29:20.922 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: finished → starting on the Start command
2026-09-27 16:29:21.464 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: starting → running on claimEstablished
2026-09-27 16:29:21.464 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-27 16:30:00.566 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: running → finishing on runEnded
2026-09-27 16:30:00.567 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-27 16:30:00.901 Df USBDriveTester[42734:192126] [com.arc3solutions.USBDriveTester:io] run control: finishing → finished on deviceReleased
```

- **2.1 ✅** `held 1` at 16:19:50: one entry, `PreventUserIdleSystemSleep "USB drive retention test
  in progress"`, and no display-sleep type. `pmset` at 16:20:40 listed exactly one assertion for the
  pid, of that type and name, 49 s old. The EVO's three volumes were unmounted at 16:19:50.619–.693,
  before the claim.
- **2.2 ✅** `holding` at 16:19:50.713, 1 ms after `starting → running on claimEstablished`; the
  548 ms from `idle → starting` at 16:19:50.165 — the unmounts and the claim — have no
  sleep-prevention line. Each Resume pairs the same way, `paused → running` then `holding`, within a
  millisecond.
- **2.3 ✅** each Pause logs `running → pausing`, then `released` within a millisecond, then
  `paused` 34, 29 and 8 ms later. The watcher read `held 0` in the same second each time — 16:21:25,
  16:23:39 and 16:23:46 — and `pmset` at 16:21:59 listed nothing for the pid.
- **2.4 ✅** `held 1` again at 16:22:50, the same type and name. `pmset` at 16:23:07 listed exactly
  one, under a new id.
- **2.5 ✅** three `paused → running on the Resume command` lines — 16:22:50.365, 16:23:42.703 and
  16:23:49.932 — each with a transcript line going to `held 1` within a second: 16:22:50, 16:23:42
  and 16:23:50. The summary reads `most at once     held 1  (PreventUserIdleSystemSleep only)`, and
  no line reads `held 2`. The extract has five `holding` lines and five `released`, alternating, and
  `pmset` at 16:24:14, after the third Resume, listed exactly one, under the third id seen.
- **2.6 ✅** Stop at 16:24:50.562 and `released` at .563 — before `run ended: stoppedByUser`
  (.572), the report line (.573) and `finishing → finished` (.907). The watcher read `held 0` at
  16:24:50, `pmset` at 16:25:16 listed nothing for the pid, and the EVO's three volumes were mounted
  again.
- **2.7 ✅** on the thumb: the pre-run prompt at 16:29:14.252 named serial
  `2211190533300386001515`, and `run authorised` at 16:29:20.922 the same; `holding` at
  16:29:21.464, in the millisecond of `starting → running`. One call covered the drive, blocks
  0–245759, 30 of 30 chunks in 39.1 s. `run ended: completed` and `running → finishing` at
  16:30:00.566, then `released` at .567 — the pid's next line — and the report, *"Completed — no
  currently-unreadable blocks were found"*, 0 failing blocks. The watcher read `held 0` at 16:30:00;
  `pmset` at 16:30:18, with the report on screen, listed nothing for the pid; Slice_A was mounted
  again.
- **2.8 ✅** the app logged `quit command: … 0 sheet(s)` at 16:32:18.440 and `terminate requested:
  runIsActive=false disposition=quitImmediately` at .475; the watcher printed `pid -  held 0
  (USBDriveTester is not running)` at 16:32:18 and one `(unchanged)` line after it. At 16:34:26 no
  process was named `USBDriveTester`, and `pmset` listed nothing for pid 42734, the daemon's pid or
  any owner of that name — while the same extraction listed `WindowServer`, Claude and `powerd`.

Read with the transcript:

- **`changes 12`** is the watcher's first line, ten changes — Start, three Pauses, three Resumes,
  Stop, the thumb's Start and its completion — and the quit, as predicted before the paste.
- **Two lines at 16:24:50.** The heartbeat fell due 60 s after 16:23:50's line, in the second Stop
  was pressed. Its sample came before the release at .563 and read `held 1  (unchanged)`; a later
  sample in the same second read `held 0`.
- **`finished → starting`** at 2.7's Start, where 2.2's reads `idle → starting`: a closed report
  leaves the state at `finished` — the extract has no transition between 16:24:50.907 and
  16:29:20.922 — and Start is accepted from `.finished` by design (`RunControlState.swift`,
  `start(in:)`).
- **`samples 2826`** in 892 s is 3.2 a second, as F2's wording says.
- **The helper logged two `connection … invalidated` lines at the quit**, both at 16:32:18.483: the
  app opens two connections to it (`HelperConnection.swift`), and the quits of 2026-09-25 20:12:30
  and 2026-09-26 20:20:22 logged two each.

The helper's side: 25 bounded calls on `disk10` from block 0 — 21 completed at 1 GiB each, three
paused, at blocks 21962752, 33357824 and 34299904, each Resume starting its call at that block, and
one stopped, at block 48349184 — then one on `disk8` covering the whole thumb. All 26 read, wrote
back and verified with no failed block range, and every one reported the cache bypassed. The EVO's
report: *"Stopped by the user — the rest of the drive was not tested"*, 0 failing blocks. Both
reports log `verify result qualified: false`, which means the bypass was confirmed
(`RunReport.verifyResultIsQualified`), not a caveat.

### Chunk 3, first walk — 2026-09-28 14:48, PASSED

**Build:** installed app from `77275be` (dylib `e6e6e884…`), pid 5999 — launched 14:45:42 from
`/Applications` for this chunk, CDHash `71b8451c…`, signed 2026-09-24 18:01:53. Daemon pid 14761
from `/Applications`: `runs = 1` and CDHash `e1e7fe63…`, the installed helper's, at 14:14:19 and
14:46:29, and again at 15:26:45 and 15:38:53, so it was neither restarted nor replaced across the
walk; BTM's query (*The daemon*) printed the four 10:56:41 lines at 14:14:19, those and the four the
launch added at 14:46:29, and nothing after the eight at 15:38:53. **Watcher:** as committed in
`5114006`, sha-256 `2cdc6de9…`, checked at 14:46:29 and again before it was stopped. **Drive,**
resolved by serial at 14:23:15, before the walk, and at 14:58:15, during it: `disk10` is the 4 TB
T5 EVO, `00000S7CLNJ0WC02266P`, 7814037168 × 512 B — EFI, `Vol_ExFAT`, the APFS container `disk11`
and `Vol_HFS`, with `Vol_ExFAT`, `Vol_APFS` (`disk11s1`) and `Vol_HFS` mounted. It was selected at
14:48:47.789 for run A and at 15:11:01.120 for run B. `disk4` is the 22 TB Seagate, connected
throughout and never a target; `disk9`, the 1 TB scratch T5, and `disk8`, the 125.8 MB thumb, were
not used. **Power settings:** AC only, `sleep` 180, `displaysleep` 60 — set to 2 for 3.2, read at
14:51:09, and back to 60, read at 14:58:15. As pasted — the whole transcript, then the summary
Ctrl-C printed:

```
sleep-assertion-watch: USBDriveTester, 0.25s between samples, heartbeat every 60s
  Reads only the 'Listed by owning process:' section. The system-wide summary line is a
  flag powerd holds while the display is on, and is never consulted. Ctrl-C to stop.

14:48:00  pid 5999  exe /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester
14:48:00  pid 5999  held 0  (owns no assertions)
14:49:00  pid 5999  held 0  (unchanged)
14:49:01  pid 5999  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
14:50:01  pid 5999  held 1  (unchanged)
14:51:01  pid 5999  held 1  (unchanged)
14:52:01  pid 5999  held 1  (unchanged)
14:53:01  pid 5999  held 1  (unchanged)
14:54:01  pid 5999  held 1  (unchanged)
14:55:01  pid 5999  held 1  (unchanged)
14:56:01  pid 5999  held 1  (unchanged)
14:57:01  pid 5999  held 1  (unchanged)
14:58:01  pid 5999  held 1  (unchanged)
14:59:01  pid 5999  held 1  (unchanged)
14:59:07  pid 5999  held 0  (owns no assertions)
15:00:07  pid 5999  held 0  (unchanged)
15:01:07  pid 5999  held 0  (unchanged)
15:02:07  pid 5999  held 0  (unchanged)
15:03:07  pid 5999  held 0  (unchanged)
15:04:07  pid 5999  held 0  (unchanged)
15:05:07  pid 5999  held 0  (unchanged)
15:06:07  pid 5999  held 0  (unchanged)
15:07:07  pid 5999  held 0  (unchanged)
15:08:07  pid 5999  held 0  (unchanged)
15:09:07  pid 5999  held 0  (unchanged)
15:10:07  pid 5999  held 0  (unchanged)
15:11:07  pid 5999  held 0  (unchanged)
15:11:22  pid 5999  held 1  PreventUserIdleSystemSleep "USB drive retention test in progress"  
15:12:07  pid 5999  held 0  (owns no assertions)
15:13:07  pid 5999  held 0  (unchanged)
15:14:07  pid 5999  held 0  (unchanged)
15:15:07  pid 5999  held 0  (unchanged)
15:16:07  pid 5999  held 0  (unchanged)
15:17:07  pid 5999  held 0  (unchanged)
15:18:07  pid 5999  held 0  (unchanged)
15:19:07  pid 5999  held 0  (unchanged)
15:20:07  pid 5999  held 0  (unchanged)
15:21:07  pid 5999  held 0  (unchanged)
15:22:07  pid 5999  held 0  (unchanged)
15:23:07  pid 5999  held 0  (unchanged)
15:24:07  pid 5999  held 0  (unchanged)
15:25:07  pid 5999  held 0  (unchanged)
^C
== summary ======================================================================
  watched          USBDriveTester from 2026-09-28 14:48:00 to 2026-09-28 15:25:21
  samples          6785, 0.25s between them
  changes          5
  held at all      yes
  most at once     held 1  (PreventUserIdleSystemSleep only)

  Paste the whole transcript AND this summary into the checklist's walk record.
```

The run-control and sleep-prevention lines, read headless after the walk with
`--start '2026-09-28 14:45:00'` and the predicate narrowed to the app's own process. Every line is
pid 5999:

```
2026-09-28 14:49:00.381 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: idle → starting on the Start command
2026-09-28 14:49:01.041 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: starting → running on claimEstablished
2026-09-28 14:49:01.042 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-28 14:59:07.622 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: running → finishing on deviceLost
2026-09-28 14:59:07.622 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-28 14:59:07.990 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: finishing → finished on deviceReleased
2026-09-28 15:11:21.263 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: finished → starting on the Start command
2026-09-28 15:11:21.915 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: starting → running on claimEstablished
2026-09-28 15:11:21.915 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] sleep prevention: holding an idle-system-sleep assertion for the run (USB drive retention test in progress)
2026-09-28 15:12:07.428 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: running → pausing on the Pause command
2026-09-28 15:12:07.428 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] sleep prevention: released the idle-system-sleep assertion
2026-09-28 15:12:07.439 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: pausing → paused on pauseSettled
2026-09-28 15:13:05.792 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: paused → finishing on deviceLost
2026-09-28 15:13:06.286 Df USBDriveTester[5999:28d0d0] [com.arc3solutions.USBDriveTester:io] run control: finishing → finished on deviceReleased
```

The power log across 3.2's window — every line `pmset -g log` has from 14:53:03 to 14:59:09, read
at 15:53:58 and again at 16:05:45, with the tab after each line's category shown as a space:

```
2026-09-28 14:53:32 -0700 Assertions           PID 476(WindowServer) TimedOut UserIsActive "com.apple.iohideventsystem.queue.tickle serviceID:100000ff9 service:AppleUserHIDEventService product:USB Optical Mouse  eventType:17" 00:02:00  id:0x0x90000944e [System: PrevIdle DeclUser kDisp]
2026-09-28 14:53:32 -0700 Assertions           Summary- [System: PrevIdle] Using AC
2026-09-28 14:53:43 -0700 Notification         Display is turned off
2026-09-28 14:53:43 -0700 Assertions           PID 419(powerd) Released PreventUserIdleSystemSleep "Powerd - Prevent sleep while display is on" 02:11:57  id:0x0x10000944f [System: PrevIdle]
2026-09-28 14:53:43 -0700 Assertions           PID 696(backupd-helper) Summary PreventUserIdleSystemSleep "Mutexed Backup Block" 00:00:00  id:0x0x100009b90 [System: PrevIdle]
2026-09-28 14:53:43 -0700 Assertions           PID 5999(USBDriveTester) Summary PreventUserIdleSystemSleep "USB drive retention test in progress" 00:04:42  id:0x0x100009b66 [System: PrevIdle]
2026-09-28 14:53:43 -0700 Assertions           PID 419(powerd) Summary ExternalMedia "com.apple.powermanagement.externalmediamounted" 74:36:25  id:0x0x800008000 [System: PrevIdle]
2026-09-28 14:56:32 -0700 Assertions           PID 476(WindowServer) Created UserIsActive "com.apple.iohideventsystem.queue.tickle serviceID:100000ff9 service:AppleUserHIDEventService product:USB Optical Mouse  eventType:17" 00:00:00  id:0x0x900009ba1 [System: PrevIdle DeclUser kDisp]
2026-09-28 14:56:32 -0700 Assertions           PID 476(WindowServer) Created PreventSystemSleep "com.apple.WindowServer.PUIDS" 00:00:00  id:0x0x700009ba2 [System: PrevIdle PrevSleep DeclUser kCPU kDisp]
2026-09-28 14:56:32 -0700 Notification         Display is turned on
2026-09-28 14:56:32 -0700 Assertions           PID 476(WindowServer) Released PreventSystemSleep "com.apple.WindowServer.PUIDS" 00:00:00  id:0x0x700009ba2 [System: PrevIdle DeclUser kDisp]
2026-09-28 14:56:37 -0700 Assertions           PID 480(loginwindow) Created UserIsActive "Loginwindow User Activity" 00:00:00  id:0x0x900009ba6 [System: PrevIdle DeclUser kDisp]
2026-09-28 14:56:37 -0700 Assertions           PID 480(loginwindow) Released UserIsActive "Loginwindow User Activity" 00:00:00  id:0x0x900009ba6 [System: PrevIdle DeclUser kDisp]
2026-09-28 14:56:38 -0700 Assertions           Summary- [System: PrevIdle DeclUser kDisp] Using AC
2026-09-28 14:59:07 -0700 Assertions           PID 5999(USBDriveTester) Released PreventUserIdleSystemSleep "USB drive retention test in progress" 00:10:06  id:0x0x100009b66 [System: PrevIdle DeclUser kDisp]
```

- **3.1 ✅** `held 1` at 14:49:01: one entry,
  `PreventUserIdleSystemSleep "USB drive retention test in progress"`, and no display-sleep type.
  `pmset` at 14:49:20 listed exactly one assertion for pid 5999, of that type and name, 19 s old,
  and read `PreventUserIdleDisplaySleep 0` and `PreventSystemSleep 0` system-wide. Run B's the same
  at 15:11:31: one, 10 s old, under a new id, and both 0.
- **3.2 ✅** with run A going, the user ran `sudo /usr/bin/pmset -a displaysleep 2` —
  `pmset -g custom` read `displaysleep 2` at 14:51:09, and `PreventUserIdleDisplaySleep 0` — left
  the Mac alone, then woke it: *"Display went dark, run still going"*. The power log has the display
  off from 14:53:43 to 14:56:32, 2 minutes 49 seconds, and nothing taking a display-sleep assertion
  in between. The helper completed 19 bounded calls inside that window, ending
  14:53:46.425–14:56:25.375, each 256 of 256 chunks with no failed range; the run stayed `running`
  — the extract has no transition between 14:49:01.041 and 14:59:07.622 — and the watcher's
  heartbeats read `held 1  (unchanged)` throughout. The user put the timer back,
  `sudo /usr/bin/pmset -a displaysleep 60`, read `60` at 14:58:15, with the run still going.
- **3.3 ✅ (its reading)** the only type attributed to pid 5999 at every read was
  `PreventUserIdleSystemSleep` — the watcher's 6785 samples, whose summary reads `most at once     held 1  (PreventUserIdleSystemSleep only)`,
  and `pmset` at 14:49:20, 14:51:09, 14:57:15, 14:58:15 and 15:11:31. `PreventSystemSleep`, the
  type that refuses a deliberate sleep, read 0 system-wide at 14:48:27, 14:49:20 and 15:11:31. The
  optional deliberate sleep was not walked.
- **3.4** not walked, by the user's decision on the plan.
- **3.5 ✅** the pull, at 14:59:07, mid-run. In order: the helper's call ended at .617, `the device
  was lost while verifying the write-back`, with its `errno 6 (Device not configured)` line; at .618
  the app's `a disk disappeared: disk10 (whole disk)`, `the drive under test left the machine while
  running: …` and `device loss: a call is in flight; waiting up to 3.000000s for the helper's
  reply`; at .622 `run ended: deviceLost`, `running → finishing on deviceLost` and `sleep
  prevention: released the idle-system-sleep assertion`; at .623 the `run report:` line. The release
  came 4 ms after the app saw the drive go — within the 2.7–6.3 ms 3.5 cites from Step 12's six
  pulls — and before the report. The watcher read `held 0` at 14:59:07; the power log has the
  app's `Released` line at 14:59:07, held `00:10:06`; and `pmset` at 14:59:25, with the report on
  screen, listed nothing for pid 5999.
- **3.6 ✅** run B: `holding` at 15:11:21.915 and the watcher's `held 1` at 15:11:22; Pause at
  15:12:07.428, `released` in the same millisecond and `paused` at .439, with the helper's `paused by
  the user at block 10633216` at .433 between them; the watcher's `held 0` at 15:12:07, which the
  user read before the pull, and `pmset` at 15:12:17 listing nothing for the pid. The pull at
  15:13:05: the watcher printed no line for it — its next was the 15:13:07 heartbeat, `held 0
  (unchanged)` — the log has no sleep-prevention line after 15:12:07.428, and `pmset` at 15:13:16
  listed nothing for the pid.
- **3.7 (a) ✅ — Step 12's 3.4.** *"App is responsive, no beach ball or freeze"*, with run A's report
  on screen.
- **3.7 (b) ✅ — 3.7.** *"Full report sheet, not an alert box"*.
- **3.7 (c) ✅ — 3.8.** The headline, *"Ended — the drive disappeared from the USB bus, and the rest
  was not tested"*, and the rows **Drive left at** block 143,491,072 and **While** verifying the
  write-back — the block and the phase, which only route (a)'s reply carries — in the user's
  screenshot of the report, grown to show all its text.
- **3.7 (d) ✅ — 3.9.** The phase was `verifying`, and the sentence on screen is that row's, word for
  word: *"The drive left while this tool was **re-reading block 143,491,072 to verify it**. The
  write-back had already completed, so the chunk was whole when the drive went — it is unverified,
  and **unverified is not the same as bad**."* The helper agrees: 109 chunks written back and 108
  verified — 457179136 − 452984832 = 4194304 B, one chunk — and the read that failed was at offset
  73467428864, block 143491072 × 512, the 109th chunk's first block, 142606336 + 108 × 8192.
- **3.7 (e) ✅ — 3.10.** *"Only Start is offered, no Resume or Stop"*.
- **3.7 (f) ✅ — 3.12.** *"Yes, 4 TB T5 EVO is gone, four drives listed"*; the log's `discovery found
  4 USB whole disk(s): disk4, disk6, disk8, disk9` and `device loss (FR-DEV-8): disconnected disk10`
  at 14:59:07.994, 376 ms after the drive went — before anyone could click.
- **Reconnect — Step 12's 3.13 ✅ and 3.14 ✅.** *"Drive reconnected, 4 TB T5 EVO is back in the
  list"*: `connected disk10` at 15:10:06.559, and at 15:10:15 the serial resolved to `disk10`,
  7814037168 × 512 B, with the same four partitions and its three volumes mounted again. Run B was
  accepted — `run authorised: drive serial 00000S7CLNJ0WC02266P` at 15:11:21.263, and the helper's
  `acquired disk10: claim held, /dev/rdisk10 open exclusively (fd 4)` and `acquire GRANTED for pid
  5999` at .913 — so the claim from run A was not still held.
- **3.7 (g) ✅ — Step 12's 4.4.** At once: the removal callback, `device loss: nothing was in flight,
  ending the run now` and `run ended: deviceLost` all at 15:13:05.791, and `paused → finishing on
  deviceLost` at .792 — no three-second wait.
- **3.7 (h) ✅ — 4.7.** The sentence on screen, word for word, in the user's screenshot: *"The run was
  **paused** when the drive left, so no chunk was part-way through anything and nothing was left
  half-written. Every chunk the run had reached was written back and verified before it stopped."*
  The report has no **Drive left at** or **While** rows: route (b) knows only that the drive went.
- **3.7 (i) ✅ — 4.8.** *"Yes, 4 TB T5 EVO is gone, four drives listed"*; the log's `discovery found
  4` at 15:13:06.290, 499 ms after the drive went, and again at .314 once discovery resumed.
- **The second reconnect.** *"Drive reconnected, 4 TB T5 EVO is back in the list"*: `connected
  disk10` at 15:20:59.440, and at 15:21:10 the serial resolved to `disk10` with the same layout as
  at 14:23:15 and all three volumes mounted — the fixture came back whole from both pulls.

Read with the transcript:

- **`changes 5`** is the watcher's first line and four changes — run A's hold and its release at
  the pull, run B's hold and its release at the Pause. The pull from the paused run added none.
- **The 14:49:00 heartbeat** fell 60 s after the first line, one second before `holding` at
  14:49:01.042, and read `held 0  (unchanged)`, which was true when it was sampled.
- **`samples 6785`** in 2241 s is 3.0 a second, as F2's wording says.
- **`finished → starting`** at run B's Start, as at chunk 2's 2.7: a closed report leaves the state
  at `finished`, and Start is accepted from it by design.
- **`device change ignored while a run is active; will refresh when it ends`**, at 14:59:07.997 and
  15:13:06.292, each followed 20–25 ms later by `discovery resumed` and a second `discovery found 4`:
  discovery is frozen while a run is active, the FR-DEV-8 path refreshes it once on the loss, and
  the device-set change that arrives while it is still frozen is refreshed when the run ends
  (`DeviceDiscovery.swift`). By design, not a finding.
- **Route (a) saw the drive go first**: the helper's `read of 4194304 bytes at offset 73467428864
  failed after 0 bytes: errno 6 (Device not configured)` at 14:59:07.617, 1 ms before the app's
  removal callback — the order Step 12 measured on 2026-09-09.

Checked, and not findings:

- **Other processes held the idle-system type at points in the walk** — `powerd`'s *"Powerd -
  Prevent sleep while display is on"*, `sharingd`'s *"Handoff"*, the Claude app's
  `NoIdleSleepAssertion` *"Electron"* and `backupd-helper`'s *"Mutexed Backup Block"* — and
  `WindowServer` held `UserIsActive`, and `PreventSystemSleep` *"com.apple.WindowServer.PUIDS"* for
  the instant of the wake at 14:56:32. None is the app's, and every reading here is matched on its
  pid.
- **3.2 shows that the display slept and the run went on, not that the assertion kept the Mac
  awake.** The system-sleep timer was 180 minutes, so the Mac would not have idle-slept in 2 minutes
  49 seconds whatever the app held; that half is 3.4's subject, not walked. The power log has no
  `Sleep`, `Wake` or `DarkWake` line between 14:45 and 15:30, against 437 in the whole log, which
  reaches back to 2026-09-21 — the latest a `Wake` at 2026-09-28 09:36:29 — the positive control,
  read at 16:07:59. The count is by the category column exactly: matched on its first word, it is
  652, because it also takes the 215 `Wake Requests` lines, which are requests, not wakes.
- **The power log's lines for the app's assertions are not a full record**: it has no `Created`
  line for run A's hold — only a `Summary` when the display went off, 00:04:42 in, and the
  `Released` at 14:59:07 — and no line at all for run B's 46 s hold; the whole log has two lines for
  pid 5999. The watcher and the app's log are this chunk's instruments, and the power log
  corroborates them where it has a line.
- **Run B's Done logged nothing**: the app's subsystem has no line from 15:13:10 to 15:19:26, across
  it; the same query over 15:13:05–15:13:07 prints 15, the positive control.

The helper's side: run A — bounded 1 GiB calls on `disk10` from block 0, 68 of them complete, 17,408
chunks, then the call from block 142606336 ended at block 143491072 after 109 chunks: 17,517 in
all, as the report shows. Run B — five 1 GiB calls from block 0 complete, then the sixth, from
block 10485760, paused at block 10633216 after 18 chunks: 1,298 in all, as its report shows. All 75
calls ended with no failed block range — 73 of them complete, 256 of 256 chunks — and every one
reported the cache bypassed. The reports' figures are the helper's last metrics lines rounded —
351 / 418 / 124 MB/s for run A, 347 / 415 / 122 for run B — and both log
`0 failing block(s) in 0 range(s)` and `verify result qualified: false`, which means the bypass
was confirmed, not a caveat.
