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
      // Modal containers. Sheets and dialogs are this app's second-most-common
      // container after the card (60+ call sites) and were rendering at raw M3
      // defaults — the largest surface still outside the tome. Colors + corners
      // only; nothing here changes a modal's behavior or layout.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.cream,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.cream,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      // Ink-on-paper inverted: a snackbar is the page speaking back.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.ink,
        contentTextStyle: tokens.uiLabel.copyWith(color: tokens.cream),
        actionTextColor: tokens.terracotta,
      ),
      // State colors. M3's defaults here are neutral grays, which the
      // warm-only palette bans; disabled is faint ink, focus is the accent.
      disabledColor: tokens.inkFaint,
      focusColor: tokens.terracotta.withValues(alpha: 0.12),
      hoverColor: tokens.terracotta.withValues(alpha: 0.06),
      dividerTheme: DividerThemeData(color: tokens.hairline, space: 1),
    );
  }
}
