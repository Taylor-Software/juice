#!/usr/bin/env python3
"""Generate assets/starter_tables.json — the bundled starter table pack.

Source of truth for the starter set: edit THIS script, rerun
`python3 build_starter_tables.py`, and copy the output into assets/ (the
script writes it in place). Never hand-edit the emitted JSON.

Licensing: every row below is ORIGINAL authored text written for this app.
The set's TOPIC coverage (NPC quirks, room features, rumors, ...) follows the
common community binder taxonomy — topics/ideas are not copyrightable, and no
third-party table text is reproduced (community collections such as
r/BehindTheTables carry no reuse license, so their rows are not vendorable).

Output shape = the app's portable table-pack format (see
lib/engine/custom_table.dart): {kind: 'juice-table-pack', v: 1, tables: [...]}
with rows as plain strings (uniform mode) and the #262 library metadata
(cat/src; genre left empty = generic).
"""

import json
import sys

SRC = "Starter set"

# Category strings MUST match kTableCategories in lib/engine/custom_table.dart.
CATEGORIES = [
    "Characters & NPCs",
    "Locations & Settings",
    "Objects & Items",
    "Events & Encounters",
    "Plot & Adventure Hooks",
    "Dungeon & Exploration",
    "Combat & Tactics",
    "Magic & Spells",
    "Factions & Organizations",
    "Bestiary & Creatures",
    "Social & Roleplay",
    "Names",
    "Inspiration & Prompts",
]

T = []


def table(id_, name, cat, rows):
    T.append({"id": f"starter-{id_}", "name": name, "cat": cat, "src": SRC,
              "rows": rows})


# -- Characters & NPCs --------------------------------------------------------
table("npc-quirk", "NPC Quirk", "Characters & NPCs", [
    "Hums tunelessly while thinking",
    "Never makes eye contact",
    "Quotes a dead relative constantly",
    "Collects small shiny stones",
    "Laughs at the wrong moments",
    "Speaks in a near-whisper",
    "Always eating something",
    "Repeats your last word back to you",
    "Cracks their knuckles before answering",
    "Superstitious about doorways",
    "Wears one glove, always",
    "Names every animal they meet",
    "Keeps checking over their shoulder",
    "Talks to their weapon or tool",
    "Refuses to sit with their back to a door",
    "Counts coins twice, every time",
    "Smells faintly of smoke",
    "Overly formal with strangers",
    "Chews a wooden splinter like a pipe",
    "Sketches faces in a battered notebook",
])
table("npc-motivation", "NPC Motivation", "Characters & NPCs", [
    "Pay off a crushing debt",
    "Win back an estranged family member",
    "Prove a rival wrong",
    "Escape a past identity",
    "Protect a secret at any cost",
    "Earn a title or rank",
    "Find a cure for a slow illness",
    "Avenge a wrong nobody else remembers",
    "Keep a promise to the dead",
    "See a far-off place before dying",
    "Hoard enough to never work again",
    "Be admired by one specific person",
    "Atone for a betrayal",
    "Recover something that was stolen",
    "Keep their community fed through winter",
    "Learn a forbidden skill",
    "Outlive their enemies",
    "Build something that lasts",
    "Stay unnoticed by powerful people",
    "Feel important, just once",
])
table("npc-occupation", "NPC Occupation", "Characters & NPCs", [
    "Ferryman", "Midwife", "Rat-catcher", "Scribe", "Lamplighter",
    "Gravedigger", "Falconer", "Tinker", "Toll collector", "Herbalist",
    "Stonemason", "Pot-mender", "Courier", "Fishmonger", "Chandler",
    "Stablehand", "Pardoner", "Mule driver", "Well-digger", "Bone-setter",
])
table("npc-secret", "NPC Secret", "Characters & NPCs", [
    "Is deep in debt to someone dangerous",
    "Is not who their papers say they are",
    "Informs for the local authority",
    "Once abandoned someone to die",
    "Is hiding a fugitive",
    "Stole the thing that made their fortune",
    "Belongs to a forbidden faith or society",
    "Is slowly being blackmailed dry",
    "Knows where a body is buried — literally",
    "Loves someone they are sworn against",
    "Is terminally ill and telling no one",
    "Witnessed a crime by someone powerful",
])
table("npc-impression", "First Impression", "Characters & NPCs", [
    "Warmer than expected",
    "Distracted, mid-task",
    "Instantly suspicious of you",
    "Desperate to be liked",
    "Exhausted to the bone",
    "Sizing you up for profit",
    "Openly grieving",
    "Cheerful in a way that feels forced",
    "Quietly terrified of something",
    "Bored and looking for trouble",
    "Curt, but fair",
    "Immediately overfamiliar",
])

# -- Locations & Settings -----------------------------------------------------
table("weather", "Weather Today", "Locations & Settings", [
    "Clear and sharp",
    "Low fog until midday",
    "Steady drizzle",
    "Gusts that slam shutters",
    "Oppressive, still heat",
    "Cold snap out of season",
    "Thunderheads building all day",
    "Rain arriving in hard bursts",
    "Dust or pollen haze",
    "Brilliant sun, biting wind",
    "A storm breaks by nightfall",
    "Unnaturally quiet skies",
])
table("wild-feature", "Wilderness Feature", "Locations & Settings", [
    "A ford marked by leaning stones",
    "A burned ring of trees",
    "An overgrown orchard gone feral",
    "A sinkhole breathing cold air",
    "A shrine no one maintains, yet tidy",
    "A game trail wider than it should be",
    "A dry riverbed paved with flat stones",
    "A single grave with fresh flowers",
    "A tower stump, floor intact",
    "A meadow loud with unseen insects",
    "A rope bridge, one rail snapped",
    "A boundary stone with a defaced crest",
    "A hollow tree used as a message drop",
    "A salt lick drawing strange tracks",
    "A waterfall hiding a shallow cave",
    "A ruined mill, wheel still turning",
    "A stand of trees all bent one way",
    "An abandoned camp, packed in haste",
    "A cairn field stretching to the ridge",
    "A hot spring smelling of iron",
])
table("urban-place", "Urban Place", "Locations & Settings", [
    "A bathhouse with a private back room",
    "A market square that floods at high tide",
    "A tenement stair everyone avoids",
    "A rooftop pigeon post",
    "A pawnshop that never haggles",
    "A shrine wedged between two taverns",
    "A courtyard of feuding laundries",
    "A gate where guards take long lunches",
    "A bridge under which business is done",
    "A theater dark since the accident",
    "A bakery up before every dawn",
    "A stable that asks no questions",
    "A public well with a locked lid",
    "A scrivener's stall outside the courts",
    "A fighting pit that calls itself a gym",
    "A garden kept by a silent order",
    "A chandlery that smells of the sea",
    "A tailor beloved by two rival houses",
    "An auction yard for seized goods",
    "A crypt entrance dressed as a wine cellar",
])
table("sensory", "Sensory Detail", "Locations & Settings", [
    "Woodsmoke and wet wool",
    "A bell tolling off-rhythm",
    "Light through a colored pane",
    "The drip of unseen water",
    "Fresh bread over old rot",
    "A chill that follows you",
    "Distant hammering, then silence",
    "The taste of dust on the wind",
    "Laughter through a thin wall",
    "Tar, rope, and fish scales",
    "A floor that gives underfoot",
    "The hum of many small wings",
])

# -- Objects & Items ----------------------------------------------------------
table("trinket", "Pocket Trinket", "Objects & Items", [
    "A brass key filed nearly smooth",
    "A dried flower pressed in wax",
    "A die that always shows the same face",
    "A child's carved toy soldier",
    "A ticket stub for a ship long sunk",
    "A ring sized for no human finger",
    "A lens that tints the world amber",
    "A coin from a country nobody knows",
    "A lock of hair tied with wire",
    "A tiny bell with no clapper",
    "A folded map missing its middle",
    "A tooth, drilled and threaded",
    "A miniature portrait, face scratched out",
    "A vial of sand that never settles",
    "A button from a uniform, still bloody",
    "A whistle only animals react to",
    "A thimble etched with a prayer",
    "A playing card with a handwritten IOU",
    "A stone that is warm at night",
    "A spool of thread that never tangles",
])
table("item-quirk", "Item Quirk", "Objects & Items", [
    "Bears a maker's mark from a rival city",
    "Repaired with the wrong materials",
    "Engraved with someone's initials",
    "Smells faintly of incense",
    "Older than it should be",
    "Obviously one of a pair",
    "Weighted subtly wrong",
    "Painted over a different color",
    "Missing a piece someone kept",
    "Stamped 'property of' — name illegible",
    "Immaculate except one deep scratch",
    "Warm, as if recently used",
])

# -- Events & Encounters ------------------------------------------------------
table("complication", "Complication", "Events & Encounters", [
    "A witness sees something they shouldn't",
    "The weather turns at the worst moment",
    "A tool or weapon breaks mid-use",
    "An old acquaintance appears, inconveniently",
    "The item isn't where it was left",
    "Someone lied about the terms",
    "A patrol changes its route",
    "An animal raises the alarm",
    "The bridge, door, or pass is closed",
    "A rival got here first",
    "A debt is called in, now",
    "The map is wrong about one thing",
    "Someone recognizable is in the crowd",
    "A child is underfoot at the wrong time",
    "The contact doesn't show",
    "A fire starts — small, for now",
    "Two problems arrive at once",
    "The escape route is blocked",
    "An injury reopens",
    "Someone offers help with strings attached",
])
table("twist", "Sudden Twist", "Events & Encounters", [
    "They were working together all along",
    "The victim staged it",
    "It's the wrong body",
    "The letter was a forgery",
    "Someone inside gave the signal",
    "The treasure is a fake — the real one moved",
    "The enemy wants the same thing you do",
    "It happened a day earlier than everyone thinks",
    "The witness is the culprit",
    "There are two of them",
    "The 'stranger' grew up here",
    "The deadline was a lie to force a mistake",
])
table("road-encounter", "Road Encounter", "Events & Encounters", [
    "A cart with a shattered wheel and a nervous driver",
    "Pilgrims singing to keep pace",
    "A toll rope where no toll should be",
    "Riders moving fast, looking back",
    "A peddler selling one impossible thing",
    "Livestock loose on the road, no herder",
    "Two travelers arguing over a map",
    "A checkpoint that wasn't here last week",
    "Fresh wreckage, already picked over",
    "A funeral procession going the wrong way",
    "A messenger begging for a fresh horse",
    "Someone sleeping dangerously near the verge",
])

# -- Plot & Adventure Hooks ---------------------------------------------------
table("hook", "Adventure Hook", "Plot & Adventure Hooks", [
    "A well-paying escort job with a vague destination",
    "Someone is buying up a worthless commodity",
    "A landmark vanished overnight",
    "Three people report the same dream",
    "A dead letter finally arrives, decades late",
    "The town's protector didn't come back",
    "A bounty is posted for someone already dead",
    "The harvest is early — and wrong",
    "A locked room upstairs is suddenly rented",
    "An heirloom turns up in a stranger's stall",
    "The ferry stopped running mid-river",
    "A child knows a password they shouldn't",
    "Two funerals for the same person",
    "A rival crew is hiring muscle, quietly",
    "The bells rang last night; no one rang them",
    "An old enemy asks for protection",
    "A map is being sold in pieces",
    "The well water tastes of salt, far inland",
    "A caravan arrives with one wagon too many",
    "Someone is paying for memories of a certain year",
])
table("villain-goal", "Villain's Goal", "Plot & Adventure Hooks", [
    "Legitimacy — a title, a seat, a name",
    "To erase a specific record of the past",
    "Control of a route everyone depends on",
    "A cure, no matter what it costs others",
    "To be feared by the ones who laughed",
    "Collect a set — the last piece is here",
    "Provoke a war someone will pay them to win",
    "Replace a leader with their own creature",
    "Outlaw the thing that ruined them",
    "A quiet retirement funded by one last job",
    "To prove their theory by demonstration",
    "Immortality of some kind — any kind",
])

# -- Dungeon & Exploration ----------------------------------------------------
table("room-feature", "Room Feature", "Dungeon & Exploration", [
    "A collapsed ceiling, sky or stone above",
    "Scorch marks in a fan pattern",
    "Furniture stacked into a barricade",
    "A mural defaced with intent",
    "Standing water, ankle deep",
    "A staircase that was walled off",
    "Bones sorted by size",
    "A cold draft from a sealed wall",
    "Tally marks — hundreds of them",
    "A table set for a meal never eaten",
    "Rusted chains bolted at head height",
    "A mosaic floor with one missing tile",
    "Roots breaking through, strangely healthy",
    "An altar repurposed as a workbench",
    "Fresh footprints in old dust",
    "A well or shaft with no bottom in sight",
    "Doors removed from every hinge",
    "A cache hidden badly, or found and re-hidden",
    "Writing in two languages, one crossed out",
    "A cage sized for something large, sprung open",
])
table("trap", "Trap", "Dungeon & Exploration", [
    "A tripline strung at ankle height",
    "A floor plate that clicks — then nothing, yet",
    "Bad air pooling in the low passage",
    "A counterweighted door that slams and locks",
    "Loose treads on a long stair",
    "A lure: something valuable, visible, staged",
    "Needles in the lock's keyhole",
    "A ceiling net of rubble and dust",
    "A false floor over a flooded cellar",
    "Bells wired to warn something deeper in",
    "A hallway that narrows by design",
    "A mark that looks like treasure-finders' code — it lies",
])

# -- Social & Roleplay --------------------------------------------------------
table("reaction", "NPC Reaction", "Social & Roleplay", [
    "Hostile — reaches for a weapon or a whistle",
    "Cold — answers in single words",
    "Wary — keeps a table between you",
    "Transactional — everything has a price",
    "Curious — asks more than they answer",
    "Neutral — genuinely too busy to care",
    "Chatty — helpful, if you can steer it",
    "Warm — offers food, gossip, or both",
    "Impressed — wants to be part of it",
    "Fawning — too eager; something's off",
    "Protective — of someone or something here",
    "Desperate — sees you as a way out",
])
table("rumor", "Rumor at the Inn", "Social & Roleplay", [
    "The mill owner pays double for night work — no one takes it twice",
    "Something has been taking dogs, but only black ones",
    "The magistrate's signature changed last spring",
    "There's a room here nobody is given",
    "The old road is faster now — and that's the problem",
    "A stranger paid in ancient coin and left before dawn",
    "The shrine's offering box is emptied by morning, untouched by hands",
    "Two farms are feuding over a field neither will plant",
    "The last three couriers took the long way, or didn't arrive",
    "Someone's been buying lamp oil in bulk",
    "The choir won't sing the third verse anymore",
    "A fisherman swears the lake got deeper",
    "The blacksmith's apprentice left mid-order, tools and all",
    "They reopened the mine on the quiet",
    "A wedding was called off an hour before the vows",
    "The healer turns away anyone from the north bank",
    "There's fresh masonry in the crypt wall",
    "The tax men came early and left empty-handed",
    "An old soldier keeps watch on the ridge every dusk",
    "The children have a new counting rhyme — listen to the names",
])

# -- Names --------------------------------------------------------------------
table("tavern-name", "Tavern Name", "Names", [
    "The Crooked Lantern",
    "The Salt and Candle",
    "The Drowned Bell",
    "The Grinning Mule",
    "The Last Ferry",
    "The Copper Kettle",
    "The Widow's Rest",
    "The Three Nails",
    "The Hollow Crown",
    "The Patient Wolf",
    "The Broken Oar",
    "The Second Sunrise",
    "The Iron Thistle",
    "The Quiet Anvil",
    "The Gilded Turnip",
    "The Wandering Door",
    "The Bald Raven",
    "The Honest Liar",
    "The Ember and Ash",
    "The Ninth Step",
])

# -- Inspiration & Prompts ----------------------------------------------------
table("spark", "Story Spark", "Inspiration & Prompts", [
    "A promise made under duress",
    "A door that should be locked",
    "The wrong person is grateful",
    "Something borrowed, never returned",
    "A signal with no agreed meaning",
    "An apology delivered too late",
    "The tool outlived its purpose",
    "A crowd where a face is missing",
    "The rehearsal went too well",
    "A gift that obligates",
    "An heir nobody expected",
    "The second attempt at the same crime",
])


def verify():
    errors = []
    if len(T) < 15:
        errors.append(f"too few tables: {len(T)}")
    ids = [t["id"] for t in T]
    if len(set(ids)) != len(ids):
        errors.append("duplicate table ids")
    for t in T:
        if not t["id"].startswith("starter-"):
            errors.append(f"{t['id']}: missing starter- prefix")
        if not t["name"].strip():
            errors.append(f"{t['id']}: empty name")
        if t["cat"] not in CATEGORIES:
            errors.append(f"{t['id']}: unknown category {t['cat']!r}")
        rows = t["rows"]
        if len(rows) not in (10, 12, 20):
            errors.append(f"{t['id']}: odd row count {len(rows)}")
        if len(set(rows)) != len(rows):
            errors.append(f"{t['id']}: duplicate rows")
        if any(not r.strip() for r in rows):
            errors.append(f"{t['id']}: blank row")
    if errors:
        for e in errors:
            print("FAIL:", e, file=sys.stderr)
        sys.exit(1)


def main():
    verify()
    pack = {"kind": "juice-table-pack", "v": 1, "tables": T}
    out = "assets/starter_tables.json"
    with open(out, "w") as f:
        json.dump(pack, f, ensure_ascii=False, indent=1)
        f.write("\n")
    rows = sum(len(t["rows"]) for t in T)
    print(f"wrote {out}: {len(T)} tables, {rows} rows")


if __name__ == "__main__":
    main()
