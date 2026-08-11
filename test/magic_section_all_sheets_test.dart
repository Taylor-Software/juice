import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/features/argosa_sheet.dart';
import 'package:loreseer/features/cairn_sheet.dart';
import 'package:loreseer/features/custom_sheet.dart';
import 'package:loreseer/features/dcc_sheet.dart';
import 'package:loreseer/features/dnd_sheet.dart';
import 'package:loreseer/features/draw_steel_sheet.dart';
import 'package:loreseer/features/embark_sheet.dart';
import 'package:loreseer/features/funnel_sheet.dart';
import 'package:loreseer/features/ironsworn_sheet.dart';
import 'package:loreseer/features/kal_arath_sheet.dart';
import 'package:loreseer/features/knave_sheet.dart';
import 'package:loreseer/features/nimble_sheet.dart';
import 'package:loreseer/features/ose_sheet.dart';
import 'package:loreseer/features/shadowdark_sheet.dart';
import 'package:loreseer/features/starforged_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One [Character] per premade system, seeded with the minimal sheet each
/// view requires (defaults for every sheet's const constructor already
/// satisfy this — pass `Character.forSheet(systemKey, id)` for the ones
/// with a `.premade()` factory, else the system's bare default sheet).
final _cases = <String, Widget Function(Character c)>{
  'argosa': (c) => ArgosaSheetView(character: c, onBack: () {}),
  'cairn': (c) => CairnSheetView(character: c, onBack: () {}),
  'custom': (c) => CustomSheetView(character: c, onBack: () {}),
  'dcc': (c) => DccSheetView(character: c, onBack: () {}),
  'dnd': (c) => DndSheetView(character: c, onBack: () {}),
  'draw-steel': (c) => DrawSteelSheetView(character: c, onBack: () {}),
  'embark': (c) => EmbarkSheetView(character: c, onBack: () {}),
  'funnel': (c) => FunnelSheetView(character: c, onBack: () {}),
  'ironsworn': (c) => IronswornSheetView(character: c, onBack: () {}),
  'kal-arath': (c) => KalArathSheetView(character: c, onBack: () {}),
  'knave': (c) => KnaveSheetView(character: c, onBack: () {}),
  'nimble': (c) => NimbleSheetView(character: c, onBack: () {}),
  'ose': (c) => OseSheetView(character: c, onBack: () {}),
  'shadowdark': (c) => ShadowdarkSheetView(character: c, onBack: () {}),
  'starforged': (c) => StarforgedSheetView(character: c, onBack: () {}),
};

void main() {
  for (final entry in _cases.entries) {
    testWidgets('${entry.key} sheet renders magicSection', (tester) async {
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'loreseer.sessions.v1':
            '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
      });
      final character = entry.key == 'funnel'
          ? const Character(
              id: 'c1', name: 'Funnel Test', funnel: FunnelSheet())
          : Character.forSheet(entry.key, 'c1');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: entry.value(character))),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('magic-enable')), findsOneWidget,
          reason: '${entry.key} sheet is missing magicSection');
    });
  }
}
