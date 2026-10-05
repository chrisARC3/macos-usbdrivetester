# Step 11 — the human checklist

> **STEP 11 CLOSED 2026-09-05.** Every chunk here was walked and passed, and the step's own
> verification gate was re-run against the v14 daemon the same day. **This file is now a record
> rather than a worklist.** ⚠️ **Its passes do not transfer.** If later work re-opens anything Step
> 11 built, re-walk the chunks that work touches rather than trusting these dates — checklist 6.3
> passed on 2026-08-18 and was silently broken four days later by a change in another step, and
> nobody noticed for thirteen days.

> ⚠️ **2026-09-19: four parts of this file are OWED a re-walk on the Xcode 27 build** (user decision,
> at the move to Xcode 27's chunk 4): ✅ **chunk 9**, the window's size — **walked 2026-09-21/22 and
> passed, lapsed 2026-09-24** by its own clause, when item 6's fix moved every floor it measured,
> and **items 2, 3 and 6 re-walked and passed 2026-09-25**, see its own box; ✅ **chunk 11**, the
> report as a sheet — **walked 2026-09-23: ten of eleven items passed and item 6 failed; fixed
> headlessly 2026-09-24; item 6 re-walked and passed 2026-09-25**, see its own box; ✅ **chunk 16**,
> ⌘Q under every modal — **walked 2026-09-25 and passed, all nine items**, see its own box; and ✅
> **item 6.3**, Cancel and Quit — **walked 2026-09-25 and passed, in its hardest form and its
> standard one**, see the item. **Every re-walk of 2026-09-25 ran on the build that carries the fix
> — installed 2026-09-24 18:01:53 from `77275be` and proved by content. All four parts are walked.**
> 9.1, 9.4 and 9.5, and chunk 11's other ten items, were
> not re-walked on that build (user decision, 2026-09-25): their passes are facts about the build
> installed 2026-09-19, and the fix changed only the two lines that set the list's floor. Every pass in this
> file was made with an Xcode 26.6 build on macOS 26, and these four are framework behaviour —
> window sizing, sheet presentation, key equivalents under a modal — that no test and no render
> reaches. **Chunk 9 was also the calibration for `window-fit-check.sh`'s probe**, which stopped
> measuring on Xcode 27 / macOS 27 at the move's chunk 4 and was fixed at **chunk 4b** the same
> evening: it measures **613 pt** again, by driving an `NSHostingView` in a probe window, and chunk 9
> was the only thing that could say whether the shipped `Window` scene agrees (`PROGRESS.md`, *The move
> to Xcode 27*). ✅ **It agrees to 2 pt** — the shipped window is pushed to **615 pt** at Start, against
> the probe's 613 — **and the calibration also found that the probe reports two different quantities
> and the gate uses only the larger.** See chunk 9's box. Until each is
> re-walked, its pass here is a fact about the Xcode 26 build only. The rest of this file is covered
> on the new build by the suite, the four hardware gates and the renders, or gets exercised again by
> Step 13's walk. **Each re-walk fills in its own Walked line and edits this note.**
> *(2026-09-24: the probe's 613 is **614** since item 6's fix, and 1152x720 is no longer
> maintained — see below. 2026-09-25, on the build that carries the fix: the shipped window was
> pushed to **614** at Start, the probe's figure exactly, and held at **615** while the run went on —
> see chunk 9's box. Later that day **615 became the spec**, by user decision.)* *(2026-09-30:
> macOS 27.0.1 (26A434), a point release, lapses none of these passes — user decision the same
> day, `CONSTRAINTS.md` §2 — and the clauses below that name Xcode or macOS were reworded to say
> so.)*
> ⚠️ *(2026-10-05: **every re-walk pass of 2026-09-25 here has lapsed** — Step 15's chunk 5
> installed the v16 build at 09:40 from `cae1d91`, and each clause names a different installed
> build. **And one had lapsed earlier, unrecorded — a finding, reported not fixed:** chunk 16's box
> names `RunController` and `RunControllerWiring` (its item 4), and Step 15's chunk 4, `5bc6a43`,
> edited both on 2026-10-01 — the run ID handed to `prepare` and `acquireDevice` — while that
> commit and `PROGRESS.md` said every pass recorded against the 2026-09-24 install stood until
> chunk 5's. No other clause here names a file chunks 3 or 4 edited *(⚠️ wrong, found 2026-10-05
> 11:05 — a second finding, reported not fixed: chunk 9's two boxes name **the probe**, and
> `5bc6a43` edited `tools/ui-probe/main.swift` — its two `prepare` closures took the run-ID
> argument, `{ _, done in` to `{ _, _, done in`, and nothing it measures. So 9.2, 9.3 and 9.6 had
> lapsed at chunk 4 as well, by the letter of their clause; the sentence was checked against file
> names and the clause names the probe by role)*. Which of these four parts
> chunk 5 re-walks is **not yet decided**: the 2026-10-04/05 walk through the checklists covered
> Steps 12 and 13 only. `PROGRESS.md`, *Chunk 5*.)*

> ⚠️ **2026-09-24 — chunk 11's item 6 diagnosed and fixed headlessly; nothing re-walked yet.**
> *(✅ 2026-09-25: re-walked — 11.6, 9.2, 9.3 and 9.6 passed on the build that carries the fix, and
> the figures below read as predicted: 600, 588 and 614. The running floor read 615, the higher of
> its two predictions, so on hardware the worst case is 615 while a run is on rather than 614 as it
> starts — reported, not adopted, and then adopted by user decision the same day. See chunk 9's
> and chunk 11's boxes.)* The
> window could be dragged **46–57 pt below the height its content fits**: `WindowMetrics`'s
> `deviceListFloor` asked the drive list's table for 46 pt and the table held about 104, and on
> Xcode 27 / macOS 27 the window drags to the declared minimum, where the Xcode 26 build had stopped
> at the table. In that band the root stack is taller than the window, and the report sheet takes
> its size from the root stack — so it overhung. The floor is now **104**, capped at the list's own
> height, and the declared minimum is the measured one in every row the gate checks: a **600 pt**
> window with two or more drives, **588** with one, and **614** while a run starts, the new worst
> case. Two lines of app code, in `WindowMetrics` and `DeviceListView` — both named in chunk 9's
> and chunk 11's **Invalidated by** clauses. The figures under chunk 9's box and items 9.2, 9.3,
> 9.6 and 11.6 are **predictions** until those are walked on the build that carries the fix. The
> account is in `PROGRESS.md` and in `nonfunctional-requirements-usb-drive-tester.md`'s 2026-09-24
> amendment, which also retires 1152x720.

> **The absolute paths in this file were rewritten on 2026-09-04.** This repository lives on a
> **removable volume** and moved from `/Volumes/1TB_Samsung/…` to `/Volumes/1TB_UGreen/…`, which
> silently turned two pasteable commands — checks **12.2** and **13.7** — into paths that do not
> exist. If a command here fails with *no such file or directory*, that is the reason: re-derive
> the root with `git rev-parse --show-toplevel` and paste that instead. The two gate scripts that
> printed the same path in an error message now derive it rather than carrying it as text.

**CHUNKS 1–7 PASSED IN FULL.** 1–7 on 2026-08-18 (increment 5); **7.4 on 2026-08-24** and **7.5 on
2026-09-01**, both added by increment 8 for FR-RPT-4's "stopped by user". Replaces the nine-item
list in `progress/step-14.md`, which increment 5 made partly unrunnable.

> ⚠️ **This line said "7.4 and 7.5 … are new and unrun" until 2026-09-01, and 7.4 had been done
> since 2026-08-24** — PROGRESS said so, and so did the owed-list four paragraphs below. The same
> defect the warning box at the end of this header describes, in the paragraph directly above it.
> **A summary that disagrees with the body is worse than no summary.**

**CHUNK 8 PASSED IN FULL** — items 1–2 on 2026-08-19, items 3–7 on 2026-08-24. Item 3 had been run
before the 2026-08-19 reversal rebuilt both controls to one rule, so its result was superseded and
it was re-walked. Added by increment 6, and it is the only cover the dropdown's and the
confirmation's wiring has: mutation M15 — *the dropdown does nothing at all* — survives the entire
suite, because no test drives a SwiftUI binding. **It was what closed Step 11's verification gate**
(BUILD-PLAN, item 5).

**CHUNK 9 PASSED IN FULL.** 9.1–9.6 at the keyboard on 2026-08-20; **9.7 was deleted on 2026-08-22
rather than walked**, because the sentences it counted no longer exist.

**CHUNK 10 PASSED 2026-08-22 AND WAS THEN DELETED** — it covered the Restart control, which was
removed the same day. See that chunk's own heading.

**CHUNK 11 PASSED IN FULL** — 11.1–11.4, 11.7 and 11.11 on 2026-08-22, 11.5, 11.6, 11.8, 11.9 and
11.10 on 2026-08-23. Added by increment 8 for the report's move from a window to a sheet, and it is
the only cover that surface has at all: no test drives a SwiftUI view, and the two lines telling the
model a run produced a report live in a file that needs a helper and a drive to construct. **11.11
found a defect**, since fixed and re-checked.

> ⚠️ **2026-09-23: that pass is a fact about the Xcode 26 build, and the Xcode 27 re-walk did not
> repeat it.** Ten of the eleven items pass on the new build. **Item 6 failed**: below about 600 pt
> the sheet is taller than the window leaves room for, and at the 542 pt idle floor it hangs 20 pt
> below the window's bottom edge. Owed, by user decision; see the chunk's own box.
> *2026-09-24: fixed headlessly — the window can no longer be dragged below the height its content
> fits — and not re-walked. The fix lapses the other ten passes too, by the chunk's own clause.*
> ✅ *2026-09-25: item 6 re-walked on the build that carries the fix and **passed** — the sheet 24 pt
> inside the window at every size taken, 588 to 1304 pt. The other ten were not re-walked (user
> decision), so their passes are facts about the build installed 2026-09-19.*

**CHUNK 13 PASSED IN FULL — ALL EIGHT ITEMS, 2026-08-27/09-01.** Added 2026-08-27 by increment 9, for the launch-time helper gate.
It is the only cover the gate's *presentation* has: two mutations survive the whole suite by
construction (the `.sheet` modifier deleted, and the trigger never called), both declared in advance,
because the wiring sits in the one file no harness compiles. Its items 3, 4 and 7 induce states and
**must be asked about first**; none of them touches a drive.

**It found five defects**, every one of them in the seam between the model and the screen: the
gate's Quit button dead (and ⌘Q dead under every sheet in the app, which turned out to be the real
cause of increment 5's check 6.1 — fixed app-wide by increment 12, and walked as chunk 16); no re-check on returning from System Settings; the
`versionMismatch` remedy inert in the one state where it is load-bearing; a second press accepted
mid-remedy; and the readiness banner stating something false. Two of those surfaced only because an
item was changed to require a button be **pressed** rather than **present**.

**CHUNK 12 PASSED IN FULL — ALL EIGHT ITEMS, 2026-08-25.** Items 1–4 passed hard: six drives read at the
keyboard, three distinct speeds, every one matching `usb-speed-check.sh`'s independent read of
the registry, and the number then followed a drive across a port change. **That is the whole of the
cover the registry read has**, so both mutations that survived all 1025 tests — a misspelled key
and a pane wired to a constant — are now dead by measurement rather than by argument. Items 5–8
then confirmed the deletion cost nothing and the report kept what it was supposed to keep. Added
2026-08-23 for the link speed's move to the Selected device
pane. Its first four items are the only cover the new registry read has: the mutation round showed a
misspelled key and a pane wired to a constant both survive the entire 1025-test suite, because
`IOKitDeviceEnumerator` needs hardware and nothing in the suite has any.

**CHUNK 14 PASSED IN FULL — ALL SEVEN ITEMS, 2026-09-02.** Added the same day by increment 10 and
walked the same day, against a build installed at 13:22 — **the walk was blocked once and rebuilt
for**: the app in `/Applications` was from 2026-09-01 15:24, before increment 10 existed, so the
first three items would have been walked against the build the chunk was written to test the
replacement of. Item 4 is the only cover the Full Disk Access modal has anywhere: an `.alert` cannot
be rendered by `ui-probe`, so that the dialog appears, that its two buttons are in the right order,
and that the remedy actually opens System Settings are reachable by a person and by nothing else.
All five of its bullets passed, including the two no test reaches — the remedy opened the pane, and
**no volume had been unmounted**, which is the ordering the whole placement decision rests on.

**It found no defects in the product.** It stalled once, on the *instruction* rather than the app:
item 4's fourth bullet was relayed to the walker as "press the remedy button", which is
`RunFailureRemedy`'s type name and appears nowhere on screen. This file's own line 878 says "press
**Open Full Disk Access Settings…**" and is correct; the paraphrase was made in conversation. The
walker stopped rather than guess, which is the right response to an instruction naming a control
that is not there. **Recorded because the lesson is this file's own**: internal vocabulary must not
reach a person at a keyboard, in the file or in any restatement of it.

Two questions raised while walking it, both answered from source and neither a defect —
"Read runs at about twice Write" is a counting identity of the cycle rather than a solid-state
claim, and the `Medium` row appears exactly when the USB bridge publishes `Medium Type`. Both
produced comment fixes; see `DiscoveredDevice.mediumType`, whose old wording invited the wrong
inference.

**That first question outlived its answer.** The 2:1 was a counting identity *because both rates
divided by running time*; asked again on 2026-09-02, it led to FR-METR-1 being amended, and Read
and Write no longer share a denominator or a ratio. On the 4 TB T5 EVO the panel now reads Write
**above** Read. The answer given here was correct for the build it was given about.

> **NOTHING IS OWED IN THIS FILE, as of 2026-09-04.** **Chunk 16 passed in full — all nine items**,
> the day it was written, and the three re-walks increment 12 owed elsewhere have all passed:
> **6.1** (the item is greyed), **11.7** (⌘Q discards the report and quits, closing the question that
> item parked on 2026-08-21) and **6.3** (Cancel and Quit, against the fix). **13.4** gained a line
> and did not need re-walking.
>
> **The walk found one defect in the product and three in this file**, which is a ratio worth
> noticing in a chunk written the same morning:
>
> * **`Cancel and Quit` did not quit** — since increment 8, thirteen days. Found by 16.5, fixed by
>   `8f6be8e`. **6.3 has been re-walked and passes**, in the hardest form of the state.
> * **16.4's induction did not work, and neither did 7.8's**, which it was copied from: pulling a
>   selected drive now moves the selection and Start runs a good test on the next drive. Both
>   corrected to pull it while the pre-run dialog waits.
> * **16.7 was unwalkable** — it asked for a reading off a log line that carried no inventory.
> * **16.8 was unusable** — 112 false errors in six hours, all from the test host. The fix is in the
>   app: the backstop no longer fires when the termination is stubbed.
>
> **It also settled a belief this app had acted on for three increments without measuring it**: a
> SwiftUI `.alert` on macOS *is* a window-modal sheet — `1 sheet(s) [_NSAlertPanel]` — so the count
> of **five** surfaces is right and the increment plan's "three sheets" was wrong.
>
> **This block was rewritten in the same commit as the walk**, which is what the ⚠️ four paragraphs
> below demands and what it has caught this file failing three times.
>
> **Everything else was walked and passed.** Chunk 15 was written and walked on 2026-09-03 — five
> items, all passed, **no defect in the product and one in this file** (its item 4, deleted mid-walk;
> see below).
>
> **The two hardware gate scripts that had been owed since increment 8 were run and passed the
> same day** — `xpc-concurrency-check.sh` 0 failures, `retention-cycle-check.sh` 15/15 over the
> whole device. They are not checklist items and live in `BUILD-PLAN.md`; "nothing is owed" above
> means nothing on *this* list.
>
> ⚠️ **It used to add "and as of 2026-09-03 nothing is owed on that one either", and that was wrong**
> — corrected 2026-09-04. It counted Step 10's three gates and forgot Step 11's own,
> **`run-control-check.sh`**, which last ran 2026-08-24 against a **v12** daemon. The protocol went
> to **v14** in increment 11, on 2026-09-03, so the sentence was false the day it was written.
> **Step 11's verification gate rests on that script for items 2, 3 and the helper-side half of 5,
> and cannot close until it is re-run.** Nothing on *this* list is affected.
>
> ✅ **Discharged 2026-09-05** — `run-control-check.sh` was re-run against the **v14** daemon and
> passed, so those three now stand; **Step 11 closed the same day.** The warning above is kept rather
> than deleted: the miscount is the lesson, not the state it happened to describe.
>
> ⚠️ **This line said "NOTHING IS OWED" until chunk 15 was written, on 2026-09-03** — which was the
> third time round this loop, and chunk 16 on 2026-09-04 is the fourth. A new chunk makes the summary false the moment it is added, and
> walking one makes it false again; the summary and the body are edited together, every time, or
> this file resumes lying about itself. Chunk 15 was added for increment 11 and FR-METR-1's
> amendment. **Its item 1 — the v12/v14 mismatch walk — was deleted on 2026-09-03 without being
> walked**: `install-app.sh` ran before it and the daemon restarted from the new binary, taking the
> only free fixture with it. See the chunk's own header for what still covers that guard and what
> does not.
>
> **A second item was deleted from chunk 15 on 2026-09-03, mid-walk: its item 4, the idle panel's
> em dashes.** That one was not merely unwalkable — it was **wrong about the app and inverted**.
> It asked for three rate rows before a run, where the panel shows a placeholder and no rows at
> all, and the state it described is a fixed defect: it would have passed on the broken build and
> invited a false failure report on the correct one. The walker caught it at the screen. Old items
> 5 and 6 are now 4 and 5. **Chunk 15 therefore has five items, and two of its original seven were
> deleted before either could be walked** — a rate worth noticing in a chunk written to close a
> requirement change.
>
> Four items elsewhere in this file went stale and were corrected on 2026-09-03: **2.3**, **7.2**
> and **13.7** named the `Covering` row, which increment 10 deleted on 2026-09-02 without updating
> this file, and 2.3 additionally asserted that Activity Monitor **agrees** with the panel, which
> FR-METR-1's amendment reversed. **14.5 and 14.6 are left as written** and annotated at their
> chunk: they are a record of a passed walk, not a live procedure, and chunk 15 covers the same
> ground against v14. A checklist that instructs a walker to verify something false produces a
> confident failure report against a correct build, which is worse than having no item at all.
>
> Chunks 1–13, and the last three items to close among them on 2026-09-01: **chunk 13** in full,
> **item 7.5** — a whole-device run on the
> 125.8 MB thumb drive (serial `2211190533300386001515`), 30/30 chunks in 39 s, reported `Completed`
> with no range caveat, exported and compared — and the **8.3 recheck**, the sentence confirmed
> unconditional and in its new place above the I/O size row, before a run and while paused.
>
> 7.5 got more than it asked for: a stopped run ten minutes after the completed one, same drive,
> so the wording was seen to **change** rather than merely to read correctly once.
>
> Chunk 10 was walked, passed, and then deleted along with the control it covered.
>
> **This claim was checked against the body before it was written** — which is the discipline the
> box below exists to enforce, and which the header of this very file had failed as recently as the
> paragraph about 7.4.
>
> ⚠️ **This line read "Everything else in this file has been walked" until 2026-08-24, and it was
> false** — chunk 8 items 3–7 were unrun the whole time, and this file's own header said so four
> lines above. The sentence predates the docs pass of 2026-08-23, which carried it forward and
> **bolded it** without reading the chunk it contradicted. It was caught by walking Step 11's
> verification gate, whose item 5 is exactly chunk 8. **A summary that disagrees with the body is
> worse than no summary**, because it is the part people read.

## Why this exists, in one paragraph

It found **three defects that 964 tests could not reach**, in a single pass, after the suite,
three zero-warning clean builds, 56 renders, 13 type-checked gate clients and a 9-of-10 mutation
score had all gone green. Every one of them lived in the seam between the model and what is
actually on screen, which is the one place this project's instruments do not look.

| Found in | Defect |
|---|---|
| 4.2 | **Pause blanked the whole measurements panel.** `paused` was grouped with the states that have nothing to show; it is the one state where a claim is held and the figures are this run's. Fixed by splitting `isMeasuring` into `hasLiveSession`. |
| 6.2 | **⌘Q during a run ended the run before the user answered.** `mayIssueNewWork` was one flag answering two questions — may Start begin (no, a quit is pending) and may the running run continue (yes, nobody has chosen yet). `RunSequencer` consulted it before every call, so *presenting* the dialog answered it. Fixed by adding `mayContinueRun`. |
| 7.2 | **The report window and the exported file disagreed.** The advertised-rate guidance was removed from the export and left on screen; the new definition paragraph was added to the export only. Two literals, already drifted — the exact defect `HonestFraming` was written to end. Fixed by `ThroughputFraming`, one definition, two surfaces. |

None of these are subtle once seen. All three survived everything automated.

## Running it

Chunks are run **one at a time**, reporting back between each. That is not ceremony: the previous
attempt ran the nine items in one go, hit "numerous problems", and stopped — and the problems were
never enumerated. Small chunks make a partial pass reportable.

Non-destructive chunks come first. Chunks 2, 4–9, 11, 12 and 14–16 start a run; 3 asks for one
that must fail before it writes, and 1 and 13 start none (10 is deleted) — and **14 also revokes a
permission**, reversibly, which is why its item 4 says to ask first.

> ⚠️ **2026-09-26: this said *"Only 2, 4, 5, 6, 7, 8 and 14 start a run"***, its wording of
> 2026-09-02, when chunks 9, 11 and 12 already existed; 15 and 16 came after it. Chunks 9 (item
> 3), 11, 12 (items 7 and 8), 15 and 16 (items 4–7) start runs too. Found 2026-09-26 while weighing
> chunk 16's heading, which had the same fault, and corrected the same day by user decision
> (`PROGRESS.md`, *Owed* (j)).

### Prerequisites

* The **4 TB T5 EVO** (serial `00000S7CLNJ0WC02266P`) connected. **Required, not optional** — it is
  the only multi-volume drive here, and half these checks are about the restore set. Its three
  mounted volumes:

  ⚠️ **The nodes below are illustrative and were stale by 2026-08-24.** They read `disk8s2`,
  `disk8s4` and `disk5s1` from a session in which the EVO was `disk8`. It is `disk5` today, and
  **`disk8` now names the 22 TB Seagate backup volume** — which is exactly the substitution
  `scripts/lib/device-identity.sh` exists to refuse. **Identify the drive by its serial, in the
  app's own device pane, every time.** Re-derive the nodes with `diskutil list` if you need them;
  never carry one over from this table.

  | Volume | Node (2026-08-24) | |
  |---|---|---|
  | `Vol_ExFAT` | `/dev/disk5s2` | direct partition |
  | `Vol_HFS` | `/dev/disk5s4` | direct partition |
  | `Vol_APFS` | synthesized as `Container disk4` | **from `disk5s3` — not a direct partition** |

  `DADiskUnmount` with `kDADiskUnmountOptionWhole` unmounts direct partitions only and **reports
  success, with no dissenter, having skipped the APFS volume.** `Vol_APFS` is what catches that.
  The 1 TB scratch drive cannot: one volume, empty restore set.

* The app installed to `/Applications` (`scripts/install-app.sh`). **If the helper changed, the
  daemon must be restarted** — copying files does not reload it, and two hardware gate runs on
  2026-08-18 measured stale code while returning plausible numbers. `install-app.sh` now says so.

* A log stream, left running throughout:

      /usr/bin/log stream --predicate 'subsystem == "com.arc3solutions.USBDriveTester"' --info

  Most checks are read off a **log line**, not off the look of a dialog. That is the main thing
  wrong with the old list: "still the full warnings" asked the tester to judge an appearance, where
  `pre-run prompt raised: full warnings` is unambiguous.

## The chunks

### 1 — Start raises the gate, and Cancel is inert *(no writes)*

1. **Start** raises the dialog → `pre-run prompt raised: full warnings; drive serial 00000S7…`
2. With the dialog open, `mount | grep -E "disk8|disk5"` still shows **all three** volumes.
3. **Cancel** → `pre-run prompt dismissed: cancel; run issued: false`, still three volumes.

Covers three of the increment-5 mutations the suite cannot reach. Item 2 is the one the old list
had no equivalent of, and it is what proves Start claims nothing.

### 2 — Start owns unmount → acquire → run *(writes)*

1. **Proceed** → `run issued: true`, then `run authorised: drive serial …`
2. **All three** volumes unmount, `Vol_APFS` included. If `Vol_APFS` alone survives, stop: that is
   the `…Whole` defect.
3. The panel shows `Read` / `Write` / `R-W-R-C`. **Activity Monitor will NOT agree, and must not**:
   expect it to show roughly 245/122 against the panel's ~376/419 on the 4 TB T5 EVO. Write above
   Read is correct — that drive writes faster than it reads. `R-W-R-C` around a third of both is
   correct on a clean run. Read the paragraph under the figures and check it says so.

   *Rewritten 2026-09-03. It read "`Read` / `Write` / `Covering`, with Read ≈ 2 × Covering, and
   Activity Monitor agrees" — every clause of which is now false: `Covering` was deleted from the
   panel in increment 10, and FR-METR-1's 2026-09-02 amendment made the disagreement with Activity
   Monitor the requirement. Left standing, this item would have produced a confident failure report
   against a correct build.*
4. **Stop** → every volume back.

### 3 — the abort path *(writes)*

Hold a volume open first: `touch /Volumes/Vol_HFS/.unmount-block && tail -f …`

1. **Proceed** → no run; an alert explains the unmount failed.
2. The alert ends *"…have been asked to remount, so the drive should be back as it was."* The other
   form, *"⚠️ Some volumes … could NOT be remounted"*, is a **pass for honesty** and a real failure
   of the restore — record which.
3. All three volumes back, **and `mount | grep disk8s1` is empty.** EFI was never mounted and the
   rollback must not mount it. Three attempts got this wrong on 2026-08-06.

### 4 — Pause, Resume, Stop *(writes)*

1. **Pause** settles → `run paused and settled at block N`.
2. **The figures stay on screen and stay identical for 60 s.** Two distinct properties: visible
   (the 4.2 defect) and unchanging (the running-time denominator).
3. **Resume** continues, and the rates did not drop.
4. **Stop**, then **Start** a second run — it must actually start. The run-control level is a
   process-wide slot the helper never clears; if Resume or Start does not clear it, the second run
   wedges silently.

### 5 — warning suppression *(one short run)*

1. Tick + **Cancel** → `suppression recorded: false`, and the next raise is still `full warnings`.
2. Tick + **Proceed** → `suppression recorded: true`; the next raise is
   `brief confirmation (warnings suppressed)`.
3. Survives a relaunch.
4. Diagnostics ▸ **Show pre-run warnings again** restores `full warnings`.

Item 1 is a mutation the suite cannot reach: the checkbox is local state, reset per raise,
deliberately not bound to the persisted preference.

### 6 — the quit boundary *(writes)*

1. **Open the app menu — the bold one named *USBDriveTester* — while the dialog is up.
   *Quit USBDriveTester* is GREYED OUT**, and ⌘Q does nothing. Cancel the dialog, and ⌘Q quits immediately.

   > **Rewritten 2026-09-04 by increment 12; the behaviour it asks for changed, the decision behind
   > it did not.** This item used to read *"⌘Q and File ▸ Quit do nothing while the dialog is
   > open"*, and that was walked and passed — but what it was describing was a **silent** refusal:
   > `NSApp.terminate(_:)` is a no-op while a sheet is attached, refused before
   > `applicationShouldTerminate`, so `QuitPolicy` was never consulted and nothing was logged. The
   > item was recording an accident that happened to match the decision.
   >
   > The refusal was re-affirmed on 2026-09-04 — the pre-run dialog is the last thing between a
   > selected drive and a write, and a keystroke meaning "leave" must not answer it. What changed is
   > that the app now *decides* to refuse instead of being unable to try, and **says so by greying
   > the item**. So the greying is the whole of what is new here, and it is the part no test can
   > see: nothing automated compiles the file the `.disabled` lives in.
   >
   > If ⌘Q quits from here, that is a serious finding — not a cosmetic one.
   >
   > ✅ **RE-WALKED AND PASSED 2026-09-04** against increment 12: the item is greyed, ⌘Q does
   > nothing, and Cancel then ⌘Q quits.
   >
   > ✅ **RE-WALKED AND PASSED 2026-09-25 on the Xcode 27 build**, installed 2026-09-24 18:01:53
   > from `77275be`, with chunk 16 — its 2026-09-25 box has the build, pids and drives. Greyed, and
   > ⌘Q did nothing, with the dialog up for the 125.8 MB thumb; *Cancel* logged `run issued: false`
   > at 16:41:11, and ⌘Q then quit at 16:41:20. **Invalidated by** that box's clause.
2. ⌘Q during a run **asks**, and **the run keeps going underneath the dialog**. *Continue Testing*
   resumes as if nothing happened.
3. *Cancel and Quit* stops at a chunk boundary, releases, **and the app actually goes** — every
   volume back, EFI not mounted. Watch for the log line `wind-down finished: … — terminating now`
   followed by `terminate requested: … disposition=quitImmediately`. **Neither line appearing while
   the app stays up is the defect below.**

   > ⚠️ **2026-09-26: the EFI half needs a drive with an EFI slice — the 1 TB scratch T5**,
   > `12345686DAA9`. The 125.8 MB thumb has none, so on the thumb *"EFI not mounted"* passes
   > without anything having been observed. A full 6.3 is therefore two runs: the **hardest form**
   > on the thumb, whose run is short enough to finish under the confirmation, and the **standard
   > form** on the scratch T5 — how it was walked on 2026-09-25, below. Found that day; this note
   > added by user decision 2026-09-26 (`PROGRESS.md`, *Owed* (k)).

   > ⚠️ **THIS ITEM PASSED ON 2026-08-18 AND WAS BROKEN FOUR DAYS LATER, AND NOBODY LOOKED AGAIN
   > FOR THIRTEEN DAYS.** Increment 8 made the run report a **sheet** on 2026-08-22. A stopped run
   > raises the report before it releases the drive, so from that day the wind-down asked AppKit to
   > terminate with a sheet attached — and `NSApp.terminate(_:)` is refused *before*
   > `applicationShouldTerminate` while one is. *Cancel and Quit* dismissed the dialog, stopped the
   > test, released the drive, and **left the app running**.
   >
   > Found by walking chunk **16.5** on 2026-09-04, thirteen days and four increments later. Fixed
   > the same day: the wind-down now takes every modal down through SwiftUI and terminates on the
   > following turn, the same mechanism ⌘Q uses, and `QuitSequence` — which had emitted nothing
   > since it was written — now logs every step. `theWindDownDiscardsTheReportBeforeItTerminates`
   > is the regression test.
   >
   > ✅ **RE-WALKED AND PASSED 2026-09-04** against the fix, in the hardest form of the state: the
   > confirmation was left up until the run finished underneath it, so the report was raised behind
   > it, and *Cancel and Quit* still took both down and quit. That is the defect's own scenario plus
   > the modal that caused it.
   >
   > **The lesson is about this file, not about the app.** An item that passes is not a fact about
   > the build that comes after it. Increment 8 changed the presentation of the very thing this
   > item quits out of, and nothing re-ran it, because "chunks 1–7 passed in full" reads like a
   > property rather than a date. **Walk 6.3 again after any change to what a finished or stopped
   > run puts on screen.**
   >
   > ✅ **RE-WALKED AND PASSED 2026-09-25 on the Xcode 27 build, in both forms** — installed
   > 2026-09-24 18:01:53 from `77275be`; chunk 16's 2026-09-25 box has the build, pids and drives.
   >
   > * **The hardest form, on the 125.8 MB thumb**, `2211190533300386001515`: the confirmation left
   >   up while the run finished underneath it at 17:43:43 — 30 of 30 chunks, no failed blocks — and
   >   the report raised behind it. *Cancel and Quit* at 17:44:12.417 found `3 window(s), 2 sheet(s)
   >   [_NSAlertPanel, SheetPresentationWindow]`, logged `wind-down finished: there was nothing to
   >   release — terminating now` and, 0.3 s later, `terminate requested: runIsActive=false
   >   disposition=quitImmediately`, and the app went. `Slice_A` came back and the second slice
   >   still has no volume. The `2 still flagged afterwards` between those lines is expected:
   >   `endSheet(_:)` does not take down a sheet SwiftUI owns, which is why the wind-down goes
   >   through SwiftUI and asks for the termination a turn later (`AppModel.dismissThenTerminate`).
   >   The defect's sign was no `terminate requested` following it.
   > * **The standard form, on the 1 TB scratch T5**, `12345686DAA9`: ⌘Q five seconds into a run,
   >   then *Cancel and Quit* at 19:54:24.248. The helper stopped 11 ms later **at block 1,949,696,
   >   the end of chunk 238** — of the first call's 256, a run going to the helper one GiB at a
   >   time — with 998,244,352 B read, written back and verified and no failed ranges, then released
   >   the drive. `terminate requested: … disposition=quitImmediately` came 0.32 s after the click,
   >   and the app went. `Test_Drive` came back and **EFI stayed unmounted**. *"Nothing to
   >   release"* is the designed reading here too: the run's own stop releases the drive before
   >   the quit sequence starts, and the sequence is built with nothing to release
   >   (`QuitSequence(release: nil)`, `AppModel.swift`). No sheet was attached when the wind-down
   >   ran — `1 window(s), 0 sheet(s)`, 11 ms after the run ended — so it is the hardest form that
   >   put the defect's own state in front of the fix.
   >
   > The EFI half of this item cannot be observed on the thumb, which has no EFI partition; the
   > scratch T5 has one, and that is why the standard form ran there. **Invalidated by** any change
   > to what a finished or stopped run puts on screen, or to the quit path — `AppModel`,
   > `QuitPolicy`, `QuitSequence`, `AppLifecycleDelegate`, `USBDriveTesterApp.swift`; by a different
   > installed build; and by any new Xcode or macOS major or minor release, but not a point release *(reworded 2026-09-30, `CONSTRAINTS.md` §2)*.
4. ⌘Q after a run has finished quits **immediately**. 3 and 4 are the pair: one must wait, the
   other must not, and the same code decides both.

**Old item 7 is retired, not skipped.** It asked for a quit pending while the dialog was open, then
Proceed. Increment 5 made Start enter `starting` only when the dialog is *answered*, so no run is
active while it is open and no quit can go pending — while `mayIssueNewWork` stops the dialog being
raised once one has. The guard in `promptDismissed` now defends an unreachable state, exactly as
`step-14.md` predicted: *"the guard alone changes nothing observable."*

### 7 — the report, and reachability

1. **The first run after a fresh launch** names model, serial and capacity. First specifically —
   later runs looked correct even with the original defect present.
2. The report shows `Read throughput` / `Write throughput` / `R-W-R-C speed`, the definition
   paragraph, and the not-graded paragraph — **on screen and in the exported `.md`, identically**.

   *Corrected 2026-09-03. It named `Covering`, which increment 10 deleted from all three surfaces
   on 2026-09-02 — this item went stale that day and was not updated with it. `R-W-R-C speed`
   replaced it in increment 11.*
3. At the app's **smallest** window, with the three-volume drive selected, Start / Pause / Stop are
   all reachable without resizing or scrolling.

4. **A run you STOP reports as stopped** (FR-RPT-4, increment 8). Start a run, let it get a few
   seconds in, press **Stop**. The report's headline reads *"Stopped by the user — the rest of the
   drive was not tested"*, with a **hand** symbol rather than the stop-sign one, and the Run
   section reads **`Range requested`** — not `Range tested` — followed by *"The run ended before
   reaching the end of that range."*

   Then **export it** and read the `.md`: the headline, the row label and that sentence must be
   **identical** on both surfaces.

   > **This is the only cover the report WINDOW has, and increment 8 measured exactly how little
   > that is.** Three mutations to `RunReportView` — dropping a claim sentence, deleting the range
   > caveats, and relabelling the row back to "Range tested" — passed the whole suite, the last two
   > of them against 1,013 tests. The window and the exported file are
   > built by two different renderers from one set of values; the *values* are pinned, that they
   > reach the screen is not. A source comment in that file claimed a `RunReportViewTests` pinned
   > them, and no such file has ever existed.
   >
   > Item 2 is the same check for the throughput paragraphs, and it is what caught the 7.2 defect
   > on 2026-08-18. This item extends it to the outcome and the range, which is where increment 8
   > put new words.

5. **A run you let FINISH reports as completed**, and carries **no** range caveat at all — the
   other half, so item 4 cannot be satisfied by a report that always says the range was not
   reached. A whole-device run is long; the quick version is to confirm the wording changes
   between the two runs rather than being printed unconditionally.

**Item 3 replaces old item 9**, which guarded `Mounting & exclusive access` — deleted by increment
5. The hazard moved rather than went away: it has cost this project three times, most recently
`Acquire exclusive access` being entirely off-screen at the app's own minimum height and reported
as *"Run one bounded cycle stays disabled no matter what I do."* The controls now sit outside any
scroll region **by construction**, and this is the check on that claim.

### 8 — the pre-run controls (increment 6) *(one short run)*

**Added by increment 6, and it is not optional: a mutation survives the whole suite here.** No test
drives a SwiftUI binding, so M15 — *the dropdown does nothing at all* — passes the entire suite.
This chunk is its only cover.

**Items 1 and 2 passed 2026-08-19; items 3–7 on 2026-08-24; item 3 re-walked 2026-09-01.** Item 3
was first run before the 2026-08-19 reversal rebuilt both controls to one rule, which superseded its
result; it was re-walked on 2026-08-24, and again on 2026-09-01 after the sentence moved above the
I/O size row on that same 08-24 — so the 08-24 walk had seen it in its old position.

> ⚠️ **This paragraph read "3–6 below are new and unrun" until 2026-09-01**, four months of walks
> after it stopped being true and while this file's own header said the opposite eight lines up.
> Same defect as the 7.4 line, same file, same day.

1. **Before a run**, change the I/O size to 8 MiB. The log says
   `I/O size changed: 4 MiB -> 8 MiB`. **Start**, and `run authorised: … I/O size 8388608 bytes`
   names the size you chose — not 4 MiB. *(This is M15: a dropdown that moves on screen and changes
   nothing would look identical without the second half.)*
2. **Quit and relaunch.** The dropdown still reads 8 MiB. Set it back to 4 MiB before continuing.

   Confirm it independently of the app, after quitting, by reading the file:

       /usr/libexec/PlistBuddy -c "Print :runIOSizeBytes" /Users/christopherkarr/Library/Preferences/com.arc3solutions.USBDriveTester.plist

   **Do NOT use `defaults read com.arc3solutions.USBDriveTester`** — measured 2026-08-19. A **stale
   sandbox container from 7 July** still exists at
   `~/Library/Containers/com.arc3solutions.USBDriveTester/`, and the `defaults` CLI prefers a
   container path whenever that directory is present. The App Sandbox is **off** for this app (and
   must stay off), so it writes to `~/Library/Preferences/<bundle-id>.plist` — as
   `UserDefaultsPreRunWarningSuppression`'s own header says. `defaults` therefore reads a file the
   app has never written and reports *"does not exist"*, which is indistinguishable from the
   preference genuinely not having been saved. **An empty result is not a finding.**
   `preRunWarningsSuppressed` lives in the same plist and is the cross-check: if it is there, the
   path is right.
3. **Start a run, Pause it.** Wait for `run paused and settled at block N` — the settle, not the
   request. **Both** controls are now dimmed.

   One sentence covers both, not two — there is one rule. This is the row the 2026-08-19 reversal
   created, and the reason it exists is that the *first* build of this increment had the size live
   here and the mode dead, which read as one control being broken.

   > **Moved and reworded 2026-08-24** (user decision). The sentence used to sit *beneath* the
   > controls and appear only while they were dimmed. It now sits **directly above the I/O size
   > row** and is shown **whether or not a run is under way**, because the moment it matters is
   > before the choice is frozen, not after. It reads:
   >
   > *"I/O size and failure handling are fixed once a run starts — stop the run to change them."*
   >
   > Both halves of the old wording presupposed a run — *"the whole run"* means this one, and
   > *"stop it"* has no referent before there is anything to stop — so the move forced the rewrite.
   > **"stop" survived because NFR-USE-5 is Mandatory** and requires the corrective step be named;
   > a tidier rule without it was written first and rejected on that ground.
   >
   > Shortened once before, in increment 7: the original ran to two sentences and cost 15 pt of
   > window height that a 13.3-inch Mac at its smallest scaling does not have.

   **What to check now it is unconditional:** it reads the same, in the same place, before you
   start and while paused — it must not move, change or disappear between the two. A line that
   shifts when a run starts is a layout jump exactly where the eye is.

4. **Try the dropdown anyway** while paused. It should not open. Nothing appears in the log — a
   dimmed control that is never asked cannot refuse.

5. **Resume**, let it run, and confirm both stay dimmed while running. **Stop.**

   > **Nothing about the controls can be checked between the Stop and dismissing the report.**
   > Since increment 8 the report is a sheet sized to the main window less a margin, so it covers
   > the run controls completely. Asked to observe them behind it on 2026-08-24, the walker
   > correctly reported that it could not be done — the instruction had been written from the
   > model rather than the screen, which is the same mistake check 6.1 punished on 2026-08-22.
   > **Check the controls after the dismissal**, which is item 6, and do not add a step here that
   > needs to see through a sheet.

6. With the run stopped, **both controls are live again** and the log shows
   `I/O size changed: …` when you move the dropdown. This is FR-CTRL-8's *"once one has finished"*
   window, and it is the whole of how you change size between runs: Stop → change → Start.

7. **Start that run** at the new size and let it finish, or Stop it after a few seconds. Open the
   report. **`I/O size` names the size you chose**, on screen **and** in the exported `.md`,
   identically.

   This is the only check that closes the loop end to end — dropdown → captured at the gate → passed
   to every call → reported. It needs a person for two reasons: the report body sits in a scroll
   region, so even a render stops at `## Measurements`, and the exported file is a separate surface
   from the window (the 7.2 defect of 2026-08-18 was exactly those two disagreeing). It also
   exercises `IOSizeSelection.label`, which since increment 6 is the single spelling shared by the
   dropdown, the window and the export.

Items 3 and 6 are the pair that matters. Together they are the whole of FR-CTRL-8 as revised
2026-08-19: fixed for the whole of a run, live once it is over. A dropdown that stayed live while
paused would be the shape this increment built first and the user rejected on sight.

Item 7 is what stops the whole chunk being a test of the *control* rather than of the *product*. A
dropdown that moves, logs, persists and is correctly dimmed, but whose value never reaches the
report, would pass 1–6.

### Chunk 9 — the window's size (increment 7)

> **Status: PASSED IN FULL. 9.1–9.6 at the keyboard on 2026-08-20; 9.7 deleted on 2026-08-22**
> rather than walked, because the sentences it counted no longer exist. It was written after the
> rest were signed off, to cover the refusals collapsed in `faf9a93`, and those refusals went with
> increment 8.
>
> ⚠️ **This box said 9.7 was deleted AND "still owed" in the same sentence, until 2026-09-01.** A
> deleted item is not owed; it is gone. Corrected alongside two other stale status lines in this
> file found the same day.

> ✅ **RE-WALKED ON THE XCODE 27 BUILD AND PASSED IN FULL — 9.1–9.6, 2026-09-21 and 2026-09-22.**
> Against the app installed 2026-09-19 10:22:50 from `bcde5f5`'s sources (Xcode 27.0 27A266a,
> `DTXcode 2700`, dylib `422c89d3…`), helper `ac4d5208…`, daemon pid 95762 on protocol v15, and
> `ui-probe` / `window-fit-check.sh` at `d98b658`, re-run 2026-09-21 08:42 to confirm the gate had
> not moved. Five drives attached for 9.1–9.5, two for 9.6. **Invalidated by** any edit to a view
> source, to `WindowMetrics` or to the probe, and by any new Xcode or macOS major or minor release, but not a point release *(reworded 2026-09-30, `CONSTRAINTS.md` §2)*.
>
> **The figures below replace the ones in items 2 and 3**, which were measured 2026-08-20 and went
> stale two days later — the refusal lines under the run buttons were deleted on 2026-08-22, taking
> the worst case from 638 to 613 pt (`progress/step-11.md`). They were never re-walked, so this
> chunk carried pre-deletion numbers for a month. Window **frames** at 640 pt wide, five drives,
> content in the second column:
>
> | | frame | content | what predicts it |
> |---|---|---|---|
> | idle floor | **542** | 510 | `ui-probe`'s `declared=510` — exact |
> | running floor | **557** | 525 | `starting`'s `declared=524` — 1 pt out |
> | idle floor again, run finished | **542** | 510 | back to `declared=510` — exact |
> | at Start, **pushed, not dragged** | **615** | 583 | `overflowAt=581` → 613 — 2 pt out |
>
> **Finding 1 — `--limits` reports two different quantities, and the gate keeps only the larger.**
> `min=` is the max of `declared=` and `overflowAt=`, and this walk shows those answer different
> questions. **`declared=` is the floor a user can drag to. `overflowAt=` is the height AppKit
> pushes the window to** when the content grows underneath it. Both were confirmed against the
> shipped window, to 1 pt and 2 pt. Items 2 and 3 ask for drag floors and are therefore checked
> against `declared=`; the push height is a separate reading, which 9.3 now takes.
>
> **Finding 2 — the worst case is confirmed on hardware for the first time, and it is 2 pt worse
> than the gate says.** 613 predicted, **615 measured**, so every spare figure is 2 pt generous:
> 1440×900 has 185 pt and not 187, 1280×800 has 85 and not 87, and **1152×720 has 5 and not 7**.
> It still fits. **The gate is unchanged and 613 is still its number** — this is a hardware reading
> recorded beside it, not a new floor.
>
> **Finding 3 — `.defaultSize` sizes the frame on macOS 27, not the content.** 9.1 opened at a
> **720 × 700 frame**, which is 668 pt of content against the 700 that
> `WindowMetrics.defaultContentHeight` declares and the 732 pt frame that would deliver it. The
> comment above that constant — *"set to the comfortable height… so nothing scrolls on opening at one
> attached drive"* — is written against a height the app no longer opens at.
>
> **The instrument changed mid-walk, which is why only the second half of it is recorded here.** The
> first readings came from `osascript` against System Events: it needs Accessibility permission, and
> nothing in its answer says whether the number is a frame or a content box — the 32 pt that decides
> whether 542 means *the declared minimum, met exactly* or *32 pt above it*. The readings that stand
> come from AppKit's own autosave, whose fourth field is always the frame and needs no permission:
>
> ```
> /usr/bin/defaults read /Users/<you>/Library/Preferences/com.arc3solutions.USBDriveTester "NSWindow Frame main"
> ```
>
> ⚠️ **It reads stale, and it did.** A drag that changes nothing leaves the previous value in place,
> which is indistinguishable from never having dragged — one round produced three identical readings
> and was recorded INCONCLUSIVE rather than as a measurement. **Drag the window obviously taller
> first and confirm the read follows it**, and every reading after that is known to be live. The two
> instruments agreeing on 542 is also what proved the accessibility number was a frame all along.
>
> ⚠️ **LAPSED 2026-09-24, by this box's own clause** — item 6's fix in chunk 11 edited
> `WindowMetrics` and `DeviceListView`. Every floor in the table above is the window dragged into a
> band its content did not fit, because on this build the window drags to `declared=` and
> `declared=` was 46–57 pt below the content (finding 1 is how that was seen). The fix raises the
> declaration onto the measurement, so **the table is a record of the old build**, and what the
> build carrying the fix should read — frames, 640 pt wide, six drives as in chunk 11's walk — is a
> prediction until walked:
>
> | | frame, predicted | from |
> |---|---|---|
> | idle floor, two or more drives | **600** | `declared=568`, which is now also `overflowAt=` |
> | idle floor, one drive | **588** | `declared=556` |
> | at Start, **pushed** | **614–616** | `starting`'s 582 + 32; the push read 2 pt over the probe on 2026-09-22 |
> | running floor | **~615, or 600** | two predictions, below |
>
> **The running floor is two predictions, and both are declared now.** The probe's `running` state
> is not the shipped one: its metrics panel never shows figures, and it never freezes the drive
> list, so it never shows the frozen-list notice. It declares 568, which is 600. But the shipped
> window's running floor read 557 on 2026-09-22 and again on 2026-09-23 — 15 pt above the probe's
> `running` — and 557 plus the 58 pt the floor rose by is **615**. At 615, a window pushed there at
> Start cannot be dragged shorter at all while the run is on, so **a drag that leaves the frame
> where it is will be the floor**, not the bottom-edge refusal described after item 6. One cost
> follows, and it is cosmetic: on 2026-09-24, at that 557 floor, the frozen list was showing **one
> row** (check (b)'s screenshot), so a run gives up the whole 58 pt too, for a list that did not
> need it.
>
> **Finding 2's spare figures are the old worst case's.** The gate's is **614** now — 104 is the
> real window's table and the probe had read 103 — so 1280×800 has **86 pt** by the probe, and 2 pt
> less if the shipped window reads over it as it did. **1152×720 is not maintained after
> 2026-09-24**, and no figure for it is kept (NFR-USE-9's amendment of that date).

> ✅ **ITEMS 2, 3 AND 6 RE-WALKED AND PASSED 2026-09-25, on the build that carries item 6's fix**
> (user decision: *"re-walk 11.6, 9.2, 9.3 and 9.6"*). Against the app installed 2026-09-24
> 18:01:53 from `77275be` (`68bc16c` records it), re-hashed that morning and again after the day's
> restart to the bytes proved by content the evening before — dylib `e6e6e884…`, stub `bf787e19…`,
> helper `ac4d5208…`, its `deviceListFloor` reading 104.0 — on macOS 27.0 (26A428), protocol v15. The
> app was pid 28582 until the user restarted the Mac at 12:13, then pid 1475; the daemon was pid
> 95762, then 1477. Six drives for the idle floor and the run, two for 9.6, one for the one-drive
> floor. **9.1, 9.4 and 9.5 were not re-walked** (user decision); their passes above are facts about
> the build installed 2026-09-19. **Invalidated by** the same clause as the box above: any edit to a
> view source, to `WindowMetrics` or to the probe; another install; any new Xcode or macOS major or minor release, but not a point release *(reworded 2026-09-30, `CONSTRAINTS.md` §2)*.
>
> Frames, 640 pt wide, from a sampler built from chunk 11's `winlist` source — the window server
> every 50 ms and the autosave every 0.5 s, a line only when either changed:
>
> | | predicted | read |
> |---|---|---|
> | idle floor, six drives | **600** | **600** — the corner, from 867 (11:16:30) |
> | idle floor, two drives | **600** | **600** — four drags, from 1304, 736, 1079 and 1227, every one stopping there (11:50–11:51) |
> | idle floor, one drive | **588** | **588** — the corner, from 600 (13:00:23) |
> | at Start, **pushed** | **614–616** | **614**, 71 ms after `starting` — the probe's 582 + 32 exactly (11:29:29) |
> | running floor | **~615, or 600** | **615**, 259 ms after `running`; the corner dragged during the run did not move it, so not 600 |
> | idle floor again, run finished | **600** | **600** — the corner (11:30:54) |
>
> **Reported, not adopted: the shipped window's worst case is the running floor, 615, and the gate's
> is 614.** Its prediction came from the old build's 557 + 58 and was right to the point. At 1280×800
> that leaves **85 pt**, not the gate's 86 — within the 2 pt this box allows for the shipped window
> reading over the probe. The gate is unchanged and 614 is still its number; whether it moves is the
> user's call. ✅ **Decided later that day: 615 is the spec** — *"Change the running height spec
> from 614 to 615."* The gate is still unchanged: it measures the probe, which reads 614, and this
> box's 2 pt allowance for the shipped window over it stands.
>
> **Three things seen that no item asks for.** The pre-run dialog grew with the window at the push,
> 470 × 528 to 470 × 542 in the same 50 ms sample. With one drive left, the window stayed at 600 when
> the other went, and only the drag took it to 588: a window does not shrink when its floor drops
> (`PROGRESS.md`'s E3). And when that drive came back, the window was **pushed** from 588 to 600 in
> 78 ms, its top edge kept: a rising floor pushes, the way Start does. *(User, 2026-09-25, on the
> push and the dialog growing with it: "Agreed" — harmless and cosmetic, kept as they are.)*
>
> **For any later walk that needs fewer drives:** the **1 TB 990 EVO Plus**, serial `013117100578`,
> holds this repository and Claude Code, so it is never unplugged and is in every such state; with it
> alone attached, the app selects it, and nothing is started. The **22 TB Seagate** may be unplugged
> for a walk step, ejected first, but must be powered on, connected and all its volumes mounted again
> **before midnight every evening**, when automated backups run (user, 2026-09-25). Its eject failed
> EBUSY that day until a restart; `/usr/sbin/lsof /Volumes/Backup "/Volumes/Time Machine"` names what
> holds it.

**Two drives attached for 9.4 and 9.6** — any second USB drive; nothing is written to either, and
every check here is idle except 9.3.

**First, clear the saved window frame.** AppKit's frame autosave beats `.defaultSize`, so a window
that was once screen-height stays that way for that user until the saved frame is removed. With the
app **quit**:

```
/usr/bin/defaults delete /Users/<you>/Library/Preferences/com.arc3solutions.USBDriveTester "NSWindow Frame main"
```

**BY PATH, NOT BY DOMAIN, AND THAT IS NOT A STYLE PREFERENCE (measured 2026-08-20).** The obvious
form — `defaults delete com.arc3solutions.USBDriveTester "NSWindow Frame main"` — resolves to a
**stale sandbox container** left under `~/Library/Containers/` since 7 July. The `defaults` CLI
prefers a container path whenever that directory exists, so the domain form reads and writes a plist
this app has never touched. It **deleted nothing and reported nothing**, and the window restored its
old frame; 9.1 was recorded as a failure before anyone noticed the delete had never happened.

This is the same trap as increment 6's `defaults read`, which is why chunk 8 reads by path — but it
was written up as a *read* problem, and it is not. It applies to every `defaults` operation on this
bundle ID. See `UserDefaultsIOSize`'s note.

Verify before launching, rather than trusting it:

```
/usr/bin/plutil -p /Users/<you>/Library/Preferences/com.arc3solutions.USBDriveTester.plist
```

No `NSWindow Frame main` line should remain. `runIOSizeBytes` and `preRunWarningsSuppressed` live in
the same file and must still be there — if they have gone, the wrong thing was deleted.

1. **Launch. The window opens at roughly 720 x 700 and not full height.** This is the whole of the
   original report — it opened at 1328 pt on a 1410 pt display against content that wanted 675,
   because the scene declared no `.defaultSize` and the content's maximum height is unbounded. No
   render can see this: a render is given a size, and the question here is what size the app *asks*
   for.

   ✅ **2026-09-21: 720 × 700 — and that is the frame**, so 668 pt of content, 32 pt short of what
   `.defaultSize` was told. The item passes as written, since what it checks is that the window opens
   small rather than screen-height; the missing 32 pt is finding 3 above, and it is a defect against
   `WindowMetrics`'s own comment rather than against this item.

2. **Drag the bottom edge up as far as it will go.** It should stop at **563–574 pt** tall
   depending on how many drives are attached, and at that height **nothing is cut off** — the drive list, the selected-device pane and the metrics
   panel each shrink and scroll rather than clipping. Watch which one gives way first: **the drive
   list should shrink before the selected-device pane does**. That ordering is a deliberate
   decision (2026-08-19) — the list is a picker you have finished with by then, the detail is what
   stands between you and testing the wrong drive.

   ⚠️ **563–574 was measured 2026-08-20 and stopped being true on 2026-08-22**, when the refusal
   lines under the run buttons were deleted. Nothing re-walked this item, so it carried a
   pre-deletion criterion for a month. ✅ **2026-09-21/22 on macOS 27: it stops at a 542 pt frame**
   — 510 pt of content, five drives, which is `ui-probe`'s `declared=` for this state hit exactly —
   and **nothing was cut off**. The drive list gave way before the selected-device pane, as decided.
   **Drag from the bottom-right corner, not the bottom edge**; see the observation after item 6.

   ⚠️ **2026-09-24: "nothing was cut off" did not hold at that floor, on that same build.** With six
   drives at the 542 pt frame (read off the window server 11:03:30, dylib `422c89d3…`), a
   screenshot showed the **"6 USB drives" heading hidden under the title bar**, but for a 1 pt
   sliver, and the **idle metrics box running into the window's bottom edge** with no border below
   it. Its text was whole. Both are **cosmetic** under the rule the user set that day (*"minor
   cosmetic imperfections at the floor vertical size"* are acceptable; *"the priority is
   function"*), so the item's function passed as recorded. What it missed was the band chunk 11's
   item 6 fell into, and item 6's fix closes it. **On the build that carries the fix, predict a
   600 pt frame with two or more drives and 588 with one**, and at that height the heading and the
   box's bottom edge whole.

   ✅ **2026-09-25, on the build that carries the fix: 600 with six drives, 600 with two, 588 with
   one**, each read off the window server and the autosave together (chunk 9's 2026-09-25 box). At
   six, the user's screenshot at the floor showed the "6 USB drives" heading whole, the idle metrics
   box's bottom border whole with space below it, and two whole rows in the list; the list gave way
   before the selected-device pane — *"Part A - everything looks good."* At one drive, the heading
   and the box's bottom edge whole — *"Everything looked exactly like it should."*

3. **Start a run and, while it is running, drag the window down to its minimum again.** The live
   metrics panel must **scroll**, not clip. This is the defect reported on 2026-08-19: the bottom
   three lines were cut off and unreachable by any means, which for FR-METR-2/4/5/6 is the
   requirement silently unmet rather than merely cramped. The heading stays pinned while the
   figures move under it.

   Note the window will refuse to go quite as small as it did in 9.2 — `running` needs **613–624**
   against idle's 563–574, and `starting` briefly needs the most at **627–638**. That is expected:
   the window grows a little at the moment you press Start and settles back when the run begins.

   ⚠️ **All three ranges are pre-2026-08-22 and all three are wrong now — and the sentence after them
   is wrong in kind, not only in number.** ✅ **2026-09-22: the metrics panel scrolled perfectly**,
   heading pinned, figures moving under it, nothing clipped — which is the whole point of the item
   and is what passed. The heights: `running`'s floor is a **557 pt** frame against idle's 542, so
   the window gives up 15 pt of range while a run is on, and **takes it back when the run finishes**
   — dragged to 542 again afterwards, checked. And at the moment you press Start the window is
   **pushed to 615 pt on its own, untouched**, and *stays* there. It does not settle back: what
   settles back is the floor, not the height. **That 615 is this chunk's most valuable single
   reading** — it is the shipped window doing what the gate's worst case says it does, within 2 pt,
   and nothing before 2026-09-22 had ever checked it (finding 2 above).

   ✅ **2026-09-24, seen again on the same build** (dylib `422c89d3…`, daemon 95762, protocol v15):
   at the 557 pt running floor with six drives, the metrics box scrolled to its end showed **p99**
   whole, the box's bottom border whole with 12 pt of window below it, and the heading whole — a
   screenshot taken while the window sat there, 12:40:41–12:41:11, during a run on the 125.8 MB
   thumb. Pushed to 615 at Proceed again. **On the build that carries item 6's fix, predict a push
   to 614–616 at Start and a running floor of ~615 or 600** — both declared under chunk 9's box.
   At ~615 this item's drag cannot move a window pushed to 615, and **the scrolling it checks
   happens at that height**.

   ✅ **2026-09-25, on the build that carries the fix** — a run on the 125.8 MB thumb, serial
   `2211190533300386001515` read off the pre-run dialog, completed in 39.9 s with 0 failing blocks.
   The window was **pushed to 614** 71 ms after `starting` and to **615** 259 ms after `running`, and
   the corner dragged up during the run did not move it, so the metrics box was scrolled at 615, as
   predicted: to its end, heading pinned, nothing cut off — *"All 5 elements of part B completed."*
   After the run the corner took the window to 600 again.

4. **With two drives attached, at a comfortable window height, check the idle metrics panel is
   exactly its two lines of copy** — no empty box beneath them — and that the spare height has gone
   to the drive list and the selected-device pane instead.

   This took two goes. The drive-count render axis found both panes greedy and splitting spare
   height evenly, so six drives at 700 pt showed two of them beside **265 pt of empty panel**;
   capping the idle panel helped and still left ~140 pt of blank box, which is what was seen on
   hardware and removed on 2026-08-20. The panel is now sized to its content when idle.

   The panel keeps its floor. Removing that as well was tried on 2026-08-20 and reverted the same
   day: it appeared to take 30 pt off every state's minimum, and every one of those windows clipped
   this placeholder's second line. **9.2 is what caught it** — the fit gate had passed on the
   smaller number, because it checks that the minimum is small enough to fit a screen and never
   that it is large enough to fit the content.

   At a very tall window (1200 pt+) the *selected-device* pane holds the leftover height instead,
   since it is the remaining flexible pane. That is known and is not a defect to report.

   ✅ **Passed 2026-09-22** on the Xcode 27 build, with five drives attached rather than two.

5. **Stop the run. Resize the window taller and shorter a few times.** Nothing should jump, flicker,
   or leave a pane stranded at the wrong size, and the three panes should give and take height
   smoothly rather than one absorbing everything.

   **The drive list scrolling under the drag is the intended behaviour, not a jump** (added
   2026-08-20, after the auto-scroll landed). It moves only far enough to keep the selected drive
   visible and only while that drive would otherwise leave the pane; a list that stays put through
   the whole drag means the selection was never in danger, which is equally correct. What would be
   a defect is the list scrolling somewhere the selection is *not*, or scrolling while the window
   is not being resized at all.

   ✅ **Passed 2026-09-22** on the Xcode 27 build, five drives, resized with the corner handle.

6. **Click the *last* drive in the list, then drag the window down to its minimum.** The list must
   scroll so the selected drive stays **fully** visible — both of its lines, not the top half of
   one. Reported from 9.3 on 2026-08-20: at the minimum the chosen drive went off screen
   altogether, leaving a one-row list above a "Selected device" pane naming a drive that was
   nowhere on it.

   Then drag taller and shorter again a few times. The selection should stay in view the whole
   way, and the list should not animate — the scroll is deliberately unanimated, because a drag
   changes the height on every frame and an animation would spend the drag chasing it.

   **Two drives is the real test here, and six is not.** With six the scroll needed is large
   enough to run into the bottom of the list and saturate, which comes out right even when the
   mechanism is wrong; with two it is a few points, and only a correct implementation finds them.
   That is measured rather than supposed — the one-run-loop-turn deferral in `scrollToSelection`
   exists *because* six drives passed without it and two did not.

   ✅ **Passed 2026-09-22** on the Xcode 27 build, with **two** drives, down to the 542 pt floor.

   *2026-09-24: on the build that carries item 6's fix the floor with two drives is predicted at
   **600**. The list then sits at the table's 104 pt against its own 108, so the scroll needed is
   about **4 pt**. That is still the "few points" this item is written for — it is what the Xcode 26
   build gave, since that build stopped at the table's floor too.*

   ✅ **2026-09-25, on the build that carries the fix, with two drives** — the 22 TB Seagate and the
   1 TB 990 EVO Plus. The EVO Plus, the last in the list, selected; the window then taken from
   1304 pt to its minimum, and three times more from 736, 1079 and 1227 pt, every one stopping at
   **600** — and by the user's eye nothing out of place: *"Part C done. Cosmetically, everything
   looks good."*

> ⚠️ **OPEN, UNREPRODUCED — the bottom edge would not shrink the window (2026-09-21, reported
> 2026-09-22).** Noticed while the readings above were being taken: dragging the **bottom edge** up
> did not shrink the main window at all, while the **bottom-right corner** handle worked perfectly
> throughout. Not reproducible later the same day, and **not chased further** (user decision,
> 2026-09-22) with the chunk half walked.
>
> **It is not a procedural footnote — it cost a whole round of this walk.** The round that returned
> three identical 615 pt readings was diagnosed as *the drag did not register*. The drag did
> register; the window genuinely did not move. **Detector:** a drag that leaves `NSWindow Frame main`
> unchanged is either this or a window already sitting on its floor, and those two are told apart by
> whether the reading is *at* the floor for that state — 542 idle, 557 running. *(Those are the old
> build's. From item 6's fix, 2026-09-24, predict 600 idle with two or more drives, 588 with one,
> and ~615 or 600 running — see chunk 9's box. ✅ 2026-09-25: read **600**, **588** and **615**. The
> bottom and top edges were tried at the six-drive idle floor that day and left no reading, which
> the detector puts down to the floor; the edge was not separately tested.)*
>
> **Hypothesis — inference, not measurement.** The one session it bit was the one in which the window
> was sitting at a height *AppKit had pushed it to* at Start (615 pt) rather than one that had been
> dragged there. If the refusal only follows a push, that is checkable in a single step next time:
> press Start, let the window be pushed, then try the edge.
>
> **If it recurs it is a defect against NFR-USE-9, not a cosmetic one.** That requirement exists so
> the window fits a 13.3-inch screen, and a 542 pt floor is worth nothing to a user whose bottom edge
> will not take them to it — the corner handle is not the control most people reach for. Three checks
> separate platform from product, cheapest first: **the bottom edge dragged *down*** (does it grow?),
> **the top edge dragged down**, and **the app's own *Privileged Helper & Diagnostics* window** —
> same process, same SwiftUI, different content, no scrolling panes. A TextEdit window is the outside
> control if those three do not separate it.
>
> ⚠️ **2026-09-23: NOT REPRODUCED, from a pushed window, in both states the hypothesis could mean** —
> chunk 11's re-walk on the Xcode 27 build, where correction (8) made the bottom edge the first
> shrink. After run 1 had finished, the edge took the window from the 615 pt AppKit had pushed it to
> at Start down to the 542 pt idle floor (12:37:29). During run 2, pushed to 615 at Start again, it
> took it to the 557 pt running floor (15:43:36). Both were read off the window server and the
> autosave together. **The one-step test above was run, and the edge worked**, so the hypothesis is
> not supported. The edge also made every drag in that walk's item 6, up and down.
> **This box stays OPEN and unreproduced** — it was seen once, on 2026-09-21 — and its detector
> stands.

> **9.7 was deleted on 2026-08-22 rather than passed.** It counted the refusal sentences under the
> run buttons, and those sentences no longer exist: the block was removed outright (user decision),
> on the grounds that nothing it printed said anything the status line above it, the drive list's
> **Unusable** badge, or the quit banner was not already saying. A check for the right *number* of
> sentences is not a check when the right number is none. `RunControlsView`'s header records what
> was weighed before it went.

### Chunk 10 — deleted 2026-08-22, after passing

Seven items covering the Restart control. **They were walked at the keyboard on 2026-08-22 and all
seven passed** — and the control was removed the same day (user decision), because Stop then Start
reaches the identical end state. FR-CTRL-5 is still met, by composition; the requirements document
carries an amendment of that date saying so.

Kept as a heading rather than deleted silently, because *"chunk 10 passed"* and *"chunk 10 does not
exist"* are different facts and a reader of this file is entitled to know which one applies. If a
Restart control is ever built again, its checks are in commit `0f65be4`.

### Chunk 11 — the report as a sheet (increment 8) — ✅ **RE-WALKED ON XCODE 27: TEN ITEMS PASSED 2026-09-23; ITEM 6 FAILED, WAS FIXED 2026-09-24 AND PASSED 2026-09-25 ON THE BUILD THAT CARRIES THE FIX, WHERE THE TEN WERE NOT RE-WALKED** *(two finished runs cover 2–7 and 9; 8 starts one that aborts; 1, 10 and 11 are dry)*

The report was a `Window` from Step 10 until increment 8 and is now a **sheet on the main window**
(user decision 2026-08-19). Nothing in the suite can see any of this: no test drives a SwiftUI view,
and `RunControllerWiring.live` needs a privileged helper and a drive to construct, so even the two
lines that tell the model a run produced a report are reachable only by a person.

> ❌ **RE-WALKED ON THE XCODE 27 BUILD 2026-09-23 — NOT PASSED. Ten of the eleven items pass; item 6
> FAILED and is owed** (user decision, 2026-09-23: recorded as walked and not as passed, and the
> chunk stays on the re-walk list for item 6 alone until the finding is diagnosed and fixed).
> 12:22–16:09 at the keyboard, against the app installed 2026-09-19 10:22:50 from `bcde5f5`'s
> sources (Xcode 27.0 27A266a, `DTXcode 2700`, dylib `422c89d3…` — re-proved by content at 11:05 that
> morning: item 0.1 greps 1, codesign OK), helper `ac4d5208…`, and daemon pid 95762 on protocol v15
> throughout, on macOS 27.0 (26A428). The app was pid 46926 from 12:22:48 to the ⌘Q at 16:00:37, then
> pid 70736 for item 7's second half. Six drives attached. **Every Start was on the 125.8 MB thumb**,
> serial `2211190533300386001515`, read off the pre-run dialog before each answer (correction (5)) —
> four dialogs: item 11's, cancelled; runs 1 and 2, about 40 s each; and item 8's, aborted. The app
> selected **the 22 TB Seagate** by itself at both launches and again when the thumb was pulled for
> item 8, and nothing was ever started against it. **Invalidated by** any edit to a view source or to
> `AppModel`, `QuitPolicy`, `AppLifecycleDelegate`, `WindowMetrics` or `DevicePreparation`; by a
> different installed build; and by any new Xcode or macOS major or minor release, but not a point release *(reworded 2026-09-30, `CONSTRAINTS.md` §2)*.
>
> **Item 6 — the sheet against the window, at every size taken.** Bounds are the window server's, in
> points; the prediction is correction (8)'s (*W* − 24) × (*H* − 56).
>
> | main window | how it got there | sheet | predicted | too tall by | sheet's bottom edge |
> |---|---|---|---|---|---|
> | 714 × 1040 | restored at launch (item 1) | 690 × 984 | 690 × 984 | 0 | 24 pt inside |
> | 640 × 615 | pushed at run 1's Start and at run 2's finish; restored at the relaunch | 616 × 559 | 616 × 559 | 0 | 24 pt inside |
> | **640 × 542** | bottom edge up to the idle floor — 12:42, and again at 15:01 | **616 × 530** | 616 × 486 | **44 pt** | **20 pt below the window** |
> | 640 × 580 | bottom edge down from 542 — 14:37 | **616 × 539** | 616 × 524 | **15 pt** | 9 pt inside |
> | 2512 × 1410 | Window ▸ Zoom — 14:42 | 2488 × 1354 | 2488 × 1354 | 0 | 24 pt inside |
> | 640 × 600 | Window ▸ Zoom again — 14:44 | 616 × 544 | 616 × 544 | 0 | 24 pt inside |
> | 640 × 677 | bottom edge down from 542 — 15:34 | 616 × 621 | 616 × 621 | 0 | 24 pt inside |
>
> Every sheet sat at the window's *x* + 12, *y* + 32 — centred, directly under the title bar — and
> every width was exact. **Only the height was wrong, and only below 600 pt.** At the idle floor the
> sheet's bottom edge was at *y* = 612 and the window's at 592, and the user confirmed it by eye with
> the sheet up: *"Yes, it overhangs."* The same 616 × 530 came back at 15:01, after three other sizes.
> The rest of item 6 passed: at the floor, *"all three visible"* — the headline, a body that scrolls,
> **Export report…** and **Done** — and at the zoomed size, *"fills with the margin as predicted"*.
> The sheet never ran off the screen.
>
> **What the readings rule out.** *Not the drag*: the bottom edge dragged down to 677 gave an exact
> sheet. *Not a minimum height*, in the content or in the sheet: a floor would give the same sheet at
> both short sizes, and they gave 530 and 539. *Not the window's own minimum*: after Zoom returned
> 600, the bottom edge still took the window to 542. What is left is **the height itself** — exact at
> 600 pt and above however the window got there, restored, pushed, zoomed or dragged, and too tall
> below it, with the onset between 580 and 600. The line through the two too-tall readings — *sheet ≈
> 0.237 H + 401.6* — meets *H* − 56 at 600, the exact reading there. That is arithmetic, not a
> mechanism.
>
> **Candidate, not tested:** the `contentSize` that `ContentView`'s `onGeometryChange` stores, and that
> `reportSheetSize` takes the margin off, reads taller than the window's content area below about
> 600 pt. The sheet would come out at 530 if it read 554 against a 510 pt content area, and at 539 if
> it read 563 against 548. The app does not log `contentSize`, so the walk could not tell. **No gate
> and no render can see any of this**: `render-ui.sh` lays the report out at a size it is handed,
> `window-fit-check.sh` sizes the main window, and the sheet's real size can only be read off the
> running app, as this walk read it. **Three app-source comments state the premise this breaks**:
> `reportSheetSize`'s *"it can never exceed a screen the window itself fits"*,
> `WindowMetrics.reportSheetMargin`'s, in the same words, and `RunReportView`'s header, *"this view's
> floor **is** the main window's floor"*. **Two instrument comments lean on it**: `ui-probe`'s
> `RunReportHost`, and `render-ui.sh`'s header, *"these renders show what a user sees"*. All five
> are left as they are (`PROGRESS.md`, Owed (f)).
>
> **Two observations, neither of them an item, both for the same diagnosis as item 6** (user
> decision, 2026-09-23):
>
> * **At run 2's finish the window was pushed from 557 to 615 pt by itself** — the height it is pushed
>   to at Start — and the report came up on it at 616 × 559. Before the run it had been dragged to the
>   542 pt floor; it was pushed to 615 at Start, as chunk 9 recorded; then the bottom edge took it to
>   the 557 pt running floor. Chunk 9 could not have seen a push at the finish: its window was never
>   below 615 when a run ended.
> * **Window ▸ Zoom, chosen a second time, returned the window to 600 pt, not the 580 it had been
>   zoomed from** (14:44:33). The app logged nothing and no drive came or went. 600 is also where item
>   6's error stops. Noticed, not tested.
>
> ⚠️ **2026-09-24 — diagnosed and fixed headlessly; not re-walked.** *(✅ 2026-09-25: re-walked and
> passed — see the paragraph after the predictions below.)* The candidate was right about
> the sheet and wrong about where the fault lay. `reportSheetSize` does take the root stack's
> `contentSize`, and below about 600 pt that stack was taller than the window. Nothing misread it:
> **the window could be dragged below the height its content fits.** This build's window drags down
> to its declared minimum, and `WindowMetrics.deviceListFloor` declared the drive list at 46 pt
> while its table would not lay out below about 104. In the band between, the root stack overflowed
> the window and the sheet copied it, less 24 pt each way. `ui-probe` showed the whole pattern with
> its own fixtures' figures, not the walk's: sheet = stack − 24 at every height, and the stack over
> the window below the knee and equal to it above. **The fix:** the floor is 104, capped at the
> list's own height, so the window's minimum is the content's — **600 pt** with two or more drives,
> **588** with one. The walk's 600 pt knee and Zoom's return to 600 are both that height, 568 of
> content plus the title bar; that is consistent, not shown. The probe did not reproduce the push
> at run 2's finish, which stays open *(closed 2026-09-25, by user decision: see "No push at the
> finish", below)*.
>
> **Re-walk predictions for item 6**, on the build that carries the fix, six drives:
>
> * at the idle floor, a **640 × 600** window and a **616 × 544** sheet at *x* + 12, *y* + 32, its
>   bottom edge 24 pt inside — the reading the 640 × 600 row above already took, exact, on the old
>   build. With one drive: 588, and 616 × 532;
> * **no height below the floor reachable by any drag**, so none of the table's too-tall rows can be
>   reproduced;
> * a window whose saved frame is below the floor — the old build's 542 is likely still in
>   `NSWindow Frame main` — **opens at the floor, not at 542**, the way the probe's window is raised
>   to its declared minimum at the first layout. Read the autosave with the app quit, and the
>   window server after launch. Opening at 542 would be the band again, by another route.
>
> The five premise comments are annotated rather than left (`PROGRESS.md`, Owed (f)). **The ten
> passes lapse by this box's clause**, since the fix edits `WindowMetrics` and a view source,
> although nothing they check moved: the only code changed is the two lines that set the list's
> floor. Which of them to re-walk is the user's call; item 6 is the one the fix is for.
>
> ✅ **ITEM 6 RE-WALKED AND PASSED 2026-09-25, on the build that carries the fix** — the build, pids
> and drives chunk 9's 2026-09-25 box names: installed 2026-09-24 18:01:53 from `77275be`, dylib
> `e6e6e884…`, helper `ac4d5208…`, protocol v15, macOS 27.0 (26A428). **The other ten items were not
> re-walked** (user decision), so their passes are facts about the build installed 2026-09-19.
> **Invalidated by** this chunk's clause: any edit to a view source or to `AppModel`, `QuitPolicy`,
> `AppLifecycleDelegate`, `WindowMetrics` or `DevicePreparation`; a different installed build; any new Xcode or macOS major or minor release, but not a point release *(reworded 2026-09-30, `CONSTRAINTS.md` §2)*. Read off the window server, as the table above was:
>
> | main window | how it got there | sheet | predicted | sheet's bottom edge |
> |---|---|---|---|---|
> | 640 × 615 | held at the running floor; the report came up at the run's finish — six drives | 616 × 559 | 616 × 559 | 24 pt inside |
> | **640 × 600** | the corner, to the idle floor after the run — six drives | **616 × 544** | 616 × 544 | 24 pt inside |
> | 1027 × 1304 | the corner, outwards | 1003 × 1248 | 1003 × 1248 | 24 pt inside |
> | **640 × 588** | the corner, to the idle floor — **one drive** | **616 × 532** | 616 × 532 | 24 pt inside |
>
> Every sheet sat at *x* + 12, *y* + 32 and every one was exact. The three predictions held:
>
> * **at the floor**, 616 × 544 on 640 × 600, with the headline, a scrolling body, **Export
>   report…** and **Done** all on screen — *"All 5 elements of part B completed … Cosmetically, all
>   UI elements of both windows passed"* — and 616 × 532 on 588 with one drive;
> * **nothing below the floor was reachable**: every drag stopped at 600, or 588 with one drive, so
>   none of the too-tall rows above could be reproduced;
> * **a frame saved below the floor opened at the floor.** The autosave held a 615 pt frame, left by
>   the 2026-09-24 run, not the 542 predicted as likely, so a 542 pt frame with the same top edge was
>   seeded by path with the app quit — `106 862 640 542` — and the window opened at 640 × 600, its top
>   edge kept, autosaved `106 804 640 600` a second after launch (user: *"Yes, the defaults command at
>   02:55:53 was the 542 seed."*).
>
> **No push at the finish**: the window sat at the 615 pt running floor when the run ended, and the
> report came up without moving it. The 2026-09-23 push, from 557 to 615, cannot be seen on this
> build, since the window can no longer be below 615 when a run ends — **inferred, not tested**, so
> that observation stays open. ✅ *Closed later that day, by user decision: "Let's close the push at
> the end of the run issue."* The one-drive row is the **empty** report — *"No run has finished
> yet"*, Done, no Export, by design — because the day's restart had emptied `lastRunReport`, which
> lives in memory only (export is the only persistence, FR-RPT-5); the sheet's frame is
> `reportSheetSize`, whatever it shows.
>
> **Two of this checklist's own instructions were wrong, and are annotated below rather than
> rewritten.** Correction (7) missed that **closing the main window is a quit**, so item 7 was walked
> in two parts across a relaunch. And item 8's note says preparation *"goes ahead against that
> captured drive"*: it did not, because a guard stopped it first. The outcome was as expected in both.
>
> **The instrument.** A sheet is a window of its own with no autosave, so correction (8) read sizes
> from the **window server**: `CGWindowListCopyWindowInfo`, on-screen windows only, filtered to the
> app's pid. It reads live, lists front to back — which is also item 9's reading — and needs no
> permission. It was checked against `NSWindow Frame main` before anything it said was used: at
> 12:24:22 both gave 714 × 1040, the restored frame, and the two agreed at every later reading of the
> main window. **A sheet window has no chrome**: its bounds are the SwiftUI frame it was given. It was
> used in three forms: `winlist <pid>` for single readings, whose source follows; a sampler through
> run 2 and item 8, which ran `winlist` and read the autosave every 0.5 s and wrote a block only when
> either changed; and `winwatch <pid> <seconds>`, the same call every 20 ms, for item 7. The log was
> read with `process == "USBDriveTester" AND subsystem BEGINSWITH "com.arc3solutions"`, and item 10
> counted with `process == "USBDriveTester"` and one `eventMessage` clause per string, the report
> line's as `BEGINSWITH`. No test suite ran during the walk (correction (6)).
>
> ```swift
> // winlist — list ONE process's on-screen windows, front to back, with their bounds.
> //
> // Usage: winlist <pid>
> //
> // It refuses to run without a pid. An unfiltered listing prints every app's window titles, and
> // those are nobody's business but the person at the keyboard.
> //
> // `z` is the window's index among ALL on-screen windows, front to back, so two of this app's
> // windows can be ordered against each other without naming anything else on screen. Bounds are
> // the window server's, read live: a frame, in points, origin top-left of the main display.
> import CoreGraphics
> import Foundation
>
> guard CommandLine.arguments.count == 2, let want = Int(CommandLine.arguments[1]), want > 0 else {
>     FileHandle.standardError.write(Data("usage: winlist <pid>\n".utf8))
>     exit(2)
> }
>
> let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
> guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
>     print("NO LIST")
>     exit(1)
> }
>
> func number(_ any: Any?) -> String {
>     guard let n = any as? NSNumber else { return "?" }
>     return n.doubleValue == n.doubleValue.rounded() ? String(Int(n.doubleValue)) : n.stringValue
> }
>
> var shown = 0
> for (z, window) in windows.enumerated() {
>     guard (window[kCGWindowOwnerPID as String] as? Int) == want else { continue }
>     let id = window[kCGWindowNumber as String] as? Int ?? -1
>     let layer = window[kCGWindowLayer as String] as? Int ?? -1
>     let name = window[kCGWindowName as String] as? String ?? "<no name>"
>     let b = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
>     print("z\(z)\twin \(id)\tlayer \(layer)\t\(number(b["Width"])) x \(number(b["Height"]))"
>           + " at (\(number(b["X"])), \(number(b["Y"])))\t\(name)")
>     shown += 1
> }
> print("pid \(want): \(shown) window(s), of \(windows.count) on screen")
> ```
>
> Built on 2026-09-23 with the pinned Xcode 27.0, from the directory holding the source:
>
> ```
> DEVELOPER_DIR=/Applications/Development/Xcode.app/Contents/Developer /usr/bin/xcrun swiftc -O -o winlist winlist.swift
> ```
>
> It prints window names, and the sheet's is empty.

**The 4 TB T5 EVO** (serial `00000S7CLNJ0WC02266P`) attached, and the log stream running. Items 1–7
need a real run; 8–10 do not.

> ⚠️ **FOUR CORRECTIONS TO THIS CHUNK, made 2026-09-23 while laying the re-walk out and before any
> of it was walked.** None is a defect in the app; three are stale text and one is this chunk
> inheriting a step-wide prerequisite it does not need.
>
> **(1) Run it on the 1 TB scratch T5, not the 4 TB T5 EVO** (user's standing rule: the scratch T5
> is the only write target, and the 22 TB Seagate never is). `scripts/lib/device-identity.sh` says
> the same thing in the repository's own words — the scratch T5 is *"THE designated scratch device:
> every write gate in this project targets this drive"*, while the T5 EVO is the **`fixture`** role,
> erasable, whose two jobs are the multi-volume unmount-rollback checks and the link-speed question.
> **Chunk 11 needs neither.** It is about a sheet: no unmount rollback, no second volume, no link
> speed. The prerequisite line above was inherited from the step-wide list at the top of this file,
> where the T5 EVO is there for *other* chunks.
> *⚠️ Replaced for this walk by (5), below — the same day, user decision.*
>
> **(2) Item 6's recorded sheet size is pre-2026-08-22.** *"Rendered at 616x461 … the sheet at the
> window's minimum"* was the sheet at the **517 pt** declared minimum of the time: 485 pt of content
> less the 24 pt `reportSheetMargin` on each axis. Chunk 9 measured the floor at **542 pt** on
> 2026-09-22 — 510 pt of content — so expect roughly **616 × 486**, which is 25 pt *more* room than
> that note describes, not less. A reading near 461 means something else has moved.
> *⚠️ Measured 2026-09-23: **616 × 530**, 44 pt taller than this predicts, and hanging 20 pt below
> the window. Item 6 failed on it; see the re-walk box above.*
>
> **(3) Item 7's ✅ is an Xcode 26 fact and lapsed at the 2026-09-19 install.** It reads *"RE-WALKED
> AND PASSED 2026-09-04"*, which is exactly the shape CLAUDE.md's 6.3 example warns about: a date
> that reads like a property. It is in scope for this re-walk.
>
> **(4) *"Items 1–7 need a real run; 8–10 do not"* mis-sorts three items.** **Item 1 needs no run at
> all** — it checks the empty-state report *before* any run, which is the only time that state
> exists. **Item 8 needs a run that is started and aborted**, not a finished one. **Item 9 needs a
> finished run**, so it is not covered by *"8–10 do not"*. And item 11, added after that line was
> written, is dry.
>
> **Two finished runs cover this chunk, not three.** One serves items 2, 3, 4 and 6, which all hang
> off the report that run leaves standing. A second serves items 5 and 9 together — check the Window
> menu is greyed while it runs (5), then raise the diagnostics window with ⇧⌘D and leave it in front
> as the run finishes (9). Item 8 is a third *start*, aborted. Items 1 and 11 are dry.
>
> ⚠️ **FIVE MORE, THE SAME DAY — from the headless check before the walk, after the four above
> were committed.** Two are user decisions; three are things the four missed. None is a defect in
> the app.
>
> **(5) The walk runs on the 125.8 MB thumb, not the 1 TB scratch T5** — user decision, 2026-09-23:
> *"We can use that for shorter testing."* General UDisk, serial `2211190533300386001515`, role
> `multislice` in `scripts/lib/device-identity.sh` — `/dev/disk12` on the day, 245,760 × 512 B,
> `Slice_A` mounted and the second slice without a volume, exactly as recorded on 2026-09-11. A
> whole-device run on it takes about **40 s** — 30/30 chunks in 39 s at item 7.5 (2026-09-01), 40.0 s
> of I/O at chunk 15's item 5 (2026-09-03) — so every start in this chunk fits one sitting, where a
> finished run on the scratch T5 takes hours. This replaces (1)'s drive for this walk and nothing
> else in it. Step 11 has used the thumb this way before: 7.5 and 15.5 ran on it, 14.6 names it as
> *"the one that finishes quickly"*, and 16.4 calls it *"the cheapest fixture"* for the same
> induction as item 8.
>
> **Unchanged:** the 22 TB Seagate is never a target. The app selects a drive by itself at launch —
> the Seagate, on 2026-09-18 — so select the thumb before **every** Start, and **read its serial off
> the pre-run dialog before every Proceed**: the dialog prints model, capacity and serial. Leave
> *Don't show this warning again* unticked; it persists, and items 8 and 11 need the dialog.
>
> ⚠️ Step 13's item 2.7 says the opposite — *"No other drive may be substituted"* — because the thumb
> is *"reserved for Step 12's item 4.9"*. That reservation was spent when 4.9 was walked on
> 2026-09-11. Whether this decision reaches 2.7 is a Step 13 question, and it is **not** settled here.
> *(Settled 2026-09-27, by the user: it does. The write targets are the scratch T5, the 4 TB T5 EVO
> and the thumb, chosen for testing efficiency, and Step 13's 2.7 no longer bans a substitute.)*
>
> **(6) Item 10's log strings are wrong, and always were.** A refused call logs `no run report: the
> helper refused the call, so no run took place — …` (`RunReportLog.noReportForRefusedCall`), and
> has since `15dbc40` on 2026-08-09, before item 10 was written. The only message containing `no
> report:` is `device loss with no report: …` — a drive lost with nothing to report, which here
> would mean the thumb dropped mid-run. A search for `run report:` also matches `no run report:`, so
> count messages that **begin** `run report: `. And item 8's abort is **not** a refused call: it logs
> `run aborted before any write: …`, raises the failure alert, and never reaches the report path.
> So this walk expects **two** messages beginning `run report: `, **none** containing `no run
> report:` or `device loss with no report:`, **one** `run aborted before any write:`, and one
> `pre-run prompt raised:` per Start — **four**, each naming serial `2211190533300386001515` — with
> one more report and one more prompt if item 9 has to be re-run. The app shares category `io` with
> the helper, so match on `process == "USBDriveTester"`; and run no test suite during the walk,
> because the test host has that name too.
>
> **(7) Item 7 is walked last.** It needs a report on screen and ends by quitting, and nothing above
> places it. It uses run 2's report, after item 8: only a start that gets as far as claiming the
> drive clears the last report (`onRunBegan()`, in `RunController`'s `.ready` branch), and item 8's
> start aborts before that.
> *⚠️ 2026-09-23, found during the walk: (7) missed that **a close is a quit**.* Closing the main
> window with no run active quits the app (user decision 2026-08-06; `QuitPolicy`'s
> `allowCloseAndQuit`). So item 7's *"work once it is gone"* cannot be seen without ending the
> session. Item 7 was walked in two parts: first ⌘Q with run 2's report up, then a relaunch. After
> the relaunch ⇧⌘R raises the empty state, because `lastRunReport` is kept in memory only
> (FR-RPT-5), and the close button was tried under that sheet and after it. The prediction above
> held: run 2's report survived item 8's aborted start.
>
> **(8) How item 6 is walked and read this time.**
>
> * **The first shrink is the bottom edge** — user decision, 2026-09-23, and the one-step test that
>   the open observation under chunk 9 asks for. After run 1 the window sits at the height AppKit
>   pushed it to at Start (615 pt on 2026-09-22), the only state the refusal has been seen in. If
>   the edge does not move it, **stop**: that is the observation reproduced, and nothing else is
>   touched until the frame has been read.
> * **Sizes are read from the window server**, because (2) predicts a size that nothing could read:
>   the sheet is a window of its own and has no autosave. `CGWindowListCopyWindowInfo`, filtered to
>   this app's pid, gives the bounds of each of its windows, live — so it does not share the
>   autosave's staleness — and front to back, which is also item 9's reading. It is checked against
>   `NSWindow Frame main` before anything it says is used: at launch both must give the restored
>   frame. Where the two disagree later, both numbers are recorded and neither wins. The lister's
>   source goes into the walk's record.
> * **Prediction:** the sheet is the content less 24 pt each way, and the content is the frame less
>   the 32 pt title bar, so a *W* × *H* frame carries a (*W* − 24) × (*H* − 56) sheet — **616 × 559**
>   at the pushed 615, **616 × 486** at the 542 idle floor. The same offset at both sizes would be the
>   sheet window's own chrome; different offsets are a finding. Chunk 9's floors were measured with
>   five drives attached and six are attached today, so a floor that moves is reported, not adopted.
>   *⚠️ 2026-09-23: 616 × 559 at 615, exact, and **616 × 530 at 542** — different offsets, so by
>   this bullet's own test a finding. It is not chrome: a sheet window's bounds are its content.
>   Item 6 failed on it. The floor did not move with six drives: 542.*
>
> **(9) Two wordings the four above missed.** The chunk's heading — *"writes for items 1–7; the rest
> are dry"* — is (4)'s mis-sort in other words; it is rewritten when this walk's status goes into
> it. And (1) gives the T5 EVO's second job as *"the link-speed question"*. `device-identity.sh`
> gives it as the reserve discriminator for the unexplained mid-gate de-enumeration, and records the
> EVO's 5 Gb/s ceiling as settled — *"DO NOT RE-DIAGNOSE THIS."* (1)'s conclusion stands: chunk 11
> needs the EVO for nothing.

1. **Menus first, before any run.** The Window menu has a *View Last Run Report* item with **⇧⌘R** on it,
   and **only one**. SwiftUI adds a permanent Window-menu entry for every `Window` scene, titled
   with the window's title — measured on a scene probe in 2026-08-05 and recorded in
   `USBDriveTesterApp` — so while the report was a scene the app's own command sat beside an entry
   named the same. Two items here would mean the scene is still being declared somewhere.

   Press it. The report opens **as a sheet on the main window**, reading *"No run has finished
   yet"*, with a **Done** button under a divider. Press **Escape**: it closes. Press ⇧⌘R again and
   press **Done**: it closes.

   > The empty state had **no footer at all** as a window, because the title bar closed it. Mutation
   > R11 takes it away again and passes every test.

   ✅ **Re-walked 2026-09-23 on the Xcode 27 build and passed** (12:22–12:25, before any run): one
   *View Last Run Report*, with ⇧⌘R; the sheet read *"No run has finished yet"* with **Done** under a
   divider; Escape closed it, and so did Done — *"All yes"*. The empty state measured **690 × 984** on
   the restored 714 × 1040 frame, which is (*W* − 24) × (*H* − 56) exactly.

2. **Start a run and let it finish.** The report appears **by itself**, as a sheet, without the
   Window menu being touched. The headline and the figures are this run's.

   ✅ **Passed 2026-09-23** (run 1, the thumb, 12:33–12:34): *"Report is up by itself, headline
   Completed"*. It was 616 × 559 on the frame pushed to 615 at Start, exactly as predicted, in front
   of the main window, with one message beginning `run report: `.

3. **While the report is up, try to start another run.** You cannot: the sheet is window-modal, so
   Start, Pause, Stop and the drive list are all unreachable. **That is the whole point of the
   change** — a run beginning clears the previous run's report, and on hardware that emptied a
   report window somebody was reading.

   ✅ **Passed 2026-09-23**: with run 1's report up, clicks in the strips of the main window around
   the sheet reached nothing, and no pre-run dialog appeared — *"as expected"*.

4. **Press Done, then ⇧⌘R.** The same report comes back, with the same content. Dismissing does not
   discard it; only a new run does.

   ✅ **Passed 2026-09-23**: Done, then ⇧⌘R, brought run 1's report back — *Completed*, with the same
   figures.

5. **Start a second run and, while it is running, look at the Window menu.** *View Last Run Report* is
   **greyed out**, and ⇧⌘R does nothing. During a run there is nothing to show — the report was
   discarded as the run began — and a window-modal sheet would put Pause and Stop out of reach.

   > Mutation R12 removes the disabling and passes all tests; `AppModel` still answers correctly,
   > and what the mutation deletes is the menu asking.

   ✅ **Passed 2026-09-23** (run 2, 15:43:29–15:44:09): *View Last Run Report* was greyed and ⇧⌘R did
   nothing — *"everything worked as expected"*. The window-server sampler saw the Window menu open at
   15:43:47, and no sheet at any point in the run.

6. **Resize the main window — small, then large — and raise the report at each size.** The sheet
   fills the window less a margin, never overhangs it, and never runs off the screen. At the
   window's own minimum the report still shows its headline, scrolls its body, and keeps
   **Export report…** and **Done** on screen.

   > Rendered at 616x461 before this was written, which is the sheet at the window's minimum, and
   > nothing was clipped. What a render cannot answer is whether the sheet really gets that size,
   > because a sheet has its own window.

   ❌ **FAILED 2026-09-23 on the Xcode 27 build: the sheet overhangs the window below about 600
   pt.** At the 542 pt idle floor it measured **616 × 530** against the predicted 616 × 486 and hung
   **20 pt below the window's bottom edge** — *"Yes, it overhangs"* — and the same reading came back at
   15:01. The rest passed: at the floor, *"all three visible"*; at the zoomed size, *"fills with the
   margin as predicted"*; and the sheet never ran off the screen. **Owed**, by user decision. The
   quoted note above is exactly the question: the sheet does **not** really get that size. The table,
   what it rules out and the candidate are in the re-walk box at the top of this chunk.

   🔧 **2026-09-24: fixed headlessly, not re-walked.** The window can no longer be dragged shorter
   than its content, which was where the oversized sheet came from. **Predicted at the floor on the
   build that carries the fix: 640 × 600 and a 616 × 544 sheet, its bottom edge 24 pt inside**, with
   six drives. The box at the top of this chunk has the account and the rest of the predictions.
   This item stays ❌ until it is walked on that build.

   ✅ **PASSED 2026-09-25 on that build.** At the 600 pt floor with six drives, a 616 × 544 sheet
   24 pt inside the window, with its headline, a scrolling body, **Export report…** and **Done** on
   screen; 616 × 532 at the 588 pt floor with one drive; exact at 615 and at 1027 × 1304 as well; no
   drag below the floor; never overhanging, never off the screen. The readings are in the box at the
   top of this chunk.

7. **Press ⌘Q while the report is up. The report goes and the app quits — one keystroke, both.**
   *Quit USBDriveTester* is **not** greyed here. Also try the close button: it should still be dead
   while the report is up, and work once it is gone.

   > **This item's expectation has now been reversed twice, and the second reversal is the answer to
   > the question the first one left open.**
   >
   > It first read *"the app quits"*, derived from `QuitPolicy`: no run is active whenever a report
   > is on screen, so the policy answered `.quitImmediately`. On 2026-08-21 that was reversed to
   > *"expect it to do nothing"* — **the policy was not what decided.** A window-modal sheet blocks
   > ⌘Q before `applicationShouldTerminate` is reached, and the report is the same kind of sheet as
   > the pre-run dialog on the same window. That reversal was right, and the underlying cause was
   > measured six days later: `NSApp.terminate(_:)` is refused by AppKit *before* the delegate.
   >
   > It was left explicitly open **"until this has been seen"** whether the report *ought* to block
   > quitting. It has been seen, and on **2026-09-04 the user decided: it ought not.** A report is a
   > document you have finished reading. Increment 12 built the custom Quit command that the
   > 2026-08-21 note said would make this a real option, and the report is the one run-time surface
   > a quit may discard. The pre-run dialog's refusal was re-affirmed in the same decision.
   >
   > So the check is back to *"the app quits"* — by a different route, and for a reason rather than
   > by accident. If ⌘Q does **nothing** here, the fix has regressed; if it quits but leaves the
   > report's sheet on screen for an instant first, say so, because the ordering is the fix.
   >
   > ✅ **RE-WALKED AND PASSED 2026-09-04.** One keystroke takes the report down and the app with
   > it. The question this item parked on 2026-08-21 is closed.

   ✅ **Re-walked 2026-09-23 on the Xcode 27 build and PASSED**, in two parts because a close is a quit
   (see the note under correction (7)). **With run 2's report up**, *Quit USBDriveTester* was not
   greyed, and one ⌘Q took the report and the app — *"app quit in one keystroke. The Report sheet
   closed right before the app quit."* A 20 ms watch of the window server agrees: the sheet slid out
   16:00:37.516–.728, the main window stood alone at .781, and nothing of the app's was on screen at
   .810. Nothing lingered. The log has `quit command: … report=true …` and `discarding the run report`
   at .473, then `ending sheets: 3 window(s), 1 sheet(s), 0 with no parent; 1 still flagged
   afterwards` at .746, then `terminate requested: runIsActive=false disposition=quitImmediately` at
   .774, and no `refused` line. The 273 ms between the first line and `ending sheets` is the
   slide-out, inside one synchronous call: `dismissForQuit`, then `AttachedSheets.endAll()`, which
   logs after `endSheet` returns. The terminate came on the next turn, 28 ms later. This record cannot
   tell whether SwiftUI's state change or `endSheet` moved the sheet. *"1 still flagged afterwards"*
   is not a failure: `isSheet` stays true after `endSheet(_:)` returns, as `AttachedSheets`' own doc
   comment says, and the test is that the terminate follows — it did.

   **After a relaunch** (pid 70736), ⇧⌘R raised the empty state at 616 × 559, the same size as a full
   report. Done removed it, and the close button then quit the app: `terminate requested: …
   quitImmediately` at 16:09:08.838, with no `quit command` line, because that path is the close and
   not ⌘Q. **The close button is *disabled* while a sheet is up, not merely dead** — *"technically I
   was not able to click it"* (user). There is no click for it to ignore, so *"it should still be
   dead"* is met by its being greyed. The daemon was still pid 95762 after both quits.

8. **Ask for a run that cannot start.** Select a drive, press **Start**, and **while the pre-run
   dialog is up, unplug that drive.** Then press Proceed. Preparation aborts and the failure is
   reported — **and no report sheet appears.** A sheet reading "No run has finished yet" straight
   after pressing Start would be worse than none.

   > ⚠️ **The induction was rewritten on 2026-09-04, at the keyboard, because the old one no longer
   > works.** It read *"the easiest is to pull the drive after selecting it"*. It is not: pulling a
   > drive that is merely selected makes `DeviceDiscovery` drop it from the list and **move the
   > selection to the next drive**, so Start then runs a perfectly good test on a *different* drive.
   > Walked that way on 2026-09-04 and it wrote to the drive below the one that had been chosen.
   >
   > **The dialog is the timing window, and it is unlimited.** `RunController` captures the device
   > in `PendingStart` at the **press**, so the prompt, the run, the report and the metrics panel all
   > name the drive that was chosen — and preparation goes ahead against that captured drive even
   > once discovery has moved on. Pulling it while the dialog waits therefore aborts preparation
   > reliably, and nothing is unmounted, because nothing is unmounted until the dialog is answered.
   >
   > **This is not a defect in the app** — it is FR-DEV-7 keeping the list current, and the capture
   > is what stops the prompt naming one drive while the run writes another. It is a defect in this
   > item, which had gone stale without anything noticing.

   ✅ **Passed 2026-09-23** (15:51:32–15:51:51). The thumb was pulled with the dialog up
   (15:51:37.081) and Proceed pressed at 15:51:45.441. Preparation aborted — `run aborted before any
   write: …`, then `starting → idle on startAborted` — the failure alert came up, and there was **no
   report sheet at any point**: *"No report sheet"*, and the sampler agrees. The alert's text is the
   abort's reason, which `RunControlsView` passes straight through; the user summarised it as *"the
   device was no longer on the bus"*.

   ⚠️ **The note above describes a mechanism that did not happen on 2026-09-23.** Preparation did not
   go ahead against the captured drive. The moment the thumb went, discovery moved the selection to
   **the 22 TB Seagate** (15:51:37.291: *"the first usable drive (FR-DEV-3), because the selected one
   has gone"*). The guard `selectionStillNamesTheDrive()` (`DevicePreparation.swift`, in since
   `1a10438`, 2026-08-18) then stopped the start before anything was unmounted: *"The drive this run
   was authorised for is no longer the selected drive — it was disconnected or replaced while the
   confirmation was open. Nothing has been unmounted and no drive has been written to."* The start was
   the thumb's, captured by serial at the press, so the Seagate was never its target. The outcome is
   the one this item expects; only the note's account of how it comes about is wrong. Whether that
   account was also wrong on 2026-09-04 is not recorded.

9. **Open the diagnostics window (⇧⌘D), leave it in front, and finish a run.** The **main window
   comes forward** with the report on it. A sheet on a window behind another one is a dialog nobody
   sees, which would read as a run that finished and said nothing.

   ✅ **Passed 2026-09-23** (run 2's finish, 15:44:09). The diagnostics window was raised with ⇧⌘D and
   left in front. At the finish the main window came forward with the report on it — *"main window
   came forward with report on top"* — and the sampler's first reading after the finish lists the
   sheet, then the main window, then diagnostics. The report was 616 × 559, on a window just pushed
   from 557 to 615 pt: see the first observation in the re-walk box.

10. **Log check, across the whole chunk.** `run report: …` appears once per finished run, and
    `no report: …` for a refused call. Neither should appear twice for one press.

    > ⚠️ **The strings are wrong** — a refused call logs `no run report:`. See correction (6) above
    > item 1 (2026-09-23) for the real messages and what this walk expects of each.

    ✅ **Passed 2026-09-23**, against correction (6)'s expectations exactly, 12:20–16:15. There were
    **2** messages beginning `run report: `, **0** containing `no run report:`, **0** `device loss
    with no report:`, **1** `run aborted before any write:` and **4** `pre-run prompt raised:`, and
    every one names serial `2211190533300386001515`. The quits and the relaunch changed none of them,
    and the same predicate finds both launches' `registration manager initialised`, so the search was
    live.

11. **With the pre-run dialog up, press ⇧⌘R. Then Cancel the dialog and wait.** *(Dry — press
    Start and answer nothing.)* Nothing should appear: not while the dialog is up, and **not when
    it goes away**. Check the Window menu too — *View Last Run Report* should be **greyed** while the
    dialog
    is open.

    > **This item was written as a probe and found a defect on 2026-08-21. It is now the regression
    > check for it.** The menu item asks the *run* state, and Start does not enter `starting` until
    > the dialog is answered — so at that moment the rule said the report could be raised. What was
    > expected to stop it was the sheet itself: a window-modal sheet was believed to swallow menu
    > commands, which is what check 6.1 concluded from ⌘Q in increment 5.
    >
    > **It does not.** The command ran, SwiftUI queued the second sheet because one window cannot
    > show two, and the report appeared **by itself** the moment the dialog was cancelled — a modal
    > arriving at a time nobody asked for it. 6.1 is narrowed rather than overturned: ⌘Q is AppKit's
    > terminate and takes a different path from an app-declared command; only that path is
    > intercepted.
    >
    > The fix moved `pendingPrompt` out of `RunControlsView`'s `@State` and onto `AppModel` —
    > whether a modal is up is a fact about the *window*, and the menu item lives in a `commands`
    > builder with no environment to read a view's state. `reportRequestedFromMenu()` re-checks the
    > rule rather than trusting the item's `.disabled`, because mutation **S3** shows what a rule
    > living only in a view modifier is worth: the menu setting the flag itself passes every test.

    ✅ **Re-walked 2026-09-23 on the Xcode 27 build and passed** (12:27:51–12:28:39, before any run,
    on the thumb's dialog). *View Last Run Report* was greyed while the dialog was up, and ⇧⌘R raised
    nothing. Nothing appeared when the dialog was cancelled, or in the 44 s after — *"everything
    worked as expected"*, and the window server found no sheet at 12:29:23. The log has `pre-run
    prompt raised: full warnings; drive serial 2211190533300386001515`, then `pre-run prompt
    dismissed: cancel; run issued: false`, and no report line.

**No longer known, and worth recording as resolved:** a 13.3-inch Mac at its *smallest* scaling
(1152x720) has 620 pt for a window, and until 2026-08-22 `starting` needed 638 — a stated non-goal
against the committed 1280x800 budget, carried since 2026-08-20. **Deleting the refusal sentences
took the worst case to 613, so every scaling that machine offers now fits**, the tightest by 7 pt.
That was not why they were deleted; it is what deleting them bought.

7 pt is thin, and `scripts/window-fit-check.sh` reports all three scalings on every run, so the
next row added to that pane will say so rather than quietly reintroducing the non-goal.

> ⚠️ **It is 5 pt, not 7 — measured on the shipped window 2026-09-22** by chunk 9's re-walk, which
> found it pushed to **615 pt** at Start where the gate models 613. Every scaling still fits; the
> tightest does so by five points, and "thin" is the right word for it.
>
> ⚠️ **And these two paragraphs are the lapse their own commit had just finished warning about.**
> The chunk 9 write-up grepped the claim as *"7 pt to spare"* and *"with 7 pt"* and corrected it in
> six places. It said the same thing here in two more wordings — *"the tightest by 7 pt"* and *"7 pt
> is thin"* — **in the same file the walk was being written into**, and the grep sailed past both.
> CLAUDE.md's rule is *grep each noun in the claim*; the number is a noun, and one spelling of it is
> not the claim. Found 2026-09-22 while laying out chunk 11, one commit later.
>
> ⚠️ **2026-09-24: 1152x720 is not maintained any more** (NFR-USE-9's amendment of that date), so
> nothing above about that scaling is a current claim. `window-fit-check.sh` no longer reports
> that scaling, and its worst case is **614**, not 613: `deviceListFloor` went to the table's own
> 104 when chunk 11's item 6 was fixed. It still happens to fit 620, and nothing will notice when
> it stops.


### Chunk 12 — the link speed before the run (2026-08-23) *(items 1–6 are dry; 7 and 8 need a run)*

The negotiated USB link speed now appears in the **Selected device pane**, read by the app from the
IORegistry at enumeration, and no longer appears in the live metrics panel. The standing backup
advice is gone from the same pane.

**Items 1–4 are the only cover the read has.** Two mutations — a misspelled registry key, and the
pane wired to a constant — survived all 1025 tests. The `devices` render caught both, but a render
is taken on demand and this list is what makes it a habit.

1. **The row is there, and in the right place.** Select a drive. The Selected device pane shows
   **USB link speed** as the **last row of the grid, directly after Mounted volumes**, reading
   something like `5 Gb/s (USB 3.0)`. Not `—`, unless item 4 explains why.

2. **It agrees with an independent instrument.** Run

   ```bash
   /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/scripts/usb-speed-check.sh
   ```

   and find the selected drive by product name. Its code must map to the speed the pane shows —
   `2 → 480 Mb/s`, `3 → 5 Gb/s`, `4 → 10 Gb/s`. **This is the check that a wrong key or a wrong
   mapping cannot pass**, and it is why the row is worth trusting at all. Read-only; it changes
   nothing.

3. **It is per-drive, not sticky.** Click through every attached drive in turn. Each shows **its
   own** speed, and a drive at a different speed from the one before it changes the row. A value
   that never changes is the stale-pane defect this project has already had twice — once in the
   readiness banner, once in the metrics panel.

4. **It follows the port, which is the whole point.** Move one drive to a port or hub of a
   different generation and let the list refresh. **The number must change.** This is the only item
   that tests the feature's actual purpose — *did this drive negotiate the link I expected* — and no
   render can stage it, because a render sees whatever is plugged in at the time.

   > **Do not reach for the 4 TB T5 EVO here. Measured 2026-08-25 and settled.** It is the obvious
   > candidate — a drive sitting at 5 Gb/s while 10 Gb/s ports stand free — and it **cannot move**:
   > two built-in Mac mini ports and two cables all produced code 3. The T5 EVO is a USB 3.2
   > **Gen 1** product rated near 460 MB/s, so `5 Gb/s (USB 3.0)` is its correct and only reading.
   > Recorded in the FIXTURE block of `scripts/lib/device-identity.sh`; do not re-diagnose it.
   >
   > **Use a drive already at code 4 and move it DOWN.** The 1 TB Portable SSD T5 is the Gen 2 drive
   > on this bench, and a device negotiating 10 Gb/s is certainly capable of 5 — so the downward
   > direction cannot fail for capability reasons, which is what makes it a test of the app rather
   > than of the hardware. **A drive that fails to change on the way down is the app.**
   >
   > **That is how it was discharged, 2026-08-25.** The 1 TB Portable SSD T5 moved from a 10 Gb/s
   > port to a 5 Gb/s one and the row went `10 Gb/s (USB 3.1 Gen 2)` → `5 Gb/s (USB 3.0)` on
   > replug. The EVO attempt is kept above rather than deleted: it is the reason the downward
   > direction was chosen, and without it the next walker repeats it.

   If a drive ever shows `—`, say so: that is the honest-unknown path, and it is **unverified on
   this hardware**. Every USB device on this machine reports a `Device Speed`, so the fallback has
   never once been exercised for real. The `devices-unmounted` render is the nearest standing check
   and it uses a fixture, not a drive.

5. **The advice is gone.** The Selected device pane contains **no** sentence beginning *"Testing can
   cause data loss"*. Nothing else in the pane moved: the identity line, the grid, the readiness
   banner and the closing block-size note are all still there, in that order.

6. **FR-WARN-1 is still discharged.** Press Start. The pre-run dialog still carries the full backup
   warning in its own words. If warnings are suppressed, the brief confirmation still names the
   device by model and serial, and the full text is still reachable from the diagnostics window.
   **This is the item that says the deletion cost nothing**: the pane line was the second copy, and
   only the second copy was removed.

7. **The metrics panel has lost the row, and nothing else.** With a run under way, the *Live run
   metrics* panel shows **Read, Write and R-W-R-C** and **no** *USB link negotiated at* row. The
   paragraph under them still explains what those three are measured against, and the latency block
   below is untouched.

   *Corrected 2026-09-03: this said "Read, Write and Covering", twice. The row it names was deleted
   by increment 10 on 2026-09-02 and replaced by `R-W-R-C` in increment 11. The item's actual
   subject — that the link-speed row went and nothing else did — is unaffected.*

8. **The report still has both numbers together.** Stop the run and read the report. Its
   measurement block still shows **Negotiated USB link speed** among the throughput rows. This is
   where the 2026-08-04 decision now lives, so if it is missing here the decision has been lost
   rather than moved — which is the difference between this change and a regression.

### Chunk 13 — the launch-time helper gate (increment 9) *(no writes; two induced states)*

**Ask before items 3 and 4.** Both temporarily disable the helper and both are reversible from
inside the app. **Neither touches a drive**, and no run is started anywhere in this chunk.

The gate is a **sheet on the main window**, raised at launch whenever the privileged helper cannot
be used. Its decision is a pure type and is pinned by 28 tests; what none of them can see is whether
the sheet is ever **presented**, because the trigger lives in `USBDriveTesterApp.swift`, which no
harness compiles. **Mutation M4 — the modal is never presented at all — was declared a survivor in
advance and confirmed as one.** This chunk is the whole of its cover.

Read the outcomes off the log, not off the look of the dialog:

    /usr/bin/log stream --predicate 'subsystem == "com.arc3solutions.USBDriveTester"' --info

Every diagnosis prints one line — `helper gate: available — no modal raised`, or
`helper gate: notRegistered — …`. Every button press prints another.

1. **A healthy launch shows nothing.** With the helper installed and approved, launch the app. **No
   modal appears**, and the log carries `helper gate: available — no modal raised`. That line is the
   check: silence alone cannot distinguish "diagnosed healthy" from "never ran".

   **It covers M12, not M4** — the attribution was wrong here until 2026-08-27. M12 is the launch
   trigger never firing, and this line is its only cover. M4 is the `.sheet` modifier replaced by
   `EmptyView`, which prints this line **unchanged**; M4's only cover is a person seeing the modal
   in item 3.

2. **The View Last Run Report menu item is live.** ⇧⌘R raises the empty report. Dismiss it. (Item 5 is what
   this is being compared against.)

3. **`.notRegistered` — ask first.** Open ⇧⌘D, choose **Uninstall helper**, wait for
   `notRegistered`, quit, and launch again.

   * The gate appears, headed *"The privileged helper is not installed yet."*
   * **Two buttons: Register Helper, then Quit — in that order**, with Register Helper the
     emphasised one. A dialog whose prominent control is Quit reads as a dead end and is what the
     2026-08-26 decision rejected.
   * The main window is **unreachable** behind it. Try Start: it cannot be pressed.
   * **Escape does nothing.** The sheet stays. Two mechanisms hold that — the binding's setter is a
     no-op and `.interactiveDismissDisabled()` is applied — and this is the item that says so,
     because neither is visible to any test. *The increment's plan predicted Escape would dismiss
     and the sheet would re-raise; that was a prediction about the presentation layer derived from
     model code, which is the shape item 6.1 falsified. Report what actually happens.*
   * Press **Register Helper**. Log: `helper gate action: registerHelper from notRegistered`.

     **What happens next depends on the machine, and this item predicted it wrongly** (found
     2026-08-27). It said the gate moves on to *"waiting for your approval"*. On a Mac that has
     approved this app before it goes **straight to `available`** and the gate clears: the
     Background Task Management record survives the unregister — same `BTM uuid` before and after —
     so re-registering the same bundle path is re-enabled without a fresh approval. Only a machine
     that has never approved it takes the `requiresApproval` step.

     So **item 3 does not chain into item 4 here.** Induce `requiresApproval` directly instead:
     System Settings ▸ General ▸ Login Items & Extensions ▸ *Allow in the Background* ▸ toggle
     **USBDriveTester off**, then relaunch. The same toggle undoes it. Do **not** reach for
     `sfltool resetbtm` — it resets Background Task Management for every app on the Mac.

4. **`.requiresApproval` — ask first.** Induced with the Login Items toggle described in item 3.
   Two buttons: **Open Login Items…** and Quit.

   * Press **Quit**. **The app quits.** This is a regression check, not a formality: on 2026-08-27
     this button was **dead**, pressed four times with all four presses visible on the log and the
     app still running. `NSApp.terminate(_:)` is a silent no-op while a sheet is attached — AppKit
     refuses it before `applicationShouldTerminate` is consulted, so `QuitPolicy` never gets a vote.
     The gate now ends the sheet before terminating. CONSTRAINTS §1 carries the measurement.

     **Increment 12 moved the mechanism under this button without changing what it does**
     (2026-09-04): it and ⌘Q now share `dismissThenTerminate(_:)`. It deliberately does **not**
     consult the new modal policy — a Quit button on a screen you cannot get past must never be able
     to refuse — so this remains a regression check for the button in its own right, not a duplicate
     of chunk 16. Also press **⌘Q** here: the gate is a surface a quit may discard, so that quits
     too.
   * Relaunch. Press **Open Login Items…**. System Settings opens at Login Items & Extensions.
   * Enable USBDriveTester under *Allow in the Background* and **switch back to the app without
     pressing anything**. **The gate must clear by itself.** Log: `helper gate: available — modal
     dismissed, was requiresApproval`.

     Added 2026-08-27 at the user's request, after this item found that returning from Settings
     changed nothing until Open Login Items was pressed a *second* time. **This retires the question
     this item used to ask** — whether to keep one button doing double duty or add a third
     (Open Login Items… · Retry · Quit). Neither: the re-check has no button, and the action table
     approved 2026-08-26 is unchanged.
   * The re-check is **guarded on the gate being up**, so a healthy app does not issue an XPC round
     trip every time you ⌘-Tab back to it. Nothing to observe; recorded so the absence of log lines
     on an ordinary activation is not read as a fault.

5. **The report cannot queue underneath it.** With the gate up (repeat 3 if you have cleared it),
   press **⇧⌘R**. **Nothing must happen**, and nothing must appear when the gate is later
   dismissed.

   This is the check for a defect this project has already had once: chunk 11.11 found that a
   window-modal sheet does **not** swallow menu commands — the command ran, SwiftUI queued a second
   sheet, and it presented itself the moment the first was answered. At launch neither `runIsActive`
   nor `pendingPrompt` blocks ⇧⌘R, so the gate had to be added to that rule.

6. **⇧⌘D still works.** The diagnostics window opens from behind the gate — it is a separate
   `Window`, not blocked by a window-modal sheet, and it is where the fuller registration story
   lives. This is wanted, not a leak.

7. **`.versionMismatch` — ask first.** Bump `TesterProtocol.version` to 13, build, and install the
   app **without restarting the daemon**. The running daemon still answers v12 while the app expects
   v13 — the real scenario this state exists for.

   ```bash
   /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/scripts/install-app.sh
   ```

   * The gate appears, headed *"The installed helper is a different version from this app."*, and the
     body names **both** versions.
   * **Register Helper, then Quit.** A version mismatch is *not* Quit-only — the project's own
     `ProtocolVersionCheck` wording already prescribes re-registering, and this is the state most
     likely to be argued back to a dead end.
   * **Press Quit.** The app quits, first press. This state was not covered by the quit fix's other
     checks, which used `notRegistered` and `requiresApproval`.
   * **Relaunch and press Register Helper. The gate must clear**, and `pgrep -lf
     'USBDriveTester.Helper'` must report a **different pid** than before.

     ⚠️ **This step is the reason the item exists, and it was missing until 2026-08-31** — the item
     checked only that the two buttons were present and in the right order. Pressed for the first
     time (to cover mutation M9), the button **did nothing**: `register()` on an already-`enabled`
     service reports success and reloads nothing, so the same daemon went on answering the same old
     protocol version. The remedy is now unregister-then-register
     (`HelperRegistrationRemedy.replaceRunningDaemon`). A button being present is not a check that
     it works.

     Log for a good run: `helper gate action: registerHelper from versionMismatch`, then
     `uninstall requested`, `unregister() returned without error`, `register() succeeded`, then
     `helper gate: available — modal dismissed, was versionMismatch`.
   * Undo by reverting the version and rebuilding.

8. **One registration, not two.** With the diagnostics window open beside a cleared gate, press
   **Refresh** there and confirm the status shown is the one the gate acted on. There is now exactly
   one `HelperRegistration` in the app; before increment 9 the panel built its own, and two
   registration states that can disagree is what this move exists to prevent.

**Two of the five states this chunk does NOT reach**, recorded rather than glossed:

* **`.notFound`** — the daemon's plist missing from the bundle. Producing it means editing an
  installed app bundle, which is a broken install rather than a test. Its render is the only look
  anyone has had at the one-button footer.
* **`.unreachable`** — a daemon that is `enabled` and silent. Nothing here stages that reliably:
  killing the daemon lets launchd restart it, and unregistering moves the status instead. Its render
  is also the only surface in this app showing a string whose length the app does not choose.

Both diagnoses are unit-tested and both are rendered in each appearance. **Neither has been seen on
this machine**, which is what the sentence above is for.

**And two gate remedies cannot be driven from a test at all**, recorded here because a test that
tried it was written on 2026-08-27, went green, and had **really registered the daemon and really
opened System Settings** — visible on the log as `register() succeeded`. `HelperRegistration` is
constructed inside `AppModel` rather than injected, so `performHelperGateAction(.registerHelper)` and
`(.openLoginItems)` reach the real `SMAppService` and the real Settings app. A unit test that changes
machine state is not a unit test, and that one would have done it on every run of `test.sh`. Only
`.retry` is driven; **items 3 and 4 are the cover for the other two.**


> **Chunk 14's items 5 and 6 describe a build that no longer exists, and are left as written.**
> They passed on 2026-09-02 against increment 10 and are a record of that walk, not a live
> procedure. Increment 11 then added `R-W-R-C` to the panel and both report surfaces, and
> FR-METR-1's 2026-09-02 amendment removed the "about twice Write" relationship those items
> check — Read and Write no longer share a denominator, so the ratio they assert is not a
> property of the current build. **Chunk 15 covers the same ground against v14; walk that.**

### Chunk 14 — Full Disk Access at Start, and two deletions (increment 10) — **PASSED IN FULL 2026-09-02** *(item 3 needs a run; item 4 revokes a permission — ask first)*

> **All seven items passed 2026-09-02**, against a Debug build installed at 13:22 that day. The
> daemon was kickstarted first: `install-app.sh` replaces the helper binary underneath a running
> daemon, and increment 10 left the helper source untouched, so nothing would have announced the
> mismatch. No product defect found. See the header for what it did find.

Increment 10 moved NFR-INST-4's Full Disk Access check out of the Selected device pane and into the
start of a run, deleted the readiness banner entirely, and deleted the `Covering` row from all three
surfaces that showed it.

**What no test can see here, and it is most of the increment.** The FDA modal is an `.alert`, and
this project cannot render an alert at all — `.alert(_:isPresented:actions:message:)` takes
`ViewBuilder`s AppKit consumes, so there is no value to hand an `NSHostingView`. The *decision*
(which failures offer a remedy, and what both buttons say) is a pure type pinned by tests; that the
dialog appears, that its buttons are in the right order, and that the remedy button does anything
are reachable by a person and nothing else. Item 4 is the whole of that cover.

The run log is the instrument for items 1–3:

    /usr/bin/log stream --predicate 'subsystem == "com.arc3solutions.USBDriveTester"' --info

1. **The Selected device pane has lost the banner, and lost nothing else.** Select each attached
   drive in turn. Below the detail rows there is **no** readiness message, no shield icon, no
   spinner, and no gap where one used to be — the rows run straight into the caption about IOKit
   and serial numbers. **Every row that was there before is still there**: capacity, exact size,
   geometry, raw device, serial number, mounted volumes, USB link speed.

   Select a drive with several mounted volumes and one with none. Neither shows a message about
   mounting. That branch said volumes *"must be unmounted before a test can start"*, which Start
   has done for itself since increment 5 — it was instructing the user to do what the app does.

2. **Unmount a volume in Disk Utility with the app open.** The `Mounted volumes` row follows it
   within a second or two. This is the check that deleting `.onChange(of: mountedVolumeNames)` cost
   nothing: that trigger existed to refresh the banner, and the row it did not feed comes from the
   device record, which the enumerator rebuilds on every mount change anyway.

3. **A normal run still starts.** With Full Disk Access granted — the ordinary state — select the
   scratch drive, press Start and proceed. The run begins as it always did. On the log:

       run authorised: drive serial …

   **No Full Disk Access dialog appears.** This is the half of the check that says the new step is
   not refusing runs it should allow; item 4 is the half that says it refuses the one it should.

4. **`accessNotPermitted` — ask before doing this, and it is the item the increment exists for.**
   Remove **USBDriveTester** from System Settings › Privacy & Security › Full Disk Access (leave it
   listed and toggle it off, which is the reversible form). Then press **Start** and proceed past
   the confirmation.

   Five things, and the last two are the ones no test reaches:

   * a modal appears headed **"Full Disk Access has not been granted"**;
   * its body is the **helper's own words** — *"This app needs Full Disk Access before it can test
     a drive. Open System Settings › Privacy & Security › Full Disk Access, add USBDriveTester,
     then try again. Administrator rights are not sufficient on their own…"*;
   * **two buttons**, with **Open Full Disk Access Settings…** as the default and **Cancel Test**
     beside it. Escape backs out;
   * **press Open Full Disk Access Settings… and System Settings actually opens at that pane.**
     The launch gate shipped a remedy that was pressed for the first time in chunk 13 and **did
     nothing**; a remedy nobody has pressed is a remedy nobody has checked;
   * **no volume was unmounted.** Check Finder, or the `Mounted volumes` row: the drive is exactly
     as it was. This is the ordering the whole placement decision rests on — after the unmount, a
     multi-volume drive would have been taken down and remounted for a run that never started.

   Re-grant the permission, then **press Start again without relaunching the app**. The run starts.
   That is the freshness property the move was made for: the old pane, asked the same question,
   would have gone on saying the permission was missing until the selection changed.

5. **The metrics panel has two rates, not three.** Start a run and look at the live panel while it
   is going. **Read** and **Write** are there; **Covering** is gone. The paragraph beneath them
   reads *"…Every byte is read, written back and read again, so Read runs at about twice Write."*
   and no longer mentions Covering. Check it against the numbers on screen: Read should be about
   twice Write.

6. **The report and the export agree with it.** Let a run finish — the 125.8 MB thumb drive
   (serial `2211190533300386001515`) is the one that finishes quickly. In **Measurements**:
   `Read throughput`, `Write throughput`, then `Negotiated USB link speed`. **No `Covering` row.**
   The paragraph below the table begins *"Both rates are measured over the time the run spent
   working…"* — **"Both"**, not "All three".

   Export the report and open the `.md`. The same two rows, the same paragraph, no `Covering`.
   The window and the export are two renderers over one set of values and they have disagreed
   before; this is the item that looks at both.

7. **Nothing else lost a row.** In the same report, confirm the rows either side survived — the
   `Drive` and `Run` tables are unchanged, `Failed block ranges` is still there, and the latency
   block still has minimum, maximum, p99 and reads measured. A deletion that took a neighbour with
   it would read as correct on the deleted row alone.


### Chunk 15 — the throughput denominators after FR-METR-1's amendment (increment 11) — **PASSED IN FULL, 2026-09-03** *(all five items; two of the original seven were deleted unwalked)*

Increment 11 added `R-W-R-C speed` to all three surfaces, then FR-METR-1 was amended mid-increment
and the three displayed rates moved from running time to **phase time** (protocol v14). This chunk
is the only place the change is checked against reality rather than against a fixture.

**WALKED 2026-09-03, against the build installed at 12:52 and daemon PID 71058 up since 13:08:46 —
the same daemon that passed `metrics-check.sh` 128/0.** The build was confirmed to be v14 *before*
the walk, headlessly and by symbol rather than by timestamp: `deviceReadBytesPerSecond` present in
the installed binary 30 times, `sustainedReadBytesPerSecond` **zero** times, the "not comparable to
Activity Monitor" string present and "directly comparable" absent. That check exists because
chunk 14's walk was blocked by a stale `/Applications` build and had to be restarted.

**No defect was found in the product. One was found in this file** — see item 4, deleted mid-walk.

**What the walk established, in one place:**

| | 4 TB T5 EVO | 125.8 MB thumb |
|---|---|---|
| `Read` | 344 MB/s | 17 MB/s |
| `Write` | 419 MB/s | 5 MB/s |
| `R-W-R-C` | 122 MB/s | 3 MB/s |
| Activity Monitor read / write | 232 / 118 MB/s | not read |
| identity residual | **0.047 %** *(and 0.19 % on a second run)* | unresolvable — see item 3 |

* **The disclaimer is true, by the factors claimed.** App Read ÷ Activity Monitor read = **1.48×**
  against the claimed ~1.5×; app Write ÷ Activity Monitor write = **3.55×** against ~3.4×. This is
  the only measurement of that anywhere, and it is what makes the amendment defensible.
* **Activity Monitor gave three things back for free.** Its read ÷ its write = **1.966**, an
  external instrument confirming the cycle moves two reads per write. Its *write* figure **is**
  `coverageBytesPerSecond` — the `Covering` row increment 10 deleted — recovered from outside the
  app and landing **inside `metrics-check.sh`'s own band** (118/122 = 0.967, band 0.80–0.995), from
  an instrument sharing no code with it. And the gap between the two denominators, the thing the
  whole amendment rests on, **measures 3.28 % of running time**: host overhead is now a number
  rather than an argument.
* **Read and Write no longer share a ratio, and two drives prove it.** The thumb drive reads at
  **3.4× its write speed**; the T5 EVO **writes** at 1.2× its read speed. Under v13 both would have
  read exactly 2:1, because that ratio was a property of the cycle rather than of the hardware.
* **Both exports matched `ThroughputFraming.definition` character for character** — 819 chars,
  two drives, diffed against source rather than compared by eye.

**Read the FR document's 2026-09-02 amendment before walking this.** Several items below ask you to
confirm that figures **disagree** with another tool. That is the requirement, not a defect, and an
item that looks wrong to a walker who has not read the amendment will be reported as one.

**What no test can see here.**

* **That the disclaimer is TRUE.** `theDefinitionWarnsThatTheFiguresDoNotMatchAnOutsideObserver`
  asserts the report *says* these figures will not match Activity Monitor. Nothing anywhere checks
  that they actually don't, by roughly the factors claimed. **Item 2** is the whole of that cover,
  and it is the item that matters most: the disclaimer is what makes the amendment defensible, and
  a disclaimer that is wrong about reality is worse than none.
  **Walked 2026-09-03: 1.48× and 3.55× against the claimed ~1.5× and ~3.4×. It is true.**

  > ⚠️ **This bullet said "Item 3" until 2026-09-03**, and had done since the chunk was written —
  > left behind when the original item 1 was deleted and everything above it shifted down. Third
  > instance of the same defect in this one chunk, alongside item 4 and the header summary. **A
  > deletion is not finished when the item is gone: every cross-reference to a number above it is
  > now wrong**, and prose references do not fail to compile.
* **The row wiring on real data.** No test drives a SwiftUI binding. The renders cover it with
  fixtures; only a run covers it with numbers the drive produced.
  **Closed 2026-09-03**: the report sheet displayed `17 / 5 / 3 MB/s` and `480 Mb/s` for the thumb
  drive's run — the same four values its export carries, read off the screen by the walker. The
  structure and wording were confirmed separately from a `render-ui.sh out.png 720 1500 report`
  looked at rather than merely produced.
* **The quiet version mismatch had an item here and it was deleted on 2026-09-03**, at the user's
  decision, without being walked. It asked the walker to launch the app against the **v12** daemon
  still in `/Applications` and confirm the launch-time gate caught the mismatch — the only fixture
  the guard would ever get for free, since v14 was the first version whose replies did not change
  shape. `install-app.sh` was run before the item was walked and the daemon restarted from the new
  binary, so the fixture was gone.
  **What still covers it:** `theProtocolVersionIsFourteen` proves the constant moved,
  `metrics-check.sh` asserts the running daemon matches, and `helper-gate-version-mismatch` has a
  render in both appearances. **What nothing covers:** a real stale daemon producing that real
  sheet, end to end. Carried as a known gap rather than as an owed item, because the next protocol
  bump recreates the fixture and increment 12 is app-side and will not bump anything.

The run log is the instrument throughout:

    /usr/bin/log stream --predicate 'subsystem == "com.arc3solutions.USBDriveTester"' --info

---

1. **The panel's three figures, on the 4 TB T5 EVO.** Start a run and read the *Live run metrics*
   panel. Expect approximately:

   | | expected | observed 2026-09-03 |
   |---|---|---|
   | `Read` | 340–380 MB/s | 344, then 352 |
   | `Write` | 410–425 MB/s | 419, then 417 |
   | `R-W-R-C` | follows from the other two — see item 3 | 122, then 124 |

   **The bands are wide on purpose.** They were point values (376 / 419 / 130) until 2026-09-03,
   taken from `ui-probe`'s fixtures; the first walk read 344 / 419 / 122 and the walker reported
   Read as "about 10% too high", which is a defect report against a healthy drive. Write landed on
   its figure exactly and `R-W-R-C` moved *because* Read did — 344 and 419 predict 121.9 through
   item 3's identity, and 376 and 419 predict 129.8, which is the fixture. **One figure drifted and
   the other two followed it correctly.** Session-to-session variation of this size on a solid-state
   drive is not a fault, and this project has a standing rule against building guards for it.
   **Do not judge this item on the absolute figures — item 3 is the test.**

   **Write above Read is correct** — that drive genuinely writes faster than it reads, and the
   figures shown until 2026-09-02 hid it behind an exact 2:1 that came from the cycle's shape. If
   Read is about twice Write you are looking at a v13 build; go back to item 1.

   **`R-W-R-C` at roughly a third of both is correct on a drive with nothing wrong.** It is a
   per-cycle rate beside two per-phase rates. This is the figure most likely to be reported as a
   fault, which is why the paragraph beneath says so before it says anything about gaps.

2. **Activity Monitor disagrees, and by about the right amount.** ⭐ *The item this chunk exists for.*

   With the run still going, open Activity Monitor's **Disk** tab and read the same drive. Expect
   roughly **245 MB/s read and 122 MB/s write** — that is, the app's Read about **1.5×** and its
   Write about **3.4×** what Activity Monitor shows.

   Now read the paragraph under the panel's figures. It must say these are the drive's own speeds,
   measured over the time it spent doing that work, and **not comparable to Activity Monitor**.
   Check that what it claims and what the two screens show are the same story.

   **Record the four numbers**, app and Activity Monitor, read at the same moment. They are the
   evidence that the disclaimer describes reality; nothing in the suite can produce them.

   **PASSED 2026-09-03. The four numbers, 4 TB T5 EVO, one moment:**

   | | app | Activity Monitor | ratio | claimed |
   |---|---|---|---|---|
   | Read | 344 MB/s | 232 MB/s | **1.48×** | ~1.5× |
   | Write | 419 MB/s | 118 MB/s | **3.55×** | ~3.4× |

   Read Activity Monitor's **Disk** tab against the process
   `com.arc3solutions.USBDriveTester.Helper`, **not** `USBDriveTester` — the app does no I/O and
   its row shows nothing, which reads as a failure of this item. At the default 4 MiB I/O size each
   phase lasts about 10 ms, so Activity Monitor's sample window spans a hundred-odd whole cycles
   and the figure sits steady rather than swinging between the phases.

   If Activity Monitor **agrees** with the app, that is a failure: the rates have gone back to
   dividing by running time.

3. **The identity holds on real numbers.** From item 1's three figures, compute:

       2 / Read  +  1 / Write        against        1 / R-W-R-C

   They should agree to within a couple of percent on a clean run. At 376 / 419 / 130 that is
   `0.00532 + 0.00239 = 0.00771` against `0.00769`.

   This is the relationship that replaced `Read ≈ 2 × Covering`, and `metrics-check.sh` asserts it
   at 2%. Doing it once by hand is worth more than trusting the script, because the script and the
   app read the same helper: an arithmetic error shared by both would satisfy the gate and be
   visible here.

   **A shortfall in `R-W-R-C` alone is the retention signal** — bytes the drive accepted and could
   not read back unchanged. If it comes out low, check `chunks failed` and the report's failed-range
   table before concluding the arithmetic is wrong.

   **PASSED 2026-09-03, twice.** Panel figures 344/419/122 gave `0.00820059` against `0.00819672`
   — predicted 121.94, observed 122, residual **0.047 %**. A second run's *report* figures,
   352/417/124, gave residual **0.19 %**. Both are inside a 2 % tolerance by more than an order of
   magnitude, and the arithmetic was done off the screen rather than through the helper, which is
   what the item asks for.

   **It cannot be walked on a slow drive, and that is arithmetic rather than a fault.** The thumb
   drive displays 17 / 5 / 3 MB/s, every figure rounded to a whole MB/s before it is shown. Read in
   `[16.5,17.5)` and Write in `[4.5,5.5)` put predicted `R-W-R-C` anywhere in `[2.912, 3.377]`,
   while a displayed 3 means the true value is somewhere in `[2.5, 3.5)`. The intervals overlap
   almost entirely: consistent, and untestable. **Walk this item on a drive fast enough to give
   three significant digits.**

**~~Item 4 as numbered until 2026-09-03 — "The idle panel shows dashes, not zeroes or minus
ones."~~ DELETED 2026-09-03 without being walked. The item was wrong about the app, and it was
inverted.** *(Left unnumbered deliberately: a struck-through `4.` in the list competes with the
live item 4 below it, which is exactly the collision this record is about.)*

   It asked for three rate rows reading `—` before a run starts. **There are no rows before a
   run.** `RunMetricsView` shows `idlePlaceholder` instead — *"Measurements appear here while a
   run is under way. When one finishes, its results … open in the run report, where they can be
   exported."* — and the rows-behind-the-placeholder state the item describes is **a defect that
   was found and fixed**. The comment at the top of `RunMetricsView.body` records it: the
   placeholder is *"replaced rather than overlaid"*, because an overlay left a row of em-dashes
   visible **behind** it, "so the panel showed empty measurements and a note saying there were
   none — two statements of the same thing, one of which looked like data."

   **So the item passed on the broken build and invited a false failure report on the correct
   one** — the exact inversion this file warns about in its own header, now found in a chunk
   written three paragraphs below that warning. The walker read the screen, recognised the
   placeholder as correct, and reported the item rather than the app.

   **And this file already knew.** Check 11.4, walked and passed on 2026-08-20, says the idle
   panel is *"exactly its two lines of copy"*. The contradiction was 600 lines apart in one
   document, and writing the new item did not include reading what the file already said about
   the same surface. **A new checklist item must be checked against the existing ones that touch
   its screen**, not only against the source — the search that would have caught this is
   `grep -n "idle" ` on this file, and it takes seconds.

   **What covers the em dash instead, which is more than the item asked for.**
   `unmeasuredFiguresRenderAsAnEmDashAndNeverAsZero` drives the wire sentinel `-1` through
   `RunReport` into the rendered markdown and asserts `—` on all three rows — end to end, wire to
   artefact. `everyFormatterRendersAnUnknownAsAnEmDash` pins every formatter's unknown. The
   `0 MB/s`-means-*stalled* distinction the item existed to protect is
   `MetricsFormatting.throughput`'s `>= 0` guard, and the first of those tests exercises exactly
   it. `metrics-idle` renders the placeholder in both appearances.

   **Numbering:** old items 5 and 6 are now 4 and 5. This is the second item deleted from this
   chunk; the first was the v12/v14 mismatch walk, recorded in the chunk's header above.

4. **The report and the export agree, and both explain themselves.** Let a run finish, or stop one.
   In **Measurements**: `Read throughput`, `Write throughput`, `R-W-R-C speed`, then `Negotiated USB
   link speed`. The paragraph below the table begins *"Each rate is measured over the time the drive
   spent doing that work…"* and names Activity Monitor as a tool these figures will **not** match.

   Export the `.md` and open it. **The same four rows, in that order, and the same paragraph,
   identically.** The
   exported file is the copy that gets forwarded and re-read months later, detached from any screen,
   so it is the artefact that most needs to carry the disclaimer.

   Increment 10 established the rule this checks: a rate one surface names and another refuses is
   drift, and `ThroughputFraming` exists to make the two impossible to separate.

   **PASSED 2026-09-03, on both drives, and "identically" was checked rather than eyeballed.** Each
   export's paragraph was diffed against `ThroughputFraming.definition` reconstructed from source:
   **819 characters, exact match, both files**. Row order confirmed on screen and in both exports.
   The sheet's own rendering was read from a `render-ui.sh out.png 720 1500 report` — four rows in
   order, both framing paragraphs entire, the Activity Monitor sentence intact, `Export report…`
   and `Done` present.

   **Diff the export against source; do not compare two screens.** One is a mechanical check that
   fails on a single character, the other is a person reading the same paragraph twice.

5. **A pause still costs nothing, and the ETA still converges.** Start a whole-device run on the
   125.8 MB thumb drive (serial `2211190533300386001515`), let it get going, **Pause** for a
   minute, then **Resume**.

   The ETA must not inflate across the pause, and the progress figure must not stall its own
   estimate. **This is the one denominator the amendment did not move**: `coverageBytesPerSecond`
   still divides by running time, precisely so an estimate is not built on a figure that ignores
   the time a run spends not doing I/O.

   It is checked here because it now has less company than it used to. Until v14 the displayed rates
   shared this denominator, so a defect in it showed up on three figures at once; now it shows up
   only in the ETA, and only to somebody watching one.

   **PASSED 2026-09-03: the ETA held steady across the pause**, and the exported report corroborates
   it. Read 17 MB/s over 2 × 125.83 MB puts read+verify at 14.8 s and Write 5 MB/s puts write at
   25.2 s, so **40.0 s of I/O** — against check 7.5's independent record of *30 chunks in 39 s* on
   this same drive. Elapsed was 83 s, leaving 43 s of pause and overhead. **Had running time counted
   the pause, coverage would have fallen about 1.9× and taken the ETA with it.**


### Chunk 16 — ⌘Q under every modal (increment 12) — **PASSED IN FULL, ALL NINE ITEMS, 2026-09-04** — ✅ **RE-WALKED ON XCODE 27 AND PASSED IN FULL, ALL NINE ITEMS, 2026-09-25**, on the build that carries item 6's fix *(items 4–7 need a run — 5, 6 and 7 one that writes, 4 one that must fail to start; item 3 switches the helper off and on in Login Items, which relaunches the daemon; 1, 2, 8 and 9 are dry)*

> ⚠️ **2026-09-26: this heading's parenthetical read *"(item 4 needs a run; the rest are dry)"***
> until today, and it was wrong: items 5, 6 and 7 each need a run that writes. Found walking the
> chunk on 2026-09-25 (the box below) and reworded by user decision 2026-09-26 (`PROGRESS.md`,
> *Owed* (j)). The item 3 clause is new the same day: a Login Items toggle relaunches the daemon,
> so its record and resolve line are read afterwards as after a kickstart (`CONSTRAINTS.md` §1,
> *Registering and replacing the helper*).

**Read this first.** The app no longer uses AppKit's Quit item. It declares its own, so that a
keystroke arriving under a sheet reaches code at all — AppKit refuses `NSApp.terminate(_:)` *before*
`applicationShouldTerminate` while a sheet is attached, which is why ⌘Q was dead under all five of
this app's window-modal surfaces and why the launch gate's own Quit button needed fixing separately
in increment 9. Everything below is about the replacement.

**Two items elsewhere belong to this increment and are not repeated here**: **6.1** (⌘Q under the
pre-run dialog is refused, and now says so) and **11.7** (⌘Q under the report discards it and
quits — an expectation reversed twice, most recently by the decision of 2026-09-04). Walk those in
their own chunks. **13.4** also gained a line: the gate's Quit button shares the new mechanism.

**The log is half the check.** `log stream --predicate 'subsystem == "com.arc3solutions.USBDriveTester"'`,
or Console filtered to that subsystem, category `quit`. Every press that reaches the app prints one
`quit command: …` line with the five flags **and an inventory of what AppKit actually has attached**,
including window class names.

> ✅ **RE-WALKED ON THE XCODE 27 BUILD 2026-09-25 AND PASSED — ALL NINE ITEMS, with 6.1 and 6.3.**
> About 16:39 to 20:12 at the keyboard, against the app installed 2026-09-24 18:01:53 from `77275be`, item
> 6's fix, proved by content that evening: dylib `e6e6e884…`, stub `bf787e19…`, helper `ac4d5208…`,
> re-hashed after the walk to the same bytes; protocol v15; macOS 27.0 (26A428). One launch per
> part — app pid 1475 for items 1, 9 and 2 and 6.1; 12508 for items 7, 5 and 6 and 6.3's hardest
> form; 14060 for 6.3's standard form; 14293 for item 4; 14752, then 14759, for item 3. The daemon
> was pid 1477 until item 3's Login Items toggle removed the service at 20:11:51.970, and pid 14761
> from 20:12:28, resolved to `/Applications`. Attached throughout: the 22 TB Seagate and the 1 TB
> EVO Plus. The 125.8 MB thumb was attached until item 4 pulled it, and the 1 TB scratch T5 from
> 6.3's standard form on. **Every Proceed was checked against the dialog's serial** — the thumb's
> `2211190533300386001515`, the scratch T5's `12345686DAA9`. The app selected the 22 TB Seagate by
> itself at every launch, and again when item 4 pulled the thumb, and nothing was ever started
> against it. **Invalidated by** any edit to the quit path — `AppModel`, `QuitPolicy`,
> `QuitSequence`, `AppLifecycleDelegate`, `USBDriveTesterApp.swift`; to `DevicePreparation`,
> `RunController` or `RunControllerWiring` (item 4); or to the helper gate (item 3); by a different
> installed build; and by any new Xcode or macOS major or minor release, but not a point release *(reworded 2026-09-30, `CONSTRAINTS.md` §2)*.
>
> | item | what was done | read |
> |---|---|---|
> | 1 | the app menu, by eye | **Quit USBDriveTester**, ⌘Q, last, under a separator; nothing above it moved |
> | 9 | Dock ▸ *Quit* with the pre-run dialog up | did not quit; nothing logged, as designed — AppKit refuses it before the app is asked |
> | 6.1 | the app menu and ⌘Q with the pre-run dialog up | **greyed**, and ⌘Q did nothing; *Cancel*, then ⌘Q quit — recorded at the item |
> | 2 | ⌘Q with nothing on screen, 16:41:20 | all five flags `false`, `1 window(s), 0 sheet(s)`, then `terminate requested: runIsActive=false disposition=quitImmediately` |
> | 7 | ⌘Q once during a run on the thumb | `state=confirming; 2 window(s), 1 sheet(s) [_NSAlertPanel]; key=_NSAlertPanel` at 17:43:07.823 — 2026-09-04's reading exactly — and again at 19:54:23.367, on the scratch T5 |
> | 5 | ⌘Q again, and the app menu | nothing logged, and **greyed**; the confirmation stayed up 65 s with nothing moving it, so 2026-09-04's unexplained dismissal did not come back |
> | 6 | the run left to finish under the confirmation | it finished at 17:43:43 and the report was raised behind the confirmation; **greyed** throughout; *Cancel and Quit* found `2 sheet(s) [_NSAlertPanel, SheetPresentationWindow]` and quit — 6.3's hardest form |
> | 4 | the thumb pulled under the pre-run dialog, then Proceed | the selection moved to the 22 TB Seagate at 19:57:37; `run aborted before any write` at 19:58:29.494, 1 ms after Proceed, with no call to the helper — no readiness check, no unmount, no acquire; **greyed** under the alert; *OK*, then ⌘Q quit |
> | 3 | Login Items off, relaunch, ⌘Q under the gate | `gate=true` and `discarding the helper gate` at 20:12:10.709, `disposition=quitImmediately` at 20:12:11.027; switched back on, the relaunch logged `helper gate: available — no modal raised` |
> | 8 | the scan, over 14:14–20:14 | **no hits**; the same window holds 17 `quit command` and `terminate requested` lines, so the scan was reading the right log |
>
> **Four things found, none of them in the app's behaviour** — reported 2026-09-25, not fixed:
>
> * **The live metrics panel's 1 Hz poll logs two error lines a second while the helper is
>   unreachable.** Under item 3's gate, with the helper switched off, `LiveRunMetricsPanel` still
>   asked for progress every second, and every ask logged `helper progress connection invalidated`
>   and `helper transport error: Couldn't communicate with a helper application.`, both at error
>   level (`HelperConnection.swift`, lines 439 and 784): 11 of each in the ten seconds 20:12:00–10.
>   On a failure the panel keeps its last snapshot, by design, so nothing on screen changes. It is
>   noise on the error channel, the shape of item 8's 2026-09-04 lesson, and nothing had recorded it.
>   Whether earlier builds did the same cannot be read: the log holds nothing older than 2026-09-23
>   17:52. Logging only.
> * **`HelperAvailability.swift`'s header is stale.** It says the gate *"fires at launch and never
>   again"* and that *"nothing re-diagnoses on activation or on a timer, deliberately"*, and
>   `8b0db53` added the re-check on activation on 2026-08-31 (`USBDriveTesterApp.swift`, at
>   `didBecomeActiveNotification`). Item 3's log shows it working: `requiresApproval` was diagnosed
>   four times in seven seconds, from the scene's `onAppear` and from activation. App source, so it
>   is left as it is. A comment only.
> * **This chunk's heading says *"item 4 needs a run; the rest are dry"*, and it is wrong.** Items
>   5, 6 and 7 each need a run that writes, and item 4 needs one that must fail to start, which
>   writes nothing. The heading is left as it is. An instrument defect.
> * **6.3's *"EFI not mounted"* cannot be observed on the thumb**, which has no EFI partition. The
>   standard form ran on the 1 TB scratch T5, which has one, and observed it. An instrument defect.
>
> *(2026-09-26, the user's decisions: the first two wait — the poll's noise for the next app-source
> change, in a shape agreed that day, and the header for the next edit of `HelperAvailability.swift`
> or of `AppModel.swift`, whose doc comment on `refreshHelperAvailability()` turned out to carry the
> same claim; the last two are fixed in this file — this chunk's heading and item 6.3 — with the
> old wording quoted. `PROGRESS.md`, *Owed* (h)–(k).)*

1. **The item is where it was and reads what it read.** Open the app menu — the bold one named
   *USBDriveTester*. The last item is **Quit USBDriveTester**, ⌘Q, black, at the bottom under a
   separator. Nothing above it moved.

   > The title must match what AppKit generated (`Quit ` + `CFBundleName`). A replacement that reads
   > differently would be the one visible sign that the standard item is gone.

2. **⌘Q with nothing on screen quits.** The baseline. Log: one `quit command: prompt=false
   report=false gate=false confirming=false failure=false; …` followed by
   `terminate requested: runIsActive=false disposition=quitImmediately`.

3. **⌘Q under the launch gate quits — the keystroke, not the button.** Induce the gate the way 13.3
   describes (Login Items toggle, then relaunch). Press **⌘Q**. The gate goes and the app quits. Log:
   `quit command: … gate=true …` then `quit command: discarding the helper gate`.

   > This route did not exist before increment 12. Increment 9 fixed only the button on the sheet.

4. **⌘Q under the failure alert is refused, and the item is greyed.** *(a run is asked for and must
   fail; nothing is written)* Induce it the way **7.8** does: select a drive, press **Start**, and
   **while the pre-run dialog is up, unplug that drive**, then press Proceed. Preparation aborts
   against the drive captured at the press and the failure alert appears. The 125.8 MB UDisk thumb
   is the cheapest fixture. Do **not** pull a drive during a run — this item needs a run that cannot
   *start*, not one interrupted.

   With the failure alert up, open the app menu: **Quit USBDriveTester is greyed**. ⌘Q does nothing.
   Dismiss the alert; ⌘Q quits.

   > ⚠️ **This induction was got wrong twice on the day it was written, and both are recorded.**
   > First it read *"press Start, answer the prompt, then pull the drive"* — a paraphrase of 7.8 that
   > changed what it asks for, putting the walker in the middle of a write for no reason. Corrected
   > to 7.8's own wording, and then **7.8's wording turned out not to work either**: pulling a merely
   > selected drive moves the selection to the next one and Start runs a good test on that. Found at
   > the keyboard on the first walk of this item. See 7.8, which is corrected too.

   > **This is the one behaviour change nobody asked for**, and it is here because of that. A failure
   > alert is the only modal in this app the user did not open, so a ⌘Q at that instant is a
   > keystroke aimed at an app that just interrupted them. The user decided on 2026-09-04 that it is
   > refused rather than obeyed. If that reads badly at the keyboard, say so — it is one line in
   > `QuitPolicy.disposition(underModals:)` to change.

5. **⌘Q while the quit confirmation is up is refused.** During a run, press ⌘Q — the confirmation
   appears (that is 6.2). Now press **⌘Q again**, and open the app menu: **greyed**. The dialog is
   still there and the run is still going. Answer it normally.

   > A quit is already being asked about; a second question behind the first is not an answer to it.
   >
   > ✅ **RE-WALKED AND PASSED 2026-09-04**, on a single press followed by *waiting*: the
   > confirmation stayed on screen, a second ⌘Q did nothing, and the menu item was greyed. **The
   > failure below did not reproduce and is not explained.** The log from the failing walk shows
   > `1 window(s), 0 sheet(s)` on the second press, and it is now known that an alert on screen
   > reads `2 window(s), 1 sheet(s) [_NSAlertPanel]` — so the dialog really was **gone** by then,
   > and the model was right to say `confirming=false`. Something dismissed it. Left recorded rather
   > than deleted: an unexplained dismissal of the quit confirmation is worth watching for.
   >
   > **INVESTIGATED 2026-09-04. Not reproduced, cause not established — but it is now diagnosable
   > in one log line, and two real gaps were found looking for it.**
   >
   > *Ruled out:* a second main window binding the same state. The main scene is a `Window`, not a
   > `WindowGroup` (`USBDriveTesterApp.swift`, and line 31 says why), so the `openWindow(id: .main)`
   > in `ContentView`'s `.onChange` only brings the existing one forward. Also ruled out: the
   > wind-down, which never ran — `QuitSequence` is not built until `.windingDown`.
   >
   > *That leaves exactly two movers*, and until now **neither said anything on the log**:
   >
   > * **`continueTesting()`** — the *Continue Testing* button, which is `role: .cancel`, so
   >   **Return and Escape both trigger it**. That is deliberate (`ContentView`: *"the right way
   >   round for a dialog that can end one"*), so a stray keypress reaching the alert produces
   >   exactly what was seen — and would be **the safety design working**, not a defect.
   > * **the `quitConfirmationIsPresented` setter** — SwiftUI writing `false` on its own. That
   >   *would* be a defect: a quit the user asked for, silently cancelled.
   >
   > **`quitState` now logs every transition with the mover that caused it and the sheet inventory
   > at that instant.** If this happens again the log says which of the two it was, and whether the
   > alert was still attached when the state moved:
   >
   >     quit state: confirming → idle, by Continue Testing; 2 window(s), 1 sheet(s) [_NSAlertPanel]
   >     quit state: confirming → idle, by SwiftUI dismissing the alert; 1 window(s), 0 sheet(s)
   >
   > The first is benign. **The second, with a sheet still attached, is the defect** — report it.
   > An ignored write logs too (`quit alert: SwiftUI wrote isPresented=false … — ignored`); one of
   > those follows every normal dismissal, and a *burst* of them would be its own finding.
   >
   > *Two gaps found while looking, both now closed*: a `true` write arriving while the confirmation
   > was already up could have cleared it (mutation Q2), and *Continue Testing* could undo a
   > confirmed quit (Q3). Both survived all 1,125 tests until then. Q2 is a **candidate mechanism
   > for this very item** — it was guarded in the shipped code, but nothing pinned the guard.
   >
   > ⚠️ **What the failing walk saw, 2026-09-04, kept for whoever meets it again.**
   > The second ⌘Q was **not** greyed: it logged a full press reading `confirming=false` and was
   > answered `askFirst` all over again, so the app re-asked a question that was already on screen.
   > Between the two presses — with nothing touched — the model went from `.confirming` back to
   > `.idle`, which only `quitConfirmationIsPresented`'s setter can do (`AppModel.swift`): SwiftUI
   > writes `false` into the alert binding and the setter reads that as a dismissal.
   >
   > **Not yet diagnosed, deliberately.** The log could not separate "the alert is not a sheet" from
   > "the alert was already gone", because the line carried no inventory — item 7's bug, now fixed.
   > Walk item 7 first; its `state=` and sheet count are what will settle this. **Do not treat a
   > failure here as new** until that has been read.

6. **Two modals at once are refused — the only way to see the ambiguity guard by hand.** Start a
   **short** run. Press ⌘Q to raise the confirmation, then **leave it up and let the run finish
   underneath it** (the run deliberately keeps going through `.confirming`). The moment it settles,
   the report is raised behind the confirmation. Open the app menu: **Quit is greyed**, and it stays
   greyed until you answer the confirmation.

   > Both of those surfaces would be answerable alone — the confirmation refuses, the report is
   > discarded — so this is not two refusals colliding. It is the model declining to guess: SwiftUI
   > cannot show two sheets on one window and queues the second invisibly, so with two flagged the
   > app does not know which one you are looking at, and taking down the wrong one would leave the
   > termination refused with nothing to show for it.
   >
   > If this is fiddly to induce, say so and skip it — the property has cover over all 32
   > combinations in `AppModelQuitTests`. What is uncovered is only the greying.
   >
   > ✅ **REACHED AND PASSED 2026-09-04, and it is not fiddly at all** — it happens by *doing
   > nothing*. Press ⌘Q during a short run, then simply wait: the run finishes underneath the
   > confirmation and raises the report behind it. Quit stayed greyed, and *Cancel and Quit* then
   > took both surfaces down and quit.
   >
   > **What this item cannot distinguish, and does not claim to**: Quit is greyed with the
   > confirmation alone, so the greying alone does not prove the *ambiguity guard* fired rather than
   > the single-modal refusal. The guard's own property is covered over all 32 subsets by
   > `everyAmbiguousSetIsRefused`. What a person adds here is that the state is reachable by
   > accident, which is the reason the guard exists.

7. **What a SwiftUI `.alert` really is — read one log line.** During a run, press ⌘Q **once** to
   raise the confirmation. About a third of a second later this appears:

       quit command: still running after a press with nothing in the way — the app's own guard
       answered it, state=confirming; N window(s), M sheet(s) [...]; key=...

   **Copy the whole line.** Two readings come off it, and both matter:

   * **`M sheet(s)` and the class name.** The line arrives with the confirmation already on screen.
     `1 sheet(s) [SheetPresentationWindow]` — the class items 3 and 6.1 show for a real `.sheet` —
     confirms what this app has assumed, that a SwiftUI `.alert` on macOS is a window-modal sheet
     like any other, which is why this defect covers **five** surfaces and not the three the
     increment plan named. **`0 sheet(s)` overturns it**, and then ⌘Q was never dead under the two
     alerts at all and the count in CONSTRAINTS §1 is wrong.
   * **`state=`.** It should read `confirming`. Anything else means the model has already forgotten
     that the dialog it is looking at is on screen — see item 5.

   > **Nothing shipped depends on the sheet answer** — the refusals under the alerts are the user's
   > decision of 2026-09-04, not a workaround for AppKit — but the app acts on the belief, so it
   > should be a measurement rather than an assumption.
   >
   > ⚠️ **This item was unwalkable when it was written**, because the line it names carried no
   > inventory: it was on the `error` branch of `reportARefusedTermination` only, and this line is
   > the `notice` branch. Found on the first walk, 2026-09-04, fixed the same day.
   >
   > ✅ **WALKED AND PASSED 2026-09-04, and the reading is recorded** — this item has done its job
   > and is now a regression check rather than an open question:
   >
   >     state=confirming; 2 window(s), 1 sheet(s) [_NSAlertPanel]; key=_NSAlertPanel
   >
   > **A SwiftUI `.alert` IS a window-modal sheet.** The five-surface count stands, and ⌘Q really
   > was dead under the quit confirmation and the failure alert as well as under the three
   > `.sheet`s. **The class name is `_NSAlertPanel`, not `SheetPresentationWindow`** — this item
   > predicted the wrong name while being right about the substance, so expect either. Both set
   > `isSheet`; the names are how a reader tells one kind from the other.

8. **Scan the whole chunk's log for the three errors this path can emit.** Expect no output:

       log show --last 6h --predicate 'subsystem == "com.arc3solutions.USBDriveTester"' --style compact \
         | grep -E "accounts for none of them|nothing will retry it|refusing to discard"

   * `accounts for none of them` — AppKit has a sheet attached that the model flags none of: a sixth
     window-modal surface nobody taught the app about, which is the exact shape this defect took all
     three times it was introduced.
   * `nothing will retry it` — a termination was asked for, refused, and nothing is going to try
     again. Under `state=terminating` that is the *Cancel and Quit* defect of 6.3 returning.
   * `refusing to discard` — a caller took down a modal the policy refuses, i.e. ignored the table.

   > ⚠️ **This item was unusable on its first walk, 2026-09-04, and the fix is in the app rather than
   > here.** It returned **112** hits over six hours, every one of them false. The unit suite runs
   > hosted *inside* the app bundle — same process name — and stubs `terminateAction` with a counter,
   > so the backstop's premise (*still here a turn later means AppKit refused it*) was false and it
   > fired **17 times per run of `test.sh`**. A real error would have been indistinguishable from the
   > noise. `AppModel.terminationIsInjected` now silences the backstop whenever the termination has
   > been replaced, which is the honest place for it: the report belongs to the real termination, not
   > to its callers.
   >
   > If this returns hits again, **check the PIDs first**: several PIDs each with the same small
   > number of lines, at `key=none` and `0 sheet(s)`, is a test run and not the app.

9. **Out of scope, so it is not a finding — but the Dock claim was MEASURED, not assumed.** The
   Dock icon's ▸ *Quit* calls `NSApp.terminate(_:)` directly and cannot be intercepted by any
   app-declared command, so under a modal it does what it always did: nothing. **Walked 2026-09-04
   with the pre-run dialog up: it did not quit.**

   > Worth the thirty seconds, because if it *had* quit it would be a hole rather than a curiosity —
   > a route past the pre-run prompt's refusal, on the one modal that stands between a selected drive
   > and a write. This item asserted it until then, which is the habit that produced 7.8. The report's **Export report…** panel and its error alert are `runModal()`
   app-modal panels, which behave as they do in every Mac app.


## What has no automated cover, and will not get any

* **The report body.** It sits in a scroll region, so a render at a normal window height stops at
  `## Measurements`. Checks 7.2, 7.4, 7.5 and 14.6 are what read it.

  **Corrected 2026-09-02, and it is a smaller blind spot than this entry claimed.** The stop is a
  function of the height the render was taken at, not of the scroll region: given a tall enough
  window the region has nothing left to hide, and `render-ui.sh out.png 720 1500 report` shows the
  **whole** body — the claim sentences, both framing paragraphs and the closing section. That is how
  increment 10's rewrite of `ThroughputFraming.definition` was checked. What stays true is that the
  *values* are the report's and the *wording* is only visible in the artefact; what was wrong is
  "even a render" cannot see it.

* **Which of the two refusals a log line reports (increment 12, 2026-09-04).**
  `reportARefusedTermination` tells the app's own guard voting against a quit (a `notice`) from
  AppKit silently refusing one (an `error`), and **nothing automated reads a log line**, so the
  discriminator has no cover at all. Mutation **W4** widens the notice branch to swallow
  `.terminating` — the state a wind-down that failed to terminate is left in — and passes all
  **1,123** tests. Declared in advance and measured rather than argued.

  It matters because that exact misclassification is what a first draft of this code did, and it
  would have reported the *Cancel and Quit* defect as normal behaviour on the very walk that found
  it. Chunk 6.3 and chunk 16 items 7 and 8 are the cover: they ask a person to read the lines.

* **The greying of the Quit item (increment 12).** `AppModel.mayQuitFromMenu` is pinned over all 32
  combinations of the five modal surfaces, and `quitRequestedFromMenu()` re-checks the same rule so a
  refused press refuses even with the modifier gone. What nothing automated can see is the
  `.disabled(!model.mayQuitFromMenu)` in `USBDriveTesterApp.swift` — no harness compiles that file,
  the same hole mutation **R12** measured in increment 8.

  Delete it and every test still passes: ⌘Q under the pre-run prompt would be *offered*, run, refuse
  and log — a keystroke that looks like it does nothing, which is the whole defect this increment
  removed. **The greying is the only report a refusal makes to a person**, because a disabled item
  runs no action and therefore logs nothing either. Chunk 16 items 4, 5 and 6 and check 6.1 are what
  read it.

  The same file's `CommandGroup(replacing: .appTermination)` is uncovered for the same reason: delete
  it and the app falls back to AppKit's Quit item, every test passes, and ⌘Q is silently dead under
  all five surfaces again. Chunk 16 item 1 is the check that the app's own item is there at all.

* **`RunReportView` in its entirety — measured, not assumed (increment 8).** Four mutations to
  that file passed the whole suite — one against 1,008 tests, two against 1,013, one against 1,040:
  dropping a claim sentence, deleting the range caveats, relabelling the range row back to the
  wording that made it a false claim, and taking the **Done** button off the empty state, which is
  now the only way out of a sheet that has no title bar. The window and the exported `.md` are two
  renderers over one set of values; `RunReport` and `HonestFraming` pin the **values**, and nothing
  pins that this view renders them. The file carried a comment citing a `RunReportViewTests` that
  **has never existed** — corrected in increment 8, with what actually covers it written at the
  site. An edit to that view is unverified until it has been rendered and looked at.
* **The report's presentation, entirely (increment 8).** The report is a **sheet** now, and
  everything about raising and dismissing it lives in SwiftUI. Three mutations, each passing all
  **1,040** tests:

    * **R10** — `Done` does nothing. A window-modal sheet with no way out, standing over the
      controls that stop a run.
    * **R11** — the empty state loses the footer it never needed as a window.
    * **R12** — the menu item stops asking whether it may raise the report, so ⇧⌘R works during a
      run. `AppModel` still answers correctly; what the mutation deletes is the asking, and
      `USBDriveTesterApp.swift` is not even compiled by the render harness.

  The **decisions** are all in `AppModel` and are pinned there — seven mutations to them were caught,
  including the one that matters most: gating the report's appearance on the same rule that disables
  the menu item, which suppresses every report the app produces. Chunk 11 is the cover for the rest.

* **The two lines that tell the model a run happened (increment 8).** `RunControllerWiring.live`
  needs a privileged helper and a drive to construct, so no test builds it. **R8** stops it calling
  `runProduced`, **R9** stops it calling `runBegan`, and both pass all 1,040 tests. The methods
  themselves are well covered; that the wiring calls them is not. Chunk 11.2 and 11.4 are the check.

* **The live metrics panel.** It needs a real helper to poll; in the render harness it always shows
  the unavailable state regardless of run state. That is why 4.2's defect was invisible.
* **Sheet modality.** `AppModelQuitTests` exercises `QuitPolicy`, and in 6.1 the policy is never
  reached — the sheet answers first. **Increment 8 gave the question a second surface**, since the
  report is a sheet now as well: ⌘Q with the report up is *reasoned* to quit cleanly, because a
  report is only ever on screen when no run is active. That is exactly the kind of reasoning 6.1
  falsified, and 11.7 is what settles it.
* **Any SwiftUI binding, and the alert increment 6 added.** No test drives a `Picker`'s selection
  or presses a button in an `.alert`, so the *wiring* between the two pre-run controls and the
  model is reachable only by a person. The decision and every word of the dialog are pure types
  and are pinned; what is not pinned is that they are called at all. Chunk 8 is the cover.

* **The Full Disk Access modal, entirely (increment 10).** An `.alert` cannot be rendered by this
  project's harness — `.alert(_:isPresented:actions:message:)` takes `ViewBuilder`s that AppKit
  consumes, so there is no value to hand an `NSHostingView`, a fact increment 9 measured before
  choosing a sheet for the launch gate. So while `OutcomeOperation.fullDiskAccess`, its heading and
  `RunFailureRemedy`'s two labels are all pinned by tests, three things are not: that the alert is
  raised, that its two buttons appear in the right order with the remedy as the default, and that
  the remedy button **does anything**. The last is not hypothetical — the launch gate shipped a
  remedy whose first press, in chunk 13, did nothing at all. **Chunk 14 item 4 is the whole of the
  cover**, and the ordering half of it (no volume was unmounted) is checkable nowhere else.

* **The selection half of the drive list's auto-scroll.** The list scrolls to the selected drive
  on two triggers and only one of them can be seen. A render establishes its layout once, so the
  height trigger always fires, and deleting the selection trigger changes no render at all
  (mutation M2, 2026-08-20 — run as a predicted survivor and confirmed as one). The case it is
  there for is a *programmatic* re-selection at a **stable** window height — what a hot-plug
  produces — and neither a render nor 9.6 stages that. The reverse mutation is caught, which is
  what says the pair is not simply redundant: a selection applied while the layout is still
  settling scrolls against a viewport that has already gone.

* **Window sizing, entirely.** Nothing automated can see what size a window *opens* at, that a
  saved frame overrides `.defaultSize`, or that dragging an edge feels right. `window-fit-check.sh`
  covers the one part that is a number — the limits the view hands the window — and chunk 9 covers
  the rest. The four defects increment 7 fixed had all been sitting in plain sight of 29 render
  cases, because a render is given a size and never asks for one.

* **The IORegistry link-speed read, entirely.** `IOKitDeviceEnumerator` needs hardware, so no test
  in the suite constructs it and none ever will. Measured, not assumed: misspelling the `Device
  Speed` key and wiring the pane to a constant both **survived all 1025 tests** (M1 and M4,
  2026-08-23). The live-hardware `devices` render caught both, and `scripts/usb-speed-check.sh`
  is the independent check on the code→speed mapping — but neither runs unless somebody runs it,
  which is what chunk 12 items 1–4 are for.

  The `?? -1` fallback is worse off: it survived the suite **and** the render (M2, declared a
  survivor in advance). Every USB device on this machine reports a `Device Speed`, so the arm that
  produces the honest `—` is never taken here. It was made visible only by breaking the read at the
  same time, which printed a confident `10 Gb/s` where `—` belonged. **A drive that reports no link
  speed has never been seen by this project**, and until one is, that path is reasoning rather than
  evidence.

* **The launch gate's presentation, entirely (increment 9).** The trigger is
  `.onAppear { model.refreshHelperAvailability() }` at `ContentView`'s call site in
  `USBDriveTesterApp.swift` — a file `render-ui.sh`, `window-fit-check.sh` and `build-tools.sh` all
  exclude **by name**, and which no unit test builds. That placement is deliberate: it is what keeps
  this machine's live `SMAppService` status out of all 36 renders *(40 since 2026-09-06, and it
  still does — noted 2026-09-19)*. The cost is that **two mutations survive by construction** and
  both were declared in advance: **M4**, the `.sheet` modifier deleted,
  and **M12**, the trigger never called. Chunk 13 is the whole of their cover, and the
  `helper gate:` log lines are what make it readable rather than a judgement about a dialog.

* **`HelperAvailability.notFound` and `.unreachable`, on hardware.** The two gate states this bench
  cannot stage — a plist missing from the bundle, and a daemon that is enabled and silent. Both
  diagnoses are unit-tested and both are rendered in each appearance; neither has been seen for
  real. The other three gate states are walked by chunk 13.

**Twelve blind spots.** The count is measured against the list above, not carried forward — it
read "three" until 2026-08-23, by which point the list had grown to ten and nothing had
recounted it. Any rebuild of this area runs this list again.
