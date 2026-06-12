import 'dice.dart';
import 'emulator_data.dart';

/// A d66 roll: two d6 read as tens then units (key 11..66).
class D66Result {
  const D66Result(this.tens, this.units);
  final int tens;
  final int units;
  int get key => tens * 10 + units;
}

/// Roll a d66 (first die = tens, second = units).
D66Result rollD66(Dice dice) => D66Result(dice.dN(6), dice.dN(6));

/// One behavior-table roll: which table, the d66 key, and the cell text.
class TableRollResult {
  const TableRollResult(
      {required this.table, required this.key, required this.text});
  final String table;
  final int key;
  final String text;
}

/// Roll d66 on a named spark/specific table and look up the entry.
TableRollResult rollBehavior(EmulatorData data, String table, Dice dice) {
  final key = rollD66(dice).key;
  return TableRollResult(
      table: table, key: key, text: data.d66Entry(table, key));
}

/// Roll each named table in order (the zine's spark combos, e.g.
/// Action + Focus).
List<TableRollResult> rollCombo(
        EmulatorData data, List<String> tables, Dice dice) =>
    [for (final t in tables) rollBehavior(data, t, dice)];

// -- Triple-O check ----------------------------------------------------------

/// The three courses of action of a Triple-O check.
enum TripleOBand { obvious, option, odd }

extension TripleOBandLabel on TripleOBand {
  String get label => switch (this) {
        TripleOBand.obvious => 'The Obvious',
        TripleOBand.option => 'The Option',
        TripleOBand.odd => 'The Odd',
      };
}

/// Band for one d6, per the zine: 4-6 the Obvious, 2-3 the Option, 1 the Odd.
TripleOBand bandFor(int d6) => switch (d6) {
      >= 4 => TripleOBand.obvious,
      >= 2 => TripleOBand.option,
      _ => TripleOBand.odd,
    };

/// A Triple-O check roll: either a single die (band decided) or a
/// double-down pair (the USER picks the favorite die in the UI, so the
/// engine decides no band; [isDoubles] flags trait growth).
class TripleOResult {
  const TripleOResult.single(int this.die) : dice = null;
  const TripleOResult.doubleDown((int, int) this.dice) : die = null;

  /// The single check die; null for double-down.
  final int? die;

  /// Both double-down dice; null for a single roll.
  final (int, int)? dice;

  /// Matching double-down dice grow the behavior into a Trait.
  bool get isDoubles => dice != null && dice!.$1 == dice!.$2;

  /// Decided band — non-null only for a single roll.
  TripleOBand? get band => die == null ? null : bandFor(die!);
}

/// Single-die Triple-O check.
TripleOResult rollTripleO(Dice dice) => TripleOResult.single(dice.dN(6));

/// Double-down: 2d6, favorite die picked by the player afterwards.
TripleOResult rollDoubleDown(Dice dice) =>
    TripleOResult.doubleDown((dice.dN(6), dice.dN(6)));

// -- PET (Player Emulator with Tags) -----------------------------------------

/// 2d6 curved roll for agenda/focus keys (the in-play method; the source's
/// flat-d12 creation variant is not surfaced in UI and is out of scope).
int roll2d6Key(Dice dice) => dice.dN(6) + dice.dN(6);

/// How the modifier die layers guidance on the Ask.
enum ActMode { asWritten, inverted, exaggerated }

/// Guidance wording for an [ActMode].
String actModeLabel(ActMode m) => switch (m) {
      ActMode.asWritten => 'as written',
      ActMode.inverted => 'inverted',
      ActMode.exaggerated => 'exaggerated',
    };

/// One PET ACT roll. Combined reading per Pettish: the coin sets the base
/// reading of the Ask (heads = as written, tails = inverted); the modifier
/// die layers as-written/inverted/exaggerated guidance on top.
class ActResult {
  const ActResult({
    required this.agendaKey,
    required this.heads,
    required this.modifierDie,
  });

  /// Rolled agenda key, 2d6 (2..12).
  final int agendaKey;

  /// Coin: true = the Ask as written, false = inverted.
  final bool heads;

  /// Modifier d6: 1-2 asWritten, 3-4 inverted, 5-6 exaggerated.
  final int modifierDie;

  ActMode get modifier => switch (modifierDie) {
        <= 2 => ActMode.asWritten,
        <= 4 => ActMode.inverted,
        _ => ActMode.exaggerated,
      };
}

/// Roll ACT. Dice order (tests pin it): agenda 2d6 as two dN(6) calls,
/// then the coin as one dN(2) (1 = heads), then the modifier dN(6).
ActResult rollAct(Dice dice) => ActResult(
      agendaKey: roll2d6Key(dice),
      heads: dice.dN(2) == 1,
      modifierDie: dice.dN(6),
    );

// -- Sidekick dialogue --------------------------------------------------------

/// One Sidekick dialogue roll: the line key plus the tone/topic/said-how
/// chips. Per the source, matching line dice change the mood BEFORE the
/// line: a d6 picks the new mood and the line rerolls under it.
class DialogueResult {
  const DialogueResult({
    required this.dice,
    this.newMood,
    required this.lineKey,
    required this.toneIx,
    required this.topicIx,
    required this.saidHowAIx,
    required this.saidHowBIx,
  });

  /// The first 2d6 — doubles trigger the mood change.
  final (int, int) dice;

  /// Doubles changed the mood before the line was rolled.
  bool get moodChanged => newMood != null;

  /// The d6-picked mood id (over [kSidekickMoods]); null unless
  /// [moodChanged].
  final String? newMood;

  /// The (re)rolled 2d6 sum keying the dialogue line (2..12).
  final int lineKey;

  /// d6 chip indices (0..5) into tones / topics / saidHowA / saidHowB.
  final int toneIx;
  final int topicIx;
  final int saidHowAIx;
  final int saidHowBIx;
}

/// Roll one dialogue line. Dice order (tests pin it): 2d6 line → when
/// doubles: d6 mood + 2d6 reroll → d6 tone → d6 topic → d6 saidHowA →
/// d6 saidHowB.
DialogueResult rollDialogue(Dice dice) {
  final a = dice.dN(6), b = dice.dN(6);
  String? newMood;
  var lineKey = a + b;
  if (a == b) {
    newMood = kSidekickMoods[dice.dN(6) - 1];
    lineKey = dice.dN(6) + dice.dN(6);
  }
  return DialogueResult(
    dice: (a, b),
    newMood: newMood,
    lineKey: lineKey,
    toneIx: dice.dN(6) - 1,
    topicIx: dice.dN(6) - 1,
    saidHowAIx: dice.dN(6) - 1,
    saidHowBIx: dice.dN(6) - 1,
  );
}

/// Pure group assignment given the three course rolls: returns course
/// indices ordered [obvious, option, odd] = highest, middle, lowest roll.
/// Ties broken by earlier list position keeping its higher slot.
List<int> assignOrder(List<int> rolls) => [0, 1, 2]..sort((a, b) {
    final byRoll = rolls[b].compareTo(rolls[a]);
    return byRoll != 0 ? byRoll : a.compareTo(b);
  });

/// Group assignment: one d6 per course (in list order); see [assignOrder].
List<int> assignCourses(Dice dice) =>
    assignOrder([dice.dN(6), dice.dN(6), dice.dN(6)]);
