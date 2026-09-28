"""Integration: the real deskflow-core parses our generated server config. Skipped when Deskflow isn't installed."""
import os
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from kvmconfig.generate import load_settings, render_server_config

ROOT = Path(__file__).resolve().parent.parent
CANDIDATES = [
    "/Applications/Deskflow.app/Contents/MacOS/deskflow-core",
    r"C:\Program Files\Deskflow\deskflow-core.exe",
]
CORE = next((p for p in CANDIDATES if os.path.exists(p)), shutil.which("deskflow-core"))


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def run_server(config_text, seconds=4):
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        (d / "server.conf").write_text(config_text)
        log = d / "server.log"
        (d / "settings.conf").write_text(
            f"[core]\nport={free_port()}\ncomputerName=DESKTOP-PC\n"
            "[security]\ntlsEnabled=false\n"
            f"[server]\nexternalConfig=true\nexternalConfigFile={(d / 'server.conf').as_posix()}\n"
            f"[log]\ntoFile=true\nfile={log.as_posix()}\nlevel=4\n"
        )
        proc = subprocess.Popen([CORE, "server", "--new-instance", "-s", str(d / "settings.conf")],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        time.sleep(seconds)
        proc.terminate()
        try:
            out, _ = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, _ = proc.communicate()
        return out + (log.read_text() if log.exists() else "")


@unittest.skipUnless(CORE, "deskflow-core not installed")
class DeskflowAcceptsConfigTest(unittest.TestCase):
    def test_generated_config_is_accepted(self):
        out = run_server(render_server_config(load_settings(ROOT / "settings.example.json")))
        if "failed to initialize screen shape" in out:
            self.skipTest("no usable display (screen locked or headless session)")
        self.assertNotIn("cannot read configuration", out)
        self.assertNotIn("ERROR", out)
        self.assertIn("started server", out)

    def test_broken_config_is_rejected(self):
        # proves the check above can fail
        out = run_server("section: screens\n\tA:\nend\nsection: links\n\tA:\n\t\tleft = NOPE\nend\n")
        self.assertNotIn("started server", out)
        self.assertIn("cannot read configuration", out)


if __name__ == "__main__":
    unittest.main()
