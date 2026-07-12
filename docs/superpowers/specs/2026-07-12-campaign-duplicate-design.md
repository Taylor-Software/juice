# Campaign duplicate ("same setup, new story") — design

**Date:** 2026-07-12
**Source:** QoL assessment #8 — reuse a campaign's configuration for the next
adventure without re-walking the wizard.

## Design

`SessionsNotifier.duplicateSetup(sourceId)` creates and activates a new
campaign named "\<name\> — new story" copying **setup only**: enabled
systems, D&D edition, `SessionMeta.genre`, the identity icon, and the
session-scoped settings blob (`juice.settings.v1.<id>` — genre, tone,
default oracle, header state). The identity hue is freshly derived so the
copy is visually distinct. No play-state keys are copied — journal, threads,
maps, decks, etc. all start empty. Rulesets are app-global and need no copy.

UI: a `session-duplicate-<id>` icon button ("New story with this setup") on
each campaigns-drawer row; on tap the new campaign is created, activated,
and entered via the normal `enterCampaign` path.

## Tests

`test/campaign_duplicate_test.dart`: full setup copy + fresh play state +
active switch; unknown-id no-op.
