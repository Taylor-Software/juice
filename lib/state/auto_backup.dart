import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'providers.dart';

/// Rolling on-disk backup writer: `backups/<sessionId>.juice.<ext>` under the
/// app-support directory, keeping two rotations (`.1`, `.2`). Pure file
/// mechanics — injectable directory for tests.
class AutoBackupWriter {
  AutoBackupWriter(this.dir);
  final Directory dir;

  Future<String> write(String sessionId, List<int> bytes, String ext) async {
    await dir.create(recursive: true);
    final base = '${dir.path}/$sessionId.juice.$ext';
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
    } catch (_) {
      // Unavailable platform (web / tests without path_provider) or a full
      // disk — a silent safety net never surfaces errors.
    } finally {
      _running = false;
    }
  }
}

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
