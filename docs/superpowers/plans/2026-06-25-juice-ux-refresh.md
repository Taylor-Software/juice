# Juice UX Refresh — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the solo-play loop faster, calmer, and more guided, and give the app a warm "tome" skin for narrative content — recreating the `docs/design_handoff_juice_ux_refresh/` mockups with the app's existing Flutter widgets, theme, and Riverpod state.

**Architecture:** A foundation phase introduces design tokens (a `ThemeExtension` + bundled serif/sans fonts) that every later phase styles against. Feature phases then either *finish* surfaces that are already 80% built (HUD tiers, slash palette, presets), *merge* a proposed affordance into an existing one (inline oracle dock → assistant rail), or *add* net-new surfaces (resume screen, Track dashboard, lead-PC card, campaign identity). No backward-compat work — this is pre-release.

**Tech Stack:** Flutter, `flutter_riverpod`, `shared_preferences`, Material 3. Two new bundled font families (Newsreader serif, Hanken Grotesk sans). No new pub dependencies.

**Decisions locked with the user (2026-06-25):**
1. **Visual scope = Typography + narrative only.** Add tokens + serif/sans split via a `ThemeExtension`; apply warm styling to journal / result cards / resume. Keep the M3 `ColorScheme` everywhere else. (NOT a full repaint.)
2. **Fonts = bundle Newsreader + Hanken Grotesk** into `assets/fonts/` + pubspec. No `google_fonts` dep (stays lean + offline-first).
3. **#2 inline oracle dock = merge into the assistant rail.** Surface the rail's existing inline roll chips always-visible above the composer; keep the rail for navigate chips + Ask-GM. One roll→`addResult` pipeline, no duplication.

**Licensing note (binding, from CLAUDE.md + memory):** Newsreader (OFL) and Hanken Grotesk (OFL) are open-licensed fonts — fine to bundle. No rulebook prose is introduced anywhere in this plan; the facts-only posture is unaffected.

---

## Reconciliation summary (what each handoff item actually requires)

| # | Handoff item | Current state (file:line) | Verdict |
|---|---|---|---|
| tokens | Centralized design tokens, serif/sans | `lib/shared/theme.dart` = bare `ColorScheme.fromSeed(0xFFB8540E)`, M3, no fonts/ThemeExtension; colors inlined per-file | **Foundation (Phase 0)** |
| 10 | Directive empty states | none (passive copy scattered) | **New shared widget (Phase 0)** |
| 3 | Journal entry hierarchy | `_PayloadCard` (`journal_screen.dart:2045`) + scene divider (`:721`) exist; one `_entry()` switch (`:694`); actions hidden in PopupMenu (`:699-718`); **no Pin** | **Restyle + new Pin (Phase 1)** |
| 2 | Inline oracle dock | duplicates rail: `roll-oracle`/`scene-event` chips → `_onTap`→`oracle.fateCheck`→`addResult` (`assistant_rail.dart:91-119`); rail collapsed-by-default above entries | **Merge into rail (Phase 1)** |
| 4 | Grouped HUD tiers | already 2-row + collapse caret `hdr-collapse` + `settings.headerCollapsed` (`play_context_hud.dart:61-199`); Chaos currently in collapsible row | **Finish: move Chaos to tier 1, group tier 2 (Phase 2)** |
| 7 | Slash-command palette | already exists: `parseSlash` + `command_registry` + `_slashPalette()` (`journal_screen.dart:933`) + 7 built-ins | **Polish: add `/roll` `/inspire` `/thread`, `/` hint chip (Phase 2)** |
| 8 | Surface on-device AI | gates exist (`aiReadyProvider`/`aiSupportedProvider`); no nudge card; `✦` only on rail header | **New nudge + glyph standardize (Phase 2)** |
| 1 | Session resume ritual | none; landing logic exists (`ShellRouteNotifier.landFor`) | **New screen (Phase 3)** |
| 5 | "Where am I?" dashboard | `SubtabHost` has no home tab (`tracking_tab.dart:33`) | **New pane (Phase 4)** |
| 6 | Roster row at a glance | `_rosterCard` plain ListTile, lead badge exists, no vitals bars/quick-actions (`tracker_screen.dart:732`) | **Rich lead card (Phase 5)** |
| 9 | Play-fantasy presets | `kCampaignPresets` presets-first, `kPresetIcons` exists (`campaign_presets.dart`) | **Cosmetic: richer labels (Phase 6)** |
| 11 | Campaign list identity | `SessionMeta` has no color/icon; genre/tone live in `CampaignSettings`, never shown in launcher | **New SessionMeta fields + launcher render (Phase 6)** |
| 12 | Iconography consistency | mode toggle = ambiguous icon; tool-search/filter icons | **Audit + segmented control (Phase 6)** |

**Phase dependency:** Phase 0 unblocks all styling and must land first. Phases 1–6 are independent of each other and can ship in any order after Phase 0 (suggested order = marquee value first: 1 → 2 → 3 → …).

**Sub-plan note:** Phase 0, plus the model/state/logic tasks throughout, are specified in full TDD detail below. The three heaviest *widget-composition* phases (3 Session Resume, 4 Track dashboard, 5 Lead card) carry complete file maps, token-exact styling values, and test targets here; per this repo's convention (a design spec + plan per feature under `docs/superpowers/`), author a short feature spec for each at execution time if the card composition needs more granular steps than given.

---

## File Structure

**New files**
- `assets/fonts/newsreader/` — Newsreader `.ttf` (400, 500, 600 + italics)
- `assets/fonts/hanken/` — Hanken Grotesk `.ttf` (400, 600, 700, 800)
- `lib/shared/design_tokens.dart` — `JuiceTokens` `ThemeExtension` (colors + text styles + spacing/radius/shadow constants)
- `lib/shared/empty_state.dart` — `EmptyState` widget (#10)
- `lib/features/session_resume_screen.dart` — `SessionResumeScreen` (#1)
- `lib/features/track_home_pane.dart` — `TrackHomePane` dashboard (#5)
- `lib/shared/ai_nudge_card.dart` — `AiNudgeCard` + shared `AiBadge` glyph (#8)
- Test files mirroring each (`test/design_tokens_test.dart`, `test/empty_state_test.dart`, `test/session_resume_screen_test.dart`, `test/track_home_pane_test.dart`, `test/ai_nudge_card_test.dart`)

**Modified files**
- `pubspec.yaml` — fonts block
- `lib/shared/theme.dart` — wire `JuiceTokens` + serif/sans `TextTheme`
- `lib/features/journal_screen.dart` — entry hierarchy (#3), rail-merge dock host (#2), slash polish (#7), AI nudge mount (#8), empty state (#10)
- `lib/features/assistant_rail.dart` — extract inline chips into always-visible dock (#2), `✦` standardize (#8)
- `lib/shared/play_context_hud.dart` — Chaos→tier 1, group tier 2 (#4)
- `lib/engine/models.dart` — `JournalEntry.pinned` (#3); `SessionMeta` `identityColor`/`identityIcon` (#11)
- `lib/engine/command_registry.dart` — `/roll` `/inspire` `/thread` (#7)
- `lib/features/tracking_tab.dart` — prepend Home tab (#5)
- `lib/features/tracker_screen.dart` — `_rosterCard` lead variant (#6)
- `lib/engine/campaign_presets.dart` — preset blurb/sublabel fields (#9)
- `lib/shared/home_shell.dart` + `lib/features/launcher_screen.dart` — preset labels (#9), identity render (#11), resume hop (#1), icon audit (#12)
- `lib/state/providers.dart` — `aiNudgeSeenProvider` (#8); resume-data derive (#1)

---

# Phase 0 — Foundation: fonts, tokens, empty state

### Task 0.1: Bundle the two font families

**Files:**
- Add binaries under: `assets/fonts/newsreader/`, `assets/fonts/hanken/`
- Modify: `pubspec.yaml:30-45`

- [ ] **Step 1: Download the OFL fonts and place them**

Fetch from Google Fonts (OFL):
```
assets/fonts/newsreader/Newsreader-Regular.ttf      (400)
assets/fonts/newsreader/Newsreader-Medium.ttf       (500)
assets/fonts/newsreader/Newsreader-SemiBold.ttf     (600)
assets/fonts/newsreader/Newsreader-Italic.ttf       (400 italic)
assets/fonts/newsreader/Newsreader-MediumItalic.ttf (500 italic)
assets/fonts/hanken/HankenGrotesk-Regular.ttf       (400)
assets/fonts/hanken/HankenGrotesk-SemiBold.ttf      (600)
assets/fonts/hanken/HankenGrotesk-Bold.ttf          (700)
assets/fonts/hanken/HankenGrotesk-ExtraBold.ttf     (800)
```
Keep the OFL `LICENSE.txt` alongside each family directory.

- [ ] **Step 2: Declare them in pubspec**

Add under `flutter:` (after the `assets:` block):
```yaml
  fonts:
    - family: Newsreader
      fonts:
        - asset: assets/fonts/newsreader/Newsreader-Regular.ttf
          weight: 400
        - asset: assets/fonts/newsreader/Newsreader-Medium.ttf
          weight: 500
        - asset: assets/fonts/newsreader/Newsreader-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/newsreader/Newsreader-Italic.ttf
          weight: 400
          style: italic
        - asset: assets/fonts/newsreader/Newsreader-MediumItalic.ttf
          weight: 500
          style: italic
    - family: HankenGrotesk
      fonts:
        - asset: assets/fonts/hanken/HankenGrotesk-Regular.ttf
          weight: 400
        - asset: assets/fonts/hanken/HankenGrotesk-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/hanken/HankenGrotesk-Bold.ttf
          weight: 700
        - asset: assets/fonts/hanken/HankenGrotesk-ExtraBold.ttf
          weight: 800
```

- [ ] **Step 3: Verify pubspec resolves**

Run: `flutter pub get`
Expected: `Got dependencies!` with no font-asset errors.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml assets/fonts
git commit -m "feat(theme): bundle Newsreader + Hanken Grotesk fonts"
```

---

### Task 0.2: Design-tokens ThemeExtension

**Files:**
- Create: `lib/shared/design_tokens.dart`
- Test: `test/design_tokens_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/design_tokens_test.dart`
Expected: FAIL — `Target of URI doesn't exist: design_tokens.dart`.

- [ ] **Step 3: Implement the tokens**

```dart
// lib/shared/design_tokens.dart
import 'package:flutter/material.dart';

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

  final Color cream;            // #FBF1EB app background
  final Color sand;             // #F6E2D7 header band
  final Color card;             // #FBE9E0 pink card fill
  final Color raised;           // #FFFBF9 raised rows/inputs
  final Color selected;         // #F3D7C6 selected chip
  final Color terracotta;       // #9A4A22 primary
  final Color terracottaDeep;   // #7C3A1A pressed
  final Color ink;              // #2B2018
  final Color inkBody;          // #5A4A40
  final Color inkMuted;         // #8A7466
  final Color inkFaint;         // #9A8576
  final Color hairline;         // #EFE0D6
  final Color borderInput;      // #E0C7B7
  final Color chaos;            // #B5762A
  final Color chaosChipBg;      // #F4D9A8
  final Color chaosChipText;    // #8A5A18
  final Color sage;             // #5B7A52
  final Color gold;             // #D9A84E lead-PC star
  final TextStyle narrative;    // Newsreader serif base
  final TextStyle uiLabel;      // Hanken Grotesk eyebrow/label base
  final List<Color> resultHeroGradient; // [#FDEFE6, #F8E0D2]
  final List<Color> aiNudgeGradient;    // [#FCEDE3, #F7E0D2]

  static const TextStyle _narrative =
      TextStyle(fontFamily: 'Newsreader', height: 1.6);
  static const TextStyle _ui =
      TextStyle(fontFamily: 'HankenGrotesk', letterSpacing: 0.10);

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

  // Dark variant: keep ink/paper readable on dark surfaces. Narrative serif is
  // retained; surface colors deepen. Tuned for parity, not pixel-match (the
  // handoff specs light only).
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
    Color? cream, Color? sand, Color? card, Color? raised, Color? selected,
    Color? terracotta, Color? terracottaDeep, Color? ink, Color? inkBody,
    Color? inkMuted, Color? inkFaint, Color? hairline, Color? borderInput,
    Color? chaos, Color? chaosChipBg, Color? chaosChipText, Color? sage,
    Color? gold, TextStyle? narrative, TextStyle? uiLabel,
    List<Color>? resultHeroGradient, List<Color>? aiNudgeGradient,
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
      resultHeroGradient: t < 0.5 ? resultHeroGradient : other.resultHeroGradient,
      aiNudgeGradient: t < 0.5 ? aiNudgeGradient : other.aiNudgeGradient,
    );
  }
}

/// Sugar: `context.juice` → the active JuiceTokens (falls back to light).
extension JuiceTokensContext on BuildContext {
  JuiceTokens get juice =>
      Theme.of(this).extension<JuiceTokens>() ?? JuiceTokens.light;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/design_tokens_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/shared/design_tokens.dart test/design_tokens_test.dart
git commit -m "feat(theme): JuiceTokens ThemeExtension (warm tome palette + serif/sans)"
```

---

### Task 0.3: Wire tokens + serif/sans TextTheme into AppTheme

**Files:**
- Modify: `lib/shared/theme.dart`
- Test: `test/theme_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/theme_test.dart
import 'package:flutter/material.dart';
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme_test.dart`
Expected: FAIL — `extension<JuiceTokens>()` is null / fontFamily mismatch.

- [ ] **Step 3: Implement**

```dart
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
          labelSmall: base.textTheme.labelSmall?.copyWith(fontFamily: 'HankenGrotesk'),
          labelMedium: base.textTheme.labelMedium?.copyWith(fontFamily: 'HankenGrotesk'),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontFamily: 'HankenGrotesk'),
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
```

- [ ] **Step 4: Run test + full suite (no regressions from the TextTheme swap)**

Run: `flutter test test/theme_test.dart`
Expected: PASS.
Run: `flutter test`
Expected: existing suite green (TextTheme family change is non-breaking — sizes/weights unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/shared/theme.dart test/theme_test.dart
git commit -m "feat(theme): wire JuiceTokens + serif/sans TextTheme into AppTheme"
```

---

### Task 0.4: `EmptyState` shared widget (#10)

**Files:**
- Create: `lib/shared/empty_state.dart`
- Test: `test/empty_state_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/empty_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/empty_state.dart';
import 'package:juice_oracle/shared/theme.dart';

void main() {
  testWidgets('renders title, body, and fires the primary action', (t) async {
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: EmptyState(
          title: 'Every story needs a hero.',
          body: 'Create your first character.',
          primaryLabel: 'Create character',
          onPrimary: () => tapped = true,
        ),
      ),
    ));
    expect(find.text('Every story needs a hero.'), findsOneWidget);
    expect(find.text('Create your first character.'), findsOneWidget);
    await t.tap(find.byKey(const Key('empty-state-primary')));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/empty_state_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/shared/empty_state.dart
import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Directive empty state: one emotive line, a short body, a prominent primary
/// action, and an optional secondary. Reused across empty roster/journal/etc.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.icon,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final IconData? icon;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 40, color: tk.inkFaint),
              const SizedBox(height: 14),
            ],
            Text(title,
                textAlign: TextAlign.center,
                style: tt.titleLarge?.copyWith(
                    fontFamily: 'Newsreader',
                    fontStyle: FontStyle.italic,
                    color: tk.ink)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                    fontFamily: 'HankenGrotesk', color: tk.inkMuted)),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('empty-state-primary'),
              onPressed: onPrimary,
              child: Text(primaryLabel),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('empty-state-secondary'),
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/empty_state_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/empty_state.dart test/empty_state_test.dart
git commit -m "feat(ui): directive EmptyState widget"
```

- [ ] **Step 6: Adopt EmptyState at the empty roster + empty journal**

In `lib/features/tracker_screen.dart` (roster) and `lib/features/journal_screen.dart` (entry list), replace the existing empty placeholders with `EmptyState`:
- Roster empty: title `'Every story needs a hero.'`, body `'Create your first character.'`, primary `'Create character'` → existing add-character flow.
- Journal empty: title `'A blank page.'`, body `'Roll the oracle or write your first line.'`, primary `'Roll oracle'` → the inline roll-oracle action (Phase 1 dock).
Find the current empty branches (grep `isEmpty` in each screen) and swap. Add/extend widget tests asserting `find.byKey(const Key('empty-state-primary'))` appears when the list is empty. Commit `feat(ui): directive empty states for roster + journal`.

---

# Phase 1 — Journal core (#3 entry hierarchy, #2 rail→dock merge)

> Marquee phase. Both items live in `journal_screen.dart` + `assistant_rail.dart`. Style everything against `context.juice` (Phase 0).

### Task 1.1: `JournalEntry.pinned` field + toggle (#3 Pin)

**Files:**
- Modify: `lib/engine/models.dart` (`JournalEntry` class — find via grep `class JournalEntry`)
- Modify: the journal notifier (grep `class JournalNotifier` / `addResult`) — add `togglePin(String id)`
- Test: `test/journal_pin_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/journal_pin_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('JournalEntry.pinned defaults false and round-trips through JSON', () {
    final e = JournalEntry(
      id: 'e1', kind: JournalKind.result, body: 'Yes, and…',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    expect(e.pinned, isFalse);
    final back = JournalEntry.fromJson(e.copyWith(pinned: true).toJson());
    expect(back.pinned, isTrue);
  });
}
```
(Match the real `JournalEntry` constructor signature — adjust required fields to whatever the class actually declares; the assertion on `pinned` is the point.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/journal_pin_test.dart`
Expected: FAIL — `pinned` not defined.

- [ ] **Step 3: Implement**

In `JournalEntry`: add `final bool pinned;`, default `false` in the constructor, thread through `copyWith`, add `'pinned': pinned` to `toJson`, read `pinned: (json['pinned'] as bool?) ?? false` in `fromJson`. In the notifier add:
```dart
void togglePin(String id) {
  state = AsyncData([
    for (final e in state.requireValue)
      e.id == id ? e.copyWith(pinned: !e.pinned) : e,
  ]);
  _persist(); // match the notifier's existing persistence call
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/journal_pin_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart lib/state test/journal_pin_test.dart
git commit -m "feat(journal): per-entry pinned flag + togglePin"
```

### Task 1.2: Result hero card restyle + on-card action row (#3)

**Files:** Modify `lib/features/journal_screen.dart` — `_PayloadCard` (`:2045-2175`) and the non-payload result branch (`:792-824`).

- [ ] **Step 1** — Wrap the result card body in a gradient `Container` (not a bare `Card`): `decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: tk.resultHeroGradient), border: Border.all(color: const Color(0xFFEFC9B4)), borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: tk.terracotta.withOpacity(0.16), blurRadius: 22, offset: const Offset(0, 8))])`.
- [ ] **Step 2** — Source row: 24×24 terracotta icon tile + UPPERCASE source label (`tk.uiLabel` 700, `tk.inkFaint`, letter-spacing 0.12) from `sourceTool`, odds right-aligned.
- [ ] **Step 3** — Big serif answer: the `summary` line in `tk.narrative` size 30 weight 500 `tk.ink`; render the qualifier ("and…"/"but…") italic in `tk.terracotta` (split on the comma; style the tail).
- [ ] **Step 4** — Intensity caption beneath in `tk.uiLabel` 11 `tk.inkMuted`.
- [ ] **Step 5** — Replace the hidden PopupMenu actions with an **inline action row** above a 1px `tk.hairline`: `✦ Interpret` (gated `aiReady` + result kind), `Voice line` (gated dialog-shaped), right-aligned `⚑ Pin` → `ref.read(journalProvider.notifier).togglePin(e.id)` (filled when `e.pinned`). Keep the PopupMenu for secondary actions (edit/delete/link/tags).
- [ ] **Step 6** — Widget test (`test/journal_entry_hierarchy_test.dart`): pump `JournalScreen` per the rootBundle recipe (override oracle/verdant/emulator/ruleset providers with file fixtures + `SharedPreferences.setMockInitialValues`, AI on); seed a `result` entry with a summary; assert the big-serif text, the inline `⚑ Pin` key (`Key('pin-<id>')`), and that tapping it flips `pinned`.
- [ ] **Step 7** — Commit `feat(journal): result hero card + on-card action row + pin`.

### Task 1.3: Prose / compact-dice / scene-divider weights (#3)

**Files:** Modify `journal_screen.dart` — `text` branch (`:779-791`), the dice/log path (payload card when `sourceTool=='dice'`), scene divider (`:721-755`).

- [ ] **Step 1** — Prose (`JournalKind.text` with no payload): drop the `Card`; render body as `tk.narrative` size 14.5 italic `tk.inkBody`, padded only.
- [ ] **Step 2** — Compact dice/log: when `sourceTool == 'dice'`, render a slim `tk.raised` row (icon tile + `Dice · d20 = 18`) instead of the full hero card. Branch inside `_PayloadCard` or before delegating to it.
- [ ] **Step 3** — Scene divider: center an eyebrow (`tk.uiLabel` UPPERCASE) `Scene 3 · Chaos 5` with the Chaos value in `tk.chaos`, flanked by `tk.hairline` rules.
- [ ] **Step 4** — Extend the hierarchy widget test: assert prose has no `Card` ancestor, dice renders the compact row, divider shows the chaos-colored eyebrow.
- [ ] **Step 5** — Commit `feat(journal): three-weight entry hierarchy (prose/dice/divider)`.

### Task 1.4: Merge inline oracle chips into an always-visible dock (#2)

**Files:** Modify `lib/features/assistant_rail.dart` (`_onTap` `:91-119`, build `:159+`) and `journal_screen.dart` (composer mount `:558-559`).

- [ ] **Step 1** — Extract the inline-roll dispatch (the `roll-oracle` / `scene-event` arms of `_onTap`, `:97-105`) into a public method or a small `InlineRollDock` widget that takes the suggestions list (filtered to the *inline* kinds only) + the same `oracle`/`journalProvider` calls. Do NOT duplicate the pipeline — call the extracted method.
- [ ] **Step 2** — Render `InlineRollDock` as a horizontal `SingleChildScrollView(scrollDirection: Axis.horizontal)` of chips (`⚀ Roll oracle` filled `tk.terracotta`; `Scene test`, `Pay the price`, `✦ Inspire` as `tk.selected` with `tk.terracotta` 600 text, radius 12), mounted **always-visible directly above the composer** in `journal_screen.dart` (between the entry list and `_composerBar`). `✦ Inspire` reuses `showGenerateSheet`; `Pay the price` reuses the existing complication/price path if present, else maps to `scene-event`.
- [ ] **Step 3** — Remove the now-duplicated inline chips from the rail's expanded chip set (keep navigate chips + Ask-GM there). The rail's collapsed-by-default header stays.
- [ ] **Step 4** — After a dock roll appends an entry, smooth-scroll via the existing `ScrollController.animateTo` (~300ms `Curves.easeOut`) — NOT `Scrollable.ensureVisible` on the root (per handoff + the tool-host constraints memory).
- [ ] **Step 5** — Widget test: pump `JournalScreen`, tap the dock `⚀ Roll oracle` chip (`Key('dock-roll-oracle')`), assert a new `result` entry appears in the stream and the rail no longer renders a duplicate inline chip.
- [ ] **Step 6** — Commit `feat(journal): always-visible inline oracle dock (merged from assistant rail)`.

---

# Phase 2 — HUD tiers (#4), slash polish (#7), AI surfacing (#8)

### Task 2.1: Chaos → tier 1, group tier 2 (#4)

**Files:** Modify `lib/shared/play_context_hud.dart` (`:61-199`).

- [ ] **Step 1** — Move the Mythic Chaos chip (`:140-165`, gated `usesMythic && crawl != null`) from the collapsible Wrap (`:106`) up into the always-visible Row 1 (`:61`), as a `tk.chaosChipBg`/`tk.chaosChipText` chip beside the quick-roll button. Keep the dec/inc stepper buttons but only show them in tier 2 (chip value stays visible in tier 1).
- [ ] **Step 2** — In the collapsible Row 2, group the remaining pills (Light, Oracle, terrain/crawl) under a quiet visual grouping using `tk.card` pills + `tk.inkMuted` text. No new provider — `settings.headerCollapsed` already persists (`:49,101`).
- [ ] **Step 3** — Update `test/campaign_header_test.dart`: the Chaos chip is now visible **when collapsed** (add an assertion mirroring the existing quick-roll "even when collapsed" test at `:276`); steppers hidden when collapsed.
- [ ] **Step 4** — Commit `feat(hud): Chaos chip in tier 1, grouped tier 2`.

### Task 2.2: Slash palette polish (#7)

**Files:** Modify `lib/engine/command_registry.dart` (`buildCommandRegistry` `:147+`); `journal_screen.dart` (`_slashPalette` `:933`, composer `:1282`).

- [ ] **Step 1** — Add registry commands `/roll <expr>` (parse a dice expression → `oracle.dice` → `addResult` as `dice`), `/inspire <gen>` (open `GenerateSheet` filtered to the named generator), `/thread <title>` (create a thread). Give each `id`/`label`/`keywords`/arg hint. Add a unit test in `test/command_registry_test.dart` asserting `matchCommands(registry, 'roll')` and `'inspire'` resolve.
- [ ] **Step 2** — Restyle palette rows with `tk` (26px icon tile + command in `tk.uiLabel` + description in `tk.inkMuted`; selected row `tk.sand`).
- [ ] **Step 3** — Add a small persistent `/` hint chip near the composer (`Key('slash-hint')`) that, tapped, inserts `/` and opens the palette — discoverability.
- [ ] **Step 4** — Widget test: type `/roll 2d6` in the composer, submit, assert a `dice` entry appears; assert `slash-hint` is present.
- [ ] **Step 5** — Commit `feat(journal): /roll /inspire /thread slash commands + discoverable hint`.

### Task 2.3: AI nudge card + shared `✦` glyph (#8)

**Files:** Create `lib/shared/ai_nudge_card.dart`; add `aiNudgeSeenProvider` in `lib/state/providers.dart`; mount in `journal_screen.dart`.

- [ ] **Step 1** — Add a global one-shot pref provider:
```dart
// in providers.dart, near aiEnabledProvider (:1236)
final aiNudgeSeenProvider =
    AsyncNotifierProvider<AiNudgeSeenNotifier, bool>(AiNudgeSeenNotifier.new);

class AiNudgeSeenNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.ai_nudge_seen.v1'; // global, NOT session-scoped
  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;
  Future<void> markSeen() async {
    (await SharedPreferences.getInstance()).setBool(_key, true);
    state = const AsyncData(true);
  }
}
```
- [ ] **Step 2** — `AiNudgeCard` (`lib/shared/ai_nudge_card.dart`): gradient `tk.aiNudgeGradient`, border `#F0CDB8`, radius 18; `✦ Bring the oracle to life`, value copy, `Enable AI` (→ open Settings sheet) / `Later` (→ `markSeen`). Gate sheen animation behind `MediaQuery.of(context).disableAnimations` (static if reduced-motion).
- [ ] **Step 3** — Mount it at the top of the journal entry list **only when** `aiSupported && !aiReady && !aiNudgeSeen` (watch the three providers). One-shot.
- [ ] **Step 4** — Extract a tiny shared `AiBadge` (`✦` = `Icons.auto_awesome`, `tk.terracotta`) and use it on **every** AI action: Interpret/Voice/Recap (journal), Narrate (composer), Ask-GM (rail), Flesh-Out. Add the footnote "✦ marks an AI-assisted action · all on-device" once near the AI affordances.
- [ ] **Step 5** — Widget tests (`test/ai_nudge_card_test.dart`): nudge renders when supported-but-not-ready and hidden after `markSeen`; reduced-motion shows the static card.
- [ ] **Step 6** — Commit `feat(ai): contextual enable nudge + standardized ✦ badge`.

---

# Phase 3 — Session Resume ritual (#1)

**Files:** Create `lib/features/session_resume_screen.dart` + `test/session_resume_screen_test.dart`; modify the Continue entry points (`launcher_screen.dart`, `home_shell.dart`) to hop through it before `landFor`.

**Data: derive, don't persist.** "Last played N days ago" = newest journal entry `createdAt`; "last entry" = newest `text` entry body. Scene/Chaos/Light/threads read the same providers the HUD uses. No new persisted state needed (optional `SessionMeta.lastOpenedAt` only if a campaign with zero entries must show a timestamp — skip for v1).

- [ ] **Step 1** — Failing widget test: pump `SessionResumeScreen` with seeded providers (a campaign with ≥1 scene + ≥1 thread + a last entry); assert the scene title, the three stat tiles (Scene/Chaos/Light), an open-thread row with `n/10`, the last-entry line, and the `Key('resume-continue')` CTA.
- [ ] **Step 2** — Run → FAIL (file missing).
- [ ] **Step 3** — Implement `SessionResumeScreen` per handoff §1 layout, styled with `tk`: header band (`tk.sand`→cream fade) eyebrow `WELCOME BACK` + scene title (`tk.narrative` italic 30); three `Expanded` stat tiles (`tk.card`, radius 14); open-threads list (`tk.raised` rows, colored dot + title + `n/10`); last-entry line (`tk.narrative` italic 14.5 `tk.inkBody`); full-width `Continue the story →` (`tk.terracotta`, radius 16) → `landFor(mode)` + pop; secondary row `Recap so far` (uses on-device AI when `aiReady`, else deterministic static summary = scene + open threads + last N entries) / `New scene`.
- [ ] **Step 4** — Wire Continue: when entering a campaign that has prior session state (≥1 journal entry), push `SessionResumeScreen` instead of landing directly; New/empty campaigns skip straight to `landFor`. Touch the launcher Continue + in-shell switch paths only (not `New`).
- [ ] **Step 5** — Run the test → PASS; run `flutter test`.
- [ ] **Step 6** — Commit `feat(launcher): session resume ritual screen`.

---

# Phase 4 — "Where am I?" Track dashboard (#5)

**Files:** Create `lib/features/track_home_pane.dart` + `test/track_home_pane_test.dart`; modify `lib/features/tracking_tab.dart` (`:33-47`) to prepend a `home` tab at index 0 via `SubtabHost`.

- [ ] **Step 1** — Failing widget test: pump the Track verb with seeded scene/threads/tracks/party/encounter providers; assert the Home tab is index 0 and shows a `Now` card (current scene), `Threads`/`Tracks` cards with progress, a `Party` mini-vitals card, and an `Encounter` card; assert tapping the `Threads` card calls `shellRouteProvider.goTo(Destination.track, subtab: 'threads')`.
- [ ] **Step 2** — Run → FAIL.
- [ ] **Step 3** — Implement `TrackHomePane`: a `Column`/`Wrap` of tap-through `Card`s styled with `tk` (each `InkWell` with matching `borderRadius`, whole card is the target). `Now` (`tk.card`) → scene + `Open ↗`; `Threads` + `Tracks` row (thin progress bars / `n/10`); `Party` (mini vitals chips e.g. `♥ 4/5`, `↯ +2` from `charactersProvider`); `Encounter` (`Idle`/live — when live, `tk.chaos` emphasis + sorts first, surface `#FFF6F0` border `#F0CDB8`). Each `onTap` → `goTo` its subtab.
- [ ] **Step 4** — Prepend to `SubtabHost` tabs in `tracking_tab.dart`: `('Home', TrackHomePane())` at index 0; keep `initialTabIndex: 0` so entering Track lands on the overview.
- [ ] **Step 5** — Run the test → PASS; run `flutter test`.
- [ ] **Step 6** — Commit `feat(track): where-am-I dashboard home pane`.

---

# Phase 5 — Roster lead card (#6)

**Files:** Modify `lib/features/tracker_screen.dart` `_rosterCard` (`:732-837`); reuse meter patterns from `lib/features/sheet_widgets.dart` (`meterStepper` `:90`, `momentumRow` `:134`).

- [ ] **Step 1** — Failing widget test: seed a lead PC (`activeCharacterId == c.id`) with vitals; assert the lead row renders a gradient card, a vitals bar group, condition chips, and a quick-action row (`Key('lead-roll-move')`, `Key('lead-hp-dec')`, `Key('lead-hp-inc')`, `Key('lead-more')`). Seed a companion; assert it stays a compact `tk.raised` row.
- [ ] **Step 2** — Run → FAIL.
- [ ] **Step 3** — Implement two variants keyed off `isLead`:
  - **Lead card:** `tk.raised`→card gradient, border `#F0CDB8`, radius 18. Gold star + name (16/600) + role badge. **Vitals row** — system-aware: Ironsworn-family → Health/Spirit/Supply (5px `LinearProgressIndicator`, `tk.hairline` track / `tk.terracotta` fill) + Momentum value (reuse `momentumRow`); D&D → HP/AC; Shadowdark → HP + torch countdown; others → first track + currentHp. Condition chips (`tk.selected`) + dashed `+ condition` (reuse `showConditionsEditor`). **Quick-action row** above a hairline: `Roll a move` (filled, deep-links to the character's move flow), `−`/`+` (mutate the primary meter via `Character.withHpDelta` / track, optimistic, no dialog), `⋯` (the existing PopupMenu).
  - **Compact row:** unchanged for companions/NPCs (`tk.raised`, icon tile + name + `NPC · Wary` + `♥ 3/3`).
- [ ] **Step 4** — Run the test → PASS; run `flutter test`.
- [ ] **Step 5** — Commit `feat(sheet): rich lead-PC roster card with vitals + quick actions`.

---

# Phase 6 — Identity, presets, iconography (#9, #11, #12)

### Task 6.1: Play-fantasy preset labels (#9)

**Files:** Modify `lib/engine/campaign_presets.dart` (add `blurb` + `kind` fields to `CampaignPreset`); the preset render in `home_shell.dart` (`:749+`).

- [ ] **Step 1** — Add to `CampaignPreset`: `final String kind;` (e.g. `'Gritty solo fantasy'`) and `final String blurb;` (e.g. `'Vows, perilous odds'`). Populate for each preset. Keep `id`/`mode`/`systems`/`presetConfig` unchanged. Unit test: every preset has non-empty `kind`+`blurb`.
- [ ] **Step 2** — Render preset rows (`tk.raised`, radius 15, selected = `tk.sand` + `tk.terracotta` border): 36px icon tile (`kPresetIcons`) + `kind` (title) + `blurb · <systemLabel>` (sublabel). Dashed `⚙ Browse all systems · Custom` row at the end (the existing `preset-custom` path). Header copy `What kind of story are you telling?`.
- [ ] **Step 3** — Widget test: the dialog shows the kind + sublabel; selecting still returns the same `(name, systems, mode, genre, tone)` record.
- [ ] **Step 4** — Commit `feat(campaign): play-fantasy preset labels`.

### Task 6.2: Campaign identity storage + launcher render (#11)

**Files:** Modify `lib/engine/models.dart` (`SessionMeta` `:3561-3602`), `SessionsNotifier.create`, launcher/shell list rows.

- [ ] **Step 1** — Failing test (`test/session_meta_identity_test.dart`): `SessionMeta` carries `identityColor` (int ARGB) + `identityIcon` (String key), default null, round-trips through `toJson`/`fromJson`, preserved by `copyWith`.
- [ ] **Step 2** — Run → FAIL.
- [ ] **Step 3** — Add `final int? identityColor; final String? identityIcon;` to `SessionMeta`; thread through constructor/`copyWith`/`toJson`/`fromJson`. At creation, derive defaults from the chosen preset (preset icon + a hue from the identity-hue table in the handoff: Terracotta/Sage/Indigo/Plum/Gold, round-robin or by ruleset). Genre stays in `CampaignSettings`.
- [ ] **Step 4** — Run → PASS.
- [ ] **Step 5** — Render launcher/shell campaign rows (`launcher_screen.dart:173`, `home_shell.dart:76`): 6px color spine (`identityColor`) + icon tile + name + `genre · <systems>` subtitle + small system dots (reduce the raw `formatSystems` tags to dots). The launcher must now also read the per-campaign `CampaignSettings` to show genre — add that read (note: currently it does not). Carry `identityColor` into the campaign's HUD accent for continuity.
- [ ] **Step 6** — Widget test: a campaign with an identity color renders the spine + icon; genre line appears.
- [ ] **Step 7** — Commit `feat(launcher): per-campaign identity color/icon + genre line`.

### Task 6.3: Iconography audit (#12)

**Files:** Modify the app-bar `IconButton`s in `home_shell.dart` + the mode toggle.

- [ ] **Step 1** — Audit app-bar icons so no two affordances share a glyph: Tool search → a command mark labeled "Find tools & rolls"; journal entry filter → a distinct funnel/`⌕` kept inside the Assistant rail; replace the ambiguous Party⇄GM "person+" with a labeled `SegmentedButton` (`Party | GM`) persisting per campaign via the existing `modeProvider`/`setMode`.
- [ ] **Step 2** — Widget test: the mode toggle is a segmented control showing the active mode; flipping it calls `setMode`.
- [ ] **Step 3** — Commit `feat(ui): icon audit + labeled Party/GM segmented toggle`.

---

## Final verification

- [ ] Run `flutter analyze` → no new warnings (the `dart format` hook keeps files formatted).
- [ ] Run `flutter test` → full suite green.
- [ ] Run `flutter test integration_test/ai_flows_test.dart -d macos` → AI flows still pass (Phase 2 touched AI affordances).
- [ ] Device-verify the motion/feel items the handoff calls out (AI nudge sheen, `✦` bob, dock smooth-scroll, HUD tier collapse) on macOS — honoring reduced-motion. Widget tests cover state; feel is device-verified (per repo convention).
- [ ] Update `CLAUDE.md` "Project notes" + auto-memory with the new tokens/fonts, the rail→dock merge, and the resume/dashboard/lead-card surfaces.

---

## Self-review notes

- **Spec coverage:** all 12 handoff items + tokens + empty states map to a task (see Reconciliation table → Phase headers). #2 is realized as the merge (locked decision), not a separate widget.
- **Type consistency:** `JuiceTokens` field names are referenced identically in Phases 1–6 (`tk.terracotta`, `tk.resultHeroGradient`, `tk.chaosChipBg`, etc.); `togglePin(String id)`, `JournalEntry.pinned`, `aiNudgeSeenProvider`/`markSeen`, `SessionMeta.identityColor/identityIcon` are defined once and reused.
- **Decisions honored:** typography+narrative-only scope (M3 ColorScheme retained in `theme.dart`); fonts bundled (no `google_fonts`); dock merged into the rail's single pipeline.
- **Open items for execution-time judgment:** exact identity-hue assignment per preset (#11), and whether `SessionMeta.lastOpenedAt` is needed for zero-entry campaigns (#1) — both noted inline, neither blocks.
