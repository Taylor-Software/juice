import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/campaign_surfaces.dart';
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

void main() {
  test('normalizeExclusive keeps the first member by group order', () {
    expect(normalizeExclusive({'juice', 'verdant', 'hexcrawl'}),
        {'juice', 'verdant'});
    expect(normalizeExclusive({'hexcrawl'}), {'hexcrawl'});
    expect(normalizeExclusive({'juice', 'party'}), {'juice', 'party'});
    expect(normalizeExclusive(const {}), isEmpty);
  });

  test('kExclusiveSystemIds flattens group members', () {
    expect(kExclusiveSystemIds, containsAll(['verdant', 'hexcrawl']));
  });

  // Guard test: both the creation wizard and the edit-systems dialog exclude
  // EVERY id in kExclusiveSystemIds from their generic chip loops and
  // instead render them via a hand-written radio row hardcoded to
  // kExclusiveGroups['hex-flavor']. That wiring works today because
  // 'hex-flavor' is the only exclusive group, but nothing enforces it — a
  // second exclusive group added to kExclusiveGroups without a matching
  // radio row in both dialogs would have its members silently unreachable
  // (skipped by the generic loop AND never rendered by the hardcoded row).
  // These two tests pin today's set of exclusive ids to a rendered chip in
  // both dialogs, so extending kExclusiveGroups without wiring the new
  // group's UI fails loudly here instead of shipping a dead system id.
  testWidgets(
      'wizard step 1 renders a cat-<id> chip for every kExclusiveSystemIds',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showDialog<void>(
              context: context, builder: (_) => const NewCampaignDialog()),
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();
    await tester.tap(find.byKey(const Key('wizard-next'))); // step 0 -> 1
    await tester.pumpAndSettle();

    for (final id in kExclusiveSystemIds) {
      await tester.ensureVisible(find.byKey(Key('cat-$id')));
      expect(find.byKey(Key('cat-$id')), findsOneWidget,
          reason: '$id belongs to kExclusiveSystemIds but the wizard never '
              'renders a cat-$id chip for it');
    }
  });

  testWidgets(
      'edit-systems dialog renders an edit-sys-<id> chip for every '
      'kExclusiveSystemIds', (t) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {
            'id': 'default',
            'name': 'Camp',
            'systems': ['juice']
          }
        ],
      }),
    });
    await t.pumpWidget(ProviderScope(
      overrides: _overrides,
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Campaigns'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Edit systems'));
    await t.pumpAndSettle();

    for (final id in kExclusiveSystemIds) {
      await t.ensureVisible(find.byKey(Key('edit-sys-$id')));
      expect(find.byKey(Key('edit-sys-$id')), findsOneWidget,
          reason: '$id belongs to kExclusiveSystemIds but the edit-systems '
              'dialog never renders an edit-sys-$id chip for it');
    }
  });
}
