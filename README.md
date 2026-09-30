# Airwang DIT for Mac

Airwang DIT for Mac is a SwiftUI macOS app for Digital Imaging Technician copy workflows. It helps ingest media from external cards or folders, copy selected assets to a primary working drive, optionally create a backup, verify the result, and keep traceable task reports.

Repository: [wngair/Xcode--for-Macos--DIT-apps](https://github.com/wngair/Xcode--for-Macos--DIT-apps)

## Current Status

- Platform: macOS app
- UI framework: SwiftUI
- Language: Swift 6
- Minimum macOS target: macOS 14.0
- Bundle identifier: `com.airwang.ditformac`
- Main scheme: `Airwang DIT for Mac`
- Test target: `Airwang DIT for MacTests`

Commercial release gates and current evidence are maintained in [DISTRIBUTION_READINESS.md](DISTRIBUTION_READINESS.md). The earlier GA plan remains a historical plan; its old code counts and defect statuses are not current validation results.

## Features

- Detects external storage volumes and shows importable media sources.
- Supports source folder selection when the whole card should not be scanned.
- Scans video, photo, audio, and sidecar files.
- Provides time-based grouping and free browsing modes.
- Supports icon, list, column, and gallery browsing.
- Creates named copy projects and queues them for execution.
- Runs queued projects sequentially or in parallel based on the selected execution mode.
- Auto-starts newly queued projects after 5 minutes when the setting is enabled.
- Copies to a primary target drive.
- Optionally backs up from the primary copy to a backup drive.
- Verifies copied files using SHA-256 or size checks, with a skip-verification option.
- Blocks unsafe paths, overlapping source and destination paths, same-volume target and backup paths, and symlink escape paths.
- Writes task reports and keeps local task history.
- Provides Chinese and English UI language settings.
- Provides day and night themes.
- Exports optional local support diagnostics with media, filenames, paths, and raw errors excluded. See [support diagnostics](SUPPORT_DIAGNOSTICS.md).

## Project Layout

```text
Airwang DIT for Mac.xcodeproj/
  xcshareddata/xcschemes/
    Airwang DIT for Mac.xcscheme

Airwang DIT for Mac/
  AirwangDITForMacApp.swift
  Models/
    Models.swift
    StoreFiles.swift
  Services/
    MediaScanner.swift
    PathSafety.swift
    SettingsStore.swift
    TransferService.swift
    VolumeMonitor.swift
  ViewModels/
    AppViewModel.swift
  Views/
    ContentView.swift
    AirwangPalette.swift

Airwang DIT for MacTests/
  MediaScannerTests.swift
  PathSafetyTests.swift
  PersistenceCompatibilityTests.swift
```

## Open Locally

Open the project in Xcode:

```bash
open "Airwang DIT for Mac.xcodeproj"
```

Select the `Airwang DIT for Mac` scheme, then run the app from Xcode.

## Build From Terminal

This machine currently has Xcode available at `/Applications/Xcode-beta.app`. If `xcodebuild` reports that the active developer directory is Command Line Tools, set `DEVELOPER_DIR` for the command:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild \
  -project "Airwang DIT for Mac.xcodeproj" \
  -scheme "Airwang DIT for Mac" \
  -configuration Debug \
  build
```

To make full Xcode the default developer directory for future terminal sessions:

```bash
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer
```

## Run Tests

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild \
  -project "Airwang DIT for Mac.xcodeproj" \
  -scheme "Airwang DIT for Mac" \
  -destination "platform=macOS" \
  test
```

The current test suite covers:

- media scanning around hidden folders, system folders, and symbolic links
- relative path safety and path containment
- Unicode filename handling
- source, target, and backup path overlap checks
- same-volume detection
- JSON persistence compatibility for older project and UI settings files
- corrupt local JSON backup behavior

## Local App Data

Runtime data is stored under the app's Application Support directory:

```text
~/Library/Application Support/com.airwang.ditformac/
```

Important files:

```text
Data/preferences.json
Data/ui-settings.json
Data/import-reports.json
Data/copy-projects.json
Reports/Airwang_*_Report_*.txt
```

When JSON persistence files are corrupt, the app backs them up with a `.corrupt-YYYYMMDD_HHMMSS` suffix and falls back to empty or default state.

Corrupt backups now have an additional unique identifier, so repeated recovery attempts preserve each copy. Before saving, the app checks the existing data again. Unrecognized valid JSON and unsupported schema versions are preserved and saving reports an error. Compatible settings retain unknown additive fields, and valid legacy arrays are backed up before migration.

## Verification Modes

- `sha256`: independently reads source and destination data and compares full SHA-256 checksums.
- `fastFingerprint`: compares size and samples the beginning, middle, and end of a file. It cannot detect every content change.
- `sizeOnly`: compares copied file size against the source file size.
- `skipped`: records the skipped verification state in the task flow and report.

## Retry and Recovery

- A fresh project continues to reject existing destination files.
- Manually retrying a project preserves its paths and enables recovery by file. Existing regular files are read back and compared to the original using full SHA-256, including when a faster verification mode was selected.
- Missing files are copied using the selected verification policy. The skip-verification option remains available for these newly copied files.
- Files with different content, symbolic links, and directory collisions are preserved and reported as failures. Recovery does not replace or remove them.
- New projects record available source, primary, and backup volume identifiers. Transfer and report writes stop if a recorded destination is disconnected or replaced, even when its old mountpoint directory still exists.
- Each attempt produces a separate report. Reports list files reused after successful full verification and the number of files newly copied in that attempt.
- Recovery repeats the primary stage before running backup. The original source must remain available. Resuming inside a partially copied file and restoring backup independently of the original source are not implemented.
- Legacy project and report JSON remains readable. Missing recovery fields default to a fresh execution policy and unrecorded volume identifiers.

The Debug test scheme places application data in `/tmp/airwang-dit-unit-tests`. The two UI tests remain excluded from the default scheme. See [the recovery verification record](RECOVERY_VERIFICATION_2026-09-30.md) for current test coverage and release limitations.

## Safety Notes

- Primary target and backup target should be separate volumes.
- Source folders, primary targets, and backup targets cannot overlap.
- Symbolic link paths are rejected for writable and existing file targets.
- Hidden system folders such as `.Trashes`, `.Spotlight-V100`, `.fseventsd`, and `__MACOSX` are skipped during scanning.
- Build output, archives, local IDE metadata, and app distribution artifacts are ignored by Git.

## Distribution Builds

Run `bash script/build-release.sh preview --version 0.1.1 --build 20260930` to test, archive, package and inspect an unsigned internal DMG. Run `bash script/build-release.sh check` to inspect signing prerequisites. See [distribution/RELEASE.md](distribution/RELEASE.md) for the signed candidate procedure and saved-package verification.

The GitHub validation workflow uses the same preview process. A local build does not prove remote CI or commercial acceptance. Developer ID credentials, Sparkle updates, licensing and the full product acceptance matrix remain required.

## GitHub

The local repository is connected to:

```text
origin  https://github.com/wngair/Xcode--for-Macos--DIT-apps.git
```

The GitHub repository is private. Push the current branch with:

```bash
git push
```
