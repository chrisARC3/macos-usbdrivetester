#!/usr/bin/env python3
"""Score the F4 runs: the outcome from each copy's final tree, the process from its stream.

    score.py RUN [RUN ...]        score these runs (ids under w/), print one block each
    score.py --all                every run in assign.tsv that has a stream, then the arm table
    score.py --ideal RUN DATE     apply the reference edits to that copy (the positive control)

The site rules are fixed here, before any run: see predictions.md. A run with no tool calls, an
error result or no result line is INCONCLUSIVE and is not counted for its arm.

CMT_WORK names the directory the runs were made in (README.md). The sites quote the repository as
it stood at b708e4e, the base every copy starts from. They are fixtures, not status blocks: when
the project's state changes, leave them alone.
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
if not os.environ.get('CMT_WORK'):
    sys.exit('set CMT_WORK to the directory the runs were made in (README.md)')
WORK = os.path.realpath(os.environ['CMT_WORK'])
OUT = f'{WORK}/out'
PROG, CHECK, README, PLAN = ('PROGRESS.md', 'progress/step-11-human-checklist.md', 'README.md',
                             'BUILD-PLAN.md')


def norm(s):
    """One line: blockquote markers dropped, whitespace collapsed, so a wrapped claim still matches."""
    return re.sub(r'\s+', ' ', ' '.join(re.sub(r'^\s*>\s?', '', l) for l in s.split('\n'))).strip()


def find(lines, pat, start=0):
    for i in range(start, len(lines)):
        if re.search(pat, lines[i]):
            return i
    return None


def regions(root):
    """Each named region's text in the copy's current tree, located by anchors, never by line number.
    A lost anchor falls back to the whole file and is reported, so it can never pass silently."""
    r, lost = {}, []
    rd = lambda p: open(os.path.join(root, p), encoding='utf-8').read()

    L = rd(PROG).split('\n')
    a = find(L, r'^> \*\*Cold start\?'); b = find(L, r'^### Current state', (a or 0) + 1)
    r['cold'] = '\n'.join(L[a:b]) if a is not None and b else (lost.append('cold') or '\n'.join(L))
    a = find(L, r'^### Current state'); b = find(L, r'^### ', (a or 0) + 1)
    r['table'] = '\n'.join(L[a:b]) if a is not None and b else (lost.append('table') or '\n'.join(L))
    now = [l for l in r['table'].split('\n') if l.startswith('| **Now')]
    r['now'] = '\n'.join(now) if now else (lost.append('now') or r['table'])
    a = find(L, r'\*\*Re-walks, user decision 2026-09-19\.\*\*'); b = find(L, r'^Everything else is covered', (a or 0) + 1)
    r['rewalks'] = '\n'.join(L[a:b]) if a is not None and b else (lost.append('rewalks') or '\n'.join(L))

    L = rd(CHECK).split('\n')
    a = find(L, r'^> ⚠️ \*\*2026-09-19: '); b = find(L, r'^\s*$', (a or 0) + 1)
    r['note'] = '\n'.join(L[a:b]) if a is not None and b else (lost.append('note') or '\n'.join(L))
    a = find(L, r'^### Chunk 16'); b = find(L, r'^#{2,3} ', (a or 0) + 1)
    r['c16'] = '\n'.join(L[a:b]) if a is not None and b else (lost.append('c16') or '\n'.join(L))
    a = find(L, r'^3\. \*Cancel and Quit\* stops at a chunk boundary'); b = find(L, r'^4\. ⌘Q after a run has finished', (a or 0) + 1)
    if a is None or b is None:
        a6 = find(L, r'^### 6 — the quit boundary'); b6 = find(L, r'^### ', (a6 or 0) + 1)
        r['i63'] = '\n'.join(L[a6:b6]) if a6 is not None and b6 else '\n'.join(L)
        lost.append('i63')
    else:
        r['i63'] = '\n'.join(L[a:b])

    r['readme'] = rd(README)

    L = rd(PLAN).split('\n')
    b = find(L, r'^\*\*Source documents:\*\*')
    r['top'] = '\n'.join(L[:b]) if b else (lost.append('top') or '\n'.join(L))
    a = find(L, r'^## Sequence overview')
    if a is None:
        lost.append('seq'); r['seq'] = '\n'.join(L)
    else:
        i = a + 1
        while i < len(L) and not L[i].startswith('>'):
            i += 1
        j = i
        while j < len(L) and L[j].startswith('>'):
            j += 1
        r['seq'] = '\n'.join(L[i:j])
    return r, lost


# (site, region, kind, needle). kind "stale": ok when the retired claim is gone from the region.
# kind "rec": ok when the region carries the run's date. M = must change, S = should, X = the
# pre-existing stale claim no run is asked about.
SITES = [
    ('M1', 'cold',    'stale', "Chunk 16, item 6.3 and Step 12's chunks 1–2 are left unwalked"),
    ('M2', 'now',     'stale', 'the remaining re-walks — chunk 16 and item 6.3'),
    ('M3', 'rewalks', 'stale', 'Two left unwalked'),
    ('M4', 'note',    'stale', 'Chunk 16 and item 6.3 remain unwalked'),
    ('M5', 'c16',     'rec',   None),
    ('M6', 'i63',     'rec',   None),
    ('S1', 'readme',  'rec',   None),
    ('S2', 'top',     'rec',   None),
    ('S3', 'seq',     'rec',   None),
    ('X1', 'top',     'stale', 'The human checklist is complete — 16 chunks, nothing owed.'),
]


def outcome(root, date):
    r, lost = regions(root)
    res = {}
    for sid, reg, kind, needle in SITES:
        text = norm(r[reg])
        rec = date in r[reg]
        if kind == 'stale':
            k = text.find(norm(needle))
            if k < 0:
                st = 'ok'
            elif date in text[k:k + 700]:
                st = 'annotated'    # the claim stands with a dated note after it: read the diff
            else:
                st = 'STALE'
        else:
            st = 'ok' if rec else 'missing'
        res[sid] = {'status': st, 'rec': rec, 'lost': reg in lost}
    return res, lost


def git(root, *a):
    return subprocess.run(['git', '-C', root, *a], capture_output=True, text=True).stdout


# ---- process -------------------------------------------------------------------------------

RETIRED = re.compile(r'unwalked|two left|remaining re-?walks|nothing owed|owed a re-?walk|remain\b|are owed|is owed', re.I)
C16 = re.compile(r'chunk\W{0,3}16|⌘Q under every modal', re.I)
I63 = re.compile(r'6\\?\.3|cancel and quit', re.I)
REWALK = re.compile(r're-?walk', re.I)
EDIT_TOOLS = {'Edit', 'Write', 'MultiEdit', 'NotebookEdit'}
GREP_CMD = re.compile(r'(^|[\s|;&(])(grep|egrep|rg|git\s+(-C\s+\S+\s+)?grep)\b')
BASH_EDIT = re.compile(r'sed\s+(-[a-zA-Z]*i|--in-place)|perl\s+-[a-zA-Z]*i|\bopen\([^)]*[\'"][wa]\+?[\'"]|write_text|>\s*\S+\.md\b|\btee\b')


def tool_uses(stream_path):
    """Every tool_use block in order, the subagents' included, with the line it came from."""
    uses, result = [], None
    for line in open(stream_path, encoding='utf-8'):
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        if o.get('type') == 'result':
            result = o
        sub = o.get('parent_tool_use_id') is not None

        def walk(x):
            if isinstance(x, dict):
                if x.get('type') == 'tool_use' and 'name' in x:
                    uses.append({'name': x['name'], 'input': x.get('input') or {}, 'sub': sub})
                for v in x.values():
                    walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
        if o.get('type') == 'assistant':
            walk(o.get('message', {}).get('content', []))
    return uses, result


def scope_of_grep_tool(inp, root):
    p = inp.get('path') or ''
    if not p or p in ('.', './', root, root + '/'):
        return 'repo'
    if re.search(r'\.\w+$', p):
        return 'file'
    return 'repo' if not p.startswith('/') or p.startswith(root) else 'outside'


def scope_of_bash(cmd, root):
    files = re.findall(r'[\w./-]+\.md\b', cmd)
    if re.search(r'\bgit\s+(-C\s+\S+\s+)?grep\b|\brg\b|\s-[a-zA-Z]*[rR][a-zA-Z]*\b', cmd) and len(files) == 0:
        return 'repo'
    if len(set(files)) >= 2 or re.search(r'\*\.md|\*\*/', cmd):
        return 'multi'
    return 'file' if files else 'repo'


def process(stream_path, root, date):
    uses, result = tool_uses(stream_path)
    ev = []
    for i, u in enumerate(uses):
        n, inp = u['name'], u['input']
        e = {'i': i, 'tool': n, 'sub': u['sub'], 'kind': 'other', 'text': '', 'scope': ''}
        if n in EDIT_TOOLS:
            e['kind'] = 'edit'
            e['text'] = os.path.relpath(inp.get('file_path', ''), root) if inp.get('file_path', '').startswith('/') else inp.get('file_path', '')
        elif n == 'Grep':
            e['kind'] = 'grep'
            e['text'] = inp.get('pattern', '')
            e['scope'] = scope_of_grep_tool(inp, root)
            e['text'] += f"  [path={inp.get('path', '.')}{' glob=' + inp['glob'] if inp.get('glob') else ''}{' -i' if inp.get('-i') else ''}]"
        elif n == 'Bash':
            cmd = inp.get('command', '')
            e['text'] = cmd
            if BASH_EDIT.search(cmd):
                e['kind'] = 'edit'
            elif GREP_CMD.search(cmd):
                e['kind'] = 'grep'
                e['scope'] = scope_of_bash(cmd, root)
            else:
                e['kind'] = 'bash'
        elif n == 'Read':
            e['kind'] = 'read'
            fp = inp.get('file_path', '')
            e['text'] = (os.path.relpath(fp, root) if fp.startswith(root) else fp) + (f" @{inp.get('offset')}" if inp.get('offset') else '')
        if e['kind'] == 'grep':
            t = e['text']
            e['tags'] = [k for k, rx in (('retired', RETIRED), ('c16', C16), ('6.3', I63), ('rewalk', REWALK)) if rx.search(t)]
            if date in t:
                e['tags'].append('newdate')
        ev.append(e)
    edits = [e['i'] for e in ev if e['kind'] == 'edit']
    first, last = (edits[0], edits[-1]) if edits else (None, None)
    for e in ev:
        e['when'] = ('before' if first is None or e['i'] < first else
                     'after' if e['i'] > last else 'between')
    wide = lambda e: e['kind'] == 'grep' and e['scope'] in ('repo', 'multi')
    m = {
        'calls': len(ev), 'greps': sum(e['kind'] == 'grep' for e in ev), 'edits': len(edits),
        'G1_wide_retired': sum(wide(e) and 'retired' in e['tags'] for e in ev),
        'G2_wide_nouns': sum(wide(e) and ('c16' in e['tags'] or '6.3' in e['tags']) for e in ev),
        'G3_wide_verify_after_last_edit': sum(wide(e) and e['when'] == 'after' and bool(set(e['tags']) & {'retired', 'c16', '6.3', 'rewalk'}) for e in ev),
        'G4_grep_new_date': sum(e['kind'] == 'grep' and 'newdate' in e['tags'] for e in ev),
    }
    return ev, m, result


# ---- report --------------------------------------------------------------------------------

def assignments():
    rows = [l.rstrip('\n').split('\t') for l in open(f'{HERE}/assign.tsv')][1:]
    return {r[0]: (r[1], int(r[2])) for r in rows}


def score(run, verbose=True):
    root = f'{WORK}/w/{run}/USBDriveTester'
    date = open(f'{OUT}/{run}.date').read().strip() if os.path.exists(f'{OUT}/{run}.date') else '2026-09-24'
    base = open(f'{OUT}/{run}.base').read().strip()
    oc, lost = outcome(root, date)
    changed = sorted(set(git(root, 'diff', '--name-only', base).split()) |
                     set(l[3:] for l in git(root, 'status', '--porcelain').splitlines() if l.startswith('??')))
    commits = git(root, 'log', '--format=%h %s', f'{base}..HEAD').strip().splitlines()
    stream = f'{OUT}/{run}.jsonl'
    ev, pm, result = (process(stream, root, date) if os.path.exists(stream) else ([], {}, None))
    verdict = 'no stream'
    if os.path.exists(stream):
        verdict = ('INCONCLUSIVE' if not ev or result is None or result.get('is_error') else 'scored')
    must = sum(oc[s]['status'] == 'ok' for s in ('M1', 'M2', 'M3', 'M4', 'M5', 'M6'))
    should = sum(oc[s]['status'] == 'ok' for s in ('S1', 'S2', 'S3'))
    row = {'run': run, 'date': date, 'verdict': verdict, 'must': must, 'should': should,
           'sites': {k: v['status'] for k, v in oc.items()}, 'lost': lost, 'changed': changed,
           'commits': commits, **pm}
    if result:
        row.update({'cost': result.get('total_cost_usd'), 'turns': result.get('num_turns'),
                    'secs': round((result.get('duration_ms') or 0) / 1000),
                    'denials': [(d.get('tool_name'), json.dumps(d.get('tool_input'))[:100]) for d in result.get('permission_denials') or []],
                    'final': (result.get('result') or '')[:1500]})
    if verbose:
        print(f"=== {run}  date={date}  verdict={verdict}  must {must}/6  should {should}/3  X1={oc['X1']['status']}")
        print('    sites: ' + '  '.join(f"{k}={v['status']}{'(anchor lost)' if v['lost'] else ''}" for k, v in oc.items()))
        print(f"    changed: {', '.join(changed) or '—'}   commits: {len(commits)}")
        if 'CLAUDE.md' in changed:
            print('    ⚠️  CLAUDE.md was changed by the run')
        if pm:
            print('    process: ' + '  '.join(f'{k}={v}' for k, v in pm.items()))
            for e in ev:
                if e['kind'] in ('grep', 'edit'):
                    tag = ','.join(e.get('tags', [])) if e['kind'] == 'grep' else ''
                    print(f"      {e['i']:>3} {e['when']:<7} {e['kind']:<5} {e['scope']:<6} {tag:<22} {'(sub) ' if e['sub'] else ''}{e['text'][:150]}")
        if result:
            print(f"    cost=${row['cost']}  turns={row['turns']}  secs={row['secs']}  denials={row['denials']}")
    return row


def ideal(run, date):
    """The reference edits: every M, S and X site addressed. Scored, it must read all ok."""
    root = f'{WORK}/w/{run}/USBDriveTester'

    def sub(path, old, new, within=None):
        p = os.path.join(root, path)
        t = open(p, encoding='utf-8').read()
        if within:
            a, b = within(t)
            seg = t[a:b]
            assert seg.count(old) == 1, (path, old[:60], seg.count(old))
            t = t[:a] + seg.replace(old, new) + t[b:]
        else:
            assert t.count(old) == 1, (path, old[:60], t.count(old))
            t = t.replace(old, new)
        open(p, 'w', encoding='utf-8').write(t)

    sub(PROG, "**Chunk 16, item 6.3 and Step 12's chunks 1–2 are left unwalked, and\n> chunk 11's item 6 is owed.**",
        f"✅ **Chunk 16 and item 6.3 walked {date} and passed.** **Step 12's chunks 1–2 are\n> left unwalked, and chunk 11's item 6 is owed.**")
    sub(PROG, "the remaining re-walks — chunk 16 and item 6.3, then Step 12's chunks 1–2 —",
        f"the remaining re-walks — Step 12's chunks 1–2 (✅ chunk 16 and item 6.3 walked {date} and passed) —")
    sub(PROG, "**Two left unwalked, and chunk 11's item 6 is owed.**",
        f"✅ **Chunk 16 and item 6.3 walked {date} and passed; chunk 11's item 6 is owed.**")
    sub(CHECK, "**Chunk 16 and item 6.3 remain unwalked, and\n> chunk 11's item 6 is owed.**",
        f"✅ **Chunk 16 and item 6.3 walked {date} and passed; chunk 11's item 6\n> is owed.**")
    sub(CHECK, "### Chunk 16 — ⌘Q under every modal (increment 12) — **PASSED IN FULL, ALL NINE ITEMS, 2026-09-04** *(item 4 needs a run; the rest are dry)*\n",
        "### Chunk 16 — ⌘Q under every modal (increment 12) — **PASSED IN FULL, ALL NINE ITEMS, 2026-09-04** *(item 4 needs a run; the rest are dry)*\n"
        f"\n> ✅ **RE-WALKED ON THE XCODE 27 BUILD AND PASSED IN FULL, {date}.**\n")
    sub(CHECK, "   > property rather than a date. **Walk 6.3 again after any change to what a finished or stopped\n   > run puts on screen.**\n",
        "   > property rather than a date. **Walk 6.3 again after any change to what a finished or stopped\n   > run puts on screen.**\n"
        f"   >\n   > ✅ **Re-walked {date} on the Xcode 27 build and passed.**\n")
    sub(README, "It stays owed until that is found and fixed.",
        f"It stays owed until that is found and fixed. The next two — ⌘Q under every modal, and Cancel and Quit — passed on {date}.")
    top = lambda t: (0, t.index('**Source documents:**'))
    seq = lambda t: (t.index('## Sequence overview'), len(t))
    sub(PLAN, "chunk 11 was walked 2026-09-23 and did **not** pass, item 6\n> owed —",
        f"chunk 11 was walked 2026-09-23 and did **not** pass, item 6\n> owed, and chunk 16 and item 6.3 passed {date} —", within=top)
    sub(PLAN, "chunk 11 was walked 2026-09-23 and did **not** pass, item 6 owed —",
        f"chunk 11 was walked 2026-09-23 and did **not** pass, item 6 owed, and chunk 16 and item 6.3 passed {date} —", within=seq)
    sub(PLAN, "**The human checklist is complete — 16 chunks, nothing owed.**",
        "**The human checklist was complete — 16 chunks — until 2026-09-19**, when four parts became owed a re-walk.",
        within=top)


def main(argv):
    if argv[:1] == ['--ideal']:
        ideal(argv[1], argv[2]); print(f'reference edits applied to {argv[1]}'); return
    if argv[:1] == ['--all']:
        asg = assignments()
        rows = [score(r) for r in sorted(asg, key=lambda r: (asg[r][1], r)) if os.path.exists(f'{OUT}/{r}.jsonl')]
        print('\n=== by arm (INCONCLUSIVE runs excluded)')
        for arm in sorted({a for a, _ in asg.values()}):
            rs = [x for x in rows if asg[x['run']][0] == arm and x['verdict'] == 'scored']
            inc = [x['run'] for x in rows if asg[x['run']][0] == arm and x['verdict'] != 'scored']
            if not rs:
                print(f'  {arm}: no scored runs {inc}'); continue
            avg = lambda k: sum(x.get(k) or 0 for x in rs) / len(rs)
            per = '  '.join(f"{x['run']}:{x['must']}/6,{x['should']}/3" for x in rs)
            print(f"  {arm}: n={len(rs)}  must {avg('must'):.2f}/6  should {avg('should'):.2f}/3  "
                  f"G1 {avg('G1_wide_retired'):.1f}  G2 {avg('G2_wide_nouns'):.1f}  G3 {avg('G3_wide_verify_after_last_edit'):.1f}  "
                  f"G4 {avg('G4_grep_new_date'):.1f}  X1 ok {sum(x['sites']['X1'] != 'STALE' for x in rs)}/{len(rs)}  "
                  f"cost ${avg('cost'):.2f}  [{per}]{'  inconclusive: ' + ','.join(inc) if inc else ''}")
        json.dump(rows, open(f'{OUT}/scores.json', 'w'), indent=1, ensure_ascii=False)
        return
    for r in argv:
        score(r)


if __name__ == '__main__':
    main(sys.argv[1:])
