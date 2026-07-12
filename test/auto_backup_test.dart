import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/state/auto_backup.dart';

void main() {
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
}
