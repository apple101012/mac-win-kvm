import json
import unittest
from pathlib import Path

from kvmconfig.generate import render_server_config, render_server_settings, render_client_settings, load_settings

ROOT = Path(__file__).resolve().parent.parent


def settings(**overrides):
    s = json.loads((ROOT / "settings.example.json").read_text())
    s.update(overrides)
    return s


class ServerConfigTest(unittest.TestCase):
    def test_repo_settings_render_the_expected_config(self):
        self.assertEqual(
            render_server_config(settings()),
            """section: screens
\tDESKTOP-PC:
\tMacBook:
\t\talt = super
\t\tsuper = alt
end

section: links
\tDESKTOP-PC:
\t\tleft = MacBook
\tMacBook:
\t\tright = DESKTOP-PC
end

section: options
\tclipboardSharing = true
\tswitchCorners = none +top-left +bottom-left
\tswitchCornerSize = 64
\tkeystroke(Super+Escape) = switchToNextScreen
end
""",
        )

    def test_mac_on_the_right_flips_the_links(self):
        out = render_server_config(settings(client={"name": "MacBook", "side": "right"}))
        self.assertIn("\tDESKTOP-PC:\n\t\tright = MacBook\n\tMacBook:\n\t\tleft = DESKTOP-PC\n", out)

    def test_identity_modifier_mappings_are_omitted(self):
        out = render_server_config(settings(macModifiers={"ctrl": "ctrl", "alt": "alt", "super": "super"}))
        self.assertIn("\tMacBook:\nend", out)

    def test_no_dead_corners(self):
        out = render_server_config(settings(switching={"hotkey": "Super+Escape", "deadCorners": [], "cornerSize": 0}))
        self.assertNotIn("switchCorners", out)
        self.assertNotIn("switchCornerSize", out)

    def test_clipboard_off(self):
        self.assertIn("clipboardSharing = false", render_server_config(settings(clipboard=False)))

    def test_rejects_unknown_side(self):
        with self.assertRaises(ValueError):
            render_server_config(settings(client={"name": "MacBook", "side": "diagonal"}))

    def test_rejects_unknown_corner(self):
        with self.assertRaises(ValueError):
            render_server_config(settings(switching={"hotkey": "Super+Escape", "deadCorners": ["middle"], "cornerSize": 5}))

    def test_rejects_unknown_modifier(self):
        with self.assertRaises(ValueError):
            render_server_config(settings(macModifiers={"ctrl": "hyper"}))


class ServerSettingsTest(unittest.TestCase):
    def test_windows_gui_settings(self):
        out = render_server_settings(settings(), config_file="C:/kvm/server.conf", log_file="C:/kvm/server.log",
                                     cert_file="C:/kvm/tls/deskflow.pem")
        for line in [
            "[core]", "computerName=DESKTOP-PC", "port=24800", "coreMode=2", "processMode=1",
            "[server]", "externalConfig=true", "externalConfigFile=C:/kvm/server.conf",
            "[security]", "tlsEnabled=true", "checkPeerFingerprints=true", "certificate=C:/kvm/tls/deskflow.pem",
            "[log]", "toFile=true", "file=C:/kvm/server.log", "level=4",
            "[gui]", "startCoreWithGui=true", "autoHide=true", "closeToTray=true", "enableUpdateCheck=false",
        ]:
            self.assertIn(line + "\n", out)

    def test_backslashes_become_forward_slashes(self):
        out = render_server_settings(settings(), config_file="C:\\kvm\\server.conf", log_file="C:\\kvm\\s.log",
                                     cert_file="C:\\kvm\\c.pem")
        self.assertIn("externalConfigFile=C:/kvm/server.conf\n", out)


class ClientSettingsTest(unittest.TestCase):
    def test_mac_client_settings(self):
        out = render_client_settings(settings(), remote_host="100.64.0.10", log_file="/tmp/c.log")
        for line in [
            "[core]", "computerName=MacBook", "port=24800",
            "[client]", "remoteHost=100.64.0.10", "invertYScroll=false",
            "[security]", "tlsEnabled=true", "checkPeerFingerprints=true",
            "[log]", "toFile=true", "file=/tmp/c.log", "level=4",
        ]:
            self.assertIn(line + "\n", out)

    def test_invert_scroll(self):
        self.assertIn("invertYScroll=true\n", render_client_settings(settings(invertScroll=True), remote_host="h", log_file="l"))


class LoadSettingsTest(unittest.TestCase):
    def test_loads_repo_settings(self):
        self.assertEqual(load_settings(ROOT / "settings.example.json")["server"]["name"], "DESKTOP-PC")


if __name__ == "__main__":
    unittest.main()
