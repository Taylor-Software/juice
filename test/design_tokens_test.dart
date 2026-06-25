// test/design_tokens_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/design_tokens.dart';

void main() {
  test('lerp at t=0 returns this instance values', () {
    const a = JuiceTokens.light;
    const b = JuiceTokens.light;
    final c = a.lerp(b, 0.0);
    expect(c.cream, a.cream);
    expect(c.terracotta, a.terracotta);
  });

  test('copyWith overrides only the given field', () {
    const t = JuiceTokens.light;
    final t2 = t.copyWith(chaos: const Color(0xFF000000));
    expect(t2.chaos, const Color(0xFF000000));
    expect(t2.cream, t.cream);
  });

  test('narrative text style uses the serif family', () {
    expect(JuiceTokens.light.narrative.fontFamily, 'Newsreader');
  });
}
