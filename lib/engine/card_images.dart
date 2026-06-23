// Pure asset-path helpers for bundled public-domain card art. Tarot images are
// public-domain Rider–Waite–Smith (1909) scans, bundled as JPG; standard
// playing-card images are a CC0 English-pattern deck, bundled as SVG (rendered
// at runtime). The CardImage widget picks Image vs SvgPicture by extension.

import 'models.dart';

/// Filesystem-safe slug for a card name: lowercase, runs of non-alphanumerics
/// collapsed to '-'. "The Tower" -> "the-tower", "10 of Clubs" -> "10-of-clubs".
String cardSlug(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Bundled tarot image path, or null if [name] isn't a tarot card.
String? tarotImageAsset(String name) =>
    kTarotDeck.contains(name) ? 'assets/tarot/${cardSlug(name)}.jpg' : null;

/// Bundled standard-deck image path (CC0 SVG), or null if [name] isn't a
/// playing card.
String? playingCardImageAsset(String name) =>
    kPlayingDeck.contains(name) ? 'assets/playing/${cardSlug(name)}.svg' : null;

/// Resolves a bundled image for any card name (tarot first, then standard), or
/// null if unknown. Strips a trailing " (reversed)" so drawn cards resolve.
String? cardImageAsset(String name) {
  const suffix = ' (reversed)';
  final base = name.endsWith(suffix)
      ? name.substring(0, name.length - suffix.length)
      : name;
  return tarotImageAsset(base) ?? playingCardImageAsset(base);
}
