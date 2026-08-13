import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/shared/home_shell.dart';

// Local mirror of NewCampaignResult so this test file can read fields off the
// popped record without importing the private wizard internals. Must match
// the shape home_shell.dart's NewCampaignDialog actually pops.
typedef _Result = ({
  String name,
  Set<String> systems,
  String genre,
  String tone,
  String start,
  String seedSystem,
  dynamic kit,
  String defaultOracle,
  String partyTool,
});

Future<_Result?> _openAndCapture(
    WidgetTester tester, Future<void> Function(WidgetTester) drive) async {
  _Result? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Builder(builder: (context) {
      return ElevatedButton(
        onPressed: () async {
          result = await showDialog<_Result>(
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
      find.byKey(const Key('new-campaign-name')), 'Test Campaign');
  await tester.pump();
  await tester.tap(find.byKey(const Key('wizard-next'))); // step 0 -> 1
  await tester.pumpAndSettle();
  await drive(tester);
  return result;
}

Future<void> _toStep2AndCreate(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('wizard-next'))); // step 1 -> 2
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('wizard-create')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'step 1 shows a Hexcrawl flavor row: none selected by default, '
      'cat-verdant + cat-hexcrawl present as radio chips', (tester) async {
    await _openAndCapture(tester, (tester) async {
      expect(find.byKey(const Key('hexflavor-none')), findsOneWidget);
      expect(find.byKey(const Key('cat-verdant')), findsOneWidget);
      expect(find.byKey(const Key('cat-hexcrawl')), findsOneWidget);
      final noneChip =
          tester.widget<ChoiceChip>(find.byKey(const Key('hexflavor-none')));
      expect(noneChip.selected, isTrue);
    });
  });

  testWidgets(
      'tapping cat-verdant then cat-hexcrawl is a radio: only hexcrawl '
      'survives in the created systems', (tester) async {
    final result = await _openAndCapture(tester, (tester) async {
      await tester.ensureVisible(find.byKey(const Key('cat-verdant')));
      await tester.tap(find.byKey(const Key('cat-verdant')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('cat-hexcrawl')));
      await tester.tap(find.byKey(const Key('cat-hexcrawl')));
      await tester.pumpAndSettle();
      await _toStep2AndCreate(tester);
    });

    expect(result!.systems, contains('hexcrawl'));
    expect(result.systems, isNot(contains('verdant')));
  });

  testWidgets(
      'party addon on: party-tool row shows emulator selected by default; '
      'tapping sidekick carries through to the result', (tester) async {
    final result = await _openAndCapture(tester, (tester) async {
      expect(find.byKey(const Key('party-tool-emulator')), findsOneWidget);
      final emulatorChip = tester
          .widget<ChoiceChip>(find.byKey(const Key('party-tool-emulator')));
      expect(emulatorChip.selected, isTrue);

      await tester.ensureVisible(find.byKey(const Key('party-tool-sidekick')));
      await tester.tap(find.byKey(const Key('party-tool-sidekick')));
      await tester.pumpAndSettle();
      await _toStep2AndCreate(tester);
    });

    expect(result!.partyTool, 'sidekick');
  });

  testWidgets(
      'turning the party addon off hides the party-tool row and the result '
      'still carries the default partyTool', (tester) async {
    final result = await _openAndCapture(tester, (tester) async {
      await tester.ensureVisible(find.byKey(const Key('cat-party')));
      await tester.tap(find.byKey(const Key('cat-party'))); // party off
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('party-tool-emulator')), findsNothing);
      await _toStep2AndCreate(tester);
    });

    expect(result!.partyTool, 'emulator');
  });
}
