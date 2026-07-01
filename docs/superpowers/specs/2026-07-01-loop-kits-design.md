# Shareable Loop Kits — Design

_Dated 2026-07-01. Implements Phase 3 of
`docs/superpowers/plans/2026-06-30-wedge-roadmap.md`: "Shareable loop kits:
custom tables + ref cards + a starter scene, bundled (builds on the existing
`.tables.json` pack path). Paste-a-link-get-a-kit import, friction-free. Seed
with 5–6 authored kits for the 3 core systems." Success: a stranger imports a
kit and starts a themed solo session in < 60s._

## What a loop kit is

A **loop kit** bundles the three things that give a fresh campaign flavor
before the player has written anything themselves:

- zero or more **custom tables** (`CustomTable`, `lib/engine/custom_table.dart`)
- zero or more **user ref cards** (`UserRefCard`, `lib/engine/quick_ref.dart`)
- one **starter scene** (a title + body — becomes the campaign's first
  `JournalKind.scene` entry, set as the active scene)

Importing a kit is what makes it "themed": the tables show up in "My Tables",
the ref cards show up in QuickRef, and the starter scene is what the loop's
Next-beat button sees immediately — no blank-scene prompt on session 1.

## Data model — `lib/engine/loop_kit.dart` (new, pure)

Mirrors `custom_table.dart`'s pack pattern exactly (no Flutter import, unit
tested without a widget harness).

```dart
class LoopKit {
  const LoopKit({
    required this.name,
    this.system,               // optional hint: 'ironsworn' | 'dnd' | 'cairn' | ...
    this.tables = const [],
    this.refCards = const [],
    this.sceneTitle = '',
    this.sceneBody = '',
  });
  final String name;
  final String? system;
  final List<CustomTable> tables;
  final List<UserRefCard> refCards;
  final String sceneTitle;
  final String sceneBody;
}

const kLoopKitKind = 'juice-loop-kit';

String encodeLoopKit(LoopKit kit) => jsonEncode({
      'kind': kLoopKitKind,
      'v': 1,
      'name': kit.name,
      if (kit.system != null) 'system': kit.system,
      'tables': kit.tables.map((t) => t.toJson()).toList(),
      'refCards': kit.refCards.map((c) => c.toJson()).toList(),
      'scene': {'title': kit.sceneTitle, 'body': kit.sceneBody},
    });

// Tolerant: unrecognized kind / malformed shape -> null. Individual bad
// tables/cards are dropped (reuses CustomTable.maybeFromJson /
// UserRefCard.maybeFromJson), never throws except on unparseable top-level
// JSON (FormatException, same contract as decodeTablePack).
LoopKit? decodeLoopKit(String raw);
```

No new roll/resolution logic — a kit is inert data until imported; rolling
happens through the existing `rollCustomTable` / QuickRef rendering once its
contents join the app-global stores.

## Import — always append, never clobber

Same rule as the existing table-pack import: importing a kit adds to what's
there, with fresh ids, and never overwrites existing user data.

1. `CustomTablesNotifier.addAll(kit.tables)` — already exists, reused as-is.
2. `UserRefCardsNotifier.addAll(kit.refCards)` — **new method**, same shape as
   `CustomTablesNotifier.addAll` (fresh ids via a `DateTime.now()`-seeded
   base + index, never touches existing cards).
3. `JournalNotifier.addScene(kit.sceneTitle)` → id, then set the body via the
   existing scene-body path (`JournalEntry.copyWith(payload:)` /
   `JournalNotifier.replace`, the same mechanism the scene-description
   flesh-out feature uses) → `PlayContextNotifier.setActiveScene(id)`. Skipped
   entirely when both `sceneTitle` and `sceneBody` are empty (an all-tables or
   all-cards kit is valid).

Note on scope: `customTablesProvider`/`userRefCardsProvider` are **app-global,
per-device stores, not session-scoped** (pre-existing design — see
[[custom-oracle-tables]]/`current backlog` memory). A kit's tables/cards land
in that shared device-wide pool, not scoped to the one campaign being
created — same as importing a table pack today. Only the starter scene is
campaign-scoped (it's a journal entry). This is the existing architecture,
not a new limitation introduced here, but worth being explicit about: deleting
the campaign later does NOT remove the kit's tables/cards from the device.

## Two import sources, three surfaces

**A. Wizard — new campaigns (the <60s path).** `NewCampaignDialog` step 2
("How do you start characters?") gets a third `_StartCard`: **"Import a
kit"**. Choosing it reveals a grid of the bundled seed kits (`kKits`, see
below), filtered to the ruleset picked in step 1 when it matches a kit's
`system` tag (unfiltered otherwise — e.g. `ruleset-none`). Selecting a kit
sets `_start = 'kit'` + a `_selectedKit` reference; `_createSession` runs the
same import steps above right after `create(...)`, before landing. Bundled →
no network, no failure mode, guarantees the <60s target.

**B. Drawer menu — existing campaigns.** Alongside the existing "Export table
pack" / "Import table pack" menu items: **"Export loop kit"** (bundles *all*
current custom tables + *all* user ref cards + the campaign's current active
scene — same all-at-once scope as the existing table-pack export, no
selection UI) and **"Import loop kit"**, which opens a small dialog with two
modes:
  - **Pick a file** (`file_picker`, same pattern as `_importTablePack`)
  - **Paste a link** (a URL text field + "Fetch" button → `http.get(uri)`,
    tolerant decode of the response body). This is the actual "paste-a-link"
    path from the roadmap — for community-shared kits, not the bundled seed
    set.

Both drawer actions reuse the existing `_exportTablePack`/`_importTablePack`
scaffolding (dialog lifecycle, snackbar messaging, `PlatformException`
handling) — new sibling methods `_exportLoopKit`/`_importLoopKit`, not a
rewrite.

**C. Bundled seed assets.** `assets/kits/*.json` (5–6 files, one per
theme/system), registered in `pubspec.yaml` `assets:` and `flutter:` list.
Loaded via a `kitsProvider` (`FutureProvider<List<LoopKit>>`) that
`rootBundle.loadString`s each file — same pattern as `systemFoesProvider` /
`systemSpellsProvider`, except this is a fixed bundled list, not
system-keyed, so it's a flat `Future.wait` over the known asset paths, not a
per-system lookup.

## Seed content (authoring task, not just code)

5–6 kits, one or two per core system (Ironsworn family / D&D 5e / Cairn),
each: 2–4 small custom tables + 1–2 ref cards + one starter scene. Original
authored content only — same posture as the Word Oracle generator (no
vendored rulebook text, no attribution needed). Concrete kit list and content
is a plan-level/implementation detail, not fixed here — the plan should
enumerate the 5–6 titles and their table/card/scene contents before writing
code.

## Error handling

- Malformed/unrecognized pasted-link content → tolerant decode returns
  `null`/empty, same snackbar pattern as `_importTablePack`'s "No tables
  found in file." (message: "Not a loop kit.").
- Network failure on paste-a-link (timeout, non-200, unreachable host) →
  caught, snackbar "Could not fetch that link." No retry logic — a plain
  single `http.get` with the package's default timeout is enough; this is a
  paste-and-fetch action, not a background sync.
- Bundled kit assets are trusted (shipped with the app) — no tolerant-decode
  path needed there beyond the same `decodeLoopKit`, defensively, in case a
  future asset edit typos the JSON.

## Testing

- `loop_kit.dart`: pure unit tests for encode/decode round-trip, tolerant
  decode of garbage/wrong-kind/partial payloads, empty-scene skip — same
  style as `custom_table_test.dart`.
- `UserRefCardsNotifier.addAll`: unit test mirroring the existing
  `CustomTablesNotifier.addAll` test (fresh ids, appends, doesn't clobber).
- Wizard "Import a kit" card + kit grid selection + `_createSession` wiring:
  widget test, following `campaign_wizard_test.dart`'s existing pattern.
- Drawer export/import (file-pick path only): widget test following
  `backup_nudge_test.dart`/existing table-pack-import test style.
- Paste-a-link fetch path: **not** unit/widget tested (real network) —
  manual/device verification only, consistent with how `pdfrx` rendering and
  the BYO-key cloud LLM calls are handled elsewhere in this repo.

## Explicitly out of scope

- No selection UI on export (export = "everything currently in the app-global
  stores + active scene," matching the existing table-pack export's scope).
- No kit versioning/update-in-place — importing the same kit twice appends
  duplicates (same as table-pack import today).
- No community kit registry/index — paste-a-link is bring-your-own-URL only.
- No per-kit preview before import beyond the wizard's picker card (name +
  system tag + rough content counts) — full preview is a possible follow-up,
  not required for the <60s success bar.
