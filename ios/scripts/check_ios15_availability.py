#!/usr/bin/env python3
"""Inventory of SwiftUI/UIKit calls that cannot run on iOS 15.

This is a *source inventory*, not a compiler. It deliberately does not try to
evaluate `#available` scopes: any availability branch is still reported so the
count cannot silently hide a call that was moved outside its guard. The gate is
therefore a baseline diff: `--check` fails only when a rule is used more often
than the reviewed baseline, which catches new unguarded usage without claiming
that the remaining calls are safe.

Usage:
    python3 ios/scripts/check_ios15_availability.py --report
    python3 ios/scripts/check_ios15_availability.py --check
    python3 ios/scripts/check_ios15_availability.py --check --update-baseline
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = REPO_ROOT / "ios" / "Agents Anywhere" / "Agents Anywhere"
DEFAULT_BASELINE = REPO_ROOT / "ios" / "ios15-availability-baseline.json"
# Adapters intentionally name the newer API behind an explicit availability
# branch; their call sites are what this inventory measures.
SKIP_DIRECTORIES = {"Compatibility", "_deprecated", "Tests"}


@dataclass(frozen=True)
class Rule:
    name: str
    pattern: re.Pattern[str]
    minimum: str
    note: str


def _rule(name: str, regex: str, minimum: str, note: str) -> Rule:
    return Rule(name, re.compile(regex), minimum, note)


RULES = (
    _rule("observation", r"(?<![\w.])(@Observable|@ObservationIgnored|@Bindable)\b", "17.0",
          "Observation replaces Update on iOS 15"),
    _rule("observation-import", r"^\s*import Observation\b", "17.0",
          "Observation module is absent on iOS 15"),
    _rule("entry-macro", r"@Entry\b", "18.0", "Environment macro; replace with explicit EnvironmentKey"),
    _rule("navigation-stack", r"(?<![\w.])(NavigationStack|NavigationSplitView|NavigationPath|navigationDestination)\b", "16.0",
          "Use NavigationView/adapter on iOS 15"),
    _rule("photos-picker", r"PhotosPicker|PhotosPickerItem", "16.0", "Use PHPickerViewController"),
    _rule("presentation-detents", r"presentationDetents|presentationContentInteraction|presentationDragIndicator", "16.0",
          "Standard sheet on iOS 15"),
    _rule("label-content", r"(?<![\w.])LabeledContent\b", "16.0", "Render a labelled row manually"),
    _rule("content-unavailable", r"(?<![\w.])ContentUnavailableView\b", "17.0", "Provide an empty-state view"),
    _rule("glass", r"glassEffect|\.glassProminent|buttonStyle\(\.glass\)|GlassEffectContainer|glassEffectID", "26.0",
          "Use the material fallback"),
    _rule("scroll-edge-effect", r"scrollEdgeEffectStyle|ScrollEdgeEffectStyle|safeAreaBar|ConcentricRectangle", "26.0",
          "Use appScrollEdgeEffect/appSafeAreaBar"),
    _rule("scroll-position", r"ScrollPosition|onScrollGeometryChange|ScrollGeometry|onScrollPhaseChange|defaultScrollAnchor", "18.0",
          "Manual geometry tracking required"),
    _rule("geometry-change", r"onGeometryChange|onScrollVisibilityChange|scrollTargetLayout|scrollTargetBehavior|scrollPosition\(", "17.0",
          "Use GeometryReader/PreferenceKey"),
    _rule("sensory-feedback", r"\.sensoryFeedback|SensoryFeedback", "17.0", "Use UIFeedbackGenerator"),
    _rule("symbol-effects", r"symbolEffect|contentTransition\(|TextRenderer|TextAttribute|Text\.Layout", "17.0",
          "Static glyphs on iOS 15"),
    _rule("smooth-animation", r"\.smooth\(|\.snappy\(|\.bouncy\(|completionCriteria:", "17.0",
          "Use easeInOut/spring with UIKit completion"),
    _rule("toolbar-new", r"toolbar\(removing:|toolbarBackground|toolbar\(\.hidden, for:", "16.0",
          "Navigation bar APIs differ on iOS 15"),
    _rule("scroll-modifiers", r"scrollDismissesKeyboard|scrollIndicators\(|scrollBounceBehavior", "16.0",
          "No-op fallback keeps system default"),
    _rule("scroll-padding", r"scrollClipDisabled|contentMargins", "17.0", "Not available"),
    _rule("textual", r"^\s*import Textual\b|StructuredText|InlineText\b", "18.0",
          "Textual requires iOS 18; legacy renderer needed"),
    _rule("textual-parse", r"AttributedStringMarkdownParser", "18.0", "Textual parser is iOS 18"),
    _rule("task-sleep-duration", r"Task\.sleep\(for:|ContinuousClock|\.sleep\(for:", "16.0",
          "Use Task.sleep(nanoseconds:)"),
    _rule("uigesture-representable", r"UIGestureRecognizerRepresentable|CoordinateSpaceConverter", "18.0",
          "Bridge with UIViewRepresentable"),
    _rule("button-role-close", r"role: \.(close|confirm)\b", "26.0", "Use destructive/cancel roles"),
    _rule("localized-string-resource", r"LocalizedStringResource", "16.0",
          "Public signatures must use LocalizedStringKey or String"),
    _rule("share-link", r"\bShareLink\b|\bSharePreview\b|CoreTransferable|\bTransferable\b|ProxyRepresentation", "16.0",
          "Use UIActivityViewController/NSTextAttachment-free sharing"),
    _rule("layout-protocol", r"\bLayout\b|ProposedViewSize|sizeThatFits\(_ proposal", "16.0",
          "Use GeometryReader/PreferenceKey measurement"),
    _rule("scroll-transition", r"scrollTransition|containerRelativeFrame|containerShape\(|scrollTargetBehavior", "17.0",
          "Static layout or UIPageViewController"),
    _rule("ios26-toolbar", r"navigationSubtitle|sharedBackgroundVisibility|containerCornerOffset|\.subtitle\b", "26.0",
          "Compose the title in a principal toolbar item"),
)

LINE_COMMENT = re.compile(r"//.*$")


def source_files(root: Path) -> list[Path]:
    return sorted(
        path
        for path in root.rglob("*.swift")
        if not SKIP_DIRECTORIES.intersection(path.relative_to(root).parts)
    )


def findings_in_text(relative: str, text: str) -> list[dict[str, object]]:
    """Inventory one Swift source. Comment-only mentions are ignored."""
    findings: list[dict[str, object]] = []
    for number, raw in enumerate(text.splitlines(), start=1):
        line = LINE_COMMENT.sub("", raw).strip()
        if not line:
            continue
        for rule in RULES:
            if rule.pattern.search(line):
                findings.append({
                    "file": relative,
                    "line": number,
                    "rule": rule.name,
                    "minimum": rule.minimum,
                    "note": rule.note,
                    "text": line[:200],
                })
    return findings


def scan(root: Path) -> list[dict[str, object]]:
    findings: list[dict[str, object]] = []
    for path in source_files(root):
        relative = path.relative_to(REPO_ROOT).as_posix()
        findings.extend(findings_in_text(relative, path.read_text(encoding="utf-8")))
    return findings


def counts(findings: list[dict[str, object]]) -> dict[str, int]:
    tally: dict[str, int] = {}
    for finding in findings:
        name = str(finding["rule"])
        tally[name] = tally.get(name, 0) + 1
    return dict(sorted(tally.items()))


def load_baseline(path: Path) -> dict[str, int]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {str(key): int(value) for key, value in data.get("rules", {}).items()}


def regressions(tally: dict[str, int], baseline: dict[str, int]) -> dict[str, tuple[int, int]]:
    return {
        rule: (baseline.get(rule, 0), count)
        for rule, count in tally.items()
        if count > baseline.get(rule, 0)
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--report", action="store_true", help="print every finding")
    parser.add_argument("--check", action="store_true", help="fail on baseline regressions")
    parser.add_argument("--json", type=Path, help="write the full inventory as JSON")
    parser.add_argument("--update-baseline", action="store_true", help="rewrite the reviewed baseline")
    args = parser.parse_args(argv)

    if not args.source.is_dir():
        parser.error(f"source directory not found: {args.source}")

    findings = scan(args.source)
    tally = counts(findings)
    baseline = load_baseline(args.baseline)

    if args.report:
        for finding in findings:
            print(f"{finding['file']}:{finding['line']}: [{finding['rule']} iOS {finding['minimum']}] {finding['text']}")
    print(json.dumps(tally, indent=2))

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps({"rules": tally, "findings": findings}, indent=2) + "\n", encoding="utf-8")

    if args.update_baseline:
        args.baseline.write_text(
            json.dumps({
                "comment": "Reviewed iOS 15 availability inventory. Counts are a ratchet: lower them as call sites are ported; never raise them without review.",
                "rules": tally,
            }, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"baseline written to {args.baseline}")
        return 0

    if args.check:
        failures = regressions(tally, baseline)
        for rule, (before, now) in sorted(failures.items()):
            print(f"ERROR: {rule}: {before} -> {now}", file=sys.stderr)
        if failures:
            print("New iOS 15-incompatible usage. Use the compatibility adapters or update the baseline after review.", file=sys.stderr)
            return 1
        print("iOS 15 availability inventory matches the reviewed baseline.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
