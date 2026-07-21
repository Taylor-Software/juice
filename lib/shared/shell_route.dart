import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'destination.dart';

class ShellRoute {
  const ShellRoute(this.destination, this.subtab);
  final Destination destination;

  /// Requested subtab key (empty = the destination's first/default subtab).
  final String subtab;
}

class ShellRouteNotifier extends Notifier<ShellRoute> {
  /// Bounded back-stack of routes visited via [goTo]/[openTool], newest last.
  final List<ShellRoute> _history = [];
  static const _maxHistory = 30;

  /// Whether [back] has somewhere to go.
  bool get canGoBack => _history.isNotEmpty;

  @override
  ShellRoute build() => const ShellRoute(Destination.journal, '');

  /// Pushes the current route onto the history (deduped on the immediate
  /// current), keeping the stack bounded.
  void _push() {
    final cur = state;
    if (_history.isNotEmpty) {
      final last = _history.last;
      if (last.destination == cur.destination && last.subtab == cur.subtab) {
        return;
      }
    }
    _history.add(cur);
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  void goTo(Destination destination, {String subtab = ''}) {
    if (destination == state.destination && subtab == state.subtab) return;
    _push();
    state = ShellRoute(destination, subtab);
  }

  /// Pops to the previous route. No-op when the history is empty.
  void back() {
    if (_history.isEmpty) return;
    state = _history.removeLast();
  }

  /// Lands on the Journal — the solo play loop's home. Called when a campaign
  /// is entered (launcher Continue/New/switch/import, in-shell switch/New).
  /// When [hasEncounter] is true (combatants in progress), lands on
  /// Track→Encounter instead so an in-progress fight isn't buried behind a tab.
  /// Clears the back-stack: entering a campaign is a fresh start.
  void land({bool hasEncounter = false}) {
    _history.clear();
    state = hasEncounter
        ? const ShellRoute(Destination.track, 'encounter')
        : const ShellRoute(Destination.journal, '');
  }

  /// Navigates to the tool's home. Returns false (no-op) for ids with no tab
  /// home, so callers can fall back (e.g. dice sheet, snackbar).
  bool openTool(String id) {
    final loc = toolLocation[id];
    if (loc == null) return false;
    if (loc.$1 == state.destination && loc.$2 == state.subtab) return true;
    _push();
    state = ShellRoute(loc.$1, loc.$2);
    return true;
  }
}

final shellRouteProvider =
    NotifierProvider<ShellRouteNotifier, ShellRoute>(ShellRouteNotifier.new);
