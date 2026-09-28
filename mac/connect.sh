#!/usr/bin/env bash
# Connect this Mac to the desktop from the command line (Ctrl+C to disconnect).
# Usage: mac/connect.sh [lan|zerotier|<host>]   (default: lan)
source "$(dirname "$0")/common.sh"
target="${1:-lan}"
case "$target" in
  lan|zerotier) host="$(setting server "$target")" ;;
  *) host="$target" ;;
esac
ensure_client_cert
write_client_settings "$host"
echo "==> Connecting to $(setting server name) at $host (log: $CLIENT_LOG)"
# deskflow-core on macOS ignores SIGINT/SIGTERM, so Ctrl+C has to SIGKILL it.
"$DESKFLOW_CORE" client --new-instance -s "$CLIENT_SETTINGS" &
pid=$!
trap 'kill -9 $pid 2>/dev/null; echo; echo "==> Disconnected"; exit 0' INT TERM
wait $pid
