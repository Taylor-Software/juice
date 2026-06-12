# In-app help system — user guide, system references, credits (design)

Date: 2026-06-12. Status: **shipped** (PR #32, 2026-06-12).

## Goal

A Help tool inside the app covering three needs:
1. **User guide** — how to use every tool in the app, plus app-level
   features (journal, sessions, campaign files, the on-device interpreter).
2. **System references** — concise quick-reference summaries of each
   supported system's procedures (Juice oracle, Roll High, Mythic GME,
   Ironsworn family, Triple-O, PET, Sidekick), written fresh in our own
   words — no verbatim source reproduction beyond what the verified data
   assets already carry.
3. **Credits & licensing** — a single About page with every content
   license and credit, plus Flutter's `showLicensePage` for package
   licenses.

## Decisions (user-confirmed)

| Question | Decision |
|---|---|
| Reference depth | Quick-reference summaries for every system; no verbatim transcription (uniform depth, no license risk) |
| Entry points | Help tool in the launcher drawer + a per-tool "?" in the tool-host header that deep-links to that tool's guide page |
| Content storage | `assets/help_data.json`, hand-written original prose; plain asset load, no build-script verification rail (that rail exists for transcribed data) |
| Credits | About page (content licenses) + button opening Flutter's `showLicensePage` (package licenses) |

## Architecture

### 1. Content asset — `assets/help_data.json`

Hand-written (committed directly; NOT generated — original prose has no
source to verify against). Shape:

```json
{ "sections": [
  { "id": "guide",   "title": "User guide",        "pages": [ ... ] },
  { "id": "systems", "title": "System references", "pages": [ ... ] },
  { "id": "about",   "title": "About & licenses",  "pages": [ ... ] } ] }
```

Page: `{ "id", "title", "blocks": [block...] }`. Block kinds (exactly one
key per block):
- `{"h": "..."}` — subheading
- `{"p": "..."}` — paragraph
- `{"tip": "..."}` — highlighted callout
- `{"steps": ["...", ...]}` — numbered list

Guide pages (section `guide`): getting-started, journal (write, scene
dividers, search, tags, filter, edit, export), sessions-campaigns
(switcher, export/import `.juice.json`, BYO cloud), fate-check, roll-high,
mythic-gme, dice-roller, story-scenes, npcs-dialog, generators-tables,
party-emulator (Triple-O check + PET procedures), behavior-tables,
sidekick-dialogue (incl. hexflower), threads-characters, encounter,
maps, moves (Ironsworn family toggle), interpreter (what it is, model
download size + consent, on-device privacy, genre/tone steering,
journal-aware recall, Voice this).

Systems pages (section `systems`): juice-oracle, roll-high, mythic-gme,
ironsworn-family, triple-o, pet, sidekick. Each: what the system is for,
its core procedure(s) summarized in original wording, where it lives in
the app, and an attribution line (`{"p": "Triple-O © Cezar Capacle /
Critical Kit, CC-BY-SA 4.0."}` style) as the final block.

About page (section `about`): app blurb ("free & non-commercial",
all data stays on device), per-source credits — see §4.

### 2. Engine + state

- `lib/engine/help_data.dart` — `HelpData` wrapping the decoded JSON
  (pattern: `EmulatorData`): `sections` (ordered), `page(id)`
  (ArgumentError on unknown), `pages(sectionId)`. Tolerant of unknown
  block keys (skip), strict on missing id/title (asset test catches).
- `lib/state/providers.dart` — `helpDataProvider`
  (`FutureProvider<HelpData>`, rootBundle load; rulesetDataProvider
  pattern) and `helpTopicProvider` (`StateProvider<String?>`): set by the
  "?" entry point, consumed once by the Help screen (navigate + clear).
- `lib/shared/tool_registry.dart` — const map `toolHelpPage`:
  registry tool id → guide page id (e.g. 'party-emulator' →
  'party-emulator', 'behavior-tables' → 'behavior-tables', 'tracker' →
  'threads-characters'). Tools without a page (none expected) simply
  show no "?".

### 3. UI

- `lib/features/help_screen.dart` — index view: sections as headers,
  pages as ListTiles; tapping pushes the page detail INSIDE the tool
  panel (internal navigation state, same approach as the Threads &
  Characters tool — no router). Block rendering: `h` → titleMedium,
  `p` → bodyMedium, `tip` → tinted Card with lightbulb icon, `steps` →
  numbered rows. Back affordance to the index. On first build after
  open: if `helpTopicProvider` is non-null, jump straight to that page
  and clear the provider.
- Registry: new group **Help** (last in `toolGroups`); ToolDef id
  'help', label 'Help', Icons.help_outline, no badge. Counts in
  tool_registry_test: 16→17 base, 17→18 with family.
- Tool-host header (`lib/shared/tool_host.dart`): a small "?"
  IconButton next to the close button, visible when the open tool has a
  `toolHelpPage` entry and is not 'help' itself; on tap: set
  `helpTopicProvider` to the mapped page id, switch the open tool to
  'help'.

### 4. Credits page (About & licenses)

Rendered from the same asset's about page, ending with a Flutter-side
button (the screen appends it; not asset-driven):

- App: Juice Oracle — free, non-commercial, no accounts, campaigns stay
  on device.
- Juice oracle content © jrruethe — CC BY-NC-SA 4.0 —
  github.com/jrruethe/juice (unofficial implementation).
- Mythic Game Master Emulator © Word Mill Games — content used under
  CC-BY-NC 4.0.
- Ironsworn / Delve / Starforged rules & oracles © Shawn Tomkin — CC-BY
  4.0 (Datasworn); Sundered Isles — CC-BY-NC-SA 4.0.
- Triple-O © Cezar Capacle / Critical Kit — CC-BY-SA 4.0 (derived table
  data in `assets/emulator_data.json` stays CC-BY-SA 4.0).
- PET & Sidekick © Tam H (hedonic.ink) — CC-BY 4.0.
- Abstract icons © thunder9861 (official Juice itch release) —
  CC BY-NC-SA 4.0.
- On-device models: Gemma 3 1B (Google, Gemma license, web); Qwen3 0.6B
  (Alibaba, Apache 2.0, mobile).
- 'Software licenses' button → `showLicensePage(context: ...,
  applicationName: 'Juice Oracle')` for package licenses
  (auto-collected by Flutter).

URLs render as selectable text (no url_launcher — lean stack; web users
can copy).

### 5. Testing

- Asset-shape test (reads the file directly, location_test pattern):
  section ids unique; page ids unique across the asset; every page has
  ≥1 block; every block has exactly one known key; every
  `toolHelpPage` value exists as a page id; about page contains all
  seven license strings (Juice, Mythic, Datasworn CC-BY, Sundered Isles,
  Triple-O, Pettish, abstract icons).
- `HelpData` unit tests: ordering, lookup, ArgumentError, unknown-block
  tolerance.
- Widget tests (AppTheme.light()): index renders all three sections;
  tapping a page renders its blocks (incl. tip + steps rendering);
  `helpTopicProvider` deep-link lands on the page and clears; tool-host
  "?" from a mapped tool switches to Help at the right page; "?" absent
  on the Help tool; About shows the license lines and the Software
  licenses button opens Flutter's license page (`LicensePage` finder).
- Registry counts/placement tests updated.

## Out of scope

- Verbatim source-rules reproduction (decided against).
- Search within help (content is ~25 short pages; revisit on demand).
- Localization (app is English-only today).
- url_launcher / tappable links (no new dependencies).

## Risks (accepted)

- Hand-written content drifts as tools evolve — mitigated by the
  asset-shape test tying `toolHelpPage` to real pages, and by docs-sync
  habit (doc-syncer) when tools change.
- Mythic/Datasworn summaries must stay summaries — flagged in the asset
  via attribution lines; review checks wording originality.

## Phasing

Single PR: asset + engine + providers + Help tool + tool-host "?" +
About/LicensePage + tests + README note.
