/// On-device LLM oracle interpretation: prompt schema + tolerant parser.
/// Pure Dart — no flutter_gemma, no Flutter. The service layer behind
/// lib/state/interpreter.dart owns the model (interpreter_gemma.dart is the
/// implementation); this file owns the words.
///
/// Adapted from a user-provided design (see spec). Key change: the seed is
/// the journal entry's already-formatted result text — Juice/Mythic tables
/// have no per-word meanings to feed.
library;

import 'dart:convert';

import 'gm_chat.dart';
import 'journal_search.dart';
import 'models.dart';

/// Hard caps on the prompt's `recall:` block. Sized against the loader's
/// 4096-token session budget (see interpreter_gemma.dart _loadModel): the
/// worst-case interpret prompt (instruction + full grounding + max recall)
/// must leave room for the JSON output even on the 2048 fallback tier.
const int kRecallMaxEntries = 8;
const int kRecallMaxChars = 360;

/// Everything the model needs to interpret one logged oracle result.
class OracleSeed {
  const OracleSeed({
    required this.resultText,
    this.genre = '',
    this.tone = '',
    this.sceneContext = '',
    this.journalContext = const [],
    this.systemPrimer = '',
    this.activeCharacter = '',
  });

  /// The journal entry's title + body, verbatim.
  final String resultText;

  /// Per-campaign settings, e.g. 'grimdark fantasy' / 'tense and dangerous'.
  final String genre;
  final String tone;

  /// Authored facts-only primer for the active TTRPG (see system_primer.dart),
  /// or '' for none. Renders as a `system:` line in the prompt.
  final String systemPrimer;

  /// Latest scene entry's title (+ chaos factor), or empty.
  final String sceneContext;

  /// Most-relevant past journal entries (see relatedEntries in
  /// journal_search.dart), one string each. The prompt renders at most
  /// [kRecallMaxEntries] of them as `recall:` lines.
  final List<String> journalContext;

  /// One-line active-PC descriptor (see activeCharacterLine), or '' for none.
  /// Renders as a `pc:` line.
  final String activeCharacter;
}

/// The recall-ranked journal lines for [target] (most-relevant past entries via
/// [relatedEntries]), formatted "Title — body" (or body only when untitled) for
/// any seam's `journalContext`. The prompt builders still take [kRecallMaxEntries]
/// and cap each at [kRecallMaxChars]. Pure.
List<String> recallLines(List<JournalEntry> journal, JournalEntry target) =>
    _format(relatedEntries(journal, target));

/// The recall-ranked journal lines for a raw [text] — the same grounding
/// [recallLines] gives an existing entry, for a roll that isn't logged yet.
/// [excludeId] drops an entry from its own recall. Pure.
List<String> recallLinesFor(
  List<JournalEntry> journal,
  String text, {
  String? excludeId,
}) =>
    _format(relatedEntriesForText(journal, text, excludeId: excludeId));

List<String> _format(List<JournalEntry> entries) => [
      for (final e in entries)
        e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
    ];

/// Folds an accepted [card] into an entry [body], producing the one combined
/// journal entry: the result that was rolled, plus the reading it inspired.
/// The single source of this format — every inspire surface appends alike, and
/// `PayloadCard` renders the remainder past its structured rolls. Pure.
String appendReading(String body, OracleInterpretation card) {
  final reading = '— Oracle reading (${card.lens}): ${card.reading}';
  return body.trim().isEmpty ? reading : '${body.trimRight()}\n\n$reading';
}

/// A short "who the PC is" line for the prompt, or '' when none. Facts-only:
/// name + role + any conditions. Pure.
String activeCharacterLine(Character? c) {
  if (c == null) return '';
  final role = switch (c.role) {
    CharacterRole.pc => 'PC',
    CharacterRole.companion => 'companion',
    CharacterRole.npc => 'NPC',
  };
  final cond = c.conditions.isEmpty ? '' : ' — ${c.conditions.join(', ')}';
  return '${c.name} ($role)$cond';
}

/// The shared grounding block every seam's prompt opens with, in one canonical
/// order: genre, tone, system, pc, scene, recall. This is the single place the
/// game-situation lines are rendered, so seams can't drift in field order,
/// capping, or placeholder behavior.
///
/// Empty fields are omitted, except under [placeholders] (the interpret/voice
/// prompts keep explicit '(unspecified)'/'(none given)' markers because their
/// few-shot examples show them). A null [sceneTitle] omits the scene line even
/// under [placeholders] — for seams with no scene concept (voice).
String _groundingBlock({
  String genre = '',
  String tone = '',
  String systemPrimer = '',
  String activeCharacter = '',
  String? sceneTitle,
  List<String> journalContext = const [],
  bool placeholders = false,
}) {
  final b = StringBuffer();
  void line(String key, String value, {String placeholder = ''}) {
    final f = _flat(value);
    if (f.isEmpty) {
      if (placeholders && placeholder.isNotEmpty) {
        b.write('$key: $placeholder\n');
      }
      return;
    }
    b.write('$key: ${_capped(f)}\n');
  }

  line('genre', genre, placeholder: '(unspecified)');
  line('tone', tone, placeholder: '(unspecified)');
  line('system', systemPrimer);
  line('pc', activeCharacter);
  if (sceneTitle != null) {
    line('scene', sceneTitle, placeholder: '(none given)');
  }
  for (final context in journalContext.take(kRecallMaxEntries)) {
    final f = _flat(context);
    if (f.isEmpty) continue;
    final cut =
        f.length > kRecallMaxChars ? '${f.substring(0, kRecallMaxChars)}…' : f;
    b.write('recall: $cut\n');
  }
  return b.toString();
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
/// small-model quality more than rules do. Kept reasonably tight for the
/// on-device Gemma 4 E4B model (desktop/mobile only; web ships no AI).
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
- recall: lines are excerpts from the player's earlier journal. Treat them as established facts; weave them in when they fit.
- system: line, when present, names the game's setting and core mechanics; honor its flavor and vocabulary in word choice.
- Output ONLY a JSON object. No preamble, no markdown fences, no commentary.

JSON shape:
{"interpretations":[{"lens":"literal","reading":"..."},{"lens":"symbolic","reading":"..."},{"lens":"complication","reading":"..."},{"lens":"foreshadow","reading":"..."}]}

Example 1
INPUT:
genre: grimdark fantasy
tone: tense and dangerous
scene: Scene: Begging entry at the city gate after dark (Chaos 6)
result: Fate Check (Likely) — No, but…
OUTPUT:
{"interpretations":[{"lens":"literal","reading":"The gate stays shut, but a postern door creaks open a hand's width — a bribe might widen it."},{"lens":"symbolic","reading":"The city turns its iron back on you; only its rats and refuse acknowledge your arrival."},{"lens":"complication","reading":"A guard waves you toward the smugglers' stair instead, and now he knows your face."},{"lens":"foreshadow","reading":"Above the gate, someone snuffs a lantern the moment you look up."}]}

Example 2
INPUT:
genre: cozy folk mystery
tone: warm but uneasy
scene: (none given)
result: Story: Discover / Object
OUTPUT:
{"interpretations":[{"lens":"literal","reading":"Behind the loose hearthstone sits a rusted tin box, something shifting inside when you lift it."},{"lens":"symbolic","reading":"A single mismatched teacup at the back of the cupboard — kept for someone who never came back."},{"lens":"complication","reading":"You find the cottage deed, and a second name on it you have never heard before."},{"lens":"foreshadow","reading":"A pressed flower falls from a book — a kind that only grows two valleys over."}]}
''';

/// Collapses internal whitespace/newlines in a seed field to single spaces
/// (the prompt format is line-keyed, so embedded newlines would break it).
String _flat(String v) => v.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Builds the per-roll user message from a seed. The format is line-keyed
/// (one field per line, matching the few-shot examples), so runs of
/// whitespace/newlines in seed fields collapse to single spaces.
String buildOraclePrompt(OracleSeed seed) {
  return 'INPUT:\n'
      '${_groundingBlock(genre: seed.genre, tone: seed.tone, systemPrimer: seed.systemPrimer, activeCharacter: seed.activeCharacter, sceneTitle: seed.sceneContext, journalContext: seed.journalContext, placeholders: true)}'
      'result: ${_flat(seed.resultText)}\n'
      'OUTPUT:';
}

/// Parses raw model output. Strips <think> spans and code fences, isolates
/// the first balanced JSON object, validates shape. If jsonDecode fails or
/// yields no cards, a salvage stage extracts lens/reading pairs by their
/// stable delimiters — small models emit unescaped quotes inside readings,
/// which breaks strict JSON. On any remaining failure returns the raw text
/// as a single 'raw' card so the player still sees something. Never throws.
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
      // fall through to salvage / raw fallback
    }
  }
  final salvaged = _salvageLensReadings(cleaned ?? _stripThink(raw));
  if (salvaged.isNotEmpty) return salvaged;
  final fallback = _stripThink(raw).trim();
  return fallback.isEmpty
      ? const <OracleInterpretation>[]
      : <OracleInterpretation>[
          OracleInterpretation(lens: 'raw', reading: fallback),
        ];
}

/// Salvage stage for structurally-correct-but-invalid JSON: small models
/// emit unescaped double quotes inside reading text, which breaks jsonDecode
/// while leaving the `{"lens":"` / `"reading":"` / closing `"}` delimiters
/// intact (readings never contain those exact sequences in practice). Splits
/// on the lens delimiter and, per fragment, takes the lens up to the next
/// quote and the reading up to the fragment's last `"}` boundary — so stray
/// inner quotes are preserved verbatim. Returns an empty list if nothing
/// salvageable is found.
List<OracleInterpretation> _salvageLensReadings(String s) {
  final out = <OracleInterpretation>[];
  final fragments = s.split('{"lens":"');
  for (var i = 1; i < fragments.length; i++) {
    final frag = fragments[i];
    final lensEnd = frag.indexOf('"');
    if (lensEnd == -1) continue;
    var lens = frag.substring(0, lensEnd).trim();
    final key =
        RegExp(r'"reading"\s*:\s*"').firstMatch(frag.substring(lensEnd));
    if (key == null) continue;
    final start = lensEnd + key.end;
    final end = frag.lastIndexOf('"}');
    if (end <= start) continue;
    final reading = frag.substring(start, end).trim();
    if (reading.isEmpty) continue;
    if (lens.isEmpty || lens.length > 24) lens = 'reading';
    out.add(OracleInterpretation(lens: lens, reading: reading));
  }
  return out;
}

/// Strips closed <think> spans, and an unterminated <think> to end-of-string
/// so truncated chain-of-thought never leaks into a raw card.
String _stripThink(String s) =>
    s.replaceAll(RegExp(r'<think>.*?(</think>|$)', dotAll: true), '');

/// Returns the first balanced JSON object in [raw]: a string-aware brace
/// scan from the first '{', so trailing prose — even prose containing
/// braces — is ignored. Null if no object closes.
String? _isolateJson(String raw) {
  final s = _stripThink(raw).replaceAll('```json', '').replaceAll('```', '');
  final start = s.indexOf('{');
  if (start == -1) return null;
  var depth = 0;
  var inString = false;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (c == r'\') {
        i++; // skip the escaped character
      } else if (c == '"') {
        inString = false;
      }
    } else if (c == '"') {
      inString = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return s.substring(start, i + 1);
    }
  }
  return null;
}

// -- Sidekick voice -----------------------------------------------------------

/// Everything the model needs to voice one rolled dialogue line
/// (party-emulator spec §4).
class VoiceSeed {
  const VoiceSeed({
    required this.line,
    required this.mood,
    this.tone,
    this.topic,
    this.characterName,
    this.characterTags = const [],
    this.genre = '',
    this.toneSetting = '',
    this.journalContext = const [],
    this.systemPrimer = '',
    this.activeCharacter = '',
  });

  /// The rolled dialogue line, verbatim.
  final String line;

  /// Mood id the line was rolled under ('default'…).
  final String mood;

  /// Tone / topic chips, when rolled alongside.
  final String? tone;
  final String? topic;

  /// The speaking character, when one is selected; tags double as Traits.
  final String? characterName;
  final List<String> characterTags;

  /// Per-campaign settings (as [OracleSeed.genre]/[OracleSeed.tone]).
  final String genre;
  final String toneSetting;

  /// Authored facts-only primer for the active TTRPG (see system_primer.dart),
  /// or '' for none. Renders as a `system:` line in the prompt.
  final String systemPrimer;

  /// Recall lines (see relatedEntries); capped like the oracle prompt.
  final List<String> journalContext;

  /// One-line active-PC descriptor (see activeCharacterLine), or '' for none.
  /// Renders as a `pc:` line (distinct from [characterName], the spoken NPC).
  final String activeCharacter;
}

/// Compact instruction (~150 tokens, well under the lens prompt's budget):
/// one in-character utterance, plain text. Inlined into the prompt on every
/// platform — the shared web session cannot take a per-chat system
/// instruction (see interpreter_gemma.dart).
const String _voiceInstruction = '''
You voice one party character for a solo tabletop RPG player. Expand the
rolled line into EXACTLY ONE in-character utterance, 1-2 short sentences,
spoken aloud in the character's words. Keep the rolled line's intent, the
stated mood, and the line tone. Honor the genre and campaign tone. recall:
lines are excerpts from the player's journal; treat them as established
facts. system: line, when present, names the game's setting and mechanics —
honor its flavor. Output plain text only: just the spoken words — no JSON, no
markdown, no quotation marks, no stage directions, no commentary.''';

/// Builds the voiceLine prompt: the instruction plus line-keyed fields
/// (format and recall capping as [buildOraclePrompt]). Optional fields are
/// omitted entirely; empty settings become explicit placeholders.
String buildVoicePrompt(VoiceSeed seed) {
  final name = seed.characterName;
  final tone = seed.tone;
  final topic = seed.topic;
  return '$_voiceInstruction\n\n'
      'INPUT:\n'
      '${_groundingBlock(genre: seed.genre, tone: seed.toneSetting, systemPrimer: seed.systemPrimer, activeCharacter: seed.activeCharacter, journalContext: seed.journalContext, placeholders: true)}'
      '${name == null ? '' : 'character: ${_flat(name)}\n'}'
      '${seed.characterTags.isEmpty ? '' : 'traits: ${_flat(seed.characterTags.join(', '))}\n'}'
      'mood: ${_flat(seed.mood)}\n'
      '${tone == null ? '' : 'line tone: ${_flat(tone)}\n'}'
      '${topic == null ? '' : 'topic: ${_flat(topic)}\n'}'
      'line: ${_flat(seed.line)}\n'
      'OUTPUT:';
}

/// Parses raw voiceLine output: strips think spans, trims. Unlike the lens
/// parser there is no salvage tier — an empty result throws FormatException
/// and the UI offers retry.
String parseVoiceResponse(String raw) {
  final out = _stripThink(raw).trim();
  if (out.isEmpty) throw const FormatException('Empty voice response');
  return out;
}

// -- Shared prompt utilities --------------------------------------------------

/// Hard cap on prompt field strings (scene title, question, entity name) fed to
/// the model, so a long pasted value can't crowd out the grounding lines.
/// Mirrors the budget discipline of [kRecallMaxChars] / [kSystemPrimerMaxChars].
const int kPromptMaxFieldChars = 300;

String _capped(String s) => s.length > kPromptMaxFieldChars
    ? '${s.substring(0, kPromptMaxFieldChars)}…'
    : s;

// -- Multi-turn GM chat -------------------------------------------------------

const int kGmChatHistoryTurns = 8; // last N turns rendered into the prompt
const int kGmChatTurnMaxChars = 300; // per-turn cap

const String _gmChatInstruction =
    'You are the game master for a solo tabletop RPG in an ongoing conversation '
    "with the player. Continue as the GM: answer the player's latest message in "
    '1-3 sentences of plain prose, consistent with the conversation and the '
    "established facts. Be concrete and decisive. Output only the GM's words.";

class GmChatSeed {
  const GmChatSeed({
    required this.history,
    this.genre = '',
    this.tone = '',
    this.sceneTitle,
    this.systemPrimer = '',
    this.activeCharacter = '',
    this.journalContext = const [],
  });

  /// The full transcript, oldest first, INCLUDING the latest player turn.
  final List<ChatTurn> history;

  /// Per-campaign settings (as [OracleSeed.genre]/[OracleSeed.tone]).
  final String genre;
  final String tone;
  final String? sceneTitle;
  final String systemPrimer;
  final String activeCharacter;
  final List<String> journalContext;
}

/// Stateless multi-turn prompt: instruction + the shared grounding block +
/// a transcript of the last [kGmChatHistoryTurns] turns + a trailing
/// `GM:` for the model to continue. Caps mirror the other builders.
String buildGmChatPrompt(GmChatSeed seed) {
  final recent = seed.history.length > kGmChatHistoryTurns
      ? seed.history.sublist(seed.history.length - kGmChatHistoryTurns)
      : seed.history;
  final transcript = StringBuffer();
  for (final t in recent) {
    final who = t.role == ChatRole.gm ? 'GM' : 'Player';
    var line = _flat(t.text);
    if (line.length > kGmChatTurnMaxChars) {
      line = '${line.substring(0, kGmChatTurnMaxChars)}…';
    }
    transcript.write('$who: $line\n');
  }
  return '$_gmChatInstruction\n\n'
      'INPUT:\n'
      '${_groundingBlock(genre: seed.genre, tone: seed.tone, systemPrimer: seed.systemPrimer, activeCharacter: seed.activeCharacter, sceneTitle: seed.sceneTitle, journalContext: seed.journalContext)}'
      '$transcript'
      'GM:';
}

/// Strip think spans, trim, throw on empty.
String parseGmChatResponse(String raw) {
  final out = _stripThink(raw).trim();
  if (out.isEmpty) throw const FormatException('Empty GM chat response');
  return out;
}

// -- GM narration -------------------------------------------------------------

/// Which GM-narration prompt to build: continue the scene, or raise the stakes.
enum NarrateMode { continueScene, complication }

/// Inputs for a one-shot GM narration. Carries the #1 grounding (scene / system
/// primer / active PC / recalled journal lines) plus the [mode].
class NarrateSeed {
  const NarrateSeed({
    required this.mode,
    this.genre = '',
    this.tone = '',
    this.sceneTitle,
    this.systemPrimer = '',
    this.activeCharacter = '',
    this.journalContext = const [],
  });
  final NarrateMode mode;

  /// Per-campaign settings (as [OracleSeed.genre]/[OracleSeed.tone]).
  final String genre;
  final String tone;
  final String? sceneTitle;
  final String systemPrimer;
  final String activeCharacter;
  final List<String> journalContext;
}

/// Instruction + one compact example per mode — examples move small-model
/// quality more than rules do (same rationale as [oracleSystemInstruction]).
String _narrateInstruction(NarrateMode mode) => switch (mode) {
      NarrateMode.continueScene =>
        'You are the game master for a solo tabletop RPG. Narrate the next beat '
            'of the current scene in 1-3 sentences of vivid present-tense prose, '
            'advancing the action and staying consistent with the established '
            'facts. Honor the stated genre and tone. Output only the narration '
            '— no preamble, no options, no questions.\n'
            '\n'
            'Example\n'
            'INPUT:\n'
            'genre: grimdark fantasy\n'
            'scene: Ambushed on the marsh causeway\n'
            'Narration:\n'
            'A second arrow hisses out of the reeds and takes the torch from '
            'your hand — the light rolls, guttering, toward the black water.',
      NarrateMode.complication =>
        'You are the game master for a solo tabletop RPG. Introduce ONE '
            'complication or twist that raises the stakes in the current scene, '
            'in 1-3 sentences of present-tense prose, consistent with the '
            'established facts. Honor the stated genre and tone. Output only '
            'the complication.\n'
            '\n'
            'Example\n'
            'INPUT:\n'
            'genre: cozy folk mystery\n'
            'scene: Asking the miller about the missing ledger\n'
            'Narration:\n'
            'The miller answers a shade too quickly — and behind him, his '
            'daughter eases the ledger drawer shut with her hip.',
    };

/// Mode-specific instruction + the shared grounding block + a trailing
/// `Narration:` cue.
String buildNarratePrompt(NarrateSeed seed) {
  return '${_narrateInstruction(seed.mode)}\n\n'
      'INPUT:\n'
      '${_groundingBlock(genre: seed.genre, tone: seed.tone, systemPrimer: seed.systemPrimer, activeCharacter: seed.activeCharacter, sceneTitle: seed.sceneTitle, journalContext: seed.journalContext)}'
      'Narration:';
}

/// Strip think spans, trim, throw on empty.
String parseNarrateResponse(String raw) {
  final out = _stripThink(raw).trim();
  if (out.isEmpty) throw const FormatException('Empty narration response');
  return out;
}

// -- Flesh out an entity ------------------------------------------------------

class FleshOutSeed {
  const FleshOutSeed({
    required this.entityKind,
    required this.name,
    this.existingDetail = '',
    this.genre = '',
    this.tone = '',
    this.systemPrimer = '',
    this.activeCharacter = '',
    this.sceneTitle,
    this.journalContext = const [],
  });

  /// Human label for the prompt, e.g. 'NPC' / 'story thread' / 'location'.
  final String entityKind;

  /// Per-campaign settings (as [OracleSeed.genre]/[OracleSeed.tone]).
  final String genre;
  final String tone;

  /// The entity's name/title — the subject of the flesh-out.
  final String name;

  /// The entity's current free-text detail; the model builds on it.
  final String existingDetail;

  /// Authored facts-only system primer (see system_primer.dart), or ''.
  final String systemPrimer;

  /// One-line active-PC descriptor (see [activeCharacterLine]), or '' — the
  /// shared `pc:` grounding line every seam carries.
  final String activeCharacter;

  /// Latest scene entry's title, or null.
  final String? sceneTitle;

  /// Name-query recall lines (entries mentioning the entity); capped in-prompt.
  final List<String> journalContext;
}

/// A fixed instruction (+ one compact example) + the shared grounding block +
/// name/existing lines + a trailing `Detail:` cue. Field strings go through
/// `_capped` ([kPromptMaxFieldChars]).
String buildFleshOutPrompt(FleshOutSeed seed) {
  final existing = _flat(seed.existingDetail);
  final existingLine =
      existing.isEmpty ? '' : 'existing: ${_capped(existing)}\n';
  return 'You are the game master for a solo tabletop RPG. Flesh out the '
      'following ${seed.entityKind} with 2-4 sentences of vivid, concrete '
      'detail consistent with the established facts. Build on any existing '
      'notes — do not contradict them. Honor the stated genre and tone. '
      'Output only the description — no preamble, no headers, no lists.\n'
      '\n'
      'Example\n'
      'INPUT:\n'
      'genre: grimdark fantasy\n'
      'name: Marta the ferrywoman\n'
      'existing: Knows everyone who crosses the river.\n'
      'Detail:\n'
      'Marta poles the ferry with a soldier\'s forearms and a debtor\'s eyes, '
      'and she remembers every crossing — who paid, who begged, and who made '
      'her look away. Lately she refuses coin from anyone heading north.\n\n'
      'INPUT:\n'
      '${_groundingBlock(genre: seed.genre, tone: seed.tone, systemPrimer: seed.systemPrimer, activeCharacter: seed.activeCharacter, sceneTitle: seed.sceneTitle, journalContext: seed.journalContext)}'
      'name: ${_capped(_flat(seed.name))}\n'
      '$existingLine'
      'Detail:';
}

/// Plain-text parse (like parseNarrateResponse): strip think, trim, throw empty.
String parseFleshOutResponse(String raw) {
  final out = _stripThink(raw).trim();
  if (out.isEmpty) throw const FormatException('Empty flesh-out response');
  return out;
}

// -- Ranked suggestions -------------------------------------------------------

class RankSuggestionsSeed {
  const RankSuggestionsSeed({
    required this.candidates,
    this.genre = '',
    this.tone = '',
    this.systemPrimer = '',
    this.sceneTitle,
    this.activeCharacter = '',
    this.journalContext = const [],
  });

  /// Candidate next-move chips in rule order: (stable id, display label).
  final List<({String id, String label})> candidates;

  /// Per-campaign settings (as [OracleSeed.genre]/[OracleSeed.tone]).
  final String genre;
  final String tone;

  /// Authored facts-only system primer (see system_primer.dart), or ''.
  final String systemPrimer;

  /// Latest scene entry's title, or null.
  final String? sceneTitle;

  /// One-line active-PC descriptor (see [activeCharacterLine]), or ''.
  final String activeCharacter;

  /// Recall lines for the current scene; capped in-prompt.
  final List<String> journalContext;
}

/// The model's ranking output. Best-effort: an empty [order] means "no opinion"
/// (the caller keeps rule order); [why] is the top pick's one-line rationale.
class RankResult {
  const RankResult({this.order = const [], this.why = ''});

  /// Suggestion ids, most→least useful. Unknown/duplicate ids are ignored by
  /// the caller ([applyRanking]).
  final List<String> order;

  /// One-line rationale for the top pick, or '' when none.
  final String why;
}

/// Instruction + the shared grounding block + the candidate lines + a JSON
/// cue. Caps mirror the other builders.
String buildRankPrompt(RankSuggestionsSeed seed) {
  final cand = StringBuffer();
  for (final c in seed.candidates) {
    cand.write('- ${c.id}: ${_flat(c.label)}\n');
  }
  return 'You are the game master for a solo tabletop RPG. Given the current '
      'scene and these candidate next moves, output the move ids ordered '
      'most-to-least useful right now, and one short sentence on why the top '
      'one fits. Output ONLY a JSON object, no prose: '
      '{"order":["id",...],"why":"..."}.\n\n'
      'INPUT:\n'
      '${_groundingBlock(genre: seed.genre, tone: seed.tone, systemPrimer: seed.systemPrimer, activeCharacter: seed.activeCharacter, sceneTitle: seed.sceneTitle, journalContext: seed.journalContext)}'
      'candidates:\n'
      '$cand'
      'OUTPUT:';
}

/// Tolerant parse — NEVER throws (ranking is best-effort; an empty result means
/// keep rule order). Isolates the first JSON object, coerces `order` to strings.
RankResult parseRankResult(String raw) {
  final json = _isolateJson(raw);
  if (json == null) return const RankResult();
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return const RankResult();
    final orderRaw = decoded['order'];
    final order = <String>[
      if (orderRaw is List)
        for (final e in orderRaw)
          if (e is String) e, // drop non-string ids (null/int/nested)
    ];
    final why = (decoded['why'] ?? '').toString().trim();
    return RankResult(order: order, why: why);
  } catch (_) {
    return const RankResult();
  }
}

// -- Journal recap ------------------------------------------------------------

/// Recap instruction, baked into [buildSummaryPrompt] (like
/// [buildVoicePrompt]'s `_voiceInstruction`): the web session is shared and
/// latch-locked, so the guidance must ride in the prompt, not a per-chat
/// system instruction.
const String _summaryInstruction =
    'You recap a solo RPG journal. Given recent entries in order, write a '
    'tight 2-3 sentence "previously on" recap in past tense, plain prose, no '
    'lists or preamble.';

/// Builds the recap prompt from recent entry texts (oldest first). Capped at
/// 20 entries AND [kPromptMaxFieldChars] per entry (flattened to one line so
/// a multi-paragraph body can't break the bullet structure or eat the
/// generation window).
String buildSummaryPrompt(List<String> entries) {
  final capped =
      entries.length > 20 ? entries.sublist(entries.length - 20) : entries;
  final body = capped.map((e) => '- ${_capped(_flat(e))}').join('\n');
  return '$_summaryInstruction\n\n'
      'Recent journal entries (oldest first):\n$body\n\nRecap:';
}

/// Plain-text parse: strip think-tags (incl. an unterminated span, via the
/// shared [_stripThink]), then trim — same discipline as parseVoiceResponse.
String parseSummary(String raw) => _stripThink(raw).trim();

/// Debug-eval seeds (see spec "Quality bar"). Used by the debug-only
/// runInterpreterEval in lib/state/interpreter.dart and by live verification.
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
