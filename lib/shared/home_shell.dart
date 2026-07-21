import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../engine/constructed_oracle.dart';
import '../engine/custom_table.dart';
import '../engine/funnel.dart';
import '../engine/journal_export.dart';
import '../engine/loop_kit.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/quick_ref.dart';
import '../features/campaign_search_sheet.dart';
import '../features/enter_campaign.dart';
import '../features/journal_screen.dart';
import '../features/loop_bar.dart';
import '../features/maps_tab.dart';
import '../features/settings_sheet.dart';
import '../features/oracles_tab.dart';
import '../features/sheet_tab.dart';
import '../features/run_screen.dart';
import '../features/tracking_tab.dart';
import '../state/auto_backup.dart';
import '../state/blob_store.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'campaign_preview_pane.dart';
import 'design_tokens.dart';
import 'destination.dart';
import 'help_nav.dart';
import 'play_context_hud.dart';
import 'shell_route.dart';
import 'tool_registry.dart';
import 'tool_search_sheet.dart';

/// Verb order for the Cmd/Ctrl+1..6 shortcuts (matches the nav order).
const _verbShortcutOrder = [
  Destination.journal,
  Destination.sheet,
  Destination.ask,
  Destination.map,
  Destination.track,
  Destination.run,
];
const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];

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
                        key: Key('session-duplicate-${s.id}'),
                        icon: const Icon(Icons.copy_all_outlined),
                        tooltip: 'New story with this setup',
                        onPressed: () async {
                          await ref
                              .read(sessionsProvider.notifier)
                              .duplicateSetup(s.id);
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (shellContext.mounted) {
                            await enterCampaign(shellContext, ref);
                          }
                        },
                      ),
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
                      await enterCampaign(shellContext, ref);
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
                key: const Key('menu-export-campaign'),
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Export campaign'),
                subtitle: _LastExportSubtitle(
                    ts: ref.watch(lastExportProvider).valueOrNull),
                onTap: () => _exportCampaign(dialogContext),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Import campaign'),
                onTap: () => _importCampaign(dialogContext),
              ),
              // The 8 secondary pack/notation rows fold under one group so
              // the drawer's two primary actions stay findable (audit #7).
              ExpansionTile(
                key: const Key('menu-more-io'),
                leading: const Icon(Icons.import_export),
                title: const Text('More import / export…'),
                subtitle:
                    const Text('Lonelog · table & oracle packs · loop kits'),
                children: [
                  ListTile(
                    leading: const Icon(Icons.notes_outlined),
                    title: const Text('Export as Lonelog (.md)'),
                    onTap: () => _exportLonelog(dialogContext),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Import Lonelog (.md)'),
                    onTap: () => _importLonelog(dialogContext),
                  ),
                  ListTile(
                    key: const Key('menu-export-tables'),
                    leading: const Icon(Icons.table_chart_outlined),
                    title: const Text('Export table pack'),
                    onTap: () => _exportTablePack(dialogContext),
                  ),
                  ListTile(
                    key: const Key('menu-import-tables'),
                    leading: const Icon(Icons.table_view_outlined),
                    title: const Text('Import table pack'),
                    onTap: () => _importTablePack(dialogContext),
                  ),
                  ListTile(
                    key: const Key('menu-export-oracles'),
                    leading: const Icon(Icons.casino_outlined),
                    title: const Text('Export oracle pack'),
                    onTap: () => _exportOraclePack(dialogContext),
                  ),
                  ListTile(
                    key: const Key('menu-import-oracles'),
                    leading: const Icon(Icons.casino_outlined),
                    title: const Text('Import oracle pack'),
                    onTap: () => _importOraclePack(dialogContext),
                  ),
                  ListTile(
                    key: const Key('menu-export-loopkit'),
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: const Text('Export loop kit'),
                    onTap: () => _exportLoopKit(dialogContext),
                  ),
                  ListTile(
                    key: const Key('menu-import-loopkit'),
                    leading: const Icon(Icons.inventory_outlined),
                    title: const Text('Import loop kit'),
                    onTap: () => _importLoopKit(dialogContext),
                  ),
                ],
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
    final kits = ref.read(kitsProvider).valueOrNull ?? const <LoopKit>[];
    final oracles =
        ref.read(constructedOraclesProvider).valueOrNull ?? const [];
    final result = await showDialog<NewCampaignResult>(
      context: dialogContext,
      builder: (context) => NewCampaignDialog(kits: kits, oracles: oracles),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(result.name.trim(),
        systems: result.systems, genre: result.genre, tone: result.tone);
    await ref
        .read(settingsProvider.notifier)
        .setDefaultOracle(result.defaultOracle);
    ref.read(shellRouteProvider.notifier).land();
    if (result.start == 'funnel') {
      await ref.read(charactersProvider.notifier).addFunnel(result.seedSystem);
      ref.read(shellRouteProvider.notifier).goTo(Destination.sheet);
    } else if (result.start == 'kit' && result.kit != null) {
      await applyLoopKit(ref, result.kit!);
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
      await ref.read(lastExportProvider.notifier).stamp();
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
      await ref.read(lastExportProvider.notifier).stamp();
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
      // Land on the imported campaign (or its encounter, if any).
      final enc = await ref.read(encounterProvider.future);
      ref
          .read(shellRouteProvider.notifier)
          .land(hasEncounter: enc.combatants.isNotEmpty);
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
      ref.read(shellRouteProvider.notifier).land();
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

  Future<void> _exportTablePack(BuildContext dialogContext) async {
    final tables =
        ref.read(customTablesProvider).valueOrNull ?? const <CustomTable>[];
    if (tables.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No custom tables to export.')),
        );
      }
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      return;
    }
    final json = encodeTablePack(tables);
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Export table pack',
        fileName: 'tables.tables.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
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

  Future<void> _importTablePack(BuildContext dialogContext) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import table pack',
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
      final decoded = decodeTablePack(utf8.decode(bytes));
      if (decoded.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No tables found in file.')),
          );
        }
      } else {
        await ref.read(customTablesProvider.notifier).addAll(decoded);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Imported ${decoded.length} table${decoded.length == 1 ? '' : 's'}.'),
            ),
          );
        }
      }
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a valid table pack.')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _exportOraclePack(BuildContext dialogContext) async {
    final oracles =
        ref.read(constructedOraclesProvider).valueOrNull ?? const [];
    if (oracles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No custom oracles to export.')),
        );
      }
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      return;
    }
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Export oracle pack',
        fileName: 'oracles.oracles.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(encodeOraclePack(oracles))),
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

  Future<void> _importOraclePack(BuildContext dialogContext) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import oracle pack',
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
      final decoded = decodeOraclePack(utf8.decode(bytes));
      if (decoded.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No oracles found in file.')),
          );
        }
      } else {
        await ref.read(constructedOraclesProvider.notifier).addAll(decoded);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Imported ${decoded.length} oracle${decoded.length == 1 ? '' : 's'}.')),
          );
        }
      }
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a valid oracle pack.')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _exportLoopKit(BuildContext dialogContext) async {
    final tables =
        ref.read(customTablesProvider).valueOrNull ?? const <CustomTable>[];
    final refCards =
        ref.read(userRefCardsProvider).valueOrNull ?? const <UserRefCard>[];
    final scene = activeSceneEntry(
        ref.read(journalProvider).valueOrNull ?? const [],
        ref.read(playContextProvider).valueOrNull?.activeSceneId);
    if (tables.isEmpty && refCards.isEmpty && scene == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Nothing to export yet — add tables, ref cards, or a scene first.')));
      }
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      return;
    }
    final activeName =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.name ?? 'Loop Kit';
    final kit = LoopKit(
      name: activeName,
      tables: tables,
      refCards: refCards,
      sceneTitle: scene?.title ?? '',
      sceneBody: scene?.body ?? '',
    );
    final json = encodeLoopKit(kit);
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Export loop kit',
        fileName: 'kit.loopkit.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
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

  Future<void> _importLoopKit(BuildContext dialogContext) async {
    final mode = await showDialog<String>(
      context: dialogContext,
      builder: (context) => SimpleDialog(
        title: const Text('Import loop kit'),
        children: [
          SimpleDialogOption(
            key: const Key('import-loopkit-file'),
            onPressed: () => Navigator.pop(context, 'file'),
            child: const Text('Pick a file'),
          ),
          SimpleDialogOption(
            key: const Key('import-loopkit-link'),
            onPressed: () => Navigator.pop(context, 'link'),
            child: const Text('Paste a link'),
          ),
        ],
      ),
    );
    if (mode == null) return;
    String? raw;
    if (mode == 'file') {
      raw = await _pickLoopKitFile();
    } else if (mode == 'link' && dialogContext.mounted) {
      raw = await _fetchLoopKitFromLink(dialogContext);
    }
    if (raw == null) return;
    try {
      final kit = decodeLoopKit(raw);
      if (kit == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not a loop kit.')),
          );
        }
      } else {
        await applyLoopKit(ref, kit);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported "${kit.name}".')),
          );
        }
      }
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a loop kit.')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    }
  }

  Future<String?> _pickLoopKitFile() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import loop kit',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access files: ${e.message}')),
        );
      }
      return null;
    }
    final bytes = (result == null || result.files.isEmpty)
        ? null
        : result.files.first.bytes;
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<String?> _fetchLoopKitFromLink(BuildContext dialogContext) async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Paste a link'),
        content: TextField(
          key: const Key('import-loopkit-url'),
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('import-loopkit-fetch'),
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Fetch')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not a valid URL.')),
        );
      }
      return null;
    }
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Could not fetch that link (${response.statusCode}).')));
        }
        return null;
      }
      return response.body;
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch that link.')),
        );
      }
      return null;
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
        return const PlayScreen();
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
      // Typing on a phone, the nav is 80px of destinations you are not going
      // to: the keyboard already halves the screen, and what the writer needs
      // is the story they are writing about. Yield it and hand the height to
      // the journal — the standard phone pattern, and the same
      // composer-focus collapse the HUD and the "Next" panel already do.
      // Returns on blur; the persisted route is untouched.
      final typing =
          c.maxWidth < kCompactWidth && ref.watch(journalComposerFocusProvider);
      return Scaffold(
        body: body,
        bottomNavigationBar: typing
            ? null
            : NavigationBar(
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
    // Pre-warm the bundled loop kits so they're ready by the time the user
    // opens the New-campaign wizard (avoids a first-tap race where the
    // "Import a kit" step would show no kits yet).
    ref.watch(kitsProvider);
    // Activate the silent rolling auto-backup (journal changes → rate-limited
    // export to app-support/backups; no-op on web/tests).
    ref.watch(autoBackupProvider);
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
        // Back through the verb/subtab history (empty until the user navigates).
        leading: ref.read(shellRouteProvider.notifier).canGoBack
            ? IconButton(
                key: const Key('shell-back'),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => ref.read(shellRouteProvider.notifier).back(),
              )
            : null,
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
            onPressed: () => showToolSearchSheet(
                context, buildToolRegistry(family: family, systems: systems),
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
          IconButton(
            icon: const Icon(Icons.folder_copy_outlined),
            tooltip: 'Campaigns',
            onPressed: () => _showSessions(context),
          ),
        ],
      ),
      body: SafeArea(
        // Desktop keyboard shortcuts. CallbackShortcuts only fires for focus
        // within its subtree, so the Focus(autofocus) gives the shell a node
        // before any field is focused; modifier combos still reach here while
        // typing (text fields don't consume them).
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                showCampaignSearchSheet(context),
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                showCampaignSearchSheet(context),
            const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () =>
                CampaignHeader.quickRollDefault(context, ref),
            const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
                CampaignHeader.quickRollDefault(context, ref),
            // Cmd/Ctrl+1..6 jump to the six verbs; Cmd/Ctrl+[ goes back.
            for (var i = 0; i < _verbShortcutOrder.length; i++) ...{
              SingleActivator(_digitKeys[i], meta: true): () => ref
                  .read(shellRouteProvider.notifier)
                  .goTo(_verbShortcutOrder[i]),
              SingleActivator(_digitKeys[i], control: true): () => ref
                  .read(shellRouteProvider.notifier)
                  .goTo(_verbShortcutOrder[i]),
            },
            const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
                () => ref.read(shellRouteProvider.notifier).back(),
            const SingleActivator(LogicalKeyboardKey.bracketLeft,
                    control: true):
                () => ref.read(shellRouteProvider.notifier).back(),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                const CampaignHeader(),
                Expanded(child: _shellBody(context, family, systems)),
              ],
            ),
          ),
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
  'classic-dungeon':
      'Roll 4 Ruin dungeon & cave crawler: tap openings to reveal shaped '
          'rooms, monsters, factions, treasure; descend stairs and chasms to '
          'deeper levels. Roll 4 Ruin © Nocturnal Peacock, CC BY-NC-SA 4.0.',
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
  'embark':
      'Embark 2E: heroic-yet-deadly OSR. d12 + attribute (STR/DEX/WIL/INT) >= 8; '
          '3-Injury death track, AV armor, slot inventory, 6 classes with resource pools. '
          'Based on Embark 2E by Infinite Fractal, CC BY-SA 4.0.',
  'ose': 'OSE/B/X: classic fantasy with 7 classes, 5 saving throws, descending AC, THAC0. '
      'Compatible with Old-School Essentials by Gavin Norman (Necrotic Gnome). Not affiliated with Necrotic Gnome.',
  'kal-arath': 'Kal-Arath: sword & sorcery OSR. 2d6 + stat >= 8; five stats, '
      'demonic pacts, Fate Points. Facts-only mechanics.',
  'dcc': 'Dungeon Crawl Classics: 0-level funnel, dice chain, mighty deeds, '
      'spellburn, disapproval. Facts-only mechanics. '
      'Not affiliated with Goodman Games.',
  'cards': 'Card oracles: draw from a 52-card deck or a 78-card tarot.',
  'custom': 'Custom / Homebrew sheet: build your own from configurable blocks — '
      'stats, HP, rolls, luck, timers, conditions. Facts-only; you author all content.',
  'funnel': '0-Level Funnel: run a pack of doomed peasants, then graduate '
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
  'flight_takeoff': Icons.flight_takeoff,
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
  'embark': 'Embark 2E',
  'ose': 'OSE/B/X',
  'kal-arath': 'Kal-Arath',
  'dcc': 'DCC',
  'funnel': '0-Level Funnel',
  'juice': 'Juice',
  'mythic': 'Mythic',
  'cards': 'Cards',
  'verdant': 'Verdant',
  'hexcrawl': 'Hexcrawl',
  'classic-dungeon': 'Classic Dungeon',
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
  String genre,
  String tone,
  String start,
  String seedSystem,
  LoopKit? kit,
  String defaultOracle,
});

class NewCampaignDialog extends StatefulWidget {
  const NewCampaignDialog(
      {super.key, this.kits = const [], this.oracles = const []});
  final List<LoopKit> kits;

  /// The player's app-global constructed oracles, offered as default-oracle
  /// choices alongside the built-ins.
  final List<ConstructedOracle> oracles;

  @override
  State<NewCampaignDialog> createState() => _NewCampaignDialogState();
}

class _NewCampaignDialogState extends State<NewCampaignDialog> {
  final _nameCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();
  final _toneCtrl = TextEditingController();

  // Wizard state
  int _step = 0;

  // Step 1 (system + tools)
  String? _ruleset; // single-select ruleset id, or null for None
  final Set<String> _addons = {'juice', 'party'}; // non-ruleset selections
  // Default yes/no oracle: 'juice'|'mythic'|'icons'|'cards'|'tarot'|'co:<id>'.
  String _oracle = 'juice';

  // Step 2 (start)
  String _start = 'roster'; // 'roster' | 'funnel' | 'kit'
  LoopKit? _selectedKit;

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

  // Kits matching the chosen ruleset (by `system` tag) come first-class; when
  // no ruleset is chosen (or none match — e.g. 'ruleset-none'), show every
  // bundled kit rather than an empty grid.
  List<LoopKit> get _availableKits {
    if (_ruleset == null) return widget.kits;
    final matching = widget.kits.where((k) => k.system == _ruleset).toList();
    return matching.isEmpty ? widget.kits : matching;
  }

  bool get _nextEnabled {
    if (_step == 0) return _nameCtrl.text.trim().isNotEmpty;
    return true; // step 1 is always satisfiable
  }

  void _submit() {
    final systemsForSubmit = {
      ..._systems,
      if (_start == 'funnel') 'funnel',
      // The chosen default oracle pulls in its backing system so its tools show.
      ...switch (_oracle) {
        'mythic' => const {'mythic'},
        'cards' || 'tarot' => const {'cards'},
        _ => const <String>{},
      },
    };
    Navigator.of(context).pop((
      name: _nameCtrl.text,
      systems: systemsForSubmit,
      genre: _genreCtrl.text.trim(),
      tone: _toneCtrl.text.trim(),
      start: _start,
      seedSystem: _seedSystem,
      kit: _start == 'kit' ? _selectedKit : null,
      defaultOracle: _oracle,
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
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Campaign name',
            // Explains why Next is disabled while blank — the requirement lives
            // right here on step 0, not on the (out-of-view) step-2 Create.
            helperText:
                _nameCtrl.text.trim().isEmpty ? 'Required to continue' : null,
          ),
          onChanged: (_) => setState(() {}), // refresh Next button state
        ),
      ],
    );
  }

  Widget _buildStep1() {
    final rulesetIds = kSystemCategory.entries
        .where((e) => e.value == SystemCategory.ruleset)
        .map((e) => e.key)
        .toList();
    // The wedge: rulesets front-and-centre (Ironsworn family, D&D 5e, Cairn,
    // OSE/B-X — kept alongside D&D 5e per user request). The rest are
    // facts-only sheets that ship no rulebook content, so they live behind an
    // "Experimental" drawer to keep the first choice small. Nothing about
    // registration changes — these still fully work when picked.
    const coreRulesets = {'ironsworn', 'dnd', 'cairn', 'ose'};
    final coreIds = rulesetIds.where(coreRulesets.contains).toList();
    final experimentalIds =
        rulesetIds.where((id) => !coreRulesets.contains(id)).toList();
    // 'funnel' excluded: step 2 (start choice) manages it. Toggling it here
    // and picking roster would silently enable the funnel verb with no character.
    final addonIds = kSystemCategory.entries
        .where((e) => e.value != SystemCategory.ruleset && e.key != 'funnel')
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
          for (final id in coreIds)
            ChoiceChip(
              key: Key('ruleset-$id'),
              label: Text(kSystemShortName[id] ?? id),
              selected: _ruleset == id,
              onSelected: (_) => setState(() => _ruleset = id),
            ),
        ]),
        const SizedBox(height: 4),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('ruleset-experimental'),
            initiallyExpanded: experimentalIds.contains(_ruleset),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            title: const Text('Experimental systems',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
            subtitle: const Text(
                'Facts-only sheets — no rulebook content bundled',
                style: TextStyle(fontSize: 11)),
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final id in experimentalIds)
                  ChoiceChip(
                    key: Key('ruleset-$id'),
                    label: Text(kSystemShortName[id] ?? id),
                    selected: _ruleset == id,
                    onSelected: (_) => setState(() => _ruleset = id),
                  ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final cat in const [
          SystemCategory.oracle,
          SystemCategory.exploration,
          SystemCategory.tools,
        ]) ...[
          Text(_categoryLabel(cat),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          // One-line differentiation for the oracle jargon (audit S6): a
          // stranger can't otherwise tell Juice from Mythic from Cards.
          if (cat == SystemCategory.oracle) ...[
            const SizedBox(height: 2),
            Text(
              'Juice: one-roll fate check + events · Mythic: fate chart with '
              'chaos factor · Cards: draw decks',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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
        const Text('Default oracle',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          'The quick yes/no you tap from any verb. Icons and cards draw for '
          'you to read.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in const [
            ('juice', 'Juice'),
            ('mythic', 'Mythic'),
            ('icons', 'Icons'),
            ('cards', 'Cards'),
            ('tarot', 'Tarot'),
          ])
            ChoiceChip(
              key: Key('oracle-choice-${o.$1}'),
              label: Text(o.$2),
              selected: _oracle == o.$1,
              onSelected: (_) => setState(() => _oracle = o.$1),
            ),
          for (final o in widget.oracles)
            ChoiceChip(
              key: Key('oracle-choice-co-${o.id}'),
              label: Text(o.name.isEmpty ? '(unnamed)' : o.name),
              selected: _oracle == 'co:${o.id}',
              onSelected: (_) => setState(() => _oracle = 'co:${o.id}'),
            ),
        ]),
        const SizedBox(height: 10),
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
        if (widget.kits.isNotEmpty) ...[
          const SizedBox(height: 6),
          _StartCard(
            key: const Key('new-start-kit'),
            title: 'Import a kit',
            subtitle: 'Seed tables, ref cards, and a starter scene',
            icon: Icons.inventory_2_outlined,
            selected: _start == 'kit',
            onTap: () => setState(() {
              _start = 'kit';
              _selectedKit ??= _availableKits.first;
            }),
          ),
          if (_start == 'kit') ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _availableKits.length; i++)
                  ChoiceChip(
                    key: Key('kit-pick-$i'),
                    label: Text(_availableKits[i].name,
                        style: const TextStyle(fontSize: 12)),
                    selected: identical(_selectedKit, _availableKits[i]),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    onSelected: (_) =>
                        setState(() => _selectedKit = _availableKits[i]),
                  ),
              ],
            ),
          ],
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
              color:
                  selected ? colorScheme.primary : colorScheme.outlineVariant,
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

/// Subtitle widget showing last-export recency below the Export menu item.
class _LastExportSubtitle extends StatelessWidget {
  const _LastExportSubtitle({required this.ts});
  final int? ts;

  @override
  Widget build(BuildContext context) {
    if (ts == null) {
      return Text('Never exported',
          key: const Key('export-subtitle-never'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.error));
    }
    final days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts!))
        .inDays;
    final label = days == 0
        ? 'Exported today'
        : days == 1
            ? 'Exported yesterday'
            : 'Exported $days days ago';
    return Text(label,
        key: const Key('export-subtitle-date'),
        style: Theme.of(context).textTheme.bodySmall);
  }
}
