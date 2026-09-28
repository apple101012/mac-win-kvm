"""Sets the keyboard to one solid colour through the OpenRGB SDK server.

Only Direct mode + set_color: streamed to the keyboard, never saved to its flash
(OpenRGB's SinowealthKeyboard10c controller has no save path; OpenRGB re-sends the frame every second).
"""


class OpenRGBDriver:
    def __init__(self, connect, device_name):
        self._connect = connect          # () -> openrgb.OpenRGBClient-like object with .devices
        self._device_name = device_name
        self._device = None

    def _get_device(self):
        if self._device is None:
            client = self._connect()
            matches = [d for d in client.devices if d.name == self._device_name]
            if not matches:
                raise LookupError(f"OpenRGB does not see {self._device_name!r}")
            self._device = matches[0]
            self._device.set_mode("direct")
        return self._device

    def set_color(self, hex_color):
        rgb = _rgb(hex_color)
        try:
            self._get_device().set_color(rgb, fast=True)
        except Exception:
            self._device = None   # reconnect next time (OpenRGB restarted, keyboard replugged)
            raise


def _rgb(hex_color):
    try:
        from openrgb.utils import RGBColor
    except ImportError:          # tests run without the openrgb package
        return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))
    return RGBColor.fromHEX(hex_color)
