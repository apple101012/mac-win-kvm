"""Turn settings.json (see settings.example.json) into Deskflow config files.

Usage: python -m kvmconfig.generate <server-config|server-settings|client-settings> [key=value ...]
"""

import json
import sys
from pathlib import Path

OPPOSITE = {"left": "right", "right": "left", "up": "down", "down": "up"}
CORNERS = {"top-left", "top-right", "bottom-left", "bottom-right"}
MODIFIERS = {"shift", "ctrl", "alt", "meta", "super", "none"}
LOG_LEVELS = range(0, 8)  # FATAL=0 .. INFO=4, DEBUG=5, DEBUG1=6, DEBUG2=7


def load_settings(path):
    return json.loads(Path(path).read_text())


def render_server_config(s):
    server, client = s["server"]["name"], s["client"]["name"]
    side = s["client"]["side"]
    if side not in OPPOSITE:
        raise ValueError(f"client.side must be one of {sorted(OPPOSITE)}, got {side!r}")

    remaps = []
    for key, target in s.get("macModifiers", {}).items():
        if key not in MODIFIERS or target not in MODIFIERS:
            raise ValueError(f"unknown modifier mapping {key!r} -> {target!r}")
        if key != target:
            remaps.append(f"\t\t{key} = {target}")

    sw = s["switching"]
    corners = sw.get("deadCorners", [])
    for c in corners:
        if c not in CORNERS:
            raise ValueError(f"unknown corner {c!r}")

    options = [f"\tclipboardSharing = {'true' if s.get('clipboard', True) else 'false'}"]
    if corners:
        options.append("\tswitchCorners = none " + " ".join("+" + c for c in corners))
        options.append(f"\tswitchCornerSize = {int(sw.get('cornerSize', 0))}")
    options.append(f"\tkeystroke({sw['hotkey']}) = switchToNextScreen")

    lines = [
        "section: screens",
        f"\t{server}:",
        f"\t{client}:",
        *remaps,
        "end",
        "",
        "section: links",
        f"\t{server}:",
        f"\t\t{side} = {client}",
        f"\t{client}:",
        f"\t\t{OPPOSITE[side]} = {server}",
        "end",
        "",
        "section: options",
        *options,
        "end",
    ]
    return "\n".join(lines) + "\n"


def _ini(sections):
    out = []
    for name, values in sections.items():
        out.append(f"[{name}]")
        out += [f"{k}={_ini_value(v)}" for k, v in values.items()]
        out.append("")
    return "\n".join(out)


def _ini_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v).replace("\\", "/")


def _log_level(s):
    level = int(s.get("logLevel", 4))
    if level not in LOG_LEVELS:
        raise ValueError(f"logLevel must be 0-7, got {level}")
    return level


def render_server_settings(s, config_file, log_file, cert_file):
    """Settings for the Deskflow GUI on Windows (server, desktop process mode)."""
    return _ini({
        "core": {"computerName": s["server"]["name"], "port": s["port"], "coreMode": 2, "processMode": 1},
        "server": {"externalConfig": True, "externalConfigFile": config_file},
        "security": {"tlsEnabled": True, "checkPeerFingerprints": True, "certificate": cert_file},
        "log": {"toFile": True, "file": log_file, "level": _log_level(s)},
        "gui": {"startCoreWithGui": True, "autoHide": True, "closeToTray": True, "enableUpdateCheck": False,
                "closeReminder": False, "shownServerFirstStartMessage": True},
    })


def render_client_settings(s, remote_host, log_file):
    """Settings for deskflow-core in client mode on the Mac."""
    return _ini({
        "core": {"computerName": s["client"]["name"], "port": s["port"]},
        "client": {"remoteHost": remote_host, "invertYScroll": bool(s.get("invertScroll", False))},
        "security": {"tlsEnabled": True, "checkPeerFingerprints": True},
        "log": {"toFile": True, "file": log_file, "level": _log_level(s)},
    })


def main(argv):
    root = Path(__file__).resolve().parent.parent
    kind, args = argv[0], dict(a.split("=", 1) for a in argv[1:])
    s = load_settings(args.pop("settings", root / "settings.json"))
    render = {"server-config": render_server_config, "server-settings": render_server_settings,
              "client-settings": render_client_settings}[kind]
    sys.stdout.write(render(s, **args))


if __name__ == "__main__":
    main(sys.argv[1:])
