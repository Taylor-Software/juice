import 'dart:typed_data';

import 'blob_store.dart';

/// Selected on web (no file system). The library/annotation affordances gate on
/// [blobStoreAvailableProvider] (false on web), so these throws are unreachable
/// in normal use; an IndexedDB-backed store is a later epic step.
BlobStore createBlobStore() => UnavailableBlobStore();

class UnavailableBlobStore implements BlobStore {
  static Never _unavailable() =>
      throw UnsupportedError('Blob store is unavailable on web');

  @override
  Future<String> put(List<int> bytes, {String? ext}) async => _unavailable();

  @override
  Future<Uint8List?> get(String id) async => _unavailable();

  @override
  Future<void> delete(String id) async => _unavailable();

  @override
  Future<List<String>> list() async => _unavailable();

  @override
  Future<bool> exists(String id) async => _unavailable();
}
