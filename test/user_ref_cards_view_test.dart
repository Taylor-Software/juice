import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/quick_ref.dart';
import 'package:juice_oracle/features/quick_ref_view.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUserCards extends UserRefCardsNotifier {
  _FakeUserCards(this._initial);
  final List<UserRefCard> _initial;
  @override
  Future<List<UserRefCard>> build() async => _initial;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, List<Override> overrides) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
          home: Scaffold(body: QuickRefView(useProvider: true))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders a user card + the Add button (no system card)',
      (tester) async {
    await pump(tester, [
      systemQuickRefProvider.overrideWithValue(null),
      userRefCardsProvider.overrideWith(() => _FakeUserCards([
            const UserRefCard(id: '1', title: 'House Rules', sections: [
              QuickRefSection('Crits', ['crits explode']),
            ]),
          ])),
    ]);
    expect(find.text('House Rules'), findsOneWidget);
    expect(find.text('Crits'), findsOneWidget);
    expect(find.byKey(const Key('quickref-add')), findsOneWidget);
    expect(find.byKey(const Key('quickref-edit-1')), findsOneWidget);
    expect(find.byKey(const Key('quickref-delete-1')), findsOneWidget);
  });

  testWidgets('empty state still shows the Add button', (tester) async {
    await pump(tester, [
      systemQuickRefProvider.overrideWithValue(null),
      userRefCardsProvider.overrideWith(() => _FakeUserCards(const [])),
    ]);
    expect(find.byKey(const Key('quickref-empty')), findsOneWidget);
    expect(find.byKey(const Key('quickref-add')), findsOneWidget);
  });
}
