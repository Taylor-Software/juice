# Cycle 4 — The Living Journal (design)

Date: 2026-06-12. Status: approved, in progress.

## Competitive context (2026-06-12 rescan)

The 2026-06-11 picture changed: the threat is no longer juice-roll
(awake since May 2026 but still journal-less). **RPG Spark v3.0**
(Apr 2026) now ships a multi-system oracle+journal with tappable
@mentions/#tags and full Ironsworn/Starforged support; **Mythic GME 2e
official app** has a journal with markdown export; **iron-vault**
(Obsidian) sets the bar for mechanics-inline-in-prose. Still true:
nobody combines verified multi-system (Juice + Mythic + Ironsworn) +
party emulation + journal + AI in one app, and **on-device oracle
interpretation remains an empty category** (AI-GM tools are all cloud
full-GM-replacement; the community's top AI pain is memory, which our
journal-aware recall targets).

Cycle 4 closes the integration gap (journal is home but passive) and
deepens both moats.

## Decisions (user-confirmed)

| Question | Decision |
|---|---|
| Lead theme | A: journal command layer (structured entries + slash commands + mentions) |
| System profiles (B2) | In this cycle |
| AI items | All four: ask-anything, entity suggestions, recap/previously-on, voice-everywhere |
| Distribution | Stay web-first; stores deferred |
| Deferred | B3 scene loop, D-theme (typography/themes/Cmd-K), stores |

## Audit findings driving the design

- `JournalEntry` is flat text (title/body/threadId/kind/chaosFactor/
  tags) — results can't re-roll, deep-link, or render structure.
- The composer is inert: one oracle answer = open panel → tool → roll
  → add to journal → close (5 gestures).
- No entity layer: character links were cut in PR #8; tags are plain
  strings; nothing in prose is tappable.
- 18 tools always visible regardless of campaign system; campaign
  state (chaos, scene, party, crawl) invisible outside tools.
- The interpreter (our differentiator) hides in a per-entry menu.

## Architecture

### 1. Command registry — `lib/shared/command_registry.dart`

The new shared seam, declarative like `tool_registry`:

```dart
class CommandDef {
  final String id;            // 'fate-juice', 'dice', 'meaning', …
  final String label;         // 'Fate Check (Juice)'
  final List<String> keywords;
  final String system;        // 'juice' | 'mythic' | 'roll-high' | 'ironsworn' | 'party' | 'core'
  final CommandArg arg;       // none | odds | notation
  final CommandResult Function(Oracle oracle, Map<String, String> args) run;
  final String? toolId;       // registry tool for deep work / open-in-tool
}
```

`CommandResult` carries `title`, `body`, and the entry `payload`
(below). Consumers: slash palette (phase 2), re-roll (phase 1),
ask-anything (phase 6), campaign-header tap-throughs (phase 3).

v1 commands: `fate-juice` (odds), `fate-mythic` (odds; caller passes
chaos from `crawlProvider` in args), `fate-roll-high` (odds), `dice`
(notation), `meaning` (Mythic action/description pair), `name`,
`detail`. Mythic/roll-high commands appear only when the campaign
profile enables those systems (phase 4). `/scene` and `/recap` are
composer built-ins (need provider/dialog access), not registry rows.

### 2. Structured entries (A1) — additive, no migration

`JournalEntry` gains `sourceTool: String?` and
`payload: Map<String, dynamic>?`. Both omitted from `toJson` when
null → existing journals and campaign files byte-stable
(`Character.emulation` precedent). Journal key stays
`juice.journal.v2`; campaign schema stays v2.

Payload shape (versioned, tolerant):

```json
{
  "v": 1,
  "command": "fate-juice",
  "args": {"odds": "likely"},
  "summary": "Yes",
  "rolls": [{"label": "Fate (likely)", "display": "8 → Yes"}],
  "rerollable": true
}
```

- `JournalNotifier.addResult` gains optional `sourceTool`/`payload`;
  a `GenResult → payload` helper gives every existing tool rich
  entries nearly free (`GenResult` already has title/summary/rolls).
  `rerollable` is true only for registry commands (pure rolls);
  stateful tools (crawl, encounter, hexflower) are never rerollable.
- Rendering: payload entries render summary + RollRow-style lines,
  a re-roll icon (runs the command again, **appends a new entry** —
  the journal is a log), and "open in tool" (`openTool(sourceTool)`;
  no state injection in v1).
- Unknown/absent payload → today's flat rendering. Unknown payload
  `v` → flat rendering (forward-tolerant).

### 3. Slash palette (A2)

Leading `/` in the composer opens an anchored popup over the
composer: command list filtered by typed text and the campaign's
enabled systems, keyboard navigable (Down/Up/Enter) and tappable.
Arg affordances: odds picker chips for fate commands; free text after
the command name for dice notation (`/dice 3d6+2`). Running a command
inserts a structured entry directly — the tool panel never opens.
Esc or clearing the `/` dismisses. `/scene` opens the existing scene
dialog; `/help` opens the Help tool.

### 4. Entity mentions (A3)

- `@` in the composer opens autocomplete over characters and open
  threads (two sections). Insertion stores a markup token in the body:
  `@[Display Name](char:ID)` / `@[Title](thread:ID)`.
- Renderer parses tokens (regex `@\[([^\]]+)\]\((char|thread):([^)]+)\)`)
  into tappable spans: character → character sheet (tracker), thread →
  journal thread filter. Unresolvable id → plain styled text.
- Display name freezes at insert; tap resolves by id (rename-safe
  navigation, stale label accepted — out of scope to repropagate).
- Journal export (md/html) renders mentions as the plain display name.
- New journal filter: by character (mention-derived), beside thread/tag
  chips.
- NPC/location result payloads get one-tap **Save as Character /
  Save as Thread** actions that create the entity and backfill a
  mention into the entry.

### 5. Campaign header (B1)

Collapsible band between app bar and journal (collapsed = one thin
row; state persisted per session):
- Chaos factor dial (shown when Mythic enabled) — taps adjust, same
  provider the Mythic tool uses.
- Current scene title (latest scene entry).
- Pinned threads: `Thread.pinned` (new additive bool; pin toggle in
  tracker + thread chips).
- Party: `Character.starred` (new additive bool; star toggle on
  character sheets) — starred characters as chips → character sheet.
- Crawl badge (dungeon/wilderness state) when active → opens tool.
All read-only watchers over existing providers; taps open the owning
tool via `openTool`.

New session-scoped setting `defaultOracle` (`'juice'`/`'mythic'`/
`'roll-high'`, default `'juice'`) in `juice.settings.v1` — used by
ask-anything and the header's quick-ask.

### 6. System profiles (B2)

`SessionMeta.systems: Set<String>` over
`{'juice','mythic','ironsworn','party'}`; absent in stored JSON →
all enabled (legacy campaigns unchanged). Campaign-create dialog gains
the picker (all on by default); a campaign-settings entry point allows
later edits.

Scoping map (core = always visible):
- juice → fate-check, gen-story, gen-npcs, gen-exploration, maps,
  gen-encounters, gen-details, tables, roll-high*
- mythic → mythic
- ironsworn → moves (existing rulesets dialog folds under this
  profile; family exclusivity logic unchanged)
- party → party-emulator, behavior-tables, sidekick-dialogue
- core → dice, encounter, threads-characters, help

*roll-high rides with juice (same Fate tool surface).

Scopes apply to: tool drawer groups, slash palette, campaign header
widgets, help-index highlighting. Keep-alive panel handles tool
removal via the existing `didUpdateWidget` path.

### 7. AI pack (C1–C4) — all gated on interpreter availability

- **C1 ask-anything:** composer text ending in `?` surfaces an "Ask
  the oracle" chip (also `/ask <question>`). Flow: odds picker
  (LLM `suggestOdds(question)` preselects when the model is warm;
  default 50/50 otherwise) → fate check via `defaultOracle` → one
  entry: question (title), answer (body), payload; optional
  "Interpret" follow-through reuses the existing sheet.
- **C4 voice-everywhere:** entry menu gains "Voice…" when the
  interpreter is supported and the entry is dialog-shaped (payload
  dialog field, quoted speech in body, or sourceTool in a dialog set);
  reuses `VoiceSeed`; result appends like a reading.
- **C3 entity suggestions:** after an entry lands, suggest tracking
  when (a) a result payload carries an NPC/location name, or (b) a
  capitalized name recurs ≥2 times without matching an existing
  entity. Dismissible chips above the composer; dismissals persisted
  per session (`juice.suggestDismissed.<id>`); never auto-creates.
  Heuristic first; LLM assist optional later.
- **C2 recap:** `/recap` summarizes entries since the last scene
  divider via new `InterpreterService.summarize(List<String>)`;
  "Previously on…" dismissible banner on campaign open when new
  entries exist since last visit (summary cached under
  `juice.recap.<sessionId>` with the last-entry id).

`suggestOdds`/`summarize` join the service seam (fake gains scripted
returns; `GemmaInterpreterService` reuses `_generate`'s watchdog/
stopGeneration discipline). Everything degrades gracefully with no
model: chips/banners simply don't appear; `/ask` works with manual
odds.

## Testing

- Command registry unit tests with seeded dice (probe-replay pattern);
  every command id unique; system values valid; fate commands honor
  odds; dice honors notation.
- Entry model: additive round-trip (old JSON loads, null payload
  omitted), forward tolerance (unknown payload v → flat render).
- Mention parser round-trip + escaping; export renders plain names.
- Widget tests (fakes, `AppTheme.light()`): palette opens on `/`,
  filters, keyboard select, structured entry lands; re-roll appends;
  open-in-tool opens the panel on the right tool; header
  collapse/expand + tap-throughs; profile scoping hides drawer rows
  and palette commands; mention autocomplete inserts markup and spans
  tap; ask-anything chip flow with FakeInterpreterService; suggestion
  chips appear/dismiss/persist; recap banner cache behavior.
- House rules: never construct `GemmaInterpreterService` in tests;
  analyze baseline 1 pre-existing info; same-frame double-tap tests on
  any new read-modify-write handlers (lost-update pattern:
  press-time fresh reads).

## Out of scope

- B3 scene start/end loop; D-theme (typography, genre themes, Cmd-K);
  store distribution.
- Mention rename re-propagation (tap resolves by id; label frozen).
- Re-open-in-tool state injection (plain `openTool` only).
- LLM odds/NER beyond the heuristic + `suggestOdds` seam.

## Risks (accepted/mitigated)

- Payload schema drift per tool → tolerant render (flat fallback),
  test pins on known `sourceTool` ids.
- Re-roll correctness → only registry commands set `rerollable`;
  args captured at roll time.
- Mention markup collisions in user prose → narrow regex, escape test;
  worst case renders as typed text.
- Profile scoping orphaning keep-alive tools → existing
  `didUpdateWidget` removal path covers it.
- Suggestion noise (C3) → conservative triggers, persisted dismissals.

## Phasing — 7 PRs

1. Command registry + structured entries + rich render + re-roll +
   open-in-tool (A1).
2. Slash palette (A2).
3. Campaign header + `defaultOracle` + pinned/starred (B1).
4. System profiles (B2).
5. Entity mentions + save-as-entity + character filter (A3).
6. Ask-anything + voice-everywhere (C1, C4).
7. Entity suggestions + recap/previously-on (C3, C2) + cycle closeout.
