import time
import unittest

from kvmlight.helper import LightingWorker


class FakeKeyboard:
    def __init__(self):
        self.sent, self.unplugged = [], False

    def send(self, color):
        if self.unplugged:
            raise OSError("device disconnected")
        self.sent.append((time.monotonic(), color))


def worker(kbd):
    w = LightingWorker(kbd)
    w.KEEPALIVE, w.RETRY = 0.05, 0.05
    w.start()
    return w


class LightingWorkerTest(unittest.TestCase):
    def test_a_change_is_sent_straight_away(self):
        kbd = FakeKeyboard(); w = worker(kbd)
        t = time.monotonic(); w.want("0050FF"); time.sleep(0.02)
        self.assertTrue(kbd.sent and kbd.sent[0][1] == "0050FF" and kbd.sent[0][0] - t < 0.02)

    def test_keeps_streaming_so_the_keyboard_stays_in_direct_mode(self):
        kbd = FakeKeyboard(); w = worker(kbd)
        w.want("FFFFFF"); time.sleep(0.3)
        self.assertGreaterEqual(len(kbd.sent), 4)

    def test_recovers_after_the_keyboard_is_unplugged(self):
        kbd = FakeKeyboard(); w = worker(kbd)
        kbd.unplugged = True; w.want("FF0000"); time.sleep(0.15)
        self.assertEqual(kbd.sent, [])
        kbd.unplugged = False; time.sleep(0.15)
        self.assertEqual(kbd.sent[-1][1], "FF0000")


if __name__ == "__main__":
    unittest.main()
