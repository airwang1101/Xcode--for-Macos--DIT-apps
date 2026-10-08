# Paper workbench ablation, 2026-10-08

`codex/dit-paper-workbench` is the active development branch. The paper appearance
remains the default, and Classic remains selectable. The safety branch is retained
as a rollback checkpoint. Existing branch history is preserved by merging.

The integrated paper source passed 155 no-window unit tests with zero failures and
zero skips. Native Debug application/test compilation, native Release compilation,
and all 17 release-tool tests passed. Each of five paper-specific variants passed
the same 77 regression tests. Three additional performance-only reruns passed.

## Controlled paper experiment

Paper baseline: `fccf3a59141782ec53140bfc1e8e41f9da3ddc4a`.
Imported safety changes: `fb0a1e362d7e29d9606e0e67767f7d208b12b75d`.
All variants start from the paper baseline and use identical current test files.
The selection and heatmap groups are applied independently; the cleanup group
contains the three previously audited removals together. The combined source was
independently checked to equal the original paper source plus these three groups.

Environment: arm64, macOS 27.2 (26B5101f), Xcode 27.0 (27A266a), Swift 6 Debug,
macOS 14 deployment target. Runs are serial, with five measured iterations per
performance test. Compilation and the complete regression finish before controlled
measurements. Build time is excluded from the workload metrics below.

| Paper variant | Selection reads, ms | 300 heatmap builds, ms | Complete statistics build, ms | Passed / failed / skipped |
| --- | ---: | ---: | ---: | ---: |
| Original paper control | 5133.5980 | 281.514 | 28.852 | 77 / 0 / 0 |
| Selection snapshot only | 0.0108 | 279.199 | 27.937 | 77 / 0 / 0 |
| Heatmap reuse and shared helpers only | 5533.7240 | 193.509 | 27.895 | 77 / 0 / 0 |
| Dead code cleanup only | 5905.3686 | 638.135 | 114.364 | 77 / 0 / 0 |
| All three groups | 0.0114 | 241.335 | 29.509 | 77 / 0 / 0 |

Later control, combined and cleanup runs check timing drift with the same two benchmarks:

| Rerun | Selection reads, ms | 300 heatmap builds, ms | Passed / failed / skipped |
| --- | ---: | ---: | ---: |
| control-repeat | 5897.3570 | 286.870 | 2 / 0 / 0 |
| combined-repeat | 0.0166 | 187.182 | 2 / 0 / 0 |
| cleanup-repeat | 5071.5210 | 274.729 | 2 / 0 / 0 |

Across both control/combined runs, mean heatmap construction time fell by
24.61%. Selection reads reuse the cached array and byte counts when inputs
are unchanged. These are local Debug microbenchmarks; they do not measure media
copy throughput, application startup, visual responsiveness or Release speed.
The first cleanup-only run shows substantial timing noise, including an 8.75-second
selection sample and heatmap samples ranging from 0.276 to 0.898 seconds. Its
performance-only rerun is reported separately. The cleanup is retained on source
reachability and passing regression evidence; no speed gain is attributed to it.
The complete statistics workload does not establish a comparable overall gain.
The initial combined heatmap mean (241.335 ms) also differs substantially from
its repeat (187.182 ms). The pooled 24.61% reduction is an observation across
these local samples, with visible run-to-run noise; it is not a fixed speedup
claim. All samples are retained, including the slow observations.

Selection workload: 10,000 scanned and selected files, followed by 30 rounds of
reading the selected count, selected bytes and scanned bytes. The premeasurement
read warms the selection snapshot. Scanning, mutation and the first read after
invalidation are excluded. Separate tests check invalidation, ordering, sidecars
and selection-summary consistency.

Heatmap workload: 10,000 synthetic reports distributed over 730 days, a 365-day
summary, and 300 daily/weekly/cumulative heatmap builds per measured iteration.
Partial weeks, cumulative counts, empty/inactive inputs, calendar behavior and
full-summary/index agreement retain regression coverage.

The common 77 tests comprise ModelPolicyTests (12), ImportSelectionTests (3),
StatisticsPerformanceTests (6), MediaScannerTests (2), PersistenceCompatibilityTests
(38), ReportPDFExporterTests (12), and four TransferServiceTests covering import
selection persistence, queued cancellation/full retry and independent backup
recovery after reload or failed preflight.

## Retained behavior and UI

The paper layout, top secondary navigation, original five bottom entries, source
selector, import sheet, Classic layout and application entry file match the paper
baseline byte for byte. Only four production files change: AppViewModel.swift,
Models.swift, MediaScanner.swift and AirwangComponents.swift. The latter removes
unused private shadow arguments while retaining paper appearance gating, drawing
formulas and the public helper signature.

Dead code cleanup removes a net 274 production lines. It removes the uncalled
single-import ViewModel path, its private state/helpers, five unreferenced computed
properties, an unread scanner metadata request and unused private shadow fields.
Queue actions, per-project cancellation, retry, independent backup recovery,
verification choices and persisted schemas remain. Performance work additionally
reuses selection snapshots and daily week grouping and shares existing statistics
calculations. The combined change removes a net 308 production lines.

The paper-specific settings tests verify legacy adoption of Paper, Classic
round-tripping, and preserving language, theme and automatic-start settings when
changing appearance. No foreground application launch, mouse/keyboard operation,
UI automation or screenshot was performed. Visual and interaction acceptance in
`design-qa.md` remains pending.

## Background validation and evidence

The staged library harness copies every Swift source and test. It omits only the
`@main AirwangDITForMacApp` declaration so the test executable creates no SwiftUI
application scene. All other Swift input bytes are retained and hashed. Native
Xcode compilation separately validates the complete application entry and assets.
The full no-window regression passed in 133.381 seconds; its performance samples
are excluded from the controlled comparison.

The initial harness run had one failure because its app-support directory differed
from the native test scheme's fixed `/tmp/airwang-dit-unit-tests` expectation.
The harness was corrected to match that environment. The complete 155-test rerun
passed without changing production code or existing tests. The initial log is
retained locally.

Run the background regression with:

```sh
python3 script/headless_tests.py
```

Native compilation uses `xcodebuild build-for-testing` for Debug and
`xcodebuild build` for Release, with signing disabled and the arm64 macOS
destination. Neither command executes tests or launches an application window.

Compact source hashes, raw-log hashes, all measured samples, test counts and
preservation checks are tracked in
[review-evidence.json](artifacts/paper-ablation-2026-10-08/review-evidence.json).
Raw logs, five exact source/test snapshots, group patches and the serial experiment
runner remain local in `artifacts/paper-ablation-2026-10-08` under the repository's
existing ignore policy. Previous safety-branch reports remain historical evidence
and are linked separately from this paper-specific result.
