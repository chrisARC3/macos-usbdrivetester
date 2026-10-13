# Step 16 — the human checklist

> **STATUS, 2026-10-12: WALKED 2026-10-12 AND STOPPED AT ITEM 2.1, ON A FINDING — the helper gate
> read `notFound` and offered only Quit; items 2.2–6.5 not walked; the clean Mac ran macOS 27.0.1,
> and the user decided the same day that all further testing is on macOS 27. The user decided to
> fix the finding, and a fixed build is another artefact, so this file is re-cut before any walk
> past 2.1 — at chunk 5e, after the code (5c, done 2026-10-12) and the artefact (5d).**
> Written at Step 16's chunk 5a, against the release
> artefact `build/release/a7eee6c/USBDriveTester-1.0-1-a7eee6c.zip`, sha256 `ed695b8f…`, built
> from `a7eee6c`: protocol v16, helper source hash `36c3a9e1…`. Items 0.1–2.1 and 7 were walked
> 2026-10-12 on a Mac mini running macOS 27.0.1 (26A434). Each item's **Record:** line holds its
> result, and the *Walk record* at the end holds the evidence; the finding is `PROGRESS.md`'s
> *Finding, 2026-10-12*. *(Until the walk's record this said "APPROVED FOR THE WALK, NOT YET
> WALKED" and "Nothing below has been walked".)* *(Until the user's decisions, later on
> 2026-10-12, the status ended "and the clean Mac ran macOS 27.0.1, not 26".)* *(Until chunk 5c's
> approval, later still, it said "which the user made the only tested version the same day", and
> named no chunk for the re-cut.)* *(Until chunk 5c's commit, the same day, it said "5c, approved
> 2026-10-12".)*
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
> - a clean Mac that is not on macOS 27. *(2026-10-12, the user's decision after the walk: all
>   further testing is on macOS 27, and macOS 26 compatibility is never assumed. Until then this
>   clause said "not on macOS 26", and the walk met it — the clean Mac ran macOS 27.0.1, so item
>   0.2's macOS row failed against what it asked then. Risk 4, macOS 26, is accepted, not
>   measured.)*

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
4. **macOS 26.** Whether this code runs on macOS 26. No run of anything built since 2026-09-16 is
   recorded on macOS 26. *(2026-10-12, the user's decision: not to be measured. All further testing
   is on macOS 27, and macOS 26 compatibility is never assumed. So this risk is accepted, not
   answered, and nothing this walk records says the app runs on macOS 26. Until the user's rule
   later that day — no document claims testing on one version alone — the second sentence said
   "Everything built since 2026-09-16 has run only on macOS 27".)*

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
  - **macOS 27.** Item 0.2 records the exact version. *(2026-10-12, the user's decision after the
    walk: all further testing is on macOS 27. It said "macOS 26", which the walk's Mac, on
    27.0.1, did not meet.)*
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

**Record:** ✅ **Passed 2026-10-12**, run headlessly on this Mac at chunk 5b's approval
(`03e905d`): `ed695b8fa493032ca24f25fe7ac681be91cd43b28052f9b7ed1b860bdf97d8e4`. 0.3's hash, taken
on the clean Mac, is the same. The first copy went over SMB, not by AirDrop — 0.3's record.

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
/usr/bin/grep -c -i -E 'arc3solutions|USBDriveTester' /Users/Shared/USBDriveTester-clean-mac/btm-before.txt
```

That prints how many lines name the app. Then the control, how many `Records for UID` lines there are:

```bash
/usr/bin/grep -c 'Records for UID' /Users/Shared/USBDriveTester-clean-mac/btm-before.txt
```

*(Split 2026-10-12. It was one command line that printed two unlabelled numbers.)*

Last, open System Settings › Privacy & Security › Full Disk Access and look for USBDriveTester.

*Pass:*

| Check | Pass |
|---|---|
| macOS | `ProductVersion` 27.x *(26.x until the user's decision of 2026-10-12)* |
| architecture | `arm64` |
| `ls` | *No such file or directory* |
| `defaults` | *Error: Domain 'com.arc3solutions.USBDriveTester' not found.* The app keeps its settings there, so the app has never run as this user. *(Corrected 2026-10-12 from the walk's reading, and read the same on this Mac. It said* Domain com.arc3solutions.USBDriveTester does not exist*, which nobody had measured.)* |
| `launchctl` | *Could not find service* |
| BTM | **0** lines name it, against a control of **≥ 1** `Records for UID` line. A 0 with a 0 control means the dump failed, not that the Mac is clean |
| Full Disk Access | does not list USBDriveTester |

*What would invalidate it:* anything that runs this app on the clean Mac before item 1.

**Record:** ❌ **Two rows failed, 2026-10-12; the other five passed.** Window A, from 11:06:58
(`terminal.txt`).
- **macOS — failed:** `ProductVersion 27.0.1`, `BuildVersion 26A434`. Not macOS 26, which is this
  file's own invalidation clause. The walk went on, because nothing had been run; what it costs is
  that risk 4, macOS 26, is not measured by this walk. *(2026-10-12, later: the prerequisite now
  names macOS 27, by the user's decision after the walk, and 27.0.1 meets it.)*
- architecture: `arm64` — passed.
- **`ls` — failed:** at 11:07:09 it read *No such file or directory*. `script` was then started a
  second time, at 11:08:43, and at 11:08:53 `ls` found `/Applications/USBDriveTester.app`. That was
  a copy sent over SMB before the walk and never run; the user deleted it and started again by
  AirDrop. The user's account, and the log that agrees with it, are in the *Walk record* below. No
  copy of the app was launched before 12:18:36.
- `defaults`: *Error: Domain 'com.arc3solutions.USBDriveTester' not found.* — passed. The row
  above expected other words; corrected 2026-10-12.
- `launchctl`: *Bad request.* / *Could not find service "com.arc3solutions.USBDriveTester.Helper" in
  domain for system* — passed.
- BTM: **0** lines name it, against **4** `Records for UID` — passed (`btm-before.txt`, 561 lines,
  11:19).
- Full Disk Access: does not list USBDriveTester — passed, the user's reading.

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

**Record:** ✅ **Passed 2026-10-12, on the second copy.** The first came over SMB: the hash was
0.1's, but `xattr` printed *No such xattr: com.apple.quarantine*. The walk stopped here, as the
item says. I then directed a copy by AirDrop, which is what 0.1 asks for. That was a second copy,
which the stop rule does not allow. I judged it acceptable because nothing had run, and a copy
with no quarantine tests nothing gate item 4 asks. The AirDropped zip: hash `ed695b8f…`, 0.1's;
quarantine `0081;6acd26e7;sharingd;EE3B8540-93B9-475B-8214-8B2AEF065B5A` — `sharingd` is AirDrop.
*A reading for the release notes:* a copy over SMB arrives with no quarantine. That copy was not
opened, so what Gatekeeper does with it is not measured.

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

**Record:** ✅ **Passed 2026-10-12, every row.** Archive Utility unpacked the AirDropped zip at
11:30:10, the log shows; then the app was dragged to Applications.
- quarantine: app `0181;6acd26e7;sharingd;EE3B8540-…`, helper `0081;6acd26e7;sharingd;EE3B8540-…`.
  The zip's event ID is on both, so the copy walked is the AirDropped one. The helper carries a
  quarantine, so 2.4 would have exercised the launchd risk.
- `--verify`: *valid on disk*, *satisfies its Designated Requirement*, the helper *--validated*.
- `Identifier`, `CDHash` (`41355694…`, `d9eeeecc…`), `Authority` (*Apple Development: …
  (424WY3TDB4)*, then the WWDR CA and Apple Root CA), `Timestamp` (*Oct 9, 2026 at 1:00:02 PM* and
  *1:00:01 PM*) and `TeamIdentifier` `5JC55GTLZA`: all as the table. `Runtime Version` 27.0.0.
- sha256: `07c392f6…`, `b5b807aa…` — as the table.
- `spctl`: *rejected*, *origin=Apple Development: … (424WY3TDB4)*. Not met, as decided 2026-10-09.

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

**Record:** ✅ **Passed 2026-10-12.** First launch at 12:18:36.494, pid 27772. `syspolicyd` logged
*Prompt shown* for team `5JC55GTLZA`. Screenshot `RefusalDialog.png`.
- Title: *“USBDriveTester” Not Opened*
- Body: *Apple could not verify “USBDriveTester” is free of malware that may harm your Mac or
  compromise your privacy.*
- Buttons: **Move to Trash**, the default, and **Done**. A **?** help button sits top right.
- Closed with **Done**; Gatekeeper's denial breadcrumb is at 12:19:08.

**1.2 — *Open Anyway*.**
1. Open System Settings › Privacy & Security and scroll to *Security*.
2. Screenshot the line that names USBDriveTester, with its **Open Anyway** button.
3. Press **Open Anyway**.
4. Authenticate when asked; the password is yours to type.
5. Screenshot **each** dialog that follows, and confirm the open.

*Pass:* the app opens.
- Record every dialog's wording, in order.
- Record what authentication was asked for, and where.

**Record:** ✅ **Passed 2026-10-12: the app opened, pid 28016, launched 12:23:16.491.**
1. *Privacy & Security › Security*, screenshot 12:22:51: *“USBDriveTester” was blocked to protect
   your Mac.*, with **Open Anyway**. Beneath it: *Apple could not verify “USBDriveTester” is free of
   malware that may harm your Mac or compromise your privacy.* *Allow applications from* reads
   *App Store & Known Developers*.
2. After **Open Anyway**, screenshot 12:23:22:
   - Title: *Open “USBDriveTester”?*
   - Body: *Apple is not able to verify that it is free from malware that could harm your Mac or
     compromise your privacy. Don’t open this unless you are certain it is from a trustworthy
     source.*
   - Buttons: **Move to Trash**, the default, then **Open Anyway** and **Done**.
   The user pressed **Open Anyway**. The app's first log line came at 12:23:38.
- **The authentication, by the user's account later on 2026-10-12:** *"When I pressed Open Anyway
  it asked for my password. I entered it successfully and the app launched."* Which of the two
  **Open Anyway** buttons asked, and the prompt's wording, were not recorded; the filtered log
  names no prompt, and its predicate would not catch one. *(Until the user's account this said
  "⚠️ What authentication was asked for, and where, was not recorded.")*
- In both dialogs the default is **Move to Trash**, so the release notes must name the button to
  press.

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

**Record:** ✅ **Passed 2026-10-12, on the log and ⇧⌘D rather than window A.** The two commands
ran in a window `script` was not recording, and their output was not kept. What shows it instead:
- `launchd`: *Successfully spawned USBDriveTester[28016]*, and `runningboardd`:
  *exPath:/Applications/USBDriveTester.app/Contents/MacOS/USBDriveTester*, both at 12:23:16.
  Neither log file has a line containing `AppTranslocation`.
- ⇧⌘D, screenshot 12:41:03: *Running from* `/Applications/USBDriveTester.app`.
- The app's pid is **28016**.
- **The quarantine value after *Open Anyway* was not read.** It is the one reading lost.
- An extra read I asked for once the gate showed, `ls -l` of the bundle's `LaunchDaemons`: the
  user saw *total 8*, and the file line was not recorded. That the plist is there rests on 0.4's
  `--verify --strict`, which seals it.

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

**Record:** ❌ **FAILED 2026-10-12, and the walk stopped here.**
- **The gate:** ***"The privileged helper is missing from this app."*** — `notFound` — with
  **Quit** only (screenshot 12:23:57). Its body: *"macOS cannot find the privileged helper's
  launchd property list inside this application, so the helper can be neither installed nor
  started. Nothing in the app can repair this. Quit, reinstall USBDriveTester from a complete copy,
  and open it again. The Privileged Helper & Diagnostics window (⇧⌘D) names the exact file it is
  looking for."*
- **The log, 12:23:38:** *registration manager initialised; daemon
  com.arc3solutions.USBDriveTester.Helper.plist status notFound* (`log-stream.txt` .525,
  `log-show.txt` .578). Then *helper gate: notFound …* at .816, and twice more at 12:40:40.
- **The stop was followed.** The app was not quit, and nothing was pressed. ⇧⌘D was screenshotted
  at 12:41:03: *Status* `notFound`; *"The system cannot find the daemon's plist in this app
  bundle. …"*; *Running from* `/Applications/USBDriveTester.app`; *No action taken yet.* Then item 7.
- **Classed functional:** `PROGRESS.md`, *Finding, 2026-10-12*.
- The pass this item named, `status notRegistered`, had never been measured on a Mac that had not
  registered the helper. The app's own note of 2026-07-27 (`HelperRegistration.swift`) says
  `notFound`.
- *(A reading.)* Behind the gate, the main window had selected disk6 by default: one of the clean
  Mac's own two 14 TB Seagate Expansion drives, the one holding its Time Machine volume. That is
  FR-DEV-3's first usable drive. Nothing ran.

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

**Record:** ✅ **Done 2026-10-12, with gaps.**
- **Log files:** both have lines. `log-stream.txt` has 3,912, from 12:18:33 to 12:47:01;
  `log-show.txt` has 12,419, from 10:56:55 to 12:49:59. I counted them on this Mac, because `wc`
  ran in a window `script` was not recording.
- **`launchctl-end.txt`:** *Bad request.* / *Could not find service …*.
- **BTM before `exit`, as I asked:** `btm-stopped.txt` has 0 lines that name the app, against 4
  `Records for UID`.
- ❌ **`terminal.txt` does not hold every item's commands.** It ends at window A's `log stream`,
  stopped about 12:47. 1.3, the extra `ls` and item 7 ran in another window.
- **The drive:** the 1 TB scratch T5 was never attached to the clean Mac.
- **The folder:** it came back as `USBDriveTester-evidence/step-16/USBDriveTester-clean-mac/`; the
  user put it there directly.

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
* **macOS 26 itself.** No run of a build made since 2026-09-16 is recorded on macOS 26.
  *(2026-10-12, the user's decision: and it is not to be tested. All further testing is on macOS
  27, and macOS 26 compatibility is never assumed; the build's minimum stays 26.0, and no document
  claims testing on one version alone — README.md's Requirements say so, and
  `Quick_Start_Guide.md` is to. Until the user's rule later that day the first sentence said
  "Every build since 2026-09-16 has run on macOS 27 only".)*

* **Which witness the running app passes to the gate** *(added 2026-10-12, Step 16's chunk 5c)*.
  `AppModel.refreshHelperAvailability()` reads whether the daemon's plist is in the bundle and
  hands it to `HelperAvailability.diagnose`. No test drives that method, so a constant there
  passes the whole suite — mutants **M4** (`false`, the gate as it was before chunk 5c) and **M5**
  (`true`) both passed all 1348 — and so does the init log line's *plist in bundle* always reading
  *yes* (**M12**). **What a person checks instead**, at the re-cut item 2.1 (chunk 5f): on a Mac
  that has never registered the helper, the gate reads *not registered* and offers **Register
  helper**, and the registration manager's init line ends *"status notFound; plist in bundle
  yes"*. That covers M4 and M12. M5's half — a bundle without its plist, which is still Quit-only —
  is walked by nobody: no build ships one on purpose, and the suite covers `diagnose` itself.

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


### 2026-10-12 — walked on a Mac mini on macOS 27.0.1, and stopped at item 2.1

*The user walked it. Claude judged it the same day, on this Mac, from the evidence.*

**The clean Mac:**
- A Mac mini (from its host name; the model was not read), `arm64`.
- macOS **27.0.1**, build **26A434** — not macOS 26, which the prerequisites and the invalidation
  clause above ask for.
- Two drives of its own were attached, both 14 TB Seagate Expansion:
  - disk6, which holds its Time Machine volume and a volume named `10 TB`;
  - disk8.
- The 1 TB scratch T5 was never attached.

**The artefact:** `USBDriveTester-1.0-1-a7eee6c.zip`, `ed695b8f…`, from `a7eee6c`: protocol v16,
helper source hash `36c3a9e1…`.

**Times.** Pacific, from the clean Mac's log, `terminal.txt` and the screenshots' names.

| Time | What |
|---|---|
| 10:56:55 | before the walk: `smbd` writes `/Volumes/10 TB/USBDriveTester.app`; copies in Downloads and on the Desktop follow at 10:57 |
| 11:06:58 | `script` started in window A; 0.2's first commands at 11:07:09 |
| 11:07:55 | Archive Utility unpacks the SMB zip on the Desktop |
| 11:08:43 | `script` started a second time, appending; 0.2 again at 11:08:53, and `ls` now finds the app |
| 11:19 | `btm-before.txt` written |
| — | 0.3: the SMB zip has no quarantine; stopped; the zip sent again by AirDrop |
| 11:30:10 | Archive Utility unpacks the AirDropped zip (0.4) |
| 12:18:33 | `log stream`'s first line — it ran in window A, not B |
| 12:18:36.494 | first launch, pid 27772; `syspolicyd` *Prompt shown* (1.1) |
| 12:19:08 | the refusal closed with **Done**; Gatekeeper's denial breadcrumb |
| 12:22:51 | Privacy & Security screenshot (1.2) |
| 12:23:16.491 | second launch, pid 28016, after *Open Anyway*; its dialog screenshotted at 12:23:22 |
| 12:23:38 | the app's first lines: `status notFound`, then `helper gate: notFound` (2.1) |
| 12:23:57 | the gate's screenshot |
| 12:40:40 | the gate re-checked twice: `notFound` |
| 12:41:03 | ⇧⌘D screenshot |
| 12:47 | `log stream` stopped; its last line is 12:47:01 |
| 12:48–12:50 | `btm-stopped.txt`, `launchctl-end.txt` and `log show` |

**The copies before the walk.** The user's account, 2026-10-12: *"I originally zipped up the copy
of the application that is in this Mac's application folder, copied it over SMB, unzipped it and
copied it to the test Mac's application folder. But I did not run the app. Then I saw that you
wanted it done through AirDrop, so I deleted everything and started over according to your
directions."*

The log agrees:
- the first line naming the app is the SMB write at 10:56:55;
- no copy was launched before 12:18:36;
- the copy walked carries the AirDrop's quarantine event, `EE3B8540-…`.

The deletions are not in the filtered log. That no copy remains, for instance on `/Volumes/10 TB`,
is to be checked before any re-walk on this Mac.

**Results.** Each item's **Record:** line holds the detail.

| Item | Result |
|---|---|
| 0.1 | ✅ |
| 0.2 | ❌ macOS 27.0.1; `ls` found the SMB copy at 11:08:53. The other five rows ✅ |
| 0.3 | ✅ on the AirDropped copy; the SMB copy had no quarantine |
| 0.4 | ✅ every row; the helper quarantined too |
| 1.1 | ✅ the refusal recorded |
| 1.2 | ✅ *Open Anyway* opened it, both screens recorded; it asked for the user's password, by their account after the walk *(until then: "the authentication was not recorded")* |
| 1.3 | ✅ from `/Applications`, on the log and ⇧⌘D; the quarantine after *Open Anyway* was not read |
| 2.1 | ❌ `notFound`, Quit only — **the stop** |
| 2.2–6.5 | not walked |
| 7 | ✅ with gaps: `terminal.txt` is incomplete |

**Not measured, because the walk did not reach them:**
- launchd starting a quarantined helper (2.4);
- the helper running with no provisioning profile (2.4);
- its admission of the shipped app (item 3);
- Full Disk Access from nothing (4.3).

macOS 26 was not on the Mac. The only one of the four risks at the top of this file that the walk
measured is the first, Gatekeeper.

**Where the walk departed from this file:**
- `script` was started twice, so `terminal.txt` holds 0.2's first commands twice.
- `log stream` ran in window A. Everything from 1.3 on ran in a window that was not recorded.
- I directed the AirDrop copy at 0.3, after the stop.
- I asked for two reads this file does not name: the `ls -l` at 1.3, and `btm-stopped.txt` at item 7.
- The evidence was copied straight into `USBDriveTester-evidence/step-16/` rather than AirDropped to
  Downloads first.

**Corrected in this file, 2026-10-12.** Both defects are cosmetic, and both were found by walking:
- 0.2's `defaults` row expected *Domain … does not exist*, wording nobody had measured. macOS 27.0.1
  prints *Error: Domain '…' not found.*, as this Mac does.
- 0.2's two BTM counts were one command line that printed two unlabelled numbers.

**Left on the clean Mac:**
- the app in `/Applications`, approved by Gatekeeper;
- nothing registered: `launchctl` *Could not find service*, and BTM 0 lines against 4 at the end.

The helper has never been registered there, so a re-walk on that Mac would still meet registration
clean, but not Gatekeeper: that has approved this artefact. The user was asked to quit the app with
the gate's **Quit** after item 7, and nothing records it.

**Evidence**, in `USBDriveTester-evidence/step-16/USBDriveTester-clean-mac/`:

| File | What |
|---|---|
| `RefusalDialog.png` | 1.1 |
| `Screenshot 2026-10-12 at 12.22.51 PM.png` | 1.2, the Security pane |
| `Screenshot 2026-10-12 at 12.23.22 PM.png` | 1.2, the dialog after *Open Anyway* |
| `Screenshot 2026-10-12 at 12.23.57 PM.png` | 2.1, the gate |
| `Screenshot 2026-10-12 at 12.41.03 PM.png` | 2.1, ⇧⌘D |
| `terminal.txt` | 72 lines, from 11:06:58 to the `log stream`'s Ctrl-C |
| `log-stream.txt` | 3,912 lines |
| `log-show.txt` | 12,419 lines |
| `btm-before.txt`, `btm-stopped.txt` | 561 lines each; 0 name the app, against 4 `Records for UID` |
| `launchctl-end.txt` | *Could not find service* |

**What it is true of:** the artefact `ed695b8f…`, on macOS 27.0.1 (26A434).

**Invalidated by:**
- another artefact;
- for 1.1 and 1.2, another macOS release.
