// test/theme_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/shared/theme.dart';
import 'package:loreseer/shared/design_tokens.dart';

void main() {
  test('light theme carries LoreTokens and a serif body font', () {
    final t = AppTheme.light();
    expect(t.extension<LoreTokens>(), isNotNull);
    expect(t.textTheme.bodyMedium?.fontFamily, 'Newsreader');
    expect(t.textTheme.labelLarge?.fontFamily, 'HankenGrotesk');
  });

  test('dark theme carries the dark token set', () {
    final t = AppTheme.dark();
    expect(t.extension<LoreTokens>()?.cream, LoreTokens.dark.cream);
  });
}
