/// Rolls the H8 treasure table: d4 form + one row of the 18-row value ladder
/// at index `d10 + depth - 1 + bonus` (1-based, clamped), resolving embedded
/// `NdX(*k)` notation (e.g. "2D6*25 GP") to a concrete amount. Pure.
library;

import '../dice.dart';

final _dicePart = RegExp(r'^(\d*)[dD](\d+)(?:\*(\d+))?\s+(GP|SP)$');

String rollTreasure(Map<String, dynamic> h8,
    {required int depth, required int bonus, required Dice dice}) {
  // The asset emits form_d4 as a {"1".."4": form} dict; list fixtures also
  // accepted.
  final formsRaw = h8['form_d4'];
  final forms = formsRaw is List
      ? formsRaw
      : formsRaw is Map
          ? formsRaw.values.toList()
          : const [];
  final rows = (h8['d10_plus_level'] as List? ?? const []);
  if (rows.isEmpty) return 'Treasure';
  final form = forms.isEmpty ? '' : forms[dice.dN(forms.length) - 1].toString();
  final idx = (dice.dN(10) + depth - 1 + bonus).clamp(1, rows.length);
  final row = rows[idx - 1].toString();

  // Resolve each "&"-joined part's trailing "<dice> GP|SP"; artifact prefixes
  // and unparseable rows pass through verbatim.
  final parts = row.split('&').map((p) => p.trim()).toList();
  final resolved = <String>[];
  var numeric = false;
  for (final p in parts) {
    final m = _dicePart.firstMatch(p);
    if (m == null) {
      resolved.add(p);
      continue;
    }
    final n = int.tryParse(m.group(1) ?? '') ?? 1;
    final sides = int.parse(m.group(2)!);
    final mult = int.tryParse(m.group(3) ?? '') ?? 1;
    var total = 0;
    for (var i = 0; i < n; i++) {
      total += dice.dN(sides);
    }
    resolved.add('${total * mult} ${m.group(4)}');
    numeric = true;
  }
  final suffix = form.isEmpty ? row : '$row, $form';
  return numeric
      ? 'Treasure: ${resolved.join(' & ')} ($suffix)'
      : 'Treasure: $row${form.isEmpty ? '' : ' ($form)'}';
}
