import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../features/fate_screen.dart';
import '../features/generators_screen.dart';
import '../features/tables_screen.dart';
import '../features/tracker_screen.dart';
import '../state/providers.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.oracle});
  final Oracle oracle;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  Future<void> _showSessions(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final sessions = ref.watch(sessionsProvider).valueOrNull;
          if (sessions == null) {
            return const Dialog(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return SimpleDialog(
            title: const Text('Campaigns'),
            children: [
              for (final s in sessions.sessions)
                ListTile(
                  leading: Icon(s.id == sessions.active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  title: Text(s.name),
                  trailing: sessions.sessions.length > 1
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(dialogContext, s),
                        )
                      : null,
                  onTap: () {
                    ref.read(sessionsProvider.notifier).switchTo(s.id);
                    Navigator.of(dialogContext).pop();
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New campaign'),
                onTap: () => _createSession(dialogContext),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createSession(BuildContext dialogContext) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('New campaign'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(name.trim());
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
  }

  Future<void> _confirmDelete(
      BuildContext dialogContext, SessionMeta session) async {
    final ok = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text('Delete "${session.name}"?'),
        content: const Text(
            'Its threads, characters, log, and crawl state are removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(sessionsProvider.notifier).remove(session.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionName =
        ref.watch(sessionsProvider).valueOrNull?.activeMeta.name;
    final pages = [
      FateScreen(oracle: widget.oracle),
      GeneratorsScreen(oracle: widget.oracle),
      TablesScreen(oracle: widget.oracle),
      const TrackerScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: sessionName == null
            ? const Text('Juice Oracle')
            : Column(
                children: [
                  const Text('Juice Oracle'),
                  Text(sessionName,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_copy_outlined),
            tooltip: 'Campaigns',
            onPressed: () => _showSessions(context),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.help_outline), label: 'Fate'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined), label: 'Generators'),
          NavigationDestination(
              icon: Icon(Icons.grid_view_outlined), label: 'Tables'),
          NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined), label: 'Tracker'),
        ],
      ),
    );
  }
}
