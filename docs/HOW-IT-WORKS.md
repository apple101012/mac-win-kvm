# How mac-win-kvm works

## The big picture

```
 Windows PC  (server)                                    Mac  (client)
 ┌─────────────────────────────────┐                     ┌──────────────────────────────────┐
 │ keyboard + mouse (plugged in)   │                     │ MacWinKVM.app  (no Dock icon)     │
 │        │                        │                     │  ├─ window / optional menu icon   │
 │        ▼                        │   TLS, port 24800   │  ├─ ConnectionController (policy) │
 │ Deskflow server  ───────────────┼────────────────────►│  ├─ runs deskflow-core client ────┼─► moves the Mac's
 │   (tray app, starts at login)   │  LAN first, then    │  └─ clipboard image fix           │   cursor, types keys
 │        │ writes server.log      │  ZeroTier/Tailscale │                                    │
 │        ▼                        │                     └──────────────────────────────────┘
 │ helper: watchdog + lighting (optional) ──► USB ──► keyboard
 └─────────────────────────────────┘
```

[Deskflow](https://github.com/deskflow/deskflow) does the hard part: it captures input on the machine the keyboard is plugged into and replays it on the other one. This repo wraps it in configuration, installers, a Mac app, and a few fixes.

## 1. One settings file → Deskflow config

`settings.json` is the only file you edit. `kvmconfig/generate.py` turns it into:

- **The server config (Windows).** Which screen sits where (`client.side`), the corners that don't switch (`switchCorners`), clipboard sharing, the switch hotkey (`keystroke(Super+Escape) = switchToNextScreen`), and per-screen modifier remaps for the Mac (`alt = super`, `super = alt`).
- **The Deskflow GUI settings (Windows).** It runs as a server in "desktop" mode (not a Windows service) with TLS on, peer checking on, and our config file.
- **The client settings (Mac).** One file per route (LAN and fallback), each pointing `client/remoteHost` at a different address.

Scroll Lock locking is built into Deskflow: the cursor is locked while the Scroll Lock toggle is on.

## 2. Trust: mutual TLS with pinned fingerprints

- **Certificates:** each side generates its own self-signed certificate with `openssl` (Git for Windows ships one on the PC). Deskflow's command-line core can't generate certificates itself.
- **Fingerprints:** the installers write each certificate's fingerprint to `trust/server.sha256` (PC) and `trust/mac.sha256` (Mac). You copy each file to the other machine once.
- **Checking:** the Mac only connects to a server whose fingerprint matches, and the PC only accepts a client whose fingerprint matches (`checkPeerFingerprints=true`).
- **Privacy:** private keys stay in `C:\ProgramData\Deskflow\tls` and `~/Library/Application Support/macwinkvm/tls`, never in the repo.

## 3. The Mac app

The app is a Swift package under `mac/`:

| Module | What it does | Tested? |
|---|---|---|
| `KVMCore/ConnectionController` | Every connection decision, as a pure state machine: *events in → effects out* | yes (unit) |
| `KVMCore/ClientLogParser` | Turns deskflow-core's log lines into events: connected, disconnected, attempt failed, fatal (untrusted, refused, missing certificate) | yes |
| `KVMCore/BMPEncoder` | Makes plain 24-bit BMPs for the clipboard fix | yes |
| `KVMRuntime/*` | Thin adapters: TCP reachability probe, spawning and killing deskflow-core, retry timers, sleep/wake and network-change observers | by hand |
| `macwinkvm/App.swift` | The window, the optional menu-bar icon, and launch-at-login | by hand |

**Connection policy (ConnectionController)**
- **Order:** try the LAN address first. If it's unreachable, or Deskflow keeps failing on it, try the fallback address.
- **Nothing reachable:** retry with backoff (2, 4, 8, 16, then 30 s) and show "Desktop unreachable".
- **Dropped connection:** stop the client and start over from the LAN.
- **Certificate or refusal errors:** stop and say why. Retrying can't fix these.
- **Auto-connect:** check quietly every 30 s and join when the PC is reachable. A manual Disconnect pauses this until the next wake or network change.
- **Sleep:** disconnect on sleep, and on wake reconnect only if you were connected.
- **Network changes:** if you're on the fallback, check whether the LAN is back and move to it.

**Details that matter**
- **Stopping the client:** deskflow-core on macOS ignores SIGTERM and SIGINT, so the app stops it with SIGKILL.
- **Accessibility permission:** the app spawns deskflow-core "responsibility-disclaimed", so macOS asks for access for **deskflow-core** itself rather than for this ad-hoc-signed app. Otherwise every rebuild would reset the permission.
- **Launch at login:** a login agent inside the app bundle starts it with `--background`, so it stays hidden at login and shows its window only when you open it.

## 4. The clipboard image fix

When you copy an image on a Mac, macOS offers it to Deskflow as a BMP with a V4/V5 header. Deskflow 1.26 cuts that header down to 40 bytes, so Windows pastes garbage colours (upstream fix [deskflow#9638](https://github.com/deskflow/deskflow/pull/9638), not merged).

While connected, the Mac app watches the clipboard. When a plain image lands there, it adds its own `com.microsoft.bmp` in the simplest format: a 40-byte header, 24-bit, uncompressed. Deskflow sends that one instead. File copies and rich documents are left alone.

## 5. Watchdog (Windows, always on)

Deskflow 1.26 can mark the active Mac as dead without handing input back to the PC, for example when the Mac switches Wi-Fi mid-session. The PC's keyboard and mouse then do nothing.

`kvmlight/strand.py` (`StrandDetector`, pure and tested against the real recording) watches the server log. If the Mac is reported dead while it had the cursor, and no switch back follows within 3 s, the helper restarts Deskflow. Input comes back and the Mac app reconnects on its own. See [ADR 0002](adr/0002-watchdog-for-input-stranded-on-a-gone-mac.md).

## 6. Keyboard lighting (optional, Windows)

```
Deskflow server.log ──► kvmlight/helper.py ──► LightingTracker ──► LightingWorker ──► USB (HID feature report) ──► keyboard
```

- **Log format:** the server log is the event source. Its line formats are pinned in [ADR 0001](adr/0001-deskflow-events-from-server-log.md), with real recordings in `fixtures/`.
- **State:** `LightingTracker` (pure, unit-tested against the recordings) tracks which screen is active, whether it's locked, and whether the Mac is connected. It picks one colour. It knows that a *rejected duplicate* client's disconnect isn't the real Mac leaving.
- **Talking to the keyboard:** `kvmlight/sinowealth.py` sends a 520-byte "stream LEDs" frame to the keyboard's lighting channel (interface 1, usage page `0xFF00`). It takes about 12 ms. The protocol was learned from OpenRGB's driver; nothing is ever written to the keyboard's flash.
- **Why not OpenRGB:** we tried it first. Its Python SDK took about 10 s per change with OpenRGB 1.0, and OpenRGB lost the keyboard after USB reconnects and then coloured the motherboard instead.
- **Keep-alive:** the keyboard leaves direct mode unless frames keep coming, so `LightingWorker` re-sends the colour every 0.4 s, and immediately on a change. If the keyboard is unplugged, it reopens it when it's back.
- **Never blocks the watchdog:** lighting runs in its own thread.

## 7. Install, doctor and uninstall

- **Install is safe to re-run:** `windows/install.ps1` and `mac/install.sh` only change what differs, and they restart services only when their config or code changed.
- **Downloads are pinned:** Deskflow comes from winget (Windows) or the release DMG checked against its `sums.txt` (Mac). Lighting only needs the `hidapi` Python package.
- **Doctor checks each part:** installed, configured, trusted, running, reachable, permissions, the firewall scope, and the Ethernet power-saving settings that cause lag.

## Files

```
settings.example.json   copy to settings.json (git-ignored) and fill in
kvmconfig/              settings → Deskflow config (Python, stdlib only)
kvmlight/               background helper: watchdog (strand detector), lighting tracker, USB keyboard driver
windows/                install / doctor / uninstall (PowerShell 5+)
mac/                    Swift package (app, CLI, core), install / doctor / uninstall / test
tests/  fixtures/       Python tests; recorded Deskflow logs
docs/                   this file, ADRs
.claude/skills/         the guided setup Claude follows
trust/                  fingerprint exchange (contents git-ignored)
```
