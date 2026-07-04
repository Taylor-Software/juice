import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/sheet_widgets.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('debounces: no save per keystroke, one save after the window',
      (tester) async {
    final saves = <String>[];
    await tester.pumpWidget(host(DebouncedTextField(
      key: const Key('f'),
      initialValue: '',
      label: 'Notes',
      onSave: saves.add,
    )));

    await tester.enterText(find.byKey(const Key('f')), 'a');
    await tester.enterText(find.byKey(const Key('f')), 'ab');
    await tester.enterText(find.byKey(const Key('f')), 'abc');
    expect(saves, isEmpty, reason: 'no save inside the debounce window');

    await tester
        .pump(DebouncedTextField.debounce + const Duration(milliseconds: 50));
    expect(saves, ['abc'], reason: 'one save with the latest text');
  });

  testWidgets('dispose flushes a pending edit post-frame', (tester) async {
    final saves = <String>[];
    await tester.pumpWidget(host(DebouncedTextField(
      key: const Key('f'),
      initialValue: '',
      label: 'Notes',
      onSave: saves.add,
    )));

    await tester.enterText(find.byKey(const Key('f')), 'draft');
    expect(saves, isEmpty);

    // Navigate away before the debounce fires: the field must not drop it.
    await tester.pumpWidget(host(const SizedBox()));
    await tester.pump();
    expect(saves, ['draft']);
  });

  testWidgets('submit flushes immediately', (tester) async {
    final saves = <String>[];
    await tester.pumpWidget(host(DebouncedTextField(
      key: const Key('f'),
      initialValue: '',
      label: 'Notes',
      onSave: saves.add,
    )));

    await tester.enterText(find.byKey(const Key('f')), 'done');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(saves, ['done']);
  });
}
