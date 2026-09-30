# Support diagnostics

Airwang DIT can save a local JSON diagnostic file from **Settings → Support and Diagnostics → Export Diagnostics**. The same command is available in the **Help** menu. Chinese labels are **设置 → 支持与诊断 → 导出诊断**.

The export is optional and starts only after you choose where to save it. Review the JSON before sharing it with a support person through a channel you have agreed on. The app does not upload this file. No support mailbox, crash reporting endpoint, or ticket service is configured by this feature.

## Included information

- App version, build number, bundle ID, and development build indicators.
- For packages built by the distribution script, the Git revision, build input SHA-256, and whether the build used a committed or modified working tree. Ordinary Xcode builds without these fields report `unknown`.
- macOS version, executable architecture, processor count, and memory capacity.
- Language, theme, execution and verification modes, active work flags, unsaved state, and a coarse error category.
- Aggregate project status and copy/verification stage counts, backup configuration counts, and recovery counts.
- Aggregate report outcomes and failure counts. At most 25 recent reports are sampled, with ordinal references and completion times. Totals still include all loaded reports.

## Excluded information

The file does not contain media content, filenames, paths, project or report UUIDs, source or target device identifiers, checksums of media, raw error messages, original report documents, or environment variable values. Export collects an allow-list of fields from the in-memory app state; it does not scan media or gather system logs.

Task counts and completion times can still reveal how the app was used. Users can inspect the JSON and decide whether to share it.

## Saving and cancellation

Choose a new `.json` filename in an existing writable folder. The default name contains a UTC timestamp and a random suffix. Existing files are preserved, including if the macOS save dialog offers a replacement confirmation. An existing name results in an error asking you to choose a new one. Symbolic links are refused.

On a local macOS filesystem the output has owner read/write permissions (`0600`). Filesystems that cannot provide the required write or permission behavior can return an export error. Publication is exclusive, so competing exports cannot replace each other's file.

Cancel the save dialog to exit before export starts. While an export is running, Settings provides **Cancel Export**. Cancellation is checked before writing and before publication. If publication already finished, the successful output remains. Quitting is deferred while the app finishes an active export; cancel and wait for the result before trying again.

## Reporting a problem

Include the app version, expected result, steps that reproduce the problem, and whether the source, target, or backup was disconnected. If the issue occurred earlier, say when it happened and which workflow stage was affected. The JSON is a snapshot taken at export time and is not a historical crash trace.

Keep original media and original task reports available locally. Share only the information needed for the case. Source filenames and full raw error text are excluded automatically and cannot be recovered from the diagnostic file.

## Scope of this release

Local export and build identification are implemented. Automatic crash reporting, a receiving backend, customer ticketing, and a verified support contact remain separate distribution requirements. Verification evidence is recorded in [SUPPORT_DIAGNOSTICS_VERIFICATION_2026-09-30.md](SUPPORT_DIAGNOSTICS_VERIFICATION_2026-09-30.md).
