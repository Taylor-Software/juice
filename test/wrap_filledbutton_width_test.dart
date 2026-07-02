import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

// Guards the natural-width overrides on FilledButtons that live inside Wraps
// (loop_bar / dcc_sheet / sidekick_screen / funnel_sheet / party_emulator_screen).
//
// Under the real AppTheme the filledButtonTheme sets a full-width
// Size.fromHeight(48) minimumSize (min-width == infinity). A FilledButton in a
// *bounded* Wrap does NOT crash (RenderWrap hands children a finite maxWidth) —
// but it STRETCHES to the whole run unless it pins a finite min-width. Those
// call sites add `FilledButton.styleFrom(minimumSize: Size(0, 48))` to stay
// natural-width; this test documents why and stops the overrides being removed
// as "pointless".
void main() {
  testWidgets('themed FilledButton in a bounded Wrap stretches without override',
      (t) async {
    await t.pumpApp(SizedBox(
      width: 600,
      child: Wrap(children: [
        FilledButton(onPressed: () {}, child: const Text('Roll')),
      ]),
    ));
    expect(t.takeException(), isNull); // bounded Wrap => no infinite-width crash
    expect(t.getSize(find.byType(FilledButton)).width, greaterThan(400));
  });

  testWidgets('the Size(0, 48) override keeps it natural-width', (t) async {
    await t.pumpApp(SizedBox(
      width: 600,
      child: Wrap(children: [
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () {},
          child: const Text('Roll'),
        ),
      ]),
    ));
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(FilledButton)).width, lessThan(200));
  });
}
