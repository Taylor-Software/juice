# Discoverability submissions (cycle 3 item E)

Drafted 2026-06-12 from the landscape scan: solo-RPG players discover tools
through community channels, not app stores. Four channels below, in impact
order. Repo metadata (description + 10 topics) is already live.

**Owner actions required** — each submission publishes content under your
name; review and post (or tell Claude to, where noted).

---

## 1. itch.io page (needs your itch.io account)

itch.io's `solo-rpg` tools tag is a primary discovery surface (One Page Solo
Engine and Lonelog both live there). Create a free **tool** project:

- **Title:** Juice Oracle — solo RPG journal & oracles
- **Project URL slug:** juice-oracle
- **Classification:** Tools / Physical game aids
- **Kind of project:** HTML — upload a zip of `build/web` (`flutter build
  web` output) so it plays embedded; set viewport 1280×832, "Mobile
  friendly" on. (Alternative: classification "link" pointing at
  https://taylor-software.github.io/juice/ — less discoverable than playable
  HTML.)
- **Pricing:** $0 / no payments (license obligations: Juice and Mythic
  content are non-commercial).
- **Short description / tagline:** Roll it, then remember it — a campaign
  journal with verified Juice, Mythic GME, and Ironsworn oracles built in.
- **Body text:**

> Juice Oracle is a free, offline-friendly companion for solo tabletop
> roleplaying. The journal is the home surface: scenes, prose, and every
> roll you keep land in one stream you can export as Markdown or a styled
> HTML page.
>
> - **Oracles:** the complete Juice oracle (every table machine-verified
>   against the source PDF), Mythic GME 2e Fate Chart + all 47 meaning
>   tables, a generic Roll High oracle, and the full Ironsworn / Delve /
>   Starforged / Sundered Isles oracle + move set from official Datasworn
>   data.
> - **Tools:** full dice-notation roller (keep/drop, advantage, Fate dice),
>   flexible character sheets, an initiative-and-tracks encounter tracker,
>   oracle-grown dungeon maps and travel-revealed hex maps.
> - **Optional on-device AI:** expand any logged result into four short
>   readings (literal / symbolic / complication / foreshadow) with a small
>   language model that runs entirely in your browser or on your phone —
>   one-time download, nothing you write ever leaves your device. The dice
>   stay authoritative.
> - **Your data is yours:** no accounts, no server. Campaigns persist
>   locally and export/import as JSON files you can keep in your own cloud
>   folder.
>
> Attribution: Juice oracle © jrruethe / thunder9861 (CC BY-NC-SA 4.0);
> Mythic GME © Word Mill Games (CC-BY-NC 4.0); Ironsworn-family content
> © Shawn Tomkin via Datasworn (CC-BY / CC-BY-NC-SA per ruleset). Source:
> https://github.com/Taylor-Software/juice

- **Tags:** solo-rpg, oracle, gm-tools, journaling, ttrpg, dice,
  ironsworn, mythic (max allowed; in this order)
- **Screenshots:** docs/screenshots/journal.png plus 2-3 more taken from
  your browser (tool launcher open, dungeon map, interpreter cards).

## 2. awesome-ironsworn PR (Claude can open this with your OK)

Repo: https://github.com/billiam/awesome-ironsworn — add under the
appropriate Tools/Apps section:

```markdown
- [Juice Oracle](https://taylor-software.github.io/juice/) - Free web/PWA campaign journal with the full Ironsworn, Delve, Starforged, and Sundered Isles oracle and move sets (from official Datasworn data), plus Mythic GME and Juice oracles, dice notation, character sheets, encounter tracker, maps, and an optional on-device AI oracle interpreter. No accounts; campaigns export as files. ([source](https://github.com/Taylor-Software/juice))
```

Process: fork → branch → one-line addition matching their list style →
PR titled "Add Juice Oracle". **Say the word and Claude forks from your gh
account and opens it.**

## 3. Tomkin Press community resources (your submission)

https://tomkinpress.com/pages/community-resources lists community tools —
effectively the official Ironsworn-family channel. Find the submission
route on that page (form or email) and send:

> **Juice Oracle** — https://taylor-software.github.io/juice/
> Free web app (PWA, offline-capable, no accounts): a campaign journal with
> the complete Ironsworn, Delve, Starforged, and Sundered Isles oracles and
> moves built from official Datasworn data, alongside dice tools, character
> sheets, an encounter tracker, and procedural maps. Per-ruleset licensing
> and attribution are displayed in-app (CC-BY for classic/Delve/Starforged,
> CC-BY-NC-SA for Sundered Isles). Source:
> https://github.com/Taylor-Software/juice

## 4. randroll.com pitch (optional, your email)

randroll runs solo-RPG tool guides and a newsletter. Short pitch:

> Hi — I built Juice Oracle, a free no-account web companion for solo play:
> campaign journal + verified Juice/Mythic GME/Ironsworn-family oracles,
> dice, sheets, encounter tracker, maps, and an optional fully-on-device AI
> oracle interpreter (no cloud, one-time model download). Might fit a tools
> roundup: https://taylor-software.github.io/juice/

---

Done already (no action needed): GitHub repo description + topics
(solo-rpg, ttrpg, oracle, mythic-gme, ironsworn, starforged,
solo-roleplaying, journaling, flutter, pwa); README hero screenshot +
"Play it now" link.
