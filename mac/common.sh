# Shared paths for the Mac (client) side. Source this file.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKFLOW_CORE="/Applications/Deskflow.app/Contents/MacOS/deskflow-core"
STATE_DIR="$HOME/Library/Application Support/macwinkvm"
TLS_DIR="$STATE_DIR/tls"                 # Deskflow looks for tls/ next to the -s settings file
CERT_FILE="$TLS_DIR/deskflow.pem"
TRUSTED_SERVERS="$TLS_DIR/trusted-servers"
CLIENT_SETTINGS="$STATE_DIR/Deskflow.conf"
CLIENT_LOG="$STATE_DIR/client.log"
MAC_FP_FILE="$REPO/trust/mac.sha256"
SERVER_FP_FILE="$REPO/trust/server.sha256"

[[ -f "$REPO/settings.json" ]] || { echo "settings.json not found: copy settings.example.json to settings.json and fill it in (or ask Claude to set it up)"; exit 1; }

# setting server lan  ->  value of settings.json["server"]["lan"] ("" if missing)
setting() {
  python3 - "$REPO/settings.json" "$@" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    v = v.get(k, "") if isinstance(v, dict) else ""
print(v)
PY
}

# Deskflow fingerprint format: v2:sha256:<lowercase hex of sha256(DER cert)>
cert_fingerprint() { echo "v2:sha256:$(openssl x509 -in "$1" -outform DER | shasum -a 256 | cut -d' ' -f1)"; }

ensure_client_cert() {
  mkdir -p "$TLS_DIR" "$REPO/trust"
  if [[ ! -f "$CERT_FILE" ]]; then
    local tmp; tmp="$(mktemp -d)"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/k.pem" -out "$tmp/c.pem" -days 3650 -subj /CN=Deskflow 2>/dev/null
    cat "$tmp/k.pem" "$tmp/c.pem" > "$CERT_FILE"; chmod 600 "$CERT_FILE"; rm -rf "$tmp"
    echo "==> Generated Mac client certificate"
  fi
  local fp; fp="$(cert_fingerprint "$CERT_FILE")"
  if [[ "$(cat "$MAC_FP_FILE" 2>/dev/null)" != "$fp" ]]; then
    echo "$fp" > "$MAC_FP_FILE"
    echo "==> Wrote trust/mac.sha256 (copy it into the desktop's trust\\ folder, then re-run windows\\install.ps1)"
  fi
  if [[ -f "$SERVER_FP_FILE" ]]; then cp "$SERVER_FP_FILE" "$TRUSTED_SERVERS"
  else echo "==> WARNING: trust/server.sha256 missing: copy it from the desktop (made by windows\\install.ps1), then re-run"; fi
}

# write_client_settings <remote host> [settings file]
write_client_settings() {
  (cd "$REPO" && python3 -m kvmconfig.generate client-settings "remote_host=$1" "log_file=$CLIENT_LOG") > "${2:-$CLIENT_SETTINGS}"
}

# One settings file per route for the app / macwinkvm-cli (they share tls/).
write_route_settings() {
  write_client_settings "$(setting server lan)" "$STATE_DIR/Deskflow-lan.conf"
  local fallback; fallback="$(setting server zerotier)"
  if [[ -n "$fallback" ]]; then write_client_settings "$fallback" "$STATE_DIR/Deskflow-zerotier.conf"
  else rm -f "$STATE_DIR/Deskflow-zerotier.conf"; fi
}

APP="/Applications/macwinkvm.app"
DESKFLOW_VERSION="1.26.0"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools   # build without accepting the Xcode licence
