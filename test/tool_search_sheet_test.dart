import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/shared/tool_search_sheet.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/tool_registry.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('search filters and tapping a tool navigates', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final tools = buildToolRegistry(family: const [], systems: kAllSystems);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => showToolSearchSheet(context, tools),
              child: const Text('open'),
            );
          }),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('tool-search')), 'verdant');
    await t.pumpAndSettle();
    await t.tap(find.text('Verdant Journey'));
    await t.pumpAndSettle();
    expect(c.read(shellRouteProvider).destination, Destination.maps);
    expect(c.read(shellRouteProvider).subtab, 'journey');
  });
}
