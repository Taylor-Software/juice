import 'package:flutter/material.dart';

import '../engine/tarot_meanings.dart';
import '../engine/tarot_spreads.dart';
import '../shared/card_image.dart';

/// Renders a drawn tarot spread in its *proper geometric layout* — a row, a
/// plus, or the Celtic Cross wheel + staff — driven by [TarotSpread.cells].
/// The crossing card (Celtic Cross) is drawn rotated a quarter turn over the
/// card it crosses. Each card keeps its name label + tap-to-view meaning popup
/// (via [CardImage]); [detail] adds the authored upright/reversed meaning line
/// under each card (used on the fate-screen Cards section).
class TarotSpreadLayout extends StatelessWidget {
  const TarotSpreadLayout({
    super.key,
    required this.spread,
    required this.cards,
    this.cardHeight = 96,
    this.detail = false,
  });

  final TarotSpread spread;
  final List<({String position, String shown})> cards;
  final double cardHeight;
  final bool detail;

  double get _cardWidth => cardHeight * 0.62;
  double get _cellWidth => detail ? 150 : _cardWidth + 16;

  @override
  Widget build(BuildContext context) {
    // Defensive fallback: an unlaid-out or mismatched spread renders as a Wrap
    // so nothing is dropped.
    if (spread.cells.length != cards.length) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [for (var i = 0; i < cards.length; i++) _tile(context, i)],
      );
    }

    // Map each grid cell to the base (non-crossing) card index there, and note
    // any crossing card sharing that cell.
    final base = <(int, int), int>{};
    final crossing = <(int, int), int>{};
    var maxCol = 0, maxRow = 0;
    for (var i = 0; i < spread.cells.length; i++) {
      final c = spread.cells[i];
      (c.crossing ? crossing : base)[(c.col, c.row)] = i;
      if (c.col > maxCol) maxCol = c.col;
      if (c.row > maxRow) maxRow = c.row;
    }

    final rows = <Widget>[
      for (var row = 0; row <= maxRow; row++)
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var col = 0; col <= maxCol; col++)
              base.containsKey((col, row))
                  ? _cell(context, base[(col, row)]!, crossing[(col, row)])
                  : SizedBox(width: _cellWidth),
          ],
        ),
    ];

    // Celtic Cross can be wider than a phone — let it scroll horizontally.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }

  Widget _cell(BuildContext context, int baseIndex, int? crossIndex) {
    if (crossIndex == null) return _tile(context, baseIndex);
    final theme = Theme.of(context);
    final baseCard = readTarot(cards[baseIndex].shown);
    final crossCard = readTarot(cards[crossIndex].shown);
    return SizedBox(
      width: _cellWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(cards[baseIndex].position,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall),
          Text('⟂ ${cards[crossIndex].position}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          SizedBox(
            height: cardHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                CardImage(baseCard.name,
                    reversed: baseCard.reversed, height: cardHeight),
                RotatedBox(
                  quarterTurns: 1,
                  child: CardImage(crossCard.name,
                      reversed: crossCard.reversed, height: cardHeight * 0.88),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, int i) {
    final theme = Theme.of(context);
    final r = readTarot(cards[i].shown);
    final meaning = r.meaning == null
        ? null
        : (r.reversed ? r.meaning!.reversed : r.meaning!.upright);
    return SizedBox(
      width: _cellWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(cards[i].position,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            CardImage(r.name,
                reversed: r.reversed, height: cardHeight, showLabel: true),
            if (detail && meaning != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(meaning,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }
}
