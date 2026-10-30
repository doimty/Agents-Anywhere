#!/usr/bin/env python3
"""Run real original-component UI interactions with native/backport observation.

This script runs on the macOS Xcode runner. The fixture uses no saved login and
never contacts a server. The xctest bundle keeps screenshots for each path.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys


def run(command: list[str], *, log: Path | None = None, timeout: int = 180) -> int:
    print("+", " ".join(command), flush=True)
    output = log.open("w", encoding="utf-8") if log else None
    process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT if output else None,
                               start_new_session=True)
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        print(f"Timed out after {timeout}s", file=sys.stderr, flush=True)
        return 124
    finally:
        if output:
            output.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
    phones = [(runtime, device) for runtime, items in devices["devices"].items()
              if ".iOS-" in runtime for device in items
              if device.get("isAvailable") and "iPhone" in device["name"]]
    if not phones:
        print("No available iPhone simulator", file=sys.stderr)
        return 1
    runtime, device = phones[0]
    udid = device["udid"]
    (args.evidence / "simulator.json").write_text(json.dumps({"runtime": runtime, "device": device}, indent=2))
    result = args.evidence / "CompatibilityUI.xcresult"
    log = args.evidence / "compatibility-ui.log"
    try:
        if device.get("state") != "Booted":
            if run(["xcrun", "simctl", "boot", udid]) != 0:
                return 1
        if run(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=600) != 0:
            return 1
        status = run([
            "xcodebuild", "test", "-project", "ios/Agents Anywhere/Agents Anywhere.xcodeproj",
            "-scheme", "CompatibilityRegression", "-configuration", "Debug",
            "-destination", f"platform=iOS Simulator,id={udid}",
            "-derivedDataPath", str(args.derived_data), "-resultBundlePath", str(result),
            "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
            "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "120",
            # XCUITest synchronises with the app for every element query. On the
            # native eager transcript each query walks hundreds of laid-out
            # Markdown nodes, so the 100-message case needs a budget above the
            # 120 s default. This raises the harness budget only; no assertion,
            # message count or content is reduced.
            "-maximum-test-execution-time-allowance", "600",
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
        ], log=log, timeout=1500)
        (args.evidence / "compatibility-ui-exit.txt").write_text(str(status) + "\n")
        if log.exists():
            lines = log.read_text(errors="replace").splitlines()
            for line in lines:
                if " error: " in line or "Test Case '" in line:
                    print(line, flush=True)
            print("\n".join(lines[-70:]), flush=True)
        if result.exists():
            run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)],
                log=args.evidence / "compatibility-ui-summary.json", timeout=60)
            run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                 "--output-path", str(args.evidence / "screenshots")], timeout=60)
        return status
    finally:
        run(["xcrun", "simctl", "shutdown", udid], timeout=30)


if __name__ == "__main__":
    raise SystemExit(main())
