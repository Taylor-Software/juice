import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';

void main() {
  test('default route is journal', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });

  test('land lands on the Journal', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(shellRouteProvider.notifier).goTo(Destination.map);
    c.read(shellRouteProvider.notifier).land();
    expect(c.read(shellRouteProvider).destination, Destination.journal);
    expect(c.read(shellRouteProvider).subtab, '');
  });

  test('land with an in-progress encounter lands on Track→Encounter', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(shellRouteProvider.notifier).land(hasEncounter: true);
    expect(c.read(shellRouteProvider).destination, Destination.track);
    expect(c.read(shellRouteProvider).subtab, 'encounter');
  });

  test('openTool resolves a mapped id to destination + subtab', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final handled = c.read(shellRouteProvider.notifier).openTool('verdant');
    expect(handled, isTrue);
    expect(c.read(shellRouteProvider).destination, Destination.map);
    expect(c.read(shellRouteProvider).subtab, 'journey');
  });

  test('openTool returns false for an unmapped id', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(shellRouteProvider.notifier).openTool('dice'), isFalse);
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });

  test('openTool navigates to party-emulator regardless of mode', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final handled =
        c.read(shellRouteProvider.notifier).openTool('party-emulator');
    expect(handled, isTrue);
    expect(c.read(shellRouteProvider).destination, Destination.track);
    expect(c.read(shellRouteProvider).subtab, 'emulator');
  });

  test('goTo sets destination and subtab', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(shellRouteProvider.notifier)
        .goTo(Destination.track, subtab: 'rumors');
    expect(c.read(shellRouteProvider).destination, Destination.track);
    expect(c.read(shellRouteProvider).subtab, 'rumors');
  });

  group('back-stack', () {
    test('back returns to the previous route', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(shellRouteProvider.notifier);
      expect(n.canGoBack, isFalse);
      n.goTo(Destination.map);
      n.goTo(Destination.track, subtab: 'rumors');
      expect(n.canGoBack, isTrue);
      n.back();
      expect(c.read(shellRouteProvider).destination, Destination.map);
      n.back();
      expect(c.read(shellRouteProvider).destination, Destination.journal);
      expect(n.canGoBack, isFalse);
      n.back(); // no-op at the bottom
      expect(c.read(shellRouteProvider).destination, Destination.journal);
    });

    test('goTo to the same route does not grow history', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(shellRouteProvider.notifier);
      n.goTo(Destination.map);
      n.goTo(Destination.map);
      expect(n.canGoBack, isTrue);
      n.back();
      expect(c.read(shellRouteProvider).destination, Destination.journal);
      expect(n.canGoBack, isFalse);
    });

    test('land clears the back-stack', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(shellRouteProvider.notifier);
      n.goTo(Destination.map);
      n.goTo(Destination.track);
      n.land();
      expect(n.canGoBack, isFalse);
      expect(c.read(shellRouteProvider).destination, Destination.journal);
    });

    test('openTool pushes history so back returns', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(shellRouteProvider.notifier);
      n.goTo(Destination.journal); // no-op (already there), no push
      n.openTool('verdant'); // -> map/journey, pushes journal
      expect(n.canGoBack, isTrue);
      n.back();
      expect(c.read(shellRouteProvider).destination, Destination.journal);
    });
  });
}
