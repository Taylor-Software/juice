# Cycle 4 Phase 2: Slash Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Typing `/` in the journal composer opens an in-place command palette; picking a command runs it and drops a structured entry inline — no tool panel.

**Architecture:** A pure parser/matcher in `command_registry.dart` (testable without widgets); a `_SlashPalette` panel rendered above the composer in `journal_screen.dart` when the composer text starts with `/`; keyboard (Down/Up/Enter/Esc) + tap selection; odds commands show odds chips, `/dice` takes trailing notation, `/scene` and `/help` are built-ins.

**Tech Stack:** Flutter + flutter_riverpod. Reuses phase-1 `buildCommandRegistry()`, `addResult`, payload rendering. House rules: TDD; format hook; analyze baseline exactly 1 info; never construct GemmaInterpreterService in tests; commits exact, no co-author.

**Branch:** `cycle4-phase2-slash-palette` off main (40018a0). Plan committed first.

**Spec:** docs/superpowers/specs/2026-06-12-cycle4-living-journal-design.md §3.

---

### Task 1: Slash parser + command matcher (pure)

**Files:**
- Modify: `lib/engine/command_registry.dart` (append)
- Test: `test/command_registry_test.dart` (append a group)

- [ ] **Step 1: Write failing tests** (append inside `main()`):

```dart
  group('slash parsing + matching', () {
    final reg = buildCommandRegistry();

    test('parseSlash returns null when not a slash command', () {
      expect(parseSlash('hello'), isNull);
      expect(parseSlash('  /fate'), isNull); // must be leading char
      expect(parseSlash(''), isNull);
    });

    test('parseSlash splits token and rest', () {
      expect(parseSlash('/'), (token: '', rest: ''));
      expect(parseSlash('/fa'), (token: 'fa', rest: ''));
      expect(parseSlash('/dice 3d6+2'), (token: 'dice', rest: '3d6+2'));
      expect(parseSlash('/fate likely'), (token: 'fate', rest: 'likely'));
      expect(parseSlash('/name  '), (token: 'name', rest: ''));
    });

    test('matchCommands by empty token returns all', () {
      expect(matchCommands(reg, '').length, reg.length);
    });

    test('matchCommands filters by id/keyword/label prefix-ish', () {
      final dice = matchCommands(reg, 'dice');
      expect(dice.map((c) => c.id), contains('dice'));
      final fate = matchCommands(reg, 'fate');
      // all three fate commands match the keyword 'fate'
      expect(fate.map((c) => c.id),
          containsAll(['fate-juice', 'fate-mythic', 'fate-roll-high']));
      expect(matchCommands(reg, 'zzz'), isEmpty);
    });

    test('matchCommands is case-insensitive', () {
      expect(matchCommands(reg, 'DICE').map((c) => c.id), contains('dice'));
    });
  });
```

- [ ] **Step 2: Run, see fail**

Run: `flutter test test/command_registry_test.dart`
Expected: `parseSlash`/`matchCommands` undefined.

- [ ] **Step 3: Implement** (append to `lib/engine/command_registry.dart`):

```dart
/// Parsed slash input: the command token (text after `/` up to the first
/// space) and the remaining argument text. Null when [text] is not a slash
/// command (must start with `/`).
({String token, String rest})? parseSlash(String text) {
  if (!text.startsWith('/')) return null;
  final body = text.substring(1);
  final sp = body.indexOf(' ');
  if (sp < 0) return (token: body, rest: '');
  return (token: body.substring(0, sp), rest: body.substring(sp + 1).trim());
}

/// Commands whose id, label, or any keyword contains [token]
/// (case-insensitive). Empty token returns all commands in registry order.
List<CommandDef> matchCommands(List<CommandDef> registry, String token) {
  final q = token.toLowerCase();
  if (q.isEmpty) return registry;
  return registry
      .where((c) =>
          c.id.toLowerCase().contains(q) ||
          c.label.toLowerCase().contains(q) ||
          c.keywords.any((k) => k.toLowerCase().contains(q)))
      .toList();
}
```

- [ ] **Step 4: Run, see pass**

Run: `flutter test test/command_registry_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/command_registry.dart test/command_registry_test.dart
git commit -m "feat: slash parser + command matcher for the palette"
```

---

### Task 2: Run-a-command helper on the journal notifier path

**Files:**
- Modify: `lib/features/journal_screen.dart` (new private method `_runCommand`)
- Test: covered by Task 3 widget tests (no standalone test — it's a thin wrapper around phase-1 addResult that the palette tests exercise)

- [ ] **Step 1: Implement** `_runCommand` in `_JournalScreenState` (near `_reroll`):

```dart
  /// Runs a registry command from the palette: rolls against the loaded
  /// oracle and drops a structured entry. Mythic pulls live chaos.
  Future<void> _runCommand(CommandDef cmd, {String? odds, String? notation}) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final args = <String, String>{};
    if (odds != null) args['odds'] = odds;
    if (notation != null) args['notation'] = notation;
    if (cmd.id == 'fate-mythic') {
      args['chaos'] = '${ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5}';
    }
    try {
      final r = cmd.run(oracle, args);
      await ref.read(journalProvider.notifier).addResult(r.title, r.body,
          sourceTool: cmd.toolId, payload: r.payload);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
```

Note: `sourceTool` is `cmd.toolId` so palette entries deep-link to the same tool the tool-logged entries do. Import `../engine/command_registry.dart` is already present from phase 1; ensure `CommandDef` resolves.

- [ ] **Step 2: Verify compile** by running the existing journal tests:

Run: `flutter test test/journal_screen_test.dart`
Expected: still green (no behavior change yet).

- [ ] **Step 3: Commit**

```bash
git add lib/features/journal_screen.dart
git commit -m "feat: _runCommand helper drops a structured entry from a command"
```

---

### Task 3: Slash palette UI in the composer

**Files:**
- Modify: `lib/features/journal_screen.dart` (composer state, `_composerBar`, `_send`, new `_SlashPalette` widget)
- Test: `test/slash_palette_test.dart` (create)

- [ ] **Step 1: Write failing widget tests**

Mirror `test/journal_screen_test.dart`'s pump (seed `juice.sessions.v1` active `default`; override `oracleProvider` with a real `Oracle(data, Dice(Random(1)))` and `interpreterServiceProvider` with `FakeInterpreterService()`). Required cases:

```dart
  testWidgets('typing / opens the palette listing commands', ...);
  // enterText(Key('journal-composer'), '/'); pump();
  // expect find.byKey(Key('slash-palette')) findsOneWidget;
  // expect find.text('Fate Check (Juice)') findsOneWidget;
  // expect find.text('Roll Dice') findsOneWidget;

  testWidgets('typing /di filters to the dice command', ...);
  // enterText('/di'); pump();
  // expect find.text('Roll Dice') findsOneWidget;
  // expect find.text('Fate Check (Juice)') findsNothing;

  testWidgets('selecting a no-arg command runs it and clears the composer', ...);
  // enterText('/name'); pump();
  // tap find.byKey(Key('slash-cmd-name')); pumpAndSettle();
  // composer controller text is now empty; journal has 1 entry sourceTool 'gen-details';
  // palette gone (find.byKey(Key('slash-palette')) findsNothing).

  testWidgets('/dice with notation runs the dice command on Enter', ...);
  // enterText('/dice 2d6+1'); pump();
  // The palette shows the dice command highlighted; tap Key('slash-cmd-dice')
  // (or simulate Enter via the send button which the palette intercepts);
  // journal newest entry sourceTool 'dice', payload summary matches '2d6+1 = \d+'.

  testWidgets('a fate command shows odds chips; picking one runs at that odds', ...);
  // enterText('/fate'); pump();
  // tap Key('slash-cmd-fate-juice') -> expands odds chips OR directly shows them;
  // tap Key('slash-odds-likely'); pumpAndSettle();
  // journal newest entry sourceTool 'fate-check', payload args odds == 'likely'.

  testWidgets('/scene opens the scene dialog', ...);
  // enterText('/scene'); pump(); tap Key('slash-cmd-scene'); pumpAndSettle();
  // expect find.text('New scene') findsOneWidget (the existing _SceneDialog title).

  testWidgets('clearing the slash dismisses the palette', ...);
  // enterText('/'); pump(); expect palette present;
  // enterText(''); pump(); expect find.byKey(Key('slash-palette')) findsNothing.

  testWidgets('plain text send still works (no palette)', ...);
  // enterText('just a note'); pump(); expect palette absent;
  // tap Key('journal-send'); pumpAndSettle(); journal has a text entry 'just a note'.
```

Flesh each into a full test with assertions.

- [ ] **Step 2: Run, see fail**

Run: `flutter test test/slash_palette_test.dart`
Expected: fail — no palette.

- [ ] **Step 3: Implement**

In `_JournalScreenState`, drive the palette off the composer text. Add a listener so the palette rebuilds as the user types:

```dart
  // Built-in (non-registry) slash commands handled inline.
  static const _builtinScene = 'scene';
  static const _builtinHelp = 'help';
```

In `initState` (add one if absent) / or convert the existing field init, attach a listener:

```dart
  @override
  void initState() {
    super.initState();
    _composer.addListener(_onComposerChanged);
  }

  void _onComposerChanged() {
    final isSlash = _composer.text.startsWith('/');
    if (isSlash != _slashActive) {
      setState(() => _slashActive = isSlash);
    } else if (isSlash) {
      setState(() {}); // refilter as the token changes
    }
  }
```

Add field `bool _slashActive = false;` and remember to `_composer.removeListener(_onComposerChanged)` before `_composer.dispose()` in `dispose`.

Render the palette directly above the composer. In `build`, the outer `Column` ends with `_composerBar()`. Change that tail to:

```dart
        if (_slashActive) _slashPalette(),
        _composerBar(),
```

`_slashPalette()` builds the panel:

```dart
  Widget _slashPalette() {
    final parsed = parseSlash(_composer.text);
    if (parsed == null) return const SizedBox.shrink();
    final registry = buildCommandRegistry();
    // Built-ins surface when their name prefixes the token.
    final showScene = _builtinScene.contains(parsed.token.toLowerCase());
    final showHelp = _builtinHelp.contains(parsed.token.toLowerCase());
    final matches = matchCommands(registry, parsed.token);
    final theme = Theme.of(context);
    return Container(
      key: const Key('slash-palette'),
      constraints: const BoxConstraints(maxHeight: 280),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final c in matches)
            _SlashRow(
              command: c,
              notation: parsed.rest,
              onRun: ({String? odds}) => _selectCommand(c, odds: odds),
            ),
          if (showScene)
            ListTile(
              key: const Key('slash-cmd-scene'),
              dense: true,
              leading: const Icon(Icons.movie_outlined),
              title: const Text('Start a scene'),
              onTap: () {
                _composer.clear();
                _newScene();
              },
            ),
          if (showHelp)
            ListTile(
              key: const Key('slash-cmd-help'),
              dense: true,
              leading: const Icon(Icons.help_outline),
              title: const Text('Open Help'),
              onTap: () {
                _composer.clear();
                ToolHost.openToolIfKnown(context, 'help');
              },
            ),
          if (matches.isEmpty && !showScene && !showHelp)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No matching command'),
            ),
        ],
      ),
    );
  }

  Future<void> _selectCommand(CommandDef c, {String? odds}) async {
    final parsed = parseSlash(_composer.text);
    _composer.clear(); // also flips _slashActive off via the listener
    await _runCommand(c,
        odds: odds,
        notation: c.arg == CommandArg.notation ? (parsed?.rest ?? '') : null);
  }
```

`_SlashRow` (private widget) renders a command and, for odds commands, an expandable chip row:

```dart
class _SlashRow extends StatefulWidget {
  const _SlashRow(
      {required this.command, required this.notation, required this.onRun});
  final CommandDef command;
  final String notation;
  final void Function({String? odds}) onRun;

  @override
  State<_SlashRow> createState() => _SlashRowState();
}

class _SlashRowState extends State<_SlashRow> {
  bool _expanded = false;

  List<String> get _oddsOptions => switch (widget.command.id) {
        'fate-juice' => const ['unlikely', 'normal', 'likely'],
        'fate-mythic' => kMythicOdds,
        'fate-roll-high' => kRollHighOdds,
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.command;
    final hasOdds = c.arg == CommandArg.odds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: Key('slash-cmd-${c.id}'),
          dense: true,
          title: Text(c.label),
          subtitle: c.arg == CommandArg.notation
              ? Text(widget.notation.isEmpty
                  ? 'Type dice notation, e.g. /dice 3d6+2'
                  : 'Roll ${widget.notation}')
              : null,
          trailing: hasOdds ? const Icon(Icons.tune, size: 18) : null,
          onTap: () {
            if (hasOdds) {
              setState(() => _expanded = !_expanded);
            } else {
              widget.onRun();
            }
          },
        ),
        if (hasOdds && _expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in _oddsOptions)
                  ActionChip(
                    key: Key('slash-odds-$o'),
                    label: Text(o == 'normal'
                        ? 'Normal'
                        : (o.isNotEmpty
                            ? '${o[0].toUpperCase()}${o.substring(1)}'
                            : o)),
                    onPressed: () => widget.onRun(odds: o),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
```

`_send` routes Enter to the palette when slash-active (runs the top match —
honors spec §3 "Enter"), else sends prose:

```dart
  Future<void> _send() async {
    final text = _composer.text;
    if (text.startsWith('/')) {
      // Enter runs the first matching command (built-ins win when they
      // exactly head the token); otherwise the palette stays open.
      final parsed = parseSlash(text)!;
      final tok = parsed.token.toLowerCase();
      if (_builtinScene == tok) {
        _composer.clear();
        await _newScene();
        return;
      }
      if (_builtinHelp == tok) {
        _composer.clear();
        if (mounted) ToolHost.openToolIfKnown(context, 'help');
        return;
      }
      final matches = matchCommands(buildCommandRegistry(), parsed.token);
      if (matches.isNotEmpty) await _selectCommand(matches.first);
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _composer.clear();
    await ref.read(journalProvider.notifier).addText(trimmed);
  }
```

Add a widget test for Enter: `enterText('/name'); await tester.testTextInput.receiveAction(TextInputAction.done)` (or tap `Key('journal-send')`); newest entry sourceTool 'gen-details'.

Imports already present from phase 1: `command_registry.dart`, `tool_host.dart`.

NOTE on the odds-chip widget-test: the fate test taps `slash-cmd-fate-juice` (expands), then `slash-odds-likely`. Ensure both keys exist as written.

NOTE house gotcha: AppTheme.light() FilledButton has infinite min width in a Row — the palette uses `ListTile`/`ActionChip`/`Wrap`, no FilledButton Rows, so it's safe.

- [ ] **Step 4: Run until green**

Run: `flutter test test/slash_palette_test.dart`
Expected: all pass.

- [ ] **Step 5: Full gates**

Run: `flutter analyze` → exactly 1 info (models.dart:2).
Run: `flutter test` → full suite green (fix any journal test that asserted the composer sends `/`-leading text as a note — none expected).

- [ ] **Step 6: Commit**

```bash
git add lib/features/journal_screen.dart test/slash_palette_test.dart
git commit -m "feat: slash command palette in the journal composer"
```

---

### Task 4: Docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1:** Add under the dice/structured-entries note:

```markdown
- Slash commands: type `/` in the journal to roll a fate check, dice, or a
  quick generator without opening a tool — the result lands inline.
```

- [ ] **Step 2:** `flutter analyze` (baseline), `flutter test` (green).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README note for slash commands"
```

---

## Self-review notes

- Spec §3 coverage: leading-`/` detection (Task 1 parseSlash + Task 3 listener), filtered command list (matchCommands), odds picker chips (fate commands), dice notation passthrough (`/dice` rest), inline structured entry (no panel — `_runCommand` → addResult), `/scene` + `/help` built-ins, dismiss on clear. System-scoping is deferred to phase 4 (palette shows all registry commands now — explicit).
- Keyboard nav (Down/Up/Enter) is NOT in this plan — tap + the natural TextField submit are covered; arrow-key navigation deferred unless verify shows it's needed (note in PR). [Spec said "keyboard navigable"; flag this as a scoped deviation — tap + Enter-to-first-match is the v1; full arrow nav is a fast-follow if verify demands it.]
- Type names consistent: parseSlash, matchCommands, _runCommand, _selectCommand, _SlashRow, _slashActive, keys slash-palette/slash-cmd-<id>/slash-odds-<o>/slash-cmd-scene/slash-cmd-help.
- No placeholder steps; all code shown.
