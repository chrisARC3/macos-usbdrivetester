# Working agreement

macOS app + privileged helper that read → write-back → verify a whole USB drive. Swift 6,
SwiftUI, `SMAppService`, XPC.

**This file holds only what is not written elsewhere.** It does not restate the plan, the
constraints or the history — those are the four documents below, and duplicating them is how they
drift.

| Read | For |
|---|---|
| `PROGRESS.md` — the **Current state** block first | Where the work actually is. It holds **one step only**; when a step closes it is archived to `progress/step-NN.md` and the file is re-cut for the next one. If it ever regrows *"Where increment N starts"* blocks, those are dated snapshots and only **Current state** is current |
| `BUILD-PLAN.md` | The steps, their verification gates, and the build/test/install recipes |
| `CONSTRAINTS.md` | Measured platform facts, working practice (§2) and the lessons (§3). **Read before designing anything** — most of it was paid for |
| `progress/step-NN-human-checklist.md` | What only a person at a keyboard can check, and why each item exists. Step 11's is the worked example — 16 chunks — and **its passes do not transfer to later work**. A step that changes behaviour a person must verify needs its own |

---

## Recording that something passed

**A pass is a fact about one build on one day, not a property of the project.** Every recorded
pass — a checklist item, a gate, a hardware script, a mutation round — carries:

1. **the date**, and
2. **what it ran against**: the commit, the protocol version, the helper source hash, or the
   installed app's build time, whichever is the thing that could move underneath it.

The date alone is not enough, and this is not theoretical:

> Checklist **6.3** — *"Cancel and Quit stops at a chunk boundary, releases, quits"* — passed
> **2026-08-18** and carried that date. Increment 8 made the run report a **sheet** four days
> later, which silently broke it. Nobody re-walked it for **thirteen days**, because *"chunks 1–7
> passed in full"* reads like a property when it is a date. What was missing was not a timestamp —
> it had one — but the build it was true of, and therefore any way to notice that the build had
> moved.

> Step 11's verification gate items 2, 3 and 5 rest on `run-control-check.sh`, which as of
> 2026-09-04 had last run **2026-08-24 against a protocol v12 daemon** — and the protocol went to
> **v14** in increment 11. That row named its protocol, which is exactly why the staleness was
> findable at all; it was the *second* lapse of that same shape in that same gate, the first being
> v10 → v12. **Re-run against v14 and passed 2026-09-05.**

So when you write a pass down, also write **what would invalidate it**. When you change something,
grep for passes recorded against it. `CONSTRAINTS.md` §2 states the rule this serves: *a gate that
has not been re-run cannot report anything.*

**A status block that disagrees with the body is worse than no status block.** When one is edited,
every other status block in the repository is edited in the same commit — `grep -rn` is the check,
and this project has now paid for skipping it **ten** times. **Grep for the claim, not for the
filename.** Snapshot blocks are the exception: correct them by annotating with a date, never by
rewriting them to match today.

The last five are the shape of the problem. The sixth, seventh, eighth and tenth were each in a
place the previous fix had not thought of; the ninth was not:

- **Sixth, 2026-09-05** — `BUILD-PLAN.md` holds **two** status blocks, 400 lines apart, and Step 12's
  chunks 1 and 2 updated only the lower one.
- **Seventh, 2026-09-06** — `PROGRESS.md`'s cold-start block, three chunks and a protocol bump
  stale, in the file whose entire job is to say where the work is. **The first one outside
  `BUILD-PLAN.md`.**
- **Eighth, 2026-09-07** — `README.md` said *"Step 12 … is next and is not yet started"*, wrong for
  seven chunks. Nobody thought of the README as a place where the current step is named. **It is.**
- **Ninth, 2026-09-10** — `README.md` and `PROGRESS.md`'s cold start, **both already on the list**,
  said *"chunk 3 must be re-walked from the top"* through all six of chunk 3's commits. Each commit
  added *"chunk 3 CLOSED"* to the blocks it was looking at, and none grepped for the sentence it was
  making false. **Grep for the claim being retired, not the one being added** — knowing where the
  five blocks are does not help when the grep is for the new sentence. **And the fix for it had the same
  gap**: `6be81e1` grepped for *"must be re-walked"* and missed three sites saying the same thing in
  other words — PROGRESS's Owed row (*"owed a re-walk from item 1"*), its reading list (*"chunks 3,
  4 and 5 are not walked"*) and BUILD-PLAN's *"so chunk 3's re-walk can tell"*. A claim has several
  wordings: **grep each noun in it**, and treat a grep that finds nothing for *every* pattern as a
  broken instrument, the way a zero test total is.
- **Tenth, found 2026-09-10** — `progress/step-12-human-checklist.md`'s own header said *"STATUS:
  UNWALKED … Nothing here has been run"* through three chunks' walks and thirteen commits to that
  file. It names no step, so the grep for the five blocks below never reaches it. **A checklist's
  status line is a status block about itself**: the commit that fills in a **Walked** line edits it
  too.

**Four files name the current step**: `README.md`, `PROGRESS.md` (cold start *and* Current state)
and `BUILD-PLAN.md` (twice). That is five blocks, and the grep has to find all five.

---

## How work is done here

- **Plan an increment in chunks and get approval before each one.** Keep the suite green between
  chunks and ratchet `scripts/.test-floor`.
- **The full account of an increment goes in its commit message**, with a summary in `PROGRESS.md`.
  Do not write it at length twice.
- **Commit straight to `main`. Never push unless asked.**
- **The user does the GUI and Xcode clicks.** Verify everything possible headlessly first. Any
  command handed to the user must use **absolute paths** and be pasteable as-is.
- **Name a drive by its capacity** — "the 4 TB T5 EVO", never a bare "the T5". Three of the
  attached drives are T5s.
- **Check whether a change moves the helper source hash.** If it does, every hardware gate result
  recorded against the old hash lapses with it. The recipe is in `PROGRESS.md`'s Helper row.

## Mutation rounds

The discipline is in `BUILD-PLAN.md`; the three that bite:

- **Assert the anchor is unique** (`assert text.count(old) == 1`). A mutation that patched the
  wrong site once reported *"SURVIVED: all 0 tests passed"*.
- **A zero test total is INCONCLUSIVE**, never a pass and never a failure.
- **Restore from a saved pristine copy**, never `git checkout <file>` — that reverts to HEAD and
  takes uncommitted work with it.

**Declare expected survivors in advance.** A predicted survivor is evidence; an unexpected one is a
finding. Survivors that are real gaps get tests; survivors that are genuinely uncoverable go in the
checklist's *"What has no automated cover"* list with what a person checks instead.

## When an instrument and the product disagree

Assume the instrument. Three of the four defects found in the week of 2026-09-04 were in the
checklist or the logging, not in the app — a walk instruction that had quietly stopped working, an
item asking for a reading off a log line that did not carry it, and an error channel firing 17 false
positives per test run. Check what the log line actually says and which process emitted it before
reporting a product defect.
