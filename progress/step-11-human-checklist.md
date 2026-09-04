# Step 11 — the human checklist

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

> **CHUNK 16 IS OWED, and two items elsewhere are owed a RE-WALK, as of 2026-09-04.** Increment 12
> added chunk 16 — nine items, ⌘Q under every modal — and changed what two already-passed items must
> now show: **6.1** (the refusal under the pre-run dialog is unchanged, but the item now asks for the
> menu to be *greyed*, where before it asked only that nothing happen) and **11.7** (⌘Q under the
> report now **discards it and quits**, which reverses that item's expectation for the second time —
> it is the answer to the question 11.7 left open "until this has been seen"). **13.4** gained a
> line and does not need re-walking on its own. Nothing else in this file is affected.
>
> **This block was rewritten in the same commit as the chunk**, which is what the ⚠️ four paragraphs
> below demands and what it has caught this file failing three times.
>
> **Everything else was walked and passed.** Chunk 15 was written and walked on 2026-09-03 — five
> items, all passed, **no defect in the product and one in this file** (its item 4, deleted mid-walk;
> see below).
>
> **The two hardware gate scripts that had been owed since increment 8 were run and passed the
> same day** — `xpc-concurrency-check.sh` 0 failures, `retention-cycle-check.sh` 15/15 over the
> whole device. They are not checklist items and live in `BUILD-PLAN.md`; "nothing is owed" above
> means nothing on *this* list, and as of 2026-09-03 nothing is owed on that one either.
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

Non-destructive chunks come first. Only 2, 4, 5, 6, 7, 8 and 14 start a run — and **14 also
revokes a permission**, reversibly, which is why its item 4 says to ask first.

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
2. ⌘Q during a run **asks**, and **the run keeps going underneath the dialog**. *Continue Testing*
   resumes as if nothing happened.
3. *Cancel and Quit* stops at a chunk boundary, releases, quits — every volume back, EFI not
   mounted.
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

2. **Drag the bottom edge up as far as it will go.** It should stop at **563–574 pt** tall
   depending on how many drives are attached, and at that height **nothing is cut off** — the drive list, the selected-device pane and the metrics
   panel each shrink and scroll rather than clipping. Watch which one gives way first: **the drive
   list should shrink before the selected-device pane does**. That ordering is a deliberate
   decision (2026-08-19) — the list is a picker you have finished with by then, the detail is what
   stands between you and testing the wrong drive.

3. **Start a run and, while it is running, drag the window down to its minimum again.** The live
   metrics panel must **scroll**, not clip. This is the defect reported on 2026-08-19: the bottom
   three lines were cut off and unreachable by any means, which for FR-METR-2/4/5/6 is the
   requirement silently unmet rather than merely cramped. The heading stays pinned while the
   figures move under it.

   Note the window will refuse to go quite as small as it did in 9.2 — `running` needs **613–624**
   against idle's 563–574, and `starting` briefly needs the most at **627–638**. That is expected:
   the window grows a little at the moment you press Start and settles back when the run begins.

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

5. **Stop the run. Resize the window taller and shorter a few times.** Nothing should jump, flicker,
   or leave a pane stranded at the wrong size, and the three panes should give and take height
   smoothly rather than one absorbing everything.

   **The drive list scrolling under the drag is the intended behaviour, not a jump** (added
   2026-08-20, after the auto-scroll landed). It moves only far enough to keep the selected drive
   visible and only while that drive would otherwise leave the pane; a list that stays put through
   the whole drag means the selection was never in danger, which is equally correct. What would be
   a defect is the list scrolling somewhere the selection is *not*, or scrolling while the window
   is not being resized at all.

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

### Chunk 11 — the report as a sheet (increment 8) *(writes for items 1–7; the rest are dry)*

The report was a `Window` from Step 10 until increment 8 and is now a **sheet on the main window**
(user decision 2026-08-19). Nothing in the suite can see any of this: no test drives a SwiftUI view,
and `RunControllerWiring.live` needs a privileged helper and a drive to construct, so even the two
lines that tell the model a run produced a report are reachable only by a person.

**The 4 TB T5 EVO** (serial `00000S7CLNJ0WC02266P`) attached, and the log stream running. Items 1–7
need a real run; 8–10 do not.

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

2. **Start a run and let it finish.** The report appears **by itself**, as a sheet, without the
   Window menu being touched. The headline and the figures are this run's.

3. **While the report is up, try to start another run.** You cannot: the sheet is window-modal, so
   Start, Pause, Stop and the drive list are all unreachable. **That is the whole point of the
   change** — a run beginning clears the previous run's report, and on hardware that emptied a
   report window somebody was reading.

4. **Press Done, then ⇧⌘R.** The same report comes back, with the same content. Dismissing does not
   discard it; only a new run does.

5. **Start a second run and, while it is running, look at the Window menu.** *View Last Run Report* is
   **greyed out**, and ⇧⌘R does nothing. During a run there is nothing to show — the report was
   discarded as the run began — and a window-modal sheet would put Pause and Stop out of reach.

   > Mutation R12 removes the disabling and passes all tests; `AppModel` still answers correctly,
   > and what the mutation deletes is the menu asking.

6. **Resize the main window — small, then large — and raise the report at each size.** The sheet
   fills the window less a margin, never overhangs it, and never runs off the screen. At the
   window's own minimum the report still shows its headline, scrolls its body, and keeps
   **Export report…** and **Done** on screen.

   > Rendered at 616x461 before this was written, which is the sheet at the window's minimum, and
   > nothing was clipped. What a render cannot answer is whether the sheet really gets that size,
   > because a sheet has its own window.

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

8. **Ask for a run that cannot start** — the easiest is to pull the drive after selecting it, or
   otherwise make preparation fail. The failure is reported **and no report sheet appears**. A sheet
   reading "No run has finished yet" straight after pressing Start would be worse than none.

9. **Open the diagnostics window (⇧⌘D), leave it in front, and finish a run.** The **main window
   comes forward** with the report on it. A sheet on a window behind another one is a dialog nobody
   sees, which would read as a run that finished and said nothing.

10. **Log check, across the whole chunk.** `run report: …` appears once per finished run, and
    `no report: …` for a refused call. Neither should appear twice for one press.

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

**No longer known, and worth recording as resolved:** a 13.3-inch Mac at its *smallest* scaling
(1152x720) has 620 pt for a window, and until 2026-08-22 `starting` needed 638 — a stated non-goal
against the committed 1280x800 budget, carried since 2026-08-20. **Deleting the refusal sentences
took the worst case to 613, so every scaling that machine offers now fits**, the tightest by 7 pt.
That was not why they were deleted; it is what deleting them bought.

7 pt is thin, and `scripts/window-fit-check.sh` reports all three scalings on every run, so the
next row added to that pane will say so rather than quietly reintroducing the non-goal.


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


### Chunk 16 — ⌘Q under every modal (increment 12) *(item 4 needs a run; the rest are dry)*

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
   fail; nothing is written)* Induce it exactly the way **7.8** does — **pull the drive after
   selecting it**, so *preparation* fails. Do **not** pull a drive during a run: this item needs a
   run that cannot start, not one interrupted. The 125.8 MB UDisk thumb is the cheapest fixture.

   With the failure alert up, open the app menu: **Quit USBDriveTester is greyed**. ⌘Q does nothing.
   Dismiss the alert; ⌘Q quits.

   > ⚠️ **This item said "press Start, answer the prompt, then pull the drive" when it was written on
   > 2026-09-04, and that is a paraphrase of 7.8 that changed what it asks for** — it puts the walker
   > in the middle of a write for no reason. Corrected before it was ever walked. The lesson is this
   > file's own, recorded at chunk 14: restating an item is as capable of breaking it as editing one.

   > **This is the one behaviour change nobody asked for**, and it is here because of that. A failure
   > alert is the only modal in this app the user did not open, so a ⌘Q at that instant is a
   > keystroke aimed at an app that just interrupted them. The user decided on 2026-09-04 that it is
   > refused rather than obeyed. If that reads badly at the keyboard, say so — it is one line in
   > `QuitPolicy.disposition(underModals:)` to change.

5. **⌘Q while the quit confirmation is up is refused.** During a run, press ⌘Q — the confirmation
   appears (that is 6.2). Now press **⌘Q again**, and open the app menu: **greyed**. The dialog is
   still there and the run is still going. Answer it normally.

   > A quit is already being asked about; a second question behind the first is not an answer to it.

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

7. **What a SwiftUI `.alert` really is — read one log line.** During a run press ⌘Q once to raise the
   confirmation, then look for the `quit command: still running after a press with nothing in the way
   — the app's own guard answered it` line that follows a turn later. **Copy its inventory.**

   > That line arrives with the confirmation already on screen, and its inventory names the window
   > class. `1 sheet(s) [SheetPresentationWindow]` confirms what this app has assumed — that a
   > SwiftUI `.alert` on macOS is a window-modal sheet like any other, which is why the defect covers
   > **five** surfaces and not the three the increment plan named. `0 sheet(s)` overturns it.
   >
   > **Nothing shipped depends on the answer** — the refusals under the alerts are the user's
   > decision, not a workaround for AppKit — but the app acts on the belief, so it should be a
   > measurement. This is the only route left to take it: ⌘Q is greyed in every state where an alert
   > is up, so no press reaches a log from there.

8. **Nothing anywhere prints `sheet(s) attached and the model accounts for none of them`.** That
   error means a window-modal surface exists that nothing in the app has an opinion about — the exact
   shape of this defect each of the three times it was introduced. Scan the whole chunk's log for it.

9. **Out of scope, so it is not a finding.** The Dock icon's ▸ *Quit* calls `NSApp.terminate(_:)`
   directly and cannot be intercepted by any app-declared command, so under a modal it does what it
   always did: nothing. The report's **Export report…** panel and its error alert are `runModal()`
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
  this machine's live `SMAppService` status out of all 36 renders. The cost is that **two mutations
  survive by construction** and both were declared in advance: **M4**, the `.sheet` modifier deleted,
  and **M12**, the trigger never called. Chunk 13 is the whole of their cover, and the
  `helper gate:` log lines are what make it readable rather than a judgement about a dialog.

* **`HelperAvailability.notFound` and `.unreachable`, on hardware.** The two gate states this bench
  cannot stage — a plist missing from the bundle, and a daemon that is enabled and silent. Both
  diagnoses are unit-tested and both are rendered in each appearance; neither has been seen for
  real. The other three gate states are walked by chunk 13.

**Twelve blind spots.** The count is measured against the list above, not carried forward — it
read "three" until 2026-08-23, by which point the list had grown to ten and nothing had
recounted it. Any rebuild of this area runs this list again.
