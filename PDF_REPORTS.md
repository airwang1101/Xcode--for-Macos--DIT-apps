# PDF report export

In the task log, choose **Export PDF Report** for a report, choose a new filename, and save. The original **View Copy Report** action continues to open the existing TXT report. The export status appears on the same report card and offers cancellation while rendering is in progress.

The PDF is a paginated copy of the original UTF-8 TXT report, including the original file names, verification modes, checksums, exceptions, recovery records and warnings that the TXT contains. It does not recompute checksums or change a task's verification status. Its content follows the language of that saved TXT report; changing the UI language does not translate historical evidence.

The destination report is used when available, with the existing local-report fallback when the destination report is missing. If neither original TXT exists, export stops. Compact report history is not used to reconstruct evidence, because it deliberately omits successful per-file checksums.

The renderer writes A4 pages in a background task, wraps long text, adds a repeated header and page number, and checks cancellation between pages. Closing the application is blocked while an export is active. Source TXT files are opened without following a final symlink and checked for changes during the read. Invalid UTF-8, empty reports and non-regular files stop the export.

PDFs are staged, synchronized, and published with an exclusive rename. Existing files, directory collisions and symbolic links are preserved, including when a save dialog's replacement prompt was accepted. Choose a new name after a conflict. Local output permissions are `0600`. Cancelled or failed exports do not publish a staged report; a cancellation arriving after successful publication is reported as success.

The PDF includes the names and paths present in the original TXT. It remains local unless the user shares it. The existing support-diagnostics exporter retains its separate redacted format.

## Verification

`ReportPDFExporterTests` checks complete multi-page Unicode and hash extraction, existing output preservation, symlink protection, missing and invalid sources, invalid destinations, cancellation, concurrent publication, application exit protection and retry after an export failure. Rendering samples use synthetic records.

Native save-dialog interaction and visual layout in the application remain separate acceptance tasks. Automated PDF tests and rendered document inspection do not establish that UI acceptance. Body text includes logical replacement text to preserve the original order when readers extract wrapped hash suffixes. Full PDF accessibility acceptance, operator signatures and company-logo templates remain pending.

The logical replacement text uses Apple's [Core Graphics ActualText property](https://developer.apple.com/documentation/coregraphics/cgpdftagproperty/actualtext).
