#!/usr/bin/env bash
# Install / update the Mac (client) side. Safe to re-run.
source "$(dirname "$0")/common.sh"
step() { echo "==> $*"; }

if [[ ! -x "$DESKFLOW_CORE" ]]; then
  step "Installing Deskflow $DESKFLOW_VERSION from its GitHub release"
  tmp="$(mktemp -d)"; dmg="deskflow-$DESKFLOW_VERSION-macos-$(uname -m).dmg"   # arm64 or x86_64
  base="https://github.com/deskflow/deskflow/releases/download/v$DESKFLOW_VERSION"
  curl -fsSL -o "$tmp/$dmg" "$base/$dmg"; curl -fsSL -o "$tmp/sums.txt" "$base/sums.txt"
  (cd "$tmp" && grep " $dmg\$" sums.txt | shasum -a 256 -c -) || { echo "checksum mismatch"; exit 1; }
  yes | hdiutil attach -nobrowse -quiet "$tmp/$dmg" -mountpoint "$tmp/mnt" >/dev/null   # accepts the GPL licence prompt
  cp -R "$tmp/mnt/Deskflow.app" /Applications/
  hdiutil detach -quiet "$tmp/mnt"; rm -rf "$tmp"
fi

mkdir -p "$STATE_DIR"
ensure_client_cert
write_route_settings

# Mission Control shortcut (settings.json macMissionControl): unchanged | ctrl+tab | ctrl+up (macOS default)
mc_params=""
case "$(setting macMissionControl)" in
  ""|unchanged) ;;
  ctrl+tab) mc_params="65535 48 262144" ;;
  ctrl+up)  mc_params="65535 126 8650752" ;;
  *) echo "unknown macMissionControl (use unchanged, ctrl+tab or ctrl+up)"; exit 1 ;;
esac
if [[ -n "$mc_params" ]]; then
read -r a k m <<<"$mc_params"
current="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null | tr -d ' \n' | grep -o '32={enabled=1;value={parameters=([0-9,]*)' || true)"
if [[ "$current" != "32={enabled=1;value={parameters=($a,$k,$m)" ]]; then
  step "Setting the Mission Control shortcut ($(setting macMissionControl))"
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 32 \
    "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>$a</integer><integer>$k</integer><integer>$m</integer></array><key>type</key><string>standard</string></dict></dict>"
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u >/dev/null 2>&1 || true
fi
fi

step "Building macwinkvm.app"
(cd "$REPO/mac" && swift build -c release --product macwinkvm 2>&1 | { grep -E "error|complete" || true; } | tail -3)
bin="$(cd "$REPO/mac" && swift build -c release --show-bin-path)/macwinkvm"
new_bin_sum="$(shasum -a 256 "$bin" | cut -d' ' -f1)"
old_bin_sum="$(cat "$APP/Contents/Resources/build.sha256" 2>/dev/null || true)"   # codesign changes the binary, so compare build hashes
AGENT="io.github.macwinkvm.agent.plist"
if [[ "$new_bin_sum" != "$old_bin_sum" ]] || ! cmp -s "$REPO/mac/Resources/Info.plist" "$APP/Contents/Info.plist" \
   || ! cmp -s "$REPO/mac/Resources/$AGENT" "$APP/Contents/Library/LaunchAgents/$AGENT"; then
  step "Installing $APP"
  osascript -e 'quit app "macwinkvm"' 2>/dev/null || true
  pkill -x macwinkvm 2>/dev/null || true
  for _ in {1..50}; do pgrep -x macwinkvm >/dev/null || break; sleep 0.1; done
  rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
  cp "$bin" "$APP/Contents/MacOS/macwinkvm"
  cp "$REPO/mac/Resources/Info.plist" "$APP/Contents/Info.plist"
  mkdir -p "$APP/Contents/Resources"; echo "$new_bin_sum" > "$APP/Contents/Resources/build.sha256"
  mkdir -p "$APP/Contents/Library/LaunchAgents"; cp "$REPO/mac/Resources/$AGENT" "$APP/Contents/Library/LaunchAgents/"
  codesign --force --sign - "$APP" 2>/dev/null
fi

pgrep -x macwinkvm >/dev/null || { step "Starting macwinkvm (look for the keyboard icon in the menu bar)"; open "$APP" || { sleep 2; open "$APP"; }; }

cat <<'MSG'
==> Done. Run mac/doctor.sh to verify.
    First time only:
      - Open macwinkvm → Connect. macOS asks for Accessibility for "deskflow-core":
        System Settings → Privacy & Security → Accessibility → turn it on, then Disconnect/Connect.
      - Open macwinkvm (Spotlight / Applications) any time for the window: Connect, auto-connect,
        "Launch at login (hidden)", and whether to show the menu-bar icon. It never shows in the Dock.
MSG
