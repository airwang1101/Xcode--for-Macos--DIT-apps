# Code efficiency ablation, 2026-10-08

The four controlled variants passed all nine selected tests. Reusing the import
selection snapshot removes repeated sorting and byte summation from UI reads.
Reusing the daily heatmap's week grouping reduces heatmap construction time by
approximately 36% in this Debug microbenchmark.

## Changes

- `AppViewModel.swift`: lazily cache the ordered selected items and selected byte
  count. Invalidate on either selection or scanned-item mutation. Cache the scanned
  byte count when rebuilding scan indexes. Build the import summary from one
  consistent snapshot.
- `Models.swift`: build the daily heatmap once and reuse its weeks for weekly
  totals. Reuse the already computed peak when choosing the color scale maximum.
  Consolidate the three identical active-byte and streak helper implementations
  in one private helper type.
- The measured optimization snapshot has a net reduction of 34 production
  lines. The final submission also includes the independently tested cleanup
  described in `DEAD_CODE_ABLATION_2026-10-08.md`, for a combined net reduction
  of 308 production lines. Existing scan order, sidecar grouping, empty selection,
  weekly boundaries, peak tie-breaking, verification options, persistence
  schemas, and UI appearance are preserved.

The selection cache retains one selected-item array until either input changes.
The first read after invalidation still performs the existing selection sort.

## Experiment

Baseline production source: `289f18f438f33333e444b3b7cc1fd61fddc39087`, branch
`codex/dit-m1-m3-safety`. The experiment ran in a separate temporary project copy,
with the same tests and settings in every variant. Tests ran serially within each
variant. The machine was also running the full regression suite during part of
the experiment, so smaller differences should be treated as noise.

Environment: arm64 MacBook Pro, macOS 27.2 (26B5101f), Xcode 27.0 (27A266a),
Debug configuration, five measured iterations per metric. All times below are
arithmetic means from XCTest's monotonic clock metric.

| Variant | Selection reads, ms | 300 heatmap builds, ms | Full statistics build, ms | Selected tests |
| --- | ---: | ---: | ---: | --- |
| Original | 4993.748545 | 283.852282 | 27.837335 | 9 passed |
| Selection cache only | 0.007142 | 279.595441 | 27.743954 | 9 passed |
| Heatmap reuse and shared helpers only | 4745.019101 | 182.364646 | 26.540054 | 9 passed |
| Both changes | 0.005699 | 181.885545 | 27.078565 | 9 passed |

Selection workload: 10,000 scanned and selected files, then 30 rounds reading
selected-item count, selected bytes, and scanned bytes. A read before measurement
warms the snapshot. These numbers describe repeated reads of an unchanged
selection; they exclude scan time, selection mutation, first-read cost, and
filesystem operations.

Heatmap workload: 365 days derived from 10,000 reports spanning 730 days, with
300 daily/weekly/cumulative heatmap builds per iteration. The combined variant
reduces this workload's mean time by 35.92%.

Full statistics workload: rebuild the index for 10,000 reports, create a 365-day
summary, and build all heatmaps. Its small timing variation does not establish a
material end-to-end improvement. The cached 30,000 mode-lookups benchmark stayed
around 1.5 to 1.6 ms across the four variants.

## Behavior checks

Five tests added by this pass cover selection invalidation and order, byte totals,
Unicode and case-insensitive sidecar relationships, import summary consistency,
partial weeks, cumulative counts, empty/inactive heatmaps, and the two isolated
performance workloads. Existing large-history summary parity and mode-switch
tests also passed in every variant.

The original full unit suite passed: 144 tests, zero failures, zero skips.
The measured optimization snapshot passed 152 unit tests with zero failures
and zero skips. After integration with the dead-code cleanup, the final
submission passed another complete run of 152 unit tests with zero failures
and zero skips. Final Swift input hashes match the tested snapshot.
Release arm64 build passed with signing disabled for the final submission.
Release-tool tests passed: 17 tests. `git diff --check` passed.

Concurrent edits to `MediaScannerTests.swift` and `TransferServiceTests.swift`
were preserved. They are included in the final workspace regression and are
outside the selected ablation test classes.

## Evidence and reproduction

Raw five-iteration measurements, summaries, logs, baseline source snapshots,
optimized source snapshots, and exact independent patches are retained under
[`artifacts/ablation-2026-10-08`](artifacts/ablation-2026-10-08).
A compact `review-evidence.json` is included in the PR. Raw logs, complete
result bundles, and reproduction snapshots remain local under the repository's
existing ignore policy.

For each variant, use the recorded baseline or optimized snapshot for each of the
two production files, retaining the current selected test files. Run:

```sh
xcodebuild test \
  -project 'Airwang DIT for Mac.xcodeproj' \
  -scheme 'Airwang DIT for Mac' \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/airwang-dit-ablation-reproduction \
  -resultBundlePath /tmp/airwang-dit-ablation-reproduction.xcresult \
  -only-testing:'Airwang DIT for MacTests/ImportSelectionTests' \
  -only-testing:'Airwang DIT for MacTests/StatisticsPerformanceTests' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Use a fresh result bundle path per run. Export the measurements with:

```sh
xcrun xcresulttool get test-results metrics \
  --path /tmp/airwang-dit-ablation-reproduction.xcresult --compact
```

The measurements establish local model and repeated-read improvements. Rendered
UI frame time, Release-mode runtime performance, physical-media throughput, and
new installation behavior were outside this experiment.
