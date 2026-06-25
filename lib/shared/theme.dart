// lib/shared/theme.dart
import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Material 3 theme seeded from a deep amber ("juice"), extended with the
/// JuiceTokens warm "tome" palette and a serif(narrative)/sans(UI) TextTheme.
class AppTheme {
  static ThemeData light() => _base(Brightness.light, JuiceTokens.light);
  static ThemeData dark() => _base(Brightness.dark, JuiceTokens.dark);

  static ThemeData _base(Brightness brightness, JuiceTokens tokens) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB8540E),
      brightness: brightness,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    // Serif for narrative-weight text (display/headline/title/body),
    // sans for controls/labels. Existing widgets reading textTheme.* inherit.
    final tt = base.textTheme.apply(fontFamily: 'Newsreader').copyWith(
          labelSmall:
              base.textTheme.labelSmall?.copyWith(fontFamily: 'HankenGrotesk'),
          labelMedium:
              base.textTheme.labelMedium?.copyWith(fontFamily: 'HankenGrotesk'),
          labelLarge:
              base.textTheme.labelLarge?.copyWith(fontFamily: 'HankenGrotesk'),
        );
    return base.copyWith(
      textTheme: tt,
      extensions: <ThemeExtension<dynamic>>[tokens],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }
}
