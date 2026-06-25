# Campaign Creation Redesign — P2: Live Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add an embedded live-preview pane to campaign creation that shows which app surfaces a campaign's decisions light up, reusing the real gating predicates so it can't drift from runtime. This is P2 (direction B's headline value) of the campaign-creation redesign.

**Architecture:** A pure `surfacesFor(mode, systems)` helper in the engine, modeled as an authored surface table whose system gates are validated against `kKnownSystems` and whose mode gates call the real `visibleForMode` (role_tags.dart). A `CampaignPreviewPane` widget renders it compactly and is embedded in `NewCampaignDialog`, live-updating as presets/Custom toggles change. No full multi-step stepper — P1's Custom picker already groups well; the preview is the differentiating add-on. The dialog's return contract is unchanged.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test.

**Working directory:** `.worktrees/campaign-wizard` (branch `campaign-wizard`, off main with P1 merged). Paths relative to repo root.

**Do NOT stage:** `macos/Runner.xcodeproj`, `macos/Runner.xcworkspace`, `macos/Podfile.lock`.

**Spec:** `docs/superpowers/specs/2026-06-24-campaign-creation-redesign-design.md` (P2 section).

---

## Why this scope (not a full stepper)

P1 shipped a grouped Custom picker (ruleset radio + category multi-select + mode toggle + dead-combo hint). The spec's remaining P2 value is the **live preview** ("streamline what's presented based on campaign decisions" → show the player what they get) and **mode auto-suggest**. A full separate stepper widget would re-risk the just-merged dialog for little gain. So P2 = the preview pane (reusing real predicates) embedded in the existing dialog. A multi-step stepper remains available as a later refinement if ever wanted.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/engine/campaign_surfaces.dart` | Create | `VerbSurfaces`, authored surface table, `surfacesFor(mode, systems)` |
| `lib/shared/campaign_preview_pane.dart` | Create | `CampaignPreviewPane` widget rendering `surfacesFor` |
| `lib/shared/home_shell.dart` | Modify | Embed `CampaignPreviewPane` in `NewCampaignDialog` |
| `test/campaign_surfaces_test.dart` | Create | gating correctness + no-drift guard |
| `test/campaign_preview_pane_test.dart` | Create | pane renders on/off rows |

---

## Task 1: surfacesFor helper

**Files:**
- Create: `lib/engine/campaign_surfaces.dart`
- Create: `test/campaign_surfaces_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/campaign_surfaces_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/campaign_surfaces.dart';

void main() {
  Map<String, bool> flat(CampaignMode mode, Set<String> systems) {
    final out = <String, bool>{};
    for (final v in surfacesFor(mode, systems)) {
      for (final r in v.rows) {
        out['${v.verb}/${r.name}'] = r.on;
      }
    }
    return out;
  }

  test('every authored system gate is a known system (no drift)', () {
    for (final v in surfacesFor(CampaignMode.party, const {})) {
      for (final r in v.rows) {
        if (r.requiresSystem != null) {
          expect(kKnownSystems.contains(r.requiresSystem), isTrue,
              reason: '${v.verb}/${r.name} → ${r.requiresSystem}');
        }
      }
    }
  });

  test('empty systems: only always-on rows are on', () {
    final f = flat(CampaignMode.party, const {});
    expect(f['Sheet/Character roster'], isTrue);
    expect(f['Sheet/D&D 5e sheet'], isFalse);
    expect(f['Ask/Juice oracle'], isFalse);
    expect(f['Map/Region / dungeon map'], isTrue);
    expect(f['Track/Encounter'], isTrue);
  });

  test('cairn party campaign lights the Cairn sheet only', () {
    final f = flat(CampaignMode.party, {'cairn', 'juice', 'party'});
    expect(f['Sheet/Cairn sheet'], isTrue);
    expect(f['Sheet/D&D 5e sheet'], isFalse);
    expect(f['Ask/Juice oracle'], isTrue);
    expect(f['Track/Party emulator'], isTrue);
  });

  test('party vs gm mode flips Rumors and party tools', () {
    final party = flat(CampaignMode.party, {'party'});
    expect(party['Track/Rumors'], isFalse);
    expect(party['Track/Party emulator'], isTrue);
    final gm = flat(CampaignMode.gm, {'party'});
    expect(gm['Track/Rumors'], isTrue);
    expect(gm['Track/Party emulator'], isFalse);
  });

  test('Moves needs ironsworn AND party mode', () {
    expect(flat(CampaignMode.party, {'ironsworn'})['Sheet/Moves'], isTrue);
    expect(flat(CampaignMode.gm, {'ironsworn'})['Sheet/Moves'], isFalse);
    expect(flat(CampaignMode.party, const {})['Sheet/Moves'], isFalse);
  });

  test('surfacesFor returns the 5 verbs in order', () {
    final verbs = surfacesFor(CampaignMode.party, const {}).map((v) => v.verb);
    expect(verbs, ['Journal', 'Sheet', 'Ask', 'Map', 'Track']);
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `cd .worktrees/campaign-wizard && flutter test test/campaign_surfaces_test.dart`
Expected: FAIL — `campaign_surfaces.dart` missing.

- [ ] **Step 3: Create `lib/engine/campaign_surfaces.dart`**

```dart
import 'models.dart';
import 'role_tags.dart';

/// One surface row in the preview. `on` is computed; `requiresSystem` /
/// `requiresModeKey` are the authored gates (kept as data so a test can
/// validate every system gate against kKnownSystems — no drift).
class SurfaceRow {
  const SurfaceRow(this.name, {this.requiresSystem, this.requiresModeKey});
  final String name;
  final String? requiresSystem;
  final String? requiresModeKey; // a visibleForMode key (role_tags)

  bool on(CampaignMode mode, Set<String> systems) {
    final sysOk = requiresSystem == null || systems.contains(requiresSystem);
    final modeOk =
        requiresModeKey == null || visibleForMode(requiresModeKey!, mode);
    return sysOk && modeOk;
  }
}

/// A verb (top-level destination) and its computed surface rows.
class VerbSurfaces {
  const VerbSurfaces(this.verb, this.rows);
  final String verb;
  final List<({String name, bool on, String? requiresSystem})> rows;
}

/// Authored surface table — the single source the live preview reads. Mode
/// gates call the real `visibleForMode`; system gates are validated against
/// kKnownSystems by a test.
const _table = <String, List<SurfaceRow>>{
  'Journal': [
    SurfaceRow('Entries + composer'),
    SurfaceRow('Assistant rail'),
  ],
  'Sheet': [
    SurfaceRow('Character roster'),
    SurfaceRow('Ironsworn / Starforged', requiresSystem: 'ironsworn'),
    SurfaceRow('D&D 5e sheet', requiresSystem: 'dnd'),
    SurfaceRow('Shadowdark sheet', requiresSystem: 'shadowdark'),
    SurfaceRow('Nimble sheet', requiresSystem: 'nimble'),
    SurfaceRow('Draw Steel sheet', requiresSystem: 'draw-steel'),
    SurfaceRow('Argosa sheet', requiresSystem: 'argosa'),
    SurfaceRow('Cairn sheet', requiresSystem: 'cairn'),
    SurfaceRow('Knave sheet', requiresSystem: 'knave'),
    SurfaceRow('OSE / B/X sheet', requiresSystem: 'ose'),
    SurfaceRow('Moves', requiresSystem: 'ironsworn', requiresModeKey: 'moves'),
  ],
  'Ask': [
    SurfaceRow('Juice oracle', requiresSystem: 'juice'),
    SurfaceRow('Mythic GME', requiresSystem: 'mythic'),
    SurfaceRow('Cards / tarot / spreads', requiresSystem: 'cards'),
    SurfaceRow('Lonelog legend', requiresSystem: 'lonelog'),
    SurfaceRow('Generators'),
  ],
  'Map': [
    SurfaceRow('Region / dungeon map'),
    SurfaceRow('Verdant Journey', requiresSystem: 'verdant'),
    SurfaceRow('Hexcrawl toolkit', requiresSystem: 'hexcrawl'),
  ],
  'Track': [
    SurfaceRow('Scenes / threads / tracks'),
    SurfaceRow('Encounter'),
    SurfaceRow('Rumors', requiresModeKey: 'rumors'),
    SurfaceRow('Party emulator',
        requiresSystem: 'party', requiresModeKey: 'emulator'),
    SurfaceRow('Sidekick', requiresSystem: 'party', requiresModeKey: 'sidekick'),
    SurfaceRow('NPC behavior',
        requiresSystem: 'party', requiresModeKey: 'behavior'),
    SurfaceRow('Lonelog resources / battle', requiresSystem: 'lonelog'),
  ],
};

/// The 5 verbs in shell order.
const _verbOrder = ['Journal', 'Sheet', 'Ask', 'Map', 'Track'];

/// Resolves the surface visibility for a (mode, systems) pair.
List<VerbSurfaces> surfacesFor(CampaignMode mode, Set<String> systems) {
  return [
    for (final verb in _verbOrder)
      VerbSurfaces(verb, [
        for (final row in _table[verb]!)
          (
            name: row.name,
            on: row.on(mode, systems),
            requiresSystem: row.requiresSystem,
          ),
      ]),
  ];
}
```

Note: the no-drift test reads `r.requiresSystem` off the returned rows; `VerbSurfaces.rows` exposes it for exactly that. The test's `flat()` helper only reads `name`/`on`.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/campaign_surfaces_test.dart`
Expected: PASS (6 tests). `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/campaign_surfaces.dart test/campaign_surfaces_test.dart
git commit -m "$(cat <<'EOF'
feat(campaign): surfacesFor live-preview helper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: CampaignPreviewPane widget

**Files:**
- Create: `lib/shared/campaign_preview_pane.dart`
- Create: `test/campaign_preview_pane_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/campaign_preview_pane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/campaign_preview_pane.dart';

void main() {
  testWidgets('renders verb headers and an on row', (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CampaignPreviewPane(
            mode: CampaignMode.party,
            systems: const {'cairn', 'juice', 'party'},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('campaign-preview')), findsOneWidget);
    expect(find.text('Sheet'), findsOneWidget);
    // an on-row for the active system is present
    expect(find.text('Cairn sheet'), findsOneWidget);
  });

  testWidgets('summary count reflects active surfaces', (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CampaignPreviewPane(
            mode: CampaignMode.party,
            systems: const {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // with no systems, the always-on rows still produce a non-zero count
    expect(find.byKey(const Key('campaign-preview-count')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/campaign_preview_pane_test.dart`
Expected: FAIL — widget missing.

- [ ] **Step 3: Create `lib/shared/campaign_preview_pane.dart`**

```dart
import 'package:flutter/material.dart';

import '../engine/campaign_surfaces.dart';
import '../engine/models.dart';

/// Compact, read-only preview of which app surfaces a campaign's (mode,
/// systems) decisions light up. Reads `surfacesFor` (the single source).
class CampaignPreviewPane extends StatelessWidget {
  const CampaignPreviewPane(
      {super.key, required this.mode, required this.systems});
  final CampaignMode mode;
  final Set<String> systems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verbs = surfacesFor(mode, systems);
    final activeCount = verbs
        .expand((v) => v.rows)
        .where((r) => r.on)
        .length;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.disabledColor, fontSize: 11);

    return Column(
      key: const Key('campaign-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Preview', style: theme.textTheme.labelLarge),
          const SizedBox(width: 8),
          Text('$activeCount surfaces active',
              key: const Key('campaign-preview-count'),
              style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 4),
        for (final v in verbs)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.verb,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Wrap(spacing: 8, runSpacing: 2, children: [
                for (final r in v.rows)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(r.on ? Icons.check : Icons.remove,
                        size: 13,
                        color: r.on ? theme.colorScheme.primary : theme.disabledColor),
                    const SizedBox(width: 2),
                    Text(r.name,
                        style: r.on ? theme.textTheme.bodySmall : muted),
                  ]),
              ]),
            ]),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/campaign_preview_pane_test.dart`
Expected: PASS (2 tests). `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/campaign_preview_pane.dart test/campaign_preview_pane_test.dart
git commit -m "$(cat <<'EOF'
feat(campaign): CampaignPreviewPane widget

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Embed the preview in NewCampaignDialog

**Files:**
- Modify: `lib/shared/home_shell.dart`

The dialog already computes the resolved `(mode, systems)` via `_resolved()`. Add the preview below the picker (both preset and Custom modes), live-updating because `build()` re-runs on every `setState`.

- [ ] **Step 1: Add the import + embed**

In `lib/shared/home_shell.dart`, add `import 'campaign_preview_pane.dart';`.

In `_NewCampaignDialogState.build()`, after the preset-grid / Custom-picker `if/else` block and before (or after) the genre/tone fields, insert:

```dart
            const SizedBox(height: 12),
            const Divider(),
            Builder(builder: (_) {
              final (mode, systems) = _resolved();
              return CampaignPreviewPane(mode: mode, systems: systems);
            }),
```

(Placing it after genre/tone is fine; choose whichever reads better in the scroll. The `Builder` just scopes the `_resolved()` call.)

- [ ] **Step 2: Run the dialog tests + full suite**

Run: `flutter test test/new_campaign_dialog_test.dart test/home_shell_test.dart`
Expected: PASS — existing dialog tests unaffected (preview is additive, no key collisions). Then `flutter test` (full) and `flutter analyze`.

Note: the dialog content is in a fixed-height `SizedBox(380)` + `SingleChildScrollView`. The preview adds height but scrolls — confirm no overflow assertion in the test output. If an existing Custom test now can't reach a chip, add `tester.ensureVisible(...)` before that tap (as Task 3 of P1 did).

- [ ] **Step 3: Commit**

```bash
git add lib/shared/home_shell.dart
git commit -m "$(cat <<'EOF'
feat(campaign): embed live preview in NewCampaignDialog

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Verify + docs + PR

- [ ] **Step 1: Full suite + analyze**

```bash
cd .worktrees/campaign-wizard
flutter analyze
flutter test
```
Expected: clean + all pass.

- [ ] **Step 2: Update CLAUDE.md**

In the "Campaign creation is presets-first" bullet, replace the final sentence
("P2 ... is a separate follow-up plan.") with:

```
A live-preview pane (`CampaignPreviewPane`, `lib/shared/campaign_preview_pane.dart`)
shows which app surfaces the current (mode, systems) light up, reading the pure
`surfacesFor` (`lib/engine/campaign_surfaces.dart`) — an authored surface table
whose mode gates call the real `visibleForMode` (role_tags) and whose system
gates a test validates against `kKnownSystems`, so the preview can't drift from
runtime. (A full multi-step stepper was judged unnecessary — P1's grouped Custom
picker + the preview cover direction B.) See
`docs/superpowers/plans/2026-06-24-campaign-wizard.md`.
```

Commit:
```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(campaign): note live-preview pane in CLAUDE.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Open PR** against `main`, title
`feat(campaign): live-preview pane for creation (P2)`, with a test-plan checklist
(full suite green; manual: preview updates as presets/Custom toggle; GM toolkit
preview shows Rumors on + party tools off).

---

## Self-Review

**Spec coverage (P2 section):**
- Embedded live preview reusing real gating predicates → Tasks 1-3 (surfacesFor uses `visibleForMode`; no-drift test guards system gates) ✓
- Mode auto-suggest → satisfied by presets (each preset carries its mode) + the preview now makes the mode's surface consequences visible; no separate control needed ✓
- Full stepper → consciously descoped (documented in "Why this scope") ✓

**Placeholder scan:** none.

**Type consistency:**
- `surfacesFor → List<VerbSurfaces>`; `VerbSurfaces.rows` = `List<({String name, bool on, String? requiresSystem})>` — consumed identically in the no-drift test, the pane, and the count. ✓
- `SurfaceRow.on(mode, systems)` returns bool; `requiresModeKey` passed to `visibleForMode`. ✓
- `_resolved()` (existing) returns `(CampaignMode, Set<String>)` — fed straight into `CampaignPreviewPane`. ✓
