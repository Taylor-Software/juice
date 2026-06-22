import 'dice.dart';
import 'models.dart';

/// Dice-notation engine: parses expressions like `4d6kh3+2`, `d20adv`,
/// `2d6+1d8-1`, `d%`, `4dF` and evaluates them against a [Dice] source.
///
/// Grammar (case-insensitive, whitespace allowed between tokens):
///
///     expr   := sign? term (('+'|'-') term)*
///     term   := dice | INT
///     dice   := INT? 'd' (INT | '%' | 'f') suffix?
///     suffix := ('kh'|'kl'|'dh'|'dl') INT | 'adv' | 'dis'
///
/// Errors throw [FormatException] with a message containing `position N`
/// (0-based index into the original input). Syntax errors anchor where the
/// expected token should start; semantic errors anchor at the start of the
/// offending token.

/// One physical die in a rolled group.
class RolledDie {
  const RolledDie(
      {required this.value, required this.kept, required this.display});

  /// Face value (for dF: -1, 0, or +1).
  final int value;

  /// False when dropped by a keep/drop suffix.
  final bool kept;

  /// Display string: '4'; for dF: '+', '−', or '0'.
  final String display;
}

/// One term of the expression after rolling: a dice group or a flat modifier.
class RolledGroup {
  const RolledGroup(
      {required this.label,
      required this.sign,
      required this.dice,
      required this.subtotal});

  /// Normalized label. Dice groups exclude their sign ('4d6kh3'); modifier
  /// groups include it ('+3', '-2').
  final String label;

  /// +1 or -1.
  final int sign;

  /// Rolled dice in roll order; empty for modifier groups.
  final List<RolledDie> dice;

  /// Unsigned kept-sum (may be negative for dF groups) or modifier magnitude.
  final int subtotal;
}

/// Result of evaluating a parsed expression.
class DiceRollResult {
  const DiceRollResult(
      {required this.expression, required this.total, required this.groups});

  /// Normalized whole expression, e.g. '4d6kh3+2'.
  final String expression;

  final int total;
  final List<RolledGroup> groups;

  /// Journal rendering, e.g.:
  ///
  ///     4d6kh3+2 = 15
  ///     4d6kh3: [1], 4, 6, 3 (13)
  ///     +2
  ///
  /// Dropped dice are bracketed.
  String get asText {
    final b = StringBuffer('$expression = $total');
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      b.write('\n');
      if (g.dice.isEmpty) {
        b.write(g.label);
      } else {
        if (g.sign < 0) {
          b.write('-');
        } else if (i > 0) {
          b.write('+');
        }
        b
          ..write(g.label)
          ..write(': ')
          ..write(g.dice
              .map((d) => d.kept ? d.display : '[${d.display}]')
              .join(', '))
          ..write(' (${g.subtotal})');
      }
    }
    return b.toString();
  }
}

/// Parses [input]; throws [FormatException] on invalid notation.
DiceExpression parseDice(String input) => _Parser(input).parse();

/// A parsed, normalized dice expression ready to roll.
class DiceExpression {
  DiceExpression._(this._terms);
  final List<_Term> _terms;

  /// Canonical form: lowercase, no spaces, counts explicit only when >1,
  /// adv/dis desugared ('d20adv' -> '2d20kh1'), '%' -> 'd100', fate -> 'dF'.
  String get normalized {
    final b = StringBuffer();
    for (var i = 0; i < _terms.length; i++) {
      final t = _terms[i];
      if (t.sign < 0) {
        b.write('-');
      } else if (i > 0) {
        b.write('+');
      }
      b.write(t.bareLabel);
    }
    return b.toString();
  }

  DiceRollResult roll(Dice dice) {
    final groups = <RolledGroup>[];
    var total = 0;
    for (final t in _terms) {
      final group = switch (t) {
        _ModTerm() => RolledGroup(
            label: '${t.sign < 0 ? '-' : '+'}${t.value}',
            sign: t.sign,
            dice: const [],
            subtotal: t.value,
          ),
        _DiceTerm() => _rollDice(t, dice),
      };
      groups.add(group);
      total += group.sign * group.subtotal;
    }
    return DiceRollResult(expression: normalized, total: total, groups: groups);
  }

  RolledGroup _rollDice(_DiceTerm t, Dice dice) {
    final values = [
      for (var i = 0; i < t.count; i++) t.fate ? dice.fate() : dice.dN(t.sides)
    ];
    // Exploding ('!'): a die showing the max re-rolls and is appended; the new
    // die can itself explode. Runs BEFORE keep (spec modifier order). Guarded
    // against runaway loops. Not applicable to dF.
    if (t.explode && !t.fate) {
      var idx = 0;
      var guard = 0;
      while (idx < values.length && guard < 1000) {
        if (values[idx] == t.sides) values.add(dice.dN(t.sides));
        idx++;
        guard++;
      }
    }
    final n = values.length;
    final kept = List<bool>.filled(n, true);
    final k = t.keep;
    if (k != null) {
      // Normalize to "drop m highest/lowest"; ties drop later-rolled dice
      // (i.e. prefer keeping earlier-rolled dice).
      final dropHighest = k.op == 'dh' || k.op == 'kl';
      final dropCount = (k.op.startsWith('d') ? k.n : n - k.n).clamp(0, n);
      final order = List<int>.generate(n, (i) => i)
        ..sort((a, b) {
          if (values[a] != values[b]) {
            return dropHighest ? values[b] - values[a] : values[a] - values[b];
          }
          return b - a; // later index drops first
        });
      for (final i in order.take(dropCount)) {
        kept[i] = false;
      }
    }
    var subtotal = 0;
    for (var i = 0; i < n; i++) {
      if (kept[i]) subtotal += values[i];
    }
    return RolledGroup(
      label: t.bareLabel,
      sign: t.sign,
      dice: [
        for (var i = 0; i < n; i++)
          RolledDie(
              value: values[i],
              kept: kept[i],
              display: _display(values[i], t.fate)),
      ],
      subtotal: subtotal,
    );
  }

  static String _display(int value, bool fate) {
    if (!fate) return '$value';
    return switch (value) { 1 => '+', -1 => '−', _ => '0' };
  }
}

// ---------------------------------------------------------------------------
// Internal AST
// ---------------------------------------------------------------------------

sealed class _Term {
  _Term(this.sign);
  final int sign;
  String get bareLabel;
}

class _ModTerm extends _Term {
  _ModTerm(super.sign, this.value);
  final int value;
  @override
  String get bareLabel => '$value';
}

class _Keep {
  _Keep(this.op, this.n);
  final String op; // 'kh' | 'kl' | 'dh' | 'dl'
  final int n;
}

class _DiceTerm extends _Term {
  _DiceTerm(super.sign, this.count, this.sides,
      {required this.fate, this.keep, this.explode = false});
  final int count;
  final int sides; // unused when fate
  final bool fate;
  final _Keep? keep;
  final bool
      explode; // '!' — a die at max re-rolls and adds (Lonelog Dice addon)
  @override
  String get bareLabel {
    final c = count > 1 ? '$count' : '';
    final s = fate ? 'F' : '$sides';
    final k = keep == null ? '' : '${keep!.op}${keep!.n}';
    return '${c}d$s$k${explode ? '!' : ''}';
  }
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class _Parser {
  _Parser(this.src);
  final String src;
  int pos = 0;

  Never _fail(int at, String what) =>
      throw FormatException('Invalid dice expression: $what (position $at)');

  void _ws() {
    while (pos < src.length && src[pos].trim().isEmpty) {
      pos++;
    }
  }

  bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }

  bool _isLetter(String c) {
    final u = c.toLowerCase().codeUnitAt(0);
    return u >= 0x61 && u <= 0x7a;
  }

  int _int() {
    final start = pos;
    while (pos < src.length && _isDigit(src[pos])) {
      pos++;
    }
    return int.tryParse(src.substring(start, pos)) ??
        _fail(start, 'number too large');
  }

  DiceExpression parse() {
    _ws();
    var sign = 1;
    if (pos < src.length && (src[pos] == '+' || src[pos] == '-')) {
      if (src[pos] == '-') sign = -1;
      pos++;
    }
    final terms = <_Term>[_term(sign)];
    while (true) {
      _ws();
      if (pos >= src.length) break;
      final c = src[pos];
      if (c != '+' && c != '-') {
        _fail(pos, "expected '+', '-', or end of input");
      }
      pos++;
      terms.add(_term(c == '-' ? -1 : 1));
    }
    return DiceExpression._(terms);
  }

  _Term _term(int sign) {
    _ws();
    if (pos >= src.length) _fail(pos, 'expected a number or die (e.g. 2d6)');
    final c = src[pos];
    if (_isDigit(c)) {
      final intStart = pos;
      final n = _int();
      _ws();
      if (pos < src.length && (src[pos] == 'd' || src[pos] == 'D')) {
        return _dice(sign, count: n, countStart: intStart, explicitCount: true);
      }
      return _ModTerm(sign, n);
    }
    if (c == 'd' || c == 'D') {
      return _dice(sign, count: 1, countStart: pos, explicitCount: false);
    }
    _fail(pos, 'expected a number or die (e.g. 2d6)');
  }

  /// [pos] is at the 'd' on entry.
  _DiceTerm _dice(int sign,
      {required int count,
      required int countStart,
      required bool explicitCount}) {
    if (explicitCount && (count < 1 || count > 100)) {
      _fail(countStart, 'dice count must be 1-100');
    }
    pos++; // consume 'd'
    _ws();
    final sidesStart = pos;
    var fate = false;
    var sides = 0;
    if (pos >= src.length) {
      _fail(pos, "expected die sides (a number, '%', or 'F')");
    } else if (_isDigit(src[pos])) {
      sides = _int();
      if (sides < 2 || sides > 1000) _fail(sidesStart, 'sides must be 2-1000');
    } else if (src[pos] == '%') {
      pos++;
      sides = 100;
    } else if (src[pos].toLowerCase() == 'f') {
      pos++;
      fate = true;
    } else {
      _fail(pos, "expected die sides (a number, '%', or 'F')");
    }

    _ws();
    // Leading explode ('5d10!' or '5d10!kh2'). Not for dF.
    var explode = false;
    if (!fate && pos < src.length && src[pos] == '!') {
      explode = true;
      pos++;
      _ws();
    }

    _Keep? keep;
    var rolled = count;
    if (pos < src.length && _isLetter(src[pos])) {
      final sufStart = pos;
      final rest = src.substring(pos).toLowerCase();
      if (rest.startsWith('adv') || rest.startsWith('dis')) {
        if (explicitCount && count != 1) {
          _fail(sufStart, "'adv'/'dis' requires a single die");
        }
        pos += 3;
        keep = _Keep(rest.startsWith('adv') ? 'kh' : 'kl', 1);
        rolled = 2;
      } else {
        const ops = ['kh', 'kl', 'dh', 'dl'];
        if (rest.length >= 2 && ops.contains(rest.substring(0, 2))) {
          final op = rest.substring(0, 2);
          pos += 2;
          _ws();
          if (pos >= src.length || !_isDigit(src[pos])) {
            _fail(pos, 'expected a number after $op');
          }
          final n = _int();
          if (op.startsWith('k')) {
            if (n < 1 || n > count) {
              _fail(sufStart, 'keep must be 1-$count for $count dice');
            }
          } else {
            if (n < 1 || n > count - 1) {
              _fail(sufStart, 'drop must be 1-${count - 1} for $count dice');
            }
          }
          keep = _Keep(op, n);
        } else {
          _fail(sufStart,
              "unknown suffix (expected kh/kl/dh/dl N, 'adv', 'dis', or '!')");
        }
      }
    }

    // Trailing explode ('5d10kh2!').
    _ws();
    if (!fate && !explode && pos < src.length && src[pos] == '!') {
      explode = true;
      pos++;
    }

    return _DiceTerm(sign, rolled, sides,
        fate: fate, keep: keep, explode: explode);
  }
}

/// The journal [GenResult] for a dice roll — title/summary/per-group rolls.
/// Shared by the dice roller and the journal reroll so both stay identical.
GenResult diceRollGenResult(DiceRollResult r) => GenResult(
      title: 'Dice Roll',
      summary: '${r.expression} = ${r.total}',
      rolls: [
        for (final g in r.groups)
          if (g.dice.isNotEmpty)
            Roll(
              label: g.label,
              value: g.dice
                  .map((d) => d.kept ? d.display : '[${d.display}]')
                  .join(', '),
              detail: '${g.subtotal}',
            ),
      ],
    );
