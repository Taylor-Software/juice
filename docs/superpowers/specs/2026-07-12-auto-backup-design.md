# Silent local auto-backup — design

**Date:** 2026-07-12
**Source:** QoL assessment #10 — the backup nudge exists, but on desktop the
app can simply make the backup itself.

## Design

`lib/state/auto_backup.dart`:

- **Writer:** `AutoBackupWriter(dir).write(sessionId, bytes, ext)` — rolling
  `backups/<sessionId>.juice.<ext>` under the app-support directory with two
  rotations (`.1`, `.2`). Injectable directory for tests.
- **Controller:** `AutoBackupController.maybeBackup()` — exports the active
  campaign via the existing `exportActiveFile()` seam, at most once per 5
  minutes, **no timers** (rate-limit by timestamp, so widget tests never leak
  pending timers). On success it stamps `lastExportProvider`, so the launcher
  backup nudge quiets down. All failures (web, tests without a path_provider
  mock, full disk) are silently swallowed — a safety net never surfaces
  errors.
- **Activation:** `autoBackupProvider` listens to `journalProvider` data
  changes; the home shell watches it once. Trailing edits inside the rate
  window are captured by the next change; the manual export path is
  unchanged.

## Tests

`test/auto_backup_test.dart`: writer creation + 2-generation rotation.
Existing `backup_nudge_test.dart` still green (stamp semantics unchanged).
