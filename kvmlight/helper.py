"""Keyboard lighting helper (Windows). Follows the Deskflow server log and recolours the keyboard.

Usage: pythonw -m kvmlight.helper <deskflow server log>
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from kvmlight.driver import OpenRGBDriver
from kvmlight.tracker import LightingTracker

ROOT = Path(__file__).resolve().parent.parent
REPLAY_BYTES = 5 * 1024 * 1024
POLL = 0.1


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


def main(log_path):
    settings = json.loads((ROOT / "settings.json").read_text())
    lighting = settings["lighting"]
    tracker = LightingTracker(settings["server"]["name"], settings["client"]["name"], lighting["colors"])

    def connect():
        from openrgb import OpenRGBClient
        return OpenRGBClient("127.0.0.1", 6742, name="macwinkvm")

    driver = OpenRGBDriver(connect, lighting["keyboard"])
    follower = LogFollower(log_path)
    wanted, shown = tracker.color, None
    last_process_check = 0.0

    while True:
        for line in follower.lines():
            if (c := tracker.feed(line)) is not None:
                wanted = c
        if time.monotonic() - last_process_check > 2:
            last_process_check = time.monotonic()
            if not deskflow_running() and (c := tracker.server_stopped()) is not None:
                wanted = c
        if wanted != shown:
            try:
                driver.set_color(wanted)
                shown = wanted
                print(f"{time.strftime('%H:%M:%S')} colour {wanted}", flush=True)
            except Exception as e:   # OpenRGB not up yet / keyboard unplugged: retry shortly
                print(f"{time.strftime('%H:%M:%S')} OpenRGB: {e}", flush=True)
                time.sleep(2)
        time.sleep(POLL)


if __name__ == "__main__":
    if sys.stdout is None:   # pythonw: no console, log to a file instead
        sys.stdout = sys.stderr = open(os.path.expandvars(r"%LOCALAPPDATA%\macwinkvm\lighting.log"), "a", buffering=1)
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.expandvars(r"%LOCALAPPDATA%\macwinkvm\server.log"))
