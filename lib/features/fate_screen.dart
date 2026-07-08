import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/constructed_oracle.dart';
import '../engine/dice.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/tarot_meanings.dart';
import '../engine/tarot_spreads.dart';
import '../shared/card_image.dart';
import '../shared/result_card.dart';
import '../state/providers.dart';
import 'oracle_constructor.dart';
import 'tarot_reference.dart';

/// A scroll target within the Fate screen, for launcher deep links.
enum FateSection { fateCheck, rollHigh, mythic, cards }

class FateScreen extends ConsumerStatefulWidget {
  const FateScreen({super.key, required this.oracle, this.initialSection});
  final Oracle oracle;

  /// When non-null, scroll to this section on first frame.
  final FateSection? initialSection;

  @override
  ConsumerState<FateScreen> createState() => _FateScreenState();
}

class _FateScreenState extends ConsumerState<FateScreen> {
  Likelihood _likelihood = Likelihood.normal;
  FateResult? _last;
  int _oddsIndex = 4; // 50/50
  GenResult? _mythicLast;
  String _meaningId = 'actions';
  String _rhDie = 'd100';
  int _rhOdds = 3; // Unknown
  GenResult? _rhLast;
  // Per constructed-oracle live state: chosen likelihood + last rolled result.
  final Map<String, OracleLikelihood> _ocLikelihood = {};
  final Map<String, GenResult> _ocLast = {};
  GenResult? _cardLast;
  TarotSpread _spread = kTarotSpreads.first;
  // The drawn spread + its cards, captured together so logging uses the spread
  // that was actually drawn — not whatever the picker shows now (changing the
  // dropdown after a draw must not rename the pending spread).
  ({
    TarotSpread spread,
    List<({String position, String shown})> cards
  })? _spreadLast;

  final _fateCheckKey = GlobalKey();
  final _rollHighKey = GlobalKey();
  final _mythicKey = GlobalKey();
  final _cardsKey = GlobalKey();

  GlobalKey _keyFor(FateSection s) => switch (s) {
        FateSection.fateCheck => _fateCheckKey,
        FateSection.rollHigh => _rollHighKey,
        FateSection.mythic => _mythicKey,
        FateSection.cards => _cardsKey,
      };

  Future<void> _drawCard({required bool tarot}) async {
    final g = await ref
        .read(decksProvider.notifier)
        .draw(widget.oracle, tarot: tarot);
    if (mounted) setState(() => _cardLast = g);
  }

  Future<void> _drawSpread() async {
    final out = await ref
        .read(decksProvider.notifier)
        .drawSpread(widget.oracle, _spread);
    if (mounted) {
      setState(() => _spreadLast = (spread: _spread, cards: out.cards));
    }
  }

  /// The AI-free authored meaning shown under a drawn tarot card (nothing for a
  /// standard-deck draw, which has no tarot meaning).
  Widget _cardMeaning(ThemeData theme, GenResult g) {
    final r = readTarot(g.summary ?? '');
    if (r.meaning == null) return const SizedBox.shrink();
    final text = r.reversed ? r.meaning!.reversed : r.meaning!.upright;
    return Padding(
      key: const Key('card-meaning'),
      padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
      child: Text('${r.reversed ? 'Reversed' : 'Upright'} — $text',
          style: theme.textTheme.bodyMedium),
    );
  }

  /// Journal body for a logged card: the card text plus its tarot meaning when
  /// present, so the reading is preserved without the AI.
  String _cardBody(GenResult g) =>
      g.asText + tarotMeaningSuffix(g.summary ?? '');

  /// One position tile in the spread grid: label, card art, name + orientation,
  /// and the authored meaning line. Uniform across all spreads.
  Widget _spreadTile(ThemeData theme, ({String position, String shown}) c) {
    final r = readTarot(c.shown);
    final meaning = r.meaning == null
        ? null
        : (r.reversed ? r.meaning!.reversed : r.meaning!.upright);
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.position,
              style: theme.textTheme.labelLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          CardImage(r.name, reversed: r.reversed, height: 120),
          const SizedBox(height: 4),
          Text('${r.name}${r.reversed ? ' (rev)' : ''}',
              style: theme.textTheme.bodySmall),
          if (meaning != null)
            Text(meaning,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final section = widget.initialSection;
    if (section != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keyFor(section).currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx);
      });
    }
  }

  void _roll() => setState(() => _last = widget.oracle.fateCheck(_likelihood));

  String _glyph(int v) => v > 0 ? '+' : (v < 0 ? '−' : '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _last;
    final systems =
        ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
            kAllSystems;
    // Non-lazy scroll container: every section's GlobalKey must resolve on
    // the first frame so initialSection deep links work on short viewports
    // (a lazy ListView leaves off-screen sections unbuilt).
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Fate Check',
              key: _fateCheckKey, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Ask a yes/no question, then roll 2dF + 1d6.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          SegmentedButton<Likelihood>(
            segments: const [
              ButtonSegment(
                  value: Likelihood.unlikely, label: Text('Unlikely')),
              ButtonSegment(value: Likelihood.normal, label: Text('Normal')),
              ButtonSegment(value: Likelihood.likely, label: Text('Likely')),
            ],
            selected: {_likelihood},
            onSelectionChanged: (s) => setState(() {
              _likelihood = s.first;
              // Tap-to-roll: selecting a likelihood rolls immediately
              // (validated demand — juice-roll issue #4). The Roll button
              // stays for re-rolls at the same likelihood.
              _last = widget.oracle.fateCheck(_likelihood);
            }),
          ),
          const SizedBox(height: 16),
          if (last != null) _FateResultCard(result: last, glyph: _glyph),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _roll,
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Roll Fate Check'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _logGen(widget.oracle.randomEvent()),
                  child: const Text('Random Event'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _logGen(widget.oracle.payThePrice()),
                  child: const Text('Pay the Price'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          Text('Roll High Oracle',
              key: _rollHighKey, style: theme.textTheme.headlineSmall),
          Text(
            'Roll high = yes. Pick a die and the odds.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'd100', label: Text('d100')),
              ButtonSegment(value: 'd20', label: Text('d20')),
              ButtonSegment(value: '2d6', label: Text('2d6')),
            ],
            selected: {_rhDie},
            onSelectionChanged: (s) => setState(() => _rhDie = s.first),
          ),
          const SizedBox(height: 12),
          DropdownMenu<int>(
            initialSelection: _rhOdds,
            label: const Text('Odds'),
            dropdownMenuEntries: [
              for (var i = 0; i < widget.oracle.data.rollHighOdds.length; i++)
                DropdownMenuEntry(
                    value: i, label: widget.oracle.data.rollHighOdds[i]),
            ],
            onSelected: (v) => setState(() => _rhOdds = v ?? _rhOdds),
          ),
          const SizedBox(height: 12),
          if (_rhLast != null) ...[
            ResultCard(
              result: _rhLast!,
              onLog: () {
                ref.read(journalProvider.notifier).addResult(
                    _rhLast!.title, _rhLast!.asText,
                    sourceTool: 'roll-high', payload: _rhLast!.toPayload());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Added to journal')),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: () => setState(
                () => _rhLast = widget.oracle.rollHigh(_rhDie, _rhOdds)),
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Roll Oracle'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          _myOraclesSection(theme),
          const SizedBox(height: 24),
          const Divider(),
          Text('Mythic GME',
              key: _mythicKey, style: theme.textTheme.headlineSmall),
          Text(
            'Mythic Game Master Emulator © Word Mill Games (wordmillgames.com), '
            'used under CC-BY-NC 4.0.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final crawl =
                ref.watch(crawlProvider).valueOrNull ?? const CrawlState();
            final chaos = crawl.chaosFactor.clamp(1, 9);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Chaos Factor: $chaos',
                        style: theme.textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: chaos > 1
                          ? () => ref
                              .read(crawlProvider.notifier)
                              .save(crawl.copyWith(chaosFactor: chaos - 1))
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: chaos < 9
                          ? () => ref
                              .read(crawlProvider.notifier)
                              .save(crawl.copyWith(chaosFactor: chaos + 1))
                          : null,
                    ),
                  ],
                ),
                DropdownMenu<int>(
                  initialSelection: _oddsIndex,
                  label: const Text('Odds'),
                  dropdownMenuEntries: [
                    for (var i = 0;
                        i < widget.oracle.data.mythicOdds.length;
                        i++)
                      DropdownMenuEntry(
                          value: i, label: widget.oracle.data.mythicOdds[i]),
                  ],
                  onSelected: (v) =>
                      setState(() => _oddsIndex = v ?? _oddsIndex),
                ),
                const SizedBox(height: 12),
                if (_mythicLast != null) ...[
                  ResultCard(
                    result: _mythicLast!,
                    onLog: () {
                      ref.read(journalProvider.notifier).addResult(
                          _mythicLast!.title, _mythicLast!.asText,
                          sourceTool: 'mythic',
                          payload: _mythicLast!.toPayload());
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Added to journal')),
                      );
                    },
                    actions: [
                      // One-tap Mythic random event (Focus + Action + Subject)
                      // — the canonical follow-up, in place of chaining the
                      // Event Focus + two Meaning buttons by hand.
                      ResultAction(
                        label: 'Random Event',
                        icon: Icons.bolt_outlined,
                        tooltip: 'Roll a Mythic random event',
                        onPressed: () => setState(() => _mythicLast =
                            widget.oracle.mythicRandomEvent(
                                threads: _openThreadTitles(),
                                characters: _characterNames())),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: () => setState(() => _mythicLast =
                      widget.oracle.mythicFate(_oddsIndex, chaos)),
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text('Fate Chart'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() =>
                            _mythicLast = widget.oracle.mythicSceneTest(chaos)),
                        child: const Text('Scene Test'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _mythicLast =
                            widget.oracle.mythicEventFocus(
                                threads: _openThreadTitles(),
                                characters: _characterNames())),
                        child: const Text('Event Focus'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownMenu<String>(
                        initialSelection: _meaningId,
                        label: const Text('Meaning table'),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: [
                          for (final t in widget.oracle.data.mythicMeaning)
                            DropdownMenuEntry(
                                value: t['id'] as String,
                                label: t['name'] as String),
                        ],
                        onSelected: (v) =>
                            setState(() => _meaningId = v ?? _meaningId),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Flexible bounds the button: a bare Material button as a
                    // non-flex Row child next to a flex sibling is measured at
                    // maxWidth:Infinity and throws under the loose tool host.
                    Flexible(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _mythicLast =
                            widget.oracle.mythicMeaning(_meaningId)),
                        child: const Text('Meaning'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
          if (systems.contains('cards')) ...[
            const SizedBox(height: 24),
            const Divider(),
            Text('Cards', key: _cardsKey, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Draw from a deck as an oracle. Log a card, then interpret it '
              'yourself or via the journal entry.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Consumer(builder: (context, ref, _) {
              final decks =
                  ref.watch(decksProvider).valueOrNull ?? const DecksState();
              final deckLen = decks.jokers
                  ? kPlayingDeckWithJokers.length
                  : kPlayingDeck.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('cards-draw'),
                        icon: const Icon(Icons.style_outlined),
                        label: const Text('Draw card'),
                        onPressed: () => _drawCard(tarot: false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('cards-draw-tarot'),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Draw tarot'),
                        onPressed: () => _drawCard(tarot: true),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  // Wrap (not Row) so the readout + reshuffle reflow instead of
                  // overflowing on a narrow phone.
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                          'Deck ${decks.standard.remainingOf(deckLen)}/$deckLen',
                          style: theme.textTheme.bodySmall),
                      TextButton(
                        key: const Key('cards-reshuffle'),
                        onPressed: () => ref
                            .read(decksProvider.notifier)
                            .reshuffle(tarot: false),
                        child: const Text('Reshuffle'),
                      ),
                      FilterChip(
                        key: const Key('cards-jokers-toggle'),
                        label: const Text('Jokers'),
                        selected: decks.jokers,
                        onSelected: (v) =>
                            ref.read(decksProvider.notifier).setJokers(v),
                      ),
                      Text(
                          'Tarot ${decks.tarot.remainingOf(kTarotDeck.length)}'
                          '/${kTarotDeck.length}',
                          style: theme.textTheme.bodySmall),
                      TextButton(
                        key: const Key('cards-reshuffle-tarot'),
                        onPressed: () => ref
                            .read(decksProvider.notifier)
                            .reshuffle(tarot: true),
                        child: const Text('Reshuffle'),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('cards-reference'),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Card meanings'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Tarot meanings')),
                            body: const TarotReference(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_cardLast != null) ...[
                    const SizedBox(height: 8),
                    ResultCard(
                      result: _cardLast!,
                      onLog: () {
                        ref.read(journalProvider.notifier).addResult(
                              _cardLast!.title,
                              _cardBody(_cardLast!),
                              sourceTool: 'cards',
                              payload: _cardLast!.toPayload(),
                            );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Added to journal')),
                        );
                      },
                    ),
                    Builder(builder: (context) {
                      final r = readTarot(_cardLast!.summary ?? '');
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: CardImage(r.name,
                              reversed: r.reversed, showLabel: true),
                        ),
                      );
                    }),
                    _cardMeaning(theme, _cardLast!),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  Text('Spreads', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<TarotSpread>(
                          key: const Key('spread-picker'),
                          isExpanded: true,
                          value: _spread,
                          items: [
                            for (final s in kTarotSpreads)
                              DropdownMenuItem(
                                value: s,
                                child: Text('${s.name}  (${s.count})'),
                              ),
                          ],
                          onChanged: (s) {
                            if (s != null) setState(() => _spread = s);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const Key('cards-draw-spread'),
                        icon: const Icon(Icons.dashboard_outlined),
                        label: const Text('Draw spread'),
                        // The app-wide FilledButton theme sets a full-width
                        // minimumSize (Size.fromHeight in theme.dart => infinite
                        // min-width). As a non-flex child of a Row with an
                        // Expanded sibling (the picker), the flex sizing pass
                        // measures this button with unbounded width, so that
                        // infinite min-width throws "forces an infinite width".
                        // Pin a finite min-width so it sits natural-width beside
                        // the dropdown.
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(64, 48)),
                        onPressed: _drawSpread,
                      ),
                    ],
                  ),
                  if (_spreadLast != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final c in _spreadLast!.cards)
                          _spreadTile(theme, c),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        key: const Key('spread-log'),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Log spread'),
                        onPressed: () {
                          ref.read(journalProvider.notifier).addResult(
                                'Tarot Spread',
                                spreadBody(_spreadLast!.spread.name,
                                    _spreadLast!.cards),
                                sourceTool: 'cards',
                              );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Added to journal')),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  List<String> _openThreadTitles() =>
      (ref.read(threadsProvider).valueOrNull ?? const <Thread>[])
          .where((t) => t.open)
          .map((t) => t.title)
          .toList();

  List<String> _characterNames() =>
      (ref.read(charactersProvider).valueOrNull ?? const <Character>[])
          .map((c) => c.name)
          .toList();

  void _logGen(GenResult g) {
    ref.read(journalProvider.notifier).addResult(g.title, g.asText,
        sourceTool: 'fate-check', payload: g.toPayload());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('${g.title}: ${g.summary ?? g.rolls.first.value}')),
    );
  }

  /// "My Oracles": player-constructed yes/no oracles. Each rolls at a live
  /// likelihood and logs a `constructed-oracle` journal entry.
  Widget _myOraclesSection(ThemeData theme) {
    final oracles =
        ref.watch(constructedOraclesProvider).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text('My Oracles', style: theme.textTheme.headlineSmall),
          ),
          Flexible(
            child: FilledButton.tonalIcon(
              key: const Key('oracle-new'),
              icon: const Icon(Icons.add),
              label: const Text('New'),
              onPressed: () => showOracleConstructor(context, ref, null),
            ),
          ),
        ]),
        Text(
          'Build your own dice, direction, outcomes, and odds.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (oracles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No custom oracles yet.',
                style: theme.textTheme.bodySmall),
          )
        else
          for (final o in oracles) _oracleCard(theme, o),
      ],
    );
  }

  Widget _oracleCard(ThemeData theme, ConstructedOracle o) {
    final likelihood = _ocLikelihood[o.id] ?? OracleLikelihood.likely;
    final last = _ocLast[o.id];
    return Card(
      key: Key('oracle-card-${o.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(o.name.isEmpty ? '(unnamed oracle)' : o.name,
                  style: theme.textTheme.titleMedium),
            ),
            IconButton(
              key: Key('oracle-edit-${o.id}'),
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showOracleConstructor(context, ref, o),
            ),
            IconButton(
              key: Key('oracle-delete-${o.id}'),
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                // Drop this oracle's ephemeral roll/likelihood state so a
                // later id can't inherit it.
                _ocLikelihood.remove(o.id);
                _ocLast.remove(o.id);
                ref.read(constructedOraclesProvider.notifier).remove(o.id);
              },
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButton<OracleLikelihood>(
              key: Key('oracle-likelihood-${o.id}'),
              value: likelihood,
              isExpanded: true,
              isDense: true,
              onChanged: (v) =>
                  setState(() => _ocLikelihood[o.id] = v ?? likelihood),
              items: [
                for (final l in OracleLikelihood.values)
                  DropdownMenuItem(value: l, child: Text(l.label)),
              ],
            ),
          ),
          if (last != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ResultCard(
                result: last,
                onLog: () {
                  ref.read(journalProvider.notifier).addResult(
                      last.title, last.asText,
                      sourceTool: 'constructed-oracle',
                      payload: last.toPayload());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to journal')),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            key: Key('oracle-roll-${o.id}'),
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Roll'),
            onPressed: () => setState(
                () => _ocLast[o.id] = oracleGenResult(o, likelihood, Dice())),
          ),
        ]),
      ),
    );
  }
}

class _FateResultCard extends ConsumerWidget {
  const _FateResultCard({required this.result, required this.glyph});
  final FateResult result;
  final String Function(int) glyph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isYes = result.result.contains('Yes') || result.result == 'Favorable';
    final isNo = result.result.contains('No') || result.result == 'Unfavorable';
    final accent = isYes
        ? scheme.primary
        : isNo
            ? scheme.error
            : scheme.tertiary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Die(label: glyph(result.primary), filled: true),
                _Die(label: glyph(result.secondary), filled: false),
                _Die(label: '${result.intensityRoll}', filled: false),
                Text(result.shorthand,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    )),
                IconButton(
                  tooltip: 'Add to journal',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: () {
                    final g = fateCheckGenResult(result);
                    ref.read(journalProvider.notifier).addResult(
                        g.title, g.asText,
                        sourceTool: 'fate-check', payload: g.toPayload());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Added to journal')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(result.result,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(color: accent, fontWeight: FontWeight.w600)),
            Text('Intensity: ${result.intensity}',
                style: theme.textTheme.titleMedium),
            if (result.isRandomEvent)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('→ also triggers a Random Event',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.tertiary)),
              ),
            if (result.isInvalidAssumption)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('→ re-ask: your question assumed something false',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.tertiary)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Die extends StatelessWidget {
  const _Die({required this.label, required this.filled});
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            filled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}
