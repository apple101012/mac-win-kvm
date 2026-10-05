"""Background helper (Windows). Follows the Deskflow server log to:
- restart Deskflow if input gets stuck on a Mac that went away (watchdog, always on), and
- recolour the keyboard over USB to show the active machine (only if lighting is enabled).

Usage: pythonw -m kvmlight.helper <deskflow server log>
"""
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

from kvmlight.sinowealth import SinowealthKeyboard
from kvmlight.strand import StrandDetector
from kvmlight.tracker import LightingTracker

ROOT = Path(__file__).resolve().parent.parent
REPLAY_BYTES = 5 * 1024 * 1024
POLL = 0.1
DESKFLOW_GUI = r"C:\Program Files\Deskflow\deskflow.exe"
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
DETACHED = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)


def restart_deskflow():
    """Kill and relaunch the Deskflow GUI (which starts the server); this hands input back to Windows."""
    subprocess.run(["taskkill", "/F", "/IM", "deskflow.exe", "/IM", "deskflow-core.exe"], capture_output=True,
                   creationflags=NO_WINDOW)
    time.sleep(1)
    subprocess.Popen([DESKFLOW_GUI], cwd=os.path.dirname(DESKFLOW_GUI), creationflags=DETACHED, close_fds=True)


def deskflow_running():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq deskflow-core.exe", "/NH"], capture_output=True, text=True,
                         creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).stdout
    return "deskflow-core.exe" in out


class LogFollower:
    """Yields complete new lines; survives the file being truncated or recreated."""

    def __init__(self, path):
        self.path, self.pos, self.partial = Path(path), 0, ""
        if self.path.exists():
            self.pos = max(0, self.path.stat().st_size - REPLAY_BYTES)   # replay recent history to recover state

    def lines(self):
        try:
            size = self.path.stat().st_size
        except FileNotFoundError:
            return []
        if size < self.pos:
            self.pos, self.partial = 0, ""
        if size == self.pos:
            return []
        with open(self.path, "r", encoding="utf-8", errors="replace") as f:
            f.seek(self.pos)
            data = f.read()
            self.pos = f.tell()
        data = self.partial + data
        *complete, self.partial = data.split("\n")
        return complete


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", flush=True)


class LightingWorker(threading.Thread):
    """Streams the wanted colour to the keyboard: immediately on change, and every KEEPALIVE seconds otherwise
    (the keyboard drops out of direct mode without a steady stream). Never blocks the watchdog."""

    KEEPALIVE = 0.4
    RETRY = 3

    def __init__(self, keyboard):
        super().__init__(daemon=True)
        self.keyboard = keyboard
        self.wanted, self.shown, self.failing = None, None, False
        self.changed = threading.Event()

    def want(self, color):
        self.wanted = color
        self.changed.set()

    def run(self):
        while True:
            self.changed.wait(timeout=self.RETRY if self.failing else self.KEEPALIVE)
            self.changed.clear()
            color = self.wanted
            if color is None:
                continue
            try:
                self.keyboard.send(color)
                if self.failing:
                    log("keyboard lighting back")
                self.failing = False
                if color != self.shown:
                    self.shown = color
                    log(f"colour {color}")
            except (OSError, LookupError) as e:
                if not self.failing:
                    log(f"keyboard: {e}")
                self.failing, self.shown = True, None


def main(log_path):
    settings = json.loads((ROOT / "settings.json").read_text())
    server, client = settings["server"]["name"], settings["client"]["name"]
    lighting_cfg = settings.get("lighting", {})
    tracker = LightingTracker(server, client, lighting_cfg.get("colors") or {k: "FFFFFF" for k in ("windows", "mac", "lockedWindows", "lockedMac")})
    strand = StrandDetector(server, client)

    lighting = None
    if lighting_cfg.get("enabled"):
        lighting = LightingWorker(SinowealthKeyboard())
        lighting.start()
        lighting.want(tracker.color)

    follower = LogFollower(log_path)
    last_process_check = 0.0
    replaying = True

    while True:
        now = time.monotonic()
        for line in follower.lines():
            if (c := tracker.feed(line)) is not None and lighting:
                lighting.want(c)
            strand.feed(line, now)
        if replaying:   # old history on startup: recover the colour, but never act on a past strand
            strand.stranded_at, replaying = None, False
        if strand.should_restart(now):
            log("watchdog: input stuck on the gone Mac, restarting Deskflow")
            restart_deskflow()
        if now - last_process_check > 2:
            last_process_check = now
            if not deskflow_running() and (c := tracker.server_stopped()) is not None and lighting:
                lighting.want(c)
        time.sleep(POLL)


if __name__ == "__main__":
    if sys.stdout is None:   # pythonw: no console, log to a file instead
        sys.stdout = sys.stderr = open(os.path.expandvars(r"%LOCALAPPDATA%\macwinkvm\helper.log"), "a", buffering=1)
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.expandvars(r"%LOCALAPPDATA%\macwinkvm\server.log"))
