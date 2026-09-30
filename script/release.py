#!/usr/bin/env python3
"""Build evidence-bearing macOS DMGs without shell interpolation or overwrites."""

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "Airwang DIT for Mac.xcodeproj"
SCHEME = "Airwang DIT for Mac"
APP_NAME = SCHEME + ".app"
BUNDLE_ID = "com.airwang.ditformac"


class ReleaseError(Exception):
    pass


def validated_version(value):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", value):
        raise argparse.ArgumentTypeError("Version must contain three numeric components, such as 0.1.1.")
    return value


def validated_build(value):
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise argparse.ArgumentTypeError("Build must be a positive integer that increases for every release.")
    return value


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(arguments, log=None, cwd=ROOT):
    """Keep credentials in Keychain profiles; never use a shell or print env values."""
    if log is None:
        completed = subprocess.run(arguments, cwd=cwd, text=True, capture_output=True)
        if completed.returncode:
            raise ReleaseError(f"{Path(arguments[0]).name} failed: {completed.stderr.strip()}")
        return completed.stdout.strip()
    with log.open("w") as stream:
        completed = subprocess.run(arguments, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
    if completed.returncode:
        raise ReleaseError(f"{Path(arguments[0]).name} failed. Evidence: {log}")
    return ""


def repository_state(root=ROOT):
    revision = run(["git", "rev-parse", "HEAD"], cwd=root)
    # Distribution directories are ignored. All other untracked files count as dirty.
    status = run(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=root)
    return {"revision": revision, "dirty": bool(status)}


def build_input_fingerprint(root=ROOT):
    digest = hashlib.sha256()
    for folder in ["Airwang DIT for Mac", "Airwang DIT for MacTests", "Airwang DIT for MacUITests", "Airwang DIT for Mac.xcodeproj", "script", "distribution"]:
        for path in sorted((root / folder).rglob("*")):
            if not path.is_file() or "xcuserdata" in path.parts or "__pycache__" in path.parts:
                continue
            if path.is_symlink():
                raise ReleaseError(f"Build inputs must not be symlinks: {path.relative_to(root)}")
            digest.update(str(path.relative_to(root)).encode())
            digest.update(b"\0")
            digest.update(bytes.fromhex(sha256(path)))
    return digest.hexdigest()


def check_environment(mode, identity=None, team=None, notary_profile=None):
    blockers = []
    if sys.platform != "darwin":
        blockers.append("macOS is required.")
    for tool in ["xcodebuild", "xcrun", "hdiutil", "ditto", "codesign", "git"]:
        if shutil.which(tool) is None:
            blockers.append(f"Required tool is missing: {tool}")
    if mode == "release":
        if not identity or not identity.startswith("Developer ID Application:"):
            blockers.append("An explicit Developer ID Application identity is required.")
        if not team or not re.fullmatch(r"[A-Z0-9]{10}", team):
            blockers.append("An explicit 10-character Apple Developer team ID is required.")
        if not notary_profile:
            blockers.append("A notarytool Keychain profile is required.")
        if identity and shutil.which("security"):
            identities = run(["security", "find-identity", "-v", "-p", "codesigning"])
            if f'"{identity}"' not in identities:
                blockers.append("The requested Developer ID identity is not available in the current Keychain.")
    return blockers


def validate_test_summary(summary):
    if summary.get("result") != "Passed" or summary.get("failedTests", 0) != 0:
        raise ReleaseError("Unit tests did not pass.")
    if summary.get("passedTests", 0) < 1:
        raise ReleaseError("No passing unit tests were recorded.")
    if summary.get("skippedTests", 0) != 0 or summary.get("expectedFailures", 0) != 0:
        raise ReleaseError("Selected unit tests contain skips or expected failures.")


def inspect_compiler_log(log):
    content = log.read_text(errors="replace")
    source_warnings = re.findall(r"^.+:\d+:\d+: warning:.*$", content, flags=re.MULTILINE)
    if source_warnings:
        raise ReleaseError(f"Compiler warnings block distribution. Evidence: {log}")
    tool_warnings = re.findall(r"^.*\bwarning:.*$", content, flags=re.MULTILINE)
    known_tool_notice = "Metadata extraction skipped, no AppIntents.framework dependency found"
    if any(known_tool_notice not in warning for warning in tool_warnings):
        raise ReleaseError(f"Unclassified build warnings block distribution. Evidence: {log}")
    return {"sourceWarnings": 0, "toolWarnings": tool_warnings}


def summarize_coverage(report):
    target = next((item for item in report.get("targets", []) if item.get("name") == APP_NAME), None)
    if target is None:
        raise ReleaseError("Coverage report does not contain the application target.")
    groups = {}
    for name, folders in {"models": ["Models"], "services": ["Services"], "businessCore": ["Models", "Services", "ViewModels"]}.items():
        files = [item for item in target.get("files", []) if any(f"/{folder}/" in item.get("path", "") for folder in folders)]
        executable = sum(item["executableLines"] for item in files)
        covered = sum(item["coveredLines"] for item in files)
        groups[name] = {"coveredLines": covered, "executableLines": executable,
                        "lineCoverage": covered / executable if executable else None}
    return {"applicationLineCoverage": target["lineCoverage"], "groups": groups}


def provenance_metadata(source):
    if not isinstance(source, dict) or not isinstance(source.get("revision"), str) or not re.fullmatch(r"[0-9a-f]{40}", source["revision"]):
        raise ReleaseError("Source provenance must contain a full Git revision.")
    if not isinstance(source.get("inputSha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", source["inputSha256"]) or type(source.get("dirty")) is not bool:
        raise ReleaseError("Source provenance must contain an input SHA-256 and a working-tree state.")
    return {
        "AirwangSourceRevision": source["revision"],
        "AirwangBuildInputSHA256": source["inputSha256"],
        "AirwangSourceState": "working-tree" if source["dirty"] else "committed",
    }


def validate_app_metadata(info, version, build, source=None):
    expected = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "LSMinimumSystemVersion": "14.0",
    }
    if source is not None:
        expected.update(provenance_metadata(source))
    for key, value in expected.items():
        if info.get(key) != value:
            raise ReleaseError(f"Unexpected app metadata: {key} must equal {value}.")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable:
        raise ReleaseError("Invalid CFBundleExecutable.")
    if not info.get("NSHumanReadableCopyright"):
        raise ReleaseError("App copyright metadata is missing.")
    return executable


def validate_signature_details(details, team):
    if not re.search(r"^Authority=Developer ID Application:", details, flags=re.MULTILINE):
        raise ReleaseError("App does not have a Developer ID Application signature.")
    if not re.search(rf"^TeamIdentifier={re.escape(team)}$", details, flags=re.MULTILINE):
        raise ReleaseError("App signature belongs to an unexpected team.")
    if not re.search(r"flags=0x[0-9a-f]+\([^\n)]*\bruntime\b", details) or not re.search(r"^Timestamp=.+$", details, flags=re.MULTILINE):
        raise ReleaseError("Hardened Runtime and a secure timestamp are required.")


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def build(args):
    blockers = check_environment(args.command, args.identity, args.team, args.notary_profile)
    state = repository_state()
    state["inputSha256"] = build_input_fingerprint()
    if args.command == "release" and state["dirty"]:
        blockers.append("A signed release requires a clean working tree, including untracked files.")
    if blockers:
        raise ReleaseError("\n".join(blockers))

    output_root = args.output.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    prefix = f"{args.command}-{args.version}-{args.build}-"
    output = Path(tempfile.mkdtemp(prefix=prefix, dir=output_root))
    print(f"Build evidence: {output}", flush=True)
    evidence = output / "evidence"
    evidence.mkdir()
    manifest = {
        "schemaVersion": 1,
        "mode": args.command,
        "version": args.version,
        "build": args.build,
        "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": state,
        "embeddedProvenance": True,
        "status": "in-progress",
        "commercialAcceptance": "unverified",
        "uiTests": "excluded-by-scheme",
        "signature": "unsigned-preview",
        "notarization": "not-requested",
        "gatekeeper": "not-assessed",
    }
    manifest_path = output / "manifest.json"
    write_json(manifest_path, manifest)
    try:
        manifest["xcode"] = run(["xcodebuild", "-version"])
        derived = output / "DerivedData"
        result = evidence / "UnitTests.xcresult"
        # Tests use the existing isolated Debug scheme. Never run the Release app
        # against a customer's Application Support directory to produce evidence.
        run([
            "xcodebuild", "test", "-project", str(PROJECT), "-scheme", SCHEME,
            "-destination", f"platform=macOS,arch={os.uname().machine}",
            "-derivedDataPath", str(derived), "-resultBundlePath", str(result),
            "CODE_SIGNING_ALLOWED=NO",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES", "GCC_TREAT_WARNINGS_AS_ERRORS=YES", "SWIFT_STRICT_CONCURRENCY=complete",
        ], evidence / "unit-tests.log")
        debug_diagnostics = inspect_compiler_log(evidence / "unit-tests.log")
        summary = json.loads(run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)]))
        write_json(evidence / "test-summary.json", summary)
        validate_test_summary(summary)
        manifest["unitTests"] = {key: summary[key] for key in ["result", "passedTests", "failedTests", "skippedTests"]}
        coverage = json.loads(run(["xcrun", "xccov", "view", "--report", "--json", str(result)]))
        write_json(evidence / "coverage.json", coverage)
        manifest["coverage"] = summarize_coverage(coverage)

        archive = output / "Airwang-DIT.xcarchive"
        # Xcode only generates its recognized INFOPLIST_KEY_* settings. Merge
        # custom provenance through a source plist before signing the product.
        provenance_plist = evidence / "BuildProvenance.plist"
        provenance_plist.write_bytes(plistlib.dumps(provenance_metadata(state)))
        archive_arguments = [
            "xcodebuild", "archive", "-project", str(PROJECT), "-scheme", SCHEME,
            "-configuration", "Release", "-destination", "generic/platform=macOS",
            "-derivedDataPath", str(derived), "-archivePath", str(archive),
            "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO",
            f"MARKETING_VERSION={args.version}", f"CURRENT_PROJECT_VERSION={args.build}",
            f"INFOPLIST_FILE={provenance_plist}", "GENERATE_INFOPLIST_FILE=YES",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES", "GCC_TREAT_WARNINGS_AS_ERRORS=YES", "SWIFT_STRICT_CONCURRENCY=complete",
        ]
        if args.command == "release":
            archive_arguments += ["CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_STYLE=Manual",
                                  f"DEVELOPMENT_TEAM={args.team}", f"CODE_SIGN_IDENTITY={args.identity}"]
        else:
            archive_arguments += ["CODE_SIGNING_ALLOWED=NO"]
        run(archive_arguments, evidence / "archive.log")
        release_diagnostics = inspect_compiler_log(evidence / "archive.log")
        write_json(evidence / "compile-diagnostics.json", {"Debug": debug_diagnostics, "Release": release_diagnostics})
        manifest["compilerWarnings"] = {"Debug": 0, "Release": 0}
        staging = output / "DMG-Contents"
        staging.mkdir()
        app = staging / APP_NAME
        archived_app = archive / "Products" / "Applications" / APP_NAME
        if args.command == "release":
            options = {
                "method": "developer-id", "teamID": args.team,
                "signingStyle": "manual", "signingCertificate": args.identity,
            }
            options_path = evidence / "ExportOptions.plist"
            options_path.write_bytes(plistlib.dumps(options))
            exported = output / "Exported"
            run([
                "xcodebuild", "-exportArchive", "-archivePath", str(archive),
                "-exportPath", str(exported), "-exportOptionsPlist", str(options_path),
            ], evidence / "export.log")
            run(["ditto", str(exported / APP_NAME), str(app)])
        else:
            run(["ditto", str(archived_app), str(app)])

        info = plistlib.loads((app / "Contents" / "Info.plist").read_bytes())
        executable = validate_app_metadata(info, args.version, args.build, source=state)
        architectures = sorted(run(["lipo", "-archs", str(app / "Contents" / "MacOS" / executable)]).split())
        if architectures != ["arm64", "x86_64"]:
            raise ReleaseError("The release app must contain both arm64 and x86_64.")
        manifest["architectures"] = architectures
        manifest["minimumMacOS"] = info["LSMinimumSystemVersion"]
        (staging / "Applications").symlink_to("/Applications", target_is_directory=True)
        instructions = ROOT / "distribution" / "INSTALL.txt"
        shutil.copy2(instructions, staging / "INSTALL.txt")
        suffix = "" if args.command == "release" else "-UNSIGNED-PREVIEW"
        dmg = output / f"Airwang-DIT-{args.version}-{args.build}{suffix}.dmg"

        if args.command == "release":
            run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], evidence / "app-signature-check.log")
            signature_log = evidence / "app-signature-details.log"
            run(["codesign", "--display", "--verbose=4", str(app)], signature_log)
            validate_signature_details(signature_log.read_text(), args.team)
            notarization_zip = output / "Notarization.zip"
            run(["ditto", "-c", "-k", "--keepParent", str(app), str(notarization_zip)])
            run(["xcrun", "notarytool", "submit", str(notarization_zip), "--keychain-profile", args.notary_profile,
                 "--wait", "--output-format", "json"], evidence / "app-notarization.json")
            notarization = json.loads((evidence / "app-notarization.json").read_text())
            if notarization.get("status") != "Accepted":
                raise ReleaseError("Apple did not accept the app notarization submission.")
            run(["xcrun", "stapler", "staple", str(app)], evidence / "app-staple.log")
            run(["xcrun", "stapler", "validate", str(app)], evidence / "app-staple-validation.log")
            run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], evidence / "app-gatekeeper.log")
            manifest["signature"] = "developer-id"
            manifest["teamID"] = args.team
            manifest["appNotarizationID"] = notarization.get("id")

        run(["hdiutil", "create", "-srcfolder", str(staging), "-volname", "Airwang DIT", "-fs", "HFS+", "-format", "UDZO", str(dmg)], evidence / "dmg-build.log")
        if args.command == "release":
            run(["codesign", "--force", "--sign", args.identity, "--timestamp", str(dmg)], evidence / "dmg-sign.log")
            run(["codesign", "--verify", "--strict", str(dmg)], evidence / "dmg-signature-check.log")
            run(["xcrun", "notarytool", "submit", str(dmg), "--keychain-profile", args.notary_profile,
                 "--wait", "--output-format", "json"], evidence / "dmg-notarization.json")
            notarization = json.loads((evidence / "dmg-notarization.json").read_text())
            if notarization.get("status") != "Accepted":
                raise ReleaseError("Apple did not accept the DMG notarization submission.")
            run(["xcrun", "stapler", "staple", str(dmg)], evidence / "dmg-staple.log")
            run(["xcrun", "stapler", "validate", str(dmg)], evidence / "dmg-staple-validation.log")
            run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", str(dmg)], evidence / "dmg-gatekeeper.log")
            manifest["notarization"] = "accepted-and-stapled"
            manifest["dmgNotarizationID"] = notarization.get("id")
            manifest["gatekeeper"] = "accepted"
        run(["hdiutil", "verify", str(dmg)], evidence / "dmg-integrity.log")
        manifest["artifact"] = {"file": dmg.name, "sha256": sha256(dmg), "bytes": dmg.stat().st_size}
        (output / "SHA256SUMS").write_text(f"{manifest['artifact']['sha256']}  {dmg.name}\n")
        if build_input_fingerprint() != state["inputSha256"] or repository_state()["revision"] != state["revision"]:
            raise ReleaseError("Build inputs changed during validation. Build from a stable checkpoint.")
        if args.command == "release" and repository_state()["dirty"]:
            raise ReleaseError("Working tree changed during release validation.")
        manifest["status"] = "verified-distribution-build" if args.command == "release" else "verified-unsigned-preview"
        write_json(manifest_path, manifest)
        verify_artifact(manifest_path)
        print(f"Created: {dmg}\nManifest: {manifest_path}", flush=True)
    except (ReleaseError, OSError, ValueError) as error:
        manifest["status"] = "failed"
        manifest["error"] = str(error)
        write_json(manifest_path, manifest)
        raise ReleaseError(f"{error}\nIncomplete output is preserved for diagnosis: {output}") from error


def verify_artifact(manifest_path):
    manifest_path = manifest_path.resolve()
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("mode") not in ["release", "preview"]:
        raise ReleaseError("Manifest build mode is invalid.")
    expected_status = "verified-distribution-build" if manifest["mode"] == "release" else "verified-unsigned-preview"
    if manifest.get("schemaVersion") != 1 or manifest.get("status") != expected_status:
        raise ReleaseError("Manifest does not describe a verified build.")
    artifact = manifest.get("artifact", {})
    name = artifact.get("file", "")
    if not name or Path(name).name != name or not name.endswith(".dmg"):
        raise ReleaseError("Manifest artifact path is invalid.")
    dmg = manifest_path.parent / name
    if dmg.is_symlink() or not dmg.is_file():
        raise ReleaseError("Manifest artifact must be a regular file.")
    if dmg.stat().st_size != artifact.get("bytes") or sha256(dmg) != artifact.get("sha256"):
        raise ReleaseError("DMG checksum or size does not match its manifest.")
    run(["hdiutil", "verify", str(dmg)])
    inspect_disk_image(dmg, manifest)
    if manifest["mode"] == "release":
        if manifest.get("signature") != "developer-id" or manifest.get("notarization") != "accepted-and-stapled" or manifest.get("gatekeeper") != "accepted":
            raise ReleaseError("Release signature, notarization, or Gatekeeper evidence is missing.")
        run(["codesign", "--verify", "--strict", str(dmg)])
        run(["xcrun", "stapler", "validate", str(dmg)])
        run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", str(dmg)])
    print(f"Verified: {dmg}\nMode: {manifest['mode']}\nCommercial acceptance: {manifest.get('commercialAcceptance', 'unverified')}")


def inspect_disk_image(dmg, manifest):
    """Read the actual installation payload without launching or installing it."""
    mount = Path(tempfile.mkdtemp(prefix="airwang-release-inspect-"))
    attached = False
    try:
        run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(dmg)])
        attached = True
        app = mount / APP_NAME
        if app.is_symlink() or not app.is_dir():
            raise ReleaseError("DMG is missing its application payload.")
        info = plistlib.loads((app / "Contents" / "Info.plist").read_bytes())
        source = None
        if manifest.get("embeddedProvenance") is True:
            source = manifest.get("source")
            provenance_metadata(source)
        executable = validate_app_metadata(info, manifest["version"], manifest["build"], source=source)
        architectures = sorted(run(["lipo", "-archs", str(app / "Contents" / "MacOS" / executable)]).split())
        if architectures != ["arm64", "x86_64"]:
            raise ReleaseError("DMG application payload is missing a supported architecture.")
        shortcut = mount / "Applications"
        if not shortcut.is_symlink() or os.readlink(shortcut) != "/Applications":
            raise ReleaseError("DMG is missing the Applications installation shortcut.")
        if manifest["mode"] == "release":
            run(["codesign", "--verify", "--deep", "--strict", str(app)])
            # codesign prints its metadata to stderr.
            result = subprocess.run(["codesign", "--display", "--verbose=4", str(app)], capture_output=True, text=True)
            if result.returncode:
                raise ReleaseError("Cannot inspect the DMG app signature.")
            validate_signature_details(result.stderr, manifest.get("teamID", ""))
            run(["xcrun", "stapler", "validate", str(app)])
            run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)])
    finally:
        if attached:
            # Never force-unmount a volume. Keep the inspection location on error.
            run(["hdiutil", "detach", str(mount)])
        mount.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ["check", "preview", "release"]:
        sub = commands.add_parser(name)
        sub.add_argument("--identity", default=os.environ.get("AIRWANG_RELEASE_IDENTITY"))
        sub.add_argument("--team", default=os.environ.get("AIRWANG_RELEASE_TEAM"))
        sub.add_argument("--notary-profile", default=os.environ.get("AIRWANG_NOTARY_PROFILE"))
        if name != "check":
            sub.add_argument("--version", required=True, type=validated_version)
            sub.add_argument("--build", required=True, type=validated_build)
            sub.add_argument("--output", type=Path, default=ROOT / "Dist")
    verification = commands.add_parser("verify")
    verification.add_argument("manifest", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "check":
            blockers = check_environment("release", args.identity, args.team, args.notary_profile)
            environment_ready = not blockers
            print(json.dumps({"signingEnvironmentReady": environment_ready, "blockers": blockers, "repository": repository_state()}, indent=2))
            return 0 if environment_ready else 1
        if args.command == "verify":
            verify_artifact(args.manifest)
        else:
            build(args)
        return 0
    except (ReleaseError, OSError, ValueError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
