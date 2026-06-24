# Global Light Timer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A campaign-wide, session-scoped light timer surfaced in the always-visible HUD — a neutral −/+ countdown with a lit/out indicator, available in every campaign regardless of system.

**Architecture:** A session-scoped `lightProvider` (int, `juice.light.v1.<sid>`, registered in `sessionScopedKeys` so it persists + exports); an ungated flame `InputChip` + dec/inc steppers in the HUD chip row (mirroring the Chaos chip, minus the `mythic` gate).

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test.

---

## File Structure

- **Modify** `lib/state/providers.dart` — `LightNotifier`/`lightProvider`; add `'juice.light.v1'` to `sessionScopedKeys`.
- **Modify** `lib/shared/play_context_hud.dart` — the ungated light chip + steppers.
- **Test** `test/light_provider_test.dart` (new); extend `test/campaign_header_test.dart`.
- **Modify** `CLAUDE.md`.

---

## Task 1: lightProvider (session-scoped) + export

**Files:** Modify `lib/state/providers.dart`; Test `test/light_provider_test.dart` (new).

- [ ] **Step 1: Write the failing test** — create `test/light_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('lightProvider: set persists (scoped) + clamps; default 0', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(lightProvider.future), 0);
    await c.read(lightProvider.notifier).set(3);
    expect(c.read(lightProvider).valueOrNull, 3);
    await c.read(lightProvider.notifier).set(-5);
    expect(c.read(lightProvider).valueOrNull, 0); // clamped

    await c.read(lightProvider.notifier).set(2);
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(await c2.read(lightProvider.future), 2); // persisted, scoped key
  });

  test('light key is session-scoped (exported with the campaign)', () {
    expect(sessionScopedKeys, contains('juice.light.v1'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/light_provider_test.dart`
Expected: FAIL — `lightProvider` undefined.

- [ ] **Step 3a: Add the notifier** — in `lib/state/providers.dart`, near `DecksNotifier`/`GmChatNotifier`, add:

```dart
// -- Light timer (campaign-wide, session-scoped, ungated) -------------------
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

- [ ] **Step 3b: Register the key** — in `lib/state/providers.dart`, add `'juice.light.v1',` to the `sessionScopedKeys` list (so it persists per campaign AND exports with the campaign file).

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/light_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/light_provider_test.dart
git commit -m "feat(light): session-scoped lightProvider (+ exported key)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: HUD light chip

**Files:** Modify `lib/shared/play_context_hud.dart`; Test `test/campaign_header_test.dart`.

- [ ] **Step 1: Write the failing test** — add to `test/campaign_header_test.dart` inside `void main()` (the `_pump(tester, data, prefs)` helper + `_prefs()` + `data` from `setUpAll`/`_loadData` already exist; mirror an existing test's shape):

```dart
  testWidgets('light timer: inc lights it, dec darkens, out at 0',
      (tester) async {
    await _pump(tester, data, _prefs()); // a bare campaign (no systems needed)
    // Default 0 -> "out", dec disabled.
    expect(find.text('Light: out'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('hdr-light-dec')))
            .onPressed,
        isNull);
    // Inc -> lit.
    await tester.tap(find.byKey(const Key('hdr-light-inc')));
    await tester.pumpAndSettle();
    expect(find.text('Light 1'), findsOneWidget);
    // Dec -> back to out.
    await tester.tap(find.byKey(const Key('hdr-light-dec')));
    await tester.pumpAndSettle();
    expect(find.text('Light: out'), findsOneWidget);
  });
```

(If `data` isn't a top-level/`setUpAll` variable in this file, read how the
existing tests obtain the `OracleData` and match it. `_prefs()` with no args
yields a bare session — confirm it produces a non-collapsed HUD; the existing
Chaos-chip test renders chips in the same harness, so the chip `Wrap` shows.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/campaign_header_test.dart`
Expected: FAIL — no `Light: out` / `hdr-light-inc`.

- [ ] **Step 3: Implement** — in `lib/shared/play_context_hud.dart`:

(a) in `build`, after the existing reads (where `theme`/`crawl` are read, ~line 47), add:
```dart
    final light = ref.watch(lightProvider).valueOrNull ?? 0;
```

(b) in the HUD's chip `Wrap` (the one holding the Chaos `InputChip` + `hdr-chaos-dec`/`inc`), add this **OUTSIDE** the `if (usesMythic …)` block (ungated — first in the `children`, before the `if (usesMythic …) ...[` Chaos block, so light shows for every campaign):

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

(`lightProvider` resolves via the existing `providers.dart` import; `theme` is in scope.)

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/campaign_header_test.dart`
Expected: PASS (the new test + all existing — the light chip is additive, the Chaos/oracle/thread chips are unchanged).

- [ ] **Step 5: Full verification**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/play_context_hud.dart test/campaign_header_test.dart
git commit -m "feat(light): ungated light timer chip in the campaign HUD

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Doc sync — CLAUDE.md

**Files:** Modify `CLAUDE.md` (the HUD / PlayContext-spine bullet).

- [ ] **Step 1: Note the light timer** — in `CLAUDE.md`, find the HUD bullet (mentions `CampaignHeader` / `hdr-quick-roll` / the always-visible row). Append:

```
  The HUD also carries a **global light timer** (`lightProvider`, session-scoped
  `juice.light.v1`, in `sessionScopedKeys` → exported) — an ungated flame chip +
  `hdr-light-dec`/`hdr-light-inc` steppers with a lit/out indicator, available in
  every campaign on every verb (no system gate), distinct from the Shadowdark
  sheet's per-character `torch`. A neutral player timer; no rulebook duration
  asserted. See `docs/superpowers/specs/2026-06-24-global-light-timer-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note the global light timer in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 state (`LightNotifier`/`lightProvider` + `sessionScopedKeys`) → Task 1. ✓
- §2 HUD control (ungated chip + dec/inc + lit/out) → Task 2. ✓
- Testing (provider round-trip + scoped-key export; HUD chip inc/dec/out) → Tasks 1, 2. ✓
- Doc → Task 3. ✓

**Type consistency:**
- `lightProvider` (Task 1) read in the HUD (`ref.watch(lightProvider).valueOrNull ?? 0`) + written (`ref.read(lightProvider.notifier).set(...)`) (Task 2). ✓
- `LightNotifier.set(int)` (Task 1) called from the steppers (Task 2). ✓
- Keys `hdr-light-dec`/`hdr-light-inc` consistent between impl (Task 2) + test (Task 2). ✓
- `'juice.light.v1'` in `sessionScopedKeys` (Task 1) asserted by the export test (Task 1). ✓

**Placeholder scan:** No TBD/TODO; complete code per step.

**Risk notes:**
- The light chip MUST be outside the `if (usesMythic …)` Chaos block — else it'd inherit the mythic gate (the whole point is ungated). The widget test pumps a bare `_prefs()` (no systems) and still expects the chip, which proves the ungating.
- `set` updates `state` before the async `prefs` write (mirrors `DecksNotifier`), so a rapid second tap reads the new value.
