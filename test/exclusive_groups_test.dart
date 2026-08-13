import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/campaign_surfaces.dart';

void main() {
  test('normalizeExclusive keeps the first member by group order', () {
    expect(normalizeExclusive({'juice', 'verdant', 'hexcrawl'}),
        {'juice', 'verdant'});
    expect(normalizeExclusive({'hexcrawl'}), {'hexcrawl'});
    expect(normalizeExclusive({'juice', 'party'}), {'juice', 'party'});
    expect(normalizeExclusive(const {}), isEmpty);
  });

  test('kExclusiveSystemIds flattens group members', () {
    expect(kExclusiveSystemIds, containsAll(['verdant', 'hexcrawl']));
  });
}
