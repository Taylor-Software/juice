// test/theme_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/shared/design_tokens.dart';

void main() {
  test('light theme carries JuiceTokens and a serif body font', () {
    final t = AppTheme.light();
    expect(t.extension<JuiceTokens>(), isNotNull);
    expect(t.textTheme.bodyMedium?.fontFamily, 'Newsreader');
    expect(t.textTheme.labelLarge?.fontFamily, 'HankenGrotesk');
  });

  test('dark theme carries the dark token set', () {
    final t = AppTheme.dark();
    expect(t.extension<JuiceTokens>()?.cream, JuiceTokens.dark.cream);
  });
}
