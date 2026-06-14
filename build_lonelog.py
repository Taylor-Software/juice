#!/usr/bin/env python3
"""Lonelog notation legend — source of truth for the Lonelog reference tool.

Like build_verdant.py: hand-transcribed literals here are authoritative; this
script (a) self-verifies structure (unique reserved prefixes, the 5 core
symbols, balanced block tags, well-formed examples), (b) cross-checks a few
literals against pdftotext extracts of the Lonelog PDFs when present, and
(c) emits lonelog_data.json. NEVER hand-edit the emitted JSON — edit this
script and rerun, then copy lonelog_data.json into assets/.

Source: Lonelog (en v1.5.0) core rulebook + 7 addons by Roberto Bisceglie,
CC BY-SA 4.0. The notation grammar is documented; addon *behavior* is not part
of this asset.
"""
import json
import os

OUT = "lonelog_data.json"
EXTRACT_DIR = "/tmp"  # optional pdftotext extracts: lonelog_core.txt etc.

VERSION = "1.5.0"

# The 5 core symbols (+ the @(Name) actor-attribution variant). Immutable.
SYMBOLS = [
    {"symbol": "@", "name": "Action", "role": "Player-character action",
     "example": "@ Pick the lock"},
    {"symbol": "@(Name)", "name": "Attributed action",
     "role": "Action by a named PC, companion, or NPC",
     "example": "@(Jonah) Keeps watch"},
    {"symbol": "?", "name": "Oracle question", "role": "Ask the oracle",
     "example": "? Is the guard asleep"},
    {"symbol": "d:", "name": "Mechanics roll", "role": "Dice / rule resolution",
     "example": "d: d20+5=17 vs DC 15"},
    {"symbol": "->", "name": "Result", "role": "Dice or oracle result",
     "example": "-> Yes, but..."},
    {"symbol": "=>", "name": "Consequence", "role": "Narrative outcome",
     "example": "=> The door creaks open"},
]

# Comparison operators / flags used inside d: lines.
COMPARATORS = [
    {"op": ">=", "meaning": "Meets or beats the target number (also written >=)"},
    {"op": "<=", "meaning": "Fails the target number (also written <=)"},
    {"op": "vs", "meaning": "Explicit 'versus' a TN/DC"},
    {"op": "S", "meaning": "Success flag"},
    {"op": "F", "meaning": "Fail flag"},
]

# Reserved tag prefixes (the conformance contract). source: which book owns it.
TAG_PREFIXES = [
    {"prefix": "N", "name": "NPC", "meaning": "A persistent named NPC", "source": "core"},
    {"prefix": "L", "name": "Location", "meaning": "A place", "source": "core"},
    {"prefix": "E", "name": "Event", "meaning": "An event / inline clock", "source": "core"},
    {"prefix": "PC", "name": "Player character", "meaning": "A PC stat block", "source": "core"},
    {"prefix": "Thread", "name": "Thread", "meaning": "A story thread / vow", "source": "core"},
    {"prefix": "Clock", "name": "Clock", "meaning": "Fills up toward a bad outcome", "source": "core"},
    {"prefix": "Track", "name": "Track", "meaning": "Fills up toward a goal", "source": "core"},
    {"prefix": "Timer", "name": "Timer", "meaning": "Counts down to zero", "source": "core"},
    {"prefix": "#", "name": "Reference", "meaning": "Refer to an established element", "source": "core"},
    {"prefix": "Inv", "name": "Inventory", "meaning": "A concrete item", "source": "resource"},
    {"prefix": "Wealth", "name": "Wealth", "meaning": "Currency totals", "source": "resource"},
    {"prefix": "R", "name": "Room", "meaning": "A dungeon room + status", "source": "dungeon"},
    {"prefix": "F", "name": "Foe", "meaning": "A combat foe stat tag", "source": "combat"},
    {"prefix": "Unit", "name": "Unit", "meaning": "A wargame unit", "source": "wargaming"},
    {"prefix": "Force", "name": "Force", "meaning": "A named force / army", "source": "wargaming"},
    {"prefix": "Scenario", "name": "Scenario", "meaning": "A battle scenario", "source": "wargaming"},
]

# Structural blocks: digital [NAME]/[/NAME]; analog --- NAME --- / --- END NAME ---.
BLOCKS = [
    {"name": "COMBAT", "openTag": "[COMBAT]", "closeTag": "[/COMBAT]",
     "analogOpen": "--- COMBAT ---", "analogClose": "--- END COMBAT ---",
     "purpose": "A tactical combat section (Combat addon)"},
    {"name": "DUNGEON STATUS", "openTag": "[DUNGEON STATUS]", "closeTag": "[/DUNGEON STATUS]",
     "analogOpen": "--- DUNGEON STATUS ---", "analogClose": "--- END STATUS ---",
     "purpose": "A snapshot of room states (Dungeon Crawling addon)"},
    {"name": "RESOURCES", "openTag": "[RESOURCES]", "closeTag": "[/RESOURCES]",
     "analogOpen": "--- RESOURCES ---", "analogClose": "--- END RESOURCES ---",
     "purpose": "A resource snapshot at a session boundary (Resource Tracking addon)"},
    {"name": "BATTLE", "openTag": "[BATTLE]", "closeTag": "[/BATTLE]",
     "analogOpen": "--- BATTLE ---", "analogClose": "--- END BATTLE ---",
     "purpose": "One wargame engagement (Wargaming addon)"},
    {"name": "CAMPAIGN", "openTag": "[CAMPAIGN]", "closeTag": "[/CAMPAIGN]",
     "analogOpen": "--- CAMPAIGN ---", "analogClose": "--- END CAMPAIGN ---",
     "purpose": "A campaign-state snapshot (Wargaming addon)"},
]

# The 7 addons. status: 'documented' now; flips to 'implemented' per later phase.
ADDONS = [
    {"key": "combat", "title": "Combat", "version": "1.1.0",
     "summary": "Round markers (Rd#), foe tags [F:], positions, [COMBAT] blocks.",
     "addsTags": ["F"], "addsBlocks": ["COMBAT"], "status": "documented"},
    {"key": "dungeon", "title": "Dungeon Crawling", "version": "1.1.0",
     "summary": "Per-room status tags [R:ID|status|exits] and dungeon snapshots.",
     "addsTags": ["R"], "addsBlocks": ["DUNGEON STATUS"], "status": "documented"},
    {"key": "resource", "title": "Resource Tracking", "version": "1.1.0",
     "summary": "Inventory [Inv:], wealth [Wealth:], usage dice, resource snapshots.",
     "addsTags": ["Inv", "Wealth"], "addsBlocks": ["RESOURCES"], "status": "documented"},
    {"key": "dice", "title": "Dice Notation", "version": "1.0.0",
     "summary": "A full dice-expression grammar (keep/drop, explode, success pools).",
     "addsTags": [], "addsBlocks": [], "status": "documented"},
    {"key": "cards", "title": "Cards", "version": "1.0.0",
     "summary": "Compact tokens for playing-card and tarot draws (Qs, M16r).",
     "addsTags": [], "addsBlocks": [], "status": "documented"},
    {"key": "wargaming", "title": "Wargaming", "version": "1.0.0",
     "summary": "Unit tags [Unit:], turn markers (Tn#), [BATTLE]/[CAMPAIGN] blocks.",
     "addsTags": ["Unit", "Force", "Scenario"], "addsBlocks": ["BATTLE", "CAMPAIGN"],
     "status": "documented"},
    {"key": "guidelines", "title": "Addon Guidelines", "version": "1.1.0",
     "summary": "The authoring contract: shared symbols + reserved prefixes + block syntax.",
     "addsTags": [], "addsBlocks": [], "status": "documented"},
]

# Campaign YAML front-matter schema (documents what P2 will read/write).
HEADER_FIELDS = [
    {"field": "title", "meaning": "Campaign title"},
    {"field": "ruleset", "meaning": "The host RPG system"},
    {"field": "genre", "meaning": "Genre / setting"},
    {"field": "player", "meaning": "Player name"},
    {"field": "pcs", "meaning": "Player characters"},
    {"field": "start_date", "meaning": "When the campaign began"},
    {"field": "last_update", "meaning": "Last session date"},
    {"field": "tools", "meaning": "Oracles / generators in use"},
    {"field": "themes", "meaning": "Campaign themes"},
    {"field": "tone", "meaning": "Tone"},
    {"field": "notes", "meaning": "Freeform notes"},
]

# Worked examples — one symbol per line so the highlighter reads cleanly.
EXAMPLES = [
    {"title": "A complete beat", "lines": [
        "@ Pick the warehouse lock",
        "d: d20+5=17 vs DC 15",
        "-> Success",
        "=> The door swings open [E:AlertClock 1/6]",
    ]},
    {"title": "Asking the oracle", "lines": [
        "? Is the guard asleep",
        "-> No, but... distracted",
        "=> I slip past while he yawns",
    ]},
    {"title": "Tracking elements", "lines": [
        "=> [N:Jonah|captured|wounded]",
        "=> [Thread:Rescue Jonah|Open]",
        "=> [Clock:Suspicion 3/6]",
    ]},
    {"title": "A combat round", "lines": [
        "[COMBAT]",
        "@(Goblins) Swarm the doorway",
        "d: 2d6=8",
        "=> [F:Goblins x3|Close]",
        "[/COMBAT]",
    ]},
    {"title": "A meta aside", "lines": [
        "(note: trying a flashback scene here)",
    ]},
]


def build():
    return {
        "version": VERSION,
        "license": "CC BY-SA 4.0",
        "attribution": "Lonelog (c) Roberto Bisceglie",
        "symbols": SYMBOLS,
        "comparators": COMPARATORS,
        "tagPrefixes": TAG_PREFIXES,
        "blocks": BLOCKS,
        "addons": ADDONS,
        "headerFields": HEADER_FIELDS,
        "examples": EXAMPLES,
    }


def verify(data):
    # The 5 immutable core symbols are present.
    syms = {s["symbol"] for s in data["symbols"]}
    for core in ["@", "?", "d:", "->", "=>"]:
        assert core in syms, f"missing core symbol {core}"

    # Reserved prefixes are unique (the Guidelines collision rule).
    prefixes = [p["prefix"] for p in data["tagPrefixes"]]
    assert len(prefixes) == len(set(prefixes)), "duplicate reserved prefix"
    for p in data["tagPrefixes"]:
        assert p["source"] in {"core", "combat", "dungeon", "resource", "wargaming"}, \
            f"bad source {p['source']}"

    # Block tags are balanced and bracket-wrapped.
    for b in data["blocks"]:
        assert b["openTag"] == f"[{b['name']}]", f"bad open {b['openTag']}"
        assert b["closeTag"] == f"[/{b['name']}]", f"bad close {b['closeTag']}"

    # Addons reference only declared blocks/prefixes; status is known.
    block_names = {b["name"] for b in data["blocks"]}
    prefix_set = {p["prefix"] for p in data["tagPrefixes"]}
    for a in data["addons"]:
        assert a["status"] in {"documented", "implemented"}, f"bad status {a['status']}"
        for bn in a["addsBlocks"]:
            assert bn in block_names, f"addon {a['key']} unknown block {bn}"
        for tn in a["addsTags"]:
            assert tn in prefix_set, f"addon {a['key']} unknown tag {tn}"

    # Examples are well-formed: non-empty titles and non-empty lines.
    assert len(data["examples"]) >= 4, "expected several worked examples"
    for ex in data["examples"]:
        assert ex["title"], "example missing title"
        assert ex["lines"], f"example {ex['title']} has no lines"
        for ln in ex["lines"]:
            assert isinstance(ln, str) and ln.strip(), "blank example line"


def cross_check():
    """Best-effort: confirm a few literals appear in pdftotext extracts."""
    path = os.path.join(EXTRACT_DIR, "lonelog_core.txt")
    if not os.path.exists(path):
        print(f"note: {path} missing; skipping PDF cross-check.")
        return
    with open(path, encoding="utf-8") as f:
        text = f.read()
    for needle in ["@", "Thread", "Clock"]:
        assert needle in text, f"expected '{needle}' in {path}"
    print("PDF cross-check passed.")


if __name__ == "__main__":
    data = build()
    verify(data)
    cross_check()
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"wrote {OUT}: {len(data['symbols'])} symbols, "
          f"{len(data['tagPrefixes'])} prefixes, {len(data['addons'])} addons, "
          f"{len(data['examples'])} examples")
