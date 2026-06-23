import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../engine/card_images.dart';

/// Renders a bundled card image for [cardName] (a card identity, with or without
/// a trailing " (reversed)"). Reversed cards are drawn rotated 180°. Hides
/// itself when no image is bundled for the card (e.g. the standard deck, whose
/// art is not yet bundled), so callers can place it unconditionally.
class CardImage extends StatelessWidget {
  const CardImage(this.cardName,
      {super.key, this.reversed = false, this.height = 140});

  final String cardName;
  final bool reversed;
  final double height;

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
    return reversed ? RotatedBox(quarterTurns: 2, child: img) : img;
  }
}
