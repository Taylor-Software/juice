import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'destination.dart';
import 'shell_route.dart';

class SubtabDef {
  const SubtabDef(this.key, this.label);
  final String key;
  final String label;
}

/// A destination root: a [TabBar] over an [IndexedStack] body (never a
/// TabBarView — see the loose-constraint freeze rule). Honours
/// [shellRouteProvider] subtab requests aimed at [destination].
class SubtabHost extends ConsumerStatefulWidget {
  const SubtabHost({
    super.key,
    required this.destination,
    required this.tabs,
    required this.children,
    this.scrollable = false,
    this.initialTabIndex = 0,
  });

  final Destination destination;
  final List<SubtabDef> tabs;
  final List<Widget> children;
  final bool scrollable;
  final int initialTabIndex;

  @override
  ConsumerState<SubtabHost> createState() => _SubtabHostState();
}

class _SubtabHostState extends ConsumerState<SubtabHost>
    with TickerProviderStateMixin {
  int get _initialIndex {
    final len = widget.tabs.length;
    assert(len > 0, 'SubtabHost requires at least one tab');
    return len == 0 ? 0 : widget.initialTabIndex.clamp(0, len - 1);
  }

  late TabController _controller = TabController(
      length: widget.tabs.length, vsync: this, initialIndex: _initialIndex);

  @override
  void didUpdateWidget(SubtabHost old) {
    super.didUpdateWidget(old);
    if (old.tabs.length != widget.tabs.length) {
      _controller.dispose();
      _controller = TabController(
          length: widget.tabs.length, vsync: this, initialIndex: _initialIndex);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyRoute(ShellRoute route) {
    if (route.destination != widget.destination || route.subtab.isEmpty) return;
    final i = widget.tabs.indexWhere((t) => t.key == route.subtab);
    if (i >= 0 && i != _controller.index) _controller.index = i;
  }

  @override
  Widget build(BuildContext context) {
    // Apply a request that arrived while this host was offstage.
    _applyRoute(ref.read(shellRouteProvider));
    ref.listen(shellRouteProvider, (_, next) => _applyRoute(next));
    final theme = Theme.of(context);
    return Column(
      children: [
        Material(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _controller,
            isScrollable: widget.scrollable,
            tabs: [for (final t in widget.tabs) Tab(text: t.label)],
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => IndexedStack(
              index: _controller.index,
              children: widget.children,
            ),
          ),
        ),
      ],
    );
  }
}
