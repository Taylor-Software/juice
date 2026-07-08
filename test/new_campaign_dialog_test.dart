import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/loop_kit.dart';
import 'package:juice_oracle/shared/home_shell.dart';

typedef NewCampaignResult = ({
  String name,
  Set<String> systems,
  String genre,
  String tone,
  String start,
  String seedSystem,
  LoopKit? kit,
  String defaultOracle,
});

// Helper: open the dialog and return a reference to the future result.
Future<NewCampaignResult?> _open(WidgetTester tester) async {
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
  // Step-0 Next is gated on a non-blank campaign name; provide one so callers
  // that navigate onward aren't stranded. Tests asserting a specific name
  // re-enter it before reading the result.
  await tester.enterText(
      find.byKey(const Key('new-campaign-name')), 'Test Campaign');
  await tester.pump();
  return result; // will still be null; caller must update after dialog closes
}

// Walk the wizard to the Create button and tap it.
// Assumes the dialog is already open and step 0 has a stance pre-selected.
Future<void> _walkToCreate(WidgetTester tester) async {
  // Flush any pending name-entry rebuild so step-0 Next is enabled (Next is
  // gated on a non-blank campaign name).
  await tester.pump();
  // Step 0 → Next
  await tester.tap(find.byKey(const Key('wizard-next')));
  await tester.pumpAndSettle();
  // Step 1 → Next
  await tester.tap(find.byKey(const Key('wizard-next')));
  await tester.pumpAndSettle();
  // Step 2 → Create
  await tester.tap(find.byKey(const Key('wizard-create')));
  await tester.pumpAndSettle();
}

void main() {
  // ── Step 0: name ─────────────────────────────────────────────────────────

  testWidgets('walking to Create yields the entered name', (tester) async {
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
        find.byKey(const Key('new-campaign-name')), 'Solo Member');
    await tester.pump();
    await _walkToCreate(tester);

    expect(result!.name, 'Solo Member');
  });

  // ── Navigation gating ─────────────────────────────────────────────────────

  testWidgets(
      'step 0 Next requires a name: disabled while blank, '
      'enabled once named', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            await showDialog<NewCampaignResult>(
              context: context,
              builder: (_) => const NewCampaignDialog(),
            );
          },
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // step 0, name still blank

    // Default stance (solo-member) is selected but the name is empty, so Next
    // stays disabled — this is the fix for the "Create never becomes clickable"
    // dead-end (the required field lived a step away from the disabled button).
    FilledButton nextBtn() =>
        tester.widget<FilledButton>(find.byKey(const Key('wizard-next')));
    expect(nextBtn().onPressed, isNull,
        reason: 'Next should be disabled while the name is blank');

    // Naming the campaign enables Next.
    await tester.enterText(find.byKey(const Key('new-campaign-name')), 'Named');
    await tester.pump();
    expect(nextBtn().onPressed, isNotNull,
        reason: 'Next should be enabled once a name is entered');
  });

  testWidgets('Back button returns to previous step', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            await showDialog<NewCampaignResult>(
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
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    // Step 0 → 1
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ruleset-none')), findsOneWidget);

    // Back → 0
    await tester.tap(find.byKey(const Key('wizard-back')));
    await tester.pumpAndSettle();
  });

  testWidgets('Create button is only on step 2', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            await showDialog<NewCampaignResult>(
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
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    // Step 0: no Create
    expect(find.byKey(const Key('wizard-create')), findsNothing);
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    // Step 1: no Create
    expect(find.byKey(const Key('wizard-create')), findsNothing);
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    // Step 2: Create is present
    expect(find.byKey(const Key('wizard-create')), findsOneWidget);
  });

  // ── Step 1: ruleset + addon chips ─────────────────────────────────────────

  testWidgets(
      'step 1 shows ruleset chips and addon chips; preview pane present',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            await showDialog<NewCampaignResult>(
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
    // Name it so step-0 Next is enabled, then advance to step 1.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ruleset-none')), findsOneWidget);
    expect(find.byKey(const Key('ruleset-dnd')), findsOneWidget);
    expect(find.byKey(const Key('cat-cards')), findsOneWidget);
    expect(find.byKey(const Key('cat-party')), findsOneWidget);
  });

  testWidgets('ruleset single-select + addon toggle flow into result systems',
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
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Custom');
    // Step 0 → Next
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    // Pick dnd ruleset
    await tester.ensureVisible(find.byKey(const Key('ruleset-dnd')));
    await tester.tap(find.byKey(const Key('ruleset-dnd')));
    await tester.pumpAndSettle();
    // Add cards addon
    await tester.ensureVisible(find.byKey(const Key('cat-cards')));
    await tester.tap(find.byKey(const Key('cat-cards')));
    await tester.pumpAndSettle();

    // Step 1 → Next → Step 2 → Create
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-create')));
    await tester.pumpAndSettle();

    expect(result!.systems, containsAll(['dnd', 'cards']));
    expect(result!.systems, isNot(contains('ironsworn')));
  });

  testWidgets('default oracle defaults to juice', (tester) async {
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
        find.byKey(const Key('new-campaign-name')), 'Oracle Default');
    await _walkToCreate(tester);
    expect(result!.defaultOracle, 'juice');
  });

  testWidgets('picking the Tarot oracle sets it + pulls in the cards system',
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
        find.byKey(const Key('new-campaign-name')), 'Tarot Game');
    await tester.pump();
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('oracle-choice-tarot')));
    await tester.tap(find.byKey(const Key('oracle-choice-tarot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-create')));
    await tester.pumpAndSettle();
    expect(result!.defaultOracle, 'tarot');
    expect(result!.systems, contains('cards'));
  });

  // ── Step 2: funnel gating ─────────────────────────────────────────────────

  testWidgets('new-start-funnel shown for dcc (funnel-capable) ruleset',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            await showDialog<NewCampaignResult>(
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
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    // Step 0 → 1
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    // Select dcc ruleset (funnel-capable) — inside the Experimental drawer
    await tester.tap(find.byKey(const Key('ruleset-experimental')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ruleset-dcc')));
    await tester.tap(find.byKey(const Key('ruleset-dcc')));
    await tester.pumpAndSettle();

    // Step 1 → 2
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-start-funnel')), findsOneWidget);
    expect(find.byKey(const Key('new-start-roster')), findsOneWidget);
  });

  testWidgets('new-start-funnel shown for ironsworn (it has a funnel profile)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            await showDialog<NewCampaignResult>(
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
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    // Step 0 → 1
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    // Select ironsworn (has a funnel profile)
    await tester.ensureVisible(find.byKey(const Key('ruleset-ironsworn')));
    await tester.tap(find.byKey(const Key('ruleset-ironsworn')));
    await tester.pumpAndSettle();

    // Step 1 → 2
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    // ironsworn has a funnel profile → funnel card is shown
    expect(find.byKey(const Key('new-start-funnel')), findsOneWidget);
    expect(find.byKey(const Key('new-start-roster')), findsOneWidget);
  });

  testWidgets('new-start-funnel hidden when ruleset is none', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            await showDialog<NewCampaignResult>(
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
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    // Default is ruleset-none; proceed to step 2
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-start-funnel')), findsNothing);
  });

  testWidgets(
      'choosing funnel puts funnel in systems + start==funnel + seedSystem',
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
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'DCC Funnel');
    // Step 0 → 1
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    // Select dcc ruleset — inside the Experimental drawer
    await tester.tap(find.byKey(const Key('ruleset-experimental')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ruleset-dcc')));
    await tester.tap(find.byKey(const Key('ruleset-dcc')));
    await tester.pumpAndSettle();

    // Step 1 → 2
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    // Choose funnel start
    await tester.tap(find.byKey(const Key('new-start-funnel')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('wizard-create')));
    await tester.pumpAndSettle();

    expect(result!.start, 'funnel');
    expect(result!.systems, contains('funnel'));
    expect(result!.systems, contains('dcc'));
    expect(result!.seedSystem, 'dcc');
  });

  testWidgets('roster start has start==roster and no funnel in systems',
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
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'My Campaign');
    await _walkToCreate(tester);

    expect(result!.start, 'roster');
    expect(result!.systems, isNot(contains('funnel')));
  });

  // ── genre + tone in result ────────────────────────────────────────────────

  testWidgets('genre and tone fields appear on step 2 and flow into result',
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
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Genre Test');
    // Navigate to step 2
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('new-campaign-genre')), 'grimdark');
    await tester.enterText(find.byKey(const Key('new-campaign-tone')), 'tense');

    await tester.tap(find.byKey(const Key('wizard-create')));
    await tester.pumpAndSettle();

    expect(result!.genre, 'grimdark');
    expect(result!.tone, 'tense');
  });

  // ── old test coverage: custom picker ─────────────────────────────────────
  // (Replaces the old preset-grid assertions with wizard flow.)

  testWidgets('Custom picker: excluding party and including verdant via wizard',
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
        find.byKey(const Key('new-campaign-name')), 'No Party');
    await tester.pump(); // flush so step-0 Next enables

    // Step 0 → 1
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    // Pick ironsworn ruleset
    await tester.ensureVisible(find.byKey(const Key('ruleset-ironsworn')));
    await tester.tap(find.byKey(const Key('ruleset-ironsworn')));
    await tester.pumpAndSettle();
    // Add verdant, remove party (party is pre-checked)
    await tester.ensureVisible(find.byKey(const Key('cat-verdant')));
    await tester.tap(find.byKey(const Key('cat-verdant')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cat-party')));
    await tester.tap(find.byKey(const Key('cat-party')));
    await tester.pumpAndSettle();
    // Also add mythic
    await tester.ensureVisible(find.byKey(const Key('cat-mythic')));
    await tester.tap(find.byKey(const Key('cat-mythic')));
    await tester.pumpAndSettle();

    // Step 1 → 2 → Create
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-create')));
    await tester.pumpAndSettle();

    expect(result!.systems, isNot(contains('party')));
    expect(result!.systems,
        containsAll(['juice', 'mythic', 'ironsworn', 'verdant']));
  });

  // ── Step 2: import-a-kit ──────────────────────────────────────────────────

  testWidgets('Step 2 "Import a kit" lists provided kits and returns the pick',
      (tester) async {
    const kits = [
      LoopKit(name: 'Ash and Embers', system: 'ironsworn'),
      LoopKit(name: 'Sunken Crypt', system: 'dnd'),
    ];
    NewCampaignResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showDialog<NewCampaignResult>(
              context: context,
              builder: (_) => const NewCampaignDialog(kits: kits),
            );
          },
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Step-0 Next is gated on a non-blank campaign name; set one so the walk
    // onward isn't blocked. Tests that assert a specific name re-enter it below.
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Test Campaign');
    await tester.pump();

    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Kit Test');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-next'))); // step 0 -> 1
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-next'))); // step 1 -> 2
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new-start-kit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kit-pick-0')), findsOneWidget);
    expect(find.byKey(const Key('kit-pick-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('kit-pick-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-create')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.start, 'kit');
    expect(result!.kit?.name, 'Sunken Crypt');
  });

  testWidgets('Step 2 has no kit card when no kits are provided',
      (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-start-kit')), findsNothing);
  });
}
