# Paper workbench checkpoint

The selected concept is the third revised image: top secondary navigation, the five existing bottom navigation items, a source/storage/verification form, and a live task rail. The implementation is native SwiftUI. No web prototype or production media is involved.

The new appearance uses a matte warm palette, system sans-serif controls, tabular numbers and restrained SF Symbols. Day/night and Chinese/English settings remain available. Appearance can be switched to Classic from the header settings menu or the existing Settings window; the original layout and glass components remain in that path.

All existing verification choices, sequential/parallel execution, auto-start settings, queue editing, retry, independent backup recovery, media selection modes, folder browsing, organization, statistics, diagnostics and TXT/PDF actions are retained. The primary new-workbench button opens the existing media-selection sheet; files must be confirmed before a task is added. No whole-volume import is silently performed.

Active development branch: `codex/dit-paper-workbench`. The validated cleanup and performance work from `codex/dit-m1-m3-safety` has been integrated while retaining the paper layout and Classic option. Continue development and ablation experiments here; the safety branch remains a rollback checkpoint.

Validation on 2026-10-08: 155 existing unit tests passed through the no-window library harness, with zero failures and zero skips. Native application and test targets compiled with `build-for-testing`; the native Release build also passed. The harness stages all Swift source and tests and omits only the application's entry declaration, which native compilation checks separately. See `PAPER_ABLATION_2026-10-08.md` for the paper-specific controlled experiment. The four earlier UI tests failed before accessibility-container corrections; no post-correction UI test is claimed. See `design-qa.md` for the pending visual acceptance.

Foreground UI testing interfered with the user's computer use. **Do not launch or activate applications, run UI tests, drive mouse/keyboard actions, resize windows, or open preview panels for this work until the user explicitly authorizes foreground interaction.** Continue background source editing, low-priority compilation and checks that create no application windows.

The default scheme continues to exclude UI tests. The separate `Airwang DIT UI Validation` scheme is present for an explicitly authorized future test run; creating this scheme does not authorize running it.
