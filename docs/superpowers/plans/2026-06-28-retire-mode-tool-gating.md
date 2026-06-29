# Retire mode-based tool-gating Implementation Plan

> Refactor. Mode (`CampaignMode {gm, party}`) stops hiding tools/subtabs; it keeps driving ONLY landing (`landingDestination` gm→run, party→sheet) + framing (the mode toggle). Tool/subtab visibility becomes governed by enabled `systems`. Foundation for the 3-step creation wizard (PR2).

**Goal:** Remove `visibleForMode`/`kSubtabRoles`/`SubtabRole` and every mode-gate on tools/subtabs, so a solo campaign sees the full toolkit regardless of mode.

**Verification:** `flutter analyze` clean + `flutter test` all green (refactor — update/delete tests that asserted mode-hiding). Prefix flutter with `export PATH="$HOME/development/flutter/bin:$PATH"`.

---

## What KEEPS working (do NOT touch)
- `CampaignMode` enum, `modeProvider`, `SessionsNotifier.setMode`, the app-bar `mode-toggle`.
- `landingDestination(mode)` (gm→run, party→sheet) + `ShellRouteNotifier.landFor`.
- All system-based gating (`systems.contains('party')` etc.).

## Change-list

### 1. Delete `lib/engine/role_tags.dart` entirely
It contains only `SubtabRole`, `kSubtabRoles`, `visibleForMode` — all removed. Delete the file and every `import '.../role_tags.dart';`.

### 2. `lib/features/sheet_tab.dart`
- Remove the `role_tags.dart` import and the `modeProvider` read (if used only for this).
- Change the bare-roster guard from `if (family.isEmpty || !visibleForMode('moves', mode))` to **`if (family.isEmpty)`**. (Moves shows whenever an Ironsworn family ruleset is enabled.)

### 3. `lib/features/tracking_tab.dart`
- Remove the `role_tags.dart` import + the `mode`/`visibleForMode` reads.
- `rumors` → always included (drop the conditional, or `const rumors = true;`).
- `partyTools` → just `systems.contains('party')` (the emulator/sidekick/behavior subtabs stay gated by the `party` SYSTEM, not mode).

### 4. `lib/shared/tool_registry.dart`
- Remove the `role_tags.dart` import.
- Drop the `mode` parameter from `buildToolRegistry({required family, systems})`.
- In the `.where`, drop `modeOk`; keep only `systemOk`.

### 5. `lib/shared/home_shell.dart`
- `buildToolRegistry(family: family, systems: systems, mode: mode)` (line ~544) → drop `mode:`. Keep the `mode` local if still used elsewhere (toggle/landing); it likely is.

### 6. `lib/shared/shell_route.dart`
- `openTool(String id, {CampaignMode? mode})` → drop the `mode` param + the `if (mode != null && !visibleForMode(...)) return false;` line. (openTool now only fails for ids with no tab home.)

### 7. openTool callers
- `lib/features/journal_screen.dart:577` `openTool(id, mode: mode)` → `openTool(id)`.
- `lib/shared/tool_search_sheet.dart:58` `openTool(t.id, mode: ref.read(modeProvider))` → `openTool(t.id)`. Remove the now-unused `modeProvider` read if it's only for this.

### 8. `lib/engine/campaign_surfaces.dart`
- Remove the `role_tags.dart` import.
- `SurfaceRow`: drop the `requiresModeKey` field; `on(...)` becomes `bool on(Set<String> systems)` (system gate only).
- `surfacesFor(...)` → `List<VerbSurfaces> surfacesFor(Set<String> systems)` (drop the `mode` param); update `row.on(systems)`.
- In `_table`, delete every `requiresModeKey: ...` argument (rows: Moves keeps `requiresSystem: 'ironsworn'`; Rumors becomes ungated `SurfaceRow('Rumors')`; emulator/sidekick/behavior keep `requiresSystem: 'party'`).

### 9. `lib/shared/campaign_preview_pane.dart`
- `surfacesFor(mode, systems)` (line ~17) → `surfacesFor(systems)`. Drop the `mode` read if now unused in the pane.

### 10. `lib/engine/suggestions.dart`
- Remove the `partyMode` parameter from `suggestionsFor(...)`.
- `make-move`: gate on `ironswornFamily && hasFocusCharacter` (drop `&& partyMode`).
- The `if (!partyMode) ...[develop-rumor, seed-npc]` block → include both unconditionally (drop the `if (!partyMode)`).

### 11. `lib/state/suggestions_provider.dart`
- Drop the `partyMode: mode == CampaignMode.party` argument (line ~36). Remove the `mode` read if now unused.

## Test fallout (update/delete)
Run the full suite; fix every failure. Expected:
- **Delete** `test/role_tags_test.dart`.
- `test/suggestions_test.dart` + `test/suggestions_provider_test.dart`: drop `partyMode`; assert make-move shows on `ironswornFamily && hasFocusCharacter` (any mode); the prep chips (develop-rumor/seed-npc) always present.
- Any `campaign_surfaces`/surfaces test: drop `requiresModeKey`/mode arg; `surfacesFor(systems)`.
- `test/tracking_tab*`/`sheet_tab*`/tool-registry/home_shell/shell_route tests: any assertion that a subtab/tool is HIDDEN by mode must flip to "shown" (or be removed). E.g. "party mode hides rumors" → rumors now always shows; "gm mode hides emulator" → emulator shows when `party` system on.
- `test/destination_test.dart` landing tests: UNCHANGED (landing still gm→run, party→sheet).

## Steps
- [ ] Apply changes 1–11.
- [ ] `flutter analyze` — resolve every error (mostly removed-symbol/param references).
- [ ] `flutter test` — iterate, updating/deleting the tests above until green. Report the count.
- [ ] Commit:
```bash
git add -A
git commit -m "refactor(modes): mode drives landing/framing only, not tool visibility"
```

## CLAUDE.md
Update the GM/Party-mode bullet: note that mode no longer gates tool/subtab visibility (the `visibleForMode`/`role_tags` gating was removed); tools follow the enabled `systems` set; mode now drives only landing + framing. Commit with the docs.

## Self-review
- Mode still: enum, provider, toggle, landing — untouched. ✅
- Only the GATING removed; system gating intact. ✅
- No new behavior; pure removal + test updates. ✅
