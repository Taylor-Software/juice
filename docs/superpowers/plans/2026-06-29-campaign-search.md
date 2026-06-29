# Campaign Search — Implementation Plan (Epic Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A single "Search campaign" affordance covering journal entries, threads,
rumors, tracks, and characters — closing the "entities are islands" information
retrieval gap. The journal-only `searchEntries` already works; this extends it.

**Architecture:** Pure `searchCampaign` function in a new `lib/engine/campaign_search.dart`
engine leaf (mirrors `journal_search.dart`). A modal `CampaignSearchSheet`
(`lib/features/campaign_search_sheet.dart`) shows grouped live results; tapping
navigates via the existing `goTo(Destination, subtab)` primitive. Wired from a new
`shell-search-campaign` `IconButton` in the shell app-bar (always-visible, every verb).

**Entity → navigation mapping:**
| Kind | destination | subtab |
|------|------------|--------|
| journalEntry | journal | '' |
| thread | track | 'threads' |
| rumor | track | 'rumors' |
| track | track | 'tracks' |
| character | sheet | 'characters' |

**Tech Stack:** Dart/Flutter, flutter_riverpod, package:test/flutter_test.

---

## File structure

- Create: `lib/engine/campaign_search.dart` — pure `CampaignSearchResult` + `searchCampaign`
- Create: `test/campaign_search_test.dart` — multi-entity search tests
- Create: `lib/features/campaign_search_sheet.dart` — modal sheet UI
- Modify: `lib/shared/home_shell.dart` — add `shell-search-campaign` button

---

## Task 1: Pure `CampaignSearchResult` model + `searchCampaign`

**Files:**
- Create `lib/engine/campaign_search.dart`
- Create `test/campaign_search_test.dart`

### Step 1: failing tests → Step 2: implement → Step 3: pass → Step 4: commit

See inline execution below.

---

## Task 2: `CampaignSearchSheet` UI

**Files:**
- Create `lib/features/campaign_search_sheet.dart`

Search-as-you-type modal sheet. Watches all five providers. Groups results by kind.
Taps call `goTo` + pop. No new persistence.

---

## Task 3: Wire shell button

**Files:**
- Modify `lib/shared/home_shell.dart:551-558`
  Add `IconButton(key: Key('shell-search-campaign'), icon: Icon(Icons.manage_search), ...)`
  BEFORE the existing search button (tools search), so the order is:
  campaign-search | tools-search | help | settings.

---

## Task 4: Ship

Full suite green → analyze clean → PR → merge.
