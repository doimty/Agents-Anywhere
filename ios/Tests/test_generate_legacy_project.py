"""Regression tests for the generated iOS 15 project.

The project file is generated, so the checks are: every source is listed, no
excluded file leaks in, the deployment floor stays 15.0, strings are quoted (a
bare "+" in a file name made Xcode refuse to open the project once), and the
checked-in project matches the generator.
"""

from __future__ import annotations

import importlib.util
import re
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "generate_legacy_project.py"


def load_generator():
    spec = importlib.util.spec_from_file_location("generate_legacy_project", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class LegacyProjectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.generator = load_generator()
        self.project = self.generator.generate()
        self.scheme = self.generator.scheme()

    def test_every_legacy_source_is_linked(self) -> None:
        for path in self.generator.legacy_sources():
            self.assertIn(f'name = "{path.name}"', self.project, path.name)

    def test_shared_sources_are_linked_with_relative_paths(self) -> None:
        for path in self.generator.shared_sources():
            relative = path.relative_to(self.generator.IOS_ROOT).as_posix()
            self.assertIn(f'"../{relative}"', self.project, relative)

    def test_excluded_shared_files_never_leak(self) -> None:
        for excluded in self.generator.SHARED_EXCLUDED:
            self.assertNotIn(excluded, self.project, excluded)

    def test_deployment_floor_is_ios_15(self) -> None:
        self.assertIn("IPHONEOS_DEPLOYMENT_TARGET = 15.0;", self.project)
        self.assertNotIn("26.5", self.project)

    def test_file_names_are_quoted(self) -> None:
        # Xcode refused to read the project when "V2ConnectorAPI+Download.swift"
        # appeared unquoted. Bare tokens are only safe for simple words.
        for match in re.finditer(r'^\s*(?:name|path) = ([^;]+);$', self.project, re.MULTILINE):
            value = match.group(1).strip()
            quoted = value.startswith('"') and value.endswith('"')
            simple = re.fullmatch(r"[A-Za-z0-9_.-]+", value) is not None
            self.assertTrue(quoted or simple, value)

    def test_scheme_points_at_the_generated_target(self) -> None:
        target = self.generator.identifier("target")
        self.assertIn(f'BlueprintIdentifier = "{target}"', self.scheme)
        self.assertIn('BuildableName = "AgentsAnywhereLegacy.app"', self.scheme)

    def test_checked_in_project_matches_the_generator(self) -> None:
        project_file = self.generator.PROJECT_FILE
        self.assertTrue(project_file.exists(), project_file)
        self.assertEqual(
            project_file.read_text(encoding="utf-8").replace("\r\n", "\n"),
            self.project,
            "run python3 ios/scripts/generate_legacy_project.py",
        )

    def test_checked_in_scheme_matches_the_generator(self) -> None:
        scheme_file = self.generator.SCHEME_FILE
        self.assertTrue(scheme_file.exists(), scheme_file)
        self.assertEqual(
            scheme_file.read_text(encoding="utf-8").replace("\r\n", "\n"),
            self.scheme,
        )


if __name__ == "__main__":
    unittest.main()
