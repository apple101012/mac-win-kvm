import json
import unittest
from pathlib import Path

from kvmlight.tracker import LightingTracker
from kvmlight.driver import OpenRGBDriver

ROOT = Path(__file__).resolve().parent.parent
COLORS = json.loads((ROOT / "settings.example.json").read_text())["lighting"]["colors"]
WHITE, BLUE, RED, PURPLE = COLORS["windows"], COLORS["mac"], COLORS["lockedWindows"], COLORS["lockedMac"]


def tracker():
    return LightingTracker(server="DESKTOP-PC", client="MacBook", colors=COLORS)


def feed(t, *lines):
    """Feed log lines, return the colour changes they caused."""
    return [c for c in (t.feed(line) for line in lines) if c is not None]


STARTED = '[t] IPC: started server, waiting for clients'
CONNECTED = '[t] IPC: client "MacBook" has connected'
DISCONNECTED = '[t] IPC: client "MacBook" has disconnected'
DEAD = '[t] IPC: client "MacBook" is dead'
TO_MAC = '[t] INFO: switch from "DESKTOP-PC" to "MacBook" at 1709,496'
TO_WIN = '[t] INFO: switch from "MacBook" to "DESKTOP-PC" at 15,1215'
JUMP_TO_WIN = '[t] INFO: jump from "MacBook" to "DESKTOP-PC" at 0,0'
LOCK = '[t] NOTE: cursor locked to current screen'
UNLOCK = '[t] NOTE: cursor unlocked from current screen'
LOCKED_AT_START = '[t] NOTE: scroll lock is on, locking cursor to screen'
DUPLICATE = '[t] WARNING: a client with name "MacBook" is already connected'


class TrackerTest(unittest.TestCase):
    def test_starts_white(self):
        self.assertEqual(tracker().color, WHITE)

    def test_switching_to_the_mac_is_blue_and_back_is_white(self):
        t = tracker()
        self.assertEqual(feed(t, STARTED, CONNECTED, TO_MAC, TO_WIN), [BLUE, WHITE])

    def test_lock_on_windows_is_red(self):
        t = tracker()
        self.assertEqual(feed(t, STARTED, CONNECTED, LOCK, UNLOCK), [RED, WHITE])

    def test_lock_on_the_mac_is_purple(self):
        t = tracker()
        self.assertEqual(feed(t, STARTED, CONNECTED, TO_MAC, LOCK, UNLOCK, TO_WIN), [BLUE, PURPLE, BLUE, WHITE])

    def test_lock_without_a_mac_stays_white_until_it_connects(self):
        t = tracker()
        self.assertEqual(feed(t, STARTED, LOCKED_AT_START), [])
        self.assertEqual(feed(t, CONNECTED), [RED])

    def test_mac_disconnecting_while_locked_turns_white(self):
        t = tracker()
        self.assertEqual(feed(t, STARTED, CONNECTED, TO_MAC, LOCK, DISCONNECTED, JUMP_TO_WIN), [BLUE, PURPLE, WHITE])

    def test_mac_dying_turns_white(self):
        t = tracker()
        self.assertEqual(feed(t, STARTED, CONNECTED, TO_MAC, DEAD), [BLUE, WHITE])

    def test_rejected_duplicate_does_not_count_as_the_mac_leaving(self):
        t = tracker()
        feed(t, STARTED, CONNECTED, LOCK)
        self.assertEqual(feed(t, DUPLICATE, '[t] NOTE: disconnecting client "MacBook"', DISCONNECTED), [])
        self.assertEqual(t.color, RED)

    def test_server_restart_resets_to_white(self):
        t = tracker()
        feed(t, STARTED, CONNECTED, TO_MAC)
        self.assertEqual(feed(t, STARTED), [WHITE])

    def test_server_stopped_is_white(self):
        t = tracker()
        feed(t, STARTED, CONNECTED, TO_MAC)
        self.assertEqual(t.server_stopped(), WHITE)
        self.assertIsNone(t.server_stopped())

    def test_unchanged_colour_reports_nothing(self):
        t = tracker()
        feed(t, STARTED, CONNECTED, TO_MAC)
        self.assertEqual(feed(t, TO_MAC, '[t] DEBUG: hiding cursor', ''), [])

    def test_other_client_names_are_ignored(self):
        t = tracker()
        self.assertEqual(feed(t, STARTED, '[t] IPC: client "Other" has connected', '[t] INFO: switch from "DESKTOP-PC" to "Other" at 0,0'), [])

    def test_replaying_the_recorded_session(self):
        t = tracker()
        lines = (ROOT / "fixtures" / "deskflow-1.26.0-server.log").read_text().splitlines()
        changes = feed(t, *lines)
        # connect; to Mac; back; Scroll Lock on Windows; off; to Mac; lock on Mac; unlock; back to Windows
        self.assertEqual(changes[:8], [BLUE, WHITE, RED, WHITE, BLUE, PURPLE, BLUE, WHITE])
        self.assertEqual(t.color, WHITE)


class FakeDevice:
    def __init__(self, name="AULA F87 Pro"):
        self.name = name
        self.calls = []

    def __getattr__(self, name):
        def record(*args, **kwargs):
            self.calls.append(name)
        return record


class FakeClient:
    def __init__(self, devices):
        self.devices = devices


class DriverTest(unittest.TestCase):
    def test_sets_direct_mode_and_colour_without_saving(self):
        dev = FakeDevice()
        d = OpenRGBDriver(connect=lambda: FakeClient([dev]), device_name="AULA F87 Pro")
        d.set_color("FF0000")
        d.set_color("0050FF")
        self.assertEqual(dev.calls, ["set_mode", "set_color", "set_color"])
        self.assertFalse(any("save" in c.lower() for c in dev.calls))


if __name__ == "__main__":
    unittest.main()


class LogFollowerTest(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "server.log"

    def tearDown(self):
        self.dir.cleanup()

    def write(self, text, mode="a"):
        with open(self.path, mode) as f:
            f.write(text)

    def test_replays_existing_lines_then_follows_new_ones(self):
        from kvmlight.helper import LogFollower
        self.write("one\ntwo\n")
        f = LogFollower(self.path)
        self.assertEqual(f.lines(), ["one", "two"])
        self.assertEqual(f.lines(), [])
        self.write("three\n")
        self.assertEqual(f.lines(), ["three"])

    def test_partial_lines_wait_for_their_newline(self):
        from kvmlight.helper import LogFollower
        f = LogFollower(self.path)
        self.write("hal")
        self.assertEqual(f.lines(), [])
        self.write("f\n")
        self.assertEqual(f.lines(), ["half"])

    def test_truncated_file_is_read_from_the_start(self):
        from kvmlight.helper import LogFollower
        self.write("old line that is long\n")
        f = LogFollower(self.path)
        f.lines()
        self.write("new\n", mode="w")
        self.assertEqual(f.lines(), ["new"])

    def test_missing_file_is_fine(self):
        from kvmlight.helper import LogFollower
        self.assertEqual(LogFollower(self.path).lines(), [])
