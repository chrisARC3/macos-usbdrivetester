# Step 11 — the human checklist

**CHUNKS 1–7 PASSED 2026-08-18** (increment 5), except **7.4 and 7.5, which are new and unrun** —
added by increment 8 for FR-RPT-4's "stopped by user". Replaces the nine-item list in
`progress/step-14.md`, which increment 5 made partly unrunnable.

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

**CHUNK 13 IS NEW AND UNRUN** — added 2026-08-27 by increment 9, for the launch-time helper gate.
It is the only cover the gate's *presentation* has: two mutations survive the whole suite by
construction (the `.sheet` modifier deleted, and the trigger never called), both declared in advance,
because the wiring sits in the one file no harness compiles. Its items 3, 4 and 7 induce states and
**must be asked about first**; none of them touches a drive.

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

> **What is owed, as of 2026-08-27:** three things — **item 7.5** (a run allowed to reach its
> end, so the report says "Completed" with no range caveat), a **one-off recheck of 8.3's new
> placement**, the sentence having moved above the I/O size row on the same day chunk 8 was walked,
> so the walk saw it in its old position, and **the whole of chunk 13**, added by increment 9 and
> unrun. Everything else in this file has been walked — and this
> time that sentence was checked against the body before it was written.
> Chunk 10 was walked, passed, and then deleted along with the control it covered.
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

Non-destructive chunks come first. Only 2, 4, 5, 6, 7 and 8 start a run.

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
3. The panel shows `Read` / `Write` / `Covering`, with Read ≈ 2 × Covering, and **Activity Monitor
   agrees**. This is the check that closes the 2026-08-17 report at the surface it was made on.
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

1. **⌘Q and File ▸ Quit do nothing while the dialog is open** — the sheet is window-modal and
   intercepts them before `QuitPolicy` is consulted. **Wanted behaviour (user decision
   2026-08-18)**, and safe because nothing is claimed yet. Cancel, then ⌘Q quits immediately.
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
2. The report shows `Read throughput` / `Write throughput` / `Covering`, the definition paragraph,
   and the not-graded paragraph — **on screen and in the exported `.md`, identically**.
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

**Items 1 and 2 passed 2026-08-19.** Item 3 was run and is what produced the 2026-08-19 reversal:
the controls were rebuilt to one rule, so 3–6 below are new and unrun.

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

> **Status: 9.1–9.6 passed at the keyboard on 2026-08-20. 9.7 was deleted on 2026-08-22** — it was
> written after the rest were signed off, to cover the refusals collapsed in `faf9a93`. It is the
> one item in this chunk still owed, and it is owed to **increment 8**.

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

7. **Press ⌘Q while the report is up. Expect it to do nothing.** Then press **Escape** to dismiss
   the report and ⌘Q again — now the app quits. Try the close button too: it should be dead while
   the report is up, and work once it is gone.

   > **This item's expectation was reversed on 2026-08-21, before it had ever been walked, and the
   > reversal is the point of keeping it.** It first read *"the app quits"*, derived from
   > `QuitPolicy`: no run is active whenever a report is on screen, so the policy answers
   > `.quitImmediately`. **The policy is not what decides.** A window-modal sheet intercepts ⌘Q
   > before `applicationShouldTerminate` is reached — observed on hardware for the pre-run dialog on
   > 2026-08-18, recorded at `RunControlsView`, and met again by a person on 2026-08-21 — and the
   > report is the same kind of sheet on the same window.
   >
   > That is the second time in one increment that an acceptance criterion derived from model code
   > has been wrong about the presentation layer, both times in this area. CONSTRAINTS already says
   > it; the docs pass should say it louder.
   >
   > So the check is now: **does the report behave like the pre-run dialog?** If ⌘Q *does* quit
   > here, that is the finding, and it means two sheets on one window differ in a way nothing
   > predicts.
   >
   > Whether the report *ought* to block quitting is a separate question, deliberately left open
   > until this has been seen. The pre-run dialog blocking it is recorded as **wanted** — it is the
   > last thing between a selected drive and a write. A report is a document you have finished
   > reading, and one keystroke dismisses it. Today's finding that menu commands are *not*
   > intercepted makes a custom Quit command a real option if the answer is "it should not".

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
   /Volumes/1TB_Samsung/AI_Stuff/claude-code-folder/USBDriveTester/scripts/usb-speed-check.sh
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
   metrics* panel shows **Read, Write and Covering** and **no** *USB link negotiated at* row. The
   paragraph under them still explains what Read, Write and Covering are measured against, and the
   latency block below is untouched.

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
   /Volumes/1TB_Samsung/AI_Stuff/claude-code-folder/USBDriveTester/scripts/install-app.sh
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


## What has no automated cover, and will not get any

* **The report body.** It sits in a scroll region, so even a render stops at `## Measurements`.
  Checks 7.2, 7.4 and 7.5 are the only things that read it.

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
