import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/home_shell.dart';

typedef NewCampaignResult = ({
  String name,
  Set<String> systems,
  CampaignMode mode,
  String genre,
  String tone,
});

void main() {
  testWidgets('kSystemBlurbs covers every known system', (tester) async {
    for (final id in kKnownSystems) {
      expect(kSystemBlurbs[id], isNotNull, reason: id);
    }
  });

  testWidgets('tapping a ruleset preset selects its systems + mode',
      (tester) async {
    NewCampaignResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showDialog<NewCampaignResult>(
              context: context,
              builder: (_) => const NewCampaignDialog(),
            );
          },
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Cairn Run');
    await tester.tap(find.byKey(const Key('preset-solo-cairn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(result!.name, 'Cairn Run');
    expect(result!.mode, CampaignMode.party);
    expect(result!.systems, {'cairn', 'juice', 'party'});
  });

  testWidgets('GM toolkit preset returns gm mode', (tester) async {
    NewCampaignResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showDialog<NewCampaignResult>(
              context: context,
              builder: (_) => const NewCampaignDialog(),
            );
          },
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-campaign-name')), 'Table');
    await tester.tap(find.byKey(const Key('preset-gm-toolkit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(result!.mode, CampaignMode.gm);
    expect(result!.systems, {'juice', 'mythic'});
  });

  testWidgets('Custom reveals grouped picker; ruleset is single-select',
      (tester) async {
    NewCampaignResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showDialog<NewCampaignResult>(
              context: context,
              builder: (_) => const NewCampaignDialog(),
            );
          },
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Custom');
    await tester.tap(find.byKey(const Key('preset-custom')));
    await tester.pumpAndSettle();
    // grouped picker is now visible
    expect(find.byKey(const Key('ruleset-dnd')), findsOneWidget);
    expect(find.byKey(const Key('cat-cards')), findsOneWidget);
    // pick a ruleset + an oracle add-on (scroll into view — dialog scrolls)
    await tester.ensureVisible(find.byKey(const Key('ruleset-dnd')));
    await tester.tap(find.byKey(const Key('ruleset-dnd')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cat-cards')));
    await tester.tap(find.byKey(const Key('cat-cards')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create'));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(result!.systems.contains('dnd'), isTrue);
    expect(result!.systems.contains('cards'), isTrue);
  });
}
