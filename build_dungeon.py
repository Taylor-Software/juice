#!/usr/bin/env python3
"""Roll 4 Ruin (Nocturnal Peacock, CC-BY-NC-SA-4.0) dungeon-branch tables ->
assets/dungeon_data.json. This script is the SOURCE OF TRUTH; never hand-edit
the emitted JSON. Rerun: python3 build_dungeon.py && cp dungeon_data.json assets/

Cross-references to other tables are encoded as the token "{ref:XX}" inside a
row string (e.g. "Chest {ref:H5}"). Tables in the P2 cave/natural set (prefixes
I, E and the D-F rooms) are NOT shipped in P1; a row referencing them keeps a
plain label and drops the token via LABEL_FALLBACKS so the P1 resolver renders
text, not an expansion.
"""
import json, re, sys

P2_REF_PREFIXES = ("I", "E", "D", "F")
# Only tables NOT yet shipped as real data keep a plain-label fallback. D3/E1
# are shape-only tables (cave/tunnel geometry, like B1/C1) with no rollable
# text content, so they are never modeled as JSON data.
LABEL_FALLBACKS = {"D3": "cave feature", "E1": "tunnel shape"}

A1 = [
    "In a magical archway portal", "Under weird alienlike ruins",
    "In overgrown formations", "Under temple ruins", "Under tower ruins",
    "Between ruined archways", "Between rocks", "At the bottom of a crater",
    "Stairs under a big statue", "In fortress ruins", "In the side of a hill",
    "Roll again",
]

A2 = {
    "2":  {"name": "Vault", "stock_double": True,
           "note": "Monsters & treasure doubled."},
    "3":  {"name": "Arcane lair",
           "note": "Halls transformed by arcane effects. If a 6 is rolled "
                   "on C2, roll on I2."},
    "4":  {"name": "Forgotten ruins", "monster_die": 12,
           "note": "Roll a D12 for monster stocking instead of a D20."},
    "5":  {"name": "Overgrown ruins", "on_stock_6": "D4 Flora {ref:I6} & fauna {ref:G7}",
           "note": "If you roll a 6 on B2 or C2, the room contains D4 flora "
                   "{ref:I6} & fauna {ref:G7}."},
    "6":  {"name": "Catacombs", "on_stock_6": "D4 Burial alcoves {ref:H1}",
           "note": "If you roll a 6 on B2 or C2, the room contains D4 burial "
                   "alcoves {ref:H1}."},
    "7":  {"name": "Ruins", "note": "A former community, now in ruins."},
    "8":  {"name": "Stronghold", "on_stock_6": "A barricade",
           "note": "If you roll a 6 for stocking, the room contains a "
                   "barricade."},
    "9":  {"name": "Temple", "on_stock_6": "Shrine {ref:H6} (1/6 intact)",
           "note": "If you roll a 6 on C2 stocking, there is a 1/6 chance "
                   "for a shrine {ref:H6}."},
    "10": {"name": "Cursed ruins", "tier_bump": 1, "treasure_bonus": 3,
           "note": "Monster stocking begins at {ref:G3} instead of {ref:G2}. "
                   "Treasure roll {ref:H8} +3."},
    "11": {"name": "Transformed ruins", "leads_to_caves": True,
           "on_stock_6": "{lvl:cross}Openings lead to cave rooms",
           "note": "If you roll a 6 on C2 for stocking, the openings of the "
                   "chamber lead to cave rooms D-F."},
    "12": {"name": "Ancient ruin", "on_stock_6": "An obstacle {ref:E4}",
           "note": "If you roll a 6 on B2, roll an obstacle {ref:E4} for "
                   "the room."},
}

# --- Corridors -------------------------------------------------------------

B2 = [
    "Monster + (2/6) Feature {ref:B3}", "Feature {ref:B3}", "Trap {ref:B4}",
    "Change of door type {ref:B5}", "Nothing", "Nothing (or Type effect)",
]

B3 = [
    "Reroll + Trap {ref:B4}", "Already activated trap {ref:B4}",
    "Floor full of mud", "Piles of rubbish or rubble", "Puddle of {ref:I7}",
    "Chest {ref:H5}", "Barricades", "Collapsed corridor {ref:E4}",
    "Small Hole (D6 ft. deep)", "D4 Flora {ref:I6}",
    "Wall fountain with {ref:I7}", "Small stairs",
    "Wall shrine {ref:H6} (2/6 intact)", "D4 Burial alcoves {ref:H1}",
    "Fresco {ref:H7}", "Nonsense graffiti", "Fauna {ref:I6}",
    "D4 Containers {ref:H4}", "D6 Carcasses of {ref:G2}", "Secret Room {ref:H3}",
]

B4 = {
    "triggers": [
        "Pressure Plate ...", "Tripwire ...", "False treasure ...",
        "Detection Glyph ...", "Light detecting crystals ...", "Lever ...",
        "Fake Corridor feature ...", "Touch sensitive walls ...",
    ],
    "effects": [
        "...Lightning Bolt", "...Frostbolt", "...Arrow trap", "...Sinkhole",
        "...Spike trap", "...Falling rubble", "...Sawing Blades", "...Flames",
        "...Poison Cloud", "...Acid-Blast", "...Spear pit", "... gas {ref:I8}",
    ],
}

B5 = ["Wooden", "Rusty metal", "Smooth stone", "Metal plates", "Portcullis",
      "Grating", "Rotting wood", "Engraved metal", "Engraved stone",
      "Ironbound wooden"]

# --- Chambers ----------------------------------------------------------------

C2 = [
    "Feature {ref:C3} + Monster", "Feature {ref:C3} + Monster + Treasure {ref:H8}",
    "Feature {ref:C3} + Treasure {ref:H8}", "Feature {ref:C3}",
    "Feature {ref:C3} + Special {ref:C4}", "Nothing (or Type effect)",
]

C3 = [
    "Roll Twice", "Campsite", "D10 carcasses of {ref:G2}", "Fresco {ref:H7}",
    "D4 Burial alcoves {ref:H1}", "D4 Chests {ref:H5}", "D6 Barricades",
    "D8 Columns", "D4 Statues {ref:H2}", "D6 Flora {ref:I6}",
    "D4 Tables + benches", "Trap {ref:B4}", "D8 containers of {ref:H4}",
    "Garbage dump", "Nest of fauna {ref:I6}", "D6 Beds",
    "Stairs (1-5. -1 lvl, 6. +1 lvl) {lvl:updown}", "Fountain filled with {ref:I7}",
    "Altar {ref:H6}", "Secret room {ref:H3}",
]

C4 = [
    "(Mini-) Bossroom {ref:G6}", "Magical corrupted with {ref:I2}",
    "D6 Traps {ref:B4}", "Arcane Laboratory", "D4 Dungeon cells with {ref:G2}",
    "Hole (-D4 levels) {lvl:chasm}", "Bookshelves & D20 books",
    "Big pool with liquid {ref:I7}", "Armory with D20 weapons",
    "Torture chamber", "Ritual site", "Alchemy laboratory",
    "D8 Armor stands", "Door to cave-system D-F {lvl:cross}",
    "D8 Flora {ref:I6} & fauna {ref:G7}",
    "D6 Chests {ref:H5} & throne", "D10 Coffins {ref:H1} & obelisk",
    "Floor mosaic of {ref:H7}", "Workshop", "Blacksmith forge",
]

C5 = [
    "Monster+Treasure D7", "Monster", "Natural Deterioration", "Nothing",
    "Nothing", "Nothing",
]

# --- Caves (D-F, natural elements I) ------------------------------------------

D1 = [
    "Narrow crack in hillside", "Bottom of a sinkhole", "In ruined mineshaft",
    "Bottom of a pit", "Side of a canyon", "In overgrown formations",
    "In hollow tree", "In hollow stone", "Between rocks",
    "Next to a standing stones", "Half-submerged in lake", "Roll again",
]

D2 = {
    "2":  {"name": "Crystal Caves", "on_stock_6": "D6 giant crystals",
           "note": "On a roll of 6 on F2 the room contains D6 giant "
                   "crystals."},
    "3":  {"name": "Icy tubes", "on_stock_6": "A solid formation of {ref:I7}",
           "note": "On a roll of 6 on F2 the room contains a solid "
                   "formation of {ref:I7}."},
    "4":  {"name": "Dungeon Entrance", "leads_to_dungeon": True,
           "on_stock_6": "{lvl:cross}Openings lead to dungeon rooms",
           "note": "On a roll of 6 on F2 the room openings lead to dungeon "
                   "rooms A-C."},
    "5":  {"name": "Old Mine", "vein_bonus_die": 6,  # "+D6 units": roll d6, add
           "note": "Veins contain +D6 units."},
    "6":  {"name": "Grotto", "on_stock_6": "A D6 ft. deep pool of {ref:I7}",
           "note": "On a roll of 6 on F2 the room contains a D6 ft. deep "
                   "pool of {ref:I7}."},
    "7":  {"name": "Natural Cave", "note": "A natural cave formed by water."},
    "8":  {"name": "Blooming Cavern", "on_stock_6": "D4 flora {ref:I6}",
           "note": "On a roll of 6 on E2 or F2 the room contains D4 flora "
                   "{ref:I6}."},
    "9":  {"name": "Outpost", "monster_die": 20,
           "note": "Roll a D20 for monster stocking instead of a D12."},
    "10": {"name": "Beast Lair", "tier_bump": 1, "vein_bonus": 3,
           "note": "Monster stocking begins at G3 instead of G2. Vein roll "
                   "I3 +3."},
    "11": {"name": "Magma Tubes", "on_stock_6": "A D6 ft. deep pool of lava",
           "note": "On a roll of 6 on F2 the room contains a D6 ft. deep "
                   "pool of lava."},
    "12": {"name": "Alien Hive", "combine_rolls": True,
           "note": "If you roll on monster, flora, gas & liquid tables, "
                   "roll twice and combine both: e.g. Stirge-Headed "
                   "zombies."},
}

E2 = [
    "Monster + (2/6) Feature {ref:E3}", "Feature {ref:F3}",
    "Feature {ref:E3} + Obstacle {ref:E4}", "Obstacle {ref:E4}", "Nothing",
    "Nothing (or Type effect)",
]

E3 = [
    "Roll twice", "Cloud of gas {ref:I8}", "Glasslike smooth walls",
    "Overgrown with moss", "Small vein of D4 units {ref:I3}",
    "D6 obstacles {ref:E4}", "Cave curio {ref:I4}",
    "Central hole (-3D6 ft.)", "D4 Solid ice vein of {ref:I7}",
    "D4 Flora {ref:I6}", "Territorial claw markings",
    "Extremely bad smell", "Change of cavestone {ref:E5}",
    "Puddle of {ref:I7}", "Full of pebbles of {ref:E5}",
    "Fossil mural walls", "Fauna {ref:G7}", "D6 Dung piles",
    "D6 Bone piles", "Secret Cave {ref:H3}",
]

E4 = [
    "Thermic vents (really hot)", "Sloping (-5 ft.)", "Steep (+5 ft.)",
    "Submerged in {ref:I7} (-5 ft.)", "Crumbly (falling rocks)",
    "Soot deposit (absorb light)", "Wind holes (really cold)",
    "Narrow (easy squeeze only)", "Sharp walls (might cut)",
    "Small (crawl only)", "Slippery (danger of fall)",
    "Windy (extinguish fire)", "Muddy (clings & dries fast)",
    "Sand floor (hard to move)", "Vertical offset is 2d6 ft. {ref:E1}",
    "Webbed (might get stuck)", "Blocking pile of rubble",
    "Dripping ceiling of {ref:I7}", "Chokepoint (squeeze only)",
    "Blocking growth of D6 {ref:I6}",
]

E5 = [
    "Limestone (grey, fossil-rich)", "Basalt (dark, absorb sound)",
    "Sandstone (brown, crumbly)", "Granite (grey, cold)",
    "Marble (light, smooth)", "Starstone (blue, echoes)",
    "Chalk (pale, soft)", "Obsidian (black, hard)",
    "Serpentine (Green, magical)", "Gloamstone (red, warm)",
]

F2 = [
    "Feature {ref:F3} + D6 Vein {ref:I3}", "Feature {ref:F3} + Monster",
    "Feature {ref:F3} + Monster", "Feature {ref:F3} + Special {ref:F4}",
    "Feature {ref:F3}", "Nothing (or type effect)",
]

F3 = [
    "Roll twice", "Fossilized {ref:G4}", "Solid formations of {ref:I7}",
    "D20 Stalagmites/ctits", "D8 Fungitrees", "Basalt columns",
    "Flowstone formations", "Coral stone formations",
    "D6 Big boulders of {ref:E5}", "D6 Flora {ref:I6}", "Cave Curio {ref:I4}",
    "Vein 3D6 {ref:I3}", "Geothermal vents of {ref:I8}", "Fauna {ref:G7}",
    "Chasm (-D4 levels) {lvl:chasm}",
    "D4 obstacles {ref:E4}", "Slope (1-5.-1 lvl; 6.+1 lvl) {lvl:updown}",
    "Small lake filled with {ref:I7}", "D6 Piles of dirt",
    "Secret cave {ref:I1}",
]

F4 = [
    "(Mini-) Bossroom G5-G6", "Geyser spraying {ref:I8}",
    "Doors to dungeon A-C {lvl:cross}", "Lake & -fall of {ref:I7}",
    "Fauna {ref:G7} & D6 flora {ref:I6}", "D8 Uranium (radioactive)",
    "D8 Sulfur vein (explosive)", "Strong echo cave",
    "Big central fossil of {ref:G5}", "Aquifer formations",
    "Intervention {ref:I5}", "D4 Cave curios {ref:I4}",
    "Bubbeling spring of {ref:I7}", "Central river of {ref:I7}",
    "D6 giant cocoons of {ref:H1}", "Chasm (-D4 levels) {lvl:chasm}",
    "6D6 Vein of {ref:I3}", "D6 Obstacles {ref:E4}",
    "D20 Giant crystal clusters", "Chasm to the deep dark {lvl:chasm}",
]

F5 = [
    "Monster", "Natural Deterioration", "Natural Growth", "Nothing",
    "Nothing", "Nothing",
]

I1 = {
    "hides_d6": [
        "Opening in shade ...", "Crumbling wall ....",
        "Opening D6 ft. above ...", "In a hole D6 ft. below ...",
        "Narrow & small opening ...", "Hole overgrown by D6 {ref:I6} ...",
    ],
    "leads_d10": [
        "... Hidden cave feature {ref:D3}", "... Tunnel", "... Cave",
        "... Vein 2D6 {ref:I3}", "... Way down a floor {lvl:down}",
        "... Way to surface", "... Vein 4D6 {ref:I3}",
        "... 3x treasures {ref:H8}", "... Crystal worth D1000",
        "... Corridor",
    ],
}

I2 = {
    "source_d4": {
        "1": "Periodic tremors ...", "2": "Hidden gems ...",
        "3": "Magical winds ...", "4": "Arcane veins in the walls ...",
    },
    "creates_d12": [
        "Slowly regain magic", "Disort light", "Pulsating magical energy",
        "Spirit world whispers", "Magnetic surfaces",
        "Subsonic numbing hum", "Shifting gravity",
        "Stone \"sweats\" {ref:I7}", "Slowly melting stone",
        "Cave fata morgana", "Melodic wind", "Fluctuation of {ref:I8}",
    ],
}

I3 = [
    "Salt (1 gp)", "Iron ore (3 gp)", "Tin ore (5 gp)", "Copper ore (8 gp)",
    "Lesser gems (10 gp)", "Silver ore (25 gp)", "Common gems (35 gp)",
    "Gold ore (50 gp)", "Uncommon gems (75 gp)", "Crystals (100 gp)",
    "Mithril ore (150 gp)", "Adamantine ore (250 gp)", "Rare gems (350 gp)",
    "Amber (500 gp)", "Obsidian ore (750 gp)", "Diamonds (1000 gp)",
    "Very rare gems (2500 gp)", "Rare crystals (5000 gp)",
]

I4 = [
    "D6 mushroom water tank", "D6 edible fungi pods", "D6 biomass piles",
    "D6 hanging egg sacs", "D6 chalk deposit vein", "D6 guano piles",
    "D6 clay vein", "D6 coal vein", "D6 shells (1/6 pearl 100 gp)",
    "D6 smooth stones of {ref:E5}", "D6 hardened pods",
    "D6 hands of gem dust", "D6 cave-driftwood sticks",
    "D6 skulls of {ref:G3}", "2D6 heavy bones", "D6 resin blocks",
    "D6 carcasses of fauna {ref:G7}", "D6 dried flora {ref:I6}",
    "D6 Fossils of {ref:G7}", "D6 arcane crystal vein",
]

I5 = [
    "Broken pottery, scraps", "Campsite (D6 tents)",
    "D6 Containers {ref:H4}", "Obsidian Portal & {ref:I2}", "Trap {ref:B4}",
    "Ruins & Secret Room {ref:H3}", "Ancient cave painting",
    "D6 Barrels (3/6 explosive)", "D6 Alien geometric blocks",
    "Carved Statue H2", "Farm of 3D6 {ref:I6}",
    "Burial Site with D6 {ref:H1}", "Skeleton + D6 equipment",
    "D8 Mining Tools", "Broken carts & tracks", "Abandoned campsite",
    "Carved symbols of {ref:H7}", "Totem shrine {ref:H6}",
    "Special chamber {ref:C4}", "Carved steps down to A3",
]

I6 = [
    "Mushroom | Edible", "Crystals | Bitter", "Corals | Bioluminescent",
    "Moss | Toxic", "Roots | Healing", "Herbs | Poisonous",
    "Mold | Magic refilling", "Fern | Boosting", "Algae | Debuffing",
    "Shrubs | Sweet", "Lianas | Good smell", "Lichen | Thorny",
    "Cave-Reed | Salty", "Sprouts | Sickening", "Pods | Carnivorous",
    "Minerals | Sticky", "Tendrils | Numbing", "Mud | Highly flammable",
    "Tufts | Hallucinogenic", "Sapling | Antiseptic",
]

I7 = {
    "condition_d6": [
        "Clear", "Clear", "Clear", "Filled with parasites",
        "With fish-like beings in it", "With coral-like formation",
    ],
    # Main liquid list, rolled D6+2D8 per the PDF header ("Liquid (D6, 2D8)").
    "liquid": [
        "Lava (Ignore condition)", "Liquid form of {ref:I8}", "Toxic",
        "Acid", "Freshwater", "Sulfurous", "Mud", "Rotten Water",
        "Saltwater", "Halucinogenic substance", "Poison", "Oil",
        "Alcoholic residue", "Mana residue", "Healing nektar",
    ],
}

I8 = [
    "Weird smelling air (None)", "Carbon Monoxide (Deadly)",
    "Spores (Halucinogenic)", "Thin air (Dizziness)",
    "Chlorine fog (Burns acidic)", "Hydrogen (flameable)",
    "Nitrogen (Paralysis)", "Miasma (Illnesses)",
    "Water vapor (Dampens)", "Helium (Lifts pitch)",
    "Methane (Flameable)", "Sulfur (Poisonous)",
    "Radon (Slow radiation)", "Wraithfog (Silence sound)",
    "Ash vapor (Dizziness)", "Ethylene (Sleeping)",
    "Argon (Slow suffocation)", "Ammonia (Burns acidic)",
    "Dragonfume (Glows red)", "Isobutane (Corrodes)",
]

# --- Monsters ----------------------------------------------------------------

G1 = {
    "2": "Immediate ambush", "3": "Hostile/Engage", "4": "Hostile/Alert",
    "5": "Hostile/Threaten", "6": "Uncertain/Threaten", "7": "Uncertain/Suspicious",
    "8": "Uncertain/Confused", "9": "Neutral/Curious", "10": "Neutral/Unaware",
    "11": "Interested/Unaware", "12": "Friendly/Inactive",
}

G2 = [
    {"text": "Insect Swarm", "count": "D4", "organized": False},
    {"text": "Giant Rat", "count": "2D6", "organized": False},
    {"text": "Giant Bats", "count": "2D6", "organized": False},
    {"text": "Stirges", "count": "2D6", "organized": False},
    {"text": "Giant Centipede", "count": "D6", "organized": False},
    {"text": "Giant Beetle", "count": "D6", "organized": False},
    {"text": "Wolves", "count": "D6", "organized": False},
    {"text": "Giant Spiders", "count": "D6", "organized": False},
    {"text": "Slime", "count": "D4", "organized": False},
    {"text": "Snakes", "count": "D6", "organized": False},
    {"text": "Yellow Mold", "count": "D6", "organized": False},
    {"text": "Cave Locusts", "count": "D6", "organized": False},
    {"text": "Zombies", "count": "D6", "organized": False},
    {"text": "Animated Skeletons", "count": "2D6", "organized": False},
    {"text": "Goblins", "count": "3D6", "organized": True},
    {"text": "Bandits", "count": "2D6", "organized": True},
    {"text": "Kobolds", "count": "3D6", "organized": True},
    {"text": "Adventurers", "count": "2D6", "organized": True},
    {"text": "Hobgoblins", "count": "2D6", "organized": True},
    {"text": "Berserkers", "count": "2D6", "organized": True},
]

G3 = [
    {"text": "Roll on G2 (Dice x2)", "count": "", "organized": False},
    {"text": "Gelatinous Cubes", "count": "D4", "organized": False},
    {"text": "Shadows", "count": "D8", "organized": False},
    {"text": "Insect Hulker", "count": "D8", "organized": False},
    {"text": "Carcass Crawler", "count": "D4", "organized": False},
    {"text": "Ghouls", "count": "D6", "organized": False},
    {"text": "Giant Lizard", "count": "", "organized": False},
    {"text": "Flail snail", "count": "D4", "organized": False},
    {"text": "Giant insect", "count": "2D6", "organized": False},
    {"text": "Giant cave toad", "count": "D8", "organized": False},
    {"text": "Bear", "count": "D4", "organized": False},
    {"text": "Giant Snake", "count": "2D4", "organized": False},
    {"text": "Pixies", "count": "2D6", "organized": False},
    {"text": "Wights", "count": "D8", "organized": False},
    {"text": "Harpys", "count": "2D4", "organized": False},
    {"text": "Gnolls", "count": "2D6", "organized": True},
    {"text": "Troglodytes", "count": "2D6", "organized": True},
    {"text": "Bugbears", "count": "3D6", "organized": True},
    {"text": "Orcs", "count": "3D6", "organized": True},
    {"text": "Cultists", "count": "2D6", "organized": True},
]

G4 = [
    {"text": "Roll on G3 (Dice x2)", "count": "", "organized": False},
    {"text": "Roll on G2 (Dice x3)", "count": "", "organized": False},
    {"text": "Roll on G2 (Dice x3)", "count": "", "organized": False},
    {"text": "Roll on G5", "count": "", "organized": False},
    {"text": "Rust Monsters", "count": "D4", "organized": False},
    {"text": "Giant Insect", "count": "2D6", "organized": False},
    {"text": "Black Puddings", "count": "D4", "organized": False},
    {"text": "Giant Weasel", "count": "D6", "organized": False},
    {"text": "Giant Leeches", "count": "D6", "organized": False},
    {"text": "Huge lizard", "count": "2D6", "organized": False},
    {"text": "Giant Scorpions", "count": "D6", "organized": False},
    {"text": "Spectres", "count": "D4", "organized": False},
    {"text": "Elementals", "count": "D4", "organized": False},
    {"text": "Ghosts", "count": "2D4", "organized": False},
    {"text": "Mummies", "count": "2D4", "organized": False},
    {"text": "Ettercaps", "count": "2D4", "organized": False},
    {"text": "Ogres", "count": "D8", "organized": True},
    {"text": "Lizardmen", "count": "2D6", "organized": True},
    {"text": "Doppelgangers", "count": "D4", "organized": False},
    {"text": "Vampires", "count": "D4", "organized": False},
]

G5 = [
    {"text": "Weaker version of G6", "count": "", "organized": False},
    {"text": "Owlbear", "count": "", "organized": False},
    {"text": "Cockatrice", "count": "", "organized": False},
    {"text": "Manticore", "count": "", "organized": False},
    {"text": "Werewolves", "count": "D4", "organized": False},
    {"text": "Invisible stalker", "count": "", "organized": False},
    {"text": "Panther beast", "count": "", "organized": False},
    {"text": "Wyvern", "count": "", "organized": False},
    {"text": "Basilisk", "count": "", "organized": False},
    {"text": "Griffon", "count": "", "organized": False},
    {"text": "Troll", "count": "D4", "organized": False},
    {"text": "Djinni", "count": "", "organized": False},
    {"text": "Minotaur", "count": "D4", "organized": False},
    {"text": "Ettin", "count": "", "organized": False},
    {"text": "Golem", "count": "", "organized": False},
    {"text": "Warlock & Cultists", "count": "D4", "organized": True},
    {"text": "Gargoyle", "count": "", "organized": False},
    {"text": "Wraith", "count": "", "organized": False},
    {"text": "Giant ...", "count": "D12 on G2", "organized": False},
    {"text": "Chief of ...", "count": "D8+12 on G2", "organized": True},
]

G6 = [
    {"text": "Ancient ... G5", "count": "", "organized": False},
    {"text": "Chimera", "count": "", "organized": False},
    {"text": "Kraken", "count": "", "organized": False},
    {"text": "Leviathan", "count": "", "organized": False},
    {"text": "Dragon", "count": "", "organized": False},
    {"text": "Mushroom Treant", "count": "", "organized": False},
    {"text": "Hydra", "count": "", "organized": False},
    {"text": "Giant", "count": "", "organized": False},
    {"text": "Giant worm", "count": "", "organized": False},
    {"text": "Arch-Hag", "count": "", "organized": False},
    {"text": "Medusa", "count": "", "organized": False},
    {"text": "Flying Eye Tyrant", "count": "", "organized": False},
    {"text": "Cyclops", "count": "", "organized": False},
    {"text": "Ancient vampire", "count": "", "organized": False},
    {"text": "Ancient sorcerer/*ess", "count": "", "organized": False},
    {"text": "King of...", "count": "D8+12 on G3", "organized": True},
    {"text": "Brain-Eating Alien", "count": "", "organized": False},
    {"text": "Demon", "count": "", "organized": False},
    {"text": "Chaos Spawn", "count": "", "organized": False},
    {"text": "Lich", "count": "", "organized": False},
]

G7 = [
    {"text": "Small cave worms", "count": "2D6", "organized": False},
    {"text": "Ant Colony", "count": "Nest", "organized": False},
    {"text": "Larvae", "count": "2D6", "organized": False},
    {"text": "Scorpions", "count": "2D6", "organized": False},
    {"text": "Living Spore clouds", "count": "D4", "organized": False},
    {"text": "Bats", "count": "2D6", "organized": False},
    {"text": "Slugs or snails", "count": "", "organized": False},
    {"text": "Hornet or wasps", "count": "Nest", "organized": False},
    {"text": "Crustaceans", "count": "", "organized": False},
    {"text": "Salamanders", "count": "2D6", "organized": False},
    {"text": "Glowworms", "count": "2D6", "organized": False},
    {"text": "Moths", "count": "2D6", "organized": False},
    {"text": "Cave crickets", "count": "2D6", "organized": False},
    {"text": "Frogs or toads", "count": "2D6", "organized": False},
    {"text": "Rats or mice", "count": "2D6", "organized": False},
    {"text": "Hares", "count": "2D6", "organized": False},
    {"text": "Spiders", "count": "2D6", "organized": False},
    {"text": "Beetles", "count": "2D6", "organized": False},
    {"text": "Weasels or lemures", "count": "2D6", "organized": False},
    {"text": "Pseudodragon", "count": "D4", "organized": False},
]

# --- Build elements ----------------------------------------------------------

H1 = {
    "contains_d4": {"1": "Dust", "2": "Dust", "3": "Carcass", "4": "Carcass"},
    "d8_2d8": [
        "2x Treasures {ref:H8}", "Statue {ref:H2}", "A container {ref:H4}",
        "Treasure {ref:H8}", "Rusty Treasure {ref:H8} (/2 gp)",
        "Overgrown Vegetation {ref:I6}", "Rusty armor", "Rotting clothes",
        "Miasma of {ref:I8}", "Cocoons and Eggs", "Fauna {ref:G7}",
        "Useable Armor", "Useable Weapon", "Filled with liquid {ref:I7}",
        "Mimic",
    ],
}

H2 = {
    "depicts_d4": {"1": "{ref:G3}", "2": "{ref:G4}", "3": "{ref:G5}", "4": "{ref:G6}"},
    "d2d8": [
        "Connected secret room {ref:H3}", "Hidden compartment {ref:H5}",
        "Engraved random spell", "Close to crumbling to dust",
        "Gem Eyes, D6*50 GP", "Obscure pose", "Gem Encrusted D6*10 GP",
        "Simple Statue", "Half Destroyed", "Destroyed", "Trapped {ref:B4}",
        "Releases Gas {ref:I8}", "Shrine {ref:H6}", "Filled with liquid {ref:I7}",
        "Upon touch activates {ref:I2}",
    ],
}

H3 = {
    "opens_d8": [
        "Visible Lever ....", "Hidden Lever ....", "Hidden button ...",
        "Behind Illusion ...", "Hidden Magic Glyph ...", "Pattern on Wall ...",
        "Shifting Feature or Wall ...", "Pressure Plate ...",
    ],
    "reveals_d10": [
        "... Useless effect", "... Hidden room feature", "... Corridor",
        "... Chamber", "... Chamber + Treasure {ref:H8}",
        "... Stairs down a level", "... Stairs to surface",
        "... Treasure {ref:H8}", "... 2x treasures {ref:H8}",
        "... 3x treasures {ref:H8}",
    ],
}

H4 = [
    "Barrels (Alcohol)", "Barrel (Oil)", "Urns (1/6 treasure {ref:H8})",
    "Urns (D4 Spell-Scrolls)", "Crates (2/6 Equipment)",
    "Barrel (with liquid {ref:I7})", "Crates  (1/6 treasure {ref:H8})",
    "Crate (2/6 weapon)", "Barrel (Building material)",
    "Sacks (4/6 edible food)", "Sacks (Sand)",
    "Sack (3/6 Cave Curio {ref:I4})", "Wardrobe (2/6 clothing)",
    "Vase (filled with Gas {ref:I8})", "Vase (1/6 treasure {ref:H8})",
    "Urns (with liquid {ref:I7})", "Cabinet (3/6 Clothing)",
    "Pouches (Vegetation {ref:I6})", "Cabinet (D4 potions)",
    "Cage with Fauna {ref:G7}",
]

H5 = [
    "D6 mundane items", "(3/6) Locked, Treasure D7",
    "(3/6) Locked, 2D6 Food", "(3/6) Locked, D4 Armor",
    "(3/6) Locked, D4 weapons", "Collected Curios {ref:I4}",
    "D12 Bottles alcohol", "D6 Equipment", "D1000 GP", "Empty",
    "Useless personal stuff", "Trapped {ref:B4}, Potion, Scroll",
    "Locked, 2x Treasures {ref:H8}", "Treasure {ref:H8}", "Minor magic item",
    "D4 bandages & salves", "D4 harvested {ref:I3}",
    "(3/6) Locked, D4 potions", "(3/6) Locked, D4 S. Scrolls", "Mimic",
]

H6 = {
    "demands_d8": [
        "Virtue, Oath of Virtue ...", "Sin, Sinful Act ...", "Death, Blood ...",
        "Fertility, Food ...", "Environmentalism ...", "Trickery, Entertainment ...",
        "Greed, Gold ...", "Cosmos, magic...",
    ],
    "offers_d10": [
        "... Healing (Instant)", "... Attribute buff (D6 hours)",
        "... Protection (D6 hours)", "... Damage (D6 hours)",
        "... Spellcasting(d6 hours)", "... Luck (1x Reroll)",
        "... Foresight (Dungeon Info)", "... Minor Artifact",
        "... Treasure {ref:H8}",
        "... Nothing, but curses adventurers if ignored",
    ],
}

H7 = [
    "Weird nonsense", "Abstract mural", "Obscure old knowledge",
    "Warning mural", "Image of a battle", "Image of a humanoid",
    "Image of god + prayer", "Image of monster {ref:G6}", "Geometric mosaic",
    "Occult mural", "Historical chronicle", "Extravagant Art",
    "Ritual mural", "Disfigured mural", "Image hides treasure {ref:H8}",
    "Carved Holes Emit {ref:I8}", "Pattern D10 gems (50 GP)",
    "Random spell engraved", "Riddle to secret room {ref:H3}",
    "Brass relief D10*100 GP",
]

H8 = {
    "form_d4": {"1": "Coins", "2": "Coins", "3": "D6 items", "4": "D4 gems"},
    "d10_plus_level": [
        "D6 SP", "2D6 SP", "D6 GP", "D6*5 GP", "D6*10 GP", "2D6*10 GP",
        "D6*25 GP", "2D6*25 GP", "D6*50 GP", "Artifact +1 & 2D6*50 GP",
        "D6*100 GP", "Artifact +1 & D6*100 GP", "2D6*100 GP",
        "Artifact +2 & D6*250 GP", "2D6*250 GP", "Artifact +2 & D6*500 GP",
        "2D6*500 GP", "Artifact +3 &D6*5000 GP",
    ],
}

# --- Misc supporting data (authored; not on the cited pages) ----------------

FACTION_NAMES = [
    "Rotfangs", "Ashclaw Pack", "The Gloomwardens", "Bonepickers",
    "Iron Maw", "The Hollow Court", "Grislefolk", "The Ninth Tally",
    "Murkeye Clan", "The Sundered Hand", "Cinder Kin", "The Pale Circle",
]
CORRIDOR_FAMILIES = {
    "straight": [[11, 22]], "l-bend": [[23, 34]], "t-junction": [[35, 44]],
    "cross": [[45, 52]], "offset": [[53, 62]], "long": [[63, 66]],
}
CHAMBER_FAMILIES = {
    "small": [[11, 22]], "medium": [[23, 36]], "large": [[41, 52]],
    "round": [[53, 56]], "cross": [[61, 64]], "l-room": [[65, 66]],
}
# E1 tunnel shapes (D66, p.6) and F1 cave shapes (D66, p.7) are organic/
# freeform art, not literal corridor/chamber geometry; family keys are reused
# from CORRIDOR_FAMILIES/CHAMBER_FAMILIES so the same placement/footprint
# machinery applies, with ranges authored to mirror shape complexity ordering
# (small/simple low, large/branching high) in the same split style as above.
TUNNEL_FAMILIES = {
    "straight": [[11, 16]], "l-bend": [[21, 26]], "t-junction": [[31, 36]],
    "cross": [[41, 45]], "offset": [[46, 56]], "long": [[61, 66]],
}
CAVE_FAMILIES = {
    "small": [[11, 16]], "medium": [[21, 32]], "large": [[33, 46]],
    "round": [[51, 54]], "cross": [[55, 61]], "l-room": [[62, 66]],
}


def d66_covered(fam):
    seen = set()
    for ranges in fam.values():
        for lo, hi in ranges:
            for v in range(lo, hi + 1):
                if 1 <= (v % 10) <= 6:
                    seen.add(v)
    want = {t * 10 + o for t in range(1, 7) for o in range(1, 7)}
    return seen == want


REF_RE = re.compile(r"\{ref:([A-Z]\d+)\}")


def all_ref_ids(*tables):
    ids = set()

    def scan(x):
        if isinstance(x, str):
            ids.update(REF_RE.findall(x))
        elif isinstance(x, dict):
            for v in x.values():
                scan(v)
        elif isinstance(x, list):
            for v in x:
                scan(v)

    for t in tables:
        scan(t)
    return ids


def build():
    data = {
        "_license": "Roll 4 Ruin: Classic Dungeon Generator (c) Nocturnal "
                    "Peacock, CC-BY-NC-SA-4.0.",
        "A1": A1, "A2": A2,
        "B2": B2, "B3": B3, "B4": B4, "B5": B5,
        "C2": C2, "C3": C3, "C4": C4, "C5": C5,
        "D1": D1, "D2": D2,
        "E2": E2, "E3": E3, "E4": E4, "E5": E5,
        "F2": F2, "F3": F3, "F4": F4, "F5": F5,
        "G1": G1, "G2": G2, "G3": G3, "G4": G4, "G5": G5, "G6": G6, "G7": G7,
        "H1": H1, "H2": H2, "H3": H3, "H4": H4, "H5": H5, "H6": H6, "H7": H7,
        "H8": H8,
        "I1": I1, "I2": I2, "I3": I3, "I4": I4, "I5": I5, "I6": I6, "I7": I7,
        "I8": I8,
        "faction_names": FACTION_NAMES,
        "corridor_families": CORRIDOR_FAMILIES,
        "chamber_families": CHAMBER_FAMILIES,
        "tunnel_families": TUNNEL_FAMILIES,
        "cave_families": CAVE_FAMILIES,
        "label_fallbacks": LABEL_FALLBACKS,
    }
    verify(data)
    return data


def verify(data):
    errs = []
    if len(data["A1"]) != 12:
        errs.append("A1 must have 12 rows")
    if set(data["A2"]) != {str(i) for i in range(2, 13)}:
        errs.append("A2 must cover 2..12")
    if set(data["G1"]) != {str(i) for i in range(2, 13)}:
        errs.append("G1 must cover 2..12")
    if len(data["D1"]) != 12:
        errs.append("D1 must have 12 rows")
    if set(data["D2"]) != {str(i) for i in range(2, 13)}:
        errs.append("D2 must cover 2..12")
    for k, n in [
        ("B2", 6), ("B5", 10), ("B3", 20),
        ("C2", 6), ("C3", 20), ("C4", 20), ("C5", 6),
        ("G2", 20), ("G3", 20), ("G4", 20), ("G5", 20), ("G6", 20), ("G7", 20),
        ("H4", 20), ("H5", 20), ("H7", 20),
        ("E2", 6), ("E3", 20), ("E4", 20), ("E5", 10),
        ("F2", 6), ("F3", 20), ("F4", 20), ("F5", 6),
        ("I3", 18), ("I4", 20), ("I5", 20), ("I6", 20), ("I8", 20),
    ]:
        if len(data[k]) != n:
            errs.append(f"{k} must have {n} rows (has {len(data[k])})")

    if len(data["B4"]["triggers"]) != 8:
        errs.append("B4 triggers must have 8 rows")
    if len(data["B4"]["effects"]) != 12:
        errs.append("B4 effects must have 12 rows")

    for name in ("G2", "G3", "G4", "G5", "G6", "G7"):
        for row in data[name]:
            if not isinstance(row, dict) or {"text", "count", "organized"} - set(row):
                errs.append(f"{name} row malformed: {row}")
                continue
            if not isinstance(row["organized"], bool):
                errs.append(f"{name} row organized must be bool: {row}")

    if set(data["H1"]["contains_d4"]) != {"1", "2", "3", "4"}:
        errs.append("H1 contains_d4 must cover 1..4")
    if len(data["H1"]["d8_2d8"]) != 15:
        errs.append("H1 d8_2d8 must have 15 rows")
    if set(data["H2"]["depicts_d4"]) != {"1", "2", "3", "4"}:
        errs.append("H2 depicts_d4 must cover 1..4")
    if len(data["H2"]["d2d8"]) != 15:
        errs.append("H2 d2d8 must have 15 rows")
    if len(data["H3"]["opens_d8"]) != 8:
        errs.append("H3 opens_d8 must have 8 rows")
    if len(data["H3"]["reveals_d10"]) != 10:
        errs.append("H3 reveals_d10 must have 10 rows")
    if set(data["H6"]["demands_d8"]) and len(data["H6"]["demands_d8"]) != 8:
        errs.append("H6 demands_d8 must have 8 rows")
    if len(data["H6"]["offers_d10"]) != 10:
        errs.append("H6 offers_d10 must have 10 rows")
    if set(data["H8"]["form_d4"]) != {"1", "2", "3", "4"}:
        errs.append("H8 form_d4 must cover 1..4")
    if len(data["H8"]["d10_plus_level"]) != 18:
        errs.append("H8 d10_plus_level must have 18 rows")

    if len(data["I1"]["hides_d6"]) != 6:
        errs.append("I1 hides_d6 must have 6 rows")
    if len(data["I1"]["leads_d10"]) != 10:
        errs.append("I1 leads_d10 must have 10 rows")
    if set(data["I2"]["source_d4"]) != {"1", "2", "3", "4"}:
        errs.append("I2 source_d4 must cover 1..4")
    if len(data["I2"]["creates_d12"]) != 12:
        errs.append("I2 creates_d12 must have 12 rows")
    if len(data["I7"]["condition_d6"]) != 6:
        errs.append("I7 condition_d6 must have 6 rows")
    if len(data["I7"]["liquid"]) != 15:
        errs.append("I7 liquid must have 15 rows")

    if not d66_covered(data["corridor_families"]):
        errs.append("corridor_families does not cover all d66 combos")
    if not d66_covered(data["chamber_families"]):
        errs.append("chamber_families does not cover all d66 combos")
    if not d66_covered(data["tunnel_families"]):
        errs.append("tunnel_families does not cover all d66 combos")
    if not d66_covered(data["cave_families"]):
        errs.append("cave_families does not cover all d66 combos")
    if set(data["tunnel_families"]) != set(data["corridor_families"]):
        errs.append("tunnel_families keys must match corridor_families keys")
    if set(data["cave_families"]) != set(data["chamber_families"]):
        errs.append("cave_families keys must match chamber_families keys")

    known = {
        "B3", "B4", "B5", "C3", "C4", "C5",
        "G2", "G3", "G4", "G5", "G6", "G7",
        "H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8",
        "D1", "D2", "D3",
        "E2", "E3", "E4", "E5",
        "F2", "F3", "F4", "F5",
        "I1", "I2", "I3", "I4", "I5", "I6", "I7", "I8",
    }
    # Scan EVERY shipped table (all_ref_ids recurses strings/lists/dicts; the
    # support keys carry no {ref} tokens, so scanning the whole dict is safe and
    # closes the gap where B4/B5/C5/G*/H8 refs went unchecked).
    refs = all_ref_ids(data)
    for rid in refs:
        if rid not in known and rid not in data["label_fallbacks"]:
            errs.append(f"unknown ref {{ref:{rid}}} (add to a table or "
                        f"label_fallbacks)")

    lvl_re = re.compile(r"\{lvl:([a-z]+)\}")
    allowed_lvl = {"down", "updown", "chasm", "cross"}

    def scan_lvl(x):
        if isinstance(x, str):
            for tok in lvl_re.findall(x):
                if tok not in allowed_lvl:
                    errs.append(f"unknown {{lvl:{tok}}} token (must be one "
                                f"of {sorted(allowed_lvl)})")
        elif isinstance(x, dict):
            for v in x.values():
                scan_lvl(v)
        elif isinstance(x, list):
            for v in x:
                scan_lvl(v)

    scan_lvl(data)

    if errs:
        print("SELF-CHECK FAILED:")
        for e in errs:
            print(" -", e)
        sys.exit(1)
    print("self-check OK")


if __name__ == "__main__":
    d = build()
    with open("dungeon_data.json", "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("wrote dungeon_data.json")
