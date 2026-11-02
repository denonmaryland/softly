"""Same cases as ReplacementTests in Tests/DictationCoreTests and
Windows/Softly.Core.Tests. Run: python3 -m unittest discover Linux/tests"""
import importlib.machinery
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("softly_fix", os.path.join(HERE, "..", "plugin", "bin", "softly-fix"))
spec = importlib.util.spec_from_loader("softly_fix", loader)
fix = importlib.util.module_from_spec(spec)
loader.exec_module(fix)

RULES = [("cloud code", "Claude Code"), ("cloud", "Claude"), ("get hub", "GitHub"),
         ("omarch", "Omarchy"), ("um", ""), ("uh", "")]


def apply(text):
    return fix.apply(text, RULES)


class ReplacementTests(unittest.TestCase):
    def test_phrases_ignore_case_and_prefer_the_longest_rule(self):
        self.assertEqual(apply("Open cloud code and push to Get Hub."), "Open Claude Code and push to GitHub.")
        self.assertEqual(apply("Ask cloud."), "Ask Claude.")
        self.assertEqual(apply("Cloud-code"), "Claude Code")
        self.assertEqual(apply("cloud   code"), "Claude Code")

    def test_only_whole_words_match(self):
        self.assertEqual(apply("Omarch runs on omarchy."), "Omarchy runs on omarchy.")
        self.assertEqual(apply("Cloudy and humid."), "Cloudy and humid.")

    def test_replacements_are_not_replaced_again(self):
        self.assertEqual(fix.apply("a b", [("a", "b"), ("b", "a")]), "b a")

    def test_empty_target_deletes_and_tidies(self):
        self.assertEqual(apply("So, um, I think it, uh, works."), "So, I think it, works.")
        self.assertEqual(apply("Um, I think so."), "I think so.")
        self.assertEqual(apply("Yes um."), "Yes.")
        self.assertEqual(apply("Um."), "")
        self.assertEqual(apply("Push it to get hub. Um, I think it works."), "Push it to GitHub. I think it works.")
        self.assertEqual(apply("Done. Uh, so we ship."), "Done. So we ship.")

    def test_no_rules_leaves_text_alone(self):
        self.assertEqual(fix.apply("  Untouched ,  text ", []), "  Untouched ,  text ")
        self.assertEqual(fix.apply("Fine", [("  ", "x")]), "Fine")



class SubmitWordTests(unittest.TestCase):
    def test_trailing_submit_is_stripped(self):
        self.assertEqual(fix.split_submit("Fix the failing test, submit."), ("Fix the failing test", True))
        self.assertEqual(fix.split_submit("Run it. Submit!"), ("Run it", True))
        self.assertEqual(fix.split_submit("Submit."), ("", True))

    def test_other_submits_are_kept(self):
        self.assertEqual(fix.split_submit("Please resubmit"), ("Please resubmit", False))
        self.assertEqual(fix.split_submit("Submit the form tomorrow."), ("Submit the form tomorrow.", False))


if __name__ == "__main__":
    unittest.main()
