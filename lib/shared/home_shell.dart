import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/journal_export.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../features/journal_screen.dart';
import '../features/maps_tab.dart';
import '../features/oracles_tab.dart';
import '../features/party_tab.dart';
import '../features/tracking_tab.dart';
import '../state/interpreter.dart';
import '../state/providers.dart';
import 'destination.dart';
import 'help_nav.dart';
import 'shell_route.dart';
import 'tool_registry.dart';
import 'tool_search_sheet.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.oracle});
  final Oracle oracle;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  AppLifecycleListener? _lifecycle;
  final GlobalKey _bodyKey = GlobalKey();
  double _journalWidth = 400; // split-view journal panel width (draggable)

  @override
  void initState() {
    super.initState();
    // Mobile: free the native LLM session when backgrounded (the model file
    // stays on disk; next use reloads). Web stays warm — reload is ~40s and
    // browsers fire hide on every tab switch.
    if (!kIsWeb) {
      _lifecycle = AppLifecycleListener(
        onPause: () => ref.read(interpreterServiceProvider).dispose(),
      );
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.tune),
                        tooltip: 'Edit systems',
                        onPressed: () => _editSystems(dialogContext, s),
                      ),
                      if (sessions.sessions.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(dialogContext, s),
                        ),
                    ],
                  ),
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
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Export campaign'),
                onTap: () => _exportCampaign(dialogContext),
              ),
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Export as Lonelog (.md)'),
                onTap: () => _exportLonelog(dialogContext),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Import campaign'),
                onTap: () => _importCampaign(dialogContext),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Import Lonelog (.md)'),
                onTap: () => _importLonelog(dialogContext),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createSession(BuildContext dialogContext) async {
    final result = await showDialog<
        ({String name, Set<String> systems, String genre, String tone})>(
      context: dialogContext,
      builder: (context) => const NewCampaignDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(result.name.trim(),
        systems: result.systems, genre: result.genre, tone: result.tone);
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
  }

  Future<void> _editSystems(
      BuildContext dialogContext, SessionMeta meta) async {
    final picked = await showDialog<Set<String>>(
      context: dialogContext,
      builder: (context) => _EditSystemsDialog(initial: meta.enabledSystems),
    );
    if (picked == null) return;
    await ref.read(sessionsProvider.notifier).editSystems(meta.id, picked);
  }

  Future<void> _exportCampaign(BuildContext dialogContext) async {
    final content = await ref.read(sessionsProvider.notifier).exportActive();
    final name =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.name ?? 'campaign';
    final fileName = '${slugify(name)}.juice.json';
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Export campaign',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _exportLonelog(BuildContext dialogContext) async {
    final content =
        await ref.read(sessionsProvider.notifier).exportActiveAsLonelog();
    final name =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.name ?? 'campaign';
    final fileName = '${slugify(name)}.lonelog.md';
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Export as Lonelog',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['md'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _importCampaign(BuildContext dialogContext) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import campaign',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      return;
    }
    final bytes = (result == null || result.files.isEmpty)
        ? null
        : result.files.first.bytes;
    if (bytes == null) return; // user cancelled
    try {
      await ref
          .read(sessionsProvider.notifier)
          .importCampaign(utf8.decode(bytes));
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on FormatException catch (e) {
      if (!mounted) return;
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        Navigator.of(dialogContext).pop();
      }
    }
  }

  Future<void> _importLonelog(BuildContext dialogContext) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import Lonelog',
        type: FileType.custom,
        allowedExtensions: ['md'],
        withData: true,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      return;
    }
    final bytes = (result == null || result.files.isEmpty)
        ? null
        : result.files.first.bytes;
    if (bytes == null) return; // user cancelled
    try {
      await ref
          .read(sessionsProvider.notifier)
          .importLonelog(utf8.decode(bytes));
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on FormatException catch (e) {
      if (!mounted) return;
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        Navigator.of(dialogContext).pop();
      }
    }
  }

  Future<void> _confirmDelete(
      BuildContext dialogContext, SessionMeta session) async {
    final ok = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text('Delete "${session.name}"?'),
        content: const Text(
            'Its journal, threads, characters, and crawl state are removed permanently.'),
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

  List<Destination> _visibleDestinations(
          Set<String> systems, List<String> family) =>
      [
        Destination.journal,
        Destination.maps,
        if (systems.contains('party')) Destination.party,
        Destination.tracking,
        Destination.oracles,
      ];

  Widget _root(Destination d, Set<String> systems, List<String> family) {
    switch (d) {
      case Destination.journal:
        return const JournalScreen();
      case Destination.maps:
        return MapsTab(oracle: widget.oracle, systems: systems);
      case Destination.party:
        return const PartyTab();
      case Destination.tracking:
        return const TrackingTab();
      case Destination.oracles:
        return OraclesTab(
            oracle: widget.oracle, family: family, systems: systems);
    }
  }

  Widget _shellBody(
      BuildContext context, List<String> family, Set<String> systems) {
    final route = ref.watch(shellRouteProvider);
    final split = ref.watch(splitViewProvider).valueOrNull ?? false;
    final destinations = _visibleDestinations(systems, family);
    final index = destinations
        .indexOf(route.destination)
        .clamp(0, destinations.length - 1);
    final body = IndexedStack(
      key: _bodyKey,
      index: index,
      children: [for (final d in destinations) _root(d, systems, family)],
    );
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 840;
      final canSplit = c.maxWidth >= 1000;
      if (split && canSplit) {
        final leftDest = [
          for (final d in destinations)
            if (d != Destination.journal) d
        ];
        final leftIndex =
            leftDest.indexOf(route.destination).clamp(0, leftDest.length - 1);
        final maxJournal = c.maxWidth * 0.6;
        final journalW = _journalWidth.clamp(320.0, maxJournal);
        return Row(children: [
          NavigationRail(
            selectedIndex: leftIndex,
            onDestinationSelected: (i) =>
                ref.read(shellRouteProvider.notifier).goTo(leftDest[i]),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in leftDest)
                NavigationRailDestination(
                  icon: Icon(destinationMeta[d]!.icon),
                  label: Text(destinationMeta[d]!.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Row(children: [
              Expanded(
                child: IndexedStack(
                  index: leftIndex,
                  children: [
                    for (final d in leftDest) _root(d, systems, family)
                  ],
                ),
              ),
              _DragHandle(
                onDelta: (dx) => setState(() => _journalWidth =
                    (_journalWidth - dx).clamp(320.0, maxJournal)),
              ),
              SizedBox(
                key: const Key('split-journal'),
                width: journalW,
                child: const JournalScreen(),
              ),
            ]),
          ),
        ]);
      }
      if (wide) {
        return Row(children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) =>
                ref.read(shellRouteProvider.notifier).goTo(destinations[i]),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(destinationMeta[d]!.icon),
                  label: Text(destinationMeta[d]!.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]);
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) =>
              ref.read(shellRouteProvider.notifier).goTo(destinations[i]),
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(destinationMeta[d]!.icon),
                label: destinationMeta[d]!.label,
              ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final split = ref.watch(splitViewProvider).valueOrNull ?? false;
    final wideEnough = MediaQuery.sizeOf(context).width >= 1000;
    final sessionName =
        ref.watch(sessionsProvider).valueOrNull?.activeMeta.name;
    final rulesets =
        ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
    final systems =
        ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
            kAllSystems;
    final family = !systems.contains('ironsworn')
        ? const <String>[]
        : [
            if (rulesets.contains('classic')) 'classic',
            if (rulesets.contains('delve')) 'delve',
            if (rulesets.contains('starforged')) 'starforged',
            if (rulesets.contains('sundered_isles')) 'sundered_isles',
          ];
    return Scaffold(
      appBar: AppBar(
        title: sessionName == null
            ? const Text('Juice Oracle')
            : Column(
                children: [
                  const Text('Juice Oracle'),
                  Text(sessionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search tools',
            onPressed: () => showToolSearchSheet(
                context, buildToolRegistry(family: family, systems: systems),
                oracle: widget.oracle),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () => openHelp(context, ref),
          ),
          if (systems.contains('ironsworn'))
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Rulesets',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Consumer(builder: (context, ref, _) {
                  const rulesetNames = {
                    'classic': 'Ironsworn',
                    'delve': 'Ironsworn: Delve',
                    'starforged': 'Ironsworn: Starforged',
                    'sundered_isles': 'Starforged: Sundered Isles',
                  };
                  final enabled = ref.watch(rulesetsProvider).valueOrNull ??
                      const <String>{};
                  return SimpleDialog(
                    title: const Text('Rulesets'),
                    children: [
                      for (final id in const [
                        'classic',
                        'delve',
                        'starforged',
                        'sundered_isles'
                      ])
                        SwitchListTile(
                          title: Text(rulesetNames[id]!),
                          subtitle: id == 'classic'
                              ? const Text('Rules © Shawn Tomkin, CC-BY 4.0')
                              : null,
                          value: enabled.contains(id),
                          onChanged: (on) async {
                            final otherFamily =
                                (id == 'classic' || id == 'delve')
                                    ? const {'starforged', 'sundered_isles'}
                                    : const {'classic', 'delve'};
                            if (on && enabled.any(otherFamily.contains)) {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Switch family?'),
                                  content: const Text(
                                      'Ironsworn and Starforged are separate games — enabling this turns the other family off.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('Cancel')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: const Text('Switch')),
                                  ],
                                ),
                              );
                              if (ok != true) return;
                            }
                            await ref
                                .read(rulesetsProvider.notifier)
                                .setRuleset(id, on);
                          },
                        ),
                    ],
                  );
                }),
              ),
            ),
          if (wideEnough)
            IconButton(
              key: const Key('split-toggle'),
              icon: Icon(
                  split ? Icons.view_sidebar : Icons.view_sidebar_outlined),
              tooltip: split ? 'Single pane' : 'Split with journal',
              onPressed: () => ref.read(splitViewProvider.notifier).toggle(),
            ),
          IconButton(
            icon: const Icon(Icons.folder_copy_outlined),
            tooltip: 'Campaigns',
            onPressed: () => _showSessions(context),
          ),
        ],
      ),
      body: SafeArea(child: _shellBody(context, family, systems)),
    );
  }
}

/// A thin, draggable vertical divider for resizing the split-view journal.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onDelta});
  final void Function(double dx) onDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        child: const SizedBox(
          width: 8,
          child: Center(child: VerticalDivider(width: 1)),
        ),
      ),
    );
  }
}

/// Dialog for creating a new campaign: name field + five system checkboxes.
/// Returns `({String name, Set<String> systems})?`; null on cancel.
/// One-line description of what each system adds, shown as the checkbox
/// subtitle in the New-campaign and Edit-systems dialogs.
const kSystemBlurbs = <String, String>{
  'juice': 'Core yes/no oracle, base maps, and most generators.',
  'mythic': 'Mythic GME oracle (Fate Chart + meaning tables).',
  'ironsworn': 'Ironsworn / Starforged Moves (also pick a ruleset).',
  'party': 'Solo-party tools, plus the Party tab.',
  'verdant': 'Book-based Journey map: terrain, points of interest, travel.',
  'lonelog': 'Lonelog notation: Resources + Battle trackers, .md export.',
  'hexcrawl': 'Generic map generator: regions, dungeons, sites — any game.',
};

class NewCampaignDialog extends StatefulWidget {
  const NewCampaignDialog({super.key});

  @override
  State<NewCampaignDialog> createState() => _NewCampaignDialogState();
}

class _NewCampaignDialogState extends State<NewCampaignDialog> {
  final _controller = TextEditingController();
  final _genre = TextEditingController();
  final _tone = TextEditingController();
  bool _juice = true;
  bool _mythic = true;
  bool _ironsworn = true;
  bool _party = true;
  bool _verdant = true;
  bool _lonelog = false;
  bool _hexcrawl = false;

  @override
  void dispose() {
    _controller.dispose();
    _genre.dispose();
    _tone.dispose();
    super.dispose();
  }

  void _submit() {
    final picked = <String>{
      if (_juice) 'juice',
      if (_mythic) 'mythic',
      if (_ironsworn) 'ironsworn',
      if (_party) 'party',
      if (_verdant) 'verdant',
      if (_lonelog) 'lonelog',
      if (_hexcrawl) 'hexcrawl',
    };
    Navigator.of(context).pop((
      name: _controller.text,
      systems: picked,
      genre: _genre.text.trim(),
      tone: _tone.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New campaign'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('new-campaign-name'),
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => _submit(),
            ),
            TextField(
              key: const Key('new-campaign-genre'),
              controller: _genre,
              decoration: const InputDecoration(
                  labelText: 'Genre (optional)',
                  hintText: 'e.g. grimdark fantasy'),
            ),
            TextField(
              key: const Key('new-campaign-tone'),
              controller: _tone,
              decoration: const InputDecoration(
                  labelText: 'Tone (optional)',
                  hintText: 'e.g. tense and dangerous'),
            ),
            const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Default systems'))),
            CheckboxListTile(
              key: const Key('sys-juice'),
              title: const Text('Juice oracle'),
              subtitle: Text(kSystemBlurbs['juice']!),
              value: _juice,
              onChanged: (v) => setState(() => _juice = v ?? true),
            ),
            CheckboxListTile(
              key: const Key('sys-mythic'),
              title: const Text('Mythic GME'),
              subtitle: Text(kSystemBlurbs['mythic']!),
              value: _mythic,
              onChanged: (v) => setState(() => _mythic = v ?? true),
            ),
            CheckboxListTile(
              key: const Key('sys-ironsworn'),
              title: const Text('Ironsworn family'),
              subtitle: Text(kSystemBlurbs['ironsworn']!),
              value: _ironsworn,
              onChanged: (v) => setState(() => _ironsworn = v ?? true),
            ),
            CheckboxListTile(
              key: const Key('sys-party'),
              title: const Text('Party emulator'),
              subtitle: Text(kSystemBlurbs['party']!),
              value: _party,
              onChanged: (v) => setState(() => _party = v ?? true),
            ),
            CheckboxListTile(
              key: const Key('sys-verdant'),
              title: const Text('Verdant Hexcrawling'),
              subtitle: Text(kSystemBlurbs['verdant']!),
              value: _verdant,
              onChanged: (v) => setState(() => _verdant = v ?? true),
            ),
            const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: EdgeInsets.only(top: 12), child: Text('Add-ons'))),
            CheckboxListTile(
              key: const Key('sys-lonelog'),
              title: const Text('Lonelog journaling'),
              subtitle: Text(kSystemBlurbs['lonelog']!),
              value: _lonelog,
              onChanged: (v) => setState(() => _lonelog = v ?? false),
            ),
            CheckboxListTile(
              key: const Key('sys-hexcrawl'),
              title: const Text('Hexcrawl toolkit'),
              subtitle: Text(kSystemBlurbs['hexcrawl']!),
              value: _hexcrawl,
              onChanged: (v) => setState(() => _hexcrawl = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Dialog to toggle the optional systems of an existing campaign.
/// Returns the chosen set, or null on cancel.
class _EditSystemsDialog extends StatefulWidget {
  const _EditSystemsDialog({required this.initial});
  final Set<String> initial;

  @override
  State<_EditSystemsDialog> createState() => _EditSystemsDialogState();
}

class _EditSystemsDialogState extends State<_EditSystemsDialog> {
  late final Set<String> _picked = {...widget.initial};

  Widget _row(String id, String label) => CheckboxListTile(
        key: Key('edit-sys-$id'),
        title: Text(label),
        subtitle: Text(kSystemBlurbs[id]!),
        value: _picked.contains(id),
        onChanged: (v) => setState(() {
          if (v ?? false) {
            _picked.add(id);
          } else {
            _picked.remove(id);
          }
        }),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enabled systems'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('juice', 'Juice oracle'),
            _row('mythic', 'Mythic GME'),
            _row('ironsworn', 'Ironsworn family'),
            _row('party', 'Party emulator'),
            _row('verdant', 'Verdant Hexcrawling'),
            _row('lonelog', 'Lonelog journaling'),
            _row('hexcrawl', 'Hexcrawl toolkit'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_picked),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
