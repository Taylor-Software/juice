import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/help_data.dart';
import '../state/providers.dart';

/// In-app help: an index of sections/pages with internal page navigation
/// (no router). Help has no tab home — it is opened as a full-screen pushed
/// route (`openHelp` -> MaterialPageRoute), so it must supply its own
/// [Scaffold] (the ambient one a hosted tab would inherit is absent here).
/// Deep links arrive via [helpTopicProvider]: consumed on first frame and,
/// for a topic set while this instance is already mounted, via ref.listen.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  /// Open page id; null = index view.
  String? _pageId;

  @override
  void initState() {
    super.initState();
    // First frame: a topic set before this screen existed (e.g. the "?"
    // instantiating the tool) is consumed here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeTopic());
  }

  void _consumeTopic() {
    if (!mounted) return;
    final topic = ref.read(helpTopicProvider);
    if (topic == null) return;
    ref.read(helpTopicProvider.notifier).state = null;
    setState(() => _pageId = topic);
  }

  @override
  Widget build(BuildContext context) {
    // Keep-alive: catch topics set while this instance is already mounted
    // (possibly offstage behind the launcher or another tool).
    ref.listen<String?>(helpTopicProvider, (_, next) {
      if (next == null) return;
      ref.read(helpTopicProvider.notifier).state = null;
      setState(() => _pageId = next);
    });
    final theme = Theme.of(context);
    return ref.watch(helpDataProvider).when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) =>
              Scaffold(body: Center(child: Text('Failed to load help:\n$e'))),
          data: (data) {
            // On a page the AppBar's back returns to the index; on the index it
            // falls back to the route's own back (pops Help — it has no tab home).
            final page = _pageId == null ? null : data.page(_pageId!);
            return Scaffold(
              appBar: AppBar(
                leading: page == null
                    ? null
                    : IconButton(
                        key: const Key('help-back'),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'All help topics',
                        onPressed: () => setState(() => _pageId = null),
                      ),
                title: Text(page?.title ?? 'Help'),
              ),
              body: page == null ? _index(theme, data) : _page(theme, page),
            );
          },
        );
  }

  Widget _index(ThemeData theme, HelpData data) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final section in data.sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                section.title,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            for (final page in section.pages)
              ListTile(
                key: Key('help-page-${page.id}'),
                title: Text(page.title),
                onTap: () => setState(() => _pageId = page.id),
              ),
          ],
        ],
      );

  Widget _page(ThemeData theme, HelpPage page) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final b in page.blocks) _block(theme, b),
          if (page.id == 'credits') ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('help-licenses'),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Software licenses'),
              onPressed: () => showLicensePage(
                  context: context,
                  applicationName: "Solo Adventurer's Journal"),
            ),
          ],
        ],
      );

  Widget _block(ThemeData theme, HelpBlock b) => switch (b.kind) {
        HelpBlockKind.h => Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(b.text, style: theme.textTheme.titleMedium)),
        HelpBlockKind.p => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(b.text, style: theme.textTheme.bodyMedium)),
        HelpBlockKind.tip => Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b.text)),
                ],
              ),
            )),
        HelpBlockKind.steps => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, s) in b.items.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. ',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(s)),
                    ],
                  ),
                ),
            ],
          ),
      };
}
