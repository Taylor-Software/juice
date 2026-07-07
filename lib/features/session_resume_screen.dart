import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/design_tokens.dart';
import '../shared/shell_route.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';

/// "Where did I leave off?" ritual shown when re-entering an existing campaign
/// with prior session state. Answers the question with the active scene, the
/// live stat tiles (Scene / Chaos / Light), open threads, and the last entry,
/// then offers a single momentum hand-off CTA (`Continue the story`).
///
/// Reads the [PlayContext] spine like [CampaignHeader]: the scene follows
/// `activeSceneId` (falling back to the newest scene entry). Pushed as a route
/// over the shell; [Continue] lands on the Journal and pops.
class SessionResumeScreen extends ConsumerWidget {
  const SessionResumeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.juice;
    final entries = ref.watch(journalProvider).valueOrNull ?? const [];
    final threads = (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        .where((t) => t.open)
        .toList();
    final crawl = ref.watch(crawlProvider).valueOrNull;
    final light = ref.watch(lightProvider).valueOrNull ?? 0;
    final meta = ref.watch(sessionsProvider).valueOrNull?.activeMeta;
    final systems = meta?.enabledSystems ?? kAllSystems;
    final usesMythic = systems.contains('mythic');

    final scene = activeSceneEntry(
        entries, ref.watch(playContextProvider).valueOrNull?.activeSceneId);
    final sceneTitle = scene?.title.trim();
    final lastEntry = entries
        .where(
            (e) => e.kind != JournalKind.scene && e.kind != JournalKind.session)
        .firstOrNull;
    final newest = entries.firstOrNull;
    final relative = newest == null ? null : formatLastPlayed(newest.timestamp);

    return Scaffold(
      backgroundColor: tk.cream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              shrinkWrap: true,
              children: [
                _header(context, tk,
                    sceneTitle: (sceneTitle == null || sceneTitle.isEmpty)
                        ? 'Untitled scene'
                        : sceneTitle,
                    campaignName: meta?.name ?? 'Campaign',
                    relative: relative),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _statTiles(
                    tk,
                    sceneLabel: (sceneTitle == null || sceneTitle.isEmpty)
                        ? '—'
                        : sceneTitle,
                    chaos: (usesMythic && crawl != null)
                        ? '${crawl.chaosFactor}'
                        : '—',
                    light: light > 0 ? '$light' : 'out',
                  ),
                ),
                if (threads.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _openThreads(tk, threads.take(4).toList()),
                  ),
                if (lastEntry != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _lastEntry(tk, lastEntry),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: _continueButton(context, ref, tk),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _secondaryRow(context, ref, tk),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -- Sections ---------------------------------------------------------------

  Widget _header(
    BuildContext context,
    JuiceTokens tk, {
    required String sceneTitle,
    required String campaignName,
    required String? relative,
  }) {
    final subtitle = relative == null
        ? campaignName
        : '$campaignName · last played $relative';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tk.sand, tk.cream],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WELCOME BACK',
            style: tk.uiLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
              color: tk.terracotta,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sceneTitle,
            style: tk.narrative.copyWith(
              fontSize: 30,
              fontStyle: FontStyle.italic,
              color: tk.ink,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: tk.uiLabel.copyWith(fontSize: 13.5, color: tk.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _statTiles(
    JuiceTokens tk, {
    required String sceneLabel,
    required String chaos,
    required String light,
  }) {
    // IntrinsicHeight so all three tiles share the tallest's height without
    // forcing an infinite height (this Row sits inside a ListView).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _statTile(tk, 'Scene', sceneLabel, tk.ink)),
          const SizedBox(width: 10),
          Expanded(child: _statTile(tk, 'Chaos', chaos, tk.chaos)),
          const SizedBox(width: 10),
          Expanded(child: _statTile(tk, 'Light', light, tk.ink)),
        ],
      ),
    );
  }

  Widget _statTile(JuiceTokens tk, String label, String value, Color valueC) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: tk.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: tk.uiLabel.copyWith(
              fontSize: 11,
              letterSpacing: 0.6,
              color: tk.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tk.uiLabel.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: valueC,
            ),
          ),
        ],
      ),
    );
  }

  Widget _openThreads(JuiceTokens tk, List<Thread> threads) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(tk, 'OPEN THREADS'),
        const SizedBox(height: 10),
        for (final t in threads)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              key: Key('resume-thread-${t.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: tk.raised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tk.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: t.pinned ? tk.terracotta : tk.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tk.uiLabel
                              .copyWith(fontSize: 14, color: tk.inkBody),
                        ),
                      ),
                      Text(
                        '${t.progress}/${t.progressMax}',
                        style: tk.uiLabel.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tk.inkMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: t.progressMax <= 0
                          ? 0.0
                          : (t.progress / t.progressMax).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: tk.hairline,
                      valueColor: AlwaysStoppedAnimation<Color>(tk.terracotta),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _lastEntry(JuiceTokens tk, JournalEntry e) {
    final text = e.title.trim().isEmpty
        ? e.body.trim()
        : (e.body.trim().isEmpty ? e.title.trim() : e.body.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(tk, 'LAST ENTRY'),
        const SizedBox(height: 8),
        Text(
          text.isEmpty ? e.title : '"$text"',
          style: tk.narrative.copyWith(
            fontSize: 14.5,
            fontStyle: FontStyle.italic,
            color: tk.inkBody,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _continueButton(BuildContext context, WidgetRef ref, JuiceTokens tk) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const Key('resume-continue'),
        style: FilledButton.styleFrom(
          backgroundColor: tk.terracotta,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: () => _continue(context, ref),
        child: const Text('Continue the story  →'),
      ),
    );
  }

  Widget _secondaryRow(BuildContext context, WidgetRef ref, JuiceTokens tk) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: tk.terracotta,
      side: BorderSide(color: tk.borderInput),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: const Key('resume-recap'),
            style: style,
            onPressed: () => _recap(context, ref),
            child: const Text('Recap so far'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            key: const Key('resume-new-scene'),
            style: style,
            onPressed: () => _newScene(context, ref),
            child: const Text('New scene'),
          ),
        ),
      ],
    );
  }

  Widget _eyebrow(JuiceTokens tk, String text) => Text(
        text,
        style: tk.uiLabel.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: tk.inkMuted,
        ),
      );

  // -- Actions ----------------------------------------------------------------

  /// Lands on the Journal (or the in-progress encounter) and pops
  /// the resume screen.
  Future<void> _continue(BuildContext context, WidgetRef ref) async {
    final enc = await ref.read(encounterProvider.future);
    ref
        .read(shellRouteProvider.notifier)
        .land(hasEncounter: enc.combatants.isNotEmpty);
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// AI recap when ready, else a deterministic static summary; shown in a dialog.
  Future<void> _recap(BuildContext context, WidgetRef ref) async {
    final entries = ref.read(journalProvider).valueOrNull ?? const [];
    final threads = ref.read(threadsProvider).valueOrNull ?? const <Thread>[];
    final scene = activeSceneEntry(
        entries, ref.read(playContextProvider).valueOrNull?.activeSceneId);
    String summary;
    if (ref.read(aiReadyProvider)) {
      final since = _recapTexts(entries);
      try {
        summary = await ref.read(interpreterServiceProvider).summarize(since);
      } catch (e) {
        summary =
            buildStaticRecap(scene: scene, threads: threads, entries: entries);
      }
    } else {
      summary =
          buildStaticRecap(scene: scene, threads: threads, entries: entries);
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('resume-recap-dialog'),
        title: const Text('Previously…'),
        content: SingleChildScrollView(child: Text(summary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Creates a new scene (reusing [JournalNotifier.addScene] +
  /// [PlayContextNotifier.setActiveScene], the same flow the journal uses), then
  /// continues.
  Future<void> _newScene(BuildContext context, WidgetRef ref) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _ResumeSceneDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    final id = await ref.read(journalProvider.notifier).addScene(
          title.trim(),
          chaosFactor: ref.read(crawlProvider).valueOrNull?.chaosFactor,
        );
    await ref.read(playContextProvider.notifier).setActiveScene(id);
    if (context.mounted) await _continue(context, ref);
  }

  /// Entry texts since the last scene divider, for the AI summarizer (mirrors
  /// the journal recap's `since`-scene slice).
  static List<String> _recapTexts(List<JournalEntry> entries) {
    final since = <JournalEntry>[];
    for (final e in entries) {
      if (e.kind == JournalKind.scene) break;
      since.add(e);
    }
    return [
      for (final e in since.reversed)
        e.title.isEmpty ? e.body : '${e.title}: ${e.body}',
    ];
  }
}

/// Pure: a relative "last played" phrase from [when] to [now] (defaults to
/// `DateTime.now()`). "just now" under a minute, then minutes / hours / days.
String formatLastPlayed(DateTime when, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(when);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) {
    final m = d.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} ago';
  }
  if (d.inDays < 1) {
    final h = d.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
  final days = d.inDays;
  return '$days day${days == 1 ? '' : 's'} ago';
}

/// Pure deterministic recap (no AI): scene title + open-thread titles + the
/// last few non-divider entry lines. Used when AI is unavailable.
String buildStaticRecap({
  required JournalEntry? scene,
  required List<Thread> threads,
  required List<JournalEntry> entries,
  int lastN = 3,
}) {
  final buf = StringBuffer();
  final sceneTitle = scene?.title.trim();
  if (sceneTitle != null && sceneTitle.isNotEmpty) {
    buf.writeln('Scene: $sceneTitle');
  }
  final open = threads.where((t) => t.open).map((t) => t.title).toList();
  if (open.isNotEmpty) {
    buf.writeln('Open threads: ${open.join(', ')}');
  }
  final recent = entries
      .where(
          (e) => e.kind != JournalKind.scene && e.kind != JournalKind.session)
      .take(lastN)
      .toList()
      .reversed
      .toList();
  if (recent.isNotEmpty) {
    buf.writeln('Recently:');
    for (final e in recent) {
      final line = e.title.trim().isEmpty
          ? e.body.trim()
          : (e.body.trim().isEmpty
              ? e.title.trim()
              : '${e.title.trim()}: ${e.body.trim()}');
      if (line.isNotEmpty) buf.writeln('• $line');
    }
  }
  final out = buf.toString().trim();
  return out.isEmpty ? 'No session activity yet.' : out;
}

/// Minimal title-only scene dialog for the resume "New scene" action.
class _ResumeSceneDialog extends StatefulWidget {
  const _ResumeSceneDialog();

  @override
  State<_ResumeSceneDialog> createState() => _ResumeSceneDialogState();
}

class _ResumeSceneDialogState extends State<_ResumeSceneDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New scene'),
      content: TextField(
        key: const Key('resume-scene-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Scene title'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('resume-scene-confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
