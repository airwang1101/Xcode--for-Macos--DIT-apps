# Independent backup retry evidence

The selected JSON summaries contain no media or device identifiers. Full test results, archive logs, coverage, the app and DMG remain in `Dist/preview-0.1.1-2026093003-v9xm83y1/`. Earlier failed attempts and a short runner sample remain locally under `raw/`.

`quality-summary.json` records 132 passing unit tests, the 14 new backup/migration cases, and 17 release-tool tests. The two existing UI tests were excluded. The attempted manual fixture never loaded into the observed app, so it provides no UI acceptance evidence. No screenshots are claimed for this feature.

The package preserves its original working-tree provenance. A later Git commit does not rewrite its manifest. Physical card/power faults, Intel/macOS 14 runtime, signing/notarization, and commercial acceptance remain unverified.
