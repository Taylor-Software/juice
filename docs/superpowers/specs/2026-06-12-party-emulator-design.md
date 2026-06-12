# Party Emulator — player/NPC emulation (design)

Date: 2026-06-12. Status: approved.
Sources (user-provided PDFs, both verified for license):
- **Pettish** by Tam H (hedonic.ink) — PET (Player Emulator with Tags),
  Sidekick dialogue oracle, Sidekick hexflower. Text **CC-BY 4.0**.
- **Triple-O: The Player Character Emulator** v1.0.2 by Cezar Capacle
  (Critical Kit, May 2026) — Obvious/Option/Odd engine, spark + specific
  d66 tables, Trait sheets. Text **CC-BY-SA 4.0**.

## Goal

Flip the solo seat: the player GMs, the app emulates the *characters* —
what they do (Triple-O), how they feel and why (PET), and what they say
(Sidekick). Everything anchors on the app's existing Characters and logs
to the journal. Results can be voiced by the on-device interpreter.

## Decisions (user-confirmed)

| Question | Decision |
|---|---|
| Scope | All four pieces: Triple-O core check, all 13 d66 tables, PET procedures, Sidekick dialogue + hexflower |
| Data model | Extend existing Characters (tags double as Traits); no separate players roster |
| LLM | Wire in v1: a "Voice this" action expands rolled dialogue/decisions via the interpreter service |
| Approach | Four phased PRs: pipeline/tables → Triple-O check + emulation state → PET procedures → dialogue + voice + hexflower |

## Architecture

### 1. Data pipeline — `build_emulator.py` → `assets/emulator_data.json`

Sibling of build_oracle.py / build_datasworn.py; the script is the source
of truth, content hand-transcribed from the PDFs as literals.
Self-verification (script fails loudly otherwise):
- Every d66 table: exactly 36 rows, keys 11-66 with digits 1-6, non-empty,
  no duplicates.
- d12 tables: row counts as the source has them (Agenda 11 entries keyed
  2-12 in 6 named groups with ask-questions; Focus 11 entries 2-12 with
  descriptions; dialogue 11 lines 2-12 per mood). Roll method per the
  source: 2d6-sum (curved) in play, flat d12 during creation — the engine
  exposes both; UI uses curved.
- Personality tags: 6 columns × 6 rows = 36 distinct.
- Hexflower: 19 hexes, each {topic, context(gray|red)}, adjacency map
  symmetric, the 2d6 direction overlay (12 / 2-3 / 4-5 / 6-7 / 8-9 /
  10-11 → the six neighbor directions) encoded once.
- Where `pdftotext` extraction of the source pages is clean, cross-check
  the literals against the extracted text (best-effort; visual pages like
  the hexflower are exempt and flagged for independent reviewer
  re-derivation).

Asset keys:
- `triple_o.spark`: action, focus, method, disposition, motivation,
  dynamics (d66).
- `triple_o.specific`: combat, social, exploration, delving,
  interpretation, downtime, planning (d66).
- `pet`: agenda (11: key 2-12, group, name, ask), focus (11: key 2-12,
  name, blurb), personality_tags (36), consequences (6), real_life (6).
- `sidekick`: dialogue {default, taciturn, savvy, high_strung, sassy,
  selfish} (11 lines each, 2-12), tone (6), topic (6), said_how_a (6),
  said_how_b (6), hexflower {hexes, adjacency, directions}.
- `meta.attribution`: the two license strings, displayed in-tool.

### 2. Tools — new launcher group **Party** (after NPCs & Dialog)

**Behavior Tables** (phase 1): one screen, 13 d66 roller chips under
Spark / Specific headers + combo chips (Action+Focus, Action+Method,
Action+Motivation — the zine's pairings). Result cards with
add-to-journal. Attribution footer.

**Party Emulator** (phases 2-3): optional character dropdown.
- Emulation panel: current Agenda (name + Ask question), Focus, mood,
  tokens; Roll Agenda / Roll Focus buttons.
- Triple-O check card: three text fields — Obvious required, Option/Odd
  may be left blank ("define after the roll", per the zine) — Roll (d6:
  4-6/2-3/1) and Double-Down (2d6, user picks favorite die; doubles →
  banner offering "mark a trait prominent" or "add new trait", writing to
  the character's tags/prominentTags). Group-action mode: three courses,
  optional "assign by dice" (d6 each: highest=Obvious, middle=Option,
  lowest=Odd), then the check.
- PET procedures (phase 3): ACT (roll Agenda; coin flip — heads the Ask as
  written, tails inverted; plus the modifier die 1-2 as written / 3-4
  inverted / 5-6 exaggerated, rendered as guidance text; agenda match →
  +1 token), REFOCUS (new Focus), Tag spend (roll Agenda twice, present
  both, chosen tag gets checked off until session reset), Session start
  (new Focus + d6 real-life event logged as a tag-like note), token
  stepper, d6 consequences/GM-moves roller.
- Every result has add-to-journal (titles like 'Triple-O — The Option',
  'ACT — Hero (inverted)').

**Sidekick Dialogue** (phase 4): character pick (mood persists on the
character; "no one" uses a transient mood).
- Roll Line: 2d6 on the current mood's dialogue table; if the two dice
  match, the mood changes first (roll new mood d6, shown) then the line
  rerolls — per the source. Tone/Topic/Said-How chips roll alongside.
- **Voice this** on any rolled line → interpreter `voiceLine`.
- Hexflower tab: the 19-hex flower drawn (reusing map hex-geometry
  patterns), current hex highlighted, Step = 2d6 walk via the direction
  overlay, readout of context (history/current events — switches when
  crossing color), topic, and d3 priority (me/you/us); crossing a heavy
  border = interrupt prompt + reset, per the source. Position persists per
  character.

### 3. Character extension (additive)

`Character.emulation` — nullable:
```
{ agendaRow?, focusRow?, mood?, tokens: 0, prominentTags: [String],
  usedTags: [String], hexIndex? }
```
- Tolerant fromJson; omitted from toJson when null → existing campaign
  files and characters byte-stable until the feature is used.
- Tags remain the one Trait list; `prominentTags`/`usedTags` are marks on
  it. Campaign schema stays v2 (rides inside `juice.characters.v1`).
- Tracker sheet editor gains a collapsed "Emulation" section mirroring the
  same state (single source of truth: `charactersProvider.replace`).

### 4. LLM voice

`InterpreterService.voiceLine(VoiceSeed)` → `Future<String>`.
- `VoiceSeed { line, mood, tone?, topic?, characterName?,
  characterTags: [String], genre, toneSetting, journalContext: [String] }`.
- New compact system instruction (~150 tokens): expand the rolled line
  into ONE in-character utterance, 1-2 sentences, keep the line's intent
  and the mood/tone, plain text only (no JSON).
- Plain-text parse: strip think-tags, trim. Empty → error surface with
  retry (reuses sheet-style affordances in a small dialog).
- Fake service gains voiceLine scripting; widget tests never touch the
  real service. Token budget comfortably under the lens prompt's.

## Licensing

- Pettish content: CC-BY 4.0 — attribution "PET & Sidekick © Tam H
  (hedonic.ink), CC-BY 4.0" in the Party tools.
- Triple-O content: CC-BY-SA 4.0 — attribution "Triple-O © Cezar Capacle /
  Critical Kit, CC-BY-SA 4.0"; the derived data section in our asset
  carries the same license note (house practice; app is free and
  non-commercial, compatible).

## Testing

- Pipeline self-verification (structure + counts + cross-checks).
- Engine unit tests: d66 addressing, agenda/focus lookups, ACT
  coin/modifier semantics, Triple-O check banding (4-6/2-3/1),
  double-down doubles detection, dialogue doubles→mood-change rule,
  hexflower adjacency with literal hand-derived assertions (maps-test
  precedent) + direction overlay.
- Widget tests (fakes, AppTheme.light()): check flow incl. blank
  Option/Odd, doubles→trait write to charactersProvider, group assign,
  PET ACT render, dialogue mood persistence, voice-this surfaces the
  fake's line, journal logging for each result type.
- Reviewer mandate: independently re-derive the hexflower adjacency and
  spot-check ≥3 random rows of every transcribed table against the PDFs.

## Phasing (one PR each)

1. Pipeline + Behavior Tables tool + attribution.
2. Character.emulation + Party Emulator with Triple-O check + group mode.
3. PET procedures (ACT/REFOCUS/tags/session/tokens/consequences).
4. Sidekick dialogue + voiceLine + hexflower.

## Out of scope

- Pettish's "All For One" mini-RPG.
- Intraparty-conflict automation (the source treats it as guidance; the
  check + journal cover it).
- Separate players-vs-characters rosters (decided against).
- d12 risks/actions/approaches + name lists from Pettish's extras (the
  app already has name generators; revisit on demand).

## Risks (accepted)

- ~600 hand-transcribed cells — structural verification + pdftotext
  cross-checks + reviewer spot-checks; errors are data fixes, not code.
- Hexflower adjacency is read off a figure — independent re-derivation
  required in review.
- CC-BY-SA propagation on the Triple-O-derived asset data — noted in
  asset meta and README.
