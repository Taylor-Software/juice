#!/usr/bin/env python3
"""Verdant Hexcrawling — source of truth for the Verdant Journey tool data.

Like build_emulator.py: hand-transcribed literals here are authoritative; this
script (a) self-verifies table structure, (b) cross-checks PDF-sourced literals
against a pdftotext extract when present, and (c) emits assets/verdant_data.json.
NEVER hand-edit the emitted JSON — edit this script and rerun.

Sources:
  PDF (supplied): Verdant - Rules Brochure.pdf, Journey Sheet, Printable Card Sheets.
  Website v1.2 "Mate" (no PDF): https://verdant.ibir.cc — quick_encounters,
    transport_modes, and the corrected natural-12 random-encounter rule.
Verdant (c) 2026 Vince Pinton / Ibir Publishing, CC BY-NC-SA 4.0.
"""
import json
import os

OUT = "verdant_data.json"
RULES_EXTRACT = "/tmp/verdant_rules.txt"

# Twelve trait icon keys -> display names (brochure legend).
TRAITS = {
    "arduous": "Arduous Terrain",
    "bountiful": "Bountiful",
    "broken_paths": "Broken Paths",
    "fast_trajectory": "Fast Trajectory",
    "foliage": "Foliage",
    "impassable": "Impassable Terrain",
    "nighttime": "Nighttime",
    "raining": "Raining",
    "reduced_visibility": "Reduced Visibility",
    "scarcity": "Scarcity",
    "vantage_point": "Vantage Point",
    "waterways": "Waterways",
}

# Journey Tasks (brochure table + task cards + website Journey Tasks page).
# types: T=Traveling, S=Stationary, C=Concurrent. easier/harder are trait keys.
JOURNEY_TASKS = [
    {"name": "Bushwhack", "attribute": "STR", "types": ["T"],
     "success": "Safer", "failure": "Riskier",
     "easier": [], "harder": [], "dependency": "foliage"},
    {"name": "Camouflage", "attribute": "DEX", "types": ["S"],
     "success": "Safer", "failure": "Riskier",
     "easier": ["foliage", "reduced_visibility"], "harder": [], "dependency": None},
    {"name": "Entertain", "attribute": "CHA", "types": ["T", "S", "C"],
     "success": "Special", "failure": "Riskier",
     "easier": [], "harder": [], "dependency": None},
    {"name": "Explore", "attribute": "WIS", "types": ["T", "S", "C"],
     "success": "Special", "failure": "Riskier",
     "easier": ["vantage_point"], "harder": ["broken_paths", "reduced_visibility"],
     "dependency": None},
    {"name": "Forage", "attribute": "INT", "types": ["T", "S", "C"],
     "success": "Special", "failure": "Riskier",
     "easier": ["bountiful", "foliage"], "harder": ["scarcity"], "dependency": None},
    {"name": "Keep Watch", "attribute": "WIS", "types": ["T", "S"],
     "success": "Safer", "failure": "Riskier",
     "easier": ["vantage_point"], "harder": ["foliage", "reduced_visibility"],
     "dependency": None},
    {"name": "Navigate", "attribute": "INT", "types": ["T"],
     "success": "Safer", "failure": "Riskier",
     "easier": ["vantage_point"], "harder": ["broken_paths", "reduced_visibility"],
     "dependency": None},
    {"name": "Scout Ahead", "attribute": "DEX", "types": ["T"],
     "success": "Safer", "failure": "Riskier",
     "easier": ["foliage"], "harder": ["broken_paths"], "dependency": None},
    {"name": "Set Camp", "attribute": "INT", "types": ["S"],
     "success": "Safer", "failure": "Riskier",
     "easier": [], "harder": ["raining"], "dependency": "firewood"},
    {"name": "Sleep", "attribute": "CON", "types": ["S", "C"],
     "success": "Rest", "failure": "No Rest",
     "easier": [], "harder": [], "dependency": None},
    {"name": "Something Else", "attribute": None, "types": ["T", "S", "C"],
     "success": "???", "failure": "???",
     "easier": [], "harder": [], "dependency": None},
    {"name": "Use Spyglass", "attribute": "WIS", "types": ["S"],
     "success": "Safer", "failure": "Riskier",
     "easier": [], "harder": ["reduced_visibility"], "dependency": "Spyglass"},
]

# Ten terrain types (brochure terrain table + terrain cards).
TERRAIN = [
    {"key": "caatinga", "name": "Caatinga", "traits": ["vantage_point"],
     "special": "Blossoms"},
    {"key": "desert", "name": "Desert",
     "traits": ["fast_trajectory", "vantage_point", "scarcity"], "special": None},
    {"key": "floodplain", "name": "Floodplain",
     "traits": ["fast_trajectory", "bountiful", "vantage_point"], "special": "Floods"},
    {"key": "forest", "name": "Forest", "traits": ["foliage", "bountiful"],
     "special": None},
    {"key": "grassland", "name": "Grassland",
     "traits": ["fast_trajectory", "bountiful", "vantage_point"], "special": None},
    {"key": "hills", "name": "Hills", "traits": ["vantage_point"], "special": None},
    {"key": "marsh", "name": "Marsh",
     "traits": ["bountiful", "vantage_point", "broken_paths", "waterways"],
     "special": None},
    {"key": "mountain", "name": "Mountain",
     "traits": ["broken_paths", "vantage_point"], "special": None},
    {"key": "swamp", "name": "Swamp",
     "traits": ["foliage", "bountiful", "broken_paths", "waterways"], "special": None},
    {"key": "water", "name": "Water", "traits": ["impassable", "waterways"],
     "special": None},
]

# d12 Points of Interest (brochure).
POINTS_OF_INTEREST = [
    (1, "Uninhabited Cave", "Makes it Safer to spend the night and protects when it's Raining."),
    (2, "Wooden Watchtower", "Gives a Vantage Point. Old and creaky; has a chance of collapsing."),
    (3, "Hunting Trail", "Fast Trajectory when traveling through the trail, but is Deadly."),
    (4, "Abandoned Chapel", "Dedicated to a random deity. Possibly haunted."),
    (5, "Buried Treasure", "Recent rains left the chest partially revealed. Guarded by a will-o'-wisp."),
    (6, "Grove of Heart Palms", "Trees with heart-shaped fronds. 1d4 chutes can be foraged; eating one has the effect of a healing potion."),
    (7, "Adventurers' Cache", "A rival adventuring party stashed 1d6 torches and 1d6 rations here."),
    (8, "Desecrated Monument", "Old statue emanates necromantic energy. Attracts ghouls at night."),
    (9, "Fey-Kept Orchard", "Forage automatically succeeds here, but angers a nearby curupira."),
    (10, "Stargazer Monoliths", "Sleeping in this henge gives prophetic dreams. Get a Luck Token."),
    (11, "Ancient Portals", "Lies inactive. Reactivation connects it to other portals."),
    (12, "Earthmote", "Floating over the land. Atop is the cabin of a wizard named Randall, who gives good advice, making it Safer for the next 3 days."),
]

# d10 Quick Encounters (WEBSITE ONLY — verdant.ibir.cc, no PDF source).
QUICK_ENCOUNTERS = [
    (1, "Dark Clouds", "It will rain soon. Raining and Reduced Visibility next Watch."),
    (2, "Hungry Vermin", "A rat got into someone's backpack and ate all their rations."),
    (3, "Mosquito Fever", "Easy CON or take 1d4 CON damage (can't heal while sick). Repeat the check once per day; ends on success."),
    (4, "Shooting Star", "Make a wish! Someone gets a Luck Token."),
    (5, "Landslide", "Soil shifts beneath your feet! Normal DEX or take 2d6 damage."),
    (6, "Hole in Backpack", "A character notices their backpack is ruptured. Lose an item."),
    (7, "Quicksand", "Someone falls face-first. Hard DEX to exit, Hard STR to be pulled out. CON check each round to hold breath or take 1d6 damage."),
    (8, "Bad Omen", "A black cat crosses the path or ominous bird sounds bring bad luck. Roll with disadvantage next Watch."),
    (9, "Psychic Crickets", "An unnerving humming sound. Normal CHA or take 2d6 damage."),
    (10, "A Coin on the Ground", "1gp. Must be your lucky day!"),
]

# Terrain features (brochure).
TERRAIN_FEATURES = [
    {"name": "Cliff", "text": "Treat as Impassable Terrain. Climbing: the party can try to climb past if all beat a Normal STR check."},
    {"name": "River", "text": "Treat as Impassable Terrain with Waterways. Crossing: the party can try to swim past if all beat a STR check (Hard for rapids, Easy for slow streams)."},
    {"name": "Road", "text": "Automatic success on Navigate and Fast Trajectory when keeping to the road. Maintained Roads are usually patrolled: Safer if party members aren't outlaws, otherwise Deadly."},
]

# Modes of Transportation (WEBSITE ONLY).
TRANSPORT_MODES = [
    {"key": "mount", "name": "Mount", "text": "Mounts made for fast transport (e.g. horses) speed up travel. Rush: once per day, gain an additional Journey Round in the same watch. You can't rush from a terrain with Broken Paths."},
    {"key": "boat", "name": "Boat", "text": "Canoes, sailboats, longships and other vessels travel through Waterways. Boats not powered by the party aren't limited to 2 Watches of travel a day."},
    {"key": "airship", "name": "Airship", "text": "Airships can travel over Impassable Terrain and ignore Arduous Terrain."},
]

CONSTANTS = {
    "erBase": 4,            # ER = erBase + (partySize // 2)
    "safer": 2,
    "riskier": -1,
    "deadly": -2,
    "pace": {"slow": 2, "fast": -2},   # added to the round's baseline Safety
    "watches": [
        {"n": 1, "name": "Morning", "night": False},
        {"n": 2, "name": "Afternoon", "night": False},
        {"n": 3, "name": "Evening", "night": True},
        {"n": 4, "name": "Night", "night": True},
    ],
    # Live website v1.2 rule (supersedes the brochure's stale natural-1 rule):
    "encounterRule": "d12 + Safety Level < ER => dangerous encounter; a natural 12 => an encounter with no immediate danger.",
}


def build():
    return {
        "license": "CC BY-NC-SA 4.0",
        "attribution": "Verdant Hexcrawling (c) 2026 Vince Pinton / Ibir Publishing",
        "source": "https://verdant.ibir.cc",
        "traits": TRAITS,
        "journey_tasks": JOURNEY_TASKS,
        "terrain": TERRAIN,
        "points_of_interest": [
            {"n": n, "name": name, "text": text} for (n, name, text) in POINTS_OF_INTEREST
        ],
        "quick_encounters": [
            {"n": n, "name": name, "text": text} for (n, name, text) in QUICK_ENCOUNTERS
        ],
        "terrain_features": TERRAIN_FEATURES,
        "transport_modes": TRANSPORT_MODES,
        "constants": CONSTANTS,
    }


def verify(data):
    STATS = {"STR", "DEX", "CON", "INT", "WIS", "CHA"}
    traits = data["traits"]
    assert len(traits) == 12, f"expected 12 traits, got {len(traits)}"

    tasks = data["journey_tasks"]
    assert len(tasks) == 12, f"expected 12 tasks, got {len(tasks)}"
    for t in tasks:
        if t["attribute"] is not None:
            assert t["attribute"] in STATS, f"bad attribute {t['attribute']}"
        for ty in t["types"]:
            assert ty in ("T", "S", "C"), f"bad type {ty}"
        for key in t["easier"] + t["harder"]:
            assert key in traits, f"task {t['name']} unknown trait {key}"
        if t["dependency"] in traits:
            pass  # trait-keyed dependency
    terr = data["terrain"]
    assert len(terr) == 10, f"expected 10 terrain, got {len(terr)}"
    keys = {x["key"] for x in terr}
    assert len(keys) == 10, "duplicate terrain key"
    for x in terr:
        for key in x["traits"]:
            assert key in traits, f"terrain {x['name']} unknown trait {key}"

    poi = data["points_of_interest"]
    assert [p["n"] for p in poi] == list(range(1, 13)), "POI must be contiguous 1..12"
    qe = data["quick_encounters"]
    assert [q["n"] for q in qe] == list(range(1, 11)), "quick encounters must be 1..10"
    assert len(data["terrain_features"]) == 3
    assert len(data["transport_modes"]) == 3
    assert {m["key"] for m in data["transport_modes"]} == {"mount", "boat", "airship"}

    w = data["constants"]["watches"]
    assert [x["n"] for x in w] == [1, 2, 3, 4]
    assert [x["night"] for x in w] == [False, False, True, True], "Evening+Night are night"


def cross_check():
    """Best-effort: confirm a few brochure literals appear in the pdftotext extract."""
    if not os.path.exists(RULES_EXTRACT):
        print(f"note: {RULES_EXTRACT} missing; skipping PDF cross-check.")
        return
    with open(RULES_EXTRACT, encoding="utf-8") as f:
        text = f.read()
    for needle in ["Bushwhack", "Camouflage", "Earthmote", "Encounter Risk", "Watches"]:
        assert needle in text, f"expected '{needle}' in {RULES_EXTRACT}"
    print("PDF cross-check passed.")


if __name__ == "__main__":
    data = build()
    verify(data)
    cross_check()
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"wrote {OUT}: {len(data['journey_tasks'])} tasks, "
          f"{len(data['terrain'])} terrain, {len(data['quick_encounters'])} quick encounters")
