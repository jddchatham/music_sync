import 'dart:io';

import 'sync_fs.dart';

/// Desktop implementation of [SyncFs] rooted at a local directory.
class IoFileSystem implements SyncFs {
  final String root;

  IoFileSystem(this.root);

  @override
  String get rootName {
    final trimmed = root.replaceAll(RegExp(r'/+$'), '');
    return trimmed.split('/').last;
  }

  String _abs(String rel) => '$root/$rel';

  @override
  Stream<FsEntry> walk() async* {
    final dir = Directory(root);
    if (!await dir.exists()) return;
    yield* _walkDir(dir, '');
  }

  Stream<FsEntry> _walkDir(Directory dir, String relPrefix) async* {
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.path.split('/').last;
      final rel = relPrefix.isEmpty ? name : '$relPrefix/$name';
      if (entity is File) {
        final st = await entity.stat();
        yield FsEntry(
          relPath: rel,
          isFile: true,
          size: st.size,
          modified: st.modified,
          uri: entity.path,
        );
      } else if (entity is Directory) {
        yield FsEntry(relPath: rel, isFile: false, size: 0, uri: entity.path);
        yield* _walkDir(entity, rel);
      }
    }
  }

  @override
  Stream<List<int>> read(FsEntry entry) => File(entry.uri).openRead();

  @override
  Future<SyncWriter> create(String relPath) async {
    final file = File(_abs(relPath));
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    return _IoWriter(sink);
  }

  @override
  Future<void> delete(FsEntry entry) async {
    await File(entry.uri).delete();
  }

  @override
  Future<void> setModified(String relPath, DateTime when) async {
    try {
      await File(_abs(relPath)).setLastModified(when);
    } catch (_) {}
  }
}

class _IoWriter implements SyncWriter {
  final IOSink _sink;
  _IoWriter(this._sink);

  @override
  Future<void> write(List<int> chunk) async {
    _sink.add(chunk);
    await _sink.flush();
  }

  @override
  Future<void> close() async {
    await _sink.close();
  }
}
