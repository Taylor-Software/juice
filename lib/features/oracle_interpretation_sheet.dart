import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../state/interpreter.dart';
import '../state/providers.dart';

/// Bottom sheet that turns one logged oracle result into lens cards.
/// The host passes the seed (entry text + scene context) and receives the
/// accepted card; genre/tone are read from and saved to settingsProvider
/// here so the seed the user sees is the seed the model gets.
class OracleInterpretationSheet extends ConsumerStatefulWidget {
  const OracleInterpretationSheet({
    super.key,
    required this.seed,
    required this.onAccept,
  });

  /// genre/tone fields of this seed are ignored — the sheet injects the
  /// campaign settings at interpret time.
  final OracleSeed seed;
  final ValueChanged<OracleInterpretation> onAccept;

  @override
  ConsumerState<OracleInterpretationSheet> createState() =>
      _OracleInterpretationSheetState();
}

class _OracleInterpretationSheetState
    extends ConsumerState<OracleInterpretationSheet> {
  List<OracleInterpretation>? _cards;
  final Set<int> _dismissed = <int>{};
  bool _generating = false;
  String? _generateError;

  // Captured once: dispose() must not touch ref (Riverpod forbids it).
  late final InterpreterService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(interpreterServiceProvider);
    // The sheet opens only when ready (Interpret is gated on
    // interpretReadyProvider), so _onStatus() auto-starts generation on the
    // first frame. Settings owns on-device download/refresh — no refresh()
    // here. Listen to both the on-device status AND interpretReadyProvider,
    // since a cloud-only readiness change never touches _service.status.
    _service.status.addListener(_onStatus);
    ref.listenManual(interpretReadyProvider, (prev, next) => _onStatus());
    _onStatus();
  }

  @override
  void dispose() {
    _service.status.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    if (!mounted) return;
    setState(() {});
    if (ref.read(interpretReadyProvider) && _cards == null && !_generating) {
      _generate();
    }
  }

  Future<void> _generate() async {
    if (_generating) return;
    // Claim the flag synchronously, before any await, so a second call in
    // the same frame (e.g. a double-tapped Regenerate) bails out above.
    setState(() {
      _generating = true;
      _generateError = null;
      _cards = null;
      _dismissed.clear();
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      if (!mounted) return;
      final cards = await _service.interpret(OracleSeed(
        resultText: widget.seed.resultText,
        genre: settings.genre,
        tone: settings.tone,
        sceneContext: widget.seed.sceneContext,
        journalContext: widget.seed.journalContext,
        systemPrimer: ref.read(systemPrimerProvider),
      ));
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generateError = '$e';
        _generating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const CampaignSettings();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, settings),
            const SizedBox(height: 12),
            Flexible(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, CampaignSettings settings) {
    final theme = Theme.of(context);
    final vibe = [settings.genre, settings.tone]
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(widget.seed.resultText,
            style: theme.textTheme.titleMedium,
            maxLines: 3,
            overflow: TextOverflow.ellipsis),
        Row(
          children: [
            Expanded(
              child: Text(
                vibe.isEmpty ? 'Set a genre and tone…' : vibe,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              key: const Key('interp-tone-edit'),
              icon: const Icon(Icons.tune, size: 18),
              tooltip: 'Genre & tone',
              onPressed: () => _editSettings(settings),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editSettings(CampaignSettings current) async {
    final result = await showDialog<CampaignSettings>(
      context: context,
      builder: (_) => _SettingsDialog(current: current),
    );
    if (!mounted || result == null) return;
    await ref.read(settingsProvider.notifier).save(result);
  }

  Widget _body(BuildContext context) {
    // This sheet opens once AI is ready for interpretation — either on-device
    // or cloud (see interpretReadyProvider). The non-ready note is a
    // defensive fallback, e.g. if the on-device model is evicted mid-session
    // or the cloud key/toggle is cleared while this sheet is still open.
    if (!ref.watch(interpretReadyProvider)) {
      return const _Note(
          icon: Icons.auto_awesome_outlined,
          title: 'Assistant not ready',
          detail: 'Enable AI in Settings to interpret.');
    }
    if (_generating) {
      return const _Note(
          icon: Icons.auto_awesome,
          title: 'Reading the omens…',
          detail: 'The page may be unresponsive while the model writes.',
          spinner: true);
    }
    if (_generateError != null) {
      return _Note(
          icon: Icons.error_outline,
          title: 'Could not interpret this result.',
          detail: _generateError!,
          action: FilledButton.tonal(
              key: const Key('interp-retry'),
              onPressed: _generate,
              child: const Text('Retry')));
    }
    final cards = _cards ?? const <OracleInterpretation>[];
    final visible = <int>[
      for (var i = 0; i < cards.length; i++)
        if (!_dismissed.contains(i)) i,
    ];
    if (visible.isEmpty) {
      return _Note(
          icon: Icons.style_outlined,
          title: 'Dismissed them all.',
          detail: 'Roll fresh readings?',
          action: FilledButton.tonal(
              key: const Key('interp-reroll'),
              onPressed: _generate,
              child: const Text('Roll new readings')));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: visible.length,
            itemBuilder: (context, idx) {
              final i = visible[idx];
              return Dismissible(
                key: ValueKey('interp-dismiss-$i'),
                direction: DismissDirection.endToStart,
                background: _dismissBackground(context),
                onDismissed: (_) => setState(() => _dismissed.add(i)),
                child: _card(context, i, cards[i]),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Swipe a card away to discard it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            TextButton.icon(
              key: const Key('interp-regenerate'),
              onPressed: _generate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Regenerate'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card(BuildContext context, int index, OracleInterpretation card) {
    final theme = Theme.of(context);
    return Card(
      key: Key('interp-card-$index'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                card.lens.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(card.reading, style: theme.textTheme.bodyLarge),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('interp-accept-$index'),
                onPressed: () => widget.onAccept(card),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Use this'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dismissBackground(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.title,
    required this.detail,
    this.spinner = false,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final bool spinner;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            const CircularProgressIndicator()
          else
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title,
              style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(detail,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.current});
  final CampaignSettings current;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _genre = TextEditingController(text: widget.current.genre);
  late final _tone = TextEditingController(text: widget.current.tone);

  @override
  void dispose() {
    _genre.dispose();
    _tone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Genre & tone'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('interp-genre-field'),
            controller: _genre,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Genre', hintText: 'e.g. grimdark fantasy'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('interp-tone-field'),
            controller: _tone,
            decoration: const InputDecoration(
                labelText: 'Tone', hintText: 'e.g. tense and dangerous'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context,
              CampaignSettings(
                  genre: _genre.text.trim(), tone: _tone.text.trim())),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
