"""Direct USB control of Sinowealth 258A:010C keyboards (AULA F87 Pro and friends), no OpenRGB needed.

Protocol from OpenRGB's SinowealthKeyboard10cController: a 520-byte HID feature report on interface 1
(usage page 0xFF00). The keyboard falls back to its own effect unless frames keep coming, so callers
re-send about twice a second. Only "stream LEDs" frames are sent; nothing is written to the keyboard's flash.
"""

VID, PID = 0x258A, 0x010C
FRAME_SIZE = 520
LED_SLOTS = 170                      # (520 - 8) // 3; unused slots are ignored by the keyboard
PROBE = bytes([0x06, 0x82, 0x01, 0x00, 0x01, 0x00, 0x06]) + bytes(FRAME_SIZE - 7)
SUPPORTED_MODELS = {0x0B: "AULA F87 Pro"}


def frame(hex_color):
    rgb = bytes(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))
    return bytes([0x06, 0x08, 0x00, 0x00, 0x01, 0x00, 0x7A, 0x01]) + rgb * LED_SLOTS + bytes(FRAME_SIZE - 8 - 3 * LED_SLOTS)


def model_id(reply):
    return reply[13] if len(reply) > 13 else None


class SinowealthKeyboard:
    """Finds the keyboard's lighting channel and sends frames. Reopens by itself after a USB reconnect."""

    def __init__(self, hid_module=None):
        self._hid = hid_module
        self._dev = None
        self.model = None

    def _open(self):
        hid = self._hid or __import__("hid")
        for info in hid.enumerate(VID, PID):
            if info.get("interface_number") != 1 or info.get("usage_page") != 0xFF00:
                continue
            dev = hid.device()
            try:
                dev.open_path(info["path"])
                dev.send_feature_report(PROBE)
                model = model_id(dev.get_feature_report(0x06, FRAME_SIZE))
                if model is not None:
                    self._dev, self.model = dev, model
                    return
            except OSError:
                pass
            dev.close()
        raise LookupError("keyboard lighting channel not found (is the keyboard plugged in by USB?)")

    def send(self, hex_color):
        if self._dev is None:
            self._open()
        try:
            self._dev.send_feature_report(frame(hex_color))
        except OSError:
            self.close()
            raise

    def close(self):
        if self._dev is not None:
            try:
                self._dev.close()
            except OSError:
                pass
        self._dev = None
