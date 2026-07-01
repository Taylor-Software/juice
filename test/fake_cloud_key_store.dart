import 'package:juice_oracle/state/cloud_key_store.dart';

class FakeCloudKeyStore implements CloudKeyStore {
  String? _value;
  int readCalls = 0;
  int writeCalls = 0;
  int clearCalls = 0;

  @override
  Future<String?> read() async {
    readCalls++;
    return _value;
  }

  @override
  Future<void> write(String key) async {
    writeCalls++;
    _value = key;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    _value = null;
  }
}
