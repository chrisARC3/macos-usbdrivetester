#!/bin/bash
#
# release.sh — Step 16's release artefact: archive, take the app from the archive, check it against
# the parts of Step 16's verification gate that this Mac can check, zip it with `ditto`, and record
# the hashes.
#
# What it does NOT do
# -------------------
# * **Export** (`xcodebuild -exportArchive`). Exporting asks the account for a distribution method,
#   and the app is taken from the archive as it is, signed *Apple Development* — so nothing is
#   created on the account beyond what every `build.sh` run already allows.
# * **Notarize.** There is no paid Apple Developer Program membership, so there is no notary service
#   and no Developer ID identity. The signer is the free Personal Team's *Apple Development*
#   certificate (`CONSTRAINTS.md` §1, *The team is a free Personal Team*), and Step 16 goes ahead
#   without notarization by the user's decision of 2026-10-09.
# * **Install.** `scripts/install-app.sh --artefact <zip>` does that. This script launches nothing
#   and registers nothing, so BTM's record does not move.
#
# What it changes after Xcode
# ---------------------------
# * **A secure timestamp — this script contacts timestamp.apple.com.** Xcode signs with
#   `--timestamp=none` (measured 2026-10-09, Step 16 chunk 2). On 2026-10-09 a test on a copy showed
#   that the free team's *Apple Development* signature can carry one, CDHashes unchanged, and the
#   user decided that the artefact does: the app taken from the archive is re-signed here, helper
#   first, by the identity that signed the archive, with `--timestamp` and
#   `--preserve-metadata=identifier,entitlements,requirements,flags`. Both CDHashes must come out
#   unchanged, and both signatures must carry `Timestamp=`; anything else fails the run. The archive
#   keeps Xcode's signature, and its dSYMs still match: a re-sign does not touch the code, which the
#   run checks by UUID. Offline, the re-sign fails and so does the run.
#
# What it checks — one line per check, PASS / FAIL / INCONCLUSIVE / NOT MET, into MANIFEST.txt
# --------------------------------------------------------------------------------------------
# Gate item 1: `codesign --verify --deep --strict`; both binaries *Apple Development* under the Team
#   ID the helper pins, read from `Shared/TesterControl.swift` rather than copied here; and the
#   `spctl -a -vv` reading, recorded as NOT MET (the user's decision of 2026-10-09), never failed.
# Gate item 2: the hardened runtime flag on both binaries, and each binary's entitlement keys
#   against a declared allowlist — a new key fails the run until it is justified and added below.
# Gate item 5, this Mac's half: both binaries satisfy the helper's requirement under
#   `codesign -v -R`, and a negative control with a wrong OU fails.
# Gate item 6: every Mach-O in the bundle has 0 `__llvm_prf_cnts` sections, 0 `___profc_` symbols
#   and no `/Users/` or `/Volumes/` path. Paths are counted BY BYTES, never `strings -a` or `grep -c`
#   (`CONSTRAINTS.md` §1, *A string check on a Mach-O counts with `strings -` or by bytes*). Each
#   count has a positive control, so a zero means something: the counter on a known string, the
#   logging subsystem's bytes in the same file, `__text` in the same `otool` read, and a non-empty
#   `nm` listing.
# Also: no compile command in the archive log carries `-profile-generate` (beside a control that
#   the log shows compile commands at all); arm64 alone; `LC_BUILD_VERSION` minos and
#   `LSMinimumSystemVersion` 26.0; no `.debug.dylib`; the LaunchDaemon plist present; and the zip,
#   unpacked again, still verifies and holds byte-identical binaries.
#
# Usage: scripts/release.sh [--allow-dirty] [--replace]
#
#   --allow-dirty  build from a tree with uncommitted changes to tracked files. The manifest and
#                  the directory name say "-dirty", and such an artefact is never the one shipped.
#   --replace      remove this commit's existing output directory first. Without it the script
#                  refuses to overwrite one.
#
# Output: build/release/<short commit>[-dirty]/ (gitignored)
#   USBDriveTester.xcarchive                        the archive, dSYMs included — kept, not shipped
#   USBDriveTester.app                              the app as taken from the archive
#   USBDriveTester-<version>-<build>-<commit>.zip   the artefact
#   archive.log                                     xcodebuild's output
#   resign.log                                      the timestamp re-sign's output
#   MANIFEST.txt                                    sources, toolchain, hashes and every reading
#
# Exit status: 0 when every check passes, NOT MET aside; 1 when any check fails or is inconclusive.
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/USBDriveTester/USBDriveTester.xcodeproj"
SCHEME="USBDriveTester"
PIN_SOURCE="$REPO_ROOT/USBDriveTester/USBDriveTester/Shared/TesterControl.swift"
HELPER_NAME="com.arc3solutions.USBDriveTester.Helper"
# A string both binaries must contain: the logging subsystem, `HelperIdentity.loggingSubsystem`,
# compiled into both targets from `Shared/`. It is the byte counter's positive control on real files.
CONTROL_STRING="com.arc3solutions.USBDriveTester"

# Entitlement keys each binary may carry, and why. A key not listed fails the run: gate item 2 says
# anything kept is justified in writing, and this list is where that writing has to be added.
#   App: none. `get-task-allow` is gone with CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO (Release), and
#     `files.user-selected.read-only` with ENABLE_USER_SELECTED_FILES (Step 16 chunk 2).
#   Helper: `com.apple.application-identifier`, which Xcode synthesizes at ProcessProductPackaging
#     for a tool target with no entitlements file and no profile (Step 16 chunk 2). It is not
#     requested by the project; its written justification is owed by gate item 2.
APP_ALLOWED_ENTITLEMENTS=""
HELPER_ALLOWED_ENTITLEMENTS="com.apple.application-identifier"
FORBIDDEN_ENTITLEMENTS="com.apple.security.get-task-allow com.apple.security.files.user-selected.read-only"

ALLOW_DIRTY=0
REPLACE=0
for arg in "$@"; do
    case "$arg" in
        --allow-dirty) ALLOW_DIRTY=1 ;;
        --replace)     REPLACE=1 ;;
        *) echo "usage: scripts/release.sh [--allow-dirty] [--replace]" >&2; exit 2 ;;
    esac
done

# --- the sources ------------------------------------------------------------------------------
COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
SHORT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
DIRTY=""
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)" ]]; then
    if [[ "$ALLOW_DIRTY" -ne 1 ]]; then
        echo "error: tracked files have uncommitted changes. A release is built from a commit;" >&2
        echo "       commit first, or pass --allow-dirty for a build that is never shipped." >&2
        git -C "$REPO_ROOT" status --short --untracked-files=no >&2
        exit 1
    fi
    DIRTY="-dirty"
fi

OUT="$REPO_ROOT/build/release/$SHORT$DIRTY"
if [[ -e "$OUT" ]]; then
    if [[ "$REPLACE" -ne 1 ]]; then
        echo "error: $OUT exists. Pass --replace to rebuild it." >&2
        exit 1
    fi
    rm -rf "$OUT"
fi
mkdir -p "$OUT"

ARCHIVE="$OUT/USBDriveTester.xcarchive"
APP="$OUT/USBDriveTester.app"
MANIFEST="$OUT/MANIFEST.txt"
: > "$MANIFEST"

FAILS=0
note()   { echo "$*" | tee -a "$MANIFEST"; }
result() { # result VERDICT what…
    local verdict="$1"; shift
    note "  $verdict  $*"
    case "$verdict" in FAIL|INCONCLUSIVE) FAILS=$((FAILS + 1)) ;; esac
}
# Occurrences of a byte string in a file — not lines, and not limited to sections.
count_bytes() {
    /usr/bin/python3 -I -c 'import sys; print(open(sys.argv[1], "rb").read().count(sys.argv[2].encode()))' "$1" "$2"
}
# `grep -c` that reports 0 rather than failing the pipeline when nothing matches.
count_lines() { /usr/bin/grep -c -- "$1" || true; }

note "USBDriveTester release artefact — $(date '+%Y-%m-%d %H:%M:%S %z')"
note "  commit        $COMMIT${DIRTY:+  (DIRTY: tracked files differ from the commit)}"
note "  macOS         $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
note "  Xcode         $(xcodebuild -version | tr '\n' ' ' | sed 's/ *$//')"
note "  helper hash   $(find "$REPO_ROOT/USBDriveTester/$HELPER_NAME" "$REPO_ROOT/USBDriveTester/USBDriveTester/Shared" -name '*.swift' | sort | xargs cat | shasum -a 256 | cut -d' ' -f1)"

# The Team ID the helper pins, from the source — so this check follows the pin if it ever moves.
TEAM_ID="$(sed -n 's/.*static let expectedTeamID = "\([A-Z0-9]*\)".*/\1/p' "$PIN_SOURCE")"
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] \
   || ! /usr/bin/grep -q 'anchor apple generic and certificate leaf\[subject.OU\] = \\"\\(expectedTeamID)\\"' "$PIN_SOURCE"; then
    echo "error: could not read the helper's pin from $PIN_SOURCE — its shape has changed;" >&2
    echo "       update this script's reading of it." >&2
    exit 1
fi
REQUIREMENT="anchor apple generic and certificate leaf[subject.OU] = \"$TEAM_ID\""
WRONG_REQUIREMENT="anchor apple generic and certificate leaf[subject.OU] = \"AAAAAAAAAA\""
note "  pinned team   $TEAM_ID  (Shared/TesterControl.swift, HelperIdentity.expectedTeamID)"
note

# --- archive ----------------------------------------------------------------------------------
echo "Archiving scheme '$SCHEME' (Release) — the log is $OUT/archive.log"
# -allowProvisioningUpdates as in build.sh: automatic signing under the Personal Team.
if ! xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE" \
        -allowProvisioningUpdates \
        archive > "$OUT/archive.log" 2>&1; then
    tail -n 40 "$OUT/archive.log" >&2
    echo "error: the archive failed; the full log is $OUT/archive.log" >&2
    exit 1
fi

SRC_APP="$ARCHIVE/Products/Applications/USBDriveTester.app"
if [[ ! -d "$SRC_APP" ]]; then
    echo "error: no app in the archive at $SRC_APP" >&2
    exit 1
fi
ditto "$SRC_APP" "$APP"
EXE="$APP/Contents/MacOS/USBDriveTester"
HELPER="$APP/Contents/MacOS/$HELPER_NAME"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ZIP="$OUT/USBDriveTester-$VERSION-$BUILD-$SHORT$DIRTY.zip"

note "The archive"
note "  products      $(cd "$ARCHIVE/Products" && find . \( -name '*.app' -prune -print \) -o -type f -print | sed 's|^\./||' | sort | tr '\n' ' ')"
note "  dSYMs         $(cd "$ARCHIVE/dSYMs" 2>/dev/null && ls | tr '\n' ' ' || echo '(none)')"
COMPILES="$(count_lines '-module-name' < "$OUT/archive.log")"
PROFILED="$(count_lines '-profile-generate' < "$OUT/archive.log")"
if [[ "$COMPILES" -eq 0 ]]; then
    result INCONCLUSIVE "coverage in the log: no line carries -module-name, so the log shows no compile command to read"
elif [[ "$PROFILED" -eq 0 ]]; then
    result PASS "coverage in the log: 0 lines carry -profile-generate, of $COMPILES carrying -module-name"
else
    result FAIL "coverage in the log: $PROFILED lines carry -profile-generate"
fi
# Every warning fails the run except a named exception, and an exception is one a person has
# decided to live with. One so far: appintentsmetadataprocessor's, which every build emits because
# the app does not link AppIntents. A warning nobody has decided about fails — a release gate that
# quietly lists one has taught itself to stop reading.
OTHER_WARNINGS="$(/usr/bin/grep 'warning:' "$OUT/archive.log" | /usr/bin/grep -v 'appintentsmetadataprocessor' | sed 's/^.*warning: /warning: /' | sort -u || true)"
if [[ -z "$OTHER_WARNINGS" ]]; then
    result PASS "warnings: none but appintentsmetadataprocessor's ($(count_lines 'warning:' < "$OUT/archive.log") warning: line(s) in all)"
else
    result FAIL "warnings in the archive log, besides appintentsmetadataprocessor's:"
    echo "$OTHER_WARNINGS" | sed 's/^/        /' | tee -a "$MANIFEST"
fi
note

# --- the secure timestamp ----------------------------------------------------------------------
# By the user's decision of 2026-10-09 — the header says why and how. The identity is the one whose
# leaf certificate signed the archive, by its SHA-1, so a second identity in the keychain is never
# picked by name.
note "The secure timestamp — re-signing with --timestamp (contacts timestamp.apple.com)"
CERTS="$OUT/.leaf-cert"
rm -rf "$CERTS"; mkdir -p "$CERTS"
codesign -d --extract-certificates="$CERTS/cert" "$APP" >/dev/null 2>&1 || true
if [[ ! -s "$CERTS/cert0" ]]; then
    rm -rf "$CERTS"
    result FAIL "could not extract the archive's leaf certificate"
    note "RESULT: stopped before the gate checks. $OUT"
    exit 1
fi
SIGNER_SHA1="$(shasum -a 1 "$CERTS/cert0" | cut -d' ' -f1 | tr 'a-f' 'A-F')"
rm -rf "$CERTS"
IDENTITIES="$(security find-identity -v -p codesigning)"
if [[ "$IDENTITIES" != *"$SIGNER_SHA1"* ]]; then
    result FAIL "the archive's signer, SHA-1 $SIGNER_SHA1, is not a valid identity in the keychain"
    note "RESULT: stopped before the gate checks. $OUT"
    exit 1
fi
note "  signer        SHA-1 $SIGNER_SHA1 — the archive's leaf certificate"
CD_EXE_BEFORE="$(codesign -dvvv "$EXE" 2>&1 | sed -n 's/^CDHash=//p')"
CD_HELPER_BEFORE="$(codesign -dvvv "$HELPER" 2>&1 | sed -n 's/^CDHash=//p')"
RESIGN=(codesign --force --sign "$SIGNER_SHA1" --timestamp
        --preserve-metadata=identifier,entitlements,requirements,flags)
if ! { "${RESIGN[@]}" "$HELPER" && "${RESIGN[@]}" "$APP"; } > "$OUT/resign.log" 2>&1; then
    result FAIL "the re-sign failed — offline, or timestamp.apple.com refused; the bundle is half re-signed:"
    sed 's/^/        /' "$OUT/resign.log" | tee -a "$MANIFEST"
    note "RESULT: stopped before the gate checks. $OUT"
    exit 1
fi
for bin in "$EXE" "$HELPER"; do
    name="$(basename "$bin")"
    info="$(codesign -dvvv "$bin" 2>&1)"
    after="$(echo "$info" | sed -n 's/^CDHash=//p')"
    if [[ "$bin" == "$EXE" ]]; then before="$CD_EXE_BEFORE"; else before="$CD_HELPER_BEFORE"; fi
    stamp="$(echo "$info" | sed -n 's/^Timestamp=//p')"
    signed_time="$(echo "$info" | sed -n 's/^Signed Time=//p')"
    if [[ -n "$before" && "$after" == "$before" && -n "$stamp" && -z "$signed_time" ]]; then
        result PASS "$name: Timestamp=$stamp; CDHash $after, unchanged by the re-sign"
    else
        result FAIL "$name: CDHash $before → $after; Timestamp='$stamp'; Signed Time='$signed_time'"
    fi
done
for pair in "$EXE|USBDriveTester.app.dSYM" "$HELPER|$HELPER_NAME.dSYM"; do
    bin="${pair%%|*}"; dsym="$ARCHIVE/dSYMs/${pair#*|}"
    # Captured first and read from a here-string: an awk that exits early on a pipe can SIGPIPE its
    # producer under pipefail (BUILD-PLAN, *Shell and scripting*).
    dump_bin="$(xcrun dwarfdump --uuid "$bin" 2>/dev/null || true)"
    dump_dsym="$(xcrun dwarfdump --uuid "$dsym" 2>/dev/null || true)"
    uuid_bin="$(awk '{print $2; exit}' <<< "$dump_bin")"
    uuid_dsym="$(awk '{print $2; exit}' <<< "$dump_dsym")"
    if [[ -n "$uuid_bin" && "$uuid_bin" == "$uuid_dsym" ]]; then
        result PASS "$(basename "$bin") UUID $uuid_bin matches the archive's ${pair#*|}"
    else
        result FAIL "$(basename "$bin") UUID '$uuid_bin', the archive's ${pair#*|} '$uuid_dsym'"
    fi
done
note

# --- gate item 1: the signature ---------------------------------------------------------------
note "Gate item 1 — the signature"
if VERIFY_OUT="$(codesign --verify --deep --strict --verbose=2 "$APP" 2>&1)"; then
    result PASS "codesign --verify --deep --strict: $(echo "$VERIFY_OUT" | tail -n 1)"
else
    result FAIL "codesign --verify --deep --strict:"
    echo "$VERIFY_OUT" | sed 's/^/        /' | tee -a "$MANIFEST"
fi
for bin in "$EXE" "$HELPER"; do
    name="$(basename "$bin")"
    info="$(codesign -dvvv "$bin" 2>&1)"
    authority="$(echo "$info" | sed -n 's/^Authority=//p' | head -n 1)"
    team="$(echo "$info" | sed -n 's/^TeamIdentifier=//p')"
    cdhash="$(echo "$info" | sed -n 's/^CDHash=//p')"
    stamp="$(echo "$info" | /usr/bin/grep -E '^(Timestamp|Signed Time)=' || echo '(neither)')"
    note "  $name: CDHash $cdhash; $stamp"
    if [[ "$authority" == "Apple Development: "* && "$team" == "$TEAM_ID" ]]; then
        result PASS "$name signed by '$authority', TeamIdentifier=$team"
    else
        result FAIL "$name signed by '$authority', TeamIdentifier=$team — expected Apple Development under $TEAM_ID"
    fi
done
SPCTL_OUT="$(spctl -a -vv "$APP" 2>&1)" && SPCTL_RC=0 || SPCTL_RC=$?
result "NOT MET" "spctl -a -vv (exit $SPCTL_RC), by the user's decision of 2026-10-09 — no Developer ID: $(echo "$SPCTL_OUT" | tr '\n' ' ' | sed "s|$APP|<app>|g")"
note

# --- gate item 2: runtime and entitlements ----------------------------------------------------
note "Gate item 2 — hardened runtime and entitlements"
for bin in "$EXE" "$HELPER"; do
    name="$(basename "$bin")"
    if [[ "$bin" == "$EXE" ]]; then allowed="$APP_ALLOWED_ENTITLEMENTS"; else allowed="$HELPER_ALLOWED_ENTITLEMENTS"; fi
    flags="$(codesign -dvvv "$bin" 2>&1 | sed -n 's/^CodeDirectory .*flags=\(0x[0-9a-f]*([^)]*)\).*/\1/p')"
    if [[ "$flags" == *runtime* ]]; then
        result PASS "$name hardened runtime: flags=$flags"
    else
        result FAIL "$name hardened runtime: flags=$flags"
    fi
    keys="$(codesign -d --entitlements - --xml "$bin" 2>/dev/null \
            | /usr/bin/python3 -I -c 'import sys, plistlib
data = sys.stdin.buffer.read()
print(" ".join(sorted(plistlib.loads(data))) if data.strip() else "")')"
    bad=""
    for key in $keys; do
        case " $FORBIDDEN_ENTITLEMENTS " in *" $key "*) bad="$bad $key(forbidden)"; continue ;; esac
        case " $allowed " in *" $key "*) ;; *) bad="$bad $key(not allowlisted)" ;; esac
    done
    if [[ -z "$bad" ]]; then
        result PASS "$name entitlements: ${keys:-none}"
    else
        result FAIL "$name entitlements: ${keys:-none} —$bad"
    fi
done
note

# --- gate item 5, this Mac's half: the helper's requirement -----------------------------------
note "Gate item 5 (this Mac) — the helper's requirement, $REQUIREMENT"
for bin in "$APP" "$HELPER"; do
    name="$(basename "$bin")"
    if codesign -v -R="$REQUIREMENT" "$bin" >/dev/null 2>&1; then
        if codesign -v -R="$WRONG_REQUIREMENT" "$bin" >/dev/null 2>&1; then
            result INCONCLUSIVE "$name satisfies the pin, and also the wrong OU — the negative control did not fail"
        else
            result PASS "$name satisfies the pin; the wrong OU (AAAAAAAAAA) does not — the negative control"
        fi
    else
        result FAIL "$name does not satisfy the pin"
    fi
done
note

# --- gate item 6: counters and paths, in every Mach-O ------------------------------------------
note "Gate item 6 — no coverage counters and no build-machine paths, in every Mach-O"
CONTROL_FILE="$OUT/.byte-count-control"
printf 'x/Users/y\0/Volumes/z\0/Volumes/' > "$CONTROL_FILE"
if [[ "$(count_bytes "$CONTROL_FILE" '/Users/')" == 1 && "$(count_bytes "$CONTROL_FILE" '/Volumes/')" == 2 ]]; then
    result PASS "the byte counter reads a known file right: /Users/ 1, /Volumes/ 2"
else
    result FAIL "the byte counter misreads a known file"
fi
rm -f "$CONTROL_FILE"
MACHOS=()
while IFS= read -r -d '' f; do
    case "$(file -b "$f")" in *Mach-O*) MACHOS+=("$f") ;; esac
done < <(find "$APP" -type f -print0)
note "  Mach-O files: ${#MACHOS[@]}"
if [[ "${#MACHOS[@]}" -eq 0 ]]; then
    result INCONCLUSIVE "no Mach-O found in the bundle"
fi
for f in "${MACHOS[@]}"; do
    rel="${f#"$APP"/}"
    loadcmds="$(otool -l "$f")"
    text="$(echo "$loadcmds" | count_lines 'sectname __text')"
    prf="$(echo "$loadcmds" | count_lines 'sectname __llvm_prf_cnts')"
    # `|| true` inside the braces: under pipefail, nm failing on a binary with no symbol table
    # would otherwise end the script; an empty listing is read below.
    symbols="$({ xcrun nm -a "$f" 2>/dev/null || true; })"
    nsyms="$(printf '%s' "$symbols" | /usr/bin/grep -c . || true)"
    profc="$(printf '%s' "$symbols" | count_lines '___profc_')"
    users="$(count_bytes "$f" '/Users/')"
    volumes="$(count_bytes "$f" '/Volumes/')"
    control="$(count_bytes "$f" "$CONTROL_STRING")"
    note "  $rel: sha256 $(shasum -a 256 "$f" | cut -c1-16)…  __text $text  symbols $nsyms  $CONTROL_STRING $control"
    if [[ "$text" -lt 1 ]]; then
        result INCONCLUSIVE "$rel counters: otool found no __text section, so its 0 says nothing"
    elif [[ "$prf" -eq 0 && "$profc" -eq 0 ]]; then
        if [[ "$nsyms" -gt 0 ]]; then
            result PASS "$rel counters: __llvm_prf_cnts 0, ___profc_ 0"
        else
            result PASS "$rel counters: __llvm_prf_cnts 0 (and nm lists no symbols at all, so ___profc_ is 0 by construction)"
        fi
    else
        result FAIL "$rel counters: __llvm_prf_cnts $prf, ___profc_ $profc"
    fi
    if [[ "$control" -lt 1 ]]; then
        result INCONCLUSIVE "$rel paths: the control string is not found, so a 0 says nothing"
    elif [[ "$users" -eq 0 && "$volumes" -eq 0 ]]; then
        result PASS "$rel paths: /Users/ 0, /Volumes/ 0 (by bytes)"
    else
        result FAIL "$rel paths: /Users/ $users, /Volumes/ $volumes (by bytes)"
    fi
done
note

# --- the rest of what the gate assumes ---------------------------------------------------------
note "Architecture, deployment target and bundle shape"
for bin in "$EXE" "$HELPER"; do
    name="$(basename "$bin")"
    archs="$(lipo -archs "$bin")"
    minos="$(otool -l "$bin" | awk '/LC_BUILD_VERSION/{f=1} f && $1 == "minos" {print $2; exit}')"
    if [[ "$archs" == "arm64" && "$minos" == "26.0" ]]; then
        result PASS "$name: $archs, minos $minos"
    else
        result FAIL "$name: archs '$archs', minos '$minos' — expected arm64 alone, 26.0"
    fi
done
LSMIN="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo '(absent)')"
if [[ "$LSMIN" == "26.0" ]]; then result PASS "LSMinimumSystemVersion $LSMIN"; else result FAIL "LSMinimumSystemVersion $LSMIN"; fi
if [[ -n "$(find "$APP" -name '*.debug.dylib')" ]]; then
    result FAIL "a .debug.dylib is in the bundle — a Release build has none"
else
    result PASS "no .debug.dylib — the code is in Contents/MacOS/USBDriveTester"
fi
if [[ -f "$APP/Contents/Library/LaunchDaemons/$HELPER_NAME.plist" ]]; then
    result PASS "LaunchDaemon plist present"
else
    result FAIL "LaunchDaemon plist missing from Contents/Library/LaunchDaemons"
fi
note

# --- the zip ----------------------------------------------------------------------------------
note "The artefact"
ditto -c -k --keepParent "$APP" "$ZIP"
CHECK="$OUT/.zip-check"
rm -rf "$CHECK"; mkdir -p "$CHECK"
ditto -x -k "$ZIP" "$CHECK"
if codesign --verify --deep --strict "$CHECK/USBDriveTester.app" >/dev/null 2>&1 \
   && cmp -s "$EXE" "$CHECK/USBDriveTester.app/Contents/MacOS/USBDriveTester" \
   && cmp -s "$HELPER" "$CHECK/USBDriveTester.app/Contents/MacOS/$HELPER_NAME"; then
    result PASS "the zip unpacked again verifies, and both binaries in it are byte-identical"
else
    result FAIL "the zip unpacked again does not verify, or its binaries differ"
fi
rm -rf "$CHECK"
note "  zip           $(basename "$ZIP")  $(stat -f '%z' "$ZIP") bytes"
note "  zip sha256    $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
note "  app exe       $(shasum -a 256 "$EXE" | cut -d' ' -f1)  CDHash $(codesign -dvvv "$EXE" 2>&1 | sed -n 's/^CDHash=//p')"
note "  helper        $(shasum -a 256 "$HELPER" | cut -d' ' -f1)  CDHash $(codesign -dvvv "$HELPER" 2>&1 | sed -n 's/^CDHash=//p')"
note "  version       $VERSION ($BUILD)"
note

if [[ "$FAILS" -eq 0 ]]; then
    note "RESULT: every check passed; spctl NOT MET, as decided. $OUT"
    exit 0
else
    note "RESULT: $FAILS check(s) failed or were inconclusive. $OUT"
    exit 1
fi
