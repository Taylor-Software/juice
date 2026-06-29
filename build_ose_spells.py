#!/usr/bin/env python3
"""Generate assets/spells_ose.json — OSE / B/X arcane & divine spells.

Source: Old-School Essentials / B-X D&D, OGL 1.0a. B/X spell mechanics are
non-copyrightable; descriptions here are concise authored summaries of each
spell's effect (not verbatim rulebook prose). Representative selection of
Magic-User (arcane) and Cleric (divine) spells, levels 1-3.

Self-verifies: unique ids, non-empty name/description, level 1-3.
Run: python3 build_ose_spells.py   (writes assets/spells_ose.json)
"""
import json
import sys

# (name, level, school, classes, description)
SPELLS = [
    # --- Magic-User, Level 1 ---
    ("Charm Person", 1, "Arcane", ["Magic-User"], "One humanoid sees you as a trusted ally until dispelled."),
    ("Detect Magic", 1, "Arcane", ["Magic-User"], "You perceive enchantments and magic auras nearby for a short time."),
    ("Floating Disc", 1, "Arcane", ["Magic-User"], "A levitating disc of force follows you, carrying heavy loads."),
    ("Hold Portal", 1, "Arcane", ["Magic-User"], "A door or gate is magically held shut."),
    ("Light", 1, "Arcane", ["Magic-User"], "An object glows like a torch, or blinds a target who fails a save."),
    ("Magic Missile", 1, "Arcane", ["Magic-User"], "An unerring dart of force strikes for 1d6+1 damage."),
    ("Protection from Evil", 1, "Arcane", ["Magic-User"], "A ward hampers enemy attacks and bars enchanted creatures."),
    ("Read Magic", 1, "Arcane", ["Magic-User"], "You decipher magical writing and scrolls."),
    ("Sleep", 1, "Arcane", ["Magic-User"], "Weak creatures in an area fall into magical slumber."),
    ("Ventriloquism", 1, "Arcane", ["Magic-User"], "Your voice seems to issue from elsewhere."),
    # --- Magic-User, Level 2 ---
    ("Continual Light", 2, "Arcane", ["Magic-User"], "A permanent, bright daylight glow, or blinding burst on a target."),
    ("Detect Invisible", 2, "Arcane", ["Magic-User"], "You see invisible and hidden creatures and objects."),
    ("ESP", 2, "Arcane", ["Magic-User"], "You read the surface thoughts of nearby creatures."),
    ("Invisibility", 2, "Arcane", ["Magic-User"], "A creature or object becomes unseen until it attacks."),
    ("Knock", 2, "Arcane", ["Magic-User"], "Locked, barred, or stuck doors and chests spring open."),
    ("Levitate", 2, "Arcane", ["Magic-User"], "You move yourself vertically through the air by will."),
    ("Mirror Image", 2, "Arcane", ["Magic-User"], "Illusory duplicates of you absorb incoming attacks."),
    ("Web", 2, "Arcane", ["Magic-User"], "Sticky strands fill an area, entangling those within."),
    # --- Magic-User, Level 3 ---
    ("Dispel Magic", 3, "Arcane", ["Magic-User"], "You end ongoing spells and magical effects in an area."),
    ("Fire Ball", 3, "Arcane", ["Magic-User"], "A burst of flame deals damage to all in the area (save for half)."),
    ("Fly", 3, "Arcane", ["Magic-User"], "A creature gains the power of flight for a time."),
    ("Haste", 3, "Arcane", ["Magic-User"], "Targets move and attack at double speed."),
    ("Hold Person", 3, "Arcane", ["Magic-User"], "Humanoid targets are paralysed unless they save."),
    ("Lightning Bolt", 3, "Arcane", ["Magic-User"], "A stroke of lightning blasts everything in a line (save for half)."),
    ("Invisibility 10' Radius", 3, "Arcane", ["Magic-User"], "You and nearby allies become invisible."),
    # --- Cleric, Level 1 ---
    ("Cure Light Wounds", 1, "Divine", ["Cleric"], "Heals 1d6+1 damage, or harms undead with reversed casting."),
    ("Detect Evil", 1, "Divine", ["Cleric"], "You sense evil intent and cursed objects nearby."),
    ("Light (Cleric)", 1, "Divine", ["Cleric"], "An object glows like a torch, or blinds a target who fails a save."),
    ("Protection from Evil (Cleric)", 1, "Divine", ["Cleric"], "A ward hampers enemy attacks and bars enchanted creatures."),
    ("Purify Food and Water", 1, "Divine", ["Cleric"], "Spoiled rations and tainted water are made wholesome."),
    # --- Cleric, Level 2 ---
    ("Bless", 2, "Divine", ["Cleric"], "Allies gain bonuses to attacks and morale (or a curse, reversed)."),
    ("Find Traps", 2, "Divine", ["Cleric"], "Nearby mechanical and magical traps are revealed."),
    ("Hold Person (Cleric)", 2, "Divine", ["Cleric"], "Humanoid targets are paralysed unless they save."),
    ("Silence 15' Radius", 2, "Divine", ["Cleric"], "An area is wrapped in total silence, foiling spellcasting."),
    ("Speak with Animals", 2, "Divine", ["Cleric"], "You converse with natural beasts."),
    # --- Cleric, Level 3 ---
    ("Cure Disease", 3, "Divine", ["Cleric"], "You cure a creature of disease (or inflict one, reversed)."),
    ("Remove Curse", 3, "Divine", ["Cleric"], "You lift a curse from a creature or object (or bestow one)."),
    ("Striking", 3, "Divine", ["Cleric"], "A weapon deals extra magical damage for a time."),
]


def build():
    out = []
    for name, level, school, classes, desc in SPELLS:
        slug = name.lower().replace("'", "").replace(" ", "-").replace("(", "").replace(")", "")
        out.append({
            "id": f"ose-{slug}",
            "system": "ose",
            "name": name,
            "level": level,
            "school": school,
            "classes": classes,
            "description": desc,
        })
    return out


def verify(spells):
    fails, seen = [], set()
    for s in spells:
        if not s["id"] or s["id"] in seen:
            fails.append(f"bad/dup id: {s.get('name')!r}")
        seen.add(s["id"])
        if not s["name"] or not s["description"]:
            fails.append(f"empty name/desc: {s['id']}")
        if not (1 <= s["level"] <= 3):
            fails.append(f"bad level {s['level']} on {s['id']}")
    return fails


def main():
    spells = build()
    fails = verify(spells)
    if fails:
        print("VERIFICATION FAILED:")
        for f in fails:
            print("  -", f)
        sys.exit(1)
    out = "assets/spells_ose.json"
    with open(out, "w") as f:
        json.dump(spells, f, ensure_ascii=False, indent=2)
    print(f"{out}: {len(spells)} spells. All checks passed.")


if __name__ == "__main__":
    main()
