import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OUTER-chrome vertical-overflow harness for the Journal body.
///
/// Distinct from the AI-nudge case in journal_payload_ui_test.dart: here AI is
/// OFF and the nudge is marked seen, so the only fixed chrome above/below the
/// entry list is the assistant rail + the suggestion row + the inline roll dock
/// + the composer. At very short heights those fixed siblings alone summed
/// taller than the available height, so the `Expanded` entry region collapsed
/// to 0 and the fixed chrome overflowed (RenderFlex overflowed by N px). This
/// isolates that OUTER body case.
///
/// The journal body is pumped inside a fixed `SizedBox(width: 700, height: H)`.
/// 700 wide avoids an unrelated narrow-width AiBadge Row squeeze below ~360px;
/// height is the axis under test.

const _sessionPrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
};

// A non-empty journal whose prose has three recurring proper nouns, so the
// suggestion row renders its full three "Track X?" chips — realistic fixed
// chrome above the dock + composer (this is what tips the bare chrome over the
// available height at short viewports). The pre-fix RenderFlex overflow shows
// up at the small heights below; without the chips the fixed chrome is thinner
// and the threshold is lower, but the failure mode is identical.
const _entryJson = '{'
    '"id":"e1",'
    '"timestamp":"2026-06-12T10:00:00.000Z",'
    '"title":"Scene",'
    '"body":"Gorath met Mira near Vault. Gorath warned Mira. The Vault held secrets.",'
    '"kind":"note",'
    '"tags":[]'
    '}';

Map<String, Object> _prefs() => {
      ..._sessionPrefs,
      'juice.journal.v2.default': '[$_entryJson]',
      // AI off (default) but mark the nudge seen so the tall nudge card does
      // not render — this isolates the OUTER chrome, not the nudge case.
      'juice.ai_nudge_seen.v1': true,
    };

Future<void> pumpJournalAt(WidgetTester tester, double height,
    {double width = 700}) async {
  SharedPreferences.setMockInitialValues(_prefs());
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: const JournalScreen(),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // After the fix, the body must not overflow at ANY height — covering both the
  // requested set {300, 360, 400, 500, 900} and the small heights where the
  // fixed chrome genuinely exceeds the viewport (this fixture's chrome overflows
  // pre-fix at ~<=285px; see the dedicated "overflows pre-fix" reasoning below).
  for (final h in <double>[200, 240, 280, 300, 360, 400, 500, 900]) {
    testWidgets('journal body does not overflow at height $h', (tester) async {
      await pumpJournalAt(tester, h);
      expect(tester.takeException(), isNull,
          reason: 'journal body overflowed at height $h');
    });
  }

  // The three small heights (200/240/280) are the ones that produce a RenderFlex
  // overflow on the pre-fix `Column[ ..., Expanded(list), suggestionRow, dock,
  // composer ]` layout: the Expanded collapses to 0 and the fixed siblings spill.
  // The suggestion chips must be present (they are part of the chrome that tips
  // the balance) so this stays a faithful reproduction.
  testWidgets('suggestion chips render (realistic chrome) at a short height',
      (tester) async {
    await pumpJournalAt(tester, 300);
    expect(find.byType(InputChip), findsNWidgets(3));
  });

  testWidgets('comfortable height (900) keeps composer + entry visible',
      (tester) async {
    await pumpJournalAt(tester, 900);
    expect(tester.takeException(), isNull);
    // Composer present and usable (the text input must stay reachable).
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
    expect(find.byKey(const Key('journal-send')), findsOneWidget);
    // Seeded entry renders normally.
    expect(find.textContaining('Gorath'), findsWidgets);
  });

  testWidgets('composer remains present at the shortest height (200)',
      (tester) async {
    await pumpJournalAt(tester, 200);
    expect(tester.takeException(), isNull);
    // Composer must stay reachable even when squeezed.
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets('journal body does not overflow at phone size (375×812)',
      (tester) async {
    // The wedge form factor: dock chips + composer + suggestion row must all
    // fit a real phone width without horizontal overflow.
    await pumpJournalAt(tester, 812, width: 375);
    expect(tester.takeException(), isNull,
        reason: 'journal body overflowed at 375px width');
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  // The body is one tree at every height: a box of max(viewport, 360) inside an
  // always-present scroll view. The height branch this replaced was what
  // destroyed the composer mid-keystroke (see journal_composer_focus_test).
  // These pin the two ends of that sizing so the outer scroll view can't start
  // scrolling where the layout used to be rigid.
  ScrollPosition bodyScroll(WidgetTester t) =>
      t.state<ScrollableState>(find.byType(Scrollable).first).position;

  testWidgets('the body does not scroll when the viewport has room',
      (tester) async {
    await pumpJournalAt(tester, 900);
    final p = bodyScroll(tester);
    expect(p.maxScrollExtent, 0,
        reason:
            'a roomy journal must stay rigid — the box equals the viewport, '
            'so the outer scroll view has nothing to scroll');
  });

  testWidgets('the body scrolls once squeezed past the floor', (tester) async {
    await pumpJournalAt(tester, 240);
    final p = bodyScroll(tester);
    expect(p.maxScrollExtent, greaterThan(0),
        reason: 'a squeezed journal holds its 360 floor and scrolls over it, '
            'rather than collapsing the entry list and spilling the chrome');
  });
}
