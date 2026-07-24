// Codifies the machine-checkable rules from DESIGN.md as a source scan, so a
// drift lands as a red test instead of a review comment nobody makes.
//
// Only rules with an unambiguous mechanical test live here — DESIGN.md's
// judgement rules (the Rubrication Rule's "count the terracotta elements", the
// Two-Voice Rule) stay human. Each rule below cites its DESIGN.md section, and
// the carve-outs are the ones DESIGN.md itself states; widening one here means
// widening it there too.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `.dart` file under `lib/`, as (path, source).
List<(String, String)> _libSources() {
  final dir = Directory('lib');
  return [
    for (final f in dir.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart')) (f.path, f.readAsStringSync()),
  ];
}

/// `path:line` for every line matching [re], skipping files in [exempt].
List<String> _hits(
  RegExp re, {
  Set<String> exempt = const {},
}) {
  final out = <String>[];
  for (final (path, src) in _libSources()) {
    if (exempt.any(path.endsWith)) continue;
    final lines = src.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (re.hasMatch(lines[i])) out.add('$path:${i + 1}  ${lines[i].trim()}');
    }
  }
  return out;
}

void main() {
  // DESIGN.md → Elevation & Depth → The One Shadow Rule.
  // Depth is tonal. The expanded oracle result card holds the system's only
  // shadow; the primary-button lift is the one sanctioned addition (2 total).
  test('The One Shadow Rule: shadows stay countable', () {
    final hits = _hits(RegExp(r'BoxShadow\('));
    expect(
      hits.length,
      lessThanOrEqualTo(2),
      reason: 'DESIGN.md allows the answer lift and the primary lift only. '
          'Separate surfaces with a hairline or a tonal step instead.\n'
          '${hits.join('\n')}',
    );
  });

  // DESIGN.md → Colors → The Warm-Only Rule + The One Meaning Rule.
  // Material's stock palette is neither warm nor semantic here: status meaning
  // belongs to Quiet Sage / colorScheme.error, and neutrals to the ink ramp.
  //
  // Carve-outs, both stated in DESIGN.md:
  //  - `Colors.white` is allowed as an ON-ACCENT glyph fill (a 14px icon on a
  //    terracotta tile), never as a surface.
  //  - map_screen.dart's terrain hues and sketch_editor.dart's drawing palette
  //    are DATA and USER INK, not chrome — see The Cartography Exception.
  test('The Warm-Only Rule: no stock Material colors in chrome', () {
    final hits = _hits(
      RegExp(r'Colors\.(blue|blueGrey|indigo|teal|cyan|lightBlue|'
          r'green|lightGreen|red|orange|amber|yellow|purple|deepPurple|pink|'
          r'brown|grey|black)[A-Za-z0-9]*'),
      exempt: {'features/map_screen.dart', 'features/sketch_editor.dart'},
    );
    expect(
      hits,
      isEmpty,
      reason: 'Use JuiceTokens via context.juice (sage / inkFaint / hairline / '
          'terracotta) or a ColorScheme role. The palette is warm-only and '
          'each accent means exactly one thing.\n${hits.join('\n')}',
    );
  });

  // DESIGN.md → Typography → The Two-Voice Rule.
  // Serif is the story, sans is the machinery, and there is no third voice —
  // except notation, where glyph alignment is the content (Lonelog's symbol
  // legend). Anything else naming a family is a new voice sneaking in.
  test('The Two-Voice Rule: only the two families, plus notation', () {
    const allowed = {'Newsreader', 'HankenGrotesk', 'monospace'};
    final bad = <String>[];
    for (final (path, src) in _libSources()) {
      for (final m in RegExp(r"""fontFamily:\s*'([^']+)'""").allMatches(src)) {
        final family = m.group(1)!;
        if (!allowed.contains(family)) bad.add('$path  $family');
      }
    }
    expect(
      bad,
      isEmpty,
      reason: 'Newsreader for fiction, HankenGrotesk for machinery. '
          "'monospace' is reserved for notation legends.\n${bad.join('\n')}",
    );
  });

  // DESIGN.md → Colors → The Identity Spine (+ The Warm-Only Rule).
  // The five campaign identity hues are chrome, so they live inside the warm
  // family. "Warm" here is mechanical: the red channel leads the blue one.
  // The handoff's original Indigo (#4A5A8A) and Plum (#8A4A6A) both failed this.
  test('The Identity Spine stays inside the warm family', () {
    final src = File('lib/engine/models.dart').readAsStringSync();
    final block = RegExp(r'const kIdentityHues = <int>\[(.*?)\];', dotAll: true)
        .firstMatch(src);
    expect(block, isNotNull, reason: 'kIdentityHues not found in models.dart');
    final hues = RegExp(r'0x([0-9A-Fa-f]{8})')
        .allMatches(block!.group(1)!)
        .map((m) => int.parse(m.group(1)!, radix: 16))
        .toList();
    expect(hues, hasLength(5));
    for (final argb in hues) {
      final r = (argb >> 16) & 0xFF;
      final b = argb & 0xFF;
      expect(
        r,
        greaterThan(b),
        reason: 'Identity hue #${argb.toRadixString(16).substring(2)} is cool '
            '(red $r <= blue $b). Campaign spines are chrome, not cartography.',
      );
    }
  });

  // DESIGN.md → Colors → Hero Border, and Don'ts → "don't hard-code a hex
  // where a token exists". These two literals were the same border wearing two
  // values at four call sites, with no dark counterpart.
  test('The hero border is a token, not a literal', () {
    final hits = _hits(
      RegExp(r'0xFFEFC9B4|0xFFF0CDB8'),
      exempt: {'shared/design_tokens.dart'},
    );
    expect(
      hits,
      isEmpty,
      reason: 'Use tk.borderHero — it is the only value with a dark twin.\n'
          '${hits.join('\n')}',
    );
  });

  // DESIGN.md → Overview + Colors → The Migration Rule.
  // The tome palette is the destination; the M3 ColorScheme layer is legacy
  // debt. This does not fail the build on the debt that exists — it pins the
  // count so it can only go DOWN. Migrating a surface? Lower the number.
  test('The Migration Rule: raw ColorScheme use only shrinks', () {
    // The debt as measured on 2026-07-24. This number may go DOWN (lower it
    // here when you migrate a surface) and must never go UP.
    const ceiling = 131;
    final hits = _hits(RegExp(r'colorScheme\.'));
    expect(
      hits.length,
      lessThanOrEqualTo(ceiling),
      reason: 'New player-facing work reads JuiceTokens via context.juice, '
          'not a raw ColorScheme role. ${hits.length - ceiling} new use(s) '
          'crossed the line — migrate them, or if this is a deliberate '
          'system-widget exception, raise the ceiling in one commit that says '
          'why.',
    );
  });
}
