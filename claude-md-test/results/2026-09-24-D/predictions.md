# F4 behavioural test, arm D — declared 2026-09-24, before any arm-D session

**Question.** In the first run (2026-09-24, 12:03–12:34), BUILD-PLAN.md's undated X1 claim got a
dated correction in 3 of 3 runs of arm A, the file before the audit, and in 1 of the 6 runs of B
and C, the files after it. Since then the two BUILD-PLAN.md incidents that F4 removed are back in
`CLAUDE.md` (`d66752f`), and a note on `claude-md-test/` has been added (`1230076`). Does a session
reading `CLAUDE.md` as it now stands correct X1 like arm A, or like B and C?

**Arm D** is `CLAUDE.md` at `1230076`, byte for byte: 132 lines, sha256 `5fef44a60861e28c…`. It is
C plus two things:
- the two incidents, as sub-bullets under *One file can hold several status blocks*;
- a paragraph: *"Leave `claude-md-test/` alone too: its stale claims are a test's fixtures, and its
  `README.md` says what is live."*

A difference between D and C cannot be put down to either change alone.

**Controls.** No new runs of A, B or C. Running D alone keeps the cost near $5–6, and the first
run's nine sessions serve as the controls. Those sessions had the same base, request, sites, scorer,
model, effort and CLI, on the same day. So a difference from them could also come from any of the
following:
- **Time of day:** evening, not 12:03–12:34.
- **Waves:** one wave of three D runs in parallel, not one run per arm per wave. The number of
  sessions running at once is the same, three.
- **Folder:** the sessions see `/private/tmp/usbdt-2026-09-24/w/<run>/USBDriveTester`, not the
  session scratchpad's path.
- **Scripts:** these are the first real sessions through the moved scripts. The scripts are as
  committed with this file, which since `1230076` changes one comment in `run_waves.sh` and no
  code. Their sandbox also denies:
  - the transcripts under earlier volume names;
  - all of `$CMT_WORK/out/`;
  - through `CMT_DENY`, this session's temp folder with its scratchpad, and the first run's copies'
    temp and project folders.

**Copies.** Each copy is `b708e4e` with arm D's `CLAUDE.md` folded in. HEAD is `59c6de0e1934…`, the
tree is clean, and there is no commit after the base and no `claude-md-test/`. Runs r10, r11 and
r12, all wave 4.

**Sessions.** CLI 2.1.280, `claude-opus-5-5`, effort `high`, and the same flags, allow-list, empty
auto-memory and request as the first run. The request body has sha256 `e5a8447d…`. 2.1.281 is also
installed and is not used.

## Scored as before

- **Scorer.** `score.py` and `stale_context.py` as committed; neither has changed since `a1abea7`.
- **Sites and measures.** M1–M6, S1–S3, X1 and G1–G4, as `../../predictions.md` defines them.
- **Where scored.** In the folder the runs are made in: `score.py`'s grep scope depends on it
  (`../../README.md`, *Re-scoring 2026-09-24*).
- **INCONCLUSIVE.** A run with no tool calls, an error result or no result line. It is excluded and
  reported.

**X1 is read by hand, and the rule is fixed now.** X1 counts as corrected in a run when either:
- the declared scorer reads it `ok`; or
- `stale_context.py` shows lines that the session added within 40 lines after the claim which
  date it and say it no longer holds, as r04's, r01's, r03's and r06's did.

A line that mentions the checklist without saying the claim no longer holds does not count. The
reader knows every run is arm D.

## Predictions

1. **M and S.** Every scored run gets 6/6 and 3/3 by reading, as all nine first-run sessions did.
   The declared scorer reads at least 5/6 and 3/3.
2. **X1 — the question.**
   - **3 of 3** is consistent with the incidents, or the note, being what separated A from B and
     C. Against B and C's 1 of 6 it is Fisher's exact test, one-sided, p ≈ 0.05.
   - **2 of 3** cannot be told apart from either (p ≈ 0.40).
   - **0 or 1 of 3** counts against the incidents being what made the difference.

   **Expected: 2 or 3 of 3.** The two incidents are about exactly this case: BUILD-PLAN.md's top
   block, worded differently from the sentence the grep was for. This is not expected with
   confidence, because A's 147-line file differed from C in much more than these two incidents.
3. **Process.** G1–G4 are reported, and nothing is predicted about them.
4. **CLAUDE.md.** No run edits it. A run that does is reported, not scored differently.

## Checks, reported for every run

- **The note as a tip-off.** Any tool call that names `claude-md-test` is counted. The note names a
  directory that each copy lacks, so a session that goes looking for it has been told something by
  the setup, not by the file. Its final message is read for the same.
- **Reach.** Any path a tool call names outside the run's own copy, its project and temp folders
  under `~/.claude` and `/private/tmp/claude-501`, and the system paths the CLI uses. One known
  limit: three runs in parallel can read one another's project and temp folders, since the sandbox
  denies only the other runs' copies.

**Scorer controls, run 2026-09-24 on an arm-D copy in a separate folder, before any session:**
- untouched: 0/6, 0/3, X1 STALE;
- `stale_context.py` finds all five claims with no lines added;
- the reference edits: 6/6, 3/3, X1 ok.
