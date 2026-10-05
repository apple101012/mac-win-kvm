import unittest

from kvmlight.sinowealth import FRAME_SIZE, frame, model_id


class FrameTest(unittest.TestCase):
    def test_direct_mode_header(self):
        f = frame("FF0000")
        self.assertEqual(len(f), FRAME_SIZE)
        self.assertEqual(f[:8], bytes([0x06, 0x08, 0x00, 0x00, 0x01, 0x00, 0x7A, 0x01]))

    def test_every_led_slot_gets_the_colour(self):
        f = frame("0050FF")
        self.assertEqual(f[8:11], bytes([0x00, 0x50, 0xFF]))
        self.assertEqual(f[8 + 3 * 169:8 + 3 * 170], bytes([0x00, 0x50, 0xFF]))
        self.assertEqual(f[8 + 3 * 170:], bytes(FRAME_SIZE - 8 - 3 * 170))

    def test_only_ever_a_direct_frame(self):
        # 0x06 0x08 = stream LEDs (OpenRGB's SetLEDsDirect). Nothing that writes settings to flash.
        for color in ("FFFFFF", "000000", "8000FF"):
            self.assertEqual(frame(color)[:2], b"\x06\x08")


class ModelIdTest(unittest.TestCase):
    def test_reads_the_model_byte_from_the_probe_reply(self):
        self.assertEqual(model_id(bytes(13) + b"\x0B"), 0x0B)

    def test_short_reply_is_not_a_keyboard(self):
        self.assertIsNone(model_id(bytes(5)))


if __name__ == "__main__":
    unittest.main()
