import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Platform impl: files on mobile/desktop, an unavailable stub on web.
import 'blob_store_io.dart'
    if (dart.library.html) 'blob_store_web.dart' as platform;

/// A binary asset store keyed by opaque id, separate from SharedPreferences
/// (which is for small structured state, not multi-MB blobs). Holds imported
/// PDFs and cached page images. See
/// `docs/superpowers/specs/2026-06-19-pdf-annotation-blob-store-design.md`.
abstract class BlobStore {
  /// Persist [bytes]; returns the blob id. Re-putting identical bytes yields
  /// the same id (content-addressed dedupe). [ext] is appended to the id.
  Future<String> put(List<int> bytes, {String? ext});

  /// The blob's bytes, or null if absent.
  Future<Uint8List?> get(String id);

  Future<void> delete(String id);

  /// All stored blob ids (for export + garbage collection).
  Future<List<String>> list();

  Future<bool> exists(String id);
}

/// Deterministic content id (FNV-1a 64-bit over the bytes, length-prefixed).
/// NOT cryptographic — just a stable key for dedupe/storage. Length in the id
/// makes accidental collisions across different files vanishingly unlikely.
String blobId(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final b in bytes) {
    hash ^= b & 0xff;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return '${bytes.length}-${hash.toRadixString(16).padLeft(16, '0')}';
}

/// In-memory [BlobStore] for tests (the disk/IO-hang rule: never hit real IO in
/// unit/widget tests).
class InMemoryBlobStore implements BlobStore {
  final Map<String, Uint8List> _blobs = {};

  String _id(List<int> bytes, String? ext) =>
      ext == null ? blobId(bytes) : '${blobId(bytes)}.$ext';

  @override
  Future<String> put(List<int> bytes, {String? ext}) async {
    final id = _id(bytes, ext);
    _blobs[id] = Uint8List.fromList(bytes);
    return id;
  }

  @override
  Future<Uint8List?> get(String id) async => _blobs[id];

  @override
  Future<void> delete(String id) async => _blobs.remove(id);

  @override
  Future<List<String>> list() async => _blobs.keys.toList();

  @override
  Future<bool> exists(String id) async => _blobs.containsKey(id);
}

/// The active blob store. File-backed on mobile/desktop; an unavailable stub on
/// web (so callers fall back / hide the affordance — see [blobStoreAvailable]).
final blobStoreProvider =
    Provider<BlobStore>((ref) => platform.createBlobStore());

/// Whether a usable blob store exists on this platform. False on web for now
/// (no file system; IndexedDB support is a later epic step).
final blobStoreAvailableProvider = Provider<bool>((ref) => !kIsWeb);
