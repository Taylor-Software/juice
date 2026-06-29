#!/usr/bin/env python3
"""Generate assets/foes_cairn.json — Cairn creature stat blocks.

Source: Cairn SRD by Yochai Gal (https://cairnrpg.com), CC BY-SA 4.0.
Stats: HP, Armor (0-3 damage reduction), STR/DEX/WIL (default 10).
Attacks listed with dice notation. All values from the Cairn SRD.

Self-verifies: unique ids, non-empty names, HP > 0.
Run: python3 build_cairn_foes.py   (writes assets/foes_cairn.json)
"""
import json
import sys

# Format: {id, name, maxHp, statBlock: {ac (=Armor), attacks:[{name,detail}], notes}}
# notes = "STR X, DEX X, WIL X" + any special abilities.
CREATURES = [
    {
        "id": "cairn-boggart",
        "name": "Boggart",
        "maxHp": 3,
        "statBlock": {
            "ac": 0,
            "attacks": [{"name": "Rusty Dagger", "detail": "d6"}],
            "notes": "STR 8, DEX 14, WIL 8\nCan become invisible at will.",
        },
    },
    {
        "id": "cairn-cave-locust",
        "name": "Cave Locust",
        "maxHp": 6,
        "statBlock": {
            "ac": 1,
            "attacks": [{"name": "Bite", "detail": "d6"}],
            "notes": "STR 14, DEX 8, WIL 6\nExcretes noxious black fluid when stressed.",
        },
    },
    {
        "id": "cairn-centaur",
        "name": "Centaur",
        "maxHp": 14,
        "statBlock": {
            "ac": 1,
            "attacks": [
                {"name": "Shortbow", "detail": "d6+d8"},
                {"name": "Hooves", "detail": "d10"},
            ],
            "notes": "STR 14, DEX 12, WIL 11",
        },
    },
    {
        "id": "cairn-ettin",
        "name": "Ettin",
        "maxHp": 10,
        "statBlock": {
            "ac": 1,
            "attacks": [{"name": "Club", "detail": "d8+d8 (two heads)"}],
            "notes": "STR 16, DEX 8, WIL 6\nHas two heads; difficult to surprise.",
        },
    },
    {
        "id": "cairn-frost-elf",
        "name": "Frost Elf",
        "maxHp": 14,
        "statBlock": {
            "ac": 1,
            "attacks": [{"name": "Icicle Dagger", "detail": "d6+d8"}],
            "notes": "STR 8, DEX 13, WIL 14\nCarries a Spellbook (d6 spells).",
        },
    },
    {
        "id": "cairn-gargoyle",
        "name": "Gargoyle",
        "maxHp": 8,
        "statBlock": {
            "ac": 2,
            "attacks": [
                {"name": "Claws", "detail": "d6+d6"},
                {"name": "Bite", "detail": "d8"},
            ],
            "notes": "STR 14, DEX 11, WIL 5\nImmune to mundane damage while motionless.",
        },
    },
    {
        "id": "cairn-goblin",
        "name": "Goblin",
        "maxHp": 4,
        "statBlock": {
            "ac": 0,
            "attacks": [{"name": "Rusty Blade", "detail": "d6"}],
            "notes": "STR 8, DEX 12, WIL 8",
        },
    },
    {
        "id": "cairn-green-slime",
        "name": "Green Slime",
        "maxHp": 10,
        "statBlock": {
            "ac": 0,
            "attacks": [{"name": "Corrosive Touch", "detail": "d8 (ignores Armor)"}],
            "notes": "STR 15, DEX 9, WIL 3\nDissolves metal and organic matter on contact.",
        },
    },
    {
        "id": "cairn-grizzly-bear",
        "name": "Grizzly Bear",
        "maxHp": 12,
        "statBlock": {
            "ac": 1,
            "attacks": [
                {"name": "Claws", "detail": "d6+d8"},
                {"name": "Bite", "detail": "d10"},
            ],
            "notes": "STR 15, DEX 12, WIL 8",
        },
    },
    {
        "id": "cairn-harpy",
        "name": "Harpy",
        "maxHp": 12,
        "statBlock": {
            "ac": 0,
            "attacks": [
                {"name": "Talons", "detail": "d6+d6"},
                {"name": "Beguiling Song", "detail": "WIL save or enthralled"},
            ],
            "notes": "STR 12, DEX 14, WIL 8\nBewitching song forces WIL save or enthrallment.",
        },
    },
    {
        "id": "cairn-hobgoblin",
        "name": "Hobgoblin",
        "maxHp": 10,
        "statBlock": {
            "ac": 2,
            "attacks": [
                {"name": "Sword", "detail": "d8"},
                {"name": "Spear", "detail": "d6"},
            ],
            "notes": "STR 14, DEX 12, WIL 11",
        },
    },
    {
        "id": "cairn-kobold",
        "name": "Kobold",
        "maxHp": 4,
        "statBlock": {
            "ac": 1,
            "attacks": [{"name": "Spear", "detail": "d6"}],
            "notes": "STR 8, DEX 12, WIL 8\nFavorite traps and ambushes.",
        },
    },
    {
        "id": "cairn-ogre",
        "name": "Ogre",
        "maxHp": 10,
        "statBlock": {
            "ac": 1,
            "attacks": [{"name": "Makeshift Club", "detail": "d10"}],
            "notes": "STR 16, DEX 8, WIL 8",
        },
    },
    {
        "id": "cairn-rat-giant",
        "name": "Rat (Giant)",
        "maxHp": 4,
        "statBlock": {
            "ac": 0,
            "attacks": [{"name": "Bite", "detail": "d6"}],
            "notes": "STR 12, DEX 14, WIL 5\nGroup attack: Blast (d6) when 3+.",
        },
    },
    {
        "id": "cairn-root-witch",
        "name": "Root Witch",
        "maxHp": 8,
        "statBlock": {
            "ac": 0,
            "attacks": [{"name": "Gnarled Branch", "detail": "d8"}],
            "notes": "STR 12, DEX 12, WIL 15\nSpells: Upwell, Entangle, Befuddle.",
        },
    },
    {
        "id": "cairn-skeleton",
        "name": "Skeleton",
        "maxHp": 6,
        "statBlock": {
            "ac": 1,
            "attacks": [
                {"name": "Rusty Blade", "detail": "d6"},
                {"name": "Shortbow", "detail": "d6"},
            ],
            "notes": "STR 8, DEX 13, WIL 0\nImmune to morale effects; mindless.",
        },
    },
    {
        "id": "cairn-troll",
        "name": "Troll",
        "maxHp": 15,
        "statBlock": {
            "ac": 1,
            "attacks": [
                {"name": "Claws", "detail": "d8+d6"},
            ],
            "notes": "STR 18, DEX 12, WIL 7\nRegenerates 3 HP/round unless fire/acid.",
        },
    },
    {
        "id": "cairn-vampire",
        "name": "Vampire",
        "maxHp": 12,
        "statBlock": {
            "ac": 1,
            "attacks": [
                {"name": "Touch", "detail": "d8 + d6 STR drain"},
            ],
            "notes": "STR 14, DEX 10, WIL 16\nControls minds (WIL save). Weaknesses: sunlight, running water.",
        },
    },
    {
        "id": "cairn-werewolf",
        "name": "Werewolf",
        "maxHp": 9,
        "statBlock": {
            "ac": 1,
            "attacks": [
                {"name": "Claw", "detail": "d6"},
                {"name": "Bite", "detail": "d8"},
            ],
            "notes": "STR 15, DEX 14, WIL 10\nHurt only by silver or magical weapons.",
        },
    },
    {
        "id": "cairn-wolf",
        "name": "Wolf",
        "maxHp": 6,
        "statBlock": {
            "ac": 0,
            "attacks": [{"name": "Bite", "detail": "d8"}],
            "notes": "STR 12, DEX 14, WIL 8\nBlast (d6) when attacking in a pack.",
        },
    },
    {
        "id": "cairn-zombie",
        "name": "Zombie",
        "maxHp": 6,
        "statBlock": {
            "ac": 0,
            "attacks": [
                {"name": "Nails", "detail": "d6"},
                {"name": "Bite", "detail": "d6"},
            ],
            "notes": "STR 14, DEX 6, WIL 3\nMindless; never retreats.",
        },
    },
]


def verify(creatures):
    failures = []
    seen_ids = set()
    for c in creatures:
        if not c.get("id"):
            failures.append(f"missing id: {c.get('name')!r}")
        elif c["id"] in seen_ids:
            failures.append(f"duplicate id: {c['id']!r}")
        else:
            seen_ids.add(c["id"])
        if not c.get("name"):
            failures.append(f"missing name: {c.get('id')!r}")
        if not c.get("maxHp", 0) > 0:
            failures.append(f"invalid maxHp on {c.get('id')!r}")
        for atk in (c.get("statBlock") or {}).get("attacks", []):
            if not atk.get("name"):
                failures.append(f"unnamed attack on {c.get('id')!r}")
    return failures


def main():
    failures = verify(CREATURES)
    if failures:
        print("VERIFICATION FAILED:")
        for f in failures:
            print("  -", f)
        sys.exit(1)
    out = "assets/foes_cairn.json"
    with open(out, "w") as f:
        json.dump(CREATURES, f, ensure_ascii=False, indent=2)
    print(f"{out}: {len(CREATURES)} creatures. All verifications passed.")


if __name__ == "__main__":
    main()
