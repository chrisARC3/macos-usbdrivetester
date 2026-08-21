# Step 11 — the human checklist

**CHUNKS 1–7 PASSED 2026-08-18** (increment 5), except **7.4 and 7.5, which are new and unrun** —
added by increment 8 for FR-RPT-4's "stopped by user". Replaces the nine-item list in
`progress/step-14.md`, which increment 5 made partly unrunnable.

**CHUNK 8 IS NEW AND UNRUN** — added by increment 6 for the two pre-run controls. It is the only
cover the dropdown's and the confirmation's wiring has: both survive the whole 998-test suite.

**CHUNK 9 PASSED 2026-08-20 except 9.7**, which was written after the rest were signed off and is
owed to increment 8.

**CHUNK 10 IS NEW AND UNRUN** — added by increment 8 for FR-CTRL-5. Two mutations to
`RunControlsView` survive the whole suite in this area, and one of them ships a build that applies
every answered Restart dialog as a Start.

> **What is owed to a single pass, as of 2026-08-21:** 7.4, 7.5, 9.7 and the whole of chunk 10.
> Everything else in this file has been walked.

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

  | Volume | Node | |
  |---|---|---|
  | `Vol_ExFAT` | `/dev/disk8s2` | direct partition |
  | `Vol_HFS` | `/dev/disk8s4` | direct partition |
  | `Vol_APFS` | `/dev/disk5s1` | **synthesized from `disk8s3` — not a direct partition** |

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
   request. **Both** controls are now dimmed, with one sentence beneath them: *"I/O size and
   failure handling are fixed for the whole run — stop it to change them."*

   > Shortened in increment 7. The original ran to two sentences and cost 15 pt of window height
   > that a 13.3-inch Mac at its smallest scaling does not have. Same rule, fewer words.

   One sentence for both, not two — there is one rule. This is the row the 2026-08-19 reversal
   created, and the reason it exists is that the *first* build of this increment had the size live
   here and the mode dead, which read as one control being broken.

4. **Try the dropdown anyway** while paused. It should not open. Nothing appears in the log — a
   dimmed control that is never asked cannot refuse.

5. **Resume**, let it run, and confirm both stay dimmed while running. **Stop.**

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

> **Status: 9.1–9.6 passed at the keyboard on 2026-08-20. 9.7 has never been walked** — it was
> written after the rest were signed off, to cover the refusals collapsed in `faf9a93`. It is the
> one item in this chunk still owed, and it is owed to **increment 8**.

**Two drives attached for 9.4 and 9.6** — any second USB drive; nothing is written to either,
every check here is idle except 9.3 and 9.7.

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

7. **While a run is starting, count the sentences under the buttons.** There should be **one**
   refusal — "The drive is already being prepared." — under a status line that already reads
   "Preparing the drive — unmounting its volumes and taking exclusive access." Not three.

   Until 2026-08-20 all three drew: Start's, Pause's and Stop's, each a differently-worded version
   of the same fact, which is why exact-string deduplication never caught them. **Each one costs
   40 pt of window height**, and together they were what pushed the window past what a small Mac
   can show.

   `starting` is transient — unmount, verify, acquire, read geometry — so you may have only a few
   seconds. If you miss it, `pausing` and `stopping` collapse the same way and are easier to catch.

   No test reaches this: `disabledReasons` is private to its view. The `content-starting` render
   and this item are the whole of its cover.

### Chunk 10 — Restart (increment 8) *(writes)*

**Two mutations to `RunControlsView` survive the whole 1,029-test suite here.** No test drives a
SwiftUI view, so the dispatch that decides whether an answered dialog is applied as a Start or a
Restart, and the rule that collapses the refusal sentences, are reachable only by a person. This
chunk is their only cover.

**The 4 TB T5 EVO** (serial `00000S7CLNJ0WC02266P`) attached, and the log stream running.

1. **Start a run, let it get a few seconds in, press Restart.** The dialog says
   `pre-run prompt raised: full warnings, restart` — the `, restart` is the half that says the app
   knows which act you asked for. Above the divider, before any scrolling, it reads *"This ends the
   run in progress and starts again from the beginning. Everything it has tested so far is
   discarded — an interrupted run cannot be continued."*

2. **Cancel.** The run keeps going: no `restart authorised` line, no unmount, the metrics panel
   keeps advancing. Then press **Stop** — the report appears and names the right drive. *(That last
   part is the check that Cancel did not throw away the run's record.)*

3. **Start again, press Restart, Proceed.** In the log, in this order:
   `restart authorised: … the run in progress is discarded and the drive will be released and
   re-acquired` → `run discarded by restart: … no report is produced` → the volumes **remount and
   unmount again** → `run authorised: …` for the new run.

   **No Run Report window appears for the discarded run.** If one does, that is the defect.

   The remount-then-unmount is expected, not a fault: Restart releases the claim so the new run's
   figures are its own. macOS remounts within ~4 ms and `DevicePreparation` takes the volumes back
   down. On this drive that is three volumes appearing and vanishing in Finder.

4. **Watch the metrics panel across the restart.** The figures from the discarded run must **not**
   carry into the new one — the read-latency minimum and the chunk count in particular should drop
   back, not continue climbing. This is the whole reason Restart releases the drive: `RunSession`
   is created at `acquireDevice` and never reset, so a restart that kept the claim would report the
   old run's p99 and chunk count as the new run's.

5. **While it is restarting, count the sentences under the buttons.** There should be **one** —
   *"The run is restarting, and a new one is about to begin from the beginning."* — under a status
   line already reading *"Restarting — finishing the current chunk, then starting again from the
   beginning. The progress so far is discarded."* Not four.

   > This is `starting`'s 9.7 problem in a new state, and it was in the build until a render caught
   > it. Four sentences cost 160 pt and would have failed `window-fit-check.sh`. Mutation P12
   > removes the collapse and passes every test.

6. **Pause a run, then Restart from paused.** Same sequence, with no wait — nothing is in flight,
   so the wind-down is instantaneous. The new run must actually begin; a restart that leaves the
   window sitting on "Restarting…" for ever is the ordering defect mutation P5 describes.

7. **Suppress the warnings** (Diagnostics ▸ tick the box on a Start), then **Restart**. The log
   reads `brief confirmation (warnings suppressed), restart`, and **the discard warning is still
   there** — suppression removes the standing FR-WARN text, never a consequence of the press being
   made now. This is the item mutation P9 defeats.

8. **Press Restart, and while its dialog is open, let the run finish on its own.** Then press
   Proceed. An alert says the run could not be restarted, in the machine's own words — *"There is
   no run to restart. Use Start."* — rather than the dialog closing and nothing happening.

   > This is the one the controller had wrong: the pending record is cleared by the release, and
   > checking for it before re-evaluating the policy meant an answered dialog produced a log line
   > and nothing else. Found by the test written for it, not by reading.

**Known, and not a defect to report:** a 13.3-inch Mac at its *smallest* scaling (1152x720) has
620 pt for a window, and `starting` needs 638. The project commits to **1280x800** with the Dock —
a 700 pt budget — which every state clears by at least 62 pt (user decision, 2026-08-20). At the
smallest scaling the window fits at rest and grows behind the Dock for the few seconds a run spends
starting. `scripts/window-fit-check.sh` reports all three scalings on every run.

## What has no automated cover, and will not get any

* **The report body.** It sits in a scroll region, so even a render stops at `## Measurements`.
  Checks 7.2, 7.4 and 7.5 are the only things that read it.

* **`RunReportView` in its entirety — measured, not assumed (increment 8).** Three mutations to
  that file passed the whole suite — one against 1,008 tests, two against 1,013: dropping a claim
  sentence, deleting the range caveats, and relabelling the range row back to the wording that made
  it a false claim. The window and the exported `.md` are two
  renderers over one set of values; `RunReport` and `HonestFraming` pin the **values**, and nothing
  pins that this view renders them. The file carried a comment citing a `RunReportViewTests` that
  **has never existed** — corrected in increment 8, with what actually covers it written at the
  site. An edit to that view is unverified until it has been rendered and looked at.
* **The live metrics panel.** It needs a real helper to poll; in the render harness it always shows
  the unavailable state regardless of run state. That is why 4.2's defect was invisible.
* **Sheet modality.** `AppModelQuitTests` exercises `QuitPolicy`, and in 6.1 the policy is never
  reached — the sheet answers first.
* **Any SwiftUI binding, and the alert increment 6 added.** No test drives a `Picker`'s selection
  or presses a button in an `.alert`, so the *wiring* between the two pre-run controls and the
  model is reachable only by a person. The decision and every word of the dialog are pure types
  and are pinned; what is not pinned is that they are called at all. Chunk 8 is the cover.

* **Which controller call an answered dialog makes (increment 8).** `PreRunPrompt` carries whether
  the acknowledgement was for a Start or a Restart, and `promptDismissed` switches on it — but the
  switch is in a SwiftUI view. **Mutation P11 applies every answered Restart dialog as a Start and
  passes all 1,029 tests.** What that build does is release the drive and start over on whatever is
  selected, having shown the user a dialog about restarting. Chunk 10.1–10.3 is the cover.

* **The refusal-sentence collapse, now for a second state.** `disabledReasons` is private to its
  view, so nothing reaches it — increment 7 recorded this for `starting` and chunk 9.7 is its
  check. Increment 8 added `restarting` and **shipped it with four sentences until a render was
  looked at**; mutation P12 puts them back and passes every test. Chunk 10.5 is the cover, and
  9.7's note applies unchanged: a new transient state needs adding to
  `statesTheStatusLineExplains`, and nothing enforces that but a render.

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

Three defects, three blind spots, one pass. Any rebuild of this area runs this list again.
