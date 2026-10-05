# mac-win-kvm

**Use your Windows PC's keyboard and mouse on your Mac: no hardware KVM switch, no extra cables.**

Push the mouse off the edge of your Windows screen and it appears on the Mac; your keyboard follows. Push it back and you're on Windows again. It's built on the open-source [Deskflow](https://github.com/deskflow/deskflow) and adds:

- **Setup that installs itself.** The installers are safe to re-run, and a `doctor` script checks each machine.
- **Nothing in the Dock.** The install marks Deskflow as an agent app, so it never appears in the Dock, not even under recent apps.
- **A Mac app with no Dock icon.** Open it for Connect/Disconnect and settings, and optionally show a menu-bar icon.
- **LAN first, with a fallback.** If your home network is flaky, it switches to ZeroTier or Tailscale. It reconnects after the Mac sleeps and can auto-connect when you get home.
- **Mutual TLS pinning.** Each machine only talks to the other one, and the Windows firewall is limited to your subnets.
- **Mac-friendly keys.** Alt → ⌘, Win → ⌥, Ctrl → ⌃, so your hands stay in the Mac layout. Switch machines with Win+Esc, and lock the cursor with Scroll Lock (handy for games).
- **Watchdog:** if the Mac drops off while it has the cursor (for example it switches Wi-Fi), Deskflow 1.26 can leave the PC's keyboard and mouse dead. A background helper notices within about 3 s and restarts Deskflow, so input comes back by itself.
- **Screenshots copied on the Mac paste correctly on Windows.** Deskflow 1.26 garbles them, and this works around it.
- **Optional keyboard lighting**, sent straight over USB in milliseconds: white on Windows, blue on the Mac, red or purple when the cursor is locked. Supported: Sinowealth `258A:010C` keyboards such as the **AULA F87 Pro**.

> **Tested setup:** a Windows 11 desktop as the *server*, sharing its keyboard and mouse, and a macOS 14+ Mac as the *client*, on the same home network. Keyboard lighting supports Sinowealth `258A:010C` keyboards (tested: AULA F87 Pro over USB). Other combinations (Mac as server, Linux) aren't supported yet.

## Easiest way: let Claude set it up

Open [Claude Code](https://claude.com/claude-code) on your **Mac** and paste:

```text
Set up https://github.com/apple101012/mac-win-kvm for me. Clone it into a sensible folder, read its CLAUDE.md, explain how it works, ask me what you need to know, then install it step by step.
```

Claude will:
1. Explain how it works, at whatever depth you like.
2. Ask a few questions: which side the Mac sits on, whether you use ZeroTier or Tailscale, whether you want keyboard lighting, and so on. It finds the rest itself, such as IP addresses and machine names.
3. Write your `settings.json` and run the installers.
4. Walk you through the few clicks only you can do: macOS permissions and the Windows admin prompt.
5. Run the checklist with you and troubleshoot anything that's off.

For the Windows side, either run Claude Code there too and paste the same prompt, or let Claude on the Mac give you the exact commands to run. The step-by-step script Claude follows is in [`.claude/skills/setup-mac-win-kvm/SKILL.md`](.claude/skills/setup-mac-win-kvm/SKILL.md).

## Manual install

**Prerequisites**
- **Windows:** [Git for Windows](https://git-scm.com/download/win), [Python 3.10+](https://www.python.org/downloads/) on PATH, and winget (built into Windows 11).
- **Mac:** macOS 14+ and the Command Line Tools (`xcode-select --install`). You don't need Xcode itself.
- **Both:** the same network. For the optional fallback, both machines on the same [ZeroTier](https://www.zerotier.com) or [Tailscale](https://tailscale.com) network.

**1. Configure (on both machines).** Clone the repo, copy [`settings.example.json`](settings.example.json) to `settings.json`, and fill in:

| Key | What |
|---|---|
| `server.name` | the Windows PC's name (`hostname`) |
| `server.lan` | its LAN IP (`ipconfig`) |
| `server.zerotier` | optional fallback IP on ZeroTier or Tailscale, or `""` |
| `client.name` | a name for the Mac |
| `client.side` | where the Mac sits relative to the Windows screen: `left`, `right`, `up` or `down` |
| `allowedSubnets` | which networks may connect, e.g. `192.168.1.0/24` plus your ZeroTier/Tailscale range |
| `macModifiers` | key mapping on the Mac (default Alt→⌘, Win→⌥, Ctrl→⌃) |
| `macMissionControl` | `unchanged`, `ctrl+tab` or `ctrl+up` |
| `lighting.enabled` | `true` to colour the keyboard. Supported: Sinowealth `258A:010C` keyboards, e.g. AULA F87 Pro, connected by USB cable |

Use the same `settings.json` on both machines.

**2. Windows** (PowerShell, in the repo folder):

```powershell
powershell -ExecutionPolicy Bypass -File windows\install.ps1   # approve the admin prompt (firewall)
```

**3. Mac.** Copy `trust\server.sha256` from the PC into the Mac's `trust/` folder, then:

```bash
mac/install.sh
```

**4. Back on Windows.** Copy the Mac's `trust/mac.sha256` into the PC's `trust\` folder and run `windows\install.ps1` again. Now both machines trust each other.

**5. First connect.** Open **MacWinKVM** (Spotlight or Applications) and click **Connect**. macOS asks for **Accessibility** access for **deskflow-core**. Turn it on in System Settings → Privacy & Security → Accessibility, then click Disconnect and Connect again.

**6. Check both machines:** `windows\doctor.ps1` and `mac/doctor.sh`, then run the [checklist](#manual-checklist).

## Everyday use

| | |
|---|---|
| Go to the Mac and back | push the mouse off the Windows screen edge (not the corners), or press **Win+Esc** |
| Lock the cursor to the current machine | **Scroll Lock** (press again to unlock) |
| On the Mac | **Alt** = ⌘, **Win** = ⌥, **Ctrl** = ⌃ (configurable) |
| Keyboard colour (if lighting is on) | white = Windows, blue = Mac, red = locked to Windows, purple = locked to Mac |

**Mac:** open **MacWinKVM** any time for its window: Connect/Disconnect, *auto-connect when the desktop is reachable*, *launch at login (hidden)* and *show icon in the menu bar*. It never shows in the Dock, and closing the window keeps it running.

**Windows:** everything starts at login. **Deskflow** sits in the tray as the server. A small background helper runs too: the watchdog, plus the keyboard lighting if it's enabled. Don't change settings in the Deskflow window; edit `settings.json` and re-run the install instead.

## Manual checklist

1. [ ] Push the mouse off the Windows screen edge that faces the Mac (middle height). The cursor appears on the Mac.
2. [ ] Push it off the Mac's opposite edge. It's back on Windows.
3. [ ] The corners listed in `deadCorners` do **not** cross.
4. [ ] **Win+Esc** jumps to the Mac and back, and doesn't open the Start menu.
5. [ ] On the Mac: Alt+C / Alt+V copy and paste, and Win+Backspace deletes a word.
6. [ ] Copy text both ways. Copy a screenshot both ways, with correct colours.
7. [ ] The mouse wheel scrolls the same way on both machines, and the side buttons go Back/Forward in a Mac browser.
8. [ ] **Scroll Lock** stops the mouse crossing; press it again to unlock.
9. [ ] If lighting is enabled: white on Windows, blue on the Mac, red or purple when locked, white after Disconnect.
10. [ ] MacWinKVM: Connect shows "Connected via LAN"; Disconnect and Quit work. With auto-connect on, closing the lid and reopening it reconnects on its own.

## How it works

See **[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md)**. It covers the architecture, the connection logic, TLS trust, keyboard lighting, the clipboard fix, and what every file does. Findings about Deskflow's behaviour are recorded in [`docs/adr/`](docs/adr).

## Troubleshooting

- **Laggy mouse.** Run `ping <desktop LAN IP>` from the Mac; it should be under about 10 ms.
  - If the PC is also slow to reach its own router, its network is the problem. Realtek adapters with **Green Ethernet** or **Power Saving Mode** on caused 100–800 ms spikes. Turning both off (Device Manager → Ethernet adapter → Advanced) fixed it, and `windows\doctor.ps1` warns about it.
  - A big upload on the PC can also fill the connection. Limit its speed, or turn on QoS/SQM on your router.
- **"Desktop certificate not trusted".** The PC made a new certificate, for example after an uninstall. Copy its `trust\server.sha256` to the Mac again and re-run `mac/install.sh`.
- **The Mac doesn't move.** Accessibility isn't granted to **deskflow-core** (see step 5).
- **PC keyboard and mouse dead after the Mac dropped off.** The watchdog should restart Deskflow within about 3 s. If it doesn't, run `windows\doctor.ps1`. Manual escape: **Ctrl+Alt+Del** → Task Manager → end Deskflow.
- **The cursor starts locked.** Deskflow follows the Scroll Lock *toggle*, so press Scroll Lock once.
- **A VPN on the PC** (e.g. Mullvad) must allow local network access, or the Mac can't reach it.

## Security

- **Encryption:** all traffic is TLS, and each machine pins the other's certificate fingerprint (the `trust/` files). Your private keys never leave their machine and are never in the repo.
- **Firewall:** the Windows rules are limited to `allowedSubnets`.
- **Private files:** `settings.json` and `trust/*.sha256` are git-ignored, so your addresses and fingerprints stay local.

## Uninstall

`windows\uninstall.ps1` and `mac/uninstall.sh`. Add `-KeepDeskflow` / `--keep-deskflow` to keep Deskflow itself installed.

## Tests

```bash
python3 -m unittest discover -s tests -t .   # config generator, keyboard lighting
mac/test.sh                                  # Mac connection logic, Deskflow log parser, BMP encoder
```

## Credits and licence

- **Built on:** [Deskflow](https://github.com/deskflow/deskflow) (GPL-2.0), which does the actual keyboard/mouse sharing. The keyboard lighting protocol was learned from [OpenRGB](https://openrgb.org)'s driver (GPL-2.0); no OpenRGB code is included. Deskflow is downloaded from their official releases at install time; neither is included in this repo.
- **Licence:** this repo's own code is [MIT](LICENSE).
