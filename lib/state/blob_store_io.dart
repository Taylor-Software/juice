import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'blob_store.dart';

/// Selected on mobile/desktop (dart:io available).
BlobStore createBlobStore() => FileBlobStore();

/// Stores blobs as files under `<appDocuments>/blobs/<id>`. The directory is
/// injectable so tests can point it at a temp dir without `path_provider`.
class FileBlobStore implements BlobStore {
  FileBlobStore({Future<Directory> Function()? dir})
      : _resolveDir = dir ?? _defaultDir;

  final Future<Directory> Function() _resolveDir;
  Directory? _cached;

  static Future<Directory> _defaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/blobs');
  }

  Future<Directory> _dir() async {
    final d = _cached ??= await _resolveDir();
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String id) async => File('${(await _dir()).path}/$id');

  @override
  Future<String> put(List<int> bytes, {String? ext}) async {
    final id = ext == null ? blobId(bytes) : '${blobId(bytes)}.$ext';
    await (await _file(id)).writeAsBytes(bytes, flush: true);
    return id;
  }

  @override
  Future<Uint8List?> get(String id) async {
    final f = await _file(id);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> delete(String id) async {
    final f = await _file(id);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<String>> list() async => (await _dir())
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .toList();

  @override
  Future<bool> exists(String id) async => (await _file(id)).exists();
}
