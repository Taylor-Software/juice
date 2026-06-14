# Lonelog Foundation (P1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Lonelog an opt-in, per-campaign system in juice — a settings gate, the notation legend as a self-verified data asset, a minimal highlighting parser, and a gated read-only reference tool that renders the legend with live-highlighted examples.

**Architecture:** Follows the existing verdant rail end-to-end: `build_lonelog.py` (hand-transcribed, self-verifying) emits `assets/lonelog_data.json`; `LonelogData` loads it; `lonelogDataProvider` caches it; a read-only `LonelogReferenceScreen` (gated by a new `lonelog` system flag) renders it, using a pure `lonelog_highlight.dart` classifier to syntax-color worked examples. Gating reuses the per-session `enabledSystems` mechanism. **`lonelog` is deliberately NOT added to `kAllSystems`** — so it is off for legacy/default campaigns and only appears when explicitly enabled, which also avoids eager-building the screen in existing shell tests.

**Tech Stack:** Python 3 (build script), Dart/Flutter, flutter_riverpod, shared_preferences, package:flutter_test.

**Scope guard (NOT in P1):** no bidirectional `.md` import/export (P2), no journal notation rendering/composing (P3), no addon behavior (P4). Addon *notation* is documented in the legend; addon *features* are later. No global settings screen.

---

## File structure

**New files**
- `build_lonelog.py` — source of truth for the legend; self-verifies, emits `lonelog_data.json`.
- `assets/lonelog_data.json` — generated; never hand-edited.
- `lib/engine/lonelog_data.dart` — `LonelogData` typed wrapper + `load()`.
- `lib/engine/lonelog_highlight.dart` — pure line→spans classifier (the "proven parser").
- `lib/features/lonelog_reference_screen.dart` — read-only gated reference tool.
- `test/lonelog_data_test.dart`, `test/lonelog_highlight_test.dart`, `test/lonelog_reference_test.dart`.

**Modified files**
- `pubspec.yaml` — register the asset.
- `lib/state/providers.dart` — `lonelogDataProvider`; `SessionsNotifier.editSystems`.
- `lib/shared/tool_registry.dart` — `lonelog-ref` ToolDef + `toolSystem` entry.
- `lib/shared/destination.dart` — route `lonelog-ref`.
- `lib/features/oracles_tab.dart` — `systems` param + gated `Lonelog` subtab.
- `lib/shared/home_shell.dart` — pass `systems` to `OraclesTab`; New Campaign checkbox; edit-systems action.
- `test/tool_registry_test.dart` — add `lonelog` to `validSystems`; add gating test.
- `CLAUDE.md` — document the `build_lonelog.py` rail.

---

### Task 1: Data asset — `build_lonelog.py` → `assets/lonelog_data.json`

**Files:**
- Create: `build_lonelog.py`
- Create (generated): `assets/lonelog_data.json`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Write `build_lonelog.py`**

```python
#!/usr/bin/env python3
"""Lonelog notation legend — source of truth for the Lonelog reference tool.

Like build_verdant.py: hand-transcribed literals here are authoritative; this
script (a) self-verifies structure (unique reserved prefixes, the 5 core
symbols, balanced block tags, well-formed examples), (b) cross-checks a few
literals against pdftotext extracts of the Lonelog PDFs when present, and
(c) emits lonelog_data.json. NEVER hand-edit the emitted JSON — edit this
script and rerun, then copy lonelog_data.json into assets/.

Source: Lonelog (en v1.5.0) core rulebook + 7 addons by Roberto Bisceglie,
CC BY-SA 4.0. The notation grammar is documented; addon *behavior* is not part
of this asset.
"""
import json
import os

OUT = "lonelog_data.json"
EXTRACT_DIR = "/tmp"  # optional pdftotext extracts: lonelog_core.txt etc.

VERSION = "1.5.0"

# The 5 core symbols (+ the @(Name) actor-attribution variant). Immutable.
SYMBOLS = [
    {"symbol": "@", "name": "Action", "role": "Player-character action",
     "example": "@ Pick the lock"},
    {"symbol": "@(Name)", "name": "Attributed action",
     "role": "Action by a named PC, companion, or NPC",
     "example": "@(Jonah) Keeps watch"},
    {"symbol": "?", "name": "Oracle question", "role": "Ask the oracle",
     "example": "? Is the guard asleep"},
    {"symbol": "d:", "name": "Mechanics roll", "role": "Dice / rule resolution",
     "example": "d: d20+5=17 vs DC 15"},
    {"symbol": "->", "name": "Result", "role": "Dice or oracle result",
     "example": "-> Yes, but..."},
    {"symbol": "=>", "name": "Consequence", "role": "Narrative outcome",
     "example": "=> The door creaks open"},
]

# Comparison operators / flags used inside d: lines.
COMPARATORS = [
    {"op": ">=", "meaning": "Meets or beats the target number (also written >=)"},
    {"op": "<=", "meaning": "Fails the target number (also written <=)"},
    {"op": "vs", "meaning": "Explicit 'versus' a TN/DC"},
    {"op": "S", "meaning": "Success flag"},
    {"op": "F", "meaning": "Fail flag"},
]

# Reserved tag prefixes (the conformance contract). source: which book owns it.
TAG_PREFIXES = [
    {"prefix": "N", "name": "NPC", "meaning": "A persistent named NPC", "source": "core"},
    {"prefix": "L", "name": "Location", "meaning": "A place", "source": "core"},
    {"prefix": "E", "name": "Event", "meaning": "An event / inline clock", "source": "core"},
    {"prefix": "PC", "name": "Player character", "meaning": "A PC stat block", "source": "core"},
    {"prefix": "Thread", "name": "Thread", "meaning": "A story thread / vow", "source": "core"},
    {"prefix": "Clock", "name": "Clock", "meaning": "Fills up toward a bad outcome", "source": "core"},
    {"prefix": "Track", "name": "Track", "meaning": "Fills up toward a goal", "source": "core"},
    {"prefix": "Timer", "name": "Timer", "meaning": "Counts down to zero", "source": "core"},
    {"prefix": "#", "name": "Reference", "meaning": "Refer to an established element", "source": "core"},
    {"prefix": "Inv", "name": "Inventory", "meaning": "A concrete item", "source": "resource"},
    {"prefix": "Wealth", "name": "Wealth", "meaning": "Currency totals", "source": "resource"},
    {"prefix": "R", "name": "Room", "meaning": "A dungeon room + status", "source": "dungeon"},
    {"prefix": "F", "name": "Foe", "meaning": "A combat foe stat tag", "source": "combat"},
]

# Structural blocks: digital [NAME]/[/NAME]; analog --- NAME --- / --- END NAME ---.
BLOCKS = [
    {"name": "COMBAT", "openTag": "[COMBAT]", "closeTag": "[/COMBAT]",
     "analogOpen": "--- COMBAT ---", "analogClose": "--- END COMBAT ---",
     "purpose": "A tactical combat section (Combat addon)"},
    {"name": "DUNGEON STATUS", "openTag": "[DUNGEON STATUS]", "closeTag": "[/DUNGEON STATUS]",
     "analogOpen": "--- DUNGEON STATUS ---", "analogClose": "--- END STATUS ---",
     "purpose": "A snapshot of room states (Dungeon Crawling addon)"},
    {"name": "RESOURCES", "openTag": "[RESOURCES]", "closeTag": "[/RESOURCES]",
     "analogOpen": "--- RESOURCES ---", "analogClose": "--- END RESOURCES ---",
     "purpose": "A resource snapshot at a session boundary (Resource Tracking addon)"},
    {"name": "BATTLE", "openTag": "[BATTLE]", "closeTag": "[/BATTLE]",
     "analogOpen": "--- BATTLE ---", "analogClose": "--- END BATTLE ---",
     "purpose": "One wargame engagement (Wargaming addon)"},
    {"name": "CAMPAIGN", "openTag": "[CAMPAIGN]", "closeTag": "[/CAMPAIGN]",
     "analogOpen": "--- CAMPAIGN ---", "analogClose": "--- END CAMPAIGN ---",
     "purpose": "A campaign-state snapshot (Wargaming addon)"},
]

# The 7 addons. status: 'documented' now; flips to 'implemented' per later phase.
ADDONS = [
    {"key": "combat", "title": "Combat", "version": "1.1.0",
     "summary": "Round markers (Rd#), foe tags [F:], positions, [COMBAT] blocks.",
     "addsTags": ["F"], "addsBlocks": ["COMBAT"], "status": "documented"},
    {"key": "dungeon", "title": "Dungeon Crawling", "version": "1.1.0",
     "summary": "Per-room status tags [R:ID|status|exits] and dungeon snapshots.",
     "addsTags": ["R"], "addsBlocks": ["DUNGEON STATUS"], "status": "documented"},
    {"key": "resource", "title": "Resource Tracking", "version": "1.1.0",
     "summary": "Inventory [Inv:], wealth [Wealth:], usage dice, resource snapshots.",
     "addsTags": ["Inv", "Wealth"], "addsBlocks": ["RESOURCES"], "status": "documented"},
    {"key": "dice", "title": "Dice Notation", "version": "1.0.0",
     "summary": "A full dice-expression grammar (keep/drop, explode, success pools).",
     "addsTags": [], "addsBlocks": [], "status": "documented"},
    {"key": "cards", "title": "Cards", "version": "1.0.0",
     "summary": "Compact tokens for playing-card and tarot draws (Qs, M16r).",
     "addsTags": [], "addsBlocks": [], "status": "documented"},
    {"key": "wargaming", "title": "Wargaming", "version": "1.0.0",
     "summary": "Unit tags [Unit:], turn markers (Tn#), [BATTLE]/[CAMPAIGN] blocks.",
     "addsTags": ["Unit", "Force", "Scenario"], "addsBlocks": ["BATTLE", "CAMPAIGN"],
     "status": "documented"},
    {"key": "guidelines", "title": "Addon Guidelines", "version": "1.1.0",
     "summary": "The authoring contract: shared symbols + reserved prefixes + block syntax.",
     "addsTags": [], "addsBlocks": [], "status": "documented"},
]

# Campaign YAML front-matter schema (documents what P2 will read/write).
HEADER_FIELDS = [
    {"field": "title", "meaning": "Campaign title"},
    {"field": "ruleset", "meaning": "The host RPG system"},
    {"field": "genre", "meaning": "Genre / setting"},
    {"field": "player", "meaning": "Player name"},
    {"field": "pcs", "meaning": "Player characters"},
    {"field": "start_date", "meaning": "When the campaign began"},
    {"field": "last_update", "meaning": "Last session date"},
    {"field": "tools", "meaning": "Oracles / generators in use"},
    {"field": "themes", "meaning": "Campaign themes"},
    {"field": "tone", "meaning": "Tone"},
    {"field": "notes", "meaning": "Freeform notes"},
]

# Worked examples — one symbol per line so the highlighter reads cleanly.
EXAMPLES = [
    {"title": "A complete beat", "lines": [
        "@ Pick the warehouse lock",
        "d: d20+5=17 vs DC 15",
        "-> Success",
        "=> The door swings open [E:AlertClock 1/6]",
    ]},
    {"title": "Asking the oracle", "lines": [
        "? Is the guard asleep",
        "-> No, but... distracted",
        "=> I slip past while he yawns",
    ]},
    {"title": "Tracking elements", "lines": [
        "=> [N:Jonah|captured|wounded]",
        "=> [Thread:Rescue Jonah|Open]",
        "=> [Clock:Suspicion 3/6]",
    ]},
    {"title": "A combat round", "lines": [
        "[COMBAT]",
        "@(Goblins) Swarm the doorway",
        "d: 2d6=8",
        "=> [F:Goblins x3|Close]",
        "[/COMBAT]",
    ]},
    {"title": "A meta aside", "lines": [
        "(note: trying a flashback scene here)",
    ]},
]


def build():
    return {
        "version": VERSION,
        "license": "CC BY-SA 4.0",
        "attribution": "Lonelog (c) Roberto Bisceglie",
        "symbols": SYMBOLS,
        "comparators": COMPARATORS,
        "tagPrefixes": TAG_PREFIXES,
        "blocks": BLOCKS,
        "addons": ADDONS,
        "headerFields": HEADER_FIELDS,
        "examples": EXAMPLES,
    }


def verify(data):
    # The 5 immutable core symbols are present.
    syms = {s["symbol"] for s in data["symbols"]}
    for core in ["@", "?", "d:", "->", "=>"]:
        assert core in syms, f"missing core symbol {core}"

    # Reserved prefixes are unique (the Guidelines collision rule).
    prefixes = [p["prefix"] for p in data["tagPrefixes"]]
    assert len(prefixes) == len(set(prefixes)), "duplicate reserved prefix"
    for p in data["tagPrefixes"]:
        assert p["source"] in {"core", "combat", "dungeon", "resource"}, \
            f"bad source {p['source']}"

    # Block tags are balanced and bracket-wrapped.
    for b in data["blocks"]:
        assert b["openTag"] == f"[{b['name']}]", f"bad open {b['openTag']}"
        assert b["closeTag"] == f"[/{b['name']}]", f"bad close {b['closeTag']}"

    # Addons reference only declared blocks; status is known.
    block_names = {b["name"] for b in data["blocks"]}
    for a in data["addons"]:
        assert a["status"] in {"documented", "implemented"}, f"bad status {a['status']}"
        for bn in a["addsBlocks"]:
            assert bn in block_names, f"addon {a['key']} unknown block {bn}"

    # Examples are well-formed: non-empty titles and non-empty lines.
    assert len(data["examples"]) >= 4, "expected several worked examples"
    for ex in data["examples"]:
        assert ex["title"], "example missing title"
        assert ex["lines"], f"example {ex['title']} has no lines"
        for ln in ex["lines"]:
            assert isinstance(ln, str) and ln.strip(), "blank example line"


def cross_check():
    """Best-effort: confirm a few literals appear in pdftotext extracts."""
    path = os.path.join(EXTRACT_DIR, "lonelog_core.txt")
    if not os.path.exists(path):
        print(f"note: {path} missing; skipping PDF cross-check.")
        return
    with open(path, encoding="utf-8") as f:
        text = f.read()
    for needle in ["@", "Thread", "Clock"]:
        assert needle in text, f"expected '{needle}' in {path}"
    print("PDF cross-check passed.")


if __name__ == "__main__":
    data = build()
    verify(data)
    cross_check()
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"wrote {OUT}: {len(data['symbols'])} symbols, "
          f"{len(data['tagPrefixes'])} prefixes, {len(data['addons'])} addons, "
          f"{len(data['examples'])} examples")
```

- [ ] **Step 2: Run the build script and verify self-check passes**

Run: `python3 build_lonelog.py && cp lonelog_data.json assets/lonelog_data.json`
Expected: prints `wrote lonelog_data.json: 6 symbols, 13 prefixes, 7 addons, 5 examples` with no assertion error; `assets/lonelog_data.json` exists.

- [ ] **Step 3: Register the asset in `pubspec.yaml`**

Add this line in the `assets:` list, right after `- assets/verdant_data.json` (line 29):

```yaml
    - assets/lonelog_data.json
```

- [ ] **Step 4: Commit**

```bash
git add build_lonelog.py lonelog_data.json assets/lonelog_data.json pubspec.yaml
git commit -m "feat(lonelog): notation legend data asset (build_lonelog.py)"
```

---

### Task 2: `LonelogData` model + loader + provider

**Files:**
- Create: `lib/engine/lonelog_data.dart`
- Create: `test/lonelog_data_test.dart`
- Modify: `lib/state/providers.dart` (add provider after `verdantDataProvider`, ~line 851-852)

- [ ] **Step 1: Write the failing test**

`test/lonelog_data_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_data.dart';

void main() {
  final data = LonelogData(
      jsonDecode(File('assets/lonelog_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('legend loads with the expected shapes', () {
    expect(data.version, '1.5.0');
    expect(data.symbols.map((s) => s.symbol), containsAll(['@', '?', 'd:', '->', '=>']));
    expect(data.tagPrefixes.length, 13);
    expect(data.blocks.length, 5);
    expect(data.addons.length, 7);
    expect(data.examples.length, greaterThanOrEqualTo(4));
  });

  test('reserved prefixes are unique', () {
    final ps = data.tagPrefixes.map((p) => p.prefix).toList();
    expect(ps.toSet().length, ps.length);
  });

  test('every example has a title and non-empty lines', () {
    for (final ex in data.examples) {
      expect(ex.title, isNotEmpty);
      expect(ex.lines, isNotEmpty);
    }
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/lonelog_data_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:juice_oracle/engine/lonelog_data.dart'`.

- [ ] **Step 3: Write `lib/engine/lonelog_data.dart`**

```dart
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One core symbol entry.
class LonelogSymbol {
  const LonelogSymbol(
      {required this.symbol, required this.name, required this.role, required this.example});
  final String symbol;
  final String name;
  final String role;
  final String example;

  static LonelogSymbol fromJson(Map<String, dynamic> j) => LonelogSymbol(
        symbol: j['symbol'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        example: j['example'] as String,
      );
}

/// One reserved tag prefix.
class LonelogPrefix {
  const LonelogPrefix(
      {required this.prefix, required this.name, required this.meaning, required this.source});
  final String prefix;
  final String name;
  final String meaning;
  final String source; // core | combat | dungeon | resource

  static LonelogPrefix fromJson(Map<String, dynamic> j) => LonelogPrefix(
        prefix: j['prefix'] as String,
        name: j['name'] as String,
        meaning: j['meaning'] as String,
        source: j['source'] as String,
      );
}

/// One structural block.
class LonelogBlock {
  const LonelogBlock(
      {required this.name,
      required this.openTag,
      required this.closeTag,
      required this.purpose});
  final String name;
  final String openTag;
  final String closeTag;
  final String purpose;

  static LonelogBlock fromJson(Map<String, dynamic> j) => LonelogBlock(
        name: j['name'] as String,
        openTag: j['openTag'] as String,
        closeTag: j['closeTag'] as String,
        purpose: j['purpose'] as String,
      );
}

/// One addon descriptor.
class LonelogAddon {
  const LonelogAddon(
      {required this.key,
      required this.title,
      required this.version,
      required this.summary,
      required this.status});
  final String key;
  final String title;
  final String version;
  final String summary;
  final String status; // documented | implemented

  static LonelogAddon fromJson(Map<String, dynamic> j) => LonelogAddon(
        key: j['key'] as String,
        title: j['title'] as String,
        version: j['version'] as String,
        summary: j['summary'] as String,
        status: j['status'] as String,
      );
}

/// One worked example (rendered live-highlighted).
class LonelogExample {
  const LonelogExample({required this.title, required this.lines});
  final String title;
  final List<String> lines;

  static LonelogExample fromJson(Map<String, dynamic> j) => LonelogExample(
        title: j['title'] as String,
        lines: (j['lines'] as List).cast<String>(),
      );
}

/// Typed wrapper over assets/lonelog_data.json (mirrors VerdantData).
class LonelogData {
  LonelogData(this._json);
  final Map<String, dynamic> _json;

  static Future<LonelogData> load() async {
    final raw = await rootBundle.loadString('assets/lonelog_data.json');
    return LonelogData(jsonDecode(raw) as Map<String, dynamic>);
  }

  String get version => _json['version'] as String;

  List<LonelogSymbol> get symbols => (_json['symbols'] as List)
      .map((e) => LonelogSymbol.fromJson(e as Map<String, dynamic>))
      .toList();

  List<LonelogPrefix> get tagPrefixes => (_json['tagPrefixes'] as List)
      .map((e) => LonelogPrefix.fromJson(e as Map<String, dynamic>))
      .toList();

  List<LonelogBlock> get blocks => (_json['blocks'] as List)
      .map((e) => LonelogBlock.fromJson(e as Map<String, dynamic>))
      .toList();

  List<LonelogAddon> get addons => (_json['addons'] as List)
      .map((e) => LonelogAddon.fromJson(e as Map<String, dynamic>))
      .toList();

  List<LonelogExample> get examples => (_json['examples'] as List)
      .map((e) => LonelogExample.fromJson(e as Map<String, dynamic>))
      .toList();
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/lonelog_data_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Add the provider in `lib/state/providers.dart`**

Immediately after the `verdantDataProvider` definition (after line 852), add:

```dart

final lonelogDataProvider =
    FutureProvider<LonelogData>((ref) => LonelogData.load());
```

And add the import near the other engine imports at the top of the file:

```dart
import '../engine/lonelog_data.dart';
```

- [ ] **Step 6: Verify analysis is clean and commit**

Run: `dart analyze lib/engine/lonelog_data.dart lib/state/providers.dart`
Expected: No issues.

```bash
git add lib/engine/lonelog_data.dart test/lonelog_data_test.dart lib/state/providers.dart
git commit -m "feat(lonelog): LonelogData model + loader + provider"
```

---

### Task 3: Highlighter — `lonelog_highlight.dart`

**Files:**
- Create: `lib/engine/lonelog_highlight.dart`
- Create: `test/lonelog_highlight_test.dart`

- [ ] **Step 1: Write the failing test**

`test/lonelog_highlight_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_highlight.dart';

void main() {
  test('classifies a bare action', () {
    expect(highlight('@ Pick the lock'), [
      const LonelogSpan('@', LonelogSpanKind.symbol),
      const LonelogSpan(' Pick the lock', LonelogSpanKind.text),
    ]);
  });

  test('classifies an attributed action with an actor', () {
    expect(highlight('@(Jonah) Keeps watch'), [
      const LonelogSpan('@', LonelogSpanKind.symbol),
      const LonelogSpan('(Jonah)', LonelogSpanKind.actor),
      const LonelogSpan(' Keeps watch', LonelogSpanKind.text),
    ]);
  });

  test('classifies an oracle question and a consequence with a tag', () {
    expect(highlight('? Is the guard asleep').first.kind, LonelogSpanKind.symbol);
    final spans = highlight('=> The door opens [E:AlertClock 1/6]');
    expect(spans.first, const LonelogSpan('=>', LonelogSpanKind.symbol));
    expect(spans.last, const LonelogSpan('[E:AlertClock 1/6]', LonelogSpanKind.tag));
  });

  test('classifies a whole-line block delimiter', () {
    expect(highlight('[COMBAT]'), [
      const LonelogSpan('[COMBAT]', LonelogSpanKind.block),
    ]);
    expect(highlight('[/DUNGEON STATUS]').single.kind, LonelogSpanKind.block);
  });

  test('classifies a standalone tag line and a meta aside', () {
    expect(highlight('[N:Jonah|captured]').single.kind, LonelogSpanKind.tag);
    expect(highlight('(note: trying a flashback)').single.kind, LonelogSpanKind.meta);
  });

  test('is tolerant: unknown content is plain text', () {
    expect(highlight('just some prose'), [
      const LonelogSpan('just some prose', LonelogSpanKind.text),
    ]);
  });

  test('span texts always reconstruct the original line (round-trip)', () {
    for (final line in [
      '@ Pick the lock',
      '@(Jonah) Keeps watch',
      'd: d20+5=17 vs DC 15',
      '=> The door opens [E:AlertClock 1/6]',
      '[COMBAT]',
      '(note: aside)',
      '',
    ]) {
      expect(highlight(line).map((s) => s.text).join(), line);
    }
  });

  test('every asset example line classifies without loss', () {
    final data = jsonDecode(File('assets/lonelog_data.json').readAsStringSync())
        as Map<String, dynamic>;
    for (final ex in (data['examples'] as List)) {
      for (final line in ((ex as Map)['lines'] as List).cast<String>()) {
        final spans = highlight(line);
        expect(spans, isNotEmpty);
        expect(spans.map((s) => s.text).join(), line);
      }
    }
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/lonelog_highlight_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:juice_oracle/engine/lonelog_highlight.dart'`.

- [ ] **Step 3: Write `lib/engine/lonelog_highlight.dart`**

```dart
/// Classifies a single Lonelog log line into typed spans for syntax
/// highlighting. Tolerant: anything unrecognized stays [LonelogSpanKind.text],
/// and the concatenation of span texts always equals the input line.
///
/// This is the minimal "proven parser" for P1 — NOT a Markdown
/// parser/serializer (P2) and NOT a dice evaluator (P4). It recognizes the
/// leading symbol, an `@(Name)` actor, bracket tags, whole-line block
/// delimiters, and `(keyword: ...)` meta asides. Mid-line `->`/`=>` are not
/// re-highlighted; legend examples are written one symbol per line.
library;

enum LonelogSpanKind { symbol, actor, tag, block, meta, text }

class LonelogSpan {
  const LonelogSpan(this.text, this.kind);
  final String text;
  final LonelogSpanKind kind;

  @override
  bool operator ==(Object other) =>
      other is LonelogSpan && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => '${kind.name}:"$text"';
}

/// Leading symbols, longest-first so `d:`/`->`/`=>`/`tbl:` win over prefixes.
const _leadingSymbols = ['=>', '->', 'tbl:', 'gen:', 'd:', '@', '?'];

/// Reserved structural block names (digital `[NAME]`/`[/NAME]`).
const lonelogBlockNames = [
  'COMBAT',
  'DUNGEON STATUS',
  'RESOURCES',
  'BATTLE',
  'CAMPAIGN',
];

/// A whole line that is just an upper-case bracket delimiter, e.g. `[COMBAT]`
/// or `[/DUNGEON STATUS]`.
final _blockLineRe = RegExp(r'^\s*\[/?[A-Z][A-Z ]*\]\s*$');

/// Inline tokens: a bracket tag, or a `(keyword: ...)` meta aside.
final _inlineRe = RegExp(
    r'\[[^\]]+\]|\((?:note|reflection|reminder|question|house rule):[^)]*\)');

List<LonelogSpan> highlight(String line) {
  if (line.isEmpty) return const [LonelogSpan('', LonelogSpanKind.text)];
  if (_blockLineRe.hasMatch(line)) {
    return [LonelogSpan(line, LonelogSpanKind.block)];
  }

  final spans = <LonelogSpan>[];
  final lead = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
  var body = line.substring(lead.length);
  if (lead.isNotEmpty) spans.add(LonelogSpan(lead, LonelogSpanKind.text));

  String? sym;
  for (final s in _leadingSymbols) {
    if (body.startsWith(s)) {
      sym = s;
      break;
    }
  }
  if (sym != null) {
    spans.add(LonelogSpan(sym, LonelogSpanKind.symbol));
    body = body.substring(sym.length);
    if (sym == '@') {
      final actor = RegExp(r'^\([^)]*\)').firstMatch(body);
      if (actor != null) {
        spans.add(LonelogSpan(actor.group(0)!, LonelogSpanKind.actor));
        body = body.substring(actor.end);
      }
    }
  }

  var idx = 0;
  for (final m in _inlineRe.allMatches(body)) {
    if (m.start > idx) {
      spans.add(LonelogSpan(body.substring(idx, m.start), LonelogSpanKind.text));
    }
    final tok = m.group(0)!;
    spans.add(LonelogSpan(
        tok, tok.startsWith('[') ? LonelogSpanKind.tag : LonelogSpanKind.meta));
    idx = m.end;
  }
  if (idx < body.length) {
    spans.add(LonelogSpan(body.substring(idx), LonelogSpanKind.text));
  }
  return spans;
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/lonelog_highlight_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/lonelog_highlight.dart test/lonelog_highlight_test.dart
git commit -m "feat(lonelog): line highlighter classifier + tests"
```

---

### Task 4: `SessionsNotifier.editSystems`

**Files:**
- Modify: `lib/state/providers.dart` (inside `SessionsNotifier`, after `create`, ~line 713)
- Modify: `test/sessions_test.dart` (add a test group)

- [ ] **Step 1: Write the failing test**

Append inside `void main()` in `test/sessions_test.dart` (after the existing groups, before the final closing brace):

```dart
  group('editSystems', () {
    test('replaces a session\'s enabled systems', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      final notifier = container.read(sessionsProvider.notifier);

      await notifier.editSystems('default', {'juice', 'lonelog'});
      final state = await container.read(sessionsProvider.future);
      final meta = state.sessions.firstWhere((m) => m.id == 'default');
      expect(meta.enabledSystems, {'juice', 'lonelog'});
    });
  });
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/sessions_test.dart`
Expected: FAIL — `The method 'editSystems' isn't defined for the type 'SessionsNotifier'`.

- [ ] **Step 3: Add `editSystems` to `SessionsNotifier`**

In `lib/state/providers.dart`, immediately after the `create` method (after line 713) add:

```dart

  /// Replace the enabled optional systems for session [id].
  Future<void> editSystems(String id, Set<String> systems) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final updated = [
      for (final m in s.sessions)
        if (m.id == id)
          SessionMeta(id: m.id, name: m.name, systems: systems.toList())
        else
          m,
    ];
    await _save(SessionsState(active: s.active, sessions: updated));
  }
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/sessions_test.dart`
Expected: PASS (existing tests + the new editSystems test).

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/sessions_test.dart
git commit -m "feat(lonelog): SessionsNotifier.editSystems"
```

---

### Task 5: Registry + route for the `lonelog-ref` tool

**Files:**
- Modify: `lib/shared/tool_registry.dart` (ToolDef + `toolSystem`)
- Modify: `lib/shared/destination.dart` (`toolLocation`)
- Modify: `test/tool_registry_test.dart` (validSystems + gating test)

- [ ] **Step 1: Write the failing test**

In `test/tool_registry_test.dart`, (a) add `'lonelog'` to the `validSystems` set (currently lines 107-114) so it reads:

```dart
    const validSystems = {
      'juice',
      'mythic',
      'ironsworn',
      'party',
      'verdant',
      'lonelog',
      'core'
    };
```

(b) Append this test before the final closing brace of `main`:

```dart
  test('lonelog-ref gating: present only when the lonelog system is enabled', () {
    expect(
        buildToolRegistry(family: [], systems: {'juice'})
            .any((t) => t.id == 'lonelog-ref'),
        isFalse);
    final tools = buildToolRegistry(family: [], systems: {'juice', 'lonelog'});
    final tool = tools.singleWhere((t) => t.id == 'lonelog-ref');
    expect(tool.group, 'Reference');
    expect(tool.label, 'Lonelog Notation');
    expect(tool.badge, 'Lonelog');
  });
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/tool_registry_test.dart`
Expected: FAIL — `Bad state: No element` (no `lonelog-ref` tool exists yet).

- [ ] **Step 3: Add the ToolDef and `toolSystem` entry**

In `lib/shared/tool_registry.dart`, add to the `toolSystem` map (after the `'tables': 'juice',` line):

```dart
  'lonelog-ref': 'lonelog',
```

In `buildToolRegistry`, add this ToolDef immediately after the `tables` ToolDef (after line 208, before the `if (family.isNotEmpty)` moves block):

```dart
    const ToolDef(
      id: 'lonelog-ref',
      label: 'Lonelog Notation',
      icon: Icons.notes_outlined,
      group: 'Reference',
      badge: 'Lonelog',
    ),
```

- [ ] **Step 4: Add the route in `lib/shared/destination.dart`**

Add to the `toolLocation` map (after the `'tables': (Destination.oracles, 'tables'),` line):

```dart
  'lonelog-ref': (Destination.oracles, 'lonelog'),
```

- [ ] **Step 5: Run the test and verify it passes**

Run: `flutter test test/tool_registry_test.dart`
Expected: PASS (all tests, including the new gating test).

- [ ] **Step 6: Commit**

```bash
git add lib/shared/tool_registry.dart lib/shared/destination.dart test/tool_registry_test.dart
git commit -m "feat(lonelog): register gated lonelog-ref reference tool"
```

---

### Task 6: Reference screen — `LonelogReferenceScreen`

**Files:**
- Create: `lib/features/lonelog_reference_screen.dart`
- Create: `test/lonelog_reference_test.dart`

- [ ] **Step 1: Write the failing test**

`test/lonelog_reference_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_data.dart';
import 'package:juice_oracle/features/lonelog_reference_screen.dart';
import 'package:juice_oracle/state/providers.dart';

LonelogData _data() => LonelogData(
    jsonDecode(File('assets/lonelog_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  testWidgets('renders the legend sections and a highlighted example', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        lonelogDataProvider.overrideWith((ref) async => _data()),
      ],
      child: const MaterialApp(home: Scaffold(body: LonelogReferenceScreen())),
    ));
    await t.pumpAndSettle();

    expect(find.text('Core symbols'), findsOneWidget);
    expect(find.text('Tags & references'), findsOneWidget);
    expect(find.text('Addons'), findsOneWidget);
    // A worked-example title and one of its highlighted lines render.
    expect(find.text('A complete beat'), findsOneWidget);
    expect(find.textContaining('Pick the warehouse lock'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/lonelog_reference_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../lonelog_reference_screen.dart'`.

- [ ] **Step 3: Write `lib/features/lonelog_reference_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/lonelog_data.dart';
import '../engine/lonelog_highlight.dart';
import '../state/providers.dart';

/// Read-only reference for the Lonelog journaling notation. Renders the legend
/// (symbols, tags, blocks, addons) plus worked examples rendered through the
/// [highlight] classifier. No interactive state — a plain scroll, so it dodges
/// the loose-constraint freeze (no TabBarView / non-flex Material buttons).
class LonelogReferenceScreen extends ConsumerWidget {
  const LonelogReferenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lonelogDataProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load Lonelog legend: $e')),
      data: (data) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section('Core symbols', [
            for (final s in data.symbols)
              _Row('${s.symbol}  —  ${s.name}', s.role),
          ]),
          _Section('Tags & references', [
            for (final p in data.tagPrefixes)
              _Row('[${p.prefix}:…]  —  ${p.name}', p.meaning),
          ]),
          _Section('Blocks', [
            for (final b in data.blocks) _Row(b.openTag, b.purpose),
          ]),
          _Section('Addons', [
            for (final a in data.addons)
              _Row('${a.title}  (${a.status})', a.summary),
          ]),
          _Section('Worked examples', [
            for (final ex in data.examples) _Example(ex),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.head, this.body);
  final String head;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(head, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Example extends StatelessWidget {
  const _Example(this.example);
  final LonelogExample example;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color colorFor(LonelogSpanKind k) => switch (k) {
          LonelogSpanKind.symbol => scheme.primary,
          LonelogSpanKind.actor => scheme.tertiary,
          LonelogSpanKind.tag => scheme.secondary,
          LonelogSpanKind.block => scheme.error,
          LonelogSpanKind.meta => scheme.outline,
          LonelogSpanKind.text => scheme.onSurface,
        };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(example.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final line in example.lines)
            RichText(
              text: TextSpan(
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                children: [
                  for (final span in highlight(line))
                    TextSpan(text: span.text, style: TextStyle(color: colorFor(span.kind))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/lonelog_reference_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/features/lonelog_reference_screen.dart test/lonelog_reference_test.dart
git commit -m "feat(lonelog): read-only reference screen with highlighted examples"
```

---

### Task 7: Host the reference screen as a gated Oracles subtab

**Files:**
- Modify: `lib/features/oracles_tab.dart`
- Modify: `lib/shared/home_shell.dart` (pass `systems` to `OraclesTab`, ~line 233)

- [ ] **Step 1: Add the `systems` param and gated subtab to `OraclesTab`**

Replace the whole body of `lib/features/oracles_tab.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/oracle.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'fate_screen.dart';
import 'generators_screen.dart';
import 'tables_screen.dart';
import 'moves_screen.dart';
import 'lonelog_reference_screen.dart';

class OraclesTab extends ConsumerWidget {
  const OraclesTab(
      {super.key,
      required this.oracle,
      required this.family,
      this.systems = const {}});
  final Oracle oracle;
  final List<String> family;
  final Set<String> systems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lonelog = systems.contains('lonelog');
    final tabs = <SubtabDef>[
      const SubtabDef('oracle', 'Oracle'),
      const SubtabDef('generators', 'Generators'),
      const SubtabDef('tables', 'Tables'),
      if (family.isNotEmpty) const SubtabDef('moves', 'Moves'),
      if (lonelog) const SubtabDef('lonelog', 'Lonelog'),
    ];
    final children = <Widget>[
      FateScreen(oracle: oracle, initialSection: FateSection.fateCheck),
      GeneratorsScreen(oracle: oracle),
      TablesScreen(oracle: oracle),
      if (family.isNotEmpty) MovesScreen(rulesetIds: family),
      if (lonelog) const LonelogReferenceScreen(),
    ];
    return SubtabHost(
      destination: Destination.oracles,
      tabs: tabs,
      children: children,
    );
  }
}
```

- [ ] **Step 2: Pass `systems` from `home_shell.dart`**

In `lib/shared/home_shell.dart`, in `_root`, change the `Destination.oracles` case (line 233) to:

```dart
      case Destination.oracles:
        return OraclesTab(
            oracle: widget.oracle, family: family, systems: systems);
```

- [ ] **Step 3: Verify analysis is clean**

Run: `dart analyze lib/features/oracles_tab.dart lib/shared/home_shell.dart`
Expected: No issues.

- [ ] **Step 4: Run the shell tests to confirm no regression**

Run: `flutter test test/shell_filtering_test.dart test/party_oracles_tab_test.dart test/home_shell_test.dart`
Expected: PASS. (These sessions do not enable `lonelog`, so the reference subtab is not built and no `lonelogDataProvider` override is needed.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/oracles_tab.dart lib/shared/home_shell.dart
git commit -m "feat(lonelog): host reference as a gated Oracles subtab"
```

---

### Task 8: Campaign UI — enable Lonelog at creation and via edit

**Files:**
- Modify: `lib/shared/home_shell.dart` (New Campaign checkbox; edit-systems action + dialog)
- Create: `test/lonelog_campaign_ui_test.dart`

- [ ] **Step 1: Write the failing test**

`test/lonelog_campaign_ui_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/state/providers.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));
final _verdant = VerdantData(
    jsonDecode(File('assets/verdant_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _emu = EmulatorData(
    jsonDecode(File('assets/emulator_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('New Campaign dialog offers a Lonelog toggle (default off)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        verdantDataProvider.overrideWith((ref) async => _verdant),
        emulatorDataProvider.overrideWith((ref) async => _emu),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();

    // Open Campaigns -> New campaign.
    await t.tap(find.byTooltip('Campaigns'));
    await t.pumpAndSettle();
    await t.tap(find.text('New campaign'));
    await t.pumpAndSettle();

    final lonelog = find.byKey(const Key('sys-lonelog'));
    expect(lonelog, findsOneWidget);
    final tile = t.widget<CheckboxListTile>(lonelog);
    expect(tile.value, isFalse); // opt-in: default off
  });
}
```

> Note: the `find.byTooltip('Campaigns')` target is the existing app-bar action that opens `_showSessions`. If the tooltip text differs, read `home_shell.dart` and match the actual tooltip/icon used to open the Campaigns dialog.

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/lonelog_campaign_ui_test.dart`
Expected: FAIL — no widget with key `sys-lonelog`.

- [ ] **Step 3: Add the Lonelog checkbox to `_NewCampaignDialog`**

In `lib/shared/home_shell.dart`, in `_NewCampaignDialogState`:

Add the field after `bool _verdant = true;` (line 424):

```dart
  bool _lonelog = false;
```

Add to the `picked` set in `_submit` (after the `if (_verdant) 'verdant',` line):

```dart
      if (_lonelog) 'lonelog',
```

Add this `CheckboxListTile` after the `sys-verdant` one (after line 486):

```dart
          CheckboxListTile(
            key: const Key('sys-lonelog'),
            title: const Text('Lonelog journaling'),
            value: _lonelog,
            onChanged: (v) => setState(() => _lonelog = v ?? false),
          ),
```

- [ ] **Step 4: Add an edit-systems action to the Campaigns dialog**

In `lib/shared/home_shell.dart`, in `_showSessions`, change the session `ListTile`'s `trailing` (lines 79-84) so each campaign row has an edit button beside the delete button:

```dart
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.tune),
                        tooltip: 'Edit systems',
                        onPressed: () => _editSystems(dialogContext, s),
                      ),
                      if (sessions.sessions.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(dialogContext, s),
                        ),
                    ],
                  ),
```

Add this method to the `State` class (next to `_createSession`, after line 123):

```dart
  Future<void> _editSystems(BuildContext dialogContext, SessionMeta meta) async {
    final picked = await showDialog<Set<String>>(
      context: dialogContext,
      builder: (context) => _EditSystemsDialog(initial: meta.enabledSystems),
    );
    if (picked == null) return;
    await ref.read(sessionsProvider.notifier).editSystems(meta.id, picked);
  }
```

Add the `_EditSystemsDialog` widget at the end of the file (after `_NewCampaignDialogState`):

```dart

/// Dialog to toggle the optional systems of an existing campaign.
/// Returns the chosen set, or null on cancel.
class _EditSystemsDialog extends StatefulWidget {
  const _EditSystemsDialog({required this.initial});
  final Set<String> initial;

  @override
  State<_EditSystemsDialog> createState() => _EditSystemsDialogState();
}

class _EditSystemsDialogState extends State<_EditSystemsDialog> {
  late final Set<String> _picked = {...widget.initial};

  Widget _row(String id, String label) => CheckboxListTile(
        key: Key('edit-sys-$id'),
        title: Text(label),
        value: _picked.contains(id),
        onChanged: (v) => setState(() {
          if (v ?? false) {
            _picked.add(id);
          } else {
            _picked.remove(id);
          }
        }),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enabled systems'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row('juice', 'Juice oracle'),
          _row('mythic', 'Mythic GME'),
          _row('ironsworn', 'Ironsworn family'),
          _row('party', 'Party emulator'),
          _row('verdant', 'Verdant Hexcrawling'),
          _row('lonelog', 'Lonelog journaling'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_picked),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run the test and verify it passes**

Run: `flutter test test/lonelog_campaign_ui_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify analysis and commit**

Run: `dart analyze lib/shared/home_shell.dart`
Expected: No issues.

```bash
git add lib/shared/home_shell.dart test/lonelog_campaign_ui_test.dart
git commit -m "feat(lonelog): enable Lonelog at campaign creation + edit-systems dialog"
```

---

### Task 9: Document the build rail + full verification

**Files:**
- Modify: `CLAUDE.md` (Project notes)

- [ ] **Step 1: Add a `build_lonelog.py` note to `CLAUDE.md`**

In `CLAUDE.md`, under "## Project notes", add this bullet after the Verdant Journey bullet:

```markdown
- The Lonelog notation legend (`assets/lonelog_data.json`: the 5 core symbols,
  reserved tag prefixes, structural blocks, the 7 addons, and worked examples)
  is generated by `build_lonelog.py`. Same rail as `build_verdant.py`:
  hand-transcribed literals are the source of truth; the script self-verifies
  structure (unique reserved prefixes, the 5 core symbols, balanced block tags,
  well-formed examples) and best-effort cross-checks `/tmp/lonelog_core.txt`.
  Edit the script, rerun `python3 build_lonelog.py`, copy `lonelog_data.json`
  into `assets/`; never hand-edit the JSON. This is the P1 Foundation slice of
  Lonelog support (see `docs/superpowers/specs/2026-06-14-lonelog-foundation-design.md`).
```

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: PASS — all tests green, including the 5 new Lonelog test files and the updated `tool_registry_test` / `sessions_test`.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(lonelog): document build_lonelog.py rail in CLAUDE.md"
```

---

## Self-review

**Spec coverage:**
- `lonelog` system flag + gating → Tasks 4 (editSystems), 5 (registry gating), 7 (subtab gating), 8 (creation + edit UI). ✓
- `build_lonelog.py` → `assets/lonelog_data.json`, self-verified → Task 1. ✓
- `lib/engine/lonelog_data.dart` + `lonelogDataProvider` → Task 2. ✓
- Highlighter (proven parser) + example cross-check → Task 3. ✓
- Gated read-only reference tool with live-highlighted examples → Tasks 6, 7. ✓
- Reference in the Table Browser group → Task 5 (`group: 'Reference'`). ✓
- Tests: build self-verify (Task 1), highlighter unit + asset cross-check (Task 3), reference widget + gated (Tasks 6/7), editSystems gating (Task 4). ✓
- CLAUDE.md rail note → Task 9. ✓
- Out-of-scope items (P2 serializer, P3 journal, P4 addon behavior, global settings) are excluded — no task builds them. ✓

**Placeholder scan:** none — every code/test step has complete content.

**Type consistency:** `LonelogData`, `LonelogSymbol/Prefix/Block/Addon/Example`, `LonelogSpan`, `LonelogSpanKind`, `highlight()`, `lonelogDataProvider`, `SessionsNotifier.editSystems`, ToolDef id `lonelog-ref`, system flag `lonelog`, subtab key `lonelog`, asset path `assets/lonelog_data.json` — all consistent across tasks. `OraclesTab.systems` defaults to `const {}` so existing call sites without the arg keep compiling; `home_shell` passes it explicitly (Task 7).

**Decisions locked here (not open):** `lonelog` is intentionally NOT in `kAllSystems` (opt-in, off for legacy/default campaigns). New Campaign checkbox defaults OFF. No `toolHelpPage` entry in P1 (no help page yet). Mid-line `->`/`=>` are not re-highlighted; examples are one symbol per line.
