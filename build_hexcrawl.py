#!/usr/bin/env python3
"""Generic, system-agnostic hexcrawl content library — source of truth for the
Hexcrawl toolkit. Authored content (NOT lifted from any game); informed by
common hexcrawl procedure. Same rail as build_verdant.py: this script is
authoritative, self-verifies structure, and emits hexcrawl_data.json. Copy the
output into assets/; never hand-edit the JSON.
"""
import json

CLIMATES = ["cold", "temperate", "hot"]

# Generic terrains. difficulty = navigation/travel difficulty (2 easy .. 4 hard).
TERRAINS = [
    {"key": "arctic", "name": "Arctic", "climates": ["cold"], "difficulty": 3,
     "travelNote": "Slow, exposed; risk of cold.", "features": ["Ice field", "Frozen river", "Snowdrift"]},
    {"key": "coast", "name": "Coast", "climates": ["cold", "temperate", "hot"], "difficulty": 2,
     "travelNote": "Open shoreline; tidal hazards.", "features": ["Tidal flats", "Sea cliffs", "Driftwood"]},
    {"key": "desert", "name": "Desert", "climates": ["hot"], "difficulty": 3,
     "travelNote": "Open but harsh; water is scarce.", "features": ["Dunes", "Dry wash", "Rock spire"]},
    {"key": "forest", "name": "Forest", "climates": ["temperate"], "difficulty": 3,
     "travelNote": "Dense cover slows travel.", "features": ["Old grove", "Game trail", "Fallen timber"]},
    {"key": "hills", "name": "Hills", "climates": ["cold", "temperate", "hot"], "difficulty": 3,
     "travelNote": "Rolling ground; many vantage points.", "features": ["Rocky knoll", "Hidden vale", "Cairn"]},
    {"key": "jungle", "name": "Jungle", "climates": ["hot"], "difficulty": 4,
     "travelNote": "Thick, humid, hard going.", "features": ["Vine wall", "Canopy gap", "Mud wallow"]},
    {"key": "marsh", "name": "Marsh", "climates": ["temperate", "hot"], "difficulty": 4,
     "travelNote": "Boggy, easy to get mired or lost.", "features": ["Reed beds", "Black pool", "Sunken log"]},
    {"key": "mountains", "name": "Mountains", "climates": ["cold", "temperate"], "difficulty": 4,
     "travelNote": "Steep climbs; thin air.", "features": ["Narrow pass", "Sheer cliff", "Scree slope"]},
    {"key": "plains", "name": "Plains", "climates": ["cold", "temperate", "hot"], "difficulty": 2,
     "travelNote": "Open and fast.", "features": ["Tall grass", "Lone tree", "Old road"]},
    {"key": "taiga", "name": "Taiga", "climates": ["cold"], "difficulty": 3,
     "travelNote": "Cold conifer forest.", "features": ["Snowy pines", "Frozen bog", "Logging cut"]},
    {"key": "wastes", "name": "Wastes", "climates": ["temperate", "hot"], "difficulty": 3,
     "travelNote": "Broken, barren badlands.", "features": ["Cracked earth", "Ash flat", "Twisted rock"]},
    {"key": "water", "name": "Open water", "climates": ["cold", "temperate", "hot"], "difficulty": 2,
     "travelNote": "Crossed by boat only.", "features": ["Open swell", "Hidden reef", "Floating debris"]},
]

# climate -> weighted starting-terrain table.
CLIMATE_TO_TERRAIN = {
    "cold": [("plains", 3), ("taiga", 3), ("hills", 2), ("arctic", 2), ("mountains", 2), ("coast", 1)],
    "temperate": [("forest", 3), ("plains", 3), ("hills", 2), ("marsh", 2), ("mountains", 1), ("coast", 1), ("wastes", 1)],
    "hot": [("plains", 3), ("desert", 3), ("jungle", 2), ("hills", 2), ("wastes", 1), ("coast", 1)],
}

# terrain -> weighted neighbouring-terrain table (drives H2 map growth).
NEIGHBOURING = {
    "arctic": [("arctic", 3), ("taiga", 2), ("mountains", 2), ("coast", 1)],
    "coast": [("coast", 2), ("plains", 2), ("hills", 1), ("marsh", 1), ("water", 2)],
    "desert": [("desert", 3), ("wastes", 2), ("hills", 1), ("plains", 1)],
    "forest": [("forest", 3), ("hills", 2), ("plains", 2), ("marsh", 1), ("mountains", 1)],
    "hills": [("hills", 3), ("plains", 2), ("mountains", 2), ("forest", 1)],
    "jungle": [("jungle", 3), ("marsh", 2), ("hills", 1), ("plains", 1)],
    "marsh": [("marsh", 2), ("plains", 2), ("forest", 1), ("coast", 1)],
    "mountains": [("mountains", 3), ("hills", 2), ("arctic", 1), ("forest", 1)],
    "plains": [("plains", 3), ("hills", 2), ("forest", 2), ("coast", 1), ("wastes", 1)],
    "taiga": [("taiga", 3), ("arctic", 2), ("mountains", 1), ("plains", 1)],
    "wastes": [("wastes", 3), ("desert", 2), ("hills", 1), ("plains", 1)],
    "water": [("water", 3), ("coast", 3)],
}

WEATHER = ["Clear skies", "Overcast", "Light rain", "Heavy rain / storm",
           "Fog / mist", "Snow / sleet", "Searing heat", "High winds"]
HAZARDS = ["Rockfall / slide", "Flash flood", "Mire / quicksand", "Exposure / extreme cold or heat",
           "Lost the trail", "Path blocked", "Unstable ground", "Sudden drop / crevasse"]
SITE_TYPES = ["Cave or grotto", "Ruined structure", "Watchtower", "Shrine or altar",
              "Spring or well", "Abandoned camp", "Standing stones", "Small settlement",
              "Old battlefield", "Strange landmark"]
REGION_FEATURES = ["A river crossing", "A commanding vantage point", "Dense, snagging thicket",
                   "A sheltered clearing", "Fresh animal tracks", "A weathered boundary marker",
                   "Signs of recent passage", "An unsettling stillness"]
ENCOUNTER_CATEGORIES = ["Nothing of note", "Predator or beast", "Sapient threat",
                        "Environmental hazard", "Traveller or NPC", "A useful find", "A lair or site"]
DUNGEON_ROOM_TYPES = ["Chamber", "Corridor junction", "Great hall", "Cave",
                      "Vault", "Shrine", "Cell block", "Pit", "Stairway",
                      "Flooded room"]
DUNGEON_CONTENTS = ["Empty", "Monster lair", "Trap", "Treasure",
                    "Puzzle / mechanism", "Denizen / NPC", "Hazard",
                    "Curious feature"]
DUNGEON_DRESSING = ["Rubble-strewn floor", "Dripping water", "Old bones",
                    "Claw marks on the walls", "A faint draft",
                    "A mouldering tapestry", "A cold spot", "Scattered coins",
                    "A strange smell", "Flickering shadows"]
LOCAL_FEATURES = ["A trickling stream", "A rocky outcrop", "A dense thicket",
                  "A quiet clearing", "Fresh animal tracks", "A fallen tree",
                  "A muddy hollow", "A worn game trail", "An old fire-pit",
                  "A weathered marker"]
SITE_OCCUPANTS = ["Unoccupied / abandoned", "A lone hermit or hold-out",
                  "A small band", "A territorial beast", "A larger warband",
                  "Scavengers", "A guardian", "Pilgrims or travellers",
                  "Something unnatural", "Recently emptied"]
SITE_HOOKS = ["Something valuable is hidden here", "A captive needs freeing",
              "A rival is also seeking it", "It guards a passage onward",
              "A curse or ill omen hangs over it",
              "It holds a clue to a larger mystery", "It is not what it appears",
              "A debt is owed here", "It is slowly being reclaimed",
              "An old promise binds it"]
SITE_FEATURES = ["A defensible approach", "Signs of a struggle", "A hidden cache",
                 "A source of fresh water", "Faded markings or writing",
                 "A collapsed section", "An unusual smell",
                 "Evidence of recent use", "A commanding view", "An uneasy quiet"]
SITE_AREA_TYPES = ["Entrance", "Antechamber", "Main hall", "Storeroom",
                   "Inner sanctum", "Collapsed section", "Hidden alcove",
                   "Well or shaft", "Living quarters", "Lookout"]


def build():
    return {
        "license": "CC0 / authored generic content",
        "climates": CLIMATES,
        "terrains": TERRAINS,
        "climateToTerrain": {c: [{"terrain": t, "weight": w} for (t, w) in rows]
                             for c, rows in CLIMATE_TO_TERRAIN.items()},
        "neighbouringTerrain": {k: [{"terrain": t, "weight": w} for (t, w) in rows]
                                for k, rows in NEIGHBOURING.items()},
        "weather": WEATHER,
        "hazards": HAZARDS,
        "siteTypes": SITE_TYPES,
        "regionFeatures": REGION_FEATURES,
        "encounterCategories": ENCOUNTER_CATEGORIES,
        "dungeonRoomTypes": DUNGEON_ROOM_TYPES,
        "dungeonContents": DUNGEON_CONTENTS,
        "dungeonDressing": DUNGEON_DRESSING,
        "localFeatures": LOCAL_FEATURES,
        "siteOccupants": SITE_OCCUPANTS,
        "siteHooks": SITE_HOOKS,
        "siteFeatures": SITE_FEATURES,
        "siteAreaTypes": SITE_AREA_TYPES,
    }


def verify(data):
    keys = {t["key"] for t in data["terrains"]}
    assert len(keys) == len(data["terrains"]), "duplicate terrain key"
    for t in data["terrains"]:
        assert t["difficulty"] in (2, 3, 4), f"bad difficulty {t['key']}"
        for c in t["climates"]:
            assert c in data["climates"], f"bad climate {c}"
        assert t["features"], f"terrain {t['key']} has no features"
    # Every climate must have a starting-terrain table (else rollTerrain -> null).
    assert set(data["climates"]) <= set(data["climateToTerrain"]), \
        "a climate is missing from climateToTerrain"
    for c, rows in data["climateToTerrain"].items():
        assert c in data["climates"], f"bad climate key {c}"
        for r in rows:
            assert r["terrain"] in keys, f"climateToTerrain {c} -> unknown {r['terrain']}"
            assert r["weight"] >= 1, "weight must be >= 1"
    for k, rows in data["neighbouringTerrain"].items():
        assert k in keys, f"neighbouringTerrain unknown source {k}"
        for r in rows:
            assert r["terrain"] in keys, f"neighbour of {k} -> unknown {r['terrain']}"
            assert r["weight"] >= 1, "weight must be >= 1"
    # Every terrain has a neighbouring table.
    assert keys <= set(data["neighbouringTerrain"]), "a terrain lacks a neighbouring table"
    for name in ["weather", "hazards", "siteTypes", "regionFeatures",
                 "encounterCategories", "dungeonRoomTypes", "dungeonContents",
                 "dungeonDressing", "localFeatures", "siteOccupants",
                 "siteHooks", "siteFeatures", "siteAreaTypes"]:
        assert data[name], f"{name} is empty"
        assert len(data[name]) == len(set(data[name])), f"{name} has duplicates"


if __name__ == "__main__":
    data = build()
    verify(data)
    with open("hexcrawl_data.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"wrote hexcrawl_data.json: {len(data['terrains'])} terrains, "
          f"{len(data['siteTypes'])} site types, {len(data['weather'])} weather")
