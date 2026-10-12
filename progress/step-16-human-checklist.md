# Step 16 — the human checklist

> **STATUS, 2026-10-12: APPROVED FOR THE WALK, NOT YET WALKED.** Written at Step 16's chunk 5a, against the release
> artefact `build/release/a7eee6c/USBDriveTester-1.0-1-a7eee6c.zip`, sha256 `ed695b8f…`, built
> from `a7eee6c`: protocol v16, helper source hash `36c3a9e1…`. Nothing below has been walked.
> Chunk 5b is the walk, on the clean second Mac, **approved by the user 2026-10-12**.
> *(2026-10-12: reviewed by the user, who answered its two questions — no re-register is added,
> and gate item 4 is to name Full Disk Access at chunk 6.)* *(2026-10-12, later: **amended before
> the walk**, by the user's approval, for `Quick_Start_Guide.md`, which chunk 6 writes from this
> walk — screenshots at 4.1, 4.3 and 4.4, and an optional item 6.5 that removes the app. This
> line said "WRITTEN, NOT WALKED", "it needs the user's approval before it starts" and "chunk
> 5b has not been approved" until then.)*
> *What would invalidate these instructions:*
> - another artefact — item 0 names this one by its hashes;
> - an edit to any string quoted below — each is quoted from the source at `6059eb2`;
> - a clean Mac that is not on macOS 26.

---

## Why this exists, in one paragraph

Everything Step 16 has measured, it measured on a Mac that has approved this app many times over.
That Mac has approved its helper, its Team ID and its Full Disk Access, and it caches every one of
those approvals. None of them exists on the Mac a user would install it on.

`BUILD-PLAN.md`'s Step 16 risks name four things that matter and that **nobody has measured**:

1. **Gatekeeper.** Whether macOS lets a quarantined app that is not notarized and is signed
   *Apple Development* open at all, and in what words. Detailed step 9's release notes quote those
   words.
2. **launchd.** Whether launchd will start the helper inside such an app.
3. **The provisioning profile.** Whether the helper runs on another Mac at all, since it carries
   `com.apple.application-identifier` with no provisioning profile.
4. **macOS 26.** Whether this code runs on macOS 26. Everything built since 2026-09-16 has run only
   on macOS 27.

No test reaches any of the four. This walk is the only instrument, and **a Mac is clean only the
first time**, which is why the stop rules below are strict.

---

## Running it

**Two Macs.** Item 0.1 runs on this Mac, the development Mac. Everything else runs on the clean
Mac.

**The stop rule.** When any item fails, stop at that item and record it. Then jump to item 7, which
gathers the evidence and brings it back, and report. **Do not repair anything on the clean Mac**,
because the first attempt is the only one made on a clean Mac:
- no second copy, and no re-download;
- no `xattr -d`, and no `launchctl kickstart`;
- no reboot to see whether it helps;
- no pressing a remedy twice.

Findings are reported, not fixed.

⚠️ **Never press *Move to Trash*** in any dialog. Close a refusal with the button that does not
delete.

**The instruments.** Every Terminal command below uses only what ships with macOS: no Xcode and no
repository. There are two Terminal windows and a screenshot habit.

- **Window A records itself.** Item 0.2 starts `script` in it, which writes every command typed
  and every line printed to `/Users/Shared/USBDriveTester-clean-mac/terminal.txt`, until item 7's
  `exit`. Nothing has to be pasted back by hand.
- **Window B runs `log stream`** into a file, from before the app is first opened until item 7. It
  takes both the app's and the helper's lines. It also takes any system process's line that names
  the app, such as Gatekeeper's, launchd's, TCC's and BTM's.
  - Step 15's traced run was judged on a live stream. That makes it the instrument here as well, and
    item 7's `log show` is the second copy.
- **A screenshot of every dialog, sheet and notification** — ⇧⌘4, then Space, then click the
  window. They land on the clean Mac's Desktop, and item 7 moves them into the folder.
  - The wording is recorded **exactly**, because the release notes quote it, and a screenshot is
    the record that cannot be paraphrased.
  - *(Added 2026-10-12.)* The screenshots are also what `Quick_Start_Guide.md` is made from. So
    three screens that are not dialogs are asked for too: the main window with the drive selected
    (4.1), Full Disk Access switched on (4.3), and the run under way (4.4). Item 6.5 asks for its
    own. Take them uncropped; chunk 6 crops out this Mac's user and computer names.

**Why the commands use `/Users/Shared` and `$HOME`.** The clean Mac's user name is not known here.
- `/Users/Shared` has the same path on every Mac, and every user can write to it, so the evidence
  folder lives there.
- `$HOME` appears only where the file belongs to the clean Mac's user. That is `Downloads`, where
  AirDrop puts what it receives.

**Time.**

| Part | Time |
|---|---|
| Items 0–3 | about 20 minutes |
| Item 4's run | about two hours, the estimate below |
| Items 5–7 | about 15 minutes, and about 10 more with the optional 6.5 |

The two hours is arithmetic, not a measurement: no whole run on this drive has a recorded duration.
- One whole-drive read pass of the retention gate took 44 min 20 s on this Mac, 2026-10-09.
- The device reads at 477–482 MB/s in the product's own run path, which is about 35 min per pass
  over 1.0 TB.
- A run reads every byte twice and writes it once.

The clean Mac's port may be faster or slower.

### Prerequisites

* **The clean Mac:**
  - **Apple silicon.** The artefact is `arm64` only (`MANIFEST.txt`: *"arm64, minos 26.0"*).
  - **macOS 26.** Item 0.2 records the exact version.
  - It has **never run any build of this app**. Item 0.2 checks four ways.
  - An **administrator account**. *Open Anyway*, the background-item approval and Full Disk
    Access each ask for one.
  - It can **receive AirDrop** from this Mac.
  - It is on **mains power**.

* **The drive — the 1 TB scratch T5, and nothing else:**

  | drive | serial | |
  |---|---|---|
  | the 1 TB scratch T5 | `12345686DAA9` | volume `Test_Drive`; holds the random fill; the drive gate item 4 names |

  ⚠️ **Identify it by serial, in the app's device pane and in the pre-run prompt.** Three of this
  project's drives are T5s.
  - Attach no other external drive to the clean Mac for the walk, if that can be helped.
  - **The 22 TB Seagate stays here**, as do the 1 TB EVO Plus and the other two write targets.

  Eject `Test_Drive` in Finder on this Mac before unplugging the T5.

* **Nothing of ours on the clean Mac.** No other copy of the app, no zip, and no earlier attempt.

---

## Item 0 — which build, and is the Mac clean *(no writes)*

**0.1 — this Mac: the zip is the artefact.**

```bash
/usr/bin/shasum -a 256 /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/build/release/a7eee6c/USBDriveTester-1.0-1-a7eee6c.zip
```

*Pass:* `ed695b8fa493032ca24f25fe7ac681be91cd43b28052f9b7ed1b860bdf97d8e4`.

Then send that file to the clean Mac by **AirDrop**: in Finder, Share › AirDrop. A copy made from a
drive is not checked.

*What would invalidate it:* another `release.sh` run into `build/release/`, or any edit to the zip.

**Record:**

**0.2 — the clean Mac is clean.** Open Terminal: this window is **window A**. Create the evidence
folder, then start the recording.

```bash
/bin/mkdir -p /Users/Shared/USBDriveTester-clean-mac
```

```bash
/usr/bin/script -a /Users/Shared/USBDriveTester-clean-mac/terminal.txt
```

Then run each of these:

```bash
/usr/bin/sw_vers; /usr/bin/uname -m; /bin/date
```

```bash
/bin/ls -d /Applications/USBDriveTester.app
```

```bash
/usr/bin/defaults read com.arc3solutions.USBDriveTester
```

```bash
/bin/launchctl print system/com.arc3solutions.USBDriveTester.Helper
```

```bash
sudo /usr/bin/sfltool dumpbtm > /Users/Shared/USBDriveTester-clean-mac/btm-before.txt
```

```bash
/usr/bin/grep -c -i -E 'arc3solutions|USBDriveTester' /Users/Shared/USBDriveTester-clean-mac/btm-before.txt; /usr/bin/grep -c 'Records for UID' /Users/Shared/USBDriveTester-clean-mac/btm-before.txt
```

Last, open System Settings › Privacy & Security › Full Disk Access and look for USBDriveTester.

*Pass:*

| Check | Pass |
|---|---|
| macOS | `ProductVersion` 26.x |
| architecture | `arm64` |
| `ls` | *No such file or directory* |
| `defaults` | *Domain com.arc3solutions.USBDriveTester does not exist*. The app keeps its settings there, so the app has never run as this user |
| `launchctl` | *Could not find service* |
| BTM | **0** lines name it, against a control of **≥ 1** `Records for UID` line. A 0 with a 0 control means the dump failed, not that the Mac is clean |
| Full Disk Access | does not list USBDriveTester |

*What would invalidate it:* anything that runs this app on the clean Mac before item 1.

**Record:**

**0.3 — the copy arrived intact and quarantined.**

```bash
/usr/bin/shasum -a 256 "$HOME/Downloads/USBDriveTester-1.0-1-a7eee6c.zip"
```

```bash
/usr/bin/xattr -p com.apple.quarantine "$HOME/Downloads/USBDriveTester-1.0-1-a7eee6c.zip"
```

*Pass:*
- The hash is 0.1's.
- The second command **prints a value**.

If it prints *No such xattr*, stop. A copy that is not quarantined does not test what gate item 4
asks.

**Record:**

**0.4 — unpack it and move it, without opening it.**
1. Double-click the zip in Finder. Archive Utility unpacks it, and it carries the quarantine to what
   it unpacks.
2. In Finder, **drag `USBDriveTester.app` from Downloads to Applications**.
3. **Do not open it yet.**

Why Finder for the move:
- An app opened where it was unpacked runs from a randomised read-only copy, which is *app
  translocation*.
- `SMAppService` records the registering app's path (`README.md`).

Then run each of these:

```bash
/usr/bin/xattr -p com.apple.quarantine /Applications/USBDriveTester.app
```

```bash
/usr/bin/xattr -p com.apple.quarantine /Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper
```

```bash
/usr/bin/codesign --verify --deep --strict --verbose=2 /Applications/USBDriveTester.app
```

```bash
/usr/bin/codesign -dvvv /Applications/USBDriveTester.app 2>&1 | /usr/bin/grep -E '^(Identifier|CDHash|Authority|Timestamp|TeamIdentifier|Runtime Version)='
```

```bash
/usr/bin/codesign -dvvv /Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper 2>&1 | /usr/bin/grep -E '^(Identifier|CDHash|Authority|Timestamp|TeamIdentifier|Runtime Version)='
```

```bash
/usr/bin/shasum -a 256 /Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester /Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper
```

```bash
/usr/sbin/spctl -a -vv /Applications/USBDriveTester.app
```

*Pass:*

| | app | helper |
|---|---|---|
| quarantine | prints a value | prints a value — **a reading**: if it is absent, the launchd risk was not exercised, and the record says so |
| `--verify` | *valid on disk*, *satisfies its Designated Requirement* | (covered by `--deep`) |
| `Identifier` | `com.arc3solutions.USBDriveTester` | `com.arc3solutions.USBDriveTester.Helper` |
| `CDHash` | `41355694bcb4e5e09c41c59347a54326de2406b2` | `d9eeeecc7de8b1a2909bd89ddfdb1c2d337cb187` |
| `Authority` | `Apple Development: … (424WY3TDB4)`, then the WWDR CA and Apple Root CA | the same |
| `Timestamp` | Oct 9, 2026 at 1:00:02 PM | Oct 9, 2026 at 1:00:01 PM |
| `TeamIdentifier` | `5JC55GTLZA` | `5JC55GTLZA` |
| sha256 | `07c392f6686c6fc850f4bc8860b5e528864c6bb48bf5dc42159035a63259603c` | `b5b807aa18052d7c7915c6c473dda39cbaf02556b1d87d0350b12a6738303d29` |

`spctl` reads *rejected*, which is **not met, as decided 2026-10-09**: there is no Developer ID.
Record its line; it is not a failure of this walk.

The timestamps are in the clean Mac's time zone, and these are this Mac's Pacific readings. A
different hour with the same minutes is the same timestamp.

**Record:**

---

## Item 1 — macOS refuses the first open, and *Open Anyway* opens it *(gate item 4; detailed step 9's wording)*

Start **window B** first: Terminal › New Window. Leave it running until item 7.

```bash
/usr/bin/log stream --level info --style compact --predicate 'subsystem == "com.arc3solutions.USBDriveTester" OR eventMessage CONTAINS[c] "USBDriveTester"' > /Users/Shared/USBDriveTester-clean-mac/log-stream.txt
```

**1.1 — the refusal.** In Finder, double-click `USBDriveTester` in Applications.

*Pass:* macOS refuses to open it.
- Screenshot the dialog.
- Record its title, its body and its buttons, word for word.
- Close it with the button that does not delete it.

**Record:**

**1.2 — *Open Anyway*.**
1. Open System Settings › Privacy & Security and scroll to *Security*.
2. Screenshot the line that names USBDriveTester, with its **Open Anyway** button.
3. Press **Open Anyway**.
4. Authenticate when asked; the password is yours to type.
5. Screenshot **each** dialog that follows, and confirm the open.

*Pass:* the app opens.
- Record every dialog's wording, in order.
- Record what authentication was asked for, and where.

**Record:**

**1.3 — it runs from `/Applications`, not a translocated copy.** Run each of these in window A:

```bash
/bin/ps -axo pid=,ppid=,uid=,comm= | /usr/bin/grep '[U]SBDriveTester'
```

```bash
/usr/bin/xattr -p com.apple.quarantine /Applications/USBDriveTester.app
```

*Pass:*
- The app's row is `/Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester`.
- No path contains `AppTranslocation`.
- **Note the app's pid**: item 3 looks for it.
- The quarantine value after *Open Anyway* is **a reading**. Compare it with 0.4's.

*What would invalidate item 1:*
- another macOS release — the dialogs are macOS's, not this app's;
- another artefact.

**Record:**

---

## Item 2 — it registers the helper, and after approval enables it *(gate item 4)*

**2.1 — the first gate.**

*Pass:* the main window opens behind the helper gate.
- The gate reads ***"The privileged helper is not installed yet."***
- It offers **Register Helper** and **Quit**.
- Screenshot it.

Window B's file holds:
- `registration manager initialised; daemon com.arc3solutions.USBDriveTester.Helper.plist status notRegistered`
- a `helper gate: notRegistered` line.

⚠️ **If it reads *"The privileged helper is missing from this app."* instead**, that is `notFound`,
the one state the gate offers only Quit for. It is a finding, and the walk stops:
1. Do not quit.
2. Screenshot the gate.
3. Open Privileged Helper & Diagnostics (⇧⌘D) and screenshot its *Helper registration* section.
4. Go to item 7.

**Record:**

**2.2 — Register Helper.** Press it.

*Pass:*
- It shows ***"Installing the helper…"*** briefly.
- Then it reads ***"The privileged helper is waiting for your approval."***, with **Open Login
  Items…** and **Quit**.
- Window B holds `register() requested for com.arc3solutions.USBDriveTester.Helper.plist` and
  `register() submitted; awaiting user approval`.

Screenshot the gate, and **any notification macOS posts about a background item**. Record that
notification's wording.

**Record:**

**2.3 — the approval.** Press **Open Login Items…**.

*Pass:* System Settings opens at General › Login Items & Extensions.
1. Screenshot USBDriveTester's entry under *Allow in the Background*.
2. Switch it on.
3. Authenticate when asked.
4. Screenshot any dialog.
5. Switch back to the app.

*Pass:*
- The gate re-checks on activation and clears by itself, without a relaunch.
- The device list shows.
- Window B holds `daemon status changed requiresApproval -> enabled`.

**Record:**

**2.4 — the helper is running, as root, from `/Applications`.** Run each of these in window A:

```bash
/bin/launchctl print system/com.arc3solutions.USBDriveTester.Helper | /usr/bin/grep -E '^\s*(state|pid|program identifier|runs|last exit code) ='
```

```bash
/bin/ps -axo pid=,ppid=,uid=,comm= | /usr/bin/grep '[U]SBDriveTester'
```

*Pass:*
- `state = running` and a `pid`.
- `program identifier = Contents/MacOS/com.arc3solutions.USBDriveTester.Helper`.
- Two `ps` rows:
  - the app, under your uid;
  - `/Applications/USBDriveTester.app/Contents/MacOS/com.arc3solutions.USBDriveTester.Helper`
    with **uid 0** and **ppid 1**.

⚠️ **The two unmeasured risks show here.** launchd may refuse to start a quarantined helper that is
not notarized. Or the kernel may refuse a helper that carries `com.apple.application-identifier`
with no provisioning profile. The signs:
- the gate reads ***"The privileged helper did not answer."***;
- `launchctl` shows no pid, or a `last exit code` that is not 0;
- there is no helper row.

If you see any of them:
1. Press **Retry** once, and only once.
2. Screenshot the result.
3. Go to item 7, which keeps `launchctl` and every system line naming the app.

**Record:**

*What would invalidate item 2:* another macOS release, another artefact, or anything that registers
this app on the clean Mac before 2.1.

---

## Item 3 — the helper accepts the shipped app *(gate item 5, the clean Mac's half)*

The other half — the shipped app satisfies the requirement under `codesign -v -R` — was met on this
Mac at chunk 3 (`MANIFEST.txt`, *Gate item 5*).

```bash
/usr/bin/grep -E 'helper started as uid|admitted connection|protocol-version handshake|FAILED the Team-ID' /Users/Shared/USBDriveTester-clean-mac/log-stream.txt
```

*Pass:* in order, these lines, shown here as they read on this Mac on 2026-10-09:

```
… helper started as uid 0; listening on com.arc3solutions.USBDriveTester.Helper; protocol v16; requiring [anchor apple generic and certificate leaf[subject.OU] = "5JC55GTLZA"]
… admitted connection from pid N (identifier com.arc3solutions.USBDriveTester, team 5JC55GTLZA) with the Team-ID requirement armed; exporting TesterControl v16. …
… protocol-version handshake with pid N (identifier com.arc3solutions.USBDriveTester, team 5JC55GTLZA); helper implements v16
```

- `N` is the app's pid from 1.3.
- Any `invalidated … FAILED the Team-ID requirement` line has a request line from the same pid
  before it. Such a line is logged on every ordinary disconnect too; one with **no** request line
  before it is a refusal.

Then open Privileged Helper & Diagnostics (⇧⌘D) and press **Ping helper**, then **Check protocol
version**.

*Pass:*
- Both succeed.
- The version check names v16.
- *Running from* reads `/Applications/USBDriveTester.app`.
- No *"Running from a temporary build location"* warning.

Screenshot the window.

*What would invalidate it:* an edit to the helper's admission or handshake log lines, which moves
the helper source hash; another artefact.

**Record:**

---

## Item 4 — a full run on the 1 TB scratch T5 *(gate item 4; writes to the drive)*

**4.1 — the drive.** Plug the 1 TB scratch T5 into the clean Mac and select it in the device list.

*Pass:* the selected device pane shows serial **`12345686DAA9`**.

Screenshot the main window, with the drive selected.

**Record:**

**4.2 — Start, and the warnings.** Press **Start**.

*Pass:* the **"Before you start"** sheet, with the full warnings, because this is the first run on
this Mac.
- Its question names ***"… serial 12345686DAA9?"***.
- Leave ***"Don't show this warning again"*** unchecked.
- Screenshot it.
- Press **Proceed**.

**Record:**

**4.3 — Full Disk Access, the first time.** On a Mac that has never granted it, this is the expected
path. Step 11's chunk 14 item 4 walked it on this Mac on 2026-09-02, by revoking the grant.

*Pass:*
- A modal headed ***"Full Disk Access has not been granted"***.
- Its body is the helper's own words: *"This app needs Full Disk Access before it can test a drive.
  Open System Settings › Privacy & Security › Full Disk Access, add USBDriveTester, then try
  again. …"*
- **Open Full Disk Access Settings…** as the default button, with **Cancel Test** beside it.
- Window B holds `run aborted before any write: This app needs Full Disk Access …`.
- **`Test_Drive` is still mounted** in Finder.

Screenshot it.

Then:
1. Press **Open Full Disk Access Settings…**. *Pass:* System Settings opens at that pane.
2. **Record whether USBDriveTester is already listed (switched off) or not listed at all.**
3. Switch it on, or add `/Applications/USBDriveTester.app` with **+**.
4. Authenticate when asked. Then screenshot the pane, with USBDriveTester listed and switched on.
5. If macOS offers to quit and reopen the app, **choose Later**. Record the offer's wording.
6. Switch back to the app.
7. Press **Start** again **without relaunching**, then **Proceed**.

*Pass:* the run starts. Window B holds
`[run <ID>] run authorised: drive serial 12345686DAA9; I/O size 4194304 bytes; mode …`.

**These are readings, not failures:**
- If the run is refused for Full Disk Access again: quit the app, open it once more, try once, and
  record both.
- If no modal appears at all and the run starts straight away: record it.

**Record:**

**4.4 — while it runs, uninstalling is refused** *(Step 4's lifecycle)*. First, screenshot the main
window while the run is under way, with its progress showing. Then open ⇧⌘D.

*Pass:* it shows ***"A run is in progress, so uninstalling the helper will be refused."***

Press **Uninstall helper**.

*Pass:*
- It shows ***"A test run is active. Stop the run before removing the helper, so the device is
  released cleanly."***
- The run goes on.
- Window B holds `uninstall requested (runIsActive=true)`, then `uninstall refused: a run is active`.

This is safe to press. The refusal is the app's own first step, and it sends the helper nothing
(`HelperRegistration.uninstall`, step 1).

Screenshot it, then close the window.

**Record:**

**4.5 — it completes.** Leave it to finish. The app holds an idle-sleep assertion (Step 13), so the
display may sleep, and the Mac should not.

*Pass:*
- The report sheet shows the run completed with **"No block ranges failed."**
- In window A:

```bash
/usr/bin/grep -E 'run authorised|acquire GRANTED|run ended|release requested' /Users/Shared/USBDriveTester-clean-mac/log-stream.txt
```

  It shows `run authorised`, `acquire GRANTED for pid N (identifier com.arc3solutions.USBDriveTester,
  team 5JC55GTLZA)`, `run ended: completed` and `release requested`. All four carry **the same
  `[run <ID>]`**.
- `Test_Drive` mounts again afterwards.

Record:
- the start and end times;
- the outcome headline;
- the final read and write rates, as readings.

Screenshot the report sheet.

*What would invalidate item 4:* another artefact; another macOS release; an edit to any line quoted
here.

**Record:**

---

## Item 5 — the report is exported through the save panel *(gate item 4)*

It is the app's only file panel. The dropped `files.user-selected.read-only` entitlement no longer
covers it (chunk 2).

In the report sheet, press **Export report…**.

*Pass:* a save panel:
- titled ***"Export run report"***;
- with the message ***"Each run stands alone — no history is kept, so this is the only copy that
  will exist."***;
- named `usb-drive-test-12345686DAA9-<yyyy-MM-dd-HHmm>.md`.

Screenshot it. Then:
1. Press ⇧⌘G and paste `/Users/Shared/USBDriveTester-clean-mac`.
2. Press Return.
3. Press **Save**.

*Pass:*
- No error alert.
- Window B holds `run report exported: outcome …; drive serial 12345686DAA9; <N> bytes`.
- The file is there, at that size:

```bash
/bin/ls -l /Users/Shared/USBDriveTester-clean-mac/
```

Then press **Done**.

**Record:**

---

## Item 6 — the helper uninstalls cleanly *(gate item 4; Step 4)*

**6.1 —** Open ⇧⌘D and press **Uninstall helper**.

*Pass:*
- *Status* reads **notRegistered**.
- Window B holds, in order:
  1. `uninstall requested (runIsActive=false)`
  2. `helper confirmed it is idle; proceeding with uninstall`
  3. `unregister() returned without error`
  4. `uninstall complete; status notRegistered`

Screenshot it.

**Record:**

**6.2 —** Run each of these in window A:

```bash
/bin/launchctl print system/com.arc3solutions.USBDriveTester.Helper
```

```bash
/bin/ps -axo pid=,ppid=,uid=,comm= | /usr/bin/grep '[U]SBDriveTester'
```

*Pass:*
- `launchctl` reports *Could not find service*.
- The app's row is the only one; there is no helper row.

**Record:**

**6.3 —** Quit the app with ⌘Q, then open it again from Applications.

*Pass:*
- It shows the gate's ***"The privileged helper is not installed yet."***
- Whether a Gatekeeper dialog appears on this second open is **a reading**; record it.

Quit it again.

**Record:**

**6.4 — BTM afterwards (a reading, no pass criterion).**

```bash
sudo /usr/bin/sfltool dumpbtm > /Users/Shared/USBDriveTester-clean-mac/btm-after.txt
```

```bash
/usr/bin/grep -n -i -E 'arc3solutions|USBDriveTester' /Users/Shared/USBDriveTester-clean-mac/btm-after.txt
```

**Record:**

**6.5 — the app itself is removed** *(optional; added 2026-10-12 for `Quick_Start_Guide.md`'s
uninstall section — no gate item asks for it)*. To keep the app on this Mac, skip to item 7.
- It comes after 6.1 because that is the order the guide will give: the helper first, then the app.
  An app removed with its helper still registered is not walked.
- It comes before item 7 so that its screenshots and readings go back with the rest. The evidence
  is in `/Users/Shared` and on the Desktop, and nothing here touches either.

1. Check the app is not running — 6.3 quit it.
2. Open *System Settings › Privacy & Security › Full Disk Access* and *System Settings › General ›
   Login Items & Extensions*. Record what each shows for USBDriveTester now — the second under
   *Allow in the Background* — and screenshot each.
3. In Finder, drag `USBDriveTester` from Applications to the Trash. **Do not empty the Trash.** This
   is a deliberate drag, not a dialog's *Move to Trash* button, which the rule at the top of this
   file is about.
4. In *Full Disk Access*: if USBDriveTester is still listed, select it, press **−** and authenticate
   when asked. Screenshot the pane.
5. In *Login Items & Extensions*: record whether USBDriveTester still appears. Screenshot it.
6. In window A, run each of these:

```bash
/bin/ls -ld /Applications/USBDriveTester.app
```

```bash
/bin/ps -axo pid=,ppid=,uid=,comm= | /usr/bin/grep '[U]SBDriveTester'
```

```bash
sudo /usr/bin/sfltool dumpbtm > /Users/Shared/USBDriveTester-clean-mac/btm-after-app-removed.txt
```

```bash
/usr/bin/grep -n -i -E 'arc3solutions|USBDriveTester' /Users/Shared/USBDriveTester-clean-mac/btm-after-app-removed.txt
```

*Pass:*
- `ls` reports *No such file or directory*.
- `ps` prints nothing.
- The Full Disk Access list no longer names USBDriveTester.

**These are readings, not failures:**
- what the two panes showed in step 2;
- whether Full Disk Access still listed the app after the drag, before **−**;
- whether *Allow in the Background* still names it;
- what BTM holds.

**Record:**

---

## Item 7 — the evidence comes back *(also where a stopped walk goes)*

1. In **window B**, press Ctrl-C.
2. In **window A**, run each of these:

```bash
/bin/launchctl print system/com.arc3solutions.USBDriveTester.Helper > /Users/Shared/USBDriveTester-clean-mac/launchctl-end.txt 2>&1
```

```bash
/usr/bin/log show --last 12h --info --style compact --predicate 'subsystem == "com.arc3solutions.USBDriveTester" OR eventMessage CONTAINS[c] "USBDriveTester"' > /Users/Shared/USBDriveTester-clean-mac/log-show.txt
```

```bash
/usr/bin/wc -l /Users/Shared/USBDriveTester-clean-mac/log-stream.txt /Users/Shared/USBDriveTester-clean-mac/log-show.txt
```

```bash
exit
```

The `exit` ends `script`'s recording.

3. In Finder, move the screenshots from the Desktop into `/Users/Shared/USBDriveTester-clean-mac`.
4. **AirDrop the folder to this Mac.**
5. Eject `Test_Drive`, and bring the 1 TB scratch T5 back.

On this Mac, the folder is copied into `USBDriveTester-evidence/step-16/`, and the walk is judged
from it.

*Pass:* both log files have lines, and `terminal.txt` holds every item's commands.

**Record:**

---

## What has no automated cover, and will not get any

Every item in this file. Each of the following happens in macOS, on a Mac this project's tests
never run on:

* **Gatekeeper's verdict, and its dialogs' wording** (items 1.1 and 1.2). They are macOS's, and they
  change with macOS releases. NFR-INST-2's *"no Gatekeeper warning"* is not met by the decision of
  2026-10-09. These dialogs are what a user sees instead, and the release notes quote them.
* **launchd starting a quarantined helper that is not notarized, and the kernel accepting one that
  has no provisioning profile** (item 2.4). On this Mac both have run since Step 3, under approvals
  that were never quarantined.
* **The helper's Team-ID check against a signature it has never seen admitted on another Mac**
  (item 3). `codesign -v -R` on this Mac proves the requirement and the signature match. Only the
  helper's own admission line proves that the running helper agrees.
* **Full Disk Access from nothing** (item 4.3). Step 11 walked the modal by revoking a grant that
  already existed. A Mac that has never seen the app may list it differently, or not at all.
* **macOS 26 itself.** Every build since 2026-09-16 has run on macOS 27 only.

**Not covered by this walk, by its scope:**
- what happens after the certificate expires on 2027-05-06, which cannot be measured before then;
- an Intel Mac — the artefact is `arm64` only;
- a browser download — only AirDrop is walked;
- a standard (non-admin) user;
- a re-register after the uninstall. Step 4's gate asks that *"a subsequent `register()` cleanly
  reinstalls"*; gate item 4 asks only that the helper *"uninstalls … cleanly"*. Detailed step 5's
  *"lifecycle end-to-end (Steps 3 & 4)"* could be read either way, and this file takes the gate's
  words. *(2026-10-12, the user's decision at review: not added.)*

---

## Walk record

*(Paste extracts and dates here as items are walked, with the walk's start and end times. Each
item's own **Record:** line above is the record of record; this section holds the evidence behind
it. Name the clean Mac by its model and macOS version, and every pass by the artefact's zip hash,
`ed695b8f…`.)*
