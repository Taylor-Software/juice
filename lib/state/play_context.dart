import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/journal_search.dart';
import '../engine/loop_kit.dart';
import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import 'providers.dart';

class PlayContextNotifier extends AsyncNotifier<PlayContext> {
  static const _baseKey = 'juice.context.v1';
  late String _scopedKey;

  @override
  Future<PlayContext> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const PlayContext();
    return PlayContext.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PlayContext> get _ready async => state.valueOrNull ?? await future;

  Future<void> _save(PlayContext c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(c.toJson()));
    state = AsyncData(c);
  }

  Future<void> setActiveCharacter(String? id) async {
    final c = await _ready;
    await _save(PlayContext(
      activeCharacterId: id,
      activeSceneId: c.activeSceneId,
      activeLocation: c.activeLocation,
    ));
  }

  Future<void> setActiveScene(String? id) async {
    final c = await _ready;
    await _save(PlayContext(
      activeCharacterId: c.activeCharacterId,
      activeSceneId: id,
      activeLocation: c.activeLocation,
    ));
  }

  Future<void> setActiveLocation(LocationRef? loc) async {
    final c = await _ready;
    await _save(PlayContext(
      activeCharacterId: c.activeCharacterId,
      activeSceneId: c.activeSceneId,
      activeLocation: loc,
    ));
  }
}

final playContextProvider =
    AsyncNotifierProvider<PlayContextNotifier, PlayContext>(
        PlayContextNotifier.new);

/// Applies a decoded [LoopKit]: appends its tables/refCards to the app-global
/// stores, and — if it carries starter-scene text — creates a new scene
/// journal entry and points the PlayContext spine at it. This is the single
/// orchestration point both the creation-wizard picker and the drawer's
/// import dialog call. Lives here (not providers.dart) for the same reason as
/// [activeCharacterLineProvider] above — it needs [playContextProvider].
Future<void> applyLoopKit(WidgetRef ref, LoopKit kit) async {
  if (kit.tables.isNotEmpty) {
    await ref.read(customTablesProvider.notifier).addAll(kit.tables);
  }
  if (kit.refCards.isNotEmpty) {
    await ref.read(userRefCardsProvider.notifier).addAll(kit.refCards);
  }
  // Ensure both providers are built (so `.value` is non-null for callers)
  // even when this kit has no scene text to apply.
  await ref.read(journalProvider.future);
  await ref.read(playContextProvider.future);
  if (kit.sceneTitle.trim().isEmpty && kit.sceneBody.trim().isEmpty) return;
  final id = await ref.read(journalProvider.notifier).addScene(kit.sceneTitle);
  if (kit.sceneBody.isNotEmpty) {
    // _persist (inside addScene) sets journalProvider's state synchronously
    // before addScene returns, so .value is already the fresh list here.
    final entry =
        ref.read(journalProvider).value!.firstWhere((e) => e.id == id);
    await ref
        .read(journalProvider.notifier)
        .replace(entry.copyWith(body: kit.sceneBody));
  }
  await ref.read(playContextProvider.notifier).setActiveScene(id);
}

/// The active campaign's PC line for AI context: resolves
/// [PlayContext.activeCharacterId] against the roster, '' when unset/missing.
/// Lives here (not providers.dart) because providers.dart must not import
/// play_context.dart — the dependency already runs the other way.
final activeCharacterLineProvider = Provider<String>((ref) {
  final id = ref.watch(playContextProvider).valueOrNull?.activeCharacterId;
  final chars =
      ref.watch(charactersProvider).valueOrNull ?? const <Character>[];
  final c = id == null ? null : chars.where((x) => x.id == id).firstOrNull;
  return activeCharacterLine(c);
});

/// The campaign's current scene: the spine's pinned [activeSceneId] when set
/// and present, else the newest scene entry (journal is newest-first), else
/// null. The single source of truth for "which scene" across the HUD + AI seams.
JournalEntry? activeSceneEntry(
    List<JournalEntry> journal, String? activeSceneId) {
  final scenes = journal.where((e) => e.kind == JournalKind.scene);
  return (activeSceneId == null
          ? null
          : scenes.where((e) => e.id == activeSceneId).firstOrNull) ??
      scenes.firstOrNull;
}

/// Pure: assemble a [FleshOutSeed] from already-read campaign state.
/// `sceneTitle` = the active scene's title (see [activeSceneEntry] — the pinned
/// [activeSceneId] else the newest scene); `journalContext` = entries mentioning
/// [name] by text (name-query recall).
FleshOutSeed fleshOutSeedFrom({
  required String entityKind,
  required String name,
  required String existingDetail,
  required String systemPrimer,
  required String activeCharacter,
  required List<JournalEntry> journal,
  String? excludeId,
  String? activeSceneId,
}) {
  final sceneEntry = activeSceneEntry(journal, activeSceneId);
  final sceneTitle = (sceneEntry != null && sceneEntry.title.trim().isNotEmpty)
      ? sceneEntry.title
      : null;
  // When the entity IS a journal entry (a scene), drop it from the name-query
  // recall so its body isn't fed twice (once as `existing:`, once as `recall:`).
  final related = searchEntries(journal, name)
      .where((e) => e.id != excludeId)
      .take(kRecallMaxEntries)
      .map((e) => e.title.isEmpty ? e.body : '${e.title}: ${e.body}')
      .toList();
  return FleshOutSeed(
    entityKind: entityKind,
    name: name,
    existingDetail: existingDetail,
    systemPrimer: systemPrimer,
    activeCharacter: activeCharacter,
    sceneTitle: sceneTitle,
    journalContext: related,
  );
}

/// Wrapper for widgets: read the providers, delegate to [fleshOutSeedFrom].
FleshOutSeed buildFleshOutSeed(
  WidgetRef ref, {
  required String entityKind,
  required String name,
  required String existingDetail,
  String? excludeId,
}) =>
    fleshOutSeedFrom(
      entityKind: entityKind,
      name: name,
      existingDetail: existingDetail,
      systemPrimer: ref.read(systemPrimerProvider),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journal: ref.read(journalProvider).valueOrNull ?? const [],
      excludeId: excludeId,
      activeSceneId: ref.read(playContextProvider).valueOrNull?.activeSceneId,
    );
