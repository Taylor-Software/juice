#!/usr/bin/env python3
"""Generate assets/foes_knave.json + assets/spells_knave.json — Knave 2e content.

Source: Knave Second Edition by Ben Milton / Questing Beast, CC-BY-4.0.
Facts-only minimal bestiary (Knave uses HP + simple attacks) and a set of
spells (Knave spells are level-less; rendered with concise authored summaries
of the spell's effect, not verbatim rulebook prose). Representative selection,
not the full book. The script is the source of truth.

Self-verifies: unique ids, non-empty names, HP > 0 (creatures), non-empty
descriptions (spells).
Run: python3 build_knave_content.py
"""
import json
import sys

CREATURES = [
    {"id": "knave-bandit", "name": "Bandit", "maxHp": 6,
     "statBlock": {"ac": 12, "attacks": [{"name": "Sword", "detail": "1d6"}],
                   "notes": "Morale 7. Waylays travellers; flees if losing."}},
    {"id": "knave-goblin", "name": "Goblin", "maxHp": 4,
     "statBlock": {"ac": 12, "attacks": [{"name": "Crude spear", "detail": "1d6"}],
                   "notes": "Morale 6. Swarms; cunning traps."}},
    {"id": "knave-hobgoblin", "name": "Hobgoblin", "maxHp": 9,
     "statBlock": {"ac": 14, "attacks": [{"name": "Blade", "detail": "1d8"}],
                   "notes": "Morale 9. Disciplined goblinoid soldiers."}},
    {"id": "knave-orc", "name": "Orc", "maxHp": 8,
     "statBlock": {"ac": 13, "attacks": [{"name": "Axe", "detail": "1d8"}],
                   "notes": "Morale 8. Brutal raiders in warbands."}},
    {"id": "knave-skeleton", "name": "Skeleton", "maxHp": 5,
     "statBlock": {"ac": 12, "attacks": [{"name": "Old blade", "detail": "1d6"}],
                   "notes": "Morale 12. Undead; mindless, fearless."}},
    {"id": "knave-zombie", "name": "Zombie", "maxHp": 8,
     "statBlock": {"ac": 10, "attacks": [{"name": "Slam", "detail": "1d6"}],
                   "notes": "Morale 12. Undead; slow, never flees."}},
    {"id": "knave-ghoul", "name": "Ghoul", "maxHp": 9,
     "statBlock": {"ac": 13, "attacks": [{"name": "Claws", "detail": "1d6 + paralysis"}],
                   "notes": "Morale 9. Undead; touch paralyses."}},
    {"id": "knave-giant-rat", "name": "Giant Rat", "maxHp": 3,
     "statBlock": {"ac": 11, "attacks": [{"name": "Bite", "detail": "1d4 + disease"}],
                   "notes": "Morale 5. Infests sewers and dungeons."}},
    {"id": "knave-giant-spider", "name": "Giant Spider", "maxHp": 12,
     "statBlock": {"ac": 13, "attacks": [{"name": "Bite", "detail": "1d6 + poison"}],
                   "notes": "Morale 8. Webs the unwary."}},
    {"id": "knave-wolf", "name": "Wolf", "maxHp": 6,
     "statBlock": {"ac": 12, "attacks": [{"name": "Bite", "detail": "1d6"}],
                   "notes": "Morale 7. Hunts in packs."}},
    {"id": "knave-bear", "name": "Cave Bear", "maxHp": 18,
     "statBlock": {"ac": 13, "attacks": [{"name": "Claw", "detail": "1d8"},
                   {"name": "Bite", "detail": "1d8"}],
                   "notes": "Morale 8. Ferocious when cornered."}},
    {"id": "knave-ogre", "name": "Ogre", "maxHp": 19,
     "statBlock": {"ac": 13, "attacks": [{"name": "Club", "detail": "1d10"}],
                   "notes": "Morale 10. Hurls boulders; dim-witted."}},
    {"id": "knave-troll", "name": "Troll", "maxHp": 28,
     "statBlock": {"ac": 14, "attacks": [{"name": "Claws", "detail": "1d8+1d8"}],
                   "notes": "Morale 10. Regenerates unless burned."}},
    {"id": "knave-giant", "name": "Hill Giant", "maxHp": 32,
     "statBlock": {"ac": 14, "attacks": [{"name": "Greatclub", "detail": "2d8"}],
                   "notes": "Morale 9. Hurls rocks at range."}},
    {"id": "knave-harpy", "name": "Harpy", "maxHp": 11,
     "statBlock": {"ac": 12, "attacks": [{"name": "Talons", "detail": "1d6"},
                   {"name": "Song", "detail": "save or lured"}],
                   "notes": "Morale 7. Beguiling song; flight."}},
    {"id": "knave-wraith", "name": "Wraith", "maxHp": 16,
     "statBlock": {"ac": 15, "attacks": [{"name": "Chill touch", "detail": "1d6 + level drain"}],
                   "notes": "Morale 12. Undead; only magic harms."}},
    {"id": "knave-dragon-young", "name": "Young Dragon", "maxHp": 40,
     "statBlock": {"ac": 17, "attacks": [{"name": "Bite", "detail": "2d8"},
                   {"name": "Breath", "detail": "3d6 (save half)"}],
                   "notes": "Morale 10. Flight; greedy and cunning."}},
    {"id": "knave-slime", "name": "Grey Slime", "maxHp": 10,
     "statBlock": {"ac": 8, "attacks": [{"name": "Acid", "detail": "1d6 (corrodes gear)"}],
                   "notes": "Morale 12. Mindless; clings to ceilings."}},
]

# Knave 2e spells are level-less. Descriptions are concise authored summaries
# of each spell's effect (system: 'knave', level 0, school '').
SPELLS = [
    {"name": "Adhere", "description": "An object becomes coated in a strong adhesive."},
    {"name": "Animate Object", "description": "An object obeys your spoken commands as if alive."},
    {"name": "Anthropomorphize", "description": "An animal gains human intelligence, or a human becomes animal-like."},
    {"name": "Arcane Eye", "description": "A floating invisible eye relays what it sees to you."},
    {"name": "Astral Prison", "description": "An object is frozen in time and space within an invisible sphere."},
    {"name": "Auditory Illusion", "description": "You create illusory sounds from a point you choose."},
    {"name": "Babble", "description": "A creature must loudly and uncontrollably speak its surface thoughts."},
    {"name": "Charm", "description": "A creature treats you as a trusted friend until you act against it."},
    {"name": "Control Weather", "description": "You shift the local weather over several minutes."},
    {"name": "Counterspell", "description": "You negate another spell as it is cast."},
    {"name": "Darkness", "description": "Lightless shadow fills an area, blocking even darkvision."},
    {"name": "Deafen", "description": "All creatures in an area are struck deaf for a time."},
    {"name": "Detect Magic", "description": "You sense the presence and strength of nearby magic."},
    {"name": "Elemental Wall", "description": "A wall of fire, ice, or stone springs up where you direct."},
    {"name": "Filch", "description": "An unattended object teleports into your hand from afar."},
    {"name": "Fog", "description": "Thick fog billows out, obscuring sight."},
    {"name": "Frenzy", "description": "Creatures in an area are driven into a violent rage."},
    {"name": "Gravity Shift", "description": "You reverse or redirect gravity in an area."},
    {"name": "Haste", "description": "A creature moves and acts with doubled speed."},
    {"name": "Knock", "description": "A locked or stuck object springs open."},
    {"name": "Levitate", "description": "An object or creature rises and floats under your control."},
    {"name": "Mirror Image", "description": "Illusory duplicates of yourself confuse attackers."},
    {"name": "Telekinesis", "description": "You move an object at a distance with your mind."},
    {"name": "Telepathy", "description": "You exchange silent thoughts with a creature you can see."},
]


def build_spells():
    out = []
    for s in SPELLS:
        slug = s["name"].lower().replace(" ", "-")
        out.append({
            "id": f"knave-{slug}",
            "system": "knave",
            "name": s["name"],
            "description": s["description"],
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
            fails.append(f"bad/dup spell id: {s.get('name')!r}")
        seen.add(s["id"])
        if not s["name"] or not s["description"]:
            fails.append(f"empty name/desc: {s['id']}")
    return fails


def main():
    spells = build_spells()
    fails = verify_creatures(CREATURES) + verify_spells(spells)
    if fails:
        print("VERIFICATION FAILED:")
        for f in fails:
            print("  -", f)
        sys.exit(1)
    with open("assets/foes_knave.json", "w") as f:
        json.dump(CREATURES, f, ensure_ascii=False, indent=2)
    with open("assets/spells_knave.json", "w") as f:
        json.dump(spells, f, ensure_ascii=False, indent=2)
    print(f"foes_knave.json: {len(CREATURES)} · spells_knave.json: {len(spells)}. "
          "All checks passed.")


if __name__ == "__main__":
    main()
