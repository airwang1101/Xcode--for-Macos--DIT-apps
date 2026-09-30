"""Release gate tests. Real codesigning/notarization still needs a Developer ID."""

import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("release", Path(__file__).resolve().parents[1] / "release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseGateTests(unittest.TestCase):
    def test_versions_cannot_be_paths_or_command_text(self):
        for value in ["../1.2.3", "1.2.3;echo injected", "1.2", "01.2.3", "$(date)"]:
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                release.validated_version(value)
        self.assertEqual(release.validated_version("0.1.1"), "0.1.1")

    def test_build_requires_a_positive_integer(self):
        for value in ["0", "-1", "1.2", "../5", "001"]:
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                release.validated_build(value)
        self.assertEqual(release.validated_build("2026093001"), "2026093001")

    def test_empty_skipped_or_failed_unit_results_do_not_pass(self):
        for summary in [
            {"result": "Passed", "passedTests": 0},
            {"result": "Failed", "passedTests": 94, "failedTests": 1},
            {"result": "Passed", "passedTests": 94, "skippedTests": 1},
            {"result": "Passed", "passedTests": 94, "expectedFailures": 1},
        ]:
            with self.subTest(summary=summary), self.assertRaises(release.ReleaseError):
                release.validate_test_summary(summary)
        release.validate_test_summary({"result": "Passed", "passedTests": 94, "failedTests": 0, "skippedTests": 0})

    def test_preview_cannot_claim_developer_id_validation(self):
        details = "Signature=adhoc\nTeamIdentifier=not set\nflags=0x10000(runtime)\nTimestamp=today"
        with self.assertRaises(release.ReleaseError):
            release.validate_signature_details(details, "ABCDEFGHIJ")

    def test_signature_requires_expected_team_runtime_and_timestamp(self):
        details = "Authority=Developer ID Application: Airwang (ABCDEFGHIJ)\nTeamIdentifier=ABCDEFGHIJ\nCodeDirectory flags=0x10000(runtime)\nTimestamp=today"
        release.validate_signature_details(details, "ABCDEFGHIJ")
        for modified in [details.replace("TeamIdentifier=ABCDEFGHIJ", "TeamIdentifier=ZZZZZZZZZZ"),
                         details.replace("(runtime)", "(none)"), details.replace("Timestamp=", "NoTimestamp=")]:
            with self.subTest(details=modified), self.assertRaises(release.ReleaseError):
                release.validate_signature_details(modified, "ABCDEFGHIJ")

    def test_app_metadata_rejects_debug_bundle_wrong_version_or_missing_copyright(self):
        info = {"CFBundleIdentifier": release.BUNDLE_ID, "CFBundleShortVersionString": "0.1.1",
                "CFBundleVersion": "42", "LSMinimumSystemVersion": "14.0", "CFBundleExecutable": release.SCHEME,
                "NSHumanReadableCopyright": "Copyright 2026 Airwang"}
        self.assertEqual(release.validate_app_metadata(info, "0.1.1", "42"), release.SCHEME)
        for key, value in [("CFBundleIdentifier", release.BUNDLE_ID + ".dev"), ("CFBundleVersion", "41"),
                           ("NSHumanReadableCopyright", ""), ("CFBundleExecutable", "../other")]:
            with self.subTest(key=key), self.assertRaises(release.ReleaseError):
                release.validate_app_metadata(dict(info, **{key: value}), "0.1.1", "42")

    def manifest_fixture(self, folder, mode="preview"):
        dmg = folder / "test.dmg"
        dmg.write_bytes(b"synthetic disk image fixture")
        manifest = {"schemaVersion": 1, "mode": mode,
                    "status": "verified-unsigned-preview" if mode == "preview" else "verified-distribution-build",
                    "version": "0.1.1", "build": "42",
                    "artifact": {"file": dmg.name, "sha256": release.sha256(dmg), "bytes": dmg.stat().st_size}}
        path = folder / "manifest.json"
        release.write_json(path, manifest)
        return path, dmg, manifest

    def test_app_metadata_requires_exact_embedded_source_provenance(self):
        source = {"revision": "a" * 40, "inputSha256": "b" * 64, "dirty": True}
        info = {"CFBundleIdentifier": release.BUNDLE_ID, "CFBundleShortVersionString": "0.1.1",
                "CFBundleVersion": "42", "LSMinimumSystemVersion": "14.0", "CFBundleExecutable": release.SCHEME,
                "NSHumanReadableCopyright": "Copyright 2026 Airwang", **release.provenance_metadata(source)}
        self.assertEqual(release.validate_app_metadata(info, "0.1.1", "42", source), release.SCHEME)
        for key in release.provenance_metadata(source):
            with self.subTest(key=key), self.assertRaises(release.ReleaseError):
                release.validate_app_metadata(dict(info, **{key: "tampered"}), "0.1.1", "42", source)
            incomplete = dict(info)
            incomplete.pop(key)
            with self.assertRaises(release.ReleaseError):
                release.validate_app_metadata(incomplete, "0.1.1", "42", source)
        self.assertEqual(release.provenance_metadata(dict(source, dirty=False))["AirwangSourceState"], "committed")

    def test_missing_or_invalid_provenance_cannot_be_embedded(self):
        for source in [None, {}, {"revision": "../path", "inputSha256": "b" * 64, "dirty": False},
                       {"revision": "a" * 40, "inputSha256": "b" * 64, "dirty": "false"},
                       {"revision": "a" * 40, "inputSha256": "b" * 63, "dirty": False}]:
            with self.subTest(source=source), self.assertRaises(release.ReleaseError):
                release.provenance_metadata(source)

    def test_altered_disk_image_does_not_verify(self):
        with tempfile.TemporaryDirectory() as directory:
            path, dmg, _ = self.manifest_fixture(Path(directory))
            dmg.write_bytes(b"changed disk image bytes")
            with self.assertRaises(release.ReleaseError), patch.object(release, "run") as run:
                release.verify_artifact(path)
            run.assert_not_called()

    def test_manifest_cannot_escape_its_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _, manifest = self.manifest_fixture(Path(directory))
            for name in ["../test.dmg", "/tmp/test.dmg", "test.zip"]:
                manifest["artifact"]["file"] = name
                release.write_json(path, manifest)
                with self.subTest(name=name), self.assertRaises(release.ReleaseError):
                    release.verify_artifact(path)

    def test_symlink_disk_image_does_not_verify(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            path, dmg, _ = self.manifest_fixture(folder)
            other = folder / "original.dmg"
            dmg.rename(other)
            dmg.symlink_to(other)
            with self.assertRaises(release.ReleaseError):
                release.verify_artifact(path)

    def test_preview_mode_and_signed_status_cannot_be_mixed(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _, manifest = self.manifest_fixture(Path(directory))
            manifest["status"] = "verified-distribution-build"
            release.write_json(path, manifest)
            with self.assertRaises(release.ReleaseError):
                release.verify_artifact(path)

    def test_signed_manifest_requires_real_signature_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _, manifest = self.manifest_fixture(Path(directory), "release")
            with patch.object(release, "run"), patch.object(release, "inspect_disk_image"), self.assertRaises(release.ReleaseError):
                release.verify_artifact(path)
            manifest.update(signature="developer-id", notarization="accepted-and-stapled", gatekeeper="accepted")
            release.write_json(path, manifest)
            with patch.object(release, "run", side_effect=release.ReleaseError("Gatekeeper rejected")), self.assertRaises(release.ReleaseError):
                release.verify_artifact(path)

    def test_source_changes_change_input_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Airwang DIT for Mac"
            app.mkdir()
            source = app / "App.swift"
            source.write_text("first version")
            initial = release.build_input_fingerprint(root)
            source.write_text("different version")
            self.assertNotEqual(initial, release.build_input_fingerprint(root))

    def test_source_warnings_block_release_even_when_compiler_returns_success(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "build.log"
            log.write_text("/project with spaces/Tests.swift:14:15: warning: actor isolation\n** BUILD SUCCEEDED **")
            with self.assertRaises(release.ReleaseError):
                release.inspect_compiler_log(log)
            log.write_text("appintentsmetadataprocessor warning: Metadata extraction skipped, no AppIntents.framework dependency found")
            self.assertEqual(release.inspect_compiler_log(log)["sourceWarnings"], 0)
            self.assertEqual(len(release.inspect_compiler_log(log)["toolWarnings"]), 1)
            log.write_text("warning: Resource missing from bundle")
            with self.assertRaises(release.ReleaseError):
                release.inspect_compiler_log(log)

    def test_coverage_uses_application_lines_and_never_test_target_percentages(self):
        report = {"targets": [
            {"name": release.APP_NAME, "lineCoverage": .3, "files": [
                {"path": "/App/Services/Transfer.swift", "executableLines": 200, "coveredLines": 100},
                {"path": "/App/Models/Model.swift", "executableLines": 50, "coveredLines": 50},
                {"path": "/App/ViewModels/VM.swift", "executableLines": 100, "coveredLines": 10},
            ]},
            {"name": "Tests.xctest", "lineCoverage": 1.0, "files": []},
        ]}
        summary = release.summarize_coverage(report)
        self.assertEqual(summary["applicationLineCoverage"], .3)
        self.assertEqual(summary["groups"]["services"]["lineCoverage"], .5)
        self.assertAlmostEqual(summary["groups"]["businessCore"]["lineCoverage"], 160 / 350)

    def test_archive_and_export_commands_preserve_spaces_as_arguments(self):
        with tempfile.TemporaryDirectory(prefix="airwang release ") as directory:
            root = Path(directory)
            log = root / "tool.log"
            with patch.object(release.subprocess, "run") as command:
                command.return_value.returncode = 0
                release.run(["codesign", "--sign", "Developer ID Application: Person Name (ABCDEFGHIJ)", "/path with spaces/App.app"], log)
                self.assertEqual(command.call_args.args[0][-1], "/path with spaces/App.app")
                self.assertNotIn("shell", command.call_args.kwargs)


if __name__ == "__main__":
    unittest.main()
