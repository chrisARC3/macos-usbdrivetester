#!/bin/bash
#
# install-app.sh — install the app to /Applications: a fresh build, or a release artefact.
#
# Why this exists
# ---------------
# SMAppService records the PATH of the app that registered a daemon. Registering from
# a DerivedData build directory works once, but that path is rebuilt and replaced
# constantly, which strands the registration pointing at a binary that no longer
# exists. The symptom is a status that will not move off .notFound or
# .requiresApproval no matter how often you re-register, and the only sanctioned
# cleanup for a wedged Background Task Management record is `sfltool resetbtm`, which
# resets it for EVERY app on the machine.
#
# Installing to a stable /Applications path avoids the whole problem: rebuild, re-run
# this script, and the registration keeps pointing at the same place.
#
# Usage: scripts/install-app.sh [Debug|Release]
#        scripts/install-app.sh --artefact <USBDriveTester-….zip | USBDriveTester.app>
#        scripts/install-app.sh --check-daemon
#
#   Debug|Release  build through scripts/build.sh and install what it built (default Debug).
#   --artefact     install a release artefact as it is, built by nothing here: the zip that
#                  scripts/release.sh writes (unpacked with `ditto -x -k` into a temporary
#                  directory), or an .app. Its signature must verify before anything is replaced.
#   --check-daemon install nothing; say whether the running daemon is the installed helper's code.
#                  Run it after `launchctl kickstart`.
#   --dest <path>  FOR TESTING THIS SCRIPT: install to <path> (an .app path) instead of
#                  /Applications/USBDriveTester.app. The daemon is not checked, because it does not
#                  run from there.
#
# Every install ends with a CONTENT PROOF: the installed tree is compared with its source by
# `diff -r`, and the files a person matches against a record are hashed — the code and the helper.
# Where the code lives depends on the build, and the proof names the file it hashed:
#   Debug    the code is in Contents/MacOS/USBDriveTester.debug.dylib; USBDriveTester is a stub.
#   Release  there is no .debug.dylib; the code is in Contents/MacOS/USBDriveTester.
# For an artefact, the hashes are the ones its MANIFEST.txt records under "The artefact".
# A file's timestamp proves nothing: `ditto` keeps the source's, and a zip keeps the build's.
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/USBDriveTester/USBDriveTester.xcodeproj"
SCHEME="USBDriveTester"
APPLICATIONS_DEST="/Applications/USBDriveTester.app"
HELPER_REL="Contents/MacOS/com.arc3solutions.USBDriveTester.Helper"

usage() { sed -n '18,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

CONFIG=""
ARTEFACT=""
CHECK_ONLY=0
DEST="$APPLICATIONS_DEST"
while (($#)); do
    case "$1" in
        Debug|Release)  CONFIG="$1" ;;
        --artefact)     [[ $# -ge 2 ]] || { echo "error: --artefact needs a path" >&2; exit 2; }
                        ARTEFACT="${2%/}"; shift ;;
        --check-daemon) CHECK_ONLY=1 ;;
        --dest)         [[ $# -ge 2 ]] || { echo "error: --dest needs a path" >&2; exit 2; }
                        DEST="${2%/}"; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
if [[ -n "$ARTEFACT" && -n "$CONFIG" ]]; then
    echo "error: --artefact installs what it is given; it takes no configuration" >&2
    exit 2
fi
if [[ "$CHECK_ONLY" -eq 1 && ( -n "$ARTEFACT" || -n "$CONFIG" || "$DEST" != "$APPLICATIONS_DEST" ) ]]; then
    echo "error: --check-daemon takes no other argument" >&2
    exit 2
fi
CONFIG="${CONFIG:-Debug}"
if [[ "$DEST" != *.app ]]; then
    echo "error: --dest must be an .app path: $DEST" >&2
    exit 2
fi

# THE RUNNING DAEMON IS NOT RELOADED BY COPYING FILES, and on 2026-08-18 that cost a full
# hardware gate run: metrics-check.sh was run twice against a daemon started before the fix it
# was meant to verify, and the version handshake could not catch it because the PROTOCOL had not
# changed — only the arithmetic behind one field had.
#
# The daemon is the helper process with uid 0 and parent pid 1 (launchd), matched on the end of its
# `comm`. Not `pgrep -f`, which matches any process whose ARGUMENTS contain the name — an `nm`,
# a `log` predicate, an editor — so `head -1` could time the wrong process and stay silent about a
# stale daemon, the one thing this check exists to say. Found 2026-09-10.
#
# `ps` is captured FIRST and awk reads it from a here-string. Piped straight into awk, the `exit`
# closed the pipe at the daemon's row while `ps` still had rows to write: `ps` died of SIGPIPE,
# `pipefail` failed the assignment, and `set -e` ended the script after the install and before
# this check — silent about a stale daemon again, by way of the 2026-09-10 fix. 97 runs in 100
# exited 141 on 2026-09-19, with 103,962 bytes of `ps` and the daemon's row ending at byte 96,694;
# it depends on how much `ps` still has to write, so some runs pass. `grep -m1` from a pipe fails
# the same way. The lesson is Step 6's, in `progress/step-06.md`.
#
# The check is on CONTENT, since 2026-10-09 (Step 16, chunk 3). Until then it compared the
# daemon's start time with the binary's modification time, and an artefact breaks that: `ditto`
# keeps the source's timestamps and a zip keeps the build's, so a daemon restarted after the build
# but before the install — a reboot is one — looked newer than the code it was not running.
# `codesign --verify <pid>` compares the code the kernel is running with the file at its path and
# says "the code on disk does not match what is running" when they differ. It needs no privilege
# for the root daemon (measured 2026-10-09 on pid 58327: "dynamically valid", "valid on disk").
# NOT `codesign -d <pid>`: its CDHash is read from the FILE AT THE PATH, so after an install it
# prints the new helper's CDHash for a daemon still running the old one — measured 2026-10-09 with
# two ad-hoc-signed programs swapped under a running process, where -d printed the replacement's
# CDHash and --verify failed.
check_daemon() {
    local helper_bin="$APPLICATIONS_DEST/$HELPER_REL"
    local ps_rows helper_pid helper_exe verify_out
    ps_rows="$(/bin/ps -axo pid=,ppid=,uid=,comm=)"
    helper_pid="$(/usr/bin/awk -v want='MacOS/com.arc3solutions.USBDriveTester.Helper' '
        $2 == 1 && $3 == 0 && substr($0, length($0) - length(want) + 1) == want { print $1; exit }' <<< "$ps_rows")"
    if [[ -z "$helper_pid" ]]; then
        echo "  No helper daemon is running. The next one launchd starts runs the installed code."
        return 0
    fi
    # The path is the kernel's, from `codesign -d <pid>`, and not `ps`'s `comm`: that is argv[0],
    # which launchd sets to the plist's relative BundleProgram — "Contents/MacOS/…Helper", with no
    # bundle in front of it (read 2026-10-09). The match above needs only its end.
    helper_exe="$( { codesign -d "$helper_pid" 2>&1 || true; } | sed -n 's/^Executable=//p')"
    if [[ "$helper_exe" != "$helper_bin" ]]; then
        echo
        echo "  ⚠️  The helper daemon (pid ${helper_pid}) runs from ANOTHER PATH:"
        echo "        ${helper_exe:-(codesign could not read it)}"
        echo "      not the installed $helper_bin. Its registration points elsewhere; unregister"
        echo "      and re-register in the app's Step 3 panel."
        return 1
    fi
    if verify_out="$(codesign --verify "$helper_pid" 2>&1)"; then
        echo "  The helper daemon (pid ${helper_pid}) is running the installed code:"
        echo "  codesign --verify on the pid is valid against $helper_bin."
        return 0
    fi
    echo
    echo "  ⚠️  The helper daemon (pid ${helper_pid}) is NOT running the installed code:"
    echo "$verify_out" | sed 's/^/        /'
    echo "      Copying files does not reload it. Until it restarts, the app and every gate"
    echo "      are talking to the old code — and if the protocol version did not change,"
    echo "      nothing will tell you."
    echo
    echo "      sudo /bin/launchctl kickstart -k system/com.arc3solutions.USBDriveTester.Helper"
    echo
    echo "      (or unregister and re-register in the app's Step 3 panel), then:"
    echo
    echo "      $REPO_ROOT/scripts/install-app.sh --check-daemon"
    return 1
}

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo "--- The helper daemon ---"
    check_daemon
    exit $?
fi

if pgrep -x "USBDriveTester" >/dev/null 2>&1; then
    echo "error: USBDriveTester is running. Quit it first, or the bundle will be" >&2
    echo "       replaced underneath a live process." >&2
    exit 1
fi

if [[ -n "$ARTEFACT" ]]; then
    case "$ARTEFACT" in
        *.zip)
            [[ -f "$ARTEFACT" ]] || { echo "error: no such zip: $ARTEFACT" >&2; exit 1; }
            echo "Artefact: $ARTEFACT"
            echo "  sha256  $(shasum -a 256 "$ARTEFACT" | cut -d' ' -f1)"
            WORK="$(mktemp -d "${TMPDIR:-/tmp}/install-app.XXXXXX")"
            trap 'rm -rf "$WORK"' EXIT
            ditto -x -k "$ARTEFACT" "$WORK"
            SRC="$WORK/USBDriveTester.app"
            ;;
        *.app)
            SRC="$ARTEFACT"
            echo "Artefact: $SRC"
            ;;
        *)
            echo "error: --artefact takes a .zip or an .app: $ARTEFACT" >&2
            exit 2
            ;;
    esac
else
    echo "Building scheme '$SCHEME' ($CONFIG)…"
    "$REPO_ROOT/scripts/build.sh" "$CONFIG" >/dev/null

    BPD="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" 2>/dev/null \
            | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')"
    SRC="$BPD/USBDriveTester.app"
fi

if [[ ! -d "$SRC" ]]; then
    echo "error: app not found at $SRC" >&2
    exit 1
fi
# Nothing is replaced until the source verifies: a bundle that fails here would have been installed
# over a working one.
if ! VERIFY_OUT="$(codesign --verify --deep --strict "$SRC" 2>&1)"; then
    echo "error: the source does not verify; nothing was installed:" >&2
    echo "$VERIFY_OUT" | sed 's/^/       /' >&2
    exit 1
fi

echo "Installing to ${DEST}..."
# ditto preserves the code signature and extended attributes; a plain cp -R does not
# reliably preserve resource forks on all volumes.
rm -rf "$DEST"
ditto "$SRC" "$DEST"

echo
echo "--- Content proof: the installed app against its source ---"
if ! DIFF_OUT="$(diff -rq "$SRC" "$DEST" 2>&1)"; then
    echo "error: the installed tree differs from its source:" >&2
    echo "$DIFF_OUT" | sed 's/^/       /' >&2
    exit 1
fi
echo "  tree      identical to the source (diff -r)"
if [[ -f "$DEST/Contents/MacOS/USBDriveTester.debug.dylib" ]]; then
    echo "  build     a .debug.dylib is present: the code is in it, and USBDriveTester is a stub"
    PROOF_FILES=("Contents/MacOS/USBDriveTester.debug.dylib" "Contents/MacOS/USBDriveTester" "$HELPER_REL")
else
    echo "  build     no .debug.dylib: the code is in Contents/MacOS/USBDriveTester"
    PROOF_FILES=("Contents/MacOS/USBDriveTester" "$HELPER_REL")
fi
for rel in "${PROOF_FILES[@]}"; do
    if ! cmp -s "$SRC/$rel" "$DEST/$rel"; then
        echo "error: $rel differs from its source" >&2
        exit 1
    fi
    echo "  sha256    $(shasum -a 256 "$DEST/$rel" | cut -d' ' -f1)  $rel"
done
if ! VERIFY_OUT="$(codesign --verify --deep --strict "$DEST" 2>&1)"; then
    echo "error: the installed app does not verify:" >&2
    echo "$VERIFY_OUT" | sed 's/^/       /' >&2
    exit 1
fi
echo "  codesign  --verify --deep --strict valid"

echo
echo "--- Installed app signature ---"
codesign -dvvv "$DEST" 2>&1 | grep -E "Identifier|TeamIdentifier|Authority=Apple Dev|Signature|Runtime|CDHash=" || true
echo
echo "--- Embedded helper signature ---"
codesign -dvvv "$DEST/$HELPER_REL" 2>&1 \
    | grep -E "Identifier|TeamIdentifier|Authority=Apple Dev|Signature|Runtime|CDHash=" || true
echo
echo "--- Embedded LaunchDaemon plist ---"
ls -l "$DEST/Contents/Library/LaunchDaemons/" 2>/dev/null || echo "(missing!)"
echo

if [[ "$DEST" != "$APPLICATIONS_DEST" ]]; then
    echo "Installed to $DEST, a test destination. The daemon was not checked."
    exit 0
fi

echo "Installed. Launch it from /Applications and use the Step 3 panel to register."
echo
echo "--- The helper daemon ---"
check_daemon || true
