import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/card_images.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  // Tests run with CWD = project root, so the bundled asset files exist on disk.
  test('every tarot card has a bundled image asset', () {
    for (final card in kTarotDeck) {
      final path = tarotImageAsset(card)!;
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
