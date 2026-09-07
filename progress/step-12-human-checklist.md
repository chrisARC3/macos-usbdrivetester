# Step 12 — the human checklist

> **STATUS: UNWALKED.** Written at chunk 7c on **2026-09-07**, against commit `3da3ef7`, protocol
> **v15**, helper source hash **`e19b0b3c…`**. Nothing here has been run. Chunk 7d installs the
> build these checks are about; chunk 7e walks them.

> ⚠️ **Step 11's checklist passes do not transfer to this file, and this file's will not transfer
> either.** A pass is a fact about one build on one day. Every chunk below carries a line for the
> date **and** the build it ran against, and both must be filled in — checklist 6.3 in Step 11
> passed on 2026-08-18, was silently broken four days later by a change in another step, and
> nobody noticed for thirteen days, because *"chunks 1–7 passed in full"* reads like a property
> when it is a date.

> ⚠️ **This repository lives on a removable volume.** The absolute paths below are correct for
> `/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester` as of 2026-09-07. If a pasteable
> command fails with *no such file or directory*, re-derive the root with
> `git rev-parse --show-toplevel` and paste that instead.

---

## Why this exists, in one paragraph

Step 12 is detection plus a decision plus a surface, and **only the first two have automated
cover**. The `ENXIO` classifier, the wind-down state machine, the report's sixth outcome and the
alert's text are all pure values with tests over them — 1,297 of them. What no test in this project
can reach is the seam between those values and what a person actually sees: the two-line closure in
`RunControllerWiring` that tells the model a drive went, the SF Symbol name in
`RunReportPresentation`, the `.alert` modifier itself. Every one of those is a mutation that
survives the whole suite, and every one was **declared in advance** — the wiring closure and the
symbol during chunk 6's round, the rest during 7b's — rather than discovered afterwards.

There is a second reason, particular to this step. **The alert cannot be rendered at all.**
`scripts/render-ui.sh` covers sheets and views; an `.alert` gets its own window and takes
`ViewBuilder`s AppKit consumes, so there is no value to hand an `NSHostingView` (measured in Step 11
increment 9). The most consequential dialog this feature raises — the one shown when a drive was
pulled mid-write-back and no report exists — has exactly one instrument, and it is a person looking
at a screen.

And a third: **two numbers in this step have never been measured.** The wind-down's three-second
deadline, and whether a real de-enumerating drive produces a short read before it produces `ENXIO`.
Both are pinned as *decisions* and neither is pinned as *physics*. Chunk 7 is what can answer them,
and chunk 5 below is where the answers get written down.

---

## Running it

Chunks are run **one at a time, reporting back between each.** Chunks 1 and 2 are dry — no run, no
writes, no unplugging. Chunks 3, 4 and 5 pull a cable out of a running machine and **write to the
scratch drive**.

### Prerequisites

* **The 1 TB scratch T5, serial `12345686DAA9`.** The only write-gate target in this project.
  ⚠️ **Identify it by serial, in the app's own device pane, every time** — three of the attached
  drives are T5s, BSD names move across a replug (and this step's whole subject is a replug), and
  `/dev/disk7` on one day is `/dev/disk9` on another. The **22 TB Seagate is never a write target.**

  Confirm before starting, and again after every replug:

  ```bash
  /usr/sbin/diskutil list
  ```

* **The app installed and the daemon kickstarted** — chunk 7d. ⚠️ **The helper source hash moved at
  chunk 7b**, so the installed daemon is stale for certain. Copying files does not reload it: two
  hardware gate runs on 2026-08-18 measured stale code while returning plausible numbers. Verify the
  reinstall took with `nm -U`, never by timestamp.

* **A log stream, left running throughout.** Most items here are read off a **log line**, not off
  the look of a dialog:

  ```bash
  /usr/bin/log stream --predicate 'subsystem == "com.arc3solutions.USBDriveTester"' --info
  ```

  ⚠️ **`log` is a zsh builtin — use `/usr/bin/log`.** And never infer a pass from the *absence* of a
  word: grep for the line you expect to see, not for the one you expect to be missing.

* **A second terminal for the unplug timing** (chunk 5 only). See 5.1.

---

## Chunk 1 — the alert, by eye *(dry: no run, no drive)*

**This chunk exists because `DeviceLossMessage`'s output cannot be rendered.** Its text is pinned by
ten tests in `DeviceLossMessageTests`; that the alert *displays* that text, with a working dismiss
button and no literal asterisks, is pinned by nothing.

The state is reachable only by a drive vanishing during the very first privileged call with the
helper never answering — so this chunk **induces** it rather than waiting for it.

⚠️ **This needs a temporary source edit installed to `/Applications`, and it must be reverted and
reinstalled before chunk 3.** Ask before running it. Two things force that route rather than a build
run in place from Xcode:

* **`SMAppService` records the path of the app that registered the daemon** (`install-app.sh`'s
  header says why at length), so a DerivedData build has no registered helper.
* **The launch-time helper gate is `.interactiveDismissDisabled()`.** An app with no helper sits
  behind a sheet that cannot be dismissed, and SwiftUI cannot present a second sheet on one window —
  it queues it invisibly (measured 2026-08-21). The alert would never be seen.

1. Add a temporary trigger that sets
   `model.runFailure = DeviceLossMessage.forRunWithNoReport(endedBy: .theHelperNeverAnswered)` —
   a debug menu item is the least invasive. The production path it stands in for is
   `RunController.swift:875`, `onFailure(DeviceLossMessage.forRunWithNoReport(endedBy:))`.
   Then install it:

   ```bash
   /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/scripts/install-app.sh Debug
   ```
2. The alert appears. Its title reads **"The drive was disconnected during the test"**.
3. **No literal `**` anywhere in the body.** This is the whole reason the type exists: the alert
   renders `Text(failure.text)`, a `String`, which SwiftUI does **not** parse as Markdown — only
   `LocalizedStringKey` does. The report parses it; the alert shows it. Opposite surfaces, one
   string type apart.
4. The body says a write-back **cannot be ruled out** and one chunk may be **partly written**.
5. The body says the run **cannot be continued** and to start again from the **beginning**.
6. **Exactly one button**, and it dismisses. There is no remedy on this path and none is offered —
   the drive is not attached, so nothing the app could open would change anything.
7. The window behind the alert is **usable after dismissal**: the device list responds, the app does
   not need restarting.
8. Repeat 2–7 with `endedBy: .nothingWasInFlight`. The body must say **"Nothing was being written"**
   and must **not** mention a half-written chunk. *(A paused run had nothing outstanding; telling
   that user a chunk may be half-written is a false alarm in a dialog, which is worse than in a
   document, because a dialog is read once and believed.)*
9. **Revert the edit, reinstall, and kickstart.** Confirm `git status --short` is clean, then
   re-run `install-app.sh` so chunks 3–5 measure ship code and not a build with a debug hook in it.
   ⚠️ **Do not walk chunk 3 without doing this** — every reading below would be against a binary
   that is not the product.

**Walked:** ____________  **Against build:** ____________

---

## Chunk 2 — the report's device-loss face *(dry: reads an existing report)*

`RunReportPresentation` pins that the six outcomes have six distinct symbols, that no two are told
apart by tint alone, and that only a verified clean pass is affirmative. What it does **not** pin is
that `eject.circle.fill` is a real SF Symbol. A misspelled or invented name compiles, passes every
test — they compare strings — and renders as nothing.

1. With a device-loss report on screen (chunk 4 produces one; until then use
   `scripts/render-ui.sh`), the header icon is **present and is an eject symbol in a circle**, not a
   blank space and not a question mark.
2. It is tinted **orange** (cautionary), not green.
3. It is **visibly a different shape** from the other five at 16 pt — not a variation on a mark
   inside a circle. Squint, or screenshot and desaturate; the point of the symbol is its silhouette.
4. The headline and the explanation below it both name the drive by **model and serial**.
5. **The paused case, by eye — BUILD-PLAN asks for this one specifically.** A run paused with
   nothing in flight must **not** be told a chunk may hold partly written data. It is the only case
   where `aWriteBackMayBeUnfinished` is `false` without route (a) having said which phase it was in,
   and a single hedged sentence covering all four cases would put a false alarm into a document
   somebody keeps. Chunk 4.7 produces this report.

**Walked:** ____________  **Against build:** ____________

---

## Chunk 3 — the unplug during write-back *(WRITES to the scratch drive)*

**The phase that matters.** `writingBack` is the one where this run holds the chunk's only copy of
the original and has not finished putting it back.

1. Scratch T5 `12345686DAA9` selected, confirmed by **serial** in the device pane. Start the run.
2. Wait until the metrics panel shows bytes **written** advancing — not merely read.
3. **Pull the cable.**
4. The run ends. The GUI **does not crash**, does not hang, and the window stays usable.
5. Log: `the drive under test left the machine while running: <model>, serial 12345686DAA9`
   — at **error** level, naming the drive by **model and serial**, with the BSD name labelled as
   what it was at the time. *(A log outlives the enumeration that produced the locator. This project
   has already shipped one artefact that could not say which drive it was about — 2026-08-06.)*
6. Log: `run ended: deviceLost`.
7. A **report** appears — not the alert. On this path a reply came back, so there is a document to
   show, and the report is the message.
8. The report's outcome is device loss, and its account names **which detector** accounted for it.
   Route (a) knows the block and the phase; route (b) knows only *that*.
9. **The phase named is `writingBack`**, and the report says a write-back may be unfinished.
10. **No Resume is offered.** Only start-from-the-beginning. Check the controls, not the report text.
11. Log after the release: either `the release was acknowledged after the deadline had already ended
    the run; the claim was dropped` (notice), or
    `release issued but not waited for — the helper has not answered the call it is inside, so this
    app cannot say the claim on <drive> was dropped` (error). **Record which**, with the timestamp.
    They are different endings and the difference is not visible afterwards without the line.
12. **Discovery re-runs by itself.** The scratch drive leaves the list without anything being
    clicked. *(FR-DEV-8's third obligation, and the closure in `RunControllerWiring` that fires it
    has no cover but this item — mutation m17 in chunk 7b's round deletes the call and passes the
    whole suite.)*
13. **Reconnect the drive.** It reappears in the list. Confirm by serial.
14. **Start a second run.** It is accepted — the claim from the interrupted run is not still held.
    If it is refused, the helper says so in its own words; record that verbatim, because it is the
    real recovery path for item 11's error case.

**Walked:** ____________  **Against build:** ____________

---

## Chunk 4 — the unplug while paused *(WRITES to the scratch drive)*

**Route (b) alone.** A paused run has returned from its call and issues no syscalls, so there is no
`errno` to classify: route (a) is blind here, and the DiskArbitration callback is the only thing
that can see the drive go. This is the case the whole of chunk 2 (2026-09-05) was built for.

1. Start a run on the scratch T5, confirmed by serial.
2. **Pause it.** Confirm paused — the measurements panel still shows this run's figures.
3. **Pull the cable.**
4. The run ends **at once** — it does not wait three seconds. *(Way 1 of the wind-down: nothing was
   in flight, so there is no reply that could come.)* Time it by eye against the log timestamps.
5. Log: `the drive under test left the machine while paused: …` — **the state named is `paused`**.
   This is the item that distinguishes route (b) working from route (a) having covered for it, and
   nothing else in the system distinguishes them.
6. The GUI stays alive and usable.
7. A report appears. **Its account says nothing was in flight, and it does NOT warn that a chunk may
   be half-written.** This is chunk 2 item 5's subject — check it here and record it there too.
8. Discovery re-runs; the drive leaves the list.
9. **⚠️ OWED, AND BLOCKED ON A DECISION: the multi-slice idempotency check.** One unplug is
   several events — a partitioned drive fires `DADiskDisappeared` once for the whole disk **and once
   per slice** (measured 2026-09-05; BUILD-PLAN records three notifications for a two-partition
   drive). Chunk 4 defends against that at three levels, and the middle one is not redundant: a
   mutation building one wind-down per callback armed three deadlines and **survived the whole
   suite**, because the test bench held only the latest. `threeCallbacksFromOneUnplugArmOneDeadline`
   closed it in the bench. On real hardware it is unchecked.

   **It cannot be walked with the drives currently attached.** The only partitioned drive here is
   the **4 TB T5 EVO** (serial `00000S7CLNJ0WC02266P`), which holds data, and starting a run on it
   writes to it — the 1 TB scratch T5 `12345686DAA9` is the only write-gate target in this project
   and it has **one** volume. Pausing does not avoid the write: the run has already read and written
   back whole chunks by the time it can be paused.

   Three ways out, and the choice is the user's, not this checklist's:

   * **Repartition the 125.8 MB UDisk thumb** into two volumes and use it as the fixture. Smallest
     blast radius; needs an explicit go-ahead because it erases that drive.
   * **Repartition the 1 TB scratch T5.** Destroys `fill.bin` — 999.9 GB, restored 2026-09-04 and
     re-verified — which several other gates depend on. Expensive.
   * **Accept it as uncovered on hardware** and record it in *What has no automated cover* with the
     bench test as the only evidence. Defensible: three independent defences, one of them pinned by
     a test written specifically for the multi-callback case.

   **Record the decision and its date here before Step 12 closes**, whichever it is. An item left
   silently unwalked is the shape this project has paid for.

**Walked:** ____________  **Against build:** ____________

---

## Chunk 5 — the two measurements this step has never made *(WRITES to the scratch drive)*

Everything above checks a decision. This chunk measures the two facts those decisions were made
without.

### 5.1 — how long route (a)'s reply actually takes

`DeviceLossWindDown.defaultDeadlineSeconds` is **3**, and its own documentation says the figure was
chosen to be *uncontroversially generous rather than tuned*: **"No real measurement stands behind it
yet."** This is that measurement.

1. Run chunk 3 again with the log stream timestamped to microseconds:

   ```bash
   /usr/bin/log stream --predicate 'subsystem == "com.arc3solutions.USBDriveTester"' --info --style compact
   ```
2. **The interval to record** is from `the drive under test left the machine while running` (route
   (b), the removal callback) to the line reporting the run's outcome (route (a)'s reply arriving,
   or the deadline firing).
3. **Three trials**, and record all three, not a mean. Note whether any trial reached the deadline.
4. **If any trial exceeds ~300 ms**, the three-second figure is doing real work rather than being
   theatre, and its header comment should say so with this date and these numbers. **If all three
   land in single-digit milliseconds**, say that too — the constant is then generous by three orders
   of magnitude as claimed, which is exactly what makes a deadline firing mean *something is wrong*
   rather than *something is slow*.

### 5.2 — does a vanishing drive produce a short read before `ENXIO`?

`RetentionTestEngine.classify` treats `.shortTransfer` as a **block failure**, not a device loss.
Chunk 7b pinned that decision (`ShortTransferIsNotDeviceLossTests`) and measured its cost if the
physics goes the other way — **one spurious bad range**, then the run ends. What no host-only test
can say is whether a real de-enumerating drive does it.

1. During the chunk 3 unplug, watch for a failed range recorded **immediately before** the run ends.
2. **If there is one**: a short read did precede the `ENXIO`, the cost is the one already pinned, and
   `classify`'s note should be updated from *open* to *measured, and it happens*.
3. **If there is not** — across all three trials of 5.1 — record that the drive went straight to
   `ENXIO`. That closes the note in the other direction.
4. Either way, **record the failure count** of each device-loss run. A device-loss run should report
   **zero** ranges unless a genuine short read preceded the loss. Two million ranges is the
   2026-08-06 defect and would mean chunk 1 regressed.

### 5.3 — the offset, for the gate item

BUILD-PLAN's gate asks that the logs be *"sufficient to reconstruct what happened (which device, at
what offset)"*. **Which device** is item 3.5. **At what offset** is the report's, not the log's —
chunk 5 (2026-09-06) put the block in `DeviceLossAccount` rather than only in a log line. Confirm
the report names a block, and that the block is plausible against the bytes the metrics panel showed
before the pull.

**Walked:** ____________  **Against build:** ____________

---

## What has no automated cover, and will not get any

Each of these was **declared in advance** in a mutation round and confirmed by measurement, not
argued for — chunk 6's round for the first three, chunk 7b's for the rest. The suite total was
**1,288** for both.

* **The two-line closure that tells the model a drive went (chunk 6).**
  `RunControllerWiring.live` needs a privileged helper and a drive to construct, so no test builds
  it. Mutation **m17 of chunk 6's round** deletes `onDeviceLost: { model.deviceUnderTestWasLost() }`
  and passes the entire suite. `AppModel.deviceUnderTestWasLost()` is well covered — five tests in
  `AppModelDeviceLossTests` pin that it rebuilds the list, that it does so even while discovery is
  frozen for the run, and that the selection does not survive the drive it named. **That the wiring
  calls it is not covered.** This is the same hole as increment 8's R8/R9, in the same file, for the
  same reason. **Chunk 3.12 is the check.**

  The parameter has **no default value**, deliberately — which is how the app's three call sites and
  `tools/ui-probe`'s two were found. `build-tools.sh` went 12/13 at chunk 6 for exactly that reason.
  Compile-error scaffolding catches a forgetful *caller*; it cannot catch a caller that passes `{}`.

* **The SF Symbol names (chunk 5).** `RunReportPresentation` is pinned over all six outcomes for
  distinctness, tint and non-emptiness — seven tests — and every one of them compares **strings**.
  `eject.circle.fill` being a real symbol that renders is covered by nothing: rename it to
  `eject.circle.definitely.fill` and the suite is green while the report header shows a gap.
  **Chunk 2 items 1–3 are the check.**

* **The alert, entirely (chunk 6).** Not "poorly covered" — **impossible** to cover. An `.alert`
  gets its own window and `.alert(_:isPresented:actions:message:)` takes `ViewBuilder`s AppKit
  consumes, so `render-ui.sh` cannot produce an image of it (measured, Step 11 increment 9). What
  *is* covered is everything made a pure value for that reason: `DeviceLossMessage`'s three bodies,
  their distinctness, the absence of Markdown, and that no case offers a remedy. What is not: that
  the modifier is attached, that the binding clears `model.runFailure` on dismiss, that the button
  works, that the window behind it survives. **Chunk 1 is the only instrument.**

  ⚠️ **And the state is unreachable by clicking.** It needs a drive to vanish during the very first
  privileged call *and* the helper never to answer it. Chunk 1 induces it with a temporary edit,
  which is why that chunk asks first and ends by checking `git status`.

* **`deviceUnderTest = nil` in `driveIsBack()` (chunk 4).** The controller clears the drive under
  test together with the claim, so a disappearance long after a run cannot look like *this* run's.
  The state guard would refuse a late event anyway, which is precisely why removing the line passes
  the suite: the two defences are independent and the tests only need one of them. Nothing
  automated distinguishes "refused because the state is wrong" from "refused because the subject is
  gone". **Chunk 3.13/3.14 is the nearest check** — reconnect the drive after a loss and confirm no
  second wind-down fires — and it is weaker than the mutation it stands against. Recorded as a known
  gap rather than claimed as covered.

* **Which log level a device-loss line carries.** `deviceLost`, `driveCannotBeWatchedForRemoval`,
  `releaseCannotBeConfirmed` and `deviceLostWithNoReport` are all **error**; `releaseAcknowledgedLate`
  is **notice**, and it is the *good* ending of `releaseCannotBeConfirmed`. Nothing automated reads a
  log line, so the level distinction has no cover at all — the same gap increment 12 recorded for
  `reportARefusedTermination`. **Chunk 3.11 is the check**, and it asks which of the two lines
  appeared rather than whether either did.

* **The three-second deadline as a duration.** `DeviceLossWindDownTests` injects the schedule, so
  the deadline's *behaviour* is pinned exactly — it fires once, it does not fail open, it is
  idempotent — with **no real time passing**. That is the right design (a test that sleeps for a
  deadline is slow now and flaky later) and it means the number itself is untested by construction.
  **Chunk 5.1 is the only thing that can put a measurement behind it.**

* **`errno` on real hardware.** That a de-enumerating drive returns `ENXIO` at all rests on **one
  observation** — the 2026-08-06 incident — which is evidence and not a gate.
  `FileDescriptorBlockDevice`'s header table carries the same split, and `DeviceLossTests`'s header
  says so in its second section. **Chunks 3 and 4 are the first deliberate reproduction.**
