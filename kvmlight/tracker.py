"""Deskflow server log lines -> keyboard colour. Pure; see docs/adr/0001 for the line formats."""
import re

SWITCH = re.compile(r'(?:switch|jump) from "[^"]*" to "([^"]*)"')
CLIENT = re.compile(r'IPC: client "([^"]*)" (has connected|has disconnected|is dead)')
DUPLICATE = re.compile(r'a client with name "([^"]*)" is already connected')


class LightingTracker:
    def __init__(self, server, client, colors):
        self.server, self.client, self.colors = server, client, colors
        self._reset()
        self._shown = self.color

    def _reset(self):
        self.active = self.server
        self.locked = False
        self.connected = False
        self._rejecting_duplicate = False

    @property
    def color(self):
        on_mac = self.connected and self.active == self.client
        if not self.connected:
            return self.colors["windows"]
        if self.locked:
            return self.colors["lockedMac" if on_mac else "lockedWindows"]
        return self.colors["mac" if on_mac else "windows"]

    def feed(self, line):
        """Returns the new colour if this line changed it, else None."""
        if "IPC: started server" in line:
            self._reset()
        elif m := SWITCH.search(line):
            self.active = m.group(1)
        elif "cursor locked to current screen" in line or "locking cursor to screen" in line:
            self.locked = True
        elif "cursor unlocked from current screen" in line:
            self.locked = False
        elif (m := DUPLICATE.search(line)) and m.group(1) == self.client:
            self._rejecting_duplicate = True
        elif (m := CLIENT.search(line)) and m.group(1) == self.client:
            if m.group(2) == "has connected":
                self.connected = True
            elif m.group(2) == "has disconnected" and self._rejecting_duplicate:
                self._rejecting_duplicate = False   # the rejected newcomer left; the real Mac is still there
            else:
                self.connected = False
                self.active = self.server
        return self._changed()

    def server_stopped(self):
        self._reset()
        return self._changed()

    def _changed(self):
        c = self.color
        if c == self._shown:
            return None
        self._shown = c
        return c
