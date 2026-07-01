// test/seed_kits_test.dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/loop_kit.dart';
import 'package:juice_oracle/state/providers.dart' show kKitAssetPaths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled seed kit is well-formed', () async {
    expect(kKitAssetPaths, hasLength(6));
    for (final path in kKitAssetPaths) {
      final raw = await rootBundle.loadString(path);
      final kit = decodeLoopKit(raw);
      expect(kit, isNotNull, reason: '$path failed to decode');
      expect(kit!.name, isNotEmpty, reason: '$path has an empty name');
      expect(kit.tables, isNotEmpty, reason: '$path has no tables');
      expect(kit.refCards, isNotEmpty, reason: '$path has no ref cards');
      expect(kit.sceneTitle, isNotEmpty, reason: '$path has no starter scene');
    }
  });
}
