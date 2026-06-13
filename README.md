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

## Verification Modes

- `sha256`: hashes source data during copy, then verifies destination data.
- `size`: compares copied file size against the source file size.
- `skip`: records the skipped verification state in the task flow and report.

## Safety Notes

- Primary target and backup target should be separate volumes.
- Source folders, primary targets, and backup targets cannot overlap.
- Symbolic link paths are rejected for writable and existing file targets.
- Hidden system folders such as `.Trashes`, `.Spotlight-V100`, `.fseventsd`, and `__MACOSX` are skipped during scanning.
- Build output, archives, local IDE metadata, and app distribution artifacts are ignored by Git.

## GitHub

The local repository is connected to:

```text
origin  https://github.com/wngair/Xcode--for-Macos--DIT-apps.git
```

The GitHub repository is private. Push the current branch with:

```bash
git push
```
