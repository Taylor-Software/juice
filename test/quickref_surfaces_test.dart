import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/quick_ref.dart';
import 'package:loreseer/features/quick_ref_view.dart';
import 'package:loreseer/state/providers.dart';

void main() {
  testWidgets('showQuickRef opens the active card', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        systemQuickRefProvider.overrideWithValue(kSystemQuickRefs['cairn']),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showQuickRef(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Cairn — Quick Reference'), findsOneWidget);
  });
}
