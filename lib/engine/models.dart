/// Plain immutable models for engine output and persisted state.
/// No freezed/codegen — the data is small and stable.
library;

import 'custom_sheet.dart';
import 'dungeon/footprint.dart';
import 'tally.dart';

// Split for navigability. `part` (not separate libraries) keeps ONE shared
// scope: the private JSON helpers below and every cross-model reference
// resolve exactly as they did in the single 5.7k-line file, so none of the
// ~90 `import 'models.dart'` sites change and nothing needs re-exporting.
part 'models/journal.dart';
part 'models/sheet_common.dart';
part 'models/sheets_ironsworn.dart';
part 'models/sheets_dnd.dart';
part 'models/sheets_osr.dart';
part 'models/combat.dart';
part 'models/map.dart';
part 'models/character.dart';
part 'models/session.dart';
part 'models/world.dart';

/// Upper clamp for player-managed numeric sheet fields (HP, slots, pools…):
/// an arbitrary "large enough" ceiling to keep JSON round-trips sane, not a
/// rules value.
const int kFieldClampMax = 1 << 20;

// Tolerant JSON readers shared by the sheets' `maybeFromJson` factories.
int _intOr(dynamic v, int d) => v is int ? v : d;
String _strOr(dynamic v) => v is String ? v : '';
Set<String> _strSet(dynamic v) =>
    v is List ? v.whereType<String>().toSet() : const {};
