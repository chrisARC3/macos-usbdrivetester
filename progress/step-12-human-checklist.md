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

And a third: **two numbers in this step had never been measured** — the wind-down's three-second
deadline, and whether a real de-enumerating drive produces a short read before it produces `ENXIO`.
Both were pinned as *decisions* and neither as *physics*. ✅ **Chunk 3's walk on 2026-09-09
answered the second: no short read.** The failing verify read returned `failed after 0 bytes:
errno 6`, and the cycle's own tally puts the gap between written and verified at exactly one 8 MiB
chunk. The deadline is answered in part and the answer inverted the 2026-09-08 reading; both are
written up under chunk 3's result and carried into 5.1.

---

## Running it

Chunks are run **one at a time, reporting back between each.** Chunks 1 and 2 are dry — no run, no
writes, no unplugging. Chunks 3, 4 and 5 pull a cable out of a running machine and **write to the
scratch drive**.

**Builds are installed automatically, and are never something you are asked about.** Any item below
that needs a build — a temporary hook going in, a revert taking it back out, a return to ship code —
is built and installed to `/Applications` before you are asked to look at anything. **The walk stops
for your eyes, not for shell commands.** Every install is **proved by content** — a symbol or a
string that exists only in that build — and never by a timestamp, because two hardware gate runs on
2026-08-18 measured stale code while returning entirely plausible numbers.

⚠️ **Point the content proof at `USBDriveTester.debug.dylib`, not at `MacOS/USBDriveTester`.** This
is a debug-dylib build: the app binary is a **59 KB launcher stub** holding 79 strings, and all
5,600-odd of the app's own strings live in the dylib beside it (the exact count moves with every commit; the 79 is the number that matters). Grepping the stub returns 0 for every
product string, which reads exactly like a failed install. Measured 2026-09-08, after that false
negative was taken at face value for one command. The helper is a normal binary and is grepped
directly.

⚠️ **The one thing an install cannot do for itself is reload the running daemon.** That needs
`sudo`, so a kickstart line is still handed to you whenever one is owed — and after it runs, the
`to program:` resolve line is checked, not just the version, because a kickstart can relaunch the
DerivedData copy and the handshake cannot tell two builds of identical source apart.

### Prerequisites

* **The 1 TB scratch T5, serial `12345686DAA9`.** The only write-gate target in this project.
  ⚠️ **Identify it by serial, in the app's own device pane, every time** — three of the attached
  drives are T5s, BSD names move across a replug (and this step's whole subject is a replug), and
  `/dev/disk7` on one day is `/dev/disk9` on another. The **22 TB Seagate is never a write target.**

  Confirm before starting, and again after every replug:

  ```bash
  /usr/sbin/diskutil list
  ```

* **The 125.8 MB "General UDisk" thumb, serial `2211190533300386001515`** — two exFAT slices,
  **59.8 MB and 64.0 MB**, role `multislice`. Needed by **4.9 only**. Contents expendable; never a
  retention target.

* **The app installed and the daemon kickstarted** — chunk 7d. ⚠️ **The helper source hash moved at
  chunk 7b**, so the installed daemon is stale for certain. Copying files does not reload it: two
  hardware gate runs on 2026-08-18 measured stale code while returning plausible numbers. Verify the
  reinstall took with `nm -U`, never by timestamp:

  ```bash
  nm -U /Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper | grep -c injectShort
  ```

  **2** means the installed helper contains chunk 7b's source; **0** means it does not, whatever
  the timestamps say. Then, because copying files never restarts a running daemon:

  ```bash
  sudo /bin/launchctl kickstart -k system/com.arc3solutions.USBDriveTester.Helper
  ```

  ⚠️ **On 2026-09-07 the running daemon was found to have started 2026-09-04 17:01:05 — before
  Step 12's first commit.** It had served the whole of chunks 4–6 on protocol v14 while the app
  was at v15, and the 2026-09-06 install had not restarted it. Check the daemon's age, not the
  bundle's: `ps -o lstart= -p "$(pgrep -f USBDriveTester.Helper)"`.

  ⚠️ **And check *which copy* it started, not just what version it answers.** The same day, a
  kickstart brought up a correct v15 daemon **from the DerivedData build**: `SMAppService` had that
  app's path recorded, and the version handshake cannot tell the two apart because the source is
  identical. It took a second kickstart — after the installed app had run and re-pointed the
  record — to get one running from `/Applications`.

  ```bash
  /usr/bin/log show --last 5m --predicate 'eventMessage CONTAINS "to program: " AND eventMessage CONTAINS "USBDriveTester"'
  ```

  The path in that line must be `/Applications/USBDriveTester.app/…`.

  ⚠️ **And a test run moves the record back to DerivedData — measured 2026-09-09, found
  2026-09-10.** The suite's host app runs from DerivedData, asks BTM about the daemon, and BTM
  re-points the app's record at it (`CONSTRAINTS.md` §1, *It does not stay fixed*). A running
  daemon does not feel that; the next launch comes up from DerivedData. So **after any test run,
  read the record before kickstarting** — the URL must be `/Applications`:

  ```bash
  sudo /usr/bin/sfltool dumpbtm | /usr/bin/grep -B4 '#1: 16.com.arc3solutions.USBDriveTester.Helper' | /usr/bin/grep -E 'URL|Generation'
  ```

  If it names DerivedData, launch the installed app and read it again; if that does not move it,
  Unregister then Register in the installed app's Step 3 panel does (measured 2026-09-08).
  **As of 2026-09-10 no kickstart is owed**: the installed helper is byte-identical to the one
  pid 89541 has run since 2026-09-08 16:22:50, launched from `/Applications`. Leave it running.

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
reinstalled before chunk 3.** Both installs happen automatically — see *Running it*. Two things
force that route rather than a build run in place from Xcode:

* **`SMAppService` records the path of the app that registered the daemon** (`install-app.sh`'s
  header says why at length), so a DerivedData build has no registered helper.
* **The launch-time helper gate is `.interactiveDismissDisabled()`.** An app with no helper sits
  behind a sheet that cannot be dismissed, and SwiftUI cannot present a second sheet on one window —
  it queues it invisibly (measured 2026-08-21). The alert would never be seen.

1. Add a temporary trigger that sets
   `model.runFailure = DeviceLossMessage.forRunWithNoReport(endedBy: .theHelperNeverAnswered)` —
   a debug menu item is the least invasive. The production path it stands in for is
   `RunController.swift:875`, `onFailure(DeviceLossMessage.forRunWithNoReport(endedBy:))`.
   ⚠️ **Put it outside `USBDriveTester/USBDriveTester/Shared/`** — that directory is in the helper
   source hash recipe, so an edit there lapses all four hardware gate results for a menu item.
   It is then built and installed for you:

   ```bash
   /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/scripts/install-app.sh Debug
   ```

   Proved by content before you are asked to look — the menu strings exist only in this build:

   ```bash
   strings /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester.debug.dylib | grep -c 'Device-loss alert'
   ```

   **2** means the hook is installed. ⚠️ **The hook is never committed.**
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

✅ **ALL EIGHT ITEMS PASSED.** Every one of items 2–8 was read off the screen by a person; nothing
here was inferred from a test. Item 3 (no literal `**`) and item 8 (the paused case not borrowing
the write-back warning) are the two the suite cannot reach, and both held.
9. **Revert the edit, reinstall, and kickstart.** The revert and the reinstall are automatic;
   `git status --short` must come back clean and the `strings` count above must come back **0**,
   which is the proof that ship code is what is installed. The **kickstart is yours** — it needs
   `sudo`:

   ```bash
   sudo /bin/launchctl kickstart -k system/com.arc3solutions.USBDriveTester.Helper
   ```

   ⚠️ **Do not walk chunk 3 without all of this** — every reading below would be against a binary
   that is not the product.

   **Done 2026-09-08 10:38:33.** Hook reverted from a saved pristine copy (never `git checkout`),
   rebuilt and reinstalled. Proved by content both ways: `strings … | grep -c 'Device-loss alert'`
   → **0**, and the product's own `The drive was disconnected during the test` → **1**. Working
   tree clean of the hook.

**Walked:** **2026-09-08**  **Against build:** commit `55a5c71` **plus the chunk-1 debug hook
(uncommitted, never committed)**, app installed 2026-09-08 08:26:05, protocol **v15**, helper source
hash **`e19b0b3c…`** (the hook lived in `USBDriveTesterApp.swift`, outside `Shared/`, so the hash
did not move and 7d's four gate results were not disturbed), daemon pid 69701 serving v15 from
`/Applications`.

⚠️ **What would invalidate this pass:** any change to `DeviceLossMessage`, to `RunControlsView`'s
`.alert` modifier, or to `RunFailureMessage`. The alert has no automated cover at all — see the
list at the end of this file — so this pass is the *only* evidence that dialog renders correctly,
and it is evidence about one build on one day.

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
3. **No two of the seven collide in greyscale at 16 pt.** That is what NFR-USE-8 actually asks,
   and the pair to check is whichever two look closest to you. Desaturate and read them. **Six of
   the seven are a mark inside a filled circle by design** — only `exclamationmark.triangle.fill`
   breaks that outline — so among those six the discriminator is the **interior mark**: a tick, a
   square, a raised hand, an exclamation, an eject bar, a question. The seventh shares its interior
   mark with `exclamationmark.circle.fill` and is told apart by its **outline** instead. Either
   discriminator is a pass; a pair with **neither** is the failure.
   *(Reworded 2026-09-08. The original demanded "a different shape … not a variation on a mark
   inside a circle", which describes six of the seven symbols, so a walker following it literally
   would have recorded a FAIL against a product behaving exactly as designed. Instrument defect,
   found in chunk 2's own walk. `RunReportPresentation`'s note carries the same overstatement —
   it calls `eject.circle.fill` a "distinct silhouette at 16pt" when the silhouette is a circle
   like five others and it is the interior mark that is distinct.)*
4. **The drive is named by model and serial, twice.** Once in the header block, on the line
   directly beneath the headline — `Samsung Portable SSD T5 (serial 12345686DAA9)` — and again in
   the **Drive** table, as separate Model and USB serial number rows. The headline itself names no
   drive, and neither does the explanatory paragraph under it; that is correct.
   *(Reworded 2026-09-08. The original asked for the naming in "the headline and the explanation
   below it", which is neither of the two places it appears. Instrument defect, not a product one —
   the identification this item exists to protect is present and doubled.)*
5. **The paused case, by eye — BUILD-PLAN asks for this one specifically.** A run paused with
   nothing in flight must **not** be told a chunk may hold partly written data. It is the only case
   where `aWriteBackMayBeUnfinished` is `false` without route (a) having said which phase it was in,
   and a single hedged sentence covering all four cases would put a false alarm into a document
   somebody keeps. Chunk 4.7 produces this report.

**Getting the report on screen without hardware.** Items 1, 2, 4 and 5 are all readings off a
rendered report, and until chunk 4.7 exists there is no real one. `scripts/render-ui.sh` draws the
product's own `RunReportPresentation` offscreen — it is the app's code path, not a mock-up — via
`tools/ui-probe`, which accepts `report-device-lost`, `report-device-lost-paused` and
`report-device-lost-silent`. **Note that `render-ui.sh`'s own usage text does not list those three**
(2026-09-08); pass them anyway.

⚠️ **A hand-built symbol sheet is not the product.** Drawing the seven names at 16 pt magnified is
the only practical way to judge item 3, but a tool that has the names **typed into it** cannot catch
a typo in the app — it would draw the right glyph while the app drew nothing. Diff the names out of
`RunReportPresentation.swift` against the sheet's before trusting it. Done and identical on
**2026-09-08**; item 1 is what actually covers the typo, and item 1 must be read off the **rendered
report**, never off the sheet.

**Walked:** **2026-09-08**  **Against build:** commit `55a5c71`, ship code — the chunk-1 debug hook
reverted and its absence proved by content (`Device-loss alert` → **0** in
`USBDriveTester.debug.dylib`, `disappeared from the USB bus` → **1**, `nothing was left half-written`
→ **1**, `eject.circle.fill` → **1**). App installed **2026-09-08 10:38**, protocol **v15**, helper
source hash **`e19b0b3c…`**, daemon **pid 84459** started **12:14:01** and resolved by `xpcproxy`
`to program: /Applications/USBDriveTester.app/…`.

**Items 1, 2 and 5 PASSED** by eye on the rendered reports (`report-device-lost`,
`report-device-lost-paused`). **Items 3 and 4 were not walked as written — both were instrument
defects and were reworded above**, which is the third and fourth of that kind found in this project
since 2026-09-04. Neither described a fault in the app.

⚠️ **This is a pass against a render, not against a run.** Items 4 and 5 are re-read on real
hardware at **chunk 4.7**, which produces the paused report for the first time. It lapses if
`RunReportPresentation.swift`, `RunReport.swift`, `HonestFraming.swift` or `DeviceLossAccount.swift`
move — none of which touch the helper hash, so nothing here re-lapses the hardware gates.

*A corroboration worth keeping: `eject.circle.fill` occurs exactly **once** in the installed
`USBDriveTester.debug.dylib`. That is item 1's real subject — the name in the shipped build is the
name, not a typo — established from the product's own binary rather than from a rendering.*

---

## Which drive is which — verified 2026-09-08 16:30, before chunk 3's re-walk

Read this before any chunk that writes. BSD names are a **locator** and this machine has
renumbered them before; the serial is the identity. Verified by a structured IORegistry walk that
attaches each `BSD Name` to the USB device entry containing it, cross-checked against
`scripts/device-probe.sh` for model and capacity.

| USB product | USB serial | Whole disk | What it is |
|---|---|---|---|
| **Portable SSD T5** | **`12345686DAA9`** | **`disk7`** | ✅ **the scratch drive — the ONLY write-gate target.** Mounted `Test_Drive`, exFAT, one data slice `disk7s2` |
| Ugreen Storage Device | `013117100578` | `disk8`, `disk9` | ⛔ **the 990 EVO Plus carrying this repository** (`/Volumes/1TB_UGreen`). Same block count as the T5 — 1,953,525,168 |
| PSSD T5 EVO | `7423J07` | `disk6`, `disk10` | the 4 TB T5 EVO. Not a target |
| Expansion HDD | `00000000NT17XBRA` | `disk11`, `disk13` | ⛔ the 22 TB Seagate. **Never** a write target |
| UDisk | `2211190533300386001515` | `disk4` | the 125.8 MB multi-slice thumb — chunk **4.9**'s drive |
| Flash Drive | `0376620100003464` | `disk5` | 256.6 GB thumb. Not a target |

⚠️ **Two 1 TB Samsung SSDs sit next to each other in that list, and one of them holds the source
tree.** They cannot be told apart by capacity or block count. Confirm the **serial** in the device
pane before starting, which is what item 1 asks for.

⚠️ **`disk7` is what chunk 3's log readings name.** If a replug renumbers it, every `disk7` below
means "whichever whole disk carries `12345686DAA9`" — re-read this table rather than trusting the
digit.

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

   ⚠️ **TWO READINGS, and the order matters. (i) was WRONG as first written — corrected
   2026-09-09 from the walk that took it.**

   **(i) At the START of the run, right after the unmount**, confirm the **discovery** category
   logs one `a disk disappeared: disk7sN (slice)` line **per slice**, at the moment of the claim:

   ```
   13:14:58.519  unmount succeeded on disk7s2: unmounted
   13:14:58.535  a disk disappeared: disk7s1 (slice)
   13:14:58.535  a disk disappeared: disk7s2 (slice)
   13:14:58.536  acquired disk7: claim held, /dev/rdisk7 open exclusively (fd 4)
   ```

   This does not prove the 7f fix. It proves **the app's DiskArbitration subscription is alive and
   delivering**, which is the only thing (ii) needs from it. If these are absent, stop — a missing
   (ii) would then be uninterpretable.

   ⚠️ **This item used to ask for `a slice of the drive under test disappeared and was ignored`,
   from the `io` category. That reading is UNSATISFIABLE and asking for it would have failed a
   sound build.** `RunController.deviceDisappeared`'s second guard is
   `guard let deviceUnderTest else { return }`, and `deviceUnderTest` is set at
   `RunController.swift:530` only when the claim comes back `.ready` — 13:14:58.540 in the walk
   above, **five milliseconds after the slices had already gone**. The slices are torn down *by*
   the claim, and the claim is what tells the app which drive is under test; the ordering is
   inherent, not a defect. Worse, at the real unplug there are **no slices left to disappear** —
   the walk logged only `disk7 (whole disk)` — so the line has no reachable path on a normal run
   at all. See `CONSTRAINTS.md` §1 *Claiming a whole disk makes its own slices disappear*.

   **(ii) After the cable is pulled**, confirm **`a disk disappeared: disk7 (whole disk)`**, with
   the words *whole disk*. ✅ **MEASURED AND PASSED 2026-09-09 13:15:15.920** — the whole-disk
   event **does** fire while the claim is held, which had never been measured and which the whole
   of route (b) rested on. Route (a) fired 1 ms earlier with `errno 6 (Device not configured)`;
   both routes saw it, and the run ended `deviceLost`.
7. A **report** appears — not the alert. On this path a reply came back, so there is a document to
   show, and the report is the message.
8. The report's outcome is device loss, and its account names **which detector** accounted for it.
   Route (a) knows the block and the phase; route (b) knows only *that*.
9. **The phase named, and what follows from it. ⚠️ You do not get to choose which phase you land
   in — corrected 2026-09-09, having been written as if you did.**

   The per-chunk cycle is read → write back → verify, and on the 1 TB T5 at ~490 MB/s each leg of
   an 8 MiB chunk is roughly 17 ms. A cable pull lands in one of the three at about **one chance in
   three**. Read the phase off the report, then check it against **its own row**:

   ⚠️ **There is no separate "warning" to look for. Every device-loss report carries EXACTLY ONE
   sentence** — `HonestFraming.claim(about:)` is documented *"one claim, always"* — and the phase
   selects **which**. So do not ask "was a warning shown"; that question has no answer and asking
   it on 2026-09-09 produced a reply that could not be interpreted. **Match the sentence.** These
   are verbatim from `HonestFraming.swift`, with `N` the digit-grouped block:

   - **reading** — *"The drive left while this tool was **reading** block N. Nothing had been
     written to that chunk, so it holds what it held before the run reached it."*
   - **writingBack** — ⚠️ *"The drive left while this tool was **writing block N back**. That is
     the one point in the cycle where the original had been read and not yet fully written back,
     so **that chunk may hold partly written data**. No other chunk is affected: every earlier one
     was written back and verified, and no later one was started."*
   - **verifying** — *"The drive left while this tool was **re-reading block N to verify it**. The
     write-back had already completed, so the chunk was whole when the drive went — it is
     unverified, and **unverified is not the same as bad**."*

   A report pairing one phase with another phase's sentence is a defect **whichever way round it
   is**: claiming an unfinished write that had completed is as wrong as the reverse, and worse for
   a person deciding whether to trust the drive. `HonestFramingTests` pins sentence against
   `DeviceLossAccount.aWriteBackMayBeUnfinished`, which is a specification the sentence is checked
   against and **not** anything the UI reads — it appears nowhere outside the test target.

   ⚠️ **`writingBack` must be observed at least once before this chunk is passed.** It is the phase
   the chunk exists for — the header above calls it *the phase that matters* — and landing in it is
   luck. **If the report names `reading` or `verifying`, that is a valid pass of that row and NOT a
   pass of this item: re-run and pull again until `writing the original back` comes up.** Expect two
   or three attempts. Record every attempt's phase, including the ones that did not land, because
   *"we pulled three times and never saw `writingBack`"* would itself be worth knowing.
10. **No Resume is offered.** Only start-from-the-beginning. Check the controls, not the report text.
11. Log after the release. **Both of these can fire, in this order** — the item said "either/or"
    until 2026-09-08, when the aborted walk produced both 3.5 seconds apart:
    - `release issued but not waited for — the helper has not answered the call it is inside, so
      this app cannot say the claim on <drive> was dropped` (**error**), at the moment the deadline
      ends the run; then
    - `the release was acknowledged after the deadline had already ended the run; the claim was
      dropped` (**notice**), when the helper finally returns and the release lands.

    **Record both timestamps, or record that the second never came** — that is the difference that
    matters. The error alone means the claim's fate is genuinely unknown and the drive may still be
    held; the pair means it was dropped and the app found out late. The gap measures how long the
    helper stayed inside its call after the app had given up on it, which is 5.1's subject.
12. **Discovery re-runs by itself.** The scratch drive leaves the list without anything being
    clicked. *(FR-DEV-8's third obligation, and the closure in `RunControllerWiring` that fires it
    has no cover but this item — mutation m17 in chunk 7b's round deletes the call and passes the
    whole suite.)*
13. **Reconnect the drive.** It reappears in the list. Confirm by serial.
14. **Start a second run.** It is accepted — the claim from the interrupted run is not still held.
    If it is refused, the helper says so in its own words; record that verbatim, because it is the
    real recovery path for item 11's error case.

**Walked:** **ATTEMPTED 2026-09-08 against `00b1ae2` — ABORTED AT ITEM 2, and it found a defect
that had been shipped for three days.** Not a pass and not a failure of the product's device-loss
handling, because the run never reached an unplug: the app ended its own run **ten milliseconds
after the claim was granted**, before the cable was touched. Route (b) accepted a *slice*
disappearance as proof the drive had gone, and the exclusive whole-disk open is what makes the
slices disappear. Fixed at **chunk 7f**; see `CONSTRAINTS.md` §1, 2026-09-08.

**This chunk must be re-walked from item 1 against the fixed build.** *(Done — re-walked 2026-09-09 against `982406a` and CLOSED; see below.)* Nothing recorded on
2026-09-08 counts toward it except the two readings below, which were taken from the aborted run
and are about the machine rather than about the unplug:

- **Item 11 got both endings, 3.5 s apart** — the error at 14:28:27.046, the notice at
  14:28:30.579. That is what corrected the item's "either/or" wording above.
- **5.1's deadline measurement, partly.** The helper was inside `runRetentionCycle` for **6.67 s**
  (14:28:23.888 → 14:28:30.561) and could not answer a second message on that connection until it
  returned, so the 3-second deadline **expired**. The three-second constant is not generous against
  a real chunk; it is shorter than one. Recorded under 5.1.

**RE-WALKED 2026-09-09 against `982406a`** — installed app from `0b37afd`, daemon pid 89541 (v15,
`/Applications`), target `disk7` = Portable SSD T5 `12345686DAA9`. **The log half PASSES in full.
Items needing a person at the screen are still open** — see *Still owed* below.

**PASSED from the log:**

| Item | Reading |
|---|---|
| (i) | Slice teardown seen in `discovery` at 13:14:58.535 — DA subscription alive. *Item as originally written was unsatisfiable; corrected above* |
| (ii) | ✅ **`a disk disappeared: disk7 (whole disk)` at 13:15:15.920, claim held.** The measurement route (b) rested on |
| 5 | `the drive under test left the machine while running: Samsung Portable SSD T5 (serial 12345686DAA9), disk7 at run time` — **error** level, model + serial, BSD labelled *at run time* |
| 6 | `run ended: deviceLost` |
| 11 | **NEITHER error fired, and that is the pass.** The helper answered in ~6 ms, so the 3 s deadline was never approached: `.920` waiting → `.926` `released disk7: descriptor closed, DiskArbitration claim dropped` → `16.299` `finishing → finished on deviceReleased` |

**Three things this walk measured that were open questions:**

1. **Route (a) and route (b) both fire, ~1 ms apart** — `ENXIO` at `.919`, whole-disk at `.920`.
   On a *running* run they race. Chunk 4's paused run is where route (b) is alone.
2. **A de-enumerating drive produces NO short read.** One of the two numbers named at the top of
   this file as never measured: `read of 8388608 bytes at offset 2726297600 failed after 0 bytes:
   errno 6 (Device not configured)`. **Zero bytes, straight to `ENXIO`.** The cycle's tally
   corroborates it — `wrote 587202560 B` against `verified 578813952 B`, a gap of exactly one
   8 MiB chunk, the one whose verify read hit `ENXIO`.
3. **The 3 s deadline is not the problem it looked like on 2026-09-08.** When the device is
   genuinely gone `ENXIO` aborts the cycle in ~1 ms and the reply is back in ~6 ms. The 6.67 s
   overrun measured on the aborted walk happened because **nothing had actually been unplugged**,
   so the cycle ran to completion. The deadline is short against a healthy chunk and generous
   against a real loss — the opposite of the reading recorded on 2026-09-08, and the two are not
   in conflict once the cause is named. Carried into 5.1.

✅ **THE GUI HALF PASSED 2026-09-09**, read off the screen by a person: **item 4** no crash, no
hang, window usable; **item 7** a report, not the alert; **item 8** the account names which
detector; **item 10** no Resume offered, checked on the controls.

⚠️ **ITEM 9 IS THE ONE THING THIS CHUNK STILL OWES, and the walk is what found that out.**

**Attempts so far — the phase is luck and every attempt is recorded, misses included:**

| # | Phase landed | Verdict |
|---|---|---|
| 1 | `verifying` | ✅ correct sentence for that phase |
| 2 | `reading` | ✅ correct sentence for that phase — block 1,261,568 |
| 3 | `verifying` | ✅ correct sentence for that phase |
| 4 | `verifying` | ✅ correct sentence for that phase — block 1,130,496 |
| 5 | `reading` | ✅ correct sentence for that phase — block 1,687,552 |
| 6 | **`writingBack`** | ✅ **THE ONE THIS CHUNK EXISTED FOR** — block 1,392,640, sentence matched `HonestFraming.swift` word for word |

**✅ ITEM 9 PASSED 2026-09-09. All three rows walked on real hardware, every sentence correct for
its phase.** Final tally `verifying` ×3, `reading` ×2, `writingBack` ×1 — against an expectation of
2 / 2 / 2, and five misses before the hit is a 13.2% run of luck. **The stopping rule was never
reached** and is left above as the record of a threshold set before the data arrived.

**The hypothesis the rule would have tested is DISPROVED, which is the better outcome than never
having asked.** A write to a departing device does **not** silently succeed: attempt 6's write
threw, was classified `.deviceLost`, and was attributed to `writingBack` by
`RetentionTestEngine.swift:519` — the end-to-end path from a real failed write to the hazard
sentence a person reads. That is the only part of this item hardware was ever needed for.

ℹ️ **The wording half needs no hardware next time.** `scripts/render-ui.sh <out.png> 600 1000
report-device-lost` renders the `writingBack` account from a fixture, and its sentence matches.
Rendered and checked 2026-09-09. So a regression in the *wording* is catchable in seconds; only a
regression in the *attribution* — a real write failure reaching the right phase — costs cable
pulls. Worth knowing before anyone budgets six runs for a re-walk. ⚠️ The argument order is
`OUT WIDTH HEIGHT VIEW`, not view-first; passing the view first silently writes a PNG named after
the view into the current directory, which happened on 2026-09-09.

**✅ CHUNK 3 IS CLOSED. Against build:** `982406a` *(all items; item 9 across six runs)*

⚠️ **STOPPING RULE, declared in advance on 2026-09-09 at three misses — before it started to feel
wrong, which is the only time a threshold means anything.** The three legs of an 8 MiB chunk are
~17.0 / 17.1 / 17.3 ms (from the run's own metrics: 492.6 / 490.8 / 483.8 MB/s), so each is
**one chance in three** and a miss costs one run:

| Misses | Chance of that run of luck | Reading |
|---|---|---|
| 3 | 29.6% | unremarkable — keep pulling |
| 6 | 8.8% | note it, keep pulling |
| **8** | **3.9%** | ⛔ **STOP. Do not keep pulling** — investigate a bias instead |

**What was checked before setting this, so the threshold is not hiding a known defect:**
`RetentionTestEngine.swift` has **three** attribution sites — 488 `.reading`, 519 `.writingBack`,
543 `.verifying` — each keyed to the error thrown by *its own* operation, so a failed write is
attributed to `writingBack` and cannot be mis-filed as a verify. Writes go to a raw character
device with `F_NOCACHE` and `F_GLOBAL_NOCACHE` (`raw, unbuffered; cache-bypass check says
bypassed` in the run log), so a write returning success has reached the device rather than a
buffer. Attempt 1's tally corroborates: `wrote 587202560 B` = 70 chunks, `verified 578813952 B` =
69 — the 70th write **succeeded** and its verify read hit `ENXIO` after 0 bytes.

**If the rule trips**, the hypothesis to test is that a write to a *departing* device returns
success while the read that follows it ~17 ms later does not — which would mean `writingBack` is
systematically under-reported, and under-reported in the **hazardous** direction, since it is the
one phase whose sentence warns of partly written data. That would be a finding about the platform,
not about this app, and it belongs in `CONSTRAINTS.md` §1 beside the other USB measurements.

Item 9 above had asserted `writingBack` as though it were guaranteed; it is about one chance in
three, and asserting it would have marked the safety-critical path walked when nothing had touched
it.

**Against build:** `982406a` *(every item PASSED — see the item 9 table above for its six runs)*

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
9. **The multi-slice idempotency check — one unplug, one wind-down.** A partitioned drive fires
   `DADiskDisappeared` **once for the whole disk and once per slice** (measured 2026-09-05), so one
   removal is several events. Chunk 4 defends against that at three levels, and the middle one is
   not redundant: a mutation building one wind-down per callback armed three deadlines and
   **survived the whole suite**, because the test bench held only the latest.
   `threeCallbacksFromOneUnplugArmOneDeadline` closed it in the bench; on hardware it is unchecked.

   **Fixture: the 125.8 MB "General UDisk" thumb, serial `2211190533300386001515`, repartitioned
   into two exFAT slices** — `Slice_A` **59.8 MB** and `Slice_B` **64.0 MB**, the command having
   asked for 60M and a remainder. User decision **2026-09-07**: the
   designated scratch T5 has one volume, and the only other partitioned drive here is the 4 TB
   T5 EVO, which holds data a run would write over. Declared as role `multislice` in
   `scripts/lib/device-identity.sh`; resolve it by **serial**, never by node.

   **The thumb de-enumerated during its own repartition, 2026-09-07 10:44.** `diskutil
   partitionDisk` wrote the GPT and both slices — `disk4`, `disk4s1` and `disk4s2` all appear in
   the StorageKit log — and the storage stack then vanished mid-format while the **USB device
   stayed enumerated in IOKit with no `IOMedia` under it**. `diskutil` hung and was killed.
   **It was physically replugged the same day and came back complete.** Confirm it is still
   present before walking this item — this step's whole subject is drives going away:

   ```bash
   /usr/sbin/diskutil list external
   ```

   **Two slices means the geometry survived.** They are **59.8 MB and 64.0 MB**, not the even
   60/60 the command asked for, so do not check for *"two 60 MB slices"*. **If the drive shows one
   slice or none, re-run the repartition** — the thumb is expendable and the command is in
   `PROGRESS.md`, or `progress/step-12.md` once Step 12 is archived.

   The check itself:

   1. Select the thumb in the app **by serial**, start a run, pause it, and pull the cable.
   2. Exactly **one** `the drive under test left the machine` line, and **one** `run ended`.
   3. Exactly **one** report.

   ⚠️ **Not a throughput or retention reading.** 125.8 MB says nothing about either, and the thumb
   holds no `/dev/urandom` fill, so a placement could land on all-zero space and report a clean
   pass having proved nothing. It exists to be unplugged.

   **The 2026-09-07 accident is itself a confirmation of the premise**, at the StorageKit layer
   rather than DiskArbitration's: three `Operation = Disappear` notifications — `disk4s1`,
   `disk4s2`, `disk4` — for one drive going away, which is exactly the count BUILD-PLAN records
   for a two-partition drive. That is the fixture doing its job before it was asked to.

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

**⚠️ A first reading already exists, and it changes what 5.1 is asking. Taken 2026-09-08 from the
aborted chunk 3 walk, against `00b1ae2`:**

The removal callback fired at **14:28:23.896** while the helper was inside `runRetentionCycle`. That
call had started at **14:28:23.888** and returned at **14:28:30.561** — **6.67 seconds**. On the same
connection a second message is not delivered until the call returns (measured 2026-08-04), so no
reply could arrive, and the deadline **expired** at 14:28:27.045: `no reply after 3.000000s — ending
the run on the removal callback alone`.

So step 4's second branch is already refuted. **The three-second figure is not generous by three
orders of magnitude; it is less than half the length of one 8 MiB × 128-chunk call.** A deadline
firing therefore means *the helper is busy*, which is the ordinary case — not *something is wrong*.

That makes 5.1's real question a different one: **what is route (a)'s reply latency measured from
when the helper's call actually returns**, and is the deadline meant to bound the reply or the
call? Record the three trials as written, and record the in-flight call's duration alongside each,
because the second number is what the constant is actually racing.

⚠️ **This reading came from a run that ended itself, not from an unplug.** The call ran to
completion rather than being cut short by a vanishing drive, so it is an upper bound on a healthy
chunk and not a measurement of the case 5.1 names. Both are worth having; they are not the same
number.

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
