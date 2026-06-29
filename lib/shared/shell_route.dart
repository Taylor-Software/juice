import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/models.dart';
import 'destination.dart';

class ShellRoute {
  const ShellRoute(this.destination, this.subtab);
  final Destination destination;

  /// Requested subtab key (empty = the destination's first/default subtab).
  final String subtab;
}

class ShellRouteNotifier extends Notifier<ShellRoute> {
  @override
  ShellRoute build() => const ShellRoute(Destination.journal, '');

  void goTo(Destination destination, {String subtab = ''}) {
    state = ShellRoute(destination, subtab);
  }

  /// Lands on the mode's home verb (gm→Track, party→Sheet). Called when a
  /// campaign is entered (launcher Continue/New/switch/import, in-shell switch/
  /// New) so each campaign opens on the surface its mode is about. When
  /// [hasEncounter] is true (combatants in progress), lands on Track→Encounter
  /// regardless of mode so an in-progress fight isn't buried behind a tab.
  void landFor(CampaignMode mode, {bool hasEncounter = false}) {
    state = hasEncounter
        ? const ShellRoute(Destination.track, 'encounter')
        : ShellRoute(landingDestination(mode), '');
  }

  /// Navigates to the tool's home. Returns false (no-op) for ids with no tab
  /// home, so callers can fall back (e.g. dice sheet, snackbar).
  bool openTool(String id) {
    final loc = toolLocation[id];
    if (loc == null) return false;
    state = ShellRoute(loc.$1, loc.$2);
    return true;
  }
}

final shellRouteProvider =
    NotifierProvider<ShellRouteNotifier, ShellRoute>(ShellRouteNotifier.new);
