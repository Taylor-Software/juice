# Multi-turn GM Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn "Ask the GM" into a persisted multi-turn conversation grounded in the #1 campaign context, with a dedicated chat view.

**Architecture:** A pure `gm_chat.dart` model (`ChatTurn`/`GmChatState`); a stateless `gmChat` seam that renders the #1 grounding + a last-8-turn transcript into one prompt (reusing the fresh-chat `_generate`); a session-scoped `GmChatNotifier`; a `gm_chat_screen.dart` bubble thread opened from the assistant rail.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `_generate`/`_flat`/`_capped`/`_pcLine`/`_stripThink`/`recallLines` (oracle_interpreter), the `DecksNotifier` persistence pattern, `aiReadyProvider`, `systemPrimerProvider`, `activeCharacterLineProvider`.

---

## File Structure

- **Create** `lib/engine/gm_chat.dart` — `ChatRole`, `ChatTurn`, `GmChatState`. Pure.
- **Modify** `lib/engine/oracle_interpreter.dart` — `GmChatSeed`, `buildGmChatPrompt`, `parseGmChatResponse`, consts.
- **Modify** `lib/state/interpreter.dart` — `gmChat` on the interface.
- **Modify** `lib/state/interpreter_gemma.dart` — `gmChat` impl.
- **Modify** `test/fake_interpreter.dart` — `gmChat` fake.
- **Create** `lib/state/gm_chat.dart` — `GmChatNotifier` + `gmChatProvider`.
- **Modify** `lib/state/providers.dart` — add `'juice.gmchat.v1'` to `sessionScopedKeys`.
- **Create** `lib/features/gm_chat_screen.dart` — chat view + `showGmChat`.
- **Modify** `lib/features/assistant_rail.dart` — Ask-GM box opens the chat.
- **Tests** `test/gm_chat_test.dart`, `test/oracle_interpreter_test.dart`, `test/gm_chat_provider_test.dart`, `test/gm_chat_screen_test.dart`, `test/assistant_rail_test.dart`.

---

## Task 1: Model — ChatTurn / GmChatState

**Files:**
- Create: `lib/engine/gm_chat.dart`
- Test: `test/gm_chat_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/gm_chat_test.dart`:

```dart
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
    final j = GmChatState.fromJson(const {'turns': [{}, 'nope']});
    expect(j.turns, hasLength(1)); // the {} parses to an empty player turn
    expect(j.turns.first.role, ChatRole.player);
    expect(GmChatState.fromJson(const {}).turns, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/gm_chat_test.dart`
Expected: FAIL — `gm_chat.dart` not found.

- [ ] **Step 3: Implement**

Create `lib/engine/gm_chat.dart`:

```dart
/// A multi-turn GM conversation: ordered player/GM turns. Pure; JSON round-trips
/// for per-campaign persistence (see GmChatNotifier).

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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/gm_chat_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/gm_chat.dart test/gm_chat_test.dart
git commit -m "feat(ai): GM chat model (ChatTurn / GmChatState)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Seam — GmChatSeed + buildGmChatPrompt + parseGmChatResponse

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart`
- Test: `test/oracle_interpreter_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/oracle_interpreter_test.dart` inside `void main()` (it imports `oracle_interpreter.dart`; add `import 'package:juice_oracle/engine/gm_chat.dart';` near the other imports):

```dart
  group('buildGmChatPrompt', () {
    test('grounds the chat + renders the transcript + trailing GM:', () {
      final p = buildGmChatPrompt(const GmChatSeed(
        history: [
          ChatTurn(ChatRole.player, 'Who guards the gate?'),
          ChatTurn(ChatRole.gm, 'A bored sergeant named Doll.'),
          ChatTurn(ChatRole.player, 'Can I bribe her?'),
        ],
        sceneTitle: 'The city gate',
        systemPrimer: 'Ironsworn: perilous Iron Lands.',
        activeCharacter: 'Taurin (PC)',
        journalContext: ['Doll owes Taurin a favor.'],
      ));
      expect(p, contains('system: Ironsworn'));
      expect(p, contains('pc: Taurin (PC)'));
      expect(p, contains('scene: The city gate'));
      expect(p, contains('recall: Doll owes Taurin a favor.'));
      expect(p, contains('Player: Who guards the gate?'));
      expect(p, contains('GM: A bored sergeant named Doll.'));
      expect(p, contains('Player: Can I bribe her?'));
      expect(p.trimRight(), endsWith('GM:')); // model continues as GM
    });

    test('keeps only the last kGmChatHistoryTurns turns', () {
      final history = [
        for (var i = 0; i < kGmChatHistoryTurns + 3; i++)
          ChatTurn(ChatRole.player, 'turn$i'),
      ];
      final p = buildGmChatPrompt(GmChatSeed(history: history));
      expect(p, isNot(contains('turn0'))); // dropped (oldest)
      expect(p, contains('turn${kGmChatHistoryTurns + 2}')); // newest kept
      final shown =
          'Player:'.allMatches(p).length; // one per rendered player turn
      expect(shown, kGmChatHistoryTurns);
    });

    test('parseGmChatResponse strips think + throws on empty', () {
      expect(parseGmChatResponse('<think>x</think> Doll grins. '), 'Doll grins.');
      expect(() => parseGmChatResponse('  '), throwsFormatException);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: FAIL — `GmChatSeed`/`buildGmChatPrompt`/`parseGmChatResponse`/`kGmChatHistoryTurns` undefined.

- [ ] **Step 3: Implement**

In `lib/engine/oracle_interpreter.dart`:

(a) Add the import (beside `models.dart`):

```dart
import 'gm_chat.dart';
```

(b) At the end of the "Ask the GM" section (after `parseAskGmResponse`), add:

```dart
// -- Multi-turn GM chat -------------------------------------------------------

const int kGmChatHistoryTurns = 8;   // last N turns rendered into the prompt
const int kGmChatTurnMaxChars = 300; // per-turn cap

const String _gmChatInstruction =
    'You are the game master for a solo tabletop RPG in an ongoing conversation '
    "with the player. Continue as the GM: answer the player's latest message in "
    '1-3 sentences of plain prose, consistent with the conversation and the '
    "established facts. Be concrete and decisive. Output only the GM's words.";

class GmChatSeed {
  const GmChatSeed({
    required this.history,
    this.sceneTitle,
    this.systemPrimer = '',
    this.activeCharacter = '',
    this.journalContext = const [],
  });

  /// The full transcript, oldest first, INCLUDING the latest player turn.
  final List<ChatTurn> history;
  final String? sceneTitle;
  final String systemPrimer;
  final String activeCharacter;
  final List<String> journalContext;
}

/// Stateless multi-turn prompt: instruction + the #1 grounding (system/pc/scene/
/// recall) + a transcript of the last [kGmChatHistoryTurns] turns + a trailing
/// `GM:` for the model to continue. Caps mirror the other builders.
String buildGmChatPrompt(GmChatSeed seed) {
  final scene = seed.sceneTitle;
  final sceneLine = (scene == null || scene.trim().isEmpty)
      ? ''
      : 'scene: ${_capped(_flat(scene))}\n';
  final primer = _flat(seed.systemPrimer);
  final systemLine = primer.isEmpty ? '' : 'system: ${_capped(primer)}\n';
  final recall = StringBuffer();
  for (final context in seed.journalContext.take(kRecallMaxEntries)) {
    final f = _flat(context);
    if (f.isEmpty) continue;
    final cut =
        f.length > kRecallMaxChars ? '${f.substring(0, kRecallMaxChars)}…' : f;
    recall.write('recall: $cut\n');
  }
  final recent = seed.history.length > kGmChatHistoryTurns
      ? seed.history.sublist(seed.history.length - kGmChatHistoryTurns)
      : seed.history;
  final transcript = StringBuffer();
  for (final t in recent) {
    final who = t.role == ChatRole.gm ? 'GM' : 'Player';
    var line = _flat(t.text);
    if (line.length > kGmChatTurnMaxChars) {
      line = '${line.substring(0, kGmChatTurnMaxChars)}…';
    }
    transcript.write('$who: $line\n');
  }
  return '$_gmChatInstruction\n\n'
      'INPUT:\n'
      '$systemLine'
      '${_pcLine(seed.activeCharacter)}'
      '$sceneLine'
      '$recall'
      '$transcript'
      'GM:';
}

/// Plain-text parse (like parseAskGmResponse): strip think spans, trim, throw
/// on empty.
String parseGmChatResponse(String raw) {
  final out = _stripThink(raw).trim();
  if (out.isEmpty) throw const FormatException('Empty GM chat response');
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat(ai): gmChat seam — GmChatSeed + buildGmChatPrompt + parse

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Interface + impls (gmChat)

**Files:**
- Modify: `lib/state/interpreter.dart`, `lib/state/interpreter_gemma.dart`, `test/fake_interpreter.dart`

(No new unit test of its own — the fake's `gmChat` is exercised by Task 5's widget test; this task just makes the interface + impls compile.)

- [ ] **Step 1: Add the interface method**

In `lib/state/interpreter.dart`, in `abstract class InterpreterService`, after the `askGm` declaration add:

```dart
  /// Free-form GM answer continuing a multi-turn conversation (plain text).
  /// Stateless: the whole transcript rides in the prompt. Requires ready.
  Future<String> gmChat(GmChatSeed seed);
```

(`GmChatSeed` comes from `oracle_interpreter.dart`, already imported by this file for the other seeds.)

- [ ] **Step 2: Add the Gemma impl**

In `lib/state/interpreter_gemma.dart`, after the `askGm` override add:

```dart
  @override
  Future<String> gmChat(GmChatSeed seed) async {
    return parseGmChatResponse(await _generate(buildGmChatPrompt(seed)));
  }
```

- [ ] **Step 3: Add the fake impl**

In `test/fake_interpreter.dart`, beside the askGm fake fields/method, add the fields (near `askGmCalls`):

```dart
  int gmChatCalls = 0;
  Object? gmChatError;
  GmChatSeed? lastGmChatSeed;
  final List<String> queuedGmChat = [];
```

and the method (beside the `askGm` override):

```dart
  @override
  Future<String> gmChat(GmChatSeed seed) async {
    lastGmChatSeed = seed;
    gmChatCalls++;
    if (gmChatError != null) throw gmChatError!;
    if (queuedGmChat.isEmpty) return 'A canned GM reply.';
    return queuedGmChat.removeAt(0);
  }
```

(`GmChatSeed` is from `oracle_interpreter.dart`, already imported by the fake for the other seeds; if not, add `import 'package:juice_oracle/engine/oracle_interpreter.dart';`.)

- [ ] **Step 4: Verify it compiles + existing tests pass**

Run: `flutter analyze lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart` → expect no issues.
Run: `flutter test test/interpreter_test.dart test/ask_gm_test.dart` → expect PASS (the fake now satisfies the interface).

- [ ] **Step 5: Commit**

```bash
git add lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart
git commit -m "feat(ai): gmChat on InterpreterService (+ Gemma + fake impls)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: State — GmChatNotifier + persistence

**Files:**
- Create: `lib/state/gm_chat.dart`
- Modify: `lib/state/providers.dart` (add to `sessionScopedKeys`)
- Test: `test/gm_chat_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/gm_chat_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/gm_chat.dart';
import 'package:juice_oracle/state/gm_chat.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('appendTurn accumulates + persists; clear empties; key is scoped',
      () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(gmChatProvider.future);

    await c
        .read(gmChatProvider.notifier)
        .appendTurn(const ChatTurn(ChatRole.player, 'Hi'));
    await c
        .read(gmChatProvider.notifier)
        .appendTurn(const ChatTurn(ChatRole.gm, 'Hello, traveler.'));
    expect(c.read(gmChatProvider).valueOrNull!.turns, hasLength(2));

    // Persisted: a fresh container reads it back.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final reloaded = await c2.read(gmChatProvider.future);
    expect(reloaded.turns, hasLength(2));
    expect(reloaded.turns.last.text, 'Hello, traveler.');

    await c.read(gmChatProvider.notifier).clear();
    expect(c.read(gmChatProvider).valueOrNull!.turns, isEmpty);
  });

  test('gmchat key is exported with the campaign', () {
    expect(sessionScopedKeys, contains('juice.gmchat.v1'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/gm_chat_provider_test.dart`
Expected: FAIL — `gm_chat.dart` (state) / `gmChatProvider` undefined; `sessionScopedKeys` lacks the key.

- [ ] **Step 3: Implement**

Create `lib/state/gm_chat.dart`:

```dart
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
```

In `lib/state/providers.dart`, add to the `sessionScopedKeys` list (after `'juice.decks.v1',`):

```dart
  'juice.gmchat.v1',
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/gm_chat_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/gm_chat.dart lib/state/providers.dart test/gm_chat_provider_test.dart
git commit -m "feat(ai): GmChatNotifier (session-scoped, exported)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: UI — gm_chat_screen.dart

**Files:**
- Create: `lib/features/gm_chat_screen.dart`
- Test: `test/gm_chat_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/gm_chat_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/gm_chat_screen.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Future<ProviderContainer> pumpChat(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
  });
  final fake = FakeInterpreterService();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      interpreterServiceProvider.overrideWithValue(fake),
      aiReadyProvider.overrideWith((ref) => true),
    ],
    child: const MaterialApp(home: GmChatScreen()),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(GmChatScreen)));
}

void main() {
  testWidgets('sending a message appends a player then a GM bubble',
      (tester) async {
    final container = await pumpChat(tester);
    await tester.enterText(
        find.byKey(const Key('gm-chat-input')), 'Is the bridge safe?');
    await tester.tap(find.byKey(const Key('gm-chat-send')));
    await tester.pumpAndSettle();
    final turns = container.read(gmChatProvider).valueOrNull!.turns;
    expect(turns, hasLength(2));
    expect(turns.first.text, 'Is the bridge safe?');
    expect(turns.last.text, 'A canned GM reply.'); // from the fake
    expect(find.text('A canned GM reply.'), findsOneWidget);
  });

  testWidgets('save-to-journal writes a gm-chat entry', (tester) async {
    final container = await pumpChat(tester);
    await tester.enterText(find.byKey(const Key('gm-chat-input')), 'Hello?');
    await tester.tap(find.byKey(const Key('gm-chat-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gm-chat-save-1'))); // the GM turn
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull ?? const [];
    expect(entries.where((e) => e.sourceTool == 'gm-chat'), hasLength(1));
  });

  testWidgets('clear empties the thread', (tester) async {
    final container = await pumpChat(tester);
    await tester.enterText(find.byKey(const Key('gm-chat-input')), 'Hi');
    await tester.tap(find.byKey(const Key('gm-chat-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gm-chat-clear')));
    await tester.pumpAndSettle();
    expect(container.read(gmChatProvider).valueOrNull!.turns, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/gm_chat_screen_test.dart`
Expected: FAIL — `gm_chat_screen.dart` / `GmChatScreen` not found.

- [ ] **Step 3: Implement**

Create `lib/features/gm_chat_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/gm_chat.dart';
import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../state/gm_chat.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';

/// Opens the multi-turn GM chat full-screen; optionally sends [initialMessage]
/// as the first turn.
Future<void> showGmChat(BuildContext context, {String? initialMessage}) {
  return Navigator.of(context).push<void>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => GmChatScreen(initialMessage: initialMessage),
  ));
}

class GmChatScreen extends ConsumerStatefulWidget {
  const GmChatScreen({super.key, this.initialMessage});
  final String? initialMessage;

  @override
  ConsumerState<GmChatScreen> createState() => _GmChatScreenState();
}

class _GmChatScreenState extends ConsumerState<GmChatScreen> {
  final _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final first = widget.initialMessage?.trim() ?? '';
    if (first.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(first));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    _input.clear();
    final notifier = ref.read(gmChatProvider.notifier);
    await notifier.appendTurn(ChatTurn(ChatRole.player, t));
    setState(() => _busy = true);
    try {
      final journal = ref.read(journalProvider).valueOrNull ?? const [];
      final scene = journal
          .where((e) => e.kind == JournalKind.scene)
          .map((e) => e.title)
          .firstOrNull;
      final target = JournalEntry(
          id: 'gm-chat-target', timestamp: DateTime.now(), title: '', body: t);
      final history = ref.read(gmChatProvider).valueOrNull?.turns ?? const [];
      final answer = await ref.read(interpreterServiceProvider).gmChat(GmChatSeed(
            history: history,
            sceneTitle: scene,
            systemPrimer: ref.read(systemPrimerProvider),
            activeCharacter: ref.read(activeCharacterLineProvider),
            journalContext: recallLines(journal, target),
          ));
      await notifier.appendTurn(ChatTurn(ChatRole.gm, answer));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The GM did not answer — try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveToJournal(List<ChatTurn> turns, int i) {
    final gm = turns[i];
    final prior = i > 0 ? turns[i - 1] : null;
    final body = prior != null && prior.role == ChatRole.player
        ? 'Player: ${prior.text}\n\nGM: ${gm.text}'
        : 'GM: ${gm.text}';
    ref
        .read(journalProvider.notifier)
        .addResult('GM chat', body, sourceTool: 'gm-chat');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to journal')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final turns = ref.watch(gmChatProvider).valueOrNull?.turns ?? const [];
    final aiReady = ref.watch(aiReadyProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('GM chat'),
        actions: [
          IconButton(
            key: const Key('gm-chat-clear'),
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear chat',
            onPressed: turns.isEmpty
                ? null
                : () => ref.read(gmChatProvider.notifier).clear(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: turns.isEmpty
                ? Center(
                    child: Text('Ask the GM anything.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: turns.length,
                    itemBuilder: (context, ri) {
                      final i = turns.length - 1 - ri; // reversed view
                      return _bubble(theme, turns, i);
                    },
                  ),
          ),
          if (_busy) const LinearProgressIndicator(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('gm-chat-input'),
                      controller: _input,
                      enabled: aiReady && !_busy,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: aiReady
                            ? 'Message the GM…'
                            : 'Enable AI in Settings',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('gm-chat-send'),
                    icon: const Icon(Icons.send),
                    onPressed:
                        aiReady && !_busy ? () => _send(_input.text) : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ThemeData theme, List<ChatTurn> turns, int i) {
    final t = turns[i];
    final isGm = t.role == ChatRole.gm;
    final scheme = theme.colorScheme;
    return Align(
      alignment: isGm ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Card(
          key: Key('gm-chat-bubble-$i'),
          color: isGm ? scheme.surfaceContainerHighest : scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.text),
                if (isGm)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: Key('gm-chat-save-$i'),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                      label: const Text('Save'),
                      onPressed: () => _saveToJournal(turns, i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/gm_chat_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/gm_chat_screen.dart test/gm_chat_screen_test.dart
git commit -m "feat(ai): GM chat screen — bubble thread, send, save, clear

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Entry point — assistant rail opens the chat

**Files:**
- Modify: `lib/features/assistant_rail.dart`
- Test: `test/assistant_rail_test.dart`

- [ ] **Step 1: Update the existing rail test**

The rail's Ask-GM box now OPENS the chat instead of single-shot-logging. In `test/assistant_rail_test.dart`, find the test that asserts asking the GM logs an `ask-gm` journal entry and replace its assertion: after entering text + submitting, expect a `GmChatScreen` is pushed (and NO `ask-gm` journal entry). Concretely, replace that test body's tail with:

```dart
    // Submitting the ask box now opens the multi-turn GM chat.
    expect(find.byType(GmChatScreen), findsOneWidget);
    final entries = container.read(journalProvider).valueOrNull ?? const [];
    expect(entries.where((e) => e.sourceTool == 'ask-gm'), isEmpty);
```

Add `import 'package:juice_oracle/features/gm_chat_screen.dart';` to the test. (If the rail test pumps the rail without a Navigator/MaterialApp, wrap it in `MaterialApp(home: Scaffold(body: AssistantRail(...)))` so `showGmChat`'s `Navigator.push` works — confirm the existing harness already provides a Navigator; the journal-screen-hosted harness does.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/assistant_rail_test.dart`
Expected: FAIL — the rail still logs `ask-gm`; no `GmChatScreen` pushed.

- [ ] **Step 3: Implement**

In `lib/features/assistant_rail.dart`:

(a) Add the import:

```dart
import 'gm_chat_screen.dart';
```

(b) Replace the whole `_ask` method with:

```dart
  Future<void> _ask() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    _controller.clear();
    await showGmChat(context, initialMessage: q);
  }
```

(c) Remove the now-unused `_busy` and `_error` state fields and their references in `build` (the inline error `Text` and the send-button busy spinner). Run `flutter analyze lib/features/assistant_rail.dart` and remove whatever it flags as unused (`_busy`, `_error`, and any `setState` that only touched them). The send button should call `_ask` and otherwise be always-enabled when `aiReady`.

(The single-shot `service.askGm(...)` call, the `recallLines`/seed construction, and the `addResult('Ask the GM', ...)` are all removed from the rail — `askGm`/`buildAskGmPrompt` stay in the engine, now app-unused.)

- [ ] **Step 4: Run analyze + the affected tests + full suite**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test test/assistant_rail_test.dart test/gm_chat_screen_test.dart` → expect PASS.
Run: `flutter test` → expect All tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/features/assistant_rail.dart test/assistant_rail_test.dart
git commit -m "feat(ai): assistant-rail Ask-GM box opens the multi-turn chat

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Doc sync — CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (the AI-expansion #1 note appended in #143)

- [ ] **Step 1: Append the #2 note**

In `CLAUDE.md`, find the "AI expansion #1 (richer context)" paragraph (ends with "multi-turn GM chat (#2) + new affordances (#3) ride on it."). Immediately after it, append:

```
  **AI expansion #2 (multi-turn GM chat):** a stateless transcript-in-prompt
  conversation — `gmChat(GmChatSeed)` renders the #1 grounding + the last
  `kGmChatHistoryTurns` (8) turns + a trailing `GM:` via the fresh-chat
  `_generate` (the runtime keeps no session). Model in `lib/engine/gm_chat.dart`
  (`ChatTurn`/`GmChatState`); persisted per campaign by `GmChatNotifier`
  (`juice.gmchat.v1`, in `sessionScopedKeys` → exported). The
  `lib/features/gm_chat_screen.dart` bubble thread (`showGmChat`) is opened from
  the assistant rail's Ask-GM box; nothing auto-logs — a per-GM-message Save
  writes a `gm-chat` journal entry. The single-shot `askGm` seam is retained but
  app-unused. See
  `docs/superpowers/specs/2026-06-24-multi-turn-gm-chat-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note multi-turn GM chat in CLAUDE.md (AI expansion #2)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 model (`ChatTurn`/`GmChatState`) → Task 1. ✓
- §2 seam (`GmChatSeed`/`buildGmChatPrompt`/`parseGmChatResponse`/consts) → Task 2; interface+impls → Task 3. ✓
- §3 state (`GmChatNotifier` + `sessionScopedKeys`) → Task 4. ✓
- §4 UI (`gm_chat_screen.dart` thread/send/busy/save/clear, `showGmChat`, aiReady gate) → Task 5. ✓
- §5 entry point (rail opens chat) → Task 6. ✓
- Testing (model, prompt, provider, screen widget, rail) → Tasks 1-6. ✓
- Out-of-scope (stateful sessions, streaming, askGm removal) absent. ✓

**Type consistency:**
- `ChatRole`/`ChatTurn`/`GmChatState` (Task 1) used in seam (Task 2), notifier (Task 4), screen (Task 5). ✓
- `GmChatSeed{history,sceneTitle,systemPrimer,activeCharacter,journalContext}` (Task 2) built identically in the screen (Task 5) + faked (Task 3). ✓
- `gmChat(GmChatSeed) -> Future<String>` consistent: interface (3), Gemma (3), fake (3), screen call (5). ✓
- `gmChatProvider` / `appendTurn` / `clear` (Task 4) used in screen (Task 5). ✓
- Keys: `gm-chat-input`/`-send`/`-clear`/`-save-<i>`/`-bubble-<i>` consistent between Task 5 impl + tests. ✓
- `showGmChat(context, {initialMessage})` defined Task 5, called Task 6. ✓

**Placeholder scan:** No TBD/TODO; complete code per step. Task 6(c) (removing unused `_busy`/`_error`) leans on `flutter analyze` — acceptable, it's a hard gate run before the commit, and the exact build references depend on the current rail layout.

**Risk note:** Task 6's rail-test update assumes the existing harness pumps the rail under a Navigator (so `showGmChat` can push). If it doesn't, wrap in `MaterialApp` per the step. The `aiReadyProvider.overrideWith` in Task 5 bypasses the status plumbing so the screen test is hermetic.
