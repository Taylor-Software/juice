import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted storage for the user's cloud API key. A real, billable secret —
/// unlike every other persisted value in this app (which lives in plaintext
/// SharedPreferences), this warrants OS Keychain/Keystore storage. Abstracted
/// as a seam (mirrors [InterpreterService] in interpreter.dart) so tests never
/// touch the platform channel.
abstract class CloudKeyStore {
  Future<String?> read();
  Future<void> write(String key);
  Future<void> clear();
}

class SecureCloudKeyStore implements CloudKeyStore {
  static const _key = 'cloud_anthropic_api_key';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String key) => _storage.write(key: _key, value: key);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
