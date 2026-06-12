import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/emulator_data.dart';
import '../engine/models.dart';
import '../engine/party_emulator.dart';
import '../state/providers.dart';

/// Party Emulator — the Triple-O check: define the Obvious / Option / Odd
/// (or let dice assign group courses), roll or double-down, and let doubles
/// grow the character's Traits (party emulator phase 2).
class PartyEmulatorScreen extends ConsumerStatefulWidget {
  const PartyEmulatorScreen({super.key, this.dice});

  /// Injectable for deterministic tests; defaults to a fresh RNG.
  final Dice? dice;

  @override
  ConsumerState<PartyEmulatorScreen> createState() =>
      _PartyEmulatorScreenState();
}

class _PartyEmulatorScreenState extends ConsumerState<PartyEmulatorScreen> {
  late final Dice _dice = widget.dice ?? Dice();

  final _obvious = TextEditingController();
  final _option = TextEditingController();
  final _odd = TextEditingController();

  String? _characterId;
  bool _groupMode = false;

  /// Last group-assignment dice, slot-ordered [obvious, option, odd].
  List<int>? _assignedDice;

  TripleOResult? _result;

  /// The double-down favorite die; picking it resolves the band.
  int? _keptDie;

  static const _undefinedCourse = '(undefined — make it up now)';

  @override
  void dispose() {
    _obvious.dispose();
    _option.dispose();
    _odd.dispose();
    super.dispose();
  }

  /// Band of the current result: decided by the single die, or by the
  /// kept double-down die once the player picks a favorite.
  TripleOBand? get _band {
    final r = _result;
    if (r == null) return null;
    return r.band ?? (_keptDie == null ? null : bandFor(_keptDie!));
  }

  String _courseFor(TripleOBand band) {
    final text = switch (band) {
      TripleOBand.obvious => _obvious.text,
      TripleOBand.option => _option.text,
      TripleOBand.odd => _odd.text,
    }
        .trim();
    return text.isEmpty ? _undefinedCourse : text;
  }

  String _rollLine(TripleOResult r) {
    if (r.die != null) return 'Roll: ${r.die}';
    final (a, b) = r.dice!;
    return _keptDie == null
        ? 'Rolls: $a & $b'
        : 'Rolls: $a & $b — kept $_keptDie';
  }

  void _roll() => setState(() {
        _result = rollTripleO(_dice);
        _keptDie = null;
      });

  void _doubleDown() => setState(() {
        _result = rollDoubleDown(_dice);
        _keptDie = null;
      });

  /// Group mode: one d6 per course; reorder the field values into the
  /// obvious/option/odd slots (highest, middle, lowest).
  void _assign() {
    final rolls = [for (var i = 0; i < 3; i++) _dice.dN(6)];
    final order = assignOrder(rolls);
    final values = [_obvious.text, _option.text, _odd.text];
    setState(() {
      _obvious.text = values[order[0]];
      _option.text = values[order[1]];
      _odd.text = values[order[2]];
      _assignedDice = [for (final i in order) rolls[i]];
    });
  }

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
    final theme = Theme.of(context);
    final chars = ref.watch(charactersProvider).valueOrNull ?? const [];
    Character? selected;
    for (final c in chars) {
      if (c.id == _characterId) selected = c;
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Party Emulator', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        DropdownButton<String?>(
          key: const Key('pe-character'),
          isExpanded: true,
          value: selected?.id,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('No one')),
            for (final c in chars)
              DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _characterId = v),
        ),
        const SizedBox(height: 12),
        _checkCard(theme),
        if (_result != null) ...[
          const SizedBox(height: 16),
          _resultCard(theme, selected),
        ],
        const SizedBox(height: 24),
        for (final line in data.attribution)
          Text(
            line,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _checkCard(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Triple-O check',
                        style: theme.textTheme.titleMedium),
                  ),
                  Text('Group', style: theme.textTheme.bodyMedium),
                  Switch(
                    key: const Key('pe-group-mode'),
                    value: _groupMode,
                    onChanged: (v) => setState(() => _groupMode = v),
                  ),
                ],
              ),
              TextField(
                key: const Key('pe-obvious'),
                controller: _obvious,
                decoration: const InputDecoration(labelText: 'The Obvious'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('pe-option'),
                controller: _option,
                decoration: const InputDecoration(
                    labelText: 'The Option',
                    hintText: '(define after the roll)'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('pe-odd'),
                controller: _odd,
                decoration: const InputDecoration(
                    labelText: 'The Odd', hintText: '(define after the roll)'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('pe-roll'),
                    onPressed: _roll,
                    child: const Text('Roll d6'),
                  ),
                  OutlinedButton(
                    key: const Key('pe-double-down'),
                    onPressed: _doubleDown,
                    child: const Text('Double-Down (2d6)'),
                  ),
                  if (_groupMode)
                    OutlinedButton(
                      key: const Key('pe-assign'),
                      onPressed: _assign,
                      child: const Text('Assign by dice'),
                    ),
                ],
              ),
              if (_assignedDice != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Assigned by dice: ${_assignedDice!.join(' · ')}',
                  key: const Key('pe-assign-dice'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _resultCard(ThemeData theme, Character? selected) {
    final r = _result!;
    final band = _band;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Triple-O check',
                      style: theme.textTheme.titleMedium),
                ),
                if (band != null)
                  IconButton(
                    key: const Key('pe-log'),
                    tooltip: 'Add to journal',
                    icon: const Icon(Icons.bookmark_add_outlined),
                    onPressed: () => _log(selected),
                  ),
              ],
            ),
            Text(_rollLine(r), key: const Key('pe-result-roll')),
            const SizedBox(height: 8),
            if (band == null)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('pe-keep-0'),
                    onPressed: () => setState(() => _keptDie = r.dice!.$1),
                    child: Text('Keep ${r.dice!.$1}'),
                  ),
                  OutlinedButton(
                    key: const Key('pe-keep-1'),
                    onPressed: () => setState(() => _keptDie = r.dice!.$2),
                    child: Text('Keep ${r.dice!.$2}'),
                  ),
                ],
              )
            else ...[
              Text(band.label,
                  key: const Key('pe-result-band'),
                  style: theme.textTheme.titleLarge),
              Text(_courseFor(band),
                  key: const Key('pe-result-course'),
                  style: theme.textTheme.bodyLarge),
              if (r.isDoubles) _doublesBanner(theme, selected),
            ],
          ],
        ),
      ),
    );
  }

  Widget _doublesBanner(ThemeData theme, Character? selected) => Container(
        key: const Key('pe-doubles'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Doubles — this behavior grows',
                style: theme.textTheme.titleSmall),
            if (selected != null)
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _markProminent(selected),
                    child: const Text('Mark trait prominent'),
                  ),
                  TextButton(
                    onPressed: () => _addTrait(selected),
                    child: const Text('Add new trait'),
                  ),
                ],
              ),
          ],
        ),
      );

  Future<void> _markProminent(Character c) async {
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Mark trait prominent'),
        children: [
          if (c.tags.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('No tags yet — add a new trait instead.'),
            ),
          for (final t in c.tags)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t),
              child: Text(t),
            ),
        ],
      ),
    );
    if (tag == null) return;
    final emulation = c.emulation ?? const CharacterEmulation();
    if (emulation.prominentTags.contains(tag)) return;
    await ref.read(charactersProvider.notifier).replace(c.copyWith(
        emulation: emulation
            .copyWith(prominentTags: [...emulation.prominentTags, tag])));
  }

  Future<void> _addTrait(Character c) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Add new trait'),
          content: TextField(
            key: const Key('pe-trait-input'),
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Trait'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    final trait = result?.trim() ?? '';
    if (trait.isEmpty || c.tags.contains(trait)) return;
    await ref
        .read(charactersProvider.notifier)
        .replace(c.copyWith(tags: [...c.tags, trait]));
  }

  void _log(Character? selected) {
    final r = _result!;
    final band = _band!;
    final lines = [
      if (selected != null) 'Character: ${selected.name}',
      for (final b in TripleOBand.values) '${b.label}: ${_courseFor(b)}',
      _rollLine(r),
      if (r.isDoubles) 'Doubles — this behavior grows into a Trait.',
    ];
    ref
        .read(journalProvider.notifier)
        .add('Triple-O — ${band.label}', lines.join('\n'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to journal')),
    );
  }
}
