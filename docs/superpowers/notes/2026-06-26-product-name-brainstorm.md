# Product name brainstorm — adopted: **Loreseer**

**Date:** 2026-06-26
**Status:** ADOPTED. The display name was renamed from *Solo Adventurer's Journal*
to **Loreseer** (tagline "The oracle behind your adventure") in this same change —
display strings only (in-app titles, platform manifests, web title/manifest,
README H1, pubspec/THIRD_PARTY/design-overview prose). Internal `juice` identifiers
are untouched per `CLAUDE.md`. This note records the exploration behind the choice.

## Brief

Rename target: the **display name only** (in-app titles, platform manifests, web
title/manifest, README H1). Per `CLAUDE.md`, the *Juice oracle* identity and the
internal `juice_oracle` / `juice.*` / `net.taylorsoftware.juice` identifiers stay
put — a rename touches display strings, not stable ids.

Chosen lane (from brainstorm with the maintainer):
- **Vibe:** mystical / evocative (north star was *Soothsayer*).
- **Brandable:** own the word, not descriptive-on-the-tin.
- **Angle:** lean into the **GM-tool / unseen-GM** framing (a feature being added).

## Front-runner: Loreseer

A coined compound — **lore·seer** — that reads on two levels at once:
*one who sees the unfolding story* and the *GM-as-oracle* role. The word already
carries fantasy resonance to players but has no commercial owner.

### Clearance findings (web check, 2026-06-26)

- **No product collision.** No app, game, or company called "Loreseer" on the App
  Store, Steam, or itch. The word appears only as fantasy flavor (a Minecraft-server
  faith title; a web-serial term).
- **Soft phonetic neighbors only:** *Lore Seeker* (a deck-building game, two words)
  and *Loreseeker Games* (a studio making a mermaid game, *SIREN*). Different
  spelling, different niche — not our lane.
- **Domain:** `loreseer.com` returned **HTTP 403**, which is inconclusive (something
  responds at the host — possibly parked/registered, not necessarily free).
  **TODO before adoption:** confirm authoritative status at a registrar
  (Namecheap/Cloudflare). `loreseer.app` is a strong fallback and arguably better
  for an app brand.

### Why it won the bake-off

Three finalists were clearance-tested:

| Name | TTRPG collision | Ownability | Verdict |
|---|---|---|---|
| **Loreseer** | none (only fantasy-flavor uses) | high (coined word) | **pick** — clear + brandable |
| **Sayer** | none in solo-RPG | low — common word + surname; `sayers.com` is a 40-yr IT consultancy; trademark/SEO crowding | runner-up if minimal/modern feel preferred |
| **Divinum** | **direct** — live action game on Steam (app 1148130), `divinumgame.com`, `@DivinumGame` | blocked — same industry, live brand owns domain/handle | retired |

## Creative direction (if adopted)

### Positioning
> **Loreseer** — your unseen GM. The app sees the story so you can live it.

### Taglines
- Hero (atmosphere): *"It sees what happens next."*
- Store subtitle (clarity): *"Solo & GM-less RPG companion."*
- Alternates: *"Every story has a seer." / "No GM? No problem." / "Your table of one."*

### Wordmark / styling
- Lowercase **`loreseer`** for the icon wordmark + UI; title-case **Loreseer** in prose.
- Emphasize the **lore·seer** seam (weight/color shift, or an iris motif in the "ee").
- Icon directions (fit the facts-only, no-rulebook-IP posture): an eye formed from an
  open book; a die with an eye on its up-face; a keyhole/iris hybrid.
- Palette: deep indigo/violet + warm gold (prophecy/candlelight; also nods to the
  light-timer mechanic). Avoid generic-fantasy green.

### Bonus: names the GM feature
The brand personifies the in-app AI GM seam as **"the Seer"** — *"Ask the Seer,"*
*"the Seer narrates,"* *"the Seer sees a complication."* Turns the product name into
the unseen-GM voice, which is exactly the framing the new GM angle wants.

## If/when adopted — rename checklist (display strings only)

- In-app titles, platform manifests (iOS/Android/macOS), web `index.html` title +
  `manifest.json`, README H1.
- Do **NOT** touch: `'juice'`/`'Juice'` oracle id, `fate-juice`, `juice_oracle`
  package, `juice.*` SharedPreferences keys, `juice-oracle` campaign marker,
  `.juice.json`/`.juice.zip` extensions, `net.taylorsoftware.juice` bundle id.
