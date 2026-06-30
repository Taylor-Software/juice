/// Pure model + roll logic for user-authored random tables.
/// No Flutter imports — unit-tested without a widget harness.
library;

import 'dart:convert';

import 'dice.dart';
import 'models.dart';

/// A parsed `NdM` dice expression (count·dSides). [count]>=1, [sides]>=2.
class DiceNotation {
  const DiceNotation(this.count, this.sides);
  final int count;
  final int sides;
}

final _diceRe = RegExp(r'^(\d*)d(\d+)$');

/// Parse `d6`/`2d6`/`d100` (whitespace + case tolerant). Returns null on garbage
/// or out-of-range (count 1..100, sides 2..1000).
DiceNotation? parseDiceNotation(String raw) {
  final s = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final m = _diceRe.firstMatch(s);
  if (m == null) return null;
  final count = m.group(1)!.isEmpty ? 1 : int.parse(m.group(1)!);
  final sides = int.parse(m.group(2)!);
  if (count < 1 || count > 100 || sides < 2 || sides > 1000) return null;
  return DiceNotation(count, sides);
}

/// Sum [n.count] rolls of d[n.sides].
int rollNotation(DiceNotation n, Dice dice) {
  var total = 0;
  for (var i = 0; i < n.count; i++) {
    total += dice.dN(n.sides);
  }
  return total;
}

/// How a [CustomTable] resolves a roll.
enum TableRoll { uniform, weighted, ranges }

TableRoll _tableRollFromName(String? s) => switch (s) {
      'weighted' => TableRoll.weighted,
      'ranges' => TableRoll.ranges,
      _ => TableRoll.uniform,
    };

/// One row of a [CustomTable]. [weight] biases weighted picks (min 1).
/// [min]/[max] give the inclusive span this row covers in ranges mode.
class CustomRow {
  const CustomRow(this.text, {this.weight = 1, this.min, this.max});
  final String text;
  final int weight;
  final int? min;
  final int? max;

  Map<String, dynamic> toJson() => {
        't': text,
        if (weight != 1) 'w': weight,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      };

  /// Lifts a bare String (legacy) or an object map into a [CustomRow].
  static CustomRow fromJson(Object? raw) {
    if (raw is String) return CustomRow(raw);
    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      return CustomRow(
        (m['t'] as String?) ?? '',
        weight: (m['w'] as num?)?.toInt() ?? 1,
        min: (m['min'] as num?)?.toInt(),
        max: (m['max'] as num?)?.toInt(),
      );
    }
    return const CustomRow('');
  }
}

/// A user-authored random table.
class CustomTable {
  const CustomTable({
    required this.id,
    required this.name,
    this.mode = TableRoll.uniform,
    this.dice = '',
    this.rows = const [],
  });

  final String id;
  final String name;
  final TableRoll mode;
  final String dice;
  final List<CustomRow> rows;

  CustomTable copyWith({
    String? name,
    TableRoll? mode,
    String? dice,
    List<CustomRow>? rows,
  }) =>
      CustomTable(
        id: id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        dice: dice ?? this.dice,
        rows: rows ?? this.rows,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (mode != TableRoll.uniform) 'mode': mode.name,
        if (dice.isNotEmpty) 'dice': dice,
        'rows': rows.map((r) => r.toJson()).toList(),
      };

  factory CustomTable.fromJson(Map<String, dynamic> j) => CustomTable(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        mode: _tableRollFromName(j['mode'] as String?),
        dice: (j['dice'] as String?) ?? '',
        rows: [
          for (final r in (j['rows'] as List? ?? const []))
            if (r is String || r is Map) CustomRow.fromJson(r),
        ],
      );

  /// Tolerant decode for persistence: null when [raw] is not a map or lacks id.
  static CustomTable? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    if (map['id'] is! String) return null;
    return CustomTable.fromJson(map);
  }
}

/// Stable marker for an exported table pack file.
const kTablePackKind = 'juice-table-pack';

/// Serialize [tables] to a portable pack JSON string.
String encodeTablePack(List<CustomTable> tables) => jsonEncode({
      'kind': kTablePackKind,
      'v': 1,
      'tables': tables.map((t) => t.toJson()).toList(),
    });

/// Decode a pack JSON string into tables. Tolerant: returns an empty list when
/// the payload is not a recognizable pack; drops individual malformed tables.
/// Throws [FormatException] only when the top-level JSON itself is unparseable.
List<CustomTable> decodeTablePack(String raw) {
  final dynamic root = jsonDecode(raw); // may throw FormatException — caller handles
  if (root is! Map) return const [];
  if (root['kind'] != kTablePackKind) return const [];
  final list = root['tables'];
  if (list is! List) return const [];
  return list
      .map(CustomTable.maybeFromJson)
      .whereType<CustomTable>()
      .toList();
}

/// Roll [table] per its [CustomTable.mode]. An empty table yields a placeholder
/// so the UI never has to special-case.
GenResult rollCustomTable(CustomTable table, Dice dice) {
  final title = table.name.isEmpty ? 'Table' : table.name;
  if (table.rows.isEmpty) {
    return GenResult(
        title: title,
        rolls: const [Roll(label: 'Result', value: '(empty table)')]);
  }
  switch (table.mode) {
    case TableRoll.ranges:
      return _rollRanges(table, dice, title);
    case TableRoll.weighted:
      return _rollWeighted(table, dice, title);
    case TableRoll.uniform:
      final n = table.rows.length;
      final idx = dice.dN(n); // 1..n
      return GenResult(title: title, rolls: [
        Roll(
            label: 'Result',
            value: table.rows[idx - 1].text,
            detail: 'd$n → $idx'),
      ]);
  }
}

String _value(String text) => text.isEmpty ? '(no result)' : text;

GenResult _rollWeighted(CustomTable table, Dice dice, String title) {
  final weights = [for (final r in table.rows) r.weight < 1 ? 1 : r.weight];
  final total = weights.fold<int>(0, (a, b) => a + b);
  final hit = dice.dN(total); // 1..total
  var acc = 0;
  for (var i = 0; i < table.rows.length; i++) {
    acc += weights[i];
    if (hit <= acc) {
      return GenResult(title: title, rolls: [
        Roll(
            label: 'Result',
            value: _value(table.rows[i].text),
            detail: 'd$total → $hit'),
      ]);
    }
  }
  // Unreachable (hit <= total), but keep total-safe.
  return GenResult(title: title, rolls: [
    Roll(
        label: 'Result',
        value: _value(table.rows.last.text),
        detail: 'd$total → $hit'),
  ]);
}

GenResult _rollRanges(CustomTable table, Dice dice, String title) {
  final n = parseDiceNotation(table.dice);
  final notation = n ?? const DiceNotation(1, 100);
  final v = rollNotation(notation, dice);
  final label = n == null
      ? 'd100'
      : table.dice.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  for (final r in table.rows) {
    final lo = r.min;
    final hi = r.max ?? r.min;
    if (lo != null && hi != null && v >= lo && v <= hi) {
      return GenResult(title: title, rolls: [
        Roll(label: 'Result', value: _value(r.text), detail: '$label → $v'),
      ]);
    }
  }
  return GenResult(title: title, rolls: [
    Roll(label: 'Result', value: '(no result)', detail: '$label → $v'),
  ]);
}

/// Parse the editor textarea into rows for [mode].
List<CustomRow> parseRows(String text, TableRoll mode) {
  final lines =
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
  return switch (mode) {
    TableRoll.uniform => [for (final l in lines) CustomRow(l)],
    TableRoll.weighted => [for (final l in lines) _parseWeightedLine(l)],
    TableRoll.ranges => [for (final l in lines) _parseRangeLine(l)],
  };
}

CustomRow _parseWeightedLine(String line) {
  // The LAST `|` separates the weight, so text keeps everything before the final
  // bar (e.g. `Heads | Tails` treats `Tails` as a non-numeric → 1 weight).
  final i = line.lastIndexOf('|');
  if (i < 0) return CustomRow(line);
  final text = line.substring(0, i).trim();
  final w = int.tryParse(line.substring(i + 1).trim()) ?? 1;
  return CustomRow(text.isEmpty ? line : text, weight: w < 1 ? 1 : w);
}

// Requires whitespace between the span and the text (e.g. `1-10 Goblin`, not
// `1-10Goblin`); a missing space silently yields a span-less text row.
final _rangeLineRe = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?\s+(.*)$');

CustomRow _parseRangeLine(String line) {
  final m = _rangeLineRe.firstMatch(line);
  if (m == null) return CustomRow(line);
  final lo = int.parse(m.group(1)!);
  final hi = m.group(2) != null ? int.parse(m.group(2)!) : lo;
  return CustomRow(m.group(3)!.trim(), min: lo, max: hi);
}

/// Serialize [rows] back to the editor textarea syntax for [mode].
String rowsToText(List<CustomRow> rows, TableRoll mode) => switch (mode) {
      TableRoll.uniform => rows.map((r) => r.text).join('\n'),
      TableRoll.weighted => rows
          .map((r) => r.weight == 1 ? r.text : '${r.text} | ${r.weight}')
          .join('\n'),
      TableRoll.ranges => rows.map((r) {
          final lo = r.min;
          final hi = r.max;
          if (lo == null) return r.text;
          final span = (hi == null || hi == lo) ? '$lo' : '$lo-$hi';
          return '$span ${r.text}';
        }).join('\n'),
    };
