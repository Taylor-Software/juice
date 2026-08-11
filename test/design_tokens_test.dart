// test/design_tokens_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/shared/design_tokens.dart';

void main() {
  test('lerp at t=0 returns this instance values', () {
    const a = LoreTokens.light;
    const b = LoreTokens.light;
    final c = a.lerp(b, 0.0);
    expect(c.cream, a.cream);
    expect(c.terracotta, a.terracotta);
  });

  test('copyWith overrides only the given field', () {
    const t = LoreTokens.light;
    final t2 = t.copyWith(chaos: const Color(0xFF000000));
    expect(t2.chaos, const Color(0xFF000000));
    expect(t2.cream, t.cream);
  });

  test('narrative text style uses the serif family', () {
    expect(LoreTokens.light.narrative.fontFamily, 'Newsreader');
  });
}
