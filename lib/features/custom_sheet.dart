import 'dart:math';

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

  List<dynamic> _valList(String id) {
    final v = _s.values[id];
    return v is List ? v : const [];
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
        CustomBlockType.computed => 'Computed',
      };

  // --- play + config dispatch -------------------------------------------------

  Widget _playBlock(CustomBlock b) => switch (b.type) {
        CustomBlockType.freeform => _playFreeform(b),
        CustomBlockType.counter => _playCounter(b),
        CustomBlockType.stat => _playStat(b),
        CustomBlockType.conditions => _playConditions(b),
        CustomBlockType.roll => _playRoll(b),
        CustomBlockType.luck => _playLuck(b),
        CustomBlockType.hp => _playHp(b),
        CustomBlockType.dropdown => _playDropdown(b),
        CustomBlockType.timer => _playTimer(b),
        CustomBlockType.togglechips => _playToggleChips(b),
        CustomBlockType.progress => _playProgress(b),
        CustomBlockType.computed => _playComputed(b),
      };

  Future<void> _configBlock(CustomBlock b) async {
    switch (b.type) {
      case CustomBlockType.counter:
        await _configCounter(b);
      case CustomBlockType.stat:
        await _configStat(b);
      case CustomBlockType.roll:
        await _configRoll(b);
      case CustomBlockType.luck:
        await _configLuck(b);
      case CustomBlockType.hp:
        await _configHp(b);
      case CustomBlockType.dropdown:
        await _configDropdown(b);
      case CustomBlockType.timer:
        await _configTimer(b);
      case CustomBlockType.togglechips:
        await _configToggleChips(b);
      case CustomBlockType.computed:
        await _configComputed(b);
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

  // --- roll ------------------------------------------------------------------

  Widget _playRoll(CustomBlock b) {
    final rows =
        ((b.config['rows'] as List?) ?? const []).whereType<String>().toList();
    final cfg = RollConfig.fromJson(b.config['roll']);
    final raw = _valList(b.id);
    final bonuses = [
      for (var i = 0; i < rows.length; i++)
        (i < raw.length ? (raw[i] as num?)?.toInt() ?? 0 : 0)
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, b.label),
      for (var i = 0; i < rows.length; i++)
        rollTrackRow(
          prefix: 'custom-${b.id}',
          index: i,
          label: rows[i],
          bonus: bonuses[i],
          onBonus: (v) {
            final next = [...bonuses]..[i] = v;
            _setVal(b.id, next);
          },
          onRoll: () => _doRoll(b, cfg, rows[i], bonuses[i]),
        ),
    ]);
  }

  Future<void> _doRoll(
      CustomBlock b, RollConfig cfg, String label, int bonus) async {
    int? promptTarget;
    if (cfg.targetKind == RollTargetKind.prompt) {
      promptTarget = await _promptInt('Target / DC');
      if (promptTarget == null) return;
    }
    final rng = Random();
    final dice = [
      for (var i = 0; i < cfg.diceCount; i++) rng.nextInt(cfg.diceSides) + 1
    ];
    final out = resolveRoll(cfg, bonus, dice, promptTarget: promptTarget);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label: ${out.total} — ${out.label}'),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<int?> _promptInt(String label) {
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => _IntPromptDialog(label: label),
    );
  }

  Future<void> _configRoll(CustomBlock b) async {
    final result = await showDialog<_RollCfg>(
      context: context,
      builder: (_) => _RollConfigDialog(block: b),
    );
    if (result == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id
                ? x.copyWith(
                    label: result.label.isEmpty ? x.label : result.label,
                    config: {
                      ...x.config,
                      'rows': result.rows,
                      'roll': result.rollConfig.toJson(),
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
          if (st['key'] is String)
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

  // --- luck ------------------------------------------------------------------

  Widget _playLuck(CustomBlock b) {
    final v = _valMap(b.id);
    final cur = (v['cur'] as num?)?.toInt() ?? 0;
    final max = (v['max'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      // Uses the shared DCC luckTokensSection brick. keyPrefix '<id>-luck' keeps
      // the spend key as 'custom-<id>-luck-spend'; the brick also renders a gain
      // (+1) button and a 'restore' reset.
      child: luckTokensSection(
        keyPrefix: 'custom-${b.id}-luck',
        label: b.label,
        current: cur,
        max: max,
        onSet: (next) => _setVal(b.id, {'cur': next, 'max': max}),
        onReset: () => _setVal(b.id, {'cur': max, 'max': max}),
      ),
    );
  }

  Future<void> _configLuck(CustomBlock b) async {
    final currentMax = (_valMap(b.id)['max'] as num?)?.toInt() ?? 0;
    final result = await showDialog<_LuckCfg>(
      context: context,
      builder: (_) => _LuckConfigDialog(block: b, initialMax: currentMax),
    );
    if (result == null) return;
    // Persist label (block) and max value (play state) in one save.
    final updatedBlocks = _s.blocks
        .map((x) => x.id == b.id
            ? x.copyWith(
                label: result.label.isEmpty ? x.label : result.label)
            : x)
        .toList();
    _save(_s.copyWith(
      blocks: updatedBlocks,
      values: {..._s.values, b.id: {'cur': result.max, 'max': result.max}},
    ));
  }

  // --- hp --------------------------------------------------------------------

  Widget _playHp(CustomBlock b) {
    final v = _valMap(b.id);
    final cur = (v['cur'] as num?)?.toInt() ?? 0;
    final max = (v['max'] as num?)?.toInt() ?? 0;
    final temp = (v['temp'] as num?)?.toInt() ?? 0;
    final allowTemp = b.config['allowTemp'] == true;
    void set(Map<String, dynamic> next) => _setVal(b.id, {...v, ...next});
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
      SizedBox(width: 64, child: Text(b.label)),
      IconButton(
          key: Key('custom-${b.id}-hp-cur-minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => set({'cur': cur - 1})),
      Text('$cur / $max'),
      IconButton(
          key: Key('custom-${b.id}-hp-cur-plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => set({'cur': cur + 1})),
      const SizedBox(width: 8),
      const Text('Max'),
      IconButton(
          key: Key('custom-${b.id}-hp-max-minus'),
          icon: const Icon(Icons.remove, size: 16),
          onPressed: () => set({'max': max - 1})),
      IconButton(
          key: Key('custom-${b.id}-hp-max-plus'),
          icon: const Icon(Icons.add, size: 16),
          onPressed: () => set({'max': max + 1})),
      if (allowTemp) ...[
        const SizedBox(width: 8),
        const Text('Temp'),
        IconButton(
            key: Key('custom-${b.id}-hp-temp-minus'),
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => set({'temp': temp - 1})),
        Text('$temp'),
        IconButton(
            key: Key('custom-${b.id}-hp-temp-plus'),
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => set({'temp': temp + 1})),
      ],
    ]);
  }

  Future<void> _configHp(CustomBlock b) async {
    final result = await showDialog<_HpCfg>(
      context: context,
      builder: (_) => _HpConfigDialog(block: b),
    );
    if (result == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id
                ? x.copyWith(
                    label: result.label.isEmpty ? x.label : result.label,
                    config: {
                      ...x.config,
                      'allowTemp': result.allowTemp,
                    })
                : x)
            .toList()));
  }

  // --- dropdown --------------------------------------------------------------

  Widget _playDropdown(CustomBlock b) {
    final options =
        ((b.config['options'] as List?) ?? const []).whereType<String>().toList();
    final raw = _s.values[b.id];
    final value = raw is String ? raw : (options.isEmpty ? '' : options.first);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 96, child: Text(b.label)),
        Expanded(
          child: DropdownButton<String>(
            key: Key('custom-${b.id}-dropdown'),
            isExpanded: true,
            value: options.contains(value) ? value : (options.isEmpty ? null : options.first),
            items: [
              for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) => v == null ? null : _setVal(b.id, v),
          ),
        ),
      ]),
    );
  }

  Future<void> _configDropdown(CustomBlock b) async {
    final result = await showDialog<_DropdownCfg>(
      context: context,
      builder: (_) => _DropdownConfigDialog(block: b),
    );
    if (result == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id
                ? x.copyWith(
                    label: result.label.isEmpty ? x.label : result.label,
                    config: {
                      ...x.config,
                      'options': result.options,
                    })
                : x)
            .toList()));
  }

  // --- conditions ------------------------------------------------------------

  Widget _playConditions(CustomBlock b) =>
      conditionsSection(context, ref, widget.character, 'custom-${b.id}');

  // --- timer -----------------------------------------------------------------

  Widget _playTimer(CustomBlock b) {
    final v = _valInt(b.id, _intCfg(b, 'start', 0));
    return Row(children: [
      Expanded(child: Text(b.label)),
      IconButton(
          key: Key('custom-${b.id}-timer-dec'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: v > 0 ? () => _setVal(b.id, v - 1) : null),
      Text('$v'),
      IconButton(
          key: Key('custom-${b.id}-timer-inc'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _setVal(b.id, v + 1)),
      const SizedBox(width: 8),
      Text(v > 0 ? 'lit' : 'out',
          style: TextStyle(
              color: v > 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error)),
    ]);
  }

  Future<void> _configTimer(CustomBlock b) async {
    final result = await showDialog<_TimerCfg>(
      context: context,
      builder: (_) => _TimerConfigDialog(block: b),
    );
    if (result == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id
                ? x.copyWith(
                    label: result.label.isEmpty ? x.label : result.label,
                    config: {
                      ...x.config,
                      'start': result.start,
                    })
                : x)
            .toList()));
  }

  // --- toggle-chips ----------------------------------------------------------

  Widget _playToggleChips(CustomBlock b) {
    final options =
        ((b.config['options'] as List?) ?? const []).whereType<String>().toList();
    final selected =
        (_valList(b.id).whereType<String>().toSet());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, b.label),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final o in options)
          FilterChip(
            key: Key('custom-${b.id}-chip-$o'),
            label: Text(o),
            selected: selected.contains(o),
            onSelected: (on) {
              final next = {...selected};
              on ? next.add(o) : next.remove(o);
              _setVal(b.id, next.toList());
            },
          ),
      ]),
    ]);
  }

  Future<void> _configToggleChips(CustomBlock b) async {
    final result = await showDialog<_DropdownCfg>(
      context: context,
      builder: (_) => _ToggleChipsConfigDialog(block: b),
    );
    if (result == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id
                ? x.copyWith(
                    label: result.label.isEmpty ? x.label : result.label,
                    config: {
                      ...x.config,
                      'options': result.options,
                    })
                : x)
            .toList()));
  }

  // --- progress --------------------------------------------------------------

  Widget _playProgress(CustomBlock b) {
    final tracks = (_valList(b.id))
        .map(ProgressTrack.maybeFromJson)
        .whereType<ProgressTrack>()
        .toList();
    void persist(List<ProgressTrack> next) =>
        _setVal(b.id, next.map((t) => t.toJson()).toList());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: sheetSection(context, b.label)),
        IconButton(
          key: Key('custom-${b.id}-progress-add'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () async {
            final t = await addProgressTrackDialog(context,
                nameKey: 'custom-${b.id}-track-name', label: 'Track');
            if (t != null) persist([...tracks, t]);
          },
        ),
      ]),
      for (var i = 0; i < tracks.length; i++)
        progressTrackRow(
          context: context,
          prefix: 'custom-${b.id}-trk',
          index: i,
          track: tracks[i],
          onChanged: (t) {
            final next = [...tracks]..[i] = t;
            persist(next);
          },
          onDelete: () {
            final next = [...tracks]..removeAt(i);
            persist(next);
          },
        ),
    ]);
  }

  // --- computed -----------------------------------------------------------------

  Widget _playComputed(CustomBlock b) {
    final cfg = ComputedConfig.maybeFromJson(b.config);
    final r = resolveComputed(_s.blocks, _s.values, cfg);
    if (r.flag != null) {
      return r.flag!
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                    key: Key('custom-${b.id}-computed-chip'),
                    label: Text(b.label)),
              ),
            )
          : const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text('${b.label}: ${r.number ?? 0}',
          key: Key('custom-${b.id}-computed')),
    );
  }

  Future<void> _configComputed(CustomBlock b) async {
    final result = await showDialog<ComputedConfig>(
      context: context,
      builder: (_) => _ComputedConfigDialog(block: b, blocks: _s.blocks),
    );
    if (result == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id ? x.copyWith(config: result.toJson()) : x)
            .toList()));
  }

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
      CustomBlockType.roll => {
          'rows': ['Row 1'],
          'roll': const RollConfig().toJson(),
        },
      CustomBlockType.dropdown => {'options': <String>[]},
      CustomBlockType.freeform => {'multiline': true},
      CustomBlockType.timer => {'start': 0},
      CustomBlockType.togglechips => {'options': <String>[]},
      CustomBlockType.computed => const ComputedConfig(
          a: ComputedOperand(), op: ComputedOp.add, b: ComputedOperand()).toJson(),
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

// ---------------------------------------------------------------------------

class _RollCfg {
  const _RollCfg({
    required this.label,
    required this.rows,
    required this.rollConfig,
  });
  final String label;
  final List<String> rows;
  final RollConfig rollConfig;
}

class _RollConfigDialog extends StatefulWidget {
  const _RollConfigDialog({required this.block});
  final CustomBlock block;

  @override
  State<_RollConfigDialog> createState() => _RollConfigDialogState();
}

class _RollConfigDialogState extends State<_RollConfigDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.block.label);

  // Row label controllers — growable; disposed when removed or in dispose().
  final List<TextEditingController> _rowCtls = [];

  // RollConfig knobs
  late final TextEditingController _count;
  late final TextEditingController _sides;
  late final TextEditingController _fixedTarget;
  late RollDirection _direction;
  late bool _addBonus;
  late RollTargetKind _targetKind;
  late RollCrit _crit;

  // Band (degree-of-success) controllers — threshold + label per band.
  final List<TextEditingController> _bandThreshCtls = [];
  final List<TextEditingController> _bandLblCtls = [];

  @override
  void initState() {
    super.initState();
    final rows =
        ((widget.block.config['rows'] as List?) ?? const []).whereType<String>();
    for (final r in rows) {
      _rowCtls.add(TextEditingController(text: r));
    }

    final cfg = RollConfig.fromJson(widget.block.config['roll']);
    _count = TextEditingController(text: '${cfg.diceCount}');
    _sides = TextEditingController(text: '${cfg.diceSides}');
    _fixedTarget = TextEditingController(text: '${cfg.fixedTarget}');
    _direction = cfg.direction;
    _addBonus = cfg.addBonus;
    _targetKind = cfg.targetKind;
    _crit = cfg.crit;

    for (final band in cfg.bands) {
      _bandThreshCtls.add(
          TextEditingController(text: band.threshold.toStringAsFixed(2)));
      _bandLblCtls.add(TextEditingController(text: band.label));
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _count.dispose();
    _sides.dispose();
    _fixedTarget.dispose();
    for (final c in _rowCtls) {
      c.dispose();
    }
    for (final c in _bandThreshCtls) {
      c.dispose();
    }
    for (final c in _bandLblCtls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _rowCtls.add(TextEditingController(text: 'Row ${_rowCtls.length + 1}'));
    });
  }

  void _removeRow(int i) {
    setState(() {
      _rowCtls.removeAt(i).dispose();
    });
  }

  void _addBand() {
    setState(() {
      _bandThreshCtls.add(TextEditingController(text: '10.00'));
      _bandLblCtls.add(TextEditingController(text: 'Success'));
    });
  }

  void _removeBand(int i) {
    setState(() {
      _bandThreshCtls.removeAt(i).dispose();
      _bandLblCtls.removeAt(i).dispose();
    });
  }

  RollConfig _buildConfig() => RollConfig(
        diceCount: int.tryParse(_count.text) ?? 1,
        diceSides: int.tryParse(_sides.text) ?? 20,
        addBonus: _addBonus,
        direction: _direction,
        targetKind: _targetKind,
        fixedTarget: int.tryParse(_fixedTarget.text) ?? 10,
        crit: _crit,
        bands: [
          for (var i = 0; i < _bandThreshCtls.length; i++)
            RollBand(
              threshold: double.tryParse(_bandThreshCtls[i].text) ?? 0,
              label: _bandLblCtls[i].text,
            ),
        ],
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit block'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Block label
            TextField(
              key: const Key('custom-cfg-label'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 12),

            // --- Row labels ---
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Rows', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (var i = 0; i < _rowCtls.length; i++)
              Row(key: ObjectKey(_rowCtls[i]), children: [
                Expanded(
                  child: TextField(
                    controller: _rowCtls[i],
                    decoration: const InputDecoration(labelText: 'Row label'),
                  ),
                ),
                IconButton(
                  key: Key('custom-cfg-roll-$i-remove'),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove',
                  onPressed: () => _removeRow(i),
                ),
              ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('custom-cfg-roll-add'),
                icon: const Icon(Icons.add),
                label: const Text('Add row'),
                onPressed: _addRow,
              ),
            ),
            const SizedBox(height: 12),

            // --- RollConfig knobs ---
            const Align(
              alignment: Alignment.centerLeft,
              child:
                  Text('Roll', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('custom-cfg-roll-count'),
                  controller: _count,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dice count'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('custom-cfg-roll-sides'),
                  controller: _sides,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dice sides'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            DropdownButton<RollDirection>(
              key: const Key('custom-cfg-roll-dir'),
              value: _direction,
              isExpanded: true,
              items: RollDirection.values
                  .map((d) => DropdownMenuItem(value: d, child: Text(d.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _direction = v;
                    // roll bonus is ignored for direction==low — disable the toggle
                    if (v == RollDirection.low) _addBonus = false;
                  });
                }
              },
            ),
            // roll bonus is ignored for direction==low — disable the switch
            SwitchListTile(
              key: const Key('custom-cfg-roll-bonus'),
              title: const Text('Add per-row bonus'),
              value: _addBonus,
              // Bonus is meaningless for roll-under (direction==low); disable
              // the switch so users can't enable an option that has no effect.
              onChanged: _direction == RollDirection.low
                  ? null
                  : (v) => setState(() => _addBonus = v),
            ),
            DropdownButton<RollTargetKind>(
              key: const Key('custom-cfg-roll-target'),
              value: _targetKind,
              isExpanded: true,
              items: RollTargetKind.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _targetKind = v);
              },
            ),
            if (_targetKind == RollTargetKind.fixed)
              TextField(
                controller: _fixedTarget,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Fixed target'),
              ),
            DropdownButton<RollCrit>(
              key: const Key('custom-cfg-roll-crit'),
              value: _crit,
              isExpanded: true,
              items: RollCrit.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _crit = v);
              },
            ),
            const SizedBox(height: 12),

            // --- Bands (degrees of success) ---
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Degrees of success',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (var i = 0; i < _bandThreshCtls.length; i++)
              Row(key: ObjectKey(_bandThreshCtls[i]), children: [
                Expanded(
                  child: TextField(
                    controller: _bandThreshCtls[i],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Threshold'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _bandLblCtls[i],
                    decoration: const InputDecoration(labelText: 'Label'),
                  ),
                ),
                IconButton(
                  key: Key('custom-cfg-roll-band-$i-remove'),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove',
                  onPressed: () => _removeBand(i),
                ),
              ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('custom-cfg-roll-band-add'),
                icon: const Icon(Icons.add),
                label: const Text('Add band'),
                onPressed: _addBand,
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
                    _RollCfg(
                      label: _label.text.trim(),
                      rows: _rowCtls.map((c) => c.text).toList(),
                      rollConfig: _buildConfig(),
                    ),
                  ),
              child: const Text('Save')),
        ],
      );
}

// ---------------------------------------------------------------------------

class _LuckCfg {
  const _LuckCfg({required this.label, required this.max});
  final String label;
  final int max;
}

class _LuckConfigDialog extends StatefulWidget {
  const _LuckConfigDialog({required this.block, required this.initialMax});
  final CustomBlock block;
  final int initialMax;

  @override
  State<_LuckConfigDialog> createState() => _LuckConfigDialogState();
}

class _LuckConfigDialogState extends State<_LuckConfigDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.block.label);
  late int _max = widget.initialMax;

  @override
  void dispose() {
    _label.dispose();
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
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('Max tokens')),
              IconButton(
                key: const Key('custom-cfg-luck-max-minus'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _max > 0 ? () => setState(() => _max--) : null,
              ),
              Text('$_max'),
              IconButton(
                key: const Key('custom-cfg-luck-max-plus'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _max++),
              ),
            ]),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                    context,
                    _LuckCfg(label: _label.text.trim(), max: _max),
                  ),
              child: const Text('Save')),
        ],
      );
}

// ---------------------------------------------------------------------------

class _HpCfg {
  const _HpCfg({required this.label, required this.allowTemp});
  final String label;
  final bool allowTemp;
}

class _HpConfigDialog extends StatefulWidget {
  const _HpConfigDialog({required this.block});
  final CustomBlock block;

  @override
  State<_HpConfigDialog> createState() => _HpConfigDialogState();
}

class _HpConfigDialogState extends State<_HpConfigDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.block.label);
  late bool _allowTemp = widget.block.config['allowTemp'] == true;

  @override
  void dispose() {
    _label.dispose();
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
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('custom-cfg-hp-temp'),
              title: const Text('Allow temp HP'),
              value: _allowTemp,
              onChanged: (v) => setState(() => _allowTemp = v),
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
                    _HpCfg(label: _label.text.trim(), allowTemp: _allowTemp),
                  ),
              child: const Text('Save')),
        ],
      );
}

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------

class _TimerCfg {
  const _TimerCfg({required this.label, required this.start});
  final String label;
  final int start;
}

class _TimerConfigDialog extends StatefulWidget {
  const _TimerConfigDialog({required this.block});
  final CustomBlock block;

  @override
  State<_TimerConfigDialog> createState() => _TimerConfigDialogState();
}

class _TimerConfigDialogState extends State<_TimerConfigDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.block.label);
  late int _start = (widget.block.config['start'] as num?)?.toInt() ?? 0;

  @override
  void dispose() {
    _label.dispose();
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
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('Start')),
              IconButton(
                key: const Key('custom-cfg-timer-start-minus'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _start > 0 ? () => setState(() => _start--) : null,
              ),
              Text('$_start'),
              IconButton(
                key: const Key('custom-cfg-timer-start-plus'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _start++),
              ),
            ]),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                    context,
                    _TimerCfg(label: _label.text.trim(), start: _start),
                  ),
              child: const Text('Save')),
        ],
      );
}

// ---------------------------------------------------------------------------

class _DropdownCfg {
  const _DropdownCfg({required this.label, required this.options});
  final String label;
  final List<String> options;
}

class _DropdownConfigDialog extends StatefulWidget {
  const _DropdownConfigDialog({required this.block});
  final CustomBlock block;

  @override
  State<_DropdownConfigDialog> createState() => _DropdownConfigDialogState();
}

class _DropdownConfigDialogState extends State<_DropdownConfigDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.block.label);

  // One controller per option — growable; disposed when removed or in dispose().
  final List<TextEditingController> _optCtls = [];

  @override
  void initState() {
    super.initState();
    final rawOptions =
        ((widget.block.config['options'] as List?) ?? const []).whereType<String>();
    for (final o in rawOptions) {
      _optCtls.add(TextEditingController(text: o));
    }
  }

  @override
  void dispose() {
    _label.dispose();
    for (final c in _optCtls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() {
      _optCtls.add(TextEditingController(text: 'Option ${_optCtls.length + 1}'));
    });
  }

  void _removeOption(int i) {
    setState(() {
      _optCtls.removeAt(i).dispose();
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
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Options', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (var i = 0; i < _optCtls.length; i++)
              Row(key: ObjectKey(_optCtls[i]), children: [
                Expanded(
                  child: TextField(
                    controller: _optCtls[i],
                    decoration: const InputDecoration(labelText: 'Option'),
                  ),
                ),
                IconButton(
                  key: Key('custom-cfg-opt-$i-remove'),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove',
                  onPressed: () => _removeOption(i),
                ),
              ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('custom-cfg-opt-add'),
                icon: const Icon(Icons.add),
                label: const Text('Add option'),
                onPressed: _addOption,
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
                    _DropdownCfg(
                      label: _label.text.trim(),
                      options: _optCtls.map((c) => c.text).toList(),
                    ),
                  ),
              child: const Text('Save')),
        ],
      );
}

// ---------------------------------------------------------------------------
// Toggle-chips config dialog — same options-list pattern as _DropdownConfigDialog
// but persisted via _configToggleChips → config['options'].
// ---------------------------------------------------------------------------

class _ToggleChipsConfigDialog extends StatefulWidget {
  const _ToggleChipsConfigDialog({required this.block});
  final CustomBlock block;

  @override
  State<_ToggleChipsConfigDialog> createState() =>
      _ToggleChipsConfigDialogState();
}

class _ToggleChipsConfigDialogState extends State<_ToggleChipsConfigDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.block.label);

  // One controller per option — growable; disposed when removed or in dispose().
  final List<TextEditingController> _optCtls = [];

  @override
  void initState() {
    super.initState();
    final rawOptions =
        ((widget.block.config['options'] as List?) ?? const [])
            .whereType<String>();
    for (final o in rawOptions) {
      _optCtls.add(TextEditingController(text: o));
    }
  }

  @override
  void dispose() {
    _label.dispose();
    for (final c in _optCtls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() {
      _optCtls.add(
          TextEditingController(text: 'Option ${_optCtls.length + 1}'));
    });
  }

  void _removeOption(int i) {
    setState(() {
      _optCtls.removeAt(i).dispose();
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
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child:
                  Text('Options', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (var i = 0; i < _optCtls.length; i++)
              Row(key: ObjectKey(_optCtls[i]), children: [
                Expanded(
                  child: TextField(
                    controller: _optCtls[i],
                    decoration: const InputDecoration(labelText: 'Option'),
                  ),
                ),
                IconButton(
                  key: Key('custom-cfg-opt-$i-remove'),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove',
                  onPressed: () => _removeOption(i),
                ),
              ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('custom-cfg-opt-add'),
                icon: const Icon(Icons.add),
                label: const Text('Add option'),
                onPressed: _addOption,
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
                    _DropdownCfg(
                      label: _label.text.trim(),
                      options: _optCtls.map((c) => c.text).toList(),
                    ),
                  ),
              child: const Text('Save')),
        ],
      );
}

// ---------------------------------------------------------------------------

class _ComputedConfigDialog extends StatefulWidget {
  const _ComputedConfigDialog({required this.block, required this.blocks});
  final CustomBlock block;
  final List<CustomBlock> blocks;

  @override
  State<_ComputedConfigDialog> createState() => _ComputedConfigDialogState();
}

class _ComputedConfigDialogState extends State<_ComputedConfigDialog> {
  late ComputedConfig _cfg = ComputedConfig.maybeFromJson(widget.block.config);

  static const _refTypes = {
    CustomBlockType.stat,
    CustomBlockType.hp,
    CustomBlockType.luck,
    CustomBlockType.counter,
    CustomBlockType.timer,
  };

  List<CustomBlock> get _refBlocks =>
      widget.blocks.where((x) => _refTypes.contains(x.type)).toList();

  List<String> _subKeysFor(String blockId) {
    CustomBlock? b;
    for (final x in widget.blocks) {
      if (x.id == blockId) {
        b = x;
        break;
      }
    }
    if (b == null) return const [];
    switch (b.type) {
      case CustomBlockType.stat:
        return [
          for (final s in (b.config['stats'] as List?) ?? const [])
            if (s is Map && s['key'] is String) s['key'] as String,
        ];
      case CustomBlockType.hp:
      case CustomBlockType.luck:
        return const ['cur', 'max'];
      default:
        return const [];
    }
  }

  Widget _operandEditor(
      String title, ComputedOperand o, ValueChanged<ComputedOperand> onChange) {
    final refs = _refBlocks;
    final subKeys = _subKeysFor(o.blockId);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      Row(children: [
        ChoiceChip(
          label: const Text('Constant'),
          selected: o.isConst,
          onSelected: (_) => onChange(o.copyWith(isConst: true)),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Reference'),
          selected: !o.isConst,
          onSelected: refs.isEmpty
              ? null
              : (_) => onChange(o.copyWith(
                  isConst: false,
                  blockId: o.blockId.isEmpty ? refs.first.id : o.blockId)),
        ),
      ]),
      if (o.isConst)
        TextFormField(
          initialValue: '${o.constant}',
          decoration: const InputDecoration(labelText: 'Value'),
          keyboardType: TextInputType.number,
          onChanged: (v) => onChange(o.copyWith(constant: int.tryParse(v) ?? 0)),
        )
      else ...[
        DropdownButton<String>(
          isExpanded: true,
          value: refs.any((x) => x.id == o.blockId) ? o.blockId : null,
          hint: const Text('Block'),
          items: [
            for (final x in refs)
              DropdownMenuItem(value: x.id, child: Text(x.label)),
          ],
          onChanged: (v) {
            if (v == null) return;
            final keys = _subKeysFor(v);
            onChange(
                o.copyWith(blockId: v, subKey: keys.isEmpty ? '' : keys.first));
          },
        ),
        if (subKeys.isNotEmpty)
          DropdownButton<String>(
            isExpanded: true,
            value: subKeys.contains(o.subKey) ? o.subKey : null,
            hint: const Text('Field'),
            items: [
              for (final k in subKeys)
                DropdownMenuItem(value: k, child: Text(k)),
            ],
            onChanged: (v) => onChange(o.copyWith(subKey: v ?? '')),
          ),
        TextFormField(
          initialValue: '${o.coeff}',
          decoration: const InputDecoration(labelText: 'Coefficient (×)'),
          keyboardType: TextInputType.number,
          onChanged: (v) => onChange(o.copyWith(coeff: int.tryParse(v) ?? 1)),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit computed value'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _operandEditor('Operand A', _cfg.a,
                (o) => setState(() => _cfg = ComputedConfig(a: o, op: _cfg.op, b: _cfg.b))),
            const SizedBox(height: 12),
            DropdownButton<ComputedOp>(
              key: const Key('custom-computed-op'),
              isExpanded: true,
              value: _cfg.op,
              items: const [
                DropdownMenuItem(value: ComputedOp.add, child: Text('+ (number)')),
                DropdownMenuItem(value: ComputedOp.sub, child: Text('- (number)')),
                DropdownMenuItem(value: ComputedOp.mul, child: Text('x (number)')),
                DropdownMenuItem(value: ComputedOp.divFloor, child: Text('/ floor (number)')),
                DropdownMenuItem(value: ComputedOp.le, child: Text('<= (chip)')),
                DropdownMenuItem(value: ComputedOp.lt, child: Text('< (chip)')),
                DropdownMenuItem(value: ComputedOp.eq, child: Text('= (chip)')),
                DropdownMenuItem(value: ComputedOp.ge, child: Text('>= (chip)')),
                DropdownMenuItem(value: ComputedOp.gt, child: Text('> (chip)')),
              ],
              onChanged: (v) => setState(
                  () => _cfg = ComputedConfig(a: _cfg.a, op: v ?? _cfg.op, b: _cfg.b)),
            ),
            const SizedBox(height: 12),
            _operandEditor('Operand B', _cfg.b,
                (o) => setState(() => _cfg = ComputedConfig(a: _cfg.a, op: _cfg.op, b: o))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('custom-computed-save'),
              onPressed: () => Navigator.pop(context, _cfg),
              child: const Text('Save')),
        ],
      );
}

/// Simple dialog that prompts for an integer. Uses a [StatefulWidget] so
/// [TextEditingController] is disposed by the widget lifecycle, not by the
/// caller — avoids a "used after disposed" assertion when the dialog
/// close-animation is still running.
class _IntPromptDialog extends StatefulWidget {
  const _IntPromptDialog({required this.label});
  final String label;

  @override
  State<_IntPromptDialog> createState() => _IntPromptDialogState();
}

class _IntPromptDialogState extends State<_IntPromptDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.label),
        content: TextField(
          key: const Key('custom-roll-target'),
          controller: _ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: widget.label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, int.tryParse(_ctrl.text) ?? 0),
              child: const Text('Roll')),
        ],
      );
}
