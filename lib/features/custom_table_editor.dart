import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/custom_table.dart';
import '../state/providers.dart';

/// New/edit/delete editor for a user-authored [CustomTable]. The rows textarea
/// syntax depends on the selected [TableRoll] mode (see [parseRows]/[rowsToText]).
Future<void> showCustomTableDialog(
    BuildContext context, WidgetRef ref, CustomTable? existing) async {
  final nameCtl = TextEditingController(text: existing?.name ?? '');
  final diceCtl = TextEditingController(text: existing?.dice ?? '');
  final genreCtl = TextEditingController(text: existing?.genre ?? '');
  final sourceCtl = TextEditingController(text: existing?.source ?? '');
  var category = existing?.category ?? '';
  var mode = existing?.mode ?? TableRoll.uniform;
  final rowsCtl =
      TextEditingController(text: rowsToText(existing?.rows ?? const [], mode));

  String hintFor(TableRoll m) => switch (m) {
        TableRoll.uniform => 'One result per line',
        TableRoll.weighted => 'One per line: text | weight   (e.g. Rain | 3)',
        TableRoll.ranges =>
          'One per line: range then text   (e.g. 01-05 Rusty Flagon)',
      };

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'New table' : 'Edit table'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const Key('table-name'),
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            // Library metadata (binder-style organization): category within
            // genre, plus the source the table came from.
            DropdownButtonFormField<String>(
              key: const Key('table-category'),
              initialValue:
                  kTableCategories.contains(category) ? category : '',
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(value: '', child: Text('(none)')),
                for (final c in kTableCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => category = v ?? '',
            ),
            const SizedBox(height: 8),
            TextField(
                key: const Key('table-genre'),
                controller: genreCtl,
                decoration: const InputDecoration(
                    labelText: 'Genre', hintText: 'Fantasy, Sci-fi, Horror…')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('table-source'),
                controller: sourceCtl,
                decoration: const InputDecoration(
                    labelText: 'Source',
                    hintText: 'Book / site it came from')),
            const SizedBox(height: 12),
            SegmentedButton<TableRoll>(
              key: const Key('table-mode'),
              segments: const [
                ButtonSegment(value: TableRoll.uniform, label: Text('Uniform')),
                ButtonSegment(
                    value: TableRoll.weighted, label: Text('Weighted')),
                ButtonSegment(value: TableRoll.ranges, label: Text('Ranges')),
              ],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                // Re-serialize the current rows into the new mode's syntax so
                // the textarea stays consistent across mode switches.
                final rows = parseRows(rowsCtl.text, mode);
                setState(() {
                  mode = s.first;
                  rowsCtl.text = rowsToText(rows, mode);
                });
              },
            ),
            if (mode == TableRoll.ranges) ...[
              const SizedBox(height: 8),
              TextField(
                  key: const Key('table-dice'),
                  controller: diceCtl,
                  decoration: const InputDecoration(
                      labelText: 'Dice', hintText: 'd100, 2d6, …')),
            ],
            const SizedBox(height: 8),
            TextField(
                key: const Key('table-rows'),
                controller: rowsCtl,
                minLines: 4,
                maxLines: 12,
                decoration: InputDecoration(
                    labelText: 'Rows',
                    helperText: hintFor(mode),
                    helperMaxLines: 2,
                    alignLabelWithHint: true)),
          ]),
        ),
        actions: [
          if (existing != null)
            TextButton(
              key: const Key('table-delete'),
              onPressed: () async {
                await ref
                    .read(customTablesProvider.notifier)
                    .remove(existing.id);
                if (ctx.mounted) Navigator.of(ctx).pop(false);
              },
              child: const Text('Delete'),
            ),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('table-save'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save')),
        ],
      ),
    ),
  );
  // Post-frame: runs after the synchronous .text reads below and after the
  // route's exit transition, so disposing here is safe either way.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    nameCtl.dispose();
    diceCtl.dispose();
    genreCtl.dispose();
    sourceCtl.dispose();
    rowsCtl.dispose();
  });
  if (result != true) return;
  final rows = parseRows(rowsCtl.text, mode);
  final name = nameCtl.text.trim();
  if (name.isEmpty && rows.isEmpty) return;
  final dice = mode == TableRoll.ranges ? diceCtl.text.trim() : '';
  final notifier = ref.read(customTablesProvider.notifier);
  final genre = genreCtl.text.trim();
  final source = sourceCtl.text.trim();
  if (existing == null) {
    await notifier.add(CustomTable(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        mode: mode,
        dice: dice,
        rows: rows,
        genre: genre,
        category: category,
        source: source));
  } else {
    await notifier.replace(existing.copyWith(
        name: name,
        mode: mode,
        dice: dice,
        rows: rows,
        genre: genre,
        category: category,
        source: source));
  }
}
