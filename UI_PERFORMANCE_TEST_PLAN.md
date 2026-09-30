# UI Performance Test Plan

## Scope

This plan starts with the Statistics section because it has the highest current risk for UI stutter and layout jumps. It now also covers the shared dashboard shell, bottom navigation, floating header, and Organizer statistics card.

## Automated Gates

1. Run the Statistics model stress tests.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project "Airwang DIT for Mac.xcodeproj" \
  -scheme "Airwang DIT for Mac" \
  -destination "platform=macOS" \
  -only-testing:"Airwang DIT for MacTests/StatisticsPerformanceTests"
```

2. Run the Organizer model tests when changing Organizer data shown in Statistics.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project "Airwang DIT for Mac.xcodeproj" \
  -scheme "Airwang DIT for Mac" \
  -destination "platform=macOS" \
  -only-testing:"Airwang DIT for MacTests/OrganizerServiceTests"
```

3. Run the full XCTest suite before marking a UI performance change ready.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project "Airwang DIT for Mac.xcodeproj" \
  -scheme "Airwang DIT for Mac" \
  -destination "platform=macOS"
```

4. Launch the app from the repo build script.

```bash
./script/build_and_run.sh --verify
```

## Opt-In UI Automation

`Airwang DIT for MacUITests` is present in the scheme but skipped by default so the normal XCTest gate stays deterministic. The tests launch the app with a temporary data directory, click the Statistics tab, and verify the layout anchors needed for future resize and jump checks.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project "Airwang DIT for Mac.xcodeproj" \
  -scheme "Airwang DIT for Mac" \
  -destination "platform=macOS" \
  -only-testing:"Airwang DIT for MacUITests/StatisticsUITests"
```

Current local blocker: `xcodebuild` launches `com.airwang.ditformac.dev` and reports it as `runningForeground`, but the XCUITest accessibility tree only exposes the menu bar and marks the application as disabled. Launching the same Debug app through LaunchServices with the same `AIRWANG_DIT_UI_TESTING` environment values does show a normal app window. Treat this as an Xcode automation or local accessibility permission issue before using these UI tests as a required gate.

## Statistics Stress Data

The seed script writes a large `import-reports.json` into the Debug app data folder, backs up existing JSON files by default, and removes `statistics-index.json` so the app rebuilds the index on launch.

Dry run:

```bash
python3 script/seed_statistics_stress_data.py --dry-run --count 10000
```

Write the default Debug app dataset:

```bash
python3 script/seed_statistics_stress_data.py --count 10000 --days 730
```

Write to a temporary directory when testing the script itself:

```bash
python3 script/seed_statistics_stress_data.py \
  --count 10000 \
  --days 730 \
  --data-dir /tmp/airwang-dit-statistics-stress
```

## Manual UI Matrix

Use the same seeded dataset for every manual pass.

1. Open the Statistics section at `1280x820`.
2. Sweep the pointer continuously over the heatmap for 20 seconds.
3. Switch activity modes in this order: daily, weekly, cumulative, daily.
4. Press refresh 10 times at normal clicking speed.
5. Resize the window through these sizes: `1280x820`, `900x820`, `760x820`, `680x900`, `1280x820`.
6. In the narrow layout, horizontally scroll the heatmap from start to end and back.
7. Leave the pointer on a heatmap cell, then resize the window across the portrait breakpoint.
8. Switch away from Statistics and return to Statistics three times.
9. Visit Copy, Dashboard, Backup, Organizer, and Statistics at each window size.
10. In every section, use a trackpad or mouse wheel from the center of the content area and confirm the page scrolls consistently.
11. In cards with bounded lists, such as task queue, detected devices, recent reports, Organizer preview, and logs, confirm the inner list scrolls only when the pointer is inside that list.
12. Confirm the floating header stays above content while scrolling and never covers the first visible card.
13. Confirm the bottom tab row stays above content while scrolling and never covers the final visible card.
14. On macOS 26 or newer, confirm the bottom tab buttons use system glass styling. On older macOS, confirm the fallback material remains visually consistent.
15. Generate an Organizer preview and return to Statistics. Confirm the Organizer data card shows preview files, executable files, date/device count, planned bytes, and duplicate handling.
16. Execute an Organizer run and return to Statistics. Confirm the same card shows the last run summary.

## Pass Criteria

1. Heatmap hover updates the focus summary without visible whole-page flicker.
2. Mode switching keeps the heatmap card stable and does not reset the entire Statistics scroll position.
3. Window resizing does not animate every Statistics card during active resize.
4. Recent reports remain bounded in height and do not push the page into repeated jumps.
5. The app remains responsive during the first launch after a 10,000 report seed.
6. The full XCTest suite and launch verification pass after the UI change.
7. Opt-in XCUITest passes on a machine where macOS automation can see app windows, or the local automation permission issue is documented with the failing `.xcresult`.
8. The top header and bottom tab bar remain visually floating while the content scrolls underneath.
9. Copy, Dashboard, Backup, Organizer, and Statistics share one primary page scroll behavior.
10. Organizer statistics appear in Statistics without changing the existing Organizer execution rules or persistence schema.

## Profiling Pass

Capture the same manual matrix in Instruments when code review or XCTest output does not explain a visible stall.

1. Use Time Profiler to check `CopyStatisticsIndex.make`, `CopyStatisticsIndex.summary`, `CopyStatisticsHeatmaps.make`, and SwiftUI view update cost.
2. Use SwiftUI profiling to check whether `ContentView.body` updates broadly during heatmap hover.
3. Record the dataset size, build configuration, OS version, app version, and exact interaction.
4. Compare the same interaction before and after the fix.

## Current Covered Risks

1. `StatisticsPerformanceTests` covers large history indexing, summary parity, heatmap cache construction, and cached mode lookup.
2. `seed_statistics_stress_data.py` gives a repeatable 10,000 report data set for manual Statistics UI testing.
3. `StatisticsUITests` covers launching the app with isolated data, entering Statistics, switching activity modes, refreshing statistics, and checking stable layout anchors once the local macOS window accessibility issue is cleared.
4. `OrganizerServiceTests.testOrganizerStatisticsSnapshotCombinesPreviewAndLastRun` covers the Organizer data snapshot used by the Statistics card.
5. The root dashboard shell uses one primary vertical scroll surface, with bounded inner lists reserved for card-local browsing.
6. The remaining gap is automated resize measurement, automated scroll-position assertions, and Instruments trace comparison.

## Jank Root-Cause Ledger (2026-07)

Diagnosis of the "scrolling and window resizing feel janky" report, with the fix
applied for each cause. Keep this list current when touching render-path code.

1. **Effect-degrade tree swap on resize (fixed).** `AirwangGlassSurface`,
   `airwangSoftShadow`, `ambientAurora`, `floatingChromeSurface`, and
   `bottomTabBar` all branched on `reduceGlassEffects`/`enabled` with `if/else`,
   so the start and the end of every window resize rebuilt every glass surface,
   shadow, and chrome bar from scratch — two guaranteed hitches per resize
   gesture, right when the user grabs the window edge. All of these now keep a
   single stable view tree and degrade through parameter values only (opacity
   to zero, blend unchanged).
2. **Per-frame live blur sampling while scrolling (fixed).** Every one of the
   ~36 on-screen `glassSurface` instances filled with `.ultraThinMaterial`
   (real-time backdrop blur). Everything inside the scroll content sits over a
   static gradient + aurora backdrop, so the blur output is visually
   indistinguishable from a translucent fill — but each visible material panel
   re-sampled and re-blurred its backdrop on every scrolled frame. Materials
   are now active only at `.floating` elevation (the header and tab-bar chrome
   that genuinely float over moving content); all in-scroll surfaces use the
   opaque-fill appearance formerly shown during resize.
3. **Verification progress published at ~6.7Hz, and per-file boundary
   publishes completely unthrottled (fixed).** Each publish re-runs the whole
   monolithic `ContentView` body. Two layers of fix: `TransferService`
   verification chunk loops now emit at most every 0.4s, and — the far bigger
   one for DIT workloads — `TransferProgressCoalescer` in `AppViewModel` now
   time-coalesces ALL progress deliveries at the MainActor sink with a
   guaranteed trailing flush. Before this, every file boundary (start, write
   confirm, finish, verify complete) published unconditionally, so copying a
   photo card at 50–300 files/sec re-ran the entire UI 200–1200 times per
   second. Terminal states are protected: every finish/cancel/failure path
   calls `cancelPending()` before writing its authoritative final state.
4. **Window configuration re-applied every SwiftUI update (fixed).**
   `MainWindowConfigurator.updateNSView` dispatched styleMask/minSize/title
   writes on every render pass — per-frame during live resize. Now configured
   once per window instance via a coordinator.
5. **Volume-identifier syscalls in the body path (fixed).**
   `displayVolumes` filtered through `PathSafety.pathsShareVolume` (filesystem
   resource lookups) on every body evaluation. Now cached and rebuilt only when
   `mountedVolumes` or `preferences` change. Note: property observers do not
   fire inside `init`, so `AppViewModel.init` must call
   `rebuildDisplayVolumesCache()` explicitly after seeding `mountedVolumes` —
   otherwise devices mounted before launch never appear until the first
   mount/unmount event.
6. **Hardcoded floating-header reserve (fixed).** The scroll content's top
   padding used constants (142/92) that had to match the real rendered header
   height by hand. The reserve now follows a `PreferenceKey` measurement, with
   the constants as first-frame fallback only.
7. **Monolithic ContentView split (fixed, 2026-07).** `ContentView.swift`
   (5321 lines) is now split into `ContentView.swift` (shell/header/tab bar),
   `ContentView+CopyWorkspace.swift`, `ContentView+OrganizeWorkspace.swift`,
   `ContentView+StatisticsWorkspace.swift`, `ImportSheet.swift`,
   `FolderPickerSheet.swift`, and `AirwangComponents.swift` (glass surfaces,
   shadows, thumbnails, shared formatters). Same view tree, faster incremental
   compiles, and per-file ownership of each workspace.
8. **Heatmap grid drawn as one Canvas (fixed, 2026-07).** The GitHub-style
   activity grid previously built 700+ SwiftUI views (53 weeks × 7 days, each
   a RoundedRectangle + stroke overlay + scaleEffect + per-cell animation);
   every hover move re-diffed all of them, and `heatmapColor` allocated two
   arrays per cell per pass. The grid and month labels are now a single
   `Canvas` draw with colors resolved once per pass, so a hover update costs
   one lightweight body evaluation plus one flat redraw.
9. **Heatmap card cut off from unrelated publishes (fixed, 2026-07).**
   `StatisticsActivityHeatmapCard` no longer observes `AppViewModel`; it takes
   narrow value inputs (summary, heatmaps, theme, language) plus an
   `onRefresh` closure, conforms to `Equatable`, and is mounted with
   `.equatable()`. Transfer-progress publishes (~2.5Hz during copies) no
   longer re-execute the heatmap body at all. This is the first landing of
   the "child view structs with narrow value inputs" plan from the old #7.
10. **Organizer plan building parallelized with progress (fixed, 2026-07).**
   Preview generation used to read ImageIO + Spotlight metadata serially for
   every file (minutes for 10k-file cards) with a static "生成中" label. Now:
   metadata reads run in a bounded task group (2–8 wide), video/audio skip
   the guaranteed-to-fail ImageIO probe, EXIF/ISO date formatters are shared
   constants, destination existence checks use one readdir per directory
   instead of one stat per file, and the UI receives throttled
   scanning/metadata/dedupe progress. Name collisions are verified by
   streaming byte comparison so content-identical files surface as "内容重复"
   (skipped) instead of silently gaining " 2" suffixes.
11. **Remaining known debt.** The copy/dashboard/backup workspaces still read
   `viewModel` directly inside `ContentView` extensions, so they re-run on
   every publish (cheap after the split, but the Statistics card pattern in
   #9 is the template if they ever feel heavy). UI-test automation blocker
   from "Opt-In UI Automation" still stands.
