import 'sync_fs.dart';

class SyncStats {
  int planned = 0;
  int copied = 0;
  int deleted = 0;
  int failed = 0;
  int bytesCopied = 0;
  int bytesTotal = 0;
  String currentFile = '';
  bool cancelled = false;

  double get fraction => bytesTotal == 0 ? 0 : bytesCopied / bytesTotal;

  Map<String, Object> toJson() => {
        'planned': planned,
        'copied': copied,
        'deleted': deleted,
        'failed': failed,
        'bytesCopied': bytesCopied,
        'bytesTotal': bytesTotal,
        'cancelled': cancelled,
      };
}

class _Item {
  final SyncFs srcFs;
  final FsEntry src;
  final String relPath;
  final int size;
  _Item(this.srcFs, this.src, this.relPath, this.size);
}

typedef ProgressFn = void Function(SyncStats stats);
typedef CancelFn = bool Function();

class Syncer {
  final List<SyncFs> sources;
  final SyncFs dest;
  final Set<String> extensions; // lowercase with dot, e.g. {'.mp3'}; empty = all files
  final bool mirror;
  final ProgressFn? onProgress;
  final CancelFn? shouldCancel;

  final SyncStats stats = SyncStats();

  Syncer({
    required this.sources,
    required this.dest,
    required this.extensions,
    this.mirror = false,
    this.onProgress,
    this.shouldCancel,
  });

  bool _cancelled() => shouldCancel?.call() ?? false;

  static String extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return '';
    return path.substring(i).toLowerCase();
  }

  bool _wanted(FsEntry e) =>
      extensions.isEmpty || extensions.contains(extOf(e.relPath));

  Future<SyncStats> run() async {
    final planned = <_Item>[];
    final usedRelPaths = <String>{};

    for (final srcFs in sources) {
      if (_cancelled()) {
        stats.cancelled = true;
        return stats;
      }
      await for (final e in srcFs.walk()) {
        if (!e.isFile || !_wanted(e)) continue;
        var rel = e.relPath;
        if (usedRelPaths.contains(rel)) {
          // collision between sources -> prefix with the source root's name
          final base = srcFs.rootName;
          rel = '$base/$rel';
          var n = 2;
          while (usedRelPaths.contains(rel)) {
            rel = '$base ($n)/${e.relPath}';
            n++;
          }
        }
        usedRelPaths.add(rel);
        planned.add(_Item(srcFs, e, rel, e.size));
      }
    }

    stats.planned = planned.length;
    stats.bytesTotal = planned.fold(0, (a, b) => a + b.size);

    // snapshot of what already exists on the destination
    final destEntries = <String, FsEntry>{};
    await for (final e in dest.walk()) {
      if (e.isFile && _wanted(e)) destEntries[e.relPath] = e;
    }

    final destSet = <String>{};

    for (final item in planned) {
      if (_cancelled()) {
        stats.cancelled = true;
        return stats;
      }
      destSet.add(item.relPath);
      stats.currentFile = item.relPath;
      try {
        final existing = destEntries[item.relPath];
        if (existing != null && _isUpToDate(item.src, existing)) {
          stats.bytesCopied += item.size;
          onProgress?.call(stats);
          continue;
        }
        final writer = await dest.create(item.relPath);
        await for (final chunk in item.srcFs.read(item.src)) {
          if (_cancelled()) {
            await writer.close();
            stats.cancelled = true;
            return stats;
          }
          await writer.write(chunk);
          stats.bytesCopied += chunk.length;
          onProgress?.call(stats);
        }
        await writer.close();
        if (item.src.modified != null) {
          await dest.setModified(item.relPath, item.src.modified!);
        }
        stats.copied++;
      } catch (_) {
        stats.failed++;
      }
      onProgress?.call(stats);
    }

    if (mirror && !_cancelled()) {
      for (final e in destEntries.values) {
        if (_cancelled()) {
          stats.cancelled = true;
          return stats;
        }
        if (!destSet.contains(e.relPath)) {
          stats.currentFile = e.relPath;
          try {
            await dest.delete(e);
            stats.deleted++;
          } catch (_) {
            stats.failed++;
          }
          onProgress?.call(stats);
        }
      }
    }

    stats.currentFile = '';
    onProgress?.call(stats);
    return stats;
  }

  bool _isUpToDate(FsEntry src, FsEntry destE) {
    if (destE.size != src.size) return false;
    final s = src.modified;
    final d = destE.modified;
    if (s == null || d == null) return true; // size matched, no mtime info
    // FAT/exFAT sticks have 2-second mtime granularity
    return (s.difference(d)).inSeconds.abs() <= 2;
  }
}
