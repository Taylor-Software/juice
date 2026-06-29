import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/funnel.dart';
import '../engine/journal_export.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../features/campaign_search_sheet.dart';
import '../features/enter_campaign.dart';
import '../features/journal_screen.dart';
import '../features/maps_tab.dart';
import '../features/settings_sheet.dart';
import '../features/oracles_tab.dart';
import '../features/sheet_tab.dart';
import '../features/run_screen.dart';
import '../features/tracking_tab.dart';
import '../state/blob_store.dart';
import '../state/interpreter.dart';
import '../state/providers.dart';
import 'campaign_preview_pane.dart';
import 'design_tokens.dart';
import 'destination.dart';
import 'help_nav.dart';
import 'play_context_hud.dart';
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
    // Captured so the resume hop below can push over the shell after the
    // dialog (and its Consumer context) is gone.
    final shellContext = context;
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
                  leading: CampaignIdentityLeading(
                    meta: s,
                    active: s.id == sessions.active,
                  ),
                  title: Text(s.name),
                  subtitle: Text(
                    campaignSubtitle(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
                  onTap: () async {
                    await ref.read(sessionsProvider.notifier).switchTo(s.id);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    // Show the Session Resume ritual when the switched-to
                    // campaign has prior state, else land directly.
                    if (shellContext.mounted) {
                      await enterCampaign(shellContext, ref, s.mode);
                    }
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
              if (ref.read(blobStoreAvailableProvider))
                ListTile(
                  key: const Key('gc-blobs'),
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Clean up unused images'),
                  onTap: () => _gcBlobs(dialogContext),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _gcBlobs(BuildContext dialogContext) async {
    final ok = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Clean up unused images?'),
        content: const Text(
            'Deletes imported images and PDFs no campaign references. '
            'This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clean up')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await ref.read(sessionsProvider.notifier).gcBlobs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == 0
          ? 'No unused images to remove.'
          : 'Removed $n unused file${n == 1 ? '' : 's'}.'),
    ));
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
  }

  Future<void> _createSession(BuildContext dialogContext) async {
    final result = await showDialog<NewCampaignResult>(
      context: dialogContext,
      builder: (context) => const NewCampaignDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(result.name.trim(),
        systems: result.systems,
        mode: result.mode,
        genre: result.genre,
        tone: result.tone);
    ref.read(shellRouteProvider.notifier).landFor(result.mode);
    if (result.start == 'funnel') {
      await ref
          .read(charactersProvider.notifier)
          .addFunnel(result.seedSystem);
      ref.read(shellRouteProvider.notifier).goTo(Destination.sheet);
    }
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
    final file = await ref.read(sessionsProvider.notifier).exportActiveFile();
    final name =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.name ?? 'campaign';
    final fileName = '${slugify(name)}.juice.${file.ext}';
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Export campaign',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [file.ext],
        bytes: Uint8List.fromList(file.bytes),
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
        allowedExtensions: ['json', 'zip'],
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
      await ref.read(sessionsProvider.notifier).importCampaignData(bytes);
      // Land on the imported campaign's restored mode (or its encounter, if any).
      final enc = await ref.read(encounterProvider.future);
      ref.read(shellRouteProvider.notifier).landFor(
          ref.read(sessionsProvider).valueOrNull?.activeMeta.mode ??
              CampaignMode.party,
          hasEncounter: enc.combatants.isNotEmpty);
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
      // Imported campaigns are always party (files carry no mode).
      ref.read(shellRouteProvider.notifier).landFor(CampaignMode.party);
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

  List<Destination> _visibleDestinations() => const [
        Destination.journal,
        Destination.sheet,
        Destination.ask,
        Destination.map,
        Destination.track,
        Destination.run,
      ];

  Widget _root(Destination d, Set<String> systems, List<String> family) {
    switch (d) {
      case Destination.journal:
        return const JournalScreen();
      case Destination.sheet:
        return SheetTab(family: family);
      case Destination.ask:
        return OraclesTab(oracle: widget.oracle, systems: systems);
      case Destination.map:
        return MapsTab(oracle: widget.oracle, systems: systems);
      case Destination.track:
        return TrackingTab(systems: systems);
      case Destination.run:
        return const RunScreen();
    }
  }

  Widget _shellBody(
      BuildContext context, List<String> family, Set<String> systems) {
    final route = ref.watch(shellRouteProvider);
    final split = ref.watch(splitViewProvider).valueOrNull ?? false;
    final destinations = _visibleDestinations();
    final index = destinations
        .indexOf(route.destination)
        .clamp(0, destinations.length - 1);
    final body = IndexedStack(
      key: _bodyKey,
      index: index,
      children: [for (final d in destinations) _root(d, systems, family)],
    );
    // Show a dot badge on Track + Run when there are active (non-defeated)
    // combatants — a persistent signal that an encounter is in progress.
    final enc = ref.watch(encounterProvider).valueOrNull;
    final hasEnc = enc != null && enc.combatants.any((c) => !c.defeated);
    Widget navIcon(Destination d) {
      final icon = Icon(destinationMeta[d]!.icon);
      if (!hasEnc) return icon;
      if (d == Destination.track || d == Destination.run) {
        return Badge(child: icon);
      }
      return icon;
    }

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
                  icon: navIcon(d),
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
                  icon: navIcon(d),
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
                icon: navIcon(d),
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
    final mode = ref.watch(modeProvider);
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
            ? const Text("Solo Adventurer's Journal")
            : Column(
                children: [
                  const Text("Solo Adventurer's Journal"),
                  Text(sessionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
        actions: [
          IconButton(
            key: const Key('shell-search-campaign'),
            icon: const Icon(Icons.manage_search),
            tooltip: 'Search campaign',
            onPressed: () => showCampaignSearchSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Find tools & rolls',
            onPressed: () => showToolSearchSheet(context,
                buildToolRegistry(family: family, systems: systems),
                oracle: widget.oracle),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () => openHelp(context, ref),
          ),
          IconButton(
            key: const Key('shell-settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => showSettingsSheet(context),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SegmentedButton<CampaignMode>(
              key: const Key('mode-toggle'),
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelMedium),
              ),
              segments: const [
                ButtonSegment(
                  value: CampaignMode.party,
                  icon: Icon(Icons.groups_outlined, size: 18),
                  label: Text('Party'),
                ),
                ButtonSegment(
                  value: CampaignMode.gm,
                  icon: Icon(Icons.castle_outlined, size: 18),
                  label: Text('GM'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selected) {
                final sessions = ref.read(sessionsProvider).valueOrNull;
                if (sessions == null) return;
                final next = selected.first;
                if (next == mode) return;
                ref
                    .read(sessionsProvider.notifier)
                    .setMode(sessions.active, next);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_copy_outlined),
            tooltip: 'Campaigns',
            onPressed: () => _showSessions(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const CampaignHeader(),
            Expanded(child: _shellBody(context, family, systems)),
          ],
        ),
      ),
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
  'dnd': 'D&D 5e character sheet: ability scores, saves, skills, HP.',
  'shadowdark': 'Shadowdark character sheet: stats, HP, AC, gear, luck.',
  'nimble': 'Nimble character sheet: stats, wounds, AC, slots, gear.',
  'draw-steel':
      'Draw Steel hero sheet: characteristics, stamina, heroic resource, power rolls. '
          'Independent product; not affiliated with MCDM Productions, LLC.',
  'argosa':
      'Tales of Argosa: roll d20 under stat (under half = Great Success), Luck degrades each adventure. '
          'Based on Tales of Argosa by Pickpocket Press (S J Grodzicki), CC BY-SA 4.0.',
  'cairn':
      'Cairn: d20-under saves, HP as hit protection (avoidance), armor reduces damage, Deprived condition. '
          'Based on Cairn by Yochai Gal, CC BY-SA 4.0.',
  'knave':
      'Knave 2e: d20 + score >= 11 saves, wounds fill inventory slots, 10 + CON slot budget. No classes. '
          'Based on Knave 2e by Ben Milton (Questing Beast), CC BY 4.0.',
  'ose': 'OSE/B/X: classic fantasy with 7 classes, 5 saving throws, descending AC, THAC0. '
      'Compatible with Old-School Essentials by Gavin Norman (Necrotic Gnome). Not affiliated with Necrotic Gnome.',
  'kal-arath': 'Kal-Arath: sword & sorcery OSR. 2d6 + stat >= 8; five stats, '
      'demonic pacts, Fate Points. Facts-only mechanics.',
  'dcc':
      'Dungeon Crawl Classics: 0-level funnel, dice chain, mighty deeds, '
          'spellburn, disapproval. Facts-only mechanics. '
          'Not affiliated with Goodman Games.',
  'cards': 'Card oracles: draw from a 52-card deck or a 78-card tarot.',
  'custom':
      'Custom / Homebrew sheet: build your own from configurable blocks — '
          'stats, HP, rolls, luck, timers, conditions. Facts-only; you author all content.',
  'funnel':
      '0-Level Funnel: run a pack of doomed peasants, then graduate '
          'survivors into full characters of any enabled system.',
};

/// Resolves a [SessionMeta.identityIcon] key (see identityIconKeyFor) to an
/// IconData. Keys mirror the per-ruleset preset icons; unknown → a default.
const kIdentityIcons = <String, IconData>{
  'bolt': Icons.bolt,
  'castle': Icons.castle,
  'dark_mode': Icons.dark_mode,
  'flash_on': Icons.flash_on,
  'shield': Icons.shield,
  'fort': Icons.fort,
  'terrain': Icons.terrain,
  'content_cut': Icons.content_cut,
  'auto_stories': Icons.auto_stories,
  'whatshot': Icons.whatshot,
  'casino': Icons.casino,
  'book': Icons.book,
};

/// The icon for a campaign's identity key, with a stable fallback.
IconData identityIconData(String? key) =>
    kIdentityIcons[key] ?? Icons.auto_stories;

/// Short display names for use in the Custom grouped picker chips.
const kSystemShortName = <String, String>{
  'ironsworn': 'Ironsworn',
  'dnd': 'D&D 5e',
  'shadowdark': 'Shadowdark',
  'nimble': 'Nimble',
  'draw-steel': 'Draw Steel',
  'argosa': 'Argosa',
  'cairn': 'Cairn',
  'knave': 'Knave 2e',
  'ose': 'OSE/B/X',
  'kal-arath': 'Kal-Arath',
  'dcc': 'DCC',
  'funnel': '0-Level Funnel',
  'juice': 'Juice',
  'mythic': 'Mythic',
  'cards': 'Cards',
  'verdant': 'Verdant',
  'hexcrawl': 'Hexcrawl',
  'party': 'Party',
  'lonelog': 'Lonelog',
  'custom': 'Custom',
};

/// Result of the campaign-creation wizard. Defined once so every `showDialog`
/// call site (home-shell + launcher) and `_submit` share the exact record shape
/// — a drifting field here is a runtime TypeError on pop, not a compile error.
typedef NewCampaignResult = ({
  String name,
  Set<String> systems,
  CampaignMode mode,
  String genre,
  String tone,
  String start,
  String seedSystem,
});

class NewCampaignDialog extends StatefulWidget {
  const NewCampaignDialog({super.key});

  @override
  State<NewCampaignDialog> createState() => _NewCampaignDialogState();
}

class _NewCampaignDialogState extends State<NewCampaignDialog> {
  final _nameCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();
  final _toneCtrl = TextEditingController();

  // Wizard state
  int _step = 0;

  // Step 0
  // null = no stance chosen yet; default to solo-member on first build
  String? _stance = 'new-stance-solo-member'; // key of selected stance card
  CampaignMode _mode = CampaignMode.party;

  // Step 1 (system + tools)
  String? _ruleset; // single-select ruleset id, or null for None
  final Set<String> _addons = {'juice', 'party'}; // non-ruleset selections

  // Step 2 (start)
  String _start = 'roster'; // 'roster' | 'funnel'

  @override
  void dispose() {
    _nameCtrl.dispose();
    _genreCtrl.dispose();
    _toneCtrl.dispose();
    super.dispose();
  }

  Set<String> get _systems => {
        if (_ruleset != null) _ruleset!,
        ..._addons,
      };

  // Whether a funnel is available for the chosen ruleset
  bool get _funnelAvailable =>
      _ruleset != null && funnelProfileFor(_ruleset!) != null;

  // The seed system to pass to addFunnel (ruleset if funnel-capable, else dcc)
  String get _seedSystem =>
      (_ruleset != null && funnelProfileFor(_ruleset!) != null)
          ? _ruleset!
          : 'dcc';

  bool get _nextEnabled {
    if (_step == 0) return _stance != null;
    return true; // step 1 is always satisfiable
  }

  void _selectStance(String key, CampaignMode mode) {
    setState(() {
      _stance = key;
      _mode = mode;
    });
  }

  void _submit() {
    final systemsForSubmit = {
      ..._systems,
      if (_start == 'funnel') 'funnel',
    };
    Navigator.of(context).pop((
      name: _nameCtrl.text,
      systems: systemsForSubmit,
      mode: _mode,
      genre: _genreCtrl.text.trim(),
      tone: _toneCtrl.text.trim(),
      start: _start,
      seedSystem: _seedSystem,
    ));
  }

  void _goNext() {
    if (_step < 2) {
      setState(() {
        // If moving from step 1 to step 2 and funnel is no longer available,
        // reset the start choice back to roster.
        if (_step == 1 && !_funnelAvailable) _start = 'roster';
        _step++;
      });
    }
  }

  void _goBack() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New campaign'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step indicator: 3 dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _StepDot(active: i == _step),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: _buildStepContent(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_step > 0)
          TextButton(
            key: const Key('wizard-back'),
            onPressed: _goBack,
            child: const Text('Back'),
          ),
        if (_step < 2)
          FilledButton(
            key: const Key('wizard-next'),
            onPressed: _nextEnabled ? _goNext : null,
            child: const Text('Next'),
          )
        else
          FilledButton(
            key: const Key('wizard-create'),
            onPressed: _nameCtrl.text.trim().isNotEmpty ? _submit : null,
            child: const Text('Create'),
          ),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('new-campaign-name'),
          controller: _nameCtrl,
          autofocus: false,
          decoration: const InputDecoration(labelText: 'Campaign name'),
          onChanged: (_) => setState(() {}), // refresh Create button state
        ),
        const SizedBox(height: 16),
        const Text('Who are you at the table?',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _StanceCard(
          key: const Key('new-stance-gm'),
          title: 'GM, live table',
          subtitle: 'Running a game for others',
          icon: Icons.table_bar,
          selected: _stance == 'new-stance-gm',
          onTap: () => _selectStance('new-stance-gm', CampaignMode.gm),
        ),
        const SizedBox(height: 6),
        _StanceCard(
          key: const Key('new-stance-solo-gm'),
          title: 'Solo, as GM',
          subtitle: 'You run the world and play characters',
          icon: Icons.psychology,
          selected: _stance == 'new-stance-solo-gm',
          onTap: () => _selectStance('new-stance-solo-gm', CampaignMode.party),
        ),
        const SizedBox(height: 6),
        _StanceCard(
          key: const Key('new-stance-solo-member'),
          title: 'Solo, as a member',
          subtitle: 'You play a character in the story',
          icon: Icons.person,
          selected: _stance == 'new-stance-solo-member',
          onTap: () =>
              _selectStance('new-stance-solo-member', CampaignMode.party),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    final rulesetIds = kSystemCategory.entries
        .where((e) => e.value == SystemCategory.ruleset)
        .map((e) => e.key)
        .toList();
    // 'funnel' excluded: step 2 (start choice) manages it. Toggling it here
    // and picking roster would silently enable the funnel verb with no character.
    final addonIds = kSystemCategory.entries
        .where(
            (e) => e.value != SystemCategory.ruleset && e.key != 'funnel')
        .map((e) => e.key)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Ruleset (pick one)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(
            key: const Key('ruleset-none'),
            label: const Text('None'),
            selected: _ruleset == null,
            onSelected: (_) => setState(() => _ruleset = null),
          ),
          for (final id in rulesetIds)
            ChoiceChip(
              key: Key('ruleset-$id'),
              label: Text(kSystemShortName[id] ?? id),
              selected: _ruleset == id,
              onSelected: (_) => setState(() => _ruleset = id),
            ),
        ]),
        const SizedBox(height: 12),
        for (final cat in const [
          SystemCategory.oracle,
          SystemCategory.exploration,
          SystemCategory.tools,
        ]) ...[
          Text(_categoryLabel(cat),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final id in addonIds.where((i) => kSystemCategory[i] == cat))
              FilterChip(
                key: Key('cat-$id'),
                label: Text(kSystemShortName[id] ?? id),
                selected: _addons.contains(id),
                onSelected: (v) => setState(() {
                  if (v) {
                    _addons.add(id);
                  } else {
                    _addons.remove(id);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 10),
        ],
        const Divider(),
        CampaignPreviewPane(systems: _systems),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('new-campaign-genre'),
          controller: _genreCtrl,
          decoration: const InputDecoration(
            labelText: 'Genre (optional)',
            hintText: 'e.g. grimdark fantasy',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('new-campaign-tone'),
          controller: _toneCtrl,
          decoration: const InputDecoration(
            labelText: 'Tone (optional)',
            hintText: 'e.g. tense and dangerous',
          ),
        ),
        const SizedBox(height: 16),
        const Text('How do you start characters?',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _StartCard(
          key: const Key('new-start-roster'),
          title: 'Start with a roster',
          subtitle: 'Add characters after campaign creation',
          icon: Icons.group,
          selected: _start == 'roster',
          onTap: () => setState(() => _start = 'roster'),
        ),
        if (_funnelAvailable) ...[
          const SizedBox(height: 6),
          _StartCard(
            key: const Key('new-start-funnel'),
            title: '0-level funnel',
            subtitle: 'Start with a group of peasants',
            icon: Icons.filter_list,
            selected: _start == 'funnel',
            onTap: () => setState(() => _start = 'funnel'),
          ),
        ],
      ],
    );
  }

  String _categoryLabel(SystemCategory c) {
    switch (c) {
      case SystemCategory.oracle:
        return 'Oracles';
      case SystemCategory.exploration:
        return 'Exploration & maps';
      case SystemCategory.tools:
        return 'Tools';
      case SystemCategory.ruleset:
        return 'Ruleset';
    }
  }
}

/// A small dot indicator for the wizard step bar.
class _StepDot extends StatelessWidget {
  const _StepDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outlineVariant;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 12 : 8,
      height: active ? 12 : 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// A tappable stance selection card for step 0.
class _StanceCard extends StatelessWidget {
  const _StanceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(icon,
                size: 22,
                color: selected ? colorScheme.primary : colorScheme.onSurface),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A tappable start-mode card for step 2.
class _StartCard extends StatelessWidget {
  const _StartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(icon,
                size: 22,
                color: selected ? colorScheme.primary : colorScheme.onSurface),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The subtitle shown under a campaign row: the campaign's genre/mood (when set)
/// prefixed to its system profile. Genre is denormalized onto SessionMeta at
/// create/import time (a cheap, sync display mirror of CampaignSettings.genre),
/// so the list render stays sync — no per-row async settings read.
String campaignSubtitle(SessionMeta meta) {
  final systems = formatSystems(meta.enabledSystems);
  final genre = meta.genre;
  return (genre != null && genre.isNotEmpty) ? '$genre · $systems' : systems;
}

/// A campaign's identity leading: a ~6px color spine on the leading edge + an
/// icon tile (resolved from [SessionMeta.identityIcon]). [active] adds a small
/// check badge. Shared by the launcher + shell campaign lists.
class CampaignIdentityLeading extends StatelessWidget {
  const CampaignIdentityLeading({
    super.key,
    required this.meta,
    this.active = false,
  });

  final SessionMeta meta;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    final spine =
        meta.identityColor != null ? Color(meta.identityColor!) : tk.terracotta;
    return SizedBox(
      width: 46,
      height: 40,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          key: const Key('campaign-spine'),
          width: 6,
          height: 36,
          decoration: BoxDecoration(
            color: spine,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: spine.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
                border: active ? Border.all(color: spine, width: 1.5) : null,
              ),
              child: Icon(identityIconData(meta.identityIcon),
                  size: 18, color: spine),
            ),
            if (active)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration:
                      BoxDecoration(color: tk.raised, shape: BoxShape.circle),
                  child: Icon(Icons.check_circle, size: 12, color: spine),
                ),
              ),
          ],
        ),
      ]),
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
            for (final cat in SystemCategory.values) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_editCategoryLabel(cat),
                      style: Theme.of(context).textTheme.labelLarge),
                ),
              ),
              for (final id in kSystemCategory.entries
                  .where((e) => e.value == cat)
                  .map((e) => e.key))
                _row(id, kSystemShortName[id] ?? id),
            ],
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

  String _editCategoryLabel(SystemCategory c) {
    switch (c) {
      case SystemCategory.ruleset:
        return 'Ruleset';
      case SystemCategory.oracle:
        return 'Oracles';
      case SystemCategory.exploration:
        return 'Exploration & maps';
      case SystemCategory.tools:
        return 'Tools';
    }
  }
}
