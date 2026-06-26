import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/campaign_presets.dart';
import '../engine/journal_export.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../features/enter_campaign.dart';
import '../features/journal_screen.dart';
import '../features/maps_tab.dart';
import '../features/settings_sheet.dart';
import '../features/oracles_tab.dart';
import '../features/sheet_tab.dart';
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
    final result = await showDialog<
        ({
          String name,
          Set<String> systems,
          CampaignMode mode,
          String genre,
          String tone
        })>(
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
            icon: const Icon(Icons.search),
            tooltip: 'Find tools & rolls',
            onPressed: () => showToolSearchSheet(context,
                buildToolRegistry(family: family, systems: systems, mode: mode),
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
  'cards': 'Card oracles: draw from a 52-card deck or a 78-card tarot.',
};

const kPresetIcons = <String, IconData>{
  'solo-ironsworn': Icons.bolt,
  'solo-dnd': Icons.castle,
  'solo-shadowdark': Icons.dark_mode,
  'solo-nimble': Icons.flash_on,
  'solo-draw-steel': Icons.shield,
  'solo-argosa': Icons.fort,
  'solo-cairn': Icons.terrain,
  'solo-knave': Icons.content_cut,
  'solo-ose': Icons.auto_stories,
  'solo-kal-arath': Icons.whatshot,
  'oracle': Icons.casino,
  'gm-toolkit': Icons.book,
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
  'juice': 'Juice',
  'mythic': 'Mythic',
  'cards': 'Cards',
  'verdant': 'Verdant',
  'hexcrawl': 'Hexcrawl',
  'party': 'Party',
  'lonelog': 'Lonelog',
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

  String? _presetId = 'solo-ironsworn'; // default selection
  bool _custom = false;
  // Custom-mode working set:
  String? _ruleset; // single-select ruleset id, or null
  final Set<String> _addons = {'juice', 'party'}; // non-ruleset picks
  CampaignMode _mode = CampaignMode.party;

  @override
  void dispose() {
    _controller.dispose();
    _genre.dispose();
    _tone.dispose();
    super.dispose();
  }

  /// The (mode, systems) the Create button will submit.
  (CampaignMode, Set<String>) _resolved() {
    if (_custom) {
      return (_mode, {if (_ruleset != null) _ruleset!, ..._addons});
    }
    final p = kCampaignPresets.firstWhere((p) => p.id == _presetId);
    return presetConfig(p);
  }

  void _submit() {
    final (mode, systems) = _resolved();
    Navigator.of(context).pop((
      name: _controller.text,
      systems: systems,
      mode: mode,
      genre: _genre.text.trim(),
      tone: _tone.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rulesetIds = kSystemCategory.entries
        .where((e) => e.value == SystemCategory.ruleset)
        .map((e) => e.key)
        .toList();
    final addonIds = kSystemCategory.entries
        .where((e) => e.value != SystemCategory.ruleset)
        .map((e) => e.key)
        .toList();

    return AlertDialog(
      title: const Text('New campaign'),
      content: SizedBox(
        width: 460,
        // Fixed height + internal scroll keeps all chips within the visible
        // area of the dialog regardless of content mode. autofocus is false
        // to prevent SingleChildScrollView jumping on field focus change.
        height: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('new-campaign-name'),
              controller: _controller,
              autofocus: false,
              decoration: const InputDecoration(labelText: 'Campaign name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            // Show preset rows OR custom picker — not both
            if (!_custom) ...[
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('What kind of story are you telling?')),
              const SizedBox(height: 6),
              for (final p in kCampaignPresets)
                _PresetRow(
                  preset: p,
                  selected: _presetId == p.id,
                  onTap: () => setState(() => _presetId = p.id),
                ),
              _BrowseAllRow(onTap: () => setState(() => _custom = true)),
            ] else ...[
              _customPicker(rulesetIds, addonIds),
            ],
            // Genre/tone are campaign metadata — always available, both modes.
            const SizedBox(height: 8),
            TextField(
              key: const Key('new-campaign-genre'),
              controller: _genre,
              decoration: const InputDecoration(
                  labelText: 'Genre (optional)',
                  hintText: 'e.g. grimdark fantasy'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('new-campaign-tone'),
              controller: _tone,
              decoration: const InputDecoration(
                  labelText: 'Tone (optional)',
                  hintText: 'e.g. tense and dangerous'),
            ),
            const SizedBox(height: 12),
            const Divider(),
            Builder(builder: (_) {
              final (mode, systems) = _resolved();
              return CampaignPreviewPane(mode: mode, systems: systems);
            }),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }

  Widget _customPicker(List<String> rulesetIds, List<String> addonIds) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('preset-back'),
          onPressed: () => setState(() => _custom = false),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back to presets'),
        ),
      ),
      const Text('Ruleset (pick one)'),
      const SizedBox(height: 4),
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
      const SizedBox(height: 8),
      for (final cat in const [
        SystemCategory.oracle,
        SystemCategory.exploration,
        SystemCategory.tools
      ]) ...[
        Text(_categoryLabel(cat)),
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
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 4),
      SegmentedButton<CampaignMode>(
        key: const Key('new-campaign-mode'),
        segments: const [
          ButtonSegment(value: CampaignMode.party, label: Text('Party')),
          ButtonSegment(value: CampaignMode.gm, label: Text('GM')),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
      if (_mode == CampaignMode.gm)
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text('GM mode hides party tools & shows Rumors',
              style: TextStyle(fontSize: 11)),
        ),
    ]);
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

/// The subtitle shown under a campaign row. We show the system profile (not a
/// genre/mood line): genre lives in per-campaign CampaignSettings
/// (`juice.settings.v1.<id>`) with no sync provider for arbitrary sessions, so
/// a genre subtitle would force a heavy async read per row. Systems are already
/// on SessionMeta — cheap and sync.
String campaignSubtitle(SessionMeta meta) => formatSystems(meta.enabledSystems);

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

/// A rich, tappable campaign-preset row: a 36px icon tile + the kind-of-play
/// headline + a `blurb · <ruleset>` sublabel. Styled with Phase-0 JuiceTokens.
class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final CampaignPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? tk.sand : tk.raised,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          key: Key('preset-${preset.id}'),
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? tk.terracotta : tk.borderInput,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tk.selected,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(kPresetIcons[preset.id],
                    size: 20, color: tk.terracotta),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(preset.kind,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: tk.ink)),
                    Text('${preset.blurb} · ${preset.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: tk.inkMuted)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The dashed "Browse all systems" entry rendered below the preset rows.
class _BrowseAllRow extends StatelessWidget {
  const _BrowseAllRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        key: const Key('preset-custom'),
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: DottedBorderBox(
          color: tk.borderInput,
          radius: 15,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(children: [
              Icon(Icons.tune, size: 20, color: tk.inkMuted),
              const SizedBox(width: 10),
              Text('Browse all systems',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tk.inkBody)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A lightweight dashed-border container (no extra deps) for the "Browse all"
/// affordance — distinguishes it from the solid preset rows.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.child,
    required this.color,
    this.radius = 12,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, (d + dash).clamp(0, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
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
