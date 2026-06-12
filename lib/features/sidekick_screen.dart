import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/emulator_data.dart';
import '../engine/journal_search.dart';
import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../engine/party_emulator.dart';
import '../state/interpreter.dart';
import '../state/providers.dart';

/// Sidekick Dialogue — mood-keyed dialogue lines with the doubles →
/// mood-change rule and tone/topic/said-how chips, a "Voice this" expansion
/// through the on-device interpreter, and the 19-hex conversation walker
/// (party emulator phase 4). Mood and hexflower position persist on the
/// selected character's emulation; 'No one' keeps a transient copy.
class SidekickScreen extends ConsumerStatefulWidget {
  const SidekickScreen({super.key, this.dice});

  /// Injectable for deterministic tests; defaults to a fresh RNG.
  final Dice? dice;

  @override
  ConsumerState<SidekickScreen> createState() => _SidekickScreenState();
}

/// Mood label: 'high_strung' → 'High strung'.
String _moodLabel(String id) =>
    id[0].toUpperCase() + id.substring(1).replaceAll('_', ' ');

/// Context label per the source: gray hexes talk history, red ones current
/// events.
String _contextLabel(String context) =>
    context == 'gray' ? 'history (gray)' : 'current events (red)';

class _SidekickScreenState extends ConsumerState<SidekickScreen> {
  late final Dice _dice = widget.dice ?? Dice();

  String? _characterId;

  /// Emulation state for 'No one' — never persisted (p3 transient pattern).
  CharacterEmulation _transient = const CharacterEmulation();

  _DialogueOutcome? _dialogue;
  String? _voiced;
  bool _voicing = false;
  String? _voiceError;

  _HexOutcome? _hex;

  @override
  Widget build(BuildContext context) {
    final emulator = ref.watch(emulatorDataProvider);
    return emulator.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load emulator data:\n$e')),
      data: (data) => _body(context, data),
    );
  }

  Widget _body(BuildContext context, EmulatorData data) {
    final chars = ref.watch(charactersProvider).valueOrNull ?? const [];
    Character? selected;
    for (final c in chars) {
      if (c.id == _characterId) selected = c;
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              tabs: [
                Tab(text: 'Dialogue'),
                Tab(key: Key('sd-hex-tab'), text: 'Hexflower'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _dialogueTab(context, data, chars, selected),
                _hexTab(context, data, selected),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _attribution(ThemeData theme, EmulatorData data) => [
        const SizedBox(height: 24),
        for (final line in data.attribution)
          Text(
            line,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ];

  // -- Fresh-read emulation helpers (party_emulator_screen pattern) ----------

  /// The selected character's emulation, or the transient 'No one' state.
  /// Build-time display only — handlers go through [_currentEmulation] /
  /// [_updateEmulation], which read fresh at press time.
  CharacterEmulation _emulationOf(Character? c) =>
      c == null ? _transient : (c.emulation ?? const CharacterEmulation());

  /// [c] as the provider holds it right now — never the build-captured
  /// snapshot. Falls back to [c] if it left the roster mid-press.
  Future<Character> _freshCharacter(Character c) async {
    final chars = await ref.read(charactersProvider.future);
    return chars.firstWhere((x) => x.id == c.id, orElse: () => c);
  }

  /// The press-time emulation a handler must base decisions on.
  Future<CharacterEmulation> _currentEmulation(Character? c) async => c == null
      ? _transient
      : ((await _freshCharacter(c)).emulation ?? const CharacterEmulation());

  /// Persist [up] applied to the character's CURRENT emulation, or to the
  /// in-screen 'No one' state. Reading fresh inside the write is the
  /// lost-update guard (see party_emulator_screen).
  Future<void> _updateEmulation(
      Character? c, CharacterEmulation Function(CharacterEmulation) up) async {
    if (c == null) {
      setState(() => _transient = up(_transient));
      return;
    }
    final cur = await _freshCharacter(c);
    await ref.read(charactersProvider.notifier).replace(cur.copyWith(
        emulation: up(cur.emulation ?? const CharacterEmulation())));
  }

  // -- Dialogue tab -----------------------------------------------------------

  Widget _dialogueTab(BuildContext context, EmulatorData data,
      List<Character> chars, Character? selected) {
    final theme = Theme.of(context);
    final mood = _emulationOf(selected).mood ?? 'default';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButton<String?>(
          key: const Key('sd-character'),
          isExpanded: true,
          value: selected?.id,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('No one')),
            for (final c in chars)
              DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _characterId = v),
        ),
        const SizedBox(height: 8),
        Text('Mood: ${_moodLabel(mood)}', key: const Key('sd-mood')),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('sd-roll'),
            onPressed: () => _rollLine(data, selected),
            child: const Text('Roll line'),
          ),
        ),
        if (_dialogue != null) ...[
          const SizedBox(height: 16),
          _resultCard(theme, selected),
        ],
        ..._attribution(theme, data),
      ],
    );
  }

  Future<void> _rollLine(EmulatorData data, Character? selected) async {
    final e = await _currentEmulation(selected);
    final r = rollDialogue(_dice);
    // Per the source: doubles change the mood BEFORE the line — persist it
    // first, then read the line from the new mood's table.
    if (r.moodChanged) {
      await _updateEmulation(selected, (cur) => cur.copyWith(mood: r.newMood));
    }
    final mood = r.newMood ?? e.mood ?? 'default';
    setState(() {
      _dialogue = _DialogueOutcome(
        mood: mood,
        roll: r,
        line: data.dialogueLine(mood, r.lineKey),
        tone: data.tones[r.toneIx],
        topic: data.topics[r.topicIx],
        saidHow:
            '${data.saidHowA[r.saidHowAIx]}, ${data.saidHowB[r.saidHowBIx]}',
      );
      _voiced = null;
      _voiceError = null;
      _voicing = false;
    });
  }

  Widget _resultCard(ThemeData theme, Character? selected) {
    final d = _dialogue!;
    return Card(
      key: const Key('sd-result'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child:
                      Text('Sidekick line', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  key: const Key('sd-log'),
                  tooltip: 'Add to journal',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: () => _logDialogue(selected),
                ),
              ],
            ),
            Text('"${d.line}"',
                key: const Key('sd-result-line'),
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(d.lines.join('\n'), key: const Key('sd-result-lines')),
            _voiceArea(theme, selected),
          ],
        ),
      ),
    );
  }

  /// The "Voice this" affordance. Gated like the journal's Interpret action:
  /// hidden when the platform can't run the model, enabled only when the
  /// service is ready.
  Widget _voiceArea(ThemeData theme, Character? selected) {
    final service = ref.read(interpreterServiceProvider);
    return ValueListenableBuilder<InterpreterStatus>(
      valueListenable: service.status,
      builder: (context, status, _) {
        if (status.phase == InterpreterPhase.unsupported) {
          return const SizedBox.shrink();
        }
        final voiced = _voiced;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            if (voiced != null)
              Text('"$voiced"',
                  key: const Key('sd-voice-line'),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontStyle: FontStyle.italic))
            else if (_voiceError != null) ...[
              Text(
                'Could not voice this line. $_voiceError',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const Key('sd-voice-retry'),
                onPressed: () => _voice(selected),
                child: const Text('Retry'),
              ),
            ] else
              OutlinedButton.icon(
                key: const Key('sd-voice'),
                onPressed: status.phase == InterpreterPhase.ready && !_voicing
                    ? () => _voice(selected)
                    : null,
                icon: _voicing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.record_voice_over_outlined, size: 18),
                label: const Text('Voice this'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _voice(Character? selected) async {
    final d = _dialogue;
    if (d == null || _voicing) return;
    setState(() {
      _voicing = true;
      _voiceError = null;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      // Await the journal (nothing on this screen watches it), so recall
      // sees the entries even before the provider's first build completes.
      final entries = await ref.read(journalProvider.future);
      // Recall mirrors the journal's Interpret wiring: rank past entries
      // against the would-be journal entry for this result.
      final related = relatedEntries(
          entries,
          JournalEntry(
            id: 'sd-voice-target',
            timestamp: DateTime.now(),
            title: 'Sidekick — ${_moodLabel(d.mood)}',
            body: _dialogueBody(selected, d),
          ));
      final voiced =
          await ref.read(interpreterServiceProvider).voiceLine(VoiceSeed(
                line: d.line,
                mood: d.mood,
                tone: d.tone,
                topic: d.topic,
                characterName: selected?.name,
                characterTags: selected?.tags ?? const [],
                genre: settings.genre,
                toneSetting: settings.tone,
                journalContext: [
                  for (final e in related)
                    e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
                ],
              ));
      // A reroll while the model wrote makes this line stale — drop it.
      if (!mounted || _dialogue != d) return;
      setState(() {
        _voiced = voiced;
        _voicing = false;
      });
    } catch (e) {
      if (!mounted || _dialogue != d) return;
      setState(() {
        _voiceError = '$e';
        _voicing = false;
      });
    }
  }

  /// The journal body for the current dialogue result (also the recall
  /// target): character, quoted line, chips, dice, and the voiced line
  /// once one exists.
  String _dialogueBody(Character? selected, _DialogueOutcome d) => [
        if (selected != null) 'Character: ${selected.name}',
        '"${d.line}"',
        ...d.lines,
        if (_voiced != null) 'Voiced: "$_voiced"',
      ].join('\n');

  void _logDialogue(Character? selected) {
    final d = _dialogue!;
    ref
        .read(journalProvider.notifier)
        .add('Sidekick — ${_moodLabel(d.mood)}', _dialogueBody(selected, d));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to journal')),
    );
  }

  // -- Hexflower tab ----------------------------------------------------------

  Widget _hexTab(BuildContext context, EmulatorData data, Character? selected) {
    final theme = Theme.of(context);
    final current = _emulationOf(selected).hexIndex ?? 0;
    final hex = data.hex(current);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Topic: ${hex.topic} · Context: ${_contextLabel(hex.context)}',
          key: const Key('sd-hex-readout'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('sd-hex-step'),
            onPressed: () => _step(data, selected),
            child: const Text('Step (2d6)'),
          ),
        ),
        if (_hex != null) ...[
          const SizedBox(height: 16),
          _hexResultCard(theme, selected),
        ],
        const SizedBox(height: 16),
        Center(
          child: CustomPaint(
            key: const Key('sd-hex-canvas'),
            size: _FlowerPainter.canvasSize,
            painter: _FlowerPainter(
              hexes: [for (var i = 0; i < 19; i++) data.hex(i)],
              current: current,
              scheme: theme.colorScheme,
            ),
          ),
        ),
        ..._attribution(theme, data),
      ],
    );
  }

  Future<void> _step(EmulatorData data, Character? selected) async {
    final e = await _currentEmulation(selected);
    final from = e.hexIndex ?? 0;
    // Dice order (tests pin it): 2d6 direction, then d3 priority (me/you/us).
    final a = _dice.dN(6), b = _dice.dN(6);
    final d3 = _dice.dN(3);
    final to = data.hexStep(from, a + b);
    if (to != null) {
      await _updateEmulation(selected, (cur) => cur.copyWith(hexIndex: to));
    }
    final landed = data.hex(to ?? from);
    setState(() => _hex = _HexOutcome(
          dice: (a, b),
          direction: data.hexDirection(a + b),
          to: to,
          topic: landed.topic,
          context: landed.context,
          contextSwitch:
              to != null && data.hex(to).context != data.hex(from).context,
          d3: d3,
        ));
  }

  Widget _hexResultCard(ThemeData theme, Character? selected) {
    final h = _hex!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Conversation step',
                      style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  key: const Key('sd-hex-log'),
                  tooltip: 'Add to journal',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: () => _logHex(selected),
                ),
              ],
            ),
            Text(h.lines.join('\n'), key: const Key('sd-hex-lines')),
          ],
        ),
      ),
    );
  }

  void _logHex(Character? selected) {
    final h = _hex!;
    ref.read(journalProvider.notifier).add(
        'Hexflower — ${h.topic}',
        [
          if (selected != null) 'Character: ${selected.name}',
          'Topic: ${h.topic}',
          'Context: ${_contextLabel(h.context)}',
          ...h.lines,
        ].join('\n'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to journal')),
    );
  }
}

/// One rolled dialogue line with its chips, resolved against the mood it
/// was read under (post mood-change when the dice matched).
class _DialogueOutcome {
  const _DialogueOutcome({
    required this.mood,
    required this.roll,
    required this.line,
    required this.tone,
    required this.topic,
    required this.saidHow,
  });

  final String mood;
  final DialogueResult roll;
  final String line;
  final String tone;
  final String topic;
  final String saidHow;

  String get _diceLine => roll.moodChanged
      ? 'Rolls: ${roll.dice.$1} & ${roll.dice.$2} — doubles; reroll → ${roll.lineKey}'
      : 'Rolls: ${roll.dice.$1} & ${roll.dice.$2} → ${roll.lineKey}';

  List<String> get lines => [
        roll.moodChanged
            ? 'Mood changed → ${_moodLabel(mood)}'
            : 'Mood: ${_moodLabel(mood)}',
        'Tone: $tone · Topic: $topic',
        'Said: $saidHow',
        _diceLine,
      ];
}

/// One hexflower step: where the 2d6 walked (null = off the edge, stay
/// put), the d3 priority, and the now-current hex's topic/context.
class _HexOutcome {
  const _HexOutcome({
    required this.dice,
    required this.direction,
    required this.to,
    required this.topic,
    required this.context,
    required this.contextSwitch,
    required this.d3,
  });

  final (int, int) dice;
  final String direction;
  final int? to;
  final String topic;
  final String context;
  final bool contextSwitch;
  final int d3;

  String get priority => const ['me', 'you', 'us'][d3 - 1];

  List<String> get lines => [
        to == null ? 'Edge — stay put' : 'Stepped $direction → $topic',
        if (contextSwitch) 'Context switch',
        'Priority: $priority',
        'Rolls: ${dice.$1} & ${dice.$2} ($direction) · d3 $d3',
      ];
}

/// Read-only 19-hex flower: flat-top hexes laid out from axial q/r, gray
/// vs red context fills, topic labels, current hex ringed in primary.
class _FlowerPainter extends CustomPainter {
  _FlowerPainter({
    required this.hexes,
    required this.current,
    required this.scheme,
  });

  final List<HexInfo> hexes;
  final int current;
  final ColorScheme scheme;

  /// Hex radius (center to corner), in logical pixels.
  static const double hexSize = 26;

  /// q spans ±2 columns (1.5·size apart) plus a hex of margin each side;
  /// r+q/2 spans ±2 rows (√3·size apart) plus the hex's vertical extent.
  static const Size canvasSize = Size(8.4 * hexSize, 9 * hexSize);

  /// Axial flat-top → pixel, origin at the canvas center.
  Offset _center(HexInfo h, Size size) => Offset(
        size.width / 2 + 1.5 * hexSize * h.q,
        size.height / 2 + math.sqrt(3) * hexSize * (h.r + h.q / 2),
      );

  /// Flat-top hexagon: corners at 0, 60, … 300 degrees from the center.
  static Path _hexPath(Offset center, double size) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i;
      final v = center + Offset(size * math.cos(a), size * math.sin(a));
      i == 0 ? path.moveTo(v.dx, v.dy) : path.lineTo(v.dx, v.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final h in hexes) {
      final c = _center(h, size);
      final path = _hexPath(c, hexSize - 1);
      final fill = h.context == 'red'
          ? Color.alphaBlend(scheme.error.withValues(alpha: 0.25),
              scheme.surfaceContainerHighest)
          : scheme.surfaceContainerHighest;
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
          path,
          Paint()
            ..color = scheme.outlineVariant
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      if (h.index == current) {
        canvas.drawPath(
            path,
            Paint()
              ..color = scheme.primary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: h.topic,
          style: TextStyle(color: scheme.onSurface, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.hexes != hexes || old.current != current || old.scheme != scheme;
}
