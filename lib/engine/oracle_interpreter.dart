/// On-device LLM oracle interpretation: prompt schema + tolerant parser.
/// Pure Dart — no flutter_gemma, no Flutter. The service layer
/// (lib/state/interpreter.dart) owns the model; this file owns the words.
///
/// Adapted from a user-provided design (see spec). Key change: the seed is
/// the journal entry's already-formatted result text — Juice/Mythic tables
/// have no per-word meanings to feed.
library;

import 'dart:convert';

/// Everything the model needs to interpret one logged oracle result.
class OracleSeed {
  const OracleSeed({
    required this.resultText,
    this.genre = '',
    this.tone = '',
    this.sceneContext = '',
  });

  /// The journal entry's title + body, verbatim.
  final String resultText;

  /// Per-campaign settings, e.g. 'grimdark fantasy' / 'tense and dangerous'.
  final String genre;
  final String tone;

  /// Latest scene entry's title (+ chaos factor), or empty. Future RAG hook.
  final String sceneContext;
}

/// A single interpretation card; [lens] is the register it was written in.
class OracleInterpretation {
  const OracleInterpretation({required this.lens, required this.reading});
  final String lens;
  final String reading;
}

/// Distinct registers, ordered safest -> most surprising. Naming the lenses
/// is what forces a small model to diversify instead of rephrasing.
const List<String> kLenses = <String>[
  'literal',
  'symbolic',
  'complication',
  'foreshadow',
];

/// Role + rules + JSON shape + two compact few-shot examples. Examples move
/// small-model quality more than rules do. Kept tight: the web model's
/// context may be as small as 1280 tokens total.
const String oracleSystemInstruction = '''
You interpret oracle results for a solo tabletop RPG player journaling their
own story. You offer possibilities; the player decides what is true. Never
resolve outcomes, never say what the player's character does or feels.

For each result output EXACTLY four interpretations, one per lens, in order:
- literal: the plainest, most direct reading of the result.
- symbolic: a metaphorical or atmospheric reading — NOT literally the result.
- complication: a "yes, but" — accepts the result and adds a cost or twist.
- foreshadow: something quiet that hints at trouble or change LATER, not now.

Rules:
- Each reading is 1-2 short sentences. Concrete and evocative. No "perhaps".
- The four readings must be genuinely different ideas, not rephrasings.
- Honor the stated genre and tone in word choice and imagery.
- Use the scene context if given; otherwise invent freely but stay in tone.
- Output ONLY a JSON object. No preamble, no markdown fences, no commentary.

JSON shape:
{"interpretations":[{"lens":"literal","reading":"..."},{"lens":"symbolic","reading":"..."},{"lens":"complication","reading":"..."},{"lens":"foreshadow","reading":"..."}]}

Example 1
INPUT:
genre: grimdark fantasy
tone: tense and dangerous
result: Fate Check (Likely) — No, but…
scene: Scene: Begging entry at the city gate after dark (Chaos 6)
OUTPUT:
{"interpretations":[{"lens":"literal","reading":"The gate stays shut, but a postern door creaks open a hand's width — a bribe might widen it."},{"lens":"symbolic","reading":"The city turns its iron back on you; only its rats and refuse acknowledge your arrival."},{"lens":"complication","reading":"A guard waves you toward the smugglers' stair instead, and now he knows your face."},{"lens":"foreshadow","reading":"Above the gate, someone snuffs a lantern the moment you look up."}]}

Example 2
INPUT:
genre: cozy folk mystery
tone: warm but uneasy
result: Story: Discover / Object
scene: (none given)
OUTPUT:
{"interpretations":[{"lens":"literal","reading":"Behind the loose hearthstone sits a rusted tin box, something shifting inside when you lift it."},{"lens":"symbolic","reading":"A single mismatched teacup at the back of the cupboard — kept for someone who never came back."},{"lens":"complication","reading":"You find the cottage deed, and a second name on it you have never heard before."},{"lens":"foreshadow","reading":"A pressed flower falls from a book — a kind that only grows two valleys over."}]}
''';

/// Builds the per-roll user message from a seed.
String buildOraclePrompt(OracleSeed seed) {
  String orElse(String v, String fallback) =>
      v.trim().isEmpty ? fallback : v.trim();
  return 'INPUT:\n'
      'genre: ${orElse(seed.genre, '(unspecified)')}\n'
      'tone: ${orElse(seed.tone, '(unspecified)')}\n'
      'result: ${seed.resultText.trim()}\n'
      'scene: ${orElse(seed.sceneContext, '(none given)')}\n'
      'OUTPUT:';
}

/// Parses raw model output. Strips <think> spans and code fences, isolates
/// the outermost JSON object, validates shape. On any failure returns the
/// raw text as a single 'raw' card so the player still sees something.
/// Never throws.
List<OracleInterpretation> parseInterpretations(String raw) {
  final cleaned = _isolateJson(raw);
  if (cleaned != null) {
    try {
      final decoded = jsonDecode(cleaned);
      final list = (decoded is Map) ? decoded['interpretations'] : null;
      if (list is List) {
        final out = <OracleInterpretation>[];
        for (final item in list) {
          if (item is Map) {
            final lens = item['lens']?.toString().trim() ?? '';
            final reading = item['reading']?.toString().trim() ?? '';
            if (reading.isNotEmpty) {
              out.add(OracleInterpretation(
                lens: lens.isEmpty ? 'reading' : lens,
                reading: reading,
              ));
            }
          }
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {
      // fall through to raw fallback
    }
  }
  final fallback = _stripThink(raw).trim();
  return fallback.isEmpty
      ? const <OracleInterpretation>[]
      : <OracleInterpretation>[
          OracleInterpretation(lens: 'raw', reading: fallback),
        ];
}

String _stripThink(String s) =>
    s.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');

String? _isolateJson(String raw) {
  final s = _stripThink(raw)
      .replaceAll('```json', '')
      .replaceAll('```', '')
      .trim();
  final start = s.indexOf('{');
  final end = s.lastIndexOf('}');
  if (start == -1 || end == -1 || end <= start) return null;
  return s.substring(start, end + 1);
}

/// Debug-eval seeds (see spec "Quality bar"). Used by the debug-only
/// runEval in lib/state/interpreter.dart and by live verification.
const List<OracleSeed> kEvalSeeds = <OracleSeed>[
  OracleSeed(
    resultText: 'Fate Check (Unlikely) — Yes…',
    genre: 'grimdark fantasy',
    tone: 'tense and dangerous',
    sceneContext: 'Scene: Alone on a forest road at dusk (Chaos 5)',
  ),
  OracleSeed(
    resultText: 'Story: Help / Stranger',
    genre: 'cozy folk mystery',
    tone: 'warm but uneasy',
    sceneContext: 'Scene: Stuck in the rain outside a shuttered inn',
  ),
  OracleSeed(
    resultText: 'Wilderness Travel — Swamp 4 Ruins, Lost',
    genre: 'hard sci-fi',
    tone: 'cold and isolating',
  ),
];
