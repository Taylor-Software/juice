import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../engine/card_images.dart';
import '../engine/tarot_meanings.dart';

/// Renders a bundled card image for [cardName] (a card identity, with or without
/// a trailing " (reversed)"). Reversed cards are drawn rotated 180°. Hides
/// itself when no image is bundled for the card (e.g. the standard deck, whose
/// art is not yet bundled), so callers can place it unconditionally.
///
/// For tarot cards, the image is tappable — a tap opens a popup with the card
/// name, orientation, and its short authored meaning. Set [showLabel] to render
/// the card name as a caption beneath the image.
class CardImage extends StatelessWidget {
  const CardImage(this.cardName,
      {super.key,
      this.reversed = false,
      this.height = 140,
      this.showLabel = false});

  final String cardName;
  final bool reversed;
  final double height;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final asset = cardImageAsset(cardName);
    if (asset == null) return const SizedBox.shrink();
    final Widget pic = asset.endsWith('.svg')
        ? SvgPicture.asset(asset, height: height)
        : Image.asset(
            asset,
            height: height,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
    final img = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: pic,
    );
    final oriented = reversed ? RotatedBox(quarterTurns: 2, child: img) : img;

    final meaning = kTarotMeanings[cardName];
    Widget content = oriented;
    if (showLabel) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          oriented,
          SizedBox(
            width: height * 0.72,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                cardName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      );
    }
    if (meaning == null) return content;

    // Tarot: hover tooltip (desktop) + tap-to-describe popup (touch).
    return Tooltip(
      message: '${reversed ? 'Reversed' : 'Upright'} — '
          '${reversed ? meaning.reversed : meaning.upright}',
      child: InkWell(
        key: Key('card-info-$cardName'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => showTarotCardInfo(context, cardName, reversed, meaning),
        child: content,
      ),
    );
  }
}

/// Popup with a tarot card's name, orientation, and its short authored meaning
/// (the drawn orientation prominent, the other dimmed for reference).
Future<void> showTarotCardInfo(
    BuildContext context, String name, bool reversed, TarotMeaning meaning) {
  final theme = Theme.of(context);
  final drawnLabel = reversed ? 'Reversed' : 'Upright';
  final drawnText = reversed ? meaning.reversed : meaning.upright;
  final otherLabel = reversed ? 'Upright' : 'Reversed';
  final otherText = reversed ? meaning.upright : meaning.reversed;
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      key: Key('card-info-dialog-$name'),
      title: Text('$name${reversed ? ' (reversed)' : ''}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(drawnLabel,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 2),
          Text(drawnText, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(otherLabel,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(otherText,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    ),
  );
}
