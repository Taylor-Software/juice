import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/map_builder.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/map_screen.dart';
import 'package:juice_oracle/state/providers.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));
HexcrawlData _hex() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

class _FixedSessions extends SessionsNotifier {
  _FixedSessions(this.systems);
  final List<String> systems;
  @override
  Future<SessionsState> build() async => SessionsState(
        active: 'default',
        sessions: [SessionMeta(id: 'default', name: 'M', systems: systems)],
      );
}

Future<void> _pump(WidgetTester t, {required bool hexcrawl}) async {
  // Seed the real MapNotifier via prefs (the scoped key is
  // juice.map.v1.<activeSession>; active = 'default') so save() works.
  const seeded = MapState(
    hexes: [
      HexCell(
          col: 0, row: 0, envRow: 1, terrain: 'hills', site: 'Cave or grotto')
    ],
    currentHexCol: 0,
    currentHexRow: 0,
  );
  SharedPreferences.setMockInitialValues({
    'flutter.juice.map.v1.default': jsonEncode(seeded.toJson()),
  });
  await t.pumpWidget(ProviderScope(
    overrides: [
      hexcrawlDataProvider.overrideWith((ref) async => _hex()),
      sessionsProvider.overrideWith(
          () => _FixedSessions(hexcrawl ? ['juice', 'hexcrawl'] : ['juice'])),
    ],
    child: MaterialApp(home: Scaffold(body: HexMapPane(oracle: _oracle()))),
  ));
  await t.pumpAndSettle();
}

Future<void> _tapOriginHex(WidgetTester t) async {
  final cells = [
    (col: 0, row: 0),
    ...hexNeighbors(0, 0),
  ];
  final minCol = cells.map((c) => c.col).reduce(min);
  final minRow = cells.map((c) => c.row).reduce(min);
  final local = hexCenterFor(0, 0, minCol, minRow, 34.0);
  final tl = t.getTopLeft(find.byKey(const Key('hex-canvas')));
  await t.tapAt(tl + local);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('site detail card shows Crawl/Full controls (hexcrawl on)',
      (t) async {
    await _pump(t, hexcrawl: true);
    await _tapOriginHex(t);
    expect(find.byKey(const Key('site-crawl')), findsOneWidget);
    expect(find.byKey(const Key('site-full')), findsOneWidget);
  });

  testWidgets('Full site writes a writeup line + reveals the Log button',
      (t) async {
    await _pump(t, hexcrawl: true);
    await _tapOriginHex(t);
    await t.tap(find.byKey(const Key('site-full')));
    await t.pumpAndSettle();
    expect(find.textContaining('Held by:'), findsOneWidget);
    expect(find.byKey(const Key('site-log')), findsOneWidget);
  });

  testWidgets('no detail card when the hexcrawl flag is off', (t) async {
    await _pump(t, hexcrawl: false);
    await _tapOriginHex(t);
    expect(find.byKey(const Key('hex-detail-card')), findsNothing);
  });
}
