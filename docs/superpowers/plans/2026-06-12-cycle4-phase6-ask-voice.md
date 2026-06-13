# Cycle 4 Phase 6: Ask-Anything + Voice-Everywhere Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ask the oracle a natural-language question from the composer and get an answer in one entry (C1); voice any dialog-shaped journal entry through the on-device interpreter (C4).

**Architecture:** Ask-anything detects a trailing `?` (or `/ask`), shows an odds picker scoped to the campaign's `defaultOracle`, runs the matching fate command, and logs ONE entry titled with the question. Voice-everywhere adds a "Voice…" entry action (gated on interpreter-supported + dialog-shaped) that builds a `VoiceSeed` from the entry and reuses the existing `voiceLine` seam. No new interpreter methods — the optional LLM `suggestOdds` is deferred (manual odds with a sensible default).

**Tech Stack:** Flutter + flutter_riverpod. House rules: TDD; format hook; analyze baseline exactly 1 info; never construct GemmaInterpreterService in tests (FakeInterpreterService via interpreterServiceProvider override); commits exact, no co-author. Lost-update rule on read-modify-write.

**Branch:** `cycle4-phase6-ask-voice` off main (after phase 5 merges). Plan committed first.

**Spec:** docs/superpowers/specs/2026-06-12-cycle4-living-journal-design.md §7 (C1, C4).

---

### Task 1: Ask-anything — question chip + odds picker + one-entry flow

**Files:**
- Modify: `lib/features/journal_screen.dart`
- Test: `test/ask_anything_test.dart`

**Context (shipped):**
- `settingsProvider` → `CampaignSettings.defaultOracle` ('juice'|'mythic'|'roll-high').
- `buildCommandRegistry()` + `commandById`; commands `fate-juice` (odds = Likelihood.key: unlikely/normal/likely), `fate-mythic` (odds ∈ kMythicOdds, +chaos arg), `fate-roll-high` (odds ∈ kRollHighOdds). `_runCommand`/`commandById` exist in journal_screen (phase 2). `CommandResult{title,body,payload}`.
- Composer listener `_onComposerChanged` + `_slashActive`/`_mentionQuery` state; built-in slash set `_builtinScene`/`_builtinHelp`.

- [ ] **Step 1: Failing tests** — pump JournalScreen with a real Oracle override + FakeInterpreter (mirror slash_palette_test). Cases:
  - Typing a question ending in `?` shows an "Ask the oracle" chip (Key('ask-chip')); plain text shows none.
  - Tapping the chip opens an odds picker; for a juice-default campaign the options are Unlikely/Normal/Likely (keys ask-odds-unlikely/normal/likely). Picking 'Likely' logs ONE entry whose title is the question text and whose payload command is 'fate-juice' with args odds 'likely'; the composer clears.
  - `/ask Is the door locked?` (slash built-in) shows in the slash palette (Key('slash-cmd-ask')) and on select opens the same odds picker.
  - A mythic-default campaign's picker shows kMythicOdds options (seed sessions with `"systems"` containing mythic + settings defaultOracle 'mythic').

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

Add `_oracleCommandId` + odds option helpers keyed off defaultOracle:
```dart
  String get _defaultOracle =>
      ref.read(settingsProvider).valueOrNull?.defaultOracle ?? 'juice';

  String _fateCommandId(String oracle) => switch (oracle) {
        'mythic' => 'fate-mythic',
        'roll-high' => 'fate-roll-high',
        _ => 'fate-juice',
      };

  List<String> _oddsOptions(String oracle) => switch (oracle) {
        'mythic' => kMythicOdds,
        'roll-high' => kRollHighOdds,
        _ => const ['unlikely', 'normal', 'likely'],
      };

  String _defaultOdds(String oracle) => switch (oracle) {
        'mythic' => '50/50',
        'roll-high' => 'Unknown',
        _ => 'normal',
      };

  String _oddsLabel(String o) =>
      o.isEmpty ? o : '${o[0].toUpperCase()}${o.substring(1)}';
```

Question detection in `_onComposerChanged` (alongside slash/mention; suppressed when slash-active or mention-active):
```dart
    final isQuestion = !slash && mention == null &&
        text.trim().endsWith('?') && text.trim().length > 1;
    setState(() {
      _slashActive = slash;
      _mentionQuery = mention;
      _askActive = isQuestion;
    });
```
(Add `bool _askActive = false;`.)

Render an "Ask the oracle" chip above the composer when `_askActive` (and not slash/mention):
```dart
  Widget _askChip() => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: ActionChip(
            key: const Key('ask-chip'),
            avatar: const Icon(Icons.psychology_alt_outlined, size: 18),
            label: const Text('Ask the oracle'),
            onPressed: () => _ask(_composer.text.trim()),
          ),
        ),
      );
```
Render order above the composer: `if (_slashActive) _slashPalette() else if (_mentionQuery != null) _mentionPanel() else if (_askActive) _askChip()`.

`_ask(question)`: pick odds, run the default-oracle fate command, log ONE entry titled with the question:
```dart
  Future<void> _ask(String question) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null || question.isEmpty) return;
    final ora = _defaultOracle;
    final opts = _oddsOptions(ora);
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('How likely?'),
        children: [
          for (final o in opts)
            SimpleDialogOption(
              key: Key('ask-odds-$o'),
              onPressed: () => Navigator.pop(context, o),
              child: Text(_oddsLabel(o)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final cmd = commandById(buildCommandRegistry(), _fateCommandId(ora))!;
    final args = <String, String>{'odds': picked};
    if (cmd.id == 'fate-mythic') {
      args['chaos'] = '${ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5}';
    }
    final r = cmd.run(oracle, args);
    _composer.clear();
    // The question is the entry title; the rolled answer is the body/payload.
    await ref.read(journalProvider.notifier).addResult(question, r.body,
        sourceTool: cmd.toolId, payload: r.payload);
  }
```

`/ask` slash built-in: in `_slashPalette`, add a row (Key('slash-cmd-ask')) when `'ask'.startsWith(token)`; on tap, take the rest of the slash text as the question (or focus the composer). Simplest: tapping `slash-cmd-ask` with rest text runs `_ask(parsed.rest)` when rest is non-empty, else clears `/ask ` and shows a hint. Also handle `'ask' == tok` in `_send`'s Enter path → `_ask(parsed.rest)`.

- [ ] **Step 4: Run until green.** Full `flutter test`.

- [ ] **Step 5: Commit.** `git commit -m "feat: ask-anything — NL question to a one-entry oracle answer"`

---

### Task 2: Voice-everywhere — voice any dialog-shaped entry

**Files:**
- Modify: `lib/features/journal_screen.dart`
- Test: `test/voice_everywhere_test.dart`

**Context (shipped):**
- `InterpreterService.voiceLine(VoiceSeed)` → Future<String>; `VoiceSeed(line, mood, {tone, topic, characterName, characterTags, genre, toneSetting, journalContext})`.
- The journal already gates Interpret on `ref.read(interpreterServiceProvider).status.value.phase != InterpreterPhase.unsupported` (see `canInterpret` in `_entry`).
- `relatedEntries(entries, entry)` (journal_search) gives recall context; `_sceneContext()` exists. settings genre/tone via settingsProvider.
- FakeInterpreterService has `queuedVoice`/`lastVoiceSeed`/`voiceError`/`voiceCalls` scripting (test/fake_interpreter.dart).

- [ ] **Step 1: Failing tests** — pump with FakeInterpreterService (status ready; script `queuedVoice = 'I will not.'`). Cases:
  - An entry whose body contains a quote (`"Stand down."`) shows a "Voice…" menu item; invoking it calls voiceLine and appends the voiced line to the entry body (re-read fresh). Assert the fake's `lastVoiceSeed.line` carries the entry text and the entry body now contains 'I will not.'.
  - A non-dialog entry (no quotes, sourceTool 'dice') does NOT show "Voice…".
  - When the interpreter is unsupported (FakeInterpreterService status unsupported), "Voice…" is absent even on a dialog entry.

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

Dialog-shaped predicate + menu item in `_entry`:
```dart
  bool _isDialogShaped(JournalEntry e) =>
      e.body.contains('"') || e.sourceTool == 'gen-npcs' ||
      e.sourceTool == 'sidekick-dialogue';

  bool get _canVoice =>
      ref.read(interpreterServiceProvider).status.value.phase !=
      InterpreterPhase.unsupported;
```
In the menu itemBuilder, add:
```dart
        if (_canVoice && _isDialogShaped(e))
          const PopupMenuItem(value: 'voice', child: Text('Voice…')),
```
Handle in `_onAction`:
```dart
      case 'voice':
        await _voiceEntry(entry);
```
`_voiceEntry`:
```dart
  Future<void> _voiceEntry(JournalEntry entry) async {
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const CampaignSettings();
    final related = relatedEntries(
        ref.read(journalProvider).valueOrNull ?? const [], entry);
    final seed = VoiceSeed(
      line: entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
      mood: 'default',
      genre: settings.genre,
      toneSetting: settings.tone,
      journalContext: [
        for (final e in related)
          e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
      ],
    );
    String? voiced;
    try {
      voiced = await ref.read(interpreterServiceProvider).voiceLine(seed);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not voice: $e')));
      return;
    }
    if (voiced.trim().isEmpty || !mounted) return;
    final fresh = (ref.read(journalProvider).valueOrNull ?? const [])
        .where((x) => x.id == entry.id)
        .firstOrNull;
    if (fresh == null) return;
    await ref.read(journalProvider.notifier).replace(
        fresh.copyWith(body: '${fresh.body}\n\n— Voiced: $voiced'));
  }
```
Imports: `../engine/oracle_interpreter.dart` (VoiceSeed), `../engine/journal_search.dart` (relatedEntries) — check which are already imported (journal_search's relatedEntries is used by _interpret, so it's likely imported; oracle_interpreter likely too).

- [ ] **Step 4: Run until green.** Full `flutter test` + analyze.

- [ ] **Step 5: Commit.** `git commit -m "feat: voice any dialog-shaped journal entry via the interpreter"`

---

### Task 3: Docs

- [ ] **Step 1:** README note:
```markdown
- Ask anything: end a journal line with `?` (or `/ask`) and the oracle answers using your campaign's default oracle — question and answer land in one entry. Any line with dialogue can be **voiced** in character by the on-device model.
```
- [ ] **Step 2:** `flutter analyze` + `flutter test` green.
- [ ] **Step 3: Commit.** `git commit -m "docs: README note for ask-anything and voice"`

---

## Self-review notes

- Spec §7 C1 coverage: trailing-`?` detection + `/ask`, odds picker scoped to defaultOracle, one entry (question as title, answer payload), optional Interpret reuses the existing entry menu (already present on result entries). LLM `suggestOdds` DEFERRED (manual odds + sensible default) — explicit descope, noted in PR; the substance (NL question → oracle answer in one flow) ships.
- Spec §7 C4 coverage: "Voice…" on dialog-shaped entries (quote OR npc/sidekick source), gated on interpreter-supported, reuses VoiceSeed/voiceLine, appends like a reading, lost-update-safe re-read.
- Graceful degradation: no model → no "Voice…" item, ask-anything still works (manual odds).
- Mutual exclusivity above the composer: slash > mention > ask (only one renders).
- Type names: _ask, _askActive, _voiceEntry, _isDialogShaped, _canVoice, _fateCommandId/_oddsOptions/_defaultOdds, keys ask-chip/ask-odds-<o>/slash-cmd-ask.
- Deferred: LLM suggestOdds; voice retry dialog (snackbar error is enough for v1; the Sidekick tool keeps its richer retry).
