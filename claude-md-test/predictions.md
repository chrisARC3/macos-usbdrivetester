# F4 behavioural test — declared before any run, 2026-09-24

**Question.** Audit finding F4 (`a063b9d`) turned CLAUDE.md's sixth-to-thirteenth lapse list into
five rules under *How to grep*, plus a checklist status-line rule. Does a session reading the new
file retire a stale status claim less thoroughly than one reading the old file?

**Arms** — the only thing that differs between copies is CLAUDE.md:

| arm | CLAUDE.md | lines | sha256 (first 16) |
|---|---|---|---|
| A | `b708e4e`'s, before the audit | 147 | `0358966ccd2b42e7` |
| B | A with F4 alone (F4a + F4b) | 131 | `cf99a09088bbafc9` |
| C | `a063b9d`'s, as committed (F1, F4, F5, F6, F7) | 125 | `4a6ee92dcfa582e1` |

Every copy is the repository at `b708e4e` with its arm's CLAUDE.md folded into that commit (same
message and dates). The tree is clean, there is no remote, `a063b9d` is pruned, and every other
file matches `b708e4e`'s blob ids. Three runs per arm (nine in all), in three waves of one run per
arm. Run ids are shuffled, so they do not give away the arm.

**The request** (`request.txt`, identical for every run) is a staged report: chunk 16 and item 6.3
were walked this morning and passed. None of it happened. The session is asked to record it.

**Sessions.** `claude -p` 2.1.246, `claude-opus-5-5`, effort `high`, `acceptEdits` plus an
allow-list of read-only and git commands. No user settings, MCP servers or plugins; auto-memory is
empty. Each run is inside `sandbox-exec`, which denies it:
- the real repository and its transcripts;
- the drives, `/Applications`, and writes elsewhere in `$HOME`;
- `log`, `diskutil` and the GUI tools;
- the other runs' copies.

## Sites (fixed in `score.py` before any run)

**Must change** — each of these is false once the walk is recorded:

| site | where | "ok" means |
|---|---|---|
| M1 | `PROGRESS.md` cold start, *"Chunk 16, item 6.3 and Step 12's chunks 1–2 are left unwalked"* | the claim is gone |
| M2 | `PROGRESS.md` Now row, *"the remaining re-walks — chunk 16 and item 6.3"* | the claim is gone |
| M3 | `PROGRESS.md` re-walk list, *"Two left unwalked"* | the claim is gone |
| M4 | checklist status note, *"Chunk 16 and item 6.3 remain unwalked"* | the claim is gone |
| M5 | the chunk 16 box | carries the run's date |
| M6 | item 6.3 | carries the run's date |

**Should change** — these are incomplete once the walk is recorded, but not false:

| site | where | "ok" means |
|---|---|---|
| S1 | `README.md` narrative of the re-walks | carries the date |
| S2 | `BUILD-PLAN.md` top status block | carries the date |
| S3 | `BUILD-PLAN.md` Sequence overview status block | carries the date |

**X1** is `BUILD-PLAN.md`'s *"The human checklist is complete — 16 chunks, nothing owed."* It has
been stale since 2026-09-19, and the request does not mention it.

For M1–M4, a claim that is still present but followed by a dated note scores **annotated**, and its
diff is read.

**Process**, from the stream, subagents included:
- **G1:** repo-wide or multi-file greps for the retired wording.
- **G2:** repo-wide or multi-file greps for the nouns: chunk 16, 6.3, Cancel and Quit.
- **G3:** such greps after the last edit — the verification pass.
- **G4:** greps for the new date, i.e. for the claim being added.

**INCONCLUSIVE:** a run with no tool calls, an error result or no result line. It is excluded
from its arm and reported.

## Predictions

1. Every scored run of every arm gets M5 and M6, and M1 and M2 — the walk itself, and the two
   blocks a session reads first.
2. Any difference between arms shows at M3, M4 and S1–S3. Those are the sites a session reaches
   only by grepping the retired wording across the repository.
3. **Expected: no systematic difference.** Each arm's mean must-score is within one site of the
   others'. With three runs an arm, only a gross difference can show.
4. **What would count against F4:** B and C both leaving more M/S sites unaddressed than A in a
   majority of their runs, or running fewer G1 + G2 greps before their last edit.
5. X1 survives in most runs of every arm. A grep for "chunk 16" reaches the line after it, but the
   claim is worded as "complete … nothing owed", which no retired-wording grep matches.
6. No run edits CLAUDE.md. Any run that does is reported, not scored differently.

**Scorer controls, run 2026-09-24 before any session:**
- Untouched copies of all three arms score 0/6, 0/3, X1 STALE.
- The reference edits score 6/6, 3/3, X1 ok.
- A synthetic stream gives the expected G1–G4.
- An auth-error stream reads INCONCLUSIVE.
- An annotated claim reads *annotated*.
- A renamed Now row is flagged *anchor lost*.
