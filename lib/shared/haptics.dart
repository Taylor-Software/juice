// lib/shared/haptics.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Light haptic tick for dice/oracle rolls on touch platforms; no-op on
/// web/desktop (where the call would be meaningless or throw nothing useful).
void hapticRoll() {
  if (kIsWeb) return;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      HapticFeedback.lightImpact();
    default:
      break;
  }
}
