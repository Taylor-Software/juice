# Global light timer

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

Shadowdark's torch (a light-pressure countdown) lives on the Shadowdark
*character* sheet. The same light-pressure mechanic is useful in **any**
campaign / system (e.g. a Nimble dungeon crawl), but there's no campaign-wide
light timer. Add a **global, per-campaign light timer** surfaced in the
always-visible HUD, available in every session regardless of enabled systems.

## Decisions (from brainstorming)

- **Campaign-wide**, not a character-sheet field — session-scoped state.
- Surfaced in the **HUD** (`play_context_hud.dart`) beside the Chaos chip, but
  **ungated** (every campaign, every verb, all session types).
- A neutral player-controlled −/+ countdown with a lit/out indicator. **No
  rulebook duration asserted** (facts-only, exactly like the Shadowdark torch).
- The Shadowdark per-*character* torch stays as-is; this is additive.

## Architecture

### 1. State — `lib/state/providers.dart`

A session-scoped `int` provider, mirroring the `DecksNotifier`/`GmChatNotifier`
pattern (but the payload is a bare int, persisted as a string):

```dart
class LightNotifier extends AsyncNotifier<int> {
  static const _baseKey = 'juice.light.v1';
  late String _scopedKey;

  @override
  Future<int> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    return int.tryParse(prefs.getString(_scopedKey) ?? '') ?? 0;
  }

  Future<void> set(int value) async {
    final v = value.clamp(0, 9999);
    state = AsyncData(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, '$v');
  }
}

final lightProvider =
    AsyncNotifierProvider<LightNotifier, int>(LightNotifier.new);
```

Register `'juice.light.v1'` in `sessionScopedKeys` (so it persists per campaign
AND exports/imports with the campaign file — the export iterates
`sessionScopedKeys`).

### 2. HUD control — `lib/shared/play_context_hud.dart`

In `build`, read `final light = ref.watch(lightProvider).valueOrNull ?? 0;`. In
the HUD's chip `Wrap` (where the Chaos `InputChip` + `hdr-chaos-dec`/`inc`
steppers live), add an **ungated** light control (NOT inside the
`if (usesMythic …)` block) — a flame `InputChip` + dec/inc steppers:

```dart
                  InputChip(
                    avatar: Icon(Icons.local_fire_department,
                        size: 16,
                        color: light > 0
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant),
                    label: Text(light > 0 ? 'Light $light' : 'Light: out'),
                    onPressed: null,
                  ),
                  IconButton(
                    key: const Key('hdr-light-dec'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: light > 0
                        ? () => ref.read(lightProvider.notifier).set(light - 1)
                        : null,
                  ),
                  IconButton(
                    key: const Key('hdr-light-inc'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () =>
                        ref.read(lightProvider.notifier).set(light + 1),
                  ),
```

(`theme` is already in scope in the HUD build; confirm and reuse it.) Shown when
the HUD isn't collapsed — the same visibility as the Chaos chip.

## Testing

- `lightProvider` unit test (`ProviderContainer` + mock prefs): `set(3)` →
  `valueOrNull == 3`; a fresh container reads back `3` (persisted, scoped key);
  `set(-1)` clamps to `0`.
- `'juice.light.v1'` is in `sessionScopedKeys` (so it exports).
- `campaign_header_test` (pumps `CampaignHeader` directly): `hdr-light-inc`
  raises the light to `1` and the chip reads `Light 1`; `hdr-light-dec` lowers
  it; at `0` the chip reads `Light: out` and `hdr-light-dec` is disabled.

## Out of scope (YAGNI)

- Auto-decrement on scene/turn advance; multiple named light sources; a light
  type/duration picker; a sound/animation; replacing the Shadowdark sheet torch;
  a per-character global light.

## Files touched

| File | Change |
|------|--------|
| `lib/state/providers.dart` | `LightNotifier`/`lightProvider`; `'juice.light.v1'` in `sessionScopedKeys` |
| `lib/shared/play_context_hud.dart` | the ungated light chip + dec/inc steppers |
| tests | `lightProvider` round-trip + scoped-key; `campaign_header` light-chip |
| `CLAUDE.md` | note the global light timer on the HUD bullet |
