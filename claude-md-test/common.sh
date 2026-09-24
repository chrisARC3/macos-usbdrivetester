# common.sh — sourced by every script here, after it sets HERE=${0:A:h}.
#
# CMT_WORK is the one thing a caller must set: where the copies and the outputs go. It must be
# outside this repository, which the sandbox denies the sessions, and outside $HOME, /Volumes,
# /Applications and /Library, where it denies them writes. 2026-09-24 used /private/tmp. Make it a
# fresh directory with nothing else in it: a session can read all of it but out/ and the other
# runs' copies. Give it a name that does not say what it is for: each session works in
# $CMT_WORK/w/<run>/USBDriveTester and can see that path.
#
# Optional: CMT_MODEL, CMT_EFFORT and CMT_CLI (below), and CMT_DENY, a colon-separated list of
# further paths no session may read — the notes of whoever is running the test, if they are not
# already under this repository.
if [[ -z ${CMT_WORK:-} ]]; then
  print -u2 "set CMT_WORK to a directory for the copies and outputs, for example"
  print -u2 "  export CMT_WORK=/private/tmp/usbdt-$(date +%F)"
  exit 2
fi
WORK=${CMT_WORK:A}
REAL=$(git -C $HERE rev-parse --show-toplevel) || exit 2
REAL=${REAL:A}
for d in $REAL $HOME /Volumes /Applications /Library; do
  if [[ $WORK == ${d:A} || $WORK == ${d:A}/* ]]; then
    print -u2 "CMT_WORK ($WORK) is under $d, which the sandbox denies the sessions"
    exit 2
  fi
done
OUT=$WORK/out
mkdir -p $OUT $WORK/w

# The commit every copy starts from: the last one before the audit. score.py's sites quote its
# text, so a different base is a different test (README.md, "Changing what is measured").
BASE=b708e4ebce4f920334eee65d42f10c3009793fb2
MODEL=${CMT_MODEL:-claude-opus-5-5}
EFFORT=${CMT_EFFORT:-high}
# The desktop app's own copy of the CLI, as on 2026-09-24. ~/.local/bin/claude was 2.1.246 that
# day, and claude-opus-5-5 refused it (400: "version 2.1.280 or newer is required").
CLI=${CMT_CLI:-"$HOME/Library/Application Support/Claude/claude-code/2.1.280/claude.app/Contents/MacOS/claude"}

# Claude Code keeps a project's transcripts and auto-memory in ~/.claude/projects/<the project's
# path, with every character but letters and digits turned into "-">.
project_dir() { print -r -- $HOME/.claude/projects/${1//[^A-Za-z0-9]/-} }
