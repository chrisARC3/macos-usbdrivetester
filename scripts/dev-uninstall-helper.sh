#!/bin/bash
#
# dev-uninstall-helper.sh — unload and remove the manually-installed Step 1 helper
# (the counterpart to dev-install-helper.sh). Requires sudo.
#
set -euo pipefail

LABEL="com.arc3solutions.USBDriveTester.Helper"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

echo "Booting out and removing helper (sudo)…"
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo rm -f "$PLIST"
sudo rm -f "/Library/PrivilegedHelperTools/$LABEL"
echo "Removed '$LABEL'."
