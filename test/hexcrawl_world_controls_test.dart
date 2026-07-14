import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
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

/// Fixed sessions so gating doesn't depend on the SharedPreferences mock cache.
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
  SharedPreferences.setMockInitialValues({});
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

/// Hexcrawl generation is a secondary control, so it lives behind the map
/// chrome's Tools toggle — open it before asserting on the gate.
Future<void> _openTools(WidgetTester t) async {
  await t.tap(find.byKey(const Key('map-tools-toggle')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('hexcrawl controls appear when the flag is on', (t) async {
    await _pump(t, hexcrawl: true);
    await _openTools(t);
    expect(find.byKey(const Key('hexcrawl-generate-region')), findsOneWidget);
  });

  testWidgets('hexcrawl controls hidden when the flag is off', (t) async {
    await _pump(t, hexcrawl: false);
    await _openTools(t);
    expect(find.byKey(const Key('hexcrawl-generate-region')), findsNothing);
  });
}
