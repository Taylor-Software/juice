// lib/shared/design_tokens.dart
import 'package:flutter/material.dart';

/// Below this viewport width the play chrome treats the device as a phone:
/// the assistant rail defaults collapsed, expanding the loop bar collapses the
/// rail (and vice versa), chrome auto-collapses while the composer has focus,
/// and the campaign header's expanded row scrolls horizontally instead of
/// wrapping. Matches the Material compact-width breakpoint.
const double kCompactWidth = 600;

/// Warm "tome" design tokens from docs/design_handoff_juice_ux_refresh/README.md.
/// Applied to narrative surfaces (journal, result cards, resume). The rest of
/// the app keeps the M3 ColorScheme; read these via Theme.of(context).extension.
@immutable
class JuiceTokens extends ThemeExtension<JuiceTokens> {
  const JuiceTokens({
    required this.cream,
    required this.sand,
    required this.card,
    required this.raised,
    required this.selected,
    required this.terracotta,
    required this.terracottaDeep,
    required this.ink,
    required this.inkBody,
    required this.inkMuted,
    required this.inkFaint,
    required this.hairline,
    required this.borderInput,
    required this.chaos,
    required this.chaosChipBg,
    required this.chaosChipText,
    required this.sage,
    required this.gold,
    required this.narrative,
    required this.uiLabel,
    required this.resultHeroGradient,
    required this.aiNudgeGradient,
  });

  final Color cream;
  final Color sand;
  final Color card;
  final Color raised;
  final Color selected;
  final Color terracotta;
  final Color terracottaDeep;
  final Color ink;
  final Color inkBody;
  final Color inkMuted;
  final Color inkFaint;
  final Color hairline;
  final Color borderInput;
  final Color chaos;
  final Color chaosChipBg;
  final Color chaosChipText;
  final Color sage;
  final Color gold;
  final TextStyle narrative;
  final TextStyle uiLabel;
  final List<Color> resultHeroGradient;
  final List<Color> aiNudgeGradient;

  static const TextStyle _narrative = TextStyle(
    fontFamily: 'Newsreader',
    height: 1.6,
  );
  static const TextStyle _ui = TextStyle(
    fontFamily: 'HankenGrotesk',
    letterSpacing: 0.10,
  );

  static const JuiceTokens light = JuiceTokens(
    cream: Color(0xFFFBF1EB),
    sand: Color(0xFFF6E2D7),
    card: Color(0xFFFBE9E0),
    raised: Color(0xFFFFFBF9),
    selected: Color(0xFFF3D7C6),
    terracotta: Color(0xFF9A4A22),
    terracottaDeep: Color(0xFF7C3A1A),
    ink: Color(0xFF2B2018),
    inkBody: Color(0xFF5A4A40),
    inkMuted: Color(0xFF8A7466),
    inkFaint: Color(0xFF9A8576),
    hairline: Color(0xFFEFE0D6),
    borderInput: Color(0xFFE0C7B7),
    chaos: Color(0xFFB5762A),
    chaosChipBg: Color(0xFFF4D9A8),
    chaosChipText: Color(0xFF8A5A18),
    sage: Color(0xFF5B7A52),
    gold: Color(0xFFD9A84E),
    narrative: _narrative,
    uiLabel: _ui,
    resultHeroGradient: [Color(0xFFFDEFE6), Color(0xFFF8E0D2)],
    aiNudgeGradient: [Color(0xFFFCEDE3), Color(0xFFF7E0D2)],
  );

  static const JuiceTokens dark = JuiceTokens(
    cream: Color(0xFF241C17),
    sand: Color(0xFF2E2620),
    card: Color(0xFF2E2620),
    raised: Color(0xFF332A23),
    selected: Color(0xFF42342A),
    terracotta: Color(0xFFD0814F),
    terracottaDeep: Color(0xFFB8693A),
    ink: Color(0xFFF3E8DF),
    inkBody: Color(0xFFD8C8BC),
    inkMuted: Color(0xFFAD9B8C),
    inkFaint: Color(0xFF8F7E70),
    hairline: Color(0xFF3D3229),
    borderInput: Color(0xFF4A3C31),
    chaos: Color(0xFFD9A84E),
    chaosChipBg: Color(0xFF4A3A1E),
    chaosChipText: Color(0xFFF4D9A8),
    sage: Color(0xFF89A57F),
    gold: Color(0xFFE0BB6B),
    narrative: _narrative,
    uiLabel: _ui,
    resultHeroGradient: [Color(0xFF34281F), Color(0xFF2A2019)],
    aiNudgeGradient: [Color(0xFF34281F), Color(0xFF2A2019)],
  );

  @override
  JuiceTokens copyWith({
    Color? cream,
    Color? sand,
    Color? card,
    Color? raised,
    Color? selected,
    Color? terracotta,
    Color? terracottaDeep,
    Color? ink,
    Color? inkBody,
    Color? inkMuted,
    Color? inkFaint,
    Color? hairline,
    Color? borderInput,
    Color? chaos,
    Color? chaosChipBg,
    Color? chaosChipText,
    Color? sage,
    Color? gold,
    TextStyle? narrative,
    TextStyle? uiLabel,
    List<Color>? resultHeroGradient,
    List<Color>? aiNudgeGradient,
  }) {
    return JuiceTokens(
      cream: cream ?? this.cream,
      sand: sand ?? this.sand,
      card: card ?? this.card,
      raised: raised ?? this.raised,
      selected: selected ?? this.selected,
      terracotta: terracotta ?? this.terracotta,
      terracottaDeep: terracottaDeep ?? this.terracottaDeep,
      ink: ink ?? this.ink,
      inkBody: inkBody ?? this.inkBody,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      hairline: hairline ?? this.hairline,
      borderInput: borderInput ?? this.borderInput,
      chaos: chaos ?? this.chaos,
      chaosChipBg: chaosChipBg ?? this.chaosChipBg,
      chaosChipText: chaosChipText ?? this.chaosChipText,
      sage: sage ?? this.sage,
      gold: gold ?? this.gold,
      narrative: narrative ?? this.narrative,
      uiLabel: uiLabel ?? this.uiLabel,
      resultHeroGradient: resultHeroGradient ?? this.resultHeroGradient,
      aiNudgeGradient: aiNudgeGradient ?? this.aiNudgeGradient,
    );
  }

  @override
  JuiceTokens lerp(ThemeExtension<JuiceTokens>? other, double t) {
    if (other is! JuiceTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return JuiceTokens(
      cream: c(cream, other.cream),
      sand: c(sand, other.sand),
      card: c(card, other.card),
      raised: c(raised, other.raised),
      selected: c(selected, other.selected),
      terracotta: c(terracotta, other.terracotta),
      terracottaDeep: c(terracottaDeep, other.terracottaDeep),
      ink: c(ink, other.ink),
      inkBody: c(inkBody, other.inkBody),
      inkMuted: c(inkMuted, other.inkMuted),
      inkFaint: c(inkFaint, other.inkFaint),
      hairline: c(hairline, other.hairline),
      borderInput: c(borderInput, other.borderInput),
      chaos: c(chaos, other.chaos),
      chaosChipBg: c(chaosChipBg, other.chaosChipBg),
      chaosChipText: c(chaosChipText, other.chaosChipText),
      sage: c(sage, other.sage),
      gold: c(gold, other.gold),
      narrative: TextStyle.lerp(narrative, other.narrative, t)!,
      uiLabel: TextStyle.lerp(uiLabel, other.uiLabel, t)!,
      resultHeroGradient:
          t < 0.5 ? resultHeroGradient : other.resultHeroGradient,
      aiNudgeGradient: t < 0.5 ? aiNudgeGradient : other.aiNudgeGradient,
    );
  }
}

/// Sugar: `context.juice` -> the active JuiceTokens (falls back to light).
extension JuiceTokensContext on BuildContext {
  JuiceTokens get juice =>
      Theme.of(this).extension<JuiceTokens>() ?? JuiceTokens.light;
}
