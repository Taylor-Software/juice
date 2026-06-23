# AI expansion #2: multi-turn GM chat

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

"Ask the GM" (the assistant rail) is a single Q→A: ask, get one answer, no
memory. AI expansion #1 gave the seams rich grounding (system/pc/scene/recall);
this builds the **flagship** on top — a real **conversation** where the GM
remembers the thread and the player follows up.

The on-device Gemma runtime is **stateless**: `GemmaInterpreterService._generate`
creates a *fresh chat* per call. So multi-turn is done by rendering the
conversation **transcript into the prompt** each turn — no stateful model
session. This fits the existing single-shot seam exactly.

## Decisions (from brainstorming)

- **Persisted per campaign** (session-scoped, exports with the campaign).
- **Dedicated chat view** (full-height route), opened from the assistant rail's
  Ask-GM box.
- **Separate thread + manual save** — nothing auto-logs; a per-message
  "save to journal" action.
- Transcript window: the **last 8 turns** (capped per-turn); older dropped.
- The single-shot `askGm` seam is **kept** (tested primitive; app-unused after
  this — cleanup is a later follow-up).

## Architecture

### 1. Model — `lib/engine/gm_chat.dart` (pure)

```dart
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
        turns: (j['turns'] is List ? j['turns'] as List : const [])
            .whereType<Map>()
            .map((m) => ChatTurn.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}
```

### 2. Seam — `oracle_interpreter.dart` + `interpreter.dart`

```dart
const int kGmChatHistoryTurns = 8;   // last N turns rendered
const int kGmChatTurnMaxChars = 300; // per-turn cap (≈ kAskGmMaxFieldChars)

class GmChatSeed {
  const GmChatSeed({
    required this.history,
    this.sceneTitle,
    this.systemPrimer = '',
    this.activeCharacter = '',
    this.journalContext = const [],
  });
  final List<ChatTurn> history; // full transcript incl. the latest player turn
  final String? sceneTitle;
  final String systemPrimer;
  final String activeCharacter;
  final List<String> journalContext;
}
```

`buildGmChatPrompt(GmChatSeed)`:
- `_gmChatInstruction`: "You are the game master for a solo tabletop RPG in an
  ongoing conversation. Continue as the GM: answer the player's latest message
  in 1-3 sentences of plain prose, consistent with the conversation and the
  established facts. Be concrete and decisive. Output only the GM's words."
- Then the **#1 grounding** lines (reuse the existing pattern):
  `system:` / `pc:` (via `_pcLine`) / `scene:` / `recall:` (capped, taking
  `kRecallMaxEntries`).
- Then the **transcript** — the last `kGmChatHistoryTurns` of `history`, each
  `Player: <text>` / `GM: <text>` (flattened, capped at `kGmChatTurnMaxChars`).
- Then a trailing `GM:` for the model to continue.

`parseGmChatResponse(String)` — strip `<think>` + trim, throw on empty (mirrors
`parseAskGmResponse`).

`InterpreterService.gmChat(GmChatSeed) → Future<String>`:
- `GemmaInterpreterService`:
  `parseGmChatResponse(await _generate(buildGmChatPrompt(seed)))` — reuses the
  stateless `_generate` (fresh chat, whole transcript in the prompt).
- `FakeInterpreterService`: a counter + optional error + a canned reply (so
  widget tests drive it), mirroring its `askGm` fake.

### 3. State — `lib/state/gm_chat.dart`

`GmChatNotifier extends AsyncNotifier<GmChatState>`, session-scoped exactly like
`DecksNotifier`:
- `_baseKey = 'juice.gmchat.v1'`; `_scopedKey = '$_baseKey.${sessions.active}'`;
  `build()` loads/parses, `_save(state)` sets `AsyncData` then persists.
- `appendTurn(ChatTurn t)` → `_save(cur.copyWith(turns: [...cur.turns, t]))`.
- `clear()` → `_save(const GmChatState())`.
- `gmChatProvider = AsyncNotifierProvider<GmChatNotifier, GmChatState>(...)`.
- **Add `'juice.gmchat.v1'` to `sessionScopedKeys`** so the thread exports/imports
  with the campaign.

### 4. UI — `lib/features/gm_chat_screen.dart`

A `ConsumerStatefulWidget` pushed as a full route (`showGmChat(context, {initialMessage})`):
- Watches `gmChatProvider` (turns) + `aiReadyProvider`.
- A reversed `ListView` of chat bubbles: player right (primary), GM left
  (surface); keys `gm-chat-bubble-<i>`.
- An input row (`gm-chat-input` + `gm-chat-send`); a busy spinner while awaiting.
- App-bar: a **clear** action (`gm-chat-clear` → `clear()`).
- Each GM bubble has a **save-to-journal** action (`gm-chat-save-<i>`) →
  `addResult('GM chat', 'Player: <preceding>\n\nGM: <text>', sourceTool: 'gm-chat')`
  + a snackbar.
- `_send(text)`:
  1. `appendTurn(ChatTurn(ChatRole.player, text))`.
  2. Build `GmChatSeed`: `history` = the updated turns; `sceneTitle` = latest
     scene entry title; `systemPrimer` = `systemPrimerProvider`;
     `activeCharacter` = `activeCharacterLineProvider`; `journalContext` =
     `recallLines(journal, <synthetic target from text>)`.
  3. `await gmChat(seed)` (busy = true); on success `appendTurn(ChatTurn(gm, answer))`.
  4. On error: snackbar; the player turn stays (the player can retry).
- If `initialMessage` is non-empty, `_send` it once on first frame.

### 5. Entry point — `lib/features/assistant_rail.dart`

The Ask-GM box's submit **opens the chat** instead of the single-shot call:
`showGmChat(context, initialMessage: q)` then clears the box. (The single-shot
`_ask`/`askGm` path is removed from the rail; the `askGm` seam + `buildAskGmPrompt`
stay in the engine.) Gated on `aiReadyProvider` as today.

## Testing

- `gm_chat` model test: `ChatTurn`/`GmChatState` JSON round-trip; tolerant
  `fromJson` (missing keys / junk).
- `oracle_interpreter` test: `buildGmChatPrompt` renders the grounding lines +
  a `Player:`/`GM:` transcript of the last `kGmChatHistoryTurns` (older dropped)
  + a trailing `GM:`; per-turn cap applied; `parseGmChatResponse` strips think /
  throws on empty.
- `gm_chat` provider test: `appendTurn` persists + accumulates; `clear` empties;
  reload from prefs round-trips; the key is in `sessionScopedKeys`.
- `gm_chat_screen` widget test (fake interpreter): sending a message appends a
  player bubble then a GM bubble; `gm-chat-save-<i>` adds a `gm-chat` journal
  entry; `gm-chat-clear` empties the thread.

## Out of scope (later)

- Stateful model sessions / token streaming; editing or deleting past turns;
  multiple named threads per campaign; auto-summarizing old turns to extend the
  window; removing the single-shot `askGm` (kept this PR); per-campaign AI
  override. #3 (a new affordance) is separate.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/gm_chat.dart` | new: `ChatRole`, `ChatTurn`, `GmChatState` |
| `lib/engine/oracle_interpreter.dart` | `GmChatSeed`, `buildGmChatPrompt`, `parseGmChatResponse`, consts |
| `lib/state/interpreter.dart` | `gmChat` on the interface |
| `lib/state/interpreter_gemma.dart` | `gmChat` impl (stateless `_generate`) |
| `lib/state/gm_chat.dart` | new: `GmChatNotifier` + `gmChatProvider` |
| `lib/state/providers.dart` | add `'juice.gmchat.v1'` to `sessionScopedKeys` |
| `lib/features/gm_chat_screen.dart` | new: the chat view + `showGmChat` |
| `lib/features/assistant_rail.dart` | Ask-GM box opens the chat |
| `test/fake_interpreter.dart` | `gmChat` fake |
| tests | `gm_chat` model/provider, `oracle_interpreter` (prompt), `gm_chat_screen` widget |
