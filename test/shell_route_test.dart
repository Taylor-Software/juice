import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';

void main() {
  test('default route is journal', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(shellRouteProvider).destination, Destination.journal);
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

  test('openTool returns false when the target subtab is hidden for the mode',
      () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // emulator is party-only → hidden in gm mode.
    final handled = c
        .read(shellRouteProvider.notifier)
        .openTool('party-emulator', mode: CampaignMode.gm);
    expect(handled, isFalse);
    // Route must not have mis-landed.
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });

  test('openTool navigates when the target subtab is visible for the mode', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final handled = c
        .read(shellRouteProvider.notifier)
        .openTool('party-emulator', mode: CampaignMode.party);
    expect(handled, isTrue);
    expect(c.read(shellRouteProvider).destination, Destination.track);
    expect(c.read(shellRouteProvider).subtab, 'emulator');
  });

  test('openTool with no mode ignores gating (back-compat)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(
        c.read(shellRouteProvider.notifier).openTool('party-emulator'), isTrue);
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
}
