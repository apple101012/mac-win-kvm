# 0001 — Read Deskflow state from the server log

Status: accepted (Deskflow 1.26.0)

## Context

The lighting helper needs to know which screen is active, whether the cursor is locked, and whether the Mac is connected. We checked this against a real Windows server and Mac client session (names changed to DESKTOP-PC / MacBook). The recordings are in `fixtures/`.

## Decision

The lighting helper tails the Deskflow server log. Log level `4` (INFO) is enough: checked on the live server, it includes the `IPC:`, `NOTE:` and `INFO:` lines below. DEBUG (`5`) is only needed for troubleshooting. Deskflow's IPC channel isn't needed. These lines are stable and enough:

| Event | Log line |
|---|---|
| Active screen changed | `INFO: switch from "<A>" to "<B>" at x,y` (also `jump from … to …` when the active client dies) |
| Locked | `NOTE: cursor locked to current screen`, or at startup `NOTE: scroll lock is on, locking cursor to screen` |
| Unlocked | `NOTE: cursor unlocked from current screen` |
| Client connected | `IPC: client "<name>" has connected` |
| Client gone | `IPC: client "<name>" has disconnected` / `IPC: client "<name>" is dead` |
| Server up | `IPC: started server, waiting for clients` |

A server that stopped is detected when the process exits, because nothing gets logged when it's killed.

## Findings that shape later tickets

- **Settings:**
  - `deskflow-core <server|client> --new-instance -s <file>` runs headless from an INI settings file.
  - Keys used: `core/computerName`, `core/port`, `client/remoteHost`, `client/invertYScroll`, `security/tlsEnabled`, `security/checkPeerFingerprints`, `security/certificate`, `server/externalConfig`, `server/externalConfigFile`, `log/toFile`, `log/file`, `log/level`.
  - `log/level` is an **integer index**: FATAL=0 … INFO=4, DEBUG=5. A string silently falls back to the default level.
- **TLS:**
  - Only Deskflow's GUI generates certificates, so `deskflow-core` needs a PEM (key followed by cert) at `security/certificate`. The **client needs one too**.
  - The default cert path is `<settings dir>/tls/deskflow.pem` (on the Mac, the settings dir is the `-s` file's directory; on non-portable Windows it's `C:\ProgramData\Deskflow`).
  - The client trusts servers listed in `<settings dir>/tls/trusted-servers`, one line per server: `v2:sha256:<lowercase hex of sha256(DER cert)>`. The server checks clients against `tls/trusted-clients` when `checkPeerFingerprints=true`.
  - We generate certificates with `openssl`. On Windows, Git for Windows ships `openssl.exe`.
- **Win+Esc** should map to `switchToNextScreen`. With `switchInDirection(left)`, the second press doesn't bring you back.
- **Scroll Lock:** the lock follows the keyboard's Scroll Lock *toggle* state. If Scroll Lock is already on when the server starts, it starts locked, so "starts unlocked" depends on the Scroll Lock state.
- **Synthetic input:** input created with Win32 `mouse_event`/`keybd_event` *does* drive the server (edge crossing, Scroll Lock, hotkeys).
- **Reconnecting too fast:** if a client reconnects too quickly after being killed, the server rejects it with `a client with name "MacBook" is already connected` until it declares the old one dead (about 1 s). The client retries by itself.
- **Mac permissions:** without Accessibility permission, the client logs `failed to create quartz event tap`.
- **Firewall:** the Windows MSI adds firewall rules named "Deskflow Server" / "Deskflow Client" that allow inbound traffic on **all profiles and addresses**. `windows/install.ps1` narrows them to `allowedSubnets`.
- **Mac install:** Homebrew is blocked until the Xcode licence is accepted, so the Mac install uses the official release DMG and checks it against `sums.txt`. (Homebrew isn't needed either way.)
- **macOS: `deskflow-core` ignores SIGTERM and SIGINT** (it's stuck in the Cocoa loop). Anything that stops the client has to use SIGKILL.
