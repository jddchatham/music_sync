import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'sync_fs.dart';

class SafPick {
  final String uri;
  final String name;
  SafPick(this.uri, this.name);
}

/// Android implementation of [SyncFs] over a Storage Access Framework tree.
///
/// The engine calls [walk] first; from its directory snapshot we keep a
/// relPath -> content-uri registry so [create]/[delete] never have to
/// resolve names twice.
class SafFileSystem implements SyncFs {
  static const MethodChannel _ch = MethodChannel('music_sync/saf');

  final String treeUri;
  final Map<String, String> _dirs = {'': ''};

  SafFileSystem(this.treeUri) {
    _dirs[''] = treeUri;
  }

  @override
  String get rootName {
    final t = treeUri.replaceAll(RegExp(r'/+$'), '');
    return Uri.decodeComponent(t.split('/').last);
  }

  static Future<SafPick?> pickTree() async {
    final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('pickTree');
    if (r == null) return null;
    return SafPick(r['uri'] as String, r['name'] as String);
  }

  static Future<bool> hasPersistedPermission(String uri) async {
    return await _ch.invokeMethod<bool>('hasPersistedPermission', {'uri': uri}) ??
        false;
  }

  @override
  Stream<FsEntry> walk() async* {
    _dirs.clear();
    _dirs[''] = treeUri;
    final queue = <List<String>>[['', treeUri]];
    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      final relPrefix = item[0];
      final uri = item[1];
      final rows = await _ch.invokeMethod<List<dynamic>>(
          'listDir', {'tree': treeUri, 'uri': uri});
      for (final row in rows ?? const []) {
        final m = Map<String, dynamic>.from(row as Map);
        final name = m['name'] as String;
        final rel = relPrefix.isEmpty ? name : '$relPrefix/$name';
        final isDir = m['dir'] as bool;
        final childUri = m['uri'] as String;
        if (isDir) {
          _dirs[rel] = childUri;
          queue.add([rel, childUri]);
        }
        yield FsEntry(
          relPath: rel,
          isFile: !isDir,
          size: (m['size'] as num?)?.toInt() ?? 0,
          modified: (m['mtime'] as num?) != null
              ? DateTime.fromMillisecondsSinceEpoch((m['mtime'] as num).toInt())
              : null,
          uri: childUri,
        );
      }
    }
  }

  @override
  Stream<List<int>> read(FsEntry entry) async* {
    final handle =
        await _ch.invokeMethod<int>('openRead', {'uri': entry.uri});
    if (handle == null) throw StateError('cannot open ${entry.relPath}');
    try {
      while (true) {
        final chunk = await _ch.invokeMethod<Uint8List>(
            'readChunk', {'handle': handle});
        if (chunk == null || chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await _ch.invokeMethod('closeRead', {'handle': handle});
    }
  }

  @override
  Future<SyncWriter> create(String relPath) async {
    final idx = relPath.lastIndexOf('/');
    final parent = idx < 0 ? '' : relPath.substring(0, idx);
    final name = idx < 0 ? relPath : relPath.substring(idx + 1);
    final parentUri = await _ensureDir(parent);
    final uri = await _ch.invokeMethod<String>('create',
        {'tree': treeUri, 'parent': parentUri, 'name': name});
    if (uri == null) throw StateError('create failed: $relPath');
    final handle = await _ch.invokeMethod<int>('openWrite', {'uri': uri});
    if (handle == null) throw StateError('openWrite failed: $relPath');
    return _SafWriter(handle);
  }

  Future<String> _ensureDir(String rel) async {
    if (_dirs.containsKey(rel)) return _dirs[rel]!;
    final idx = rel.lastIndexOf('/');
    final parent = idx < 0 ? '' : rel.substring(0, idx);
    final name = idx < 0 ? rel : rel.substring(idx + 1);
    final parentUri = await _ensureDir(parent);
    final existing = await _ch.invokeMethod<String>('child',
        {'tree': treeUri, 'parent': parentUri, 'name': name});
    final uri = existing ??
        await _ch.invokeMethod<String>(
            'mkdir', {'tree': treeUri, 'parent': parentUri, 'name': name});
    if (uri == null) throw StateError('mkdir failed: $rel');
    _dirs[rel] = uri;
    return uri;
  }

  @override
  Future<void> delete(FsEntry entry) =>
      _ch.invokeMethod('delete', {'uri': entry.uri});

  @override
  Future<void> setModified(String relPath, DateTime when) async {
    // SAF providers do not reliably support setting mtimes; the engine's
    // size-based comparison handles this.
  }
}

class _SafWriter implements SyncWriter {
  final int handle;
  _SafWriter(this.handle);

  @override
  Future<void> write(List<int> chunk) => SafFileSystem._ch.invokeMethod(
      'writeChunk', {'handle': handle, 'bytes': Uint8List.fromList(chunk)});

  @override
  Future<void> close() =>
      SafFileSystem._ch.invokeMethod('closeWrite', {'handle': handle});
}
