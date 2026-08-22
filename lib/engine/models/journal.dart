/// Journal entries, oracle results, and threads.
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

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
  String get shorthand =>
      '${_glyph(primary)}${_glyph(secondary)}$intensityRoll';

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

  /// Structured journal payload (spec: cycle4 living-journal §2).
  Map<String, dynamic> toPayload() => {
        'v': 1,
        if (summary != null) 'summary': summary,
        'rolls': [
          for (final r in rolls) {'label': r.label, 'display': r.display}
        ],
      };
}

/// Kind of journal entry: player prose, a tool result, a scene divider, or a
/// freehand sketch.
enum JournalKind { text, result, scene, sketch, session }

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
    this.tags = const [],
    this.sourceTool,
    this.payload,
    this.pinned = false,
    this.location,
  });
  final String id;
  final DateTime timestamp;
  final String title;
  final String body;
  final String? threadId;
  final JournalKind kind;

  /// Chaos factor snapshot for scene dividers (Mythic), else null.
  final int? chaosFactor;

  /// Player-applied tags; replaced wholesale via copyWith (pass `[]` to clear).
  final List<String> tags;

  /// Tool-registry id that produced this result (open-in-tool), else null.
  final String? sourceTool;

  /// Structured result payload (v1: summary/rolls/command/args/rerollable);
  /// null for prose and legacy entries. Tolerant: render falls back to flat
  /// text for unknown shapes.
  final Map<String, dynamic>? payload;

  /// Player-pinned flag (shows a ⚑ Pin action on result cards), default false.
  final bool pinned;

  /// The map location (hex or dungeon room) this entry was logged at, when
  /// the [PlayContext] spine had an active location at creation time. Null
  /// for entries logged with no location focus (and all legacy entries).
  final LocationRef? location;

  JournalEntry copyWith({
    String? title,
    String? body,
    String? threadId,
    bool clearThreadId = false,
    List<String>? tags,
    Map<String, dynamic>? payload,
    bool? pinned,
    LocationRef? location,
    bool clearLocation = false,
  }) =>
      JournalEntry(
        id: id,
        timestamp: timestamp,
        title: title ?? this.title,
        body: body ?? this.body,
        threadId: clearThreadId ? null : (threadId ?? this.threadId),
        kind: kind,
        chaosFactor: chaosFactor,
        tags: tags ?? this.tags,
        sourceTool: sourceTool,
        payload: payload ?? this.payload,
        pinned: pinned ?? this.pinned,
        location: clearLocation ? null : (location ?? this.location),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'title': title,
        'body': body,
        'threadId': threadId,
        'kind': kind.name,
        if (chaosFactor != null) 'chaosFactor': chaosFactor,
        'tags': tags,
        if (sourceTool != null) 'sourceTool': sourceTool,
        if (payload != null) 'payload': payload,
        'pinned': pinned,
        if (location != null) 'loc': location!.toJson(),
      };

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        title: j['title'] as String,
        body: j['body'] as String,
        threadId: j['threadId'] as String?,
        kind: JournalKind.values.asNameMap()[j['kind']] ?? JournalKind.result,
        chaosFactor: j['chaosFactor'] as int?,
        tags: ((j['tags'] as List?) ?? const []).whereType<String>().toList(),
        sourceTool: j['sourceTool'] as String?,
        payload: (j['payload'] as Map?)?.cast<String, dynamic>(),
        pinned: (j['pinned'] as bool?) ?? false,
        location: j['loc'] is Map
            ? LocationRef.fromJson(Map<String, dynamic>.from(j['loc'] as Map))
            : null,
      );
}

/// Lifecycle stage of a tracked thread. A rumor is an unconfirmed lead
/// (the old Rumor entity); active is a live storyline or clock (the old
/// Thread/Track); done is finished either way.
enum ThreadStage { rumor, active, done }

ThreadStage _threadStageFromJson(Map<String, dynamic> j) {
  switch (j['stage']) {
    case 'rumor':
      return ThreadStage.rumor;
    case 'done':
      return ThreadStage.done;
    case 'active':
      return ThreadStage.active;
  }
  // Legacy shape: an explicit open:false was a closed thread.
  return (j['open'] as bool?) == false ? ThreadStage.done : ThreadStage.active;
}

/// Persisted thread (Mythic-style "thread"/vow the player tracks).
class Thread {
  Thread({
    required this.id,
    required this.title,
    this.note = '',
    this.stage = ThreadStage.active,
    this.pinned = false,
    int progress = 0,
    int progressMax = 10,
    this.tally,
  })  : progressMax = progressMax < 1 ? 1 : progressMax,
        progress = progress.clamp(0, progressMax < 1 ? 1 : progressMax);
  final String id;
  final String title;
  final String note;
  final ThreadStage stage;

  /// Derived: true while the thread is not finished (rumor or active).
  bool get open => stage != ThreadStage.done;
  final bool pinned;

  /// Numeric progress clock (n/[progressMax]); always clamped into 0..max.
  final int progress;

  /// Clock denominator (default 10); always >= 1.
  final int progressMax;

  /// Optional bidirectional success/failure tally (Cairn-Solo style); null when
  /// this thread is a plain storyline. Distinct from the [progress] clock.
  final Tally? tally;

  Thread copyWith({
    String? title,
    String? note,
    ThreadStage? stage,
    bool? pinned,
    int? progress,
    int? progressMax,
    Tally? tally,
    bool clearTally = false,
  }) =>
      Thread(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        stage: stage ?? this.stage,
        pinned: pinned ?? this.pinned,
        progress: progress ?? this.progress,
        progressMax: progressMax ?? this.progressMax,
        tally: clearTally ? null : (tally ?? this.tally),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        if (stage != ThreadStage.active) 'stage': stage.name,
        if (pinned) 'pinned': true,
        if (progress > 0) 'progress': progress,
        if (progressMax != 10) 'progressMax': progressMax,
        if (tally != null) 'tally': tally!.toJson(),
      };

  factory Thread.fromJson(Map<String, dynamic> j) => Thread(
        id: j['id'] as String,
        title: j['title'] as String,
        note: (j['note'] as String?) ?? '',
        stage: _threadStageFromJson(j),
        pinned: (j['pinned'] as bool?) ?? false,
        progress: (j['progress'] as int?) ?? 0,
        progressMax: (j['progressMax'] as int?) ?? 10,
        tally:
            Tally.maybeFromJson((j['tally'] as Map?)?.cast<String, dynamic>()),
      );
}
