import unittest
from pathlib import Path

from kvmlight.strand import StrandDetector

ROOT = Path(__file__).resolve().parent.parent
TO_MAC = '[t] INFO: switch from "DESKTOP-PC" to "MacBook" at 1709,268'
TO_WIN = '[t] INFO: switch from "MacBook" to "DESKTOP-PC" at 1,347'
JUMP_TO_WIN = '[t] INFO: jump from "MacBook" to "DESKTOP-PC" at 0,0'
DEAD = '[t] IPC: client "MacBook" is dead'
DISCONNECTED = '[t] IPC: client "MacBook" has disconnected'
DUPLICATE = '[t] WARNING: a client with name "MacBook" is already connected'
STARTED = '[t] IPC: started server, waiting for clients'


def detector():
    return StrandDetector(server="DESKTOP-PC", client="MacBook", grace=3.0)


class StrandDetectorTest(unittest.TestCase):
    def test_mac_dying_while_it_has_the_cursor_strands_input_after_the_grace_period(self):
        d = detector()
        d.feed(TO_MAC, now=0)
        d.feed(DEAD, now=1)
        self.assertFalse(d.should_restart(now=3.9))
        self.assertTrue(d.should_restart(now=4.0))

    def test_only_fires_once(self):
        d = detector()
        d.feed(TO_MAC, now=0); d.feed(DEAD, now=1)
        self.assertTrue(d.should_restart(now=5))
        self.assertFalse(d.should_restart(now=6))

    def test_deskflow_handing_input_back_cancels_it(self):
        d = detector()
        d.feed(TO_MAC, now=0); d.feed(DEAD, now=1); d.feed(JUMP_TO_WIN, now=1.2)
        self.assertFalse(d.should_restart(now=10))

    def test_mac_leaving_while_the_cursor_is_on_windows_is_fine(self):
        d = detector()
        d.feed(TO_MAC, now=0); d.feed(TO_WIN, now=1); d.feed(DEAD, now=2)
        self.assertFalse(d.should_restart(now=10))

    def test_disconnect_counts_too(self):
        d = detector()
        d.feed(TO_MAC, now=0); d.feed(DISCONNECTED, now=1)
        self.assertTrue(d.should_restart(now=5))

    def test_rejected_duplicate_is_not_the_real_mac_leaving(self):
        d = detector()
        d.feed(TO_MAC, now=0); d.feed(DUPLICATE, now=1); d.feed(DISCONNECTED, now=1)
        self.assertFalse(d.should_restart(now=10))

    def test_server_restart_clears_it(self):
        d = detector()
        d.feed(TO_MAC, now=0); d.feed(DEAD, now=1); d.feed(STARTED, now=2)
        self.assertFalse(d.should_restart(now=10))

    def test_replaying_the_real_incident_triggers_a_restart(self):
        # Real recording: Wi-Fi switched while the cursor was on the Mac; Deskflow marked it dead but kept input there
        d = detector()
        for i, line in enumerate((ROOT / "fixtures" / "deskflow-1.26.0-stranded.log").read_text().splitlines()):
            d.feed(line, now=i * 0.01)
        self.assertTrue(d.should_restart(now=100))


if __name__ == "__main__":
    unittest.main()
