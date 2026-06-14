/// Lonelog Cards addon: expand a compact card token (`Qs`, `M16r`, `ACu`) to a
/// human-readable name. Pure; returns null for an unrecognized token. The Cards
/// addon is recording vocabulary (the player supplies the physical card), so
/// this parser is the faithful implementation.
library;

const _suits = {'h': 'Hearts', 'd': 'Diamonds', 'c': 'Clubs', 's': 'Spades'};
const _tarotSuits = {
  'Wa': 'Wands',
  'Cu': 'Cups',
  'Sw': 'Swords',
  'Pe': 'Pentacles',
};
const _ranks = {
  'A': 'Ace',
  '2': 'Two',
  '3': 'Three',
  '4': 'Four',
  '5': 'Five',
  '6': 'Six',
  '7': 'Seven',
  '8': 'Eight',
  '9': 'Nine',
  '10': 'Ten',
  'J': 'Jack',
  'Q': 'Queen',
  'K': 'King',
  'Pg': 'Page',
  'Kn': 'Knight',
};

/// Rider-Waite-Smith Major Arcana, indexed 0..21.
const kMajorArcana = [
  'The Fool',
  'The Magician',
  'The High Priestess',
  'The Empress',
  'The Emperor',
  'The Hierophant',
  'The Lovers',
  'The Chariot',
  'Strength',
  'The Hermit',
  'Wheel of Fortune',
  'Justice',
  'The Hanged Man',
  'Death',
  'Temperance',
  'The Devil',
  'The Tower',
  'The Star',
  'The Moon',
  'The Sun',
  'Judgement',
  'The World',
];

/// Expand [token] to a card name, or null if it isn't a recognized token.
/// A trailing `r` marks a reversed (tarot) card.
String? cardName(String token) {
  var t = token.trim();
  if (t.isEmpty) return null;
  switch (t) {
    case 'Jkr':
      return 'Joker';
    case 'RJkr':
      return 'Red Joker';
    case 'BJkr':
      return 'Black Joker';
    case 'R':
      return 'Red';
    case 'B':
      return 'Black';
  }
  // A trailing `r` is reversed only when the remainder is itself a card (no
  // card suit ends in `r`, so this is unambiguous).
  var reversed = false;
  if (t.length > 1 && t.endsWith('r')) {
    final base = t.substring(0, t.length - 1);
    if (_upright(base) != null) {
      reversed = true;
      t = base;
    }
  }
  final name = _upright(t);
  if (name == null) return null;
  return reversed ? '$name (reversed)' : name;
}

String? _upright(String t) {
  // Major arcana: M<n>.
  if (t.startsWith('M') && t.length > 1) {
    final n = int.tryParse(t.substring(1));
    if (n != null && n >= 0 && n < kMajorArcana.length) return kMajorArcana[n];
    return null;
  }
  // Tarot minor (2-char suit) takes precedence over standard suits.
  for (final entry in _tarotSuits.entries) {
    if (t.endsWith(entry.key)) {
      final rank = _ranks[t.substring(0, t.length - entry.key.length)];
      if (rank != null) return '$rank of ${entry.value}';
    }
  }
  // Standard playing card (1-char suit).
  final suit = _suits[t.substring(t.length - 1)];
  if (suit != null) {
    final rank = _ranks[t.substring(0, t.length - 1)];
    if (rank != null) return '$rank of $suit';
  }
  return null;
}
