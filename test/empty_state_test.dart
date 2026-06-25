import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/empty_state.dart';
import 'package:juice_oracle/shared/theme.dart';

void main() {
  testWidgets('renders title, body, and fires the primary action', (t) async {
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: EmptyState(
          title: 'Every story needs a hero.',
          body: 'Create your first character.',
          primaryLabel: 'Create character',
          onPrimary: () => tapped = true,
        ),
      ),
    ));
    expect(find.text('Every story needs a hero.'), findsOneWidget);
    expect(find.text('Create your first character.'), findsOneWidget);
    await t.tap(find.byKey(const Key('empty-state-primary')));
    expect(tapped, isTrue);
  });
}
