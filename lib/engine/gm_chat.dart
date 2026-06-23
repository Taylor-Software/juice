// A multi-turn GM conversation: ordered player/GM turns. Pure; JSON round-trips
// for per-campaign persistence (see GmChatNotifier).

enum ChatRole { player, gm }

class ChatTurn {
  const ChatTurn(this.role, this.text);
  final ChatRole role;
  final String text;

  Map<String, dynamic> toJson() => {'r': role.name, 't': text};

  factory ChatTurn.fromJson(Map<String, dynamic> j) => ChatTurn(
        j['r'] == 'gm' ? ChatRole.gm : ChatRole.player,
        (j['t'] as String?) ?? '',
      );
}

class GmChatState {
  const GmChatState({this.turns = const []});
  final List<ChatTurn> turns;

  GmChatState copyWith({List<ChatTurn>? turns}) =>
      GmChatState(turns: turns ?? this.turns);

  Map<String, dynamic> toJson() =>
      {'turns': turns.map((t) => t.toJson()).toList()};

  factory GmChatState.fromJson(Map<String, dynamic> j) => GmChatState(
        turns: (j['turns'] is List
                ? (j['turns'] as List<dynamic>)
                : const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => ChatTurn.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}
