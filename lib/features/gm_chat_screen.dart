import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/gm_chat.dart';
import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../state/gm_chat.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';

/// Opens the multi-turn GM chat full-screen; optionally sends [initialMessage]
/// as the first turn.
Future<void> showGmChat(BuildContext context, {String? initialMessage}) {
  return Navigator.of(context).push<void>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => GmChatScreen(initialMessage: initialMessage),
  ));
}

class GmChatScreen extends ConsumerStatefulWidget {
  const GmChatScreen({super.key, this.initialMessage});
  final String? initialMessage;

  @override
  ConsumerState<GmChatScreen> createState() => _GmChatScreenState();
}

class _GmChatScreenState extends ConsumerState<GmChatScreen> {
  final _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final first = widget.initialMessage?.trim() ?? '';
    if (first.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(first));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    _input.clear();
    setState(() => _busy = true); // before the first await — closes the
    // double-send window (a tap during appendTurn must hit the guard).
    final notifier = ref.read(gmChatProvider.notifier);
    await notifier.appendTurn(ChatTurn(ChatRole.player, t));
    try {
      final journal = ref.read(journalProvider).valueOrNull ?? const [];
      // The active scene (pinned else newest) — consistent with every other seam.
      final scene = activeSceneEntry(
              journal, ref.read(playContextProvider).valueOrNull?.activeSceneId)
          ?.title;
      final target = JournalEntry(
          id: 'gm-chat-target', timestamp: DateTime.now(), title: '', body: t);
      final history = ref.read(gmChatProvider).valueOrNull?.turns ?? const [];
      final answer =
          await ref.read(interpreterServiceProvider).gmChat(GmChatSeed(
                history: history,
                sceneTitle: scene,
                systemPrimer: ref.read(systemPrimerProvider),
                activeCharacter: ref.read(activeCharacterLineProvider),
                journalContext: recallLines(journal, target),
              ));
      await notifier.appendTurn(ChatTurn(ChatRole.gm, answer));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('The Oracle did not answer — try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat'),
        content: const Text('Clear this Oracle conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(gmChatProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat cleared')),
    );
  }

  void _saveToJournal(List<ChatTurn> turns, int i) {
    final gm = turns[i];
    final prior = i > 0 ? turns[i - 1] : null;
    final body = prior != null && prior.role == ChatRole.player
        ? 'Player: ${prior.text}\n\nOracle: ${gm.text}'
        : 'Oracle: ${gm.text}';
    ref
        .read(journalProvider.notifier)
        .addResult('Oracle chat', body, sourceTool: 'gm-chat');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to journal')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final turns = ref.watch(gmChatProvider).valueOrNull?.turns ?? const [];
    final aiReady = ref.watch(aiReadyProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Oracle chat'),
        actions: [
          if (turns.isNotEmpty)
            IconButton(
              key: const Key('gm-chat-clear'),
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear chat',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: turns.isEmpty
                ? Center(
                    child: Text('Ask the Oracle anything.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: turns.length,
                    itemBuilder: (context, ri) {
                      final i = turns.length - 1 - ri; // reversed view
                      return _bubble(theme, turns, i);
                    },
                  ),
          ),
          if (_busy) const LinearProgressIndicator(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('gm-chat-input'),
                      controller: _input,
                      enabled: aiReady && !_busy,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: aiReady
                            ? 'Message the Oracle…'
                            : 'Enable AI in Settings',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('gm-chat-send'),
                    icon: const Icon(Icons.send),
                    onPressed:
                        aiReady && !_busy ? () => _send(_input.text) : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ThemeData theme, List<ChatTurn> turns, int i) {
    final t = turns[i];
    final isGm = t.role == ChatRole.gm;
    final scheme = theme.colorScheme;
    return Align(
      alignment: isGm ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Card(
          key: Key('gm-chat-bubble-$i'),
          color:
              isGm ? scheme.surfaceContainerHighest : scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.text),
                if (isGm)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: Key('gm-chat-save-$i'),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                      label: const Text('Save'),
                      onPressed: () => _saveToJournal(turns, i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
