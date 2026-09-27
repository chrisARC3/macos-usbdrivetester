# Step 12 — the human checklist

> **STATUS, 2026-09-11: ALL FIVE CHUNKS CLOSED — chunks 1–4 WALKED; chunk 5 DISCHARGED, by user
> decision, from chunk 3's log.** Chunks 1 and 2 passed **2026-09-08** against `55a5c71` (chunk 1
> with its debug hook, chunk 2 without); chunk 3 aborted that day on a shipped defect, fixed at 7f,
> and was re-walked and closed **2026-09-09** against `982406a`; **chunk 4 was walked and closed
> 2026-09-11** against `c767317`, installed app built from `2086090`, on the 1 TB scratch T5 and —
> for 4.9 — the 125.8 MB thumb. Chunk 5 needed no cable pull: chunk 3's six logged pulls discharge
> 5.1 and 5.2, and the helper's cycle tallies stand in for 5.3's metrics-panel reading. **The one
> thing this checklist left owed — chunk 4's two logging gaps — was closed in code at 7g and seen
> on the installed build 2026-09-11, all four command labels**: Start, Pause and Stop at
> 16:14–16:19, and `Resume` at 18:02:13 on a second run made for it; the note under chunk 4 carries
> the log lines. **With that, STEP 12 CLOSED the same day** — all four of its verification-gate
> items ticked in `BUILD-PLAN.md`, this checklist being the evidence behind three of them. Each chunk's
> own **Walked** line is the record; this block only points at them. Written at chunk 7c on
> **2026-09-07**, against commit `3da3ef7`, protocol **v15**, helper source hash **`e19b0b3c…`**.
>
> ⚠️ **Found 2026-09-10: this block still said *"STATUS: UNWALKED … Nothing here has been run"***,
> through three chunks' walks and thirteen commits to this very file. It names no step, so the grep
> for the five blocks that do never finds it — the tenth stale status block (`CLAUDE.md`).
>
> ⚠️ **2026-09-19: chunks 1 and 2 are OWED a re-walk on the Xcode 27 build, and chunks 3 and 4's
> pulls are carried by Step 13's** (user decision, at the move to Xcode 27's chunk 4). Every pass
> above was made with an Xcode 26.6 build on macOS 26. Chunks 1 and 2 are dry and take minutes: the
> alert, induced through chunk 1's debug hook, and the report's device-loss face. Chunks 3 and 4 are
> not re-walked on their own — Step 13's checklist pulls the cable twice on this build in its
> chunk 3, and its item **3.7** takes this file's 3.4, 3.7–3.10 and 3.12 at the running pull and
> 4.4, 4.7 and 4.8 at the paused one. Chunk 5 was discharged from logs and is not re-opened.
> **Chunk 1's hook is installed to `/Applications` and taken out again**, so it goes before Step
> 13's walk restarts, whose item 0 re-checks the install after it. Until each is walked, its pass
> here is a fact about the Xcode 26 build only. **Each re-walk fills in its own Walked line and
> edits this note.** *(2026-09-26: chunks 1 and 2 are **next**, with the user's go — Step 11's
> re-walks finished 2026-09-25. Chunk 1's hook is installed and then taken out again, so its plan
> first settles, with the user, what that reinstall does to the passes recorded against the
> 2026-09-24 18:01:53 install: `PROGRESS.md`, the *Now* row.)* *(Later 2026-09-26: settled by the
> user — those passes stand only if the bundle put back is the one taken out, **byte for byte**: it is
> saved before the hook goes in, restored from that copy afterwards, and proved identical. A rebuild
> is not enough, because a signature carries its signing time. **Chunk 2 went first and PASSED on
> the Xcode 27 build, all five items**, its re-walk box under the chunk. **Chunk 1 is next**, with
> the user's go; its item 9 kickstart is skipped if the helper is still `ac4d5208…`.)* *(Later
> again, 2026-09-26: **chunk 1 PASSED on the Xcode 27 build, items 2–8**, 19:55–20:19, its re-walk
> box under the chunk. Its hook was taken out by 20:22:42 — the source from a pristine copy, the
> bundle from the saved one, proved byte-identical — and no kickstart was needed: the helper stayed
> `ac4d5208…`. **Both re-walks are done**, and the passes recorded against the 2026-09-24 18:01:53
> install stand. Chunks 3 and 4 stay carried by Step 13's pulls. **Next: Step 13's walk restarts at
> item 0.**)*

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
written up under chunk 3's result and carried into 5.1. ⚠️ **On 2026-09-10 both became six trials, not one**: the
persisted unified log still held all six of chunk 3's pulls, and they are read back under 5.1 and 5.2.

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

* **The 125.8 MB "General UDisk" thumb, serial `2211190533300386001515`** — two slices,
  **59.8 MB and 64.0 MB**, role `multislice`. Needed by **4.9 only**. Contents expendable; never a
  retention target. *(Corrected 2026-09-11 from "two exFAT slices": only the first holds a volume.
  `diskutil info` reads `disk4s1` as `Slice_A`, exFAT, mounted, and `disk4s2` as **no volume name,
  not mounted, personality `MS-DOS` with no FAT variant** — where the scratch T5's real FAT32 EFI
  slice reads `EFI` / `MS-DOS FAT32`. Most likely the second slice's format is what the 2026-09-07
  hang cut off, and "came back complete" was judged on the partition map and the sizes, which did
  survive. It does not touch 4.9, which counts slices, not volumes: a slice is an `IOMedia` whether
  or not it holds a filesystem, and the scratch T5's unmounted EFI slice goes at the claim like the
  mounted one.)*

* **The app installed and the daemon kickstarted** — chunk 7d. ⚠️ **The helper source hash moved at
  chunk 7b**, so the installed daemon is stale for certain. Copying files does not reload it: two
  hardware gate runs on 2026-08-18 measured stale code while returning plausible numbers. Verify the
  reinstall took with `nm -gU`, never by timestamp:

  ```bash
  /usr/bin/nm -gU /Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper | /usr/bin/grep -c injectShort
  ```

  **2** means the installed helper contains chunk 7b's source; **0** means it does not, whatever
  the timestamps say. ⚠️ **The `-g` is load-bearing, and was found missing 2026-09-10.** Every
  build from this project's scheme is coverage-instrumented, so plain `nm -U` also lists a local
  `___profc_` and `___profd_` counter for each of the two functions and each of their closures:
  **14** lines, not 2, on both helpers installed since 7b's source landed — `7590b920…` and
  `ab4b6957…`, the very binary 7d recorded as "2" (`CONSTRAINTS.md` §1, *Every scheme build is
  coverage-instrumented*). `-g` keeps external symbols only. Then, because copying files never
  restarts a running daemon:

  ```bash
  sudo /bin/launchctl kickstart -k system/com.arc3solutions.USBDriveTester.Helper
  ```

  ⚠️ **On 2026-09-07 the running daemon was found to have started 2026-09-04 17:01:05 — before
  Step 12's first commit.** It had served the whole of chunks 4–6 on protocol v14 while the app
  was at v15, and the 2026-09-06 install had not restarted it. Check the daemon's age, not the
  bundle's — the daemon is the process with **uid 0 and parent pid 1**:

  ```bash
  /bin/ps -axo pid=,ppid=,uid=,lstart=,comm= | /usr/bin/awk '$2 == 1 && $3 == 0 && $NF ~ /com\.arc3solutions\.USBDriveTester\.Helper$/'
  ```

  *(Found 2026-09-10: this read `ps -o lstart= -p "$(pgrep -f USBDriveTester.Helper)"`, and
  `pgrep -f` matches any process whose command line contains the name — a second pid breaks the
  `ps`.)*

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
   `RunController.deliverTheEndOfRun`, `onFailure(DeviceLossMessage.forRunWithNoReport(endedBy:))`
   — `RunController.swift:911` at `77275be`. *(Corrected 2026-09-26: this cited `:875`, true when
   it was written and walked, at `3da3ef7` and `55a5c71`; the call moved four times, from `7b4f200`
   on the day of the walk to `ad1ee28` on 2026-09-12, and has been at `:911` since. The function's
   name is the part that stays true.)*
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
8. Repeat 2–7 with `endedBy: .nothingWasInFlight`. **The pass is this sentence on screen, word for
   word:** *"Nothing was being written when the drive left, so no chunk was left half-written."*
   `DeviceLossMessage`'s body is one fixed text per ending, so what this item guards against is a
   *different* text in that place — one of the two that say a chunk *may hold partly written data*.
   *(A paused run had nothing outstanding; telling that user a chunk may be half-written is a false
   alarm in a dialog, which is worse than in a document, because a dialog is read once and
   believed.)*
   *(Reworded 2026-09-26, after the Xcode 27 re-walk, by the user's decision, from "The body must say
   **"Nothing was being written"** and must **not** mention a half-written chunk". Read literally,
   that fails the correct text, which mentions a half-written chunk to say there is none; read by
   the reason above, it holds — the reading both walks took, the 2026-09-08 one without recording
   it, since `DeviceLossMessage.swift` has not changed since `55a5c71`. It was also a reading off an
   absence, the shape chunk 4.7 was reworded out of on 2026-09-10. The sentence was checked against
   `DeviceLossMessage.swift:105-106` at `77275be` the same day.)*

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

   **Done again 2026-09-26, 20:22:18–20:22:42 — by restore, not reinstall** (user decision, the
   same day: the passes recorded against the install stand only if the bytes put back are proved
   identical). The hook reverted from a saved pristine copy with `cp -p`: `git status --short`
   clean, `git diff` empty, the file's sha-256 `9d3d0a9c…` equal to `HEAD`'s. The bundle put back
   with `rm -rf` and `ditto` from the copy saved at 19:50:18, before the hook went in — never rebuilt,
   because a signature carries its signing time. Proved identical to the install before the hook:
   `diff -rq` against the saved copy empty; a manifest of all 17 entries — type, mode, flags, owner,
   size, sha-256, every extended attribute's value, and separately mtime and birth time — identical;
   `codesign -dvvv` of the app and of the helper identical, signing times included (2026-09-24
   18:01:53 and 2026-09-19 09:23:51); dylib `e6e6e884…`, stub `bf787e19…`, helper `ac4d5208…`,
   strict verify OK; `Device-loss alert` → **0**, the title → **1**. **No kickstart** (user
   decision: skipped if the helper stays as is): the helper was `ac4d5208…` throughout, the bytes
   the daemon, pid 14761, was started from. DerivedData was then rebuilt from the reverted source,
   at 20:23:33: its three binaries differ from the install's by signing time only — each one's
   CDHash is the install's.

**Walked:** **2026-09-08**  **Against build:** commit `55a5c71` **plus the chunk-1 debug hook
(uncommitted, never committed)**, app installed 2026-09-08 08:26:05, protocol **v15**, helper source
hash **`e19b0b3c…`** (the hook lived in `USBDriveTesterApp.swift`, outside `Shared/`, so the hash
did not move and 7d's four gate results were not disturbed), daemon pid 69701 serving v15 from
`/Applications`.

⚠️ **What would invalidate this pass:** any change to `DeviceLossMessage`, to `RunControlsView`'s
`.alert` modifier, or to `RunFailureMessage`. The alert has no automated cover at all — see the
list at the end of this file — so this pass is the *only* evidence that dialog renders correctly,
and it is evidence about one build on one day.

✅ **Re-walked:** **2026-09-26**, dry — **ITEMS 2–8 ALL PASSED on the Xcode 27 build** (user
decisions: 2026-09-19, that chunks 1 and 2 are re-walked on it; 2026-09-26, *"chunk 2 first"*, then
*"Keep the new list and proceed with Chunk B"*). Every reading is the user's, by eye, off the
installed app, one check at a time, 19:55–20:19 — the helper-never-answered alert for items 2–7,
then the nothing-in-flight one for item 8:

| item | the user's reading, verbatim |
|---|---|
| 2 | *"Yes to the first test. Alert still open."* |
| 3 | *"No asterisks."* |
| 4 | *"Yes to both. Here is the exact quote: "It cannot be ruled out that a write-back was interrupted: one chunk of the drive may hold partly written data, and nothing can say which one.""* |
| 5 | *"Yes to both. Here is the exact quote: "This run cannot be continued — start it again from the beginning.""* |
| 6 | *"Only one: the OK button. Clicking it closes the alert."* |
| 7 | *"I am able to use both the up and down arrow and click on a drive successfully"* |
| 8, as 2 | *"Yes to both."* |
| 8, as 3 | *"No asterisks."* |
| 8, its own check | asked for the whole message word for word: *"The drive was disconnected during the test / The drive left the USB bus part-way through the run, while the run was paused. There is no report for this run. / Nothing was being written when the drive left, so no chunk was left half-written. This run cannot be continued — start it again from the beginning."* — then, on the wording finding below, *"Yes, that's a pass by its stated reason."* |
| 8, as 5 | taken from that quote, which holds the sentence whole |
| 8, as 6 | *"One button only that says "OK"; clicking the button dismisses the alert."* |
| 8, as 7 | *"Yes, arrows and clicking both move the selection normally."* |

The quotes at 4, 5 and 8 were compared by script with `DeviceLossMessage.swift` at `77275be`, and
each is the source's text exactly — item 8's the `.nothingWasInFlight` title and body whole.

**Against build:** `77275be` **plus the chunk-1 debug hook (uncommitted, never committed)** — two
menu items in `USBDriveTesterApp.swift`, outside `Shared/`, so the helper source hash stayed
**`e19b0b3c…`** — by Xcode 27.0 (27A266a), Swift 6.4, on macOS 27.0 (26A428), installed by
`install-app.sh Debug` at 19:50:50 over the 2026-09-24 18:01:53 install, which was saved first
(item 9). Proved by content at 19:51:01: dylib `a22eaee0…` and stub `1c32916e…`, helper `ac4d5208…`
unchanged with its signing time, strict verify OK, `Device-loss alert` → **2**, the title → **1**,
and the install equal to DerivedData's build. The app walked was pid 31583, launched 19:52:59 from
`/Applications` — by `ps`, and by BTM, which resolved it to `file:///Applications/USBDriveTester.app/`
at 19:52:59.704, the only app URL it logged from 19:45 to the restore. Daemon pid **14761**, up since
2026-09-25 20:12:28, protocol **v15**. The install was put back afterwards and proved byte-identical —
item 9 — so the passes recorded against the 2026-09-24 install stand.

**One finding, cosmetic — the checklist's wording, not the app** — decided by the user the same day,
*"go with (a)"*: reworded, with a dated note. Item 8 said the body *"must **not** mention a
half-written chunk"*; read literally, that fails the correct text. The pass is now the sentence on
screen. **A second, of the same shape, found while rewording it and reported, not fixed** — *Owed*
(m) in `PROGRESS.md`: item 8 says *"Repeat 2–7"*, and item 4 among them asks the body for the very
warning item 8 exists to keep out of it. This walk took item 8's own check in item 4's place, and
the 2026-09-08 one must have, since it passed the same text.

⚠️ **What would invalidate it:** the 2026-09-08 clause — any change to `DeviceLossMessage`, to
`RunControlsView`'s `.alert` modifier, or to `RunFailureMessage`; any new Xcode or macOS. None of
these is in the helper hash, so nothing here lapses a hardware gate.

---

## Chunk 2 — the report's device-loss face *(dry: no run, no drive — reads `render-ui.sh`'s renders)*

`RunReportPresentation` pins that the six outcomes have six distinct symbols, that no two are told
apart by tint alone, and that only a verified clean pass is affirmative. What it does **not** pin is
that `eject.circle.fill` is a real SF Symbol. A misspelled or invented name compiles, passes every
test — they compare strings — and renders as nothing.

1. With a device-loss report on screen (chunk 4 produces one; until then use
   `scripts/render-ui.sh`), the header icon is **present and is an eject symbol in a circle**, not a
   blank space and not a question mark.
2. It is tinted **orange** (cautionary), not green.
3. **No two of the seven collide in greyscale at 13 pt**, the size the report header draws them
   at. That is what NFR-USE-8 actually asks, and the pair to check is whichever two look closest to
   you. Desaturate and read them. **Six of the seven are a mark inside a filled circle by design** —
   only `exclamationmark.triangle.fill` breaks that outline — so among those six the discriminator
   is the **interior mark**: a tick, a square, a raised hand, an exclamation, an eject bar, a
   question. The seventh shares its interior mark with `exclamationmark.circle.fill` and is told
   apart by its **outline** instead. Either discriminator is a pass; a pair with **neither** is the
   failure.
   *(Reworded 2026-09-08. The original demanded "a different shape … not a variation on a mark
   inside a circle", which describes six of the seven symbols, so a walker following it literally
   would have recorded a FAIL against a product behaving exactly as designed. Instrument defect,
   found in chunk 2's own walk. `RunReportPresentation`'s note carries the same overstatement —
   it calls `eject.circle.fill` a "distinct silhouette at 16pt" when the silhouette is a circle
   like five others and it is the interior mark that is distinct.)*
   *(Reworded again 2026-09-26: this said **16 pt**, and so does `RunReportPresentation`'s note —
   "their real 16 pt". The header's `Label` sets `.headline` on its text only, so the icon takes
   the environment's body font, **13 pt** on macOS; nothing in the app or in `tools/ui-probe` sets
   a font above `RunReportView`. Measured on `render-ui.sh`'s 1x render: the header icon is
   13 × 13 px, the size of `eject.circle.fill` at the body font, against 16 × 16 at 16 pt. So the
   2026-09-08 reading was taken 3 pt larger than the product draws. Instrument defect, found in the
   Xcode 27 re-walk. The note in the source waits for that file's next edit — editing it now would
   lapse this chunk — as Owed (l) in `PROGRESS.md`.)*
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
(2026-09-08); pass them anyway. *(Fixed 2026-09-09 in `2086090`: the usage block now lists all
three. The argument order is `OUT WIDTH HEIGHT VIEW`.)*
*(2026-09-26: and once chunk 4.7 has been walked there is still no real report to go back to. The
app keeps no run history — the report's own footer says "No run history is kept" — so a real one
can be read only while it is on screen, at the end of the run that made it. Until that day this
chunk's heading said "dry: reads an existing report", and no report exists to read; a dry walk
reads these renders. Instrument wording, found in the Xcode 27 re-walk.)*

⚠️ **A hand-built symbol sheet is not the product.** Drawing the seven names at 13 pt, magnified, is
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

✅ **Re-read on a real report 2026-09-11, at chunk 4.7** — a paused run on the 1 TB scratch T5,
unplugged, against `c767317` with the app built from `2086090`. **Items 1, 2, 4 and 5 all hold on
it**, by the user's eye: the eject symbol in a circle, orange, `Samsung Portable SSD T5 (serial
12345686DAA9)` beneath the headline and again in the Drive table, and the paused sentence word for
word. Item 3 is a comparison across seven symbols and stays the 2026-09-08 reading. The same lapse
conditions apply to this re-read.

*A corroboration worth keeping: `eject.circle.fill` occurs exactly **once** in the installed
`USBDriveTester.debug.dylib`. That is item 1's real subject — the name in the shipped build is the
name, not a typo — established from the product's own binary rather than from a rendering.*

✅ **Re-walked:** **2026-09-26**, dry — **ALL FIVE ITEMS PASSED on the Xcode 27 build** (user
decisions: 2026-09-19, that chunks 1 and 2 are re-walked on it; 2026-09-26, *"chunk 2 first"*).
Every reading is the user's, by eye, one item at a time, 18:00–19:31:

| item | read off | the user's reading, verbatim |
|---|---|---|
| 1 | `header-crops.png` — the header of each of the three renders, ×4 | *"Header icon is present with eject symbol in all three"* |
| 2 | the same | *"Yes, the eject icon is orange in each"* |
| 3 | `symbol-sheet-13pt.png`, the 1x greyscale row | *"row 1x stop.circle.fill and hand.raised.circle.fill look the most similar."*, then *"Yes, I can tell the difference even though they are similar."* — a square against a raised hand: the interior mark |
| 4 | `report-device-lost.png` | *"1. Yes the drive is named correctly. 2. Yes, a model row and separate serial number row 3. Yes"* — beneath the headline; in the Drive table; and in neither the headline nor the paragraph under it |
| 5 | `report-device-lost-paused.png` | *"It specifically says: "...no chunk was part-way through anything and nothing was left half-written." So that's a pass."* |

Item 2 was first answered off a symbol sheet — *"The two tinted checkmark.circle.fill are green.
The rest are orange or grey."* — and asked again, because item 2 is read off the product's render.
The first answer is kept as a corroboration: on the sheets, whose tints are read out of the source,
only `.completedClean`'s symbol is green.

**Against build:** the renders `report-device-lost`, `report-device-lost-paused` and
`report-device-lost-silent`, drawn by `scripts/render-ui.sh` at 696 × 1400, light, 17:15:35–17:16:08,
from the working tree at `4299e46` — whose app sources, `tools/` and `scripts/` are `77275be`'s byte
for byte; every commit since is documents or `claude-md-test/` — by Xcode 27.0 (27A266a), Swift 6.4,
on macOS 27.0 (26A428). The two symbol sheets, 13 pt and 16 pt, come from a scratch tool that reads
the seven names and their tints out of `RunReportPresentation.swift` and the tint-to-colour map out of
`RunReportView`'s `iconTint`, so nothing is typed in; an independent grep of the names agrees, and all
seven resolve on this macOS. The installed app is the one of **2026-09-24 18:01:53** from `77275be`,
re-checked before the walk, 16:02–16:04 (`PROGRESS.md`, *Installed app*), and re-hashed after it at
19:33:33 — dylib `e6e6e884…`, stub `bf787e19…`, helper `ac4d5208…` — strict verify OK,
`Device-loss alert` → **0** and each of the seven names **once** in `USBDriveTester.debug.dylib`;
daemon pid **14761**, up since 2026-09-25 20:12:28, protocol **v15**; helper source hash
**`e19b0b3c…`**, re-derived.

**Four findings, all cosmetic — instrument wording and citations, none of them in the app.** The
user decided them the same day: *"fix all three in the same commit"*, and *"fix (4) in CONSTRAINTS
the same way as (1) and leave the checklist's alone"*. (1) Chunk 1's item 1 cited
`RunController.swift:875`; the call has been at `:911` since `ad1ee28`. (2) This chunk's heading said
it reads an existing report, and none exists to read. (3) Item 3, and the warning on hand-built
sheets, said 16 pt; the header draws the icon at 13. Each is fixed above, (1) to (3) with a dated
note; (3)'s figure is also in `RunReportPresentation.swift`'s note, which waits as Owed (l) in
`PROGRESS.md`. (4) `CONSTRAINTS.md` cited `RunController.swift:530` for where `deviceUnderTest` is
set; it is `:552`, corrected there with a dated note. Chunk 3's record below cites `:530` too, and
stays as written.

⚠️ **Still a pass against renders, not against a run** — the 2026-09-11 re-read on a real report
was of the Xcode 26 build. On this one, the first real device-loss reports come at Step 13's chunk 3
pulls. **What would invalidate it:** the 2026-09-08 clause — a change to
`RunReportPresentation.swift`, `RunReport.swift`, `HonestFraming.swift` or `DeviceLossAccount.swift`
— **and a change to `RunReportView.swift`**, which draws the header's `Label`, its font and
`iconTint`, and the Drive table, and which that clause did not name (kept in it by the user the
same day: *"Keep the new list"*); any new Xcode or macOS. None of these files is in the helper hash,
so nothing here lapses a hardware gate.

---

## Which drive is which — verified 2026-09-08 16:30, before chunk 3's re-walk

Read this before any chunk that writes. BSD names are a **locator** and this machine has
renumbered them before; the serial is the identity. Verified by a structured IORegistry walk that
attaches each `BSD Name` to the USB device entry containing it, cross-checked against
`scripts/device-probe.sh` for model and capacity.

**Re-verified 2026-09-10, before chunk 4**, by two sources that agree on all six drives: an
IORegistry walk attaching each whole disk to its **nearest** enclosing `IOUSBHostDevice`, and the
app's own enumerator (`tools/device-id serial-of`, which `scripts/lib/device-identity.sh` builds).
Every row still holds **except two cells, annotated in place**: the 4 TB T5 EVO's serial, which was
**wrong on 2026-09-08**, and the 22 TB Seagate's APFS container, renumbered `disk13` → `disk12`.
⚠️ **The wrong serial is a hub's.** `7423J07` belongs to the Apple *USB3 Gen2 Hub* (and its *USB2
Hub* twin) that the 4 TB T5 EVO and the 1 TB scratch T5 both sit behind — a hub is a USB device
entry too, and it carries a serial. The drive's own is `00000S7CLNJ0WC02266P`, which every other
record in this repository names. Not a write hazard, since that drive is not a target and the
scratch T5's row was right, but it is the **second wrong serial from a BSD↔serial walk in three
days** (`CONSTRAINTS.md` §1, *Do not pair a serial to a drive by ADJACENCY*).

| USB product | USB serial | Whole disk | What it is |
|---|---|---|---|
| **Portable SSD T5** | **`12345686DAA9`** | **`disk7`** | ✅ **the scratch drive — the ONLY write-gate target.** Mounted `Test_Drive`, exFAT, one data slice `disk7s2` |
| Ugreen Storage Device | `013117100578` | `disk8`, `disk9` | ⛔ **the 990 EVO Plus carrying this repository** (`/Volumes/1TB_UGreen`). Same block count as the T5 — 1,953,525,168 |
| PSSD T5 EVO | ~~`7423J07`~~ **`00000S7CLNJ0WC02266P`** *(corrected 2026-09-10; `7423J07` is the hub's)* | `disk6`, `disk10` | the 4 TB T5 EVO. Not a target |
| Expansion HDD | `00000000NT17XBRA` | `disk11`, `disk13` *(`disk12` on 2026-09-10)* | ⛔ the 22 TB Seagate. **Never** a write target |
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
Items needing a person at the screen are still open** — see *Still owed* below. *(All since passed —
see ✅ **THE GUI HALF PASSED 2026-09-09** below, which replaced the *Still owed* list this pointed to.)*

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
7. A report appears, and **its device-loss account is this sentence, word for word** — the
   `.nothingWasInFlight` case of `HonestFraming.claim(about:)`, with *paused* in bold:

   > The run was **paused** when the drive left, so no chunk was part-way through anything and
   > nothing was left half-written. Every chunk the run had reached was written back and verified
   > before it stopped.

   **The pass is that sentence being on screen**, not a warning being absent. `claim(about:)`
   returns exactly one sentence for every ending and the report has no separate warning element,
   so *"does not warn"* gives a person nothing to look at; what this item guards against is a
   *different* sentence in that slot — one of those that say a chunk *may hold partly written data*.
   *(Reworded 2026-09-10, before the walk, from "it does NOT warn that a chunk may be half-written":
   a reading off an absence, the same shape chunk 3 item 9 was reworded for on 2026-09-09. The
   sentence was checked against `HonestFraming.swift:184-188` and against
   `scripts/render-ui.sh <out.png> 600 1000 report-device-lost-paused` the same day.)* This is
   chunk 2 item 5's subject — check it here and record it there too.
8. Discovery re-runs; the drive leaves the list.
9. **The multi-slice idempotency check — one unplug, one wind-down.** A partitioned drive fires
   `DADiskDisappeared` **once for the whole disk and once per slice** (measured 2026-09-05), so one
   removal is several events. Chunk 4 defends against that at three levels, and the middle one is
   not redundant: a mutation building one wind-down per callback armed three deadlines and
   **survived the whole suite**, because the test bench held only the latest.
   `threeCallbacksFromOneUnplugArmOneDeadline` closed it in the bench; on hardware it is unchecked.

   ⚠️ **Prediction, declared 2026-09-10 before the walk: this item cannot exercise what it is named
   for.** The premise above — the whole disk *and* each slice — was measured on 2026-09-05 with
   **nothing claimed**. A run holds an exclusive whole-disk claim, a **paused** run keeps it
   (`RunController.pause()` only sends `setRunControl(.pause)`), and under a claim the slices go
   **at the claim**, not at the pull. Measured on every one of chunk 3's six pulls on 2026-09-09 and
   read back from the persisted log on 2026-09-10: `disk7s1 (slice)` and `disk7s2 (slice)` in the
   same millisecond as the helper's `acquired disk7` *(too tight — within a few milliseconds of it,
   on either side; measured 2026-09-11, see the result below)*, and at the pull exactly **one**
   `disk7 (whole disk)`. So on the thumb — `disk4` today; resolve it by serial — expect in the
   `discovery` category:

   - **at the claim**: `a disk disappeared: disk4s1 (slice)` and `a disk disappeared: disk4s2
     (slice)` — which is also the proof the subscription is alive, as in chunk 3's reading (i);
   - **at the pull**: exactly **one** `a disk disappeared: disk4 (whole disk)`, and no slice lines.

   **One event cannot test idempotency against several.** The three checks below would pass and say
   nothing about the three-level defence this item was written for. **In this design multi-slice
   idempotency has no hardware path at all**: `threeCallbacksFromOneUnplugArmOneDeadline` covers it
   on the bench, and nothing covers it on hardware. What walking 4.9 would still buy is chunk 4
   repeated on a second drive — a 125.8 MB thumb behind a different hub, rather than the 1 TB T5 —
   *(so it was, checked 2026-09-11: the kernel's detach line at the pull names
   `AppleUSB20HubPort@00131000`, a USB 2 hub on another bus from the T5's `0x02210000`)* —
   and a test of this prediction on it. **Not a second *shape*, though:** the 1 TB scratch T5 is
   itself a two-slice drive — EFI `disk7s1` and data `disk7s2`, both seen going at every claim
   above — so items 1–8 on the scratch T5 already run a paused unplug on two slices. **Whether that is worth a run is the user's decision at the
   walk.** *(Decided 2026-09-11: walked, and the prediction held in both halves — see the result
   below.)* If the prediction fails — slice lines at the pull — the premise is back, and so is this
   item. `CONSTRAINTS.md` §1 *Under a claim* carries the same correction; the `.finishing` row's
   comment in `RunControlState.swift` still states the unclaimed premise and is owed a fix at the
   next code boundary.

   **Fixture: the 125.8 MB "General UDisk" thumb, serial `2211190533300386001515`, repartitioned
   into two exFAT slices** — `Slice_A` **59.8 MB** and `Slice_B` **64.0 MB**, the command having
   asked for 60M and a remainder. *(Corrected 2026-09-11: two slices, but one volume — `disk4s2`
   holds no exFAT and no name. See Prerequisites.)* User decision **2026-09-07**: the
   designated scratch T5 has one volume *(one volume but two slices, EFI and data — see the
   2026-09-10 prediction above)*, and the only other partitioned drive here is the 4 TB
   T5 EVO, which holds data a run would write over. Declared as role `multislice` in
   `scripts/lib/device-identity.sh`; resolve it by **serial**, never by node.

   **The thumb de-enumerated during its own repartition, 2026-09-07 10:44.** `diskutil
   partitionDisk` wrote the GPT and both slices — `disk4`, `disk4s1` and `disk4s2` all appear in
   the StorageKit log — and the storage stack then vanished mid-format while the **USB device
   stayed enumerated in IOKit with no `IOMedia` under it**. `diskutil` hung and was killed.
   **It was physically replugged the same day and came back complete.** *(Complete as a partition
   map. Its second slice never got its volume — found 2026-09-11, see Prerequisites.)* Confirm it is still
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
   for a two-partition drive. That is the fixture doing its job before it was asked to. *(Of the
   premise for an **unclaimed** drive, which is what a repartition is. A run's drive is claimed —
   see the 2026-09-10 prediction above.)*

**✅ CHUNK 4 PASSED 2026-09-11 — all nine items, on two drives.** Walked by the user at the
keyboard; the log read back with `/usr/bin/log show --style compact` and filtered by process. The
daemon was **pid 89541** before, between and after both pulls.

**Items 1–8 on the 1 TB scratch T5**, serial `12345686DAA9`, `disk7`, I/O size 4 MiB:

| Item | Reading |
|---|---|
| 1 | The pre-run prompt and `run authorised` both name serial `12345686DAA9`; the helper claimed `disk7` at 09:26:36.171 |
| 2 | `retention cycle END: paused by the user at block 1236992; 151/256 chunks` — read, wrote and verified 633,339,904 B each, no failed ranges — then `run paused and settled at block 1236992` and `pausing → paused on pauseSettled` at 09:26:40.219. The measurements panel: **every field plausible, by eye, before the pull** (the log's figures: read 477.3 MB/s, write 491.9 MB/s, R-W-R-C 160.7 MB/s) |
| 3 | `a disk disappeared: disk7 (whole disk)` at 09:29:33.544 — **one**, and no slice line, the slices having gone at the claim (09:26:36.173) |
| 4 | `device loss: nothing was in flight, ending the run now` (way 1) and `run ended: deviceLost` at 09:29:33.545 — **1 ms after the callback**, no deadline line. By eye: at once |
| 5 | `the drive under test left the machine while paused: Samsung Portable SSD T5 (serial 12345686DAA9), disk7 at run time` — **`paused`** |
| 6 | By eye: the GUI alive and usable |
| 7 | By eye: a report, and **this item's sentence word for word** — with chunk 2's items 1, 2 and 4 re-read on the same report and recorded there. Log: `run report: Ended — the drive disappeared from the USB bus, and the rest was not tested; … 0 failing block(s) in 0 range(s)` |
| 8 | `discovery found 5 USB whole disk(s): disk4, disk5, disk6, disk8, disk11` at 09:29:34.099, and again after `discovery resumed` at .116 |

Also seen, and gate items rather than this chunk's: the helper `released disk7` at 09:29:33.546;
after the report was dismissed, **no Resume** — Pause and Stop disabled, Start offered — and the
list on FR-DEV-3's default selection (`DeviceSelectionPolicy` rule 2, by design). **Replugged at
09:42:02.735**: `connected disk7`, still serial `12345686DAA9`, **no second loss line**, and
`fill.bin` still 999,947,239,424 bytes, modified 2026-09-04 18:19:30. *Not 5.1's number, recorded
beside chunk 3's so it is not taken for one:* `finishing → finished on deviceReleased` came
**551 ms** after `run ended` here and **368 ms** on the thumb, against 342–377 ms on chunk 3's six.
Not investigated.

**Item 9 on the 125.8 MB thumb**, serial `2211190533300386001515`, `disk4`, over USB High Speed
(480 Mb/s) where the T5 ran at 10 Gb/s. Paused at block 32768, 4/30 chunks. **The 2026-09-10
prediction held in both halves:**

- **at the claim**: `disk4s1 (slice)` and `disk4s2 (slice)` at 09:43:12.584;
- **at the pull**: exactly **one** `a disk disappeared: disk4 (whole disk)`, at 09:55:03.555, and
  no slice line;
- **the three checks**: **one** `the drive under test left the machine while paused: General UDisk
  (serial 2211190533300386001515), disk4 at run time`, **one** `run ended: deviceLost` in the same
  millisecond, and **one** report — by the user's eye, the UI *"exactly as before"*.

So 4.9 passed and, as declared, exercised no idempotency — one event cannot. Multi-slice
idempotency stays pinned by `threeCallbacksFromOneUnplugArmOneDeadline` alone.

⚠️ **"The same millisecond as the helper's `acquired`" was too tight.** On the T5 the slice lines
came **2 ms after** `acquired disk7` (.171 → .173); on the thumb **3 ms before** `acquired disk4`
(.584 → .587), 14 ms after the app unmounted `Slice_A`. Both are inside the claim — the helper
logs `acquired` once the claim is already held, and two processes' lines are not ordered at this
resolution — and both are **4–5 ms before `claimEstablished`** (.177, .589), which is
`RunController`'s own account of why its slice guard never fires. Read *"at the claim"* as within a
few milliseconds of it, never as an ordering.

**Two instrument readings taken on the way:**

- **`tools/device-id` logs into the app's own subsystem and category.** `scripts/lib/device-identity.sh`
  runs it, and each run writes `discovery found N USB whole disk(s)` exactly as the app does — two
  such lines at 09:43:52 were the resolver. **Read the process column on any `discovery` line**, and
  do not resolve a drive between a pull and its readback.
- **`log show --start` rejects fractional seconds** (*"Failed conversion of '… 09:29:34.2'"*) and
  prints only that error, which a line count reads as a one-line log. Whole seconds only.

**Two logging gaps, neither a product defect — to be fixed at the next app build (user decision
2026-09-11):**

- **The user's own commands leave no `run control: A → B` line.** Start, `pause()`, `resume()` and
  `stop()` assign `state` directly, and only `report(_:)` logs a transition — so this walk logged
  `pausing → paused` with no `running → pausing` before it, and the helper's `run control set to
  pause` is the only trace of the press.
- **FR-DEV-3's default re-selection is not logged.** `refresh()` applies `DeviceSelectionPolicy`
  silently; only a click logs `selected …`. The log cannot say which drive the app pointed at once
  the drive under test had gone.

*(Both closed in code 2026-09-11 at chunk 7g: `run control: A → B on the <Label> command` for every
accepted command, and `<reason>: selected diskN (capacity) by default — …` whenever the policy moves
the selection. Not yet seen by a person on an installed build — `PROGRESS.md`'s Owed row.)*

*(✅ **Seen 2026-09-11 16:14–16:19** on the installed 7g build, `abc07e3`, on the 1 TB scratch T5
(serial `12345686DAA9`, disk7) — read back from the unified log, not off the screen. Both gaps are
closed in fact: the run logged `idle → starting on the Start command`, `running → pausing on the
Pause command` **with** `pausing → paused on pauseSettled` after it — the missing half this item
was written for — `paused → stopping on the Stop command`, and the two event transitions to
`finished`; and the ejection of the idle selected drive logged `device connect/disconnect: selected
disk5 (256.64 GB) by default — the first usable drive (FR-DEV-3), because the selected one has
gone`, once, with launch having logged the `because nothing was selected` variant. ⚠️ **`paused →
running on the Resume command` was not seen**: the walk went Start → Pause → Stop, and the helper
log confirms no second `run control set to proceed` between them. It is the fourth label on the
same `apply(_:movingTo:)` call, and one of the three seen is enough to show the mechanism — but the
line itself is unseen, and this project records what a pass was true of. Carried in the Owed row.)*

*(✅ **And seen 2026-09-11 18:01:39–18:02:19**, on a second run made for it — same installed build,
same drive, now `disk4` after the replug, which is itself why a drive is named by serial and not by
node. `run control: paused → running on the Resume command` at **18:02:13.596**, six milliseconds
after the helper's own `run control set to proceed`; and the Stop that followed reads `running →
stopping on the Stop command`, **not** `paused → stopping` as it did at 16:18 — a second,
independent confirmation that the Resume actually moved the machine rather than only writing a
line. **All four command labels are now observed on hardware, and this item is closed in full.**)*

**What would invalidate this:** a behavioural change to `DeviceLossWindDown.swift`,
`RunController.swift`'s pause or device-loss path, `VolumeChangeWatcher`, `DeviceDiscovery`,
`HonestFraming.swift`, `RunReportPresentation.swift`, `RunReport.swift` or `DeviceLossAccount.swift`
— all app target, none of which moves the helper hash — or a helper-hash move, which lapses the
claim-and-release half. The two logging fixes above add lines and change no behaviour, but the
commit that makes them should re-read this list by name rather than assume so. *(Re-read by name
2026-09-11 at chunk 7g, from `git diff -U0` filtered to non-comment lines: `RunController.swift`'s
pause path — and start, resume and stop — now assigns through `apply(_:movingTo:)`, which logs one
line and makes the same assignment, so the same states in the same order; its device-loss path,
`DeviceLossWindDown.swift` and `VolumeChangeWatcher` changed comments only; `DeviceDiscovery.refresh()`
computes the same selection from the same inputs and logs after it; `HonestFraming.swift`,
`RunReportPresentation.swift`, `RunReport.swift` and `DeviceLossAccount.swift` are untouched; the
helper hash is unmoved. No behavioural change by this line's terms, so chunk 4 stands.)*

**Walked:** **2026-09-11**, 09:24–09:55  **Against build:** commit `c767317` — installed app built
from `2086090` (dylib `44610313…`, helper `7590b920…`; no app or helper source differs between the
two, and the working tree held documentation and script edits only), protocol **v15**, helper
source hash **`e19b0b3c…`**, daemon **pid 89541** started 2026-09-08 16:22:50 and resolved from
`/Applications`.

---

## Chunk 5 — the two measurements this step has never made *(WRITES to the scratch drive)* — ⚠️ *made 2026-09-09; read the note below first* — ✅ **DISCHARGED 2026-09-11**

Everything above checks a decision. This chunk measures the two facts those decisions were made
without.

⚠️ **Both measurements already exist, six trials each — read back 2026-09-10 from the persisted
unified log.** Chunk 3's re-walk pulled the cable six times on a *running* run on 2026-09-09,
against `982406a` (installed app from `0b37afd`, daemon pid 89541, helper `e19b0b3c…`), and 5.1's
own step 1 is *"Run chunk 3 again with the log stream timestamped"* — so those six pulls are six
trials on the item's own definition, and the log kept microseconds. The readings are under 5.1 and
5.2. **Whether they discharge this chunk is the user's decision at the walk**: if they do, 5.1 and
5.2 need no further cable pull and 5.3 needs only the reading under it. **✅ Decided 2026-09-11:
they do** — 5.1 and 5.2 from the six pulls, and 5.3 from the helper's cycle tallies in place of the
metrics panel. See the **Walked** line at the end of this chunk. ⚠️ The log will not keep
them for ever; the raw lines are in the message of the commit that added this note
(`git log -S'six trials each' -- progress/step-12-human-checklist.md`).

### 5.1 — how long route (a)'s reply actually takes

`DeviceLossWindDown.defaultDeadlineSeconds` is **3**, and its own documentation says the figure was
chosen to be *uncontroversially generous rather than tuned*: **"No real measurement stands behind it
yet."** This is that measurement.

1. Run chunk 3 again with the log stream timestamped — `--style compact` stamps to the
   **millisecond**, which is the resolution this item needs *(found 2026-09-10 saying
   "microseconds", which `--style compact` does not give)*:

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

So step 4's second branch is already refuted *(it is not: six real unplugs put the reply in
single-digit milliseconds — see the six-trial reading below, 2026-09-10)*. **The three-second figure is not generous by three
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

**✅ The six-trial reading — taken 2026-09-09, read back 2026-09-10 — and it inverts the first.**
From the persisted unified log (`/usr/bin/log show`, microseconds): chunk 3's six pulls, `disk7` =
Portable SSD T5 `12345686DAA9`, against `982406a`, daemon pid 89541, helper `e19b0b3c…`.

| Trial | Pull | Phase | (a) helper ends the cycle → (b) callback | **(b) callback → `run ended`** | Call had run for | Deadline |
|---|---|---|---|---|---|---|
| 1 | 13:15:15.920 | `verifying` | 1.8 ms | **4.2 ms** | 3.75 s | not reached |
| 2 | 15:20:50.995 | `reading` | 2.0 ms | **6.3 ms** | 4.10 s | not reached |
| 3 | 15:23:58.986 | `verifying` | 1.9 ms | **3.3 ms** | 3.15 s | not reached |
| 4 | 15:27:40.151 | `verifying` | 1.8 ms | **2.7 ms** | 3.69 s | not reached |
| 5 | 15:30:01.768 | `reading` | 1.9 ms | **4.9 ms** | 5.46 s | not reached |
| 6 | 15:31:09.562 | `writingBack` | 0.8 ms | **3.0 ms** | 4.64 s | not reached |

The bold column is step 2's interval, line to line: `the drive under test left the machine while
running` → `run ended: deviceLost`. *Call had run for* is the helper's `retention cycle START` →
`retention cycle END` — the number the 2026-09-08 note above asked to be recorded alongside. All six
logged `device loss: a call is in flight; waiting up to 3.000000s`, and **none** logged `no reply
after`.

- **Step 4's second branch: all six land in single-digit milliseconds.** 3 s is **479× to 1,098×**
  the readings — about three orders of magnitude, as the constant's own comment supposed. A
  deadline firing therefore does mean *something is wrong*, not *something is slow*.
- **Route (a) fires first at the helper and arrives second at the app, every time.** The helper
  ends its cycle on `ENXIO` 0.8–2.0 ms before the removal callback, and its reply lands 2.7–6.3 ms
  after it. So the wind-down started waiting in all six, and *the run ended by itself* — its way 2
  — resolved all six. The race `DeviceLossWindDown`'s header calls the overwhelmingly common case
  is the only one seen.
- **The deadline does not race the call.** In four of the six the call had already run past 3 s when
  the drive left, and the reply still came within 6.3 ms, because `ENXIO` cuts the call short in
  about a millisecond. The deadline starts at the callback and bounds only what is left of the call
  after a real loss. The 6.67 s of 2026-09-08 was a call nothing cut short, because nothing had been
  unplugged — which is what the 7f defect looked like from here.
- **Not 5.1's number, recorded so it is not taken for it:** `finishing → finished on
  deviceReleased` came **342–377 ms** after `run ended` in all six. That is the release being
  acknowledged, not the reply, and it was not investigated.

**Owed at the next code boundary:** `DeviceLossWindDown.defaultDeadlineSeconds`'s header still says
*"No real measurement stands behind it yet"*. App target; it moves no helper hash. *(Paid
2026-09-11 at chunk 7g: the header now carries these six readings.)*

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

**✅ Answered — taken 2026-09-09, read back 2026-09-10: no short transfer, six of six.** Every one
of chunk 3's six pulls failed its in-flight I/O **after 0 bytes** with `errno 6 (Device not
configured)` — five reads and, on trial 6, a **write** (`write of 8388608 bytes at offset 713031680
failed after 0 bytes`), so the answer covers both directions. Every run's `run report:` line says
`0 failing block(s) in 0 range(s)`: step 4's count is **zero, six times**. The cycle tallies agree —
where the loss hit a verify read, `verified` trails `wrote` by exactly one 8 MiB chunk (trials 1, 3
and 4); where it hit a read, all three tallies are equal (2 and 5); where it hit the write-back,
`wrote` trails `read` by one chunk (6). **So step 3's branch: the drive went straight to `ENXIO`**,
and `classify`'s note is owed its update from *open* to *measured: it does not happen, six of six*.
⚠️ **That note is in `RetentionTestEngine.swift`, which is helper source — editing it moves the
helper source hash and lapses the four hardware gates.** Batch it with the next helper change rather
than buying a gate re-run for a comment. *(User decision 2026-09-11, at chunk 7g: exactly that — it
waits for the next helper-source change.)*

### 5.3 — the offset, for the gate item

BUILD-PLAN's gate asks that the logs be *"sufficient to reconstruct what happened (which device, at
what offset)"*. **Which device** is item 3.5. **At what offset** is the report's, not the log's —
chunk 5 (2026-09-06) put the block in `DeviceLossAccount` rather than only in a log line. Confirm
the report names a block, and that the block is plausible against the bytes the metrics panel showed
before the pull.

**Partly read back 2026-09-10.** For trials 2, 4, 5 and 6 the block was read off the report on
screen on 2026-09-09 — chunk 3 item 9's table: 1,261,568, 1,130,496, 1,687,552 and 1,392,640 — and
each equals the helper's own `retention cycle END: ended at block …` for that run, and is exactly
the first block of the chunk whose I/O failed (block × 512 = the offset in the `failed after 0
bytes` line). Plausibility against the **metrics panel** is a reading nobody took; the cycle's byte
tallies say the same thing more precisely, and whether they stand in for it is part of the chunk 5
decision above. **✅ Decided 2026-09-11: they stand in for it.**

**Walked:** **not walked — DISCHARGED 2026-09-11 by user decision**, from chunk 3's six cable pulls
of 2026-09-09.  **Against build:** those pulls ran against `982406a` — installed app from
`0b37afd`, daemon **pid 89541**, helper source hash **`e19b0b3c…`**, protocol **v15**, I/O size
8 MiB. **They describe the current build too**: the same daemon process is still running, and the
app source from `0b37afd` to the installed `2086090` differs **in comments only** —
`RunController.swift` and `RunReportPresentation.swift` doc comments, plus `render-ui.sh`'s usage
line (`git diff 0b37afd 2086090`, read 2026-09-11). **5.1**: six trials against the three asked
for, 2.7–6.3 ms from the removal callback to `run ended`, the deadline never reached. **5.2**: no
short transfer, six of six, 0 failing ranges each time. **5.3**: the report's block equals the
helper's `ended at block …` on all four trials that read one off the screen. Lapses with a
behavioural change to `DeviceLossWindDown.swift` or `RunController.swift`'s device-loss path, or a
helper-hash move. Owed from it: `DeviceLossWindDown.defaultDeadlineSeconds`' header (5.1, app
target) and `classify`'s note (5.2, **helper source** — moves the hash), both listed in
`PROGRESS.md`'s Owed row. *(2026-09-11, at chunk 7g: the first is paid; the second waits for the
next helper-source change, by user decision. In `DeviceLossWindDown.swift` and on
`RunController.swift`'s device-loss path 7g changed comments only, so this stands.)*

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
  gap rather than claimed as covered. *(Seen again 2026-09-11 after chunk 4's paused unplug: the
  1 TB scratch T5 replugged, `connected disk7`, no second loss line. Same weakness.)*

* **Which log level a device-loss line carries.** `deviceLost`, `driveCannotBeWatchedForRemoval`,
  `releaseCannotBeConfirmed` and `deviceLostWithNoReport` are all **error**; `releaseAcknowledgedLate`
  is **notice**, and it is the *good* ending of `releaseCannotBeConfirmed`. Nothing automated reads a
  log line, so the level distinction has no cover at all — the same gap increment 12 recorded for
  `reportARefusedTermination`. **Chunk 3.11 is the check**, and it asks which of the two lines
  appeared rather than whether either did. *(The paused case's `deviceLost` line logged at **error**
  on both of chunk 4's pulls, 2026-09-11 — `E` in the compact style's type column.)*

* **The three-second deadline as a duration.** `DeviceLossWindDownTests` injects the schedule, so
  the deadline's *behaviour* is pinned exactly — it fires once, it does not fail open, it is
  idempotent — with **no real time passing**. That is the right design (a test that sleeps for a
  deadline is slow now and flaky later) and it means the number itself is untested by construction.
  **Chunk 5.1 is the only thing that can put a measurement behind it.** *(Six measurements behind
  it as of 2026-09-10 — 2.7–6.3 ms from the removal callback to the reply; see 5.1. Still no
  automated cover, which is what this list is about.)*

* **`errno` on real hardware.** That a de-enumerating drive returns `ENXIO` at all rests on **one
  observation** — the 2026-08-06 incident — which is evidence and not a gate.
  `FileDescriptorBlockDevice`'s header table carries the same split, and `DeviceLossTests`'s header
  says so in its second section. **Chunks 3 and 4 are the first deliberate reproduction.**
  *(Reproduced **six times** by chunk 3's pulls on 2026-09-09 — `ENXIO` after 0 bytes every time,
  five reads and one write — read back from the log 2026-09-10; see 5.2. **Chunk 4 cannot add to
  it**: a paused run issues no I/O, so there is no errno to see — which is chunk 4's whole premise.)*
