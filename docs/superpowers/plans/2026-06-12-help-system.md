# Help System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In-app Help tool — user guide for every tool, fresh-worded system references, About/credits page with all content licenses + Flutter's package LicensePage — reachable from the drawer and a per-tool "?".

**Architecture:** Hand-written `assets/help_data.json` (sections → pages → typed blocks) loaded via a `HelpData` wrapper + `helpDataProvider`; a Help tool screen with internal index→page navigation; `helpTopicProvider` deep-link set by a "?" in the tool-host header.

**Spec:** docs/superpowers/specs/2026-06-12-help-system-design.md (read first).

**Branch:** `feat/help-system` off `main`.

Hard rules: analyze exactly 1 pre-existing info (lib/engine/models.dart:2); suite green (current: 445); TDD for Dart; exact commit messages, no co-author lines; no new dependencies; widget tests pump `theme: AppTheme.light()`.

---

### Task 1: Content asset + shape test

**Files:**
- Create: `assets/help_data.json`
- Modify: `pubspec.yaml` (assets list)
- Test: `test/help_asset_test.dart`

**Step 1 — write the failing asset-shape test** (reads the file directly,
`test/location_test.dart` pattern — `File('assets/help_data.json')`):

```dart
// Asserts (write as individual test() cases):
// - top-level 'sections' is a 3-list with ids ['guide','systems','about'] in order
// - section/page ids unique; every page has non-empty title and >=1 block
// - every block is a 1-key map with key in {'h','p','tip','steps'};
//   'steps' value is a non-empty List<String>, others non-empty String
// - guide section contains EXACTLY these page ids:
//   getting-started, journal, sessions-campaigns, fate-check, roll-high,
//   mythic-gme, dice-roller, story-scenes, npcs-dialog, generators-tables,
//   party-emulator, behavior-tables, sidekick-dialogue, threads-characters,
//   encounter, maps, moves, interpreter
// - systems section contains EXACTLY: juice-oracle, roll-high-system,
//   mythic-gme-system, ironsworn-family, triple-o, pet, sidekick
// - about section contains exactly: credits
// - every systems page's LAST block is a 'p' containing '©'
// - the credits page text (all blocks joined) contains each of:
//   'jrruethe', 'CC BY-NC-SA 4.0', 'Word Mill Games', 'CC-BY-NC 4.0',
//   'Shawn Tomkin', 'CC-BY 4.0', 'Sundered Isles', 'CC-BY-NC-SA 4.0',
//   'Cezar Capacle', 'CC-BY-SA 4.0', 'Tam H', 'hedonic.ink',
//   'thunder9861', 'Gemma', 'Qwen', 'free' (non-commercial statement)
```

**Step 2 — run it, expect FAIL** (file missing).

**Step 3 — author the asset.** Shape per spec §1. Content requirements
(original prose, second person, 2-6 blocks/page typical; `tip` for one
practical pointer per page where natural; `steps` for any multi-step flow):

Two fully-worked examples to copy the voice from:

```json
{ "id": "getting-started", "title": "Getting started", "blocks": [
  {"p": "Juice Oracle is a solo-RPG toolkit built around a campaign journal. The journal is your home screen: everything you roll can be kept as an entry, and your own prose goes right in the text field at the bottom."},
  {"h": "Open a tool"},
  {"steps": ["Tap the tools icon (crossed hammers) in the app bar.", "Pick a tool from the list, or type in the search field.", "Tools keep their state while the panel is closed — reopen to continue where you left off."]},
  {"tip": "Recently used tools appear as chips at the top of the launcher."},
  {"p": "Your campaign lives entirely on this device. Use sessions (folder icon) for multiple campaigns, and campaign files to back up or move them."}
]}
```

```json
{ "id": "triple-o", "title": "Triple-O (player emulator)", "blocks": [
  {"p": "Triple-O answers 'what would this character do?' with three candidate courses of action: the Obvious (what anyone would expect), the Option (a sound alternative), and the Odd (the surprise)."},
  {"h": "The check"},
  {"steps": ["Name the Obvious — Option and Odd can be defined after the roll.", "Roll a d6: 4-6 the character takes the Obvious, 2-3 the Option, 1 the Odd.", "Or Double-Down with 2d6 and keep whichever die you prefer.", "Doubles on a double-down mean the behavior grows: mark a trait prominent or add a new one."]},
  {"p": "Group mode rolls a d6 per course and assigns them by rank: highest is the Obvious, lowest the Odd. The thirteen behavior tables (spark and specific) feed the check with concrete prompts."},
  {"p": "Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0."}
]}
```

Required coverage per remaining page (each bullet = content that must
appear, in the author's own words):

*Guide section:*
- `journal`: writing entries; scene dividers (chaos snapshot); kept rolls;
  search (magnifier) incl. `#tag` filtering; tags on entries; thread links
  + filter chips; in-place edit via the ⋯ menu; export (share icon) as
  Markdown or styled HTML.
- `sessions-campaigns`: app-bar folder icon; create/switch/delete sessions;
  export/import `.juice.json` (schema v2, v1 imports); BYO-cloud advice
  (save into a synced folder).
- `fate-check`: ask yes/no questions; likelihood ladder; chaos factor;
  Random Event / Invalid Assumption outcomes; tap-to-roll from the journal.
- `roll-high`: 7-step likelihood ladder, six graded answers, d100/d20/2d6
  variants.
- `mythic-gme`: Fate Chart vs chaos factor; Scene Test at scene start;
  Event Focus targeting your Threads/Characters lists; 47 Meaning Tables.
- `dice-roller`: notation (`NdX`, `d%`, `dF`, modifiers, multi-group,
  keep/drop `4d6kh3`, `d20adv`/`d20dis`); per-die breakdown; history;
  journal logging.
- `story-scenes`, `npcs-dialog`, `generators-tables`: what each generator
  group produces; crawl modes (wilderness drift + Lost, dungeon linger,
  NPC dialog state) on their tools; one `tip` pointing at journal logging.
- `party-emulator`: character picker; emulation panel (Agenda + Ask,
  Focus, tokens); Triple-O check fields incl. group mode; PET actions —
  ACT (coin + modifier reading, agenda match earns a token), REFOCUS,
  Spend tag (marks the tag until session start), Session start (new focus,
  real-life event, resets spent tags), Consequence.
- `behavior-tables`: spark vs specific tables; combo chips; journal.
- `sidekick-dialogue`: per-character mood; Roll line (tone/topic/said-how);
  doubles change the mood first; Voice this (needs the interpreter model);
  hexflower tab — step with 2d6, topic + history/current-events context,
  direction tone, d3 priority, Reset.
- `threads-characters`: open threads; characters with free-form stats,
  tracks (current/max), tags; emulation summary line comes from the Party
  tools.
- `encounter`: add combatants (linked characters share their HP track
  live); initiative with drag override; turns/rounds; status tags;
  defeated; end-of-encounter journal summary.
- `maps`: dungeon rooms drawn as you roll (tap room for detail, linger);
  wilderness hex reveal from travel; Lost markers; manual reveal; per
  campaign persistence; journal snapshots.
- `moves`: enabling rulesets via the app-bar tune icon; family exclusivity
  (Ironsworn vs Starforged); action vs progress rolls; expansion folding
  (Delve, Sundered Isles); oracle tables.
- `interpreter`: what it does (four lens readings on oracle entries);
  one-time model download (~670 MB web / ~480 MB mobile) after consent;
  runs entirely on device, nothing leaves it; genre/tone steering from the
  campaign sheet; journal-aware recall of related entries; Voice this on
  Sidekick lines; dice stay authoritative.

*Systems section* (each: what it is, core procedure summary, where it
lives in the app, final `p` attribution block):
- `juice-oracle`: Fate Check ladder + chaos; generators (quest, NPC,
  settlement, dungeon, treasure, names, meaning…); crawl tables.
  Attribution: `Juice oracle content © jrruethe, CC BY-NC-SA 4.0 — this app is an unofficial implementation.`
- `roll-high-system`: ladder + graded answers concept.
  Attribution: `Roll High table data verified in-app; part of the Juice oracle content, © jrruethe, CC BY-NC-SA 4.0.`
- `mythic-gme-system`: chaos factor loop, fate chart odds, scenes
  (expected/altered/interrupt), event focus + meaning.
  Attribution: `Mythic Game Master Emulator © Word Mill Games, content used under CC-BY-NC 4.0.`
- `ironsworn-family`: action roll (d6+stat vs two d10 challenge dice),
  progress rolls, oracles; four titles + exclusivity rule.
  Attribution: `Ironsworn, Delve and Starforged © Shawn Tomkin, CC-BY 4.0 (Datasworn data); Sundered Isles CC-BY-NC-SA 4.0.`
- `triple-o`: as the worked example above.
- `pet`: agendas (with the Ask), focuses, tokens, ACT coin + modifier
  (as-written / inverted / exaggerated), tag spend, session start.
  Attribution: `PET © Tam H (hedonic.ink), CC-BY 4.0.`
- `sidekick`: six moods, doubles → mood change, tone/topic/said-how,
  hexflower walk (2d6 rose, history vs current events, reset).
  Attribution: `Sidekick © Tam H (hedonic.ink), CC-BY 4.0.`

*About section* — `credits` page blocks, in order:
```json
[
 {"p": "Juice Oracle is free and non-commercial. No accounts, no network play — your campaigns stay on your device."},
 {"h": "Content"},
 {"p": "Juice oracle content © jrruethe — CC BY-NC-SA 4.0 — github.com/jrruethe/juice. This app is an unofficial implementation of those tables."},
 {"p": "Mythic Game Master Emulator © Word Mill Games — content used under CC-BY-NC 4.0."},
 {"p": "Ironsworn, Ironsworn: Delve and Ironsworn: Starforged © Shawn Tomkin — CC-BY 4.0, via the official Datasworn data. Starforged: Sundered Isles — CC-BY-NC-SA 4.0."},
 {"p": "Triple-O © Cezar Capacle / Critical Kit — CC-BY-SA 4.0. The derived table data in this app stays CC-BY-SA 4.0."},
 {"p": "PET & Sidekick © Tam H (hedonic.ink) — CC-BY 4.0."},
 {"p": "Abstract icon set © thunder9861 (official Juice itch.io release) — CC BY-NC-SA 4.0."},
 {"h": "On-device AI models"},
 {"p": "Web: Gemma 3 1B (Google) under the Gemma license. Mobile: Qwen3 0.6B (Alibaba) under Apache 2.0. Models run entirely on your device after a one-time download."}
]
```

Add `- assets/help_data.json` to pubspec assets.

**Step 4 — run the shape test, expect PASS.** Also `flutter analyze`.

**Step 5 — commit:**
```bash
git add assets/help_data.json pubspec.yaml test/help_asset_test.dart
git commit -m "feat: help content asset — user guide, system references, credits"
```

---

### Task 2: HelpData engine + providers (TDD)

**Files:**
- Create: `lib/engine/help_data.dart`
- Modify: `lib/state/providers.dart`
- Test: `test/help_data_test.dart`

**Step 1 — failing tests** (load the asset via `File` like
help_asset_test):

```dart
// HelpData(decodedJson):
// - sections: ordered List<HelpSection> (id, title, pages)
// - page('triple-o') returns HelpPage(id, title, blocks)
// - page('nope') throws ArgumentError
// - pagesOf('guide') returns that section's pages in order;
//   pagesOf('nope') throws ArgumentError
// - HelpBlock: sealed-ish small class — kind in {h,p,tip,steps};
//   text for h/p/tip; items for steps
// - unknown block keys in the JSON are skipped (feed a doctored map)
```

**Step 2 — run, expect FAIL. Step 3 — implement** (`EmulatorData`
pattern: store decoded map, lazy parse, small immutable classes).
Providers (in `lib/state/providers.dart`, next to `emulatorDataProvider`):

```dart
final helpDataProvider = FutureProvider<HelpData>((ref) async {
  final raw = await rootBundle.loadString('assets/help_data.json');
  return HelpData(jsonDecode(raw) as Map<String, dynamic>);
});

/// Page id the Help tool should open at (set by the tool-host '?');
/// consumed once by the Help screen, then reset to null.
final helpTopicProvider = StateProvider<String?>((ref) => null);
```

**Step 4 — tests PASS; analyze 1 info. Step 5 — commit:**
```bash
git add lib/engine/help_data.dart lib/state/providers.dart test/help_data_test.dart
git commit -m "feat: HelpData accessors + help providers"
```

---

### Task 3: Help tool screen + registry (TDD)

**Files:**
- Create: `lib/features/help_screen.dart`
- Modify: `lib/shared/tool_registry.dart`
- Tests: `test/help_screen_test.dart`; modify `test/tool_registry_test.dart`

**Step 1 — failing widget tests** (override helpDataProvider with data
loaded from the file; `AppTheme.light()`; pump pattern from
`test/sidekick_screen_test.dart`):

```dart
// - index renders the three section titles and a tile per page
//   (Key('help-page-<id>') on each tile)
// - tapping Key('help-page-triple-o') shows the page title and its
//   block texts; tip blocks render inside a Card; steps render with
//   leading numbers '1.' '2.'; back button Key('help-back') returns
//   to the index
// - deep link: set helpTopicProvider to 'party-emulator' BEFORE pump;
//   screen opens directly on that page; provider is null afterwards
// - credits page: renders all license paragraphs; below the asset
//   blocks a FilledButton Key('help-licenses') 'Software licenses';
//   tapping it pushes Flutter's LicensePage (find.byType(LicensePage))
// Registry tests: counts 16->17 base, 17->18 with family; group 'Help'
// LAST in toolGroups; ToolDef 'help' label 'Help' icon
// Icons.help_outline.
```

**Step 2 — FAIL. Step 3 — implement.** `HelpScreen extends
ConsumerStatefulWidget`; internal `String? _pageId` state (null = index;
Threads & Characters pattern). Build: `ref.watch(helpDataProvider).when`
loading/error/data. On data, FIRST frame: if
`ref.read(helpTopicProvider)` non-null → `_pageId = it` +
`ref.read(helpTopicProvider.notifier).state = null` (do this in a
post-frame callback or directly in build guarded by a `_consumedTopic`
flag — must also work when the screen is already mounted and re-shown:
ALSO `ref.listen(helpTopicProvider, ...)` in build to catch sets while
the keep-alive instance is offstage).

Block rendering:
```dart
Widget _block(ThemeData theme, HelpBlock b) => switch (b.kind) {
  HelpBlockKind.h => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(b.text, style: theme.textTheme.titleMedium)),
  HelpBlockKind.p => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SelectableText(b.text, style: theme.textTheme.bodyMedium)),
  HelpBlockKind.tip => Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lightbulb_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(b.text)),
        ]),
      )),
  HelpBlockKind.steps => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, s) in b.items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}. ',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Expanded(child: Text(s)),
              ]),
          ),
      ]),
};
```

Credits page special-case: when `_pageId == 'credits'`, append after the
blocks:
```dart
FilledButton.icon(
  key: const Key('help-licenses'),
  icon: const Icon(Icons.description_outlined),
  label: const Text('Software licenses'),
  onPressed: () => showLicensePage(
      context: context, applicationName: 'Juice Oracle'),
)
```

Registry: `toolGroups` gains `'Help'` (last); ToolDef:
```dart
ToolDef(
  id: 'help',
  label: 'Help',
  icon: Icons.help_outline,
  group: 'Help',
  builder: (_, __) => const HelpScreen(),
),
```
(match the actual ToolDef constructor signature in the file).

**Step 4 — suite green, analyze 1 info. Step 5 — commit:**
```bash
git add lib/features/help_screen.dart lib/shared/tool_registry.dart test/help_screen_test.dart test/tool_registry_test.dart
git commit -m "feat: Help tool — guide, system references, credits + LicensePage"
```

---

### Task 4: Tool-host "?" deep link (TDD)

**Files:**
- Modify: `lib/shared/tool_host.dart` (header Row, ~line 158)
- Modify: `lib/shared/tool_registry.dart` (the id→page map)
- Test: extend `test/help_screen_test.dart` (or tool_host's existing test
  file if one exists — check `test/` first and follow suit)

**Step 1 — failing tests:**

```dart
// - pumping the app shell with the party-emulator tool open shows
//   IconButton Key('tool-help'); tapping it switches the panel to the
//   Help tool showing the 'Party Emulator' help page title
// - with the help tool open, Key('tool-help') is absent
// - toolHelpPage: every key is a real registry tool id (compare against
//   defaultTools/buildTools list) and every value is a page id present
//   in assets/help_data.json (load the file in the test)
```

**Step 2 — FAIL. Step 3 — implement.** In tool_registry.dart:

```dart
/// Registry tool id -> help page id (Help tool itself is absent).
const toolHelpPage = <String, String>{
  'fate-check': 'fate-check',
  'roll-high': 'roll-high',
  'mythic': 'mythic-gme',
  'dice': 'dice-roller',
  'gen-story': 'story-scenes',
  'gen-npcs': 'npcs-dialog',
  'gen-exploration': 'generators-tables',
  'gen-encounters': 'generators-tables',
  'gen-details': 'generators-tables',
  'tables': 'generators-tables',
  'party-emulator': 'party-emulator',
  'behavior-tables': 'behavior-tables',
  'sidekick-dialogue': 'sidekick-dialogue',
  'threads-characters': 'threads-characters',
  'encounter': 'encounter',
  'maps': 'maps',
  'moves': 'moves',
};
```
(Verify each key against the ids actually in the registry — including the
family-gated moves tools — and adjust; the map test enforces it.)

tool_host.dart `_panel` header Row, before the close IconButton:

```dart
if (active != null &&
    active.id != 'help' &&
    toolHelpPage.containsKey(active.id))
  IconButton(
    key: const Key('tool-help'),
    icon: const Icon(Icons.help_outline),
    tooltip: 'Help',
    onPressed: () {
      ref.read(helpTopicProvider.notifier).state =
          toolHelpPage[active.id];
      openTool('help');
    },
  ),
```

**Step 4 — suite green, analyze 1 info. Step 5 — commit:**
```bash
git add lib/shared/tool_host.dart lib/shared/tool_registry.dart test/help_screen_test.dart
git commit -m "feat: per-tool help entry point in the tool host"
```

---

### Task 5: Docs

**Files:**
- Modify: `README.md`

Add one sentence to the features area: in-app Help covering every tool, a
quick-reference for each supported system, and a credits page with all
content licenses (plus Flutter's package-license viewer).

```bash
git add README.md
git commit -m "docs: in-app help system"
```

---

## Verification (controller)

`flutter test` (445 + new green), analyze 1 info, `flutter build web`.
Browser: drawer → Help → index sections render → open a guide page (steps/
tip render) → systems page attribution visible → About: all licenses +
Software licenses opens the package list → close, open Party Emulator →
"?" lands on its help page. Reviewer: wording-originality pass on the
systems pages (summaries, not reproductions; Mythic/Datasworn especially).
PR → CI → squash-merge → ROADMAP note.
