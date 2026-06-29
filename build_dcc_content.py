#!/usr/bin/env python3
"""Generate assets/foes_dcc.json + assets/spells_dcc.json — Dungeon Crawl Classics.

Source: Dungeon Crawl Classics RPG core (Goodman Games), OGL 1.0a. Game
mechanics under the OGL; descriptions are concise authored summaries, not
verbatim rulebook prose. Representative selection — not the full book.
Not affiliated with Goodman Games.

Self-verifies: unique ids, non-empty names, HP > 0 (creatures), non-empty
descriptions + level 1-5 (spells).
Run: python3 build_dcc_content.py
"""
import json
import sys

CREATURES = [
    {"id": "dcc-goblin", "name": "Goblin", "maxHp": 4,
     "statBlock": {"ac": 12, "attacks": [{"name": "Spear", "detail": "1d6"}],
                   "notes": "HD 1d6, Init +0, Mor 8. Cowardly raiders in packs."}},
    {"id": "dcc-orc", "name": "Orc", "maxHp": 8,
     "statBlock": {"ac": 13, "attacks": [{"name": "Sword", "detail": "1d8"}],
                   "notes": "HD 2d8, Init +0, Mor 9. Warband infantry."}},
    {"id": "dcc-skeleton", "name": "Skeleton", "maxHp": 5,
     "statBlock": {"ac": 12, "attacks": [{"name": "Claw or blade", "detail": "1d6"}],
                   "notes": "HD 1d8, undead, immune to mind effects."}},
    {"id": "dcc-zombie", "name": "Zombie", "maxHp": 13,
     "statBlock": {"ac": 9, "attacks": [{"name": "Slam", "detail": "1d4"}],
                   "notes": "HD 3d6, undead, always acts last."}},
    {"id": "dcc-wolf", "name": "Wolf", "maxHp": 9,
     "statBlock": {"ac": 12, "attacks": [{"name": "Bite", "detail": "1d4+1"}],
                   "notes": "HD 2d6, Init +2. Pack hunters, fast."}},
    {"id": "dcc-giant-rat", "name": "Giant Rat", "maxHp": 2,
     "statBlock": {"ac": 11, "attacks": [{"name": "Bite", "detail": "1d3 + disease"}],
                   "notes": "HD 1d4. Swarms in the dark."}},
    {"id": "dcc-giant-spider", "name": "Giant Spider", "maxHp": 11,
     "statBlock": {"ac": 13, "attacks": [{"name": "Bite", "detail": "1d6 + poison (DC 12 Fort or 1d6 Str)"}],
                   "notes": "HD 3d8. Lairs in webs."}},
    {"id": "dcc-ogre", "name": "Ogre", "maxHp": 22,
     "statBlock": {"ac": 14, "attacks": [{"name": "Great club", "detail": "1d10+4"}],
                   "notes": "HD 4d8, Mor 10. Hurls boulders."}},
    {"id": "dcc-troll", "name": "Troll", "maxHp": 36,
     "statBlock": {"ac": 16, "attacks": [{"name": "Claw", "detail": "1d6+4"},
                   {"name": "Bite", "detail": "1d8+4"}],
                   "notes": "HD 6d8. Regenerates 3/round unless fire or acid."}},
    {"id": "dcc-ghoul", "name": "Ghoul", "maxHp": 9,
     "statBlock": {"ac": 12, "attacks": [{"name": "Claw", "detail": "1d4 + paralysis (DC 13 Will)"}],
                   "notes": "HD 2d6, undead. Paralysing touch."}},
    {"id": "dcc-wraith", "name": "Wraith", "maxHp": 22,
     "statBlock": {"ac": 15, "attacks": [{"name": "Touch", "detail": "1d6 + 1 level drain"}],
                   "notes": "HD 4d12, undead. Only magic weapons harm it."}},
    {"id": "dcc-mummy", "name": "Mummy", "maxHp": 30,
     "statBlock": {"ac": 16, "attacks": [{"name": "Fist", "detail": "1d12 + rot"}],
                   "notes": "HD 6d8, undead. Mummy rot; fears fire."}},
    {"id": "dcc-beastman", "name": "Beastman", "maxHp": 11,
     "statBlock": {"ac": 13, "attacks": [{"name": "Axe", "detail": "1d8+2"},
                   {"name": "Horns", "detail": "1d6"}],
                   "notes": "HD 3d8, Mor 9. Chaos-warped raiders."}},
    {"id": "dcc-mind-flayer", "name": "Brain-Eater", "maxHp": 36,
     "statBlock": {"ac": 16, "attacks": [{"name": "Tentacles", "detail": "1d4 + grab"},
                   {"name": "Mind blast", "detail": "stun (DC 16 Will)"}],
                   "notes": "HD 8d8. Psionic horror; devours brains."}},
    {"id": "dcc-demon-minor", "name": "Type I Demon", "maxHp": 27,
     "statBlock": {"ac": 16, "attacks": [{"name": "Claws", "detail": "1d6+1d6"},
                   {"name": "Bite", "detail": "1d8"}],
                   "notes": "HD 6d12, chaotic. Resists non-magic weapons; minor magic."}},
    {"id": "dcc-dragon-wyrmling", "name": "Dragon (Young)", "maxHp": 45,
     "statBlock": {"ac": 18, "attacks": [{"name": "Bite", "detail": "2d6+5"},
                   {"name": "Breath", "detail": "4d6 (DC 15 Reflex half)"}],
                   "notes": "HD 8d12. Flight; innate spellcasting and greed."}},
    {"id": "dcc-purple-worm", "name": "Purple Worm", "maxHp": 70,
     "statBlock": {"ac": 15, "attacks": [{"name": "Bite", "detail": "2d8 + swallow"},
                   {"name": "Sting", "detail": "1d8 + poison"}],
                   "notes": "HD 12d8. Burrows; swallows whole on a strong hit."}},
    {"id": "dcc-gelatinous-cube", "name": "Gelatinous Cube", "maxHp": 27,
     "statBlock": {"ac": 8, "attacks": [{"name": "Engulf", "detail": "2d4 acid + paralysis"}],
                   "notes": "HD 6d8. Near-invisible; fills corridors."}},
    {"id": "dcc-stirge", "name": "Stirge", "maxHp": 3,
     "statBlock": {"ac": 14, "attacks": [{"name": "Proboscis", "detail": "1d3 + blood drain"}],
                   "notes": "HD 1d4, Init +4. Swarms and latches on."}},
    {"id": "dcc-bandit", "name": "Bandit", "maxHp": 5,
     "statBlock": {"ac": 12, "attacks": [{"name": "Sword", "detail": "1d8"},
                   {"name": "Crossbow", "detail": "1d6"}],
                   "notes": "HD 1d8, Mor 7. Ambush travellers."}},
]

# (name, level, classes, description) — DCC spell mechanics under OGL; concise
# authored effect summaries.
SPELLS = [
    ("Magic Missile", 1, ["Wizard"], "Bolts of force strike targets; the result die scales the number and damage."),
    ("Magic Shield", 1, ["Wizard"], "An invisible shield of force improves your defenses."),
    ("Cantrip", 1, ["Wizard"], "Minor magical tricks and effects of the caster's choosing."),
    ("Choking Cloud", 1, ["Wizard"], "A cloud of noxious vapor sickens and damages those within."),
    ("Ropework", 1, ["Wizard"], "You command a rope to move, bind, or animate."),
    ("Spider Climb", 1, ["Wizard"], "You climb walls and ceilings as a spider does."),
    ("Sleep", 1, ["Wizard"], "Creatures in an area fall into magical slumber."),
    ("Invoke Patron", 1, ["Wizard"], "You call on your otherworldly patron for aid; results vary wildly."),
    ("Detect Magic", 1, ["Wizard"], "You sense magical auras and their relative power."),
    ("Animal Summoning", 2, ["Wizard"], "You call beasts to your aid; greater results summon stronger creatures."),
    ("Levitate", 2, ["Wizard"], "You rise and float, controlling your vertical movement."),
    ("Scorching Ray", 2, ["Wizard"], "Searing rays of flame lance out at your foes."),
    ("Fireball", 3, ["Wizard"], "A roaring burst of flame engulfs an area (save for half)."),
    ("Lightning Bolt", 3, ["Wizard"], "A stroke of lightning blasts everything in a line."),
    ("Runic Alphabet", 3, ["Wizard"], "You inscribe potent magical runes with delayed or triggered effects."),
    ("Polymorph", 4, ["Wizard"], "You reshape a creature into another form."),
    ("Control Fire", 1, ["Wizard"], "You shape, douse, or kindle flames within range."),
    # Clerics
    ("Lay on Hands", 1, ["Cleric"], "You heal wounds by touch; aligned targets benefit most."),
    ("Word of Command", 1, ["Cleric"], "A divine command compels a creature to obey a single word."),
    ("Holy Sanctuary", 2, ["Cleric"], "A blessed ward protects an area or creature from harm."),
    ("Cure Paralysis", 2, ["Cleric"], "You free a creature from paralysis and similar bonds."),
    ("Banish", 4, ["Cleric"], "You drive an extraplanar creature back to its home plane."),
    ("Divine Symbol", 3, ["Cleric"], "You manifest your deity's symbol to smite foes or shield allies."),
]


def build_spells():
    out = []
    for name, level, classes, desc in SPELLS:
        slug = name.lower().replace("'", "").replace(" ", "-")
        out.append({
            "id": f"dcc-{slug}",
            "system": "dcc",
            "name": name,
            "level": level,
            "classes": classes,
            "description": desc,
        })
    return out


def verify_creatures(cs):
    fails, seen = [], set()
    for c in cs:
        if not c.get("id") or c["id"] in seen:
            fails.append(f"bad/dup id: {c.get('name')!r}")
        seen.add(c.get("id"))
        if not c.get("maxHp", 0) > 0:
            fails.append(f"bad maxHp: {c.get('id')!r}")
    return fails


def verify_spells(ss):
    fails, seen = [], set()
    for s in ss:
        if not s["id"] or s["id"] in seen:
            fails.append(f"bad/dup id: {s.get('name')!r}")
        seen.add(s["id"])
        if not s["name"] or not s["description"]:
            fails.append(f"empty name/desc: {s['id']}")
        if not (1 <= s["level"] <= 5):
            fails.append(f"bad level {s['level']} on {s['id']}")
    return fails


def main():
    spells = build_spells()
    fails = verify_creatures(CREATURES) + verify_spells(spells)
    if fails:
        print("VERIFICATION FAILED:")
        for f in fails:
            print("  -", f)
        sys.exit(1)
    with open("assets/foes_dcc.json", "w") as f:
        json.dump(CREATURES, f, ensure_ascii=False, indent=2)
    with open("assets/spells_dcc.json", "w") as f:
        json.dump(spells, f, ensure_ascii=False, indent=2)
    print(f"foes_dcc.json: {len(CREATURES)} · spells_dcc.json: {len(spells)}. "
          "All checks passed.")


if __name__ == "__main__":
    main()
