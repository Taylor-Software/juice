/// Plain immutable models for engine output and persisted state.
/// No freezed/codegen — the data is small and stable.

/// Likelihood applied to a Fate Check.
enum Likelihood { unlikely, normal, likely }

extension LikelihoodLabel on Likelihood {
  String get label => switch (this) {
        Likelihood.unlikely => 'Unlikely',
        Likelihood.normal => 'Normal',
        Likelihood.likely => 'Likely',
      };
  String get key => name; // 'unlikely' | 'normal' | 'likely'
}

/// Result of a Fate Check.
class FateResult {
  const FateResult({
    required this.primary,
    required this.secondary,
    required this.side,
    required this.intensityRoll,
    required this.intensity,
    required this.likelihood,
    required this.result,
  });

  final int primary; // -1, 0, +1
  final int secondary; // -1, 0, +1
  final String? side; // 'left' | 'right' for double-blank, else null
  final int intensityRoll; // 1..6
  final String intensity; // Minimal..Maximum
  final Likelihood likelihood;
  final String result; // e.g. "Yes But", "Invalid Assumption"

  static String _glyph(int v) => v > 0 ? '+' : (v < 0 ? '-' : '0');

  /// Shorthand like "+-4" (primary, secondary, intensity), per the PDF.
  String get shorthand => '${_glyph(primary)}${_glyph(secondary)}$intensityRoll';

  bool get isRandomEvent => result.contains('Random Event');
  bool get isInvalidAssumption => result == 'Invalid Assumption';
}

/// A single rolled table line ("Color: Crimson Red").
class Roll {
  const Roll({required this.label, required this.value, this.detail});
  final String label; // e.g. "Color"
  final String value; // e.g. "Crimson Red"
  final String? detail; // optional extra (e.g. die roll, intensity)

  String get display => detail == null ? value : '$value ($detail)';
}

/// A composite generator result: a titled group of rolls.
class GenResult {
  const GenResult({required this.title, required this.rolls, this.summary});
  final String title;
  final List<Roll> rolls;
  final String? summary; // optional one-line summary

  String get asText {
    final body = rolls.map((r) => '${r.label}: ${r.display}').join('\n');
    return summary == null ? body : '$summary\n$body';
  }
}

/// Persisted log entry.
class LogEntry {
  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.title,
    required this.body,
  });
  final String id;
  final DateTime timestamp;
  final String title;
  final String body;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'title': title,
        'body': body,
      };

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        title: j['title'] as String,
        body: j['body'] as String,
      );
}

/// Persisted thread (Mythic-style "thread"/vow the player tracks).
class Thread {
  const Thread({
    required this.id,
    required this.title,
    this.note = '',
    this.open = true,
  });
  final String id;
  final String title;
  final String note;
  final bool open;

  Thread copyWith({String? title, String? note, bool? open}) => Thread(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        open: open ?? this.open,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'note': note, 'open': open};

  factory Thread.fromJson(Map<String, dynamic> j) => Thread(
        id: j['id'] as String,
        title: j['title'] as String,
        note: (j['note'] as String?) ?? '',
        open: (j['open'] as bool?) ?? true,
      );
}

/// Persisted character/NPC the player tracks.
class Character {
  const Character({required this.id, required this.name, this.note = ''});
  final String id;
  final String name;
  final String note;

  Character copyWith({String? name, String? note}) =>
      Character(id: id, name: name ?? this.name, note: note ?? this.note);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'note': note};

  factory Character.fromJson(Map<String, dynamic> j) => Character(
        id: j['id'] as String,
        name: j['name'] as String,
        note: (j['note'] as String?) ?? '',
      );
}
