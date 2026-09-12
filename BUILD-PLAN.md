# Build Plan: USB Drive Retention & Hard-Fault Tester

**Status:** Draft for execution
**Date:** 2026-06-25
**Last amended:** 2026-08-14 — "Working on this project" corrected on **target membership** (the
note said `Helper/Core/` needs an Xcode tick to join the *helper*; it does not — what needs one is
the *test target's* `membershipExceptions` list), plus mutation-harness and zsh traps paid for in
Step 11 increment 3.
Previously 2026-08-06 — Step 10's scoping decisions recorded at the head of that step
(protocol v9 carries the final figures; "stopped by user" deferred to Step 11 and device loss to
Step 12; the report gets its own `Window`), with the matching inherited notes on Steps 11 and 12.
Previously 2026-08-01 — Steps 6 and 7 (measured exclusivity semantics, Full Disk Access), and the
test target fixed to the designated scratch device with disk images removed as an option (see
"Test hardware")

> **Step 11 is COMPLETE (2026-09-05) — twelve increments gated, the 16-chunk checklist walked, its
> own gate re-run against v14. STEP 12 (DEVICE-LOSS HANDLING) IS COMPLETE (2026-09-11) — all nine
> chunks done and all four gate items ticked on real hardware, eight cable pulls on two drives;
> archived to [`progress/step-12.md`](progress/step-12.md). STEP 13 (SYSTEM-SLEEP PREVENTION) IS
> IN PROGRESS — planned in five chunks; 1 (the instrument) and 2 (the rule and the seam) done
> 2026-09-12.** Step 12's
> chunks 0–6 built it and chunk 7 proved it
> (7a–7d done 2026-09-07, **7f done 2026-09-08**; **7e — the
> five-chunk checklist walk — CLOSED 2026-09-11**: chunks 1 and 2 passed 2026-09-08, chunk 3
> aborted the same day on a shipped defect and was **re-walked in full and CLOSED 2026-09-09** — the
> whole-disk event fires under claim — **chunk 4, the paused unplug, passed and CLOSED 2026-09-11**
> on the 1 TB scratch T5 and the 125.8 MB thumb, and **chunk 5 was discharged the same day by user
> decision**, its two measurements being in the persisted log already, six trials each, from chunk
> 3's pulls); **7g, the same day, closed both of the walk's logging gaps in code** and retired the
> two stale app-target comments with them — the third, in helper source, waits for the next helper
> change by user decision. **A person ran that build on the 1 TB scratch T5 the same evening** and
> both kinds of line came out as specified, all four command labels, `Resume` included.
> **7h then closed the mutation survivor 7g predicted**: measured surviving all 1301 tests, killed
> by one new test. **The step's four gate items are ticked** against `7e51398`, app installed from
> `abc07e3` — the evidence and what invalidates each is beside them. ⚠️ **7f
> fixed a false-positive device loss**: route (b) took a *slice* disappearance for the drive
> leaving, and the run's own exclusive whole-disk open is what makes the slices go — every
> partitioned drive ended its run ten milliseconds after the claim. The suite is **1313 / 156 / 0**,
> floor 1313. **The protocol is v15** (chunk 3,
> 2026-09-05) **and the helper source hash is `e19b0b3c…`, moved by chunk 7b** — chunks 4, 5 and 6
> did not move it, all three being app target only, and 7b did because `InMemoryBlockDevice` is a
> member of the helper target as well as the test target.
> ✅ **All four hardware gates were re-run at chunk 7d on 2026-09-07 against `e19b0b3c…` and v15,
> and all four passed with zero failures** — they had lapsed at chunk 1 and again at 7b. The ticks
> further down this file that name `e6888aa5…`, `42774589…` or v14 are historical from that moment.
>
> ⚠️ **This block said "Step 12 … is UNSTARTED. The protocol is v14" until 2026-09-05, through
> chunks 1 and 2**, because the *other* status block 400 lines below it was the one being edited
> and nothing compares the two. That is the second time this file has done this and the paragraph
> at the end of this block already warns about it. **There are two status blocks in BUILD-PLAN.md.
> `grep -n "protocol is v" BUILD-PLAN.md` finds both.**
>
> ⚠️ **The repository moved on 2026-09-04** to
> `/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester` — still a **removable volume**,
> so builds still go outside it, and any absolute path written down before that date is wrong.
> **Increment 12 — ⌘Q under every modal — was built on 2026-09-04** in four chunks, app target only;
> its account is in `PROGRESS.md` and its plan section has been deleted from
> [`progress/step-11-increment-plans.md`](progress/step-11-increment-plans.md), which now holds only
> the settled-decision table. **No increment is planned right now.**
>
> **The human checklist is complete — 16 chunks, nothing owed.** Chunk 16 (⌘Q under every modal)
> was written and walked on 2026-09-04, all nine items, and 6.1, 11.7 and 6.3 were re-walked at
> expectations increment 12 changed. **Step 10's three hardware gates are not owed** — `metrics-check.sh`,
> `xpc-concurrency-check.sh` and `retention-cycle-check.sh` all passed 2026-09-03, and increment 12
> **did not move the helper hash**, so those results still stand. **`run-control-check.sh` was the
> last thing owed, and it is no longer owed** — re-run **2026-09-05 against the v14 daemon** and
> passed: 14 assertions, 0 failures, all four I/O sizes settled at a chunk boundary with the correct
> resume point. That discharges items 2, 3 and the helper-side half of 5 in Step 11's verification
> gate, so **all five stand against v14, and Step 11 closed on 2026-09-05.**
>
> ⚠️ **This block said "increment 10 next … protocol is v12 … the human checklist is complete"
> until 2026-09-03, and increment 10 had landed on 2026-09-02.** It survived a docs cold-start pass
> that was reading it. A status block is the first thing a cold session believes and the last thing
> anyone thinks to check; edit it in the same commit as the thing it describes.
>
> Anything below that names an earlier protocol version is a dated record of what was true when it
> was written — the inherited notes on Steps 11 and 12 especially. `PROGRESS.md` is the tracker;
> `CONSTRAINTS.md` is what binds.
**Source documents:**
- [Product Brief](USBDriveTester.md)
- [ADR-001](ADR-001-usb-drive-tester.md) — the 16 Action Items this plan sequences
- [Functional Requirements](functional-requirements-usb-drive-tester.md) (Baselined 2026-06-25)
- [Non-Functional Requirements](nonfunctional-requirements-usb-drive-tester.md) (Baselined 2026-06-25)

### Where everything lives (documentation split 2026-08-11)

`PROGRESS.md` had reached 7,156 lines — a log a cold start was explicitly told not to read, which
meant the facts that still bind the work were buried in narratives nobody could safely open. Split
into four:

| file | what it is | read it |
|---|---|---|
| **[CONSTRAINTS.md](CONSTRAINTS.md)** | what binds future work — measured behaviour, settled decisions, the lessons | **in full, every session** |
| **BUILD-PLAN.md** (this file) | the plan, the per-step gates, the process gotchas, the test hardware | the current step, plus "Working on this project" |
| **[PROGRESS.md](PROGRESS.md)** | the step in progress, and only that | at the start of a step |
| `progress/step-NN.md` | archived per-step history | only for *"why was it done that way?"* |

**The full account of an increment now goes in its commit message**, with `PROGRESS.md` carrying a
summary and the hash. Writing it twice at length produced two long prose accounts of one increment
that could drift; the commit is the immutable, greppable one.

---

## How to use this plan

This plan turns the ADR's 16 Action Items (AI-1 … AI-16) into an ordered sequence of **build steps**. The work is intended to be done **slowly and deliberately, one step at a time**, with each step fully verified before the next begins.

- **Steps are renumbered (Step 1 … Step 16)** to reflect true build order. Each step is annotated with its original **`AI-n`** so traceability back to the ADR is preserved.
- Every step lists the **requirements it satisfies** (FR-/NFR- IDs) so you can confirm coverage.
- Every step ends with a **Verification Gate** — an explicit, testable definition of "done." **Do not start the next step until the current gate passes.** This is the core discipline of the plan.
- Where a step builds code that touches the privileged trust boundary, the step calls out which side of the boundary (GUI vs. helper) the code lives on.

### Nothing is distributed until the whole plan is complete (user decision 2026-08-14)

No early access, no preview build, no external tester. **Step 16 is where distribution happens**,
and every build before it runs on this machine, for the person building it.

This is recorded because it changes how a risk in these pages should be read, and because it is easy
to over-apply. It means **there is no partly-finished version anyone else can be handed**, so a
hazard framed as "a stranger is told something false about their own hardware" is really "the author
is", until Step 16.

It does **not** relax anything in the plan, and two things in particular:

- **The runtime guards are not release guards.** The mount guard, the exclusive claim, FR-TEST-10's
  placement refusal, `mayIssueNewWork` and the pre-run dialog protect the drives attached to *this*
  machine on *every gate run between now and Step 16* — including the 22 TB Seagate that FR-DEV-3
  default-selects. Their exposure is today's.
- **Every step still ends at its Verification Gate.** A gate exists so a step's defects are found in
  that step rather than four steps later; who eventually receives the result is not part of that
  argument.

Full entry, including what was searched for and not found, in
[CONSTRAINTS.md](CONSTRAINTS.md) section 2.

### Why the order differs from the ADR's 1–16 list

The ADR lists action items by topic, not by dependency. Three deliberate re-orderings:

1. **AI-16 (test abstraction) moves to Step 2 — the foundation.** The ADR explicitly wants the core algorithm "unit-testable against a simulated/in-memory device independent of privileged hardware" (NFR-MAINT-2). Building that abstraction *first* lets us develop and verify the entire read→write→verify→metrics→failure engine (Steps 7–10) with fast, deterministic unit tests, before any privileged hardware is involved. This is the single biggest risk-reducer in the plan.
2. **AI-14 (helper teardown) pairs with AI-2 (helper registration)** as Step 4, immediately after registration. Registration and unregistration are two ends of the same lifecycle; building them together means you can install/remove cleanly throughout the rest of development.
3. **AI-15 (logging) is cross-cutting.** It gets a dedicated consolidation step (Step 15) near the end, but each earlier step instructs you to add its `os_log` points as you go, so logging grows with the code rather than being bolted on.

### Working on this project: the things that have cost time (consolidated 2026-08-06)

Each of these was learned the expensive way and, until 2026-08-06, lived only in a step-log entry
that a cold start is explicitly told not to read end to end. They are collected here because they
are **process**, not history.

**Verifying a step**

- **"Zero warnings" is only true from a CLEAN build, and it is THREE commands, not two.**
  Incremental builds do not re-emit warnings, and `build.sh` does **not** compile the test target —
  so `build.sh Debug`, `build.sh Release` **and** `test.sh`, each with DerivedData wiped first.
  Two of the three were the whole check for seven steps.
- **Prove the clean build was actually clean, by counting compile tasks.** Wiping DerivedData and
  seeing `BUILD SUCCEEDED` is not evidence that anything recompiled, and a wipe that silently
  failed would make the whole zero-warnings check worthless. Count them:
  `grep -c 'SwiftCompile' <log>`. Measured 2026-08-11 on a genuine clean run — **Debug 76**
  per-file tasks, **Release 2** (that is correct: `-O -whole-module-optimization` emits one task
  per *module*, each consuming a full `.SwiftFileList`), **test 148**. A Release count of 2 looks
  alarming and is not; a Debug count of 2 would be the real thing to worry about.
  **Re-measured 2026-09-07 at Step 12 chunk 7: Debug 92, Release 2, test 182** — the project has
  grown; the shape has not.
- **But count the SOURCES, not the tasks — the task count cannot detect a cached Release.** This
  was found by taking the note above at face value and then not believing the reading: Release
  emits 2 tasks whether it compiled seventy files or two, so for that configuration the number is
  the same on a clean build and a fully cached one. The metric that works for **both** batch mode
  and WMO is *how many distinct project sources the compile tasks name*:

      grep 'SwiftCompile normal' <log> | grep -oE '[A-Za-z0-9_]+\.swift' | sort -u

  Intersect that with the `.swift` files actually on disk — the raw list also contains ~40 **SDK
  module names** (`Foundation.swift`, `SwiftUI.swift`, `Darwin.swift`…) that appear as module
  inputs on the WMO command line and are not project sources. Measured 2026-09-07:
  **70 of 70 in Debug and 70 of 70 in Release**, plus `GeneratedAssetSymbols.swift` in each.
  That is the claim "nothing was cached" actually rests on.
- **Get the test count from the xcresult, not the console.**
  `xcrun xcresulttool get test-results summary --path <xcresult>` and read the **top-level**
  `totalTestCount` — not `passedTests` inside `devicesAndConfigurations`, which counts something
  else. `xcresulttool` needs `DEVELOPER_DIR` exported like everything else.
- **A number that does not move is a finding.** Test files written to the wrong directory still
  leave a green suite — at the *old* count. The project layout has a **nested folder**
  (`USBDriveTester/USBDriveTester/…`), so an absolute path is easy to get wrong by exactly one
  level, and the failure is silent: the files land in a directory nobody compiles. The suite total
  is the check. (Cost an hour on 2026-08-05; caught only because 516 did not become 551.)
- **Parallel testing is OFF in `test.sh`**, deliberately: several assertions read process-global
  counters.
- **A green suite is not evidence a test works.** Break the thing on purpose and re-run — the
  project's oldest lesson, and it has caught something every time it has been applied.
- **A mutation script must restore a file only if it actually differs.** Writing the pristine text
  back unconditionally still counts as a file modification, and anything watching the working tree —
  an editor, a build system, an assistant's context — re-reads the whole file for a change that did
  not happen. Twelve mutations across five files did this ~60 times on 2026-08-12. One line fixes
  it: `if path.read_text() != pristine: path.write_text(pristine)`.
- **Run a mutation you expect to survive, and say so in advance.** Step 11 increment 2 deliberately
  mutated the helper's `main.swift`, which the test target does not compile. It survived, as
  predicted — and that is the result: it confirms the hole is where the code comments claim it is
  rather than somewhere nobody has looked. A predicted survivor is evidence; an unexpected one is a
  finding. Both beat only running mutations you are confident will die.
- **Assert the anchor is UNIQUE, and treat a zero test count as inconclusive.** Increment 3's
  harness checked only that its search text *existed*; the text occurred twice, it patched the
  wrong site, the build failed, zero tests ran, and it printed "SURVIVED: all 0 tests passed". Full
  account in CONSTRAINTS section 3 — the short version is that `assert text.count(old) == 1` and
  `if not total: verdict = INCONCLUSIVE` are both one line and both mandatory.
- **Restore from a saved pristine copy, never with `git checkout <file>`**, which reverts to HEAD
  and takes any uncommitted work in that file with it. Re-derive the helper source hash afterwards
  and check it against the known-good value; that is what caught it.

- **Reinstall before walking a human-checklist chunk, and kickstart the daemon after.** On
  2026-09-02 chunk 14 was about to be walked against a build from the previous day that **predated
  the increment the chunk exists to test** — `/Applications` is only as current as the last
  `install-app.sh`, and running the suite does not update it. `strings` cannot settle it: the
  increment's literals were absent and so were the controls, so the test is inert. **Compare the
  installed binary's mtime against the increment's commit.** Then
  `sudo /bin/launchctl kickstart -k system/com.arc3solutions.USBDriveTester.Helper`, because
  `install-app.sh` replaces the helper binary underneath a running daemon and **nothing announces
  the mismatch when the helper source has not moved.**
- **Internal vocabulary must not reach a person at a keyboard.** The same walk stalled on an item
  relayed as "press the remedy button": `RunFailureRemedy` is a type name and no control says
  "remedy". The checklist itself was correct; the paraphrase was not. Restating a checklist item
  is as capable of breaking it as editing one.

**The build environment**

- Full Xcode 26.5 is at **`/Applications/Development/Xcode.app`** and is **not** the selected
  developer dir. `build.sh` / `test.sh` pin `DEVELOPER_DIR` themselves; anything else you run by
  hand must export it. **Do not run `sudo xcode-select`.**
- App target: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which makes even plain value types,
  protocols, C-callback functions, file-scope `Logger`s and extensions on standard-library types
  main-actor-isolated. Mark them `nonisolated`, or the test target cannot use them.
- `MemberImportVisibility` is on: a member from a transitively-imported module needs its module
  imported **directly** (`Timer.publish(…).autoconnect()` needs `import Combine`; `NSApp` needs
  `import AppKit`).
- `SWIFT_VERSION = 5.0` — keep it. `ARCHS = arm64`, deployment target 26.0, team `5JC55GTLZA`,
  App Sandbox **off** (must stay off), Hardened Runtime on.
- **Target membership — and the version of this note that stood until 2026-08-12 was WRONG about
  which target needs the tick.** Read from `project.pbxproj`, not remembered:
  - The app folder, the test folder **and the helper folder** are each a
    `PBXFileSystemSynchronizedRootGroup`, so a new file in any of them **joins its own target
    automatically**. A new file under `Helper/Core/` joins the *helper* with no Xcode work at all.
  - What needs a manual tick is the **test target's** view of `Helper/Core/`, which it picks up
    through an explicit `membershipExceptions` list — 14 files as of increment 3. **A new file in
    `Core/` is invisible to the tests until it is added to that list**, which is the user's job
    (see "How we work" in the session brief).
  - So the question to ask is never "is this file in `Core/`?" but **"does a test need to see
    it?"**. Step 11's increments 1–3 needed no Xcode work at all, because each put its new types in
    files already on that list (`Core/RetentionRun.swift`, `Core/RunMetrics.swift`) — which is
    itself the cheap way to avoid the tick. **Check `project.pbxproj` before assuming either way.**
- `SMAppService` records the **registering app's path**, so always install to `/Applications` with
  `scripts/install-app.sh` and register from there. That script **only copies files**: after
  installing you must reload the daemon yourself, or the running one is still the old one. **This
  has cost real time twice** — a helper fix that appeared not to work, twice, because the old daemon
  was still answering. Either kick it directly:

  ```
  sudo /bin/launchctl kickstart -k system/com.arc3solutions.USBDriveTester.Helper
  ```

  or unregister and re-register in the app's Step 3 panel, then confirm with **Check version**.
  `install-app.sh` prints the kickstart line itself when it finishes. It refuses to overwrite a
  running app — quit it first.
- This repo lives on an **external volume**, and macOS gates daemon access to removable volumes:
  anything the root helper must read has to live outside the repo (`/tmp`).

**Shell and scripting**

- Scripts are `#!/bin/bash` → **bash 3.2** on macOS. No associative arrays, no `mapfile`, no
  `${var,,}`; and `"${empty[@]}"` under `set -u` is an unbound-variable error — write
  `${arr[@]+"${arr[@]}"}`.
- Under `set -euo pipefail`, `producer | grep -q` returns **non-zero when grep MATCHES**, and
  `producer | head -1` can SIGPIPE the producer. Use `grep -m1`.
- Bash arithmetic is **signed** 64-bit: `od -An -N8 -tu8` yields values above 2⁶³ that go negative
  through a modulo. Use 32 bits.
- Invoke `log` as **`/usr/bin/log`** — the bare name gets mangled in this environment. *(It is zsh's
  own `log` builtin, which lists logins and takes no arguments: `log:1: too many arguments`. Hit
  again 2026-09-11.)*
- **Ad-hoc commands run under zsh, where `path` is tied to `PATH`.** Assigning a scalar to a
  variable named `path` in a loop destroys the search path for the rest of that command, and every
  subsequent tool fails with `command not found` — which reads like a broken environment rather
  than a typo. Name it anything else. (Checked-in scripts are `#!/bin/bash` and unaffected.)
- **zsh does not word-split an unquoted variable.** `D="a.md b.md"; grep pat $D` searches one
  file literally named `a.md b.md`, and with `2>/dev/null` on the end it reports **no match for
  every pattern** — which reads exactly like a clean result. Hit 2026-09-10 on the very grep that
  was checking the docs for stale status claims. Use an array — `D=(a.md b.md)`, then `"${D[@]}"` —
  and **treat zero hits for every pattern as a broken instrument**, the way a zero test total is.
  *(Hit again 2026-09-11, the day after this was written, on the same kind of grep — 32 patterns,
  zero each, a date known to be present among them. Knowing the trap did not prevent it; the
  zero-for-every-pattern rule caught it both times. Keep a pattern that must hit in every sweep.)*
- Scripts needing `sudo` must be run in a **real Terminal**; a run button has no TTY.
- **`system_profiler SPUSBDataType` prints nothing on macOS 26** and exits 0 — the data type is now
  `SPUSBHostDataType`. An empty result is not a finding; it did not mean the drives had no serials.

**Swift and test authoring**

- `String(format:)` with `%s` and a Swift `String` is undefined behaviour and **segfaults** — use
  `%@`.
- `#expect`'s comment argument is a `Comment`, expressible by a string **literal**: `"a" + "b"` is
  a `String` expression and will not convert.
- A **compound integer literal** in `#expect` stays `Int` instead of promoting to `Double` — write
  explicit `Double` literals.
- `min` inside a `Sequence` conformance resolves to `Sequence.min()` — use `Swift.min`.
- **Do not edit Swift multi-line strings (`"""`) from inside a Python triple-quoted heredoc** — the
  Swift delimiter closes the Python one. Use the edit tool.
- **SwiftUI modifiers fail silently.** `.defaultFocus` on a `List`, `.selectionDisabled` on a
  container instead of its rows, `.id()` to force a selection re-assert: all compiled, rendered,
  and did nothing, with no warning. Verify with `scripts/render-ui.sh` (its
  `appActive / windowKey / firstResponder` line settles focus questions) or with the unified log.
- **An imported `@objc` enum's `@unknown default` arm is MANDATORY, REACHABLE and TESTABLE** —
  all three measured 2026-08-27 against `SMAppService.Status`, and the third is the surprise.
  Omitting the arm both **warns** (so the zero-warnings gate fails) and **traps at runtime**:
  `Fatal error: unexpected enum case 'SMAppServiceStatus(rawValue: 99)'`. And
  `SMAppService.Status(rawValue: 99)` **constructs** — the raw-value initialiser admits values the
  enum does not name — so the arm is reachable from a unit test. It was about to be written down as
  a declared blind spot. Check before recording one: `xcrun swiftc` on a five-line file answers it.
- **A `nonisolated` type reading a `MainActor` COMPUTED property warns; reading a `static let` of a
  `Sendable` type does not.** Both appear identical at the call site. Under the app target's
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `HelperIdentity.loggingSubsystem` (a `static let`) is
  readable from a `nonisolated` type and `HelperIdentity.daemonPlistName` (a computed `static var`)
  is not. **What the fix costs depends on which file the property is in**: `nonisolated` on an
  app-target-only type is free, while the same keyword on anything in `Shared/` moves the **helper
  source hash** and puts Step 10's three hardware gates back in question. Check which before
  reaching for the keyword; the cheaper answer is often not to make the reference.
- **`allSatisfy(\.keyPath)` inside `#expect` fails to compile.** `allSatisfy` is `rethrows`, and
  inside the macro's expansion the key-path form is not proven non-throwing — *"call can throw, but
  it is not marked with `try`"*, reported against the generated macro file rather than the test.
  Hoist it to a `let` above the `#expect`, or use a closure.

### Global "Definition of Done" applied to every step

Before a step's gate is considered passed:
- The code compiles for **arm64 / macOS 26 (Tahoe)** with no new warnings (NFR-COMPAT-1/2/3).
- Any logic added in this step that *can* be unit-tested **is** unit-tested (NFR-MAINT-2).
- The privileged/unprivileged trust boundary is respected: no raw I/O outside the helper (FR-ARCH-6, NFR-SEC-1).
- New significant events are emitted via `os_log` (NFR-OBS-1) — see Step 15.
- A one-paragraph note is recorded describing what was verified and how. **Since 2026-08-11 the full account goes in the commit message**, and `PROGRESS.md` carries a summary plus the hash — two long prose accounts of one increment are two things that can drift.

### Version control convention (recorded 2026-08-02, user decision)

**Commit directly to `main`.** Every step so far has been committed that way, and it is the
intended workflow, not an accident of habit.

> *"I generally prefer commits to main. If I want to commit to a branch I will let you know in
> advance."* — user, 2026-08-02

So: **do not create a branch for a step's work unless told to in advance.** A step's commit
lands on `main` once its Verification Gate passes. Recorded here because the opposite default —
branch first, then merge — is a common convention and would otherwise be a reasonable
assumption for anyone (or any tool) joining the project cold, leaving a step's work stranded
unmerged on a side branch.

Commits are made **only when asked**, and only after the gate passes. The message convention
follows Steps 1–7: a `Step N: <title>` subject, a body explaining what changed and *why* —
including any requirement added or amended, and any defect found — and the verification
results with their numbers.

### Test hardware (amended 2026-08-01; **identity moved to serial numbers 2026-08-06**)

> **Drives are named here by USB SERIAL NUMBER. A BSD name is not an identity and must not be
> used as one** (user decision 2026-08-06, and the product has said the same since 2026-08-05).
>
> **This is not a style rule. It was learned.** A reboot on 2026-08-06 renumbered this machine's
> drives: the designated scratch device stopped being `disk4` and became `disk8` — and `disk4`
> became the **22 TB Seagate holding Backup and Time Machine**. Every gate script took a BSD name
> on the command line and trusted it, and every document said `disk4`. The documented command
> `retention-cycle-check.sh disk4` would have unmounted the backup drive and written a gibibyte
> to it. Worse, `metrics-check.sh` carried a guard that *refused any drive but `disk4`* — a safety
> check that the renumbering turned exactly inside out: it would have refused the correct drive
> and admitted the backup.
>
> **This is not "BSD names are bad" — the rule has two halves, and the test is LIFETIME.** A BSD
> name is a *locator*: it answers "which of the things in front of me right now?", and it ties this
> window to `diskutil` and `/dev/rdiskN`. **Live surfaces should show it** — the device list, the
> selected-device detail, a metrics heading — beside the serial, because two identifiers a user can
> cross-check are better than one. What must never carry it is anything that **outlives the
> enumeration that produced it**: this document, PROGRESS, gate scripts and their command lines,
> the exported run report, release notes. Those identify by **serial**. Full statement of the rule,
> with the user's wording, in the FR document's 2026-08-06 amendment entry.
>
> **What that means for anyone reading this document.** Every BSD name below is either historical
> (what a drive was called on the day something was measured) or an example of the *form* of a BSD
> name. None of them designates hardware. The scripts no longer accept one as an identity either:
> they resolve their target through `scripts/lib/device-identity.sh`, which asks the app's own
> enumerator for the drive with the expected **serial**, cross-checks its block count, and refuses
> otherwise — with a message naming both serials. Passing a stale `diskN` is refused rather than
> obeyed. **Shown refusing on 2026-08-06**, not merely shown passing.

| role | drive | **serial** | notes |
|---|---|---|---|
| **scratch** — every write gate | Samsung Portable SSD T5, 1 TB, 512 B blocks, one exFAT volume `Test_Drive` | **`12345686DAA9`** | Contents expendable. 1,953,525,168 blocks. |
| **bulk** — read-only, by prior agreement | Seagate Expansion HDD, 22 TB | **`00000000NT17XBRA`** | Live HFS volume + Time Machine. **Never a write target.** 42,970,644,479 blocks. |
| **source tree** — never tested | Samsung SSD 990 EVO Plus in a Ugreen enclosure | **`013117100578`** | Holds this repository. The serial belongs to the *enclosure*. |
| **fixture** — multi-volume unmount tests; reserve discriminator | Samsung PSSD **T5 EVO**, **4 TB**, 512 B blocks | **`00000S7CLNJ0WC02266P`** | Contents expendable. 7,814,037,168 blocks — **above 2³²**. Built by `scripts/make-unmount-fixture.sh`; see the two roles below. |

**The fixture drive, added 2026-08-09.** It carries two roles and they do not conflict:

1. **The multi-volume unmount fixture.** `VolumeMounter.restoringUnmount` can only be exercised
   end to end on a drive with **two or more mounted volumes** — on a single-volume drive the
   restore set is empty, `mount(volumeBSDNames:)` short-circuits and `mountOne` is never called,
   so a run looks like a pass while leaving the interesting half untouched. The scratch T5 has
   exactly one mounted volume and the only other multi-volume drive on this machine is the live
   Time Machine disk. `scripts/make-unmount-fixture.sh` builds GPT + EFI(unmounted) + exFAT +
   APFS + HFS+ on it. **Step 11 needs the same fixture**: its Start owns unmount → acquire → run
   and its abort path reaches the identical partial-unmount state with no manual control at all.
2. **The reserve discriminator for the unexplained de-enumeration** (Step 12's inherited note).
   If the scratch drive drops off the bus again, this drive separates "the T5 or its enclosure"
   from "this Mac's USB" from "this tool's access pattern".

> **It was recorded as a "second 1 TB Samsung" until 2026-08-09 and that was wrong** — user
> correction. It is a different model line (T5 **EVO**) at four times the capacity. The figure
> mattered: the note that quoted it also quoted the cost of promoting it to a gate target as
> "~1 TB of `/dev/urandom`", which is **~4 TB**, and 7,814,037,168 blocks is **above 2³²**, so
> the drive is also a *writable* NFR-COMPAT-6 candidate where the Seagate is read-only. A
> remembered capacity is an assigned identifier by another name; the serial and the block count
> are the intrinsic ones, and `device-identity.sh` now cross-checks the latter.

**Promoting it to a write-gate target** would still need the same three things as before —
`FIXTURE_BLOCKS` is already in `scripts/lib/device-identity.sh` and the table row is above, so
what remains is **~4 TB of `/dev/urandom`** written to it. Until that exists it is not a
retention-gate target: a random placement landing on all-zero space reports a clean pass having
proved nothing.

- **The internal disk** (Apple Fabric, not USB) is the non-USB exclusion case and is excluded by
  discovery, not by name.

**How to run a hardware gate, from 2026-08-06.** Pass no drive at all — the script finds its own:

```
./scripts/metrics-check.sh                        # resolves serial 12345686DAA9
./scripts/retention-cycle-check.sh [startBlock] [--quick]
./scripts/large-address-check.sh                  # resolves serial 00000000NT17XBRA
```

`--device <serial|diskN>` still exists, and is a **confirmation, never an override**: it must
agree with the role the script was written for, or the script refuses. A bare `diskN` is accepted
in that position for one reason — so that an old command line is checked and refused rather than
silently obeyed.

  > **Amended 2026-08-02, user decision (Step 7 scoping): the scratch device only, "unless there
  > is an important test case that cannot be satisfied with"** it. The Seagate is therefore
  > **not** part of any gate by default; using it requires a specific case to be named and agreed
  > first, per step. Reading its geometry is not free — it means unmounting a 22 TB volume, and
  > only the scratch device's contents are expendable.
  >
  > **One such case was known, and has since been agreed and closed: NFR-COMPAT-6.**
  > The scratch device is **1,953,525,168** blocks, *below* 2³² (4,294,967,296), so no test on it
  > can distinguish a correct 64-bit block count from one a USB bridge has truncated to 32
  > bits. The Seagate is 42,970,644,479 blocks — ten times over the boundary — and is the only
  > hardware here that can.
  >
  > **Agreed and run 2026-08-02, before Step 8**, via `scripts/large-address-check.sh`:
  > 10/10, see Step 7's gate. That run is the model for any future use of the Seagate —
  > **read-only** (`O_RDONLY`, no `O_EXLOCK`), **nothing unmounted**, the live volume named to the
  > user before it starts and verified still mounted afterwards. It remains outside every
  > other gate: a specific case still has to be named and agreed before it is used again.
- **Disk images are not a test target.** Discovery excludes them (they report
  `Physical Interconnect == "Virtual Interface"`), and they lack the USB bridge, real
  block device and NAND this tool exists to exercise. Earlier wording in Steps 7, 8 and
  Appendix B offering a disk image as a safer stand-in has been removed — see Step 7,
  "The test target".
- **The helper requires Full Disk Access** (NFR-INST-4) before any raw I/O works at all.

The drive's data being expendable relaxes the *consequence* of a bug, never the discipline:
simulation-first still applies wherever the plan calls for it.

> **The scratch device must hold real data, not empty space (added 2026-08-03, learned on hardware).**
> Step 8's gate places its run at a **random** LBA. `Test_Drive` was 1% used, so the first
> placement landed on unwritten space — and a cycle over an all-zero region is non-destructive
> however wrongly it addresses the device: reading zeros, writing zeros back and verifying zeros
> against zeros proves nothing, while reporting a clean pass. The volume was filled with ~1 TB
> from `/dev/urandom` and **the fill file is kept**, because deleting it may let the drive
> discard the blocks and put the next run straight back to zeros.
>
> Any gate that places work at a random offset must also **prove the region it tested was not
> uniform**, rather than assuming the drive has data on it. Step 8's gate samples three chunks
> from inside its range before writing and requires their fingerprints to differ.

> **Measured 2026-08-02, and it constrains every future gate: `O_EXLOCK` excludes a plain
> reader.** While the helper holds the device, a second process — root, carrying Terminal's Full
> Disk Access grant, requesting **no lock at all** — is refused `EBUSY` on
> `open("/dev/rdiskN", O_RDONLY)`. The 2026-07-30 exclusivity matrix did not cover this: it
> tested `O_EXLOCK` against `O_EXLOCK`, and plain `O_RDWR` against plain `O_RDWR`. So **nothing
> outside the helper can read the device during a run**, and any evidence a gate needs from the
> media while a claim is held has to come from the helper itself.

---

## Sequence overview

> **Status, 2026-09-11: Steps 1–12 and Step 14 are complete and committed. STEP 11 IS CLOSED** —
> twelve increments done and gated, the 16-chunk human checklist walked in full, and the step's own
> verification gate re-run against the **v14** daemon on 2026-09-05. **STEP 12 (device-loss
> handling) IS CLOSED, 2026-09-11** — all nine chunks done, all four gate items ticked against
> `7e51398` with the app installed from `abc07e3`, and the account archived to
> [`progress/step-12.md`](progress/step-12.md). **Step 13 (system-sleep prevention) is IN PROGRESS —
> five chunks planned; 1 (the instrument) and 2 (the rule and the seam) done 2026-09-12.** Step 12's chunks 0–6 built it and chunk 7 proved it — 7a (the clean
> build figures), 7b (the mutation round) and 7c (the human checklist) are done; **7d is DONE
> — the app is reinstalled and verified by symbol, the daemon is kickstarted, the multi-slice thumb
> is replugged with both slices intact, and all four hardware gates are re-run and passed** on
> 2026-09-07 against a v15 daemon resolved from `/Applications`; **and 7e is CLOSED, 2026-09-11** —
> the five-chunk checklist walk, whose **chunks 1 and 2 were walked and passed 2026-09-08** against
> `55a5c71`, with the daemon rekickstarted at 12:14:01 (pid 84459, v15, `/Applications`). The daemon kickstarted after 7f part 2 came back out of **DerivedData** (pid 88873, 16:01:04) — byte-identical
> binary, so not a correctness fault, but a provenance one; **fixed the same day** by Unregister +
> Register from the installed app, and the daemon now runs as **pid 89541 (16:22:50, v15,
> `/Applications`)**, its helper byte-identical to the one reinstalled 2026-09-10 from `2086090`.
> ⚠️ **BTM was re-parented then and did not stay so**: the 2026-09-09 15:34 test run re-pointed it
> at DerivedData, which the running daemon does not feel and the next kickstart would — so none is
> to be run until the record reads `/Applications` again (`CONSTRAINTS.md` §1). **Chunk 3
> aborted on 2026-09-08 having found a shipped defect** — the app ended its own run ten milliseconds
> after the claim, because route (b) accepted a slice disappearance and the exclusive whole-disk
> open is what makes the slices disappear. **Fixed at 7f**, killed by seven tests, helper hash
> unmoved — and an ignored slice now logs a line, which **can never fire** on a normal run
> (found 2026-09-09: the claim tears the slices down ~5 ms before the run knows its drive, and at the
> pull there are none left); `discovery`'s own slice lines at claim time are what prove the callback
> alive. **Chunk 3's log half was re-walked and PASSED 2026-09-09** — route (b) confirmed under
> claim, no short read before `ENXIO`, and the 3 s deadline never approached because `ENXIO`
> aborts the cycle in ~1 ms. **Six of six pulls**, read back from the persisted log 2026-09-10: the reply
> 2.7–6.3 ms behind the removal callback and 0 bytes then `ENXIO` every time — which **discharged
> chunk 5 without a cable pull, by user decision 2026-09-11**. **Chunk 3 is CLOSED, all items PASSED 2026-09-09** — item 9 took six runs
> because the phase a cable-pull lands in is one chance in three, and the sixth landed in
> `writingBack`, the hazard case. **Chunk 4 is CLOSED, all nine items PASSED 2026-09-11** against
> `c767317`: a *paused* run unplugged, route (b) alone, ended 1 ms after the removal callback with a
> report saying *paused*, on the 1 TB scratch T5 and — 4.9, by user decision — the thumb, where the
> declared prediction held: one whole-disk event, so no idempotency exercised, and none has a
> hardware path in this design. **7g closed chunk 4's two logging gaps in code the same day** —
> commands and automatic re-selections now log — with the helper hash unmoved, **and a person saw
> those lines on the installed build that evening**, all four command labels, `Resume` at 18:02:13.
> **7h closed the mutation survivor 7g predicted**, measured
> surviving all 1301 tests and killed by one new test. **The step is CLOSED**: all four gate items
> ticked, the account archived to [`progress/step-12.md`](progress/step-12.md). Both of chunk 2's unwalked items were **instrument defects and were reworded, not failed**
> — the third and fourth of that kind since 2026-09-04, and neither described a fault in the app. The suite stands at
> **1313 tests / 156 suites / 0 failures** (floor 1313, ratcheted at Step 13 chunk 2), protocol **v15** (chunk 3, 2026-09-05),
> zero source warnings from three clean builds, **14/14** gate clients type-checking against v15 —
> **12/13 on the first attempt at chunk 6**, because `ui-probe` builds a `RunController` and the new
> `onDeviceLost:` parameter has no default. That is `build-tools.sh` doing the job it exists for:
> the app build does not compile the tools, so nothing else would have found those two call sites.
> The helper's source hash is **`e19b0b3c…`** — it moved at chunk 1, at chunk 3 and at **chunk 7b**,
> **not** at chunks 4, 5 or 6, all app target only; and **all four hardware gate results lapsed at
> chunk 1**, so 7b's move costs nothing that was not already owed. See `PROGRESS.md`.
>
> ⚠️ **Until 2026-09-05 this block said "Status, 2026-09-02 … increments 1–10 are done, 11 and 12
> remain", protocol v12, helper hash `73990c90…`** — three days and two increments stale, and
> **internally inconsistent the whole time**: the paragraph below it already named `e6888aa5…` as
> the current hash, as of 2026-09-03. A block that contradicts itself two paragraphs apart is the
> loudest signal this file can produce and nobody heard it, because each half was edited on the day
> someone happened to be touching that half. **Edit a status block whole, or leave it alone.**
>
> [`progress/step-11-increment-plans.md`](progress/step-11-increment-plans.md) no longer holds any
> increment — all four sections were deleted as they landed, as its own header instructs. What is
> left is the settled-decision table. **Read it before re-opening one of those decisions**, not
> before building.
>
> **All three of Step 10's hardware gates passed at helper hash `e6888aa5…`, as of 2026-09-03.**
> ⚠️ That was *"the current helper hash"* until 2026-09-05, when Step 12's chunk 1 moved it to
> `a951e527…`. **The three results below are historical from that moment** — true on the day, about
> a build that no longer exists — and they are re-run at Step 12's chunk 7. `metrics-check.sh` **128/0** at increment 11's gate; `xpc-concurrency-check.sh`
> **0 failures**, its increment 8 finding unchanged (same connection serialized, second connection
> concurrent at 5.0 ms worst); `retention-cycle-check.sh` **15/15** over the **whole device** —
> 932 window fingerprints before and after, byte-identical, after a cycle that wrote 1,072,693,248
> bytes at block 1482268672. The two that had been owed since increment 8 were owed because the
> helper binary moved, never because anything failed. The 4 TB T5 EVO fixture **is attached
> as of 2026-09-03** (`disk6`, `PSSD T5 EVO`), along with the 125.8 MB thumb drive (`disk4`) and the
> 1 TB scratch T5 (`disk7`) — chunk 15 was walked on the first two. All three were still attached on
> 2026-09-04.
>
> ✅ **The 1 TB T5's `fill.bin` was restored 2026-09-04 18:19**, with the command below, against the
> scratch device identified by **serial `12345686DAA9`** (`/dev/disk7` that day — BSD names move
> across a replug): 999,947,239,424 bytes of `/dev/urandom`, written in 57m43s at 288.8 MB/s, `dd`
> ending on `No space left on device` as intended. The volume now reads **100% used**, so the gate's
> `df` early warning no longer fires. Three 1 MiB samples, taken at 1 GiB, 476811 MiB and 953622
> MiB, digest distinctly — and none of them is the all-zero block.
>
> **What would invalidate it:** unlinking the file, or erasing the volume — which is what
> `make-unmount-fixture.sh` guards against at its own prompt. Neither `retention-cycle-check.sh` nor
> `run-control-check.sh` will: both write back exactly the bytes they read.
>
>     dd if=/dev/urandom of=/Volumes/Test_Drive/fill.bin bs=4m status=progress
>
> **It had been deleted, and the rule that it "must be kept" was already broken when the retention
> gate ran on 2026-09-03.** That gate passed because the residual `/dev/urandom` pattern survived
> the unlink — `df` read the volume at 1% used and the CONTENT check found three distinct
> fingerprints anyway. That was luck, not design: a drive that discards those blocks puts the next
> run back to zeros, where the CONTENT check is the only thing between that and a vacuous pass.
> **Keep the file.**
>
> **Complete again as of 2026-09-04**: increment 12 added chunk 16 and changed 6.1 and 11.7, and
> all four were walked the same day. What follows was true up to 2026-09-03.
>
> **The human checklist is complete. Chunk 15 was added and walked on 2026-09-03** — five items,
> all passed, no product defect. Its item 2 was the one that mattered: nothing anywhere checked that
> the figures actually disagree with Activity Monitor by the factors the report claims, only that
> the report claims them. **They do** — 1.48× on Read and 3.55× on Write, against ~1.5× and ~3.4×
> claimed. Two of the chunk's original seven items were deleted unwalked: the v12/v14 protocol
> mismatch (fixture destroyed by an early `install-app.sh`) and the idle-panel em dashes (the item
> was wrong about the app and inverted — it would have passed on a build with the defect it was
> written to catch). Full record in `PROGRESS.md`, increment 11.
>
> Everything else is walked and passed. Chunk 14, added by increment 10, passed in full on
> 2026-09-02: all seven items, no product defect. Its item 4 revokes Full Disk Access and is the
> only cover the run-start dialog has anywhere; the remedy button was pressed and System Settings
> opened, and no volume had been unmounted. Chunks 1–13 passed by 2026-09-01. **Four items went
> stale and were corrected 2026-09-03**, three of them since increment 10 — see that file's header.
>
> **`window-fit-check.sh` worst case is 613 pt** against a committed 700 pt budget, with
> `.window-fit-exceptions` empty; **37** render cases.
>
> **The repository has a remote as of 2026-09-02** — private
> [`chrisARC3/macos-usbdrivetester`](https://github.com/chrisARC3/macos-usbdrivetester), branch
> `main`. Nothing about the distribution decision below changes: source only, and Step 16 is still
> where a build reaches anyone.
>
> One unplanned change sits between increments 5 and 6: **protocol v12**, after the displayed
> throughput figures were reported as "way off". They divided by phase time where every other tool
> divides by the wall clock. See PROGRESS.md — the denominator took three attempts and two of them
> were refuted on hardware.
>
> **That decision was reversed in increment 11 (protocol v14, 2026-09-02).** FR-METR-1 was amended:
> the displayed rates divide by phase time again, because reconciling with Activity Monitor is no
> longer an objective — a device tester should report what the device did while it was working. The
> denominator work above still stands for `coverageBytesPerSecond` and the ETA, which never moved.
> Read the FR document's 2026-09-02 amendment before reading the two entries as a circle.
>
> **The order is deliberate and is not the numbering.** Step 14 was built before Step 11 because
> Step 11's deletion of the `Unmount All` / `Acquire` / `Release` controls was gated on Step 14's
> warnings existing — after that deletion, **two** clicks stand between FR-DEV-3's default selection
> and a write (Start, then Proceed on a dialog naming the drive by model and USB serial), and on
> this machine that default is the 22 TB Seagate carrying Backup and Time Machine.
> **That gate is now discharged**, so Step 11 may proceed.
>
> **The deletion itself is settled and will not be re-visited** (user decision 2026-08-12). The
> "one deliberate click" phrasing this plan used until then — still present in Step 14's notes
> below, which are dated rationale and deliberately not rewritten — undercounted by one. See
> [CONSTRAINTS.md](CONSTRAINTS.md) section 2, which supersedes it.
>
> **Read [PROGRESS.md](PROGRESS.md) first** — it holds the step in progress and what that step
> inherits (Step 12, as of 2026-09-05). For *why* something was
> done the way it was, `progress/step-NN.md` has the archived history of that step; this table is the
> map, not the tracker.

| Step | AI | Title | Primarily on | Gate in one line |
|------|----|-------|--------------|------------------|
| 1 | AI-1 | Xcode workspace: app + helper targets | Both | Both targets build and launch; empty XPC round-trip works |
| 2 | AI-16 | Raw-device abstraction + simulated device + test harness | Helper/core | Core algorithm scaffold runs against an in-memory device under Swift Testing |
| 3 | AI-2 | `SMAppService` registration + XPC protocol + code-signature validation | Both | GUI registers helper; helper rejects an unsigned/foreign caller |
| 4 | AI-14 | Helper lifecycle teardown (unregister/remove) | Both | GUI can fully remove the helper; status reflects it |
| 5 | AI-3 | Device discovery & selection | GUI | USB devices enumerate, sort stably, default-select, live-refresh |
| 6 | AI-4 | Mount-guard: unmount + exclusive whole-disk claim | Helper | Test refuses to start unless unmounted **and** claimed; precise errors |
| 7 | AI-5 | Raw I/O core: open `rdiskN`, no-cache, block geometry, chunking | Helper | Geometry read correctly; chunk plan correct incl. final chunk |
| 8 | AI-6 | read → write-back → read-verify cycle | Helper/core | Cycle is bit-for-bit non-destructive in simulation **and** on the scratch device, whole-device fingerprint unchanged |
| 9 | AI-8 | Metrics: throughput + read-latency min/max/p99 | Both | Live metrics refresh ≥1/s; ETA converges; constant-memory p99 |
| 10 | AI-7 | Failure modes + bad-block report + Markdown export | Both | Stop-on-error and log-and-continue both correct; report exports |
| 11 | AI-10 | Run-control state machine: start/pause/resume/stop/restart | Both | Illegal transitions blocked; pause settles at chunk boundary |
| 12 | AI-9 | Device-loss handling (hot-unplug mid-run) | Both | Unplug terminates cleanly, errors, re-runs discovery |
| 13 | AI-12 | System-sleep prevention | GUI | Assertion held only while actively running; released on all exits |
| 14 | AI-11 | Mandatory pre-run warnings & honest framing | GUI | Three warnings shown & acknowledged before any run |
| 15 | AI-15 | Logging / observability consolidation | Both | All significant events logged; never logs device contents |
| 16 | AI-13 | Signing, hardened runtime, notarization | Both | Notarized build launches Gatekeeper-clean on a clean Mac |

---

# Phase 0 — Foundations & Test Harness

## Step 1 — Stand up the Xcode workspace (two targets)

**Original action item:** AI-1
**Satisfies:** FR-ARCH-1, FR-ARCH-2; NFR-COMPAT-1/2/3, NFR-MAINT-3, NFR-MAINT-4
**Trust boundary:** establishes both sides.

### Objective
Create the Xcode project containing two products — an unprivileged SwiftUI app and a privileged LaunchDaemon helper — that build reproducibly and can exchange a trivial XPC message. No real functionality yet; this is the skeleton everything else hangs on.

### Detailed steps
1. **Create the app target.** New Xcode project → macOS → App → SwiftUI lifecycle, Swift. Name e.g. `USBDriveTester`. Set **Deployment Target = macOS 26.0**, **Architectures = arm64** (NFR-COMPAT-1/2). Set the **Team** to your Apple Developer team in Signing & Capabilities (you will need a real Team ID later for code-sig validation; set it now).
2. **Add the helper target.** Add a new target of type **Command Line Tool** (Swift), e.g. `com.<you>.USBDriveTester.helper`. This becomes the LaunchDaemon. Its bundle/executable name must be a reverse-DNS identifier — it will double as the **Mach service name** and the **`SMAppService` plist name** (keep these three consistent from the start; mismatches are the #1 cause of `SMAppService` failures).
3. **Lay out the source tree so the trust boundary is obvious** (NFR-MAINT-4). Suggested top-level groups:
   - `App/` — SwiftUI views, view models, app-side controllers (unprivileged).
   - `Helper/` — daemon `main`, XPC listener, privileged I/O (privileged).
   - `Shared/` — the XPC protocol definition, shared model types (DTOs), error enums. Compiled into **both** targets.
   - `USBDriveTesterTests/` — Swift Testing target (the unit-test target; our "CoreTests").
4. **Embed the helper in the app bundle the way `SMAppService` expects:**
   - Helper executable goes in `Contents/MacOS/` of the app, *or* is referenced from the LaunchDaemon plist.
   - Create the LaunchDaemon **launchd property list** at `Contents/Library/LaunchDaemons/<helper-id>.plist`. Minimum keys: `Label` (= helper id), `BundleProgram` (path to the helper executable inside the app bundle), and `MachServices` = `{ <helper-id> = true }`. Add a **Copy Files build phase** on the app target that copies this plist into `Contents/Library/LaunchDaemons/`.
   - Add a build phase to embed the built helper executable into the app bundle.
5. **Add a placeholder XPC protocol** in `Shared/` (e.g. `protocol TesterControl { func ping(reply: @escaping (String) -> Void) }`) and a no-op helper implementation that returns `"pong"`. Wire the GUI to a temporary "Ping helper" button. (Real registration is Step 3; for Step 1 you may run the helper manually via `launchctl bootstrap` to prove the plumbing.)
6. **Confirm reproducible build** (NFR-MAINT-3): a clean build (`⇧⌘K` then build, or `xcodebuild`) produces the `.app` with the helper and plist embedded.

### Verification Gate (must pass before Step 2)
- [ ] Both targets build for arm64 / macOS 26 with zero errors and no new warnings.
- [ ] The built `.app` bundle contains the helper executable **and** `Contents/Library/LaunchDaemons/<helper-id>.plist`, and the plist's `Label`, `BundleProgram`, and `MachServices` are internally consistent and match the helper id.
- [ ] The GUI launches and shows its window.
- [ ] The "Ping helper" round-trip returns `"pong"` (helper may be launched manually for this step).
- [ ] `git` repo initialized/committed; a progress note records the verification.

### Risks / gotchas
- The Mach service name, plist `Label`, and `SMAppService.daemon(plistName:)` argument must be **identical**. Decide the string now and never change it casually.
- Command-line-tool helpers still need an `Info.plist` (embedded via linker flags) for code signing later (Step 16) — note this for now.

---

## Step 2 — Raw-device abstraction, simulated device, and test harness

**Original action item:** AI-16 *(pulled forward — see "Why the order differs")*
**Satisfies:** NFR-MAINT-2 (and de-risks FR-TEST-*, FR-FAIL-*, FR-METR-*)
**Trust boundary:** core/helper-side code, but designed to run with **no privileges** under Swift Testing.

### Objective
Define the abstraction that separates the **core test algorithm** (chunking, final-chunk sizing, verify, metrics, failure classification) from the **physical device**. Provide an in-memory implementation so the entire engine can be developed and unit-tested deterministically, before any hardware or privilege is involved.

### Detailed steps
1. **Define a `RawBlockDevice` protocol** in `Shared/` (or a `Core/` group compiled into the helper and the test target). Minimal surface, mirroring the real raw-device operations:
   ```
   protocol RawBlockDevice {
       var logicalBlockSize: Int { get }      // bytes, e.g. 512 or 4096
       var blockCount: UInt64 { get }          // total addressable blocks
       func read(into buffer: UnsafeMutableRawBufferPointer,
                 atByteOffset: UInt64) throws -> Int
       func write(_ buffer: UnsafeRawBufferPointer,
                  atByteOffset: UInt64) throws -> Int
   }
   ```
   Use **64-bit** offsets/counts throughout (NFR-COMPAT-6). Define a `DeviceIOError` enum with cases for read error, write error, short transfer, and misalignment.
2. **Implement `InMemoryBlockDevice`** conforming to `RawBlockDevice`, backed by a `Data`/byte array sized `blockSize * blockCount`. Parameterize block size so you can test **both 512-byte and 4096-byte** geometries (NFR-COMPAT-5). Add **fault-injection hooks**: ability to make specific block ranges throw on read or write, or to silently corrupt bytes on write (so a later verify mismatch is triggered) — these power the failure-mode tests in Step 10.
3. **Use the `USBDriveTesterTests` (Swift Testing) target.** Add a first test that constructs an `InMemoryBlockDevice`, fills it with known pseudo-random data, and asserts read-back equality (`#expect`). This proves the harness itself is sound.
4. **Stub the core engine type** (e.g. `RetentionTestEngine`) that takes a `RawBlockDevice` plus an `ioSize` and will host the algorithm built in Steps 7–10. For now it only computes the **chunk plan** (see Step 7 detail) so you have something to test immediately.
5. **Document the contract:** alignment requirements (offset and length multiples of `logicalBlockSize`), and that the engine must never assume `ioSize` divides the device evenly (final-chunk handling, FR-TEST-5).

### Verification Gate (must pass before Step 3)
- [ ] `RawBlockDevice` protocol and `InMemoryBlockDevice` exist and compile into both the helper target and the test target — with **no UIKit/IOKit/privileged dependencies** in the core (proves true independence per NFR-MAINT-2).
- [ ] Swift Testing suite runs green: read/write round-trip on a 512-byte-block device **and** on a 4096-byte-block device.
- [ ] Fault-injection demonstrably forces a read error, a write error, and a silent corruption (verify-mismatch) in a test.
- [ ] The engine's chunk-plan stub is callable from a test (even if it only returns a list of `(offset, length)`).

### Risks / gotchas
- Resist putting any `Dispatch`/UI/IOKit code in the core. The whole value of this step is that the engine is pure and host-only-testable.
- Keep buffers as raw byte buffers, not typed arrays, so the same code path drives both the simulated and the real (Step 7) device.

---

# Phase 1 — Privilege Plumbing

## Step 3 — `SMAppService` registration + XPC protocol + client code-signature validation

**Original action item:** AI-2
**Satisfies:** FR-ARCH-3/4/5/6; NFR-SEC-1/2/3/5, NFR-INST-1, NFR-MAINT-1
**Trust boundary:** spans both; this step *builds* the boundary.

### Objective
Make the helper a real, `SMAppService`-registered LaunchDaemon, define the versioned XPC protocol the GUI uses to drive it, and have the helper **refuse commands from any client not signed by your Team ID**.

### Detailed steps
1. **Register the daemon.** In the GUI, use `SMAppService.daemon(plistName: "<helper-id>.plist")`. Call `.register()` to install; read `.status` (`.enabled`, `.requiresApproval`, `.notRegistered`, `.notFound`). When `.requiresApproval`, guide the user to **System Settings → General → Login Items & Extensions** (NFR-INST-1). Surface status clearly in the GUI.
2. **Stand up the XPC listener in the helper.** The daemon's `main` creates an `NSXPCListener` for the Mach service name from the plist, sets a delegate implementing `listener(_:shouldAcceptNewConnection:)`, and `resume()`s. Keep the daemon alive (run loop).
3. **Define the real XPC protocol** in `Shared/` and **version it** (NFR-MAINT-1) — e.g. include a `protocolVersion` query the GUI checks on connect. Keep the interface **minimal** (NFR-SEC-3): device geometry query, start run (with parameters), pause, resume, stop, and a callback/progress channel back to the GUI. Use a second `*Client` protocol for helper→GUI progress callbacks via `NSXPCConnection.exportedObject`. **(Not what Step 9 built — see Step 9, detailed step 4. The GUI polls `runProgress` on a second connection instead; no reverse protocol and no exported object on the app side. Left as written because it was the plan at the time.)**
4. **Validate the caller's code signature (the security crux, FR-ARCH-5 / NFR-SEC-2).** In `shouldAcceptNewConnection`, before configuring the exported object, require the connection's peer to satisfy a code-signing requirement pinned to your **Team ID**:
   - Preferred modern API: `connection.setCodeSigningRequirement("anchor apple generic and certificate leaf[subject.OU] = \"<YOUR_TEAM_ID>\"")` (macOS 13+). Per NFR-SEC-2, Team-ID match is the accepted bar — do **not** additionally pin bundle id or Apple anchor beyond this requirement string.
   - Reject (return `false`) if the requirement is not met.
5. **Validate every request's parameters at the boundary** (NFR-REL-7, NFR-SEC-3): even after a trusted connection, the helper independently re-checks device identity, offset/length range, and block alignment, rejecting anything out of range or misaligned **before** any privileged I/O.
6. **Connect from the GUI** via `NSXPCConnection(machServiceName:options:.privileged)`, set `remoteObjectInterface`, set the interrupt/invalidation handlers, and `resume()`.
7. **Add `os_log` points** (NFR-OBS-1): helper registration, connection accepted/rejected (with reason), protocol-version handshake.

### Verification Gate (must pass before Step 4)
- [ ] From the GUI, `register()` installs the daemon; after user approval, `.status == .enabled`, and the GUI shows that status.
- [ ] A real XPC round-trip (e.g. protocol-version query) succeeds **through the registered daemon** (not a manually-bootstrapped one).
- [ ] **Negative test:** a build signed with a *different* Team ID (or an ad-hoc/unsigned dummy client) is **rejected** by `shouldAcceptNewConnection`, and the rejection is logged. This is the security gate — do not pass the step without demonstrating rejection.
- [ ] The helper rejects an out-of-range / misaligned parameter request with a clear error (NFR-REL-7), exercised by a deliberately bad call.

### Risks / gotchas
- `SMAppService` requires the app to be **code-signed** (even locally) and the plist embedded correctly. If `.status == .notFound`, the plist path/Label/Mach-service name are inconsistent — recheck Step 1.
- The helper runs as **root**; treat every byte from the GUI as untrusted input (this is why Step 5/NFR-REL-7 validation is mandatory).
- Keep the protocol minimal now; widening it later is cheap, but a wide attack surface is hard to walk back.

---

## Step 4 — Helper lifecycle teardown (unregister / remove)

**Original action item:** AI-14
**Satisfies:** NFR-INST-3, NFR-SEC-5
**Trust boundary:** GUI initiates; helper is removed.

### Objective
Provide a clean, user-invokable path to fully unregister and remove the privileged helper — the other half of the lifecycle started in Step 3.

### Detailed steps
1. **Add an "Uninstall helper" action** in the GUI that calls `SMAppService.daemon(...).unregister()` (async; handle the completion/error).
2. **Refuse teardown mid-run.** Guard: if a run is active, block uninstall and tell the user to stop the run first (interacts with Step 11's state machine).
3. **Drain the XPC connection** before/while unregistering: invalidate the `NSXPCConnection`, ensure the helper has released the device node (ties to NFR-REL-5), then unregister.
4. **Reflect the new status** in the GUI (`.notRegistered`). Confirm no leftover Mach service or daemon process remains (`launchctl print system/<helper-id>` should not find it).
5. **`os_log`** the unregister event.

### Verification Gate (must pass before Step 5)
- [ ] "Uninstall helper" transitions `.status` to `.notRegistered` and the GUI shows it.
- [ ] After uninstall, the daemon process is gone (verified via `launchctl`), and a subsequent `register()` cleanly reinstalls (install→uninstall→reinstall cycle works repeatedly).
- [ ] Uninstall is blocked with a clear message while a (simulated) run is active.

### Risks / gotchas
- `unregister()` is asynchronous and can lag; poll `.status` rather than assuming immediate removal.
- Ensure the device node is released first, or removal can leave a claimed disk (revisited in Step 6).

---

# Phase 2 — Device Discovery & Safety

## Step 5 — Device discovery & selection

**Original action item:** AI-3
**Satisfies:** FR-DEV-1/2/3/4/5/6/7; NFR-USE-3, NFR-COMPAT-4/6
**Trust boundary:** primarily GUI (discovery does not require root); geometry for the *selected* device may be confirmed via the helper.

### Objective
Enumerate connected USB mass-storage devices, present them in a stable, identifiable list, default-select the first, allow the user to change selection, and live-refresh as devices come and go **while no test is running**.

### Detailed steps
1. **Enumerate USB mass-storage whole disks.** Use IOKit: match `kIOMediaClass` with `kIOMediaWholeKey = true`, then walk each media object's parent chain to confirm it sits behind a **USB** transport (USB mass-storage). For each match collect:
   - **BSD name** (`kIOBSDNameKey`) → e.g. `disk6` (FR-DEV-6). A *locator*, not an identity: it is assigned at enumeration and names a different drive after a replug or a reboot (see "Test hardware").
   - **Capacity** = `kIOMediaSizeKey` (bytes) (FR-DEV-6, NFR-USE-3).
   - **Logical block size** = `kIOMediaPreferredBlockSizeKey` and/or confirm later via ioctl (FR-DEV-5; reconciled in Step 7).
   - **Model / vendor / product** from the USB device properties up the chain.
2. **Sort stably by BSD name** (FR-DEV-2) — a numeric-aware sort so `disk2` < `disk10`. Stability matters so the list does not jump around between refreshes.
3. **Default-select the first device** (FR-DEV-3); allow re-selection (FR-DEV-4). Surface the selected device **unambiguously** — BSD name + model + human-readable capacity (NFR-USE-3) so the wrong drive can't be picked by accident.
4. **Live refresh (FR-DEV-7).** Register IOKit/DiskArbitration appearance & disappearance callbacks and update the list **only while no run is active**. (During a run, discovery is frozen; hot-unplug of the *device under test* is handled separately in Step 12.)
5. **Determine geometry for the selected device (FR-DEV-5):** record logical block size and block count; this feeds the chunk plan. Final authority on geometry is the helper's ioctl in Step 7 — reconcile and prefer the device-reported values.
6. **`os_log`** device connect/disconnect events (NFR-OBS-1).

### Verification Gate (must pass before Step 6)
- [ ] Connecting two or more USB drives lists all of them; non-USB/internal disks are excluded.
- [ ] List order is stable and numeric-correct across refreshes; first device is default-selected; selection can be changed.
- [ ] Each row shows BSD name, model, and human-readable capacity; the selected device is unambiguously identified.
- [ ] Plugging/unplugging a drive **with no run active** updates the list within a second or two.
- [ ] Selected device's logical block size and block count are captured and displayed/recorded.

### Risks / gotchas
- A single physical device can expose multiple `IOMedia` nodes (whole disk + partitions). List **whole disks only** (`kIOMediaWholeKey`).
- Capacity formatting: use base-10 vs base-2 consistently and label units (ties to NFR-USE-1).

---

## Step 6 — Mount-guard: unmount verification + exclusive whole-disk claim

**Original action item:** AI-4
**Satisfies:** FR-SAFE-1/2/3/4/5/6/7; NFR-REL-3, NFR-USE-5
**Trust boundary:** the **claim/exclusive-open is helper-side** (privileged); the GUI orchestrates and shows errors.

### Objective
Guarantee that no test ever starts unless **(a) every volume on the device is unmounted** and **(b) the helper holds exclusive whole-disk access** to the device node — with precise, actionable errors distinguishing the two failure causes.

### Detailed steps
1. **Check for mounted volumes (FR-SAFE-1/2).** Via DiskArbitration, enumerate the selected whole disk's child media; for each, get its `DADiskCopyDescription` and check `kDADiskDescriptionVolumePathKey` (non-nil ⇒ mounted). If any are mounted, **do not proceed**.
2. **Acquire exclusive whole-disk access (FR-SAFE-3).** Helper-side, and **without
   unmounting anything** — see the amendment note below.
   - **Claim the disk** — `DADiskClaim(wholeDisk, …)` so the OS won't auto-remount mid-run, **and** open `/dev/rdiskN` with `O_EXLOCK` (Step 7's `open` must succeed). Hold both for the run's duration.
   - **Claim with a timeout.** Measured 2026-07-30: a contended `DADiskClaim` is neither
     granted nor dissented — it stays **pending indefinitely**. A blocking claim would
     wedge the helper, so the claim must time out, and a timeout means *another process
     holds the disk* (FR-SAFE-4(b)), not that the call failed.
   - If any volume is still mounted, **refuse** (FR-SAFE-4(a), FR-SAFE-6). Acquiring must
     never change the mount state as a side effect.

   > **Measured, 2026-07-30** (`scripts/exclusivity-probe.sh`), and load-bearing for this
   > step:
   > - **The mount guard is kernel-enforced.** `open(rdiskN, O_RDWR)` fails `EBUSY` while
   >   any volume is mounted. FR-SAFE-1/2 is backed by the OS, not only by our policy.
   > - **Auto-remount is real.** The moment a probe released its claim, macOS silently
   >   remounted the volume. Unmounting alone is *not* sufficient — the claim is what
   >   keeps it unmounted, exactly as this step's "risks" note warns.
   > - **The two FR-SAFE-4 causes are the same errno.** Both (a) and (b) surface as
   >   `EBUSY`. The mount check is the only thing that separates them, which is why the
   >   read-only readiness check must report mount state rather than just an error code.
   > - **Release is asynchronous.** An open immediately after `DADiskUnclaim` can still
   >   see `EBUSY`. The release path must not assume the device is instantly reusable.

   > **Amended 2026-07-30.** This step originally read "unmount the whole disk (all
   > volumes)" as part of acquiring, with an in-app unmount as an optional extra. That
   > conflicted with FR-SAFE-4(a), which requires a mounted volume to produce a refusal
   > naming the volume and instructing the user. Unmounting is now **only** ever the
   > result of the user pressing the control in 2a, never a side effect of starting a
   > test (FR-SAFE-6).

2a. **Mount/unmount control (FR-SAFE-5/6/7).** One button in the app, acting on **all**
   volumes of the selected device, whose label and action always agree:

   | Selected device | Label | State |
   |---|---|---|
   | none | `Unmount All` (default) | disabled |
   | one or more volumes mounted | `Unmount All` | enabled → unmount all |
   | no volumes mounted | `Mount All` | enabled → mount all |

   A partially-mounted device reads `Unmount All` — any mounted volume selects the
   unmount direction. Also disabled during a run or while the helper holds the claim
   (FR-SAFE-7). Unmount is a common failure case (open files), so a failure must name the
   volume and the reason (NFR-USE-5), not merely report that it failed. The control lives
   app-side and uses unprivileged DiskArbitration, keeping the privileged XPC surface to
   check/acquire/release (NFR-SEC-3). Its state derives from the Step 5 device model,
   which live-updates through the volume watcher, so the label re-evaluates itself when
   the action completes.
3. **Distinguish the two failure causes precisely (FR-SAFE-4, NFR-USE-5):**
   - (a) Volume(s) still mounted → name the specific volume(s) and instruct the user to unmount them.
   - (b) Volumes unmounted but exclusive access fails because the device node is **claimed by another process** → say exactly that (and, if discoverable, which process / that the node is busy).
   - Never show a generic "couldn't start" — the message must name the actual cause and the corrective step.
4. **Hard precondition on writes (NFR-REL-3):** the helper must **never** issue a block write unless both conditions hold. Encode this as an assertion at the top of the write path, not just a UI check.
5. **`os_log`** the unmount, the claim acquire/release, and any block reason (NFR-OBS-1).

### Verification Gate (must pass before Step 7)
- [ ] With a mounted volume present, starting a test is refused with a message naming the **mounted volume** and telling the user to unmount it.
- [ ] With volumes unmounted but the node held busy by another process, starting is refused with the **"device node is claimed"** message — distinct from the mounted-volume message.
- [ ] On success, the helper holds an exclusive claim and an exclusive `rdiskN` open; releasing it (stop/teardown) makes the disk normally usable again.
- [ ] The write path has an enforced guard that exclusive access is held (verified by a unit/integration check that the guard trips when access is absent).
- [ ] **Mount/unmount control (FR-SAFE-5/6/7):** disabled with no device selected; reads `Unmount All` and unmounts every volume when any is mounted; reads `Mount All` and mounts them when none is; a partially-mounted device reads `Unmount All`; the label re-evaluates after each action; a failed unmount names the volume and the reason.
- [ ] **Nothing mounts or unmounts implicitly (FR-SAFE-6):** attempting to start with a volume mounted refuses and leaves the mount state unchanged.

### Risks / gotchas
- Unmounting volumes is **not** sufficient — without `DADiskClaim`, `diskarbitrationd` or Spotlight can re-probe/remount and corrupt an in-flight run. The claim is mandatory.
- Releasing the claim cleanly on **every** exit path (stop, error, device loss, crash-as-much-as-possible) ties to NFR-REL-5 and is re-checked in Steps 11/12.

---

# Phase 3 — I/O Core (built test-first against the simulated device from Step 2)

## Step 7 — Raw I/O core: open `rdiskN`, no-cache, block geometry, chunk plan

**Original action item:** AI-5
**Satisfies:** FR-TEST-2/5/6; **FR-TEST-9 (mechanism only — added 2026-08-02)**; FR-DEV-5; NFR-PERF-1/2, NFR-COMPAT-5/6
**Trust boundary:** **helper-side only** (FR-ARCH-6).

### Objective
Implement the real `RawBlockDevice` for hardware: open the raw device uncached, read true block geometry, and produce the block-aligned chunk plan (including the correctly-sized final chunk). The same engine from Step 2 will now run against either the in-memory device or this real one.

### Detailed steps
1. **Use the raw descriptor Step 6 already holds.** `AcquiredDevice.fileDescriptor` is `/dev/rdiskN` (raw, not buffered `diskN`), already open `O_RDWR | O_EXLOCK | O_NONBLOCK`. Steps 2–4 below are applied to *that* descriptor. **Step 7 opens nothing of its own.**

   > **Amended 2026-07-30, measured.** This originally specified a plain `O_RDWR` open.
   > `scripts/exclusivity-probe.sh` established that **a plain `O_RDWR` open on an
   > unmounted raw disk is not exclusive at all** — two independent opens both succeed,
   > so two processes could write the same device simultaneously. `O_EXLOCK` does
   > exclude: the second attempt fails `EBUSY`. `O_NONBLOCK` matters too, or a contended
   > open blocks instead of returning the error the guard needs.

   > **Amended 2026-08-02, user decision (Step 7 scoping).** This step originally read
   > "**Open the raw device** in the helper: `open(…)` … Fail with a precise error if it
   > can't be opened exclusively (ties to Step 6)." **Step 6 now performs that open**, in
   > `DeviceClaim.acquire(_:)`, because the open is one half of the mount guard: it is the
   > thing that actually excludes another writer, and it has to be taken in the same
   > sequence as the DiskArbitration claim so the two cannot disagree.
   >
   > Followed literally, Step 7 would therefore open a **second** descriptor — and it is
   > *closing* that descriptor that does the damage. Measured 2026-08-01: releasing an
   > exclusive open on the raw node makes DiskArbitration re-probe the media and remount
   > the volume ~4 ms later, silently undoing the user's unmount. The same measurement
   > forced the Full Disk Access probe away from the device (see
   > `DeviceClaim.fullDiskAccessState()`). Any Step 7 geometry read, experiment or probe
   > that opens the node on its own has the same defect.
   >
   > "Fail with a precise error if it can't be opened exclusively" is **already
   > discharged** by Step 6's `DeviceAccessPrecondition` classification, which separates
   > FR-SAFE-4's two causes and adds `accessNotPermitted` for the TCC case.
2. **Disable caching (FR-TEST-6):** `fcntl(fd, F_NOCACHE, 1)` and `fcntl(fd, F_GLOBAL_NOCACHE, 1)` so reads/writes hit the device, not the unified buffer cache.

2a. **Build the cache-bypass self-check (FR-TEST-9, added 2026-08-02).** Setting the flags in step 2 cannot be verified by its own return value — measured 2026-08-02, `fcntl(fd, F_NOCACHE, 1)` returns `0` on `/dev/null`, and there is no `F_GETNOCACHE` to read the flag back. Behaviour is the only observable. Step 7 therefore builds the *mechanism*, and **Step 8 calls it at run start**:

   - a **pure classifier** (`Core/CacheBypassCheck.swift`) mapping two read durations plus the byte count onto `bypassed` / `likelyCached` / `inconclusive` — **three** states, never two, so "could not tell" cannot collapse into an answer;
   - a **helper-side timing harness** that reads one chunk twice on the already-held descriptor. Read-only; no write reaches the device in this step.

   Polarity, because it is easy to state backwards: **similar durations = healthy** (both reads reached the device); a large **speed-up on the re-read = caching is live**, and is the warning condition.

   Read a chunk from the **middle of the device, not chunk 0** — block 0 holds the GPT and partition table, the region the OS has most recently touched, so its "first" read is the least likely to be genuinely cold.

   > **MEASURED 2026-08-02 — re-read timing does NOT discriminate. Mechanism revised.**
   > `./scripts/nocache-calibration.sh` on the scratch device (4 MiB, 4 reads/phase, 0 failures) settled the
   > open risk in the negative. With `F_NOCACHE` unset, four reads of one region took
   > 12,295 / 8,829 / 8,786 / 8,737 µs; with the flags set, a different region took
   > 8,903 / 8,872 / 8,846 / 8,887 µs. A 4 MiB copy from RAM on this machine takes **58 µs**,
   > so a real cache hit would be **~150×** faster — the observed 1.41× is first-read warm-up
   > (USB spin-up plus first-touch faults on 256 fresh 16 KiB pages), confirmed by the second
   > phase's first read of an untouched region showing no penalty at all.
   >
   > Root cause, confirmed: `/dev/rdisk4` is `crw-`, a **character** device, while
   > `/dev/disk4` is `brw-`. The buffer cache belongs to the block node, so the raw path was
   > never cached and `F_NOCACHE` had nothing to suppress.
   >
   > **The asymmetry this forces:** timing can *falsify* (a 150×-fast read proves a cache
   > hit) but cannot *verify* (similar timings are identical whether caching was suppressed
   > or was never possible). So `bypassed` may never rest on timing:
   >
   > - **Primary, structural:** `fstat(fd)` → assert `S_ISCHR`. The descriptor must be the
   >   character device. This catches the failure that can actually happen — opening
   >   `/dev/diskN` instead of `/dev/rdiskN`, a one-character bug that would make every
   >   verify vacuous — and it is a fact about the file, not a heuristic. Plus both `fcntl`
   >   calls returning 0.
   > - **Secondary, falsification only:** during the run, flag `likelyCached` if a chunk read
   >   returns faster than the transport allows. Calibrated here: RAM 71.3 GB/s vs. device
   >   0.475 GB/s, so a threshold near **2 GB/s** sits ~4× above the fastest plausible USB
   >   device and ~35× below RAM.
   >
   > FR-TEST-9's own text is unchanged — it specifies what to verify, never how.
3. **Query geometry:**
   - `ioctl(fd, DKIOCGETBLOCKSIZE, &blockSize)` → `UInt32` logical block size (expect 512 or 4096; NFR-COMPAT-5).
   - `ioctl(fd, DKIOCGETBLOCKCOUNT, &blockCount)` → `UInt64` (NFR-COMPAT-6).
   - Reconcile against the **helper's own** IOKit reading (`AcquiredDevice.geometry`); prefer the ioctl values. Log both so they can be compared directly.

   > **Amended 2026-08-02, user decision (Step 7 scoping).** The last bullet originally
   > read "Reconcile with the values discovered in **Step 5**; prefer the ioctl values."
   > Step 5's discovery runs in the **app**, on the far side of the trust boundary.
   >
   > Step 6 established that the helper reads the IOKit registry **independently** —
   > `HelperDeviceRegistry.eligibility(of:)` produces `EligibleDevice` with its own
   > `sizeBytes` and `logicalBlockSize` — precisely so a root daemon need not take the
   > app's word for a device's identity or its geometry (NFR-REL-7, BUILD-PLAN Step 3.5).
   > The helper's copy of the registry filters is duplicated from the app's *on purpose*:
   > "a shared filter would mean one bug excusing itself on both sides of the trust
   > boundary" (`DeviceClaim.swift`).
   >
   > Reconciling against a Step 5 value would re-cross the boundary Step 6 deliberately
   > closed, and would make a GUI bug capable of influencing what the helper believes
   > about the device it is about to write to. The comparison is therefore
   > **ioctl vs. helper-IOKit**, and the app is not a party to it.

   > **Note on the ioctl constants (measured 2026-08-02).** `DKIOCGETBLOCKSIZE` and
   > `DKIOCGETBLOCKCOUNT` are **not importable into Swift** — the SDK reports
   > `macro 'DKIOCGETBLOCKSIZE' unavailable: structure not supported`, because they are
   > `_IOR(…)` macros rather than plain integer `#define`s. They must be re-derived in
   > Swift. The derivation was checked against the SDK by compiling C and comparing:
   > `DKIOCGETBLOCKSIZE = 0x40046418`, `DKIOCGETBLOCKCOUNT = 0x40086419`. No C shim or
   > bridging header is required; `ioctl(fd:_:_:)` and `fcntl(fd:_:_:)` are both callable
   > directly from Swift.
4. **Implement read/write** using `pread`/`pwrite` at explicit byte offsets (block-aligned). Treat short transfers and `errno` as `DeviceIOError`. **All offsets/lengths are 64-bit and block-aligned** (NFR-COMPAT-6, NFR-REL-7).
5. **Build the chunk plan (FR-TEST-2/5):**
   - `ioSize` ∈ {1,2,4,8} MiB (default 4) — passed in; fixed for the run (FR-CTRL-8).
   - `blocksPerChunk = ioSize / blockSize`; iterate from block 0 to `blockCount-1`.
   - **Final chunk:** size to **exactly the remaining blocks**, i.e. `remaining = blockCount - offsetBlocks`, length `= remaining * blockSize` — **rounded to the logical block size, never to an arbitrary byte remainder** (FR-TEST-5). (Because the device is an integer number of logical blocks, the final chunk is already a whole number of blocks; the requirement is to never truncate to a sub-block byte count.)
6. **Bounded memory (NFR-PERF-1/2):** allocate exactly **two** buffers of `ioSize` (original-read + verify-read) and reuse them for every chunk — memory must **not** scale with device capacity. Use page-aligned buffers (`valloc`/`posix_memalign`) for raw I/O.

   > **Amended 2026-08-02, user decision (Step 7 scoping): "peak buffer memory ≈ 2×`ioSize`
   > is the correct and final design. I do not want memory to scale with capacity."**
   >
   > The buffers were never the problem — the **chunk plan** was. Step 2's
   > `RetentionTestEngine.chunkPlan()` returns a materialised `[Chunk]`, and `Chunk` has a
   > 40-byte stride (measured). That is memory scaling linearly with capacity, which is
   > exactly what NFR-PERF-2 forbids, and it slipped through because this gate item says
   > "peak **buffer** memory" and the buffers really were bounded:
   >
   > | Device | Blocks (512 B) | Chunks @ 4 MiB | Materialised plan |
   > |---|---|---|---|
   > | scratch device — 1.0 TB | 1,953,525,168 | 238,468 | **9.1 MiB** |
   > | Seagate — 22 TB | 42,970,644,479 | 5,245,440 | **200.1 MiB** |
   >
   > So the requirement is restated here as its true scope: **no run-state structure may
   > scale with device capacity** — not the buffers, not the plan, not anything Steps 8–10
   > add. The plan is therefore produced **lazily**, as a `Sequence` of `Chunk` computed on
   > demand, and the eagerly-materialised array becomes a convenience for tests only.
   >
   > This is a requirement about the *shape* of the design, so it constrains every later
   > step: Step 9's metrics and Step 10's bad-block report must accumulate bounded summaries
   > (counts, min/max/percentile state, coalesced failed ranges), never a per-chunk record.
7. **`os_log`** device open and geometry (NFR-OBS-1) — never log contents (NFR-SEC-6).

### Verification Gate — COMPLETE (2026-08-02)
- [x] Against the **designated scratch device**, geometry (block size, block count, capacity) reads correctly and matches `diskutil info`. *(Amended 2026-08-01: disk images are not an option — see "The test target" below.)* — **`scripts/geometry-check.sh` on the scratch device, 9 PASS / 0 failures:** 512 / 1,953,525,168 / 1,000,204,886,016, matching `diskutil` on all three and matching the helper's independent IOKit reading.
- [x] The chunk plan computed for several sizes (e.g. a device whose block count is **not** a multiple of `blocksPerChunk`) yields a correct final chunk equal to the exact remaining blocks — verified by **unit tests using `InMemoryBlockDevice`** with deliberately awkward sizes, for both 512B and 4096B blocks. — `RetentionTestEngineTests` (7 cases, unchanged since Step 2) plus `ChunkPlanTests` (12), which adds the **real** geometries: the scratch device → 238,468 chunks with a 3,504-block remainder, the Seagate → 5,245,440 chunks with an 8,191-block remainder, the latter verified by full traversal.
- [x] Peak buffer memory == ~2×`ioSize` regardless of device size (instrument and confirm; NFR-PERF-1) — **and no other run-state structure scales with capacity either (NFR-PERF-2)**, the chunk plan included. *(Amended 2026-08-02 — see step 6 above: the original wording said "buffer memory", which a 200 MiB materialised plan for a 22 TB device would have passed.)* — `ChunkBuffers` cannot scale because capacity is not one of its inputs; `peakAllocatedBytes` instrumented and asserted flat across a 1,000-chunk loop; the plan is now a lazily-computed `Sequence`, proved by an 18-exabyte plan (4.4 trillion chunks, ~176 TB if materialised) that is fully usable.
- [x] `F_NOCACHE`/`F_GLOBAL_NOCACHE` are set — **both `fcntl` calls checked, and the acquire fails if either does not return 0.** — hardware: `CACHE_BYPASS=1`.
- [x] **The cache-bypass self-check exists and works (FR-TEST-9).** `scripts/nocache-calibration.sh` has established, on real hardware, whether re-read timing can discriminate F_NOCACHE off from on, and the classifier's thresholds are the measured numbers. If the calibration shows the comparison **cannot** discriminate, that is recorded as the finding and the check reports `inconclusive` — it is **not** allowed to report `bypassed` on evidence that would say `bypassed` regardless. *(Added 2026-08-02. The original wording — "verified by code path / no cache-hit behavior on re-read timing" — accepted a code path as sufficient; `fcntl(F_NOCACHE)` returning 0 on `/dev/null` is why that is not.)*

      **Result: the calibration showed re-read timing CANNOT discriminate**, so the mechanism
      was rebuilt rather than the finding rationalised away. `bypassed` now rests on a
      structural fact — `fstat` proving the descriptor is the **character** device, which
      catches opening `/dev/diskN` by mistake — and timing is retained only as a *falsifier*,
      against a ceiling derived from the negotiated USB link speed (1.333 GB/s for the scratch device,
      against the 0.475 GB/s it delivers). Timing can falsify; it cannot verify.

- [x] **NFR-COMPAT-6 on hardware that can actually test it.** *(Added to this gate 2026-08-02 by user instruction: verify it on the Seagate before Step 8 begins. It was previously recorded here as a known limit carried forward.)* Nothing run on the scratch device can discharge this — at 1,953,525,168 blocks it is below 2³², where a bridge truncating its count to 32 bits is indistinguishable from a correct one, and the failure is silent: the tool would test the first portion of a larger drive and report a clean pass.

      **`scripts/large-address-check.sh` passes 10/10 on the Seagate.** `DKIOCGETBLOCKCOUNT` returns
      **42,970,644,479** — not the 20,971,519 (10.7 GB instead of 22 TB) a truncation would
      give. Reads succeed at block 0, at 2³²−1, at **2³²**, at 2³²+10⁶, and at the last block
      (42,970,644,478). A read one block **past** the end is refused. The last block is
      **distinct** from its 32-bit-wrapped twin (20,971,518), with neither all-zero.

      Succeeding at the final block *and* being refused one past it brackets the device
      exactly, which is only possible if 64-bit addressing holds end to end — a truncated size
      or wrapped addressing would have made the past-the-end read land on a valid low block
      and succeed.

      **Run read-only, with nothing unmounted.** The Seagate is not the expendable scratch device
      — it carries a live HFS volume — so `tools/large-address-probe` departs from
      `DeviceClaim`'s flags deliberately and opens `O_RDONLY` with no `O_EXLOCK`: the
      descriptor cannot write, no volume has to be disturbed, and with no exclusive lock there
      is no release to trigger DiskArbitration's remount. The script **refuses the scratch device** for
      being at or below 2³², so it cannot be pointed at hardware that would pass it vacuously.

### The test target (amended 2026-08-01, user decision)

**All real-hardware I/O testing uses the scratch device** — the Samsung Portable SSD T5, serial `12345686DAA9`, 1 TB, 512-byte
blocks, one exFAT volume `Test_Drive`. It holds only expendable test files. **Disk images
are not used and are not supported as a test target.**

Two reasons, one practical and one deliberate:

1. **They do not work.** Discovery lists USB mass-storage whole disks only, and an attached
   disk image reports `Physical Interconnect == "Virtual Interface"` (measured, Step 5). It
   never appears in the device list, so it cannot be selected, and the helper's own
   independent identity re-check (Step 6) would refuse it as ineligible even if it were.
   The original wording here — "or a disk image attached as a raw device for safety" —
   could not have been followed.
2. **They would be the wrong kind of safe.** This project's recurring defect is a
   substitute standing in for the real thing: a disk image that exercised a notification
   path but had no filesystem, an APFS drive that masked a bug the exFAT drive exposed, an
   incremental build that hid warnings, three `open(2)` flag combinations that reported a
   permission as granted when it was not. A disk image has no USB bridge, no real block
   device, and no NAND — exactly the layers this tool exists to exercise.

**What does *not* change:** the drive being expendable relaxes the *consequence* of a bug,
not the discipline. NFR-REL-1 still requires non-destructiveness to be **proven in
simulation first** (Step 8's gate), and the engine must still write back the bytes it read
rather than any pattern (FR-TEST-7). "We can afford to lose this data" is not a licence to
skip the in-memory proof; it is what makes the hardware run survivable when the proof
misses something.

### Risks / gotchas
- **All destructive testing goes on the designated scratch device** (serial `12345686DAA9`). Even though the algorithm is non-destructive, bugs in this step write to raw blocks. Never the drive holding the source tree, and never the Seagate. The scripts enforce this by serial; they no longer accept a BSD name as an identity.
- Raw devices reject misaligned offsets/lengths with `EINVAL` — alignment is not optional.
- Some USB bridges report odd geometry; trust the ioctl and reject impossible values.
- **The helper needs Full Disk Access** (NFR-INST-4, added 2026-08-01) or the raw open fails `EPERM`. Running as root is not sufficient.
- **Releasing an `O_EXLOCK` open or a `DADiskClaim` makes macOS remount the volume within milliseconds** (measured). Any code that opens and closes the raw device outside a held acquire will undo the user's unmount.

---

## Step 8 — read → write-back → read-verify cycle

**Original action item:** AI-6
**Satisfies:** FR-TEST-1/3/4/7/8; FR-FAIL-6/7; NFR-REL-1/2/4/8
**Trust boundary:** **helper-side core** (runs identically against the simulated device).

### Objective
Implement the heart of the tool: for each chunk, read original → write the *same* bytes back → read again into a second buffer → compare. Bit-for-bit non-destructive, one chunk in flight, no journaling, no resume.

### Detailed steps
1. **Per-chunk cycle (FR-TEST-3):**
   - `read` original chunk into buffer A at the chunk's offset.
   - `write` **buffer A unchanged** back to the same offset (FR-TEST-7 — never patterns/known values).
   - `read` the just-written data into buffer B.
   - **compare A vs B** byte-for-byte; any single-bit difference is a verify failure (NFR-REL-8, FR-TEST-8).
2. **Sequential whole-device traversal (FR-TEST-1/4):** first addressable block → last, in order, using the Step 7 chunk plan.
3. **Failure classification (FR-FAIL-6):** a chunk fails if the read errors, the write errors, **or** the verify mismatches. Produce a `BlockRangeFailure { startBlock, blockCount, kind }`. (How the run *reacts* to a failure — halt vs. continue — is Step 10; this step only **detects and classifies**.)
4. **No journaling / one-chunk-in-flight (FR-FAIL-7, NFR-REL-4):** never hold more than the current chunk's original data (in buffer A). The in-flight data-loss window is bounded to exactly the chunk being written.
5. **No resume (FR-FAIL-7):** if interrupted, the engine reports and the run is over — there is no checkpoint to resume from. (Restart-from-beginning is wired in Step 11.)
6. **Clean termination contract (NFR-REL-5):** on stop/error, issue no further writes and leave buffers/state consistent for the caller to release the device.
7. **`os_log`** run start, and each failed block range (NFR-OBS-1) — never the data itself (NFR-SEC-6).
8. **Carry the cache-bypass verdict into the run (FR-TEST-9, added 2026-08-02; amended 2026-08-02).** A `likelyCached` or `inconclusive` verdict **qualifies the verify result — it does not stop the run**: a cached *read* does not prevent the write-back reaching the device, so the retention refresh remains valid and only fault detection becomes unreliable. Blocking here would withhold a working feature to protect a broken one. The verdict travels with the run into Step 10's report.

   > **Amended 2026-08-02 (Step 8 scoping).** This step originally said to *"call the Step 7 mechanism"* before the first chunk. **There is nothing to call.** FR-TEST-9's check is performed at **acquire**, inside `DeviceClaim`, and its verdict is already on `AcquiredDevice.cacheBypass` before Step 8 gets control. Step 8 **seeds** a `CacheBypassAssessment` from that verdict plus `AcquiredDevice.usbLinkSpeed`, then feeds each read's throughput in via `observe(bytes:nanoseconds:)`, which can only ever downgrade it.
   >
   > This is not a shortcut. The check is `fstat` plus the two `fcntl` results **on the descriptor**, and Step 7 measured that opening the raw node speculatively to answer a query makes DiskArbitration remount the volume ~4 ms later — so a second, run-start check would be actively harmful. It is sound because the acquire holds that same descriptor continuously between the check and the run: **performed at acquire, consumed at run start.**
   >
   > **Both reads are fed to the falsifier, and the verify read is the load-bearing one** — it is the read a host cache would answer, so feeding only the original read would systematically miss the very signal FR-TEST-9 exists to catch.

9. **The bounded-range run and its cap (added 2026-08-02, user decision).** `ChunkPlan` carries a `startBlock`, so a run over part of a device is expressed as **the plan the engine is given** rather than as an early stop — the engine keeps its single behaviour, *complete the plan you were given*, and a bounded run therefore finishes as a completed run. A whole-device run (`startBlock = 0`, the whole block count) remains the default and is what FR-TEST-1/4 requires.

   The XPC method is **capped at 1 GiB per call**. There is no cancellation until Step 11 and no progress channel until Step 9, so an uncancellable privileged operation that any caller can start must be bounded by construction — otherwise a root daemon can be wedged for hours with `prepareForShutdown` correctly refusing throughout.

10. **A failed read must never be followed by a write (added 2026-08-02).** The buffers are reused, so if a chunk's original read fails and control falls through, buffer A still holds the **previous** chunk's data and the engine would write it to this chunk's offset — silent, permanent corruption of a region the tool was asked to preserve, on a drive whose every other block verifies clean. The read step returns a `LoadedChunk` token, produced only on a successful read, and the write step takes that token, so no path from a failed read to a write is expressible. Likewise a **failed write ends the chunk**: reading back after a failed write compares buffer A against the *old* data and reports a spurious verify mismatch on a chunk whose actual fault was the write.

11. **Failures are coalesced and bounded (NFR-PERF-2, added 2026-08-02).** An unbounded `[BlockRangeFailure]` would reintroduce the capacity-scaling growth Step 7 removed from the chunk plan. Failures are coalesced on append (same kind, contiguous blocks) and the retained list is capped, with the total count and a `truncated` flag carried separately — **reported, never silent.**

### Verification Gate — COMPLETE (2026-08-03)
- [x] **Non-destructiveness proven in simulation (NFR-REL-1):** fill an `InMemoryBlockDevice` with known random data, run the full cycle over the whole device, assert the backing store is **bit-for-bit identical** afterward.
- [x] **Verify-mismatch detection (NFR-REL-8):** with write-corruption fault injection on a specific block range, the engine flags exactly that range as a verify failure and no other.
- [x] **Hard-error classification (FR-FAIL-6):** with read-error and write-error fault injection, the engine produces correctly-typed `BlockRangeFailure`s for the injected ranges.
- [x] **One-chunk-in-flight (NFR-REL-4):** instrumentation confirms only one chunk's worth of original data is ever held. *(Amended 2026-08-02: `ChunkBuffers.peakAllocatedBytes` from Step 7 already covers the **buffer** half and is not sufficient on its own — it cannot see a second chunk's original being held, or per-chunk state accumulating beside bounded buffers, which is what NFR-REL-4 actually names. The gate additionally requires an **ordering** proof over the recorded device operations, and — per this project's standing rule — the checker must first be shown capable of **failing** against hand-built bad sequences.)*
- [x] **A failed read leaves the device untouched (added 2026-08-02):** with a read fault injected on one chunk, the backing store at that chunk's offset is unchanged — not merely that a failure was recorded. This is the stale-buffer hazard of step 10 above.
- [x] The cycle also runs against the **designated scratch device** and leaves its contents unchanged. **Only after the simulation proof passes.** *(Amended 2026-08-01: disk images are not a test target — see Step 7, "The test target". The drive's data is expendable, which is what makes this survivable if the simulation proof missed something — it is not a reason to run it before that proof passes.)*

  > **Amended 2026-08-02, user decision.** "End-to-end" is bounded, and "checksum before == after" is made specific:
  >
  > - **One run of 1 GiB − 512 KiB (2,096,128 blocks)**, starting at a **random** LBA that is a multiple of **8,192** — one 4 MiB chunk at 512-byte geometry, so the gate writes at the offsets a real whole-device run would use — and at least 1 GiB before the logical end of the drive. Random placement spreads NAND wear across repeated gate runs; the end-of-drive margin keeps the run clear of the device boundary. 3 GiB of I/O (R+W+R), under ~15 s at the 200 MiB/s floor and ≈6.8 s at the scratch device's measured 475 MB/s. The start LBA is chosen by the **script**, not the helper, and is printed and recorded so a failure can be re-run in the same place. On the scratch device that is one of **238,212** positions, 0 through 1,951,424,512; block 0 is a legal draw, so a run may land on the GPT — deliberate, and the only live case for the "torn write bricks the drive" risk below.
  > - **The range is deliberately not a whole multiple of the I/O size.** 1 GiB divides by 4 MiB exactly, so a full 1 GiB run would contain no short final chunk; shortening it by 512 KiB yields 255 full chunks plus a final chunk of 7,168 blocks, which exercises FR-TEST-5's `original(byteCount:)` / `verify(byteCount:)` path — and whether the bridge accepts a **write** shorter than the I/O size — on real media, at no cost.
  > - **Not discharged by this gate, and not to be mistaken for covered:** the final chunk at the **physical end** of the device, and the whole-device traversal. Neither is reachable under the clear-of-the-end rule; both belong to a later, separately agreed run, following the Seagate precedent.
  > - **The evidence is a per-1-GiB SHA-256 vector plus a whole-device digest, taken twice, both inside the claim window.** The vector costs the same I/O as a scalar digest and localises any difference to a 1 GiB window rather than merely asserting one exists. Both digests must be taken while the helper still holds the claim: releasing makes DiskArbitration remount ~4 ms later, and a mounted exFAT volume writes to itself, so an "after" digest taken post-release would differ for reasons unrelated to this tool.
  > - **The digest tool is built and run before the gate design commits to it**, because it must first settle a fact this project has not measured: whether a second process can `open("/dev/rdiskN", O_RDONLY)` while the helper holds `O_EXLOCK`. The 2026-07-30 matrix records that two plain `O_RDWR` opens both succeed and that a second `O_EXLOCK` is refused — but not that combination, and the digest ordering above rests on it.
  >
  > **DISCHARGED 2026-08-03.** `./scripts/retention-cycle-check.sh` on the scratch device, placement block
  > **277,372,928**, 15 checks / 0 failures. The whole device was fingerprinted before and after
  > — **932 windows, 1,000,204,886,016 bytes, exactly the device's reported size** — and the two
  > vectors are byte-identical. Verified independently of the script afterwards: **0 of 932
  > windows are all-zero**, and **932 of 932 fingerprints are distinct**, so a stray write
  > anywhere on the drive would have changed a window. The run's own numbers:
  > `COMPLETED=1`, `CHUNKS=256`, `FAILED_RANGES=0`, `CACHE_BYPASS=1`,
  > `FASTEST_BYTES_PER_SECOND=492,870,060`, `BUFFER_BYTES=8,388,608`.
  >
  > **CORRECTED 2026-08-02, on hardware.** That fact was measured, and the answer is **no**: with the helper holding `O_EXLOCK`, a root process carrying Terminal's Full Disk Access grant and requesting **no lock at all** is refused `EBUSY`. So "taken by a separate process while the helper still holds the claim" is impossible, and the two bullets above are wrong as written. **Both fingerprints must be taken by the helper, through its own descriptor.** The pre-flight existed precisely to catch this before the design was committed to; assuming it would have produced a gate that failed at the "after" fingerprint, ~40 minutes in, immediately after the first write this project ever made to real media — with no way to distinguish a digest that could not be taken from a device that had been changed.
- [x] **The run's cache-bypass verdict survives real I/O (FR-TEST-9):** on the scratch device the assessment is still `bypassed` at the end of the run, and the fastest observed read is transport-plausible (~475 MB/s), not RAM-plausible (71.3 GB/s measured on this machine).

### Risks / gotchas
- A torn write to GPT/superblocks can brick an otherwise-good drive (per the brief) — this is exactly why the simulation-first verification above is mandatory before trusting hardware.
- Ensure the write of buffer A truly precedes the verify read, and that nothing can answer the verify read without the device.

  > **Amended 2026-08-02.** This bullet used to end *"(Step 7's `F_NOCACHE` is what makes the verify meaningful)"*. **Step 7 measured that this is false.** `/dev/rdiskN` is the **character** device, the unified buffer cache belongs to the **block** node (`/dev/diskN`), and `F_NOCACHE` therefore had nothing to suppress — with it unset, repeated reads took ~8.8 ms, identical to with it set, while a 4 MiB copy from RAM takes 58 µs. What makes the verify meaningful is that the descriptor **is** the character device, which is why FR-TEST-9's check became structural (`fstat` → `S_ISCHR`) with timing retained only as a falsifier. Left as written, this line points the next reader at the wrong mechanism and would justify re-proposing the timing check the calibration probe already killed.
- **`chunkPlan()` must not appear in the run path or in any many-chunk test** — it is the materialised plan (9.1 MiB for the scratch device, 200.1 MiB for the Seagate) that NFR-PERF-2 forbids. A run iterates `chunks()`. Stated because `chunkPlan()` is still the more convenient API and the Step 2 tests use it.
- **The simulated device must be filled from a seeded PRNG keyed by block index**, so a mis-addressed write is detectable by content. Uniform random is not enough, and an all-zero or repeating fill would let a wrong-offset write pass — the same family of vacuity as a verify that compares a buffer with itself.

---

## Step 9 — Metrics: throughput + read-latency (min/max/p99) with live monitoring

**Original action item:** AI-8
**Satisfies:** FR-METR-1/2/3/4/5/6; NFR-PERF-3/4/5/6/7, NFR-USE-1/2
**Trust boundary:** measured **helper-side**, displayed **GUI-side** — by the GUI **polling**
`runProgress` on a **second XPC connection**, not by a helper→GUI callback. Measured 2026-08-04:
a second message on a connection with a blocking call in flight is not delivered until that call
returns, while a second connection is answered in 0.2–0.3 ms. See detailed step 4.

### Objective
Measure average read and write throughput and per-chunk read latency (min/max/p99), and surface progress + a measured-throughput ETA live in the GUI, refreshing at least once per second, all with negligible overhead and constant memory.

### Detailed steps
1. **Throughput (FR-METR-1):** accumulate bytes read and bytes written and elapsed time; report running averages (MB/s). Use a monotonic clock.
2. **Read latency per chunk (FR-METR-3):** time each original read. Maintain **min**, **max**, and a **p99** using a **constant-memory** method (fixed-bucket histogram or a streaming/approximate percentile such as t-digest) — must **not** store per-chunk samples (NFR-PERF-7).
3. **Progress + ETA (FR-METR-5/6):** percent complete and current block offset; ETA = remaining bytes ÷ measured average throughput, **updated continuously** and converging over time (NFR-PERF-6). Never assume a fixed link speed (NFR-COMPAT-7).
4. **Live push to GUI (FR-METR-2/4, NFR-PERF-5):** helper sends a metrics snapshot to the GUI over the XPC progress callback **at least once per second**. Keep the per-chunk measurement overhead negligible relative to device I/O (NFR-PERF-3).

   > **Measured 2026-08-04, before this step was written, and it constrains the mechanism.**
   > `scripts/xpc-concurrency-check.sh`, 0 failures on the scratch device. Read-only: the long call underneath
   > the probe is `digestRange`, not `runRetentionCycle`.
   >
   > While the helper is inside a blocking privileged call, **a second message on that same
   > connection is not delivered until the call returns.** Twenty-four pings issued at 100 ms
   > intervals during a 2,827.9 ms digest were all answered between 2,828.0 and 2,828.5 ms —
   > the queue draining in ~0.6 ms *after* the call finished. **A second connection was
   > answered concurrently throughout, in 0.2–0.3 ms.**
   >
   > So the daemon is not blocked; the connection is. Three mechanisms follow, and the
   > difference between them is what has been measured:
   >
   > * **poll on the run's own connection** — ruled out by the above. It cannot work.
   > * **push on the run's own connection** — what this step originally assumed. Needs a
   >   reverse `@objc` protocol, an exported object on the *app* side, and the helper calling
   >   back one-way (no reply block) from a 1 Hz timer on its own queue, never from the I/O
   >   loop. **Rests on a further unmeasured assumption**: that an outbound send succeeds on a
   >   connection whose inbound queue is blocked.
   > * **poll on a second connection** — measured working, today, with no assumption left over.
   >   One additive query method; no reverse protocol; no new inbound surface on the app; the
   >   helper never initiates traffic to a client; and the GUI owns the ≥1/s cadence, so
   >   NFR-PERF-5 is satisfied by the GUI's own timer rather than by the daemon.
   >
   > **Decided 2026-08-04, user decision: poll on a second connection.** The wording of this
   > step ("the helper sends") anticipated the push and is superseded — it was written before
   > the delivery behaviour was known. The deciding argument is that it is the only one of the
   > three that rests on no unmeasured assumption; push would still require establishing that
   > an outbound send succeeds on a connection whose inbound queue is blocked, which is
   > precisely the kind of plausible-sounding claim this pre-flight had just falsified once.
   >
   > The second connection is **non-owning**: it never calls `acquireDevice`, so
   > `HelperActivity.releaseIfOwned(by:)` means its death releases nothing (NFR-REL-5). Both
   > connections live inside the app's single `HelperConnection`, which was hoisted to one
   > shared instance in Step 6 precisely so the device has one owner.
5. **UI responsiveness (NFR-PERF-4):** all heavy work is in the helper / off the main thread; the GUI only renders snapshots. Format values human-readably with clear units — MB/s, ms (NFR-USE-1) — and show percent/position/ETA clearly (NFR-USE-2).

5a. **Measure the helper's CPU cost per unit of throughput (NFR-PERF-3, added 2026-08-02, user observation).** NFR-PERF-3 requires the run to be *device-bound, not host-bound*, and nothing has ever put a number on it. Record helper CPU as a percentage of one core against the measured MB/s, so the ratio can be extrapolated to faster transports.

   > **Why this arrived now.** During Step 8's hardware gate the user observed the helper at **36–39% of one core on an M4 Mac Mini at ~500 MB/s**. That figure is the *gate's* SHA-256 fingerprint (`Core/DeviceDigest`), which exists only to prove the cycle moved nothing and is **not in the product's run path** — but the observation generalises: linear extrapolation puts SHA-256 at one full core near **1.3 GB/s**, which a USB4 enclosure can reach.
   >
   > The **cycle's** own per-chunk cost is a `memcmp` of the chunk (the block-by-block walk is paid only on mismatch), expected to be far cheaper — order 40–80 µs against ~25 ms of I/O at 500 MB/s. **Expected, not measured.** That is exactly the kind of assumption this project has been burned by, and NFR-PERF-3 is the requirement that says it must not be assumed.
6. **Carry metrics into the report:** expose the final throughput and latency stats so Step 10's report can include them.

### Verification Gate — COMPLETE (2026-08-05)
- [x] During a (simulated or real) run, the GUI shows read & write throughput, read-latency min/max/p99, percent complete, current position, and ETA, all **refreshing ≥ once per second**. — `metrics-check.sh` **0 failures** on the scratch device: 13–14 snapshots per run arrived **while the privileged call was blocking**, widest gap **505 ms** against the 1000 ms requirement, at all four I/O sizes. User confirmed the GUI panel and progress display on 2026-08-05.
- [x] p99/min/max computed with **constant memory** — verified by running a very large simulated device and confirming no per-chunk sample growth. — Discharged **structurally plus by test**, not by running a large device: see conflict 4 below. `LatencyHistogram.init()` takes no parameters, so capacity cannot reach it; `LatencyHistogramTests` drives **5,245,440** observations (more than the Seagate has chunks) and asserts the bucket array is unchanged at 2,240 entries / 17,920 bytes.
- [x] ETA converges toward actual remaining time as the run progresses (observed on a long-enough run). — Discharged by a **synthetic run with a known true remaining time** (`RunMetricsTests`): 100 chunks whose rate changes partway, error **1200 → 450 → 200 → 75 → 3.03 ms**. Observed on real media too, converging to 0.1 s over a 7 s run. The multi-hour observation the wording implies is **not dischargeable** under the 1 GiB cap — see conflict 2.
- [x] GUI stays responsive (scroll/interact) throughout (NFR-PERF-4). — **User-observed on hardware 2026-08-05**, across two live bounded cycles against the scratch device with the v8 daemon. Exercised: scrolling the selected-device detail and the device list, drag-selecting a throughput value, dragging and resizing the main window, holding a menu open, and switching focus between both windows. **No stalls, no beachball, clean redraws** — and, the part only interaction can settle, **the metrics kept advancing *during* those gestures**. That last property is not implied by the off-main-thread structure: the 1 Hz timer is published on the `.common` run-loop mode, so it survives AppKit's tracking loops; on `.default` the run would have been fine while the display froze every time the user touched the window, which is the failure mode this item exists to catch and which nothing renderable or scriptable can see.
- [x] Latency p99 from a controlled fault-injection (artificially slow reads on some chunks) reflects the injected slow tail. — Injected as **duration** through the already-injected `MonotonicClock`, not as a fault: `InMemoryBlockDevice`'s injection produces errors, not latency, and a failed read is not a read latency at all. `p99ExcludesTheFastPopulationEntirely` requires the interval to exclude the fast population outright, so it distinguishes rather than merely brackets.
- [x] **Helper CPU is recorded against measured throughput (NFR-PERF-3, added 2026-08-02)**, as a percentage of one core at a stated MB/s, on the designated scratch device. The run must be shown device-bound rather than host-bound — and if the ratio implies the host becomes the limit at a transport speed the product plausibly meets, that is a **release-note item**, carried to Step 16. — At the 4 MiB default with the device moving ~470 MB/s: in-span host overhead **2.55%** of device I/O time, daemon CPU **4.22% of one core**, independently cross-checked by a `ps` sampler peaking at 8.5%. The run is **97.4% device-bound**. **The release-note condition IS met** and is recorded in Step 16, detailed step 7.

Also discharged, and not asked for by the wording above:
- [x] **FR-TEST-10 shown *refusing*.** A run that satisfies a placement rule proves only that the rule did not get in the way. A start at block 1 and a length one block short of a whole MiB were both refused with **zero chunks processed**.
- [x] **NFR-PERF-1 at every I/O size:** buffers held exactly 2 × the I/O size for 1, 2, 4 and 8 MiB.
- [x] **The engine's rewritten loop is still non-destructive on real media.** `retention-cycle-check.sh` **15/15** on the scratch device, all **932** whole-device window fingerprints unchanged after writing 1,072,693,248 bytes (NFR-REL-1).

### UI work folded into this step after the gate (2026-08-05, user decision)

With the gate passed, the user reviewed the running app and raised a series of UI defects and one
product-design change. Asked whether to commit Step 9 first or fold the work in, the user chose
**fold in** — so Step 9's commit covers the metrics work *and* this. The full record is in
`progress/step-09.md`, "the UI work folded in after the gate"; what follows is what the plan needs.

**Delivered, in five increments.** A `ui-probe` view that had silently rendered the wrong state
since it was written; the device list focused on launch, with its Refresh button removed; merged
panes, deselection that auto-releases, a selection frozen during a run, and **drives identified by
USB serial number**; the main scene changed from `WindowGroup` to **`Window`**; and a
**quit/close confirmation** with a wind-down that stops at the call boundary.

**Verification.** **551 tests, 0 failures, 65 suites** (was 497 at the gate, 516 before the last
increment). **Zero source warnings from all three clean builds** — `build.sh Debug`,
`build.sh Release`, `test.sh`, DerivedData wiped before each. Five deliberate mutations of the quit
logic, **all five caught**, including the two paths no amount of clicking can reach. The hardware
gates above are unchanged and were not re-run, verified rather than assumed: **no helper, `Core/`
or `Shared/` file has been touched** by any of this work.

**Two requirements-level consequences**, both recorded in the FR document's 2026-08-05 amendment:
**FR-SAFE-5 withdrawn, FR-SAFE-6 reversed, FR-SAFE-7 moot** — the work itself belongs to Step 11
and is gated on Step 14, and is **not** brought forward into this step.

- [x] **NFR-PERF-4, re-checked against the post-UI-work binary.** Increments 3 and 4 change the
  window layer, which is what that requirement is about, so the earlier user observation did not
  carry over. **Re-checked and passed, user-observed 2026-08-06** on the installed Release build
  with the helper re-registered from `/Applications` and confirmed by Check version: a live
  bounded cycle over the scratch device while scrolling, drag-selecting a value, resizing the
  window, holding a menu open and switching windows — with the metrics still **advancing during**
  those gestures, which is the part only interaction can settle.
- [x] **The confirmation dialog observed in the product.** A SwiftUI `alert` is presented in its own
  window, so `ui-probe` cannot capture it. **User-observed 2026-08-06**, both entry points: ⌘Q and
  the main window's close button raise the same dialog on the main window (bringing it forward from
  the diagnostics window), *Continue Testing* leaves everything as it was, the bounded-cycle control
  is disabled with its corrective note while a quit is pending, and *Cancel and Quit* quits. Also
  confirmed: **`File ▸ New Window` and ⌘W are gone**, and the Window menu reopens a closed main
  window — the behaviour the scene probe predicted, now seen in the product.

> The two items above are recorded as the user reported them. **No figures are claimed for them
> here**, because none were re-measured: they are observations of behaviour, and the numbers in
> this gate come from `metrics-check.sh`.

### Risks / gotchas
- Don't let metrics formatting/IPC dominate per-chunk time — batch/throttle the once-per-second push rather than sending per chunk.
- Approximate-percentile error is acceptable (the spec says "e.g., p99"); document the method chosen.
- **Progress freezes on a failing drive unless an observer event is added (found 2026-08-04).** A chunk whose read, write, or verify-read *hard-errors* never reaches `observer?.chunkCompleted(...)` — all three `catch` blocks `continue` past it. (A verify *mismatch* does still emit, having completed all three phases.) An observer-based accumulator would therefore stall its chunk counter while the engine walks on: percent complete frozen, ETA running away, throughput reading low, on exactly the drive this tool exists to find. `failureDetected` cannot fill the gap — it carries no timing and can fire many times per chunk — and on a hard read error there is no timing at all, because `readNanoseconds` is computed *after* the read, on the success path only.
- **A "very large simulated device" cannot show constant memory, and would be the wrong evidence.** `InMemoryBlockDevice` allocates its whole backing store, so "very large" is bounded by RAM; and a genuinely large traversal is bounded by *time* — the Seagate's geometry is 5,245,440 chunks, i.e. ~21 TB of `memcmp` even at RAM speed. Constant memory is shown the way `ChunkBuffers` shows it: **structurally**, by there being no input through which capacity could reach the accumulator, plus a direct test driving millions of observations into it. Running a big device would be the weaker claim wearing the bigger costume — the same trap Step 2's "peak *buffer* memory" wording set.
- **`InMemoryBlockDevice`'s fault injection produces errors, not latency.** The slow tail the gate asks for has to be injected as **duration**, through the already-injected `MonotonicClock` — which is also the real thing for a statistic that is pure arithmetic over durations, and is deterministic rather than sleep-flaky.
- **The ETA denominator is not the read rate.** A cycle moves 3× the range (read + write + verify), so ETA must divide remaining *range* bytes by *range bytes covered ÷ wall elapsed*. Using read throughput would make every ETA about three times too optimistic. Read and write throughput (FR-METR-1) are separate figures — `bytesRead ÷ time-spent-reading` and `bytesWritten ÷ time-spent-writing`. Three distinct rates that are easy to collapse into one wrong one.
- **Do not measure the overhead with an unpinned clock.** NFR-PERF-3's ratio is measured with `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)`, the same call being timed around. Its own cost must be pinned first, or the measurement partly measures itself.

### Conflicts between this step's original text and what Steps 7–8 established (recorded 2026-08-04)

Recorded rather than silently edited, so the delta from the plan as written is auditable.

1. **"During a (simulated or real) run, the GUI shows …" presumes a GUI that can start a run.** It cannot: `HelperConnection` has no `runRetentionCycle`, and the only caller in the project is `tools/mount-guard-client`. Even if the CLI started one, a progress callback would land on the CLI's connection. So this step must add a GUI-side trigger — which collides with Step 8's own note that the bounded call "is deliberately **not** enough to serve as a substitute for the run-control machinery". Resolved by D2: the metrics **panel** is product surface and goes in the main window; the **trigger** is scaffolding and Step 11 deletes it. (It went into the diagnostics **window** — that panel moved out of the main window on 2026-08-04.)
2. **"ETA converges … observed on a long-enough run" is unreachable under the 1 GiB cap, which this step must not lift.** 1 GiB at the scratch device's measured 475–505 MB/s is **~6.5–7 s**, i.e. about six refreshes. Convergence is therefore proven in unit tests over a synthetic run with a known true remaining time, and *observed* on the real bounded run. A multi-hour convergence observation is **not discharged** and belongs to Step 11.
3. **A run is one call, so this step's progress and ETA are per-call, not per-device.** That is not what FR-METR-5 means by "test progress". Whole-device progress and ETA are Step 11's, and are recorded as not discharged.
4. **The gate's CPU item and NFR-PERF-3's own wording are two different numbers.** The requirement states a ratio of *per-chunk compare + metrics + bookkeeping* to the *wall-clock of the I/O* — directly measurable in the product's own run path. Step 5a asks for CPU as a percentage of one core at a stated MB/s, which is the extrapolation figure for the release note. **Both** are measured; measuring only the second would leave the requirement's own claim unnumbered.

---

## Step 10 — Failure modes + end-of-run bad-block report + Markdown export

> **Scoping decisions, 2026-08-06 (user), taken before any code was written.** Full record in
> `progress/step-10.md`.
>
> 1. **The final figures come back in `runRetentionCycle`'s own reply — protocol v9.** They are
>    not there today (see the correction below), and the alternative was to poll `runProgress`
>    after the cycle returned. Chosen because `MetricsChannel.begin()` runs *after* validation, so
>    a **refused** run leaves the previous run's figures installed in the slot — and a report
>    assembled from a post-reply poll would export the wrong run's throughput and latency, in the
>    one artefact that outlives the session. The version was bumping for the failure mode anyway;
>    this removes the hazard by construction instead of detecting it.
> 2. **"Stopped by user" is deferred to Step 11** — see the amended gate below.
> 3. **The report gets its own `Window` scene**, like the diagnostics window: opened when a run
>    ends, reopenable from the Window menu, and — the deciding reason — **renderable by
>    `tools/ui-probe`**, where a sheet or an alert is not (a SwiftUI `alert` gets its own window;
>    Step 9's quit confirmation always needed a person). The cost is a third automatic Window-menu
>    entry beside the known cosmetic duplicate.
>
> **A correction to what Step 9 handed over.** Step 9's closing notes say *"final throughput and
> latency are on the wire already — `runRetentionCycle`'s reply carries them"*. **They are not in
> that reply.** Verified 2026-08-06 against `TesterControl.swift` and the helper's `main.swift`:
> the reply carries `completed, chunksProcessed, failedRangeCount, failureSummary, cacheBypassCode,
> fastestObservedBytesPerSecond, bufferBytesHeld, hostOverheadFraction, helperCoreFraction,
> message`. The one rate in it is FR-TEST-9's falsifier figure — the *fastest observed read*, not
> an average — and the app discards it. The final throughput and latency are reachable, but on
> `runProgress`, which returns the last run's completed snapshot after the cycle ends. Decision 1
> is what that correction produced.
>
> **Two things settled by checking rather than by reasoning, and they constrain the work.**
> `failureSummary` **stays** in the reply: `metrics-check.sh` and `retention-cycle-check.sh` parse
> `FAILURE_SUMMARY` / `FAILED_RANGES` out of `tools/mount-guard-client` and `tools/metrics-probe`,
> and three tools call `runRetentionCycle` — all three must be updated with the signature. And the
> new **wire vocabulary goes into `Shared/TesterControl.swift`** rather than a new `Shared/` file:
> seven scripts name that one file as a single `SHARED=` in their standalone `swiftc` lines, so a
> second file would mean editing all seven *and* a helper-target membership tick. Core keeps the
> domain types, Shared keeps the wire mirrors, pinned by a test — the existing
> `DeviceAccessRefusal.causeCode` pattern. The one genuinely two-sided thing, the failed-range
> codec, lives in Shared as a **single** implementation, because the helper encodes and the app
> decodes.

**Original action item:** AI-7
**Satisfies:** FR-FAIL-1/2/3/4/5; FR-RPT-1/2/3/4/5; NFR-USE-7
**Trust boundary:** mode logic **helper-side**; report assembly/export **GUI-side**.

### Objective
React to classified failures per the user-selected mode, and conclude every run with a structured report — bad-block ranges + throughput + latency + outcome — exportable to Markdown.

### Detailed steps
0. **The cycle's reply names the mode the run actually used** (added 2026-08-06, during increment
   2). Not cosmetic: `RunCoordinator` is not in the test target, so "the deciding observer is
   installed in the shipped run path" is otherwise a code-level inference — and on a healthy drive
   there is no failure to not-stop on, so nothing would reveal it. Echoing the mode back is the
   only evidence available without a bad drive. The report prints it (detailed step 3), and a
   hardware gate asserts it.
1. **Two modes, chosen before the run (FR-FAIL-1, default = log-and-continue FR-FAIL-4):**
   - **Stop on first error (FR-FAIL-2):** on the first hard I/O failure (or verify mismatch), halt immediately and report the offending range. (No resume — restart from the beginning, FR-FAIL-7.)
   - **Log and continue (FR-FAIL-3):** append the offending range to a bad-block list and keep refreshing the rest of the device.
2. **Both modes end with a report (FR-FAIL-5, FR-RPT-1):** list **every** failed block range (hard error or verify mismatch).
3. **Report contents:**
   - Bad-block ranges (start block, length, kind) (FR-RPT-1).
   - Average read/write throughput (FR-RPT-2) and read-latency min/max/p99 (FR-RPT-3) — from Step 9.
   - **Run outcome (FR-RPT-4):** completed clean / completed with failures / stopped on error / stopped by user / terminated by device loss.
   - Device identity, I/O size, failure mode, start/end time.

     > **Device identity in the report means the USB serial, not the BSD name** (rule recorded
     > 2026-08-06; see the FR document's entry and Step 16's release-note item for what a serial
     > actually names). The test is lifetime: the exported report outlives the session and the
     > enumeration that produced it, so a report headed "disk4" answers "which drive was tested?"
     > with a name that may since have moved to another drive — the exact failure the 2026-08-06
     > renumbering produced in this project's own scripts. The BSD name may appear **labelled as
     > the locator it was at run time**; it may not be the identification. A drive that reports no
     > usable serial is labelled as such, and its report must say its results cannot be told apart
     > from an identical model's.
   - **The run-start cache-bypass verdict (FR-TEST-9, added 2026-08-02).** Mandatory, not conditional on it having failed — an absent line is indistinguishable from a passing one. On `likelyCached` or `inconclusive` the report must state that **the verify result may be unreliable while the read → write-back refresh remains valid**, prominently enough that it cannot be read past. The exported file outlives the session and the UI banner; a report saying "0 bad blocks" that has outlived its qualification reproduces the exact silent failure FR-TEST-9 exists to prevent.
4. **Markdown export (FR-RPT-5, NFR-USE-7):** an "Export report…" action writing a well-structured `.md` (via `NSSavePanel`): headings, a clear pass/fail outcome line, and **tabulated** bad-block ranges and statistics. No run history is retained (each run standalone) — export is the only persistence.
5. **Honest outcome wording:** "completed clean" must read as "no currently-unreadable blocks found," not "healthy" (ties to Step 14 / FR-WARN-3).
6. **`os_log`** the failure-mode selection and final outcome (NFR-OBS-1).

### Verification Gate (must pass before Step 11)
- [ ] **Stop-on-error:** with an injected fault, the run halts immediately at the offending range and reports it; nothing past it is processed.
- [ ] **Log-and-continue (default):** with multiple injected faults, all bad ranges are recorded and the rest of the device is still refreshed to completion.
- [ ] A clean run reports "completed clean / no currently-unreadable blocks," with throughput + latency stats present.
- [ ] Exported Markdown is well-structured (headings, outcome line, tabulated ranges + stats) and opens cleanly in a Markdown viewer.
- [ ] Outcome field correctly distinguishes clean / with-failures / stopped-on-error. ~~/ stopped-by-user~~ — **deferred to Step 11, user decision 2026-08-06.**

  > **Why the fourth outcome is not this step's.** Nothing can stop a run until Step 11's
  > `FR-CTRL-4` machinery exists, so "stopped by user" would be an outcome case with no trigger —
  > and *a sound mechanism behind a trigger that never fires looks exactly like a broken
  > mechanism* (Step 9's own lesson, paid for). The alternative considered was to build the case
  > now and unit-test it; the user chose to ship only the outcomes reachable today, so that
  > **nothing untriggerable ships**. The report's outcome vocabulary therefore grows in Step 11
  > (stopped by user) and again in Step 12 (terminated by device loss). Recorded as an inherited
  > note on both.
  >
  > The wording rule travels with it: whatever Step 11 adds must obey detailed step 5 —
  > "completed clean" reads as *no currently-unreadable blocks found*, never as "healthy".

- [ ] **The injected-fault items above are discharged in simulation, and can only be.** A healthy
  scratch device produces no failures, and this project does not manufacture one on real hardware.
  `InMemoryBlockDevice` already carries the three hooks (`injectReadFault`, `injectWriteFault`,
  `injectSilentCorruption`), so FR-FAIL-2 and FR-FAIL-3 are proven there. The **hardware** half of
  this gate is a clean bounded run on the scratch device producing a report and exporting it —
  which is what keeps the hardware-dependent part small, as intended.

### Risks / gotchas
- Coalesce contiguous failing chunks into ranges for a readable report, but don't lose a non-contiguous failure.
- The report must include stats even when the run stopped early.
- **Increments 2 and 3 touch `Core/` and the helper**, so all three hardware gates
  (`xpc-concurrency-check.sh`, `metrics-check.sh`, `retention-cycle-check.sh`) must be re-run
  before this step closes — two of them write to the scratch device.

---

# Phase 4 — Control, Resilience, and Power

## Step 11 — Run-control state machine: start / pause / resume / stop / restart

> **STEP 11 IS COMPLETE (2026-09-05).** Twelve increments built and gated, the 16-chunk human
> checklist in [`progress/step-11-human-checklist.md`](progress/step-11-human-checklist.md) walked
> and passed in full, and the verification gate below re-run against the **v14** daemon on
> 2026-09-05. **FR-CTRL-5 (Restart) was built and withdrawn** — redundant with Stop-then-Start, and
> the requirement is met by composition; do not re-derive the control from the gate item that names
> it. **The full account is archived in [`progress/step-11.md`](progress/step-11.md)** (2026-09-05,
> when Step 12 was picked up), following the template `progress/step-14.md` set when Step 14 closed.
> Its two companion files stay outside the archive because they are still consulted: the
> increment-plans file holds settled decisions that bind Step 12, and the human checklist is the
> record of what only a person could check.

> **Inherited from Step 8 (2026-08-03).** Protocol v7 has `runRetentionCycle(startBlock:blockCount:ioSizeBytes:)`,
> **capped at `TesterProtocol.maximumBytesPerCall` (1 GiB)**, and `digestRange` under the same
> cap. The cap is not a tuning parameter: it is what makes an uncancellable privileged operation
> safe to expose at all, given there is no cancellation until this step and no progress channel
> until Step 9. Step 11 is what replaces it with real run control — and until the state machine
> can actually stop a run, **whatever replaces it must stay bounded**. `Core/RetentionRun`
> already carries `FailureDisposition { continueRun, stopRun }`, which the engine honours by
> issuing no further I/O; Step 8 ships one caller that always continues.

> **Inherited from Step 9's D1 pre-flight (measured 2026-08-04) — read this before designing pause/stop.**
> While the helper is inside a blocking privileged call, **a second message on that same connection
> is not delivered until the call returns.** Measured on the scratch device: 24 pings issued during a 2,827.9 ms
> `digestRange` were all answered between 2,828.0 and 2,828.5 ms, the queue draining *after* the
> call finished. A **second connection** was answered concurrently throughout, in 0.2–0.3 ms. The
> daemon is not blocked; the connection is.
>
> Two consequences for this step. **Pause and stop must be able to reach a running helper**, and a
> call on the run's own connection provably cannot while `runRetentionCycle` blocks — so either the
> control path uses a second connection, or the run call must stop being a blocking one. Second:
> the same property already applies to `releaseDevice`'s "the device is in use — try again shortly"
> refusal and `prepareForShutdown`'s busy refusal (Step 4). Both are correct, and both are only
> *reachable* from a connection other than the one running. The 1 GiB cap is what keeps that
> survivable at ~7 s — a second justification for the cap that had not been written down.
>
> **Also inherited from Step 9: FR-TEST-10 constrains how this step may slice a whole-device run.**
> Every call must start on a **1 MiB boundary** and cover a **whole number of MiB**, the sole
> exception being a range that ends at the device's final block (FR-TEST-5's short final chunk).
> The helper enforces both and refuses otherwise — verified refusing on hardware, not merely
> assumed. Slice by whole MiB and let only the final call be short — the scratch device is
> 953,869 MiB **plus 1,456 blocks**, so the exemption is not hypothetical.
>
> **This note used to claim** that a sequencer advancing by *"1 GiB or whatever is left"* would be
> *"refused on its last-but-one call"*. **Measured 2026-08-14 (increment 4, `c8bcc2a`): it is not** —
> it produces 0 refusals and identical slices on all four real geometries, because the 1 GiB cap is
> itself a whole multiple of 1 MiB. A cap that is not would break it on **call 2**. The
> last-but-one symptom belongs to a *different* sequencer, one that backs the final call up to a
> full 1 GiB. Full correction in [CONSTRAINTS.md](CONSTRAINTS.md) section 1.
>
> Two more things Step 9 leaves in place that this step's design depends on: **progress is
> byte-denominated, never chunk-denominated** (which is what makes FR-CTRL-8's revised mid-run
> size change expressible at all), and **`chunkMeasured` fires once per chunk on every path**,
> including the three failure branches — so a run-control display keeps advancing on a failing
> drive instead of freezing.

> **Inherited from Step 9's UI work (user decisions 2026-08-05) — this step now owns the claim.**
> **FR-SAFE-5 is withdrawn, FR-SAFE-6 is reversed, FR-SAFE-7 is moot** (see the FR document's
> 2026-08-05 amendment). The `Unmount All`, `Acquire exclusive access` and `Release` buttons are
> **this step's to delete**, and **Start becomes the owner of the whole sequence**: unmount the
> selected device's volumes → acquire exclusive access → run → release on completion, stop or
> failure, after which macOS remounts the volumes by itself. If the volumes cannot be unmounted or
> the claim cannot be taken, report the actual cause (FR-SAFE-4 still distinguishes "still mounted"
> from "claimed elsewhere") and abort, leaving the cause for the user to clear.
>
> **FR-SAFE-1/2/3 and NFR-REL-3 are untouched** — no write may happen unless every volume is
> unmounted *and* exclusive access is held. Only who performs the unmount has changed.
>
> **This removal was gated on Step 14's warnings existing, and THAT GATE IS NOW DISCHARGED** —
> Step 14 completed 2026-08-11 (`f082716`), which is why it was built out of numeric order. The
> explicit unmount click was the only deliberate act between selecting a drive and writing to it;
> FR-WARN-1/2/3 are what replace it.
>
> **What that means for this step is not "proceed and forget it".** After this deletion the pre-run
> dialog is the *only* thing between FR-DEV-3's default selection and a write, and on this machine
> that default is the 22 TB Seagate carrying Backup and Time Machine. Two obligations follow:
>
> - **The gate must be relocated, not re-implemented.** It currently sits on `Run one bounded cycle`
>   in the diagnostics window (Step 14 scoping decision 2), because there was no Start control until
>   now. Move it to Start along the same path FR-CTRL-7's failure-mode picker beside it is already
>   documented to take, and delete the scaffolding with the button.
> - **Keep `runBoundedCycle(authorisedBy:)`'s shape.** It takes a `PreRunOutcome` as proof the gate
>   ran, and the `guard` re-checks it. That parameter exists to make "wire Start straight to a run" a
>   deliberate act visible in a diff rather than a one-word edit — the mutation is not catchable by
>   the suite, so prevention is the only cover it has.
>
> **The nine-item human checklist in `progress/step-14.md` is what the relocated gate must pass
> again.** Three of its items cover mutations no test here can reach.
>
> **A PARTIAL UNMOUNT THAT FAILS MUST NOT STRAND THE USER (found in real use, 2026-08-06).**
> Reported against the control this step deletes, but the hazard survives the deletion and lands
> squarely here.
>
> `DADiskUnmount` with `kDADiskUnmountOptionWhole` dissents as a unit, but **volumes it already
> unmounted stay unmounted**. So an unmount refused by one busy volume leaves the drive partially
> mounted. The user hit this with the *wrong drive selected* — volumes vanished from a drive they
> had not meant to touch, and the control offered only to repeat the failure:
>
> > *"I very much wanted an easy way to restore the mounted volumes."*
>
> Step 10 fixed the control (it now offers "Mount All" after a refusal). **This step deletes that
> control**, so the fix goes with it — and Start owning unmount → acquire → run → release
> reproduces the same situation with *no manual control left at all*: unmount volume A, fail on
> volume B, abort per FR-SAFE-4(a)'s revised remedy, and the user is left with A unmounted and
> nothing to press.
>
> **So the abort path has to put the volumes back.** Either roll back the unmounts the attempt
> performed, or offer the way back explicitly. An abort that leaves a drive half-unmounted has
> changed the user's machine in a way they did not ask for and cannot undo through this app — on
> the screen whose entire job is stopping the wrong drive from being touched.
>
> **AND THE UNMOUNT'S OWN SUCCESS SIGNAL CANNOT BE BELIEVED (measured 2026-08-06).**
> `DADiskUnmount` calls back with **no dissenter — success — while a volume is still mounted**.
> Confirmed from the unified log, which recorded `unmount succeeded on disk6: Unmounted every
> volume on disk6: 1TB_Samsung` for a volume that was mounted and in active use at that moment.
>
> A `nil` dissenter means *nothing refused the request*, not *the volumes are unmounted*. Step 10
> built two versions of the rollback on that signal and **both were inert by construction** before
> the postcondition was checked instead.
>
> This step's Start sequence unmounts before it acquires. **It must verify the mount table rather
> than trust the unmount's reply** — read it back the way `DeviceListView` now does, through the
> enumerator's IOKit subtree walk (a BSD-name prefix match does not work: an APFS volume is
> mounted from a synthesised disk).
>
> The safety property was never at risk and is worth stating for whoever reads this: the **helper**
> evaluates `DeviceAccessPrecondition` independently on the acquire path and refuses with
> `volumesMounted`, so a false "unmounted" in the app cannot put a write on a mounted drive. Keep
> that independence — it is what turned this into a wrong message rather than an incident.
>
> **Two more things Step 10 paid for, both of which this step needs.**
>
> - **The mount table lags the callback.** Reading it the instant `DADiskUnmount` returns still
>   lists a volume that has in fact gone, so a *successful* unmount reads as failed. Re-read until
>   it settles, with a bounded budget — Step 10 uses twelve looks at 150 ms — before concluding
>   anything. Without this, Start would abort every run it was about to perform.
> - **Restore exactly what went, by device node.** A whole-disk mount brings up every *mountable*
>   volume, which on a GPT drive means an EFI partition that was never mounted (observed on the
>   scratch device). `DiscoveredDevice.mountedVolumeBSDNames` exists for this: a name cannot be
>   mounted and a node can, and an APFS volume's node is not derivable from the physical disk by
>   prefix. Capture the mounted set **before** unmounting; restore `before − still mounted`.

> **Two interim behaviours this step subsumes**, both introduced in Step 9 and both stop-gaps for
> the claim not yet belonging to the run:
> - **The claim follows the selection** — deselecting a drive, or selecting a different one,
>   releases it. Once Start owns the claim this rule is redundant and should go, not be carried.
> - **The selection is frozen while a run is active** (`DeviceDiscovery.select`/`deselect` refuse,
>   and `TableSelectionPolicy` sets `NSTableView.allowsEmptySelection = false`). The refusal is
>   still wanted; the *reason* changes from "a selection change would release the device" to "the
>   run owns the device".
>
> **And one defect this step deletes rather than fixes.** `AppModel.helperHoldsDevice` is written
> from `checkDeviceReadiness`'s `helperHoldsThisDevice` — a *per-device* answer — but read at every
> use site as "the helper holds *some* device". The two can only disagree when the held device and
> the selected device differ, which the follow-the-selection rule currently makes unreachable. A
> run-owned claim removes the ambiguity at the source; do not reintroduce a selection-scoped flag.

> **Inherited from Step 9's increment 4 (built 2026-08-05) — the quit machinery this step must
> keep honest.** Quitting during a run now asks first, and "Cancel and Quit" means **stop at the
> call boundary**: issue no further work, wait for the in-flight privileged call to return, release
> the device, terminate. `Quit/QuitPolicy` holds both truth tables, `Quit/QuitSequence` the
> release-then-terminate step, `Quit/MainWindowCloseGuard` the close half, and
> `Quit/AppLifecycleDelegate` the ⌘Q half. Three things this step inherits:
>
> - **`AppModel.mayIssueNewWork` is a precondition, not a hint.** It is `false` from the moment a
>   quit is *pending*, and today the only thing that issues privileged work — the bounded-cycle
>   button — consults it. **A run sequencer must check it before every call it issues**, or the
>   first half of the promise ("issue no further work") silently stops being kept the moment a run
>   becomes a sequence rather than a single call.
> - **The boundary is `cycleIsRunning` going false**, and the wind-down hangs off that transition.
>   When the state machine replaces both run-state sources, the boundary must move with it — and
>   the "the run already finished while the dialog was up" case must survive the move
>   (`quittingAfterTheRunHasAlreadyFinishedDoesNotWaitForever` is the test that pins it).
> - **`QuitPolicy` takes `runIsActive` as the union of the stand-in toggle and a real cycle**, which
>   is what makes the dialog exercisable without writing to a drive. Collapsing both into one
>   authoritative source is this step's job; the policy's shape does not need to change.
>
> **The wait exists because of D1, not for tidiness.** `releaseDevice` goes out on the owning
> connection, and a second message on a connection with a blocking call in flight is not delivered
> until that call returns. Issuing the release mid-run would queue it behind the very call it was
> meant to shorten. Any pause/stop this step adds is subject to the same constraint.

> **Inherited from Step 10 (user decision 2026-08-06) — this step owns the "stopped by user"
> outcome, and the pre-run controls.** Step 10 built both failure modes, the bad-block report and
> the Markdown export, but deliberately shipped **only the outcomes reachable without a stop
> control**: completed clean, completed with failures, stopped on error. Two things follow.
>
> - **The report's outcome vocabulary gains "stopped by user" here**, when FR-CTRL-4 gives it a
>   trigger. It was not built in advance on purpose — a sound mechanism behind a trigger that
>   never fires looks exactly like a broken one. Step 10's gate carries the deferred checkbox;
>   this step discharges it. The wording rule comes with it: "completed clean" means *no
>   currently-unreadable blocks were found*, never "healthy" (Step 10.5, FR-WARN-3).
> - **FR-CTRL-7's "require a failure mode before start" is this step's**, not Step 10's, because
>   there is no Start control until here. Step 10 puts the mode picker beside the bounded-cycle
>   button in the **diagnostics** window, as scaffolding; this step relocates it to the real
>   pre-run controls alongside the I/O-size dropdown and deletes the scaffolding with the button.
>   The mode itself is `FailureMode` in `Core/RetentionRun.swift`, carried over XPC as
>   `FailureModeCode` (protocol v9) — and an **unrecognised** mode code is *refused* at the
>   boundary, never defaulted, for the reason recorded on that type.
> - **A whole-device run is a sequence of calls, and each one takes a mode.** Whatever this step's
>   sequencer does, `stopOnFirstError` has to mean "stop the *run*", not "stop this call" — a
>   sequencer that saw one call stop on a failure and then issued the next would turn the mode
>   into a no-op that still reports honestly per call.

**Original action item:** AI-10
**Satisfies:** FR-CTRL-1/2/3/4/5/6/7/8/9; NFR-REL-10
**Trust boundary:** state owned **GUI-side**, enforced **helper-side** (pause must settle in the helper).

### Objective
Implement the explicit run-control state machine with legal-transition enforcement, the pre-run controls (I/O size, failure mode), single-device-at-a-time enforcement, and a pause that settles at a chunk boundary with no write in flight.

### Detailed steps
1. **Define states:** `Idle → Configured → Running ⇄ Paused → (Stopped | Completed | Failed)`; `Restart` returns to the start of `Running` from beginning. Enumerate **legal transitions only** (FR-CTRL-6): pause only while running; resume only from paused; stop from running/paused; start only from configured/idle.
2. **Pre-run controls (FR-CTRL-7/8):** require failure-mode selection before start; provide the **I/O-size dropdown {1,2,4,8 MiB, default 4}**, configurable before start and **fixed for the run's duration**.
3. **Pause settles at a chunk boundary (NFR-REL-10, key safety property):** the helper finishes the current chunk's full read→write→verify (or the read-before-write point with **no write in flight**), then acknowledges the pause, leaving the device consistent. The GUI shows "Paused" only **after** the helper acknowledges (not optimistically).
4. **Resume from point of pause (FR-CTRL-3):** continue at the next chunk (this in-session resume is allowed; it is **not** the prohibited cross-interruption resume of FR-FAIL-7).
5. **Stop (FR-CTRL-4):** halt, release the device (Step 6), produce the report (Step 10) with outcome "stopped by user."
6. **Restart (FR-CTRL-5):** discard state and begin again from block 0.
7. **One device at a time (FR-CTRL-9):** disallow starting a new run while any run is active; the start control is disabled and explained.
8. **`os_log`** start/stop and mode at run start (NFR-OBS-1).

### Verification Gate — COMPLETE (2026-09-05)

> ✅ **ITEMS 2, 3 AND 5 WERE RE-RUN 2026-09-05 AND PASSED**, against the **v14** daemon. All three
> rest on `scripts/run-control-check.sh`, which had gone stale on 2026-09-03 when increment 11 took
> the protocol to v14 and moved the helper hash, so the v12 daemon that evidence came from no
> longer existed. **That has now happened twice in this one gate** — item 2 records the v10 → v12
> lapse, and this was the v12 → v14 one — and **both were findable only because the tick named the
> protocol it ran against, not just the date.** Items 1 and 4 were unaffected either time: unit
> tests over `RunControlPolicy`, and an app-side checklist item with no daemon in it.
>
> **What invalidates the ticks below:** the next protocol bump, or any move of the helper source
> hash. Neither is announced — grep for it.
>
> ⚠️ **BOTH HAVE NOW HAPPENED. The helper source hash moved on 2026-09-05 and again on
> 2026-09-07** — `e6888aa5…` → `a951e527…` → `42774589…` (Step 12 chunks 1 and 3) → `e19b0b3c…`
> (chunk 7b) — **and the protocol went to v15 at chunk 3 on the first of those days.** **The
> daemon-backed ticks below are therefore historical: they record a real pass on a real day
> against a build that no longer exists.** They are not evidence about the current build and must
> not be cited as such. This does **not** reopen Step 11, which closed on the strength of them
> when they were current; it means the same scripts are re-run at Step 12's chunk 7. Items 1 and 4
> are unaffected either way — unit tests over `RunControlPolicy`, and an app-side checklist item
> with no daemon in it.

**WALKED AND PASSED 2026-08-24 — all five; items 2, 3 and the helper-side half of 5 re-run against
v14 and passed again 2026-09-05.** Each tick names its evidence so it can be checked
rather than trusted. Four were discharged in the morning; item 5 needed a check built for it (the
device-operation slot had none) and a human walk of the checklist's chunk 8, both done the same day.

Two of the five were re-run rather than taken on record, and **both re-runs found stale instruments
rather than product defects** — see PROGRESS. A gate that has not been re-run cannot report
anything.

- [x] **Illegal transitions are impossible** (e.g., resume while running, start while running) —
  by this item's own stated method, unit tests over the state machine. `RunControlPolicyTests`
  (27 tests) carries them by name: `resumeIsAcceptedFromExactlyOneState`,
  `startIsAcceptedOnlyWhenNoRunIsActive`, `startDuringARunIsRefusedWithAReasonThatNamesTheRule`.
- [x] **Pause acknowledgment arrives only after the helper confirms no write is in flight and it is
  at a chunk boundary (NFR-REL-10)** — `scripts/run-control-check.sh`, **re-run 2026-09-05 against
  the v14 daemon** (handshake `PROTOCOL=14 EXPECTED=14`, HEAD `12118f3`, helper hash `e6888aa5…`,
  1 TB T5 scratch drive `12345686DAA9`). All four I/O sizes settled at a chunk boundary with the
  correct resume point: 306 / 153 / 76 / 38 chunks; settle 9.33 / 7.59 / 5.93 / 6.59 ms;
  ack 0.55–0.60 ms. **What discharges this item is the resume arithmetic, not the latency** —
  NFR-REL-10 requires a settle *at a chunk boundary with no write in flight* and puts no bound on
  how long it takes, so the exact resume point is the evidence and the millisecond figures are
  characterisation.
  ⚠️ **The 1 MiB settle, 9.33 ms, exceeded its own one-chunk bound of ~6.5 ms** — the first of
  twelve samples across three runs to do so, and outside the model `CONSTRAINTS.md` §1 stated at the
  time. That is a latency question and not a pause-correctness one; it did not bear on this tick.
  **RESOLVED the same day**: `run-control-check.sh --repeat-1mib 8`, a second v14 run at the same
  helper hash, measured the settle to be the remainder of the current chunk **plus a fixed ~3.5 ms**
  — no sample below 0.65 of its bound, a one-in-4,400 event under a uniform draw. That second run
  also re-passed this gate in full (14 assertions, 0 failures), so this item now rests on two
  independent v14 passes. Model, tables and arithmetic in `CONSTRAINTS.md` §1.
  *Superseded evidence, kept because the pattern is the point:* 2026-08-24 against **v12**
  (300 / 147 / 73 / 38 chunks; settle 6.4 / 3.1 / 9.8 / 20.1 ms; ack 0.34–0.58 ms), and before it
  2026-08-12 against **v10** — each one two protocol bumps behind the run that replaced it. That
  v12 record also carried the sentence *"settle tracks the I/O size rather than the 1 GiB call
  cap"*; **it is withdrawn.** It was fitted to one run's four samples and neither of the other two
  runs shows that ordering.
- [x] **Resume continues from the correct next chunk** — same gate, same run (**2026-09-05, v14**).
  The resume point is asserted arithmetically against this call's own work rather than checked for
  plausibility, and all four were 1 MiB-aligned, so the resumed call cannot be refused under
  FR-TEST-10.
  **"Metrics/ETA continue sensibly" is human**, and chunk 4 of the human checklist covers it:
  passed 2026-08-18, and that pass is **accepted as still standing** (user decision 2026-08-24)
  rather than re-walked after increments 6–8.
- [x] **Stop releases the device and yields a "stopped by user" report** — chunk 7.4 of the human
  checklist, passed 2026-08-22. ~~Restart begins from block 0.~~ **Amended 2026-08-24: there is no
  Restart control.** It was built in `0f65be4` and withdrawn in `916a630` as redundant with
  Stop-then-Start, and FR-CTRL-5 carries a 2026-08-22 amendment recording that the requirement is
  met by composition. **Do not re-derive the control from this line** — a gate item naming a
  control is exactly how a withdrawn one comes back.
- [x] **I/O size is selectable before start, fixed during the run; failure mode required before
  start; second concurrent run is refused.** Discharged 2026-08-24, in two separate places; the
  **helper-side half was re-run against v14 and passed again 2026-09-05**:
    * ~~**Chunk 8 items 3–7 of the human checklist are unrun.**~~ **Walked and passed 2026-08-24.**
      Items 1–2 had passed 2026-08-19; item 3 was run *before* the 2026-08-19 reversal rebuilt both
      controls to one rule, so its result was superseded and it was re-walked. No test drives a
      SwiftUI binding, so mutation M15 — *the dropdown does nothing at all* — passes the entire
      suite; **this chunk is its only cover**, and item 7 is the only check anywhere that follows a
      chosen I/O size from the dropdown through the gate, into every call, onto the report screen
      and into the exported Markdown. All four agreed on `8 MiB`.
    * ~~**"Second concurrent run is refused" has no helper-side cover.**~~ **Covered 2026-08-24.**
      App-side was already discharged by `startDuringARunIsRefusedWithAReasonThatNamesTheRule`.
      Helper-side the guard is the **device-operation slot** — `beginDeviceOperation`, taken by
      `runRetentionCycle` and by `digestRange` — not the `isBusy` check, which guards *release*.
      Nothing covered it: `HelperActivity` is in the helper's `main.swift` (top-level code, so not
      importable by a test target) and `RetentionCycleRefusal` is in `RunCoordinator.swift`, which
      is **not in the test target either**, so no unit test can reach the refusal or its wording.
      `claim-contention-test.sh` covers *acquire* contention, a different question.

      `scripts/run-control-check.sh` now issues a **1 MiB run on the second connection while a
      7-second call is in flight** and asserts it is refused, reports no chunks, and names both the
      operation and the disk. **Then it issues the identical call with nothing in flight and asserts
      it is accepted** — same request, same connection, one variable. Without that half a refusal
      proves only that *something* refused, and the check could not be seen answering both ways. It
      also rules out connection ownership as the cause, which reading the source had not settled.
      A fifth assertion checks the in-flight run still completed, separating *refused cleanly* from
      *both broke*. No mutation round: mutating the guard would mean rebuilding and **reinstalling a
      privileged daemon** to test it live, and the idle attempt already supplies the evidence a
      mutation would buy.

      **Re-run 2026-09-05 against the v14 daemon and passed again**, all five assertions: the second
      run was refused while a call was in flight, named both the operation and the disk (*"a
      retention cycle is writing is already in progress on disk7"*), and reported **0 chunks**; the
      identical call with nothing in flight was **accepted** and did 1 chunk; and the in-flight run
      completed normally regardless.

### Risks / gotchas
- Pause acknowledgment is a **two-party handshake** across XPC — never show "Paused" before the helper confirms, or you imply a safety guarantee you don't have.
- State must be the single source of truth gating Step 4 (no uninstall mid-run) and Step 13 (sleep assertion lifecycle).

---

## Step 12 — Device-loss handling (hot-unplug / de-enumeration mid-run)

> **Inherited from Step 9 (user decision 2026-08-05) — how FR-DEV-8's recovery should behave.**
> The requirement says "terminate the test, present a suitable error message, and re-run the
> initial device discovery routine" and stops there. Three details were specified during Step 9
> and are recorded so they are not re-derived:
>
> - **Wait for the in-flight I/O to time out rather than trying to abort it.** The same
>   stop-at-a-call-boundary shape agreed for quitting mid-run, and consistent with there being no
>   cancellation of a privileged call once issued. **That shape now exists in code**: Step 9's
>   `Quit/QuitSequence` is exactly "wait for one thing, or for a deadline, then act — once", with
>   its clock injected. Device loss is the same problem with a different trigger, and reusing it
>   would inherit the once-only and cannot-hang properties already mutation-tested rather than
>   writing a second version of them.
> - **Rebuild the device list from scratch**, not patch it.
> - **The rebuilt list re-applies FR-DEV-3's default**, so recovery lands on the first device
>   rather than on nothing. `DeviceSelectionPolicy` already does this — a rebuild with no previous
>   selection returns the first usable device — so the behaviour is inherited, not new work.

> **A REAL DEVICE LOSS HAPPENED DURING STEP 10'S HARDWARE GATE (2026-08-06), AND IT SHOWS WHAT
> THIS STEP IS ACTUALLY FOR.** Not a simulation, not a fault hook — the scratch device
> de-enumerated part-way through `retention-cycle-check.sh`'s pre-run fingerprint. Full log in
> `progress/step-10.md`, increment 6.
>
> **What the helper saw:** `errno 6` — `ENXIO`, *"Device not configured"* — on every read from
> that moment, **including offset 0**. That is the exact signal detailed step 1 names. A bad block
> gives `EIO` on that block; `ENXIO` on offset 0 of a working descriptor means the descriptor is
> dead. The drive re-enumerated ~2 s later, healthy, at full link speed.
>
> **What the product did with it, and why it is wrong.** Nothing detected the loss, so the run in
> log-and-continue mode did exactly what it is supposed to do with a bad drive: it recorded every
> failing chunk and walked to the end. The reply was
>
> > `Cycle completed: 256 of 256 chunks; 2095104 block(s) in 1 range(s): read error`
>
> A report built from that says **"Completed with failures"** and tabulates one range of
> **2,095,104 bad blocks**. The drive does not have two million bad blocks. It went away.
>
> **That is a false accusation about somebody's hardware**, produced by a tool whose entire output
> is a judgement about their hardware — and it is the same class of error `RunAbort` exists to
> prevent when the fault is *ours*. `RunAbort` refuses to record an addressing bug as a bad block
> precisely so this cannot happen; device loss has no equivalent protection until this step
> builds it.
>
> So the outcome case this step adds is not cosmetic. **Until it exists, a drive that drops off
> the bus is reported as a catastrophically failing drive**, in an exported file that outlives the
> session. Detect **`ENXIO`** per detailed step 1 — *not* `EIO`, see the correction there — and
> make sure the failures already recorded before the loss are not presented as a bad-block
> verdict.
>
> One thing that did work, and is worth keeping: the run's figures came back `-1` / sample count
> `0` rather than `0 MB/s`, because nothing was measured. The sentinel discipline held under a
> real fault nobody arranged.
>
> **And the fix that must NOT be built.** The tempting shortcut is a heuristic in the report:
> *"every chunk failed, so it was probably device loss rather than a bad drive."* **Do not.** A
> genuinely dead drive also fails every chunk, so the heuristic is wrong exactly when being wrong
> is most expensive — and it is a judgement the tool is not entitled to make, which is the same
> rule that stops it grading throughput (D9) and stops FR-DEV-3 guessing which drive is
> expendable. Device loss is **detected**, per detailed step 1, from **`ENXIO`** and the
> DiskArbitration/IOKit removal callback. It is not inferred from a failure count.

> **Inherited from Step 10 (user decision 2026-08-06) — this step owns the "terminated by device
> loss" outcome.** Step 10's report ships the outcomes reachable without a stop control or a
> removal event; Step 11 adds "stopped by user" and this step adds the fifth. Same reasoning:
> nothing untriggerable ships. The report already carries everything the outcome needs beside it
> — the ranges found before the loss, the partial statistics, and FR-TEST-9's verdict — so what
> is added here is the outcome case and its wording, not a second report path. A run terminated
> by device loss must still produce a report (FR-FAIL-5 admits no exception), and it must not
> read as "completed".

**Original action item:** AI-9
**Satisfies:** FR-DEV-8; FR-FAIL-7; NFR-REL-5/6
**Trust boundary:** detected **helper-side** (I/O errors) and via **DiskArbitration/IOKit** removal callbacks; surfaced **GUI-side**.

### Objective
If the device under test disappears mid-run, immediately terminate the test cleanly, surface a clear error, and re-run device discovery — with no resume.

### Detailed steps
1. **Detect loss two ways:** (a) raw I/O suddenly returns **`ENXIO`** from `pread`/`pwrite`; (b) DiskArbitration "disk disappeared" / IOKit termination callback for the device under test. Treat either as device loss.

   > **CORRECTED 2026-09-05 (Step 12, chunk 1).** This step used to say `ENXIO`/`EIO`, which
   > **contradicted the incident note above it** — the note has said since 2026-08-06 that *"a bad
   > block gives `EIO` on that block; `ENXIO` on offset 0 of a working descriptor means the
   > descriptor is dead."* Two other lines in this section deferred to this one, so the wrong half
   > was stated three times and the right half once.
   >
   > **`EIO` is a bad block and must never end a run.** It is the ordinary answer from a single
   > unreadable block, so treating it as device loss would stop the run at the first genuine bad
   > block — turning the one thing this tool exists to find into a reason to stop looking, and
   > breaking FR-FAIL-3's log-and-continue outright. The discriminator is **`ENXIO` alone** (user
   > decision 2026-09-05), and it is pinned by `DeviceLossErrnoTests.eioStaysABadBlockAndIsNeverDeviceLoss`.
   >
   > Every other `errno` keeps its existing meaning, `EBADF` included: a closed or invalid
   > descriptor is *this program's* mistake, not the device's absence.
2. **Terminate immediately and cleanly (NFR-REL-5):** stop issuing I/O, release the claim and close the fd, leave the helper in a consistent state (no further writes).
3. **Surface a specific error (NFR-REL-6, NFR-USE-5):** GUI shows "The device under test was removed; the run was terminated and cannot be resumed — restart from the beginning if you reconnect it." The GUI must **not crash** and must return to a usable state.
4. **No resume (FR-FAIL-7):** the partially-completed run is over; only restart-from-beginning is offered.
5. **Re-run discovery (FR-DEV-8):** automatically re-execute Step 5's discovery routine so the (possibly reconnected) device list is fresh.
6. **`os_log`** device loss and clean termination (NFR-OBS-1/2 — logs must be enough to diagnose the interrupted run after the fact).

### Verification Gate (must pass before Step 13) — ✅ **ALL FOUR PASSED, ticked 2026-09-11 at chunk 7h**

**What these are true of.** The evidence is `progress/step-12-human-checklist.md`, walked on real
hardware across three days, and the ticks are recorded against **`7e51398`** with the app installed
from **`abc07e3`** (dylib `c08f95ad…`, helper `7590b920…`, daemon pid 89541 started 2026-09-08
16:22:50 and resolved from `/Applications`, protocol **v15**, helper source hash **`e19b0b3c…`**).
The cable pulls themselves ran against earlier commits — chunk 3 against `982406a` (app from
`0b37afd`), chunk 4 against `c767317` (app from `2086090`) — and **the chain from those to the
installed build touches no device-loss behaviour**: `0b37afd` → `2086090` differs in comments only,
and `2086090` → `abc07e3` is 7g, which adds two log lines on the *command* and *selection* paths and
changes only comments in `DeviceLossWindDown.swift` and on `RunController.swift`'s device-loss path.
`abc07e3` → `7e51398` is 7h, test and documents only. The drive throughout is the 1 TB scratch T5,
serial **`12345686DAA9`**.

- [x] Physically unplugging the device mid-run (the designated scratch device) **immediately** terminates the run, releases the node, and shows the specific device-loss error — the GUI stays alive and usable. — **Chunk 3, 2026-09-09, six pulls of a running run**, plus **chunk 4, 2026-09-11, paused pulls on two drives**. *Immediately* is measured, not asserted: **2.7–6.3 ms** from the removal callback to `run ended` across six trials (5.1), the 3 s deadline never approached; the release lands ~6 ms after the whole-disk callback (`.920` → `.926 released disk7: descriptor closed, DiskArbitration claim dropped` → `finishing → finished on deviceReleased`). The specific error is at **error** level and names model and serial — `the drive under test left the machine while running: Samsung Portable SSD T5 (serial 12345686DAA9), disk7 at run time`. GUI checked by eye 2026-09-09 (items 4 and 7): no crash, no hang, window usable, and a report rather than the alert. **Invalidated by** a behavioural change to `DeviceLossWindDown.swift` or `RunController.swift`'s device-loss path, or a helper-hash move.
- [x] Discovery re-runs automatically; reconnecting the device repopulates the list. — **Chunk 3 items 12–14 and chunk 4 item 8**, walked and passed: the scratch drive leaves the list with nothing clicked, reappears on reconnect **confirmed by serial**, and a second run is accepted — so the interrupted run's claim is not still held. ⚠️ The `RunControllerWiring` closure that fires the re-run has **no automated cover** — chunk 7b's mutation m17 deletes the call and passes the whole suite — so this item is the only thing standing behind it and a re-walk is the only way to re-establish it. **Invalidated by** a change to `RunControllerWiring`'s `onDeviceLost:` wiring or to `DeviceDiscovery`'s refresh path.
- [x] No resume is offered; only restart-from-beginning. — **Chunk 3 item 10**, read off the controls by a person 2026-09-09. Reinforced in the machine itself: `RunControlPolicy` admits `resume` only from `.paused`, and a device loss routes through `.finishing` to `.finished`, from which no resume is reachable — pinned by `RunControlPolicyTests`. **Invalidated by** a new edge into `.paused`, or a control that offers resume from a finished run.
- [x] Logs after the event are sufficient to reconstruct what happened (which device, at what offset) without recording contents. — **Which device**: chunk 3 item 5, the error line above, model + serial + BSD name labelled *at run time*. **At what offset**: 5.3 — the block is in the report via `DeviceLossAccount`, and on all four trials where it was read off the screen (1,261,568 / 1,130,496 / 1,687,552 / 1,392,640) it equalled the helper's own `retention cycle END: ended at block …` and the first block of the failing chunk (block × 512 = the offset in the `failed after 0 bytes` line). **Without contents**: the log carries block numbers, byte counts and errnos, never buffers. ✅ **Strengthened at 7g and seen by a person 2026-09-11**: every accepted command now logs `run control: A → B on the <Start|Pause|Resume|Stop> command`, so the reconstruction covers what the *operator* did as well as what the device did — all four labels observed on the installed build, the first three at 16:14–16:19 and `paused → running on the Resume command` at 18:02:13.596. **Invalidated by** a change to `DeviceLossAccount`, `RunControlLog`, or the helper's cycle-end line.

### Risks / gotchas
- Simulate this safely first, then confirm on real hardware with the scratch device. **The hook this named did not exist when it was written** — `InMemoryBlockDevice`'s three fault hooks were all *range*-based, and `injectReadFault(blocks: 0 ..< blockCount)` simulates a drive with every block bad, which is the exact misreading this step exists to remove rather than a way to test it. Chunk 1 (2026-09-05) added `injectDeviceLoss(afterCalls:)`, which takes no range because the device leaving the bus is not a property of any range.
- Ensure the claim is released even though the device is already gone (avoid a stuck DiskArbitration state). **Chunk 4 (2026-09-06): the release is always issued, but it is only *waited for* when the owning connection is free.** If the wind-down's deadline expired, that connection is still blocked by the call that never answered — measured 2026-08-04 — so the release cannot be delivered, let alone acknowledged. The controller therefore does not wait, does **not** claim the drive was released, and logs `releaseCannotBeConfirmed`. The real recovery is that the next `acquireDevice` is refused with the helper's own reason if the claim is still held.
- **Route (a) is blind while the run is paused**, and no line of this section said so. A paused run has returned from its call and issues no syscalls, so there is no `errno` to classify — the helper simply sits holding the claim and the fd. Only route (b) can see a device unplugged while paused, which makes it load-bearing rather than a second opinion. **Chunk 2 (2026-09-05) built the detection**; `VolumeChangeWatcher` no longer discards which disk changed. **Chunk 4 (2026-09-06) wired it to `DeviceLossWindDown`**, whose way 1 — nothing in flight — is the paused case, and which ends the run at once there rather than waiting for a reply that provably cannot come.
- **One unplug is several events.** Measured 2026-09-05: a partitioned drive fires `DADiskDisappeared` once for the whole disk and once per slice. Whatever chunk 4 wires this to **must be idempotent** — a two-partition drive produces three notifications for one removal, and a wind-down that runs three times is a different defect from the one being fixed. **Chunk 4 (2026-09-06) made it so, at three levels**: the event table refuses `deviceLost` from `finishing`, `RunController` builds one wind-down per run, and `DeviceLossWindDown.begin` is idempotent in itself. The middle one is not redundant — a mutation building one per callback armed three deadlines and **survived the whole suite**, because the test bench held only the latest; `threeCallbacksFromOneUnplugArmOneDeadline` is what closed it. **⚠️ 2026-09-10: "one unplug is several events" holds for an *unclaimed* drive only.** Under the run's exclusive claim the slices go at the claim, and an unplug fires exactly one whole-disk event — six of six on chunk 3's pulls (`CONSTRAINTS.md` §1, *Under a claim*) — so this defence has **no hardware path** in this design, and checklist 4.9 cannot exercise it. It stays: it is cheap, and it is pinned on the bench. *(✅ 4.9 walked anyway 2026-09-11, by user decision, on the thumb: one whole-disk event at the pull, as predicted — eight of eight claimed unplugs now, on two drives.)*
- **Do not match a disappearing disk by name prefix.** `disk7` and `disk70` share one and are different drives; a `hasPrefix` check ends a healthy run when an unrelated drive is unplugged. `DeviceUnderTest` compares the parsed unit number, and `DeviceUnderTestTests` pins five names that a prefix check gets wrong.
- **The gate item above about reconstructing "which device, at what offset" is now partly answered by the report rather than only by the log. Chunk 5 (2026-09-06)** gives `RunReportOutcome` its sixth case and attaches a `DeviceLossAccount` — four named cases, because the two detectors leave the run knowing different amounts. **The one to check by eye at chunk 7 is the paused case**: a run paused with nothing in flight must NOT be told a chunk may hold partly written data, and that is the only case where `aWriteBackMayBeUnfinished` is `false` without route (a) having said which phase it was in. A single hedged sentence covering all four would put a false alarm into a document somebody keeps. *(✅ Checked by eye on a real report 2026-09-11, checklist 4.7: a paused run unplugged, and the report said* paused *and that nothing was left half-written, word for word.)*

---

## Step 13 — System-sleep prevention

**Original action item:** AI-12
**Satisfies:** NFR-REL-9 (and FR-FAIL-7 rationale)
**Trust boundary:** **GUI-side** power assertion tied to run state.

### Objective
Prevent idle system sleep while a run is **actively executing** (because runs can take many hours and cannot be resumed), and release the assertion the moment the run pauses, stops, completes, or fails.

### Detailed steps
1. **Hold an idle-system-sleep assertion** while `state == Running`: `ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "USB drive retention test in progress")`, retaining the returned token. (Equivalently `IOPMAssertionCreateWithName` with `kIOPMAssertPreventUserIdleSystemSleep` — the ADR specifies the `NSProcessInfo` route.)
2. **Release on every exit from Running (NFR-REL-9):** `endActivity(token)` on pause, stop, completion, and failure (including device loss, Step 12). Driven by the Step 11 state machine so there is exactly one acquire/release path.
3. **Do not prevent display sleep or block manual sleep** — only *idle system* sleep. The user can still deliberately sleep/quit.
4. **`os_log`** assertion acquire/release alongside run start/stop.

### Verification Gate (must pass before Step 14)
- [ ] During an active run, the Mac does not idle-sleep (verify with a short idle-sleep timer or `pmset -g assertions` showing `PreventUserIdleSystemSleep` while running).
- [ ] On pause/stop/complete/fail/device-loss, the assertion is released (`pmset -g assertions` no longer lists it).
- [ ] Exactly one assertion is held at a time (no leaks across pause/resume cycles) — verified across several transitions.

> ⚠️ **How these three are read — settled 2026-09-12 by `scripts/sleep-assertion-check.sh`, before
> any of Step 13 was wired.** The three items above are unchanged; what follows is how to take the
> reading, because two of the obvious ways of taking it pass without the product.
>
> **Read the `Listed by owning process:` section, matched on the app's pid — never the system-wide
> summary count.** `PreventUserIdleSystemSleep` reads **1** on this machine with nothing of ours
> loaded, because `powerd` holds one the whole time the display is on, and it is a **flag, not a
> count**: measured 1 at baseline, 1 while we held one, 1 while we held **two**, 1 after release.
> An item answered from that line is answered by `powerd`.
>
> The type string the items name is **correct as written** — `beginActivity` does publish
> `PreventUserIdleSystemSleep` — and the `reason:` string reaches `pmset`'s `named:` field verbatim,
> so the reading can be matched on both axes. Item 3 is readable there too: two activities from one
> process show as **two** entries with two ids, so a leak is visible rather than hidden behind a
> per-process flag.
>
> For item 1's *"the Mac does not idle-sleep"* half, the **display must be allowed to sleep first**.
> Until it does, `powerd`'s own assertion keeps the machine awake whether or not this app holds
> anything, so a run that survives an idle timer with the display on has demonstrated nothing.
>
> Full findings, and what invalidates them (a macOS update, not a commit): `CONSTRAINTS.md` §1,
> *Idle-sleep assertions*.

### Risks / gotchas
- The most common bug is a **leaked assertion** on an error path — route acquire/release exclusively through the state machine so every exit releases it.

---

# Phase 5 — Honesty & Observability

## Step 14 — Mandatory pre-run warnings & honest framing

> **Inherited from the 2026-08-06 renumbering — the default selection now lands on a backup drive,
> and this step is where that stops mattering.** FR-DEV-2 sorts by BSD name and FR-DEV-3 selects
> the first usable device. Both are satisfied. But BSD names are assigned at enumeration, so *which
> physical drive is selected on launch* changes when the machine renumbers — and after this
> reboot it is the **22 TB Seagate with Backup and Time Machine mounted**. Observed by rendering
> the real device list (`scripts/render-ui.sh devices`), not reasoned about.
>
> Harmless today: nothing happens without an explicit unmount and acquire, and the panel already
> says "Testing can cause data loss. Please make sure any important files on the test drive are
> backed up before starting a test." **It stops being harmless at Step 11**,
> where Start owns unmount → acquire → run: the default selection then sits one deliberate click
> away from a write, on whichever drive happened to sort first. FR-WARN-1/2/3's acknowledgement is
> what stands in that gap, which is why Step 11's removal of the explicit unmount is gated on this
> step existing.
>
> **The warnings must identify the drive they are about by model *and* USB serial**, for exactly
> the reason this note exists: an acknowledgement whose subject is "disk4" is an acknowledgement of
> a name that may have moved. The BSD name belongs **beside** that identification, not instead of
> it — the user is looking at the machine while they read the warning, so the locator is useful
> there. See the FR document's 2026-08-06 entry for the rule and its lifetime test.
>
> **FR-DEV-3 stands as written — settled 2026-08-06, user decision.** The default selection was
> put to the user and kept unchanged.
>
> > *"FR-DEV-3 is perfect as written. I do not want to go down the road of trying to divine user
> > intentions."* — user, 2026-08-06
> >
> > **This is the same policy as D9, not a separate one.** The tool reports throughput and refuses
> > to grade it, because the manufacturer's figure is not something it knows and inventing one
> > would be a judgement dressed as a measurement. A default that guessed which drive its owner
> > considers expendable — "prefer removable", "prefer unmounted", "prefer the smallest" — would be
> > the same error in the same place: a judgement dressed as a default, and one the user would have
> > no reason to distrust because it would look like the app knowing something. Selecting the first
> > device in a stated order says only what is true.
>
> **So the whole weight of this sits here.** With FR-DEV-3 fixed, nothing upstream narrows which
> drive is selected on launch, and Step 11 puts that selection one deliberate click from a write.
> FR-WARN-1/2/3's acknowledgement is the only thing between them, which is why Step 11's removal of
> the explicit unmount is gated on this step and not merely sequenced after it.

> **STEP 14 IS COMPLETE (2026-08-11).** Full account in [`progress/step-14.md`](progress/step-14.md)
> — the eight scoping decisions, the increment table, the accessibility audit, the two defects the
> keyboard session found, and the nine-item human checklist. The requirement changes are in the NFR
> document's 2026-08-09 entry (NFR-USE-4 qualified) and 2026-08-11 entry (VoiceOver removed from
> scope), and the FR document's 2026-08-09 entry (FR-WARN-1 qualified; FR-WARN-2/3/4 examined and
> unaffected). The notes below record how it was scoped and are kept as written.
>
> **SCOPED 2026-08-09 — seven user decisions, taken before a line was written, and one of them
> changed this step's own gate.**
>
> 1. **This step lands BEFORE Step 11**, which is what its gating relationship always required.
> 2. **Until Step 11 builds Start, the gate sits on `Run one bounded cycle`** in the diagnostics
>    window — the only control in the product that currently writes to a drive. So the mechanism
>    ships with a real trigger rather than waiting for one, and Step 11 relocates it along the same
>    path the failure-mode picker beside it is already documented to take.
> 3. **A modal sheet raised by pressing Start**, Proceed / Cancel — not an inline panel. It must be
>    a **sheet, not an `alert`**: a SwiftUI alert takes buttons and message text only, and decision
>    5 puts a `Toggle` in it.
> 4. **One acknowledgement, and Proceed is it.** No per-warning checkboxes. This replaces this
>    step's original gate wording, "*until all three mandatory warnings are acknowledged*".
> 5. **A "Don't show this warning again" checkbox, recorded per logged-in user** — the app's
>    `UserDefaults`, **never the helper's**: the helper runs as root, so anything it persisted
>    would be system-wide and would silently apply to every account on the machine.
> 6. **Suppressing the text does not suppress the deliberate act.** Start then raises a one-line
>    confirmation naming the drive by **model and USB serial**. This is what keeps NFR-USE-4
>    *qualified* rather than weakened, and it is the half FR-DEV-3's mitigation actually rests on.
> 7. **A "Show pre-run warnings again" control in the diagnostics window** — a setting with no way
>    back is one the user cannot undo without editing a plist.
>
> **What Step 10 already discharged, checked in the code rather than assumed.** Detailed step 3's
> report and result-screen halves are **built**: `RunReportMarkdown.whatThisDoesNotProve` (headed
> *"BUILD-PLAN 10.5, FR-WARN-3/4, NFR-USE-6"*) and `RunReport.headline`. Detailed step 4's
> colour rule is largely honoured already — every status in the app is a `Label` carrying a symbol
> **and** words, with the rule stated at `RunMetricsView.failures`. **None of it is suppressible**,
> which is why decision 5 leaves NFR-USE-6, FR-WARN-3 and FR-WARN-4 untouched. What is genuinely
> new here is detailed step 1, the pre-run half of step 2, and step 4's **audit**, which has never
> been run on any surface.
>
> **This step needs no hardware gate and no Xcode GUI step.** It is app-target and test-target only
> — both join file-system synchronized groups automatically — and it does not touch the helper, so
> the helper source hash stays `737e6972…` and Step 10's three hardware gates continue to apply.
>
> **One defect found while scoping this step, and it is NOT this step's to fix.** At the app's own
> `minHeight: 700`, the `Mounting & exclusive access` controls are **clipped**: rendered at 640×700
> they are absent, and at 640×900 they draw with ~170 pt to spare. `ContentView`'s comment says
> *"700 is where the idle window's content stops being clipped — measured … not guessed"*, and that
> measurement was taken in Step 9, before Step 10 added the **Mounted volumes** row and the
> helper-readiness explanation to the selected-device detail. Idle content now needs roughly
> **730 pt**. A measured constant whose premise expired silently — the same shape as
> `metrics-check.sh`'s inverted `disk4` guard, and the same below-the-fold-in-an-unadvertised-scroll-region
> defect that cost Step 10 two of its five rounds on the unmount control, in the same pane. Decision
> 3 means this step no longer depends on it; it is recorded here so it does not evaporate along with
> the design that found it.

**Original action item:** AI-11
**Satisfies:** FR-WARN-1/2/3/4; NFR-USE-4/6/8
**Trust boundary:** **GUI-side**.

### Objective
Before any run, prominently present the three mandatory warnings and the honest-framing message, requiring acknowledgment so a clean pass is never mistaken for a clean bill of health.

### Detailed steps
1. **Three mandatory warnings, shown in a modal raised by pressing Start (NFR-USE-4), acknowledged by a single Proceed before any run is issued (decisions 3 and 4 above):**
   - **Back up first (FR-WARN-1):** non-destructive *by design*, but data loss/corruption remains possible; back up the device first.
   - **Infrequent on NAND (FR-WARN-2):** this testing should be run only infrequently on NAND devices.
   - **Clean pass ≠ healthy (FR-WARN-3):** a clean pass means "no currently-unreadable blocks were found," **not** that the drive is healthy.
2. **Honest dual-role framing (FR-WARN-4, priority S):** explain that the tool is both a retention refresher and a hard-fault detector, and that degrading-but-still-correctable blocks cannot be detected at the USB block level.
3. **Presentation (NFR-USE-6):** the honest-framing must be positioned so a clean pass cannot reasonably be read as a health certificate — echo it on the result screen and in the report's outcome wording (Step 10).
4. **Accessibility, best-effort (NFR-USE-8):** use SwiftUI's built-in accessibility (Dynamic Type, contrast); **never convey pass/fail by color alone** — pair color with text/icon. Full audit is not a v1 gate. **Screen-reader support is out of scope** — user decision 2026-08-11, see the NFR document's amendment of that date; the colour rule and Dynamic Type are unaffected.

### Verification Gate — PASSED 2026-08-11 (all items; Step 14 is complete)

> **Gate note.** The seven-item human checklist that discharges the first three boxes is in
> `progress/step-14.md`, kept rather than deleted: the three increment-5 mutations it covers are
> **not catchable by the suite**, so it is what any future change to this area has to pass again.
> The gate sits on `Run one bounded cycle` rather than Start, per scoping decision 2 — there is no
> Start control until Step 11, which relocates the gate along with it.

- [x] Pressing Start issues **no run** until Proceed is pressed; Cancel issues none at all. The three warnings appear in that modal on every run **unless the user has suppressed them**. *(Checklist items 1–3, passed by a person 2026-08-11; the log's `pre-run prompt raised` line is the durable record.)*
- [x] With the warnings suppressed, Start still raises a confirmation naming the device by **model and USB serial**, and still issues no run until Proceed. **The deliberate act is not suppressible** — shown refusing, not merely shown passing. *(Checklist item 5.)*
- [x] Suppression is **per logged-in user** (the app's `UserDefaults`, not the helper's), survives a relaunch, and is reversible from the diagnostics window. *(Checklist items 4 and 6 — item 4 is the tick-then-Cancel case, which must record nothing.)*
- [x] The honest-framing message appears pre-run and on the result/report so a clean pass can't be mistaken for "healthy." **Suppressing the pre-run warnings does not suppress the report's copy.** *(Increment 2 put both renderers on one wording and found they had already drifted; the report's copy is not reachable by the suppression flag.)*
- [x] Pass/fail is conveyed by text/icon, not color alone (toggle to grayscale and confirm meaning survives). **Done 2026-08-11**, increment 6: every status-bearing view case rendered in both appearances and converted to greyscale. Four report outcomes carry four distinct glyphs *and* four distinct headlines; the pre-run dialog contains no saturated pixels at all. Contrast measured off the rendered pixels with a calibrated sampler — headline 13.97:1 light / 12.63:1 dark, against status tints at 2.22–2.31:1 light, which is why the words and the symbol are the carriers and the tint is decoration.
- [x] Dynamic Type: every string uses a semantic text style rather than a fixed point size — **verified 2026-08-11** (81 semantic sites; the only two fixed sizes are decorative SF Symbols). **Satisfied as far as the platform permits, confirmed twice independently:** the probe measured `DynamicTypeSize` inert inside an `NSHostingView` (discriminated with two controls, see `scripts/render-ui.sh`'s header), and at the keyboard, changing System Settings ▸ Accessibility ▸ Display ▸ Text size changed no font in any window. macOS does not scale these; there is no third lever.
- **VoiceOver is out of scope** — user decision 2026-08-11. Removed from this gate rather than left unticked, because an unticked box reads as work outstanding. See the NFR document's amendment of that date.
- [x] Both dialog variants are confirmed **by a person** to actually present in the shipped app — a sheet cannot be captured by `scripts/render-ui.sh`. Their layout is verified headlessly beforehand via their own `render-ui.sh` view cases; only *presentation* needs the keyboard. *(Both forms presented; checklist items 1–6.)*
- [x] **Three clean builds, DerivedData wiped before each: `build.sh Debug`, `build.sh Release`, `test.sh`.** Zero source warnings from all three, 2026-08-11. Confirmed genuinely clean rather than assumed — Debug ran 76 per-file `SwiftCompile` tasks, Release two `-whole-module-optimization` invocations covering both modules, the test target 148. **801 tests, 0 failures, 93 suites**, read from the xcresult's top-level `totalTestCount`.

> **Two defects were found by this step's keyboard session, and both are recorded because they say
> something about the method.** The exported report could not identify its drive (model, serial and
> capacity missing on the first run after every launch), and `Acquire exclusive access` was
> off-screen at the app's own `minHeight`, which presented as *"Run one bounded cycle stays disabled
> no matter what I do."* Both were Step 9/10 wiring, both fixed in `e61c4f0`, both re-tested by hand.
> **Increment 6's headless half — 36 renders, a calibrated contrast sampler, six mutations — found no
> defects in the app at all.** A person using the product remains the only instrument that has found
> this class of defect here, which is the argument for the human checklist surviving the tick.

### Risks / gotchas
- **The warnings are suppressible but the deliberate act is not, and that asymmetry is the whole
  requirement** (user decision 2026-08-09; NFR-USE-4 qualified). The original wording of this note
  read *"they must gate the Start action each run (the spec says 'before a run starts,' not
  'once')"* — rewritten rather than left standing beside code that contradicts it. What must gate
  Start each run is a **deliberate act naming the device**; what may be shown once is the *text*.
  Suppressing the act would hand back exactly the hazard this step exists to mitigate: FR-DEV-3
  default-selects the first device in BSD-name order, which on the development machine on
  2026-08-09 was the **22 TB Seagate with Backup and Time Machine mounted** (serial
  `00000000NT17XBRA`), re-measured through the app's own enumerator.
- **Do not put the suppression flag in the helper.** It runs as root; the setting would become
  system-wide and apply to every account on the machine, which is the opposite of what was asked
  for.
- A SwiftUI **sheet gets its own window and `render-ui.sh` cannot capture it** — the same permanent
  human-verification cost Step 10 accepted for the unmount alert, and accepted here knowingly. The
  mitigation is Step 10's: put the *decision* in a pure type a mutation can reach, give each dialog
  a standalone renderable `View`, and log which route was taken, so the only thing left to a person
  is "did a dialog appear" rather than "was the right thing decided".

---

## Step 15 — Logging / observability consolidation

**Original action item:** AI-15
**Satisfies:** NFR-OBS-1/2; NFR-SEC-6
**Trust boundary:** **both** (app and helper each log to unified logging).

### Objective
Ensure all significant events from both executables are emitted to the macOS unified logging system, sufficient to diagnose an interrupted/failed run after the fact, and **never** recording device contents.

### Detailed steps
1. **Audit the event set (NFR-OBS-1):** confirm `os_log`/`Logger` points exist for: run start/stop, failure-mode selection, failed block ranges, device connect/loss, helper registration/unregistration, exclusive-claim acquire/release, pause/resume, sleep-assertion acquire/release. (Most were added per-step; this step fills gaps and standardizes.)
2. **Subsystem/category scheme:** one subsystem (your bundle id) with categories like `discovery`, `safety`, `io`, `metrics`, `lifecycle`, `xpc` — for both targets — so logs filter cleanly in Console/`log show`.
3. **Diagnosability of interrupted runs (NFR-OBS-2):** ensure a failed/interrupted run leaves enough breadcrumbs (which device, offset/block at failure, outcome) to reconstruct what happened.
4. **Privacy (NFR-SEC-6, NFR-OBS-2):** **never** log device contents. Mark any potentially-identifying interpolations as `private` in `os_log` format strings; offsets/sizes/BSD names are fine, data bytes are not.
5. **No user-visible activity log required for v1** (resolved open question) — unified logging is sufficient.

### Verification Gate (must pass before Step 16)
- [ ] `log show --predicate 'subsystem == "<bundle-id>"'` (and Console) shows a coherent trace across a full run lifecycle from both app and helper.
- [ ] An induced interrupted run (device loss / stop-on-error) is fully reconstructable from logs (device, offset, outcome).
- [ ] No log entry anywhere contains device data bytes (inspect read/write/verify paths specifically).

### Risks / gotchas
- The privileged helper logs as root; double-check no buffer contents are interpolated into format strings even at debug level.

---

# Phase 6 — Ship

## Step 16 — Code-signing, hardened runtime, notarization

**Original action item:** AI-13
**Satisfies:** NFR-SEC-4, NFR-INST-2; supports NFR-SEC-2 (Team-ID stability)
**Trust boundary:** **both** targets.

### Objective
Code-sign both the app and the helper, enable the hardened runtime, and notarize so the app launches Gatekeeper-clean on a clean supported Mac.

### Detailed steps
1. **Sign both targets** with a Developer ID (or Apple Distribution) identity under the **same Team ID** the helper pins in Step 3 (NFR-SEC-2 depends on this stability). The embedded helper must be signed and sealed inside the app bundle.
2. **Enable the hardened runtime** (NFR-SEC-4) on both targets. Request **only the entitlements actually required** (NFR-SEC-7) — keep the set minimal.
3. **Notarize:** archive, submit via `notarytool`, and **staple** the ticket to the app (NFR-INST-2).
4. **Verify Gatekeeper-clean launch (NFR-INST-2):** on a **clean** macOS 26 machine (or a fresh user), download/copy the app, confirm it launches without Gatekeeper warnings, registers the helper via `SMAppService` (Step 3), and the helper accepts the now-properly-signed client (Step 3's Team-ID requirement is satisfied by the real signature).
5. **Confirm the install/uninstall lifecycle** end-to-end on the clean machine (Steps 3 & 4) with the signed build.
6. **`os_log`** nothing new required; ensure release logging level is sane.
7. **Release notes (added 2026-08-03, user observation during Step 8).** If Step 9's CPU
   measurement (detailed step 5a) shows the **host** becoming the throughput limit at a transport
   speed this product plausibly meets, say so in the release notes. Conditional on that number,
   not on the one that prompted it: the 36–39% of one core observed at ~500 MB/s during Step 8's
   gate was the gate's own SHA-256 fingerprint, which is **not** in the product's run path.

   > **The condition was measured on 2026-08-04/05, and it is MET. This is no longer conditional.**
   >
   > Measured on the scratch device in the product's own run path, swept across **all four** I/O sizes
   > (`scripts/metrics-check.sh`, 0 failures). At the 4 MiB default, with the device moving
   > ~470 MB/s: in-span host overhead **2.55%** of device I/O time, daemon CPU **4.22% of one
   > core**. So at USB 3.1 Gen 2 the run is **97.4% device-bound** — NFR-PERF-3 is satisfied
   > comfortably, and the 36–39% figure that prompted this item was indeed the gate's SHA-256
   > fingerprint, not the product.
   >
   > **Host cost follows BYTES MOVED, not chunk count** — the question this sweep existed to
   > settle. Across an 8× range of I/O size, µs/MiB varied **1.32×** while µs/chunk varied
   > **8.65×**. **A larger I/O size does not reduce host overhead**, and the release note must not
   > suggest otherwise.
   >
   > Because the cost is per-byte, its *share* of run time rises in proportion to transport speed:
   >
   > | transport | in-span overhead | daemon CPU |
   > |---|---|---|
   > | USB 3.1 Gen 2 (measured, ~470 MB/s) | 2.6% | 4.2% of one core |
   > | USB 3.2 Gen 2×2 (~2 GB/s) | 10.9% | 18.0% of one core |
   > | USB4 / Thunderbolt (~3.8 GB/s) | **20.6%** | **34.1% of one core** |
   >
   > Host work equals device time near **18.4 GB/s**; the daemon saturates one core near
   > **11.1 GB/s**. USB4 enclosures exist and this product plausibly meets them, so **the release
   > notes must say that on the fastest transports a meaningful fraction of run time is host
   > processing rather than device I/O** — while being clear that the run stays device-bound on
   > every transport this tool is likely to meet.
   >
   > **Correction (2026-08-05).** An earlier draft of this note said the daemon saturates one core
   > near **4.7 GB/s**. That was an arithmetic error — a stray factor of 0.5 — and it understated
   > the headroom by more than half. It also rested on a single 4 MiB data point and used the
   > *fastest observed read* as the throughput rather than the run's actual rate. The figures above
   > come from four sizes and wall-clock throughput.
   >
   > **One thing measured but not explained, and deliberately not guessed at.** Total daemon CPU
   > (`getrusage`) fits roughly **209 µs fixed per chunk + 207 µs per MiB**, while the *in-span*
   > overhead follows bytes alone. The difference is work outside the timed span — which the span
   > is documented to exclude, since it stops before the observer is called. What that per-chunk
   > term actually is has not been measured, and the 40–80 µs estimate that stood for three steps
   > was wrong by 11× for exactly the want of measuring rather than reasoning.

8. **Release notes — what a drive's serial number identifies (added 2026-08-05, user decision).**
   The UI and the run report identify the tested drive by its **USB serial number**, because the
   BSD name (`diskN`) is assigned at enumeration and is a different drive after any replug. The
   notes must say what that serial actually names.

   > **It identifies the USB device presented to the host, which is not always the drive.**
   > Measured on the development machine 2026-08-05:
   >
   > | drive | reported serial | what it names |
   > |---|---|---|
   > | Samsung Portable SSD T5 | `12345686DAA9` | the drive — enclosure and drive are one unit |
   > | Samsung 990 EVO Plus in a Ugreen caddy | `013117100578` | **the caddy** |
   > | Seagate Expansion HDD | `00000000NT17XBRA` | the drive |
   >
   > For a bare enclosure the serial belongs to the bridge, so **swapping the drive inside a caddy
   > leaves the reported serial unchanged** — two different SSDs tested in the same caddy will be
   > reported under one identity. Accepted as a limit rather than worked around: nothing visible at
   > the USB block level can see past the bridge, which is the same boundary FR-TEST-9 runs into
   > when it cannot prove a verify read came from NAND.
   >
   > **Some bridges report a placeholder instead of a serial.** The same Ugreen caddy reports a
   > SCSI INQUIRY serial of `0000000000000000`. The app rejects any serial that is a single
   > repeated character, so a placeholder is reported as *no serial* rather than becoming an
   > identifier every drive behind that bridge would share. A drive with no usable serial is
   > labelled as such, and its run report says its results cannot be told apart from an identical
   > model's.
   >
   > The note belongs in the release notes rather than only in the UI because the **exported
   > report outlives the session** — the same reasoning that puts FR-TEST-9's qualification into
   > the report (Step 10, detailed step 3).

### Verification Gate (release gate)
- [ ] `codesign --verify --deep --strict` and `spctl -a -vv` pass on the app; the embedded helper is validly signed under the expected Team ID.
- [ ] Hardened runtime is on; entitlement set is minimal and justified.
- [ ] Notarization succeeds and the ticket is stapled (`stapler validate` passes).
- [ ] On a clean macOS 26 Mac: the app launches with **no Gatekeeper warning**, registers and (after approval) enables the helper, runs a full test on the scratch device, and uninstalls the helper cleanly.
- [ ] The helper's Team-ID code-signing requirement (Step 3) now matches the real signing identity end-to-end.

### Risks / gotchas
- `SMAppService` is unforgiving about signing/notarization: an unsigned or mismatched helper fails to register on a clean system. This step is what makes Step 3 work for real users.
- Test on a machine that has **never** run a dev build of this app, or you'll get false "it works" results from cached approvals.

---

## Appendix A — Action-item → build-step cross-reference

| ADR AI | Build Step |
|--------|-----------|
| AI-1 Xcode workspace | Step 1 |
| AI-2 SMAppService + XPC + code-sig validation | Step 3 |
| AI-3 Device discovery | Step 5 |
| AI-4 Mount-guard / exclusive access | Step 6 |
| AI-5 Raw I/O core | Step 7 |
| AI-6 read→write→verify cycle | Step 8 |
| AI-7 Failure modes + report + Markdown export | Step 10 |
| AI-8 Metrics (throughput + latency) | Step 9 |
| AI-9 Device-loss handling | Step 12 |
| AI-10 Run-control state machine | Step 11 |
| AI-11 Pre-run warnings | Step 14 |
| AI-12 System-sleep prevention | Step 13 |
| AI-13 Signing & distribution | Step 16 |
| AI-14 Helper teardown | Step 4 |
| AI-15 Logging/observability | Step 15 (woven throughout) |
| AI-16 Test abstraction | Step 2 |

## Appendix B — The discipline of this plan

1. **One step at a time.** Do not begin a step until the previous step's Verification Gate is fully checked off.
2. **Simulate before you touch hardware.** Steps 2, 7, 8, 9, 10, 12 all have an in-memory verification *before* the real-device verification. Never debug the algorithm on a drive you can't afford to lose.
3. **Always test on the designated scratch device** (serial `12345686DAA9`) for any real-hardware step. The tool writes raw blocks; treat every hardware run as potentially destructive until proven otherwise. Disk images are **not** an alternative — discovery excludes them by design, and they lack the USB bridge, block device and NAND this tool exists to exercise (amended 2026-08-01).
4. **The trust boundary is sacred.** Raw I/O only ever happens in the helper; the GUI never elevates. Re-confirm this at every step that adds helper code.
5. **Record what you verified.** The full account goes in the commit message; `PROGRESS.md` keeps a summary and the hash. That keeps the deliberate pace auditable without writing it twice.
