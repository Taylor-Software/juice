# Cycle 3 Item A: Quick Wins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three small validated wins from the 2026-06-11 competitive rescan: the Juice Location grid generator (only content gap vs juice-roll), tap-to-roll fate check (juice-roll issue #4 — validated UX demand), and a WCAG AA contrast regression test.

**Architecture:** Location follows the verified-data rail (encode + verify in build_oracle.py → asset → Dart accessor → generator UI). Tap-to-roll is a one-widget change. Contrast is a pure Dart test over `AppTheme`.

**Tech Stack:** Python (build_oracle.py), Flutter/Dart, flutter_test.

**Branch:** `feat/cycle3-quick-wins` off `main`.

Source of truth for the Location grid — Juice PDF (`pdftotext -layout` of
`~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/juice_081425_screen.pdf`,
already extracted at /tmp/juice_screen.txt lines ~55-75), cross-checked against
juice-roll's transcription. Both agree:

```
            North
  0-3   4-7   8-11  12-15 16-19
  20-23 24-27 28-31 32-35 36-39
W 40-43 44-47 48-51 52-55 56-59 E
  60-63 64-67 68-71 72-75 76-79
  80-83 84-87 88-91 92-95 96-99
            South
```

1d100 read as 0-99. `row = n ~/ 20`, `col = (n % 20) ~/ 4`. Columns 0-1 =
West, 2 = Center, 3-4 = East; rows 0-1 = North, 2 = Center, 3-4 = South.

Hard rules: `flutter analyze --no-fatal-infos` exactly 1 pre-existing info
(lib/engine/models.dart:2); full suite green (currently 254); TDD; exact
commit messages, no co-author lines. After editing build_oracle.py run
`python3 build_oracle.py` and copy the output JSON over
`assets/oracle_data.json` (check how the script emits — read its `__main__`
section first).

---

### Task 1: Location grid — pipeline + engine + UI

**Files:**
- Modify: `build_oracle.py` (new section + verify + emit `location` key)
- Regenerate: `assets/oracle_data.json`
- Modify: `lib/engine/oracle_data.dart` (accessor; read the file first, follow the existing accessor pattern for keys like `roll_high`)
- Modify: `lib/engine/oracle.dart` (new result type + roll method; follow existing result-class pattern)
- Modify: `lib/features/generators_screen.dart` (new generator card in `GenSection.exploration`; read `_Gen`/section tagging first; update `labelsFor` expectations if the screen test asserts them)
- Tests: `test/oracle_engine_test.dart` or a new `test/location_test.dart` (engine), update `test/generators_screen_test.dart` if section labels are asserted there (check `screen_params_test.dart` too)

- [ ] **Step 1: build_oracle.py.** Add:

```python
# Location grid (screen PDF, bottom-left): 1d100 -> 5x5 compass grid.
# Read 1d100 as 0-99; row = n // 20, col = (n % 20) // 4.
LOCATION_GRID = {
    "rows": 5,
    "cols": 5,
    "row_labels": ["North", "North", "Center", "South", "South"],
    "col_labels": ["West", "West", "Center", "East", "East"],
}

def location_cell(n):
    """0-99 -> (col, row) on the Location grid."""
    return ((n % 20) // 4, n // 20)
```

In `verify()` add a section that checks the formula against the PDF's
explicit ranges (encode the 25 ranges literally and assert every n in each
range maps to that cell, and that all 100 values are covered exactly once):

```python
    # 10. Location grid: formula matches the PDF's explicit cell ranges.
    expected = {}
    for row in range(5):
        for col in range(5):
            lo = row * 20 + col * 4
            for n in range(lo, lo + 4):
                expected[n] = (col, row)
    assert len(expected) == 100
    for n in range(100):
        assert location_cell(n) == expected[n], f"location_cell({n})"
```

(Adjust the section number to follow the script's existing verify numbering.)
Emit `"location": LOCATION_GRID` alongside the other top-level keys.
Run `python3 build_oracle.py`, confirm verification passes, copy output to
`assets/oracle_data.json` per the script's documented flow.

- [ ] **Step 2: failing engine tests** (new `test/location_test.dart`):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';

void main() {
  final data = OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>);
  final oracle = Oracle(data, seed: 42);

  test('locationFor maps d100 to grid cell and compass label', () {
    expect(oracle.locationFor(0).col, 0);
    expect(oracle.locationFor(0).row, 0);
    expect(oracle.locationFor(0).label, 'North-West');
    expect(oracle.locationFor(48).label, 'Center');
    expect(oracle.locationFor(51).label, 'Center');
    expect(oracle.locationFor(19).label, 'North-East');
    expect(oracle.locationFor(99).label, 'South-East');
    expect(oracle.locationFor(80).label, 'South-West');
    expect(oracle.locationFor(56).label, 'East');
    expect(oracle.locationFor(8).label, 'North');
  });

  test('every value 0-99 maps into the 5x5 grid exactly', () {
    final seen = <String, int>{};
    for (var n = 0; n < 100; n++) {
      final loc = oracle.locationFor(n);
      expect(loc.col, inInclusiveRange(0, 4));
      expect(loc.row, inInclusiveRange(0, 4));
      seen['${loc.col},${loc.row}'] = (seen['${loc.col},${loc.row}'] ?? 0) + 1;
    }
    expect(seen.length, 25);
    expect(seen.values.every((c) => c == 4), isTrue);
  });

  test('rollLocation rolls 1d100 and carries the roll value', () {
    final loc = oracle.rollLocation();
    expect(loc.roll, inInclusiveRange(0, 99));
    expect(loc, equals(oracle.locationFor(loc.roll)));
  });
}
```

(If `Oracle` has no seeded constructor, follow however other engine tests
make deterministic rolls — read `test/oracle_engine_test.dart` first and
match its pattern; adjust the third test to assert range + consistency only.)

- [ ] **Step 3: implement engine.** In `lib/engine/oracle.dart`, follow the
existing result-record/class style:

```dart
/// Location grid cell (screen PDF): 1d100 read as 0-99 onto a 5x5
/// compass grid; row = n ~/ 20, col = (n % 20) ~/ 4.
class LocationResult {
  const LocationResult(
      {required this.roll, required this.col, required this.row});
  final int roll;
  final int col;
  final int row;

  /// 'North-West' … 'Center' … 'South-East' (cols 0-1 W, 2 center, 3-4 E;
  /// rows 0-1 N, 2 center, 3-4 S).
  String get label {
    final ns = row < 2 ? 'North' : (row == 2 ? '' : 'South');
    final ew = col < 2 ? 'West' : (col == 2 ? '' : 'East');
    if (ns.isEmpty && ew.isEmpty) return 'Center';
    if (ns.isEmpty) return ew;
    if (ew.isEmpty) return ns;
    return '$ns-$ew';
  }

  @override
  bool operator ==(Object other) =>
      other is LocationResult &&
      other.roll == roll &&
      other.col == col &&
      other.row == row;
  @override
  int get hashCode => Object.hash(roll, col, row);
}
```

with `locationFor(int n)` (pure) and `rollLocation()` (1d100 via the
engine's Dice, converting to 0-99 the same way other d100 tables do — read
how existing d100 rolls treat 100/00 and match it). Use the asset's
`location` key for grid dims if the accessor pattern wants data-driven
values; the formula itself may live in Dart (mirrors the verified Python,
same as the Fate Check map rule — note it in a comment).

- [ ] **Step 4: UI.** `generators_screen.dart`, exploration section: a
`_Gen`-style card "Location" that rolls, then renders a small 5×5 grid
(e.g. `Table` or `GridView.count` of 25 cells, highlighted cell uses
`colorScheme.primaryContainer`) with North/South/West/East edge labels,
the label text ('North-West') + roll value, and the standard add-to-journal
action ("Location: North-West (37)"). Match surrounding card structure and
keys (give the roll button `Key('gen-location')`).

- [ ] **Step 5: widget test** (in generators_screen_test.dart, matching its
patterns): tapping `gen-location` shows a result containing a compass label
and the grid; add-to-journal writes an entry titled 'Location'.

- [ ] **Step 6: gates + commit.** `python3 build_oracle.py` verification
passes; `flutter test` green; analyze 1 info.

```bash
git add build_oracle.py assets/oracle_data.json lib/engine/oracle.dart lib/engine/oracle_data.dart lib/features/generators_screen.dart test/location_test.dart test/generators_screen_test.dart
git commit -m "feat: Location grid generator (1d100 5x5 compass grid, PDF-verified)"
```

---

### Task 2: Tap-to-roll fate check

**Files:**
- Modify: `lib/features/fate_screen.dart` (~line 86)
- Test: update/add in `test/fate_screen_test.dart` (read it first; if no such file, find where FateScreen is widget-tested)

- [ ] **Step 1: failing test.** Selecting a likelihood segment immediately
produces a fate-check result (result card appears without tapping 'Roll
Fate Check'), and the result used the tapped likelihood (assert via the
rendered result card's content or provider state, matching existing test
style).

- [ ] **Step 2: implement.** In the fate-check `SegmentedButton`:

```dart
            onSelectionChanged: (s) => setState(() {
              _likelihood = s.first;
              // Tap-to-roll: selecting a likelihood rolls immediately
              // (validated demand — juice-roll issue #4). The Roll button
              // stays for re-rolls at the same likelihood.
              _last = widget.oracle.fateCheck(_likelihood);
            }),
```

Keep the Roll button unchanged.

- [ ] **Step 3: gates + commit.**

```bash
git add lib/features/fate_screen.dart test/fate_screen_test.dart
git commit -m "feat: tap-to-roll fate check — selecting a likelihood rolls immediately"
```

---

### Task 3: WCAG AA contrast regression test

**Files:**
- Create: `test/theme_contrast_test.dart`

The theme is M3 `ColorScheme.fromSeed` (lib/shared/theme.dart) and widgets
use only scheme tokens (verify with a grep for `Color(0x` under lib/ —
expect matches only in theme.dart; report any others as findings). The test
pins WCAG AA for the token PAIRS the app actually renders as text.

- [ ] **Step 1: write the test:**

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/theme.dart';

double _luminance(Color c) => c.computeLuminance();

double contrast(Color a, Color b) {
  final l1 = max(_luminance(a), _luminance(b));
  final l2 = min(_luminance(a), _luminance(b));
  return (l1 + 0.05) / (l2 + 0.05);
}

void main() {
  for (final entry in {
    'light': AppTheme.light().colorScheme,
    'dark': AppTheme.dark().colorScheme,
  }.entries) {
    final s = entry.value;
    // Token pairs rendered as normal-size text in the app -> 4.5:1 (AA).
    final textPairs = <String, (Color, Color)>{
      'onSurface/surface': (s.onSurface, s.surface),
      'onSurfaceVariant/surface': (s.onSurfaceVariant, s.surface),
      'onPrimary/primary': (s.onPrimary, s.primary),
      'onPrimaryContainer/primaryContainer':
          (s.onPrimaryContainer, s.primaryContainer),
      'onSecondaryContainer/secondaryContainer':
          (s.onSecondaryContainer, s.secondaryContainer),
      'onErrorContainer/errorContainer':
          (s.onErrorContainer, s.errorContainer),
      'onError/error': (s.onError, s.error),
      'primary/surface': (s.primary, s.surface), // TextButton labels
      'error/surface': (s.error, s.surface),
      'onSurfaceVariant/surfaceContainerHighest':
          (s.onSurfaceVariant, s.surfaceContainerHighest), // cards/sheets
    };
    for (final p in textPairs.entries) {
      test('[${entry.key}] ${p.key} meets WCAG AA (4.5:1)', () {
        expect(contrast(p.value.$1, p.value.$2), greaterThanOrEqualTo(4.5),
            reason:
                '${p.key} = ${contrast(p.value.$1, p.value.$2).toStringAsFixed(2)}');
      });
    }
  }
}
```

- [ ] **Step 2: run.** If any pair fails, fix the THEME (e.g. override the
failing role on the scheme in theme.dart with a compliant shade — keep the
seed; smallest change that passes) and note it in the commit body. If all
pass, the test still lands as a regression pin.

- [ ] **Step 3: hardcoded-color audit.** `grep -rn 'Color(0x' lib/ --include=*.dart`
— anything outside theme.dart gets reported in your final summary (do NOT
refactor beyond the task; alpha-faded decorative non-text elements are
WCAG-exempt).

- [ ] **Step 4: commit.**

```bash
git add test/theme_contrast_test.dart lib/shared/theme.dart
git commit -m "test: pin WCAG AA contrast for rendered theme token pairs"
```

(Drop theme.dart from the add if unchanged.)

---

## Verification (controller, after tasks)

Browser check on built web app: Location card rolls and renders grid;
fate-check likelihood tap produces result in one tap. Then PR → CI →
squash-merge → roadmap row A done.
