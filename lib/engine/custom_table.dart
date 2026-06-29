/// Pure model + roll logic for user-authored random tables.
/// No Flutter imports — unit-tested without a widget harness.
library;

import 'dice.dart';
import 'models.dart';

/// A user-authored random table: a flat list of row strings rolled uniformly.
class CustomTable {
  const CustomTable({required this.id, required this.name, required this.rows});

  final String id;
  final String name;
  final List<String> rows;

  CustomTable copyWith({String? name, List<String>? rows}) => CustomTable(
        id: id,
        name: name ?? this.name,
        rows: rows ?? this.rows,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'rows': rows};

  factory CustomTable.fromJson(Map<String, dynamic> j) => CustomTable(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        rows: [
          for (final r in (j['rows'] as List? ?? const []))
            if (r is String) r
        ],
      );

  /// Tolerant decode for persistence: returns null when [raw] is not a map or
  /// lacks an id.
  static CustomTable? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    if (map['id'] is! String) return null;
    return CustomTable.fromJson(map);
  }
}

/// Roll [table]: uniformly pick one row and return it as a one-roll [GenResult].
/// An empty table yields a placeholder roll so the UI never has to special-case.
GenResult rollCustomTable(CustomTable table, Dice dice) {
  if (table.rows.isEmpty) {
    return GenResult(
        title: table.name.isEmpty ? 'Table' : table.name,
        rolls: const [Roll(label: 'Result', value: '(empty table)')]);
  }
  final n = table.rows.length;
  final idx = dice.dN(n); // 1..n
  return GenResult(
    title: table.name.isEmpty ? 'Table' : table.name,
    rolls: [
      Roll(label: 'Result', value: table.rows[idx - 1], detail: 'd$n → $idx')
    ],
  );
}
