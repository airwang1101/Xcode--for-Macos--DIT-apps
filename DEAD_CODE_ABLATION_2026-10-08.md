# Dead code ablation, 2026-10-08

Three independent removals each passed the same 65 regression tests with zero
failures and zero skips. The cleanup has a net reduction of 274 production lines.
Final integrated workspace: 152 unit tests passed, zero failures and zero skips.
The final Release arm64 build and 17 release-tool tests passed. Swift input
hashes were checked against the completed regression run before submission.

## Controlled experiment

Baseline production source: `289f18f438f33333e444b3b7cc1fd61fddc39087`.
The isolated temporary project contained that source and the three regression
tests added by this cleanup. Each variant started from the same baseline;
removals were tested separately. The selected tests and build settings were
identical across all four controlled runs.

| Variant | Removal | Net lines removed | Passed | Failed | Skipped |
| --- | --- | ---: | ---: | ---: | ---: |
| Control | None | 0 | 65 | 0 | 0 |
| A | Unreachable single-import ViewModel workflow and its private state/helpers | 240 | 65 | 0 | 0 |
| B | Five unreferenced computed properties | 27 | 65 | 0 | 0 |
| C | Unread scanner metadata key and unused private shadow fields | 7 | 65 | 0 | 0 |

The original full unit suite also passed: 144 tests, zero failures and zero skips.
Release-tool tests passed: 17 tests. The initial sandboxed Xcode run failed on
SwiftUI compiler macros and test notifications. The completed runs used the same
local Xcode installation outside that sandbox.

Environment: arm64, macOS 27.2 (26B5101f), Xcode 27.0 (27A266a), Debug,
serial test execution, signing disabled. This experiment verifies reachability
and behavior preservation; it does not establish a runtime performance gain.

## Removed code and preserved behavior

The import sheet calls `startImport()`, which creates and persists a queued
`CopyProject`. The private `startImport(with:)` overload had no callers.
`cancelImport()` and `retryLatestFailedItems()` also had no callers in application
or test source. Their legacy state, retry-item reconstruction helpers, and the
unmount handler's unreachable legacy tail were removed together. Queue execution,
per-project cancellation, full retry, independent backup retry, and the existing
transfer service remain in place.

The unused properties were `selectedSourceCapacity`, `usageFraction`,
`shortAvailableText`, `copyFraction`, and `verificationFraction`. They were
computed properties; persisted fields and schemas were retained.

The scanner no longer requests `.typeIdentifierKey`, which had no reader.
Extension classification and sidecar rules are retained. The private shadow
modifier no longer stores or receives unused tint arguments. Its drawing formulas
and the public `airwangSoftShadow` parameter list are unchanged. UI workspace
source, existing options, formatter caches, thumbnail caches, and progress
coalescing were retained. Framework callbacks were excluded from the removal
candidates even when they had no explicit source call sites.

Three added tests cover import selection and persistence across all four
verification modes and both automatic-start settings, queued cancellation followed
by a complete retry, and scanner filtering with sidecars and metadata. Test paths
are compared after resolving macOS filesystem aliases. Transfer tests use
synthetic files and temporary disk images.

## Workspace integration and evidence

Concurrent selection-cache and statistics changes, their five additional tests,
and their separate report were preserved. Those changes were excluded from the
controlled variants and included in the final workspace regression.

Evidence is retained locally in
[`artifacts/ablation-2026-10-08/dead-code-cleanup`](artifacts/ablation-2026-10-08/dead-code-cleanup).
It contains test logs, `.xcresult` bundles, structured result summaries, the four
source snapshots immediately before applying this cleanup, and
`workspace-cleanup.patch`, which contains only this cleanup's production changes.
`final-input-hashes.json` records every Swift input to the final workspace test.
A compact `../review-evidence.json` is included in the PR. Raw logs and result
bundles remain local under the repository's existing ignore policy.

To reproduce the complete unit regression:

```sh
xcodebuild test \
  -project 'Airwang DIT for Mac.xcodeproj' \
  -scheme 'Airwang DIT for Mac' \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/airwang-dit-cleanup-review \
  -only-testing:'Airwang DIT for MacTests' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

The three variants use the same selected test classes: `ModelPolicyTests`,
`PersistenceCompatibilityTests`, `MediaScannerTests`, `ReportPDFExporterTests`,
and four queue tests in `TransferServiceTests`. Their exact invocation is retained
at the start of each variant log. Check `git apply --reverse --check` against the
saved cleanup patch before using it for a later rollback.

Native UI automation and physical-media acceptance were outside this cleanup.
