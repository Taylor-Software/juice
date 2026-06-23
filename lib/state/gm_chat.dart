import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/gm_chat.dart';
import 'providers.dart';

/// Per-campaign multi-turn GM conversation, session-scoped exactly like
/// DecksNotifier (key `juice.gmchat.v1.<sessionId>`, in sessionScopedKeys so it
/// exports with the campaign).
class GmChatNotifier extends AsyncNotifier<GmChatState> {
  static const _baseKey = 'juice.gmchat.v1';
  late String _scopedKey;

  @override
  Future<GmChatState> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const GmChatState();
    return GmChatState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(GmChatState s) async {
    state = AsyncData(s);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(s.toJson()));
  }

  Future<void> appendTurn(ChatTurn t) async {
    final cur = state.valueOrNull ?? await future;
    await _save(cur.copyWith(turns: [...cur.turns, t]));
  }

  Future<void> clear() async => _save(const GmChatState());
}

final gmChatProvider =
    AsyncNotifierProvider<GmChatNotifier, GmChatState>(GmChatNotifier.new);
