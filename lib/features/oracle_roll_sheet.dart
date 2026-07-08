import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/tarot_meanings.dart';
import '../engine/tarot_spreads.dart';
import '../shared/card_image.dart';
import '../state/providers.dart';
import 'dice_roll_animation.dart';

/// Opens the roll sheet for a draw-style default oracle (`icons`/`cards`/
/// `tarot`) — the controls the HUD quick-roll can't fit: icon count + tumble
/// animation, standard/tarot deck, single card vs a spread. Rolls log to the
/// journal like any oracle. (Juice/Mythic/Custom stay instant, not routed here.)
Future<void> showOracleRollSheet(
        BuildContext context, Oracle oracle, String defaultOracle) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _OracleRollSheet(oracle: oracle, defaultOracle: defaultOracle),
    );

class _OracleRollSheet extends ConsumerStatefulWidget {
  const _OracleRollSheet({required this.oracle, required this.defaultOracle});
  final Oracle oracle;
  final String defaultOracle;

  @override
  ConsumerState<_OracleRollSheet> createState() => _OracleRollSheetState();
}

class _OracleRollSheetState extends ConsumerState<_OracleRollSheet> {
  // Icons
  int _iconCount = 1;
  int _iconRollId = 0;
  List<({String asset, int d10, int d6})>? _lastIcons;
  // Cards
  late bool _tarot = widget.defaultOracle == 'tarot';
  bool _spread = false;
  TarotSpread _spreadPick = kTarotSpreads.first;
  String? _lastCard; // shown string of the last single draw
  String? _lastSpreadName;
  List<({String position, String shown})> _lastSpreadCards = const [];

  bool get _isIcons => widget.defaultOracle == 'icons';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isIcons ? 'Story dice' : 'Card oracle',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_isIcons) ..._iconControls(theme) else ..._cardControls(theme),
          ],
        ),
      ),
    );
  }

  // -- Icons ------------------------------------------------------------------
  List<Widget> _iconControls(ThemeData theme) => [
        Row(children: [
          Text('Dice', style: theme.textTheme.labelMedium),
          const SizedBox(width: 12),
          for (var n = 1; n <= 5; n++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('oracle-roll-icon-count-$n'),
                label: Text('$n'),
                selected: _iconCount == n,
                onSelected: (_) => setState(() => _iconCount = n),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        if (_lastIcons != null)
          Center(
            child: IconDiceRollAnimation(
              assets: [for (final i in _lastIcons!) i.asset],
              rollId: _iconRollId,
              size: _lastIcons!.length == 1 ? 120 : 72,
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('oracle-roll-icons'),
            icon: const Icon(Icons.casino_outlined),
            label: Text(_lastIcons == null ? 'Roll' : 'Roll again'),
            onPressed: _rollIcons,
          ),
        ),
      ];

  void _rollIcons() {
    final icons = widget.oracle.abstractIcons(_iconCount);
    setState(() {
      _lastIcons = icons;
      _iconRollId++;
    });
    final g = GenResult(
      title:
          icons.length == 1 ? 'Abstract Icon' : 'Story Dice (${icons.length})',
      rolls: [
        for (var i = 0; i < icons.length; i++)
          Roll(
              label: icons.length == 1 ? 'Icon' : 'Icon ${i + 1}',
              value: 'd10 ${d10Label(icons[i].d10)}, d6 ${icons[i].d6}'),
      ],
    );
    ref.read(journalProvider.notifier).addResult(g.title, g.asText,
        sourceTool: 'gen-abstract-icon',
        payload: {
          ...g.toPayload(),
          'icons': [for (final i in icons) i.asset]
        });
  }

  // -- Cards ------------------------------------------------------------------
  List<Widget> _cardControls(ThemeData theme) => [
        SegmentedButton<bool>(
          key: const Key('oracle-roll-deck'),
          segments: const [
            ButtonSegment(value: false, label: Text('Standard')),
            ButtonSegment(value: true, label: Text('Tarot')),
          ],
          selected: {_tarot},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() {
            _tarot = s.first;
            if (!_tarot) _spread = false; // spreads are tarot-only
          }),
        ),
        const SizedBox(height: 12),
        if (_tarot) ...[
          SegmentedButton<bool>(
            key: const Key('oracle-roll-mode'),
            segments: const [
              ButtonSegment(value: false, label: Text('Single')),
              ButtonSegment(value: true, label: Text('Spread')),
            ],
            selected: {_spread},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _spread = s.first),
          ),
          const SizedBox(height: 8),
          if (_spread)
            DropdownButton<TarotSpread>(
              key: const Key('oracle-roll-spread'),
              value: _spreadPick,
              isExpanded: true,
              onChanged: (v) => setState(() => _spreadPick = v ?? _spreadPick),
              items: [
                for (final s in kTarotSpreads)
                  DropdownMenuItem(
                      value: s,
                      child: Text('${s.name} (${s.positions.length})')),
              ],
            ),
        ],
        const SizedBox(height: 12),
        if (_lastSpreadCards.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final c in _lastSpreadCards)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Builder(builder: (_) {
                    final r = readTarot(c.shown);
                    return CardImage(r.name, reversed: r.reversed, height: 110);
                  }),
                  SizedBox(
                    width: 76,
                    child: Text(c.position,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall),
                  ),
                ]),
            ],
          )
        else if (_lastCard != null)
          Center(
            child: Builder(builder: (_) {
              final r = readTarot(_lastCard!);
              return CardImage(r.name, reversed: r.reversed, height: 160);
            }),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('oracle-roll-cards'),
            icon: const Icon(Icons.style_outlined),
            label: Text(_lastCard == null && _lastSpreadName == null
                ? 'Draw'
                : 'Draw again'),
            onPressed: _drawCards,
          ),
        ),
      ];

  Future<void> _drawCards() async {
    final decks = ref.read(decksProvider.notifier);
    if (_tarot && _spread) {
      final cards = await decks.drawSpreadAndLog(widget.oracle, _spreadPick);
      setState(() {
        _lastSpreadName = _spreadPick.name;
        _lastSpreadCards = cards;
        _lastCard = null;
      });
    } else {
      final g = await decks.drawAndLog(widget.oracle, tarot: _tarot);
      setState(() {
        _lastCard = g.summary;
        _lastSpreadName = null;
        _lastSpreadCards = const [];
      });
    }
  }
}
