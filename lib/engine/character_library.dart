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
