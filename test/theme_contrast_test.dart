import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/theme.dart';

double _luminance(Color c) => c.computeLuminance();

/// WCAG 2.1 contrast ratio between two colors.
double contrast(Color a, Color b) {
  final l1 = max(_luminance(a), _luminance(b));
  final l2 = min(_luminance(a), _luminance(b));
  return (l1 + 0.05) / (l2 + 0.05);
}

void main() {
  for (final entry in {
    'light': AppTheme.light().colorScheme,
    'dark': AppTheme.dark().colorScheme,
  }.entries) {
    final s = entry.value;
    // Token pairs rendered as normal-size text in the app -> 4.5:1 (AA).
    final textPairs = <String, (Color, Color)>{
      'onSurface/surface': (s.onSurface, s.surface),
      'onSurfaceVariant/surface': (s.onSurfaceVariant, s.surface),
      'onPrimary/primary': (s.onPrimary, s.primary),
      'onPrimaryContainer/primaryContainer':
          (s.onPrimaryContainer, s.primaryContainer),
      'onSecondaryContainer/secondaryContainer':
          (s.onSecondaryContainer, s.secondaryContainer),
      'onErrorContainer/errorContainer':
          (s.onErrorContainer, s.errorContainer),
      'onError/error': (s.onError, s.error),
      'primary/surface': (s.primary, s.surface), // TextButton labels
      'error/surface': (s.error, s.surface),
      'onSurfaceVariant/surfaceContainerHighest':
          (s.onSurfaceVariant, s.surfaceContainerHighest), // cards/sheets
    };
    for (final p in textPairs.entries) {
      test('[${entry.key}] ${p.key} meets WCAG AA (4.5:1)', () {
        expect(contrast(p.value.$1, p.value.$2), greaterThanOrEqualTo(4.5),
            reason:
                '${p.key} = ${contrast(p.value.$1, p.value.$2).toStringAsFixed(2)}');
      });
    }
  }
}
