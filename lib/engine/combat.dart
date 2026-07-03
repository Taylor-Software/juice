// lib/engine/combat.dart
//
// Pure combat-resolution helpers for the Encounter screen's attacker→target
// flow. No Flutter, no models — just the hit/miss rule and the journal log line.
// The dice roll (attack + damage) is done by the caller via parseDice; this file
// only decides hit/miss against a recorded AC and formats the log entry. The
// attackDiceFromDetail helper additionally scans a freeform attack detail for
// its dice via dice_scan (still pure — no Flutter, no models).

import 'dice_scan.dart';

/// Whether an attack lands. [unknown] means the target has no recorded AC
/// (`StatBlock.ac == 0`), so the GM decides Hit/Miss manually.
enum AttackOutcome { hit, miss, unknown }

/// Hit determination: an attack [attackTotal] meets or beats [targetAc]. A
/// non-positive [targetAc] means no AC is recorded → [AttackOutcome.unknown].
AttackOutcome resolveHit(int attackTotal, int targetAc) {
  if (targetAc <= 0) return AttackOutcome.unknown;
  return attackTotal >= targetAc ? AttackOutcome.hit : AttackOutcome.miss;
}

/// One-line combat log entry for the journal, e.g.
/// `Goblin → Mira: 18 vs AC 15 — Hit, 7 dmg (Mira 12→5)`.
///
/// - [targetAc] `<= 0` drops the `vs AC N` clause.
/// - [damage] null (a miss, or no damage rolled) drops the `, N dmg` clause.
/// - [hp] null (target has no HP pool) drops the `(target before→after)` clause.
String combatLogLine({
  required String attacker,
  required String target,
  required int attackTotal,
  required int targetAc,
  required bool hit,
  int? damage,
  (int, int)? hp,
}) {
  final ac = targetAc > 0 ? ' vs AC $targetAc' : '';
  if (!hit) return '$attacker → $target: $attackTotal$ac — Miss';
  final dmg = damage != null ? ', $damage dmg' : '';
  final pool = hp != null ? ' ($target ${hp.$1}→${hp.$2})' : '';
  return '$attacker → $target: $attackTotal$ac — Hit$dmg$pool';
}

/// Best-effort extraction of the attack and damage dice from a freeform
/// stat-block attack [detail]. Uses [scanDice], which returns only validated
/// dice notations (a bare "+4" is not a die and is ignored). The first token
/// containing "d20" is the attack roll; the first remaining token is the
/// damage. Either may be null when the detail has no matching token.
({String? attack, String? damage}) attackDiceFromDetail(String detail) {
  final toks = scanDice(detail).map((s) => s.notation).toList();
  String? attack;
  for (final t in toks) {
    if (t.toLowerCase().contains('d20')) {
      attack = t;
      break;
    }
  }
  String? damage;
  for (final t in toks) {
    if (t != attack) {
      damage = t;
      break;
    }
  }
  return (attack: attack, damage: damage);
}
