#!/usr/bin/env python3
"""Verify device IPA metadata and every embedded Mach-O before delivery."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile

# Exact import from the user's iOS 15.1.1 launch-crash report. Synthesised
# Equatable over AttributedString.Runs.Index must never reintroduce it.
FORBIDDEN_IMPORT = b"_$s10Foundation16AttributedStringV4RunsV5IndexV2eeoiySbAG_AGtFZ"


def mach_o(data: bytes) -> dict | None:
    if data[:4] != b"\xcf\xfa\xed\xfe":
        return None
    _, cpu, subtype, file_type, count, _, _, _ = struct.unpack_from("<8I", data)
    commands = []
    dependencies = []
    offset = 32
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid Mach-O load command")
        if command == 0x32:
            platform, minimum, sdk = struct.unpack_from("<III", data, offset + 8)
            commands.append({"platform": platform, "minimum": minimum, "sdk": sdk})
        if command in (0xC, 0x80000018):
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            name = data[offset + name_offset:offset + size].split(b"\0", 1)[0].decode("utf-8")
            dependencies.append({"path": name, "weak": command == 0x80000018})
        offset += size
    return {"cpu": cpu, "subtype": subtype, "fileType": file_type,
            "buildVersions": commands, "dependencies": dependencies,
            "forbiddenFoundationImport": FORBIDDEN_IMPORT in data}


def verify(ipa: Path, expected_build: str | None = None) -> dict:
    report = {"file": ipa.name, "sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
              "bytes": ipa.stat().st_size, "images": []}
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise ValueError("IPA CRC verification failed")
        plist_paths = [name for name in archive.namelist()
                       if name.startswith("Payload/") and name.count("/") == 2 and name.endswith("/Info.plist")]
        if len(plist_paths) != 1:
            raise ValueError("Expected exactly one application payload")
        info = plistlib.loads(archive.read(plist_paths[0]))
        report.update(bundle=info["CFBundleIdentifier"], version=info["CFBundleShortVersionString"],
                      build=info["CFBundleVersion"], minimumOS=info["MinimumOSVersion"])
        if info["MinimumOSVersion"] != "15.0":
            raise ValueError("Wrong minimum operating system")
        if expected_build and str(info["CFBundleVersion"]) != expected_build:
            raise ValueError("Unexpected app build number")
        for name in archive.namelist():
            if name.endswith("/"):
                continue
            image = mach_o(archive.read(name))
            if image is None:
                continue
            if image["cpu"] != 0x0100000C:
                raise ValueError(f"Not an arm64 image: {name}")
            if not image["buildVersions"]:
                raise ValueError(f"Missing platform evidence: {name}")
            for build in image["buildVersions"]:
                if build["platform"] != 2 or build["minimum"] > (15 << 16):
                    raise ValueError(f"Image cannot run on an iOS 15 device: {name}: {build}")
            if image["forbiddenFoundationImport"]:
                raise ValueError(f"iOS 15.1.1 missing Foundation import reintroduced: {name}")
            report["images"].append({"path": name, **image})
        if not report["images"]:
            raise ValueError("No executable images found")
    report["verified"] = True
    report["runtimeValidation"] = "Binary checks only; device interaction and visual acceptance remain separate."
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--expected-build")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = verify(args.ipa, args.expected_build)
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.write_text(rendered + "\n", encoding="utf-8")
    print(f"Verified {report['file']}: {report['version']} ({report['build']}), iOS {report['minimumOS']}, {len(report['images'])} arm64 device images")
    print("SHA256 " + report["sha256"])


if __name__ == "__main__":
    main()
