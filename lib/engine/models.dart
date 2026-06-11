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

/// Kind of journal entry: player prose, a tool result, or a scene divider.
enum JournalKind { text, result, scene }

/// Persisted journal entry (formerly LogEntry; old JSON parses as `result`).
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.timestamp,
    required this.title,
    required this.body,
    this.threadId,
    this.kind = JournalKind.result,
    this.chaosFactor,
  });
  final String id;
  final DateTime timestamp;
  final String title;
  final String body;
  final String? threadId;
  final JournalKind kind;

  /// Chaos factor snapshot for scene dividers (Mythic), else null.
  final int? chaosFactor;

  JournalEntry copyWith({
    String? title,
    String? body,
    String? threadId,
    bool clearThreadId = false,
  }) =>
      JournalEntry(
        id: id,
        timestamp: timestamp,
        title: title ?? this.title,
        body: body ?? this.body,
        threadId: clearThreadId ? null : (threadId ?? this.threadId),
        kind: kind,
        chaosFactor: chaosFactor,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'title': title,
        'body': body,
        'threadId': threadId,
        'kind': kind.name,
        if (chaosFactor != null) 'chaosFactor': chaosFactor,
      };

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        title: j['title'] as String,
        body: j['body'] as String,
        threadId: j['threadId'] as String?,
        kind: JournalKind.values.asNameMap()[j['kind']] ?? JournalKind.result,
        chaosFactor: j['chaosFactor'] as int?,
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

/// Persisted crawl-mode state: wilderness position + NPC dialog marker.
class CrawlState {
  const CrawlState({
    this.envRow,
    this.lost = false,
    this.dialogRow = 2,
    this.dialogCol = 2,
    this.chaosFactor = 5,
  });

  /// Current wilderness environment row 1..10; null until first travel step.
  final int? envRow;

  /// Lost per the Juice Lost/Found cycle (encounter rolls drop to d6).
  final bool lost;

  /// NPC dialog marker on the 5x5 grid (center "Fact" = 2,2).
  final int dialogRow;
  final int dialogCol;

  /// Mythic GME 2e Chaos Factor (1..9, default 5).
  final int chaosFactor;

  CrawlState copyWith({
    int? envRow,
    bool clearEnvRow = false,
    bool? lost,
    int? dialogRow,
    int? dialogCol,
    int? chaosFactor,
  }) =>
      CrawlState(
        envRow: clearEnvRow ? null : (envRow ?? this.envRow),
        lost: lost ?? this.lost,
        dialogRow: dialogRow ?? this.dialogRow,
        dialogCol: dialogCol ?? this.dialogCol,
        chaosFactor: chaosFactor ?? this.chaosFactor,
      );

  Map<String, dynamic> toJson() => {
        'envRow': envRow,
        'lost': lost,
        'dialogRow': dialogRow,
        'dialogCol': dialogCol,
        'chaosFactor': chaosFactor,
      };

  factory CrawlState.fromJson(Map<String, dynamic> j) => CrawlState(
        envRow: j['envRow'] as int?,
        lost: (j['lost'] as bool?) ?? false,
        dialogRow: (j['dialogRow'] as int?) ?? 2,
        dialogCol: (j['dialogCol'] as int?) ?? 2,
        chaosFactor: (j['chaosFactor'] as int?) ?? 5,
      );
}

/// A campaign/session: an isolated set of threads, characters, log, crawl.
class SessionMeta {
  const SessionMeta({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory SessionMeta.fromJson(Map<String, dynamic> j) =>
      SessionMeta(id: j['id'] as String, name: j['name'] as String);
}

/// Registry of sessions plus the active one.
class SessionsState {
  const SessionsState({required this.active, required this.sessions});
  final String active;
  final List<SessionMeta> sessions;

  SessionMeta get activeMeta => sessions.firstWhere(
        (s) => s.id == active,
        orElse: () => sessions.first,
      );

  Map<String, dynamic> toJson() => {
        'active': active,
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };

  factory SessionsState.fromJson(Map<String, dynamic> j) => SessionsState(
        active: j['active'] as String,
        sessions: (j['sessions'] as List)
            .map((e) => SessionMeta.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
