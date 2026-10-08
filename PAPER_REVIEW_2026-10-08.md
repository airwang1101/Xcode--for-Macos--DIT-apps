# Paper workbench review, 2026-10-08

No blocking defect was found in the reviewed integration changes. This conclusion
covers the changed source and the recorded regression evidence. Rendered UI,
physical-media operation and commercial distribution require separate acceptance.

## Review scope and checks

The production diff against paper commit `fccf3a5` changes four files:
AppViewModel.swift, Models.swift, MediaScanner.swift and AirwangComponents.swift.
The merged source was independently reconstructed from the original paper source
and the three experiment groups; every resulting Swift file matched.

- The legacy ViewModel import overload was private and had no callers. Import-sheet
  confirmation continues to create a persisted CopyProject. Queue cancellation,
  full retry, backup-only retry and the active-operation quit guard remain connected.
- Both selection inputs invalidate the cached snapshot. AppViewModel is isolated
  to MainActor; the snapshot keeps the existing scan order and sidecar behavior.
- The extracted statistics calculations retain their existing conditions. Reused
  daily week grouping has the same input calendar and days. The maximum-byte value
  comes from the already computed maximum day before the active-day display filter.
- Removed model properties were computed; persisted schemas and stored fields are
  retained. Compatibility tests continue to cover migration and protected writes.
- Scanner classification retains its metadata and extension rules. Shadow changes
  retain the public helper parameters, rendering formulas and paper gating.
- Paper navigation, forms, the Classic layout, settings and the application entry
  file remain unchanged from the paper checkpoint. Settings tests preserve language,
  theme and automatic-start preferences across appearance changes.

Evidence: 155 full unit tests passed, zero failures and zero skips; all five
controlled variants passed the same 77 tests; three two-test benchmark reruns
passed. Native Debug application/test compilation, Release compilation and 17
release-tool tests passed. See [paper experiment](PAPER_ABLATION_2026-10-08.md).

The initial no-window harness used a different temporary storage directory than
the native scheme. Its isolated-storage assertion failed. The harness environment
was corrected, and the complete suite passed with application code/tests retained.

## Current product assessment

The existing implementation supports a substantial local DIT workflow: device and
folder sources, media/sidecar selection, four browsing modes, named project queues,
sequential/parallel execution, primary copy, verification, backup from primary,
interruption recovery, full and independent-backup retry, organization, statistics,
TXT/PDF reports and local diagnostic export. Verification modes remain SHA-256,
fast fingerprint, size-only and skipped verification.

The paper workbench supplies a new native interface over those workflows, with
top secondary navigation and the five original bottom destinations. Classic,
Chinese/English, day/night and automatic-start options remain available. A first
launch without a saved destination still uses the retained setup workflow.

Current limitations relevant to trying the app:

- Post-correction visual, interaction, accessibility and narrow-window acceptance
  remains pending. No foreground app or UI tests were run during this work.
- Synthetic-file and temporary-volume tests cover important failure paths. Actual
  camera cards, readers, APFS/exFAT devices, long transfers and power-loss handling
  still need measured acceptance on real hardware.
- Local Debug benchmark results improve repeated selection reads and heatmap work.
  Some samples show substantial variance. These measurements establish no physical
  copy-throughput or end-to-end UI latency guarantee.
- AppViewModel has 2,583 lines, TransferService 3,272, and Models 2,549. Their broad
  responsibilities increase future review effort. Further structural work should
  preserve behavior and proceed through small, separately tested changes.
- The source currently has no xxhash, MHL or Sparkle integration. Developer ID
  signing/notarization, update delivery and commercial acceptance remain separate
  requirements in [the readiness ledger](DISTRIBUTION_READINESS.md). Historical
  coverage percentages in that ledger were not remeasured by this experiment.

## Trial delivery and next acceptance

The requested local trial is version 0.1.1, Build 2026100801, for Apple Silicon,
requiring macOS 14 or later. It is built from a saved Git checkpoint, packaged
under the ignored Dist directory, and locally ad-hoc signed. It has no Developer
ID notarization. The package manifest records the actual source revision, input
fingerprint, architectures, archive checksum and verification evidence.

The trial keeps the existing bundle identifier and normal saved preferences.
Previous packages remain intact. Its .app can be tried directly; the ZIP preserves
the bundle for storage or transfer. Package verification checks the executable,
metadata, signature and a fresh ZIP extraction without launching the application.

For the first hands-on pass, use copied test media and separate source, primary
and backup locations. Check appearance switching, all five navigation entries,
selection/sidecars, queue confirmation, SHA-256 copy and backup, cancellation/retry,
TXT/PDF export and reopening saved history. Record source/target sizes and hashes,
elapsed time, device models and filesystem types before broad real-media use.
