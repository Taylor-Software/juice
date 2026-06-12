# Party Emulator Phase 4 (Sidekick Dialogue + Hexflower + Voice) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The last party-emulator slice: a **Sidekick Dialogue** tool (mood-keyed dialogue lines with doubles→mood-change, tone/topic/said-how chips, hexflower conversation walker) and the **"Voice this"** LLM action (`InterpreterService.voiceLine`).

**Spec:** docs/superpowers/specs/2026-06-12-party-emulator-design.md (§2 "Sidekick Dialogue", §4 "LLM voice"). Phases 1-3 shipped the data (incl. `sidekick.*`), `CharacterEmulation` (`mood`, `hexIndex`), and the fresh-read `_updateEmulation` pattern (party_emulator_screen.dart — REUSE it; never read-modify-write from build-captured state).

**Branch:** `feat/party-emulator-p4` off `main` (after PR #30 merges).

Hard rules: analyze exactly 1 pre-existing info (lib/engine/models.dart:2); suite green (current: 408); TDD; exact commit messages, no co-author lines; no new dependencies; never construct GemmaInterpreterService in tests (FakeInterpreterService only).

**Asset shape** (shipped): `sidekick.dialogue.{default,taciturn,savvy,high_strung,sassy,selfish}` keys '2'..'12'; `tone`/`topic`/`said_how_a`/`said_how_b` [6]; `hexflower.hexes` [19] `{index,q,r,topic,context:red|gray}`, `adjacency` index→neighbors, `directions` '2'..'12'→{N,NE,SE,S,SW,NW}, `direction_deltas`, `direction_tones`.

---

### Task 1: Engine — sidekick accessors + rollers (TDD)

**Files:**
- Modify: `lib/engine/emulator_data.dart`
- Modify: `lib/engine/party_emulator.dart`
- Tests: extend `test/emulator_data_test.dart`, `test/party_emulator_test.dart`

Binding API (emulator_data.dart):

```dart
List<String> get moods;                 // dialogue mood ids, stable order:
                                        // default, taciturn, savvy,
                                        // high_strung, sassy, selfish
String dialogueLine(String mood, int key); // 2-12; ArgumentError on unknown
List<String> get tones; topics; saidHowA; saidHowB; // each 6
HexInfo hex(int index);                 // {index, topic, context}; 0-18
List<int> hexNeighbors(int index);
String hexDirection(int key2d6);        // 'N'|'NE'|...
int? hexStep(int from, int key2d6);     // neighbor in that direction via
                                        // direction_deltas + q/r; null = off
                                        // the flower edge (UI: stay put)
```

Binding API (party_emulator.dart):

```dart
class DialogueResult {
  final (int, int) dice;     // the 2d6
  final bool moodChanged;    // doubles → mood changed BEFORE the line
  final String? newMood;     // set when moodChanged (d6 over moods)
  final int lineKey;         // the (re)rolled 2d6 sum used for the line
  final int toneIx, topicIx, saidHowAIx, saidHowBIx; // d6 indices 0-5
}

/// Per the source: roll 2d6; if doubles, first change mood (d6 over the
/// six moods), then reroll 2d6 for the line. Tone/topic/said-how roll
/// alongside. Dice order documented and pinned by tests:
/// 2d6 line → [d6 mood + 2d6 reroll when doubles] → d6 tone → d6 topic →
/// d6 saidHowA → d6 saidHowB.
DialogueResult rollDialogue(Dice dice);
```

- [ ] Steps: failing tests (moods order pinned; dialogueLine('default',2)
  == 'Look out!'; high_strung remap intact — pin one cell, e.g.
  dialogueLine('high_strung', 2) equals the asset's '2' entry read from
  file; unknown mood / key 1 / key 13 throw; tones[0] 'aggressive',
  topics[5] 'anecdote', saidHowA[5] 'neutrally', saidHowB[0] 'ruefully';
  hex(0) red fact, hex(6) gray need; adjacency symmetric spot-checks
  (0↔1..6); hexStep determinism: from 0 with key 12 ('N') lands on the
  northern ring-1 hex — derive expected from the asset's
  direction_deltas at test time (read the asset, don't hand-hardcode) —
  and an edge hex stepping outward returns null; rollDialogue seeded:
  non-doubles path (no mood change), doubles path (mood change + reroll),
  dice-order probe-replay across seeds per the p3 test pattern) →
  implement → gates →

```bash
git add lib/engine/emulator_data.dart lib/engine/party_emulator.dart test/emulator_data_test.dart test/party_emulator_test.dart
git commit -m "feat: sidekick engine — dialogue roller with mood change, hexflower walker"
```

---

### Task 2: voiceLine service seam (TDD)

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart` (VoiceSeed + prompt builder + plain-text parse)
- Modify: `lib/state/interpreter.dart` (abstract `voiceLine`)
- Modify: `lib/state/interpreter_gemma.dart` (real impl, mirrors interpret()'s session discipline)
- Modify: `test/fake_interpreter.dart` (scripting)
- Tests: extend `test/oracle_interpreter_test.dart` (or sibling)

Binding API (spec §4):

```dart
class VoiceSeed {
  final String line;            // the rolled dialogue line
  final String mood;            // mood id
  final String? tone, topic;    // chips when rolled
  final String? characterName;
  final List<String> characterTags;
  final String genre, toneSetting;        // campaign settings (as OracleSeed)
  final List<String> journalContext;      // recall lines (reuse relatedEntries
                                          // capping: kRecallMaxEntries/Chars)
}

String buildVoicePrompt(VoiceSeed seed); // compact (~150-token instruction):
  // expand the line into ONE in-character utterance, 1-2 sentences,
  // keep the line's intent + mood/tone, plain text only (no JSON).
String parseVoiceResponse(String raw);   // strip think-tags, trim;
                                         // empty -> FormatException
```

`InterpreterService.voiceLine(VoiceSeed) → Future<String>`. Gemma impl:
same single-flight/watchdog/stopGeneration-in-finally discipline as
interpret() (factor shared helpers only if minimal). Fake: `queuedVoice`
list + `lastVoiceSeed` capture, default canned line; widget tests use the
fake ONLY.

- [ ] Steps: failing tests (prompt contains line/mood/tone/genre/recall
  lines and the plain-text instruction; parse strips `<think>` and trims;
  empty/whitespace → FormatException; fake scripting works) → implement →
  gates →

```bash
git add lib/engine/oracle_interpreter.dart lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat: InterpreterService.voiceLine — compact in-character prompt + plain-text parse"
```

---

### Task 3: Sidekick Dialogue tool (TDD)

**Files:**
- Create: `lib/features/sidekick_screen.dart`
- Modify: `lib/shared/tool_registry.dart` ('sidekick-dialogue', group 'Party', AFTER party-emulator BEFORE behavior-tables, icon Icons.forum_outlined, badge 'PET')
- Tests: `test/sidekick_screen_test.dart`; tool_registry counts 16→17 base (17→18 family)

Screen (spec §2; two tabs via the house TabBar pattern — see
tracker_screen):

- **Dialogue tab**:
  - Character picker Key('sd-character') ('No one' = transient mood/hex,
    reuse the p3 transient pattern). Current mood line Key('sd-mood')
    ('Mood: Default'); persisted via emulation.mood (fresh-read updater).
  - Button Key('sd-roll') 'Roll line': `rollDialogue`; if moodChanged,
    persist the new mood first and show 'Mood changed → Sassy' in the
    result. Result card Key('sd-result'): the line (quoted), mood,
    'Tone: eager · Topic: a want/desire', 'Said: growled, tartly',
    dice line. Bookmark Key('sd-log') → title 'Sidekick — Default',
    body lines (character first when selected).
  - **Voice this** Key('sd-voice') on the result card: builds VoiceSeed
    (line, mood, tone/topic, character name+tags, campaign genre/tone
    from settings provider, journalContext via relatedEntries — mirror
    the journal Interpret wiring) → `voiceLine`. Busy spinner; result
    appended to the card Key('sd-voice-line') (quoted, italic); error →
    inline error text + retry button (small, sheet-style). Voiced line
    included in the journal body when logged after voicing.
    Gate the button exactly like the journal's Interpret action
    (interpreter enabled + state ready; reuse its provider checks).
- **Hexflower tab** Key('sd-hex-tab'):
  - CustomPaint flower (19 hexes from q/r — reuse hex-geometry math style
    from the wilderness map painter; small, read-only), current hex
    highlighted (emulation.hexIndex ?? 0 center), gray/red context
    colored, topic label on each hex.
  - Readout Key('sd-hex-readout'): 'Topic: need · Context: history
    (gray)' (red = current events). Button Key('sd-hex-step') 'Step
    (2d6)': roll 2d6 → direction; `hexStep`; null → 'Edge — stay put';
    crossing into the other color → note 'Context switch'. d3 priority
    chip ('Priority: me/you/us') rolled alongside per the source.
    Persist hexIndex (fresh-read updater). Bookmark Key('sd-hex-log') →
    title 'Hexflower — need', body with topic/context/priority/dice.
- Attribution footer (both lines).

- [ ] Steps: failing widget tests (fake interpreter via
  interpreterServiceProvider override; seeded Dice injection; cover:
  roll renders line+chips; doubles changes persisted mood and shows note;
  mood persists across character reselect; voice-this surfaces the
  fake's line and captures a VoiceSeed with the rolled line+mood+tags;
  voice error → retry visible; hex step persists hexIndex and renders
  readout; edge stay-put; journal entries for dialogue (incl. voiced
  line) and hex step; registry counts/placement) → implement → gates →

```bash
git add lib/features/sidekick_screen.dart lib/shared/tool_registry.dart test/sidekick_screen_test.dart test/tool_registry_test.dart
git commit -m "feat: Sidekick Dialogue tool — mood lines, hexflower walker, Voice this"
```

---

### Task 4: Docs

**Files:**
- Modify: `README.md` (Party paragraph: Sidekick dialogue + hexflower + on-device voicing sentence)

```bash
git add README.md
git commit -m "docs: Sidekick dialogue + voice on the Party toolkit"
```

---

## Verification (controller)

Browser: Sidekick → pick character → Roll line (chips render) → roll until
doubles (mood change persists) → hexflower tab → Step (context/topic
readout, persistence) → journal entries. Voice-this on web needs the real
model: verify the button gates correctly when the interpreter is off, and
(if the model is installed in the verify profile) one live voiceLine.
PR → CI → merge → spec status flip to shipped + ROADMAP party-emulator
section + memory update.
