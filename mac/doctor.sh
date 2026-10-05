#!/usr/bin/env bash
# Health check for the Mac side. Exit code = number of failures.
source "$(dirname "$0")/common.sh"
set +e
fails=0
check() { local name="$1" fix="$2"; shift 2; if "$@" >/dev/null 2>&1; then echo "PASS  $name"; else echo "FAIL  $name  -> $fix"; fails=$((fails+1)); fi; }
warn()  { local name="$1" fix="$2"; shift 2; if "$@" >/dev/null 2>&1; then echo "PASS  $name"; else echo "WARN  $name  -> $fix"; fi; }

check "Deskflow installed" "run mac/install.sh" test -x "$DESKFLOW_CORE"
check "Deskflow hidden from the Dock" "run mac/install.sh" bash -c "[[ \"\$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' /Applications/Deskflow.app/Contents/Info.plist 2>/dev/null)\" == true ]]"
check "Mac certificate exists" "run mac/install.sh" test -f "$CERT_FILE"
check "trust/mac.sha256 matches the certificate" "run mac/install.sh, then copy trust/mac.sha256 to the desktop" \
  bash -c "[[ \"\$(cat '$MAC_FP_FILE')\" == \"$(cert_fingerprint "$CERT_FILE" 2>/dev/null)\" ]]"
check "desktop certificate trusted (trust/server.sha256)" "copy trust\\server.sha256 from the desktop into trust/, run mac/install.sh" cmp -s "$SERVER_FP_FILE" "$TRUSTED_SERVERS"
check "connection settings" "run mac/install.sh" test -f "$STATE_DIR/Deskflow-lan.conf"
check "macwinkvm.app installed" "run mac/install.sh" test -x "$APP/Contents/MacOS/macwinkvm"
check "macwinkvm running" "open /Applications/macwinkvm.app" pgrep -x macwinkvm
warn  "launch at login enabled" "menu bar → Launch at Login" bash -c "sfltool dumpbtm 2>/dev/null | grep -q 'io.github.macwinkvm'"
port="$(setting port)"
lan_ok=0; nc -z -G 2 "$(setting server lan)" "$port" >/dev/null 2>&1 && lan_ok=1
zt_ok=0;  fb="$(setting server zerotier)"; [[ -n "$fb" ]] && nc -z -G 2 "$fb" "$port" >/dev/null 2>&1 && zt_ok=1
if (( lan_ok )); then echo "PASS  desktop reachable via LAN"; elif (( zt_ok )); then echo "WARN  desktop reachable only via the fallback address"; else echo "WARN  desktop unreachable (fine when away from home)"; fi
warn  "Accessibility granted to deskflow-core" "System Settings → Privacy & Security → Accessibility" \
  bash -c "! tail -200 '$CLIENT_LOG' 2>/dev/null | grep -q 'failed to create quartz event tap'"

(( fails )) && echo -e "\n$fails problem(s) found." || echo -e "\nAll good."
exit $fails
