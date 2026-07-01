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
  // Prefers the legacy file-based keychain (no keychain-access-groups
  // entitlement required) over the newer data-protection keychain — still
  // AES-256-GCM-encrypted and gated behind the user's login, just an older
  // API surface, not a weaker-security fallback. NOTE: on THIS project, this
  // alone did not clear macOS -34018 "A required entitlement isn't present."
  // on an ad-hoc-signed (no Apple Developer Team configured) local build —
  // confirmed via integration_test/cloud_key_store_test.dart and by reading
  // flutter_secure_storage_darwin's Swift source directly (this option IS
  // correctly wired through; the -34018 persists regardless). macOS Keychain
  // access appears to require the OS to verify a real code-signing identity
  // (sandboxed or not), which ad-hoc signing doesn't provide. Real device
  // verification is BLOCKED pending a real Apple Developer Team being
  // configured for this project — see the wedge Phase 2 plan's Task 8 notes.
  final _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String key) => _storage.write(key: _key, value: key);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
