/// Tolerant, lossy parser: a Lonelog `.md` document into juice campaign data.
/// Pure — no Flutter, no clock (timestamps derive from [importedAt]). The
/// inverse of lonelog_export.dart. Unrecognized lines are ignored.
library;

import 'models.dart';

/// Parsed campaign data ready to write into a new session's stores.
class LonelogImport {
  const LonelogImport({
    required this.campaignName,
    required this.genre,
    required this.tone,
    required this.threads,
    required this.characters,
    required this.tracks,
    required this.entries,
  });
  final String campaignName;
  final String genre;
  final String tone;
  final List<Thread> threads;
  final List<Character> characters;
  final List<Track> tracks;
  final List<JournalEntry> entries; // newest-first (juice convention)
}

final _sceneRe = RegExp(r'^###\s+S\d+\s+(.*?)\s*$');
final _chaosRe = RegExp(r'^\(note:\s*Chaos\s+(\d+)\)$');
final _threadRe = RegExp(r'^\[Thread:(.*)\|(Open|Closed)\]$');
final _trackRe = RegExp(r'^\[Track:(.*)\s(\d+)/(\d+)\]$');
final _npcRe = RegExp(r'^\[N:([^|\]]*)(?:\|(.*))?\]$');

LonelogImport parseLonelog(String md, {required DateTime importedAt}) {
  final lines = md.split('\n');
  var i = 0;

  var campaignName = 'Imported Lonelog';
  var genre = '';
  var tone = '';
  if (i < lines.length && lines[i].trim() == '---') {
    i++;
    while (i < lines.length && lines[i].trim() != '---') {
      final line = lines[i];
      final colon = line.indexOf(':');
      if (colon > 0) {
        final key = line.substring(0, colon).trim();
        final val = _unquote(line.substring(colon + 1).trim());
        switch (key) {
          case 'title':
            if (val.isNotEmpty) campaignName = val;
          case 'genre':
            genre = val;
          case 'tone':
            tone = val;
        }
      }
      i++;
    }
    if (i < lines.length) i++; // skip the closing ---
  }

  final threads = <Thread>[];
  final characters = <Character>[];
  final tracks = <Track>[];
  final entries = <JournalEntry>[];
  final beat = <String>[];
  var inState = false;

  void flushBeat() {
    final body = beat.join('\n').trim();
    beat.clear();
    if (body.isEmpty || body == '(note: empty journal)') return;
    entries.add(JournalEntry(
      id: 'll-entry-${entries.length}',
      timestamp: importedAt.add(Duration(seconds: entries.length)),
      title: '',
      body: body,
      kind: JournalKind.text,
    ));
  }

  while (i < lines.length) {
    final line = lines[i].trim();

    if (line == '[STATE]') {
      inState = true;
      i++;
      continue;
    }
    if (line == '[/STATE]') {
      inState = false;
      i++;
      continue;
    }
    if (inState) {
      _parseTag(line, threads, characters, tracks);
      i++;
      continue;
    }
    if (line == '## Session log' || line.isEmpty) {
      flushBeat();
      i++;
      continue;
    }

    final sm = _sceneRe.firstMatch(line);
    if (sm != null) {
      flushBeat();
      var title = sm.group(1)!.trim();
      if (title.length >= 2 && title.startsWith('*') && title.endsWith('*')) {
        title = title.substring(1, title.length - 1).trim();
      }
      int? chaos;
      if (i + 1 < lines.length) {
        final cm = _chaosRe.firstMatch(lines[i + 1].trim());
        if (cm != null) {
          chaos = int.parse(cm.group(1)!);
          i++; // consume the chaos note line
        }
      }
      entries.add(JournalEntry(
        id: 'll-entry-${entries.length}',
        timestamp: importedAt.add(Duration(seconds: entries.length)),
        title: title,
        body: '',
        kind: JournalKind.scene,
        chaosFactor: chaos,
      ));
      i++;
      continue;
    }

    beat.add(lines[i]); // accumulate the raw line (preserve indentation)
    i++;
  }
  flushBeat();

  return LonelogImport(
    campaignName: campaignName,
    genre: genre,
    tone: tone,
    threads: threads,
    characters: characters,
    tracks: tracks,
    entries: entries.reversed.toList(), // newest-first
  );
}

void _parseTag(String line, List<Thread> threads, List<Character> characters,
    List<Track> tracks) {
  final th = _threadRe.firstMatch(line);
  if (th != null) {
    threads.add(Thread(
      id: 'll-thread-${threads.length}',
      title: th.group(1)!.trim(),
      open: th.group(2) == 'Open',
    ));
    return;
  }
  final tr = _trackRe.firstMatch(line);
  if (tr != null) {
    tracks.add(Track(
      id: 'll-track-${tracks.length}',
      name: tr.group(1)!.trim(),
      filled: int.parse(tr.group(2)!),
      max: int.parse(tr.group(3)!),
    ));
    return;
  }
  final n = _npcRe.firstMatch(line);
  if (n != null) {
    final tags = (n.group(2) ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    characters.add(Character(
      id: 'll-char-${characters.length}',
      name: n.group(1)!.trim(),
      tags: tags,
    ));
  }
}

/// Reverse the exporter's `_yaml` quoting: strip one pair of surrounding `"`
/// and unescape `\"` / `\\`.
String _unquote(String s) {
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    return s
        .substring(1, s.length - 1)
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\');
  }
  return s;
}
