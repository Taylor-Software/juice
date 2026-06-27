import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/custom_sheet.dart';
import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// The user-defined custom/homebrew sheet. Renders for characters whose
/// [Character.custom] is non-null. Two modes: Play (use the sheet) and Edit
/// (author the schema). Edits persist via charactersProvider.
class CustomSheetView extends ConsumerStatefulWidget {
  const CustomSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  @override
  ConsumerState<CustomSheetView> createState() => _CustomSheetViewState();
}

class _CustomSheetViewState extends ConsumerState<CustomSheetView> {
  late bool _editing = (widget.character.custom?.blocks.isEmpty ?? true);

  CustomSheet get _s => widget.character.custom ?? const CustomSheet();

  void _save(CustomSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(widget.character.copyWith(custom: next));

  // Defensive typed reads. A campaign file can be hand-edited or corrupted, so
  // a value of the wrong JSON shape must degrade gracefully (this file is
  // tolerant elsewhere) rather than throw a TypeError and crash the sheet.
  // Reused by every block renderer that reads a typed value.
  int _valInt(String id, int fallback) {
    final v = _s.values[id];
    return v is num ? v.toInt() : fallback;
  }

  Map<String, dynamic> _valMap(String id) {
    final v = _s.values[id];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  void _setVal(String id, dynamic value) =>
      _save(_s.copyWith(values: {..._s.values, id: value}));

  // base-36 of the microsecond clock -> compact, collision-safe block keys.
  String _newBlockId() =>
      'blk-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('custom-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
            key: const Key('sheet-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          Expanded(
            child: Text(widget.character.name,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            key: const Key('custom-mode-toggle'),
            icon: Icon(_editing ? Icons.visibility : Icons.edit_outlined),
            tooltip: _editing ? 'Play' : 'Edit layout',
            onPressed: () => setState(() => _editing = !_editing),
          ),
        ]),
        Text('Custom / Homebrew', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        if (_editing)
          _editList(s)
        else
          for (final b in s.blocks) _playBlock(b),
        if (_editing)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              key: const Key('custom-add-block'),
              icon: const Icon(Icons.add),
              label: const Text('Add block'),
              onPressed: _addBlock,
            ),
          ),
      ],
    );
  }

  Widget _editList(CustomSheet s) => ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // onReorderItem already adjusts newIndex for the removed item (Flutter
        // does `if (newIndex > oldIndex) newIndex -= 1` internally), so a
        // direct removeAt + insert is correct — do NOT subtract 1 again here.
        onReorderItem: (oldI, newI) {
          final list = [...s.blocks];
          final moved = list.removeAt(oldI);
          list.insert(newI, moved);
          _save(s.copyWith(blocks: list));
        },
        children: [
          for (final b in s.blocks)
            Card(
              key: ValueKey(b.id),
              child: ListTile(
                title: Text(b.label.isEmpty ? b.type.name : b.label),
                subtitle: Text(b.type.name),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    key: Key('custom-block-${b.id}-config'),
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => _configBlock(b),
                  ),
                  IconButton(
                    key: Key('custom-block-${b.id}-delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _save(s.copyWith(
                        blocks: s.blocks.where((x) => x.id != b.id).toList())),
                  ),
                ]),
              ),
            ),
        ],
      );

  Future<void> _addBlock() async {
    final type = await showDialog<CustomBlockType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add block'),
        children: [
          for (final t in CustomBlockType.values)
            SimpleDialogOption(
              key: Key('custom-add-type-${t.name}'),
              child: Text(t.name),
              onPressed: () => Navigator.pop(context, t),
            ),
        ],
      ),
    );
    if (type == null) return;
    final block = CustomBlock(
        id: _newBlockId(),
        type: type,
        label: _defaultLabel(type),
        config: defaultConfigFor(type));
    _save(_s.copyWith(blocks: [..._s.blocks, block]));
    if (mounted) _configBlock(block);
  }

  String _defaultLabel(CustomBlockType t) => switch (t) {
        CustomBlockType.stat => 'Abilities',
        CustomBlockType.counter => 'Counter',
        CustomBlockType.hp => 'HP',
        CustomBlockType.roll => 'Checks',
        CustomBlockType.luck => 'Luck',
        CustomBlockType.conditions => 'Conditions',
        CustomBlockType.dropdown => 'Class',
        CustomBlockType.freeform => 'Notes',
        CustomBlockType.timer => 'Timer',
        CustomBlockType.togglechips => 'Flags',
        CustomBlockType.progress => 'Tracks',
      };

  // --- play + config dispatch -------------------------------------------------

  Widget _playBlock(CustomBlock b) => switch (b.type) {
        CustomBlockType.freeform => _playFreeform(b),
        CustomBlockType.counter => _playCounter(b),
        CustomBlockType.stat => _playStat(b),
        CustomBlockType.conditions => _playConditions(b),
        _ => const SizedBox.shrink(),
      };

  Future<void> _configBlock(CustomBlock b) async {
    switch (b.type) {
      case CustomBlockType.counter:
        await _configCounter(b);
      case CustomBlockType.stat:
        await _configStat(b);
      default:
        await _renameBlock(b);
    }
  }

  // --- counter ---------------------------------------------------------------

  int _intCfg(CustomBlock b, String key, int fallback) =>
      (b.config[key] as num?)?.toInt() ?? fallback;

  Widget _playCounter(CustomBlock b) {
    final min = _intCfg(b, 'min', 0);
    final max = _intCfg(b, 'max', 999);
    final step = _intCfg(b, 'step', 1);
    final v = _valInt(b.id, min);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(b.label)),
        IconButton(
          key: Key('custom-${b.id}-counter-minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: v > min ? () => _setVal(b.id, v - step) : null,
        ),
        Text('$v'),
        IconButton(
          key: Key('custom-${b.id}-counter-plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: v < max ? () => _setVal(b.id, v + step) : null,
        ),
      ]),
    );
  }

  Future<void> _configCounter(CustomBlock b) async {
    final result = await showDialog<_CounterCfg>(
      context: context,
      builder: (_) => _CounterConfigDialog(block: b),
    );
    if (result == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id
                ? x.copyWith(
                    label: result.label.isEmpty ? x.label : result.label,
                    config: {
                      ...x.config,
                      'min': result.min,
                      'max': result.max,
                      'step': result.step,
                    })
                : x)
            .toList()));
  }

  // --- stat ------------------------------------------------------------------

  Widget _playStat(CustomBlock b) {
    final min = _intCfg(b, 'min', 3);
    final max = _intCfg(b, 'max', 18);
    final formula = statModFormulaFromName(b.config['modFormula'] as String?);
    final stats = ((b.config['stats'] as List?) ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .toList();
    final cur = _valMap(b.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, b.label),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final st in stats)
          () {
            final key = st['key'] as String;
            final label = (st['label'] as String?) ?? key.toUpperCase();
            final score = (cur[key] as num?)?.toInt() ?? ((min + max) ~/ 2);
            final modText = formula == StatModFormula.raw
                ? ''
                : fmtSigned(customStatMod(formula, score));
            return ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 80),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: const TextStyle(fontSize: 11)),
                if (modText.isNotEmpty)
                  Text(modText,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                Row(mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                    key: Key('custom-${b.id}-stat-$key-minus'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove, size: 16),
                    onPressed: score > min
                        ? () => _setVal(b.id, {...cur, key: score - 1})
                        : null,
                  ),
                  Text('$score'),
                  IconButton(
                    key: Key('custom-${b.id}-stat-$key-plus'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: score < max
                        ? () => _setVal(b.id, {...cur, key: score + 1})
                        : null,
                  ),
                ]),
              ]),
            );
          }(),
      ]),
    ]);
  }

  Future<void> _configStat(CustomBlock b) async {
    final result = await showDialog<_StatCfg>(
      context: context,
      builder: (_) => _StatConfigDialog(block: b),
    );
    if (result == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id
                ? x.copyWith(
                    label: result.label.isEmpty ? x.label : result.label,
                    config: {
                      ...x.config,
                      'stats': result.stats,
                      'min': result.min,
                      'max': result.max,
                      'modFormula': result.formula.name,
                    })
                : x)
            .toList()));
  }

  // --- conditions ------------------------------------------------------------

  Widget _playConditions(CustomBlock b) =>
      conditionsSection(context, ref, widget.character, 'custom-${b.id}');

  Future<void> _renameBlock(CustomBlock b) async {
    final name = await renameDialog(context,
        nameKey: 'custom-block-${b.id}-label', current: b.label);
    if (name == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id ? x.copyWith(label: name) : x)
            .toList()));
  }

  // --- freeform (placeholder real block) -------------------------------------

  Widget _playFreeform(CustomBlock b) {
    final raw = _s.values[b.id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        key: Key('custom-${b.id}-freeform'),
        initialValue: raw is String ? raw : '',
        maxLines: (b.config['multiline'] == true) ? 4 : 1,
        decoration: InputDecoration(labelText: b.label),
        onChanged: (v) => _setVal(b.id, v),
      ),
    );
  }
}

/// Default config for a freshly added block of [type].
Map<String, dynamic> defaultConfigFor(CustomBlockType type) => switch (type) {
      CustomBlockType.stat => {
          'stats': [
            {'key': 'str', 'label': 'STR'},
          ],
          'min': 3,
          'max': 18,
          'modFormula': StatModFormula.raw.name,
        },
      CustomBlockType.counter => {'min': 0, 'max': 999, 'step': 1},
      CustomBlockType.hp => {'allowTemp': false},
      CustomBlockType.dropdown => {'options': <String>[]},
      CustomBlockType.freeform => {'multiline': true},
      CustomBlockType.timer => {'start': 0},
      CustomBlockType.togglechips => {'options': <String>[]},
      _ => const {},
    };

// ---------------------------------------------------------------------------
// Config dialog result types + StatefulWidget dialogs.
// Using StatefulWidget (not StatefulBuilder + external controllers) so that
// TextEditingControllers are disposed by the widget's own dispose(), which
// runs after the route fully unmounts — not immediately after showDialog
// returns (which triggers "used after dispose" during the dismiss animation).
// ---------------------------------------------------------------------------

class _CounterCfg {
  const _CounterCfg(
      {required this.label,
      required this.min,
      required this.max,
      required this.step});
  final String label;
  final int min, max, step;
}

class _CounterConfigDialog extends StatefulWidget {
  const _CounterConfigDialog({required this.block});
  final CustomBlock block;

  @override
  State<_CounterConfigDialog> createState() => _CounterConfigDialogState();
}

class _CounterConfigDialogState extends State<_CounterConfigDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.block.label);
  late final TextEditingController _min = TextEditingController(
      text: '${(widget.block.config['min'] as num?)?.toInt() ?? 0}');
  late final TextEditingController _max = TextEditingController(
      text: '${(widget.block.config['max'] as num?)?.toInt() ?? 999}');
  late final TextEditingController _step = TextEditingController(
      text: '${(widget.block.config['step'] as num?)?.toInt() ?? 1}');

  @override
  void dispose() {
    _label.dispose();
    _min.dispose();
    _max.dispose();
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit block'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('custom-cfg-label'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            TextField(
              key: const Key('custom-cfg-min'),
              controller: _min,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Min'),
            ),
            TextField(
              key: const Key('custom-cfg-max'),
              controller: _max,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Max'),
            ),
            TextField(
              key: const Key('custom-cfg-step'),
              controller: _step,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Step'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                    context,
                    _CounterCfg(
                      label: _label.text.trim(),
                      min: int.tryParse(_min.text) ??
                          (widget.block.config['min'] as num?)?.toInt() ??
                          0,
                      max: int.tryParse(_max.text) ??
                          (widget.block.config['max'] as num?)?.toInt() ??
                          999,
                      step: int.tryParse(_step.text) ??
                          (widget.block.config['step'] as num?)?.toInt() ??
                          1,
                    ),
                  ),
              child: const Text('Save')),
        ],
      );
}

// ---------------------------------------------------------------------------

class _StatCfg {
  const _StatCfg(
      {required this.label,
      required this.min,
      required this.max,
      required this.formula,
      required this.stats});
  final String label;
  final int min, max;
  final StatModFormula formula;
  final List<Map<String, String>> stats;
}

class _StatConfigDialog extends StatefulWidget {
  const _StatConfigDialog({required this.block});
  final CustomBlock block;

  @override
  State<_StatConfigDialog> createState() => _StatConfigDialogState();
}

class _StatConfigDialogState extends State<_StatConfigDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.block.label);
  late final TextEditingController _min = TextEditingController(
      text: '${(widget.block.config['min'] as num?)?.toInt() ?? 3}');
  late final TextEditingController _max = TextEditingController(
      text: '${(widget.block.config['max'] as num?)?.toInt() ?? 18}');

  late StatModFormula _formula = statModFormulaFromName(
      widget.block.config['modFormula'] as String?);

  // One pair of controllers per stat row. Both lists grow/shrink together via
  // _addRow/_removeRow; every controller ever created is disposed in dispose().
  final List<TextEditingController> _keyCtls = [];
  final List<TextEditingController> _lblCtls = [];

  @override
  void initState() {
    super.initState();
    final rawStats = ((widget.block.config['stats'] as List?) ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .toList();
    for (final s in rawStats) {
      _keyCtls.add(TextEditingController(text: s['key'] as String? ?? ''));
      _lblCtls.add(TextEditingController(text: s['label'] as String? ?? ''));
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _min.dispose();
    _max.dispose();
    for (final c in _keyCtls) {
      c.dispose();
    }
    for (final c in _lblCtls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _keyCtls.add(TextEditingController(text: 'stat${_keyCtls.length + 1}'));
      _lblCtls.add(TextEditingController());
    });
  }

  void _removeRow(int i) {
    setState(() {
      // Dispose the removed row's controllers immediately — they are no longer
      // mounted in the tree, so disposing now (not in dispose()) is safe and
      // avoids leaking a controller per removed row.
      _keyCtls.removeAt(i).dispose();
      _lblCtls.removeAt(i).dispose();
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit block'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('custom-cfg-label'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            TextField(
              key: const Key('custom-cfg-min'),
              controller: _min,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Min'),
            ),
            TextField(
              key: const Key('custom-cfg-max'),
              controller: _max,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Max'),
            ),
            const SizedBox(height: 8),
            DropdownButton<StatModFormula>(
              key: const Key('custom-cfg-formula'),
              value: _formula,
              isExpanded: true,
              items: StatModFormula.values
                  .map((f) =>
                      DropdownMenuItem(value: f, child: Text(f.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _formula = v);
              },
            ),
            const SizedBox(height: 8),
            // Editable stat rows. Key each row by its key-controller identity so
            // a removal re-pairs the right element with the right controller
            // (index keys would shift a controller into a stale element).
            for (var i = 0; i < _keyCtls.length; i++)
              Row(key: ObjectKey(_keyCtls[i]), children: [
                Expanded(
                  child: TextField(
                    controller: _keyCtls[i],
                    decoration: const InputDecoration(labelText: 'Key'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lblCtls[i],
                    decoration: const InputDecoration(labelText: 'Label'),
                  ),
                ),
                IconButton(
                  key: Key('custom-cfg-stat-$i-remove'),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove',
                  onPressed: () => _removeRow(i),
                ),
              ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('custom-cfg-stat-add'),
                icon: const Icon(Icons.add),
                label: const Text('Add stat'),
                onPressed: _addRow,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                    context,
                    _StatCfg(
                      label: _label.text.trim(),
                      min: int.tryParse(_min.text) ??
                          (widget.block.config['min'] as num?)?.toInt() ??
                          3,
                      max: int.tryParse(_max.text) ??
                          (widget.block.config['max'] as num?)?.toInt() ??
                          18,
                      formula: _formula,
                      stats: [
                        for (var i = 0; i < _keyCtls.length; i++)
                          {
                            'key': _keyCtls[i].text,
                            'label': _lblCtls[i].text
                          },
                      ],
                    ),
                  ),
              child: const Text('Save')),
        ],
      );
}
