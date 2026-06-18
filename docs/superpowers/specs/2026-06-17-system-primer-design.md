# System Primer (rules→LLM, facts-only) — Design

**Date:** 2026-06-17
**Status:** Approved
**Slice:** B of the pre-made-character-sheets feature (A = sheet templates, C =
new d20 systems, both shipped). This is the "feed the game's rules to the LLM"
half of the original ask, recast within the licensing constraint.

## Problem

The original ask was to "include a PDF of the rules… to feed to the LLM" so a
chosen ruleset shapes play. That literal form is infeasible **and** out of
scope on licensing grounds:

- **Architecture.** The on-device interpreter (Gemma 3 1B web / Qwen 0.6B
  mobile, ~1280-token proven context, no network/RAG) cannot ingest a
  rulebook. It does exactly three things — oracle interpretation (4 lenses),
  sidekick voice lines, journal recap — none of which adjudicate rules.
- **Licensing.** Per `memory/licensing-constraint`, new content must be
  strictly facts-only: no vendored rulebook prose, no new attribution.

**Recast:** a tiny **authored, facts-only system primer** — one line per
system carrying a setting descriptor plus the system's core resolution
vocabulary — injected into the prompts where it changes the output. This nudges
the model's imagery and lets the *complication*/*foreshadow* lenses speak the
game's language, without quoting any rulebook.

## Scope

- **Payload:** flavor (setting descriptor) **+** mechanic vocabulary, one tight
  line per system.
- **Prompts fed:** oracle interpret **and** sidekick voice. Not recap (rules
  irrelevant to a past-tense summary).
- **Systems covered (5):** Ironsworn, Starforged, Sundered Isles, D&D 5e,
  Shadowdark — the systems with bespoke sheets. The base oracle/emulator tools
  (juice, mythic, party, verdant, lonelog, hexcrawl) are not TTRPG rulesets and
  get no primer.

Out of scope (YAGNI): per-character sheet-system precision for voice
(campaign-resolved is enough); recap prompt; any vendored data or picker.

## Content & resolution — `lib/engine/system_primer.dart` (new, pure Dart)

Owns both the authored strings and the resolution logic. No Flutter import, so
it is unit-testable in isolation like `oracle_interpreter.dart`.

```dart
/// Budget guard: each primer stays short so the worst-case prompt fits the
/// web model's ~1280-token context (see "Token budget"). A test pins this.
const int kSystemPrimerMaxChars = 220;

const Map<String, String> kSystemPrimers = {
  'ironsworn':      'Ironsworn: grim, mythic low-fantasy survival in the Ironlands, ruled by sworn vows. Resolution: action die +stat vs two challenge dice → strong/weak hit or miss; momentum; pay the price.',
  'starforged':     'Starforged: hardscrabble space opera in a lawless frontier sector. Resolution: action die +stat vs two challenge dice → strong/weak hit or miss; momentum; pay the price.',
  'sundered_isles': 'Sundered Isles: supernatural age-of-sail adventure across haunted, sundered seas. Resolution: action die +stat vs two challenge dice → strong/weak hit or miss; momentum; pay the price.',
  'dnd':            'D&D 5e: heroic high fantasy. Resolution: d20 + modifier vs DC or AC; advantage/disadvantage; saving throws; conditions; hit points and death saves.',
  'shadowdark':     'Shadowdark: lethal, gritty old-school dungeon-crawling where light and time are deadly resources. Resolution: d20 + modifier vs DC or AC; real-time torches; luck tokens; swift death.',
};

/// Resolve the campaign's enabled systems + rulesets to one primer, or ''.
/// Priority: dnd > shadowdark > Ironsworn-family. The family shares the
/// `ironsworn` campaign flag, so it is refined by the enabled ruleset
/// (sundered_isles > starforged > classic).
String resolveSystemPrimer(Set<String> systems, Set<String> rulesets) {
  if (systems.contains('dnd')) return kSystemPrimers['dnd']!;
  if (systems.contains('shadowdark')) return kSystemPrimers['shadowdark']!;
  if (systems.contains('ironsworn')) {
    if (rulesets.contains('sundered_isles')) return kSystemPrimers['sundered_isles']!;
    if (rulesets.contains('starforged'))     return kSystemPrimers['starforged']!;
    return kSystemPrimers['ironsworn']!;
  }
  return '';
}
```

All strings are authored setting descriptors + non-copyrightable mechanic
vocabulary — facts, not rulebook prose. The three Ironsworn-family entries
share resolution vocab (one engine); only the flavor clause differs.

## Wiring — one provider, three call sites

`lib/state/providers.dart`:

```dart
/// The resolved facts-only primer for the active campaign, or '' when no
/// covered TTRPG system is enabled.
final systemPrimerProvider = Provider<String>((ref) {
  final systems = ref.watch(sessionsProvider).valueOrNull?.activeMeta
          .enabledSystems ??
      kAllSystems;
  final rulesets = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
  return resolveSystemPrimer(systems, rulesets);
});
```

Read `ref.read(systemPrimerProvider)` (or `ref.watch` in build) at the three
generation sites and pass into the seed:

- `lib/features/oracle_interpretation_sheet.dart` `_generate` — oracle. (This
  is where genre/tone are already injected from settings; the primer joins
  them.)
- `lib/features/journal_screen.dart` `_voiceEntry` — voice.
- `lib/features/sidekick_screen.dart` voiceLine call — voice.

## Seeds & prompt builders — `lib/engine/oracle_interpreter.dart`

- Add `final String systemPrimer;` (default `''`) to `OracleSeed` and
  `VoiceSeed` ctors.
- `buildOraclePrompt` / `buildVoicePrompt`: emit one `system: <primer>` INPUT
  line **only when non-empty**, placed after the `tone:` line and before
  `result:` / `line:`, so the trailing `OUTPUT:` cue is never displaced. Run
  the value through the existing `_flat` (defensive; authored strings are
  already single-line).
- Add one short clause to each instruction so the small model uses the new key
  instead of ignoring it:
  - Oracle Rules list: `- system: line names the game's setting and core
    mechanics; honor its flavor and vocabulary in word choice.`
  - `_voiceInstruction`: append `system: line names the game's setting and
    mechanics — honor its flavor.`
- No few-shot example change: adding a `system:` line to an example would cost
  ~40 tokens in the latch-locked system block, which the budget can't spare.

## Token budget (the hard constraint)

Web model proven at 1280 total. Worst case:

| Part | tokens |
|------|-------:|
| system instruction + new clause | ~720 |
| output | ~250 |
| recall (2 × ~35) | ~70 |
| INPUT genre/tone/result/scene | ~130 |
| primer line (~180 chars) | ~45 |
| **total** | **~1215 < 1280** |

Primers are authored-short and `kSystemPrimerMaxChars` (+ a test) pins the cap
so a future edit can't blow the budget. No runtime truncation — these are
authored constants, not user data (unlike the recall block, which stays capped).

## Testing

`test/system_primer_test.dart`:
- `dnd` wins over a co-enabled `ironsworn`.
- `shadowdark` wins over `ironsworn`.
- `ironsworn` + `sundered_isles` ruleset → Sundered primer; `+ starforged` →
  Starforged; `ironsworn` alone → Ironsworn.
- No covered system → `''`.
- Every `kSystemPrimers` value is non-empty and ≤ `kSystemPrimerMaxChars`.

Prompt builder tests (extend the existing oracle_interpreter tests):
- `buildOraclePrompt` with a non-empty `systemPrimer` contains a `system:`
  line; with `''` it does not; `OUTPUT:` stays last.
- Same for `buildVoicePrompt`.

The `systemPrimerProvider` itself is a thin wrapper over the pure
`resolveSystemPrimer`, so it needs no dedicated provider test.

## Docs & memory

- CLAUDE.md project-notes bullet for `system_primer.dart`.
- Update `memory/pre-made-character-sheets` (Slice B shipped, facts-only).

## Licensing check

Descriptors are original wording; mechanic vocabulary is non-copyrightable
fact. No rulebook prose, no logos, no taglines, no attribution. Consistent with
`memory/licensing-constraint` (strictly facts-only for new content).
