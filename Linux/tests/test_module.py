"""The Hyprland module helpers/control.py writes to ~/.config/hypr/softly.lua.
Rendering only reads hypr/module.lua; nothing here touches the live config.
Run: python3 -m unittest discover Linux/tests"""
import importlib.machinery
import importlib.util
import os
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("softly_control", os.path.join(HERE, "..", "plugin", "helpers", "control.py"))
spec = importlib.util.spec_from_loader("softly_control", loader)
control = importlib.util.module_from_spec(spec)
loader.exec_module(control)

PRESS = 'o.bind("Alt_R", "Softly: tap or hold to dictate", "omarchy-shell io.github.denonmaryland.softly press")'
RELEASE = 'o.bind("ALT + Alt_R", "Softly: release", "omarchy-shell io.github.denonmaryland.softly release", { release = true })'


def code(text):
    """The Lua lines that do something, comments and blanks dropped."""
    out = []
    for line in text.splitlines():
        line = line.split("  --", 1)[0].strip()
        if line and not line.startswith("--"):
            out.append(line)
    return out


class SoftlyModeTests(unittest.TestCase):
    def test_takes_omarchy_45_keys_back_before_its_own_binds(self):
        lines = code(control.render_module("Alt_R", "softly"))
        self.assertEqual(lines[:4], ["if o.dictation_installed then", 'hl.unbind("ALT + SPACE")', 'hl.unbind("ALT + Alt_R")', "end"])
        self.assertEqual(lines[4:6], [PRESS, RELEASE])

    def test_header_records_key_and_mode(self):
        text = control.render_module("Alt_R", "softly")
        self.assertTrue(text.startswith("-- softly-hotkey: Alt_R\n-- softly-mode: softly\n"))
        self.assertNotIn("@", text.split("local softly_esc")[0])

    def test_omarchy_dictation_keys_on_softlys_key_are_unbound(self):
        self.assertIn('hl.unbind("F9")', code(control.render_module("F9", "softly")))
        self.assertIn('hl.unbind("SUPER + CTRL + X")', code(control.render_module("CTRL + SUPER + X", "softly")))
        self.assertNotIn('hl.unbind("F9")', code(control.render_module("Alt_R", "softly")))


class OmarchyModeTests(unittest.TestCase):
    def test_binds_nothing_where_omarchy_has_dictation_keys(self):
        lines = code(control.render_module("Alt_R", "omarchy"))
        self.assertEqual(lines[:4], ["if not o.dictation_installed then", PRESS, RELEASE, "end"])
        self.assertFalse(any("unbind(\"ALT" in l for l in lines))

    def test_esc_cancel_stays(self):
        self.assertIn("softly_esc", control.render_module("Alt_R", "omarchy"))


class KeyTests(unittest.TestCase):
    def test_release_keys_add_the_modifier_a_lone_modifier_key_holds(self):
        self.assertEqual(control.release_keys("Alt_R"), "ALT + Alt_R")
        self.assertEqual(control.release_keys("F9"), "F9")

    def test_key_identity_ignores_order_case_and_control_spelling(self):
        self.assertEqual(control.key_id("control + super + x"), control.key_id("SUPER + CTRL + X"))
        self.assertNotEqual(control.key_id("SUPER + X"), control.key_id("SUPER + CTRL + X"))


if __name__ == "__main__":
    unittest.main()
