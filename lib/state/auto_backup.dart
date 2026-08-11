import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'providers.dart';

/// Rolling on-disk backup writer: `backups/<sessionId>.loreseer.<ext>` under the
/// app-support directory, keeping two rotations (`.1`, `.2`). Pure file
/// mechanics — injectable directory for tests.
class AutoBackupWriter {
  AutoBackupWriter(this.dir);
  final Directory dir;

  Future<String> write(String sessionId, List<int> bytes, String ext) async {
    await dir.create(recursive: true);
    final base = '${dir.path}/$sessionId.loreseer.$ext';
    final f = File(base);
    if (await f.exists()) {
      final r1 = File('$base.1');
      if (await r1.exists()) await r1.rename('$base.2');
      await f.rename('$base.1');
    }
    await File(base).writeAsBytes(bytes, flush: true);
    return base;
  }
}

/// Silent desktop/mobile safety net: after journal changes (at most once per
/// [minInterval]) the active campaign is exported to the rolling backup and
/// the last-export stamp updated, so the launcher backup nudge quiets down.
/// No timers (test-safe); unavailable platforms (web, unmocked path_provider)
/// fail silently.
class AutoBackupController {
  AutoBackupController(this.ref, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final Ref ref;
  final DateTime Function() _now;

  static const minInterval = Duration(minutes: 5);
  DateTime? _lastRun;
  bool _running = false;

  /// Last successful backup path (null until one lands); test/debug hook.
  String? lastPath;

  Future<void> maybeBackup({bool force = false}) async {
    if (kIsWeb || _running) return;
    final now = _now();
    if (!force && _lastRun != null && now.difference(_lastRun!) < minInterval) {
      return;
    }
    _running = true;
    try {
      final file = await ref.read(sessionsProvider.notifier).exportActiveFile();
      final support = await getApplicationSupportDirectory();
      final writer = AutoBackupWriter(Directory('${support.path}/backups'));
      final active =
          ref.read(sessionsProvider).valueOrNull?.active ?? 'campaign';
      lastPath = await writer.write(active, file.bytes, file.ext);
      _lastRun = now;
      await ref.read(lastExportProvider.notifier).stamp();
      _report(null);
    } on MissingPluginException {
      // No path_provider: web, or a widget test that didn't mock it. Expected,
      // not a fault — stay quiet.
    } on UnsupportedError {
      // Platform has no app-support directory. Also expected.
    } catch (e) {
      // A REAL fault: a full disk, a revoked directory permission, a corrupt
      // export. This used to be swallowed with everything else, so the one
      // feature whose whole job is data safety could fail forever in silence.
      // The 7-day export nudge is not a substitute — it says "back up soon",
      // not "your backups are broken".
      _report(e.toString());
    } finally {
      _running = false;
    }
  }

  /// Publishes backup health so the UI can watch it. Writes only on a change,
  /// so a healthy backup every five minutes doesn't churn listeners.
  void _report(String? error) {
    final notifier = ref.read(autoBackupErrorProvider.notifier);
    if (notifier.state != error) notifier.state = error;
  }
}

/// The last real auto-backup failure, or null when backups are healthy.
///
/// Null on web and wherever path_provider is absent — those are not failures.
/// Watched by the Settings sheet so a silently-dead safety net becomes
/// visible without the user having to go looking for a backup file.
final autoBackupErrorProvider = StateProvider<String?>((ref) => null);

/// Activate by watching this once (the home shell does): journal changes
/// trigger a rate-limited backup of the active campaign.
final autoBackupProvider = Provider<AutoBackupController>((ref) {
  final controller = AutoBackupController(ref);
  ref.listen(journalProvider, (prev, next) {
    // Only on real data changes (skip loading frames).
    if (next.hasValue && prev?.valueOrNull != next.valueOrNull) {
      controller.maybeBackup();
    }
  });
  return controller;
});
