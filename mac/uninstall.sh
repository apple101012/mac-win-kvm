#!/usr/bin/env bash
# Remove the Mac side (Deskflow.app too, unless --keep-deskflow).
source "$(dirname "$0")/common.sh"
set +e
osascript -e 'quit app "macwinkvm"' 2>/dev/null; pkill -x macwinkvm; pkill -9 -f "$DESKFLOW_CORE"
rm -rf "$APP" "$STATE_DIR"
[[ "${1:-}" == "--keep-deskflow" ]] || rm -rf /Applications/Deskflow.app
echo "Removed. (trust/mac.sha256 stays in the repo; it is regenerated on the next install.)"
