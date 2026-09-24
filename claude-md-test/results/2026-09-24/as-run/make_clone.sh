#!/bin/zsh
# make_clone.sh <run-id> <arm A|B|C>
# A private copy of the repository as it stood at b708e4e — the commit before the audit — with that
# arm's CLAUDE.md folded into b708e4e itself, so every arm starts from a clean tree and the same
# log. The audit commit a063b9d is pruned, and there is no remote.
set -euo pipefail
S=/private/tmp/claude-501/-Volumes-1TB-UGreen-AI-Stuff-claude-code-folder-USBDriveTester/9b3706ab-cf2e-4a65-9796-e2d7dba5cabb/scratchpad
REAL=/Volumes/1TB_UGreen/AI_Stuff/claude-code-folder/USBDriveTester
BASE=b708e4ebce4f920334eee65d42f10c3009793fb2
run=$1 arm=$2
dir=$S/w/$run/USBDriveTester
[[ -e $S/w/$run ]] && { echo "exists: $S/w/$run" >&2; exit 1 }
mkdir -p $S/w/$run
git clone -q --no-hardlinks $REAL $dir
cd $dir
git checkout -q -B main $BASE
git remote remove origin
if [[ $arm != A ]]; then
  cp $S/f4test/arms/$arm/CLAUDE.md CLAUDE.md
  git add CLAUDE.md
  GIT_COMMITTER_NAME='Chris Karr' GIT_COMMITTER_EMAIL='chris@arc3solutions.com' \
  GIT_COMMITTER_DATE='1790206914 -0700' git commit -q --amend --no-verify -C HEAD
fi
git reflog expire --expire=now --all
git gc -q --prune=now
# Proofs, each of which must hold or the copy is not used.
head=$(git rev-parse HEAD)
[[ -z $(git status --porcelain) ]] || { echo "$run: tree not clean" >&2; exit 1 }
git show HEAD:CLAUDE.md | cmp -s - $S/f4test/arms/$arm/CLAUDE.md || { echo "$run: CLAUDE.md is not arm $arm" >&2; exit 1 }
[[ $(git log -1 --format=%s) == "Step 11 chunk 11 walked on Xcode 27"* ]] || { echo "$run: wrong subject" >&2; exit 1 }
[[ $(git rev-parse HEAD~1) == $(git -C $REAL rev-parse b708e4e~1) ]] || { echo "$run: wrong parent" >&2; exit 1 }
if git cat-file -e a063b9d 2>/dev/null; then echo "$run: a063b9d still present" >&2; exit 1; fi
[[ -z $(git remote) ]] || { echo "$run: has a remote" >&2; exit 1 }
[[ $(git branch -a | wc -l | tr -d ' ') == 1 ]] || { echo "$run: extra refs" >&2; exit 1 }
# Every tracked file but CLAUDE.md is b708e4e's, byte for byte (same blob ids).
diff <(git ls-tree -r HEAD | grep -v $'\tCLAUDE.md$') <(git -C $REAL ls-tree -r $BASE | grep -v $'\tCLAUDE.md$') >/dev/null \
  || { echo "$run: a file other than CLAUDE.md differs from b708e4e" >&2; exit 1 }
[[ $(git ls-files | wc -l) == $(git -C $REAL ls-tree -r --name-only $BASE | wc -l) ]] || { echo "$run: file count differs" >&2; exit 1 }
echo "$head" > $S/f4test/out/$run.base
echo "$run arm=$arm head=${head:0:12} clean, CLAUDE.md=arm $arm, a063b9d absent, no remote"
