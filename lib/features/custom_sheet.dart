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

  /// Reads a block's live value, or [fallback] when unset.
  dynamic _val(String id, dynamic fallback) => _s.values[id] ?? fallback;

  void _setVal(String id, dynamic value) =>
      _save(_s.copyWith(values: {..._s.values, id: value}));

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
        // onReorderItem gives the already-adjusted insertion index (item is
        // conceptually removed first), so removeAt + insert is direct.
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

  // --- play + config dispatch (filled in by later tasks) ---------------------

  Widget _playBlock(CustomBlock b) => switch (b.type) {
        CustomBlockType.freeform => _playFreeform(b),
        _ => const SizedBox.shrink(),
      };

  Future<void> _configBlock(CustomBlock b) async {
    switch (b.type) {
      default:
        await _renameBlock(b);
    }
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

  Widget _playFreeform(CustomBlock b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          key: Key('custom-${b.id}-freeform'),
          initialValue: _val(b.id, '') as String,
          maxLines: (b.config['multiline'] == true) ? 4 : 1,
          decoration: InputDecoration(labelText: b.label),
          onChanged: (v) => _setVal(b.id, v),
        ),
      );
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
