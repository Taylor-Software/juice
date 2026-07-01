import 'package:flutter_test/flutter_test.dart';
import 'fake_cloud_key_store.dart';

void main() {
  test('fake starts empty, write then read round-trips, clear empties it',
      () async {
    final store = FakeCloudKeyStore();
    expect(await store.read(), isNull);
    await store.write('sk-ant-test123');
    expect(await store.read(), 'sk-ant-test123');
    await store.clear();
    expect(await store.read(), isNull);
  });
}
