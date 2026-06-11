import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/oracle.dart';
import '../state/providers.dart';
import 'tool_registry.dart';

/// Shows [child] (the journal) full-screen with a tool panel layered over it.
///
/// The panel hosts a searchable launcher plus every tool opened so far; opened
/// tools stay mounted (keep-alive) so their state survives close/reopen and
/// switching between tools via the launcher.
class ToolHost extends ConsumerStatefulWidget {
  const ToolHost({
    super.key,
    required this.tools,
    this.oracle,
    required this.child,
  });

  final List<ToolDef> tools;
  final Oracle? oracle; // null only in tests whose builders ignore it
  final Widget child; // the journal

  /// Open the launcher from anywhere below a ToolHost (used by tests).
  static void openLauncher(BuildContext context) =>
      context.findAncestorStateOfType<ToolHostState>()!.openLauncher();

  @override
  ConsumerState<ToolHost> createState() => ToolHostState();
}

class ToolHostState extends ConsumerState<ToolHost> {
  /// Tools instantiated so far, in insertion order (stable: IndexedStack
  /// children must not reorder, or their State would be lost).
  final List<String> _instantiated = [];
  String? _activeId; // null = launcher view
  bool _open = false;
  String _query = '';
  final TextEditingController _search = TextEditingController();

  void openLauncher() {
    _search.clear();
    setState(() {
      _open = true;
      _activeId = null;
      _query = '';
    });
  }

  void openTool(String id) {
    if (!_instantiated.contains(id)) _instantiated.add(id);
    ref.read(toolMruProvider.notifier).record(id);
    setState(() {
      _open = true;
      _activeId = id;
    });
  }

  void close() => setState(() => _open = false);

  @override
  void didUpdateWidget(ToolHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.tools.map((t) => t.id).toSet();
    _instantiated.removeWhere((id) => !ids.contains(id));
    if (_activeId != null && !_instantiated.contains(_activeId)) {
      _activeId = null; // active tool was removed: fall back to launcher
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Offstage (not conditional removal) so tool state survives close.
        Offstage(
          offstage: !_open,
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            return Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: close,
                  child: const ColoredBox(color: Colors.black54),
                ),
                Align(
                  alignment:
                      wide ? Alignment.centerRight : Alignment.bottomCenter,
                  child: SizedBox(
                    width: wide ? 400 : constraints.maxWidth,
                    height: wide
                        ? constraints.maxHeight
                        : constraints.maxHeight * 0.85,
                    // Absorb taps on empty panel areas so they don't reach
                    // the scrim and close the panel.
                    child: GestureDetector(
                      onTap: () {},
                      behavior: HitTestBehavior.opaque,
                      child: Material(
                        elevation: 8,
                        color: Theme.of(context).colorScheme.surface,
                        clipBehavior: Clip.antiAlias,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight:
                              wide ? Radius.zero : const Radius.circular(16),
                        ),
                        child: _panel(context),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context) {
    final active = _activeId == null
        ? null
        : widget.tools.firstWhere((t) => t.id == _activeId);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              if (active != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'All tools',
                  onPressed: () => setState(() => _activeId = null),
                ),
              Expanded(
                child: Text(
                  active?.label ?? 'Tools',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('tool-close'),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: close,
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(offstage: _activeId != null, child: _launcher()),
              // Keep-alive: the tools stack stays in the tree whenever it has
              // children, even while the launcher view is showing.
              Offstage(
                offstage: _activeId == null,
                child: _instantiated.isEmpty
                    ? const SizedBox.shrink()
                    : IndexedStack(
                        index: _activeId == null
                            ? 0
                            : _instantiated.indexOf(_activeId!),
                        children: [
                          for (final id in _instantiated)
                            KeyedSubtree(
                              key: ValueKey(id),
                              child: widget.tools
                                  .firstWhere((t) => t.id == id)
                                  .builder(widget.oracle),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _launcher() {
    final q = _query.trim().toLowerCase();
    bool matches(ToolDef t) =>
        q.isEmpty ||
        t.label.toLowerCase().contains(q) ||
        t.group.toLowerCase().contains(q);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            key: const Key('tool-search'),
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search tools',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              // TODO: 'Recent' MRU row rendered in Task 4 (HomeShell wiring);
              // MRU is already recorded via toolMruProvider.
              for (final group in toolGroups)
                if (widget.tools
                    .any((t) => t.group == group && matches(t))) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      group,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  for (final tool in widget.tools
                      .where((t) => t.group == group && matches(t)))
                    ListTile(
                      leading: Icon(tool.icon),
                      title: Text(tool.label),
                      trailing: tool.badge == null
                          ? null
                          : Text(
                              tool.badge!,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline),
                            ),
                      onTap: () => openTool(tool.id),
                    ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
