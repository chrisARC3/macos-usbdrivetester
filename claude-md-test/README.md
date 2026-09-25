# claude-md-test

A behavioural test of `CLAUDE.md`. Each session gets the same staged report of a walk and is asked
to record it. The question is whether a session reading one version of the file retires the
repository's stale status claims less thoroughly than a session reading another. It was built for
finding F4 of the prompt audit `a063b9d`, which turned the old file's lapse list into rules. It first
ran 2026-09-24, 12:03–12:34. The result is in `PROGRESS.md`'s Model row, and the full account is
the message of `c8ac81e`.

> **Apart from the status line below, nothing in this directory is a status block.** The arms are
> fixed versions of `CLAUDE.md`. The sites in `score.py` and `stale_context.py`, and the
> predictions, quote the repository as it stood at `b708e4e`. `staged-request.txt` and everything
> under `results/` describe a walk that never happened. A grep for a retired claim will find them
> here. They are fixtures, and editing one changes the test: leave them alone.

**Status, 2026-09-24 evening: the moved scripts have run real sessions, and on this machine the
test no longer runs as designed.** Arm D's three sessions ran 18:14:49–18:16:47 through the scripts
as committed at `6993096`. The probe, every session's sandbox controls and the wave worked, and each
session ended with a clean result line. None recorded the walk. Two found that the installed app is
no longer the build the staged request names, and stopped to ask; the third stopped to ask about
the daemon's pid. Arm D's question is unanswered (*What a re-run inherits*, below; the full account
is the message of the commit that added its results). The scorers still reproduce the first run's
three files byte for byte in the folder it was made in (*Re-scoring 2026-09-24*). An edit to any
script here lapses what this line says of them.

## Arms

Each copy is the repository at `b708e4e`, the last commit before the audit, with its arm's
`CLAUDE.md` folded into that commit. Nothing else differs.

| arm | `CLAUDE.md` | lines | sha256 (first 16) |
|---|---|---|---|
| A | `b708e4e`'s, before the audit | 147 | `0358966ccd2b42e7` |
| B | A with F4 alone (it exists only here) | 131 | `cf99a09088bbafc9` |
| C | `a063b9d`'s, as committed (F1, F4–F7) | 125 | `4a6ee92dcfa582e1` |
| D | `1230076`'s, as committed: C with the two `BUILD-PLAN.md` incidents back and the note on this directory | 132 | `5fef44a60861e28c` |

The files are `arms/<arm>.CLAUDE.md`, not `CLAUDE.md`. Claude Code loads a file named exactly
`CLAUDE.md` from a subdirectory when a session reads files there. A session in this repository
would then take the arms' working agreements as its own.

## Files

| file | what it is |
|---|---|
| `common.sh` | sourced by every script: `CMT_WORK`, the base commit, the model, effort and CLI |
| `make_clone.sh <run> <arm>` | makes one run's copy under `$CMT_WORK/w/`, then proves it: a clean tree, the arm's `CLAUDE.md`, no commit after the base in the store, no remote, and every other blob the base's |
| `sandbox_profile.sh <run>` | prints the run's `sandbox-exec` profile |
| `check_sandbox.sh <run> <profile>` | the profile's controls: each denial must fail with *"Operation not permitted"*, and the run's own copy must be readable and writable |
| `run_one.sh <run> [--probe]` | one headless session in the run's copy, after the login, memory and sandbox checks; outputs go to `$CMT_WORK/out/` |
| `run_waves.sh [first-wave]` | the waves of `assign.tsv` in order, each wave's runs in parallel; it stops after a wave in which a run has no clean result |
| `assign.tsv` | run → arm → wave. Waves 1–3 are the first run: one run per arm per wave, with ids shuffled so they do not give away the arm. Wave 4 is arm D's three runs |
| `staged-request.txt` | a header, then below the scissors line the body every session was sent |
| `probe.txt` | the probe's one-line request |
| `predictions.md` | the question, sites, predictions and scorer controls, declared 2026-09-24 11:21:13, before any run. Its `request.txt` is the body of `staged-request.txt`. It names CLI 2.1.246; 2.1.280 ran, and `c8ac81e` says why |
| `score.py` | the declared scorer: the sites from each copy's final tree, the process from its stream |
| `stale_context.py` | a reading aid written after the pilot: the lines a session added near a claim it left in place. It is not the declared scorer |
| `results/2026-09-24/` | the first run: `score-all.txt`, `scores.json`, `stale-context.txt`, and `runs.tsv` — times, model, effort, CLI, base commit, `CLAUDE.md` and stream per run. Effort comes from `as-run/run_one.sh`, the rest from each run's outputs. `as-run/` holds the scripts as they ran. `raw.tar.xz` holds the raw outputs, and `raw-manifest.tsv` lists them (*The raw outputs*, below) |
| `results/2026-09-24-D/` | arm D's run, 2026-09-24 18:14:49–18:16:47: `predictions.md`, declared before any of its sessions; `score-all.txt`, `scores.json`, `stale-context.txt` and `runs.tsv` as for the first run, scored in the folder the run was made in, with effort from each run's `.model`. `raw.tar.xz` holds the raw outputs, and `raw-manifest.tsv` lists them. There are no bundles, because no copy has a commit; `copies/heads.tsv` shows each copy at its base. No session recorded the walk |

## Re-running it

Run everything in one shell, since every script reads `CMT_WORK`. It must be a fresh directory
outside this repository, `$HOME`, `/Volumes`, `/Applications` and `/Library`, because the sandbox
denies those to the sessions; the scripts refuse any other. Name it neutrally: each session works in
`$CMT_WORK/w/<run>/USBDriveTester` and can see that path.

```bash
export CMT_WORK=/private/tmp/usbdt-$(date +%F)
```

Make the copies for the waves from `first` on, and one for the probe. `first=1` makes all of them;
arm D's runs are wave 4:

```bash
first=1; awk -F'\t' -v first=$first 'NR > 1 && $3 >= first { print $1, $2 }' /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/assign.tsv | while read run arm; do /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/make_clone.sh $run $arm || break; done
```

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/make_clone.sh probe C
```

The probe checks the login, the session limit and the sandbox. On 2026-09-24 it cost $0.06 in the
first run and $0.14 before arm D's. It should print `probe (probe) rc=0 "result":"OK`:

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/run_one.sh probe --probe
```

Then run the waves from `first` on. In the first run, on 2026-09-24, a wave took four to five
minutes, and the nine sessions cost $16.61 API-equivalent against the subscription, $1.59–2.09
each. Arm D's wave took two minutes and $3.12, because its sessions stopped early:

```bash
/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/run_waves.sh $first
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
python3 /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/stale_context.py $(awk -F'\t' -v first=$first 'NR > 1 && $3 >= first' /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/assign.tsv | sort -k2,2 -k3,3n | cut -f1) > $CMT_WORK/out/stale-context.txt
```

Read by hand every site the scorer calls *annotated*, as `predictions.md` says. Then record the run
the way `results/2026-09-24/` and `c8ac81e` do, in a new `results/<date>/` that names the model,
effort and CLI.

## Changing what is measured

- **Model, effort, CLI:** set `CMT_MODEL` (default `claude-opus-5-5`), `CMT_EFFORT` (`high`) and
  `CMT_CLI`. The default CLI is the desktop app's copy of 2.1.280, and its path names that version.
  `ls "$HOME/Library/Application Support/Claude/claude-code"` shows what is there now, and
  `run_one.sh` will not start without a CLI. Each run's `.model` and `.version` record what it used.
- **Another `CLAUDE.md`:** add it as the next letter, `arms/E.CLAUDE.md`, and give it runs in a new
  wave of `assign.tsv`; `score.py` takes its arms from that file. A wave's runs go in parallel, and
  so far three at a time. Never reuse or edit an arm.
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

## The raw outputs

`results/2026-09-24/raw.tar.xz` holds what the committed results were made from: 154 files, 23 MB
unpacked and 0.8 MB packed. It is compressed so that a grep of the repository does not find the
sessions' text.

| in it | what |
|---|---|
| `out/` | each run's stream (2.0–2.8 MB), CLI debug log, stderr, sandbox profile, base commit and times; the probe's; and the failed attempts', under `failed-session-limit/` and `failed-cli-2.1.246/` |
| `bundles/` | each scored copy's one commit, as a git bundle on its base, and `heads.tsv`: run, base, head |
| `tool-results/` | the two outputs the CLI saved in full, r01's and r08's. Their streams show only a preview |
| `smoke/` | the CLI smoke tests, 11:02–11:03 |
| `as-run/run_one.sh.v2146` | the script of the attempt on CLI 2.1.246. It differs from `as-run/run_one.sh` only in the CLI's path and version line |
| `MANIFEST.tsv` | every other file's size and sha256. `raw-manifest.tsv`, beside the archive, is the same file |

It leaves out the copies, which `make_clone.sh` and the bundles rebuild; the failed attempts'
copies, which were clean at their base; the scorer controls' copies, which `score.py --ideal`
regenerates; and the three files committed beside it. The streams match `runs.tsv`'s sizes and
sha256s.

### Re-scoring 2026-09-24

`score.py` counts a grep as searching the repository, for G1–G3, only when its path lies under
`$CMT_WORK/w/<run>/USBDriveTester`, and the streams hold the paths the sessions saw. The committed
scores were made in place, so they stand, but they come back only in the folder the runs were made
in: that day's session scratchpad. Scored anywhere else, G1 and G2 come out lower for five runs,
all in arms B and C — r02, r05, r06, r07 and r08 — and G3 for three of them. Arm B's G1 average
falls from 2.7 to 1.7, and C's from 3.0 to 1.3. Must, should and X1 do not move.

The folder must not already hold `w/` or `out/`:

```bash
export CMT_WORK=/private/tmp/claude-501/-Volumes-1TB-UGreen-AI-Stuff-claude-code-folder-USBDriveTester/9b3706ab-cf2e-4a65-9796-e2d7dba5cabb/scratchpad
```

```bash
mkdir -p $CMT_WORK && tar -xJf /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/results/2026-09-24/raw.tar.xz -C $CMT_WORK
```

Rebuild the nine copies, waves 1–3 of `assign.tsv`, each with its run's commit:

```bash
awk -F'\t' 'NR > 1 && $3 <= 3 { print $1, $2 }' /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/assign.tsv | while read run arm; do /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/make_clone.sh $run $arm && git -C $CMT_WORK/w/$run/USBDriveTester pull -q --ff-only $CMT_WORK/bundles/$run.bundle main || break; done
```

```bash
python3 /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/score.py --all > $CMT_WORK/out/score-all.txt
```

```bash
python3 /Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester/claude-md-test/stale_context.py r04 r01 r03 r02 r09 r08 r07 r05 r06 > $CMT_WORK/out/stale-context.txt
```

**Checked 2026-09-24** against the archive whose sha256 begins `6ec5f15b631a4d31`: these five
commands, run as written in that folder with the live copies moved aside, gave back
`score-all.txt`, `scores.json` and `stale-context.txt` byte for byte. The same steps in another
folder gave the differences above. **Checked again the same day** with arm D's rows in
`assign.tsv`: `score-all.txt` has one more line, the last, `  D: no scored runs []`, and the rest
is unchanged. *What would invalidate it:* an edit to `score.py`, `stale_context.py`,
`make_clone.sh`, the archive, or `assign.tsv`.

## What a re-run inherits

The limits of the 2026-09-24 run are listed in `c8ac81e`'s message. A re-run inherits three of
them:
- one staged request;
- empty auto-memory;
- sessions that can see where they are. That is `CMT_WORK`'s path and the names, though not the
  contents, of the other runs' copies.

**Found by arm D's run, 2026-09-24: the installed app.** The sandbox lets a session read
`/Applications/USBDriveTester.app`. The staged request says the walk ran on *"the 2026-09-19
10:22:50 install"*, and in the first run that held: six of the nine sessions hashed the app and read
the dylib's `422c89d3…`, the hash every record names for that install. At 18:01:53 the same day,
`68bc16c`'s install put another build there. Its dylib hashes to `e6e6e884…`, while the helper is
still `ac4d5208…`. Two of arm D's three sessions hashed it, found the difference, and stopped to ask
which build the walk ran on. Until `/Applications` holds the build the request names, a run here is
a different test. Each way back is a decision to make before spending on runs:
- reinstall that build;
- make the sandbox hide the app too. The first run had no such denial, so a clean comparison
  needs new runs of every arm;
- write a new request, which needs new sites and predictions.

*What would invalidate this:* the installed dylib hashing to `422c89d3…` again.

A session can also read the other runs' project and temp folders, under `~/.claude/projects` and
`/private/tmp/claude-501`, since the sandbox denies only their copies. `CMT_DENY` can list an
earlier run's, but not a running one's. No arm-D session named one.
