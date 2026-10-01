---
name: setup-mac-win-kvm
description: Explain mac-win-kvm and walk a user through installing it on their Windows PC and Mac. Use when someone asks what this repo is, how it works, or to set it up / install / configure / troubleshoot it.
---

# Set up mac-win-kvm with the user

You are guiding a possibly non-technical person. Keep messages short, one step at a time. **You** find facts (IPs, names, versions); **they** make decisions and do the few clicks only a human can do.

## 0. Where am I?

Detect the OS (`uname` / `$env:OS`). The Mac is the usual starting point.

- **The Windows side needs doing too.** Offer two options:
  - (a) They run Claude Code on the PC with the same prompt, and you do each side there.
  - (b) You give them exact PowerShell commands to paste. Ask which they prefer.
- **The repo needs to be on both machines.** If it isn't cloned yet, clone it: on the Mac, somewhere like `~/Documents/GitHub/mac-win-kvm` unless their own instructions say otherwise.

## 1. Explain (keep it brief, offer more)

Tell them, in about 6 lines:
- The keyboard and mouse stay plugged into the PC. Push the mouse off the screen edge toward the Mac, or press Win+Esc, and you're controlling the Mac.
- It uses the open-source Deskflow over their home network, encrypted, and only between their two machines.
- On the Mac, a small app with no Dock icon handles Connect/Disconnect. It can auto-connect when they get home.
- Optional extras: a fallback over ZeroTier/Tailscale, and keyboard backlight colours showing which machine is active.
- Tested with a Windows 11 PC and a macOS 14+ Mac only.

Ask if they want more detail; if so, explain from `docs/HOW-IT-WORKS.md`.

## 2. Gather facts yourself

On the Mac, run and read:
- `sw_vers`, `uname -m`
- `ipconfig getifaddr en0`
- `xcode-select -p`, which must exist (if not, `xcode-select --install`, which the user clicks through)
- whether `python3` is available
- ZeroTier or Tailscale IPs, if installed

On the PC (yourself, or via the commands you give them):
- `hostname`
- `ipconfig` (the LAN IPv4, and any ZeroTier/Tailscale adapter)
- `python --version`
- `git --version`, and `Test-Path 'C:\Program Files\Git\usr\bin\openssl.exe'`
- `winget --version`
- the monitor layout, if relevant
- any VPN client (for example Mullvad, which needs "local network sharing" on)

If a prerequisite is missing, say what it is and how to get it: Git for Windows, Python 3.10+ ("Add to PATH"), or the Command Line Tools.

## 3. Ask the decisions (one round, a recommendation for each)

Number the questions, give your recommended answer, and let them answer in one go:

1. **Where is the Mac**, relative to the PC's screen: left, right, above or below? → whichever matches their desk.
2. **Key mapping on the Mac:**
   - (a) Mac layout: Alt→⌘, Win→⌥, Ctrl→⌃ (recommended if they know Mac shortcuts)
   - (b) Windows feel: Ctrl→⌘, Win→⌃
3. **Mission Control shortcut:** leave it unchanged (recommended), or Ctrl+Tab.
4. **Fallback network:** if ZeroTier or Tailscale is on both machines, use it as a fallback (recommended). Otherwise, LAN only.
5. **Keyboard lighting:** only if their keyboard is RGB and OpenRGB supports it. Off by default. If they want it, you'll check whether OpenRGB detects the keyboard.
6. **Auto-connect when home:** on or off. Recommended on once it works.

## 4. Write settings.json

Copy `settings.example.json` → `settings.json` and fill it in from the facts and answers:
- `server.name` (exact hostname), `server.lan` and `server.zerotier` (or `""`)
- `client.side`
- `allowedSubnets`: their LAN /24, plus the overlay subnet if used
- `macModifiers`: (a) `{"ctrl":"ctrl","alt":"super","super":"alt"}`; (b) `{"ctrl":"super","alt":"alt","super":"ctrl"}`
- `macMissionControl`
- `lighting.enabled` and `lighting.keyboard`

Show them the file and confirm it. **Use the same file on both machines.** It's git-ignored; never commit it.

## 5. Install, in this order

Before each step, say in one line what it will do. Before anything that installs software or shows an admin prompt, get a yes.

1. **PC:** `powershell -ExecutionPolicy Bypass -File windows\install.ps1`
   - It installs Deskflow via winget (plus OpenRGB and `openrgb-python` if lighting is on) and generates the certificate.
   - An **admin prompt** appears for the firewall: they click Yes.
   - It writes `trust\server.sha256`.
2. **Carry the PC's fingerprint to the Mac.** The file holds one line (`v2:sha256:…`). They paste it to you, and you write it to the Mac's `trust/server.sha256`.
3. **Mac:** `mac/install.sh`
   - It installs Deskflow from the official DMG (checksum-verified), builds and installs `MacWinKVM.app`, and writes `trust/mac.sha256`.
4. **Carry the Mac's fingerprint to the PC** the same way, into `trust\mac.sha256`, then **re-run `windows\install.ps1`**.
5. **First connect:** they open **MacWinKVM** and click Connect.
   - macOS asks for **Accessibility** for **deskflow-core**. Guide them: System Settings → Privacy & Security → Accessibility → turn on deskflow-core.
   - Then Disconnect and Connect again.
   - Suggest turning on *launch at login (hidden)* and, if they want, auto-connect.

## 6. Verify

- Run `mac/doctor.sh` (and have `windows\doctor.ps1` run). Fix every FAIL; explain any WARN.
- Walk through the README's **Manual checklist**, a few items per message: edge crossing, corners, Win+Esc, keys, clipboard (both directions, including a screenshot), scroll direction and side buttons, Scroll Lock, lighting, the app buttons.
- If something's off, see Troubleshooting below. Change `settings.json` and re-run the install on the affected side, never the Deskflow GUI.

## Troubleshooting you can do

- **Lag:** ping the PC from the Mac, and the router from the PC.
  - If the PC → router ping is slow, its Ethernet power saving (Green Ethernet / Power Saving Mode) is the usual culprit. `windows\doctor.ps1` warns about it. Turning it off needs an admin prompt and resets the network for a few seconds, so ask first.
  - A big upload on the PC also causes lag. Suggest limiting it, or router QoS/SQM.
- **"Desktop certificate not trusted":** the PC certificate was regenerated. Carry `trust\server.sha256` over again and re-run `mac/install.sh`.
- **The Mac cursor doesn't move:** Accessibility isn't granted to deskflow-core.
- **Unreachable:** the IP changed (check `ipconfig`), a VPN is blocking the LAN, or the firewall subnets are wrong in `allowedSubnets`.
- **Starts locked:** the Scroll Lock toggle is on; press it.
- **PC keyboard and mouse dead after the Mac dropped off** (e.g. it switched Wi-Fi while it had the cursor): the watchdog restarts Deskflow within about 3 s (`helper.log` says `watchdog:`). If it didn't, check that the helper is running (`windows\doctor.ps1`). Manual escape: Ctrl+Alt+Del → Task Manager → end Deskflow.
- **Logs:**
  - Mac: `~/Library/Application Support/macwinkvm/client.log`
  - PC: `%LOCALAPPDATA%\macwinkvm\server.log`, and `helper.log` (watchdog and lighting)

## Uninstall

`windows\uninstall.ps1` and `mac/uninstall.sh`. Add `-KeepDeskflow` / `--keep-deskflow` to keep Deskflow.

## Rules

- Never commit or print `settings.json` contents to a public place, and never do that with `trust/` files or private keys.
- Don't disable security features to make something work, such as turning off TLS or opening the firewall to everything. Fix the cause instead.
- If they're on an untested combination (Mac as server, Linux, multiple monitors), say so plainly before trying.
