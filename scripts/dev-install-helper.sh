#!/bin/bash
#
# dev-install-helper.sh — manually load the helper as a system LaunchDaemon so the
# Step 1 "Ping helper" round-trip can be exercised BEFORE SMAppService exists
# (SMAppService registration is Step 3). This mirrors what SMAppService will later
# automate: copy the helper to a root-owned location, install a launchd plist, and
# bootstrap it into the system domain.
#
# Requires sudo. Undo with scripts/dev-uninstall-helper.sh.
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Development/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/USBDriveTester/USBDriveTester.xcodeproj"
LABEL="com.arc3solutions.USBDriveTester.Helper"
TOOL_DIR="/Library/PrivilegedHelperTools"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

echo "Building app (Debug)…"
xcodebuild -project "$PROJECT" -scheme USBDriveTester -configuration Debug \
    -destination 'platform=macOS,arch=arm64' build >/dev/null

BPD="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme USBDriveTester -configuration Debug 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')"
HELPER_SRC="$BPD/USBDriveTester.app/Contents/MacOS/$LABEL"

if [[ ! -x "$HELPER_SRC" ]]; then
    echo "error: helper executable not found at:" >&2
    echo "       $HELPER_SRC" >&2
    echo "Has the app's 'Copy Files -> Contents/MacOS' phase for the helper been added?" >&2
    exit 1
fi

echo "Installing helper (sudo)…"
sudo mkdir -p "$TOOL_DIR"
sudo cp "$HELPER_SRC" "$TOOL_DIR/$LABEL"
sudo chown root:wheel "$TOOL_DIR/$LABEL"
sudo chmod 755 "$TOOL_DIR/$LABEL"

echo "Writing launchd plist $PLIST (absolute ProgramArguments for manual bootstrap)…"
sudo tee "$PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$TOOL_DIR/$LABEL</string></array>
    <key>MachServices</key><dict><key>$LABEL</key><true/></dict>
</dict>
</plist>
EOF
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"

echo "Bootstrapping into system domain…"
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"

echo
echo "Helper '$LABEL' is loaded. Launch the app and click 'Ping helper' (expect: pong)."
echo "If bootstrap fails on code signature, that's expected for some local builds —"
echo "the definitive cross-process ping is validated in Step 3 via SMAppService."
