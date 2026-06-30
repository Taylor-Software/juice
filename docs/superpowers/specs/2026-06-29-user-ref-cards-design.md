# User-Authored Ref Cards — Design

**Date:** 2026-06-29
**Status:** Approved (brainstorming)
**Context:** Second half of the in-app rules-reference effort (the first was the authored
Rules QuickRef, `2026-06-29-rules-quickref-design.md`, shipped #225). Lets players author
their own quick-reference cards — house rules, a personal cheat sheet, rules for a system
that ships no authored card (e.g. `custom`).

## Summary

User-authored ref cards, reusing the just-shipped `QuickRefCard`/`QuickRefSection` model so
they render identically to the 7 authored cards in the same `QuickRefView`. Cards are
**app-global** (device-wide, reusable across campaigns — like Custom Tables + Bestiary).
Authored via a simple title + `#`-heading textarea dialog. They appear under the active
system's authored card on all four QuickRef surfaces with **zero per-surface work** (the
surfaces already embed `QuickRefView(useProvider: true)`).

**Licensing:** none — all content is user-authored.

## Architecture

### Engine — `lib/engine/quick_ref.dart` (additions, pure)

```dart
/// A user-authored ref card. Renders as a QuickRefCard.
class UserRefCard {
  const UserRefCard({required this.id, required this.title, required this.sections});
  final String id;
  final String title;
  final List<QuickRefSection> sections;

  QuickRefCard toQuickRefCard() =>
      QuickRefCard(system: 'custom', title: title, sections: sections);

  Map<String, dynamic> toJson();          // {id, title, sections: [{title, lines}]}
  static UserRefCard? maybeFromJson(Map<String, dynamic>? json);  // tolerant; null on bad
}

/// Parse an editor body into sections (pure). Rules:
///  - a line starting with '# ' (or '#') begins a new section with that heading;
///  - other non-empty lines become bullet lines of the current section;
///  - non-empty lines BEFORE the first heading go into a leading section titled 'Notes';
///  - blank lines are ignored.
/// Returns [] for empty/whitespace input.
List<QuickRefSection> parseRefSections(String text);
```

`UserRefCard` carries an `id` (for edit/delete) that `QuickRefCard` lacks, and converts to a
`QuickRefCard` for rendering. `parseRefSections` is the single source of truth for the
editor → model transform.

### Persistence — `lib/state/providers.dart`

`userRefCardsProvider` — an **app-global** `AsyncNotifier<List<UserRefCard>>` keyed
`juice.userrefcards.v1`, **NOT session-scoped, NOT in campaign export** (mirrors
`customTablesProvider` / `bestiaryProvider` exactly). Methods: `add(UserRefCard)`,
`replace(UserRefCard)`, `remove(String id)`, each persisting via SharedPreferences.

### UI — extend `QuickRefView` (`lib/features/quick_ref_view.dart`)

Today `QuickRefView` takes a `card` or reads `systemQuickRefProvider` (`useProvider: true`).
Change:

- **Explicit `card:` mode** — unchanged: pure read-only render of that one card (keeps the
  existing widget tests + any direct embeds behavior-identical).
- **`useProvider: true` mode** — becomes a composite that also watches
  `userRefCardsProvider`. Renders, in one scroll view:
  1. the active system's authored card (if any),
  2. each user card (`userRefCardsProvider`), each with `quickref-edit-<id>` +
     `quickref-delete-<id>` icon actions,
  3. a `quickref-add` "＋ Add card" button.
- **Empty state** — when there is no authored card AND no user cards, show the existing
  "No quick reference for this system yet." text **plus** the `quickref-add` button (so a
  no-card system can still be given user cards).

`showRefCardEditor(BuildContext, WidgetRef, {UserRefCard? existing})` — a dialog with a
title `TextField` (`refcard-title`) and a body `TextField` (`refcard-body`, multiline,
`#`-heading syntax, seeded from the existing card's sections when editing) + Save
(`refcard-save`) / Delete (`refcard-delete`, edit mode only). Save parses the body via
`parseRefSections`, builds a `UserRefCard` (new id on create, same id on edit), and calls
`add`/`replace`. Empty title or empty parsed sections → no save (treat as cancel). Mirrors
the Custom Tables `_showTableDialog` pattern.

### Surfaces — none changed

Encounter (`enc-rules`), Run (`run-panel-quickref`), `/rules`, and the Reference Rules
segment all embed `QuickRefView(useProvider: true)`, so user cards + the Add button appear
on every surface automatically. No edits to those files.

## Data flow

`showRefCardEditor` → `parseRefSections(body)` → `UserRefCard` → `userRefCardsProvider.add/
replace` → persisted to `juice.userrefcards.v1` → `QuickRefView` (watching the provider)
rebuilds → card renders via `toQuickRefCard()` through the existing section renderer.

## Testing

- **`test/user_ref_card_test.dart`** (pure):
  - `parseRefSections`: `# Heading` starts sections; pre-heading lines → a leading 'Notes'
    section; blank lines ignored; empty input → `[]`; a body with two headings → two
    sections with the right lines.
  - `UserRefCard.toJson`/`maybeFromJson` round-trip; `maybeFromJson(null)` and a malformed
    map → null; `toQuickRefCard()` carries title + sections.
- **`test/user_ref_cards_view_test.dart`** (widget):
  - With `userRefCardsProvider` overridden to one card + `systemQuickRefProvider` null,
    `QuickRefView(useProvider: true)` shows the user card's title + a section line and the
    `quickref-add` button; the empty-state add button shows when both are empty.
  - (Editor dialog interaction — open via `quickref-add`, type title/body, save, assert the
    notifier got a card — as a light widget test with a `ProviderContainer` read-back.)

Follow the existing app-global-provider test setup (mock prefs; no asset loads).

## Files touched

**Changed**
- `lib/engine/quick_ref.dart` — `UserRefCard` + `parseRefSections`.
- `lib/state/providers.dart` — `userRefCardsProvider` (+ notifier).
- `lib/features/quick_ref_view.dart` — composite `useProvider` render + `showRefCardEditor`.

**New**
- `test/user_ref_card_test.dart`, `test/user_ref_cards_view_test.dart`.

## Non-goals / deferred

- No per-system tagging of user cards (all user cards show regardless of active system).
- No markdown beyond `#` headings + bullet lines.
- No reordering, no import/export of card packs, no per-campaign scope.
- No editing of the 7 authored cards (those stay code-owned).
