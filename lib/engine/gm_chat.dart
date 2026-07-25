// A multi-turn GM conversation: ordered player/GM turns. Pure; JSON round-trips
// for per-campaign persistence (see GmChatNotifier).

/// Who spoke a turn in the Ask-the-Oracle thread.
enum ChatRole { player, gm }

/// One line of the Oracle conversation. JSON keys are terse ('r'/'t')
/// because the whole transcript is persisted per campaign.
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

/// The persisted Ask-the-Oracle transcript. The runtime keeps no LLM session,
/// so these turns ARE the conversation — they get replayed into each prompt.
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
