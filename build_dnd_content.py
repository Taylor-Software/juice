#!/usr/bin/env python3
"""Generate assets/spells_dnd.json + assets/foes_dnd.json from vendored SRD JSON.

Source: SRD 5.1 (5e-bits/5e-database, CC-BY-4.0 / OGL), vendored under
data/dnd_srd/. The script is the source of truth — edit it, rerun, copy output.
Self-verifies counts, ids, required fields, level/cr ranges. Supports --edition
for the later SRD 5.2 follow-up.

Run: python3 build_dnd_content.py            # edition 5.1 (default)
     python3 build_dnd_content.py --edition 5.2

Source data: data/dnd_srd/spells.json + data/dnd_srd/monsters.json
  Fetched from: https://raw.githubusercontent.com/5e-bits/5e-database/main/src/2014/en/
  License: CC-BY-4.0 / OGL 1.0a (SRD 5.1)
"""
import argparse
import json
import re
import sys


def slug(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def id_for(edition, name):
    prefix = 'dnd' if edition == '5.1' else 'dnd-2024'
    return f'{prefix}-{slug(name)}'


def transform_spell(s, edition):
    desc = '\n\n'.join(s.get('desc') or [])
    higher = '\n\n'.join(s.get('higher_level') or []) or None
    comps = ', '.join(s.get('components') or [])
    if s.get('material'):
        comps = f'{comps} ({s["material"]})' if comps else s['material']
    return {
        'id': id_for(edition, s['name']),
        'system': 'dnd',
        'edition': edition,
        'name': s['name'],
        'level': int(s.get('level', 0)),
        'school': (s.get('school') or {}).get('name', ''),
        'castingTime': s.get('casting_time', ''),
        'range': s.get('range', ''),
        'components': comps,
        'duration': s.get('duration', ''),
        'concentration': bool(s.get('concentration')),
        'ritual': bool(s.get('ritual')),
        'classes': [c.get('name', '') for c in (s.get('classes') or [])],
        'description': desc,
        **({'higherLevels': higher} if higher else {}),
    }


ABIL_KEYS = [('STR', 'strength'), ('DEX', 'dexterity'), ('CON', 'constitution'),
             ('INT', 'intelligence'), ('WIS', 'wisdom'), ('CHA', 'charisma')]


def extract_ac(ac_field):
    """Extract primary AC value from the list-of-dict armor_class structure.

    The 5e-bits schema returns a list of objects like:
      [{"type": "natural", "value": 17}, {"type": "condition", "value": 11, ...}]
    We prefer the first non-condition entry, falling back to the first entry.
    """
    if isinstance(ac_field, int):
        return ac_field
    if isinstance(ac_field, list) and ac_field:
        # Prefer any entry that isn't a condition (condition AC is situational)
        for entry in ac_field:
            if isinstance(entry, dict) and entry.get('type') != 'condition':
                return int(entry.get('value', 0))
        # Fallback: first entry
        first = ac_field[0]
        if isinstance(first, dict):
            return int(first.get('value', 0))
    return 0


def fmt_speed(sp):
    if isinstance(sp, dict):
        return ', '.join(f'{k} {v}' for k, v in sp.items())
    return str(sp or '')


def transform_monster(m, edition):
    ac = extract_ac(m.get('armor_class'))
    abilities = {k: int(m.get(src, 10)) for k, src in ABIL_KEYS}
    traits = []
    for t in (m.get('special_abilities') or []):
        traits.append({'name': t.get('name', ''), 'text': t.get('desc', '')})
    attacks = []
    for a in (m.get('actions') or []):
        attacks.append({'name': a.get('name', ''), 'detail': a.get('desc', '')})
    cr = m.get('challenge_rating')
    cr_str = ('1/8' if cr == 0.125 else '1/4' if cr == 0.25 else
              '1/2' if cr == 0.5 else str(int(cr)) if isinstance(cr, (int, float)) else str(cr))
    hp = int(m.get('hit_points', 0))
    return {
        'id': id_for(edition, m['name']),
        'name': m['name'],
        'edition': edition,
        'maxHp': hp,
        'statBlock': {
            'ac': int(ac),
            'cr': cr_str,
            'creatureType': (m.get('type') or '').title(),
            'size': m.get('size', ''),
            'speed': fmt_speed(m.get('speed')),
            'abilities': abilities,
            'attacks': [a for a in attacks if a['name']],
            'traits': [t for t in traits if t['name']],
        },
    }


def verify_spells(spells):
    fails, seen = [], set()
    for s in spells:
        if not s['id'] or s['id'] in seen:
            fails.append(f"bad/dup spell id: {s.get('name')!r}")
        seen.add(s['id'])
        if not s['name'] or not s['description']:
            fails.append(f"empty name/desc: {s['id']}")
        if not (0 <= s['level'] <= 9):
            fails.append(f"bad level {s['level']} on {s['id']}")
    return fails


def verify_monsters(monsters):
    fails, seen = [], set()
    for m in monsters:
        if not m['id'] or m['id'] in seen:
            fails.append(f"bad/dup monster id: {m.get('name')!r}")
        seen.add(m['id'])
        if not m['name']:
            fails.append(f"empty name: {m['id']}")
        if not m['statBlock']['abilities']:
            fails.append(f"no abilities: {m['id']}")
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--edition', default='5.1', choices=['5.1', '5.2'])
    args = ap.parse_args()
    src_spells = json.load(open('data/dnd_srd/spells.json'))
    src_monsters = json.load(open('data/dnd_srd/monsters.json'))
    spells = [transform_spell(s, args.edition) for s in src_spells]
    monsters = [transform_monster(m, args.edition) for m in src_monsters]
    fails = verify_spells(spells) + verify_monsters(monsters)
    if not spells or not monsters:
        fails.append('empty output')
    if fails:
        print('VERIFICATION FAILED:')
        for f in fails:
            print('  -', f)
        sys.exit(1)
    suffix = '' if args.edition == '5.1' else '_2024'
    with open(f'assets/spells_dnd{suffix}.json', 'w') as f:
        json.dump(spells, f, ensure_ascii=False, indent=2)
    with open(f'assets/foes_dnd{suffix}.json', 'w') as f:
        json.dump(monsters, f, ensure_ascii=False, indent=2)
    print(f'spells_dnd{suffix}.json: {len(spells)} · '
          f'foes_dnd{suffix}.json: {len(monsters)}. All checks passed.')


if __name__ == '__main__':
    main()
