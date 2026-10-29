"""Tests for the iOS 15 availability inventory script.

The fixtures are strings, not files: the gate logic is pure text analysis, so
these tests run anywhere without a Swift toolchain or temporary directories.
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "check_ios15_availability.py"


def load_script():
    spec = importlib.util.spec_from_file_location("check_ios15_availability", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    # dataclasses resolves annotations through sys.modules; register first.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class InventoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.script = load_script()

    def findings(self, text: str):
        return self.script.findings_in_text("App/View.swift", text)

    def test_detects_glass_use_and_skips_comments(self) -> None:
        findings = self.findings("\n".join([
            "// glassEffect is not called here",
            "content.glassEffect(.regular)",
            "",
        ]))
        self.assertEqual(["glass"], [finding["rule"] for finding in findings])
        self.assertEqual(2, findings[0]["line"])

    def test_rule_names_are_stable_and_documented(self) -> None:
        rules = {rule.name: rule for rule in self.script.RULES}
        self.assertEqual("26.0", rules["glass"].minimum)
        self.assertEqual("17.0", rules["observation"].minimum)
        self.assertEqual("18.0", rules["textual"].minimum)
        self.assertTrue(all(rule.note for rule in rules.values()))

    def test_observation_and_import_are_separate_rules(self) -> None:
        tally = self.script.counts(self.findings(
            "import Observation\n@Observable final class Model {}\n@ObservationIgnored var x = 0\n"
        ))
        self.assertEqual({"observation": 2, "observation-import": 1}, tally)

    def test_counting_ignores_blank_and_comment_only_lines(self) -> None:
        self.assertEqual({}, self.script.counts(self.findings("// NavigationStack\n\n   \n")))

    def test_regressions_only_reports_growth(self) -> None:
        tally = {"glass": 2, "navigation-stack": 1}
        self.assertEqual({"glass": (1, 2)}, self.script.regressions(tally, {"glass": 1, "navigation-stack": 1}))
        self.assertEqual({}, self.script.regressions({"glass": 1}, {"glass": 1}))
        self.assertEqual({}, self.script.regressions({}, {}))

    def test_missing_baseline_reads_as_empty(self) -> None:
        missing = Path("does-not-exist-ios15-baseline.json")
        self.assertFalse(missing.exists())
        self.assertEqual({}, self.script.load_baseline(missing))

    def test_missing_source_directory_is_an_error(self) -> None:
        with self.assertRaises(SystemExit):
            self.script.main(["--source", "definitely-missing-directory", "--check"])


if __name__ == "__main__":
    unittest.main()
