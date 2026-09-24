# claude-md-test

A behavioural test of `CLAUDE.md`. Each session gets the same staged report of a walk and is asked
to record it. The question is whether a session reading one version of the file retires the
repository's stale status claims less thoroughly than a session reading another. It was built for
finding F4 of the prompt audit `a063b9d`, which turned the old file's lapse list into rules. It first
ran 2026-09-24, 12:03–12:34. The result is in `PROGRESS.md`'s Model row, and the full account is
the message of `c8ac81e`.

> **Apart from the status line below, nothing in this directory is a status block.** The arms, the
> sites in `score.py` and `stale_context.py`, and `predictions.md` quote the repository as it stood
> at `b708e4e`. `staged-request.txt` and everything under `results/` describe a walk that never
> happened. A grep for a retired claim will find them here. They are fixtures, and editing one
> changes the test: leave them alone.

**Status, 2026-09-24: moved here from the session scratchpad; no real session has run through the
moved scripts.** That day they were checked headlessly, with a stand-in for the CLI. The copies
come out with the same HEADs as the scored runs', the sandbox's controls pass, and the scorers
reproduce `score-all.txt`, `scores.json` and `stale-context.txt` byte for byte. The account is in the message of the commit that
added this file. An edit to any script here lapses that check. So does the first real session,
which also retires this line.

## Arms

Each copy is the repository at `b708e4e`, the last commit before the audit, with its arm's
`CLAUDE.md` folded into that commit. Nothing else differs.

| arm | `CLAUDE.md` | lines | sha256 (first 16) |
|---|---|---|---|
| A | `b708e4e`'s, before the audit | 147 | `0358966ccd2b42e7` |
| B | A with F4 alone (it exists only here) | 131 | `cf99a09088bbafc9` |
| C | `a063b9d`'s, as committed (F1, F4–F7) | 125 | `4a6ee92dcfa582e1` |

The files are `arms/<arm>.CLAUDE.md`, not `CLAUDE.md`. Claude Code loads a file named exactly
`CLAUDE.md` from a subdirectory when a session reads files there. A session in this repository
would then take three old working agreements as its own.

## Files

| file | what it is |
|---|---|
| `common.sh` | sourced by every script: `CMT_WORK`, the base commit, the model, effort and CLI |
| `make_clone.sh <run> <arm>` | makes one run's copy under `$CMT_WORK/w/`, then proves it: a clean tree, the arm's `CLAUDE.md`, no commit after the base in the store, no remote, and every other blob the base's |
| `sandbox_profile.sh <run>` | prints the run's `sandbox-exec` profile |
| `check_sandbox.sh <run> <profile>` | the profile's controls: each denial must fail with *"Operation not permitted"*, and the run's own copy must be readable and writable |
| `run_one.sh <run> [--probe]` | one headless session in the run's copy, after the login, memory and sandbox checks; outputs go to `$CMT_WORK/out/` |
| `run_waves.sh [first-wave]` | the waves of `assign.tsv` in order, each wave's runs in parallel; it stops after a wave in which a run has no clean result |
| `assign.tsv` | run → arm → wave: one run per arm per wave, with ids shuffled so they do not give away the arm |
| `staged-request.txt` | a header, then below the scissors line the body every session was sent |
| `probe.txt` | the probe's one-line request |
| `predictions.md` | the question, sites, predictions and scorer controls, declared 2026-09-24 11:21:13, before any run. Its `request.txt` is the body of `staged-request.txt`. It names CLI 2.1.246; 2.1.280 ran, and `c8ac81e` says why |
| `score.py` | the declared scorer: the sites from each copy's final tree, the process from its stream |
| `stale_context.py` | a reading aid written after the pilot: the lines a session added near a claim it left in place. It is not the declared scorer |
| `results/2026-09-24/` | the first run: `score-all.txt`, `scores.json`, `stale-context.txt`, and `runs.tsv` — times, model, effort, CLI, base commit, `CLAUDE.md` and stream per run. Effort comes from `as-run/run_one.sh`, the rest from each run's outputs. `as-run/` holds the scripts as they ran |

## Re-running it

Run everything in one shell, since every script reads `CMT_WORK`. It must be a fresh directory
outside this repository, `$HOME`, `/Volumes`, `/Applications` and `/Library`, because the sandbox
denies those to the sessions; the scripts refuse any other. Name it neutrally: each session works in
`$CMT_WORK/w/<run>/USBDriveTester` and can see that path.

```bash
export CMT_WORK=/private/tmp/usbdt-$(date +%F)
```

Make the nine copies, and one for the probe:

```bash
awk -F'\t' 'NR > 1 { print $1, $2 }' /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/assign.tsv | while read run arm; do /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/make_clone.sh $run $arm || break; done
```

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/make_clone.sh probe C
```

The probe costs about $0.06 and checks the login, the session limit and the sandbox. It should
print `probe (probe) rc=0 "result":"OK`:

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/run_one.sh probe --probe
```

Then run the waves. On 2026-09-24 a wave took four to five minutes, and the nine sessions cost
$16.61 API-equivalent against the subscription, $1.59–2.09 each:

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/run_waves.sh
```

`run_waves.sh` may stop with exit 5; on 2026-09-24 the cause was the subscription's session limit.
If it does, move the stopped wave's outputs and copies into `out/`, where no session can read them.
Then re-make those copies, probe with a fresh copy (`make_clone.sh probe2 C`), and start again from
that wave with `run_waves.sh <wave>`. If `run_one.sh` then refuses because a copy's auto-memory is
not empty, the failed session wrote some: start over with a fresh `CMT_WORK`. For wave 2:

```bash
w=2; mkdir -p $CMT_WORK/out/failed-wave-$w && for run in $(awk -F'\t' -v w=$w 'NR > 1 && $3 == w { print $1 }' /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/assign.tsv); do mv $CMT_WORK/out/$run.* $CMT_WORK/w/$run $CMT_WORK/out/failed-wave-$w/; done
```

Score, which also writes `$CMT_WORK/out/scores.json`:

```bash
python3 /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/score.py --all > $CMT_WORK/out/score-all.txt
```

```bash
python3 /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/stale_context.py $(awk -F'\t' 'NR > 1' /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/assign.tsv | sort -k2,2 -k3,3n | cut -f1) > $CMT_WORK/out/stale-context.txt
```

Read by hand every site the scorer calls *annotated*, as `predictions.md` says. Then record the run
the way `results/2026-09-24/` and `c8ac81e` do, in a new `results/<date>/` that names the model,
effort and CLI.

## Changing what is measured

- **Model, effort, CLI:** set `CMT_MODEL` (default `claude-opus-5-5`), `CMT_EFFORT` (`high`) and
  `CMT_CLI`. The default CLI is the desktop app's copy of 2.1.280, and its path names that version.
  `ls "$HOME/Library/Application Support/Claude/claude-code"` shows what is there now, and
  `run_one.sh` will not start without a CLI. Each run's `.model` and `.version` record what it used.
- **Another `CLAUDE.md`:** add it as the next letter, `arms/D.CLAUDE.md`, and give it runs in
  `assign.tsv`, one per wave; `score.py` takes its arms from that file. Never reuse or edit an arm.
- **The base, the request or the sites:** changing any of these makes it a different test.
  `score.py`'s sites quote `b708e4e`'s text. A new base or request needs new sites and new
  predictions, declared before any run, as `predictions.md` was.
- **The date:** each session is told the walk was *"this morning"*, in a copy whose last commit is
  2026-09-23 16:41. The later a re-run, the wider that gap, and a session may notice it.

## What differs from the scripts that ran

`results/2026-09-24/as-run/` holds the scripts as they ran, byte for byte. They have the session
scratchpad's paths written in, so they are records, not tools, and are not executable. The scripts
here differ from them only as follows.

- Paths come from `CMT_WORK` and from where this repository is.
- `run_waves.sh` replaces `run_wave.sh`, `chain.sh` and `chain2.sh`, and reads the waves from
  `assign.tsv`.
- The sandbox also denies this repository's transcripts under any earlier volume.
  - On 2026-09-24 it denied only the current path, `-Volumes-1TB-UGreen-…`, so the older
    `-Volumes-1TB-Samsung-…` was readable.
  - No stream named either: a search for `projects/-Volumes-` found 0, and its positive control
    found 63 in the running session's own transcript.
- It denies all of `$CMT_WORK/out/` in place of the scratchpad's named directories. `CMT_DENY`
  adds more.
- `check_sandbox.sh` runs the profile's controls before every session and starts none if one fails.
  On 2026-09-24 three of them were run once, by hand: the repository, another run's copy and
  `log`. The `log` control must see the exec refused, because
  `log` also refuses to run under any sandbox. A check that saw only the failure would pass a
  profile that allowed it.
- `run_one.sh` refuses a copy whose auto-memory is not empty. It sends only the body of
  `staged-request.txt`, checked by its sha256. It also writes `<run>.model`, which the 2026-09-24
  outputs lack.
- `make_clone.sh` also proves three more things. The copy's store holds no commit after the base,
  reachable or not. The copy has no tags. This directory is not in it. It takes the committer from
  the base, where the as-run script had it written in, and the result is the same HEADs.

## Not kept

The streams (2.0–2.8 MB each), the CLI debug logs, the profiles and the copies are not in this
repository. On 2026-09-24 they were in the session scratchpad under `/private/tmp`. `runs.tsv`
gives each stream's size and sha256, so a copy archived elsewhere can be identified.

The limits of the 2026-09-24 run are listed in `c8ac81e`'s message. A re-run inherits three of
them:
- one staged request;
- empty auto-memory;
- sessions that can see where they are. That is `CMT_WORK`'s path and the names, though not the
  contents, of the other runs' copies.
