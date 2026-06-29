# Loop-Aware Suggestion Chips — Design

**Date:** 2026-06-29
**Status:** Approved (brainstorming)
**Context:** Deferred follow-up from the Solo Loop + Success Tally feature
(`docs/superpowers/specs/2026-06-29-solo-loop-success-tally-design.md`). Surfaces the
solo loop's signature moves as one-tap suggestion chips so the player can run the loop
without opening the Loop subtab.

## Summary

Add two loop-aware chips to the rule-based `SuggestionEngine`:

- **`ask-yes-no`** (inline) — a direct one-tap **d10 solo yes/no** (even odds) that logs
  a `solo-loop` reading. Renders in the journal's **InlineRollDock** beside Roll
  oracle / Inspire.
- **`roll-tally`** (navigate) — appears only when a thread has a Success Tally; taps to
  **Track → Threads** (where tallies render + roll). Renders in the **assistant rail**.

No Word Oracle chip: it is already reachable via the dock's existing **Inspire** chip,
which opens `GenerateSheet` (now containing the Word Oracle). Avoiding a redundant chip.

## Architecture findings (existing code)

- `lib/engine/suggestions.dart` — pure `suggestionsFor({...booleans})` returns a
  `List<Suggestion>` (`{id, label, action: inline|navigate}`). `rollInlineSuggestion`
  runs the inline ids (`roll-oracle` → fate check, `scene-event` → random event).
- The **rail** (`assistant_rail.dart`) renders only `action == navigate` chips
  (`_onTap` maps each id → `route.goTo(...)`). Inline ids are NOT rendered there.
- The **InlineRollDock** (`inline_roll_dock.dart`) hand-picks specific inline ids to
  render (`roll-oracle`, `scene-event`) plus a hardcoded **Inspire** chip
  (`showGenerateSheet`). It is NOT a generic "render all inline suggestions" widget —
  new inline chips must be added explicitly.
- The AI ranking seam (#5) builds candidates from the live suggestion list
  (`[for (final s in candidates) (id: s.id, label: s.label)]`) and `applyRanking` is
  tolerant of unknown/omitted ids — so new chips ride along with no change.

## Changes

### 1. `lib/engine/suggestions.dart`

Add a `hasTally` parameter and two chips. Final `suggestionsFor`:

```dart
List<Suggestion> suggestionsFor({
  required bool hasScenes,
  required bool hasOpenThreads,
  required bool encounterActive,
  required bool ironswornFamily,
  required bool hasFocusCharacter,
  required bool hasTally,
}) {
  return [
    const Suggestion('roll-oracle', 'Roll the oracle', SuggestionAction.inline),
    const Suggestion('ask-yes-no', 'Ask yes/no', SuggestionAction.inline),
    if (hasScenes)
      const Suggestion('scene-event', 'Scene event', SuggestionAction.inline)
    else
      const Suggestion('start-scene', 'Start a scene', SuggestionAction.navigate),
    if (hasOpenThreads)
      const Suggestion('advance-thread', 'Advance a thread', SuggestionAction.navigate),
    if (hasTally)
      const Suggestion('roll-tally', 'Roll a task', SuggestionAction.navigate),
    if (encounterActive)
      const Suggestion('combat-turn', 'Take a turn', SuggestionAction.navigate),
    if (ironswornFamily && hasFocusCharacter)
      const Suggestion('make-move', 'Make a move', SuggestionAction.navigate),
    const Suggestion('develop-rumor', 'Develop a rumor', SuggestionAction.navigate),
    const Suggestion('seed-npc', 'Add an NPC', SuggestionAction.navigate),
  ];
}
```

`ask-yes-no` sits right after `roll-oracle` (the two core "ask the oracle" rolls);
`roll-tally` sits after `advance-thread` (both are thread/task moves). Order is the
rule-based fallback only — the AI rank reorders by relevance.

### 2. `lib/state/suggestions_provider.dart`

Compute and pass `hasTally`:

```dart
    hasTally: threads.any((t) => t.tally != null),
```

(`threads` is already read in this provider; `Thread.tally` exists.)

### 3. `rollInlineSuggestion` (`suggestions_provider.dart`)

Add the `ask-yes-no` case (imports: `solo_oracle.dart`). `Oracle` exposes a public
`final Dice dice`, reused so the roll shares the oracle's RNG:

```dart
    case 'ask-yes-no':
      final g = soloYesNo(SoloLikelihood.even, oracle.dice).toGenResult();
      return ref.read(journalProvider.notifier).addResult(g.title, g.asText,
          sourceTool: 'solo-loop', payload: g.toPayload());
```

Even odds is the rail/dock default; the Loop subtab keeps the full likelihood picker.

### 4. `lib/features/inline_roll_dock.dart`

Render an **Ask yes/no** chip when the suggestion is present (mirrors the `scene-event`
pattern — `byId('ask-yes-no')`, then a `chip(...)` calling `_roll`):

```dart
    final askYesNo = byId('ask-yes-no');
    // ...inside the Row, after the scene-event chip / near Inspire:
    if (askYesNo != null)
      chip(
        key: const Key('dock-ask-yes-no'),
        label: '? Yes/No',
        bg: tk.selected,
        fg: tk.terracottaDeep,
        onTap: () => _roll(ref, askYesNo),
      ),
```

`_roll` already calls `rollInlineSuggestion` + the optional `onRolled` scroll callback.

### 5. `lib/features/assistant_rail.dart`

Add the navigate case in `_onTap` (the rail already auto-renders any `navigate` chip):

```dart
      case 'roll-tally':
        route.goTo(Destination.track, subtab: 'threads');
```

## Testing

- `test/suggestions_test.dart` (extend) — `suggestionsFor`:
  - always contains `ask-yes-no` (inline), positioned right after `roll-oracle`.
  - contains `roll-tally` (navigate) iff `hasTally: true`; absent when false.
- `rollInlineSuggestion` (provider/widget test) — tapping `ask-yes-no` writes exactly one
  journal entry with `sourceTool == 'solo-loop'` and a `Yes/No` title. Follow the
  existing inline-dock/suggestions test setup (mock prefs + fixture oracle data per the
  rootBundle-hang rule; seed `Dice` for determinism).
- `test/inline_roll_dock_test.dart` (extend or add) — the `dock-ask-yes-no` chip renders
  and, on tap, logs a `solo-loop` entry.
- Rail navigate mapping — `roll-tally` → `goTo(track, 'threads')` (extend the existing
  rail `_onTap` coverage if present; otherwise assert via the suggestion's presence).

## Files touched

**Changed**
- `lib/engine/suggestions.dart` — `hasTally` param + `ask-yes-no`/`roll-tally` chips.
- `lib/state/suggestions_provider.dart` — `hasTally` wiring + `ask-yes-no` inline case.
- `lib/features/inline_roll_dock.dart` — Ask yes/no chip.
- `lib/features/assistant_rail.dart` — `roll-tally` navigate case.
- `test/suggestions_test.dart` (+ dock test) — coverage.

## Non-goals / deferred

- No Word Oracle chip (redundant with the Inspire chip → GenerateSheet → Word Oracle).
- No loop-state reordering of chips (the AI rank seam already orders by relevance).
- No AI auto-interpret of the logged yes/no roll (separate deferred item).
- No likelihood picker in the chip (even-odds default; the Loop subtab has the picker).
