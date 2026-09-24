#!/bin/zsh
# make_clone.sh <run-id> <arm> — a private copy of this repository as it stood at BASE, the commit
# before the audit, with arms/<arm>.CLAUDE.md folded into BASE itself, so every arm starts from a
# clean tree and the same log. Nothing after BASE survives in the copy, and there is no remote.
# The committer is BASE's own, so a copy of a given arm has the same HEAD every time it is made.
set -euo pipefail
HERE=${0:A:h}; source $HERE/common.sh
run=$1 arm=$2
armfile=$HERE/arms/$arm.CLAUDE.md
[[ -f $armfile ]] || { print -u2 "no arm file $armfile"; exit 1 }
dir=$WORK/w/$run/USBDriveTester
[[ -e $WORK/w/$run ]] && { print -u2 "exists: $WORK/w/$run"; exit 1 }
mkdir -p $WORK/w/$run
git clone -q --no-hardlinks $REAL $dir
cd $dir
git checkout -q -B main $BASE
git remote remove origin
if ! git show HEAD:CLAUDE.md | cmp -s - $armfile; then
  cp $armfile CLAUDE.md
  git add CLAUDE.md
  GIT_COMMITTER_NAME=$(git log -1 --format=%cn HEAD) GIT_COMMITTER_EMAIL=$(git log -1 --format=%ce HEAD) \
  GIT_COMMITTER_DATE=$(git log -1 --format=%cd --date=raw HEAD) git commit -q --amend --no-verify -C HEAD
fi
git reflog expire --expire=now --all
git gc -q --prune=now
# Proofs, each of which must hold or the copy is not used.
head=$(git rev-parse HEAD)
fail() { print -u2 "$run: $1"; exit 1 }
[[ -z $(git status --porcelain) ]] || fail "tree not clean"
git show HEAD:CLAUDE.md | cmp -s - $armfile || fail "CLAUDE.md is not arm $arm"
[[ $(git log -1 --format=%s) == $(git -C $REAL log -1 --format=%s $BASE) ]] || fail "wrong subject"
[[ $(git rev-parse HEAD~1) == $(git -C $REAL rev-parse $BASE~1) ]] || fail "wrong parent"
# Nothing after BASE, counting every commit object in the store, reachable or not: the audit
# (a063b9d) and every commit since are gone, this harness with them.
ncommits=$(git cat-file --batch-all-objects --batch-check='%(objecttype)' | grep -c '^commit$')
[[ $ncommits == $(git -C $REAL rev-list --count $BASE) ]] || fail "$ncommits commits; BASE has $(git -C $REAL rev-list --count $BASE)"
if git cat-file -e a063b9d 2>/dev/null; then fail "a063b9d still present"; fi
[[ -z $(git ls-tree -d HEAD ${HERE#$REAL/}) ]] || fail "the harness is in the copy"
[[ -z $(git remote) ]] || fail "has a remote"
[[ -z $(git tag) ]] || fail "has tags"
[[ $(git branch -a | wc -l | tr -d ' ') == 1 ]] || fail "extra refs"
# Every tracked file but CLAUDE.md is BASE's, byte for byte (same blob ids).
diff <(git ls-tree -r HEAD | grep -v $'\tCLAUDE.md$') <(git -C $REAL ls-tree -r $BASE | grep -v $'\tCLAUDE.md$') >/dev/null \
  || fail "a file other than CLAUDE.md differs from BASE"
[[ $(git ls-files | wc -l) == $(git -C $REAL ls-tree -r --name-only $BASE | wc -l) ]] || fail "file count differs"
print -r -- $head > $OUT/$run.base
print "$run arm=$arm head=${head:0:12} clean, CLAUDE.md=arm $arm, $ncommits commits, nothing after ${BASE:0:7}, no remote"
