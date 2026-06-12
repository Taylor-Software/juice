# Oracle Interpreter Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On-device LLM interpretation of journal oracle results — engine, service seam, bottom-sheet UI, per-campaign genre/tone, and the web (MediaPipe/WebGPU) path.

**Architecture:** Pure-Dart prompt/parser engine (no plugin import) + an `InterpreterService` seam whose flutter_gemma implementation pins a per-platform model (web: Gemma3 1B int4 `-web.task`; mobile: Qwen3 0.6B int4 `.litertlm`). Journal result entries get an Interpret menu action that opens an interpretation sheet; an accepted reading appends to the entry. All widget tests run against a fake service — CI never touches native code.

**Tech Stack:** Flutter, flutter_riverpod, shared_preferences, flutter_gemma ^0.16.5 (NEW dependency — user-approved rail change).

**Spec:** `docs/superpowers/specs/2026-06-11-oracle-interpreter-design.md` (read it first; "Verified facts" + "Spike results" sections explain every constraint below).

**Branch:** `feat/oracle-interpreter` off `main`.

Existing patterns to follow (read these before coding):
- `lib/state/providers.dart` — `_PersistedList`/`CrawlNotifier` patterns, `sessionScopedKeys`, the `_ready` house rule (every mutator awaits `state.valueOrNull ?? await future`).
- `lib/features/journal_screen.dart` — entry rendering + `_onAction` menu.
- `lib/state/campaign_io.dart` — per-key validation in `parseCampaign`.
- `test/map_screen_test.dart` — widget-test bootstrap pattern (mock SharedPreferences, ProviderScope).

Hard rules:
- `flutter analyze` must stay at exactly 1 issue (pre-existing info at `lib/engine/models.dart:2`). No new infos/warnings.
- All existing 213 tests stay green.
- `lib/engine/oracle_interpreter.dart` must NOT import flutter_gemma, flutter, or riverpod (pure Dart; `dart:convert` only).
- Nothing in the test suite may construct `GemmaInterpreterService`.

---

### Task 1: Engine — seed, prompt, tolerant parser

**Files:**
- Create: `lib/engine/oracle_interpreter.dart`
- Test: `test/oracle_interpreter_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';

void main() {
  group('buildOraclePrompt', () {
    test('carries result, genre, tone, scene', () {
      const seed = OracleSeed(
        resultText: 'Fate Check (Likely) — Yes, and…',
        genre: 'grimdark fantasy',
        tone: 'tense',
        sceneContext: 'Scene: The burned mill (Chaos 5)',
      );
      final p = buildOraclePrompt(seed);
      expect(p, contains('genre: grimdark fantasy'));
      expect(p, contains('tone: tense'));
      expect(p, contains('result: Fate Check (Likely) — Yes, and…'));
      expect(p, contains('scene: Scene: The burned mill (Chaos 5)'));
      expect(p, endsWith('OUTPUT:'));
    });

    test('empty fields become explicit placeholders', () {
      const seed = OracleSeed(resultText: 'Story: Betrayal / Ally');
      final p = buildOraclePrompt(seed);
      expect(p, contains('genre: (unspecified)'));
      expect(p, contains('tone: (unspecified)'));
      expect(p, contains('scene: (none given)'));
    });
  });

  group('parseInterpretations', () {
    const clean =
        '{"interpretations":[{"lens":"literal","reading":"A"},{"lens":"symbolic","reading":"B"},'
        '{"lens":"complication","reading":"C"},{"lens":"foreshadow","reading":"D"}]}';

    test('clean JSON -> four cards in order', () {
      final cards = parseInterpretations(clean);
      expect(cards.map((c) => c.lens).toList(), kLenses);
      expect(cards.map((c) => c.reading).toList(), ['A', 'B', 'C', 'D']);
    });

    test('fenced JSON parses', () {
      expect(parseInterpretations('```json\n$clean\n```'), hasLength(4));
    });

    test('think tags are stripped before parsing', () {
      final cards = parseInterpretations(
          '<think>\nthe player wants…\n</think>\n$clean');
      expect(cards, hasLength(4));
      expect(cards.first.reading, 'A');
    });

    test('prose around the JSON object is ignored', () {
      expect(parseInterpretations('Here you go!\n$clean\nEnjoy.'), hasLength(4));
    });

    test('entries missing a reading are dropped; empty lens defaults', () {
      final cards = parseInterpretations(
          '{"interpretations":[{"lens":"literal","reading":""},'
          '{"reading":"only one"}]}');
      expect(cards, hasLength(1));
      expect(cards.single.lens, 'reading');
      expect(cards.single.reading, 'only one');
    });

    test('garbage falls back to a single raw card', () {
      final cards = parseInterpretations('not json at all');
      expect(cards.single.lens, 'raw');
      expect(cards.single.reading, 'not json at all');
    });

    test('empty/whitespace output -> no cards', () {
      expect(parseInterpretations('   \n'), isEmpty);
    });

    test('malformed JSON inside braces falls back to raw', () {
      final cards = parseInterpretations('{"interpretations": [oops');
      expect(cards.single.lens, 'raw');
    });
  });

  test('system instruction states the contract', () {
    expect(oracleSystemInstruction, contains('"interpretations"'));
    for (final lens in kLenses) {
      expect(oracleSystemInstruction, contains(lens));
    }
    expect(oracleSystemInstruction, contains('ONLY a JSON object'));
  });
}
```

- [ ] **Step 2: Run, verify failure**

`flutter test test/oracle_interpreter_test.dart` → FAIL (file missing).

- [ ] **Step 3: Implement**

```dart
/// On-device LLM oracle interpretation: prompt schema + tolerant parser.
/// Pure Dart — no flutter_gemma, no Flutter. The service layer
/// (lib/state/interpreter.dart) owns the model; this file owns the words.
///
/// Adapted from a user-provided design (see spec). Key change: the seed is
/// the journal entry's already-formatted result text — Juice/Mythic tables
/// have no per-word meanings to feed.
library;

import 'dart:convert';

/// Everything the model needs to interpret one logged oracle result.
class OracleSeed {
  const OracleSeed({
    required this.resultText,
    this.genre = '',
    this.tone = '',
    this.sceneContext = '',
  });

  /// The journal entry's title + body, verbatim.
  final String resultText;

  /// Per-campaign settings, e.g. 'grimdark fantasy' / 'tense and dangerous'.
  final String genre;
  final String tone;

  /// Latest scene entry's title (+ chaos factor), or empty. Future RAG hook.
  final String sceneContext;
}

/// A single interpretation card; [lens] is the register it was written in.
class OracleInterpretation {
  const OracleInterpretation({required this.lens, required this.reading});
  final String lens;
  final String reading;
}

/// Distinct registers, ordered safest -> most surprising. Naming the lenses
/// is what forces a small model to diversify instead of rephrasing.
const List<String> kLenses = <String>[
  'literal',
  'symbolic',
  'complication',
  'foreshadow',
];

/// Role + rules + JSON shape + two compact few-shot examples. Examples move
/// small-model quality more than rules do. Kept tight: the web model's
/// context may be as small as 1280 tokens total.
const String oracleSystemInstruction = '''
You interpret oracle results for a solo tabletop RPG player journaling their
own story. You offer possibilities; the player decides what is true. Never
resolve outcomes, never say what the player's character does or feels.

For each result output EXACTLY four interpretations, one per lens, in order:
- literal: the plainest, most direct reading of the result.
- symbolic: a metaphorical or atmospheric reading — NOT literally the result.
- complication: a "yes, but" — accepts the result and adds a cost or twist.
- foreshadow: something quiet that hints at trouble or change LATER, not now.

Rules:
- Each reading is 1-2 short sentences. Concrete and evocative. No "perhaps".
- The four readings must be genuinely different ideas, not rephrasings.
- Honor the stated genre and tone in word choice and imagery.
- Use the scene context if given; otherwise invent freely but stay in tone.
- Output ONLY a JSON object. No preamble, no markdown fences, no commentary.

JSON shape:
{"interpretations":[{"lens":"literal","reading":"..."},{"lens":"symbolic","reading":"..."},{"lens":"complication","reading":"..."},{"lens":"foreshadow","reading":"..."}]}

Example 1
INPUT:
genre: grimdark fantasy
tone: tense and dangerous
result: Fate Check (Likely) — No, but…
scene: Scene: Begging entry at the city gate after dark (Chaos 6)
OUTPUT:
{"interpretations":[{"lens":"literal","reading":"The gate stays shut, but a postern door creaks open a hand's width — a bribe might widen it."},{"lens":"symbolic","reading":"The city turns its iron back on you; only its rats and refuse acknowledge your arrival."},{"lens":"complication","reading":"A guard waves you toward the smugglers' stair instead, and now he knows your face."},{"lens":"foreshadow","reading":"Above the gate, someone snuffs a lantern the moment you look up."}]}

Example 2
INPUT:
genre: cozy folk mystery
tone: warm but uneasy
result: Story: Discover / Object
scene: (none given)
OUTPUT:
{"interpretations":[{"lens":"literal","reading":"Behind the loose hearthstone sits a rusted tin box, something shifting inside when you lift it."},{"lens":"symbolic","reading":"A single mismatched teacup at the back of the cupboard — kept for someone who never came back."},{"lens":"complication","reading":"You find the cottage deed, and a second name on it you have never heard before."},{"lens":"foreshadow","reading":"A pressed flower falls from a book — a kind that only grows two valleys over."}]}
''';

/// Builds the per-roll user message from a seed.
String buildOraclePrompt(OracleSeed seed) {
  String orElse(String v, String fallback) =>
      v.trim().isEmpty ? fallback : v.trim();
  return 'INPUT:\n'
      'genre: ${orElse(seed.genre, '(unspecified)')}\n'
      'tone: ${orElse(seed.tone, '(unspecified)')}\n'
      'result: ${seed.resultText.trim()}\n'
      'scene: ${orElse(seed.sceneContext, '(none given)')}\n'
      'OUTPUT:';
}

/// Parses raw model output. Strips <think> spans and code fences, isolates
/// the outermost JSON object, validates shape. On any failure returns the
/// raw text as a single 'raw' card so the player still sees something.
/// Never throws.
List<OracleInterpretation> parseInterpretations(String raw) {
  final cleaned = _isolateJson(raw);
  if (cleaned != null) {
    try {
      final decoded = jsonDecode(cleaned);
      final list = (decoded is Map) ? decoded['interpretations'] : null;
      if (list is List) {
        final out = <OracleInterpretation>[];
        for (final item in list) {
          if (item is Map) {
            final lens = item['lens']?.toString().trim() ?? '';
            final reading = item['reading']?.toString().trim() ?? '';
            if (reading.isNotEmpty) {
              out.add(OracleInterpretation(
                lens: lens.isEmpty ? 'reading' : lens,
                reading: reading,
              ));
            }
          }
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {
      // fall through to raw fallback
    }
  }
  final fallback = _stripThink(raw).trim();
  return fallback.isEmpty
      ? const <OracleInterpretation>[]
      : <OracleInterpretation>[
          OracleInterpretation(lens: 'raw', reading: fallback),
        ];
}

String _stripThink(String s) =>
    s.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');

String? _isolateJson(String raw) {
  final s = _stripThink(raw)
      .replaceAll('```json', '')
      .replaceAll('```', '')
      .trim();
  final start = s.indexOf('{');
  final end = s.lastIndexOf('}');
  if (start == -1 || end == -1 || end <= start) return null;
  return s.substring(start, end + 1);
}

/// Debug-eval seeds (see spec "Quality bar"). Used by the debug-only
/// runEval in lib/state/interpreter.dart and by live verification.
const List<OracleSeed> kEvalSeeds = <OracleSeed>[
  OracleSeed(
    resultText: 'Fate Check (Unlikely) — Yes…',
    genre: 'grimdark fantasy',
    tone: 'tense and dangerous',
    sceneContext: 'Scene: Alone on a forest road at dusk (Chaos 5)',
  ),
  OracleSeed(
    resultText: 'Story: Help / Stranger',
    genre: 'cozy folk mystery',
    tone: 'warm but uneasy',
    sceneContext: 'Scene: Stuck in the rain outside a shuttered inn',
  ),
  OracleSeed(
    resultText: 'Wilderness Travel — Swamp 4 Ruins, Lost',
    genre: 'hard sci-fi',
    tone: 'cold and isolating',
  ),
];
```

- [ ] **Step 4: Run, verify pass**

`flutter test test/oracle_interpreter_test.dart` → all PASS.

- [ ] **Step 5: Verify purity + analyze + commit**

`grep -E "import 'package:(flutter|flutter_gemma|flutter_riverpod)" lib/engine/oracle_interpreter.dart` → no output.
`flutter analyze --no-fatal-infos` → 1 pre-existing info only.

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat: oracle interpreter engine — prompt schema + tolerant parser"
```

---

### Task 2: Per-campaign settings (genre/tone) + campaign-file support

**Files:**
- Modify: `lib/engine/models.dart` (append at end)
- Modify: `lib/state/providers.dart` (`sessionScopedKeys` at line ~458; new notifier after `MapNotifier`)
- Modify: `lib/state/campaign_io.dart` (validation branch after the `juice.map.v1` branch, line ~87)
- Test: `test/settings_test.dart`; Modify: `test/campaign_io_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CampaignSettings json round-trip + defaults', () {
    const s = CampaignSettings(genre: 'grimdark', tone: 'tense');
    final back = CampaignSettings.fromJson(s.toJson());
    expect(back.genre, 'grimdark');
    expect(back.tone, 'tense');
    expect(const CampaignSettings().genre, '');
    expect(CampaignSettings.fromJson(const {}).tone, '');
  });

  test('settings persist per session and reload', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    await c1.read(settingsProvider.future);
    await c1
        .read(settingsProvider.notifier)
        .save(const CampaignSettings(genre: 'noir', tone: 'wry'));

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final loaded = await c2.read(settingsProvider.future);
    expect(loaded.genre, 'noir');
    expect(loaded.tone, 'wry');
  });

  test('save before build completes does not throw', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // No await of the future first: the _ready house rule.
    await c
        .read(settingsProvider.notifier)
        .save(const CampaignSettings(genre: 'g', tone: 't'));
    expect((await c.read(settingsProvider.future)).genre, 'g');
  });
}
```

Append to `test/campaign_io_test.dart` (match its existing style; read it first):

```dart
  test('campaign export/import carries juice.settings.v1', () {
    final encoded = encodeCampaign(
      name: 'S',
      savedAt: DateTime(2026, 6, 11),
      rawByKey: {
        'juice.settings.v1': '{"genre":"grimdark","tone":"tense"}',
      },
    );
    final parsed = parseCampaign(encoded);
    expect(parsed.rawByKey['juice.settings.v1'], contains('grimdark'));
  });

  test('malformed settings section rejects the file', () {
    final encoded = encodeCampaign(
      name: 'S',
      savedAt: DateTime(2026, 6, 11),
      rawByKey: {'juice.settings.v1': '[1,2]'},
    );
    expect(() => parseCampaign(encoded), throwsFormatException);
  });
```

- [ ] **Step 2: Run, verify failure**

`flutter test test/settings_test.dart test/campaign_io_test.dart` → FAIL (CampaignSettings undefined).

- [ ] **Step 3: Implement**

Append to `lib/engine/models.dart`:

```dart
// -- Campaign settings (genre/tone for the oracle interpreter) ---------------
class CampaignSettings {
  const CampaignSettings({this.genre = '', this.tone = ''});
  final String genre;
  final String tone;

  CampaignSettings copyWith({String? genre, String? tone}) =>
      CampaignSettings(genre: genre ?? this.genre, tone: tone ?? this.tone);

  factory CampaignSettings.fromJson(Map<String, dynamic> json) =>
      CampaignSettings(
        genre: json['genre'] as String? ?? '',
        tone: json['tone'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'genre': genre, 'tone': tone};
}
```

In `lib/state/providers.dart`, add `'juice.settings.v1',` to `sessionScopedKeys` (after `'juice.map.v1',`), and add after the map section (mirror `CrawlNotifier` exactly):

```dart
// -- Campaign settings (genre/tone for the interpreter) ----------------------
class SettingsNotifier extends AsyncNotifier<CampaignSettings> {
  static const _baseKey = 'juice.settings.v1';

  late String _scopedKey;

  @override
  Future<CampaignSettings> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const CampaignSettings();
    return CampaignSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(CampaignSettings s) async {
    // Await build() so an early save cannot throw on _scopedKey.
    state.valueOrNull ?? await future;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(s.toJson()));
    state = AsyncData(s);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, CampaignSettings>(
        SettingsNotifier.new);
```

In `lib/state/campaign_io.dart`, add a branch after the `juice.map.v1` one:

```dart
      } else if (key == 'juice.settings.v1') {
        CampaignSettings.fromJson(value as Map<String, dynamic>);
```

- [ ] **Step 4: Run, verify pass**

`flutter test test/settings_test.dart test/campaign_io_test.dart` → PASS.
`flutter test` → full suite green. `flutter analyze --no-fatal-infos` → 1 info.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart lib/state/providers.dart lib/state/campaign_io.dart test/settings_test.dart test/campaign_io_test.dart
git commit -m "feat: per-campaign genre/tone settings (juice.settings.v1, campaign v2 additive)"
```

---

### Task 3: Service seam + flutter_gemma implementation + providers

**Files:**
- Modify: `pubspec.yaml` (add `flutter_gemma: ^0.16.5` after `flutter_riverpod`)
- Modify: `lib/main.dart`
- Create: `lib/state/interpreter.dart` (seam + providers + debug eval)
- Create: `lib/state/interpreter_gemma.dart` (flutter_gemma impl)
- Create: `lib/shared/webgpu_check_stub.dart`, `lib/shared/webgpu_check_web.dart`
- Test: `test/interpreter_test.dart`; Create: `test/fake_interpreter.dart`

- [ ] **Step 1: Add dependency + initialize**

`pubspec.yaml` dependencies block:

```yaml
  flutter_gemma: ^0.16.5
```

`lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  runApp(const ProviderScope(child: JuiceApp()));
}
```

Run `flutter pub get`, then `flutter test` — the full suite must STILL pass
(tests build their own widgets and never run `main()`; if anything fails,
stop and report rather than papering over).

- [ ] **Step 2: Write the failing tests**

`test/fake_interpreter.dart` (shared by Tasks 4-5):

```dart
import 'package:flutter/foundation.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/state/interpreter.dart';

/// Scriptable fake. Tests drive [status] directly and queue results.
class FakeInterpreterService implements InterpreterService {
  FakeInterpreterService({InterpreterStatus? initial})
      : statusNotifier =
            ValueNotifier(initial ?? const InterpreterStatus(InterpreterPhase.needsDownload));

  final ValueNotifier<InterpreterStatus> statusNotifier;
  final List<List<OracleInterpretation>> queuedResults = [];
  Object? interpretError;
  int refreshCalls = 0;
  int warmUpCalls = 0;
  int interpretCalls = 0;
  int disposeCalls = 0;

  @override
  ValueListenable<InterpreterStatus> get status => statusNotifier;

  @override
  String get downloadLabel => '~123 MB';

  @override
  Future<void> refresh() async => refreshCalls++;

  @override
  Future<void> warmUp() async {
    warmUpCalls++;
    statusNotifier.value = const InterpreterStatus(InterpreterPhase.ready);
  }

  @override
  Future<List<OracleInterpretation>> interpret(OracleSeed seed) async {
    interpretCalls++;
    if (interpretError != null) throw interpretError!;
    if (queuedResults.isEmpty) {
      return const [OracleInterpretation(lens: 'literal', reading: 'fallback')];
    }
    return queuedResults.removeAt(0);
  }

  @override
  Future<void> dispose() async => disposeCalls++;
}
```

`test/interpreter_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/state/interpreter.dart';

import 'fake_interpreter.dart';

void main() {
  test('InterpreterStatus equality + progress default', () {
    const a = InterpreterStatus(InterpreterPhase.installing, progress: 40);
    expect(a.phase, InterpreterPhase.installing);
    expect(a.progress, 40);
    expect(const InterpreterStatus(InterpreterPhase.ready).progress, 0);
    expect(const InterpreterStatus(InterpreterPhase.error, message: 'x').message,
        'x');
  });

  test('interpreterServiceProvider is overridable with the fake', () {
    final fake = FakeInterpreterService();
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    expect(c.read(interpreterServiceProvider), same(fake));
  });
}
```

Run: `flutter test test/interpreter_test.dart` → FAIL (files missing).

- [ ] **Step 3: Implement the seam**

`lib/shared/webgpu_check_stub.dart`:

```dart
/// Non-web platforms: WebGPU is irrelevant; native backends exist.
bool get hasWebGpu => true;
```

`lib/shared/webgpu_check_web.dart`:

```dart
import 'dart:js_interop';

@JS('navigator.gpu')
external JSAny? get _navigatorGpu;

/// True when the browser exposes WebGPU (required by MediaPipe GenAI).
bool get hasWebGpu => _navigatorGpu != null;
```

`lib/state/interpreter.dart`:

```dart
/// Interpreter service seam. UI and tests depend on this file only; the
/// flutter_gemma implementation lives in interpreter_gemma.dart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/oracle_interpreter.dart';
import 'interpreter_gemma.dart';

enum InterpreterPhase {
  /// Model not on disk; user consent (download) required.
  needsDownload,

  /// Downloading; [InterpreterStatus.progress] is 0-100.
  installing,

  /// Model on disk, loading into memory.
  loading,

  /// Loaded; interpret() may be called.
  ready,

  /// This platform cannot run the model (e.g. no WebGPU). Hide the feature.
  unsupported,

  /// warmUp failed; [InterpreterStatus.message] says why. Retry allowed.
  error,
}

@immutable
class InterpreterStatus {
  const InterpreterStatus(this.phase, {this.progress = 0, this.message = ''});
  final InterpreterPhase phase;
  final int progress;
  final String message;
}

abstract class InterpreterService {
  /// Current lifecycle phase; the sheet rebuilds off this.
  ValueListenable<InterpreterStatus> get status;

  /// Human download size, e.g. '~670 MB' — shown in the consent step.
  String get downloadLabel;

  /// Resolve needsDownload vs (auto-)warmUp: if the model is already on
  /// disk, proceeds to load without further consent.
  Future<void> refresh();

  /// User-consented install + load. Safe to call repeatedly.
  Future<void> warmUp();

  /// One roll = one fresh chat. Requires phase == ready.
  Future<List<OracleInterpretation>> interpret(OracleSeed seed);

  /// Free the native session (model stays on disk). Next use reloads.
  Future<void> dispose();
}

/// App-global service. Overridden with a fake in every widget test —
/// the real implementation touches platform channels.
final interpreterServiceProvider = Provider<InterpreterService>((ref) {
  final service = GemmaInterpreterService();
  ref.onDispose(service.dispose);
  return service;
});

/// Debug-only eval over the engine's seed set (spec "Quality bar").
/// Call from a debug build; prints to console.
Future<void> runInterpreterEval(InterpreterService service) async {
  await service.warmUp();
  for (final seed in kEvalSeeds) {
    final cards = await service.interpret(seed);
    debugPrint('-- ${seed.genre} | ${seed.resultText} --');
    for (final c in cards) {
      debugPrint('  [${c.lens}] ${c.reading}');
    }
  }
}
```

`lib/state/interpreter_gemma.dart`:

```dart
/// flutter_gemma-backed interpreter. Never constructed in tests.
///
/// Per-platform model (see spec "Spike results" for why they differ):
/// - web: Gemma3 1B int4 `-web.task` via MediaPipe/WebGPU. NOTE: the
///   pinned URL is a third-party mirror for DEVELOPMENT ONLY — the
///   release merge-gate is swapping it to the user's own HF mirror.
/// - mobile: Qwen3 0.6B int4 `.litertlm` from the official
///   litert-community repo.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../engine/oracle_interpreter.dart';
import '../shared/webgpu_check_stub.dart'
    if (dart.library.js_interop) '../shared/webgpu_check_web.dart';
import 'interpreter.dart';

class _ModelSpec {
  const _ModelSpec({
    required this.url,
    required this.filename,
    required this.modelType,
    required this.fileType,
    required this.approxMb,
  });
  final String url;
  final String filename;
  final ModelType modelType;
  final ModelFileType fileType;
  final int approxMb;
}

// DEV PIN — swap to the user's own HF mirror before enabling web in a
// release (spec: "Weights provenance").
const _webSpec = _ModelSpec(
  url:
      'https://huggingface.co/darkB/gemma3-1b-it-int4-web-litert/resolve/main/gemma3-1b-it-int4-web.task',
  filename: 'gemma3-1b-it-int4-web.task',
  modelType: ModelType.gemmaIt,
  fileType: ModelFileType.task,
  approxMb: 670,
);

const _mobileSpec = _ModelSpec(
  url:
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm',
  filename: 'qwen3_0_6b_mixed_int4.litertlm',
  modelType: ModelType.qwen3,
  fileType: ModelFileType.litertlm,
  approxMb: 480,
);

class GemmaInterpreterService implements InterpreterService {
  GemmaInterpreterService() {
    if (kIsWeb && !hasWebGpu) {
      _status.value = const InterpreterStatus(InterpreterPhase.unsupported,
          message: 'This browser has no WebGPU support.');
    }
  }

  final _spec = kIsWeb ? _webSpec : _mobileSpec;
  final _status =
      ValueNotifier(const InterpreterStatus(InterpreterPhase.needsDownload));
  InferenceModel? _model;

  @override
  ValueListenable<InterpreterStatus> get status => _status;

  @override
  String get downloadLabel => '~${_spec.approxMb} MB';

  bool get _unsupported =>
      _status.value.phase == InterpreterPhase.unsupported;

  @override
  Future<void> refresh() async {
    if (_unsupported || _model != null) return;
    try {
      if (await FlutterGemma.isModelInstalled(_spec.filename)) {
        await warmUp(); // already consented (it's on disk) — just load
      } else {
        _status.value =
            const InterpreterStatus(InterpreterPhase.needsDownload);
      }
    } catch (e) {
      _status.value =
          InterpreterStatus(InterpreterPhase.error, message: '$e');
    }
  }

  @override
  Future<void> warmUp() async {
    if (_unsupported || _model != null) return;
    try {
      if (!await FlutterGemma.isModelInstalled(_spec.filename)) {
        _status.value =
            const InterpreterStatus(InterpreterPhase.installing);
        await FlutterGemma.installModel(
                modelType: _spec.modelType, fileType: _spec.fileType)
            .fromNetwork(_spec.url)
            .withProgress((p) => _status.value =
                InterpreterStatus(InterpreterPhase.installing, progress: p))
            .install();
      }
      _status.value = const InterpreterStatus(InterpreterPhase.loading);
      _model = await _loadModel();
      _status.value = const InterpreterStatus(InterpreterPhase.ready);
    } catch (e) {
      _status.value =
          InterpreterStatus(InterpreterPhase.error, message: '$e');
    }
  }

  /// Try a roomy context first; some artifacts cap the KV cache (the web
  /// build was only proven at 1280 in the spike).
  Future<InferenceModel> _loadModel() async {
    Object? lastError;
    for (final maxTokens in const [2048, 1280]) {
      for (final backend in [
        PreferredBackend.gpu,
        if (!kIsWeb) PreferredBackend.cpu, // web is GPU-only
      ]) {
        try {
          return await FlutterGemma.getActiveModel(
              maxTokens: maxTokens, preferredBackend: backend);
        } catch (e) {
          lastError = e;
        }
      }
    }
    throw StateError('Model load failed: $lastError');
  }

  @override
  Future<List<OracleInterpretation>> interpret(OracleSeed seed) async {
    final model = _model;
    if (model == null) throw StateError('Interpreter not ready');
    final chat = await model.createChat(
      temperature: 1.0, // variety is the product; defaults (topK 1) kill it
      topK: 64,
      topP: 0.95,
      isThinking: false,
      modelType: _spec.modelType,
      systemInstruction: oracleSystemInstruction,
    );
    await chat.addQueryChunk(
        Message.text(text: buildOraclePrompt(seed), isUser: true));
    final buffer = StringBuffer();
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) buffer.write(r.token);
    }
    return parseInterpretations(buffer.toString());
  }

  @override
  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    if (!_unsupported) {
      _status.value = const InterpreterStatus(InterpreterPhase.needsDownload);
    }
  }
}
```

- [ ] **Step 4: Run, verify pass**

`flutter test test/interpreter_test.dart` → PASS.
`flutter test` → full suite green (proves adding the dep + provider broke nothing).
`flutter analyze --no-fatal-infos` → 1 info.
`flutter build web` → succeeds (proves the conditional import resolves on web).

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart lib/state/interpreter.dart lib/state/interpreter_gemma.dart lib/shared/webgpu_check_stub.dart lib/shared/webgpu_check_web.dart test/interpreter_test.dart test/fake_interpreter.dart
git commit -m "feat: interpreter service seam + flutter_gemma implementation (per-platform models)"
```

(If `flutter pub get` touched platform registrant files — e.g. `linux/flutter/generated_plugins.cmake`, ios/macos xcconfig — include them; they are generated and expected.)

---

### Task 4: Interpretation sheet UI

**Files:**
- Create: `lib/features/oracle_interpretation_sheet.dart`
- Test: `test/oracle_interpretation_sheet_test.dart`

The sheet is adapted from the user-provided widget (spec "Origin"): keep its
card/chip/dismiss structure and Theme-driven styling; replace its
loading/error model with the service's status phases, and add the consent
step, genre/tone header editing, and the freeze warning.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/features/oracle_interpretation_sheet.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

void main() {
  const seed = OracleSeed(resultText: 'Fate Check (Likely) — Yes…');

  Future<FakeInterpreterService> pump(WidgetTester tester,
      {InterpreterStatus? initial,
      void Function(OracleInterpretation)? onAccept}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final fake = FakeInterpreterService(initial: initial);
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Scaffold(
          body: OracleInterpretationSheet(
            seed: seed,
            onAccept: onAccept ?? (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('needsDownload shows consent with size; download warms up',
      (tester) async {
    final fake = await pump(tester);
    expect(fake.refreshCalls, 1);
    expect(find.textContaining('~123 MB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('interp-download')));
    await tester.pumpAndSettle();
    expect(fake.warmUpCalls, 1);
    // warmUp flips the fake to ready -> generation starts.
    expect(fake.interpretCalls, 1);
  });

  testWidgets('installing shows progress', (tester) async {
    await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.installing,
            progress: 42));
    expect(find.textContaining('42%'), findsOneWidget);
  });

  testWidgets('ready generates and renders cards; accept passes the card',
      (tester) async {
    OracleInterpretation? accepted;
    final fake = await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.ready),
        onAccept: (c) => accepted = c);
    fake.queuedResults.add(const [
      OracleInterpretation(lens: 'literal', reading: 'Wolves at the gate'),
      OracleInterpretation(lens: 'symbolic', reading: 'The road closes'),
    ]);
    // pump() already triggered generation with the fallback card; regenerate
    // to consume the queued pair.
    await tester.tap(find.byKey(const Key('interp-regenerate')));
    await tester.pumpAndSettle();
    expect(find.text('Wolves at the gate'), findsOneWidget);
    expect(find.text('LITERAL'), findsOneWidget);
    await tester.tap(find.byKey(const Key('interp-accept-0')));
    expect(accepted?.reading, 'Wolves at the gate');
  });

  testWidgets('swipe dismisses a card; all dismissed offers reroll',
      (tester) async {
    final fake = await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.ready));
    expect(fake.interpretCalls, 1);
    // One fallback card rendered. Swipe it away.
    await tester.drag(
        find.byKey(const Key('interp-card-0')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interp-card-0')), findsNothing);
    expect(find.byKey(const Key('interp-reroll')), findsOneWidget);
    await tester.tap(find.byKey(const Key('interp-reroll')));
    await tester.pumpAndSettle();
    expect(fake.interpretCalls, 2);
  });

  testWidgets('interpret error shows retry', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    fake.interpretError = StateError('boom');
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Scaffold(
            body: OracleInterpretationSheet(seed: seed, onAccept: (_) {})),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interp-retry')), findsOneWidget);
    fake.interpretError = null;
    await tester.tap(find.byKey(const Key('interp-retry')));
    await tester.pumpAndSettle();
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('genre/tone editable from header and persisted',
      (tester) async {
    await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.ready));
    await tester.tap(find.byKey(const Key('interp-tone-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('interp-genre-field')), 'grimdark');
    await tester.enterText(
        find.byKey(const Key('interp-tone-field')), 'tense');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('grimdark'), findsOneWidget);
    final el = tester.element(find.byType(OracleInterpretationSheet));
    final container = ProviderScope.containerOf(el);
    final s = await container.read(settingsProvider.future);
    expect(s.genre, 'grimdark');
    expect(s.tone, 'tense');
  });

  testWidgets('unsupported phase explains itself', (tester) async {
    await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.unsupported,
            message: 'This browser has no WebGPU support.'));
    expect(find.textContaining('WebGPU'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, verify failure**

`flutter test test/oracle_interpretation_sheet_test.dart` → FAIL.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../state/interpreter.dart';
import '../state/providers.dart';

/// Bottom sheet that turns one logged oracle result into lens cards.
/// The host passes the seed (entry text + scene context) and receives the
/// accepted card; genre/tone are read from and saved to settingsProvider
/// here so the seed the user sees is the seed the model gets.
class OracleInterpretationSheet extends ConsumerStatefulWidget {
  const OracleInterpretationSheet({
    super.key,
    required this.seed,
    required this.onAccept,
  });

  /// genre/tone fields of this seed are ignored — the sheet injects the
  /// campaign settings at interpret time.
  final OracleSeed seed;
  final ValueChanged<OracleInterpretation> onAccept;

  @override
  ConsumerState<OracleInterpretationSheet> createState() =>
      _OracleInterpretationSheetState();
}

class _OracleInterpretationSheetState
    extends ConsumerState<OracleInterpretationSheet> {
  List<OracleInterpretation>? _cards;
  final Set<int> _dismissed = <int>{};
  bool _generating = false;
  String? _generateError;

  InterpreterService get _service => ref.read(interpreterServiceProvider);

  @override
  void initState() {
    super.initState();
    _service.status.addListener(_onStatus);
    _service.refresh();
    _onStatus();
  }

  @override
  void dispose() {
    _service.status.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    if (!mounted) return;
    setState(() {});
    if (_service.status.value.phase == InterpreterPhase.ready &&
        _cards == null &&
        !_generating) {
      _generate();
    }
  }

  Future<void> _generate() async {
    final settings = await ref.read(settingsProvider.future);
    if (!mounted) return;
    setState(() {
      _generating = true;
      _generateError = null;
      _cards = null;
      _dismissed.clear();
    });
    try {
      final cards = await _service.interpret(OracleSeed(
        resultText: widget.seed.resultText,
        genre: settings.genre,
        tone: settings.tone,
        sceneContext: widget.seed.sceneContext,
      ));
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generateError = '$e';
        _generating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const CampaignSettings();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, settings),
            const SizedBox(height: 12),
            Flexible(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, CampaignSettings settings) {
    final theme = Theme.of(context);
    final vibe = [settings.genre, settings.tone]
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(widget.seed.resultText,
            style: theme.textTheme.titleMedium,
            maxLines: 3,
            overflow: TextOverflow.ellipsis),
        Row(
          children: [
            Expanded(
              child: Text(
                vibe.isEmpty ? 'Set a genre and tone…' : vibe,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              key: const Key('interp-tone-edit'),
              icon: const Icon(Icons.tune, size: 18),
              tooltip: 'Genre & tone',
              onPressed: () => _editSettings(settings),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editSettings(CampaignSettings current) async {
    final result = await showDialog<CampaignSettings>(
      context: context,
      builder: (_) => _SettingsDialog(current: current),
    );
    if (result == null) return;
    await ref.read(settingsProvider.notifier).save(result);
  }

  Widget _body(BuildContext context) {
    final status = _service.status.value;
    switch (status.phase) {
      case InterpreterPhase.unsupported:
        return _Note(
            icon: Icons.desktop_access_disabled,
            title: 'Not available here',
            detail: status.message);
      case InterpreterPhase.needsDownload:
        return _Consent(
            sizeLabel: _service.downloadLabel, onDownload: _service.warmUp);
      case InterpreterPhase.installing:
        return _Note(
            icon: Icons.download,
            title: 'Downloading model… ${status.progress}%',
            detail: 'One time only. Stored on this device.',
            progress: status.progress / 100);
      case InterpreterPhase.loading:
        return const _Note(
            icon: Icons.memory,
            title: 'Loading model…',
            detail: 'This can take a minute.',
            spinner: true);
      case InterpreterPhase.error:
        return _Note(
            icon: Icons.error_outline,
            title: 'Could not prepare the interpreter.',
            detail: status.message,
            action: FilledButton.tonal(
                key: const Key('interp-warm-retry'),
                onPressed: _service.warmUp,
                child: const Text('Retry')));
      case InterpreterPhase.ready:
        break;
    }
    if (_generating) {
      return const _Note(
          icon: Icons.auto_awesome,
          title: 'Reading the omens…',
          detail: 'The page may be unresponsive while the model writes.',
          spinner: true);
    }
    if (_generateError != null) {
      return _Note(
          icon: Icons.error_outline,
          title: 'Could not interpret this result.',
          detail: _generateError!,
          action: FilledButton.tonal(
              key: const Key('interp-retry'),
              onPressed: _generate,
              child: const Text('Retry')));
    }
    final cards = _cards ?? const <OracleInterpretation>[];
    final visible = <int>[
      for (var i = 0; i < cards.length; i++)
        if (!_dismissed.contains(i)) i,
    ];
    if (visible.isEmpty) {
      return _Note(
          icon: Icons.style_outlined,
          title: 'Dismissed them all.',
          detail: 'Roll fresh readings?',
          action: FilledButton.tonal(
              key: const Key('interp-reroll'),
              onPressed: _generate,
              child: const Text('Roll new readings')));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: visible.length,
            itemBuilder: (context, idx) {
              final i = visible[idx];
              return Dismissible(
                key: ValueKey('interp-dismiss-$i'),
                direction: DismissDirection.endToStart,
                background: _dismissBackground(context),
                onDismissed: (_) => setState(() => _dismissed.add(i)),
                child: _card(context, i, cards[i]),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Swipe a card away to discard it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            TextButton.icon(
              key: const Key('interp-regenerate'),
              onPressed: _generate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Regenerate'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card(BuildContext context, int index, OracleInterpretation card) {
    final theme = Theme.of(context);
    return Card(
      key: Key('interp-card-$index'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                card.lens.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(card.reading, style: theme.textTheme.bodyLarge),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('interp-accept-$index'),
                onPressed: () => widget.onAccept(card),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Use this'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dismissBackground(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _Consent extends StatelessWidget {
  const _Consent({required this.sizeLabel, required this.onDownload});
  final String sizeLabel;
  final Future<void> Function() onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Interpret rolls with an on-device model',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            'Downloads a $sizeLabel language model once and stores it on '
            'this device. Everything runs locally — nothing you write '
            'leaves this device.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('interp-download'),
            onPressed: onDownload,
            icon: const Icon(Icons.download),
            label: Text('Download model ($sizeLabel)'),
          ),
          const SizedBox(height: 12),
          // Model attribution, alongside the app's other source credits.
          Text(
            'Web: Gemma 3 1B © Google, Gemma license. '
            'Mobile: Qwen3 0.6B © Alibaba, Apache 2.0.',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.title,
    required this.detail,
    this.spinner = false,
    this.progress,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final bool spinner;
  final double? progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            const CircularProgressIndicator()
          else
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(detail,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
          ],
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.current});
  final CampaignSettings current;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _genre = TextEditingController(text: widget.current.genre);
  late final _tone = TextEditingController(text: widget.current.tone);

  @override
  void dispose() {
    _genre.dispose();
    _tone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Genre & tone'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('interp-genre-field'),
            controller: _genre,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Genre', hintText: 'e.g. grimdark fantasy'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('interp-tone-field'),
            controller: _tone,
            decoration: const InputDecoration(
                labelText: 'Tone', hintText: 'e.g. tense and dangerous'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context,
              CampaignSettings(genre: _genre.text.trim(), tone: _tone.text.trim())),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```

Note `CampaignSettings` comes from `../engine/models.dart` via the
`providers.dart` export chain — if the analyzer complains, import
`../engine/models.dart` directly.

- [ ] **Step 4: Run, verify pass**

`flutter test test/oracle_interpretation_sheet_test.dart` → PASS. Full suite + analyze.

- [ ] **Step 5: Commit**

```bash
git add lib/features/oracle_interpretation_sheet.dart test/oracle_interpretation_sheet_test.dart
git commit -m "feat: oracle interpretation sheet (consent/progress/cards, genre+tone editing)"
```

---

### Task 5: Journal wiring + lifecycle + web include

**Files:**
- Modify: `lib/features/journal_screen.dart` (menu at ~line 120, `_onAction` at ~line 268)
- Modify: `lib/shared/home_shell.dart` (lifecycle hook in the State)
- Modify: `web/index.html` (MediaPipe include)
- Test: `test/journal_interpret_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

void main() {
  const journalJson =
      '[{"id":"2","timestamp":"2026-06-11T12:00:00.000","title":"Fate Check (Likely)","body":"Yes, and…","kind":"result"},'
      '{"id":"1","timestamp":"2026-06-11T11:00:00.000","title":"The burned mill","body":"","kind":"scene","chaosFactor":5}]';

  Future<(FakeInterpreterService, ProviderContainer)> pump(
      WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': journalJson,
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: Scaffold(body: JournalScreen())),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    return (fake, container);
  }

  Future<void> openMenuFor(WidgetTester tester, String entryTitle) async {
    final entry = find.ancestor(
        of: find.text(entryTitle), matching: find.byType(Card));
    await tester.tap(find.descendant(
        of: entry, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
  }

  testWidgets('result entries get Interpret; accept appends the reading',
      (tester) async {
    final (fake, container) = await pump(tester);
    fake.queuedResults.add(const [
      OracleInterpretation(lens: 'symbolic', reading: 'The road closes'),
    ]);
    await openMenuFor(tester, 'Fate Check (Likely)');
    await tester.tap(find.text('Interpret…'));
    await tester.pumpAndSettle();
    // Sheet generated one card from the queue; accept it.
    await tester.tap(find.byKey(const Key('interp-accept-0')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull!;
    final entry = entries.firstWhere((e) => e.id == '2');
    expect(entry.body,
        'Yes, and…\n\n— Oracle reading (symbolic): The road closes');
    // Sheet closed after accept.
    expect(find.byKey(const Key('interp-accept-0')), findsNothing);
    // Seed carried the entry text and the latest scene as context.
    expect(fake.lastSeed?.resultText, 'Fate Check (Likely)\nYes, and…');
    expect(fake.lastSeed?.sceneContext, 'Scene: The burned mill (Chaos 5)');
  });

  testWidgets('scene/text entries do not offer Interpret', (tester) async {
    await pump(tester);
    // The scene row's menu:
    final sceneMenu = find.byType(PopupMenuButton<String>).last;
    await tester.tap(sceneMenu);
    await tester.pumpAndSettle();
    expect(find.text('Interpret…'), findsNothing);
  });

  testWidgets('unsupported service hides Interpret on result entries',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': journalJson,
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.unsupported));
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: Scaffold(body: JournalScreen())),
    ));
    await tester.pumpAndSettle();
    await openMenuFor(tester, 'Fate Check (Likely)');
    expect(find.text('Interpret…'), findsNothing);
  });
}
```

Add to `test/fake_interpreter.dart` (field + assignment inside `interpret`):

```dart
  OracleSeed? lastSeed;
  // in interpret(): lastSeed = seed;  (first line)
```

- [ ] **Step 2: Run, verify failure**

`flutter test test/journal_interpret_test.dart` → FAIL.

- [ ] **Step 3: Implement journal wiring**

In `lib/features/journal_screen.dart`:

Imports to add:

```dart
import '../engine/oracle_interpreter.dart';
import '../state/interpreter.dart';
import 'oracle_interpretation_sheet.dart';
```

In `_entry(...)`, replace the fixed `itemBuilder` list so result entries can
offer Interpret (menu stays identical for other kinds):

```dart
    final canInterpret = e.kind == JournalKind.result &&
        ref.read(interpreterServiceProvider).status.value.phase !=
            InterpreterPhase.unsupported;
    final menu = PopupMenuButton<String>(
      onSelected: (action) => _onAction(action, e, threads),
      itemBuilder: (_) => [
        if (canInterpret)
          const PopupMenuItem(value: 'interpret', child: Text('Interpret…')),
        const PopupMenuItem(value: 'link', child: Text('Link to thread…')),
        const PopupMenuItem(value: 'edit', child: Text('Edit note…')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
```

In `_onAction`, add a case:

```dart
      case 'interpret':
        await _interpret(entry);
```

And the handler + seed builder (new methods on `_JournalScreenState`):

```dart
  /// Latest scene entry (storage is newest-first), as model context.
  String _sceneContext() {
    final entries = ref.read(journalProvider).valueOrNull ?? const [];
    for (final e in entries) {
      if (e.kind == JournalKind.scene) {
        final chaos = e.chaosFactor != null ? ' (Chaos ${e.chaosFactor})' : '';
        return 'Scene: ${e.title}$chaos';
      }
    }
    return '';
  }

  Future<void> _interpret(JournalEntry entry) async {
    final seed = OracleSeed(
      resultText: entry.title.isEmpty
          ? entry.body
          : '${entry.title}\n${entry.body}',
      sceneContext: _sceneContext(),
    );
    final accepted = await showModalBottomSheet<OracleInterpretation>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => OracleInterpretationSheet(
        seed: seed,
        onAccept: (card) => Navigator.pop(sheetContext, card),
      ),
    );
    if (accepted == null || !mounted) return;
    await ref.read(journalProvider.notifier).replace(entry.copyWith(
        body:
            '${entry.body}\n\n— Oracle reading (${accepted.lens}): ${accepted.reading}'));
  }
```

- [ ] **Step 4: Lifecycle hook (mobile only) in home_shell**

In `lib/shared/home_shell.dart` State class (add import
`package:flutter/foundation.dart` for `kIsWeb` and
`../state/interpreter.dart`):

```dart
  AppLifecycleListener? _lifecycle;

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
```

(If `home_shell.dart`'s State already has `initState`/`dispose`, merge into
them instead of duplicating.)

- [ ] **Step 5: web/index.html**

Insert after the `<link rel="manifest" href="manifest.json">` line:

```html

  <!-- MediaPipe GenAI inference for the oracle interpreter's .task model
       over WebGPU (flutter_gemma web backend). -->
  <script type="module">
  import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27';
  window.FilesetResolver = FilesetResolver;
  window.LlmInference = LlmInference;
  </script>
```

- [ ] **Step 6: Run, verify pass**

`flutter test test/journal_interpret_test.dart` → PASS.
`flutter test` full suite. `flutter analyze --no-fatal-infos` → 1 info.
`flutter build web` → succeeds.

- [ ] **Step 7: Commit**

```bash
git add lib/features/journal_screen.dart lib/shared/home_shell.dart web/index.html test/journal_interpret_test.dart test/fake_interpreter.dart
git commit -m "feat: Interpret action on journal results; lifecycle disposal; MediaPipe web include"
```

---

### Task 6: Docs sync

**Files:**
- Modify: `CLAUDE.md` (lean-stack bullet)
- Modify: `README.md` (feature paragraph + attribution/licensing section)

- [ ] **Step 1: CLAUDE.md**

Update the lean-stack bullet to read (replacing the current dependency list
sentence; keep the rest of the bullet):

```
- Stack is deliberately lean: `flutter_riverpod` + `shared_preferences` +
  `file_picker` (campaign file export/import) + `flutter_gemma` (on-device
  oracle interpreter; service seam in `lib/state/interpreter.dart`, tests
  always use the fake — never construct `GemmaInterpreterService` in tests).
```

Add a bullet under Project notes:

```
- Interpreter models are pinned in `lib/state/interpreter_gemma.dart`.
  The web URL is a third-party dev mirror; swapping it to the user's own
  HF mirror is a release gate for web (see the oracle-interpreter spec,
  "Weights provenance").
```

- [ ] **Step 2: README.md**

Add to the features area (match surrounding voice):

```
- **Oracle interpreter (on-device AI, optional):** any oracle result in the
  journal can be expanded into four short readings — literal, symbolic,
  complication, foreshadow — by a small language model that runs entirely
  on your device (WebGPU in the browser; arm64 on mobile). One-time model
  download (~670 MB web / ~480 MB mobile) after explicit consent; nothing
  you write leaves your device. The dice stay authoritative — the model
  only suggests, you decide. Set your campaign's genre and tone from the
  sheet to steer the voice. Web uses Gemma 3 1B (Google, Gemma license);
  mobile uses Qwen3 0.6B (Alibaba, Apache 2.0).
```

- [ ] **Step 3: Full gate + commit**

`flutter test` → all green. `flutter analyze --no-fatal-infos` → 1 info.

```bash
git add CLAUDE.md README.md
git commit -m "docs: oracle interpreter feature notes, rail update, model licensing"
```

---

## Verification (controller, after all tasks)

1. `flutter build web` and serve `build/web`; in real Chrome (WebGPU):
   journal → roll something via a tool → entry menu → Interpret… → consent
   shows ~670 MB → download → cards render; set genre/tone; accept; entry
   body gains the reading; regenerate differs. Judge spec quality bar
   (parse rate, lens distinctness, tone shift) on at least 3 results.
2. Reload page: model loads from cache without re-download (refresh() path).
3. Full suite + analyze as in each task.

## Out of scope for this PR (phase 2)

Android/iOS platform config (ABI filters, OpenCL manifest entries, Podfile,
entitlements) and mobile runtime verification. The mobile model spec ships
in this PR but is exercised only in phase 2.
