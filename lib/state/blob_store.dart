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
///
/// Uses [BigInt] so the 64-bit math compiles on web (JS has no 64-bit int — the
/// hex literals overflowed the JS number range and broke the web build). The id
/// is an unsigned 16-hex value, identical across native and web. (Pre-release,
/// this changes the exact id vs the old native-only int math — which printed a
/// signed value — so any device-local blobs from before re-id on next put; no
/// migration is needed.)
String blobId(List<int> bytes) {
  final mask = (BigInt.one << 64) - BigInt.one;
  final prime = BigInt.parse('100000001b3', radix: 16);
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  for (final b in bytes) {
    hash ^= BigInt.from(b & 0xff);
    hash = (hash * prime) & mask;
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
