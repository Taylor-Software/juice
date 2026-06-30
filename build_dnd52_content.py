#!/usr/bin/env python3
"""Parse vendored SRD 5.2 markdown into 5.2-tagged spell/monster JSON and MERGE
it into the existing assets/spells_dnd.json + assets/foes_dnd.json.

Source: SRD 5.2.1 (CC-BY-4.0), vendored under data/dnd_srd_52/ (from
github.com/springbov/dndsrd5.2_markdown, itself CC-BY-4.0). The script is the
source of truth — edit it, rerun, never hand-edit the JSON. data/ is source-only,
not bundled.

The 5.1 entries (id prefix `dnd-`) pass through untouched; this only adds 5.2
entries (id prefix `dnd-2024-`, edition "5.2"). Idempotent: each run drops any
existing edition=="5.2" entries from the asset, then re-appends the freshly
parsed 5.2 set.

Run order:
    python3 build_dnd_content.py        # writes the 5.1 baseline
    python3 build_dnd52_content.py      # merges the 5.2 set in

Self-verifies counts per edition, unique ids, required fields, level/cr ranges.
"""
import json
import re
import sys

SPELLS_MD = 'data/dnd_srd_52/07_Spells.md'
MONSTERS_MD = ['data/dnd_srd_52/12_MonstersA-Z.md',
               'data/dnd_srd_52/13_Animals.md']
SPELLS_ASSET = 'assets/spells_dnd.json'
FOES_ASSET = 'assets/foes_dnd.json'
EDITION = '5.2'

SCHOOLS = {'Abjuration', 'Conjuration', 'Divination', 'Enchantment',
           'Evocation', 'Illusion', 'Necromancy', 'Transmutation'}


def slug(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def id_for(name):
    return f'dnd-2024-{slug(name)}'


def clean_name(raw):
    """Strip surrounding ** / * and whitespace from a header name."""
    return raw.strip().strip('*').strip()


def strip_md(text):
    """Remove markdown emphasis markers (*** ** *) from body text — the app
    renders descriptions/details as plain Text, so SRD inline labels like
    *Melee Attack Roll:* must not show literal asterisks. Collapses the doubled
    spaces the SRD leaves after *Failure:*  labels."""
    if not text:
        return text
    # Flattened wikilink artifacts. Bracketed form `[Area of Effect]|XPHB|Sphere`
    # → keep the canonical `Sphere`. Bare form `Cover|XPHB|Total Cover` has an
    # unrecoverable multi-word alias, so just drop the `|SRC|` link token (leaves
    # both sides — slightly redundant but complete + readable).
    text = re.sub(r'\[[^\]]*\]\|[A-Za-z]+\|', '', text)
    text = re.sub(r'\s*\|[A-Z]{2,}\|\s*', ' ', text)
    text = re.sub(r'\*{1,3}([^*]+?)\*{1,3}', r'\1', text)
    text = text.replace('*', '')  # any stray unmatched marker
    text = re.sub(r'[ \t]{2,}', ' ', text)
    return text.strip()


# --------------------------------------------------------------------------- #
# Spells
# --------------------------------------------------------------------------- #
ITALIC_RE = re.compile(r'^\*(.+)\*\s*$')
FIELD_RE = re.compile(r'^\*\*([A-Za-z ]+):\*\*\s*(.*)$')
# Every spell header field on a line, matched anywhere (tolerates a leading
# typo like `kj**Duration:**`) and split when several are glued onto one line
# (e.g. Forcecage). Restricted to the 4 known labels so description bold isn't
# mistaken for a field.
FIELD_SPLIT_RE = re.compile(
    r'\*\*(Casting Time|Range|Components?|Duration):\*\*', re.I)


def extract_fields_from_line(raw):
    """[(label_lower, value), …] for every known **Label:** on the line, or None.
    Splits each value as the text up to the next label. Normalizes the singular
    `Component` to `components`."""
    marks = list(FIELD_SPLIT_RE.finditer(raw))
    if not marks:
        return None
    out = []
    for idx, m in enumerate(marks):
        start = m.end()
        end = marks[idx + 1].start() if idx + 1 < len(marks) else len(raw)
        label = m.group(1).strip().lower()
        if label == 'component':
            label = 'components'
        out.append((label, raw[start:end].strip()))
    return out

# A canonical Duration value; some source lines glue the description right after
# it (e.g. "Concentration, up to 10 minutes You touch ...") — split it back out.
DURATION_RE = re.compile(
    r'^(Instantaneous'
    r'|Special'
    r'|Permanent'
    r'|Until dispelled(?: or triggered)?'
    r'|Concentration, up to \d+ \w+'
    r'|\d+ \w+(?:, \w+)?'
    r')\b')


def split_duration(value):
    """Return (duration, trailing_prose). The prose is '' when the value is a
    clean canonical duration."""
    m = DURATION_RE.match(value)
    if not m:
        return value, ''
    return m.group(1).strip(), value[m.end():].strip()


def parse_level_school_classes(line):
    """*Level N School (Class, Class)* OR *School Cantrip (Classes)*."""
    inner = line.strip().strip('*').strip()
    classes = []
    m = re.search(r'\(([^)]*)\)\s*$', inner)
    if m:
        classes = [c.strip() for c in m.group(1).split(',') if c.strip()]
        inner = inner[:m.start()].strip()
    cantrip = re.match(r'^([A-Za-z]+)\s+Cantrip$', inner)
    if cantrip:
        return 0, cantrip.group(1), classes
    lev = re.match(r'^Level\s+(\d+)\s+([A-Za-z]+)$', inner)
    if lev:
        return int(lev.group(1)), lev.group(2), classes
    return None


def split_spell_blocks(text):
    """Yield (name, body_lines) for each #### header after Spell Descriptions,
    skipping the ### X Spells section dividers."""
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines)
                     if l.strip() == '## Spell Descriptions')
    except StopIteration:
        raise SystemExit('could not find "## Spell Descriptions"')
    cur_name = None
    cur = []
    for l in lines[start + 1:]:
        if l.startswith('#### '):
            if cur_name is not None:
                yield cur_name, cur
            cur_name = clean_name(l[5:])
            cur = []
        elif cur_name is not None:
            # next H1/H2/H3 closes the current spell (section dividers etc.)
            if l.startswith('## ') or l.startswith('# ') or l.startswith('### '):
                yield cur_name, cur
                cur_name = None
                cur = []
            else:
                cur.append(l)
    if cur_name is not None:
        yield cur_name, cur


def parse_spell(name, body):
    fields = {}
    level = school = None
    classes = []
    desc_parts = []
    higher = None
    i = 0
    # find the italic level/school/classes line first
    for idx, raw in enumerate(body):
        if ITALIC_RE.match(raw):
            parsed = parse_level_school_classes(raw)
            if parsed and (parsed[1] in SCHOOLS):
                level, school, classes = parsed
                i = idx + 1
                break
    if level is None:
        return None  # not a spell (no level/school italic line)
    n = len(body)
    while i < n:
        raw = body[i]
        flds = extract_fields_from_line(raw)
        if flds:
            for k, v in flds:
                fields[k] = v
            i += 1
            continue
        stripped = raw.strip()
        # The canonical `**_Using a Higher-Level Spell Slot._**` /
        # `**_Cantrip Upgrade._**`, plus the source's occasional typo variants:
        # no underscore (`**Using ..._**`) and single-asterisk italic
        # (`*Using a Higher-Level Spell Slot.*`).
        hl = re.match(
            r'^\*{1,2}_?(?:Using a Higher-Level Spell Slot|Cantrip Upgrade)'
            r'\._?\*{1,2}\s*',
            stripped)
        if hl:
            higher = stripped[hl.end():].strip()
            i += 1
            continue
        if stripped:
            desc_parts.append(stripped)
        i += 1

    casting = fields.get('casting time', '')
    duration, dur_prose = split_duration(fields.get('duration', ''))
    if dur_prose:
        desc_parts.insert(0, dur_prose)
    description = '\n\n'.join(desc_parts).strip()
    out = {
        'id': id_for(name),
        'system': 'dnd',
        'edition': EDITION,
        'name': name,
        'level': level,
        'school': school,
        'castingTime': casting,
        'range': fields.get('range', ''),
        'components': fields.get('components', ''),
        'duration': duration,
        'concentration': 'Concentration' in duration,
        'ritual': 'Ritual' in casting,
        'classes': classes,
        'description': strip_md(description),
    }
    if higher:
        out['higherLevels'] = strip_md(higher)
    return out


def parse_spells():
    text = open(SPELLS_MD, encoding='utf-8').read()
    out = []
    for name, body in split_spell_blocks(text):
        spell = parse_spell(name, body)
        if spell:
            out.append(spell)
    return out


# --------------------------------------------------------------------------- #
# Monsters
# --------------------------------------------------------------------------- #
ABIL_ORDER = ['STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA']
ABIL_ROW_RE = re.compile(r'^\|\s*(STR|DEX|CON|INT|WIS|CHA)\s*\|\s*(-?\d+)\s*\|')
TRAIT_RE = re.compile(r'^\*\*\*(.+?)\.?\*\*\*\s*(.*)$')


def split_monster_blocks(text):
    lines = text.splitlines()
    cur_name = None
    cur = []
    for l in lines:
        if l.startswith('## '):
            if cur_name is not None:
                yield cur_name, cur
            cur_name = clean_name(l[3:])
            cur = []
        elif l.startswith('# '):
            # H1 title — closes any open block, not a monster itself
            if cur_name is not None:
                yield cur_name, cur
            cur_name = None
            cur = []
        elif cur_name is not None:
            cur.append(l)
    if cur_name is not None:
        yield cur_name, cur


def parse_size_type(line):
    inner = line.strip().strip('*').strip()
    # "Size Type(tags), Alignment"
    head = inner.split(',', 1)[0].strip()
    parts = head.split(None, 1)
    size = parts[0] if parts else ''
    ctype = parts[1].strip() if len(parts) > 1 else ''
    return size, ctype


def parse_cr(line):
    m = re.search(r'\*\*CR\*\*[:\s]*([0-9]+/[0-9]+|[0-9]+)', line)
    if m:
        return m.group(1)
    return None


def collect_sections(body, start_idx):
    """From start_idx (a '### Section' line), gather '***Name.*** text' items,
    folding continuation lines into the current item. Returns (items, end_idx)."""
    items = []
    i = start_idx + 1
    n = len(body)
    cur = None
    while i < n:
        l = body[i]
        if l.startswith('### ') or l.startswith('## ') or l.startswith('# '):
            break
        m = TRAIT_RE.match(l.strip())
        if m:
            if cur:
                items.append(cur)
            cur = {'name': m.group(1).strip().rstrip('.'),
                   'text': m.group(2).strip()}
        elif cur is not None and l.strip():
            cur['text'] = (cur['text'] + '\n' + l.strip()).strip()
        i += 1
    if cur:
        items.append(cur)
    for it in items:
        it['name'] = strip_md(it['name'])
        it['text'] = strip_md(it['text'])
    return items, i


def parse_monster(name, body):
    ac = None
    maxhp = None
    speed = ''
    size = ctype = ''
    cr = None
    abilities = {}
    traits = []
    attacks = []

    i = 0
    n = len(body)
    while i < n:
        l = body[i]
        s = l.strip()
        if not size and ITALIC_RE.match(l):
            size, ctype = parse_size_type(l)
        elif s.startswith('- **Armor Class:**'):
            m = re.search(r'(\d+)', s)
            if m:
                ac = int(m.group(1))
        elif s.startswith('- **Hit Points:**'):
            m = re.search(r'(\d+)', s)
            if m:
                maxhp = int(m.group(1))
        elif s.startswith('- **Speed:**'):
            speed = s.split('**Speed:**', 1)[1].strip()
        elif '**CR**' in s:
            c = parse_cr(s)
            if c:
                cr = c
        else:
            am = ABIL_ROW_RE.match(l)
            if am:
                abilities[am.group(1)] = int(am.group(2))
            elif l.startswith('### '):
                section = l[4:].strip()
                items, end = collect_sections(body, i)
                if section == 'Traits':
                    traits.extend(items)
                else:
                    prefix = '' if section == 'Actions' else f'{section[:-1] if section.endswith("s") else section}: '
                    for it in items:
                        attacks.append({'name': f'{prefix}{it["name"]}',
                                        'detail': it['text']})
                i = end
                continue
        i += 1

    stat = {
        'ac': ac if ac is not None else 0,
        'creatureType': ctype,
        'size': size,
        'speed': speed,
        'abilities': {k: abilities.get(k, 10) for k in ABIL_ORDER},
        'attacks': [a for a in attacks if a['name']],
        'traits': [t for t in traits if t['name']],
    }
    if cr is not None:
        stat['cr'] = cr
    return {
        'id': id_for(name),
        'name': name,
        'edition': EDITION,
        'maxHp': maxhp if maxhp is not None else 0,
        'statBlock': stat,
    }


def parse_monsters():
    out = []
    for path in MONSTERS_MD:
        text = open(path, encoding='utf-8').read()
        for name, body in split_monster_blocks(text):
            out.append(parse_monster(name, body))
    return out


# --------------------------------------------------------------------------- #
# Merge + verify
# --------------------------------------------------------------------------- #
def merge(asset_path, new_entries):
    existing = json.load(open(asset_path, encoding='utf-8'))
    kept = [e for e in existing if e.get('edition') != EDITION]
    return kept + new_entries


def verify_spells(spells, floor):
    fails, seen = [], set()
    counts = {}
    for s in spells:
        ed = s.get('edition')
        counts[ed] = counts.get(ed, 0) + 1
        sid = s.get('id', '')
        if not sid or sid in seen:
            fails.append(f'bad/dup spell id: {s.get("name")!r}')
        seen.add(sid)
        if ed == EDITION and not sid.startswith('dnd-2024-'):
            fails.append(f'5.2 spell id not prefixed: {sid}')
        if not s.get('name') or not s.get('description'):
            fails.append(f'empty name/desc: {sid}')
        if not (0 <= s.get('level', -1) <= 9):
            fails.append(f'bad level {s.get("level")} on {sid}')
    if counts.get('5.1', 0) != 319:
        fails.append(f'expected 319 5.1 spells, got {counts.get("5.1")}')
    if counts.get('5.2', 0) < floor:
        fails.append(f'expected >= {floor} 5.2 spells, got {counts.get("5.2")}')
    return fails, counts


def verify_monsters(monsters, floor):
    fails, seen = [], set()
    counts = {}
    for m in monsters:
        ed = m.get('edition')
        counts[ed] = counts.get(ed, 0) + 1
        mid = m.get('id', '')
        if not mid or mid in seen:
            fails.append(f'bad/dup monster id: {m.get("name")!r}')
        seen.add(mid)
        if ed == EDITION and not mid.startswith('dnd-2024-'):
            fails.append(f'5.2 monster id not prefixed: {mid}')
        if not m.get('name'):
            fails.append(f'empty name: {mid}')
        if (m.get('maxHp') or 0) <= 0:
            fails.append(f'maxHp <= 0: {mid}')
        ab = (m.get('statBlock') or {}).get('abilities') or {}
        if sorted(ab) != sorted(ABIL_ORDER):
            fails.append(f'bad ability keys: {mid}')
    if counts.get('5.1', 0) != 334:
        fails.append(f'expected 334 5.1 monsters, got {counts.get("5.1")}')
    if counts.get('5.2', 0) < floor:
        fails.append(f'expected >= {floor} 5.2 monsters, got {counts.get("5.2")}')
    return fails, counts


def main():
    new_spells = parse_spells()
    new_monsters = parse_monsters()
    if not new_spells or not new_monsters:
        raise SystemExit('parsed nothing — check source paths')

    # sane floors a bit below the actual parse
    spell_floor = max(250, len(new_spells) - 20)
    foe_floor = max(180, len(new_monsters) - 20)

    spells = merge(SPELLS_ASSET, new_spells)
    monsters = merge(FOES_ASSET, new_monsters)

    fs, sc = verify_spells(spells, spell_floor)
    fm, mc = verify_monsters(monsters, foe_floor)
    fails = fs + fm
    if fails:
        print('VERIFICATION FAILED:')
        for f in fails:
            print('  -', f)
        sys.exit(1)

    with open(SPELLS_ASSET, 'w', encoding='utf-8') as f:
        json.dump(spells, f, ensure_ascii=False, indent=2)
    with open(FOES_ASSET, 'w', encoding='utf-8') as f:
        json.dump(monsters, f, ensure_ascii=False, indent=2)

    print('Merged SRD 5.2 into assets. All checks passed.')
    print(f'  spells_dnd.json: {len(spells)} total  '
          f'(5.1={sc.get("5.1")}, 5.2={sc.get("5.2")})')
    print(f'  foes_dnd.json:   {len(monsters)} total  '
          f'(5.1={mc.get("5.1")}, 5.2={mc.get("5.2")})')


if __name__ == '__main__':
    main()
