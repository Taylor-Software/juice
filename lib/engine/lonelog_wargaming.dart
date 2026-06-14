/// Serializes a wargame unit roster as a Lonelog Wargaming-addon `[BATTLE]`
/// block for the journal (highlighted by P3). Pure — no Flutter. Each unit is a
/// `[Unit:Name|size|status]` tag.
library;

import 'models.dart';

String battleToLonelog(List<Unit> units) {
  final buf = StringBuffer('[BATTLE]');
  for (final u in units) {
    final fields = [
      if (u.size.trim().isNotEmpty) u.size.trim(),
      if (u.status.trim().isNotEmpty) u.status.trim(),
    ];
    final name = _t(u.name);
    buf.write(fields.isEmpty
        ? '\n[Unit:$name]'
        : '\n[Unit:$name|${fields.map(_t).join('|')}]');
  }
  buf.write('\n[/BATTLE]');
  return buf.toString();
}

/// Safe as a single `[Unit:…]` field value: replace the bracket and pipe
/// delimiters so only the intended field separators remain.
String _t(String s) => s
    .replaceAll('\n', ' ')
    .replaceAll('[', '(')
    .replaceAll(']', ')')
    .replaceAll('|', '/');
