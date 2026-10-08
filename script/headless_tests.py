#!/usr/bin/env python3
"""Run existing macOS unit tests without starting the SwiftUI application.

Stages a disposable Swift package, retaining every Swift source and test file.
Only the application's @main App declaration is omitted from the staged copy.
Native Xcode compilation must separately validate that declaration and assets.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--package-path", type=Path)
    parser.add_argument("--scratch-path", type=Path)
    parser.add_argument("--filter")
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    root = args.source_root.resolve()
    if not (root / "Airwang DIT for Mac/AirwangDITForMacApp.swift").is_file():
        parser.error("source-root must contain the native Airwang DIT project")
    if not list((root / "Airwang DIT for MacTests").glob("*.swift")):
        parser.error("source-root must contain the existing unit tests")
    package = args.package_path or Path(tempfile.mkdtemp(prefix="airwang-dit-headless-"))
    package.mkdir(parents=True, exist_ok=True)
    if any(package.iterdir()) and not (package / "source-manifest.json").is_file():
        parser.error("package-path must be empty or an existing headless harness directory")
    records = []
    for directory, target in [("Airwang DIT for Mac", "Sources/Airwang_DIT_for_Mac"),
                              ("Airwang DIT for MacTests", "Tests/Airwang_DIT_for_MacTests")]:
        for source in sorted((root / directory).rglob("*.swift")):
            original = source.read_bytes()
            staged = original
            if source.name == "AirwangDITForMacApp.swift":
                start = b"@main\nstruct AirwangDITForMacApp: App {"
                end = b"private struct MainWindowConfigurator: NSViewRepresentable {"
                assert original.count(start) == original.count(end) == 1
                staged = original[:original.index(start)] + original[original.index(end):]
            destination = package / target / source.relative_to(root / directory)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if not destination.exists() or destination.read_bytes() != staged:
                destination.write_bytes(staged)
            records.append({"path": str(source.relative_to(root)),
                            "source_sha256": hashlib.sha256(original).hexdigest(),
                            "staged_sha256": hashlib.sha256(staged).hexdigest()})
    expected = {str(Path(record["path"]).relative_to("Airwang DIT for Mac"))
                for record in records if record["path"].startswith("Airwang DIT for Mac/")}
    expected_tests = {str(Path(record["path"]).relative_to("Airwang DIT for MacTests"))
                      for record in records if record["path"].startswith("Airwang DIT for MacTests/")}
    for target, paths in [("Sources/Airwang_DIT_for_Mac", expected),
                          ("Tests/Airwang_DIT_for_MacTests", expected_tests)]:
        for staged_file in (package / target).rglob("*.swift"):
            if str(staged_file.relative_to(package / target)) not in paths:
                staged_file.unlink()
    package_definition = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AirwangDITHeadlessValidation",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Airwang_DIT_for_Mac"),
        .testTarget(name: "Airwang_DIT_for_MacTests", dependencies: ["Airwang_DIT_for_Mac"])
    ]
)
'''
    package_file = package / "Package.swift"
    if not package_file.exists() or package_file.read_text() != package_definition:
        package_file.write_text(package_definition)
    (package / "source-manifest.json").write_text(json.dumps({
        "source_root": str(root),
        "transformation": "Omit only @main AirwangDITForMacApp declaration in staged library",
        "files": records,
    }, indent=2) + "\n")
    print(f"Headless package: {package}", flush=True)
    if args.prepare_only:
        return 0
    environment = dict(os.environ, AIRWANG_DIT_UNIT_TESTING="1",
                       AIRWANG_DIT_APP_SUPPORT_DIR="/tmp/airwang-dit-unit-tests")
    command = ["swift", "test", "--package-path", str(package), "--jobs", "2"]
    if args.scratch_path:
        command += ["--scratch-path", str(args.scratch_path)]
    if args.filter:
        command += ["--filter", args.filter]
    return subprocess.call(command, env=environment)


if __name__ == "__main__":
    raise SystemExit(main())
