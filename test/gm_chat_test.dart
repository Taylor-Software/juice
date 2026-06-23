import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/gm_chat.dart';

void main() {
  test('ChatTurn round-trips through JSON', () {
    const t = ChatTurn(ChatRole.gm, 'The door creaks open.');
    final back = ChatTurn.fromJson(t.toJson());
    expect(back.role, ChatRole.gm);
    expect(back.text, 'The door creaks open.');
  });

  test('GmChatState round-trips; tolerant of junk', () {
    const s = GmChatState(turns: [
      ChatTurn(ChatRole.player, 'Is it locked?'),
      ChatTurn(ChatRole.gm, 'No, it swings free.'),
    ]);
    final back = GmChatState.fromJson(s.toJson());
    expect(back.turns, hasLength(2));
    expect(back.turns.first.role, ChatRole.player);
    expect(back.turns.last.text, 'No, it swings free.');
    // Missing/odd keys default safely.
    final j = GmChatState.fromJson(const {
      'turns': [{}, 'nope']
    });
    expect(j.turns, hasLength(1)); // the {} parses to an empty player turn
    expect(j.turns.first.role, ChatRole.player);
    expect(GmChatState.fromJson(const {}).turns, isEmpty);
  });
}
