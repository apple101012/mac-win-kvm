"""Detects input stranded on a Mac that has gone away. Pure; fed Deskflow server log lines.

Deskflow 1.26 can mark the active client dead (e.g. the Mac switched Wi-Fi) without handing input back
to the server, leaving the PC's keyboard and mouse dead until Deskflow restarts. See docs/adr/0002.
"""
from kvmlight.tracker import CLIENT, DUPLICATE, SWITCH


class StrandDetector:
    def __init__(self, server, client, grace=3.0):
        self.server, self.client, self.grace = server, client, grace
        self.active = server
        self.stranded_at = None
        self._rejecting_duplicate = False

    def feed(self, line, now):
        if "IPC: started server" in line:
            self.active, self.stranded_at, self._rejecting_duplicate = self.server, None, False
        elif m := SWITCH.search(line):
            self.active = m.group(1)
            if self.active == self.server:
                self.stranded_at = None
        elif (m := DUPLICATE.search(line)) and m.group(1) == self.client:
            self._rejecting_duplicate = True
        elif (m := CLIENT.search(line)) and m.group(1) == self.client and m.group(2) != "has connected":
            if m.group(2) == "has disconnected" and self._rejecting_duplicate:
                self._rejecting_duplicate = False
            elif self.active == self.client and self.stranded_at is None:
                self.stranded_at = now

    def should_restart(self, now):
        """True once when input has been stuck on a gone Mac for longer than the grace period."""
        if self.stranded_at is not None and now - self.stranded_at >= self.grace:
            self.stranded_at = None
            self.active = self.server
            return True
        return False
