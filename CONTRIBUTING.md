# Contributing

Airwang DIT for Mac is licensed under the [MIT License](LICENSE).

Use `codex/dit-paper-workbench` as the base for changes. Preserve existing UI
choices, verification modes, sidecar rules, report evidence, and recovery behavior.
Changes that write media should retain independent verification, destination
conflict protection, and source/destination separation checks.

## Build and check

Use an Apple Silicon or Intel Mac with Xcode that supports Swift 6 and a macOS 14 or newer deployment target.
Open `Airwang DIT for Mac.xcodeproj`, select the `Airwang DIT for Mac` scheme,
and build. Distribution prerequisites are documented in
[distribution/RELEASE.md](distribution/RELEASE.md).

For tests without launching application windows:

```sh
AIRWANG_DIT_APP_SUPPORT_DIR=/tmp/airwang-dit-unit-tests python3 script/headless_tests.py
python3 -m unittest discover -s script/tests -v
git diff --check
```

Use disposable synthetic media and isolated data directories for automated tests.
Keep real card media, copy histories, signing certificates, credentials, build
products, and personal screenshots out of commits. Describe observed behavior
and relevant evidence in pull requests. Synthetic or warm-cache benchmarks
should state their scope; physical-card performance requires hardware validation.

## Reporting problems

Include the application version, build number, macOS version, and reproducible
steps. The application can export support diagnostics that exclude media names
and paths. Review any attachment before posting it publicly. Avoid uploading
original media, complete copy reports, private paths, or credentials.
