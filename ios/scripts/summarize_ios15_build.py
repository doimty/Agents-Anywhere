"""Report real source-located compiler diagnostics without hiding build failure."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

DIAGNOSTIC = re.compile(r"^(.*\.(?:swift|m|mm|c|h)):(\d+):(\d+):\s*(error|warning):\s*(.*)$")


def extract(text: str) -> list[dict[str, object]]:
    output: list[dict[str, object]] = []
    seen: set[tuple[str, str, str, str]] = set()
    for line in text.splitlines():
        match = DIAGNOSTIC.match(line.strip())
        if match is None:
            continue
        file, row, column, severity, message = match.groups()
        key = (file, row, column, message)
        if key in seen:
            continue
        seen.add(key)
        output.append(dict(file=file, line=int(row), column=int(column), severity=severity, message=message))
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--exit-code", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    text = args.log.read_text(encoding="utf-8", errors="replace")
    diagnostics = extract(text)
    errors = [value for value in diagnostics if value["severity"] == "error"]
    report = {"xcodebuild_exit": args.exit_code, "build_succeeded": args.exit_code == 0 and "** BUILD SUCCEEDED **" in text,
              "error_count": len(errors), "diagnostics": diagnostics}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("# Original interface iOS 15 build\n")
    print(f"xcodebuild exit: **{args.exit_code}**; source-located errors: **{len(errors)}**\n")
    print("```text")
    for error in errors[:100]:
        print(f"{error['file']}:{error['line']}:{error['column']}: {error['message']}")
    print("```")
    if args.exit_code != 0 and not errors:
        print("Build failed before source diagnostics; inspect the complete build log.")


if __name__ == "__main__":
    main()
