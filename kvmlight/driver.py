"""Sets the keyboard to one solid colour through the OpenRGB SDK server.

Only Direct mode + set_color: streamed to the keyboard, never saved to its flash
(OpenRGB's SinowealthKeyboard10c controller has no save path; OpenRGB re-sends the frame every second).
"""


class OpenRGBDriver:
    """Finds the keyboard by name in OpenRGB's *current* device list on every change.

    OpenRGB drops a keyboard after a USB reconnect and the remaining devices shift up, so a cached device
    would silently point at something else (e.g. the motherboard). Raises LookupError when it's missing.
    """

    def __init__(self, connect, device_name):
        self._connect = connect          # () -> openrgb.OpenRGBClient-like object with .devices and .update()
        self._device_name = device_name
        self._client = None
        self._device = None

    def _current_device(self):
        if self._client is None:
            self._client = self._connect()
        else:
            self._client.update()        # refresh the device list from the server
        matches = [d for d in self._client.devices if d.name == self._device_name]
        if not matches:
            self._device = None
            raise LookupError(f"OpenRGB does not see {self._device_name!r}")
        if matches[0] is not self._device:
            self._device = matches[0]
            self._device.set_mode("direct")
        return self._device

    def set_color(self, hex_color):
        rgb = _rgb(hex_color)
        try:
            self._current_device().set_color(rgb, fast=True)
        except LookupError:
            raise
        except Exception:
            self._client = self._device = None   # reconnect next time (OpenRGB restarted)
            raise


def _rgb(hex_color):
    try:
        from openrgb.utils import RGBColor
    except ImportError:          # tests run without the openrgb package
        return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))
    return RGBColor.fromHEX(hex_color)
