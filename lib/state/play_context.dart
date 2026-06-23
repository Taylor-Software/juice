import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
