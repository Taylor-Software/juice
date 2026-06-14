import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/features/hexcrawl_screen.dart';
import 'package:juice_oracle/state/providers.dart';

HexcrawlData _data() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('rolls a weather result and shows it', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [hexcrawlDataProvider.overrideWith((ref) async => _data())],
      child: const MaterialApp(home: Scaffold(body: HexcrawlScreen())),
    ));
    await t.pumpAndSettle();

    expect(find.text('Weather'), findsWidgets);
    await t.tap(find.byKey(const Key('roll-weather')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('hexcrawl-result')), findsOneWidget);
  });
}
