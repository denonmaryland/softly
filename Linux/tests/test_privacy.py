"""Privacy fixes from the marketplace review: rewritten config keeps its
permissions, and copying a dictation never puts the text on a command line.
Run: python3 -m unittest discover Linux/tests"""
import importlib.machinery
import importlib.util
import os
import stat
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.join(HERE, "..", "plugin")
loader = importlib.machinery.SourceFileLoader("softly_control_privacy", os.path.join(PLUGIN, "helpers", "control.py"))
spec = importlib.util.spec_from_loader("softly_control_privacy", loader)
control = importlib.util.module_from_spec(spec)
loader.exec_module(control)


class AtomicWrite(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "hyprland.lua")

    def mode(self):
        return stat.S_IMODE(os.stat(self.path).st_mode)

    def test_private_file_stays_private(self):
        with open(self.path, "w") as f:
            f.write("old\n")
        os.chmod(self.path, 0o600)
        control.atomic_write(self.path, "new\n")
        self.assertEqual(self.mode(), 0o600)
        with open(self.path) as f:
            self.assertEqual(f.read(), "new\n")

    def test_new_file_uses_requested_mode(self):
        control.atomic_write(self.path, "x\n")
        self.assertEqual(self.mode(), 0o644)

    def test_no_temporary_files_left(self):
        control.atomic_write(self.path, "x\n")
        self.assertEqual(os.listdir(self.dir.name), ["hyprland.lua"])


class CopyText(unittest.TestCase):
    def test_copy_does_not_pass_text_in_argv(self):
        with open(os.path.join(PLUGIN, "Panel.qml")) as f:
            qml = f.read()
        self.assertNotIn('execDetached(["wl-copy"', qml)
        self.assertIn('command: ["wl-copy"]', qml)
        self.assertIn("stdinEnabled: true", qml)


if __name__ == "__main__":
    unittest.main()
