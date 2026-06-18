# System Primer (rules→LLM, facts-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inject a tiny authored, facts-only per-system primer (setting descriptor + mechanic vocabulary) into the on-device oracle and voice prompts so readings honor the chosen TTRPG's flavor and vocabulary.

**Architecture:** A new pure-Dart `system_primer.dart` owns the authored primer strings and a `resolveSystemPrimer(systems, rulesets)` function (priority: dnd > shadowdark > Ironsworn-family, family refined by ruleset). A thin `systemPrimerProvider` resolves the active campaign's primer; three generation sites pass it into `OracleSeed`/`VoiceSeed`, whose prompt builders emit a `system:` INPUT line when non-empty. No vendored prose, no attribution.

**Tech Stack:** Dart, Flutter, flutter_riverpod, package:flutter_test. On-device interpreter (flutter_gemma) is untouched except for two one-clause instruction edits.

**Spec:** `docs/superpowers/specs/2026-06-17-system-primer-design.md`

---

### Task 1: `system_primer.dart` — content + resolution (TDD)

**Files:**
- Create: `lib/engine/system_primer.dart`
- Test: `test/system_primer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/system_primer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/system_primer.dart';

void main() {
  group('resolveSystemPrimer', () {
    test('dnd wins over a co-enabled ironsworn', () {
      final p = resolveSystemPrimer({'ironsworn', 'dnd'}, {'classic'});
      expect(p, kSystemPrimers['dnd']);
    });

    test('shadowdark wins over ironsworn', () {
      final p = resolveSystemPrimer({'ironsworn', 'shadowdark'}, {'classic'});
      expect(p, kSystemPrimers['shadowdark']);
    });

    test('ironsworn family refined by ruleset: sundered_isles', () {
      final p = resolveSystemPrimer({'ironsworn'}, {'classic', 'sundered_isles'});
      expect(p, kSystemPrimers['sundered_isles']);
    });

    test('ironsworn family refined by ruleset: starforged', () {
      final p = resolveSystemPrimer({'ironsworn'}, {'starforged'});
      expect(p, kSystemPrimers['starforged']);
    });

    test('ironsworn alone -> classic Ironsworn primer', () {
      final p = resolveSystemPrimer({'ironsworn'}, {'classic'});
      expect(p, kSystemPrimers['ironsworn']);
    });

    test('sundered_isles outranks starforged when both rulesets on', () {
      final p = resolveSystemPrimer({'ironsworn'}, {'starforged', 'sundered_isles'});
      expect(p, kSystemPrimers['sundered_isles']);
    });

    test('no covered system -> empty string', () {
      expect(resolveSystemPrimer({'juice', 'mythic', 'party'}, {}), '');
      expect(resolveSystemPrimer({}, {}), '');
    });
  });

  group('kSystemPrimers', () {
    test('every primer is non-empty and within the budget cap', () {
      expect(kSystemPrimers, isNotEmpty);
      for (final entry in kSystemPrimers.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
        expect(entry.value.length, lessThanOrEqualTo(kSystemPrimerMaxChars),
            reason: '${entry.key} exceeds kSystemPrimerMaxChars');
      }
    });

    test('covers the five sheet systems', () {
      expect(kSystemPrimers.keys, containsAll(
          ['ironsworn', 'starforged', 'sundered_isles', 'dnd', 'shadowdark']));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/system_primer_test.dart`
Expected: FAIL — `system_primer.dart` does not exist / `kSystemPrimers` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/engine/system_primer.dart`:

```dart
/// Authored, facts-only per-system primers fed into the oracle and voice
/// prompts (see lib/engine/oracle_interpreter.dart). Each line is a setting
/// descriptor plus the system's core resolution vocabulary — non-copyrightable
/// game-mechanic facts, NOT rulebook prose. No attribution, no logos, no
/// taglines (see docs spec + memory/licensing-constraint). Pure Dart.
library;

/// Budget guard: each primer stays short so the worst-case oracle prompt fits
/// the web model's ~1280-token context (spec "Token budget"). A test pins it;
/// no runtime truncation — these are authored constants, not user data.
const int kSystemPrimerMaxChars = 220;

const Map<String, String> kSystemPrimers = {
  'ironsworn':
      'Ironsworn: grim, mythic low-fantasy survival in the Ironlands, ruled by sworn vows. Resolution: action die +stat vs two challenge dice → strong/weak hit or miss; momentum; pay the price.',
  'starforged':
      'Starforged: hardscrabble space opera in a lawless frontier sector. Resolution: action die +stat vs two challenge dice → strong/weak hit or miss; momentum; pay the price.',
  'sundered_isles':
      'Sundered Isles: supernatural age-of-sail adventure across haunted, sundered seas. Resolution: action die +stat vs two challenge dice → strong/weak hit or miss; momentum; pay the price.',
  'dnd':
      'D&D 5e: heroic high fantasy. Resolution: d20 + modifier vs DC or AC; advantage/disadvantage; saving throws; conditions; hit points and death saves.',
  'shadowdark':
      'Shadowdark: lethal, gritty old-school dungeon-crawling where light and time are deadly resources. Resolution: d20 + modifier vs DC or AC; real-time torches; luck tokens; swift death.',
};

/// Resolves a campaign's enabled [systems] + [rulesets] to one primer, or ''
/// when no covered TTRPG system is enabled. Priority: dnd > shadowdark >
/// Ironsworn-family. The Ironsworn family shares the `ironsworn` campaign flag,
/// so it is refined by the enabled ruleset (sundered_isles > starforged >
/// classic).
String resolveSystemPrimer(Set<String> systems, Set<String> rulesets) {
  if (systems.contains('dnd')) return kSystemPrimers['dnd']!;
  if (systems.contains('shadowdark')) return kSystemPrimers['shadowdark']!;
  if (systems.contains('ironsworn')) {
    if (rulesets.contains('sundered_isles')) {
      return kSystemPrimers['sundered_isles']!;
    }
    if (rulesets.contains('starforged')) return kSystemPrimers['starforged']!;
    return kSystemPrimers['ironsworn']!;
  }
  return '';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/system_primer_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/system_primer.dart test/system_primer_test.dart
git commit -m "feat(primer): authored facts-only system primers + resolver"
```

---

### Task 2: thread `systemPrimer` into the oracle prompt (TDD)

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart` (`OracleSeed` ctor + field; `buildOraclePrompt`; `oracleSystemInstruction` Rules list)
- Test: `test/oracle_interpreter_test.dart` (extend the `buildOraclePrompt` group)

- [ ] **Step 1: Write the failing tests**

Add these tests inside the existing `group('buildOraclePrompt', () {...})` in `test/oracle_interpreter_test.dart` (e.g. right after the `'carries result, genre, tone, scene'` test):

```dart
    test('systemPrimer renders a system: line between tone and result', () {
      const seed = OracleSeed(
        resultText: 'Fate Check — Yes',
        systemPrimer: 'D&D 5e: heroic high fantasy.',
      );
      final lines = buildOraclePrompt(seed).split('\n');
      final toneIdx = lines.indexWhere((l) => l.startsWith('tone:'));
      expect(lines[toneIdx + 1], 'system: D&D 5e: heroic high fantasy.');
      expect(lines.indexWhere((l) => l.startsWith('result:')),
          greaterThan(toneIdx + 1));
      expect(lines.last, 'OUTPUT:');
    });

    test('empty systemPrimer emits no system: line', () {
      const seed = OracleSeed(resultText: 'Story: Betrayal / Ally');
      expect(buildOraclePrompt(seed), isNot(contains('system:')));
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/oracle_interpreter_test.dart -p vm`
Expected: FAIL — `OracleSeed` has no `systemPrimer` named parameter (compile error).

- [ ] **Step 3: Implement**

In `lib/engine/oracle_interpreter.dart`, add the field + ctor param to `OracleSeed`. Change the constructor block:

```dart
  const OracleSeed({
    required this.resultText,
    this.genre = '',
    this.tone = '',
    this.sceneContext = '',
    this.journalContext = const [],
    this.systemPrimer = '',
  });
```

and add the field next to `tone` (after the `genre`/`tone` doc comment block, before `sceneContext`):

```dart
  /// Authored facts-only primer for the active TTRPG (see system_primer.dart),
  /// or '' for none. Renders as a `system:` line in the prompt.
  final String systemPrimer;
```

Then update `buildOraclePrompt`. Replace the final `return` block:

```dart
  final primer = _flat(seed.systemPrimer);
  final systemLine = primer.isEmpty ? '' : 'system: $primer\n';

  return 'INPUT:\n'
      'genre: ${_orElse(seed.genre, '(unspecified)')}\n'
      'tone: ${_orElse(seed.tone, '(unspecified)')}\n'
      '$systemLine'
      'result: ${_flat(seed.resultText)}\n'
      '$recall'
      'scene: ${_orElse(seed.sceneContext, '(none given)')}\n'
      'OUTPUT:';
```

Then teach the model the new key. In `oracleSystemInstruction`, in the `Rules:`
list, add a bullet immediately after the existing `recall:` bullet
(`- recall: lines are excerpts ... when they fit.`):

```
- system: line, when present, names the game's setting and core mechanics; honor its flavor and vocabulary in word choice.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/oracle_interpreter_test.dart -p vm`
Expected: PASS (existing tests still green — the exact-order recall test uses an empty primer, so no `system:` line appears there).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat(primer): system: line in oracle prompt + instruction clause"
```

---

### Task 3: thread `systemPrimer` into the voice prompt (TDD)

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart` (`VoiceSeed` ctor + field; `buildVoicePrompt`; `_voiceInstruction`)
- Test: `test/oracle_interpreter_test.dart` (extend the `buildVoicePrompt` group)

- [ ] **Step 1: Write the failing tests**

Add inside the existing `group('buildVoicePrompt', () {...})`:

```dart
    test('systemPrimer renders a system: line after tone', () {
      const seed = VoiceSeed(
        line: 'Hold the line!',
        mood: 'default',
        systemPrimer: 'Shadowdark: lethal old-school dungeon-crawling.',
      );
      final lines = buildVoicePrompt(seed).split('\n');
      final toneIdx = lines.indexWhere((l) => l.startsWith('tone:'));
      expect(lines[toneIdx + 1],
          'system: Shadowdark: lethal old-school dungeon-crawling.');
      expect(lines.last, 'OUTPUT:');
    });

    test('empty systemPrimer emits no system: line', () {
      const seed = VoiceSeed(line: 'Hi', mood: 'default');
      expect(buildVoicePrompt(seed), isNot(contains('system:')));
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/oracle_interpreter_test.dart -p vm`
Expected: FAIL — `VoiceSeed` has no `systemPrimer` named parameter.

- [ ] **Step 3: Implement**

In `VoiceSeed`, add the ctor param (after `journalContext`):

```dart
    this.journalContext = const [],
    this.systemPrimer = '',
  });
```

and the field (next to `genre`/`toneSetting`):

```dart
  /// Authored facts-only primer for the active TTRPG (see system_primer.dart),
  /// or '' for none. Renders as a `system:` line in the prompt.
  final String systemPrimer;
```

In `buildVoicePrompt`, after the existing `final topic = seed.topic;` line add:

```dart
  final primer = _flat(seed.systemPrimer);
  final systemLine = primer.isEmpty ? '' : 'system: $primer\n';
```

and insert `'$systemLine'` into the returned string immediately after the
`tone:` line and before the `character:` line:

```dart
  return '$_voiceInstruction\n\n'
      'INPUT:\n'
      'genre: ${_orElse(seed.genre, '(unspecified)')}\n'
      'tone: ${_orElse(seed.toneSetting, '(unspecified)')}\n'
      '$systemLine'
      '${name == null ? '' : 'character: ${_flat(name)}\n'}'
      '${seed.characterTags.isEmpty ? '' : 'traits: ${_flat(seed.characterTags.join(', '))}\n'}'
      'mood: ${_flat(seed.mood)}\n'
      '${tone == null ? '' : 'line tone: ${_flat(tone)}\n'}'
      '${topic == null ? '' : 'topic: ${_flat(topic)}\n'}'
      'line: ${_flat(seed.line)}\n'
      '$recall'
      'OUTPUT:';
```

Then teach the model the new key in `_voiceInstruction`. Insert a sentence
immediately after the existing `recall:` sentence (`... treat them as
established facts.`) and before `Output plain text only`:

```
system: line, when present, names the game's setting and mechanics — honor its flavor.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/oracle_interpreter_test.dart -p vm`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat(primer): system: line in voice prompt + instruction clause"
```

---

### Task 4: `systemPrimerProvider` (TDD)

**Files:**
- Modify: `lib/state/providers.dart` (add import + provider)
- Test: `test/system_primer_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/system_primer_provider_test.dart`. This overrides the upstream
async providers so no SharedPreferences / asset load is needed (see
memory/juice-widget-test-rootbundle-hang). Confirm the exact provider names
(`sessionsProvider`, `rulesetsProvider`) and state shape against
`lib/state/providers.dart` while writing — `sessionsProvider` yields a state
with `.activeMeta.enabledSystems`, `rulesetsProvider` yields a `Set<String>`.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/system_primer.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  test('systemPrimerProvider resolves dnd from the active session', () async {
    final container = ProviderContainer(overrides: [
      sessionsProvider.overrideWith(() => _FakeSessions(
            const SessionMeta(id: 's1', name: 'C', systems: ['dnd']),
          )),
      rulesetsProvider.overrideWith(() => _FakeRulesets(const {'classic'})),
    ]);
    addTearDown(container.dispose);
    // settle the async notifiers
    await container.read(sessionsProvider.future);
    await container.read(rulesetsProvider.future);
    expect(container.read(systemPrimerProvider), kSystemPrimers['dnd']);
  });

  test('systemPrimerProvider is empty for a non-TTRPG campaign', () async {
    final container = ProviderContainer(overrides: [
      sessionsProvider.overrideWith(() => _FakeSessions(
            const SessionMeta(id: 's1', name: 'C', systems: ['juice', 'mythic']),
          )),
      rulesetsProvider.overrideWith(() => _FakeRulesets(const {})),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);
    await container.read(rulesetsProvider.future);
    expect(container.read(systemPrimerProvider), '');
  });
}

class _FakeSessions extends SessionsNotifier {
  _FakeSessions(this._meta);
  final SessionMeta _meta;
  @override
  Future<SessionsState> build() async =>
      SessionsState(active: _meta.id, sessions: [_meta]);
}

class _FakeRulesets extends RulesetsNotifier {
  _FakeRulesets(this._enabled);
  final Set<String> _enabled;
  @override
  Future<Set<String>> build() async => _enabled;
}
```

Verified against source: `SessionsState({required String active, required
List<SessionMeta> sessions})` (in `lib/engine/models.dart`, with an
`activeMeta` getter); `SessionMeta({required id, required name, List<String>?
systems})`; `SessionsNotifier extends AsyncNotifier<SessionsState>` and
`RulesetsNotifier extends AsyncNotifier<Set<String>>` (both in
`lib/state/providers.dart`). The fakes above match these — keep them in sync if
the source changes.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/system_primer_provider_test.dart`
Expected: FAIL — `systemPrimerProvider` undefined.

- [ ] **Step 3: Implement**

In `lib/state/providers.dart`, add the import near the other engine imports:

```dart
import '../engine/system_primer.dart';
```

(`kAllSystems` is already available via the existing `models.dart` import.)

Add the provider (place it near `rulesetsProvider`):

```dart
/// The resolved facts-only system primer for the active campaign, or '' when
/// no covered TTRPG system is enabled. Fed into the oracle/voice prompts.
final systemPrimerProvider = Provider<String>((ref) {
  final systems = ref
          .watch(sessionsProvider)
          .valueOrNull
          ?.activeMeta
          .enabledSystems ??
      kAllSystems;
  final rulesets = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
  return resolveSystemPrimer(systems, rulesets);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/system_primer_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/system_primer_provider_test.dart
git commit -m "feat(primer): systemPrimerProvider resolves active campaign"
```

---

### Task 5: wire the three generation sites

**Files:**
- Modify: `lib/features/oracle_interpretation_sheet.dart` (`_generate`, ~line 78)
- Modify: `lib/features/journal_screen.dart` (`_voiceEntry`, ~line 1243)
- Modify: `lib/features/sidekick_screen.dart` (voiceLine call, ~line 328)

No new test here — Task 4 covers resolution and Tasks 2–3 cover prompt
rendering. This is pure plumbing of an already-tested provider into
already-tested seeds. The full widget suite (Task 6) guards against regressions.

- [ ] **Step 1: oracle interpretation sheet**

In `lib/features/oracle_interpretation_sheet.dart`, in `_generate`, add the
field to the `OracleSeed(...)` passed to `_service.interpret`:

```dart
      final cards = await _service.interpret(OracleSeed(
        resultText: widget.seed.resultText,
        genre: settings.genre,
        tone: settings.tone,
        sceneContext: widget.seed.sceneContext,
        journalContext: widget.seed.journalContext,
        systemPrimer: ref.read(systemPrimerProvider),
      ));
```

- [ ] **Step 2: journal screen voice**

In `lib/features/journal_screen.dart`, in `_voiceEntry`, add to the
`VoiceSeed(...)`:

```dart
    final seed = VoiceSeed(
      line: entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
      mood: 'default',
      genre: settings.genre,
      toneSetting: settings.tone,
      systemPrimer: ref.read(systemPrimerProvider),
      journalContext: [
        for (final e in related)
          e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
      ],
    );
```

- [ ] **Step 3: sidekick screen voice**

In `lib/features/sidekick_screen.dart`, in the `voiceLine(VoiceSeed(...))`
call (~line 328), add `systemPrimer: ref.read(systemPrimerProvider),` alongside
the existing `genre:`/`toneSetting:` fields.

- [ ] **Step 4: Confirm provider import + analyze**

All three files already import `lib/state/providers.dart` (they use
`interpreterServiceProvider` / `settingsProvider`). Verify the import exists in
each; add it if any is missing.

Run: `flutter analyze`
Expected: No new issues (warnings clean).

- [ ] **Step 5: Commit**

```bash
git add lib/features/oracle_interpretation_sheet.dart lib/features/journal_screen.dart lib/features/sidekick_screen.dart
git commit -m "feat(primer): feed system primer into oracle + voice seeds"
```

---

### Task 6: docs, memory, full verify

**Files:**
- Modify: `CLAUDE.md` (project notes)
- Modify: `~/.claude/projects/-Users-johntaylor-StudioProjects-juice/memory/pre-made-character-sheets.md`

- [ ] **Step 1: CLAUDE.md project-notes bullet**

Add a bullet under "Project notes" (near the sheet bullets) describing the
primer. Example:

```markdown
- The on-device interpreter gets an authored, facts-only **system primer**
  (`lib/engine/system_primer.dart`): one line per sheet system (Ironsworn /
  Starforged / Sundered Isles / D&D 5e / Shadowdark) carrying a setting
  descriptor + core resolution vocabulary — non-copyrightable facts, NO
  rulebook prose/attribution. `resolveSystemPrimer(systems, rulesets)` picks one
  by priority (dnd > shadowdark > Ironsworn-family, family refined by ruleset);
  `systemPrimerProvider` resolves the active campaign's. It rides a `system:`
  INPUT line in the oracle + voice prompts (NOT recap), kept tiny
  (`kSystemPrimerMaxChars`) for the web model's ~1280-token budget. See
  `docs/superpowers/specs/2026-06-17-system-primer-design.md`.
```

- [ ] **Step 2: Update memory**

In `memory/pre-made-character-sheets.md`, change the Slice B line from
"pending" to shipped:

> - **Slice B — rules→LLM (shipped, facts-only).** Authored per-system primer
>   (`lib/engine/system_primer.dart`): setting descriptor + mechanic vocabulary
>   per sheet system, resolved by `resolveSystemPrimer` / `systemPrimerProvider`,
>   injected as a `system:` line into the oracle + voice prompts. No quoted
>   rulebook prose (per [[licensing-constraint]]).

- [ ] **Step 3: Full verify**

Run: `flutter analyze`
Expected: clean (no new warnings/errors).

Run: `flutter test`
Expected: all tests pass (prior count + the new `system_primer_test.dart`,
`system_primer_provider_test.dart`, and the 4 added prompt-builder tests).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(primer): document system primer in project notes"
```

(The memory file lives outside the repo; it is saved, not committed.)

- [ ] **Step 5: Open the PR**

```bash
git push -u origin feat/system-primer
gh pr create --title "System primer (rules→LLM, facts-only)" --body "<summary + test evidence>"
```

---

## Self-Review

**Spec coverage:**
- Content + resolution (5 systems, ruleset-refined) → Task 1. ✓
- Wiring provider → Task 4; three call sites → Task 5. ✓
- Seeds + prompt builders + instruction clauses (oracle + voice) → Tasks 2–3. ✓
- Token budget guard (`kSystemPrimerMaxChars` + test) → Task 1. ✓
- Tests (resolution, prompt lines) → Tasks 1–4. ✓
- Docs + memory → Task 6. ✓
- Licensing (facts-only, no attribution) → enforced by authored strings in Task 1; documented Task 6. ✓
- Out of scope (recap, per-character voice precision) → not implemented. ✓

**Placeholder scan:** Task 4's fakes carry an explicit "match real constructor names" note rather than a placeholder — the implementer verifies `SessionsState`/`SessionMeta`/`RulesetsNotifier` signatures against source (they are not fully shown in the spec). All other steps have complete code.

**Type consistency:** `systemPrimer` (field), `systemPrimerProvider`, `resolveSystemPrimer(Set<String>, Set<String>)`, `kSystemPrimers`, `kSystemPrimerMaxChars` used identically across tasks. Prompt line key is `system:` everywhere.
