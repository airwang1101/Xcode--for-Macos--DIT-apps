# IO ablation evidence, 2026-10-10

The final implementation preserves the existing UI, onboarding, verification policies,
and persistence schema. See [the report](../../IO_ABLATION_2026-10-10.md).

Published evidence:

- `measurements/*.json`: every raw timing sample from serial Debug candidates and Release repeats, including slower results.
- `median-summary.json`: medians derived from those raw samples.
- `line-counts.json`: before/after line counts for the four production and two regression files changed by the IO work.
- `final-integrity-check.json`: 33 application files unchanged relative to the pre-IO baseline and tested-source hash consistency at packaging.
- `removed-transfer-declarations.json`: exact old declarations or overloads removed from the unreachable import path.

These are synthetic warm-cache measurements on one Mac. Temporary disk-image
volumes share the same physical internal storage. Physical-card, reader and
external-drive acceptance remains pending. Test logs, source staging directories,
fixtures and packaged application bundles remain local and ignored; links in the
report to those paths describe retained local evidence, not public downloads.

The source before onboarding and IO cleanup is preserved by the
`backup/pre-onboarding-io-20261011` tag. The onboarding was already present in the
local pre-IO baseline, so this tag is an earlier source checkpoint than the IO
experiment's control snapshot.
