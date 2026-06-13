# Cycle 4 Phase 1: Command Registry + Structured Entries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Journal entries gain a structured payload (summary + roll rows + re-roll + open-in-tool) and a pure command registry powers re-roll now and the slash palette next phase.

**Architecture:** Additive `JournalEntry.sourceTool`/`payload` fields (no schema bump — `Character.emulation` precedent); `lib/engine/command_registry.dart` (pure Dart, NOT lib/shared — commands need no Flutter; spec §1 path amended) exposes 7 commands over the existing `Oracle`; the journal renders payload entries richly and re-runs commands. Existing GenResult-shaped tool log sites pass payloads.

**Tech Stack:** Flutter + flutter_riverpod; no new deps. House rules: TDD; `dart format` hook runs on every edit; analyze baseline is exactly 1 pre-existing info (lib/engine/models.dart:2); never construct `GemmaInterpreterService` in tests.

**Branch:** work on `cycle4-phase1-command-registry` off main.

**Spec:** docs/superpowers/specs/2026-06-12-cycle4-living-journal-design.md §1–2.

---

### Task 1: JournalEntry payload fields + GenResult.toPayload

**Files:**
- Modify: `lib/engine/models.dart` (JournalEntry ~line 73, GenResult ~line 57)
- Test: `test/journal_payload_test.dart` (create)

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('JournalEntry payload fields', () {
    final entry = JournalEntry(
      id: 'e1',
      timestamp: DateTime.utc(2026, 6, 12),
      title: 'Fate Check (Likely)',
      body: 'Answer: Yes (+04)',
      sourceTool: 'fate-check',
      payload: {
        'v': 1,
        'command': 'fate-juice',
        'args': {'odds': 'likely'},
        'summary': 'Yes',
        'rolls': [
          {'label': 'Answer', 'display': 'Yes (+04)'}
        ],
        'rerollable': true,
      },
    );

    test('payload and sourceTool round-trip through JSON', () {
      final back = JournalEntry.fromJson(entry.toJson());
      expect(back.sourceTool, 'fate-check');
      expect(back.payload!['command'], 'fate-juice');
      expect((back.payload!['rolls'] as List).single['display'], 'Yes (+04)');
    });

    test('null payload/sourceTool are omitted from JSON (byte-stable legacy)', () {
      final plain = JournalEntry(
          id: 'e2', timestamp: DateTime.utc(2026), title: 't', body: 'b');
      final json = plain.toJson();
      expect(json.containsKey('payload'), isFalse);
      expect(json.containsKey('sourceTool'), isFalse);
    });

    test('old JSON without the new keys still parses', () {
      final old = JournalEntry.fromJson({
        'id': 'e3',
        'timestamp': '2026-06-12T00:00:00.000Z',
        'title': 't',
        'body': 'b',
        'kind': 'result',
        'tags': <String>[],
      });
      expect(old.payload, isNull);
      expect(old.sourceTool, isNull);
    });

    test('copyWith preserves payload and sourceTool', () {
      final edited = entry.copyWith(body: 'Answer: Yes (+04)\n\n— note');
      expect(edited.payload, isNotNull);
      expect(edited.sourceTool, 'fate-check');
    });
  });

  group('GenResult.toPayload', () {
    test('maps summary and roll displays', () {
      const g = GenResult(
        title: 'NPC',
        summary: 'Grim hunter',
        rolls: [Roll(label: 'Trait', value: 'Grim', detail: 'd10 4')],
      );
      final p = g.toPayload();
      expect(p['v'], 1);
      expect(p['summary'], 'Grim hunter');
      expect((p['rolls'] as List).single,
          {'label': 'Trait', 'display': 'Grim (d10 4)'});
    });

    test('omits summary when null', () {
      const g = GenResult(title: 'T', rolls: [Roll(label: 'A', value: 'x')]);
      expect(g.toPayload().containsKey('summary'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/journal_payload_test.dart`
Expected: compile errors — `sourceTool` / `payload` / `toPayload` undefined.

- [ ] **Step 3: Implement**

In `lib/engine/models.dart`, add to `GenResult` (after `asText`):

```dart
  /// Structured journal payload (spec: cycle4 living-journal §2).
  Map<String, dynamic> toPayload() => {
        'v': 1,
        if (summary != null) 'summary': summary,
        'rolls': [
          for (final r in rolls) {'label': r.label, 'display': r.display}
        ],
      };
```

In `JournalEntry`: add fields + constructor params (after `tags`):

```dart
    this.sourceTool,
    this.payload,
```
```dart
  /// Tool-registry id that produced this result (open-in-tool), else null.
  final String? sourceTool;

  /// Structured result payload (v1: summary/rolls/command/args/rerollable);
  /// null for prose and legacy entries. Tolerant: render falls back to flat
  /// text for unknown shapes.
  final Map<String, dynamic>? payload;
```

`copyWith` — pass both through unchanged (they are not parameters):

```dart
        kind: kind,
        chaosFactor: chaosFactor,
        tags: tags ?? this.tags,
        sourceTool: sourceTool,
        payload: payload,
```

`toJson` — add before the closing brace:

```dart
        if (sourceTool != null) 'sourceTool': sourceTool,
        if (payload != null) 'payload': payload,
```

`fromJson` — add:

```dart
        sourceTool: j['sourceTool'] as String?,
        payload: (j['payload'] as Map?)?.cast<String, dynamic>(),
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/journal_payload_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/journal_payload_test.dart
git commit -m "feat: JournalEntry sourceTool/payload + GenResult.toPayload (additive)"
```

---

### Task 2: JournalNotifier.addResult

**Files:**
- Modify: `lib/state/providers.dart` (JournalNotifier, after `add` ~line 88)
- Test: `test/journal_test.dart` (append a group)

- [ ] **Step 1: Write the failing test**

Append to the existing `main()` in `test/journal_test.dart` (it already
builds a ProviderContainer with `SharedPreferences.setMockInitialValues`;
follow its existing setup helper — read the file first and reuse its
container pattern):

```dart
  test('addResult persists sourceTool and payload', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(journalProvider.notifier);
    await container.read(journalProvider.future);
    await notifier.addResult(
      'Dice Roll',
      '3d6 = 11',
      sourceTool: 'dice',
      payload: {'v': 1, 'summary': '3d6 = 11', 'rolls': const []},
    );
    final entries = await container.read(journalProvider.future);
    expect(entries.first.sourceTool, 'dice');
    expect(entries.first.payload!['summary'], '3d6 = 11');
    expect(entries.first.kind, JournalKind.result);
  });
```

(Adjust imports/container construction to match the file's existing tests
exactly — the file already imports providers/models/SharedPreferences.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/journal_test.dart`
Expected: compile error — `addResult` undefined.

- [ ] **Step 3: Implement**

In `JournalNotifier` (lib/state/providers.dart), after `add`:

```dart
  Future<void> addResult(
    String title,
    String body, {
    String? sourceTool,
    Map<String, dynamic>? payload,
  }) async {
    await _persist([
      JournalEntry(
          id: _newId(),
          timestamp: DateTime.now(),
          title: title,
          body: body,
          sourceTool: sourceTool,
          payload: payload),
      ...await _ready,
    ]);
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/journal_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/journal_test.dart
git commit -m "feat: JournalNotifier.addResult carries sourceTool/payload"
```

---

### Task 3: Command registry engine

**Files:**
- Create: `lib/engine/command_registry.dart`
- Test: `test/command_registry_test.dart` (create)

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/command_registry.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  final data = _loadData();
  Oracle oracleWith(int seed) => Oracle(data, Dice(Random(seed)));
  final commands = buildCommandRegistry();

  test('ids unique, systems valid, toolIds known shape', () {
    final ids = commands.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    const systems = {'juice', 'mythic', 'roll-high', 'core'};
    for (final c in commands) {
      expect(systems.contains(c.system), isTrue, reason: c.id);
      expect(c.keywords, isNotEmpty, reason: c.id);
    }
    expect(ids, containsAll(['fate-juice', 'fate-mythic', 'fate-roll-high',
        'dice', 'meaning', 'name', 'detail']));
  });

  test('odds label constants match the verified asset', () {
    expect(kMythicOdds, data.mythicOdds);
    expect(kRollHighOdds, data.rollHighOdds);
  });

  test('fate-juice honors odds and emits rerollable payload', () {
    final cmd = commandById(commands, 'fate-juice')!;
    final r = cmd.run(oracleWith(7), {'odds': 'likely'});
    expect(r.title, 'Fate Check (Likely)');
    expect(r.payload['command'], 'fate-juice');
    expect(r.payload['args'], {'odds': 'likely'});
    expect(r.payload['rerollable'], true);
    expect(r.payload['rolls'], isNotEmpty);
    expect(r.body, isNotEmpty);
  });

  test('fate-juice defaults to normal on unknown odds', () {
    final cmd = commandById(commands, 'fate-juice')!;
    final r = cmd.run(oracleWith(8), {'odds': 'nonsense'});
    expect(r.title, 'Fate Check (Normal)');
  });

  test('fate-mythic uses chaos arg and stores it back', () {
    final cmd = commandById(commands, 'fate-mythic')!;
    final r = cmd.run(oracleWith(9), {'odds': '50/50', 'chaos': '7'});
    expect(r.payload['args'], {'odds': '50/50', 'chaos': '7'});
    // The Chaos roll row carries the chaos detail (engine emits it).
    expect(r.body, contains('Chaos'));
  });

  test('fate-roll-high defaults die d20 / odds Unknown', () {
    final cmd = commandById(commands, 'fate-roll-high')!;
    final r = cmd.run(oracleWith(10), {});
    expect(r.payload['args'], {'odds': 'Unknown', 'die': 'd20'});
    expect(r.body, contains('d20'));
  });

  test('dice rolls notation and rejects garbage', () {
    final cmd = commandById(commands, 'dice')!;
    final r = cmd.run(oracleWith(11), {'notation': '3d6+2'});
    expect(r.title, 'Dice Roll');
    expect(r.payload['args'], {'notation': '3d6+2'});
    expect(r.payload['summary'], matches(RegExp(r'^3d6\+2 = \d+$')));
    expect(() => cmd.run(oracleWith(11), {'notation': 'zzz'}),
        throwsFormatException);
    expect(() => cmd.run(oracleWith(11), {}), throwsFormatException);
  });

  test('meaning, name, detail run without args', () {
    for (final id in ['meaning', 'name', 'detail']) {
      final r = commandById(commands, id)!.run(oracleWith(12), {});
      expect(r.payload['rolls'], isNotEmpty, reason: id);
      expect(r.payload['rerollable'], true, reason: id);
    }
  });

  test('commandById returns null for unknown', () {
    expect(commandById(commands, 'nope'), isNull);
  });

  test('command bodies equal the payload-derived text (render contract)', () {
    // Render shows summary+rolls; body must start from the same text so the
    // journal can detect appended notes (see journal payload rendering).
    for (final id in ['fate-juice', 'fate-mythic', 'fate-roll-high',
        'meaning', 'name', 'detail']) {
      final r = commandById(commands, id)!.run(oracleWith(13), {});
      final rolls = (r.payload['rolls'] as List)
          .map((m) => '${m['label']}: ${m['display']}')
          .join('\n');
      final expected =
          r.payload.containsKey('summary') ? '${r.payload['summary']}\n$rolls' : rolls;
      expect(r.body, expected, reason: id);
    }
  });
}
```

Note: `data.mythicOdds` may not exist yet as an accessor — check
`lib/engine/oracle_data.dart`; `rollHighOdds` exists (~line 110). If
`mythicOdds` is missing, add alongside it:

```dart
  List<String> get mythicOdds =>
      ((_json['mythic'] as Map<String, dynamic>)['odds'] as List)
          .cast<String>();
```

(Inspect the file's existing accessor style first and match it.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/command_registry_test.dart`
Expected: compile error — command_registry.dart missing.

- [ ] **Step 3: Implement `lib/engine/command_registry.dart`**

```dart
/// Declarative quick-command registry (spec: cycle4 living-journal §1).
///
/// Pure engine layer — consumed by the journal's re-roll action now and the
/// slash palette in phase 2. Deep work stays in the tools; commands cover
/// the high-frequency "ask and keep playing" loop.
library;

import 'dice_notation.dart';
import 'models.dart';
import 'oracle.dart';

/// Argument shape a command expects (drives palette affordances, phase 2).
enum CommandArg { none, odds, notation }

/// What a command produces: a ready-to-journal title/body plus the
/// structured entry payload (always `rerollable: true` — commands are pure).
class CommandResult {
  const CommandResult(
      {required this.title, required this.body, required this.payload});
  final String title;
  final String body;
  final Map<String, dynamic> payload;
}

class CommandDef {
  const CommandDef({
    required this.id,
    required this.label,
    required this.keywords,
    required this.system,
    required this.arg,
    required this.run,
    this.toolId,
  });

  final String id;
  final String label;
  final List<String> keywords;

  /// 'juice' | 'mythic' | 'roll-high' | 'core' (profile scoping, phase 4).
  final String system;
  final CommandArg arg;

  /// Runs the command. May throw [FormatException] for bad args (dice
  /// notation); never throws otherwise.
  final CommandResult Function(Oracle oracle, Map<String, String> args) run;

  /// Tool-registry id for "open in tool" / deep work.
  final String? toolId;
}

/// Mythic fate-chart odds ladder, index-aligned with the verified asset
/// (pinned by test against OracleData.mythicOdds).
const kMythicOdds = [
  'Certain',
  'Nearly Certain',
  'Very Likely',
  'Likely',
  '50/50',
  'Unlikely',
  'Very Unlikely',
  'Nearly Impossible',
  'Impossible',
];

/// Roll High odds ladder, index-aligned with the verified asset
/// (pinned by test against OracleData.rollHighOdds).
const kRollHighOdds = [
  'Almost Certain',
  'Very Likely',
  'Likely',
  'Unknown',
  'Unlikely',
  'Very Unlikely',
  'Almost Impossible',
];

CommandDef? commandById(List<CommandDef> commands, String id) {
  for (final c in commands) {
    if (c.id == id) return c;
  }
  return null;
}

Map<String, dynamic> _payload(
        String command, Map<String, String> args, GenResult g) =>
    {
      ...g.toPayload(),
      'command': command,
      'args': args,
      'rerollable': true,
    };

CommandResult _fromGen(String command, Map<String, String> args, GenResult g) =>
    CommandResult(title: g.title, body: g.asText, payload: _payload(command, args, g));

List<CommandDef> buildCommandRegistry() => [
      CommandDef(
        id: 'fate-juice',
        label: 'Fate Check (Juice)',
        keywords: ['fate', 'check', 'yes', 'no', 'juice', 'oracle'],
        system: 'juice',
        arg: CommandArg.odds,
        toolId: 'fate-check',
        run: (o, args) {
          final lk = Likelihood.values.asNameMap()[args['odds']] ??
              Likelihood.normal;
          final r = o.fateCheck(lk);
          final g = GenResult(
            title: 'Fate Check (${lk.label})',
            summary: r.result,
            rolls: [
              Roll(label: 'Answer', value: r.result, detail: r.shorthand),
              Roll(
                  label: 'Intensity',
                  value: r.intensity,
                  detail: 'd6 ${r.intensityRoll}'),
            ],
          );
          return _fromGen('fate-juice', {'odds': lk.key}, g);
        },
      ),
      CommandDef(
        id: 'fate-mythic',
        label: 'Fate Check (Mythic)',
        keywords: ['fate', 'mythic', 'chart', 'yes', 'no', 'chaos'],
        system: 'mythic',
        arg: CommandArg.odds,
        toolId: 'mythic',
        run: (o, args) {
          var idx = kMythicOdds.indexOf(args['odds'] ?? '50/50');
          if (idx < 0) idx = 4; // 50/50
          final chaos = (int.tryParse(args['chaos'] ?? '') ?? 5).clamp(1, 9);
          final g = o.mythicFate(idx, chaos);
          return _fromGen('fate-mythic',
              {'odds': kMythicOdds[idx], 'chaos': '$chaos'}, g);
        },
      ),
      CommandDef(
        id: 'fate-roll-high',
        label: 'Fate Check (Roll High)',
        keywords: ['fate', 'roll', 'high', 'yes', 'no'],
        system: 'roll-high',
        arg: CommandArg.odds,
        toolId: 'roll-high',
        run: (o, args) {
          var idx = kRollHighOdds.indexOf(args['odds'] ?? 'Unknown');
          if (idx < 0) idx = 3; // Unknown
          const die = 'd20';
          final g = o.rollHigh(die, idx);
          return _fromGen('fate-roll-high',
              {'odds': kRollHighOdds[idx], 'die': die}, g);
        },
      ),
      CommandDef(
        id: 'dice',
        label: 'Roll Dice',
        keywords: ['dice', 'roll', 'd6', 'd20', 'notation'],
        system: 'core',
        arg: CommandArg.notation,
        toolId: 'dice',
        run: (o, args) {
          final notation = (args['notation'] ?? '').trim();
          if (notation.isEmpty) {
            throw const FormatException('Add dice notation, e.g. /dice 3d6+2');
          }
          final r = parseDice(notation).roll(o.dice);
          final g = GenResult(
            title: 'Dice Roll',
            summary: '${r.expression} = ${r.total}',
            rolls: [
              for (final grp in r.groups)
                if (grp.dice.isNotEmpty)
                  Roll(
                      label: grp.label,
                      value: grp.dice
                          .map((d) => d.kept ? d.display : '[${d.display}]')
                          .join(', '),
                      detail: '${grp.subtotal}'),
            ],
          );
          return _fromGen('dice', {'notation': notation}, g);
        },
      ),
      CommandDef(
        id: 'meaning',
        label: 'Discover Meaning',
        keywords: ['meaning', 'discover', 'inspiration', 'prompt'],
        system: 'juice',
        arg: CommandArg.none,
        toolId: 'gen-story',
        run: (o, args) => _fromGen('meaning', const {}, o.discoverMeaning()),
      ),
      CommandDef(
        id: 'name',
        label: 'Generate Name',
        keywords: ['name', 'npc', 'generate'],
        system: 'juice',
        arg: CommandArg.none,
        toolId: 'gen-details',
        run: (o, args) => _fromGen('name', const {}, o.generateName()),
      ),
      CommandDef(
        id: 'detail',
        label: 'Random Detail',
        keywords: ['detail', 'random', 'flavor'],
        system: 'juice',
        arg: CommandArg.none,
        toolId: 'gen-details',
        run: (o, args) => _fromGen('detail', const {}, o.detail()),
      ),
    ];
```

If `parseDice`'s group/die member names differ (check
`lib/engine/dice_notation.dart` ~lines 50–110: `RolledGroup.label/sign/
dice/subtotal`, die `.display`/`.kept`), match the real names.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/command_registry_test.dart`
Expected: all pass. If `data.mythicOdds` was missing, the accessor added in
Step 1 makes the pin test compile.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/command_registry.dart lib/engine/oracle_data.dart test/command_registry_test.dart
git commit -m "feat: pure command registry (7 quick commands over Oracle)"
```

---

### Task 4: ToolHost.openToolIfKnown

**Files:**
- Modify: `lib/shared/tool_host.dart` (~line 26, beside `openLauncher`)
- Test: `test/tool_host_test.dart` (append)

- [ ] **Step 1: Write the failing test**

Append to `test/tool_host_test.dart` (reuse its existing fake-tools pump
helper — read the file and follow its established pattern for building a
ToolHost with fake ToolDefs):

```dart
  testWidgets('openToolIfKnown opens known tools and rejects unknown',
      (tester) async {
    // Pump the same fake ToolHost the file's other tests use.
    // ... existing helper ...
    final ctx = tester.element(find.byType(ToolHost));
    expect(ToolHost.openToolIfKnown(ctx, 'no-such-tool'), isFalse);
    expect(ToolHost.openToolIfKnown(ctx, /* a fake tool id from helper */ 'a'),
        isTrue);
    await tester.pumpAndSettle();
    // Panel shows the tool's label per the helper's fake tool.
  });
```

(Concrete ids/labels: mirror whatever the file's existing tests assert —
do not invent new fixtures.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/tool_host_test.dart`
Expected: compile error — `openToolIfKnown` undefined.

- [ ] **Step 3: Implement**

In `ToolHost` (below the existing `openLauncher` static):

```dart
  /// Opens [id] in the nearest ToolHost when the registry has it; returns
  /// false (no-op) otherwise. Used by journal entry "open in tool" actions.
  static bool openToolIfKnown(BuildContext context, String id) {
    final host = context.findAncestorStateOfType<ToolHostState>();
    if (host == null || !host.widget.tools.any((t) => t.id == id)) {
      return false;
    }
    host.openTool(id);
    return true;
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/tool_host_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/tool_host.dart test/tool_host_test.dart
git commit -m "feat: ToolHost.openToolIfKnown for journal deep links"
```

---

### Task 5: Journal payload rendering (rich card + re-roll + open-in-tool)

**Files:**
- Modify: `lib/features/journal_screen.dart` (`_entry` result case ~line 262; new widgets at file end)
- Test: `test/journal_payload_ui_test.dart` (create)

- [ ] **Step 1: Write the failing tests**

Follow the pump pattern of `test/journal_screen_test.dart` (ProviderScope
with `SharedPreferences.setMockInitialValues`, `MaterialApp(theme:
AppTheme.light(), home: ...)`); seed a journal entry list via prefs under
the active-session key the way that file does (read it first; it seeds
`juice.journal.v2.<sessionId>`). The journal must be hosted under a
ToolHost with the real registry for the open-in-tool test — reuse
`test/home_shell_test.dart`'s approach if simpler (it pumps HomeShell with
a real Oracle via overridden providers).

Test cases:

```dart
  testWidgets('payload entry renders summary, roll rows, and actions', ...);
  // seed one entry with payload {summary: 'Yes', rolls: [{label: 'Answer',
  // display: 'Yes (+04)'}], command: 'fate-juice', args: {'odds': 'likely'},
  // rerollable: true}, sourceTool: 'fate-check', body equal to
  // 'Yes\nAnswer: Yes (+04)'.
  // expect: find.text('Yes') (summary), find.textContaining('Answer:'),
  // re-roll icon (Key('entry-reroll-<id>')), open-in-tool icon
  // (Key('entry-open-tool-<id>')); raw body NOT duplicated (the string
  // 'Yes\nAnswer: Yes (+04)' appears zero times as a single Text).

  testWidgets('appended notes beyond the payload text still render', ...);
  // same entry but body = 'Yes\nAnswer: Yes (+04)\n\n— Oracle reading
  // (literal): The guard nods.' → expect find.textContaining('Oracle
  // reading'). (Interpret-append survives rich rendering.)

  testWidgets('re-roll appends a new entry via the command registry', ...);
  // pump with a seeded oracleProvider override (Oracle(data, Dice(Random(1))))
  // like home_shell_test does; tap Key('entry-reroll-<id>');
  // expect journal length grows by 1 and newest entry payload command ==
  // 'fate-juice' with args odds 'likely'.

  testWidgets('open-in-tool opens the source tool panel', ...);
  // pump HomeShell-style (real ToolHost); tap Key('entry-open-tool-<id>');
  // expect the Fate Check tool header visible (find.text('Fate Check')).

  testWidgets('entry with unknown payload version falls back to flat', ...);
  // payload {'v': 99, 'weird': true}; expect ListTile body text rendered,
  // no re-roll icon.

  testWidgets('non-rerollable payload hides the re-roll icon', ...);
  // payload without 'command'/'rerollable' (tool-logged) + sourceTool set;
  // expect open-in-tool icon present, re-roll icon absent.
```

Write these as real tests (full pumps + assertions), mirroring the host
file's helpers; the bullets above pin the required behavior and keys.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/journal_payload_ui_test.dart`
Expected: failures — payload entries currently render as plain ListTiles
(no keys/icons).

- [ ] **Step 3: Implement**

In `_entry`'s `JournalKind.result` case (journal_screen.dart ~line 262):

```dart
      case JournalKind.result:
        final extras = _suffixLines(e, threadTitle);
        final p = e.payload;
        if (p != null && p['v'] == 1 && p['rolls'] is List) {
          return _PayloadCard(
            entry: e,
            extras: extras,
            menu: menu,
            onReroll: _canReroll(e) ? () => _reroll(e) : null,
            onOpenTool: e.sourceTool == null
                ? null
                : () {
                    if (!ToolHost.openToolIfKnown(context, e.sourceTool!)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Tool not available')));
                    }
                  },
          );
        }
        return Card( /* existing flat ListTile rendering unchanged */ );
```

Helpers in `_JournalScreenState`:

```dart
  bool _canReroll(JournalEntry e) {
    final p = e.payload;
    return p != null &&
        p['rerollable'] == true &&
        p['command'] is String &&
        ref.read(oracleProvider).valueOrNull != null;
  }

  Future<void> _reroll(JournalEntry e) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    final p = e.payload;
    if (oracle == null || p == null) return;
    final cmd = commandById(buildCommandRegistry(), p['command'] as String);
    if (cmd == null) return;
    final args = <String, String>{
      for (final entry in ((p['args'] as Map?) ?? const {}).entries)
        '${entry.key}': '${entry.value}',
    };
    if (cmd.id == 'fate-mythic') {
      // Re-rolls happen under CURRENT conditions; stored chaos is display-only.
      args['chaos'] =
          '${ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5}';
    }
    final r = cmd.run(oracle, args);
    await ref.read(journalProvider.notifier).addResult(r.title, r.body,
        sourceTool: e.sourceTool, payload: r.payload);
  }
```

New widget at file end (private):

```dart
/// Rich rendering for entries that carry a structured payload: summary +
/// roll rows + appended-notes remainder + re-roll / open-in-tool actions.
class _PayloadCard extends StatelessWidget {
  const _PayloadCard({
    required this.entry,
    required this.extras,
    required this.menu,
    this.onReroll,
    this.onOpenTool,
  });

  final JournalEntry entry;
  final List<String> extras;
  final Widget menu;
  final VoidCallback? onReroll;
  final VoidCallback? onOpenTool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = entry.payload!;
    final summary = p['summary'] as String?;
    final rolls = [
      for (final r in (p['rolls'] as List))
        if (r is Map) ('${r['label']}', '${r['display']}'),
    ];
    // Body content beyond the payload-derived text (e.g. appended oracle
    // readings) still renders; the base text is shown structured instead.
    final rollsText = rolls.map((r) => '${r.$1}: ${r.$2}').join('\n');
    final baseText = summary == null ? rollsText : '$summary\n$rollsText';
    var remainder = '';
    if (entry.body != baseText) {
      remainder = entry.body.startsWith(baseText)
          ? entry.body.substring(baseText.length).trimLeft()
          : entry.body;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child:
                      Text(entry.title, style: theme.textTheme.titleSmall)),
              if (onReroll != null)
                IconButton(
                  key: Key('entry-reroll-${entry.id}'),
                  tooltip: 'Roll again',
                  icon: const Icon(Icons.replay, size: 20),
                  onPressed: onReroll,
                ),
              if (onOpenTool != null)
                IconButton(
                  key: Key('entry-open-tool-${entry.id}'),
                  tooltip: 'Open in tool',
                  icon: const Icon(Icons.open_in_new, size: 20),
                  onPressed: onOpenTool,
                ),
              menu,
            ]),
            if (summary != null)
              Text(summary,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 4),
            for (final r in rolls)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(r.$1,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(
                          child: Text(r.$2,
                              style: theme.textTheme.bodyMedium)),
                    ]),
              ),
            if (remainder.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(remainder, style: theme.textTheme.bodyMedium),
            ],
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(extras.join('\n'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}
```

Imports to add in journal_screen.dart: `../engine/command_registry.dart`,
`../shared/tool_host.dart`.

- [ ] **Step 4: Run all affected tests**

Run: `flutter test test/journal_payload_ui_test.dart test/journal_screen_test.dart test/journal_interpret_test.dart`
Expected: all pass (existing tests use flat entries — unchanged path).

- [ ] **Step 5: Commit**

```bash
git add lib/features/journal_screen.dart test/journal_payload_ui_test.dart
git commit -m "feat: rich payload rendering with re-roll and open-in-tool"
```

---

### Task 6: Wire GenResult-shaped tool log sites

**Files:**
- Modify: `lib/features/fate_screen.dart` (~lines 157, 232, 315, 359)
- Modify: `lib/features/generators_screen.dart` (~lines 117, 133)
- Modify: `lib/features/dice_roller_screen.dart` (~line 151)
- Test: extend `test/fate_screen_test.dart`, `test/generators_screen_test.dart`, `test/dice_roller_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

In each screen test file, add one test (following that file's existing
pump/seed pattern) asserting that after rolling and tapping
add-to-journal, the newest journal entry has the expected `sourceTool`
and a payload with non-empty `rolls`:

- fate_screen Roll High path → `sourceTool == 'roll-high'`
- fate_screen Mythic path → `sourceTool == 'mythic'`
- fate_screen Juice fate-check path → `sourceTool == 'fate-check'` and
  payload summary equals the rolled answer
- generators_screen (whichever section that test file already exercises) →
  `sourceTool == 'gen-<section>'` matching the screen's section
- dice_roller → `sourceTool == 'dice'`, payload summary matches
  `<expr> = <total>`

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/fate_screen_test.dart test/generators_screen_test.dart test/dice_roller_screen_test.dart`
Expected: new tests fail (entries have null sourceTool).

- [ ] **Step 3: Implement call-site changes**

fate_screen.dart line ~157 (Roll High):
```dart
                    .addResult(_rhLast!.title, _rhLast!.asText,
                        sourceTool: 'roll-high', payload: _rhLast!.toPayload());
```
line ~232 (Mythic):
```dart
                          .addResult(_mythicLast!.title, _mythicLast!.asText,
                              sourceTool: 'mythic',
                              payload: _mythicLast!.toPayload());
```
line ~315 (generic juice generator inside the fate tool):
```dart
    ref.read(journalProvider.notifier).addResult(g.title, g.asText,
        sourceTool: 'fate-check', payload: g.toPayload());
```
line ~359 (manual fate check) — build the same GenResult the `fate-juice`
command builds, then log it; replace the `.add(...)` call with:
```dart
                    final g = GenResult(
                      title: 'Fate Check (${result.likelihood.label})',
                      summary: result.result,
                      rolls: [
                        Roll(
                            label: 'Answer',
                            value: result.result,
                            detail: result.shorthand),
                        Roll(
                            label: 'Intensity',
                            value: result.intensity,
                            detail: 'd6 ${result.intensityRoll}'),
                      ],
                    );
                    ref.read(journalProvider.notifier).addResult(
                        g.title, g.asText,
                        sourceTool: 'fate-check', payload: g.toPayload());
```
(The old body format `'$result — $intensity [..]'` is replaced by
`g.asText` so the render contract holds; check the screen still compiles
with `GenResult`/`Roll` imported from models.)

generators_screen.dart line ~117:
```dart
              ref.read(journalProvider.notifier).addResult(
                  last.title, last.asText,
                  sourceTool: _sourceTool, payload: last.toPayload());
```
with a section→tool-id getter on the screen's state/widget:
```dart
  String get _sourceTool => switch (widget.section) {
        GenSection.story => 'gen-story',
        GenSection.npcs => 'gen-npcs',
        GenSection.exploration => 'gen-exploration',
        GenSection.encounters => 'gen-encounters',
        GenSection.details => 'gen-details',
      };
```
(Check the actual GenSection enum cases in the file and cover them all.)

line ~133 (Location quick log):
```dart
              final g = GenResult(title: 'Location', rolls: [
                Roll(label: 'Location', value: loc.label, detail: '${loc.roll}'),
              ]);
              ref.read(journalProvider.notifier).addResult(g.title, g.asText,
                  sourceTool: _sourceTool, payload: g.toPayload());
```

dice_roller_screen.dart line ~151:
```dart
                              .addResult('Dice Roll', last.asText,
                                  sourceTool: 'dice',
                                  payload: {
                                    'v': 1,
                                    'summary':
                                        '${last.expression} = ${last.total}',
                                    'rolls': [
                                      for (final grp in last.groups)
                                        if (grp.dice.isNotEmpty)
                                          {
                                            'label': grp.label,
                                            'display':
                                                '${grp.dice.map((d) => d.kept ? d.display : '[${d.display}]').join(', ')} (${grp.subtotal})',
                                          }
                                    ],
                                  });
```
Note: dice body stays `last.asText` (multi-line breakdown) — it does NOT
start with the payload base text, so the rich card shows structured rows
plus the full breakdown as remainder. That is acceptable duplication ONLY
if it reads badly in verify — if so, set body to
`'${last.expression} = ${last.total}'` and let rolls carry the breakdown;
decide during browser verify and note the choice in the PR.

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: all pass; fix any existing assertions that pinned the old fate
body format (update them to the new `g.asText` shape — they are asserting
formatting, not behavior).

- [ ] **Step 5: Commit**

```bash
git add lib/features/fate_screen.dart lib/features/generators_screen.dart lib/features/dice_roller_screen.dart test/
git commit -m "feat: fate/generators/dice log structured payloads"
```

---

### Task 7: Gates + docs

**Files:**
- Modify: `README.md` (feature list — one line about rich journal results)
- Modify: `.github` nothing; CI runs analyze+test as-is

- [ ] **Step 1: README line**

In the README features section, add (match surrounding bullet style):
```markdown
- Rich journal results: oracle/dice entries render structured rolls with one-tap re-roll and open-in-tool.
```

- [ ] **Step 2: Full gates**

Run: `flutter analyze`
Expected: exactly 1 pre-existing info (lib/engine/models.dart:2 dangling_library_doc_comments) — nothing new.

Run: `flutter test`
Expected: full suite green.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README note for structured journal results"
```

---

## Self-review notes

- Spec §1 coverage: CommandDef/CommandResult/7 commands/odds constants — Task 3. Path amendment (engine/ not shared/) recorded in header.
- Spec §2 coverage: additive fields (Task 1), addResult (Task 2), rich render + re-roll appends + open-in-tool (Tasks 4–5), GenResult helper + tool wiring (Tasks 1, 6), flat fallback for unknown payloads (Task 5 test), stateful tools never rerollable (only commands set the flag).
- Render contract (body == summary+rolls text) pinned by a registry test and honored by Task 6's fate rewrite; dice deviation documented inline.
- Type names cross-checked: `toPayload`, `addResult`, `openToolIfKnown`, `commandById`, `buildCommandRegistry`, `kMythicOdds`, `kRollHighOdds` consistent across tasks.
