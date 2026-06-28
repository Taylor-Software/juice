# Custom Sheet — Computed Badges (P2)

**Date:** 2026-06-27
**Status:** Design approved, pending implementation plan
**Builds on:** `docs/superpowers/specs/2026-06-26-custom-character-creator-design.md` (the "computed badge" + "cross-block references" Out-of-scope items)

## Summary

Add a `computed` block type to the Custom/Homebrew sheet: a **read-only derived
value** that references other blocks and shows either a **number badge** or a
**conditional chip**. This is the deferred "computed badge / cross-block
reference" item — built deliberately **without a general expression parser**,
mirroring the roll model's enumerated, self-contained design.

Motivating real-world targets (from the bespoke sheets):
- **Knave** inventory slots = `10 + CON` → a number badge.
- **Argosa** "Staggered" = `currentHp * 2 ≤ maxHp` → a conditional chip.

## Decision (from brainstorming)

Expressiveness = **two operands, one binary op** (option C). Each operand is a
constant or a block-reference with an optional integer coefficient; one operator
that is arithmetic (→ number) or a comparison (→ conditional chip). Bounded:
exactly two operands, one op, no nesting, no parser.

## Model

In `lib/engine/custom_sheet.dart` (pure — no Flutter — alongside `resolveRoll` /
`customStatMod`):

```dart
enum ComputedOp { add, sub, mul, divFloor, le, lt, eq, ge, gt }

class ComputedOperand {
  const ComputedOperand({
    this.isConst = true,
    this.constant = 0,
    this.blockId = '',
    this.subKey = '',
    this.coeff = 1,
  });
  final bool isConst;
  final int constant;   // when isConst
  final String blockId; // referenced block id (when !isConst)
  final String subKey;  // stat key, or 'cur'/'max' for hp/luck; '' for counter/timer
  final int coeff;      // multiplier on the referenced value
  // toJson / maybeFromJson (tolerant: bad shape → const 0)
}

class ComputedConfig {  // serialized into CustomBlock.config
  const ComputedConfig({required this.a, required this.op, required this.b});
  final ComputedOperand a, b;
  final ComputedOp op;
  // toJson / maybeFromJson (tolerant: missing/bad → a=const0, op=add, b=const0)
}
```

- `op` arithmetic (`add`/`sub`/`mul`/`divFloor`) → result is an **int** (number
  badge). `op` comparison (`le`/`lt`/`eq`/`ge`/`gt`) → result is a **bool**
  (conditional chip).
- A `computed` block has **no value** in `CustomSheet.values` (it is derived);
  its formula lives entirely in `block.config`.

### Resolver

```dart
({int? number, bool? flag}) resolveComputed(
    List<CustomBlock> blocks, Map<String, dynamic> values, CustomBlock block);
```

Pure + **total** (never throws). Steps:
1. Parse `ComputedConfig.maybeFromJson(block.config)`.
2. `operandValue(o)` = `o.isConst ? o.constant : o.coeff * lookup(blocks, values, o.blockId, o.subKey)`.
3. Arithmetic op → `(number: a op b, flag: null)`; comparison op →
   `(number: null, flag: a cmp b)`.

`lookup(blocks, values, id, subKey)` resolves the referenced scalar:
- referenced block type `stat` → `values[id][subKey]` (the stat score).
- `hp` → `values[id]['cur']` or `['max']` (per `subKey`).
- `luck` → `values[id]['cur']` or `['max']`.
- `counter` / `timer` → `values[id]` (the int; `subKey` ignored).
- anything else — `freeform`, `dropdown`, `roll`, `progress`, `conditions`,
  `togglechips`, or another **`computed`** — → **0** (not referenceable).
- missing block id / missing key / wrong value type → **0**.

`divFloor` with divisor `0` → result `0`.

### No cycles by construction

A `computed` block may reference only **non-computed value blocks**. The config
UI's source-block dropdown omits `computed` blocks, and `lookup` treats a
`computed` reference as `0`. So there is no dependency graph and no cycle
detection — a computed value can never depend on another computed value.

## UI

`lib/features/custom_sheet.dart`:

**Play** — `_playBlock` switch gains a `computed` arm (`_playComputed(b)`):
- calls `resolveComputed(_s.blocks, _s.values, b)`.
- number result → `Text('${b.label}: $n')` (key `custom-<id>-computed`).
- flag `true` → `Chip(label: Text(b.label))` (key `custom-<id>-computed-chip`).
- flag `false` → `SizedBox.shrink()` (chip hidden — matches Argosa "Staggered").
- read-only: no stepper, no `_setVal` write.

**Edit config** — `_configBlock` switch gains a `computed` arm
(`_configComputed(b)`) opening a `_ComputedConfigDialog` (StatefulWidget, like
`_StatConfigDialog`):
- **Operand A** and **Operand B** editors, each: a const/ref toggle; const → an
  int field; ref → a **source-block dropdown** (referenceable blocks only —
  stat/hp/luck/counter/timer, by label; `computed` blocks omitted), a **sub-key
  dropdown** (the stat keys for a stat block; `cur`/`max` for hp/luck; hidden for
  counter/timer), and a coefficient int field.
- an **operator dropdown** (`ComputedOp`, visually grouped arithmetic vs
  comparison).
- the block **label** field (doubles as the badge/chip text).
- persists `ComputedConfig.toJson()` into `block.config` via the existing
  `_save(... copyWith(blocks: ...))`.

**Add-block picker** — add `computed` (label "Computed value") to the type list
so a new computed block can be created. Default config: `a = const 0`, `op = add`,
`b = const 0` → renders `"<label>: 0"` until configured.

## Registration / wiring

- `lib/engine/custom_sheet.dart`: add `computed` to `CustomBlockType`; add
  `ComputedOp` / `ComputedOperand` / `ComputedConfig` (+ tolerant JSON) and
  `resolveComputed` / `lookup`. `CustomBlock.maybeFromJson` already drops unknown
  block types, so an older client ignores a `computed` block gracefully (forward-compat).
- No new `CustomSheet.values` entry for computed blocks (derived only).
- No change to `resolveRoll` / templates / other block types.

## Testing

`test/custom_sheet_model_test.dart`:
- `resolveComputed` — `10 + CON` (number 16); `cur*2 ≤ max` true and false;
  one case per arithmetic op (add/sub/mul/divFloor incl. div-by-0 → 0) and per
  comparison op (le/lt/eq/ge/gt); coefficient applied; const-vs-ref operands.
- graceful — missing block id → 0; missing stat key → 0; ref to a non-numeric
  block (freeform) → 0; ref to another `computed` block → 0.
- `ComputedConfig` / `ComputedOperand` JSON round-trip; tolerant `maybeFromJson`
  (missing/garbage → `a=const0, op=add, b=const0`).

`test/custom_sheet_ui_test.dart`:
- a computed number badge renders `"<label>: <n>"` for a `10+CON` block over a
  stat block holding `con: 14` (→ `24`); editing the referenced CON updates it.
- a comparison chip shows the label when the flag is true and is absent when
  false.
- the config dialog: add a `computed` block, set A=const 10 + B=ref(stat,'con'),
  op=add, confirm → the badge reads the computed number.

## Out of scope (deferred)

- **Chained computed-on-computed** — cycle-free by construction (a computed block
  can't reference another computed block).
- **`ceil` / 3+ operands / nesting / a general expression parser** — Argosa
  `resetLuck = 10 + ceil(level/2)` is NOT expressible; acceptable (niche).
- **Computed values as a roll-row bonus** — rolls stay self-contained.
- **No starter template uses `computed`** (templates kept simple); it is only
  reachable via the Add-block picker.
- No backward-compat concerns (pre-release; a `computed` block simply didn't
  exist before).
