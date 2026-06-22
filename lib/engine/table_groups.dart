/// Pure grouping for the browse-tables screen. Turns a flat list of raw table
/// keys into category sections derived from each key's prefix (the part before
/// the first '_'). No asset or generator coupling — UI-layer only.

/// A labeled section of table keys.
class TableGroup {
  const TableGroup(this.label, this.keys);
  final String label;
  final List<String> keys;
}

const _generalLabel = 'General';

/// Prefixes whose title-cased form needs a manual fix.
const _labelOverrides = {'npc': 'NPC'};

String _label(String prefix) =>
    _labelOverrides[prefix] ??
    '${prefix[0].toUpperCase()}${prefix.substring(1)}';

/// Groups [keys] by the prefix before the first '_'. A prefix shared by >=2
/// keys forms its own group; no-'_' keys and singleton prefixes fall into a
/// 'General' bucket. Groups are sorted by label with 'General' pinned last;
/// keys within each group are sorted ascending. Every input key lands in
/// exactly one group.
List<TableGroup> groupTableKeys(List<String> keys) {
  final byPrefix = <String, List<String>>{};
  for (final key in keys) {
    final i = key.indexOf('_');
    final prefix = i <= 0 ? '' : key.substring(0, i);
    byPrefix.putIfAbsent(prefix, () => []).add(key);
  }

  final groups = <TableGroup>[];
  final general = <String>[];
  byPrefix.forEach((prefix, members) {
    if (prefix.isEmpty || members.length < 2) {
      general.addAll(members);
    } else {
      groups.add(TableGroup(_label(prefix), members..sort()));
    }
  });

  groups.sort((a, b) => a.label.compareTo(b.label));
  if (general.isNotEmpty) {
    groups.add(TableGroup(_generalLabel, general..sort()));
  }
  return groups;
}
