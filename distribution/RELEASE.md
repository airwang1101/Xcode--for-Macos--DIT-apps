# Reproducible distribution builds

The release entry point is `script/build-release.sh`, backed by a standard-library Python tool. It does not install the app, publish files, change Keychain contents, or remove previous build outputs. Each attempt creates a new directory and keeps logs on failure.

## Local unsigned preview

```sh
bash script/build-release.sh preview --version 0.1.1 --build 20260930
```

This runs the isolated Debug unit suite, creates a universal Release archive, packages a DMG with an Applications shortcut, verifies its checksum and actual app payload, and records the source commit plus a hash of build inputs. Source changes during validation stop the build. The filename contains `UNSIGNED-PREVIEW`.

New builds also embed the full Git revision, input SHA-256 and working-tree state in the app's information property list before signing. Payload inspection checks these values against the build manifest. Local support diagnostics can then identify the exact build without collecting paths. Earlier saved packages without embedded provenance remain verifiable with their original manifests.

Default output is the ignored `Dist/` directory. The app requires macOS 14.0. UI tests remain excluded by the current scheme and are reported as such. Preview generation does not prove customer installation or commercial readiness.

## Signing prerequisite check

```sh
bash script/build-release.sh check
```

Use these environment variables or their corresponding command arguments:

- `AIRWANG_RELEASE_IDENTITY`: full `Developer ID Application: ...` identity name.
- `AIRWANG_RELEASE_TEAM`: Apple team ID.
- `AIRWANG_NOTARY_PROFILE`: an existing `notarytool` Keychain profile.

Store credentials interactively with Apple's `notarytool store-credentials`. Keep certificates and passwords out of the repository and chat. The tool reads an existing profile. It does not create or export a key.

## Signed and notarized candidate

```sh
bash script/build-release.sh release --version 0.1.1 --build 20260930
```

This additionally requires a clean working tree and a valid configured identity. It archives and exports with Developer ID, checks the app's team, Hardened Runtime and timestamp, submits the app for notarization, staples it, creates and signs the DMG, notarizes and staples the DMG, and checks Gatekeeper for both payloads. Any failed step prevents a verified result. Apple rejection details and incomplete outputs remain in the attempt's evidence folder.

There is no certificate on the currently inspected build machine, so the real signing and notarization path remains unverified. This command is a release candidate build procedure. Commercial acceptance, real hardware testing, updates, licensing, support and other product gates remain in `DISTRIBUTION_READINESS.md`.

## Reverify a saved package

```sh
bash script/build-release.sh verify Dist/preview-0.1.1-20260930-EXAMPLE/manifest.json
```

Use the actual manifest path printed by the build. Verification checks the hash and size, disk image integrity, application metadata, both architectures, and the Applications shortcut. It mounts only that DMG read-only with a unique temporary mountpoint, then detaches it. Signed candidates additionally require real signature, staple and Gatekeeper checks; manifest text cannot replace those checks.

## Evidence and CI

Every attempt keeps `manifest.json`, test summary, `.xcresult`, build logs, a `.xcarchive` including dSYM, `SHA256SUMS`, and the DMG when generation succeeds. `commercialAcceptance` remains `unverified`.

The GitHub Actions workflow runs script gates and this same preview procedure on a macOS runner. It uploads only installation previews and evidence, uses read-only repository permissions, and never receives signing secrets or publishes a release. Remote CI success must be recorded separately from local validation.

Authoritative implementation references: [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [Sparkle distribution](https://sparkle-project.org/documentation/), [GitHub workflow artifacts](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts).

Custom application metadata follows [Apple's information property list guidance](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AboutInformationPropertyListFiles.html). A generated source plist contributes the custom provenance keys while the existing Xcode settings continue to supply the app's metadata.
