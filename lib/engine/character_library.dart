// Pure copy helpers for the app-global character library. Copies go through
// JSON so every sheet type rides along without a per-field list. The library
// is a library of COPIES — play state diverges per campaign after the copy.
import 'models.dart';

/// Copy for saving INTO the library: fresh [newId]; the Practical-Magic link
/// is dropped because the linked magic record lives in the source campaign's
/// storage and would dangle anywhere else.
Character libraryCopy(Character c, String newId) {
  final j = c.toJson()
    ..['id'] = newId
    ..remove('polarityId');
  return Character.fromJson(j);
}

/// Copy for importing INTO a campaign roster: everything [libraryCopy] does,
/// plus role reset to pc and star cleared (both are campaign-local flags).
Character campaignCopy(Character c, String newId) {
  final j = c.toJson()
    ..['id'] = newId
    ..remove('polarityId')
    ..remove('role')
    ..remove('starred');
  return Character.fromJson(j);
}

/// Human sheet-system label for library rows/pickers, by non-null sheet
/// field. Sundered Isles shares [Character.starforged], so it reads plain
/// 'Starforged' here too. 'Generic' when no sheet field is set.
String sheetLabel(Character c) {
  if (c.ironsworn != null) return 'Ironsworn';
  if (c.starforged != null) return 'Starforged';
  if (c.dnd != null) return 'D&D 5e';
  if (c.shadowdark != null) return 'Shadowdark';
  if (c.nimble != null) return 'Nimble';
  if (c.drawSteel != null) return 'Draw Steel';
  if (c.argosa != null) return 'Tales of Argosa';
  if (c.cairn != null) return 'Cairn';
  if (c.knave != null) return 'Knave';
  if (c.embark != null) return 'Embark';
  if (c.ose != null) return 'OSE';
  if (c.kalArath != null) return 'Kal-Arath';
  if (c.custom != null) return 'Custom';
  if (c.dcc != null) return 'DCC';
  if (c.funnel != null) return '0-Level Funnel';
  return 'Generic';
}

String _roleLabel(CharacterRole r) => switch (r) {
      CharacterRole.pc => 'PC',
      CharacterRole.companion => 'Companion',
      CharacterRole.npc => 'NPC',
    };

/// Row/picker badge text: [sheetLabel] plus the role, omitted for the
/// default `pc` (e.g. "D&D 5e" or "Cairn · Companion").
String sheetRoleBadge(Character c) {
  final label = sheetLabel(c);
  if (c.role == CharacterRole.pc) return label;
  return '$label · ${_roleLabel(c.role)}';
}
