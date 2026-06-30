import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/quick_ref.dart';
import '../state/providers.dart';

/// Read-only render of a system's QuickRef card. Pass [card] explicitly (pure,
/// single-card), or set [useProvider] to render the active system's authored
/// card PLUS the user's app-global cards + an Add control.
class QuickRefView extends ConsumerWidget {
  const QuickRefView({super.key, this.card, this.useProvider = false});
  final QuickRefCard? card;
  final bool useProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (!useProvider) {
      final c = card;
      if (c == null) return _empty(context);
      return ListView(
        key: const Key('quickref-list'),
        padding: const EdgeInsets.all(12),
        children: _cardBlock(theme, c),
      );
    }

    final authored = ref.watch(systemQuickRefProvider);
    final userCards = ref.watch(userRefCardsProvider).valueOrNull ?? const [];

    if (authored == null && userCards.isEmpty) {
      return ListView(
        key: const Key('quickref-list'),
        padding: const EdgeInsets.all(12),
        children: [
          _empty(context),
          const SizedBox(height: 12),
          _addButton(context, ref),
        ],
      );
    }

    return ListView(
      key: const Key('quickref-list'),
      padding: const EdgeInsets.all(12),
      children: [
        if (authored != null) ..._cardBlock(theme, authored),
        for (final u in userCards) ...[
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(u.title, style: theme.textTheme.titleLarge),
              ),
              IconButton(
                key: Key('quickref-edit-${u.id}'),
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit card',
                onPressed: () => showRefCardEditor(context, ref, existing: u),
              ),
              IconButton(
                key: Key('quickref-delete-${u.id}'),
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete card',
                onPressed: () =>
                    ref.read(userRefCardsProvider.notifier).remove(u.id),
              ),
            ],
          ),
          ..._sections(theme, u.sections),
        ],
        const SizedBox(height: 12),
        _addButton(context, ref),
      ],
    );
  }

  Widget _addButton(BuildContext context, WidgetRef ref) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('quickref-add'),
          icon: const Icon(Icons.add),
          label: const Text('Add card'),
          onPressed: () => showRefCardEditor(context, ref),
        ),
      );

  Widget _empty(BuildContext context) => Center(
        key: const Key('quickref-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No quick reference for this system yet.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );

  List<Widget> _cardBlock(ThemeData theme, QuickRefCard c) => [
        Text(c.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        ..._sections(theme, c.sections),
      ];

  List<Widget> _sections(ThemeData theme, List<QuickRefSection> sections) => [
        for (final s in sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(s.title, style: theme.textTheme.titleSmall),
          ),
          for (final line in s.lines)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: theme.textTheme.bodyMedium),
                  Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ];
}

/// Opens the active system's QuickRef (+ user cards) in a modal bottom sheet.
Future<void> showQuickRef(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.85,
        child: QuickRefView(useProvider: true),
      ),
    );

/// Body seed: render a card's sections back into the '#'-heading editor format.
String _bodyFromSections(List<QuickRefSection> sections) => sections
    .map((s) => '# ${s.title}\n${s.lines.join('\n')}')
    .join('\n')
    .trim();

/// Add/edit a user ref card. Parses the body via [parseRefSections]; saves only
/// when the title and parsed sections are non-empty.
Future<void> showRefCardEditor(BuildContext context, WidgetRef ref,
    {UserRefCard? existing}) async {
  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  final bodyCtrl = TextEditingController(
      text: existing == null ? '' : _bodyFromSections(existing.sections));
  final saved = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text(existing == null ? 'New card' : 'Edit card'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('refcard-title'),
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('refcard-body'),
              controller: bodyCtrl,
              minLines: 5,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Body',
                hintText: '# Section heading\nbullet line\nbullet line',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            key: const Key('refcard-delete'),
            onPressed: () {
              ref.read(userRefCardsProvider.notifier).remove(existing.id);
              Navigator.pop(dctx, false);
            },
            child: const Text('Delete'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel')),
        FilledButton(
          key: const Key('refcard-save'),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (saved != true) return;
  final title = titleCtrl.text.trim();
  final sections = parseRefSections(bodyCtrl.text);
  if (title.isEmpty || sections.isEmpty) return;
  final notifier = ref.read(userRefCardsProvider.notifier);
  if (existing == null) {
    notifier.add(UserRefCard(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        sections: sections));
  } else {
    notifier.replace(
        UserRefCard(id: existing.id, title: title, sections: sections));
  }
}
