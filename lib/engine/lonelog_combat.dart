/// Serializes a juice encounter as a Lonelog Combat-addon `[COMBAT]` block for
/// the journal (so it renders highlighted when the lonelog system is on).
/// Pure — no Flutter. Combatants render as `[F:]` foe tags (HP + statuses),
/// with the outcome on a `=>` line.
library;

import 'models.dart';

String encounterToLonelog(EncounterState s) {
  final buf = StringBuffer('[COMBAT]')..write('\nRd${s.round} Roster:');
  for (final c in s.combatants) {
    final parts = <String>[
      if (c.track != null) 'HP ${c.track!.current}/${c.track!.max}',
      ...c.tags.where((t) => t.trim().isNotEmpty),
      if (c.defeated) 'defeated',
    ];
    final name = _t(c.name);
    buf.write(parts.isEmpty
        ? ' [F:$name]'
        : ' [F:$name|${parts.map(_t).join(', ')}]');
  }
  final defeated = [
    for (final c in s.combatants)
      if (c.defeated) c.name,
  ];
  buf.write('\n=> ${defeated.isEmpty //
      ? 'no combatants defeated' : 'defeated: ${defeated.join(', ')}'}');
  buf.write('\n[/COMBAT]');
  return buf.toString();
}

/// Safe inside a `[F:…|…]` tag: replace the bracket and pipe delimiters.
String _t(String s) => s
    .replaceAll('\n', ' ')
    .replaceAll('[', '(')
    .replaceAll(']', ')')
    .replaceAll('|', '/');
