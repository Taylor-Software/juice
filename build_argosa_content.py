#!/usr/bin/env python3
"""Generate assets/foes_argosa.json — Tales of Argosa creature stat blocks.

Source: Tales of Argosa by S.J. Grodzicki / Pickpocket Press, CC-BY-SA-4.0.
Facts-only sword & sorcery bestiary: ascending AC, HD (→ average HP), attacks
as dice notation, morale + notes. Authored representative creatures (not the
full book). The script is the source of truth — edit it, rerun, copy output.

Self-verifies: unique ids, non-empty names, HP > 0.
Run: python3 build_argosa_content.py   (writes assets/foes_argosa.json)
"""
import json
import sys

# Creature JSON shape (matches Dart Creature/StatBlock):
#   {id, name, maxHp, statBlock:{ac, attacks:[{name,detail}], notes}}
# notes carries HD / Morale / movement / special — the OSR facts.
CREATURES = [
    {"id": "argosa-brigand", "name": "Brigand", "maxHp": 5,
     "statBlock": {"ac": 13, "attacks": [{"name": "Sword", "detail": "1d8"},
                   {"name": "Short bow", "detail": "1d6"}],
                   "notes": "HD 1, Morale 8. Roams in bands; flees when outmatched."}},
    {"id": "argosa-cultist", "name": "Blood Cultist", "maxHp": 5,
     "statBlock": {"ac": 12, "attacks": [{"name": "Ritual dagger", "detail": "1d4"}],
                   "notes": "HD 1, Morale 9. Fanatical; sacrifices captives to dark powers."}},
    {"id": "argosa-cult-priest", "name": "Cult Priest", "maxHp": 14,
     "statBlock": {"ac": 13, "attacks": [{"name": "Mace", "detail": "1d6"},
                   {"name": "Dark prayer", "detail": "save or fear"}],
                   "notes": "HD 3, Morale 10. Commands cultists; minor sorcery."}},
    {"id": "argosa-sand-viper", "name": "Sand Viper", "maxHp": 4,
     "statBlock": {"ac": 13, "attacks": [{"name": "Bite", "detail": "1d4 + poison (save or paralysed)"}],
                   "notes": "HD 1, Morale 7. Buried in dunes; strikes from ambush."}},
    {"id": "argosa-desert-lion", "name": "Desert Lion", "maxHp": 16,
     "statBlock": {"ac": 13, "attacks": [{"name": "Claw", "detail": "1d4"},
                   {"name": "Claw", "detail": "1d4"}, {"name": "Bite", "detail": "1d8"}],
                   "notes": "HD 4, Morale 9. Hunts in prides on the open steppe."}},
    {"id": "argosa-jackalman", "name": "Jackal-Man", "maxHp": 9,
     "statBlock": {"ac": 13, "attacks": [{"name": "Spear", "detail": "1d6"},
                   {"name": "Bite", "detail": "1d4"}],
                   "notes": "HD 2, Morale 8. Cackling desert raiders; cowardly alone."}},
    {"id": "argosa-giant-scorpion", "name": "Giant Scorpion", "maxHp": 18,
     "statBlock": {"ac": 16, "attacks": [{"name": "Claw", "detail": "1d6"},
                   {"name": "Claw", "detail": "1d6"},
                   {"name": "Sting", "detail": "1d4 + poison (save or die)"}],
                   "notes": "HD 4, Morale 11. Lethal venom; armoured carapace."}},
    {"id": "argosa-serpent-folk", "name": "Serpent-Folk Sorcerer", "maxHp": 14,
     "statBlock": {"ac": 13, "attacks": [{"name": "Envenomed blade", "detail": "1d6 + poison"},
                   {"name": "Hypnotic gaze", "detail": "save or charmed"}],
                   "notes": "HD 4, Morale 9. Ancient reptilian wizards; serpent magic."}},
    {"id": "argosa-ghoul", "name": "Ghoul", "maxHp": 9,
     "statBlock": {"ac": 13, "attacks": [{"name": "Claw", "detail": "1d3 + paralysis"},
                   {"name": "Bite", "detail": "1d4"}],
                   "notes": "HD 2, Morale 9. Undead; touch paralyses the living."}},
    {"id": "argosa-tomb-wight", "name": "Tomb Wight", "maxHp": 14,
     "statBlock": {"ac": 15, "attacks": [{"name": "Cold touch", "detail": "1d6 + 1 level drain"}],
                   "notes": "HD 3, Morale 12. Undead; struck only by silver or magic."}},
    {"id": "argosa-mummy-guardian", "name": "Mummy Guardian", "maxHp": 23,
     "statBlock": {"ac": 16, "attacks": [{"name": "Crushing fist", "detail": "1d10 + rot"}],
                   "notes": "HD 5, Morale 12. Undead; rot disease, half damage from mundane weapons."}},
    {"id": "argosa-pit-fiend-imp", "name": "Lesser Demon", "maxHp": 14,
     "statBlock": {"ac": 15, "attacks": [{"name": "Claws", "detail": "1d6+1d6"},
                   {"name": "Hellish bite", "detail": "1d8"}],
                   "notes": "HD 4, Morale 11. Summoned horror; resists fire."}},
    {"id": "argosa-giant-spider", "name": "Giant Spider", "maxHp": 14,
     "statBlock": {"ac": 13, "attacks": [{"name": "Bite", "detail": "1d6 + poison (save or die)"}],
                   "notes": "HD 3, Morale 8. Webs immobilise; lurks in ruins."}},
    {"id": "argosa-ape-beast", "name": "White Ape", "maxHp": 18,
     "statBlock": {"ac": 13, "attacks": [{"name": "Fists", "detail": "1d8+1d8"},
                   {"name": "Rend", "detail": "1d10"}],
                   "notes": "HD 4, Morale 9. Savage ruin-dweller; immense strength."}},
    {"id": "argosa-harpy", "name": "Harpy", "maxHp": 13,
     "statBlock": {"ac": 12, "attacks": [{"name": "Talons", "detail": "1d4+1d4"},
                   {"name": "Song", "detail": "save or lured"}],
                   "notes": "HD 3, Morale 7. Flight; beguiling song draws victims close."}},
    {"id": "argosa-stone-golem", "name": "Stone Sentinel", "maxHp": 27,
     "statBlock": {"ac": 17, "attacks": [{"name": "Slam", "detail": "1d10"},
                   {"name": "Slam", "detail": "1d10"}],
                   "notes": "HD 6, Morale 12. Construct; immune to fear, sleep, charm."}},
    {"id": "argosa-pirate", "name": "Corsair", "maxHp": 9,
     "statBlock": {"ac": 13, "attacks": [{"name": "Cutlass", "detail": "1d8"}],
                   "notes": "HD 2, Morale 8. Coastal raiders; fight dirty."}},
    {"id": "argosa-sea-serpent", "name": "Sea Serpent", "maxHp": 36,
     "statBlock": {"ac": 16, "attacks": [{"name": "Bite", "detail": "3d6"},
                   {"name": "Constrict", "detail": "2d6"}],
                   "notes": "HD 8, Morale 10. Capsizes small craft; swallows whole."}},
    {"id": "argosa-flesh-eater", "name": "Carrion Crawler", "maxHp": 14,
     "statBlock": {"ac": 13, "attacks": [{"name": "Tentacles", "detail": "save or paralysed"},
                   {"name": "Bite", "detail": "1d4"}],
                   "notes": "HD 3, Morale 9. Eight paralysing tentacles; scavenger."}},
    {"id": "argosa-skeleton-warrior", "name": "Skeleton Warrior", "maxHp": 5,
     "statBlock": {"ac": 13, "attacks": [{"name": "Rusted blade", "detail": "1d8"}],
                   "notes": "HD 1, Morale 12. Undead; mindless, immune to fear."}},
    {"id": "argosa-warlord", "name": "Barbarian Warlord", "maxHp": 23,
     "statBlock": {"ac": 15, "attacks": [{"name": "Great axe", "detail": "1d10+2"}],
                   "notes": "HD 5, Morale 10. Commands raiders; ferocious in melee."}},
    {"id": "argosa-night-stalker", "name": "Night Stalker", "maxHp": 18,
     "statBlock": {"ac": 14, "attacks": [{"name": "Shadow claws", "detail": "1d8 + 1d4 cold"}],
                   "notes": "HD 4, Morale 10. Hunts in darkness; surprises on 1-4 in 6."}},
]


def verify(creatures):
    fails, seen = [], set()
    for c in creatures:
        if not c.get("id") or c["id"] in seen:
            fails.append(f"bad/dup id: {c.get('name')!r}")
        seen.add(c.get("id"))
        if not c.get("name"):
            fails.append(f"empty name: {c.get('id')!r}")
        if not c.get("maxHp", 0) > 0:
            fails.append(f"bad maxHp: {c.get('id')!r}")
        for a in (c.get("statBlock") or {}).get("attacks", []):
            if not a.get("name"):
                fails.append(f"unnamed attack: {c.get('id')!r}")
    return fails


def main():
    fails = verify(CREATURES)
    if fails:
        print("VERIFICATION FAILED:")
        for f in fails:
            print("  -", f)
        sys.exit(1)
    out = "assets/foes_argosa.json"
    with open(out, "w") as f:
        json.dump(CREATURES, f, ensure_ascii=False, indent=2)
    print(f"{out}: {len(CREATURES)} creatures. All checks passed.")


if __name__ == "__main__":
    main()
