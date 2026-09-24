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
and this project has skipped it more than a dozen times. **Grep for the claim, not for the
filename.** Snapshot blocks are the exception: correct them by annotating with a date, never by
rewriting them to match today.

How to grep:

- **Grep for the claim being retired, not the one being added.** The new sentence is where you put
  it; the old one is wherever nobody was looking.
- **A claim has several wordings: grep each noun in it** — the step, the chunk, the figure, the
  hash — and treat a grep that finds nothing for *every* pattern as a broken instrument, the way a
  zero test total is.
- **One file can hold several status blocks**, each wording the same state differently; editing the
  one in front of you is not the check.
- **Grep the sources too, doc comments included** — a claim about what the code does is also
  written on the code.
- **An install retires the old build's hash everywhere it is named as current** — grep for the
  hash.

Each of these was paid for by a stale claim that shipped; the incidents are in the documents'
dated notes and in this file's git history.

**Three files name the current step**: `README.md`, `PROGRESS.md` (cold start *and* Current state)
and `BUILD-PLAN.md` (**three times** — the block under the title, the *"Status, …"* block under
`## Sequence overview`, and the gates-and-figures annotation ~120 lines below it). That is **six**
blocks, and the grep has to find all six.

The list of places is a hint; **the grep is the instrument**, and a count in a rule is itself a
status claim.

**A checklist's status line is a status block about itself** —
`progress/step-11-human-checklist.md`, `step-12-human-checklist.md` and `step-13-human-checklist.md`
each carry one. It names no step, so a step-name grep never reaches it: the commit that fills in a
**Walked** line edits it too.

**A measured figure is a status claim too, including in documents that name no step** —
`nonfunctional-requirements-usb-drive-tester.md` carries several that none of the six blocks
reaches. When a measurement moves, grep the bare number and unit, not a phrase around it, as well
as the sentence; and leave the archived `progress/step-NN.md` copies alone, because those are
records of what was true.

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
