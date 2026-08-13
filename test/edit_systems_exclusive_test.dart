import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/emulator_data.dart';
import 'package:loreseer/engine/hexcrawl_data.dart';
import 'package:loreseer/engine/oracle.dart';
import 'package:loreseer/engine/oracle_data.dart';
import 'package:loreseer/engine/verdant_data.dart';
import 'package:loreseer/shared/home_shell.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));
final _verdant = VerdantData(
    jsonDecode(File('assets/verdant_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _emu = EmulatorData(
    jsonDecode(File('assets/emulator_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _hex = HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

final _overrides = [
  verdantDataProvider.overrideWith((ref) async => _verdant),
  emulatorDataProvider.overrideWith((ref) async => _emu),
  hexcrawlDataProvider.overrideWith((ref) async => _hex),
];

// Opens the Campaigns dialog and taps the (single, default-session) "Edit
// systems" tooltip icon, landing on the private _EditSystemsDialog.
Future<void> _openEditSystems(WidgetTester t) async {
  await t.tap(find.byTooltip('Campaigns'));
  await t.pumpAndSettle();
  await t.tap(find.byTooltip('Edit systems'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'legacy both-on seed (verdant + hexcrawl): saving untouched keeps '
      'verdant, drops hexcrawl (normalizeExclusive keeps first by group '
      'order)', (t) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {
            'id': 'default',
            'name': 'Camp',
            'systems': ['juice', 'verdant', 'hexcrawl'],
          }
        ],
      }),
    });
    await t.pumpWidget(ProviderScope(
      overrides: _overrides,
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    await _openEditSystems(t);

    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    final container =
        ProviderScope.containerOf(t.element(find.byType(HomeShell)));
    final systems =
        container.read(sessionsProvider).valueOrNull!.activeMeta.enabledSystems;
    expect(systems, contains('verdant'));
    expect(systems, isNot(contains('hexcrawl')));
  });

  testWidgets('tapping edit-sys-hexcrawl then Save swaps in hexcrawl',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {
            'id': 'default',
            'name': 'Camp',
            'systems': ['juice', 'verdant'],
          }
        ],
      }),
    });
    await t.pumpWidget(ProviderScope(
      overrides: _overrides,
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();

    final container =
        ProviderScope.containerOf(t.element(find.byType(HomeShell)));

    await _openEditSystems(t);
    await t.ensureVisible(find.byKey(const Key('edit-sys-hexcrawl')));
    await t.tap(find.byKey(const Key('edit-sys-hexcrawl')));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    final systems =
        container.read(sessionsProvider).valueOrNull!.activeMeta.enabledSystems;
    expect(systems, contains('hexcrawl'));
    expect(systems, isNot(contains('verdant')));
  });

  testWidgets('tapping edit-hexflavor-none then Save clears both flavors',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {
            'id': 'default',
            'name': 'Camp',
            'systems': ['juice', 'hexcrawl'],
          }
        ],
      }),
    });
    await t.pumpWidget(ProviderScope(
      overrides: _overrides,
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();

    final container =
        ProviderScope.containerOf(t.element(find.byType(HomeShell)));

    await _openEditSystems(t);
    await t.ensureVisible(find.byKey(const Key('edit-hexflavor-none')));
    await t.tap(find.byKey(const Key('edit-hexflavor-none')));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    final systems =
        container.read(sessionsProvider).valueOrNull!.activeMeta.enabledSystems;
    expect(systems, isNot(contains('hexcrawl')));
    expect(systems, isNot(contains('verdant')));
  });

  testWidgets(
      'party enabled + initialPartyTool emulator: an edit-party-tool-behavior '
      'chip exists; tapping it and saving returns partyTool==behavior',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {
            'id': 'default',
            'name': 'Camp',
            'systems': ['juice', 'party'],
          }
        ],
      }),
    });
    await t.pumpWidget(ProviderScope(
      overrides: _overrides,
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    await _openEditSystems(t);

    expect(find.byKey(const Key('edit-party-tool-behavior')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('edit-party-tool-behavior')));
    await t.tap(find.byKey(const Key('edit-party-tool-behavior')));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    final container =
        ProviderScope.containerOf(t.element(find.byType(HomeShell)));
    expect(
        container
            .read(sessionsProvider)
            .valueOrNull!
            .activeMeta
            .enabledPartyTool,
        'behavior');
  });

  testWidgets(
      'without party in the picked set, the party-tool row is hidden and '
      'partyTool is unchanged on save', (t) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {
            'id': 'default',
            'name': 'Camp',
            'systems': ['juice'],
            'partyTool': 'behavior',
          }
        ],
      }),
    });
    await t.pumpWidget(ProviderScope(
      overrides: _overrides,
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    await _openEditSystems(t);

    expect(find.byKey(const Key('edit-party-tool-behavior')), findsNothing);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    final container =
        ProviderScope.containerOf(t.element(find.byType(HomeShell)));
    expect(
        container
            .read(sessionsProvider)
            .valueOrNull!
            .activeMeta
            .enabledPartyTool,
        'behavior');
  });
}
