// Device integration test for the map snapshot → journal annotation flow.
//
// Unit tests can't exercise this end to end: RenderRepaintBoundary.toImage
// needs a real engine, and the flow opens the sketch-editor route + uses the
// real (path_provider-backed) BlobStore. This test drives it on a device,
// tapping by widget Key (the app's UI resists synthetic OS clicks, so
// pixel-driving the verbs is unreliable — see the juice-browser-verify note).
//
// Run: flutter test integration_test/map_snapshot_test.dart -d macos

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/map_screen.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('World map snapshot → annotate → journal sketch entry',
      (tester) async {
    // Seed a session + a one-hex World map so the canvas (and the
    // RepaintBoundary the snapshot captures) renders instead of the empty state.
    const map = MapState(hexes: [HexCell(col: 0, row: 0, envRow: 1)]);
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.map.v1.default': jsonEncode(map.toJson()),
    });

    final oracle = Oracle(OracleData(
        jsonDecode(await rootBundle.loadString('assets/oracle_data.json'))
            as Map<String, dynamic>));

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: HexMapPane(oracle: oracle))),
    ));
    await tester.pumpAndSettle();

    // The web-gated snapshot button is present (blob store available; region zoom).
    final snapBtn = find.byKey(const Key('map-snapshot'));
    expect(snapBtn, findsOneWidget);

    // Tap it → captures the full map, opens the sketch editor over the raster.
    await tester.tap(snapBtn);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sketch-canvas')), findsOneWidget,
        reason: 'snapshot should open the sketch editor');

    // Draw an annotation stroke, then save.
    final canvas = find.byKey(const Key('sketch-canvas'));
    final g = await tester.startGesture(tester.getCenter(canvas));
    await g.moveBy(const Offset(60, 40));
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();

    // A sketch journal entry now exists, backed by the captured map raster
    // (backgroundBlobId) and carrying our annotation stroke.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HexMapPane)));
    final entries = await container.read(journalProvider.future);
    final sketches =
        entries.where((e) => e.kind == JournalKind.sketch).toList();
    expect(sketches, hasLength(1));
    final sketch = sketches.single.payload!['sketch'] as Map<String, dynamic>;
    expect(sketch['bg'], isNotNull); // background = the map snapshot blob
    expect(sketch['strokes'] as List, isNotEmpty); // our annotation stroke
  });
}
