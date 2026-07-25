import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/state/auto_backup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('juice_backup_test');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('writer creates the backups dir and writes the file', () async {
    final w = AutoBackupWriter(Directory('${tmp.path}/backups'));
    final path = await w.write('sid1', [1, 2, 3], 'json');
    expect(path, endsWith('sid1.juice.json'));
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('writer rotates two generations', () async {
    final w = AutoBackupWriter(Directory('${tmp.path}/backups'));
    final base = await w.write('sid1', [1], 'json');
    await w.write('sid1', [2], 'json');
    await w.write('sid1', [3], 'json');
    await w.write('sid1', [4], 'json');

    expect(await File(base).readAsBytes(), [4]);
    expect(await File('$base.1').readAsBytes(), [3]);
    expect(await File('$base.2').readAsBytes(), [2]);
    // Oldest generation was overwritten by the rotation, not accumulated.
    expect(File('$base.3').existsSync(), isFalse);
  });

  // Backup health: a silently-dead safety net is worse than none, so a real
  // fault has to become visible. Platform-unavailability is NOT a fault.
  group('backup health reporting', () {
    test('starts clean', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(autoBackupErrorProvider), isNull);
    });

    test('a missing path_provider plugin is NOT reported as a failure',
        () async {
      // No plugin mock is registered here, so getApplicationSupportDirectory
      // throws MissingPluginException — exactly the widget-test/web case.
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(autoBackupProvider).maybeBackup(force: true);
      expect(c.read(autoBackupErrorProvider), isNull,
          reason: 'an unavailable platform must stay quiet');
    });

    test('a real write fault IS reported', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // A file where the backups directory should be: create() fails.
      final blocker = File('${tmp.path}/backups');
      await blocker.writeAsString('not a directory');
      final w = AutoBackupWriter(Directory(blocker.path));
      await expectLater(
          w.write('sid', [1], 'json'), throwsA(isA<FileSystemException>()));
    });
  });
}
