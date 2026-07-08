import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/oracle_constructor.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await c.read(constructedOraclesProvider.future);
  return c;
}

Future<void> _pumpOpener(WidgetTester t, ProviderContainer c) async {
  t.view.physicalSize = const Size(700, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          return Center(
            child: ElevatedButton(
              onPressed: () => showOracleConstructor(context, ref, null),
              child: const Text('open'),
            ),
          );
        }),
      ),
    ),
  ));
}

void main() {
  testWidgets('constructor builds and saves an oracle', (t) async {
    final c = await _container();
    await _pumpOpener(t, c);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('oracle-name')), 'Grim Fate');
    await t.enterText(find.byKey(const Key('oracle-formula')), '2d6');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('oracle-save')));
    await t.pumpAndSettle();

    final saved = c.read(constructedOraclesProvider).value!;
    expect(saved.single.name, 'Grim Fate');
    expect(saved.single.notation, '2d6');
  });

  testWidgets(
      'advantage/disadvantage control appears only for 2+ dice; dF chip sets '
      'fate; mode persists', (t) async {
    final c = await _container();
    await _pumpOpener(t, c);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // Single die → no adv/disadv control.
    expect(find.byKey(const Key('oracle-mode')), findsNothing);

    // dF chip sets a fate formula.
    await t.tap(find.byKey(const Key('oracle-die-F')));
    await t.pumpAndSettle();
    // 2+ dice → the mode control shows; pick Advantage.
    await t.enterText(find.byKey(const Key('oracle-formula')), '2d20');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('oracle-mode')), findsOneWidget);
    await t.tap(find.text('Advantage'));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('oracle-name')), 'Edge');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('oracle-save')));
    await t.pumpAndSettle();
    final saved = c.read(constructedOraclesProvider).value!.single;
    expect(saved.notation, '2d20');
    expect(saved.mode.name, 'advantage');
  });

  testWidgets('save is disabled without a name and blocked below 2 bands',
      (t) async {
    final c = await _container();
    await _pumpOpener(t, c);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // No name yet → Save disabled.
    final saveBtn =
        t.widget<FilledButton>(find.byKey(const Key('oracle-save')));
    expect(saveBtn.onPressed, isNull);

    // Turning off all but one band is prevented (>=2 guard): unselect 4 of 6.
    await t.enterText(find.byKey(const Key('oracle-name')), 'X');
    await t.pumpAndSettle();
    for (final b in ['yesAnd', 'yes', 'yesBut', 'noBut']) {
      await t.tap(find.byKey(Key('oracle-band-$b')));
      await t.pumpAndSettle();
    }
    // Two bands remain (no, noAnd); tapping one more is a no-op.
    await t.tap(find.byKey(const Key('oracle-band-no')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('oracle-save')));
    await t.pumpAndSettle();
    expect(c.read(constructedOraclesProvider).value!.single.bands.length, 2);
  });
}
