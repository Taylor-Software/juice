import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/subtab_host.dart';

Widget _host() => const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SubtabHost(
            destination: Destination.track,
            tabs: [
              SubtabDef('a', 'Alpha'),
              SubtabDef('b', 'Beta'),
            ],
            children: [Text('PANE A'), Text('PANE B')],
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders first subtab by default', (t) async {
    await t.pumpWidget(_host());
    expect(find.text('PANE A'), findsOneWidget);
  });

  testWidgets('switching tab shows the other pane (IndexedStack keep-alive)',
      (t) async {
    await t.pumpWidget(_host());
    await t.tap(find.text('Beta'));
    await t.pumpAndSettle();
    expect(find.text('PANE B'), findsOneWidget);
  });

  testWidgets('a shellRoute request selects the matching subtab', (t) async {
    late WidgetRef capturedRef;
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            capturedRef = ref;
            return const SubtabHost(
              destination: Destination.track,
              tabs: [SubtabDef('a', 'Alpha'), SubtabDef('b', 'Beta')],
              children: [Text('PANE A'), Text('PANE B')],
            );
          }),
        ),
      ),
    ));
    capturedRef
        .read(shellRouteProvider.notifier)
        .goTo(Destination.track, subtab: 'b');
    await t.pumpAndSettle();
    expect(find.text('PANE B'), findsOneWidget);
  });

  testWidgets('opens on initialTabIndex', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: SubtabHost(
          destination: Destination.track,
          initialTabIndex: 1,
          tabs: [SubtabDef('a', 'A'), SubtabDef('b', 'B')],
          children: [Text('PANE-A'), Text('PANE-B')],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
  });
}
